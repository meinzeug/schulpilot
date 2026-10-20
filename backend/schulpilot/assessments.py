"""Explicit child rechecks, serialised with answers. No provider call or time."""

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from fastapi import HTTPException
from sqlalchemy import select, update

from .answer_evaluation import VERSION, evaluate
from .db import Attempt, AttemptAssessment, Child, LearningUnit, Mastery, UnitCoaching
from .schemas import Preferences


def rebuild_mastery(db, child, subject, topic):
    """Recalculate from original dated attempts; no invented practice day."""
    units = list(db.scalars(select(LearningUnit).where(
        LearningUnit.child_id == child.id, LearningUnit.subject == subject, LearningUnit.topic == topic,
        LearningUnit.status == "completed", LearningUnit.round_kind != "vocabulary"
    ).order_by(LearningUnit.completed, LearningUnit.id)))
    if not units:
        return
    mastery = db.scalar(select(Mastery).where(Mastery.child_id == child.id, Mastery.subject == subject, Mastery.topic == topic))
    if mastery is not None:
        mastery.independent = mastery.assisted = mastery.difficulties = mastery.uncertain_units = mastery.review_successes = 0
    previous_day = None
    zone = ZoneInfo(Preferences(**child.preferences).timezone)
    for unit in units:
        attempts = list(db.scalars(select(Attempt).where(Attempt.unit_id == unit.id).order_by(Attempt.created, Attempt.id)))
        final = {a.question_id: a for a in attempts}
        values = [final[q["id"]] for q in unit.questions if q["id"] in final]
        if not values or len(values) != len(unit.questions) or not unit.completed:
            continue
        if mastery is None:
            mastery = Mastery(child_id=child.id, subject=subject, topic=topic, independent=0,
                             assisted=0, difficulties=0, uncertain_units=0, review_successes=0)
            db.add(mastery)
        day = datetime.fromtimestamp(unit.completed, zone).date()
        if all(a.outcome == "correct" and not a.assisted for a in values):
            mastery.independent += 1
            if unit.review_of and previous_day is not None and previous_day < day:
                mastery.review_successes += 1
            interval = min(14, 2 ** min(mastery.review_successes, 3))
        elif all(a.outcome == "correct" for a in values):
            mastery.assisted += 1
            interval = 1
        elif any(a.outcome == "incorrect" for a in values):
            mastery.difficulties += 1
            interval = 1
        else:
            mastery.uncertain_units += 1
            interval = 1
        mastery.last_practiced = day.isoformat()
        mastery.next_review = (day + timedelta(days=interval)).isoformat()
        previous_day = day


def recheck(db, unit, question, actor_id):
    if question.get("language"):
        raise HTTPException(409, "Für Wörter gelten die bestätigten Bedeutungen und Varianten. Öffne die Wortkarte zur Klärung.")
    attempt = db.scalar(select(Attempt).where(Attempt.unit_id == unit.id, Attempt.question_id == question["id"])
                        .order_by(Attempt.created.desc(), Attempt.id.desc()).limit(1))
    if not attempt:
        raise HTTPException(409, "Bitte zuerst eine Antwort abgeben.")
    if db.scalar(select(AttemptAssessment.id).where(AttemptAssessment.attempt_id == attempt.id,
                                                  AttemptAssessment.rules_version == VERSION)):
        return attempt
    child = db.get(Child, unit.child_id)
    db.execute(update(Child).where(Child.id == child.id).values(grade=Child.grade))
    assessment = evaluate(question, attempt.answer)
    previous = attempt.evaluation or {}
    assessment.update({k: previous[k] for k in ("support_reasons", "attempt_number", "independent_attempt") if k in previous})
    assessment["independent_evidence"] = assessment["outcome"] == "correct" and not attempt.assisted
    audit = AttemptAssessment(attempt_id=attempt.id, rules_version=VERSION, previous_outcome=attempt.outcome,
                              outcome=assessment["outcome"], previous_evaluation=attempt.evaluation,
                              evaluation=assessment, actor_id=actor_id)
    db.add(audit)
    attempt.outcome, attempt.evaluation = assessment["outcome"], assessment
    db.flush()
    from .learning_controller import observe

    observe(db, unit, "assessment_corrected", "assessment:" + audit.id, ["attempt:" + attempt.id, "assessment:" + audit.id])
    rebuild_mastery(db, child, unit.subject, unit.topic)
    # A corrected verdict must not leave an obsolete parent alarm or repair
    # reason behind. Preserve already generated exercises and original dates;
    # this does not generate a follow-up or reserve another provider call.
    coach = db.get(UnitCoaching, unit.id)
    if coach and coach.status == "ready":
        from .coaching import plan_review

        before = {key: getattr(coach, key) for key in ("decision", "reason", "next_review")}
        planned = plan_review(db, unit)
        followup = db.get(LearningUnit, coach.next_unit_id) if coach.next_unit_id else None
        coach.decision = (followup.round_kind if followup and followup.round_kind in ("repair", "check")
                          else planned["next_action"])
        coach.reason = "Die Antwort wurde nachgeprüft. " + (
            "Die bereits vorbereitete nächste Runde bleibt erhalten." if followup else planned["reason"])
        mastery = db.scalar(select(Mastery).where(Mastery.child_id == child.id,
                            Mastery.subject == unit.subject, Mastery.topic == unit.topic))
        if mastery:
            coach.next_review = mastery.next_review
        if not followup and (coach.report or {}).get("learning_goals") and coach.decision in ("repair", "check"):
            coach.report = {**coach.report, "practice_deferred": True}
        audit.evaluation = {**assessment, "planning_before": before,
                            "planning_after": {key: getattr(coach, key) for key in before}}
    return attempt
