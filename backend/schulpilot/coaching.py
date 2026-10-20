"""Source-bound learning cycles: evidence decides; AI explains and prepares.

One automatic review per completed unit, one explicit retry, no provider loops.
An AI opinion never upgrades an uncertain answer to a mastery observation.
"""

import copy
import hashlib
import json
import logging
import re
import unicodedata
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, Header, HTTPException
from sqlalchemy import func, or_, select, update

from . import schemas as s
from .db import (
    DB,
    Activity,
    Assignment,
    Attempt,
    Child,
    Family,
    Job,
    LearningUnit,
    Material,
    ProviderConfig,
    UnitCoaching,
    UnitSource,
    Usage,
    get_db,
    now,
    uid,
)
from .model_routing import job_config
from .providers import ProviderError, config_for_function, external_allowed, request_provider, reserve, settle
from .security import child_user, rate_limit

router = APIRouter(tags=["Betreutes Lernen"])
log = logging.getLogger("schulpilot.coaching")
CHECK_KINDS = ("check", "spaced_review", "study_recall")
RECOMMENDED_DAILY_ROUNDS = 3
MAX_REQUESTS = 2


def observations(db, unit):
    attempts = list(db.scalars(select(Attempt).where(Attempt.unit_id == unit.id).order_by(Attempt.created, Attempt.id)))
    events = list(db.scalars(select(Activity).where(Activity.unit_id == unit.id)))
    return [
        {
            "question_id": q["id"],
            "learning_goal_id": q.get("learning_goal_id"),
            "type": q["type"],
            "prompt": q["prompt"],
            "expected_answer": q["answer"],
            "accepted": q["accepted"],
            "task_explanation": q["explanation"],
            "evidence_kind": (q.get("presentation") or {}).get("evidence_kind", "knowledge"),
            "attempts": [
                {"answer": a.answer, "outcome": a.outcome, "assisted": a.assisted}
                for a in attempts
                if a.question_id == q["id"]
            ],
            "deterministic_outcome": next(
                (a.outcome for a in reversed(attempts) if a.question_id == q["id"]), "uncertain"
            ),
            "hints_used": sum(e.kind == "hint" and e.detail.get("question_id") == q["id"] for e in events),
        }
        for q in unit.questions
    ]


def independently_correct(db, unit):
    if unit.status != "completed":
        return False
    items = observations(db, unit)
    helped = db.scalar(
        select(Activity.id).where(
            Activity.unit_id == unit.id,
            Activity.kind == "explanation",
            Activity.created <= unit.completed,
        )
    )
    difficulty_feedback = any(
        e.detail.get("kind") in ("too_hard", "unclear")
        for e in db.scalars(
            select(Activity).where(
                Activity.unit_id == unit.id,
                Activity.kind == "feedback",
                Activity.created <= unit.completed,
            )
        )
    )
    return (
        bool(items)
        and not helped
        and not difficulty_feedback
        and all(
            len(q["attempts"]) == 1
            and q["attempts"][0]["outcome"] == "correct"
            and not q["attempts"][0]["assisted"]
            and not q["hints_used"]
            for q in items
        )
    )


def root_and_units(db, unit):
    root = db.get(LearningUnit, unit.learning_root_id) if unit.learning_root_id else unit
    if not root or root.child_id != unit.child_id:
        root = unit
    units = list(
        db.scalars(
            select(LearningUnit).where(
                LearningUnit.child_id == unit.child_id,
                or_(LearningUnit.id == root.id, LearningUnit.learning_root_id == root.id),
            )
        )
    )
    by_id = {u.id: u for u in units}

    def depth(value):
        seen = {value.id}
        parent_id = value.followup_of or value.review_of
        while parent_id in by_id and parent_id not in seen:
            seen.add(parent_id)
            parent = by_id[parent_id]
            parent_id = parent.followup_of or parent.review_of
        return len(seen)

    answered_at = dict(
        db.execute(
            select(Attempt.unit_id, func.max(Attempt.created))
            .where(Attempt.unit_id.in_(by_id))
            .group_by(Attempt.unit_id)
        ).all()
    )
    units.sort(key=lambda u: (u.completed or 2**62, answered_at.get(u.id, 0), depth(u), u.created, u.id))
    return root, units


def planned_review(child, subject, successful_dates, *, difficult=False, anchor=None):
    from .learning import local_day

    prefs = s.Preferences(**child.preferences)
    intervals = (1, 3, 7, 14, 30)
    interval = 1 if difficult else intervals[min(max(0, len(successful_dates) - 1), len(intervals) - 1)]
    target = (anchor or local_day(child)) + timedelta(days=interval)
    if prefs.pause_until:
        target = max(target, prefs.pause_until + timedelta(days=1))
    for offset in range(35):
        candidate = target + timedelta(days=offset)
        if candidate.weekday() in prefs.weekdays and (
            not prefs.subject_days.get(subject) or candidate.weekday() in prefs.subject_days[subject]
        ):
            return candidate.isoformat()
    # No compatible learning day: no invented date. Parents see this conflict.
    return None


def goal_catalog(db, unit):
    root, chain = root_and_units(db, unit)
    item = db.get(UnitCoaching, root.id)
    if item and (item.report or {}).get("learning_goals"):
        return item
    for old in chain:
        item = db.get(UnitCoaching, old.id)
        if item and (item.report or {}).get("learning_goals"):
            return item
    return None


def goals_for(db, unit):
    item = goal_catalog(db, unit)
    return item.report["learning_goals"] if item else []


def source_goals(materials, subject, topic):
    """Recognizable fraction procedures have concrete, quoted targets.

    Other subjects use the validated AI proposal. This is not an assertion
    that a photo contains the whole curriculum or every possible skill.
    """
    content = "\n".join(m["content"] for m in materials)
    if subject.casefold() not in ("mathematik", "mathe") or not re.search(
        r"br[uü]ch|nenner|z[aä]hler", (topic + " " + content).casefold()
    ):
        return []
    result = []
    for pattern, label in (
        (r"nenner\s*(?:sagt|gibt|steht|:)|zähler\s*(?:zählt|steht|:)", "Zähler und Nenner benennen"),
        (r"addier|addition", "Brüche addieren"),
        (r"kürz", "Brüche kürzen"),
        (r"erweit", "Brüche erweitern"),
        (r"gleichwert", "Gleichwertige Brüche erkennen"),
    ):
        for material in materials:
            match = re.search(pattern, material["content"], re.I)
            if match:
                start = max(
                    material["content"].rfind("\n", 0, match.start()) + 1,
                    material["content"].rfind(".", 0, match.start()) + 1,
                )
                start = max(start, match.start() - 100)
                excerpt = material["content"][start : start + 350].strip()
                result.append({"id": f"g{len(result) + 1}", "label": label, "source_excerpt": excerpt})
                break
    return result


