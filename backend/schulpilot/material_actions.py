"""Explicit notebook deletion snapshots and revision-safe photo reprocessing.

Deletion tokens contain only opaque IDs/filter values and bind the exact current
selection to the actor, session and child for ten minutes. No writes or inference
are triggered by GET/listing. Confirmed deletion also removes linked learning
rounds and answers. Reprocessing preserves them and reserves one extraction.
"""

import hashlib
import json
import shutil
from datetime import date, datetime, time
from types import SimpleNamespace
from typing import Literal
from zoneinfo import ZoneInfo

from cryptography.fernet import InvalidToken
from fastapi import Depends, Header, HTTPException
from pydantic import Field, model_validator
from sqlalchemy import or_, select, update

from . import schemas as s
from .config import settings
from .db import Child, Job, LearningUnit, Material, SchoolDay, Usage, get_db, now, uid
from .security import authenticated, child_access, crypt, rate_limit

MAX_DELETE = 5000
TTL = 600


class MaterialFilters(s.Strict):
    q: str = Field(default="", max_length=120)
    subject: str | None = Field(None, max_length=80)
    subject_id: str | None = Field(None, pattern=r"^(?:[a-f0-9]{32}|unassigned)$")
    topic: str | None = Field(None, max_length=160)
    status: Literal["all", "review", "confirmed"] = "all"
    sort: Literal["subject", "newest", "oldest"] = "subject"
    since: date | None = None
    until: date | None = None

    @model_validator(mode="after")
    def valid_range(self):
        if self.subject is not None and self.subject_id is not None:
            raise ValueError("Bitte nur einen Fachfilter verwenden.")
        if self.since and self.until and self.since > self.until:
            raise ValueError("Der Beginn muss vor dem Ende des Zeitraums liegen.")
        return self


class DeletePreview(s.Strict):
    ids: list[str] | None = Field(None, min_length=1, max_length=500)
    all_matching: bool = False
    filters: MaterialFilters = Field(default_factory=MaterialFilters)

    @model_validator(mode="after")
    def one_selection(self):
        if bool(self.ids) == self.all_matching:
            raise ValueError("Bitte einzelne Seiten oder alle gefilterten Seiten auswählen.")
        if self.ids and (
            len(set(self.ids)) != len(self.ids)
            or any(len(value) != 32 or any(c not in "0123456789abcdef" for c in value) for value in self.ids)
        ):
            raise ValueError("Die Seitenauswahl enthält ungültige oder doppelte Einträge.")
        if self.ids and self.filters != MaterialFilters():
            raise ValueError("Einzelne Seiten benötigen keinen zusätzlichen Filter.")
        return self


class DeleteConfirm(s.Strict):
    selection_token: str = Field(min_length=80, max_length=48000)
    delete_linked_units: bool = False


class Reprocess(s.Strict):
    revision: int = Field(ge=1)


def selection_query(db, p, child, selection):
    from .library import contains, subject_value
    from .subjects import owned_subject

    conditions = [Material.child_id == child.id]
    if selection.ids:
        conditions.append(Material.id.in_(selection.ids))
    else:
        conditions.append(Material.purpose != "exam")
        f = selection.filters
        if f.subject_id == "unassigned":
            conditions.append(Material.subject_id.is_(None))
        elif f.subject_id:
            owned_subject(db, child, f.subject_id, p)
            conditions.append(Material.subject_id == f.subject_id)
        if f.subject is not None:
            conditions.append(subject_value(Material.subject) == f.subject.strip())
        if f.topic is not None:
            conditions.append(Material.topic == f.topic)
        if f.q.strip():
            conditions.append(
                or_(
                    *(
                        contains(column, f.q.strip())
                        for column in (Material.title, Material.topic, Material.subject, Material.content)
                    )
                )
            )
        if f.status != "all":
            conditions.append(Material.confirmed.is_(f.status == "confirmed"))
        zone = ZoneInfo(s.Preferences(**child.preferences).timezone)
        if f.since:
            start = int(datetime.combine(f.since, time.min, zone).timestamp())
            conditions.append(
                or_(SchoolDay.school_date >= f.since.isoformat(), SchoolDay.id.is_(None) & (Material.created >= start))
            )
        if f.until:
            end = int(datetime.combine(f.until, time.max, zone).timestamp())
            conditions.append(
                or_(SchoolDay.school_date <= f.until.isoformat(), SchoolDay.id.is_(None) & (Material.created <= end))
            )
    return (
        select(Material)
        .outerjoin(SchoolDay, SchoolDay.id == Material.school_day_id)
        .where(*conditions)
        .order_by(Material.id)
    )


