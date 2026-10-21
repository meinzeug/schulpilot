"""Read-only, source-scoped learning memory derived from persisted evidence.

No model percentage, video click, draft or new copy of an answer is evidence.
The original Attempts and their source snapshots remain authoritative.
"""

from datetime import date, datetime
from zoneinfo import ZoneInfo

from sqlalchemy import or_, select

from .db import Attempt, Child, LearningUnit, UnitCoaching, UnitSource
from .schemas import Preferences


def prerequisites(goals):
    labels = {g["label"]: g["id"] for g in goals}
    rules = [("Zähler und Nenner benennen", "Brüche erweitern"),
        ("Zähler und Nenner benennen", "Brüche kürzen"), ("Brüche erweitern", "Brüche addieren"),
        ("Gleichwertige Brüche erkennen", "Brüche addieren")]
    return [{"before": labels[a], "after": labels[b], "basis": "reviewed_teaching_rule"}
        for a, b in rules if a in labels and b in labels]


def catalogue(db, unit, sources):
    from .coaching import goals_for, source_goals

    proposed = goals_for(db, unit)
    goals = [{**g, "origin": "validated_model_source_quote" if proposed else "reviewed_source_rule",
        "status": "source_checked_not_teacher_reviewed" if proposed else "checked"}
        for g in (proposed or source_goals(
            [{"content": m.content or ""} for m in sources], unit.subject, unit.topic))]
    labels = {g["label"] for g in goals}
    for q in unit.questions:
        extra = q.get("controller_goal")
        if extra and extra["label"] not in labels:
            goals.append({"id": "controller_" + extra["key"], "label": extra["label"],
                "source_excerpt": extra["source_excerpt"], "origin": extra["origin"], "status": extra["status"]})
            labels.add(extra["label"])
    return goals


def evidence(db, unit, sources):
    from .coaching import CHECK_KINDS, fraction_task_goal, fraction_task_signature, normalized_prompt, planned_review
    from .learning_controller import source_state

    goals = catalogue(db, unit, sources)
    by_label = {g["label"]: g["id"] for g in goals}
    result = {g["id"]: {**g, "tasks": 0, "attempts": 0, "independent": 0, "supported": 0,
        "needs_practice": 0, "uncertain": 0, "historical_tasks": 0,
        "successful_check_dates": [], "evidence_refs": [], "last_independent_success": None,
        "last_observation": None, "last_difficulty": None} for g in goals}
    source_ids = [m.id for m in sources]
    related = select(UnitSource.unit_id).where(UnitSource.material_id.in_(source_ids))
    source_bound_ids = set(db.scalars(related))
    units = list(db.scalars(select(LearningUnit).where(LearningUnit.child_id == unit.child_id,
        LearningUnit.subject == unit.subject, or_(LearningUnit.id.in_(related), LearningUnit.material_id.in_(source_ids)))))
    attempts = list(db.scalars(select(Attempt).where(Attempt.unit_id.in_([u.id for u in units])).order_by(Attempt.created, Attempt.id)))
    reports = {r.unit_id: r for r in db.scalars(select(UnitCoaching).where(UnitCoaching.unit_id.in_([u.id for u in units])))}
    grouped = {}
    for attempt in attempts:
        grouped.setdefault((attempt.unit_id, attempt.question_id), []).append(attempt)
    child = db.get(Child, unit.child_id)
    zone = ZoneInfo(Preferences(**child.preferences).timezone)
    seen_checks = {}
    for old in sorted(units, key=lambda item: (item.created, item.id)):
        # A legacy material_id only identifies a page, not the revision used by
        # that old exercise. Keep its original practice, but never attribute it
        # to today's corrected source or invent current recall evidence.
        valid = old.id in source_bound_ids and source_state(db, old)[1]
        report = reports.get(old.id)
        old_goals = (report.report or {}).get("learning_goals", []) if report else []
        old_labels = {g["id"]: g["label"] for g in old_goals}
        review_map = {r["question_id"]: r["learning_goal_id"] for r in (report.report or {}).get("question_reviews", [])} if report else {}
        for q in old.questions:
            values = grouped.get((old.id, q["id"]), [])
            if not values:
                continue
            extra = q.get("controller_goal")
            goal = by_label.get(extra["label"]) if extra else by_label.get(old_labels.get(q.get("learning_goal_id") or review_map.get(q["id"])))
            if not goal and not extra:
                goal = fraction_task_goal(q["prompt"], goals)
            if goal not in result:
                continue
            state = result[goal]
            if not valid:
                state["historical_tasks"] += 1
                continue
            last = values[-1]
            independent = len(values) == 1 and last.outcome == "correct" and not last.assisted
            state["tasks"] += 1
            state["attempts"] += len(values)
            state["last_observation"] = max(state["last_observation"] or 0, last.created)
            bucket = "independent" if independent else "supported" if last.outcome == "correct" else "needs_practice" if last.outcome == "incorrect" else "uncertain"
            state[bucket] += 1
            if not independent:
                state["last_difficulty"] = max(state["last_difficulty"] or 0, last.created)
            state["evidence_refs"].extend("attempt:" + a.id for a in values)
            if independent:
                state["last_independent_success"] = max(state["last_independent_success"] or 0, last.created)
            if independent and old.round_kind in CHECK_KINDS:
                stamp = datetime.fromtimestamp(last.created, zone).date().isoformat()
                signature = fraction_task_signature(q["prompt"]) or normalized_prompt(q["prompt"])
                if signature not in seen_checks.setdefault(goal, set()):
                    seen_checks[goal].add(signature)
                    if stamp not in state["successful_check_dates"]:
                        state["successful_check_dates"].append(stamp)
    for state in result.values():
        days = sorted(state["successful_check_dates"])
        state["successful_check_dates"] = days
        difficulty_day = datetime.fromtimestamp(state["last_difficulty"], zone).date().isoformat() if state["last_difficulty"] else None
        recent_days = [day for day in days if difficulty_day is None or day > difficulty_day]
        secure = len(recent_days) >= 3 and (date.fromisoformat(recent_days[-1]) - date.fromisoformat(recent_days[0])).days >= 7
        state["confidence"] = "repeated_recall" if secure else "initial_evidence" if state["independent"] else "support_needed" if state["needs_practice"] or state["supported"] else "unverified"
        anchor = datetime.fromtimestamp(state["last_observation"], zone).date() if state["last_observation"] else None
        state["review_due"] = planned_review(child, unit.subject, days,
            difficult=not secure and bool(state["needs_practice"] or state["supported"]), anchor=anchor) if state["tasks"] else None
        state["evidence_total"] = len(state["evidence_refs"])
        state["evidence_refs"] = state["evidence_refs"][-12:]
    return list(result.values())
