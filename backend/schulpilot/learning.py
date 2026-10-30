import re
import unicodedata
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from sqlalchemy import and_, case, func, or_, select, update
from sqlalchemy.orm import aliased, defer, load_only

from . import schemas as s
from .daily_planner import completed_portions, distribute, period_starts, voluntary_steps
from .db import (
    Activity,
    Assignment,
    Attempt,
    AttemptAssessment,
    Child,
    Family,
    Job,
    LearningUnit,
    Mastery,
    Material,
    Message,
    SchoolDay,
    UnitCoaching,
    UnitSource,
    User,
    get_db,
    now,
)
from .families import child_data
from .security import authenticated, child_access, child_user, digest, own_child, parent, rate_limit

router = APIRouter(tags=["Lernen und Planung"])


def local_day(child):
    zone = s.Preferences(**child.preferences).timezone
    return datetime.now(ZoneInfo(zone)).date()


def record(db, child_id, kind, detail=None, unit_id=None):
    activity = Activity(child_id=child_id, kind=kind, detail=detail or {}, unit_id=unit_id)
    db.add(activity)
    from .learning_controller import activity_recorded

    activity_recorded(db, activity)


def prior_explanation_reveals_answer(db, unit, question, events):
    """Detect a literal text answer in another question's opened explanation.

    Unknown overlap remains unknown; existing attempts are never modified.
    """
    if question.get("type") not in ("short", "gap", "choice") or question.get("language"):
        return False
    answers = [question.get("answer"), *(question.get("accepted") or [])]
    words = {" ".join(unicodedata.normalize("NFKC", a).casefold().split()) for a in answers if isinstance(a, str)}
    words = {a for a in words if len(a) >= 4 and all(c.isalpha() or c.isspace() or c in "-'’" for c in a)}
    # An entire uniquely keyed option can also be shown verbatim in an earlier
    # explanation. Shared subject words or partial phrases are not proof.
    choice = question.get("type") == "choice"
    answer = question.get("answer")
    options = question.get("options")
    choice_text = None
    if (choice and isinstance(answer, str) and isinstance(options, list)
            and all(isinstance(option, str) for option in options)
            and options.count(answer) == 1):
        normalized = " ".join(unicodedata.normalize("NFKC", answer).casefold().split()).rstrip(".!?")
        normalized_options = [" ".join(unicodedata.normalize("NFKC", option).casefold().split()).rstrip(".!?")
                              for option in options]
        if 3 <= len(normalized) <= 500 and normalized_options.count(normalized) == 1:
            choice_text = normalized
    # Equivalent formulations are accepted only for the small, explicitly
    # source-verified exchange reference. Negations, unlisted predicates and
    # merely similar words cannot satisfy this closed grammar.
    photosynthesis_choice = bool(choice_text and re.fullmatch(
        r"(?:bei der fotosynthese )?(?:"
        r"pflanzen nehmen kohlenstoffdioxid auf und geben sauerstoff ab|"
        r"(?:pflanzen nehmen|nehmen pflanzen) (?:wasser und )?kohlenstoffdioxid auf|"
        r"(?:pflanzen nehmen|nehmen pflanzen) wasser auf|"
        r"(?:pflanzen geben|geben pflanzen) sauerstoff ab|"
        r"(?:pflanzen bilden|bilden pflanzen) (?:mithilfe von licht |mit licht )?zucker)",
        choice_text))
    if choice and not choice_text:
        return False
    if not words and not choice_text:
        return False
    from .visual_references import question_projection

    questions = {q["id"]: q for q in unit.questions}
    seen = set()
    for event in events:
        detail = event.detail if isinstance(event.detail, dict) else {}
        prior = detail.get("question_id")
        event_kind = getattr(event, "kind", "explanation")
        exposure_key = (prior, event_kind, detail.get("surface"))
        if not prior or prior == question.get("id") or prior not in questions or exposure_key in seen:
            continue
        seen.add(exposure_key)
        # Feedback graphics alone do not prove the full explanation text or
        # the separate step-by-step projection was displayed.
        if event_kind == "feedback_exposure":
            if detail.get("surface") != "text":
                continue
            exposed = [str(questions[prior].get("explanation", ""))]
            text = " ".join(unicodedata.normalize("NFKC", " ".join(exposed)).casefold().split())
            if choice_text and re.search(r"(?<!\w)" + re.escape(choice_text) + r"(?!\w)", text):
                return True
            if any(re.search(r"(?<!\w)" + re.escape(word) + r"(?!\w)", text) for word in words):
                return True
            continue
        # Only the initially displayed step is evidence that the text could be
        # seen; later steps may never have been opened by the learner.
        steps = question_projection(db, unit, questions[prior], closed=True, hints=3)[:1]
        exposed = [str(detail.get("text", "")), *(str(step.get("text", "")) for step in steps)]
        text = " ".join(unicodedata.normalize("NFKC", " ".join(exposed)).casefold().split())
        if photosynthesis_choice:
            from .package_prepared_photosynthesis import bases

            if next(bases(text), None) is not None:
                return True
        if choice_text and re.search(r"(?<!\w)" + re.escape(choice_text) + r"(?!\w)", text):
            return True
        if any(re.search(r"(?<!\w)" + re.escape(word) + r"(?!\w)", text) for word in words):
            return True
    return False


def introduction_reveals_answer(db, unit, question, events, *, user_id=None):
    """Only the initially displayed structured step, after explicit reading."""
    if not any(e.kind == "introduction_read" for e in events):
        return False
    if question.get("language") or question.get("type") not in ("short", "gap", "choice"):
        return False
    from .visual_references import projection

    steps = projection(db, unit).get("explanation_steps", [])
    if not steps or not isinstance(steps[0].get("text"), str):
        return False
    if user_id:
        from .visual_reference_models import UnitVisualPosition

        position = db.get(UnitVisualPosition, (unit.id, user_id))
        if position and (not isinstance(position.position, dict) or
            (position.position.get("explanation_kind") == "intro" and position.position.get("explanation_step_id") != steps[0].get("id"))):
            return False
    text = " ".join(unicodedata.normalize("NFKC", steps[0]["text"]).casefold().split())
    answer = question.get("answer")
    if question.get("type") == "choice":
        options = question.get("options")
        if not isinstance(answer, str) or not isinstance(options, list) or options.count(answer) != 1:
            return False
        values = [answer]
    else:
        values = [answer, *(question.get("accepted") or [])]
    for value in values:
        if not isinstance(value, str):
            continue
        literal = " ".join(unicodedata.normalize("NFKC", value).casefold().split()).rstrip(".!?")
        if len(literal) < 4 or not all(c.isalpha() or c.isspace() or c in "-'’" for c in literal):
            continue
        if re.search(r"(?<!\w)" + re.escape(literal) + r"(?!\w)", text):
            return True
    return False


def message_context_targets(db, rows):
    """Batch-check exact message targets; historic/client context grants no rights."""
    models = {"unit_id": LearningUnit, "material_id": Material, "day_id": SchoolDay}
    contexts = [m.context for m in rows if isinstance(m.context, dict) and len(m.context) == 1]
    existing = set()
    for key, model in models.items():
        ids = {context[key] for context in contexts if isinstance(context.get(key), str)}
        if ids:
            existing.update((child_id, key, target) for child_id, target in db.execute(
                select(model.child_id, model.id).where(model.child_id.in_({m.child_id for m in rows}), model.id.in_(ids))))
    return existing


def message_previews(db, child_id):
    """Bounded private reader; deleted references never turn into clickable links."""
    rows = list(db.scalars(select(Message).where(Message.child_id == child_id)
                           .order_by(Message.created.desc(), Message.id.desc()).limit(100)))
    existing = message_context_targets(db, rows)
    sender_ids = {m.sender_id for m in rows if m.sender_id}
    roles = dict(db.execute(select(User.id, User.role).where(User.id.in_(sender_ids))).all()) if sender_ids else {}
    result = []
    for m in rows:
        context = m.context if isinstance(m.context, dict) and len(m.context) == 1 else {}
        # Do not hash malformed historical values, or expose another child's IDs.
        available = any(isinstance(value, str) and (child_id, key, value) in existing for key, value in context.items())
        result.append({
            "id": m.id, "kind": m.kind, "body": m.body, "resolved": m.resolved,
            "sender_role": roles.get(m.sender_id, "system"),
            "context": context if available else None,
            "context_unavailable": bool(m.context) and not available, "created": m.created,
        })
    return result


def material_data(material):
    from .material_tasks import preview as task_preview
    from .material_vocabulary import preview
    from .subject_content import SourceBlock

    # Only expose an ordered reading projection of this exact saved revision.
    # Corrections and historical malformed blocks must never show stale text.
    source_blocks = []
    try:
        parsed = [SourceBlock.model_validate(row).model_dump(exclude_none=True) for row in (material.source_blocks or [])[:80]]
        if "\n\n".join(row["text"] for row in parsed) == material.content:
            source_blocks = parsed
    except (ValueError, TypeError):
        pass

    return {
        k: getattr(material, k)
        for k in (
            "id",
            "purpose",
            "child_id",
            "school_day_id",
            "page_number",
            "quality_warnings",
            "legibility",
            "title",
            "status",
            "subject",
            "subject_id",
            "topic",
            "content",
            "uncertainties",
            "homework",
            "confirmed",
            "synthetic",
            "fixture_id",
            "extraction_provider",
            "extraction_model",
            "created",
            "revision",
        )
    } | {"source_blocks": source_blocks,
         "vocabulary_preview": preview(material.subject, material.topic, material.content, material.source_blocks) if not material.synthetic else None,
         "task_preview": task_preview(material.content, material.homework, material.task_decisions),
         "confirmed_tasks": [row["text"] for row in task_preview(material.content, material.homework, material.task_decisions)
                             if row["classification"] == "homework" and any(
                                 d["key"] == row["key"] and d["classification"] == "homework" for d in material.task_decisions or [])],
         "supports_task_confirmation": True,
         "supports_notebook_practice": True,
         "fixed_example": bool(material.fixture_id)}


def assignment_data(assignment):
    return {
        k: getattr(assignment, k)
        for k in ("id", "revision", "kind", "origin_kind", "source_status", "source_revisions", "subject", "topic", "note", "due", "scheduled_for", "mandatory", "done", "material_id", "source_unit_id")
    }


def mastery_data(m):
    return {
        "id": m.id,
        "subject": m.subject,
        "topic": m.topic,
        "independent_units": m.independent,
        "assisted_units": m.assisted,
        "difficult_units": m.difficulties,
        "uncertain_units": m.uncertain_units,
        "later_review_successes": m.review_successes,
        "next_review": m.next_review,
        "last_practiced": m.last_practiced,
        "description": (
            "Bei mehreren späteren Wiederholungen selbstständig gelöst"
            if m.review_successes >= 2
            else "Weiter beobachten und gezielt wiederholen"
        ),
    }


def break_recommendation(db, unit):
    prefs = s.Preferences(**db.get(Child, unit.child_id).preferences)
    return {
        "break_recommended": unit.status == "active" and (unit.segment_seconds or 0) >= prefs.session_minutes * 60,
        "break_minutes": prefs.break_minutes,
    }


def learning_time(db, child):
    """Only saved activity establishes a minimum; estimates never earn time."""
    return learning_times(db, [child])[child.id]


