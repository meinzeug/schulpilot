"""Event-driven school learning controller, without an always-on model process.

Observations refer to existing attempts/activities. Decisions are versioned
product rules, not diagnoses. Reading a projection never writes learning data.
"""

import re
from fractions import Fraction
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import Field
from sqlalchemy import select

from .catalog_import import fingerprint
from .db import (
    Activity,
    Assignment,
    Attempt,
    Child,
    Job,
    LearningEvent,
    LearningMemory,
    LearningUnit,
    Material,
    UnitSource,
    get_db,
    now,
)
from .schemas import Strict
from .security import authenticated, child_user, rate_limit

router = APIRouter(tags=["Lernbegleitung"])
STRATEGY = "school-controller-2"
ActionKind = Literal["check_prior", "explain", "visual_example", "practice", "hint", "check_understanding",
    "recommend_resource", "review_prerequisite", "transfer", "schedule_review", "finish_round", "offer_break",
    "clarify_assessment", "confirm_source", "resume"]
EVENTS = {"unit_started", "unit_paused", "answer", "hint", "explanation", "introduction", "unit_completed",
    "feedback", "feedback_seen", "review_scheduled", "coach_review", "coach_support", "language_stimulus", "question_skipped"}


class Action(Strict):
    version: Literal[1] = 1
    kind: ActionKind
    phase: Literal["entry", "prior_knowledge", "understand", "practice", "help", "media_return", "review", "finish"]
    learning_goal_id: str | None = None
    question_id: str | None = None
    evidence_refs: list[str] = Field(default_factory=list, max_length=80)
    reason_code: str = Field(max_length=60)
    reason: str = Field(max_length=600)
    title: str = Field(max_length=160)
    expected_result: str = Field(max_length=250)
    on_success: ActionKind
    on_error: ActionKind
    resources: list[dict] = Field(default_factory=list, max_length=3)
    prerequisites: list[dict] = Field(default_factory=list, max_length=5)
    model_needed: bool = False
    strategy_version: str = STRATEGY


class ActionProposal(Strict):
    """Advisory output in the existing reserved coach call, never commands."""
    kind: Literal["explain", "visual_example", "review_prerequisite", "check_understanding",
        "recommend_resource", "transfer", "schedule_review", "finish_round", "clarify_assessment"]
    learning_goal_id: str | None
    question_ids: list[str] = Field(min_length=1, max_length=8)
    reason: str = Field(min_length=1, max_length=240)
    expected_result: str = Field(min_length=1, max_length=160)
    on_success: Literal["practice", "transfer", "schedule_review", "finish_round"]
    on_error: Literal["hint", "visual_example", "review_prerequisite", "clarify_assessment"]


def proposal_model(base):
    from pydantic import create_model

    return create_model("Controller" + base.__name__, __base__=base, next_step=(ActionProposal, ...))


def checked_proposal(value, payload):
    proposal = ActionProposal.model_validate(value).model_dump()
    ids = {q["question_id"] for q in payload["completed_questions"]}
    goals = {g["id"] for g in payload.get("learning_goals", [])}
    if (not set(proposal["question_ids"]) <= ids or len(set(proposal["question_ids"])) != len(proposal["question_ids"])
            or (proposal["learning_goal_id"] is not None and proposal["learning_goal_id"] not in goals)):
        raise ValueError("Unknown proposal evidence or goal")
    return proposal


def accept_proposal(db, unit, value, job_id):
    """Do not let a model overwrite fixed results or the review schedule."""
    if not value:
        return
    proposal = ActionProposal.model_validate(value).model_dump()
    data = facts(db, unit)
    selected = [a for a in data["attempts"] if a.question_id in proposal["question_ids"]]
    if any(a.outcome == "uncertain" for a in selected):
        allowed = {"clarify_assessment"}
    elif any(a.outcome != "correct" or a.assisted for a in selected):
        allowed = {"explain", "visual_example", "review_prerequisite", "recommend_resource", "check_understanding"}
    else:
        allowed = {"transfer", "check_understanding", "schedule_review", "finish_round"}
    status = "accepted" if selected and proposal["kind"] in allowed else "rejected_by_evidence"
    observe(db, unit, "model_action_proposed", "model-action:" + job_id,
        ["attempt:" + a.id for a in selected], working_patch={"model_proposal": {
            **proposal, "status": status, "advisory_only": True, "job_id": job_id}})


