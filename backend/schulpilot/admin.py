import base64
import hashlib
import json
import re
from datetime import date, datetime, time, timedelta, timezone
from typing import Literal

import httpx
from fastapi import APIRouter, Depends, Header, HTTPException, Query
from sqlalchemy import func, or_, select, update

from . import schemas as s
from .config import runtime_settings, settings
from .db import Audit, Family, ProviderConfig, Session, Usage, User, get_db, now
from .providers import usage_summary
from .security import admin, audit, decrypt, encrypt, family_access, parent, rate_limit

router = APIRouter(tags=["Betrieb und Kontingente"])


def config_data(config):
    result = {
        c.name: getattr(config, c.name)
        for c in ProviderConfig.__table__.columns
        if c.name not in ("encrypted_key", "id")
    }
    result["has_key"] = bool(config.encrypted_key or (config.provider == "openrouter" and settings.openrouter_api_key))
    result["key_source"] = (
        "environment" if config.provider == "openrouter" and settings.openrouter_api_key else "encrypted_settings"
    )
    site = runtime_settings()
    result["real_data_gate"] = bool(site.real_data_approved and site.privacy_evidence)
    result["codex_isolated_worker"] = bool(settings.codex_socket and settings.codex_approved)
    return result


@router.get("/admin/provider")
def provider(p=Depends(admin), db=Depends(get_db)):
    audit(db, p.user.id, "admin.provider_read", "provider")
    db.commit()
    return config_data(db.get(ProviderConfig, 1))


@router.put("/admin/provider")
def update_provider(data: s.ProviderUpdate, p=Depends(admin), db=Depends(get_db)):
    return save_provider(data, p.user.id, db)


@router.get("/admin/provider/codex/models")
def codex_models(p=Depends(admin), db=Depends(get_db)):
    return provider_model_catalog(p.user.id, db)


def provider_model_catalog(actor, db):
    from .codex_setup import worker_models

    rate_limit(db, "codex-models:" + actor, 12, 60, commit=False)
    rate_limit(db, "codex-models-global", 60, 60, commit=False)
    audit(db, actor, "admin.codex_models_read", "codex_cli")
    db.commit()
    return worker_models()


def validate_codex_selection(catalog, values, config):
    models = {m["id"]: m for m in catalog["models"]}
    text_id = values["model"]
    image_id = values.get("extraction_model", config.extraction_model) or text_id
    effort = values.get("reasoning_effort", config.reasoning_effort)
    if text_id not in models or image_id not in models:
        raise HTTPException(422, "Ein ausgewähltes Codex-Modell ist für diese Anmeldung nicht im Katalog verfügbar.")
    text, image = models[text_id], models[image_id]
    if "text" not in text["input_modalities"]:
        raise HTTPException(422, "Das gewählte Lernmodell unterstützt laut Katalog keine Texteingaben.")
    if "image" not in image["input_modalities"]:
        raise HTTPException(422, "Das gewählte Bildmodell unterstützt laut Katalog keine Fotos.")
    if effort not in text["reasoning_efforts"] or effort not in image["reasoning_efforts"]:
        raise HTTPException(422, "Diese Denkstufe wird nicht von beiden gewählten Codex-Modellen unterstützt.")


