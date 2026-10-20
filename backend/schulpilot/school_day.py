"""Persisted after-school wizard; a package combines confirmed notebook pages."""

import hashlib
import json
from datetime import date
from typing import Literal

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from sqlalchemy import select, update

from . import schemas as s
from .config import settings
from .db import (
    Assignment,
    Child,
    Family,
    Job,
    LearningUnit,
    Material,
    ProviderConfig,
    SchoolDay,
    UnitSource,
    get_db,
    uid,
)
from .fixtures import DAY_FIXTURE_IDS, worksheet
from .learning import local_day, material_data, plan, record, unit_data
from .materials import enqueue, lock_material_units
from .providers import ProviderError, config_for_function, external_allowed
from .security import authenticated, child_access, rate_limit

router = APIRouter(tags=["Nach der Schule"])
MAX_PAGES = 24
MAX_CONTENT = 60_000


class StageUpdate(s.Strict):
    stage: Literal["collecting", "review"]


class PageOrder(s.Strict):
    material_ids: list[str]


def pages(db, day):
    return list(
        db.scalars(select(Material).where(Material.school_day_id == day.id).order_by(Material.page_number, Material.id))
    )


def get_day(db, p, day_id, *, write=False, allow_archived=False):
    day = db.get(SchoolDay, day_id)
    if not day:
        raise HTTPException(404, "Schultag nicht gefunden.")
    child = child_access(db, p, day.child_id, write=write and p.user.role == "parent")
    if write:
        # The same child row serializes upload, stage changes and job creation.
        db.execute(update(Child).where(Child.id == child.id).values(grade=Child.grade))
        db.refresh(day)
        if not allow_archived and day.school_date != local_day(child).isoformat():
            raise HTTPException(409, "Dieser Schultag ist gespeichert. Bitte den Assistenten für heute öffnen.")
    return day, child


def idle(db, child_id):
    if db.scalar(select(Job.id).where(Job.child_id == child_id, Job.status.in_(["queued", "running"]))):
        raise HTTPException(409, "Eine Verarbeitung läuft noch. Bitte kurz warten und aktualisieren.")


def append_page(db, p, child, day_id):
    day, _ = get_day(db, p, day_id, write=True)
    if day.child_id != child.id:
        raise HTTPException(404, "Schultag nicht gefunden.")
    idle(db, child.id)
    if day.stage != "collecting":
        raise HTTPException(409, "Bitte zuerst zum Schritt „Seiten sammeln“ zurückgehen.")
    existing = pages(db, day)
    if len(existing) >= MAX_PAGES:
        raise HTTPException(409, f"Ein Tagespaket kann höchstens {MAX_PAGES} Seiten enthalten.")
    day.revision += 1
    return day, max((m.page_number or 0 for m in existing), default=0) + 1


def planning_fingerprint(db, child):
    from .db import SchoolGrade

    db.refresh(child)
    goals = [
        (a.id, a.revision, a.done)
        for a in db.scalars(select(Assignment).where(Assignment.child_id == child.id).order_by(Assignment.id))
    ]
    snapshot = [child.grade, child.preferences, goals]
    grades = list(db.execute(select(SchoolGrade.id, SchoolGrade.revision).where(SchoolGrade.child_id == child.id).order_by(SchoolGrade.id)))
    if grades or not child.grade_planning_enabled:
        snapshot.append([child.grade_planning_enabled, [tuple(row) for row in grades]])
    return hashlib.sha256(json.dumps(snapshot, sort_keys=True).encode()).hexdigest()