def goal_states(db, unit):
    root, chain = root_and_units(db, unit)
    goals = goals_for(db, root)
    dates = {g["id"]: [] for g in goals}
    practice = {g["id"]: {"practiced_tasks": 0, "independent_tasks": 0, "assisted_tasks": 0,
                           "needs_practice_tasks": 0, "uncertain_tasks": 0, "attempts": 0} for g in goals}
    child = db.get(Child, unit.child_id)
    zone = ZoneInfo(s.Preferences(**child.preferences).timezone)
    for old in chain:
        old_report = db.get(UnitCoaching, old.id)
        mapping = (
            {q["question_id"]: q["learning_goal_id"] for q in (old_report.report or {}).get("question_reviews", [])}
            if old_report
            else {}
        )
        by_id = {q["question_id"]: q for q in observations(db, old)}
        groups = {}
        for question in old.questions:
            goal_id = question.get("learning_goal_id") or mapping.get(question["id"])
            if goal_id in dates:
                groups.setdefault(goal_id, []).append(by_id[question["id"]])
        for goal_id, items in groups.items():
            for item in items:
                attempts = item["attempts"]
                if not attempts:
                    continue
                count = practice[goal_id]
                count["practiced_tasks"] += 1
                count["attempts"] += len(attempts)
                last = attempts[-1]
                key = ("independent_tasks" if len(attempts) == 1 and not last["assisted"] else "assisted_tasks") if last["outcome"] == "correct" else "needs_practice_tasks" if last["outcome"] == "incorrect" else "uncertain_tasks"
                count[key] += 1
        if old.status != "completed":
            continue
        helped = bool(
            db.scalar(
                select(Activity.id).where(
                    Activity.unit_id == old.id, Activity.kind == "explanation", Activity.created <= old.completed
                )
            )
        )
        hard = any(
            e.detail.get("kind") in ("too_hard", "unclear")
            for e in db.scalars(
                select(Activity).where(
                    Activity.unit_id == old.id, Activity.kind == "feedback", Activity.created <= old.completed
                )
            )
        )
        for goal_id, items in groups.items():
            clean = (
                not helped
                and not hard
                and all(
                    len(q["attempts"]) == 1
                    and q["deterministic_outcome"] == "correct"
                    and not q["attempts"][0]["assisted"]
                    and not q["hints_used"]
                    for q in items
                )
            )
            if not clean:
                dates[goal_id] = []
            elif old.round_kind in CHECK_KINDS:
                stamp = datetime.fromtimestamp(old.completed, zone).date().isoformat()
                if stamp not in dates[goal_id]:
                    dates[goal_id].append(stamp)
    return [
        {
            **g,
            "practice": practice[g["id"]],
            "successful_check_dates": dates[g["id"]],
            "successful_check_days": len(dates[g["id"]]),
            "secure_observation": len(dates[g["id"]]) >= 3
            and (date.fromisoformat(dates[g["id"]][-1]) - date.fromisoformat(dates[g["id"]][0])).days >= 7,
        }
        for g in goals
    ]


def focus_ids(db, unit, action):
    states = goal_states(db, unit)
    if action == "repair":
        report = db.get(UnitCoaching, unit.id)
        reviewed = {
            r["question_id"]: r["learning_goal_id"]
            for r in (report.report if report else {}).get("question_reviews", [])
        }
        by_question = {q["id"]: q.get("learning_goal_id") or reviewed.get(q["id"]) for q in unit.questions}
        weak = {
            by_question[q["question_id"]]
            for q in observations(db, unit)
            if q["deterministic_outcome"] != "correct" or q["hints_used"] or any(a["assisted"] for a in q["attempts"])
        }
        states.sort(key=lambda g: (g["id"] not in weak, g["successful_check_days"], g["id"]))
        selected = [g["id"] for g in states if g["id"] in weak]
        if selected:
            return selected[:2]
    states = [g for g in states if not g["secure_observation"]] or states
    states.sort(key=lambda g: (g["successful_check_days"], g["successful_check_dates"][-1:] or [""], g["id"]))
    return [g["id"] for g in states[:2]]


def persistent_errors(db, units):
    done = [u for u in units if u.status == "completed"]
    return len(done) >= 2 and all(
        any(q["deterministic_outcome"] == "incorrect" and len(q["attempts"]) >= 2 for q in observations(db, u))
        for u in done[-2:]
    )


def open_assessment_only(db, unit):
    outcomes = [q["deterministic_outcome"] for q in observations(db, unit)]
    return "uncertain" in outcomes and "incorrect" not in outcomes


def progress(db, unit, *, ledger=None):
    from .learning_progress import read_ledger, topic_evidence, totals

    root, units = root_and_units(db, unit)
    if ledger is None:
        ledger = read_ledger(db, unit.child_id)
    chain_ids = {u.id for u in units}
    child = db.get(Child, unit.child_id)
    prefs = s.Preferences(**child.preferences)
    completed = [u for u in units if u.status == "completed"]
    clean = {u.id: independently_correct(db, u) for u in completed}
    goals = goal_states(db, unit)
    dates = sorted({d for goal in goals for d in goal["successful_check_dates"]})
    secure = bool(goals) and all(goal["secure_observation"] for goal in goals)
    latest = completed[-1] if completed else root
    coaching = db.get(UnitCoaching, latest.id)
    pending = next((u for u in units if u.status != "completed"), None)
    if pending:
        state = "needs_practice" if pending.round_kind == "repair" else "checking"
    elif completed and not clean[latest.id]:
        state = "needs_practice"
    else:
        state = "secure" if secure else "consolidating" if dates else "learning"
    if completed and open_assessment_only(db, latest):
        state = "assessment_open"
    try:
        catalog = goal_catalog(db, root)
        context(db, db.get(LearningUnit, catalog.unit_id) if catalog else root)
        sources_current = True
    except ProviderError:
        sources_current = False
        state = "source_changed"
    from .subject_content import open_learning_unit

    open_contribution = open_learning_unit(unit)
    if open_contribution:
        state, secure, dates = "reflection", False, []
    labels = {
        "reflection": "Eigene Gedanken festgehalten",
        "learning": "Gelernt – jetzt selbstständig prüfen",
        "checking": "Eine neue Abrufprobe steht bereit",
        "needs_practice": "Gezielt weiter üben",
        "assessment_open": "Antwortprüfung offen – mit der Lernhilfe klären",
        "consolidating": "Wissen festigen und später wieder abrufen",
        "secure": "Im geprüften Stoff gefestigt",
        "source_changed": "Lernstoff geändert oder entfernt – gemeinsam neu prüfen",
    }
    return {
        "evidence_kind": "reflection" if open_contribution else "knowledge",
        "root_unit_id": root.id,
        "latest_unit_id": latest.id,
        "subject": root.subject,
        "topic": root.topic,
        "state": state,
        "label": labels[state],
        "successful_check_dates": dates,
        "successful_check_days": min((g["successful_check_days"] for g in goals), default=0),
        "learning_goals": goals,
        "required_check_days": 3,
        "minimum_span_days": 7,
        "secure_observation": secure and state == "secure",
        "completed_rounds": len(completed),
        "practice": totals([row for row in ledger if row["id"] in chain_ids]),
        "topic_practice": topic_evidence(ledger, root.subject, root.topic),
        "next_unit_id": pending.id if pending else None,
        "next_review": None
        if not sources_current
        else coaching.next_review
        if coaching
        else planned_review(
            child,
            root.subject,
            min(goals, key=lambda g: g["successful_check_days"], default={"successful_check_dates": []})[
                "successful_check_dates"
            ],
            anchor=datetime.fromtimestamp(latest.completed, ZoneInfo(prefs.timezone)).date()
            if latest.completed
            else None,
        ),
        "needs_parent": not sources_current or bool(coaching and coaching.decision == "parent_help" and persistent_errors(db, units)),
        "needs_source_review": not sources_current,
        "assessment_open": state == "assessment_open",
        "notice": "Gilt für den bestätigten Stoff dieser Lernfolge. Keine Garantie für den gesamten Unterricht; spätere Wiederholungen bleiben wichtig.",
    }


