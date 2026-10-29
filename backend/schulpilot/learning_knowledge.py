"""Read-only, source-scoped learning memory derived from persisted evidence.

No model percentage, video click, draft or new copy of an answer is evidence.
The original Attempts and their source snapshots remain authoritative.
"""

from datetime import date, datetime
from zoneinfo import ZoneInfo

from sqlalchemy import func, or_, select

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
    from .source_lineage import learning_source

    texts = [learning_source(db, material)["content"] for material in sources]
    proposed = [goal for goal in goals_for(db, unit) if any(goal["source_excerpt"] in text for text in texts)]
    goals = [{**g, "origin": "validated_model_source_quote" if proposed else "reviewed_source_rule",
        "status": "source_checked_not_teacher_reviewed" if proposed else "checked"}
        for g in (proposed or source_goals(
            [{"content": text} for text in texts if text.strip()], unit.subject, unit.topic))]
    labels = {g["label"] for g in goals}
    for q in unit.questions:
        extra = q.get("controller_goal")
        if extra and extra["label"] not in labels:
            goals.append({"id": "controller_" + extra["key"], "label": extra["label"],
                "source_excerpt": extra["source_excerpt"], "origin": extra["origin"], "status": extra["status"]})
            labels.add(extra["label"])
    return goals


def evidence(db, unit, sources):
    from .coaching import CHECK_KINDS, conflicting_fraction_goal, fraction_task_goal, fraction_task_signature, normalized_prompt, planned_review
    from .learning_controller import source_state

    goals = catalogue(db, unit, sources)
    by_label = {g["label"]: g["id"] for g in goals}
    result = {g["id"]: {**g, "tasks": 0, "attempts": 0, "independent": 0, "supported": 0,
        "needs_practice": 0, "uncertain": 0, "reflection_tasks": 0, "historical_tasks": 0,
        "successful_check_dates": [], "evidence_refs": [], "last_independent_success": None,
        "last_observation": None, "last_assessment_observation": None, "last_difficulty": None} for g in goals}
    source_ids = [m.id for m in sources]
    related = select(UnitSource.unit_id).where(UnitSource.material_id.in_(source_ids))
    source_bound_ids = set(db.scalars(related))
    units = list(db.scalars(select(LearningUnit).where(LearningUnit.child_id == unit.child_id,
        LearningUnit.subject == unit.subject, or_(LearningUnit.id.in_(related), LearningUnit.material_id.in_(source_ids)))))
    attempts = list(db.scalars(select(Attempt).where(Attempt.unit_id.in_([u.id for u in units])).order_by(
        Attempt.created, func.coalesce(Attempt.evaluation["attempt_number"].as_integer(), 0), Attempt.id)))
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
        # Follow-up units keep the confirmed root goal IDs, even before they
        # have their own report. A missing new report must not hide evidence.
        old_goals = catalogue(db, old, sources)
        old_labels = {g["id"]: g["label"] for g in old_goals}
        review_map = {r["question_id"]: r["learning_goal_id"] for r in (report.report or {}).get("question_reviews", [])} if report else {}
        for q in old.questions:
            values = grouped.get((old.id, q["id"]), [])
            if not values:
                continue
            extra = q.get("controller_goal")
            mapped_label = old_labels.get(q.get("learning_goal_id") or review_map.get(q["id"]))
            if not extra and mapped_label and conflicting_fraction_goal(q["prompt"], mapped_label):
                # Preserve attempts and reports, but do not count an explicitly
                # mismatched old mapping as evidence for the operation goal.
                continue
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
            reflection = (last.evaluation or {}).get("method") == "open_learning_v1"
            independent = not reflection and len(values) == 1 and last.outcome == "correct" and not last.assisted
            state["tasks"] += 1
            state["attempts"] += len(values)
            state["last_observation"] = max(state["last_observation"] or 0, last.created)
            bucket = "reflection_tasks" if reflection else "independent" if independent else "supported" if last.outcome == "correct" else "needs_practice" if last.outcome == "incorrect" else "uncertain"
            state[bucket] += 1
            if not reflection:
                state["last_assessment_observation"] = max(state["last_assessment_observation"] or 0, last.created)
            if not reflection and not independent:
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
        stamp = state["last_assessment_observation"]
        anchor = datetime.fromtimestamp(stamp, zone).date() if stamp else None
        state["review_due"] = planned_review(child, unit.subject, days,
            difficult=not secure and bool(state["needs_practice"] or state["supported"]), anchor=anchor) if stamp else None
        state["evidence_total"] = len(state["evidence_refs"])
        state["evidence_refs"] = state["evidence_refs"][-12:]
    return list(result.values())


