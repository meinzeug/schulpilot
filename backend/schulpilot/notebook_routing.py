"""Read-only recorded output need for an explicit repeat of one notebook selection.

This does not retry a job or raise any limit. The ordinary enqueue/reservation
path may choose its already approved route before a new, conscious request.
"""

import re

from fastapi import HTTPException
from sqlalchemy import select

from .db import Child, Job, Subject

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


def extended_output(db, child_id, job):
    """Use the real source compiler contract, never input length as output size.

    Only two-question selections with immutable prepared fraction steps keep
    the small economy route. This read-only check does not plan questions,
    publish data, consume history, reserve money or dispatch a provider.
    The worker still rebuilds and validates its full current context normally.
    """
    if not job or job.child_id != child_id or job.kind != "unit" or job.status != "queued":
        return False
    data = job.payload
    if not isinstance(data, dict) or not data.get("notebook_practice"):
        return False
    child = db.get(Child, child_id, populate_existing=True)
    if child is None:
        return False
    from .notebook_practice import guard
    from .providers import ProviderError

    try:
        pages = guard(db, child, data)
    except (HTTPException, ProviderError):
        return False
    anchor = next((page for page in pages if page.id == data.get("material_id")), None)
    if (anchor is None or type(data.get("material_revision")) is not int
            or data["material_revision"] != anchor.revision):
        return False
    if data["notebook_practice"]["question_count"] != 2:
        return True
    from . import notebook_fraction_expansions as notebook_expansion
    from . import study_fraction_expansions as expansion
    from .unit_fraction_compositions import compile_candidates
    from .visual_references import with_visual_context

    subject = db.get(Subject, anchor.subject_id)
    payload = {"required_subject": subject.title,
        "notebook_practice": {key: data["notebook_practice"][key] for key in ("version", "question_count")},
        "material": {"subject": anchor.subject, "topic": anchor.topic, "content": anchor.content},
        **({"labs_enabled": True} if data.get("labs_enabled") is True else {})}
    payload = with_visual_context(db, child, payload, pages)
    context = payload["visual_context"]
    # add_reference has already checked the immutable database recipe/digest.
    # _supported is the exact predicate used again by prepare and bind_schema;
    # failure/exhaustion in the later planner remains a zero-dispatch stop.
    if (notebook_expansion._supported(payload) and any(ref.get("id") == expansion.RECIPE
            and type(ref.get("version")) is int and ref["version"] == expansion.VERSION
            and ref.get("digest") for ref in context["references"])
            and expansion._introductions(context, [])):
        return False
    candidates = compile_candidates(context)
    return not (any(row["disclosure"] == "given" for row in candidates)
        and any(row["disclosure"] == "solution" for row in candidates))