def source_state(db, unit):
    refs = list(db.scalars(select(UnitSource).where(UnitSource.unit_id == unit.id)))
    expected = {r.material_id: r.revision for r in refs}
    if not refs and unit.material_id:
        material = db.get(Material, unit.material_id)
        if material:
            expected[material.id] = material.revision
    sources = list(db.scalars(select(Material).where(Material.id.in_(list(expected))))) if expected else []
    valid = len(sources) == len(expected) and all(m.confirmed and m.revision == expected[m.id] for m in sources)
    assignment = db.get(Assignment, unit.assignment_id) if unit.assignment_id else None
    if unit.assignment_id:
        valid = valid and bool(assignment and assignment.source_status == "confirmed"
            and (unit.goal_revision is None or assignment.revision == unit.goal_revision))
    signature = fingerprint([unit.id, unit.goal_revision,
        sorted((m.id, m.revision, m.confirmed) for m in sources), sorted(expected.items()), unit.questions,
        [assignment.id, assignment.revision, assignment.source_status] if assignment else None])
    return signature, valid, sources


def facts(db, unit):
    from . import adaptive_plan, instructional_decisions

    attempts = list(db.scalars(select(Attempt).where(Attempt.unit_id == unit.id).order_by(Attempt.created, Attempt.id)))
    activities = list(db.scalars(select(Activity).where(Activity.unit_id == unit.id).order_by(Activity.created, Activity.id)))
    signature, source_valid, sources = source_state(db, unit)
    by_question = {q["id"]: [a for a in attempts if a.question_id == q["id"]] for q in unit.questions}
    deferred = adaptive_plan.deferred(db, unit) | instructional_decisions.deferred(db, unit)
    current = adaptive_plan.current_question(db, unit)
    model_step = instructional_decisions.current(db, unit)
    if model_step and model_step[1]["question_id"]:
        current = model_step[1]["question_id"]
    open_question = next((q for q in unit.questions if q["id"] == current), None) if current else None
    if open_question is None:
        open_question = next((q for q in unit.questions if q["id"] not in deferred and (not by_question[q["id"]] or (
            len(by_question[q["id"]]) < 3 and by_question[q["id"]][-1].outcome == "incorrect"))), None)
    misconceptions = []
    if unit.subject.casefold() in ("mathematik", "mathe"):
        for q in unit.questions:
            numbers = re.search(r"(?<!\d)(\d+)\s*/\s*(\d+)\s*\+\s*(\d+)\s*/\s*(\d+)", q["prompt"])
            if not numbers:
                continue
            a, b, c, d = map(int, numbers.groups())
            if not b or not d:
                continue
            for attempt in by_question[q["id"]]:
                try:
                    if (attempt.outcome == "incorrect" and Fraction(str(attempt.answer).strip()) == Fraction(a + c, b + d)
                            and Fraction(a + c, b + d) != Fraction(a, b) + Fraction(c, d)):
                        misconceptions.append({"kind": "denominators_added", "attempt_id": attempt.id,
                            "question_id": q["id"], "observation": "Zähler und Nenner wurden jeweils addiert."})
                except (ValueError, ZeroDivisionError):
                    pass
    return {"attempts": attempts, "activities": activities, "by_question": by_question, "question": open_question,
        "source_signature": signature, "source_valid": source_valid, "sources": sources, "misconceptions": misconceptions}