def paths(db, child_id, *, ledger=None):
    from .learning_progress import read_ledger

    roots = list(
        db.scalars(
            select(LearningUnit)
            .where(
                LearningUnit.child_id == child_id,
                LearningUnit.learning_root_id.is_(None),
                LearningUnit.followup_of.is_(None),
                LearningUnit.round_kind != "vocabulary",
                LearningUnit.status == "completed",
            )
            .order_by(LearningUnit.created.desc())
            .limit(100)
        )
    )
    if ledger is None:
        ledger = read_ledger(db, child_id)
    return [progress(db, root, ledger=ledger) for root in roots]


def plan_review(db, unit):
    from .learning import local_day

    child = db.get(Child, unit.child_id)
    prefs = s.Preferences(**child.preferences)
    today = local_day(child)
    root, units = root_and_units(db, unit)
    evidence = progress(db, unit)
    clean = independently_correct(db, unit)
    done = [u for u in units if u.status == "completed"]
    recent_hard = persistent_errors(db, done)
    action = "repair" if not clean else "spaced" if unit.round_kind in CHECK_KINDS else "check"
    if action == "spaced" and (
        not evidence["learning_goals"]
        or any(today.isoformat() not in goal["successful_check_dates"] for goal in evidence["learning_goals"])
    ):
        action = "check"
    reason = {
        "repair": "Wir üben die Schritte, bei denen Fehler, Hilfen oder offene Bewertungen gespeichert sind.",
        "check": "Eine neue kurze Abrufprobe zeigt, was du schon ohne Hilfe anwenden kannst.",
        "spaced": "Diese Abrufprobe ist selbstständig gelungen. Wir prüfen den Stoff an einem späteren Tag erneut.",
    }[action]
    if open_assessment_only(db, unit):
        reason = "Die Prüfung einzelner Antworten ist offen. Das ist kein nachgewiesener Fehler. Die Lernhilfe kann die Antwort klären; eine neue kurze Runde bietet einen weiteren Versuch ohne die vorige Vorlage."
    from .daily_planner import period_starts

    start, _ = period_starts(today, prefs.timezone)
    rounds_today = sum(u.created >= start for u in units)
    if recent_hard:
        action, reason = (
            "parent_help",
            "In zwei Runden blieb nach weiteren Versuchen ein Fehler offen. Die App bietet eine andere Erklärung an; bei Bedarf hilft ein gemeinsamer Blick auf diesen Schritt.",
        )
    elif action in ("repair", "check") and rounds_today >= RECOMMENDED_DAILY_ROUNDS:
        reason += " Eine kurze Pause kann guttun. Danach geht es mit dem nächsten Lernschritt weiter."
    return {
        "next_action": action,
        "reason": reason,
        "next_review": planned_review(
            child,
            root.subject,
            min(
                evidence["learning_goals"],
                key=lambda g: g["successful_check_days"],
                default={"successful_check_dates": []},
            )["successful_check_dates"],
            difficult=not clean,
        ),
    }


def continuation_block(db, unit, child, *, check_sources=True):
    """Protect source/explicit release dates, never recommended learning time."""
    from .learning import local_day

    today = local_day(child).isoformat()
    if unit.not_before and unit.not_before > today:
        return f"Diese spätere Abrufprobe beginnt frühestens am {unit.not_before}."
    goal = db.get(Assignment, unit.assignment_id) if unit.assignment_id else None
    if goal and goal.scheduled_for and goal.scheduled_for > today:
        return f"Dieser Lernauftrag beginnt am {goal.scheduled_for}. Deine Eltern können ihn neu planen."
    # Validate all copied source revisions again when a prepared round starts.
    if check_sources:
        try:
            context(db, unit)
        except ProviderError as error:
            return str(error)
    return None