def learning_times(db, children):
    """One scoped aggregate for a family, respecting each child's timezone."""
    if not children:
        return {}
    periods = {}
    for child in children:
        prefs = s.Preferences(**child.preferences)
        today = local_day(child)
        periods[child.id] = (prefs, today, *period_starts(today, prefs.timezone))
    seconds = Activity.detail["seconds"].as_integer()
    daily_condition = or_(
        *(and_(Activity.child_id == id, Activity.created >= values[2]) for id, values in periods.items())
    )
    weekly_condition = or_(
        *(and_(Activity.child_id == id, Activity.created >= values[3]) for id, values in periods.items())
    )
    totals = {
        id: (daily, weekly)
        for id, daily, weekly in db.execute(
            select(
                Activity.child_id,
                func.coalesce(func.sum(case((daily_condition, seconds), else_=0)), 0),
                func.coalesce(func.sum(seconds), 0),
            )
            .where(Activity.kind == "active_time", weekly_condition)
            .group_by(Activity.child_id)
        )
    }
    result = {}
    for id, (prefs, today, _, _) in periods.items():
        daily, weekly = totals.get(id, (0, 0))
        required = today.weekday() in prefs.weekdays and not (prefs.pause_until and today <= prefs.pause_until)
        result[id] = {
            "daily_active_seconds": daily,
            "weekly_active_seconds": weekly,
            "daily_goal_minutes": prefs.daily_minutes,
            "weekly_goal_minutes": prefs.weekly_minutes,
            "daily_goal_met": bool(required and daily >= prefs.daily_minutes * 60),
            "weekly_goal_met": weekly >= prefs.weekly_minutes * 60,
            "daily_remaining_seconds": max(0, prefs.daily_minutes * 60 - daily),
            "goal_required": bool(required),
        }
    return result


def pending_feedback(unit, attempts, events):
    """Resume only the latest explicitly guided response; legacy history stays unchanged."""
    if not attempts:
        return None
    latest = attempts[-1]
    pending = any(e.kind == "feedback_pending" and e.detail.get("attempt_id") == latest.id for e in events)
    seen = any(e.kind == "feedback_seen" and e.detail.get("attempt_id") == latest.id for e in events)
    if not pending or seen:
        return None
    q = next((q for q in unit.questions if q["id"] == latest.question_id), None)
    if not q:
        return None
    count = sum(a.question_id == latest.question_id for a in attempts)
    return {
        "attempt_id": latest.id,
        "question_id": latest.question_id,
        "answer": latest.answer,
        "outcome": latest.outcome,
        "assisted": latest.assisted,
        "explanation": q["explanation"] if latest.outcome != "incorrect" or count >= 3 else None,
    }


def feedback_resume_id(db, child_id, *, include_language=True):
    """Find unread latest feedback without loading answer bodies or scanning units in Python."""
    pending, seen, newer = aliased(Activity), aliased(Activity), aliased(Attempt)
    newer_answer = select(newer.id).where(
        newer.unit_id == Attempt.unit_id,
        or_(newer.created > Attempt.created, and_(newer.created == Attempt.created, newer.id > Attempt.id)),
    ).correlate(Attempt).exists()
    return db.scalar(
        select(LearningUnit.id)
        .join(Attempt, Attempt.unit_id == LearningUnit.id)
        .join(pending, and_(pending.unit_id == LearningUnit.id, pending.child_id == child_id,
                           pending.kind == "feedback_pending", pending.detail["attempt_id"].as_string() == Attempt.id))
        .outerjoin(seen, and_(seen.unit_id == LearningUnit.id, seen.child_id == child_id,
                             seen.kind == "feedback_seen", seen.detail["attempt_id"].as_string() == Attempt.id))
        .where(LearningUnit.child_id == child_id, seen.id.is_(None), ~newer_answer,
               True if include_language else LearningUnit.round_kind != "vocabulary")
        .order_by(Attempt.created.desc(), Attempt.id.desc()).limit(1)
    )


def unit_source_texts(db, unit):
    references = list(db.scalars(select(UnitSource).where(UnitSource.unit_id == unit.id)))
    # A legacy material_id is not a revision snapshot. LearningUnit has no
    # source_revision field, and today's confirmed text cannot safely stand in
    # for the material used by an older exercise. Keep the exercise readable,
    # but only derive source-bound graphics from explicit matching references.
    from .source_lineage import learning_source

    return [safe["content"] for ref in references
            if (material := db.get(Material, ref.material_id)) and material.child_id == unit.child_id
            and (safe := learning_source(db, material, revision=ref.revision))["content"].strip()]



def unit_source_projection(db, unit):
    """Only owned source metadata; never invent a legacy revision snapshot."""
    refs = list(db.scalars(select(UnitSource).where(UnitSource.unit_id == unit.id)
        .order_by(UnitSource.material_id)))
    snapshots = [(ref.material_id, ref.revision) for ref in refs]
    if not refs and unit.material_id:
        snapshots = [(unit.material_id, None)]
    result = []
    for material_id, revision in snapshots:
        material = db.get(Material, material_id)
        if not material or material.child_id != unit.child_id:
            continue
        status = ("legacy" if revision is None else "changed" if material.revision != revision
            else "unconfirmed" if not material.confirmed else "ready")
        result.append({"material_id": material.id, "revision": revision,
            "current_revision": material.revision, "status": status,
            "title": material.title, "has_image": bool(material.path)})
    return result


def unit_data(db, unit, include_answers=False, *, include_progress=True):
    from . import adaptive_plan, coaching
    from .learning_controller import projection as session_projection
    from .legacy_learning_content import issue as content_issue
    from .visual_references import projection as visual_projection

    sources = unit_source_texts(db, unit)
    attempts = list(db.scalars(select(Attempt).where(Attempt.unit_id == unit.id).order_by(Attempt.created, func.coalesce(Attempt.evaluation["attempt_number"].as_integer(), 0), Attempt.id)))
    events = list(db.scalars(select(Activity).where(Activity.unit_id == unit.id)))
    history = {}
    for row in db.scalars(select(AttemptAssessment).where(AttemptAssessment.attempt_id.in_([a.id for a in attempts]))
                           .order_by(AttemptAssessment.created, AttemptAssessment.id)):
        history.setdefault(row.attempt_id, []).append({"previous_outcome": row.previous_outcome,
            "outcome": row.outcome, "rules_version": row.rules_version, "created": row.created})
    session = session_projection(db, unit, include_draft=not include_answers)
    entry = session.get("learning_path")
    prior = next((step for step in (entry or {}).get("steps", []) if step["kind"] == "prior_check"), None)
    hide_introduction = not include_answers and prior is not None and prior["status"] != "completed"
    questions = []
    from .instructional_decisions import deferred as instructional_deferred

    deferred_questions = adaptive_plan.deferred(db, unit) | instructional_deferred(db, unit)
    for q in unit.questions:
        value = dict(q)
        if q.get("field_group"):
            from .grouped_questions import public_group

            value["field_group"] = public_group(q["field_group"])
        if unit.subject.strip().casefold() == "mathematik" and q.get("type") in ("short", "gap") and not q.get("language") and re.fullmatch(r"[+-]?\d+(?:[.,]\d+)?", str(q.get("answer", "")).strip()):
            value["input_kind"] = "number"
        if not include_answers:
            value.pop("answer", None)
            value.pop("accepted", None)
            value.pop("hints", None)
            value.pop("explanation", None)
            value.pop("language_feedback", None)
            if q.get("language"):
                from .language_tasks import public_metadata

                value["language"] = public_metadata(q["language"])
            if q["type"] == "match":
                value["options"] = [pair.split("|")[0] for pair in q["options"]]
                value["choices"] = sorted(pair.split("|")[1] for pair in q["options"])
        value["attempts"] = [
            {"id": a.id, "answer": a.answer, "outcome": a.outcome, "assisted": a.assisted, "created": a.created,
             "evaluation": a.evaluation, "input_method": a.input_method, "assessment_history": history.get(a.id, [])}
            for a in attempts
            if a.question_id == q["id"]
        ]
        shown = [e for e in events if e.kind == "hint" and e.detail.get("question_id") == q["id"]]
        value["hints_used"] = len(shown)
        if q["id"] in deferred_questions:
            value["controller_deferred"] = True
        value["shown_hints"] = [{"number":e.detail.get("number"), "text":e.detail.get("text", "")} for e in sorted(shown,key=lambda e:(e.created,e.id))]
        if (
            unit.status == "completed"
            or len(value["attempts"]) >= 3
            or any(a["outcome"] in ("correct", "uncertain") for a in value["attempts"])
        ):
            value["feedback_explanation"] = q["explanation"]
            if q.get("language_feedback"):
                value["language_feedback"] = q["language_feedback"]
        from .subject_content import legacy_presentation, public_presentation

        closed = "feedback_explanation" in value
        value["presentation"] = public_presentation(q.get("presentation") or legacy_presentation(q, sources),
            closed=include_answers or closed, hints=value["hints_used"])
        from .visual_references import question_projection

        value["explanation_steps"] = question_projection(db, unit, q, closed=include_answers or closed, hints=value["hints_used"])
        questions.append(value)
    return {
        "id": unit.id,
        "child_id": unit.child_id,
        "subject": unit.subject,
        "topic": unit.topic,
        "explanation": unit.explanation
        if not hide_introduction and (include_answers or unit.round_kind not in coaching.CHECK_KINDS or unit.status == "completed")
        else "",
        "questions": questions,
        **visual_projection(db, unit,
            show_introduction=not hide_introduction and (include_answers or unit.round_kind not in coaching.CHECK_KINDS or unit.status == "completed")),
        "pending_feedback": pending_feedback(unit, attempts, events),
        "supports_recheck": True,
        "supports_question_explanation": True,
        "supports_feedback_exposure": True,
        "supports_detailed_feedback": True,
        "learning_session": session,
        "content_version": 1,
        "content_issue": content_issue(unit),
        "supports_answer_idempotency": True,
        "status": unit.status,
        "synthetic": unit.synthetic,
        "active_seconds_approx": unit.active_seconds,
        "learning_time": learning_time(db, db.get(Child, unit.child_id)),
        "break_until": unit.break_until,
        **break_recommendation(db, unit),
        "material_id": unit.material_id,
        "school_day_id": unit.school_day_id,
        "estimated_minutes": unit.estimated_minutes,
        "package_version": unit.package_version,
        "introduction_seen": unit.introduction_seen,
        "sources": unit_source_projection(db, unit),
        "source_material_ids": list(db.scalars(select(UnitSource.material_id).where(UnitSource.unit_id == unit.id)))
        or ([unit.material_id] if unit.material_id else []),
        "assignment_id": unit.assignment_id,
        "review_of": unit.review_of,
        "learning_root_id": unit.learning_root_id,
        "followup_of": unit.followup_of,
        "round_kind": unit.round_kind,
        "not_before": unit.not_before,
        "language_version": 1 if any(q.get("language") for q in unit.questions) else None,
        "vocabulary_result": vocabulary_result(db, unit),
        "coaching": {"status": "not_needed"} if unit.round_kind == "vocabulary" else coaching.view(db, unit),
        "learning_progress": coaching.progress(db, unit)
        if include_progress and unit.round_kind != "vocabulary"
        else None,
        "created": unit.created,
        "completed": unit.completed,
        "provider": unit.provider,
        "model": unit.model,
    }


def vocabulary_result(db, unit):
    if unit.round_kind != "vocabulary":
        return None
    from .db import VocabularyReviewEvent

    events = list(db.scalars(select(VocabularyReviewEvent).join(Attempt).where(Attempt.unit_id == unit.id)))
    return {"answered_tasks": len({a.question_id for a in db.scalars(select(Attempt).where(Attempt.unit_id == unit.id))}),
            "advanced_skills": sum(e.advanced for e in events),
            "next_due": min((e.due for e in events), default=None),
            "skills": sorted({q["language"]["skill"] for q in unit.questions if q.get("language")})}


