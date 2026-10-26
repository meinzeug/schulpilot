"""Current normal material/review teaching has no small output-count contract.

This pre-reservation projection reads the same owned snapshots as the worker.
It never plans/retries a round or derives a count from old questions or input
length. Notebook selections keep their separate compiler-bound policy.
"""
import re

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import load_only

from .db import Child, LearningUnit, Material, UnitSource

MESSAGE = "Die Quellen dieser Lernrunde wurden geändert. Bitte die bestätigten Heftseiten neu auswählen."
_SPECIAL = ("assignment_id", "notebook_practice", "study_block", "homework_practice", "exam_round_id", "exam_review_practice", "controller_guard")


def extended_output(db, child_id, job):
    if not job or job.kind != "unit" or job.status != "queued" or job.child_id != child_id:
        return False
    data = job.payload
    if not isinstance(data, dict) or any(data.get(key) for key in _SPECIAL) or not data.get("material_id"):
        return False
    if not isinstance(data["material_id"], str) or not re.fullmatch(r"[a-f0-9]{32}", data["material_id"]):
        raise HTTPException(409, MESSAGE)
    anchor = db.get(Material, data["material_id"], populate_existing=True)
    if anchor and (anchor.synthetic or anchor.fixture_id or anchor.purpose != "notebook"):
        return False  # Existing fixed fixtures and specialist homework/exam paths.
    child = db.get(Child, child_id, populate_existing=True)
    if (child is None or anchor is None or anchor.child_id != child_id or not anchor.confirmed
            or type(data.get("material_revision")) is not int
            or data["material_revision"] != anchor.revision):
        raise HTTPException(409, MESSAGE)
    refs = data.get("sources", [])
    if not isinstance(refs, list):
        raise HTTPException(409, MESSAGE)
    refs = refs or [{"id": anchor.id, "revision": anchor.revision}]
    if (any(not isinstance(ref, dict) or set(ref) != {"id", "revision"}
            or not isinstance(ref["id"], str) or not re.fullmatch(r"[a-f0-9]{32}", ref["id"])
            or type(ref["revision"]) is not int or ref["revision"] < 1 for ref in refs)
            or len({ref["id"] for ref in refs}) != len(refs)
            or anchor.id not in {ref["id"] for ref in refs}):
        raise HTTPException(409, MESSAGE)
    from .source_lineage import learning_source

    pages = []
    for ref in refs:
        page = db.get(Material, ref["id"], populate_existing=True)
        if (page is None or page.child_id != child_id or not page.confirmed
                or page.revision != ref["revision"] or page.purpose == "exam"):
            raise HTTPException(409, MESSAGE)
        pages.append(page)
    if any(page.purpose != "notebook" or page.synthetic or page.fixture_id for page in pages):
        return False  # Preserve the existing specialist/mixed-source semantics.
    if not any(learning_source(db, page, revision=page.revision)["content"].strip() for page in pages):
        raise HTTPException(409, MESSAGE)
    if data.get("review_of"):
        if not isinstance(data["review_of"], str) or not re.fullmatch(r"[a-f0-9]{32}", data["review_of"]):
            raise HTTPException(409, MESSAGE)
        previous = db.get(LearningUnit, data["review_of"],
            options=[load_only(LearningUnit.id, LearningUnit.child_id, LearningUnit.status, LearningUnit.material_id)], populate_existing=True)
        if (previous is None or previous.child_id != child_id or previous.status != "completed"
                or previous.material_id != anchor.id):
            raise HTTPException(409, MESSAGE)
        linked = set(db.scalars(select(UnitSource.material_id).where(UnitSource.unit_id == previous.id)))
        if linked and linked != {ref["id"] for ref in refs}:
            raise HTTPException(409, MESSAGE)
    # UnitCreate has no non-notebook output-count receipt. learning_entry may
    # turn an initially compact request into four/five questions. A saved unit's
    # question count or an unrecognized payload field is not a new contract.
    # Proven fixed two-question notebook bindings are handled independently.
    return True
