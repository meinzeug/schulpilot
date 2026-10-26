"""Read-only completion receipts for an exact source-bound after-school run."""

import re

from sqlalchemy import select
from sqlalchemy.orm import load_only

from .db import SchoolDay

PREPARATION_PATH_PATTERN = r"/after-school/[a-f0-9]{32}\?day=[a-f0-9]{32}"


def valid_preparation_path(value):
    return isinstance(value, str) and re.fullmatch(PREPARATION_PATH_PATTERN, value, re.ASCII) is not None


def events_for_child(db, child, current):
    from .school_preparation import notice_allowed

    result = []
    query = select(SchoolDay).options(load_only(
        SchoolDay.id, SchoolDay.child_id, SchoolDay.revision, SchoolDay.preparation
    )).where(SchoolDay.child_id == child.id,
        SchoolDay.preparation["notice_created"].as_integer() > current - 86400,
        SchoolDay.preparation["notice_created"].as_integer() <= current
    ).order_by(SchoolDay.created.desc(), SchoolDay.id).limit(100)
    for day in db.scalars(query):
        state = day.preparation or {}
        status, run_id = state.get("status"), state.get("run_id")
        if (status not in ("needs_review", "needs_photo", "ready", "saved") or state.get("notice_status") != status
                or not isinstance(run_id, str) or not re.fullmatch(r"[a-f0-9]{32}", run_id, re.ASCII)
                or not notice_allowed(db, day)):
            continue
        from .ready_notifications import day_route

        route = day_route(db, day, child) or f"/after-school/{child.id}?day={day.id}"
        from .ready_notifications import valid_unit_path

        if not (valid_preparation_path(route) or valid_unit_path(route)):
            continue
        result.append({"id": f"preparation:{day.id}:{run_id}:{status}",
            "kind": "preparation_ready" if status in ("ready", "saved") else "preparation_review",
            "created": state["notice_created"], "route": route})
    return result


def delivery_key(device, event):
    return device.id + ":" + event["id"]