def selection_rows(db, p, child, selection):
    rows = list(db.scalars(selection_query(db, p, child, selection).limit(MAX_DELETE + 1)))
    if len(rows) > MAX_DELETE:
        raise HTTPException(
            422, "Bitte höchstens 5.000 Seiten auf einmal auswählen. Grenze die Auswahl nach Fach oder Datum ein."
        )
    if selection.ids and len(rows) != len(selection.ids):
        raise HTTPException(404, "Eine ausgewählte Seite ist nicht mehr vorhanden oder gehört nicht zu diesem Kind.")
    return rows


def snapshot(rows):
    # OCR can update unconfirmed text without advancing revision. Include every
    # persisted field, not only the version counter, so a changed review page
    # never slips through an already acknowledged deletion preview.
    digest = hashlib.sha256()
    for material in rows:
        values = {column.name: getattr(material, column.name) for column in Material.__table__.columns}
        digest.update(json.dumps(values, sort_keys=True, separators=(",", ":")).encode())
        digest.update(b"\n")
    return digest.hexdigest()


def ensure_idle(db, child_id):
    if db.scalar(select(Job.id).where(Job.child_id == child_id, Job.status.in_(("queued", "running")))):
        raise HTTPException(409, "Eine Verarbeitung läuft noch. Bitte kurz warten und erneut versuchen.")


def ensure_deletable(rows):
    if any(material.fixture_id for material in rows):
        raise HTTPException(
            409,
            "Die Auswahl enthält eine feste Beispielseite. Nichts wurde gelöscht. Bitte nur eigene Heftseiten auswählen.",
        )


def lock_units(db, child_id, ids):
    from .unit_erasure import linked_ids

    selected = linked_ids(db, child_id, ids)
    # FK cleanup can also clear a predecessor's coaching link. Lock all rounds
    # of this child before Child, in the same order as answer/tutor mutations.
    list(db.scalars(select(LearningUnit.id).where(LearningUnit.child_id == child_id)
                    .order_by(LearningUnit.id).with_for_update()))
    return selected


def delete_rows(db, child, rows):
    """Caller owns sorted Unit locks then Child, and revalidated the selection."""
    from .erasure import request
    from .learning import record
    from .school_preparation import sources_removed
    from .tutor import purge_source_turns

    ensure_deletable(rows)
    ids = [m.id for m in rows]
    from .unit_erasure import linked_ids, remove

    remove(db, child, linked_ids(db, child.id, ids))
    day_ids = sorted({m.school_day_id for m in rows if m.school_day_id})
    paths = [m.path for m in rows if m.path]
    purge_source_turns(db, ids, child_id=child.id)
    for material in rows:
        request(db, "material", material.id)
        db.delete(material)
    db.flush()
    for day_id in day_ids:
        day = db.get(SchoolDay, day_id)
        if day:
            day.revision += 1
            # Cancel old preparation intent. A background tick may only reserve
            # again after a new explicit submission; learning history remains.
            sources_removed(db, day)
    record(db, child.id, "material_deleted", {"count": len(rows)})
    return paths


def remove_files(paths):
    from .erasure import flush_journal

    for path in paths:
        (settings.data_dir / "uploads" / path).unlink(missing_ok=True)
    flush_journal()