def save_provider(data, actor, db):
    catalog, catalog_error = None, None
    previous_stop = None
    if data.provider == "codex":
        previous_stop = db.scalar(select(ProviderConfig.emergency_stop).where(ProviderConfig.id == 1))
        try:
            catalog = provider_model_catalog(actor, db)
        except HTTPException as error:
            if error.status_code not in (429, 503):
                raise
            catalog_error = error
    # Fetch metadata before this lock, so slow CLI discovery cannot hold up
    # the emergency stop. Re-read under the lock for safe omission/fallback.
    config = db.scalar(
        select(ProviderConfig).where(ProviderConfig.id == 1).with_for_update().execution_options(populate_existing=True)
    )
    if data.expected_revision is not None and data.expected_revision != config.revision:
        raise HTTPException(
            409,
            "Die Konfiguration wurde inzwischen geändert. Dein Entwurf bleibt erhalten. Lade den gespeicherten Stand bewusst neu.",
        )
    # PostgreSQL locks this row above; SQLite does not implement FOR UPDATE.
    # Claim the submitted revision atomically before dirtying any config field.
    # Legacy callers without a revision retain their unconditional-save contract.
    claim = update(ProviderConfig).where(ProviderConfig.id == 1)
    if data.expected_revision is not None:
        claim = claim.where(ProviderConfig.revision == data.expected_revision)
    claimed = db.execute(
        claim.values(revision=ProviderConfig.revision + 1).execution_options(synchronize_session=False)
    )
    if claimed.rowcount != 1:
        db.rollback()
        raise HTTPException(
            409,
            "Die Konfiguration wurde inzwischen geändert. Dein Entwurf bleibt erhalten. Lade den gespeicherten Stand bewusst neu.",
        )
    # The SQL expression bypassed the identity map. Refresh now, while the row
    # has no unflushed edits, so both the result and omission checks use it.
    db.refresh(config)
    if previous_stop is False and config.emergency_stop and not data.emergency_stop:
        raise HTTPException(409, "Der Notfallstopp wurde inzwischen aktiviert. Bitte die Einstellungen neu laden.")
    values = data.model_dump(exclude={"api_key", "expected_revision"})
    for field in ("openrouter_free_only", "openrouter_require_zdr", "reasoning_effort"):
        if field not in data.model_fields_set:
            values.pop(field)
    free_only = values.get("openrouter_free_only", config.openrouter_free_only)
    if data.provider == "openrouter" and free_only:
        if not data.model.endswith(":free") or (data.extraction_model and not data.extraction_model.endswith(":free")):
            raise HTTPException(
                422, "Im kostenlosen OpenRouter-Betrieb benötigen Text- und Bildmodell eine :free-Modell-ID."
            )
        if data.input_per_million_micros != 0 or data.output_per_million_micros != 0:
            raise HTTPException(422, "Kostenloser OpenRouter-Betrieb benötigt Preisobergrenzen von null.")
    # An explicit model/provider change invalidates the previous endpoint result.
    # The operator's privacy approval is separate from endpoint availability.
    routing_fields = (
        "provider",
        "model",
        "extraction_model",
        "reasoning_effort",
        "capability_evidence",
        "extraction_capability_evidence",
        "openrouter_free_only",
        "openrouter_require_zdr",
    )
    routing_changed = bool(data.api_key) or any(
        values.get(field, getattr(config, field)) != getattr(config, field) for field in routing_fields
    )
    if data.provider == "codex":
        if catalog_error:
            if routing_changed:
                raise catalog_error
        else:
            validate_codex_selection(catalog, values, config)
    if routing_changed:
        config.production_block_reason = "Neue Modellkonfiguration: datenschutzkonformen Endpunkt zuerst mit künstlichen Daten prüfen und lokal freigeben."
    if data.provider != config.provider:
        config.encrypted_key = None
    for key, value in values.items():
        setattr(config, key, value)
    if data.api_key:
        config.encrypted_key = encrypt(data.api_key)
    config.status = "Konfiguration gespeichert. Verbindung noch nicht geprüft."
    if catalog_error:
        config.status = "Konfiguration gespeichert. Codex-Modellauswahl unverändert; Katalog gerade nicht erreichbar."
    audit(db, actor, "admin.provider_update", data.provider)
    db.commit()
    return config_data(config)


@router.post("/admin/emergency-stop")
def emergency(p=Depends(admin), db=Depends(get_db)):
    config = db.scalar(
        select(ProviderConfig).where(ProviderConfig.id == 1).with_for_update().execution_options(populate_existing=True)
    )
    if not config.emergency_stop:
        config.emergency_stop = True
        config.revision += 1
    audit(db, p.user.id, "admin.emergency_stop", "global")
    db.commit()
    return {
        "message": "Neue kostenpflichtige Aufrufe sind gesperrt. Bereits laufende externe Verarbeitung lässt sich nicht zurückholen.",
        "revision": config.revision,
    }


