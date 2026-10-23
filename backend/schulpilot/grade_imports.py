"""Parent-confirmed, repeatable local PDF imports. No model/provider calls."""

import hashlib
import json
from decimal import Decimal
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, UploadFile
from pydantic import Field
from sqlalchemy import select

from . import schemas as s
from .db import GradeImport, GradeSourceSlot, SchoolGrade, Session, User, get_db, now
from .grade_pdf import isolated_extract
from .grades import grade_data, subject_key
from .learning import local_day
from .security import audit, child_access, parent, rate_limit
from .vocabulary import KEY, lock_child

router = APIRouter(tags=["Notenimport"])


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def school_year(today):
    # Calendar boundary is an explicit product convention, not an asserted
    # state-specific term date. The PDF's year must independently agree.
    return today.year if today.month >= 8 else today.year - 1


def slot_key(year, row):
    return digest(["fuxnoten-grid-v1", year, subject_key(row["subject"]), row["semester"], row["kind"], row["slot"]])


def owned_import(db, child, import_id):
    row = db.get(GradeImport, import_id)
    if not row or row.child_id != child.id:
        raise HTTPException(404, "Notenimport nicht gefunden.")
    return row


def live_parent(db, principal, child):
    status = db.execute(
        select(User.role, User.disabled, User.verified, Session.revoked, Session.expires)
        .join(Session, Session.user_id == User.id)
        .where(User.id == principal.user.id, Session.id == principal.session.id)
    ).first()
    if (
        not status
        or status.role != "parent"
        or status.disabled
        or not status.verified
        or status.revoked
        or status.expires <= now()
    ):
        raise HTTPException(401, "Bitte erneut anmelden.")
    return child_access(db, principal, child.id, write=True)


def projection(db, child, batch):
    grades = list(db.scalars(select(SchoolGrade).where(SchoolGrade.child_id == child.id).order_by(SchoolGrade.id)))
    sources = list(
        db.scalars(select(GradeSourceSlot).where(GradeSourceSlot.child_id == child.id).order_by(GradeSourceSlot.id))
    )
    by_id, by_slot = {g.id: g for g in grades}, {g.slot_key: g for g in sources}
    linked = {g.grade_id for g in sources if g.grade_id}
    context = digest(
        {
            "grades": [[g.id, g.revision] for g in grades],
            "slots": [[g.id, g.grade_id, g.last_value, g.ignored] for g in sources],
        }
    )
    start, end = f"{batch.school_year_start}-08-01", f"{batch.school_year_start + 1}-07-31"
    items = []
    for original in batch.entries:
        key = slot_key(batch.school_year_start, original)
        source = by_slot.get(key)
        grade = by_id.get(source.grade_id) if source else None
        item = {
            **original,
            "slot_key": key,
            "grade_id": grade.id if grade else None,
            "grade_revision": grade.revision if grade else None,
            "matches": [],
        }
        if source:
            if source.ignored or not grade:
                item["status"] = "ignored"
            else:
                item["status"] = "existing" if source.last_value == original["value"] else "changed"
                item["existing_value"] = float(grade.value)
        else:
            matches = [
                g
                for g in grades
                if g.id not in linked
                and subject_key(g.subject) == subject_key(original["subject"])
                and g.scale == "grade_1_6"
                and Decimal(g.value) == Decimal(original["value"])
                and (g.kind == "classwork") == (original["kind"] == "classwork")
                and (not g.assessed_on or start <= g.assessed_on <= end)
            ]
            item["matches"] = [grade_data(g) for g in matches]
            item["status"] = "possible_match" if matches else "new"
        items.append(item)
    counts = {
        key: sum(i["status"] == key for i in items)
        for key in ("new", "existing", "changed", "possible_match", "ignored")
    }
    return {
        "id": batch.id,
        "status": batch.status,
        "school_year_start": batch.school_year_start,
        "school_year": f"{batch.school_year_start}/{batch.school_year_start + 1}",
        "items": items,
        "counts": counts,
        "context_revision": context,
        "result": batch.result,
        "notice": "Die PDF enthält keine einzelnen Bewertungsdaten oder Gewichtungen. Einträge bleiben dem Halbjahr zugeordnet; Standardgewicht 1. Durchschnitts- und Summenspalten werden nicht importiert.",
    }