def local_resources(db, unit, question, need, sources):
    """Titles and metadata only; never pretend to know the complete video."""
    from .catalog_models import LearningTipContext, LearningTipInteraction
    from .catalog_search import candidates
    from .learning_tips import contents_for

    if not unit.subject_id:
        return []
    title = unit.topic + "\n" + question.get("prompt", "") if question else unit.topic
    if unit.subject.casefold() in ("mathe", "mathematik") and question and re.search(r"\d+\s*/\s*\d+\s*\+", question["prompt"]):
        title = "Brüche addieren"
    if need == "denominators_added":
        title = "Brüche gleichnamig machen gemeinsamen Nenner erweitern"
    content = question.get("source_excerpt", "") if question else ""
    matches = candidates(db, unit.subject_id, title, content, limit=3, automatic=True, child=db.get(Child, unit.child_id))
    if not matches:
        return []
    view = contents_for(db, db.get(Child, unit.child_id), unit.subject_id, [m["id"] for m in matches], 3, title)
    context = db.scalar(select(LearningTipContext).where(LearningTipContext.unit_id == unit.id))
    history = list(db.scalars(select(LearningTipInteraction).where(
        LearningTipInteraction.context_id == context.id))) if context else []
    excluded = {r.content_id for r in history if r.kind in ("not_relevant", "broken", "not_helpful")}
    for event in history:
        if event.kind == "watched" and db.scalar(select(Attempt.id).where(Attempt.unit_id == unit.id,
            Attempt.created > event.created, Attempt.outcome == "incorrect",
            Attempt.question_id == event.data["question_id"] if event.data.get("question_id") else True)):
            excluded.add(event.content_id)
    # Avoid repeatedly prescribing the same resource after it did not help.
    result = [item for item in view["recommended"] + view["additional"] if item["id"] not in excluded][:3]
    for item in result:
        item["reason"] = "Eine andere Erklärung zum Thema „" + item["topic_title"] + "“."
        item["knowledge_basis"] = "catalog_title_and_topic"
    return result