def package_plan(db, day, child):
    from .grades import priorities, subject_key

    current = plan(db, child)
    available = current["available_minutes"] if day.school_date == local_day(child).isoformat() else 0
    # Mandatory parent/homework goals keep their existing place in the day.
    reserved = sum(
        x.get("estimated_minutes") or current["session_minutes"] for x in current["today"] if x["kind"] != "study_path"
    )
    remaining = max(0, available - reserved)
    minutes = min(8, s.Preferences(**child.preferences).session_minutes)
    groups = []
    covered = {
        (source.material_id, source.revision)
        for source in db.scalars(select(UnitSource).join(LearningUnit).where(LearningUnit.school_day_id == day.id))
    }
    for material in pages(db, day):
        if not material.confirmed:
            continue
        group = next((g for g in groups if g["subject"].casefold() == material.subject.casefold()), None)
        if group is None:
            group = {
                "id": f"g{len(groups) + 1}",
                "subject": material.subject,
                "topics": [],
                "material_ids": [],
                "new_material_ids": [],
                "estimated_minutes": minutes,
            }
            groups.append(group)
        group["material_ids"].append(material.id)
        if (material.id, material.revision) not in covered:
            group["new_material_ids"].append(material.id)
        if material.topic not in group["topics"]:
            group["topics"].append(material.topic)
    prefs = s.Preferences(**child.preferences)
    grade_priorities = priorities(db, child)
    ranked = sorted(
        groups,
        key=lambda g: (
            g["subject"] not in prefs.focus_subjects,
            -grade_priorities.get(subject_key(g["subject"]), 0),
            not any(t in prefs.repeat_topics for t in g["topics"]),
        ),
    )
    eligible = [g for g in ranked if g["new_material_ids"]]
    # Each explicit request prepares a small finite package. Daily/weekly
    # targets and preferred subject days never deny voluntary preparation.
    selected = eligible[:3]
    for group in groups:
        group["selected"] = group in selected
        group["covered"] = not bool(group["new_material_ids"])
    notices = []
    if reserved:
        notices.append("Deine eingeplanten Aufträge bleiben im Tagesplan. Du kannst zusätzlich freiwillig üben.")
    if current["paused"] or current["free_day"]:
        notices.extend(current["notices"][:1])
    pending_count = sum(not g["covered"] for g in groups)
    if len(selected) < pending_count:
        notices.append("Dieses Paket beginnt mit bis zu drei Fächern. Die übrigen Seiten bleiben im Lernweg erhalten.")
    return {
        "groups": groups,
        "estimated_minutes": sum(g["estimated_minutes"] for g in selected),
        "available_minutes": remaining,
        "notices": notices,
    }


def day_data(db, day, child, p):
    from .school_preparation import preparation_data

    material_list = pages(db, day)
    units = list(
        db.scalars(
            select(LearningUnit)
            .where(LearningUnit.school_day_id == day.id)
            .order_by(LearningUnit.created, LearningUnit.id)
        )
    )
    jobs = [
        j
        for j in db.scalars(select(Job).where(Job.child_id == child.id).order_by(Job.created.desc(), Job.id).limit(200))
        if j.payload.get("school_day_id") == day.id or j.payload.get("material_id") in {m.id for m in material_list}
    ]
    active = next((j for j in jobs if j.status in ("queued", "running")), None)
    unresolved_pages = {m.id for m in material_list if m.status == "uploaded"}
    latest_failed = next(
        (
            j
            for j in jobs
            if j.status == "failed"
            and (
                (j.kind == "package" and day.stage != "ready")
                or (j.kind == "extract" and j.payload.get("material_id") in unresolved_pages)
            )
        ),
        None,
    )
    return {
        "id": day.id,
        "child_id": child.id,
        "date": day.school_date,
        "stage": day.stage,
        "package_version": day.package_version,
        "read_only": day.school_date != local_day(child).isoformat(),
        "allow_uploads": day.school_date == local_day(child).isoformat(),
        "preparation": preparation_data(db, day, child),
        "max_pages": MAX_PAGES,
        "pages": [material_data(m) for m in material_list],
        "confirmed_count": sum(m.confirmed for m in material_list),
        "units": [unit_data(db, u, include_answers=p.user.role == "parent") for u in units],
        "plan": package_plan(db, day, child),
        "active_job": {"id": active.id, "kind": active.kind, "status": active.status} if active else None,
        "last_error": latest_failed.error if latest_failed else None,
        "synthetic": db.get(Family, child.family_id).synthetic,
    }