@router.post("/children/{child_id}/grade-imports", status_code=201)
def upload_pdf(child_id: str, file: UploadFile, idempotency_key: str = KEY, p=Depends(parent), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=True)
    raw = file.file.read(6 * 1024 * 1024 + 1)
    file.file.close()
    if len(raw) > 6 * 1024 * 1024:
        raise HTTPException(413, "Die PDF darf höchstens 6 MB groß sein.")
    file_digest = hashlib.sha256(raw).hexdigest()
    lock_child(db, child)
    previous = db.scalar(
        select(GradeImport).where(GradeImport.child_id == child.id, GradeImport.request_key == idempotency_key)
    )
    if previous:
        if previous.file_digest != file_digest:
            raise HTTPException(409, "Dieser Uploadschlüssel gehört zu einer anderen PDF.")
        return projection(db, child, previous)
    rate_limit(db, "grade-pdf:" + p.user.id, 12, 3600, commit=False)
    # Reserve the bounded parse attempt, then release all locks while reading
    # untrusted PDF data. Logout and permission changes must remain possible.
    db.commit()
    db.expunge_all()
    try:
        parsed = isolated_extract(raw)
    except ValueError as error:
        raise HTTPException(422, str(error)) from None
    # Another upload may have completed while parsing. Reacquire the same
    # child lock and recheck fresh authority and idempotency before any write.
    lock_child(db, child)
    child = live_parent(db, p, child)
    previous = db.scalar(
        select(GradeImport).where(GradeImport.child_id == child.id, GradeImport.request_key == idempotency_key)
    )
    if previous:
        if previous.file_digest != file_digest:
            raise HTTPException(409, "Dieser Uploadschlüssel gehört zu einer anderen PDF.")
        return projection(db, child, previous)
    if parsed["school_year_start"] != school_year(local_day(child)):
        raise HTTPException(422, "Bitte die Übersicht des aktuellen Schuljahres hochladen.")
    keys = [slot_key(parsed["school_year_start"], e) for e in parsed["entries"]]
    if len(set(keys)) != len(keys):
        raise HTTPException(422, "Die PDF enthält doppelte oder nicht eindeutig zuordenbare Tabellenzeilen.")
    batch = GradeImport(
        child_id=child.id,
        request_key=idempotency_key,
        file_digest=file_digest,
        school_year_start=parsed["school_year_start"],
        entries=parsed["entries"],
    )
    db.add(batch)
    db.flush()
    audit(db, p.user.id, "grade.import_preview", batch.id)
    db.commit()
    return projection(db, child, batch)


@router.get("/children/{child_id}/grade-imports/{import_id}")
def read_import(child_id: str, import_id: str, p=Depends(parent), db=Depends(get_db)):
    child = child_access(db, p, child_id)
    return projection(db, child, owned_import(db, child, import_id))


class ImportChoice(s.Strict):
    slot_key: str = Field(pattern=r"^[a-f0-9]{64}$")
    action: Literal["add", "link", "update", "keep", "skip"]
    grade_id: str | None = Field(default=None, pattern=r"^[a-f0-9]{32}$")


class ImportConfirmation(s.Strict):
    school_year_start: int = Field(ge=2000, le=2200)
    context_revision: str = Field(pattern=r"^[a-f0-9]{64}$")
    choices: list[ImportChoice] = Field(max_length=1200)
    classwork_weight: int = Field(default=1, ge=1, le=5)
    other_weight: int = Field(default=1, ge=1, le=5)


