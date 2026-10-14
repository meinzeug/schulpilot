import httpx
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select, update

from . import schemas as s
from .config import settings
from .db import Audit, Family, ProviderConfig, Usage, get_db
from .providers import usage_summary
from .security import admin, audit, decrypt, encrypt, family_access, parent

router = APIRouter(tags=["Betrieb und Kontingente"])


def config_data(config):
    result = {
        c.name: getattr(config, c.name)
        for c in ProviderConfig.__table__.columns
        if c.name not in ("encrypted_key", "id")
    }
    result["has_key"] = bool(config.encrypted_key)
    result["real_data_gate"] = bool(settings.real_data_approved and settings.privacy_evidence)
    result["codex_isolated_worker"] = bool(settings.codex_socket and settings.codex_approved)
    return result


@router.get("/admin/provider")
def provider(p=Depends(admin), db=Depends(get_db)):
    audit(db, p.user.id, "admin.provider_read", "provider")
    db.commit()
    return config_data(db.get(ProviderConfig, 1))


@router.put("/admin/provider")
def update_provider(data: s.ProviderUpdate, p=Depends(admin), db=Depends(get_db)):
    config = db.get(ProviderConfig, 1)
    values = data.model_dump(exclude={"api_key"})
    for field in ("openrouter_free_only", "openrouter_require_zdr"):
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
        "capability_evidence",
        "extraction_capability_evidence",
        "openrouter_free_only",
        "openrouter_require_zdr",
    )
    if data.api_key or any(
        values.get(field, getattr(config, field)) != getattr(config, field) for field in routing_fields
    ):
        config.production_block_reason = "Neue Modellkonfiguration: datenschutzkonformen Endpunkt zuerst mit künstlichen Daten prüfen und lokal freigeben."
    if data.provider != config.provider:
        config.encrypted_key = None
    for key, value in values.items():
        setattr(config, key, value)
    if data.api_key:
        config.encrypted_key = encrypt(data.api_key)
    db.execute(update(ProviderConfig).where(ProviderConfig.id == 1).values(revision=ProviderConfig.revision + 1))
    db.refresh(config)
    config.status = "Konfiguration gespeichert. Verbindung noch nicht geprüft."
    audit(db, p.user.id, "admin.provider_update", data.provider)
    db.commit()
    return config_data(config)


@router.post("/admin/emergency-stop")
def emergency(p=Depends(admin), db=Depends(get_db)):
    config = db.get(ProviderConfig, 1)
    config.emergency_stop = True
    audit(db, p.user.id, "admin.emergency_stop", "global")
    db.commit()
    return {
        "message": "Neue kostenpflichtige Aufrufe sind gesperrt. Bereits laufende externe Verarbeitung lässt sich nicht zurückholen."
    }


@router.post("/admin/provider/check")
def check(p=Depends(admin), db=Depends(get_db)):
    config = db.get(ProviderConfig, 1)
    if config.provider == "codex":
        status = "Experimentell. Isolierter Worker und separate Authentifizierung müssen lokal eingerichtet und geprüft werden."
    elif config.provider in ("openai", "openrouter") and config.encrypted_key:
        url = (
            "https://api.openai.com/v1/models" if config.provider == "openai" else "https://openrouter.ai/api/v1/models"
        )
        try:
            response = httpx.get(
                url,
                headers={"Authorization": "Bearer " + decrypt(config.encrypted_key)},
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
    audit(db, p.user.id, "admin.provider_check", config.provider)
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


class Entitlement(s.Strict):
    plan: str = s.Field(min_length=1, max_length=40)
    child_limit: int = s.Field(ge=1, le=20)
    call_limit: int = s.Field(ge=0, le=10000)
    budget_micros: int = s.Field(ge=0, le=100_000_000)


@router.get("/admin/families")
def family_operations(p=Depends(admin), db=Depends(get_db)):
    audit(db, p.user.id, "admin.entitlements_read", "families")
    db.commit()
    # Deliberately no names, children, messages, materials or learning histories.
    return [
        {
            "id": f.id,
            "plan": f.plan,
            "child_limit": f.child_limit,
            "call_limit": f.call_limit,
            "budget_micros": f.budget_micros,
            "synthetic": f.synthetic,
        }
        for f in db.scalars(select(Family).limit(200))
    ]


@router.put("/admin/families/{family_id}/entitlements")
def entitlements(family_id: str, data: Entitlement, p=Depends(admin), db=Depends(get_db)):
    family = db.get(Family, family_id)
    if not family:
        raise HTTPException(404, "Familie nicht gefunden.")
    for key, value in data.model_dump().items():
        setattr(family, key, value)
    audit(db, p.user.id, "admin.entitlements_update", family.id)
    db.commit()
    return {"message": "Tarifberechtigungen aktualisiert."}


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
            "cost_micros_usd": u.cost_micros,
            "reserved_micros_usd": u.reserved_micros,
            "created": u.created,
        }
        for u in db.scalars(select(Usage).where(Usage.family_id == family.id).order_by(Usage.created.desc()).limit(200))
    ]
    return result