def decide(db, unit, memory=None):
    from . import adaptive_plan, instructional_decisions
    from .learning import completion_ready

    data = facts(db, unit)
    q = data["question"]
    attempts = data["by_question"].get(q["id"], []) if q else []
    refs = ["attempt:" + a.id for a in data["attempts"]][-40:]
    value = dict(kind="practice", phase="practice", question_id=q["id"] if q else None,
        learning_goal_id=q.get("learning_goal_id") if q else None, evidence_refs=refs,
        reason_code="prepared_question", reason="Die nächste Aufgabe gehört zu deinem bestätigten Lernstoff.",
        title="Probiere die nächste Aufgabe", expected_result="Eine eigene Antwort auf die nächste Aufgabe.",
        on_success="check_understanding", on_error="hint")
    if not data["source_valid"]:
        value.update(kind="confirm_source", phase="entry", reason_code="source_changed",
            title="Der Lernstoff wurde geändert", reason="Die alte Runde bleibt gespeichert. Prüfe zuerst die neue Heftseite.",
            expected_result="Aktuell bestätigter Lernstoff.", on_success="check_prior", on_error="confirm_source")
    elif unit.status != "completed" and (model_action := instructional_decisions.action(db, unit)):
        value.update(model_action)
    elif any(a.outcome == "uncertain" for a in data["attempts"]):
        value.update(kind="clarify_assessment", phase="help", reason_code="assessment_pending",
            title="Eine Antwort ist noch offen", reason="Die Prüfung ist unklar. Das zählt nicht als falsche Antwort.",
            expected_result="Eine nachvollziehbar geklärte Bewertung.", on_success="practice", on_error="clarify_assessment")
    elif unit.status == "completed" or (instructional_decisions.deferred(db, unit)
            and completion_ready(db, unit, data["attempts"])):
        supported = any(a.assisted or a.outcome != "correct" for a in data["attempts"])
        value.update(kind="finish_round", phase="finish", reason_code="round_completed_supported" if supported else "round_completed",
            title="Deine Runde ist fertig", reason="Nach der Hilfe probierst du es später mit einer neuen Aufgabe allein." if supported
                else "Deine Antworten sind gespeichert. Später prüfst du den Abruf mit neuen Aufgaben.",
            expected_result="Runde beenden oder bewusst eine weitere kleine Runde wählen.",
            on_success="schedule_review", on_error="offer_break")
    elif adaptive_action := adaptive_plan.decision(db, unit):
        value.update(adaptive_action)
    elif (memory or {}).get("media_return"):
        value.update(kind="check_understanding", phase="media_return", reason_code="media_return",
            title="Probier es jetzt selbst", reason="Der Link ist kein Lernnachweis. Eine eigene Antwort zeigt, was dir geholfen hat.",
            on_success="practice", on_error="visual_example")
    elif any(e.kind == "feedback" and e.detail.get("kind") in ("too_hard", "unclear") for e in data["activities"][-4:]):
        value.update(kind="offer_break", phase="help", reason_code="child_requested_smaller_step",
            title="Ein kleinerer Schritt", reason="Du hast gemeldet, dass die Aufgabe gerade schwer oder unklar ist. Schau dir ein Beispiel an oder pausiere.",
            on_success="visual_example", on_error="offer_break")
    elif len(data["misconceptions"]) >= 2:
        count = len({m["question_id"] for m in data["misconceptions"]})
        reason = f"In {len(data['misconceptions'])} Antworten auf {count} Aufgabe(n) wurden Zähler und Nenner jeweils addiert. Vergleiche zuerst gleich große Bruchteile."
        value.update(kind="review_prerequisite", phase="help", reason_code="denominators_added",
            title="Schau auf die gleich großen Teile", reason=reason, expected_result="Den gemeinsamen Nenner an einem neuen Beispiel anwenden.",
            on_success="check_understanding", on_error="recommend_resource")
        # A proposed check is not a new asserted weakness or an invented mastery.
        if any(re.search(r"Nenner|erweiter|gleichnam", m.content, re.I) for m in data["sources"]):
            value["prerequisites"] = [{"key": "common_denominator", "label": "Gleich große Bruchteile",
                "status": "check_suggested", "basis": "confirmed_material", "material_ids": [m.id for m in data["sources"]]}]
    elif attempts and attempts[-1].outcome == "incorrect":
        shown = [e for e in data["activities"] if e.kind in ("hint", "explanation") and e.detail.get("question_id") == q["id"]]
        if len(attempts) >= 2 or len(shown) >= 2:
            value.update(kind="visual_example", phase="help", reason_code="change_explanation",
                title="Schau dir einen Schritt an", reason="Die bisherigen Versuche haben noch nicht geholfen. Wir wechseln die Erklärung.",
                on_success="check_understanding", on_error="recommend_resource")
        else:
            value.update(kind="hint", phase="help", reason_code="single_error",
                title="Ein kleiner Tipp hilft weiter", reason="Eine falsche Antwort zeigt noch keine grundsätzliche Lücke.",
                on_success="practice", on_error="visual_example")
    elif unit.status == "paused":
        value.update(kind="resume", phase="entry", reason_code="paused", title="Mach hier weiter",
            reason="Deine Antwort und Lernposition bleiben gespeichert.", on_success="practice", on_error="offer_break")
    elif not unit.introduction_seen and not data["attempts"] and unit.round_kind not in ("check", "review", "vocabulary"):
        from .coaching import fraction_task_goal
        from .learning import local_day
        from .learning_knowledge import evidence

        previous = evidence(db, unit, data["sources"])
        goal_id = q.get("learning_goal_id") if q else None
        goal_id = goal_id or (fraction_task_goal(q["prompt"], previous) if q else None)
        secure = next((g for g in previous if g["id"] == goal_id and g["confidence"] == "repeated_recall"), None)
        if secure and secure["review_due"] and secure["review_due"] >= local_day(db.get(Child, unit.child_id)).isoformat():
            value.update(reason_code="secure_prior_evidence", reason="Mehrere selbstständige Abrufprüfungen liegen vor. Beginne mit einer Anwendung.",
                evidence_refs=secure["evidence_refs"])
        else:
            value.update(kind="check_prior", phase="prior_knowledge", reason_code="new_goal_no_current_evidence",
                title="Was weißt du schon?", reason="Die erste kleine Aufgabe zeigt, ob du eine Erklärung brauchst.",
                on_success="practice", on_error="explain")
    # Query existing resources before requesting any new explanation.
    if value["kind"] in ("check_prior", "hint", "visual_example", "review_prerequisite", "recommend_resource"):
        need = "denominators_added" if data["misconceptions"] else value["reason_code"]
        value["resources"] = local_resources(db, unit, q, need, data["sources"])
        selected = instructional_decisions.current(db, unit)
        if selected and selected[1]["kind"] == "recommend_resource":
            from .learning_tips import contents_for

            plan, step = selected
            candidate = next((r for r in plan.get("resource_candidates", []) if r["id"] == step["resource_id"]), None)
            if candidate and unit.subject_id:
                existing = contents_for(db, db.get(Child, unit.child_id), unit.subject_id, [candidate["topic_id"]], 3)
                chosen = next((r for r in existing["recommended"] + existing["additional"] if r["id"] == candidate["id"]), None)
                if chosen:
                    chosen.update(reason=step["reason"], expected_result=step["expected_result"], knowledge_basis="catalog_title_and_topic")
                    value["resources"] = [chosen, *[r for r in value["resources"] if r["id"] != chosen["id"]]][:3]
    return Action(**value).model_dump(), data