def delete_preview(child_id: str, data: DeletePreview, p=Depends(authenticated), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=p.user.role == "parent")
    rate_limit(db, "material-delete-preview:" + p.user.id, 30, 60, commit=False)
    rows = selection_rows(db, p, child, data)
    if not rows:
        raise HTTPException(409, "Es sind keine Seiten ausgewählt.")
    ensure_idle(db, child.id)
    ensure_deletable(rows)
    payload = {
        "v": 2,
        "actor": p.user.id,
        "session": p.session.id,
        "child": child.id,
        "selection": data.model_dump(mode="json"),
        "snapshot": snapshot(rows),
        "count": len(rows),
    }
    from .unit_erasure import counts, linked_ids
    from .unit_erasure import snapshot as unit_snapshot

    unit_ids = linked_ids(db, child.id, [m.id for m in rows])
    payload["units_snapshot"] = unit_snapshot(db, unit_ids)
    token = crypt().encrypt(json.dumps(payload, separators=(",", ":")).encode()).decode()
    db.commit()
    return {
        "count": len(rows),
        **counts(db, unit_ids),
        "selection_token": token,
        "expires_in": TTL,
        "sample": [{"id": m.id, "title": m.title, "subject": m.subject, "topic": m.topic} for m in rows[:5]],
    }


def bulk_delete(child_id: str, data: DeleteConfirm, p=Depends(authenticated), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=p.user.role == "parent")
    try:
        token = json.loads(crypt().decrypt(data.selection_token.encode(), ttl=TTL))
        if (token["v"], token["actor"], token["session"], token["child"]) != (2, p.user.id, p.session.id, child.id):
            raise ValueError("scope")
        selection = DeletePreview.model_validate(token["selection"])
    except (InvalidToken, ValueError, KeyError, TypeError):
        raise HTTPException(
            409, "Die Löschvorschau ist abgelaufen oder gehört zu einer anderen Anmeldung. Bitte erneut auswählen."
        ) from None
    rows = selection_rows(db, p, child, selection)
    ids = [m.id for m in rows]
    locked_units = lock_units(db, child.id, ids)
    db.execute(update(Child).where(Child.id == child.id).values(grade=Child.grade))
    db.expire_all()
    if p.session.revoked or p.session.expires <= now() or p.user.disabled or not p.user.verified:
        raise HTTPException(401, "Bitte erneut anmelden und die Seiten neu auswählen.")
    child = child_access(db, p, child_id, write=p.user.role == "parent")
    rows = selection_rows(db, p, child, selection)
    if len(rows) != token["count"] or snapshot(rows) != token["snapshot"]:
        raise HTTPException(
            409, "Die Seitenauswahl wurde inzwischen geändert. Nichts wurde gelöscht. Bitte die Vorschau neu öffnen."
        )
    from .unit_erasure import linked_ids
    from .unit_erasure import snapshot as unit_snapshot

    current_units = linked_ids(db, child.id, ids)
    if current_units != locked_units or unit_snapshot(db, current_units) != token["units_snapshot"]:
        raise HTTPException(
            409, "Neue Übungen wurden gespeichert. Nichts wurde gelöscht. Bitte die Vorschau neu öffnen."
        )
    ensure_idle(db, child.id)
    if current_units and not data.delete_linked_units:
        raise HTTPException(409, "Die verknüpften Übungen und Antworten werden mitgelöscht. Bitte die App aktualisieren und erneut bestätigen.")
    paths = delete_rows(db, child, rows)
    from .security import audit

    audit(db, p.user.id, "notebook.pages_and_rounds_deleted", child.id)
    db.commit()
    remove_files(paths)
    return {"deleted_count": len(rows)}


