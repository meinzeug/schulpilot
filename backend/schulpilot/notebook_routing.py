"""Read-only recorded output need for an explicit repeat of one notebook selection.

This does not retry a job or raise any limit. The ordinary enqueue/reservation
path may choose its already approved route before a new, conscious request.
"""

import re

from fastapi import HTTPException
from sqlalchemy import select

from .db import Child, Job

LENGTH_MESSAGE = (
    "Die KI hat die begrenzte Ausgabelänge erreicht. Die unvollständige Antwort wurde verworfen; "
    "kein automatischer Wiederholungsversuch."
)


def length_failed(db, child_id, job):
    if not job or job.child_id != child_id or job.kind != "unit" or job.status != "queued":
        return False
    data = job.payload
    meta = data.get("notebook_practice") if isinstance(data, dict) else None
    if (not isinstance(meta, dict) or set(meta) != {"version", "question_count", "subject_id", "source_signature"}
            or not isinstance(meta.get("source_signature"), str)
            or not re.fullmatch(r"[0-9a-f]{64}", meta["source_signature"])
            or type(data.get("material_revision")) is not int or data["material_revision"] < 1
            or data.get("assignment_id") or data.get("review_of")):
        return False
    child = db.get(Child, child_id, populate_existing=True)
    if not child:
        return False
    from .notebook_practice import guard
    from .providers import ProviderError

    try:
        pages = guard(db, child, data)
    except (HTTPException, ProviderError):
        return False
    anchor = next((page for page in pages if page.id == data.get("material_id")), None)
    if not anchor or anchor.revision != data["material_revision"]:
        return False
    previous = db.scalars(select(Job).where(
        Job.child_id == child_id, Job.kind == "unit", Job.status == "failed", Job.id != job.id,
        Job.payload["material_id"].as_string() == data["material_id"],
        Job.payload["notebook_practice"]["source_signature"].as_string() == meta["source_signature"],
    ).order_by(Job.created.desc(), Job.id.desc()).limit(8))
    for old in previous:
        if (old.error_code != "invalid_output" or not isinstance(old.error, str)
                or " ".join(old.error.split()) != LENGTH_MESSAGE
                or old.payload.get("notebook_practice") != meta
                or old.payload.get("sources") != data.get("sources")
                or type(old.payload.get("material_revision")) is not int
                or old.payload["material_revision"] != data["material_revision"]
                or old.payload.get("assignment_id") or old.payload.get("review_of")):
            continue
        try:
            guard(db, child, old.payload)
        except (HTTPException, ProviderError):
            continue
        return True
    return False