def projection(db, unit, *, include_draft=True):
    from . import adaptive_plan, instructional_decisions

    memory = db.get(LearningMemory, unit.id)
    decision, data = decide(db, unit, memory.working if memory else None)
    working = dict(memory.working) if memory else {}
    working.pop("adaptive_flow", None)  # Private recipe/source and unrevealed steps.
    working.pop("instructional_plan", None)
    working.pop("instructional_deferrals", None)
    if not include_draft:
        working.pop("draft", None)  # Unsubmitted input is not a parent activity.
    pending = db.get(Job, working.get("pending_check_job_id")) if working.get("pending_check_job_id") else None
    preparation = None
    if pending and pending.child_id == unit.child_id and pending.kind == "controller_check" and pending.payload.get("unit_id") == unit.id:
        following = db.get(LearningUnit, (pending.result or {}).get("unit_id")) if (pending.result or {}).get("unit_id") else None
        if not following or following.status != "completed":
            preparation = {"id": pending.id, "status": pending.status, "unit_id": following.id if following else None}
    decision_job = db.get(Job, working.get("decision_job_id")) if working.get("decision_job_id") else None
    decision_preparation = None
    if decision_job and decision_job.child_id == unit.child_id and decision_job.kind == "decision" and decision_job.payload.get("unit_id") == unit.id:
        decision_preparation = {"id": decision_job.id, "status": decision_job.status}
    decision_jobs = list(db.scalars(select(Job.id).where(Job.child_id == unit.child_id, Job.kind == "decision",
        Job.payload["unit_id"].as_string() == unit.id)))
    return {"version": 2 if adaptive_plan.enabled(db, unit) else 1, "strategy_version": STRATEGY, "revision": memory.revision if memory else 0,
        "updated": memory.updated if memory else 0, "draft_revision": working.get("draft_revision", 0),
        "plan_revision": memory.plan_revision if memory else 0, "source_signature": data["source_signature"],
        "source_valid": data["source_valid"], "action": decision,
        "working_memory": working, "preparation": preparation, "short_plan": adaptive_plan.public_plan(db, unit),
        "instructional_plan": instructional_decisions.public(db, unit),
        "decision_preparation": decision_preparation,
        "can_request_support_check": not unit.synthetic and data["source_valid"] and preparation is None
            and any(e.kind == "explanation" for e in data["activities"]),
        "can_request_decision": unit.status == "active" and not unit.synthetic and data["source_valid"]
            and decision["kind"] != "finish_round" and bool(data["attempts"]) and len(decision_jobs) < 2,
        "observations": {"answered_tasks": len({a.question_id for a in data["attempts"]}),
            "attempts": len(data["attempts"]), "misconceptions": data["misconceptions"],
            "independent_first_answers": sum(len(values) == 1 and values[0].outcome == "correct" and not values[0].assisted
                for values in data["by_question"].values()),
            "uncertain_answers": sum(a.outcome == "uncertain" for a in data["attempts"])},
        "memory_notice": "Übungen, Hilfen und späterer Abruf sind getrennte Belege. Ein Videoaufruf ist kein Verständnisnachweis."}


