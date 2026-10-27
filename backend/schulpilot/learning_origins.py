"""Read-only provenance for saved notebook rounds, including legacy follow-ups.

Only the child's own explicit UnitSource links establish a day. Mixed-day rounds
stay independent. Nothing here changes a source, answer, plan or learning time.
"""
from sqlalchemy import select

from .db import LearningUnit, Material, UnitSource


def round_days(db, child_id):
    values = {}
    for unit_id, day_id in db.execute(select(UnitSource.unit_id, Material.school_day_id)
            .join(LearningUnit, LearningUnit.id == UnitSource.unit_id)
            .join(Material, Material.id == UnitSource.material_id)
            .where(LearningUnit.child_id == child_id, Material.child_id == child_id)):
        values.setdefault(unit_id, set()).add(day_id)
    return {unit_id: next(iter(days)) for unit_id, days in values.items()
            if len(days) == 1 and None not in days}


def open_rounds(db, child_id, day_id):
    days = round_days(db, child_id)
    return [{"id": unit.id, "topic": unit.topic, "subject": unit.subject,
             "status": unit.status, "round_kind": unit.round_kind}
            for unit in db.scalars(select(LearningUnit).where(LearningUnit.child_id == child_id,
                LearningUnit.status != "completed").order_by(LearningUnit.created, LearningUnit.id))
            if days.get(unit.id) == day_id and not unit.school_day_id]


def next_item(plan):
    items = [item for item in [*plan.get("today", []), *plan.get("voluntary", [])]
             if item.get("status") != "completed" and
             (not item.get("scheduled_for") or item["scheduled_for"] <= plan["date"])]
    return next((item for item in items if item["kind"] == "unit" and item.get("status") in ("active", "paused")), None) or \
        next((item for item in items if item.get("mandatory")), None) or \
        next((item for item in items if item["kind"] == "unit"), None) or next(iter(items), None)
