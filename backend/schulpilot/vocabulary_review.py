"""Small, auditable spaced-retrieval policy; Attempt is the sole evidence."""

from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from sqlalchemy import select, update

from .db import Activity, Attempt, Child, VocabularyItem, VocabularyReview, VocabularyReviewEvent, now
from .schemas import Preferences

INTERVALS = (1, 3, 7, 14, 30)


def local_day(child, at=None):
    instant = datetime.fromtimestamp(now(), timezone.utc) if at is None else at
    if instant.tzinfo is None:
        raise ValueError("A timezone-aware clock is required")
    return instant.astimezone(ZoneInfo(Preferences(**child.preferences).timezone)).date()


def recent_exposure(db, unit, question):
    task = question.get("language")
    if not task:
        return False
    return any(event.detail.get("item_id") == task["vocabulary_item_id"] for event in db.scalars(
        select(Activity).where(Activity.child_id == unit.child_id, Activity.kind == "vocabulary_exposure",
                               Activity.created >= int(now()) - 600)))


def record_review(db, unit, question, attempt, *, at=None):
    task = question.get("language")
    if not task or db.get(VocabularyReviewEvent, attempt.id):
        return
    # All callers already hold their unit lock. Serialize every review mutation
    # behind the same child lock, including creation of a previously unseen key.
    db.execute(update(Child).where(Child.id == unit.child_id).values(grade=Child.grade))
    item = db.get(VocabularyItem, task["vocabulary_item_id"])
    if not item or item.child_id != unit.child_id:
        return
    day = local_day(db.get(Child, unit.child_id), at)
    skill = "grammar:" + task["grammar_topic"] if task["skill"] == "grammar" and task.get("grammar_topic") else task["skill"]
    row = db.scalar(select(VocabularyReview).where(
        VocabularyReview.item_id == item.id, VocabularyReview.revision == task["vocabulary_revision"],
        VocabularyReview.direction == task["direction"], VocabularyReview.skill == skill).with_for_update())
    if not row:
        row = VocabularyReview(child_id=unit.child_id, item_id=item.id, revision=task["vocabulary_revision"],
                               direction=task["direction"], skill=skill, stage=0, due=day.isoformat())
        db.add(row)
        db.flush()
    independent = attempt.outcome == "correct" and not attempt.assisted
    possible_exposure = attempt.outcome == "correct" and bool((attempt.evaluation or {}).get("independence_uncertain"))
    advanced = independent and row.last_promoted != day.isoformat()
    if advanced:
        row.stage = min(len(INTERVALS), row.stage + 1)
        row.last_promoted = day.isoformat()
        row.due = (day + timedelta(days=INTERVALS[row.stage - 1])).isoformat()
    elif not independent and not possible_exposure:
        row.stage = 0
        row.due = (day + timedelta(days=1)).isoformat()
    if not possible_exposure:
        row.needs_clarification = attempt.outcome == "uncertain"
    db.add(VocabularyReviewEvent(attempt_id=attempt.id, review_id=row.id, day=day.isoformat(),
                                  advanced=advanced, stage=row.stage, due=row.due))


def states(db, item):
    rows = list(db.scalars(select(VocabularyReview).where(VocabularyReview.item_id == item.id,
                 VocabularyReview.revision == item.revision).order_by(VocabularyReview.direction, VocabularyReview.skill)))
    result = []
    for row in rows:
        attempts = list(db.execute(select(Attempt.outcome, Attempt.assisted, Attempt.evaluation).join(VocabularyReviewEvent).where(VocabularyReviewEvent.review_id == row.id)
                                  .order_by(Attempt.created, Attempt.id)))
        result.append({"direction": row.direction, "skill": row.skill, "stage": row.stage, "due": row.due,
             "needs_clarification": row.needs_clarification, "revision": row.revision}
              | {"attempts": len(attempts), "independent_correct": sum(a.outcome == "correct" and not a.assisted for a in attempts),
                 "assisted_correct": sum(a.outcome == "correct" and a.assisted and not (a.evaluation or {}).get("independence_uncertain") for a in attempts),
                 "incorrect": sum(a.outcome == "incorrect" for a in attempts),
                 "uncertain": sum(a.outcome == "uncertain" or (a.outcome == "correct" and bool((a.evaluation or {}).get("independence_uncertain"))) for a in attempts)})
    return result