@router.post("/admin/provider/check")
def check(p=Depends(admin), db=Depends(get_db)):
    return provider_check(p.user.id, db)


def provider_check(actor, db):
    config = db.get(ProviderConfig, 1)
    if config.provider == "codex":
        from .codex_setup import worker_health

        status = worker_health()["status"]
    elif config.provider in ("openai", "openrouter") and (
        config.encrypted_key or (config.provider == "openrouter" and settings.openrouter_api_key)
    ):
        url = (
            "https://api.openai.com/v1/models" if config.provider == "openai" else "https://openrouter.ai/api/v1/models"
        )
        try:
            response = httpx.get(
                url,
                headers={
                    "Authorization": "Bearer "
                    + (
                        settings.openrouter_api_key
                        if config.provider == "openrouter" and settings.openrouter_api_key
                        else decrypt(config.encrypted_key)
                    )
                },
                timeout=10,
                follow_redirects=False,
            )
            if response.status_code != 200:
                status = f"Verbindung fehlgeschlagen: HTTP {response.status_code}. Schlüssel und Berechtigungen prüfen."
            else:
                models = response.json().get("data", [])
                model = next((m for m in models if m.get("id") == config.model), None)
                if not model:
                    status = "Verbindung erreichbar; ausgewähltes Modell ist nicht im Modellkatalog dieses Zugangs enthalten."
                elif config.provider == "openrouter":
                    image = "image" in model.get("architecture", {}).get("input_modalities", [])
                    structured = "structured_outputs" in model.get(
                        "supported_parameters", []
                    ) or "response_format" in model.get("supported_parameters", [])
                    status = f"Metadaten erreichbar. Modell gefunden. Katalog: Bilder={image}, strukturierte Ausgabe={structured}. Ein echter Schema-/Bildtest ist noch erforderlich."
                else:
                    status = "Metadaten erreichbar; Modell gefunden. Bild- und Schemafähigkeit müssen anhand offizieller Modelldokumentation und eines separaten synthetischen Tests bestätigt werden."
        except (httpx.HTTPError, ValueError):
            status = "Verbindung nicht erreichbar oder ungültige Metadaten. Keine Lernanfrage wurde gesendet."
    else:
        status = "Provider, Modell oder Schlüssel fehlen."
    config.status = status
    audit(db, actor, "admin.provider_check", config.provider)
    db.commit()
    return {"status": status}


@router.get("/admin/audit")
def audit_view(p=Depends(admin), db=Depends(get_db)):
    audit(db, p.user.id, "admin.audit_read", "audit")
    db.commit()
    return [
        {"id": a.id, "actor": a.actor, "action": a.action, "target": a.target, "created": a.created}
        for a in db.scalars(select(Audit).order_by(Audit.created.desc()).limit(200))
    ]


def audit_cursor_decode(value):
    try:
        if not re.fullmatch(r"[A-Za-z0-9_-]+", value):
            raise ValueError
        decoded = json.loads(base64.urlsafe_b64decode(value + "=" * (-len(value) % 4)))
        if (not isinstance(decoded, dict) or set(decoded) != {"created", "id"}
                or type(decoded["created"]) is not int or not 0 <= decoded["created"] <= 9999999999
                or not isinstance(decoded["id"], str) or not re.fullmatch(r"[a-f0-9]{32}", decoded["id"])):
            raise ValueError
        return decoded
    except (ValueError, TypeError, UnicodeError, KeyError):
        raise HTTPException(422, "Die Protokollposition ist ungültig. Starte die Auswahl erneut.") from None


