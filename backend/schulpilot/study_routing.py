"""Read the actual unpublished stage's visual output before reservation.

No stage creation, provider call, retry or route/cost-setting change. The study
worker independently revalidates the bound authority and sources before/after AI.
"""
import re

from fastapi import HTTPException

from .db import Child, Family, Job, SchoolDay, now


def extended_output(db, child_id, job):
    if not job or job.child_id != child_id or job.kind != "study_block" or job.status != "queued":
        return False
    data = job.payload
    if (not isinstance(data, dict) or any(not isinstance(data.get(key), str)
            or not re.fullmatch(r"[a-f0-9]{32}", data[key]) for key in ("day_id", "block_id"))
            or any(not isinstance(data.get(key), str) or not re.fullmatch(r"[a-f0-9]{64}", data[key])
                for key in ("source_hash", "planning"))):
        return False
    day, child = db.get(SchoolDay, data["day_id"]), db.get(Child, child_id)
    if not day or not child or day.child_id != child_id:
        return False
    from .providers import ProviderError
    from .school_day import planning_fingerprint
    from .study_authority import validate
    from .study_path import PHASES, fingerprint, sources
    from .visual_references import with_visual_context

    try:
        validate(db, child, data.get("study_authority"))
        family = db.get(Family, child.family_id)
        if not family or family.synthetic or family.expires and family.expires < now():
            return False
        items = sources(db, day)
        plan = day.learning_plan or {}
        block = next((row for row in plan.get("blocks", []) if row.get("id") == data["block_id"]), None)
        if (not block or block.get("unit_id") or plan.get("source_hash") != data["source_hash"]
                or fingerprint(items, db) != data["source_hash"]
                or planning_fingerprint(db, child) != data["planning"]
                or any(page.child_id != child_id or page.school_day_id != day.id or page.synthetic for page in items)
                or block.get("phase") not in {phase for phase, _ in PHASES}
                or type(block.get("question_count")) is not int or not 2 <= block["question_count"] <= 5
                or not isinstance(block.get("subject"), str) or not block["subject"]
                or not isinstance(block.get("title"), str) or not block["title"]):
            return False
        # generate() reserves before assigning block.job_id. A previous failed
        # request may still occupy that slot; it contributes no routing evidence.
        previous_id = block.get("job_id")
        if previous_id and previous_id != job.id:
            previous = db.get(Job, previous_id)
            if (not previous or previous.child_id != child_id or previous.kind != "study_block"
                    or previous.status != "failed" or previous.payload.get("day_id") != day.id
                    or previous.payload.get("block_id") != block["id"]):
                return False
        ids = block.get("material_ids")
        if (not isinstance(ids, list) or not ids or any(not isinstance(key, str) for key in ids)
                or len(set(ids)) != len(ids)):
            return False
        selected = [page for page in items if page.id in ids]
        if len(selected) != len(ids) or any(page.subject != block["subject"] for page in selected):
            return False
        payload = {"required_subject": block["subject"], "required_topic": block["title"],
            "material": {"subject": block["subject"], "topic": block["title"], "content": ""},
            "study_block": {"mode": block["phase"], "question_count": block["question_count"], "tasks": []}}
        payload = with_visual_context(db, child, payload, selected)
    except (HTTPException, ProviderError, ValueError):
        return False
    return (payload.get("visual_context") or {}).get("required") is True