def language_capability(unit, capabilities, db=None):
    from .learning_labs import contains

    supported = capabilities.split(",") if isinstance(capabilities, str) else []
    lab_present = contains(unit.questions)
    if db is not None:
        from .visual_reference_models import UnitVisualSnapshot

        visuals = db.get(UnitVisualSnapshot, unit.id)
        lab_present = lab_present or (visuals is not None and (contains(visuals.steps) or contains(visuals.question_steps)))
    if lab_present and "labs-v1" not in supported:
        raise HTTPException(409, "Diese Runde enthält neue Lernlabore. Bitte die App aktualisieren oder die aktuelle Web-App öffnen.")
    if db is not None:
        from .db import LearningMemory

        memory = db.get(LearningMemory, unit.id)
        if memory and (memory.working or {}).get("entry_plan") and "learning-entry-v1" not in (capabilities.split(",") if isinstance(capabilities, str) else []):
            raise HTTPException(426, "Diese Runde nutzt den neuen Lernstart. Bitte die App aktualisieren oder die aktuelle Web-App öffnen.")
    if any(q.get("type") == "grouped" for q in unit.questions) and "grouped-v1" not in (capabilities.split(",") if isinstance(capabilities, str) else []):
        raise HTTPException(426, "Diese Runde enthält Mehrfeldaufgaben. Bitte die App aktualisieren oder die aktuelle Web-App öffnen.")
    if any(q.get("presentation") for q in unit.questions) and "visual-v1" not in (capabilities.split(",") if isinstance(capabilities, str) else []):
        raise HTTPException(426, "Diese Runde enthält neue Lernbilder. Bitte die App aktualisieren oder die aktuelle Web-App öffnen.")
    if any(q.get("language") for q in unit.questions) and not language_supported(capabilities):
        raise HTTPException(426, "Für diese Sprachrunde bitte die App aktualisieren oder die aktuelle Web-App öffnen.")


def language_supported(capabilities):
    return isinstance(capabilities, str) and "language-v1" in capabilities.split(",")


def summary(db, child, days, *, learning_paths=None):
    from .coaching import paths

    current = datetime.now(ZoneInfo(s.Preferences(**child.preferences).timezone))
    since = int((current.replace(hour=0, minute=0, second=0, microsecond=0) - timedelta(days=days - 1)).timestamp())
    units = list(db.scalars(select(LearningUnit).where(LearningUnit.child_id == child.id)))
    recent = [u for u in units if u.completed and u.completed >= since]
    unit_ids = [u.id for u in units]
    attempts = list(db.scalars(select(Attempt).where(Attempt.unit_id.in_(unit_ids), Attempt.created >= since)))
    unresolved = list(
        db.scalars(
            select(Message).where(Message.child_id == child.id, Message.kind == "help", Message.resolved.is_(False))
        )
    )
    difficulties = list(db.scalars(select(Mastery).where(Mastery.child_id == child.id, Mastery.difficulties > 0)))
    hints = list(
        db.scalars(
            select(Activity).where(Activity.child_id == child.id, Activity.kind == "hint", Activity.created >= since)
        )
    )
    final = {(a.unit_id, a.question_id): a for a in sorted(attempts, key=lambda a: (a.created, a.id))}
    uncertain = sum(a.outcome == "uncertain" for a in final.values())
    topics = list(dict.fromkeys(f"{u.subject}: {u.topic}" for u in recent))
    coach_support = [
        p for p in (paths(db, child.id) if learning_paths is None else learning_paths)
        if p["needs_parent"] and p["state"] != "source_changed"
    ]
    if unresolved:
        support = f"Ja – {len(unresolved)} offener Hilfewunsch. Bitte gemeinsam das Anliegen ansehen."
    elif coach_support:
        support = (
            "Bitte gemeinsam unterstützen bei: "
            + ", ".join(p["topic"] for p in coach_support[:3])
            + ". Die gespeicherte Lernbegleitung zeigt den Anlass."
        )
    elif uncertain:
        support = f"Für {uncertain} offene Bewertung(en) bietet die App eine Antwortprüfung an. Daraus folgt noch kein fachlicher Hilfebedarf."
    elif any(a.outcome == "incorrect" for a in final.values()):
        support = "Die App bietet zu den noch schwierigen Aufgaben eine andere Erklärung und kurze Anschlussübungen."
    elif attempts:
        support = "Aktuell kein ausdrücklicher Hilfebedarf erfasst. Weitere Wiederholungen bleiben sinnvoll."
    else:
        support = "Noch keine Antworten im Zeitraum. Daraus lässt sich kein Verständnis ableiten."
    return {
        "period_days": days,
        "completed_units": len(recent),
        "started_units": sum(u.status in ("active", "paused") for u in units),
        "answer_count": len(attempts),
        "hints_used": len(hints),
        "uncertain_answers": uncertain,
        "active_minutes_approx": round(
            sum(
                e.detail.get("seconds", 0)
                for e in db.scalars(
                    select(Activity).where(
                        Activity.child_id == child.id, Activity.kind == "active_time", Activity.created >= since
                    )
                )
            )
            / 60,
            1,
        ),
        "topics": topics,
        "support": support,
        "help_requests": len(unresolved),
        "coaching_support_topics": [p["topic"] for p in coach_support],
        "recurring_difficulties": [m.topic for m in difficulties if m.difficulties >= 2],
        "notice": "Zeitmessung ist eine Näherung. Eine richtige Antwort beweist noch keine sichere Beherrschung.",
    }


