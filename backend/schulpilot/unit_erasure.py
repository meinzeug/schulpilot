"""Explicit removal of stored rounds and their derived learning evidence.

Callers acquire all selected Unit locks in ID order before Child. Usage and
budget reservations remain untouched. Restore replay uses the same cleanup.
"""

import hashlib
import json

from sqlalchemy import delete, or_, select

from .db import (
    Activity,
    Attempt,
    Job,
    LanguageProject,
    LearningMemory,
    LearningUnit,
    Mastery,
    SchoolDay,
    UnitCoaching,
    UnitSource,
    VocabularyReview,
    VocabularyReviewEvent,
)


def linked_ids(db, child_id, material_ids):
    if not material_ids:
        return []
    selected = set(
        db.scalars(
            select(LearningUnit.id).where(
                LearningUnit.child_id == child_id,
                or_(
                    LearningUnit.material_id.in_(material_ids),
                    LearningUnit.id.in_(select(UnitSource.unit_id).where(UnitSource.material_id.in_(material_ids))),
                ),
            )
        )
    )
    # Legacy follow-ups may have only their predecessor/root reference.
    rows = list(
        db.execute(
            select(
                LearningUnit.id, LearningUnit.review_of, LearningUnit.followup_of, LearningUnit.learning_root_id
            ).where(LearningUnit.child_id == child_id)
        )
    )
    while True:
        extra = {row.id for row in rows if any(value in selected for value in row[1:])} - selected
        if not extra:
            return sorted(selected)
        selected.update(extra)


def snapshot(db, ids):
    digest = hashlib.sha256()
    for model, condition in (
        (LearningUnit, LearningUnit.id.in_(ids)),
        (Attempt, Attempt.unit_id.in_(ids)),
        (Activity, Activity.unit_id.in_(ids)),
        (UnitSource, UnitSource.unit_id.in_(ids)),
        (UnitCoaching, UnitCoaching.unit_id.in_(ids)),
        (LearningMemory, LearningMemory.unit_id.in_(ids)),
    ):
        for row in db.scalars(select(model).where(condition).order_by(*model.__table__.primary_key.columns)):
            values = {c.name: getattr(row, c.name) for c in model.__table__.columns}
            digest.update(json.dumps(values, sort_keys=True, separators=(",", ":")).encode())
            digest.update(b"\n")
    return digest.hexdigest()


def counts(db, ids):
    from sqlalchemy import func

    return {
        "unit_count": len(ids),
        "answer_count": db.scalar(select(func.count()).select_from(Attempt).where(Attempt.unit_id.in_(ids))) or 0,
    }


def references(value, ids):
    if isinstance(value, str):
        return value in ids
    if isinstance(value, dict):
        return any(references(v, ids) for v in value.values())
    if isinstance(value, list):
        return any(references(v, ids) for v in value)
    return False


def remove(db, child, ids, *, journal=True):
    """Remove only selected rounds; preserve other rounds and parent orders."""
    from .assessments import rebuild_mastery
    from .erasure import request

    ids = set(ids)
    if not ids:
        return 0
    rows = list(
        db.scalars(
            select(LearningUnit)
            .where(LearningUnit.child_id == child.id, LearningUnit.id.in_(ids))
            .order_by(LearningUnit.id)
        )
    )
    topics = {(u.subject, u.topic) for u in rows}
    reviews = set(db.scalars(select(VocabularyReviewEvent.review_id).join(Attempt).where(Attempt.unit_id.in_(ids))))
    for day in db.scalars(select(SchoolDay).where(SchoolDay.child_id == child.id)):
        plan = day.learning_plan or {}
        blocks = [b for b in plan.get("blocks", []) if b.get("unit_id") not in ids]
        if blocks != plan.get("blocks", []):
            # Do not turn deleted blocks back into pending generation requests.
            day.learning_plan = {**plan, "blocks": blocks}
            day.revision += 1
    for project in db.scalars(
        select(LanguageProject).where(LanguageProject.child_id == child.id, LanguageProject.unit_id.in_(ids))
    ):
        # Keep the request tombstone and dialog chain. Deleting a project row
        # would cascade to later independent dialog steps and free its key.
        project.unit_id, project.result = None, None
        project.inputs = {"goal": "", "draft": "", "item_ids": [], "grammar_topic": None}
        project.source_revisions, project.item_revisions = [], []
        project.status = "failed"
        project.error = "Die zugehörige Lernrunde wurde gelöscht. Öffne eine andere gespeicherte Runde oder bereite bewusst neu vor."
    # Keep job/idempotency and financial history, erase content-bearing outputs.
    for job in db.scalars(select(Job).where(Job.child_id == child.id)):
        if references(job.payload, ids) or references(job.result, ids):
            job.payload, job.result, job.error = {}, {"deleted": True}, None
    for unit in rows:
        if journal:
            request(db, "unit", unit.id)
        db.delete(unit)
    db.flush()
    # Database SET NULL actions may have changed surviving predecessor/root
    # links. Derived reviews must read those persisted values, not ORM caches.
    db.expire_all()
    for subject, topic in topics:
        db.execute(
            delete(Mastery).where(Mastery.child_id == child.id, Mastery.subject == subject, Mastery.topic == topic)
        )
        rebuild_mastery(db, child, subject, topic)
    for review_id in sorted(reviews):
        row = db.get(VocabularyReview, review_id)
        if row is None:
            continue
        events = list(
            db.scalars(
                select(VocabularyReviewEvent)
                .join(Attempt)
                .where(VocabularyReviewEvent.review_id == review_id)
                .order_by(Attempt.created, Attempt.id)
            )
        )
        if not events:
            db.delete(row)
            continue
        # Rebuild the finite policy from surviving attempts, including daily cap.
        from datetime import date, timedelta

        from .vocabulary_review import INTERVALS

        row.stage, row.last_promoted = 0, None
        for event in events:
            attempt = db.get(Attempt, event.attempt_id)
            independent = attempt.outcome == "correct" and not attempt.assisted
            advanced = independent and row.last_promoted != event.day
            if advanced:
                row.stage = min(len(INTERVALS), row.stage + 1)
                row.last_promoted = event.day
                row.due = (date.fromisoformat(event.day) + timedelta(days=INTERVALS[row.stage - 1])).isoformat()
            elif not independent:
                row.stage = 0
                row.due = (date.fromisoformat(event.day) + timedelta(days=1)).isoformat()
            row.needs_clarification = attempt.outcome == "uncertain"
            event.advanced, event.stage, event.due = advanced, row.stage, row.due
    return len(rows)