def buddy_context(db, child, *, unit=None, material_ids=(), limit=12):
    """Compact read-only facts after the caller's authentication checks.

    A source match is exact and revision-bound. Subject summaries are practice
    observations, never a claim that a whole subject has been mastered. Chat,
    media opens, grades, draft answers and private answer bodies are excluded.
    """
    from .learning_controller import source_state
    from .learning_progress import read_ledger, subject_evidence

    limit = max(1, min(int(limit), 12))
    if unit is not None and unit.child_id != child.id:
        raise ValueError("Knowledge context belongs to another child")
    requested = set(material_ids)
    if unit is None and requested:
        candidates = select(UnitSource.unit_id).where(UnitSource.material_id.in_(requested))
        # No guessed semantic association: only a stored source reference can
        # connect a page to an existing exercise and its learning goals.
        for candidate in db.scalars(select(LearningUnit).where(
            LearningUnit.child_id == child.id, LearningUnit.id.in_(candidates)
        ).order_by(LearningUnit.created.desc(), LearningUnit.id.desc())):
            _, valid, sources = source_state(db, candidate)
            if valid and all(source.child_id == child.id for source in sources) and requested <= {source.id for source in sources}:
                unit = candidate
                break
    goals, edges, signature = [], [], None
    valid = False
    if unit is not None:
        signature, valid, sources = source_state(db, unit)
        valid = valid and all(source.child_id == child.id for source in sources)
        if valid:
            rows = evidence(db, unit, sources)
            # Preserve the source catalogue order. Weak and strong evidence
            # both matter; do not select only errors or only successes.
            selected = rows[:limit]
            fields = ("id", "label", "origin", "status", "tasks", "attempts", "independent", "supported",
                "needs_practice", "uncertain", "reflection_tasks", "historical_tasks", "confidence", "successful_check_dates",
                "last_independent_success", "last_observation", "last_assessment_observation", "last_difficulty", "review_due",
                "evidence_total", "evidence_refs")
            goals = [{key: row.get(key) for key in fields} for row in selected]
            edges = prerequisites(goals)
    ledger = read_ledger(db, child.id)
    subjects = subject_evidence(ledger)[:limit]
    # No elapsed screen time or round count is transmitted as a competence
    # score. Only actual answered tasks and the latest observed outcomes.
    subject_fields = ("subject", "topic_count", "practiced_tasks", "attempts", "independent_tasks",
        "assisted_tasks", "needs_practice_tasks", "uncertain_tasks", "reflection_tasks", "last_activity")
    return {"version": 1, "scope": "confirmed_source_goals" if valid else "practice_summary_only",
        "source_valid": valid, "source_signature": signature, "goals": goals, "prerequisites": edges,
        "subjects": [{key: row.get(key) for key in subject_fields} for row in subjects],
        "notice": "Nur gespeicherte Übungsbelege. Ohne passende aktuelle Belege ist Vorwissen unbekannt. "
            "Unterstützte Lösungen, spätere Abrufprüfungen und unklare Bewertungen getrennt betrachten; "
            "Eigene Beiträge und Selbstreflexion sind keine geprüften Kompetenznachweise. "
            "Chat-Aussagen und geöffnete Videos beweisen kein Verständnis."}