@router.get("/children/{child_id}/school-day/today")
def today(child_id: str, p=Depends(authenticated), db=Depends(get_db)):
    child = child_access(db, p, child_id)
    day = db.scalar(
        select(SchoolDay).where(SchoolDay.child_id == child.id, SchoolDay.school_date == local_day(child).isoformat())
    )
    return {"day": day_data(db, day, child, p) if day else None, "date": local_day(child).isoformat()}


@router.post("/children/{child_id}/school-day/today", status_code=201)
def begin(child_id: str, p=Depends(authenticated), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=p.user.role == "parent")
    db.execute(update(Child).where(Child.id == child.id).values(grade=Child.grade))
    day = db.scalar(
        select(SchoolDay).where(SchoolDay.child_id == child.id, SchoolDay.school_date == local_day(child).isoformat())
    )
    if not day:
        day = SchoolDay(child_id=child.id, school_date=local_day(child).isoformat())
        db.add(day)
        record(db, child.id, "school_day_started")
        db.commit()
    return day_data(db, day, child, p)


@router.get("/school-days/{day_id}")
def view(day_id: str, p=Depends(authenticated), db=Depends(get_db)):
    day, child = get_day(db, p, day_id)
    return day_data(db, day, child, p)


@router.get("/children/{child_id}/school-days")
def history(
    child_id: str,
    before: date | None = None,
    limit: int = Query(20, ge=1, le=50),
    p=Depends(authenticated),
    db=Depends(get_db),
):
    child = child_access(db, p, child_id)
    query = select(SchoolDay).where(SchoolDay.child_id == child.id)
    if before:
        query = query.where(SchoolDay.school_date < before.isoformat())
    days = list(db.scalars(query.order_by(SchoolDay.school_date.desc()).limit(limit + 1)))
    rows = []
    for day in days[:limit]:
        units = list(db.scalars(select(LearningUnit).where(LearningUnit.school_day_id == day.id)))
        rows.append(
            {
                "id": day.id,
                "date": day.school_date,
                "stage": day.stage,
                "package_version": day.package_version,
                "page_count": len(pages(db, day)),
                "unit_count": len(units),
                "completed_units": sum(u.status == "completed" for u in units),
                "subjects": sorted({m.subject for m in pages(db, day) if m.subject}),
            }
        )
    return {"days": rows, "next_before": rows[-1]["date"] if len(days) > limit else None}


@router.post("/school-days/{day_id}/extend")
def extend(day_id: str, p=Depends(authenticated), db=Depends(get_db)):
    day, child = get_day(db, p, day_id, write=True)
    idle(db, child.id)
    if day.stage == "ready":
        day.stage = "collecting"
        day.revision += 1
        record(db, child.id, "school_day_extended", {"school_day_id": day.id, "version": day.package_version})
        db.commit()
    return day_data(db, day, child, p)


@router.put("/school-days/{day_id}/page-order")
def reorder(day_id: str, data: PageOrder, p=Depends(authenticated), db=Depends(get_db)):
    day, child = get_day(db, p, day_id, write=True)
    idle(db, child.id)
    source_pages = pages(db, day)
    if day.stage != "collecting":
        raise HTTPException(409, "Seiten können beim Sammeln sortiert werden.")
    if len(data.material_ids) != len(source_pages) or set(data.material_ids) != {m.id for m in source_pages}:
        raise HTTPException(422, "Bitte alle Seiten dieses Tages genau einmal angeben.")
    by_id = {m.id: m for m in source_pages}
    for position, material_id in enumerate(data.material_ids, 1):
        by_id[material_id].page_number = position
    day.revision += 1
    record(db, child.id, "school_day_reordered", {"school_day_id": day.id})
    db.commit()
    return day_data(db, day, child, p)