@router.get("/admin/audit-events")
def audit_events(q: str = Query("", max_length=160), actor: str = Query("", max_length=32),
                 action: str = Query("", max_length=80), start: date | None = None, end: date | None = None,
                 order: Literal["newest", "oldest"] = "newest", cursor: str | None = Query(None, max_length=160),
                 snapshot: int | None = Query(None, ge=0, le=9999999999), limit: int = Query(50, ge=1, le=100),
                 p=Depends(admin), db=Depends(get_db)):
    from .db import now

    latest_complete_second = max(0, int(now()) - 1)
    if snapshot is None:
        snapshot = latest_complete_second
    if snapshot > latest_complete_second or start and end and start > end:
        raise HTTPException(422, "Prüfe den Zeitbereich des Protokolls.")
    query = select(Audit).where(Audit.created <= snapshot)
    if q.strip():
        query = query.where(or_(*(func.lower(column).contains(q.strip().lower(), autoescape=True)
                                 for column in (Audit.action, Audit.target, Audit.actor))))
    if actor:
        query = query.where(Audit.actor == actor)
    if action:
        query = query.where(Audit.action == action)
    if start:
        query = query.where(Audit.created >= int(datetime.combine(start, time.min, timezone.utc).timestamp()))
    if end:
        if end.year >= 9999:
            raise HTTPException(422, "Bitte ein gültiges Enddatum vor dem Jahr 9999 wählen.")
        query = query.where(Audit.created < int(datetime.combine(end + timedelta(days=1), time.min, timezone.utc).timestamp()))
    total = db.scalar(select(func.count()).select_from(query.subquery()))
    filtered = query.subquery()
    counts = db.execute(select(filtered.c.action, func.count()).group_by(filtered.c.action)
        .order_by(func.count().desc(), filtered.c.action).limit(21)).all()
    if cursor:
        old = audit_cursor_decode(cursor)
        if old["created"] > snapshot:
            raise HTTPException(422, "Diese Protokollposition gehört nicht zu diesem Zeitbereich.")
        older = (Audit.created < old["created"]) | ((Audit.created == old["created"]) & (Audit.id < old["id"]))
        newer = (Audit.created > old["created"]) | ((Audit.created == old["created"]) & (Audit.id > old["id"]))
        query = query.where(older if order == "newest" else newer)
    ordering = (Audit.created.desc(), Audit.id.desc()) if order == "newest" else (Audit.created, Audit.id)
    rows = list(db.scalars(query.order_by(*ordering).limit(limit + 1)))
    items = [{"id": row.id, "actor": row.actor, "action": row.action, "target": row.target, "created": row.created}
        for row in rows[:limit]]
    next_cursor = base64.urlsafe_b64encode(json.dumps({"created": rows[limit-1].created,
        "id": rows[limit-1].id}, separators=(",", ":")).encode()).decode().rstrip("=") if len(rows) > limit else None
    actions = list(db.scalars(select(Audit.action).distinct().order_by(Audit.action).limit(201)))
    actors = list(db.scalars(select(Audit.actor).distinct().order_by(Audit.actor).limit(201)))
    audit(db, p.user.id, "admin.audit_read", "audit-pages")
    db.commit()
    return {"items": items, "total": total, "snapshot": snapshot, "next_cursor": next_cursor,
        "filters": {"q": q.strip(), "actor": actor, "action": action, "start": start, "end": end, "order": order},
        "actions": actions[:200], "actors": actors[:200],
        "options_truncated": len(actions) > 200 or len(actors) > 200,
        "action_counts": [{"action": action, "count": count} for action, count in counts[:20]],
        "action_counts_truncated": len(counts) > 20,
        "notice": "Berechtigte Betriebsmetadaten in einem festen Zeitbereich. Neue Ereignisse erscheinen erst nach bewusstem Aktualisieren; laufende oder verspätet verbuchte Vorgänge können fehlen. Keine privaten Lerninhalte."}


class Entitlement(s.Strict):
    plan: str = s.Field(min_length=1, max_length=40)
    child_limit: int = s.Field(ge=1, le=20)
    call_limit: int = s.Field(ge=0, le=10000)
    budget_micros: int = s.Field(ge=0, le=100_000_000)