def knowledge(db, unit):
    """Reuse goal evidence; only link prerequisites present in confirmed goals.

    The edges are reviewed teaching rules, not inferred competence or a full
    curriculum. Old answers remain the single authoritative observations.
    """
    from .coaching import goal_states
    from .learning_knowledge import evidence, prerequisites

    signature, valid, sources = source_state(db, unit)
    states = goal_states(db, unit) if valid else []
    long_term = evidence(db, unit, sources) if valid else []
    return {"version": 1, "source_signature": signature, "source_valid": valid,
        "goals": states, "long_term": long_term, "prerequisites": prerequisites(long_term),
        "notice": "Voraussetzungen sind Lernvorschläge. Eine richtige Wiedererkennung belegt keinen freien Abruf."}


def observe(db, unit, kind, key, evidence, *, working_patch=None):
    """Caller holds the unit lock before any child lock; same event is a no-op."""
    digest = fingerprint([kind, evidence, working_patch])
    previous = db.scalar(select(LearningEvent).where(LearningEvent.unit_id == unit.id, LearningEvent.event_key == key))
    if previous:
        if previous.digest != digest:
            raise HTTPException(409, "Dieser Vorgang gehört zu einem anderen Lernschritt.")
        return previous
    memory = db.get(LearningMemory, unit.id)
    decision, data = decide(db, unit, memory.working if memory else None)
    if not memory:
        memory = LearningMemory(unit_id=unit.id, child_id=unit.child_id, source_signature=data["source_signature"],
            working={}, decision={}, revision=0, plan_revision=0)
        db.add(memory)
    if working_patch is not None:
        memory.working = {**memory.working, **working_patch}
        decision, data = decide(db, unit, memory.working)
    from .instructional_decisions import event_recorded

    event_recorded(db, unit, kind, working_patch or {})
    decision, data = decide(db, unit, memory.working)
    if memory.decision != decision or memory.source_signature != data["source_signature"]:
        memory.plan_revision += 1
    memory.decision, memory.source_signature = decision, data["source_signature"]
    memory.revision, memory.updated = memory.revision + 1, int(now())
    if kind == "answer":
        memory.working = {**memory.working, "draft": None, "media_return": None,
            "draft_revision": memory.working.get("draft_revision", 0) + 1}
    event = LearningEvent(unit_id=unit.id, child_id=unit.child_id, event_key=key, digest=digest, kind=kind,
        evidence=evidence, decision=decision, strategy_version=STRATEGY)
    db.add(event)
    db.flush()
    return event


def activity_recorded(db, activity):
    if not activity.unit_id or activity.kind not in EVENTS:
        return
    db.flush()
    unit = db.get(LearningUnit, activity.unit_id)
    if unit:
        from .instructional_decisions import event_recorded

        event_recorded(db, unit, activity.kind, activity.detail)
        observe(db, unit, activity.kind, "activity:" + activity.id, ["activity:" + activity.id])


def generation_guard(db, unit_id):
    memory = db.get(LearningMemory, unit_id)
    return {"unit_id": unit_id, "plan_revision": memory.plan_revision,
        "source_signature": memory.source_signature} if memory else None


class Draft(Strict):
    request_key: str = Field(min_length=8, max_length=80, pattern=r"^[A-Za-z0-9_-]+$")
    revision: int = Field(ge=0)
    question_id: str = Field(min_length=1, max_length=60)
    answer: str = Field(max_length=2000)
    input_method: Literal["typed", "speech"] = "typed"