@router.post("/school-days/{day_id}/finish-additions")
def finish_additions(day_id: str, p=Depends(authenticated), db=Depends(get_db)):
    day, child = get_day(db, p, day_id, write=True)
    idle(db, child.id)
    if not db.scalar(select(LearningUnit.id).where(LearningUnit.school_day_id == day.id)) or not all(
        m.confirmed for m in pages(db, day)
    ):
        raise HTTPException(409, "Bitte neue Seiten zuerst prüfen. Vorhandene Einheiten bleiben weiterhin nutzbar.")
    day.stage = "ready"
    day.revision += 1
    record(db, child.id, "day_additions_deferred", {"school_day_id": day.id})
    from .school_preparation import saved_by_user

    saved_by_user(db, day, p)
    db.commit()
    return day_data(db, day, child, p)


@router.post("/school-days/{day_id}/save-for-later")
def save_for_later(day_id: str, p=Depends(authenticated), db=Depends(get_db)):
    day, child = get_day(db, p, day_id, write=True, allow_archived=True)
    idle(db, child.id)
    source_pages = pages(db, day)
    if not source_pages or not all(m.confirmed for m in source_pages):
        raise HTTPException(409, "Bitte zuerst alle Heftseiten prüfen und bestätigen.")
    from .study_path import ensure_plan

    ensure_plan(db, day)
    if day.stage != "ready":
        day.stage = "ready"
        day.revision += 1
        record(db, child.id, "school_day_saved", {"school_day_id": day.id, "page_count": len(source_pages)})
    from .school_preparation import saved_by_user

    saved_by_user(db, day, p)
    db.commit()
    return day_data(db, day, child, p)


@router.post("/school-days/{day_id}/prepare", status_code=202)
def prepare(day_id: str, idempotency_key: str | None = Header(None), p=Depends(authenticated), db=Depends(get_db)):
    from .school_preparation import advance, preparation_data, submit

    day, child = get_day(db, p, day_id, write=True, allow_archived=True)
    submit(db, p, day, child, idempotency_key)
    db.commit()
    # This only reserves one durable job. No external request runs in HTTP.
    advance(day.id)
    db.expire_all()
    day = db.get(SchoolDay, day_id)
    return {"preparation": preparation_data(db, day, child)}


@router.post("/school-days/{day_id}/postpone")
def postpone(day_id: str, p=Depends(authenticated), db=Depends(get_db)):
    from .school_preparation import postpone_preparation

    day, child = get_day(db, p, day_id, write=True, allow_archived=True)
    idle(db, child.id)
    postpone_preparation(db, day)
    db.commit()
    return day_data(db, day, child, p)


@router.put("/school-days/{day_id}/stage")
def change_stage(day_id: str, data: StageUpdate, p=Depends(authenticated), db=Depends(get_db)):
    day, child = get_day(db, p, day_id, write=True)
    idle(db, child.id)
    if day.stage == "ready":
        raise HTTPException(
            409, "Das fertige Tagespaket bleibt erhalten. Zusätzliche Materialien können einzeln importiert werden."
        )
    if data.stage == "review" and not pages(db, day):
        raise HTTPException(409, "Bitte zuerst mindestens eine Seite hinzufügen.")
    day.stage = data.stage
    day.revision += 1
    db.commit()
    return day_data(db, day, child, p)