def plan(db, child, *, learning_paths=None, include_language=True):
    from .coaching import paths
    from .grades import priorities, subject_key
    from .study_path import plan_sources_current, source_backed_blocks

    prefs = s.Preferences(**child.preferences)
    today = local_day(child)
    grade_priorities = priorities(db, child)
    units = list(
        db.scalars(
            select(LearningUnit)
            .options(defer(LearningUnit.questions), defer(LearningUnit.explanation))
            .where(LearningUnit.child_id == child.id, True if include_language else LearningUnit.round_kind != "vocabulary")
            .order_by(LearningUnit.created)
        )
    )
    assignments = list(
        db.scalars(select(Assignment).where(Assignment.child_id == child.id, Assignment.done.is_(False), Assignment.source_status == "confirmed"))
    )
    reviews = list(
        db.scalars(select(Mastery).where(Mastery.child_id == child.id, Mastery.next_review <= today.isoformat()))
    )
    start, week = period_starts(today, prefs.timezone)
    measured = learning_time(db, child)
    daily_seconds = measured["daily_active_seconds"]
    weekly_seconds = measured["weekly_active_seconds"]
    daily_used = (daily_seconds + 59) // 60
    weekly_used = (weekly_seconds + 59) // 60
    completed_daily, completed_weekly = completed_portions(units, prefs, start, week)
    daily_load, weekly_load = max(daily_used, completed_daily), max(weekly_used, completed_weekly)
    # Estimates bound the suggested portion, never measured progress or access.
    available = max(0, prefs.daily_minutes - daily_load)
    daily_remaining = max(0, prefs.daily_minutes * 60 - daily_seconds)
    weekly_remaining = max(0, prefs.weekly_minutes * 60 - weekly_seconds)
    notices = []
    paused = bool(prefs.pause_until and today <= prefs.pause_until)
    free_day = today.weekday() not in prefs.weekdays
    if paused:
        notices.append(f"Lernpause bis {prefs.pause_until.isoformat()}. Offene Ziele bleiben erhalten.")
        available = 0
    elif free_day:
        notices.append("Heute ist kein Lernziel eingeplant. Wenn du möchtest, kannst du freiwillig lernen.")
        available = 0
    if prefs.session_minutes > prefs.daily_minutes:
        notices.append("Für den Tagesvorschlag planen wir eine kürzere Runde. Du kannst danach weiterlernen.")
    if len(prefs.weekdays) * prefs.daily_minutes < prefs.weekly_minutes:
        notices.append("Das Wochenminimum liegt über den Tagesvorschlägen. Plant bei Bedarf weitere Lernzeit ein.")
    days = list(db.scalars(select(SchoolDay).where(SchoolDay.child_id == child.id).order_by(SchoolDay.school_date)))
    source_ids_by_day = {}
    for material_id, day_id in db.execute(select(Material.id, Material.school_day_id).where(
            Material.child_id == child.id, Material.purpose != "exam", Material.confirmed.is_(True))):
        source_ids_by_day.setdefault(day_id, set()).add(material_id)
    unit_ids = {u.id for u in units}
    day_blocks = {d.id: source_backed_blocks(db, d, material_ids=source_ids_by_day.get(d.id, set()),
                                           unit_ids=unit_ids) for d in days}
    source_dates = {d.id: d.school_date for d in days}
    practiced = {}
    for unit in units:
        if unit.completed and unit.school_day_id:
            practiced[unit.school_day_id] = max(practiced.get(unit.school_day_id, 0), unit.completed)
    units_by_id = {u.id: u for u in units}
    # Initial stages in older saved plans lack the subject field. Resolve it
    # from the existing unit; otherwise different subjects share one empty
    # chain and a started maths round disappears behind untouched biology.
    chains = {
        block["unit_id"]: (f"{day.id}:{block.get('subject') or units_by_id[block['unit_id']].subject}", index)
        for day in days
        for index, block in enumerate(day_blocks[day.id])
        if block.get("unit_id") in units_by_id
    }
    synthetic_family = db.get(Family, child.family_id).synthetic
    synthetic_days = set(
        db.scalars(
            select(Material.school_day_id).where(
                Material.child_id == child.id, Material.synthetic.is_(True), Material.school_day_id.is_not(None)
            )
        )
    )
    assignments_by_id = {a.id: a for a in assignments}
    minutes = min(prefs.session_minutes, max(5, available))
    candidates = []
    from .learning_origins import round_days

    origins = round_days(db, child.id)
    for unit in units:
        if unit.status != "completed":
            goal = assignments_by_id.get(unit.assignment_id)
            chain = chains.get(unit.id)
            candidates.append(
                {
                    "kind": "unit",
                    "id": unit.id,
                    "topic": unit.topic,
                    "subject": unit.subject,
                    "mandatory": bool(goal and goal.mandatory),
                    "status": unit.status,
                    "estimated_minutes": max(1, (unit.estimated_minutes or minutes) - unit.active_seconds // 60),
                    "scheduled_for": goal.scheduled_for if goal else None,
                    "due": goal.due if goal else None,
                    "not_before": unit.not_before,
                    "source_date": source_dates.get(unit.school_day_id or origins.get(unit.id)),
                    "study_path_id": unit.school_day_id or origins.get(unit.id),
                    "round_kind": unit.round_kind,
                    "_chain": chain[0] if chain else None,
                    "_sequence": chain[1] if chain else 0,
                }
            )
    for a in sorted(assignments, key=lambda a: (not a.mandatory, a.due or "9999", a.created)):
        if any(u.assignment_id == a.id and u.status != "completed" for u in units):
            continue
        candidates.append(
            {
                "kind": "assignment",
                "id": a.id,
                "topic": a.topic,
                "subject": a.subject,
                "mandatory": a.mandatory,
                "due": a.due,
                "scheduled_for": a.scheduled_for,
                "assignment_kind": a.kind,
                "material_id": a.material_id,
                "estimated_minutes": min(prefs.session_minutes, prefs.daily_minutes, max(5, available)),
                "status": "practiced_today"
                if any(u.assignment_id == a.id and u.completed and u.completed >= start for u in units)
                else "not_started",
            }
        )
    if learning_paths is None:
        learning_paths = paths(db, child.id)
    for path in learning_paths:
        if path["next_unit_id"] or not path["next_review"]:
            continue
        candidates.append(
            {
                "kind": "review",
                "id": path["latest_unit_id"],
                "learning_root_id": path["root_unit_id"],
                "topic": path["topic"],
                "subject": path["subject"],
                "mandatory": False,
                "status": "not_started",
                "due": path["next_review"],
                "not_before": path["next_review"],
                "estimated_minutes": min(8, prefs.session_minutes, prefs.daily_minutes),
            }
        )
    for mastery in reviews:
        if any(p["subject"] == mastery.subject and p["topic"] == mastery.topic for p in learning_paths):
            continue
        if any(x["topic"] == mastery.topic for x in candidates):
            continue
        old = next((u for u in reversed(units) if u.topic == mastery.topic and u.status == "completed"), None)
        if old:
            candidates.append(
                {
                    "kind": "review",
                    "id": old.id,
                    "topic": old.topic,
                    "subject": old.subject,
                    "mandatory": False,
                    "status": "not_started",
                    "due": mastery.next_review,
                    "not_before": mastery.next_review,
                    "estimated_minutes": min(8, prefs.session_minutes, prefs.daily_minutes),
                }
            )
    confirmed_materials = list(
        db.scalars(
            select(Material)
            .where(Material.child_id == child.id, Material.purpose != "exam", Material.confirmed.is_(True))
            .options(defer(Material.content), defer(Material.homework), defer(Material.uncertainties))
            .order_by(Material.created, Material.id)
        )
    )
    for m in confirmed_materials:
        if m.school_day_id:
            continue
        if not any(x["topic"] == m.topic for x in candidates) and not any(u.material_id == m.id for u in units):
            candidates.append(
                {
                    "kind": "material",
                    "id": m.id,
                    "topic": m.topic,
                    "subject": m.subject,
                    "mandatory": False,
                    "status": "not_started",
                    "estimated_minutes": min(8, prefs.session_minutes, prefs.daily_minutes),
                }
            )
    blocked_study_paths = []
    for school_day in days:
        unpublished = any(not block.get("unit_id") for block in (school_day.learning_plan or {}).get("blocks", []))
        sources_current = not unpublished or plan_sources_current(db, school_day)
        if not sources_current:
            blocked_study_paths.append({"day_id": school_day.id, "date": school_day.school_date,
                                        "reason_code": "source_changed"})
        for index, block in enumerate(day_blocks[school_day.id]):
            saved_unit = units_by_id.get(block.get("unit_id"))
            if saved_unit and saved_unit.status == "completed":
                continue
            if not saved_unit and school_day.id not in synthetic_days and not synthetic_family:
                if not sources_current:
                    continue
                candidates.append(
                    {
                        "kind": "study_path",
                        "id": school_day.id,
                        "block_id": block["id"],
                        "topic": block["title"],
                        "subject": block.get("subject", "Lernreise"),
                        "mandatory": False,
                        "status": "planned",
                        "estimated_minutes": min(prefs.session_minutes, max(5, block["question_count"] * 2)),
                        "source_date": school_day.school_date,
                        "not_before": school_day.school_date,
                        "_chain": f"{school_day.id}:{block.get('subject', '')}",
                        "_sequence": index,
                        "_last_practiced": (
                            datetime.fromtimestamp(practiced[school_day.id], ZoneInfo(prefs.timezone))
                            .date()
                            .isoformat()
                            if school_day.id in practiced
                            else None
                        ),
                    }
                )
    completed_chains = {}
    for unit in units:
        if unit.completed and unit.completed >= start and unit.school_day_id:
            key = f"{unit.school_day_id}:{unit.subject}"
            completed_chains[key] = completed_chains.get(key, 0) + 1
    # A grade changes emphasis, never daily capacity, release dates or answers.
    # If all ordinary rounds in a priority subject are done, offer one bounded
    # new practice from its confirmed material instead of manufacturing a topic.
    for key, priority in grade_priorities.items():
        if not any(subject_key(item["subject"]) == key for item in candidates):
            material = next((m for m in reversed(confirmed_materials) if subject_key(m.subject) == key), None)
            if material and not any(u.status != "completed" and u.material_id == material.id for u in units):
                candidates.append({"kind": "material", "id": material.id, "topic": material.topic,
                                   "subject": material.subject, "mandatory": False, "status": "ready",
                                   "estimated_minutes": min(8, prefs.session_minutes, prefs.daily_minutes)})
    from .vocabulary import summary as vocabulary_summary

    words = vocabulary_summary(db, child)
    for language in words["by_locale"]:
        if include_language and (language["due_words"] or language["new_words"] or language["unpracticed_skills"]):
            exams = [a.due for a in assignments if a.kind == "exam" and a.due and subject_key(a.subject) == subject_key(language["subject"])]
            candidates.append({"kind": "vocabulary", "id": child.id + ":" + language["locale"], "topic": "Deine Wörter wiederholen",
                               "target_locale": language["locale"], "subject": language["subject"], "mandatory": False, "status": "ready",
                               "due": min(exams) if exams else None, "estimated_minutes": min(5, prefs.session_minutes)})
    for item in candidates:
        item["_grade_priority"] = grade_priorities.get(subject_key(item["subject"]), 0)
        if item["_grade_priority"]:
            item["focus_reason"] = "Diesen Stoff üben wir besonders regelmäßig."
    from .parent_insights import apply_guidance

    apply_guidance(db, child, candidates)
    proposal = distribute(
        candidates,
        prefs,
        today,
        daily_seconds=daily_load * 60,
        weekly_seconds=weekly_load * 60,
        completed_chains=completed_chains,
    )
    if proposal["later"]:
        notices.append("Weiterer Stoff wird auf die nächsten Lerntage verteilt. Das Tagesziel bleibt gleich.")
    if proposal["beyond_week_steps"]:
        notices.append(
            "Wir verteilen den Stoff in kleine Portionen. Was diese Woche nicht passt, bleibt gespeichert und wird später eingeplant."
        )
    if proposal["conflicts"]:
        notices.append(
            "Ein Elterntermin passt voraussichtlich nicht in die Lernzeit. Bitte Termin oder Schwerpunkte gemeinsam prüfen."
        )
    optional = voluntary_steps(candidates, today)
    offered_materials = {item["id"] for item in optional if item["kind"] == "material"}
    offered_groups = set()
    group_materials = {}
    for material in confirmed_materials:
        group = (material.school_day_id or material.id, material.subject.casefold())
        group_materials.setdefault(group, set()).add(material.id)
    source_units = {}
    if confirmed_materials:
        for unit_id, material_id in db.execute(
            select(UnitSource.unit_id, UnitSource.material_id)
            .join(LearningUnit, LearningUnit.id == UnitSource.unit_id)
            .where(LearningUnit.child_id == child.id, UnitSource.material_id.in_([m.id for m in confirmed_materials]))
        ):
            source_units.setdefault(material_id, set()).add(unit_id)
    for material in confirmed_materials:
        group = (material.school_day_id or material.id, material.subject.casefold())
        if material.id in offered_materials or group in offered_groups:
            continue
        material_ids = group_materials[group]
        related_units = set().union(*(source_units.get(id, set()) for id in material_ids))
        previous = [
            unit
            for unit in units
            if unit.material_id in material_ids
            or unit.id in related_units
            or (
                material.school_day_id
                and unit.school_day_id == material.school_day_id
                and unit.subject.casefold() == material.subject.casefold()
            )
        ]
        if not previous or any(unit.status != "completed" for unit in previous):
            continue
        day = next((value for value in days if value.id == material.school_day_id), None)
        if day and any(
            block.get("subject", "").casefold() == material.subject.casefold()
            and (not units_by_id.get(block.get("unit_id")) or units_by_id[block["unit_id"]].status != "completed")
            for block in day_blocks[day.id]
        ):
            continue
        offered_groups.add(group)
        optional.append(
            {
                "kind": "material",
                "id": material.id,
                "topic": material.topic,
                "subject": material.subject,
                "mandatory": False,
                "status": "ready",
                "estimated_minutes": min(8, prefs.session_minutes),
                "reason": "material",
            }
        )
    optional.sort(key=lambda item: (
        item.get("status") not in ("active", "paused"), not item.get("mandatory", False),
        -grade_priorities.get(subject_key(item["subject"]), 0),
    ))
    return {
        **proposal,
        "date": today.isoformat(),
        "vocabulary": words,
        "available_minutes": available,
        "session_minutes": minutes,
        "break_minutes": prefs.break_minutes,
        # Old clients retain the numeric fields, but they are no access limit.
        "daily_limit_minutes": prefs.daily_minutes,
        "weekly_limit_minutes": prefs.weekly_minutes,
        "daily_goal_minutes": prefs.daily_minutes,
        "weekly_goal_minutes": prefs.weekly_minutes,
        "daily_active_seconds": daily_seconds,
        "weekly_active_seconds": weekly_seconds,
        "daily_goal_met": measured["daily_goal_met"],
        "weekly_goal_met": weekly_seconds >= prefs.weekly_minutes * 60,
        "goal_required": not paused and not free_day,
        "daily_remaining_minutes": (daily_remaining + 59) // 60,
        "daily_used_minutes_approx": round(daily_seconds / 60, 1),
        "weekly_used_minutes_approx": round(weekly_seconds / 60, 1),
        "weekly_remaining_minutes": (weekly_remaining + 59) // 60,
        "voluntary": optional,
        "blocked_study_paths": blocked_study_paths[-3:],
        "subject_focus": [{"subject": name, "priority": priority, "reason": "Schwerpunkt aus den eingetragenen Schulleistungen"}
                          for name, priority in sorted({item["subject"]: item["_grade_priority"] for item in candidates if item["_grade_priority"]}.items())],
        "can_continue_voluntarily": bool(optional),
        "optional_learning": True,
        "completed_portion_minutes": completed_daily,
        "weekly_portion_minutes": completed_weekly,
        "notices": notices,
        "completed_today": sum(bool(u.completed and u.completed >= start) for u in units),
        "free_day": free_day,
        "paused": paused,
        "forecast_notice": "Vorschlag für sieben Tage: Neue Seiten, Antworten und Elternvorgaben passen ihn an. Zeiten sind Schätzungen; weitere Hilfen und Wiederholungen kommen nach Bedarf hinzu.",
        "notice": "Versäumte Tage vergrößern das Tagesziel nicht. Eltern sehen ausschließlich Aktivitäten innerhalb von SchuleSchlau.",
    }


def capture_status(db, child, current_plan):
    from .school_preparation import preparation_data

    day = db.scalar(
        select(SchoolDay).where(SchoolDay.child_id == child.id, SchoolDay.school_date == current_plan["date"])
    )
    count = db.scalar(select(func.count()).select_from(Material).where(Material.school_day_id == day.id)) if day else 0
    skipped = db.scalar(
        select(Activity.id)
        .where(
            Activity.child_id == child.id,
            Activity.kind == "daily_checkin",
            Activity.detail["date"].as_string() == current_plan["date"],
        )
        .limit(1)
    )
    return {
        "date": current_plan["date"],
        "day_id": day.id if day else None,
        "page_count": count,
        "status": day.stage if count else "skipped" if skipped else "empty",
        "preparation": preparation_data(db, day, child) if day and day.preparation else None,
    }


@router.post("/children/{child_id}/day-check-in")
def no_new_pages(child_id: str, p=Depends(child_user), db=Depends(get_db)):
    child = child_access(db, p, child_id)
    db.execute(update(Child).where(Child.id == child.id).values(grade=Child.grade))
    day = local_day(child).isoformat()
    existing = db.scalar(
        select(Activity.id)
        .where(
            Activity.child_id == child.id, Activity.kind == "daily_checkin", Activity.detail["date"].as_string() == day
        )
        .limit(1)
    )
    if not existing:
        record(db, child.id, "daily_checkin", {"date": day, "new_pages": False})
    db.commit()
    return {"date": day, "status": "skipped"}


@router.get("/children/{child_id}/overview")
def overview(child_id: str, p=Depends(authenticated), db=Depends(get_db), *, compact: bool = False,
             capabilities: str | None = Header(None, alias="X-Schulpilot-Capabilities")):
    from .coaching import paths
    from .learning_progress import read_ledger, subject_evidence, totals

    child = child_access(db, p, child_id)
    from .exams import today_sessions

    include_language = language_supported(capabilities)
    resume_id = feedback_resume_id(db, child.id, include_language=include_language)
    if resume_id:
        from .library import unit_summaries

        feedback_resume = unit_summaries(db, [resume_id])[resume_id] | {"kind": "unit", "pending_feedback": True}
    else:
        feedback_resume = None
    preparing_unit = db.scalar(
        select(Job).options(load_only(Job.id, Job.status))
        .where(Job.child_id == child.id, Job.kind.in_(["unit", "controller_check", "decision"]), Job.status.in_(["queued", "running"]))
        .order_by(Job.created, Job.id).limit(1)
    )
    ledger = read_ledger(db, child.id)
    learning_paths = paths(db, child.id, ledger=ledger)
    subject_progress = subject_evidence(ledger)
    days = list(
        db.scalars(
            select(SchoolDay).where(SchoolDay.child_id == child.id).order_by(SchoolDay.school_date.desc()).limit(30)
        )
    )
    current_plan = plan(db, child, learning_paths=learning_paths, include_language=include_language)
    capture = capture_status(db, child, current_plan)
    from .school_preparation import preparation_data

    preparations = [
        {"day_id": day.id, "date": day.school_date, **preparation_data(db, day, child)}
        for day in db.scalars(
            select(SchoolDay)
            .where(
                SchoolDay.child_id == child.id,
                SchoolDay.preparation["status"]
                .as_string()
                .in_(["processing", "needs_review", "needs_photo", "failed", "blocked"]),
            )
            .order_by(SchoolDay.school_date.desc())
            .limit(3)
        )
    ]
    if compact:
        from .library import MATERIAL_FIELDS, material_summary, unit_summaries

        material_count = db.scalar(select(func.count()).select_from(Material).where(Material.child_id == child.id, Material.purpose != "exam"))
        pending = list(
            db.scalars(
                select(Material)
                .outerjoin(SchoolDay, SchoolDay.id == Material.school_day_id)
                .options(load_only(*MATERIAL_FIELDS))
                .where(
                    Material.child_id == child.id,
                    Material.purpose != "exam",
                    Material.confirmed.is_(False),
                    or_(Material.school_day_id.is_(None), SchoolDay.school_date == current_plan["date"]),
                )
                .order_by(Material.created.desc(), Material.id.desc())
                .limit(24)
            )
        )
        pending_review_ids = list(
            db.scalars(
                select(LearningUnit.id)
                .join(UnitCoaching, UnitCoaching.unit_id == LearningUnit.id)
                .where(
                    LearningUnit.child_id == child.id,
                    LearningUnit.status == "completed",
                    UnitCoaching.status == "pending",
                )
                .order_by(LearningUnit.created.desc(), LearningUnit.id.desc())
                .limit(3)
            )
        )
        unit_previews = list(unit_summaries(db, pending_review_ids).values())
        for preview in unit_previews:
            preview["coaching"] = {"status": preview["review_status"]}
        later = current_plan["later"]
        current_plan = current_plan | {
            "today_count": len(current_plan["today"]),
            "later_count": len(later),
            "today": current_plan["today"][:3],
            "later": [
                item for item in later if not item.get("scheduled_for") or item["scheduled_for"] <= current_plan["date"]
            ][:1],
            "week": [
                day | {"item_count": len(day["items"]), "items": day["items"][:3]} for day in current_plan["week"]
            ],
        }
    else:
        material_count = None
    # Existing plan is authoritative. This small, read-only bridge neither
    # rebuilds a plan nor generates content during login or page navigation.
    from .learning_origins import next_item as select_next

    selected_next = select_next(current_plan)
    next_item = [selected_next] if selected_next else []
    guidance = None
    if next_item and next_item[0]["kind"] == "unit":
        from .learning_controller import projection

        next_unit = db.get(LearningUnit, next_item[0]["id"])
        if next_unit and next_unit.child_id == child.id:
            action = projection(db, next_unit)["action"]
            guidance = {"unit_id": next_unit.id, "title": action["title"], "reason": action["reason"],
                "kind": action["kind"], "subject": next_unit.subject, "topic": next_unit.topic,
                "estimated_minutes": next_item[0]["estimated_minutes"]}
    return {
        "child": child_data(db, child),
        "school_days": [
            {
                "id": d.id,
                "date": d.school_date,
                "stage": d.stage,
                "page_count": len(list(db.scalars(select(Material.id).where(Material.school_day_id == d.id)))),
            }
            for d in days
        ],
        "plan": current_plan,
        "learning_guidance": guidance,
        "next_learning_item": selected_next,
        "daily_capture": capture,
        "feedback_resume": feedback_resume,
        "learning_preparation": {"id": preparing_unit.id, "status": preparing_unit.status} if preparing_unit else None,
        "exam_sessions": today_sessions(db, child) if isinstance(capabilities, str) and "exams-v1" in capabilities.split(",") else [],
        "pending_preparations": preparations,
        "day_summary": summary(db, child, 1, learning_paths=learning_paths),
        "week_summary": summary(db, child, 7, learning_paths=learning_paths),
        "material_count": material_count,
        "materials": [material_summary(m) for m in pending]
        if compact
        else [
            material_data(m)
            for m in db.scalars(select(Material).where(Material.child_id == child.id, Material.purpose != "exam").order_by(Material.created.desc()))
        ],
        "assignments": [
            assignment_data(a)
            for a in db.scalars(
                select(Assignment).where(Assignment.child_id == child.id).order_by(Assignment.created.desc())
            )
        ],
        "units": unit_previews
        if compact
        else [
            unit_data(db, u, include_answers=p.user.role == "parent", include_progress=False)
            for u in db.scalars(
                select(LearningUnit).where(LearningUnit.child_id == child.id,
                    True if include_language else LearningUnit.round_kind != "vocabulary").order_by(LearningUnit.created.desc())
            )
        ],
        "mastery": [
            mastery_data(m)
            for m in db.scalars(select(Mastery).where(Mastery.child_id == child.id).limit(3 if compact else None))
        ],
        "learning_paths": learning_paths[:3] if compact else learning_paths,
        "practice_summary": totals(ledger),
        "subject_progress": subject_progress[:4] if compact else subject_progress,
        "subject_count": len(subject_progress),
        "messages": message_previews(db, child.id),
    }


@router.get("/children/{child_id}/activity")
def activity(child_id: str, before: int | None = None, p=Depends(authenticated), db=Depends(get_db)):
    child_access(db, p, child_id)
    query = select(Activity).where(
        Activity.child_id == child_id, Activity.kind.not_in(["feedback_pending", "feedback_seen", "feedback_exposure"])
    )
    if before:
        query = query.where(Activity.created < before)
    return [
        {"id": a.id, "kind": a.kind, "detail": a.detail, "unit_id": a.unit_id, "created": a.created}
        for a in db.scalars(query.order_by(Activity.created.desc(), Activity.id).limit(200))
    ]


@router.post("/children/{child_id}/assignments", status_code=201)
def add_assignment(child_id: str, data: s.AssignmentCreate, key: str = Header(default="", alias="Idempotency-Key"), p=Depends(parent), db=Depends(get_db)):
    from .parent_insights import fingerprint, lock_parent
    from .parent_plans import assignment_values

    child = lock_parent(db, p, child_id)
    if len(key) > 80:
        raise HTTPException(422, "Anfrageschlüssel ist zu lang.")
    source_key = fingerprint(["parent-topic", p.user.id, key]) if key else None
    request_digest = fingerprint(data.model_dump(mode="json"))
    old = db.scalar(select(Assignment).where(Assignment.source_key == source_key)) if key else None
    if old:
        if old.child_id != child.id or old.request_digest != request_digest:
            raise HTTPException(409, "Dieser Schlüssel gehört zu einem anderen Lernziel.")
        return assignment_data(old)
    a = Assignment(child_id=child.id, **assignment_values(db, child, data), source_key=source_key, request_digest=request_digest)
    db.add(a)
    record(db, child.id, "parent_assignment", {"subject": data.subject, "topic": data.topic, "due": a.due})
    db.commit()
    return assignment_data(a)


@router.put("/children/{child_id}/assignments/{assignment_id}")
def edit_assignment(child_id: str, assignment_id: str, data: s.AssignmentCreate, p=Depends(parent), db=Depends(get_db)):
    from .parent_insights import lock_parent
    from .parent_plans import assignment_values

    child = lock_parent(db, p, child_id)
    a = db.get(Assignment, assignment_id)
    if not a or a.child_id != child_id:
        raise HTTPException(404, "Lernauftrag nicht gefunden.")
    if data.revision is not None and data.revision != a.revision:
        raise HTTPException(409, "Das Lernziel wurde inzwischen geändert. Bitte neu laden.")
    values = assignment_values(db, child, data, a)
    if a.origin_kind is None:
        a.origin_kind = a.kind
    a.source_status = "confirmed"  # a managing parent explicitly reviews it
    if "scheduled_for" not in data.model_fields_set:
        # Older clients cannot see the new start-date field; preserve the
        # binding date unless a managing parent explicitly sends a new value.
        values.pop("scheduled_for")
    for key, value in values.items():
        setattr(a, key, value)
    a.done = False
    a.revision += 1
    record(db, child_id, "assignment_changed", {"topic": a.topic})
    db.commit()
    return assignment_data(a)


@router.delete("/children/{child_id}/assignments/{assignment_id}")
def delete_assignment(child_id: str, assignment_id: str, revision: int | None = Query(None, ge=1),
                      p=Depends(parent), db=Depends(get_db)):
    child_access(db, p, child_id, write=True)
    db.execute(update(Child).where(Child.id == child_id).values(grade=Child.grade))
    a = db.get(Assignment, assignment_id)
    if not a or a.child_id != child_id:
        raise HTTPException(404, "Lernauftrag nicht gefunden.")
    if revision is not None and revision != a.revision:
        raise HTTPException(409, "Dieser Auftrag wurde inzwischen geändert. Lade den Lernplan neu, bevor du ihn entfernst.")
    db.delete(a)
    record(db, child_id, "assignment_removed", {"topic": a.topic})
    db.commit()
    return {"message": "Lernauftrag entfernt."}


@router.post("/children/{child_id}/assignments/{assignment_id}/complete")
def complete_assignment(child_id: str, assignment_id: str, data: s.AssignmentComplete | None = None,
                        p=Depends(parent), db=Depends(get_db)):
    from .parent_insights import lock_parent

    lock_parent(db, p, child_id)
    assignment = db.get(Assignment, assignment_id)
    if not assignment or assignment.child_id != child_id:
        raise HTTPException(404, "Lernauftrag nicht gefunden.")
    if data and data.revision is not None and data.revision != assignment.revision:
        raise HTTPException(409, "Das Lernziel wurde inzwischen geändert. Bitte neu laden.")
    if not assignment.done:
        assignment.done = True
        assignment.revision += 1
        record(db, child_id, "parent_goal_completed", {"topic": assignment.topic})
    db.commit()
    return {"message": "Elternziel als erledigt markiert. Dies ist keine automatische Aussage über die Beherrschung."}


def get_unit(db, p, unit_id, child_only=False, lock=False):
    unit = db.get(LearningUnit, unit_id)
    if not unit:
        raise HTTPException(404, "Lerneinheit nicht gefunden.")
    child_access(db, p, unit.child_id)
    if child_only and p.user.role != "child":
        raise HTTPException(403, "Aufgaben werden mit dem Kinderzugang bearbeitet.")
    if lock:
        db.execute(update(LearningUnit).where(LearningUnit.id == unit.id).values(status=LearningUnit.status))
        db.refresh(unit)
    return unit


@router.get("/units/{unit_id}")
def unit_view(unit_id: str, p=Depends(authenticated), db=Depends(get_db),
              capabilities: str | None = Header(None, alias="X-Schulpilot-Capabilities")):
    unit = get_unit(db, p, unit_id)
    if p.user.role == "child":
        language_capability(unit, capabilities, db)
    value = unit_data(db, unit, p.user.role == "parent")
    can_prepare = not unit.synthetic
    if can_prepare and p.user.role == "parent":
        try:
            child_access(db, p, unit.child_id, write=True)
        except HTTPException as error:
            if error.status_code != 403:
                raise
            can_prepare = False
    value["can_prepare_visual"] = can_prepare
    return value



def readable_unit_source(db, p, unit_id, material_id, revision):
    unit = get_unit(db, p, unit_id)
    ref = db.get(UnitSource, (unit.id, material_id))
    material = db.get(Material, material_id)
    if not ref or not material or material.child_id != unit.child_id:
        raise HTTPException(404, "Diese Heftquelle ist nicht verfügbar.")
    if not material.confirmed or ref.revision != revision or material.revision != revision:
        raise HTTPException(409, "Diese Heftquelle wurde geändert. Bitte lade den aktuellen Rundenstand.")
    return unit, material


@router.get("/units/{unit_id}/sources/{material_id}")
def unit_source_view(unit_id: str, material_id: str, revision: int = Query(ge=1),
                     p=Depends(authenticated), db=Depends(get_db)):
    unit, material = readable_unit_source(db, p, unit_id, material_id, revision)
    return {"unit_id": unit.id, "child_id": unit.child_id, "material_id": material.id,
        "revision": material.revision, "confirmed": True, "title": material.title,
        "content": material.content, "has_image": bool(material.path)}


@router.get("/units/{unit_id}/sources/{material_id}/image")
def unit_source_image(unit_id: str, material_id: str, revision: int = Query(ge=1),
                      p=Depends(authenticated), db=Depends(get_db)):
    from .materials import image

    _, material = readable_unit_source(db, p, unit_id, material_id, revision)
    # Reuse the existing authenticated private-photo response/no-store policy.
    return image(material.id, p, db)


@router.post("/units/{unit_id}/start")
def start(unit_id: str, p=Depends(child_user), db=Depends(get_db),
          capabilities: str | None = Header(None, alias="X-Schulpilot-Capabilities")):
    unit = get_unit(db, p, unit_id, True, True)
    language_capability(unit, capabilities, db)
    if unit.status == "completed":
        return unit_data(db, unit)
    if reason := learning_block(db, unit):
        raise HTTPException(409, reason)
    if recover_instructional_round(db, unit):
        db.commit()
        schedule_completed_review(db, unit)
        return unit_data(db, unit)
    if unit.status == "active":
        return unit_data(db, unit)
    child = db.get(Child, unit.child_id)
    assignment = db.get(Assignment, unit.assignment_id) if unit.assignment_id else None
    if assignment and assignment.scheduled_for and assignment.scheduled_for > local_day(child).isoformat():
        raise HTTPException(
            409, f"Dieser Lernauftrag beginnt am {assignment.scheduled_for}. Deine Eltern können ihn neu planen."
        )
    prefs = s.Preferences(**child.preferences)
    if unit.break_until:
        unit.segment_seconds = 0
        unit.break_until = None
    elif unit.heartbeat and now() - unit.heartbeat >= prefs.break_minutes * 60:
        unit.segment_seconds = 0
    unit.status = "active"
    unit.heartbeat = int(now())
    record(db, unit.child_id, "unit_started", {"topic": unit.topic}, unit.id)
    from .adaptive_plan import CAPABILITY
    from .db import LearningMemory

    if CAPABILITY in (capabilities.split(",") if isinstance(capabilities, str) else []):
        memory = db.get(LearningMemory, unit.id)
        memory.working = {**memory.working, "controller_version": 2}
    db.commit()
    return unit_data(db, unit)


@router.post("/units/{unit_id}/pause")
def pause(unit_id: str, p=Depends(child_user), db=Depends(get_db)):
    unit = get_unit(db, p, unit_id, True, True)
    if unit.status == "active":
        unit.status = "paused"
        unit.heartbeat = int(now())
        record(db, unit.child_id, "unit_paused", unit_id=unit.id)
        db.commit()
    return unit_data(db, unit)


@router.post("/units/{unit_id}/heartbeat")
def heartbeat(unit_id: str, data: s.HeartbeatRequest | None = None, p=Depends(child_user), db=Depends(get_db)):
    unit = get_unit(db, p, unit_id, True, True)
    # Serialize activity across this child's devices/units. Two open exercises
    # must never earn two minutes in the same minute of wall-clock time.
    db.execute(update(Child).where(Child.id == unit.child_id).values(grade=Child.grade))
    prefs = s.Preferences(**db.get(Child, unit.child_id).preferences)
    stamp = int(now())
    if unit.status == "active":
        if learning_block(db, unit):
            unit.status = "paused"
            unit.heartbeat = None
            record(db, unit.child_id, "plan_paused", unit_id=unit.id)
            db.commit()
            return {
                "active_seconds_approx": unit.active_seconds,
                "learning_time": learning_time(db, db.get(Child, unit.child_id)),
                "status": unit.status,
                "break_until": unit.break_until,
                **break_recommendation(db, unit),
            }
        elapsed = stamp - (unit.heartbeat or stamp)
        if elapsed >= prefs.break_minutes * 60:
            unit.segment_seconds = 0
        if 0 < elapsed <= 45 and not (data and data.baseline):
            last_credit = db.scalar(
                select(func.max(Activity.created)).where(
                    Activity.child_id == unit.child_id,
                    Activity.kind == "active_time",
                    Activity.created >= stamp - 45,
                )
            )
            seconds = min(elapsed, 25, max(0, stamp - last_credit) if last_credit is not None else 25)
            unit.active_seconds += seconds
            unit.segment_seconds += seconds
            if seconds:
                db.add(
                    Activity(
                        child_id=unit.child_id,
                        unit_id=unit.id,
                        kind="active_time",
                        detail={"seconds": seconds},
                        created=stamp,
                    )
                )
        unit.heartbeat = stamp
        unit.break_until = None
        db.commit()
    return {
        "active_seconds_approx": unit.active_seconds,
        "learning_time": learning_time(db, db.get(Child, unit.child_id)),
        "status": unit.status,
        "break_until": unit.break_until,
        **break_recommendation(db, unit),
    }


@router.post("/units/{unit_id}/explanation")
def explanation(unit_id: str, data: s.ExplanationRequest | None = None, p=Depends(child_user), db=Depends(get_db)):
    unit = get_unit(db, p, unit_id, True, True)
    rate_limit(db, "explain:" + p.user.id, 30)
    q = question(unit, data.question_id) if data else None
    text = q["explanation"] if q else unit.explanation
    record(db, unit.child_id, "explanation", {"text": text, **({"question_id": q["id"]} if q else {})}, unit.id)
    db.commit()
    from .subject_content import legacy_presentation, public_presentation
    from .visual_references import projection as visual_projection
    from .visual_references import question_projection

    visual_state = visual_projection(db, unit)
    return {"explanation": text, "question_id": q["id"] if q else None,
            "explanation_visual_status": visual_state["explanation_visual_status"],
            "explanation_visual_reason": visual_state["explanation_visual_reason"],
            # This explicit action opens the full saved explanation. A model
            # may have placed its sole graphic at a hint stage rather than at
            # solution; do not return the text while filtering that graphic.
            "explanation_steps": question_projection(db, unit, q, closed=True, hints=3) if q else visual_projection(db, unit)["explanation_steps"],
            "presentation": public_presentation(q.get("presentation") or legacy_presentation(q, unit_source_texts(db, unit)), closed=True) if q else None}


@router.post("/units/{unit_id}/introduction")
def introduction(unit_id: str, p=Depends(child_user), db=Depends(get_db)):
    unit = get_unit(db, p, unit_id, True, True)
    if unit.status != "active":
        raise HTTPException(409, "Bitte die Einheit zuerst starten oder fortsetzen.")
    if not unit.introduction_seen:
        unit.introduction_seen = True
        record(db, unit.child_id, "introduction_read", unit_id=unit.id)
        db.commit()
    return unit_data(db, unit)


def question(unit, question_id):
    q = next((q for q in unit.questions if q["id"] == question_id), None)
    if not q:
        raise HTTPException(404, "Aufgabe nicht gefunden.")
    return q


@router.post("/units/{unit_id}/questions/{question_id}/hint")
def hint(unit_id: str, question_id: str, p=Depends(child_user), db=Depends(get_db),
         idempotency_key: str | None = Header(None, alias="Idempotency-Key", min_length=16, max_length=80, pattern=r"^[A-Za-z0-9_-]+$")):
    unit = get_unit(db, p, unit_id, True, True)
    q = question(unit, question_id)
    saved = list(db.scalars(select(Activity).where(Activity.unit_id == unit.id, Activity.kind == "hint")))
    if idempotency_key:
        replay = next((event for event in saved if event.detail.get("request_key") == idempotency_key), None)
        if replay:
            if replay.detail.get("question_id") != question_id:
                raise HTTPException(409, "Dieser Hinweisschlüssel gehört zu einer anderen Aufgabe.")
            return {"hint": replay.detail["text"], "hints_used": replay.detail["number"],
                    "exhausted": replay.detail["number"] >= 3,
                    "presentation": hint_presentation(q, replay.detail["number"])}
    if unit.status not in ("active", "paused"):
        raise HTTPException(409, "Diese Runde ist abgeschlossen. Du kannst die gespeicherte Erklärung im Rückblick lesen.")
    previous = db.scalar(select(Attempt).where(Attempt.unit_id == unit.id, Attempt.question_id == question_id)
                         .order_by(Attempt.created.desc(), Attempt.id.desc()).limit(1))
    if previous and previous.outcome in ("correct", "uncertain"):
        raise HTTPException(409, "Diese Antwort ist gespeichert. Öffne die Erklärung oder kläre die offene Prüfung mit der Lernhilfe.")
    count = len(list(db.scalars(select(Activity.id).where(Activity.unit_id == unit.id, Activity.kind == "hint"))))
    shown = [
            e
            for e in db.scalars(select(Activity).where(Activity.unit_id == unit.id, Activity.kind == "hint"))
            if e.detail.get("question_id") == question_id
        ]
    if count >= len(unit.questions) * 3 or len(shown) >= 3:
        raise HTTPException(409, "Die Hinweise sind gelesen. Öffne die Erklärung und versuche den gezeigten Schritt; danach geht es mit einer passenden Runde weiter.")
    from .learning_hints import next_hint

    text = next_hint(q, previous.answer if previous else None, [e.detail.get("text") for e in shown])
    if text is None:
        raise HTTPException(409, "Öffne die Erklärung für einen gemeinsam gelösten Schritt.")
    record(db, unit.child_id, "hint", {"question_id": question_id, "text": text,
                                     "number": len(shown)+1, "request_key": idempotency_key}, unit.id)
    db.commit()
    return {"hint": text, "hints_used": len(shown)+1, "exhausted": len(shown)+1 >= 3,
            "presentation": hint_presentation(q, len(shown)+1)}


def hint_presentation(q, count):
    from .subject_content import legacy_presentation, public_presentation

    private = q.get("presentation") or legacy_presentation(q)
    if private and not q.get("presentation") and count:
        private["blocks"].append({**private["blocks"][0], "disclosure": "hint1",
                                  "title": "Das Dreieck ist die Hälfte des Rechtecks"})
    return public_presentation(private, hints=count)


def normalized(text):
    from .answer_evaluation import normalized as normalize_answer

    return normalize_answer(text)


def evaluate(q, answer):
    from .answer_evaluation import evaluate as assess

    return assess(q, answer)["outcome"]


def learning_block(db, unit):
    from .legacy_learning_content import issue as content_issue

    if problem := content_issue(unit):
        return problem["message"]
    if unit.round_kind == "vocabulary":
        from .vocabulary import current_sources

        try:
            snapshots = {source["id"]: source for q in unit.questions
                         for source in (q.get("language") or {}).get("source_revisions", [])}
            for row in db.scalars(select(UnitSource).where(UnitSource.unit_id == unit.id)):
                snapshots[row.material_id] = {"id": row.material_id, "revision": row.revision}
            current_sources(db, unit.child_id, list(snapshots.values()))
        except HTTPException as error:
            return error.detail
        if unit.status == "not_started":
            from .db import VocabularyItem

            for q in unit.questions:
                meta = q.get("language") or {}
                item = db.get(VocabularyItem, meta.get("vocabulary_item_id"))
                if not item or not item.confirmed or item.revision != meta.get("vocabulary_revision"):
                    return "Ein Wort wurde korrigiert. Bitte eine neue Runde aus den bestätigten Wörtern beginnen."
        return None
    from .learning_controller import source_state

    if not source_state(db, unit)[1]:
        return "Der Lernstoff wurde geändert. Deine bisherigen Antworten bleiben gespeichert. Prüfe zuerst die aktuelle Heftseite oder den Lernauftrag."
    child = db.get(Child, unit.child_id)
    today = local_day(child)
    if unit.not_before and unit.not_before > today.isoformat():
        return f"Diese spätere Abrufprobe beginnt frühestens am {unit.not_before}."
    from .coaching import continuation_block

    if reason := continuation_block(db, unit, child, check_sources=False):
        return reason
    if any(q.get("presentation") for q in unit.questions):
        try:
            from .coaching import context

            context(db, unit)
        except Exception:
            return "Eine Heftseite wurde geändert. Bitte zuerst den aktuellen Lernstoff prüfen."
    if unit.round_kind in ("study_block", "study_recall"):
        from .coaching import context
        from .study_path import block_reason

        try:
            context(db, unit)
        except Exception:
            return "Eine Heftseite wurde geändert. Bitte die aktuelle Lernreise öffnen."
        if reason := block_reason(db, child, unit.subject, unit_id=unit.id, question_count=len(unit.questions)):
            return reason
    if unit.learning_root_id or unit.followup_of:
        from .coaching import continuation_block

        if reason := continuation_block(db, unit, child):
            return reason
    assignment = db.get(Assignment, unit.assignment_id) if unit.assignment_id else None
    if assignment and assignment.source_status != "confirmed":
        return "Die Heftseite dieses Auftrags wurde geändert. Bitte zuerst den aktuellen Auftrag prüfen."
    if assignment and assignment.scheduled_for and assignment.scheduled_for > today.isoformat():
        return f"Dieser Lernauftrag beginnt am {assignment.scheduled_for}. Deine Eltern können ihn neu planen."
    return None


def update_mastery(db, unit, attempts):
    child = db.get(Child, unit.child_id)
    today = local_day(child)
    mastery = db.scalar(
        select(Mastery).where(
            Mastery.child_id == unit.child_id, Mastery.subject == unit.subject, Mastery.topic == unit.topic
        )
    )
    if not mastery:
        mastery = Mastery(
            child_id=unit.child_id,
            subject=unit.subject,
            topic=unit.topic,
            next_review=(today + timedelta(days=1)).isoformat(),
            last_practiced=today.isoformat(),
            independent=0,
            assisted=0,
            difficulties=0,
            uncertain_units=0,
            review_successes=0,
        )
        db.add(mastery)
    final = [next(a for a in reversed(attempts) if a.question_id == q["id"]) for q in unit.questions]
    independent = all(a.outcome == "correct" and not a.assisted for a in final)
    if independent:
        mastery.independent += 1
        if unit.review_of and mastery.last_practiced < today.isoformat():
            mastery.review_successes += 1
        interval = min(14, 2 ** min(mastery.review_successes, 3))
    elif all(a.outcome == "correct" for a in final) and any((a.evaluation or {}).get("independence_uncertain") for a in final):
        mastery.uncertain_units += 1
        interval = 1
    elif all(a.outcome == "correct" for a in final):
        mastery.assisted += 1
        interval = 1
    elif any(a.outcome == "incorrect" for a in final):
        mastery.difficulties += 1
        interval = 1
    else:
        mastery.uncertain_units += 1
        interval = 1
    mastery.next_review = (today + timedelta(days=interval)).isoformat()
    mastery.last_practiced = today.isoformat()


def completion_ready(db, unit, attempts=None):
    from . import adaptive_plan, instructional_decisions

    if unit.status not in ("active", "paused") or not unit.questions:
        return False
    attempts = attempts if attempts is not None else list(db.scalars(select(Attempt).where(Attempt.unit_id == unit.id)))
    deferred = adaptive_plan.deferred(db, unit) | instructional_decisions.deferred(db, unit)
    active_flow = adaptive_plan.flow(db, unit)
    flow_pending = active_flow and active_flow["phase"] not in ("offer_probe", "closed")
    return not flow_pending and not instructional_decisions.current(db, unit) and all(
        q["id"] in deferred
        or any(a.question_id == q["id"] and a.outcome in ("correct", "uncertain") for a in attempts)
        or sum(a.question_id == q["id"] for a in attempts) >= 3
        for q in unit.questions
    )


def complete_round(db, unit, attempts=None):
    """Close saved work under the existing unit→child lock order, without an answer."""
    from . import instructional_decisions
    from .subject_content import open_learning_unit

    if not completion_ready(db, unit, attempts):
        return False
    db.execute(update(Child).where(Child.id == unit.child_id).values(grade=Child.grade))
    if learning_block(db, unit):
        return False
    attempts = attempts if attempts is not None else list(db.scalars(select(Attempt).where(Attempt.unit_id == unit.id).order_by(Attempt.created, Attempt.id)))
    instructional_decisions.persist_deferred(db, unit, instructional_decisions.deferred(db, unit))
    unit.status, unit.completed, unit.heartbeat = "completed", int(now()), None
    if unit.round_kind != "vocabulary" and not open_learning_unit(unit):
        update_mastery(db, unit, attempts)
    record(db, unit.child_id, "unit_completed", {"topic": unit.topic}, unit.id)
    return True


def recover_instructional_round(db, unit):
    """Only a conscious POST reconciles a previously exhausted saved plan."""
    from . import instructional_decisions
    from .learning_controller import source_state

    if not source_state(db, unit)[1] or not instructional_decisions.deferred(db, unit):
        return False
    attempts = list(db.scalars(select(Attempt).where(Attempt.unit_id == unit.id).order_by(Attempt.created, Attempt.id)))
    events = list(db.scalars(select(Activity).where(Activity.unit_id == unit.id)))
    if pending_feedback(unit, attempts, events):
        return False
    return complete_round(db, unit, attempts)


def schedule_completed_review(db, unit):
    if unit.round_kind != "vocabulary":
        from .coaching import schedule

        schedule(unit.id, automatic=True)
        db.expire_all()


@router.post("/units/{unit_id}/questions/{question_id}/answer")
def answer(unit_id: str, question_id: str, data: s.AnswerRequest, p=Depends(child_user), db=Depends(get_db),
           capabilities: str | None = Header(None, alias="X-Schulpilot-Capabilities")):
    unit = get_unit(db, p, unit_id, True, True)
    language_capability(unit, capabilities, db)
    q = question(unit, question_id)
    if q.get("type") == "grouped":
        from .grouped_questions import canonical, parse_answer

        try:
            data.answer = canonical(parse_answer(q["field_group"], data.answer))
        except ValueError as error:
            raise HTTPException(422, str(error)) from None
    from .vocabulary import fingerprint

    request_digest = fingerprint([question_id, data.answer, data.input_method, data.guided_feedback])
    if data.request_id:
        saved = db.scalar(select(Attempt).where(Attempt.unit_id == unit.id, Attempt.request_key == data.request_id))
        if saved:
            if saved.request_digest != request_digest:
                raise HTTPException(409, "Dieser Antwortschlüssel gehört zu einer anderen Antwort.")
            return answer_response(db, unit, question(unit, question_id), saved)
    if unit.status != "active":
        raise HTTPException(409, "Bitte die Lerneinheit zuerst starten oder fortsetzen.")
    if reason := learning_block(db, unit):
        raise HTTPException(409, reason)
    from . import adaptive_plan
    from .db import LearningMemory

    if adaptive_plan.CAPABILITY in (capabilities.split(",") if isinstance(capabilities, str) else []):
        memory = db.get(LearningMemory, unit.id)
        if memory:
            memory.working = {**memory.working, "controller_version": 2}
    active_question = adaptive_plan.current_question(db, unit)
    active_flow = adaptive_plan.flow(db, unit)
    from .instructional_decisions import current as current_instructional_step

    model_step = current_instructional_step(db, unit)
    if model_step:
        step = model_step[1]
        if step["kind"] not in ("practice", "check_understanding"):
            raise HTTPException(409, "Öffne zuerst den gespeicherten Lernschritt und gehe dann weiter.")
        active_question = step["question_id"]
    if active_question and active_question != question_id:
        raise HTTPException(409, "Dieser Lernschritt wurde geändert. Bitte lade die aktuelle Aufgabe.")
    if not model_step and active_flow and active_flow["phase"] in ("explanation", "change_support"):
        raise HTTPException(409, "Schau zuerst die Erklärung an und starte dann bewusst die nächste Aufgabe.")
    if q.get("language") and not data.request_id:
        raise HTTPException(422, "Für Sprachantworten wird ein eindeutiger Antwortschlüssel benötigt. Bitte die App aktualisieren.")
    existing = list(db.scalars(select(Attempt).where(Attempt.unit_id == unit.id).order_by(Attempt.created, Attempt.id)))
    if data.guided_feedback:
        events = list(db.scalars(select(Activity).where(Activity.unit_id == unit.id)))
        if pending_feedback(unit, existing, events):
            raise HTTPException(409, "Lies zuerst die Rückmeldung und tippe auf Weiter.")
    previous = [a for a in existing if a.question_id == question_id]
    if previous and (previous[-1].outcome in ("correct", "uncertain") or len(previous) >= 3):
        raise HTTPException(409, "Diese Aufgabe wurde bereits abgeschlossen.")
    # Live parent support is an actual aid, including when the child opened a
    # different exercise during the call. Earlier answers remain untouched.
    from .family_calls import record_answer_help

    record_answer_help(db, p, unit)
    explanation_events = list(db.scalars(select(Activity).where(Activity.unit_id == unit.id,
        Activity.kind.in_(("explanation", "feedback_exposure")))))
    explained = bool(
        any(e.kind == "explanation" and (not e.detail.get("question_id") or e.detail.get("question_id") == question_id)
            for e in explanation_events)
    )
    prior_solution = prior_explanation_reveals_answer(db, unit, q, explanation_events)
    intro_events = list(db.scalars(select(Activity).where(Activity.unit_id == unit.id, Activity.kind == "introduction_read")))
    intro_solution = introduction_reveals_answer(db, unit, q, intro_events, user_id=p.user.id)
    # An absent literal match cannot rule out a paraphrase or diagram having
    # revealed an answer. Only explanations actually opened here count.
    prior_explanation = any(
        isinstance(e.detail, dict) and e.detail.get("question_id")
        and e.detail.get("question_id") != question_id
        for e in explanation_events
    )
    had_hint = any(
        e.detail.get("question_id") == question_id
        for e in db.scalars(select(Activity).where(Activity.unit_id == unit.id, Activity.kind == "hint"))
    )
    hinted = explained or had_hint or prior_solution or intro_solution
    from .answer_evaluation import evaluate as assess

    evaluation = assess(q, data.answer)
    outcome = evaluation["outcome"]
    if q["type"] == "match":
        from .learning_hints import match_parts

        evaluation["parts"] = match_parts(q, data.answer)
        right = sum(p["outcome"] == "correct" for p in evaluation["parts"])
        evaluation["reason"] = f"{right} von {len(evaluation['parts'])} Zuordnungen passen. Richtige Paare bleiben erhalten."
    if q.get("language"):
        from .language_evaluation import evaluate as evaluate_language
        from .vocabulary_review import recent_exposure

        # Sources can change while waiting for the common child lock. Recheck
        # after it, before storing any language answer or review event.
        db.execute(update(Child).where(Child.id == unit.child_id).values(grade=Child.grade))
        if reason := learning_block(db, unit):
            raise HTTPException(409, reason)
        evaluation = evaluate_language(q, data.answer)
        exposed = recent_exposure(db, unit, q)
        hinted = hinted or exposed or data.input_method == "speech"
        evaluation.update(skill=q["language"]["skill"], direction=q["language"]["direction"],
                          input_method=data.input_method, independent_attempt=not bool(hinted or previous),
                          independent_evidence=outcome == "correct" and not bool(hinted or previous))
        evaluation["support_reasons"] = (["recent_solution"] if exposed else []) + (["speech_transcript"] if data.input_method == "speech" else [])
        if q["language"]["skill"] == "listening":
            heard = any(e.detail.get("question_id") == question_id and e.detail.get("kind") == "listen"
                        for e in db.scalars(select(Activity).where(Activity.unit_id == unit.id, Activity.kind == "language_stimulus")))
            if not heard:
                raise HTTPException(409, "Bitte zuerst den Hörtext abspielen. Ohne Audio ist das keine Hörübung.")
    # Keep the answer verdict distinct from uncertainty about independence.
    # Conservatively set assisted for legacy evidence consumers as well.
    from .learning_disclosures import independent_example

    independence_uncertain = bool(outcome == "correct" and prior_explanation and not prior_solution
                                  and not hinted and not previous
                                  and not independent_example(unit, q, explanation_events))
    hinted = hinted or independence_uncertain
    evaluation.update(attempt_number=len(previous) + 1,
                      independent_attempt=not bool(hinted or previous),
                      independent_evidence=outcome == "correct" and not bool(hinted or previous),
                      independence_uncertain=independence_uncertain)
    evaluation["support_reasons"] = list(dict.fromkeys([
        *evaluation.get("support_reasons", []),
        *(["hint"] if had_hint else []), *(["explanation"] if explained else []),
        *(["recent_solution"] if prior_solution else []),
        *(["intro_solution"] if intro_solution else []),
        *(["possible_prior_solution"] if independence_uncertain else []),
        *(["another_attempt"] if previous else []),
    ]))
    attempt = Attempt(
        unit_id=unit.id, question_id=question_id, answer=data.answer, outcome=outcome, assisted=bool(hinted or previous),
        request_key=data.request_id, request_digest=request_digest if data.request_id else None,
        evaluation=evaluation, input_method=data.input_method,
    )
    db.add(attempt)
    db.flush()
    from .learning_controller import source_state

    adaptive_plan.answer_recorded(db, unit, q, attempt, source_state(db, unit)[2])
    from .instructional_decisions import answered as advance_instructional_plan

    advance_instructional_plan(db, unit, attempt)
    if q.get("language"):
        from .vocabulary_review import record_review

        record_review(db, unit, q, attempt)
        if outcome in ("correct", "uncertain") or len(previous) >= 2:
            record(db, unit.child_id, "vocabulary_exposure", {"item_id": q["language"]["vocabulary_item_id"],
                   "revision": q["language"]["vocabulary_revision"], "via": "answer_feedback"}, unit.id)
    if data.guided_feedback:
        record(db, unit.child_id, "feedback_pending", {"attempt_id": attempt.id}, unit.id)
    record(db, unit.child_id, "answer", {"question_id": question_id, "outcome": outcome}, unit.id)
    attempts = [*existing, attempt]
    done = complete_round(db, unit, attempts)
    db.commit()
    if done:
        schedule_completed_review(db, unit)
        unit = db.get(LearningUnit, unit_id)
    return answer_response(db, unit, q, attempt)


def answer_response(db, unit, q, attempt):
    outcome = attempt.outcome
    count = db.scalar(select(func.count()).select_from(Attempt).where(Attempt.unit_id == unit.id, Attempt.question_id == q["id"]))
    text = {
        "correct": "Gut gelöst. Wiederholen hilft dir, das Wissen zu festigen.",
        "incorrect": "Das passt noch nicht. Schau dir den Hinweis an und versuche es noch einmal.",
        "uncertain": "Deine Antwort ist gespeichert. Die Prüfung ist noch offen – das bedeutet nicht, dass sie falsch ist.",
    }[outcome]
    return {
        "outcome": outcome,
        "assisted": attempt.assisted,
        "attempt_id": attempt.id,
        "evaluation": attempt.evaluation,
        "can_clarify": outcome == "uncertain" and count < 3,
        "feedback": text,
        "explanation": q["explanation"] if outcome != "incorrect" or count >= 3 else None,
        "unit": unit_data(db, unit),
    }


@router.post("/units/{unit_id}/questions/{question_id}/recheck")
def recheck_answer(unit_id: str, question_id: str, p=Depends(child_user), db=Depends(get_db)):
    from .assessments import recheck

    unit = get_unit(db, p, unit_id, True, True)
    rate_limit(db, "answer-recheck:" + p.user.id, 12, 60, commit=False)
    attempt = recheck(db, unit, question(unit, question_id), p.user.id)
    db.commit()
    return answer_response(db, unit, question(unit, question_id), attempt)


def record_feedback_exposure(db, unit, attempt, surface):
    """Idempotent display marker under the existing unit lock, without text."""
    events = db.scalars(select(Activity).where(Activity.unit_id == unit.id,
        Activity.child_id == unit.child_id, Activity.kind == "feedback_exposure"))
    if not any(e.detail.get("attempt_id") == attempt.id and e.detail.get("surface") == surface for e in events):
        db.add(Activity(child_id=unit.child_id, unit_id=unit.id, kind="feedback_exposure",
                        detail={"attempt_id": attempt.id, "question_id": attempt.question_id, "surface": surface}))


@router.post("/units/{unit_id}/questions/{question_id}/feedback-exposure")
def open_feedback_explanation(unit_id: str, question_id: str, data: s.FeedbackAcknowledgement,
                              p=Depends(child_user), db=Depends(get_db)):
    """Record before showing expandable text, never create a learning attempt."""
    unit = get_unit(db, p, unit_id, True, True)
    question(unit, question_id)
    attempt = db.get(Attempt, data.attempt_id)
    if not attempt or attempt.unit_id != unit.id or attempt.question_id != question_id:
        raise HTTPException(404, "Rückmeldung nicht gefunden.")
    attempts = list(db.scalars(select(Attempt).where(Attempt.unit_id == unit.id).order_by(Attempt.created, Attempt.id)))
    events = list(db.scalars(select(Activity).where(Activity.unit_id == unit.id)))
    pending = pending_feedback(unit, attempts, events)
    if attempt.outcome != "correct" or not pending or pending["attempt_id"] != attempt.id:
        raise HTTPException(409, "Die Rückmeldung hat sich geändert. Bitte die Runde neu laden.")
    record_feedback_exposure(db, unit, attempt, "text")
    db.commit()
    return {"recorded": True}


@router.post("/units/{unit_id}/feedback/acknowledge")
def acknowledge_feedback(
    unit_id: str, data: s.FeedbackAcknowledgement, p=Depends(child_user), db=Depends(get_db)
):
    unit = get_unit(db, p, unit_id, True, True)
    attempt = db.get(Attempt, data.attempt_id)
    if not attempt or attempt.unit_id != unit.id:
        raise HTTPException(404, "Rückmeldung nicht gefunden.")
    events = list(db.scalars(select(Activity).where(Activity.unit_id == unit.id)))
    if any(e.kind == "feedback_seen" and e.detail.get("attempt_id") == attempt.id for e in events):
        if recover_instructional_round(db, unit):
            db.commit()
            schedule_completed_review(db, unit)
        return unit_data(db, unit)
    attempts = list(db.scalars(select(Attempt).where(Attempt.unit_id == unit.id).order_by(Attempt.created, Attempt.id)))
    pending = pending_feedback(unit, attempts, events)
    if not pending or pending["attempt_id"] != attempt.id:
        raise HTTPException(409, "Die Rückmeldung hat sich geändert. Bitte die Runde neu laden.")
    q = question(unit, attempt.question_id)
    from .subject_content import legacy_presentation, public_presentation

    closed = attempt.outcome in ("correct", "uncertain") or sum(a.question_id == attempt.question_id for a in attempts) >= 3
    shown = public_presentation(q.get("presentation") or legacy_presentation(q, unit_source_texts(db, unit)), closed=closed)
    if shown and any(block.get("disclosure") == "solution" for block in shown.get("blocks", [])):
        record_feedback_exposure(db, unit, attempt, "visual")
    # Incorrect/uncertain closed feedback is displayed without an expansion.
    if attempt.outcome != "correct" and pending.get("explanation"):
        record_feedback_exposure(db, unit, attempt, "text")
    record(db, unit.child_id, "feedback_seen", {"attempt_id": attempt.id}, unit.id)
    recovered = recover_instructional_round(db, unit)
    db.commit()
    if recovered:
        schedule_completed_review(db, unit)
    return unit_data(db, unit)


@router.post("/units/{unit_id}/feedback")
def feedback(unit_id: str, data: s.FeedbackRequest, p=Depends(child_user), db=Depends(get_db)):
    unit = get_unit(db, p, unit_id, True, True)
    rate_limit(db, "feedback:" + p.user.id, 10, commit=False)
    if data.question_id:
        question(unit, data.question_id)
    record(db, unit.child_id, "feedback", {"kind": data.kind, "question_id": data.question_id}, unit.id)
    db.commit()
    return {
        "message": "Deine Rückmeldung wurde gespeichert und wird bei der nächsten Einheit berücksichtigt. Das Lernziel bleibt erhalten."
    }


@router.post("/children/{child_id}/messages", status_code=201)
def send_message(child_id: str, data: s.MessageRequest, p=Depends(authenticated), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=p.user.role == "parent")
    if (p.user.role == "child" and data.kind == "reply") or (p.user.role == "parent" and data.kind != "reply"):
        raise HTTPException(403, "Nachrichtentyp für diesen Zugang nicht erlaubt.")
    context = {key: getattr(data, key) for key in ("unit_id", "material_id", "day_id") if getattr(data, key)}
    if len(context) > 1:
        raise HTTPException(422, "Bitte nur eine Aufgabe oder Heftseite für das Anliegen auswählen.")
    db.execute(update(Child).where(Child.id == child.id).values(grade=Child.grade))
    # Check permissions again after waiting for another mutation of this child.
    child_access(db, p, child_id, write=p.user.role == "parent")
    message_id = digest("family-message-v1:" + p.user.id + ":" + child.id + ":" + data.request_key)[:32] if data.request_key else None
    if message_id:
        existing = db.get(Message, message_id)
        if existing:
            if existing.child_id != child.id or existing.sender_id != p.user.id or existing.kind != data.kind or existing.body != data.body or (existing.context or {}) != context:
                raise HTTPException(409, "Dieser Sendeschlüssel gehört zu einer anderen Nachricht. Bitte den ursprünglichen Vorgang zuerst prüfen.")
            return {"id": existing.id, "message": "Nachricht innerhalb deiner Familie gespeichert."}
    rate_limit(db, "message:" + p.user.id, 10, 600, commit=False)
    for key, value in context.items():
        model = {"unit_id": LearningUnit, "material_id": Material, "day_id": SchoolDay}[key]
        target = db.get(model, value)
        if not target or target.child_id != child_id:
            raise HTTPException(404, "Der Bezug dieses Anliegens ist nicht verfügbar.")
    message = Message(**({"id": message_id} if message_id else {}), child_id=child_id, sender_id=p.user.id, kind=data.kind, body=data.body, context=context or None)
    db.add(message)
    record(db, child_id, "message", {"kind": data.kind})
    db.commit()
    return {"id": message.id, "message": "Nachricht innerhalb deiner Familie gespeichert."}


@router.post("/children/{child_id}/messages/{message_id}/resolve")
def resolve(child_id: str, message_id: str, p=Depends(parent), db=Depends(get_db)):
    child_access(db, p, child_id, write=True)
    message = db.get(Message, message_id)
    if not message or message.child_id != child_id:
        raise HTTPException(404, "Nachricht nicht gefunden.")
    message.resolved = True
    db.commit()
    return {"message": "Anliegen als besprochen markiert."}


@router.get("/child/home")
def child_home(p=Depends(child_user), db=Depends(get_db),
               capabilities: str | None = Header(None, alias="X-Schulpilot-Capabilities")):
    child = own_child(db, p)
    return overview(child.id, p, db, capabilities=capabilities)