@router.get("/units/{unit_id}/learning-session")
def read(unit_id: str, p=Depends(authenticated), db=Depends(get_db)):
    from .learning import get_unit

    return projection(db, get_unit(db, p, unit_id), include_draft=p.user.role == "child")


@router.get("/units/{unit_id}/learning-session/knowledge")
def read_knowledge(unit_id: str, p=Depends(authenticated), db=Depends(get_db)):
    from .learning import get_unit

    return knowledge(db, get_unit(db, p, unit_id))


@router.put("/units/{unit_id}/learning-session/draft")
def draft(unit_id: str, data: Draft, p=Depends(child_user), db=Depends(get_db)):
    from .learning import get_unit, question

    unit = get_unit(db, p, unit_id, True, True)
    q = question(unit, data.question_id)
    if q.get("type") == "grouped":
        from .grouped_questions import parse_answer

        try:
            parse_answer(q["field_group"], data.answer, partial=True)
        except ValueError as error:
            raise HTTPException(422, str(error)) from None
    previous = db.scalar(select(LearningEvent).where(LearningEvent.unit_id == unit.id, LearningEvent.event_key == "draft:" + data.request_key))
    evidence = [data.question_id, "draft:" + fingerprint([data.answer, data.input_method])]
    patch = {"draft": {"question_id": data.question_id, "answer": data.answer, "input_method": data.input_method},
        "draft_revision": data.revision + 1}
    if previous:
        if previous.digest != fingerprint(["draft_saved", evidence, patch]):
            raise HTTPException(409, "Dieser Speichervorgang gehört zu einer anderen Antwort.")
        return projection(db, unit)
    memory = db.get(LearningMemory, unit.id)
    if ((memory.working or {}).get("draft_revision", 0) if memory else 0) != data.revision:
        raise HTTPException(409, "Die Antwort wurde auf einem anderen Gerät geändert. Bitte lade den gespeicherten Stand.")
    if unit.status not in ("active", "paused"):
        raise HTTPException(409, "Diese Runde ist bereits beendet.")
    current, _ = decide(db, unit, memory.working if memory else None)
    if current["question_id"] != data.question_id:
        raise HTTPException(409, "Dieser Entwurf gehört nicht zur aktuellen Aufgabe.")
    attempts = list(db.scalars(select(Attempt).where(Attempt.unit_id == unit.id, Attempt.question_id == data.question_id)))
    if any(a.outcome in ("correct", "uncertain") for a in attempts) or len(attempts) >= 3:
        raise HTTPException(409, "Die Antwort auf diese Aufgabe ist bereits abgegeben.")
    rate_limit(db, "learning-draft:" + p.user.id, 180, 60, commit=False)
    observe(db, unit, "draft_saved", "draft:" + data.request_key, evidence, working_patch=patch)
    db.commit()
    return projection(db, unit)


class ChooseAction(Strict):
    request_key: str = Field(min_length=8, max_length=80, pattern=r"^[A-Za-z0-9_-]+$")
    revision: int = Field(ge=0)
    kind: ActionKind


class SkipQuestion(Strict):
    request_key: str = Field(min_length=8, max_length=80, pattern=r"^[A-Za-z0-9_-]+$")
    revision: int = Field(ge=0)
    question_id: str = Field(min_length=1, max_length=80)


