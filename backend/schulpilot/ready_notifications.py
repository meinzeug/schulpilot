"""Neutral ready receipts for newly requested, saved rounds; no model calls.

Legacy jobs without a submitting identity are not backfilled. The receipt is
private job metadata; the inbox message contains only an owned unit reference.
"""

import copy
import re

from fastapi import HTTPException
from sqlalchemy import select

from .db import DB, Assignment, Child, Job, LearningUnit, Material, Message, SchoolDay, UnitSource, now
from .providers import ProviderError
from .security import insert_ignore
from .source_lineage import digest, usable_source

KIND = "round_ready"
ORIGIN = "completion_origin"
RECEIPTS = "ready_notice_receipts"
UNIT_PATH_PATTERN = r"/unit/[a-f0-9]{32}"
ROUND_KINDS = ("unit", "coach_practice", "study_block", "controller_check")


def valid_unit_path(value):
    return isinstance(value, str) and re.fullmatch(UNIT_PATH_PATTERN, value, re.ASCII) is not None


def valid_unit(db, unit, child):
    if not unit or unit.child_id != child.id or unit.synthetic or unit.status != "not_started":
        return False
    from .visual_reference_models import UnitVisualSnapshot
    from .visual_references import projection

    if db.get(UnitVisualSnapshot, unit.id) is not None and projection(db, unit)["explanation_visual_status"] != "ready":
        return False
    refs = list(db.scalars(select(UnitSource).where(UnitSource.unit_id == unit.id)))
    if refs:
        return all(
            (material := db.get(Material, ref.material_id)) is not None
            and material.child_id == child.id
            and material.revision == ref.revision
            and material.confirmed
            and usable_source(db, material, ref.revision)
            for ref in refs
        )
    assignment = db.get(Assignment, unit.assignment_id) if unit.assignment_id else None
    return bool(
        assignment
        and assignment.child_id == child.id
        and assignment.source_status == "confirmed"
        and assignment.revision == unit.goal_revision
    )


def authority(db, job, child):
    from .study_authority import validate

    value = job.payload.get(ORIGIN)
    if value:
        validate(db, child, value)
        return True
    if job.kind == "package" and job.payload.get("preparation_id"):
        from .school_preparation import _check_sources, _state
        from .school_preparation import authority as day_authority

        day = db.get(SchoolDay, job.payload.get("school_day_id"))
        state = _state(day) if day else {}
        if (
            not day
            or day.child_id != child.id
            or state.get("run_id") != job.payload["preparation_id"]
            or state.get("job_id") != job.id
        ):
            return False
        day_authority(db, day, state)
        _check_sources(db, day, state)
        return True
    return False


def unit_ids(job):
    data = job.result or {}
    if job.kind in ROUND_KINDS:
        return [data["unit_id"]] if isinstance(data.get("unit_id"), str) else []
    if job.kind == "package" and isinstance(data.get("unit_ids"), list):
        return data["unit_ids"][:24]
    return []


def remember(db, job):
    """Called after a committed success, under Child lock. Idempotent receipts."""
    if not job or job.status != "completed" or not job.finished or job.kind not in (*ROUND_KINDS, "package"):
        return False
    # Existing exam notifications own these requests; avoid duplicate notices.
    if (
        job.payload.get("exam_round_id")
        or job.payload.get("exam_review_practice")
        or (job.kind == "package" and job.payload.get("preparation_id"))
    ):
        return False
    child = db.get(Child, job.child_id)
    try:
        if not child or not authority(db, job, child):
            return False
    except (ProviderError, HTTPException):
        return False
    receipts = copy.deepcopy(job.payload.get(RECEIPTS, []))
    old = len(receipts)
    for identifier in dict.fromkeys(unit_ids(job)):
        unit = db.get(LearningUnit, identifier)
        if not valid_unit(db, unit, child):
            continue
        mid = digest([KIND, job.id, unit.id])[:32]
        if any(row.get("message_id") == mid for row in receipts):
            continue
        insert_ignore(
            db,
            Message,
            {
                "id": mid,
                "child_id": child.id,
                "sender_id": None,
                "kind": KIND,
                "body": "Deine Lernrunde ist bereit.",
                "context": {"unit_id": unit.id},
                "resolved": False,
                "created": job.finished,
            },
        )
        receipts.append({"message_id": mid, "unit_id": unit.id, "created": job.finished})
    if len(receipts) == old:
        return False
    job.payload = {**job.payload, RECEIPTS: receipts}
    return True


def events_for_child(db, child, current, *, retention=86400):
    result = []
    query = (
        select(Job)
        .where(
            Job.child_id == child.id,
            Job.status == "completed",
            Job.finished > current - retention,
            Job.finished <= current,
            Job.payload[RECEIPTS][0]["message_id"].as_string().is_not(None),
        )
        .order_by(Job.finished.desc(), Job.id)
        .limit(100)
    )
    for job in db.scalars(query):
        try:
            if not authority(db, job, child):
                continue
        except (ProviderError, HTTPException):
            continue
        allowed = set(unit_ids(job))
        for receipt in (job.payload.get(RECEIPTS) or [])[:24]:
            identifier = receipt.get("unit_id")
            mid = receipt.get("message_id")
            if identifier not in allowed or mid != digest([KIND, job.id, identifier])[:32]:
                continue
            unit, message = db.get(LearningUnit, identifier), db.get(Message, mid)
            if (
                not valid_unit(db, unit, child)
                or not message
                or message.child_id != child.id
                or message.kind != KIND
                or message.sender_id is not None
                or message.context != {"unit_id": identifier}
                or message.created != job.finished
            ):
                continue
            route = "/unit/" + identifier
            if valid_unit_path(route):
                result.append(
                    {
                        "id": KIND + ":" + mid,
                        "kind": KIND,
                        "child_id": child.id,
                        "created": message.created,
                        "title": "Deine Lernrunde ist bereit",
                        "route": route,
                    }
                )
    return result


def delivery_key(device, event):
    return device.id + ":" + event["id"]


def day_route(db, day, child):
    """Only saved rounds from this exact completed package can be a target."""
    from .school_preparation import notice_allowed

    state = day.preparation or {}
    if state.get("status") != "ready" or not notice_allowed(db, day):
        return None
    job = db.get(Job, state.get("job_id")) if state.get("job_id") else None
    if (
        not job
        or job.kind != "package"
        or job.child_id != child.id
        or job.status != "completed"
        or job.payload.get("preparation_id") != state.get("run_id")
    ):
        return None
    for identifier in unit_ids(job):
        unit = db.get(LearningUnit, identifier)
        if valid_unit(db, unit, child) and unit.school_day_id == day.id:
            return "/unit/" + unit.id
    return None


def advance_one():
    """Recover a crash between saving a new bound round and its local notice."""
    from sqlalchemy import update

    with DB() as db:
        ids = list(
            db.scalars(
                select(Job.id)
                .where(
                    Job.status == "completed",
                    Job.finished > int(now()) - 86400,
                    Job.finished <= int(now()),
                    Job.kind.in_(ROUND_KINDS),
                    Job.payload[ORIGIN]["version"].as_integer() == 1,
                    Job.payload[RECEIPTS][0]["message_id"].as_string().is_(None),
                )
                .order_by(Job.finished.desc(), Job.id)
                .limit(50)
            )
        )
    for identifier in ids:
        with DB.begin() as db:
            job = db.get(Job, identifier)
            if not job:
                continue
            db.execute(update(Child).where(Child.id == job.child_id).values(grade=Child.grade))
            db.refresh(job)
            remember(db, job)