def validate_reprocess_job(db, job):
    guard = job.payload.get("reprocess_guard")
    if not guard:
        return
    from .model_routing import job_config
    from .providers import ProviderError, external_allowed
    from .school_preparation import authority

    child, family = authority(db, SimpleNamespace(child_id=job.child_id), guard)
    source = db.get(Material, guard.get("source_id"))
    if not source or source.child_id != child.id or source.revision != guard.get("source_revision"):
        raise ProviderError("Die ursprüngliche Heftseite wurde geändert oder gelöscht. Bitte neu starten.")
    config = job_config(db, job, "extract")
    usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
    if not usage or (usage.provider, usage.model, usage.config_revision) != (
        config.provider,
        config.model,
        config.revision,
    ):
        raise ProviderError("Die KI-Einstellungen haben sich geändert. Bitte erneut einlesen lassen.")
    external_allowed(config, image=True, synthetic_fixture=False)
    return child, family


def reprocess(
    material_id: str,
    data: Reprocess,
    idempotency: str = Header(alias="Idempotency-Key", default=""),
    p=Depends(authenticated),
    db=Depends(get_db),
):
    from .learning import record
    from .materials import enqueue, get_material

    if not idempotency or len(idempotency) > 80:
        raise HTTPException(422, "Ein eindeutiger Idempotency-Key (max. 80 Zeichen) ist erforderlich.")
    source, child = get_material(db, p, material_id, True)
    if source.purpose == "exam":
        raise HTTPException(409, "Bitte Arbeitsfotos über die gemeinsame Fotoabgabe neu fotografieren und abgeben.")
    existing = db.scalar(select(Job).where(Job.idempotency == p.user.id + ":" + idempotency))
    if existing:
        guard = existing.payload.get("reprocess_guard") or {}
        if (
            existing.kind != "extract"
            or existing.child_id != child.id
            or guard.get("source_id") != source.id
            or guard.get("source_revision") != data.revision
        ):
            raise HTTPException(409, "Dieser Anfrageschlüssel gehört bereits zu einer anderen Verarbeitung.")
        return {"id": existing.id, "status": existing.status, "material_id": existing.payload["material_id"]}
    if source.revision != data.revision:
        raise HTTPException(409, "Die Seite wurde inzwischen geändert. Bitte neu laden.")
    if source.synthetic or source.fixture_id or not source.path:
        raise HTTPException(409, "Diese Beispielseite hat kein eigenes Foto zum erneuten Einlesen.")
    original = settings.data_dir / "uploads" / source.path
    if not original.is_file():
        raise HTTPException(409, "Das ursprüngliche Foto ist nicht mehr vorhanden. Bitte fotografiere die Seite neu.")
    ensure_idle(db, child.id)
    directory = settings.data_dir / "uploads"
    new_path = uid() + ".jpg"
    destination = directory / new_path
    try:
        shutil.copyfile(original, destination)
        destination.chmod(0o600)
        clone = Material(
            purpose=source.purpose,
            id=uid(),
            child_id=child.id,
            title=source.title,
            path=new_path,
            image_digest=source.image_digest,
            quality_warnings=list(source.quality_warnings or []),
            synthetic=False,
            upload_key="reprocess:" + hashlib.sha256((p.user.id + ":" + idempotency).encode()).hexdigest(),
        )
        db.add(clone)
        db.flush()
        guard = {
            "source_id": source.id,
            "source_revision": source.revision,
            "session_id": p.session.id,
            "user_id": p.user.id,
            "family_id": child.family_id,
        }
        result = enqueue(
            db, p, child, "extract", {"material_id": clone.id, "reprocess_guard": guard}, idempotency, commit=False
        )
        record(db, child.id, "material_reprocessed")
        db.commit()
    except Exception as error:
        db.rollback()
        destination.unlink(missing_ok=True)
        from .providers import ProviderError

        if isinstance(error, ProviderError):
            raise HTTPException(
                503, "Die Seite kann gerade nicht neu eingelesen werden. Bitte versuche es später noch einmal."
            ) from None
        raise
    return result | {"material_id": clone.id}