@router.post("/children/{child_id}/grade-imports/{import_id}/confirm")
def confirm_import(child_id: str, import_id: str, data: ImportConfirmation, p=Depends(parent), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=True)
    lock_child(db, child)
    # Ordinary grade editing locks its grade row. Serialize the snapshot with
    # those writes too; child locking alone only serializes imports/creation.
    list(
        db.scalars(
            select(SchoolGrade).where(SchoolGrade.child_id == child.id).order_by(SchoolGrade.id).with_for_update()
        )
    )
    batch = owned_import(db, child, import_id)
    fingerprint = digest(data.model_dump(mode="json"))
    if batch.status == "applied":
        if batch.confirmation_digest != fingerprint:
            raise HTTPException(409, "Dieser Import wurde bereits mit einer anderen Auswahl übernommen.")
        return batch.result
    if batch.school_year_start != data.school_year_start or data.school_year_start != school_year(local_day(child)):
        raise HTTPException(409, "Das Schuljahr hat sich geändert. Bitte eine aktuelle PDF verwenden.")
    preview = projection(db, child, batch)
    if preview["context_revision"] != data.context_revision:
        raise HTTPException(409, "Die Noten wurden inzwischen geändert. Bitte die Vorschau neu laden.")
    choices = {r.slot_key: r for r in data.choices}
    if len(choices) != len(data.choices) or set(choices) != {r["slot_key"] for r in preview["items"]}:
        raise HTTPException(422, "Bitte jede erkannte Note genau einmal prüfen.")
    counts = {"added": 0, "linked": 0, "updated": 0, "unchanged": 0, "skipped": 0}
    for item in preview["items"]:
        choice = choices[item["slot_key"]]
        source = db.scalar(
            select(GradeSourceSlot).where(
                GradeSourceSlot.child_id == child.id, GradeSourceSlot.slot_key == item["slot_key"]
            )
        )
        grade = db.get(SchoolGrade, item["grade_id"]) if item["grade_id"] else None
        allowed = {
            "new": {"add", "skip"},
            "possible_match": {"add", "link", "skip"},
            "changed": {"update", "keep", "skip"},
            "existing": {"keep", "skip"},
            "ignored": {"skip"},
        }
        if choice.action not in allowed[item["status"]] or (choice.grade_id and choice.action != "link"):
            raise HTTPException(422, "Diese Auswahl passt nicht mehr zur Vorschau.")
        if not source:
            source = GradeSourceSlot(
                child_id=child.id,
                slot_key=item["slot_key"],
                school_year_start=batch.school_year_start,
                last_value=item["value"],
            )
            db.add(source)
        if choice.action == "link":
            if choice.grade_id not in {r["id"] for r in item["matches"]} or db.scalar(
                select(GradeSourceSlot.id).where(GradeSourceSlot.grade_id == choice.grade_id)
            ):
                raise HTTPException(409, "Diese vorhandene Note wurde bereits zugeordnet. Bitte Vorschau neu laden.")
            grade = db.get(SchoolGrade, choice.grade_id)
            counts["linked"] += 1
        elif choice.action == "add":
            grade = SchoolGrade(
                child_id=child.id,
                subject=item["subject"],
                topic="",
                kind=item["kind"],
                scale="grade_1_6",
                value=Decimal(item["value"]),
                assessed_on=None,
                school_year_start=batch.school_year_start,
                semester=item["semester"],
                weight=data.classwork_weight if item["kind"] == "classwork" else data.other_weight,
                note="",
                revision=1,
            )
            db.add(grade)
            db.flush()
            counts["added"] += 1
        elif choice.action == "update":
            grade.value, grade.updated, grade.revision = Decimal(item["value"]), int(now()), grade.revision + 1
            counts["updated"] += 1
        else:
            counts["unchanged" if choice.action == "keep" else "skipped"] += 1
        source.grade_id = grade.id if grade else None
        source.last_value = item["value"]
        source.ignored = choice.action == "skip"
        db.flush()
    batch.status, batch.confirmation_digest, batch.result = "applied", fingerprint, {"id": batch.id, **counts}
    audit(db, p.user.id, "grade.import_confirm", batch.id)
    db.commit()
    return batch.result