@router.post("/school-days/{day_id}/synthetic-pages", status_code=201)
def synthetic_pages(day_id: str, p=Depends(authenticated), db=Depends(get_db)):
    day, child = get_day(db, p, day_id, write=True)
    if not db.get(Family, child.family_id).synthetic:
        raise HTTPException(403, "Testseiten sind ausschließlich im synthetischen Testraum verfügbar.")
    if pages(db, day):
        return day_data(db, day, child, p)
    if day.stage != "collecting":
        raise HTTPException(409, "Bitte zuerst Seiten sammeln.")
    idle(db, child.id)
    try:
        external_allowed(config_for_function(db.get(ProviderConfig, 1), "extract"), image=True, synthetic_fixture=True)
    except ProviderError as error:
        raise HTTPException(503, str(error)) from None
    rate_limit(db, "day-fixtures:" + p.user.id, 3, 86400, commit=False)
    directory = settings.data_dir / "uploads"
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    destinations = []
    try:
        for i, fixture_id in enumerate(DAY_FIXTURE_IDS, 1):
            path = uid() + ".jpg"
            destination = directory / path
            destinations.append(destination)
            destination.write_bytes(worksheet(fixture_id))
            destination.chmod(0o600)
            db.add(
                Material(
                    child_id=child.id,
                    school_day_id=day.id,
                    page_number=i,
                    title=f"Testheft · Seite {i}",
                    path=path,
                    synthetic=True,
                    fixture_id=fixture_id,
                )
            )
        day.revision += 1
        record(db, child.id, "school_day_pages", {"count": 2, "synthetic": True})
        db.commit()
    except Exception:
        for destination in destinations:
            destination.unlink(missing_ok=True)
        raise
    return day_data(db, day, child, p)


@router.delete("/school-days/{day_id}/pages/{material_id}")
def remove_page(day_id: str, material_id: str, p=Depends(authenticated), db=Depends(get_db)):
    day, child = get_day(db, p, day_id)
    child_access(db, p, child.id, write=p.user.role == "parent")
    material = db.get(Material, material_id)
    if not material or material.school_day_id != day.id or material.child_id != child.id:
        raise HTTPException(404, "Seite nicht gefunden.")
    lock_material_units(db, child.id, material_id)
    day, child = get_day(db, p, day_id, write=True, allow_archived=True)
    idle(db, child.id)
    material = db.get(Material, material_id, populate_existing=True)
    if not material or material.school_day_id != day.id or material.child_id != child.id:
        raise HTTPException(404, "Seite nicht gefunden.")
    if (day.stage not in ("collecting", "review") and material.status != "unreadable") or material.confirmed:
        raise HTTPException(
            409,
            "Nur ungeprüfte Seiten können hier gelöscht werden. Bestätigte Inhalte verwalten deine Eltern.",
        )
    if material.synthetic and material.fixture_id in DAY_FIXTURE_IDS and db.get(Family, child.family_id).synthetic:
        raise HTTPException(409, "Diese Beispielseiten gehören zusammen. Bitte nutze beide Seiten.")
    # Older review clients never acknowledged loss of linked answers. Route
    # those selections through the counted, revision-bound notebook deletion.
    from .unit_erasure import linked_ids

    if linked_ids(db, child.id, [material.id]):
        raise HTTPException(409, "Diese Seite hat verknüpfte Übungen. Bitte die App aktualisieren und die Löschvorschau verwenden; sie entfernt Seite, Übungen und Antworten gemeinsam.")
    path = material.path
    from .erasure import flush_journal, request
    from .tutor import purge_source_turns

    purge_source_turns(db, [material.id], child_id=material.child_id)
    request(db, "material", material.id)
    db.delete(material)
    day.revision += 1
    db.flush()
    from .school_preparation import sources_removed

    sources_removed(db, day)
    record(db, child.id, "school_day_page_removed")
    db.commit()
    if path:
        (settings.data_dir / "uploads" / path).unlink(missing_ok=True)
    flush_journal()
    return day_data(db, day, child, p)


def validate_package_sources(db, job):
    day = db.get(SchoolDay, job.payload["school_day_id"])
    child = db.get(Child, job.child_id)
    source_pages = pages(db, day) if day else []
    actual = [{"id": m.id, "revision": m.revision} for m in source_pages]
    if (
        not day
        or day.child_id != child.id
        or day.stage != "review"
        or day.revision != job.payload["day_revision"]
        or actual != job.payload["sources"]
        or not all(m.confirmed for m in source_pages)
    ):
        raise ProviderError("Seiten wurden inzwischen geändert oder gelöscht. Bitte das Tagespaket erneut prüfen.")
    if planning_fingerprint(db, child) != job.payload["planning_fingerprint"]:
        raise ProviderError("Die Elternvorgaben haben sich geändert. Bitte den aktuellen Tagesplan erneut prüfen.")
    return day, source_pages


