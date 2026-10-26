"""Read the real next-practice output contract before its normal reservation.

Existing coaching/source helpers remain the authority. This projection neither
creates/retries a job nor changes a report, answer, source, cap or route setting.
"""

from fastapi import HTTPException
from sqlalchemy import select

from .db import Child, Job, LearningUnit, Material, UnitCoaching

LENGTH_MESSAGE = (
    "Die KI hat die begrenzte Ausgabelänge erreicht. Die unvollständige Antwort wurde verworfen; "
    "kein automatischer Wiederholungsversuch."
)


def output_need(db, child_id, job):
    result = {"coach_extended_output": False, "coach_length_failed": False}
    if not job or job.child_id != child_id or job.kind != "coach_practice" or job.status != "queued":
        return result
    data = job.payload
    if (
        not isinstance(data, dict)
        or not isinstance(data.get("unit_id"), str)
        or not isinstance(data.get("signature"), str)
        or not data["signature"]
        or data.get("next_action") not in ("repair", "check")
        or type(data.get("practice_number")) is not int
        or data["practice_number"] not in (1, 2)
    ):
        return result
    unit = db.get(LearningUnit, data["unit_id"], populate_existing=True)
    child = db.get(Child, child_id)
    item = db.get(UnitCoaching, data["unit_id"], populate_existing=True)
    if (
        unit is None
        or child is None
        or unit.child_id != child_id
        or unit.synthetic
        or item is None
        or item.status != "ready"
        or item.next_unit_id
        or not item.report.get("practice_deferred")
        or item.decision != data["next_action"]
    ):
        return result
    from .coaching import context, focus_ids
    from .providers import ProviderError
    from .visual_references import with_visual_context

    try:
        signature, payload, sources = context(db, unit)
        if signature != data["signature"]:
            return result
        payload.update(
            review=True,
            practice_kind=item.decision,
            focus_goal_ids=focus_ids(db, unit, item.decision),
            material={
                "subject": unit.subject,
                "topic": unit.topic,
                "content": "\n\n".join(source["content"] for source in payload["materials"]),
            },
        )
        payload = with_visual_context(db, child, payload, [db.get(Material, source["id"]) for source in sources])
    except (ProviderError, HTTPException, ValueError):
        # This is not permission to dispatch. The unchanged worker rebuilds and
        # strictly validates its context again before any provider call.
        return result
    result["coach_extended_output"] = (payload.get("visual_context") or {}).get("required") is True
    if data["practice_number"] == 2:
        old_jobs = db.scalars(
            select(Job).where(
                Job.child_id == child_id,
                Job.kind == "coach_practice",
                Job.status == "failed",
                Job.id != job.id,
                Job.payload["unit_id"].as_string() == unit.id,
                Job.payload["signature"].as_string() == signature,
                Job.payload["next_action"].as_string() == data["next_action"],
            )
        )
        result["coach_length_failed"] = any(
            type(old.payload.get("practice_number")) is int
            and old.payload["practice_number"] == 1
            and isinstance(old.error, str)
            and " ".join(old.error.split()) == LENGTH_MESSAGE
            for old in old_jobs
        )
    return result