def entitlement_revision(family):
    values = {key: getattr(family, key) for key in ("plan", "child_limit", "call_limit", "budget_micros")}
    return hashlib.sha256(json.dumps(values, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


@router.get("/admin/families")
def family_operations(
    paginated: bool = False,
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=50, ge=1, le=200),
    search: str = Query(default="", max_length=80),
    plan: str | None = Query(default=None, max_length=40),
    synthetic: bool | None = None,
    p=Depends(admin),
    db=Depends(get_db),
):
    audit(db, p.user.id, "admin.entitlements_read", "families")
    db.commit()
    conditions = []
    query = search.strip()
    if query:
        conditions.append(
            or_(Family.id.icontains(query, autoescape=True), Family.plan.icontains(query, autoescape=True))
        )
    if plan is not None:
        conditions.append(Family.plan == plan)
    if synthetic is not None:
        conditions.append(Family.synthetic.is_(synthetic))
    total = db.scalar(select(func.count()).select_from(Family).where(*conditions)) if paginated else None
    pages = max(1, (total + page_size - 1) // page_size) if paginated else 1
    selected_page = min(page, pages)
    statement = select(Family).where(*conditions).order_by(Family.id)
    statement = (
        statement.offset((selected_page - 1) * page_size).limit(page_size) if paginated else statement.limit(200)
    )
    # Deliberately no names, children, messages, materials or learning histories.
    items = [
        {
            "id": f.id,
            "plan": f.plan,
            "child_limit": f.child_limit,
            "call_limit": f.call_limit,
            "budget_micros": f.budget_micros,
            "synthetic": f.synthetic,
            "entitlement_revision": entitlement_revision(f),
        }
        for f in db.scalars(statement)
    ]
    if not paginated:
        return items
    return {
        "items": items,
        "pagination": {"page": selected_page, "pages": pages, "page_size": page_size, "total": total},
        "filters": {"search": query, "plan": plan, "synthetic": synthetic},
    }


@router.put("/admin/families/{family_id}/entitlements")
def entitlements(family_id: str, data: Entitlement,
                 if_match: str | None = Header(None, max_length=66, pattern=r'^"?[a-f0-9]{64}"?$'),
                 p=Depends(admin), db=Depends(get_db)):
    statement = select(Family).where(Family.id == family_id)
    if db.bind.dialect.name == "postgresql":
        statement = statement.with_for_update()
    else:
        db.execute(update(Family).where(Family.id == family_id).values(child_limit=Family.child_limit))
    family = db.scalar(statement.execution_options(populate_existing=True))
    if not family:
        raise HTTPException(404, "Familie nicht gefunden.")
    session = db.get(Session, p.session.id, populate_existing=True)
    actor = db.get(User, p.user.id, populate_existing=True)
    if not session or session.revoked or session.expires <= now() or not actor or actor.disabled:
        raise HTTPException(401, "Bitte melde dich erneut an.")
    if actor.role != "admin":
        raise HTTPException(403, "Nur für Administratoren verfügbar.")
    if if_match is not None and if_match.strip('"') != entitlement_revision(family):
        raise HTTPException(409, "Dieser Familientarif wurde inzwischen geändert. Vergleiche den gespeicherten Stand; dein Entwurf bleibt erhalten.")
    for key, value in data.model_dump().items():
        setattr(family, key, value)
    audit(db, p.user.id, "admin.entitlements_update", family.id)
    db.commit()
    return {"message": "Tarifberechtigungen aktualisiert.", "entitlement_revision": entitlement_revision(family)}


@router.get("/families/{family_id}/usage")
def usage(family_id: str, p=Depends(parent), db=Depends(get_db)):
    family, _ = family_access(db, p, family_id)
    result = usage_summary(db, family)
    result["records"] = [
        {
            "child_id": u.child_id,
            "provider": u.provider,
            "model": u.model,
            "function": u.function,
            "status": u.status,
            "input_tokens": u.input_tokens,
            "output_tokens": u.output_tokens,
            "search_calls": u.search_calls,
            "cost_micros_usd": u.cost_micros,
            "reserved_micros_usd": u.reserved_micros,
            "created": u.created,
        }
        for u in db.scalars(select(Usage).where(Usage.family_id == family.id).order_by(Usage.created.desc()).limit(200))
    ]
    return result