@router.post("/units/{unit_id}/learning-session/skip")
def skip_question(unit_id: str, data: SkipQuestion, p=Depends(child_user), db=Depends(get_db)):
    from . import instructional_decisions, learning

    unit = learning.get_unit(db, p, unit_id, True, True)
    key = "skip:" + data.request_key
    previous = db.scalar(select(LearningEvent).where(LearningEvent.unit_id == unit.id, LearningEvent.event_key == key))
    if previous:
        if previous.evidence != ["question:" + data.question_id]:
            raise HTTPException(409, "Dieser Vorgang gehört zu einer anderen Aufgabe.")
        return learning.unit_data(db, unit)
    memory = db.get(LearningMemory, unit.id)
    selected, state = decide(db, unit, memory.working if memory else None)
    if (unit.status != "active" or not state["source_valid"] or not memory
            or memory.revision != data.revision or selected["question_id"] != data.question_id):
        raise HTTPException(409, "Dieser Lernschritt wurde geändert. Lade zuerst deine Runde neu.")
    if learning.pending_feedback(unit, state["attempts"], state["activities"]):
        raise HTTPException(409, "Lies zuerst deine gespeicherte Rückmeldung.")
    if not instructional_decisions.current(db, unit):
        # No invented replacement or fake completion. The original stays resumable.
        unit.status, unit.heartbeat = "paused", None
    learning.record(db, unit.child_id, "question_skipped", {"question_id": data.question_id}, unit.id)
    observe(db, unit, "question_skipped", key, ["question:" + data.question_id])
    db.commit()
    return learning.unit_data(db, unit)


@router.post("/units/{unit_id}/learning-session/action")
def execute(unit_id: str, data: ChooseAction, p=Depends(child_user), db=Depends(get_db)):
    from . import adaptive_plan, instructional_decisions, learning

    unit = learning.get_unit(db, p, unit_id, True, True)
    memory = db.get(LearningMemory, unit.id)
    previous = db.scalar(select(LearningEvent).where(LearningEvent.unit_id == unit.id,
        LearningEvent.event_key == "action:" + data.request_key))
    if previous:
        if previous.evidence != [data.kind]:
            raise HTTPException(409, "Dieser Vorgang gehört zu einer anderen Aktion.")
        return learning.unit_data(db, unit)
    if data.revision != (memory.revision if memory else 0):
        raise HTTPException(409, "Dein Lernschritt hat sich geändert. Bitte lade ihn neu.")
    current, facts_now = decide(db, unit, memory.working if memory else None)
    if not facts_now["source_valid"]:
        raise HTTPException(409, "Der Lernstoff wurde geändert. Prüfe zuerst die aktuelle Heftseite.")
    if (adaptive_plan.flow(db, unit) or instructional_decisions.current(db, unit)) and data.kind not in ("offer_break", "recommend_resource"):
        if learning.pending_feedback(unit, facts_now["attempts"], facts_now["activities"]):
            raise HTTPException(409, "Lies zuerst die gespeicherte Rückmeldung und tippe auf Weiter.")
        if unit.status != "active":
            raise HTTPException(409, "Setze zuerst deine gespeicherte Runde fort.")
    allowed = {current["kind"], "offer_break"}
    if unit.status != "completed":
        allowed |= {"explain", "visual_example", "practice", "recommend_resource"}
        flow = adaptive_plan.flow(db, unit)
        if flow and flow["phase"] == "explanation":
            allowed.add("check_understanding")
    else:
        allowed |= {"finish_round", "schedule_review"}
    if data.kind not in allowed:
        raise HTTPException(409, "Diese Aktion gehört nicht zum aktuellen Lernschritt.")
    if unit.status != "completed" and instructional_decisions.execute(db, unit, data.kind):
        pass
    elif unit.status != "completed" and adaptive_plan.execute(db, unit, data.kind):
        pass
    elif data.kind == "offer_break" and unit.status == "active":
        unit.status, unit.heartbeat = "paused", None
    elif data.kind in ("practice", "check_prior"):
        unit.introduction_seen = True
    elif data.kind in ("explain", "visual_example"):
        # Reuse verified saved explanation; no model call or extra answer.
        learning.record(db, unit.child_id, "explanation", {"question_id": current["question_id"], "via": "controller"}, unit.id)
    elif data.kind == "recommend_resource":
        from .catalog_jobs import refresh_context

        refresh_context(db, "unit", unit)
    recovered = learning.recover_instructional_round(db, unit)
    observe(db, unit, "action_selected", "action:" + data.request_key, [data.kind],
        working_patch={"phase": "practice" if data.kind in ("practice", "check_prior") else current["phase"]})
    db.commit()
    if recovered:
        learning.schedule_completed_review(db, unit)
    return learning.unit_data(db, unit)