@router.post("/school-days/{day_id}/package", status_code=202)
def create_package(
    day_id: str, idempotency_key: str | None = Header(None), p=Depends(authenticated), db=Depends(get_db)
):
    day, child = get_day(db, p, day_id, write=True, allow_archived=True)
    if day.stage == "ready":
        raise HTTPException(409, "Dein Lernpaket ist bereits fertig. Bitte die gespeicherten Einheiten öffnen.")
    source_pages = pages(db, day)
    if day.stage != "review" or not source_pages or not all(m.confirmed for m in source_pages):
        raise HTTPException(409, "Bitte erst alle Seiten erkennen lassen, prüfen und bestätigen.")
    if sum(len(m.content) for m in source_pages) > MAX_CONTENT:
        raise HTTPException(
            422,
            "Der bestätigte Text ist für ein Tagespaket zu umfangreich (maximal 60.000 Zeichen). Bitte mit deinen Eltern den Stoff eingrenzen.",
        )
    if any(m.synthetic for m in source_pages) and [m.fixture_id for m in source_pages] != list(DAY_FIXTURE_IDS):
        raise HTTPException(409, "Der KI-Tagespakettest benötigt genau die zwei festen Testheftseiten.")
    preview = package_plan(db, day, child)
    selected = [g for g in preview["groups"] if g["selected"]]
    if not selected:
        raise HTTPException(
            409,
            "Für diese bestätigten Seiten gibt es bereits Einheiten. Bitte den gespeicherten Lernweg öffnen.",
        )
    # No client-provided page IDs, family IDs, goals, durations or provider settings.
    payload = {
        "school_day_id": day.id,
        "day_revision": day.revision,
        "material_id": source_pages[0].id,
        "sources": [{"id": m.id, "revision": m.revision} for m in source_pages],
        "groups": selected,
        "planning_fingerprint": planning_fingerprint(db, child),
    }
    return enqueue(db, p, child, "package", payload, idempotency_key)


def save_package(db, job, data, *, synthetic, provider, model):
    day, source_pages = validate_package_sources(db, job)
    output = s.PackageOutput.model_validate(data)
    groups = {g["id"]: g for g in job.payload["groups"]}
    if len(output.units) != len(groups) or {u.group_id for u in output.units} != set(groups):
        raise ProviderError(
            "Die KI hat das Paket nicht vollständig nach der geprüften Fächerauswahl erstellt. Es wurden keine Teilaufgaben gespeichert."
        )
    if any(u.subject.casefold() != groups[u.group_id]["subject"].casefold() for u in output.units):
        raise ProviderError("Das erzeugte Paket weicht von den bestätigten Fächern ab. Es wurde nicht übernommen.")
    ids = []
    for value in output.units:
        group = groups[value.group_id]
        unit = LearningUnit(
            child_id=job.child_id,
            school_day_id=day.id,
            material_id=group["material_ids"][0],
            estimated_minutes=group["estimated_minutes"],
            synthetic=synthetic,
            provider=provider,
            model=model,
            **value.model_dump(exclude={"group_id"}),
        )
        db.add(unit)
        db.flush()
        for material in source_pages:
            if material.id in group["material_ids"]:
                db.add(UnitSource(unit_id=unit.id, material_id=material.id, revision=material.revision))
        ids.append(unit.id)
        record(
            db,
            job.child_id,
            "unit_created",
            {"subject": unit.subject, "topic": unit.topic, "synthetic": synthetic, "school_day_id": day.id},
            unit.id,
        )
    day.stage = "ready"
    day.package_version += 1
    for unit_id in ids:
        db.get(LearningUnit, unit_id).package_version = day.package_version
    job.result = {"school_day_id": day.id, "unit_ids": ids, "package_version": day.package_version}
    from .study_path import ensure_plan

    ensure_plan(db, day)
    record(db, job.child_id, "school_day_ready", {"page_count": len(source_pages), "unit_count": len(ids)})