def context(db, unit):
    child = db.get(Child, unit.child_id)
    source_rows = list(
        db.scalars(select(UnitSource).where(UnitSource.unit_id == unit.id).order_by(UnitSource.material_id))
    )
    previous_coach = db.get(UnitCoaching, unit.id)
    if not source_rows and previous_coach and previous_coach.report:
        source_rows = [
            UnitSource(material_id=m["id"], revision=m["revision"])
            for m in previous_coach.report.get("source_revisions", [])
        ]
    if not source_rows and unit.material_id:
        material = db.get(Material, unit.material_id)
        if material:
            source_rows = [UnitSource(material_id=material.id, revision=material.revision)]
    materials = []
    for source in source_rows:
        material = db.get(Material, source.material_id)
        if (
            not material
            or material.child_id != unit.child_id
            or not material.confirmed
            or material.revision != source.revision
        ):
            raise ProviderError("Der bestätigte Stoff wurde geändert oder gelöscht. Bitte zuerst gemeinsam prüfen.")
        materials.append(
            {
                "id": material.id,
                "revision": material.revision,
                "subject": material.subject,
                "topic": material.topic,
                "content": material.content,
                "uncertainties": material.uncertainties,
            }
        )
    assignment = db.get(Assignment, unit.assignment_id) if unit.assignment_id else None
    if assignment and unit.goal_revision is not None and assignment.revision != unit.goal_revision:
        raise ProviderError(
            "Der verbindliche Elternauftrag wurde geändert. Bitte zuerst den aktuellen Lernplan gemeinsam prüfen."
        )
    if not materials and not assignment:
        raise ProviderError("Der bestätigte Stoff oder Elternauftrag ist nicht mehr verfügbar.")
    if sum(len(m["content"]) for m in materials) > 60_000:
        raise ProviderError("Die Quellen sind für eine gemeinsame Lernbegleitung zu umfangreich.")
    goal = (
        {
            "subject": assignment.subject,
            "topic": assignment.topic,
            "note": assignment.note,
            "revision": assignment.revision,
        }
        if assignment
        else None
    )
    completed_questions = observations(db, unit)
    learning_goals = goals_for(db, unit)
    if not learning_goals:
        candidates = source_goals(materials, unit.subject, unit.topic)
        # Complete the audited mixed fraction/triangle catalogue only when the
        # general area rule is literally present. Never attach a fraction goal
        # to a geometry question merely because it shares the same unit.
        if unit.subject.casefold() in ("mathematik", "mathe") and len(candidates) < 4:
            for material in materials:
                text = material["content"]
                match = re.search(r"(?i)(?:A|fläche)\s*=\s*(?:g\s*[*·×]\s*h|h\s*[*·×]\s*g)\s*/\s*2", text)
                if match and "dreieck" in text.casefold():
                    start = max(0, text.rfind("\n", 0, match.start()) + 1)
                    if re.search(r"nicht|falsch|fehler", text[start:match.start()], re.I):
                        continue
                    candidates.append({"id":f"g{len(candidates)+1}", "label":"Fläche eines Dreiecks berechnen", "source_excerpt":text[start:start+350]})
                    break
        candidate_ids = {goal["id"] for goal in candidates}
        # A fraction-only catalogue must never prescribe the entire mixed
        # fraction/geometry round. Let the same reserved review propose quoted
        # goals for the complete source instead; stored catalogues remain binding.
        if candidates and all(fraction_task_goal(q["prompt"], candidates) in candidate_ids for q in unit.questions):
            learning_goals = candidates
            # Assignment is based on the confirmed rule and the stored prompt,
            # restored by question ID in the adapter; no model-selected IDs.
            for observation, question in zip(completed_questions, unit.questions, strict=True):
                if observation["learning_goal_id"] is None:
                    observation["learning_goal_id"] = fraction_task_goal(question["prompt"], candidates)
    snapshot = {
        "materials": materials,
        "goal": goal,
        "preferences": child.preferences,
        "questions": unit.questions,
        "observations": completed_questions,
        "learning_goals": learning_goals,
    }
    signature = hashlib.sha256(json.dumps(snapshot, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
    _, chain = root_and_units(db, unit)
    payload = {
        "grade": child.grade,
        "required_subject": unit.subject,
        "required_topic": unit.topic,
        "materials": [{k: m[k] for k in ("subject", "topic", "content", "uncertainties")} for m in materials],
        "goal": goal,
        "completed_questions": completed_questions,
        "previous_prompts": [q["prompt"] for previous in chain for q in previous.questions][-80:],
        "learning_goals": snapshot["learning_goals"],
    }
    return signature, payload, [{"id": m["id"], "revision": m["revision"]} for m in materials]


def report_projection(db, unit, stored):
    """Every screen uses saved verdicts; model prose cannot claim bookkeeping."""
    if not stored:
        return stored
    report = copy.deepcopy(stored)
    def factual_prose(value):
        sentences = re.split(r"(?<=[.!?])\s+", value)
        return " ".join(s for s in sentences if not re.search(
            r"gespeichert|verbucht|bewertet|mit\s+hilfe|selbstständig|alleine?\s+gelöst|hinweis\w*\s+(?:genutzt|verwendet)", s, re.I))

    for field in ("strengths", "practice_focus"):
        if isinstance(report.get(field), list):
            report[field] = [text for value in report[field] if (text := factual_prose(value))]
    if isinstance(report.get("explanation"), str):
        report["explanation"] = factual_prose(report["explanation"])
    items = {q["question_id"]: q for q in observations(db, unit)}
    independent = supported = incorrect = uncertain = 0
    for q in items.values():
        attempts = q["attempts"]
        if not attempts:
            continue
        if q["deterministic_outcome"] == "correct":
            if len(attempts) == 1 and not attempts[-1]["assisted"]:
                independent += 1
            else:
                supported += 1
        elif q["deterministic_outcome"] == "incorrect":
            incorrect += 1
        else:
            uncertain += 1
    report["summary"] = (f"{independent} beim ersten Versuch selbstständig richtig, "
                         f"{supported} mit Unterstützung oder erneut richtig, {incorrect} weiter üben, "
                         f"{uncertain} Bewertungen offen. Eine offene Prüfung ist kein nachgewiesener Fehler.")
    for review in report.get("question_reviews", []):
        observed = items.get(review["question_id"])
        if observed is None:
            continue
        known = observed["deterministic_outcome"]
        review["saved_outcome"] = known
        review["hints_used"] = observed["hints_used"]
        if known != "uncertain":
            if review.get("outcome") != known:
                review["feedback"] = observed["task_explanation"]
            review["outcome"], review["assessment_kind"] = known, "fixed_result"
        # Keep explanations, but discard model-generated claims about state,
        # help or persistence. These are supplied from our own saved events.
        prose = factual_prose(review.get("feedback", ""))
        label = {"correct": "Gespeichert: richtig.", "incorrect": "Gespeichert: noch nicht richtig.",
                 "uncertain": "Die Prüfung ist offen; eine KI-Einschätzung ändert sie nicht."}[known]
        support = f" {observed['hints_used']} Hinweise aufgerufen." if observed["hints_used"] else " Kein Aufgabenhinweis aufgerufen."
        review["feedback"] = label + support + (" " + prose if prose else "")
    return report


def view(db, unit):
    from .subject_content import open_learning_unit

    if open_learning_unit(unit):
        return {"status":"local", "local_only":True, "can_retry":False,
                "reason":"Eigene Gedanken oder Beschreibungen sind gespeichert. Daraus wird keine gemessene Fähigkeit abgeleitet."}
    item = db.get(UnitCoaching, unit.id)
    if not item:
        return None
    status, reason = item.status, item.reason
    job = db.get(Job, item.job_id) if item.job_id else None
    if status == "pending" and job and job.status == "failed":
        status, reason = "failed", job.error
    elif status == "pending" and not job:
        status, reason = (
            "failed",
            "Die frühere Verarbeitung ist nicht mehr verfügbar. Deine Antworten bleiben gespeichert.",
        )
    decision = item.decision
    if status == "ready" and decision == "parent_help":
        _, units = root_and_units(db, unit)
        if not persistent_errors(db, units):
            decision = "check" if independently_correct(db, unit) else "repair"
            reason = "Die App bietet zunächst eine passende Erklärung und einen weiteren Lernschritt. Eine offene Bewertung ist kein nachgewiesener Fehler."
    practice_job = db.scalar(
        select(Job)
        .where(
            Job.child_id == unit.child_id,
            Job.kind == "coach_practice",
            Job.payload["unit_id"].as_string() == unit.id,
        )
        .order_by(Job.payload["practice_number"].as_integer().desc().nullslast(), Job.created.desc(), Job.id.desc())
        .limit(1)
    )
    return {
        "status": status,
        "decision": decision,
        "reason": reason,
        "report": report_projection(db, unit, item.report),
        "next_unit_id": item.next_unit_id,
        "next_review": item.next_review,
        "request_count": item.request_count,
        "can_retry": status in ("blocked", "failed") and item.request_count < MAX_REQUESTS,
        "provider": item.provider,
        "model": item.model,
        "practice_deferred": bool((item.report or {}).get("practice_deferred") and not item.next_unit_id),
        "practice_job_id": practice_job.id if practice_job else None,
        "practice_status": practice_job.status if practice_job else None,
        "practice_error": practice_job.error if practice_job else None,
        "assessment_notice": "KI-Einschätzungen ergänzen die feste Prüfung. Unklare Antworten zählen dadurch nicht automatisch als selbstständig richtig gelöst.",
    }


def normalized_prompt(value):
    return " ".join(unicodedata.normalize("NFKC", value).casefold().split()).rstrip(".?!")


def fraction_task_signature(prompt):
    lower = unicodedata.normalize("NFKC", prompt).casefold()
    parts = re.findall(r"\b(\d{1,4})\s*/\s*([1-9]\d{0,3})\b", lower)
    if not parts:
        return None
    if len(parts) == 2 and "+" in lower:
        return "add", tuple(sorted(parts))
    # Read the requested operation before supporting instructions. In
    # particular, "Erweitere ... Kürze das Ergebnis nicht" is expansion.
    operation = re.search(r"\b(?:kürz\w*|gekürz\w*|einfachste form|erweit\w*)", lower)
    if operation:
        if operation[0].startswith("erweit"):
            factor = re.search(r"mit\s+(?:(?:dem\s+)?faktor\s+)?([1-9]\d{0,3})\b", lower)
            return ("expand", parts[0], factor[1]) if factor else None
        return "reduce", parts[0]
    if "zähler" in lower or "nenner" in lower:
        return "component", "zähler" if "zähler" in lower else "nenner", parts[0]
    return None


def fraction_task_goal(prompt, goals):
    from .subject_content import legacy_presentation

    geometry = next((g["id"] for g in goals if g["label"] == "Fläche eines Dreiecks berechnen"), None)
    if geometry and re.search(r"fläch", prompt, re.I) and legacy_presentation({"prompt":prompt}):
        return geometry
    if re.search(r"dieselbe Menge|gleichwertig", prompt, re.I):
        return next((g["id"] for g in goals if g["label"] == "Gleichwertige Brüche erkennen"), None)
    labels = ("Zähler und Nenner benennen", "Brüche addieren", "Brüche kürzen", "Brüche erweitern")
    known = {g["label"]: g["id"] for g in goals if g["label"] in labels}
    if not known:
        return None
    lower = prompt.casefold()
    label = None
    signature = fraction_task_signature(prompt)
    if signature:
        label = labels[{"component": 0, "add": 1, "reduce": 2, "expand": 3}[signature[0]]]
    elif "kürz" in lower or "einfachste form" in lower:
        label = labels[2]
    elif "erweit" in lower:
        label = labels[3]
    elif re.search(r"\d+\s*/\s*\d+\s*\+\s*\d+\s*/\s*\d+", lower) or "addier" in lower:
        label = labels[1]
    elif any(word in lower for word in ("zähler", "nenner", "bruchstrich", "begriffe")):
        label = labels[0]
    return known.get(label, "outside_confirmed_goals") if label else None


def validate_new_round(db, previous_unit, data, *, desired_ids=None):
    if (
        data["subject"].casefold() != previous_unit.subject.casefold()
        or data["topic"].casefold() != previous_unit.topic.casefold()
    ):
        raise ProviderError("Die neue Lernprobe weicht vom bestätigten Lernziel ab.")
    _, chain = root_and_units(db, previous_unit)
    previous = {normalized_prompt(q["prompt"]) for old in chain for q in old.questions}
    previous_arithmetic = {fraction_task_signature(q["prompt"]) for old in chain for q in old.questions} - {None}
    if any(
        normalized_prompt(q["prompt"]) in previous or fraction_task_signature(q["prompt"]) in previous_arithmetic
        for q in data["questions"]
    ):
        raise ProviderError(
            "Die neue Runde wiederholt eine bereits gestellte Aufgabe. Keine zusätzliche Lernprobe wurde behauptet."
        )
    goals = goals_for(db, previous_unit)
    if goals:
        desired = set(desired_ids if desired_ids is not None else focus_ids(db, previous_unit, "check"))
        if {q.get("learning_goal_id") for q in data["questions"]} != desired:
            raise ProviderError("Die neue Runde deckt die angeforderten Lernziele nicht ab.")
        for question in data["questions"]:
            goal_id = fraction_task_goal(question["prompt"], goals)
            if goal_id and goal_id != question.get("learning_goal_id"):
                raise ProviderError(
                    "Eine Bruchaufgabe ist dem falschen oder einem nicht bestätigten Lernziel zugeordnet."
                )


def save_report(
    db, unit, item, data, sources, *, synthetic=False, defer_practice=False, practice_identity=None, record_review=True
):
    from .learning import record

    data = s.CoachingOutput.model_validate(data).model_dump()
    goals = data["learning_goals"]
    old_goals = goals_for(db, unit)
    prescribed_goals = old_goals or context(db, unit)[1]["learning_goals"]
    by_goal = {g["id"]: g for g in goals}
    if len(by_goal) != len(goals) or len({normalized_prompt(g["label"]) for g in goals}) != len(goals):
        raise ProviderError("Die Lernziele der KI-Auswertung sind nicht eindeutig.")
    if prescribed_goals:
        if by_goal != {g["id"]: g for g in prescribed_goals}:
            raise ProviderError("Die KI hat gespeicherte Lernziele verändert. Die Ausgabe wurde verworfen.")
        data["learning_goals"] = prescribed_goals
    else:
        source_payload = context(db, unit)[1]
        texts = [m["content"] for m in source_payload["materials"]]
        if source_payload["goal"]:
            texts.extend(str(v) for k, v in source_payload["goal"].items() if k != "revision")
        if any(
            not any(normalized_prompt(g["source_excerpt"]) in normalized_prompt(text) for text in texts) for g in goals
        ):
            raise ProviderError("Ein vorgeschlagenes Lernziel hat keinen wörtlichen Beleg im bestätigten Stoff.")
        if any(re.search(r"\b(?:verstehen|lernen|beherrschen|wissen)\s*$", goal["label"], re.I) for goal in goals):
            raise ProviderError("Ein Lernziel ist zu allgemein. Benötigt wird eine konkret prüfbare Fähigkeit.")
    observations_by_id = {q["question_id"]: q for q in observations(db, unit)}
    reviews = data["question_reviews"]
    if len(reviews) != len(observations_by_id) or {r["question_id"] for r in reviews} != set(observations_by_id):
        raise ProviderError("Die KI-Rückmeldung ist nicht vollständig den beantworteten Aufgaben zugeordnet.")
    for review in reviews:
        original = observations_by_id[review["question_id"]]
        assigned_goal = original["learning_goal_id"]
        if assigned_goal is not None:
            # These assignments were checked when the questions were created.
            # Keep them authoritative even for legacy/mixed provider schemas.
            if assigned_goal not in by_goal:
                raise ProviderError("Eine gespeicherte Aufgabe verweist auf ein unbekanntes Lernziel.")
            review["learning_goal_id"] = assigned_goal
        if review["learning_goal_id"] not in by_goal:
            raise ProviderError("Die Aufgabenrückmeldung verweist auf ein unbekanntes Lernziel.")
        goal_id = fraction_task_goal(original["prompt"], goals) if assigned_goal is None else None
        if goal_id and goal_id != review["learning_goal_id"]:
            raise ProviderError("Die Aufgabenrückmeldung passt nicht zum erkennbaren Lernziel.")
        known = observations_by_id[review["question_id"]]["deterministic_outcome"]
        if known != "uncertain" and known != review["outcome"]:
            raise ProviderError(
                "Die KI-Rückmeldung widerspricht einer fest prüfbaren Antwort. Sie wurde nicht übernommen."
            )
        review["assessment_kind"] = "ai_opinion" if known == "uncertain" and not synthetic else "fixed_result"
        # A report about an old answer must not substitute numbers from a new
        # exercise. New worked examples belong in the separate explanation.
        numbers = set(re.findall(r"\d+", json.dumps(original, ensure_ascii=False)))
        if not set(re.findall(r"\d+", review["feedback"])).issubset(numbers):
            raise ProviderError("Die Rückmeldung nennt Zahlen, die nicht zur gespeicherten Aufgabe gehören.")
    next_unit = data.pop("next_unit")
    deferred = defer_practice and next_unit is None and item.decision in ("repair", "check")
    wants_next = item.decision in ("repair", "check") and not deferred
    if wants_next != bool(next_unit):
        raise ProviderError("Die Anschlussübungen passen nicht zur gespeicherten Lernplanung.")
    if next_unit:
        if (
            next_unit["subject"].casefold() != unit.subject.casefold()
            or next_unit["topic"].casefold() != unit.topic.casefold()
        ):
            raise ProviderError("Die Anschlussübung weicht vom bestätigten Lernziel ab.")
        if len(next_unit["questions"]) != 2:
            raise ProviderError("Die Anschlussrunde benötigt genau zwei kurze Aufgaben.")
        root, _ = root_and_units(db, unit)
        desired = focus_ids(db, unit, item.decision) if old_goals else None
        validate_new_round(db, unit, next_unit, desired_ids=desired)
        selected = {q.get("learning_goal_id") for q in next_unit["questions"]}
        if not selected.issubset(by_goal):
            raise ProviderError("Die Anschlussübungen verwenden unbekannte Lernziele.")
        for question in next_unit["questions"]:
            goal_id = fraction_task_goal(question["prompt"], goals)
            if goal_id and goal_id != question.get("learning_goal_id"):
                raise ProviderError("Die Anschlussaufgabe passt nicht zum erkennbaren Lernziel.")
        if not old_goals and item.decision == "repair":
            weak = {
                r["learning_goal_id"]
                for r in reviews
                if observations_by_id[r["question_id"]]["deterministic_outcome"] != "correct"
                or observations_by_id[r["question_id"]]["hints_used"]
                or any(a["assisted"] for a in observations_by_id[r["question_id"]]["attempts"])
            }
            if not set(sorted(weak)[:2]).issubset(selected):
                raise ProviderError("Die Anschlussübungen greifen die beobachteten Schwierigkeiten nicht auf.")
        followup = LearningUnit(
            child_id=unit.child_id,
            learning_root_id=root.id,
            followup_of=unit.id,
            round_kind=item.decision,
            material_id=unit.material_id,
            assignment_id=unit.assignment_id,
            goal_revision=unit.goal_revision,
            subject=unit.subject,
            topic=unit.topic,
            explanation=next_unit["explanation"],
            questions=next_unit["questions"],
            estimated_minutes=5,
            introduction_seen=item.decision == "check",
            synthetic=unit.synthetic,
            provider=practice_identity[0] if practice_identity else item.provider,
            model=practice_identity[1] if practice_identity else item.model,
        )
        db.add(followup)
        db.flush()
        for source in sources:
            db.add(UnitSource(unit_id=followup.id, material_id=source["id"], revision=source["revision"]))
        item.next_unit_id = followup.id
    values = list(observations_by_id.values())
    independent = [
        q
        for q in values
        if len(q["attempts"]) == 1
        and q["deterministic_outcome"] == "correct"
        and not q["attempts"][0]["assisted"]
        and not q["hints_used"]
    ]
    supported = [q for q in values if q["deterministic_outcome"] == "correct" and q not in independent]
    unresolved = [q for q in values if q["deterministic_outcome"] != "correct"]
    data.update(
        practice_deferred=deferred,
        source_revisions=sources,
        summary=f"{len(values)} Aufgaben bearbeitet: {len(independent)} beim ersten Versuch ohne zusätzliche Hilfe richtig, {len(supported)} mit Unterstützung gelöst, {len(unresolved)} noch falsch oder nicht sicher bewertbar. Das sind Beobachtungen aus dieser Runde.",
        strengths=[
            q["prompt"][:250] + " · beim ersten Versuch ohne zusätzliche Hilfe richtig" for q in independent[:3]
        ],
        practice_focus=[q["prompt"][:300] for q in values if q not in independent][:3],
    )
    item.report = data
    item.status = "ready"
    if record_review:
        record(
            db,
            unit.child_id,
            "coach_support" if item.decision == "parent_help" else "coach_review",
            {"decision": item.decision},
            unit.id,
        )
    elif item.next_unit_id:
        record(db, unit.child_id, "unit_created", {"subject": unit.subject, "topic": unit.topic}, item.next_unit_id)


def synthetic_report(db, unit, action):
    from .synthetic import sample_unit

    _, chain = root_and_units(db, unit)
    goals = goals_for(db, unit) or context(db, unit)[1]["learning_goals"]
    if not goals:
        material = db.get(Material, unit.material_id) if unit.material_id else None
        goals = [
            {
                "id": "g1",
                "label": "Brüche an neuen Beispielen anwenden",
                "source_excerpt": material.content[:200] if material else unit.topic,
            }
        ]

    def goal_for_question(question):
        if question.get("learning_goal_id"):
            return question["learning_goal_id"]
        lower = question["prompt"].casefold()
        key = (
            "erweit"
            if "erweit" in lower
            else "kürz"
            if "kürz" in lower
            else "addier"
            if "+" in lower or "addier" in lower
            else "zähler"
        )
        return next((g["id"] for g in goals if key in g["label"].casefold()), goals[0]["id"])

    desired = focus_ids(db, unit, action)
    if action == "repair":
        old = {q["id"]: q for q in unit.questions}
        weak = {
            goal_for_question(old[q["question_id"]])
            for q in observations(db, unit)
            if q["deterministic_outcome"] != "correct" or q["hints_used"] or any(a["assisted"] for a in q["attempts"])
        }
        desired = sorted(weak)[:2] or desired
    selected_goals = [g for g in goals if g["id"] in desired] or goals[:2]
    next_unit = None
    if action in ("repair", "check"):
        # Explicitly fixed demo tasks. No fabricated provider response.
        next_unit = sample_unit(len(chain))
        denominator = 10 + len(chain) * 2
        for index, q in enumerate(next_unit["questions"][:2]):
            selected_goal = selected_goals[index % len(selected_goals)]
            q.update(
                id=f"practice{index}",
                type="short",
                prompt=f"Rechne aus: {index + 1}/{denominator} + 2/{denominator} = ?",
                options=[],
                answer=f"{index + 3}/{denominator}",
                accepted=[],
                hints=["Addiere die Zähler. Der Nenner bleibt gleich."],
                explanation=f"Das Ergebnis ist {index + 3}/{denominator}.",
                learning_goal_id=selected_goal["id"],
            )
            if "Zähler" in selected_goal["label"]:
                q.update(
                    prompt=f"Welcher Zähler steht in dem Bruch {index + 1}/{denominator}?",
                    answer=str(index + 1),
                    hints=["Der Zähler steht oben."],
                    explanation=f"Der Zähler ist {index + 1}.",
                )
            elif "kürzen" in selected_goal["label"]:
                from fractions import Fraction

                reduced = Fraction(index + 1, denominator)
                q.update(
                    prompt=f"Kürze {2 * (index + 1)}/{2 * denominator} vollständig.",
                    answer=f"{reduced.numerator}/{reduced.denominator}",
                    hints=["Teile beide Zahlen durch den größten gemeinsamen Teiler."],
                    explanation=f"Der vollständig gekürzte Bruch ist {reduced.numerator}/{reduced.denominator}.",
                )
            elif "erweitern" in selected_goal["label"]:
                q.update(
                    prompt=f"Erweitere den Bruch {index + 1}/{denominator} mit dem Faktor 2.",
                    answer=f"{2 * (index + 1)}/{2 * denominator}",
                    hints=["Multipliziere beide Zahlen mit 2."],
                    explanation=f"Der erweiterte Bruch ist {2 * (index + 1)}/{2 * denominator}.",
                )
        next_unit["questions"] = next_unit["questions"][:2]
        next_unit.update(subject=unit.subject, topic=unit.topic)
    return {
        "learning_goals": goals,
        "explanation": "Hinweise sind erlaubt. Mit einer neuen Aufgabe und späteren Wiederholungen kannst du weiter üben.",
        "question_reviews": [
            {
                "question_id": q["question_id"],
                "learning_goal_id": goal_for_question(
                    next(question for question in unit.questions if question["id"] == q["question_id"])
                ),
                "outcome": q["deterministic_outcome"],
                "feedback": q["task_explanation"],
            }
            for q in observations(db, unit)
        ],
        "next_unit": next_unit,
    }


def schedule(unit_id, *, automatic=False):
    """Never roll back a saved child answer when AI/quota/network is unavailable."""
    try:
        with DB.begin() as db:
            unit = db.get(LearningUnit, unit_id)
            if not unit or unit.status != "completed":
                raise HTTPException(409, "Bitte die Einheit zuerst abschließen.")
            from .subject_content import open_learning_unit

            if open_learning_unit(unit):
                return view(db, unit)
            if unit.round_kind == "vocabulary":
                return {"status": "not_needed", "reason": "Sprachrunden verwenden ihre gespeicherte Sprachbewertung und Wiedervorlage."}
            db.execute(update(Child).where(Child.id == unit.child_id).values(grade=Child.grade))
            item = db.get(UnitCoaching, unit_id)
            if item and (automatic or item.status == "ready" or item.request_count >= MAX_REQUESTS):
                return view(db, unit)
            if item and item.job_id:
                job = db.get(Job, item.job_id)
                if job and job.status in ("queued", "running"):
                    return view(db, unit)
            item = item or UnitCoaching(unit_id=unit.id)
            db.add(item)
            db.flush()
            if unit.assignment_id and unit.goal_revision is None:
                goal = db.get(Assignment, unit.assignment_id)
                if goal:
                    unit.goal_revision = goal.revision
            planned = plan_review(db, unit)
            item.decision, item.reason, item.next_review = (
                planned["next_action"],
                planned["reason"],
                planned["next_review"],
            )
            signature, payload, sources = context(db, unit)
            if unit.synthetic:
                item.provider, item.model = "synthetic", "fixed-coaching-v1"
                save_report(db, unit, item, synthetic_report(db, unit, item.decision), sources, synthetic=True)
                return view(db, unit)
            if db.scalar(select(Job.id).where(Job.child_id == unit.child_id, Job.status.in_(["queued", "running"]))):
                raise HTTPException(
                    409,
                    "Eine Verarbeitung läuft noch. Die Antworten sind gespeichert; du kannst die Begleitung danach anfordern.",
                )
            child = db.get(Child, unit.child_id)
            config = config_for_function(db.get(ProviderConfig, 1), "coach")
            item.provider, item.model = config.provider, config.model
            job = Job(
                id=uid(),
                child_id=unit.child_id,
                kind="coach",
                payload={
                    "unit_id": unit.id,
                    "signature": signature,
                    "next_action": item.decision,
                    "next_review": item.next_review,
                    "reason": item.reason,
                    "defer_practice": True,
                },
                idempotency="coach:" + unit.id + ":" + str(item.request_count + 1),
            )
            db.add(job)
            db.flush()
            reserve(db, db.get(Family, child.family_id), child.id, job.id, "coach")
            item.job_id, item.status = job.id, "pending"
            item.request_count += 1
            return view(db, unit)
    except Exception as error:
        reason = (
            str(error.detail)
            if isinstance(error, HTTPException)
            else str(error)
            if isinstance(error, ProviderError)
            else "Die Lernbegleitung konnte nicht vorbereitet werden. Deine Antworten bleiben gespeichert."
        )
        with DB.begin() as db:
            unit = db.get(LearningUnit, unit_id)
            if not unit:
                return None
            db.execute(update(Child).where(Child.id == unit.child_id).values(grade=Child.grade))
            item = db.get(UnitCoaching, unit_id)
            if item and item.status in ("ready", "pending") and item.job_id:
                return view(db, unit)
            item = item or UnitCoaching(unit_id=unit_id)
            item.status, item.reason = "blocked", reason[:500]
            db.add(item)
            db.flush()
            return view(db, unit)


def process(job_id):
    result = None
    try:
        with DB() as db:
            job = db.get(Job, job_id)
            if not job or job.status != "running":
                return
            unit = db.get(LearningUnit, job.payload["unit_id"])
            item = db.get(UnitCoaching, job.payload["unit_id"])
            if (
                not unit
                or unit.child_id != job.child_id
                or unit.status != "completed"
                or not item
                or item.job_id != job.id
            ):
                raise ProviderError("Die beantwortete Einheit ist nicht mehr für diesen Auftrag verfügbar.")
            signature, payload, sources = context(db, unit)
            if signature != job.payload["signature"]:
                raise ProviderError(
                    "Quellen, Antworten oder Elternvorgaben wurden geändert. Bitte die aktuelle Lernbegleitung anfordern."
                )
            config = job_config(db, job, "coach")
            usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
            if not usage or (usage.provider, usage.model, usage.config_revision) != (
                config.provider,
                config.model,
                config.revision,
            ):
                raise ProviderError(
                    "Die Anbieter-Konfiguration wurde geändert. Kein anderer Anbieter wurde aufgerufen."
                )
            payload["next_action"] = job.payload["next_action"]
            payload["focus_goal_ids"] = focus_ids(db, unit, payload["next_action"])
            payload["defer_practice"] = bool(job.payload.get("defer_practice"))
            values = {c.name: getattr(config, c.name) for c in ProviderConfig.__table__.columns}
            from .commerce import usage_terms

            child = db.get(Child, job.child_id)
            usage_terms(db, db.get(Family, child.family_id), enforce=True)
            from .catalog_ai import with_catalog_context

            payload = with_catalog_context(db, child, payload)
            from .model_routing import enabled

            if enabled(config):
                from .learning_controller import projection

                session = projection(db, unit)
                payload["controller_context"] = {"strategy_version": session["strategy_version"],
                    "action": session["action"], "observations": session["observations"]}
            db.rollback()
        result = request_provider(ProviderConfig(**values), "coach", payload)
        with DB.begin() as db:
            job = db.get(Job, job_id)
            if not job or job.status != "running":
                return
            unit = db.scalar(select(LearningUnit).where(LearningUnit.id == job.payload["unit_id"]).with_for_update())
            db.execute(update(Child).where(Child.id == job.child_id).values(grade=Child.grade))
            item = db.get(UnitCoaching, unit.id) if unit else None
            if not unit or not item or item.job_id != job.id or context(db, unit)[0] != job.payload["signature"]:
                raise ProviderError(
                    "Der Lernstand oder die Elternplanung wurde während der Auswertung geändert. Die Ausgabe wurde verworfen."
                )
            if plan_review(db, unit)["next_action"] != item.decision:
                raise ProviderError(
                    "Die verfügbare Lernzeit wurde während der Auswertung geändert. Bitte den aktuellen Plan öffnen."
                )
            verify_current_provider(db, unit, values, "coach", job)
            save_report(db, unit, item, result.data, sources, defer_practice=bool(job.payload.get("defer_practice")))
            if result.action_proposal:
                from .learning_controller import accept_proposal

                accept_proposal(db, unit, result.action_proposal, job.id)
            if result.catalog_assignment:
                from .catalog_ai import remember

                remember(db, "unit", unit, result.catalog_assignment)
                if item.next_unit_id and (next_unit := db.get(LearningUnit, item.next_unit_id)):
                    remember(db, "unit", next_unit, result.catalog_assignment)
            settle(db, db.scalar(select(Usage).where(Usage.job_id == job.id)), result)
            job.status, job.finished, job.result = "completed", int(now()), {"unit_id": unit.id}
    except Exception as error:
        reason = (
            str(error)
            if isinstance(error, ProviderError)
            else "Die KI-Auswertung konnte nicht sicher übernommen werden. Antworten und Lernstand bleiben gespeichert."
        )
        with DB.begin() as db:
            job = db.get(Job, job_id)
            if job:
                job.status, job.error, job.finished = "failed", reason[:500], int(now())
                item = db.get(UnitCoaching, job.payload["unit_id"])
                if item and item.job_id == job.id:
                    item.status, item.reason = "failed", reason[:500]
                usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
                if usage:
                    settle(db, usage, result or getattr(error, "billing_result", None), failed=True)
        log.warning("coach_failed type=%s", type(error).__name__)


@router.post("/units/{unit_id}/coaching")
def request_coaching(unit_id: str, p=Depends(child_user), db=Depends(get_db)):
    from .learning import get_unit

    unit = get_unit(db, p, unit_id, True)
    if unit.status != "completed":
        raise HTTPException(409, "Bitte die Einheit zuerst abschließen.")
    rate_limit(db, "coach-request:" + p.user.id, 10, 600)
    db.rollback()
    return schedule(unit_id)


@router.post("/units/{unit_id}/practice", status_code=202)
def request_practice(
    unit_id: str,
    idempotency: str = Header(alias="Idempotency-Key", default=""),
    p=Depends(child_user),
    db=Depends(get_db),
):
    from .learning import get_unit
    from .materials import enqueue

    unit = get_unit(db, p, unit_id, True)
    db.execute(update(Child).where(Child.id == unit.child_id).values(grade=Child.grade))
    child = db.get(Child, unit.child_id)
    if reason := continuation_block(db, unit, child, check_sources=False):
        raise HTTPException(409, reason)
    item = db.get(UnitCoaching, unit.id)
    if not item or item.status != "ready" or not item.report.get("practice_deferred") or item.next_unit_id:
        raise HTTPException(409, "Bitte den aktuellen Rückblick öffnen.")
    try:
        signature, _, _ = context(db, unit)
    except ProviderError as error:
        raise HTTPException(409, str(error)) from None
    payload = {"unit_id": unit.id, "signature": signature, "next_action": item.decision}
    previous = db.scalar(select(Job).where(Job.idempotency == p.user.id + ":" + idempotency)) if idempotency else None
    if previous:
        payload["practice_number"] = previous.payload.get("practice_number", 1)
        return enqueue(db, p, db.get(Child, unit.child_id), "coach_practice", payload, idempotency)
    if plan_review(db, unit)["next_action"] not in ("repair", "check"):
        raise HTTPException(
            409, "Bitte schau in deinen Rückblick. Eine spätere Wiederholung oder Elternhilfe ist dran."
        )
    old_jobs = list(db.scalars(select(Job).where(Job.child_id == unit.child_id, Job.kind == "coach_practice")))
    if sum(j.payload.get("unit_id") == unit.id for j in old_jobs) >= 2:
        raise HTTPException(
            409, "Die Übungsvorbereitung hat zweimal nicht geklappt. Bitte deine Eltern um Hilfe bitten."
        )
    payload["practice_number"] = sum(j.payload.get("unit_id") == unit.id for j in old_jobs) + 1
    return enqueue(db, p, db.get(Child, unit.child_id), "coach_practice", payload, idempotency)


def process_practice(job_id):
    """An unavailable generator must never discard an already saved review."""
    result = None
    try:
        with DB() as db:
            job = db.get(Job, job_id)
            if not job or job.status != "running":
                return
            unit = db.get(LearningUnit, job.payload["unit_id"])
            item = db.get(UnitCoaching, unit.id) if unit else None
            if not unit or unit.child_id != job.child_id or not item or item.status != "ready" or item.next_unit_id:
                raise ProviderError("Diese Lernrunde wurde inzwischen verändert.")
            if reason := continuation_block(db, unit, db.get(Child, unit.child_id), check_sources=False):
                raise ProviderError(reason)
            signature, payload, sources = context(db, unit)
            if signature != job.payload["signature"] or plan_review(db, unit)["next_action"] not in ("repair", "check"):
                raise ProviderError(
                    "Die Quellen oder der nächste Lernschritt wurden geändert. Bitte den aktuellen Lernplan öffnen."
                )
            config = job_config(db, job, "unit")
            usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
            if not usage or (usage.provider, usage.model, usage.config_revision) != (
                config.provider,
                config.model,
                config.revision,
            ):
                raise ProviderError("Die KI-Einstellungen wurden geändert. Bitte erneut vorbereiten.")
            from .commerce import usage_terms

            child = db.get(Child, unit.child_id)
            usage_terms(db, db.get(Family, child.family_id), enforce=True)
            payload.update(
                review=True,
                practice_kind=item.decision,
                focus_goal_ids=focus_ids(db, unit, item.decision),
                material={
                    "subject": unit.subject,
                    "topic": unit.topic,
                    "content": "\n\n".join(m["content"] for m in payload["materials"]),
                },
            )
            from .db import LearningMemory

            memory = db.get(LearningMemory, unit.id)
            proposal = (memory.working or {}).get("model_proposal") if memory else None
            if proposal and proposal.get("status") == "accepted":
                # A validated model suggestion shapes this explicitly requested
                # round; it cannot change goals, canonical answers or the budget.
                payload["controller_next_step"] = {k: proposal[k] for k in
                    ("kind", "learning_goal_id", "expected_result", "on_success", "on_error")}
            if unit.school_day_id:
                # A day can contain several independent stage chains. New
                # practice must also avoid questions from those other stages.
                payload["previous_prompts"] = [
                    question["prompt"]
                    for previous in db.scalars(
                        select(LearningUnit)
                        .where(
                            LearningUnit.child_id == unit.child_id,
                            LearningUnit.school_day_id == unit.school_day_id,
                        )
                        .order_by(LearningUnit.created, LearningUnit.id)
                    )
                    for question in previous.questions
                ][-120:]
            # Review observations belong in the report, not the new exercise request.
            payload.pop("completed_questions", None)
            from .catalog_ai import with_catalog_context

            payload = with_catalog_context(db, child, payload)
            values = {c.name: getattr(config, c.name) for c in ProviderConfig.__table__.columns}
            db.rollback()
        result = request_provider(ProviderConfig(**values), "unit", payload)
        with DB.begin() as db:
            job = db.get(Job, job_id)
            if not job or job.status != "running":
                return
            db.execute(update(Child).where(Child.id == job.child_id).values(grade=Child.grade))
            unit = db.get(LearningUnit, job.payload["unit_id"])
            item = db.get(UnitCoaching, unit.id) if unit else None
            if (
                not unit
                or not item
                or item.next_unit_id
                or context(db, unit)[0] != job.payload["signature"]
                or plan_review(db, unit)["next_action"] not in ("repair", "check")
            ):
                raise ProviderError(
                    "Der Lernplan wurde während der Vorbereitung geändert. Bitte den aktuellen Plan öffnen."
                )
            if reason := continuation_block(db, unit, db.get(Child, unit.child_id), check_sources=False):
                raise ProviderError(reason)
            data = {key: copy.deepcopy(item.report[key]) for key in s.CoachingOutput.model_fields if key != "next_unit"}
            for review in data["question_reviews"]:
                review.pop("assessment_kind", None)
            data["next_unit"] = result.data
            verify_current_provider(db, unit, values, "unit", job)
            save_report(
                db,
                unit,
                item,
                data,
                sources,
                practice_identity=(values["provider"], values["model"]),
                record_review=False,
            )
            if result.catalog_assignment and item.next_unit_id:
                from .catalog_ai import remember

                remember(db, "unit", db.get(LearningUnit, item.next_unit_id), result.catalog_assignment)
            settle(db, db.scalar(select(Usage).where(Usage.job_id == job.id)), result)
            job.status, job.finished, job.result = "completed", int(now()), {"unit_id": item.next_unit_id}
    except Exception as error:
        reason = (
            str(error)
            if isinstance(error, ProviderError)
            else "Die neue Übung konnte nicht sicher erstellt werden. Dein Rückblick bleibt gespeichert."
        )
        with DB.begin() as db:
            job = db.get(Job, job_id)
            if job:
                job.status, job.error, job.finished = "failed", reason[:500], int(now())
                usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
                if usage:
                    settle(db, usage, result or getattr(error, "billing_result", None), failed=True)
        log.warning("coach_practice_failed type=%s", type(error).__name__)


def verify_current_provider(db, unit, values, function, job):
    from .commerce import usage_terms

    current = job_config(db, job, function)
    if (current.revision, current.provider, current.model) != (values["revision"], values["provider"], values["model"]):
        raise ProviderError("Die KI-Einstellungen wurden während der Vorbereitung geändert.")
    external_allowed(current)
    family = db.get(Family, db.get(Child, unit.child_id).family_id)
    if family.expires and family.expires < now():
        raise ProviderError("Dieser Zugang ist abgelaufen. Die Antworten bleiben gespeichert.")
    usage_terms(db, family, enforce=True)
