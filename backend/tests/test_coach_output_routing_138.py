"""Artificial route/ledger contracts; no real child data or provider/network."""

import copy
import socket
from types import SimpleNamespace

import pytest
import test_coaching_stages as stages
from conftest import create_child
from schulpilot import coach_routing, coaching
from schulpilot.db import (
    DB,
    Assignment,
    Attempt,
    Family,
    Job,
    LearningUnit,
    Material,
    ProviderConfig,
    UnitCoaching,
    UnitSource,
    Usage,
    now,
)
from schulpilot.model_routing import choose_tier, features_for, job_config
from schulpilot.providers import ProviderError, Result, reserve
from sqlalchemy import func, select
from test_model_routing import setup_policy

normal_unit = stages.normal_unit
deferred_review = stages.deferred_review
CONTENT = "Ein künstlicher bestätigter Lehrsatz beschreibt ein eigenes Beispiel."


@pytest.fixture(autouse=True)
def no_network(monkeypatch):
    def refuse(*args, **kwargs):
        raise AssertionError("External network forbidden in artificial coach routing tests")

    monkeypatch.setattr(socket.socket, "connect", refuse)
    monkeypatch.setattr(socket, "getaddrinfo", refuse)


@pytest.fixture
def book(household):
    parent, kid = household
    with DB.begin() as db:
        page = Material(
            child_id=kid["id"],
            subject="Mathematik",
            topic="Künstliches Thema",
            title="Künstliche Quelle",
            content=CONTENT,
            confirmed=True,
            status="confirmed",
            purpose="notebook",
        )
        db.add(page)
        db.flush()
        question = {
            "id": "saved_q",
            "type": "short",
            "prompt": "Künstliche abgeschlossene Frage?",
            "answer": "a",
            "options": [],
            "accepted": [],
            "hints": [],
            "explanation": "Gespeicherter eigener Text.",
            "learning_goal_id": "g1",
        }
        unit = LearningUnit(
            child_id=kid["id"],
            material_id=page.id,
            subject=page.subject,
            topic=page.topic,
            explanation="Gespeicherte Einführung.",
            questions=[question],
            status="completed",
            completed=int(now()),
            provider="fixture",
        )
        db.add(unit)
        db.flush()
        db.add(UnitSource(unit_id=unit.id, material_id=page.id, revision=page.revision))
        db.add(Attempt(unit_id=unit.id, question_id="saved_q", answer="b", outcome="incorrect", assisted=False))
        db.add(
            UnitCoaching(
                unit_id=unit.id,
                status="ready",
                decision="repair",
                report={
                    "practice_deferred": True,
                    "learning_goals": [{"id": "g1", "label": "Eigene Regel unterscheiden", "source_excerpt": CONTENT}],
                    "question_reviews": [{"question_id": "saved_q", "learning_goal_id": "g1"}],
                },
            )
        )
        db.flush()
        signature = coaching.context(db, unit)[0]
        job = Job(
            child_id=kid["id"],
            kind="coach_practice",
            status="queued",
            idempotency="artificial-coach-output-1",
            payload={"unit_id": unit.id, "signature": signature, "next_action": "repair", "practice_number": 1},
        )
        db.add(job)
        db.flush()
        return SimpleNamespace(
            child=kid["id"], family=parent["families"][0]["id"], parent=parent, unit=unit.id, page=page.id, job=job.id
        )


def configure_route(family):
    setup_policy(family)
    with DB.begin() as db:
        cfg = db.get(ProviderConfig, 1)
        value = copy.deepcopy(cfg.routing_policy)
        value["economy_mode"] = True
        value["routes"]["luna"].update(max_output_tokens=4000, reserve_micros=150000)
        value["routes"]["sol"].update(max_output_tokens=8000, reserve_micros=250000)
        cfg.routing_policy = value
        cfg.max_output_tokens, cfg.reserve_micros = 8000, 1500000


@pytest.mark.parametrize("subject", ["Mathematik", "Deutsch", "Englisch", "Physik", "Geschichte"])
def test_actual_graphic_practice_contract_not_source_size_or_subject_controls_route(book, subject):
    with DB.begin() as db:
        page, unit = db.get(Material, book.page), db.get(LearningUnit, book.unit)
        page.subject = unit.subject = subject
        job = db.get(Job, book.job)
        job.payload = {**job.payload, "signature": coaching.context(db, unit)[0]}
        before = (
            copy.deepcopy(unit.questions),
            copy.deepcopy(db.get(UnitCoaching, unit.id).report),
            db.scalar(select(func.count()).select_from(Usage)),
            db.scalar(select(func.count()).select_from(Job)),
        )
        facts = features_for(db, book.child, book.job)
        assert facts["coach_extended_output"] and not facts["coach_length_failed"]
        assert facts["source_count"] == 1 and facts["source_chars"] < 100
        assert choose_tier("coach_practice", facts, economy=True) == ("sol", "coach_graphic_teaching")
        assert (
            unit.questions,
            db.get(UnitCoaching, unit.id).report,
            db.scalar(select(func.count()).select_from(Usage)),
            db.scalar(select(func.count()).select_from(Job)),
        ) == before
        assert not db.new and not db.dirty


@pytest.mark.parametrize("purpose,assignment", [("homework", False), ("notebook", True)])
def test_same_graphic_contract_keeps_source_or_parent_scope_and_does_not_silently_exclude_it(book, purpose, assignment):
    with DB.begin() as db:
        page, unit, job = db.get(Material, book.page), db.get(LearningUnit, book.unit), db.get(Job, book.job)
        page.purpose = purpose
        if assignment:
            goal = Assignment(child_id=book.child, kind="parent", subject=unit.subject, topic=unit.topic, note=CONTENT)
            db.add(goal)
            db.flush()
            unit.assignment_id, unit.goal_revision = goal.id, goal.revision
        job.payload = {**job.payload, "signature": coaching.context(db, unit)[0]}
        assert coach_routing.output_need(db, book.child, job)["coach_extended_output"]


def test_reservation_snapshots_existing_sol_limits_and_replay_never_upgrades_or_reserves_again(book):
    configure_route(book.family)
    with DB.begin() as db:
        job = db.get(Job, book.job)
        usage = reserve(db, db.get(Family, book.family), book.child, job.id, "coach_practice")
        assert usage.reserved_micros == 250000 and usage.route_snapshot["reason"] == "coach_graphic_teaching"
        assert usage.route_snapshot["route"]["max_output_tokens"] == 8000
        first = usage.id
        job.status = "running"
        assert reserve(db, db.get(Family, book.family), book.child, job.id, "coach_practice").id == first
        assert job_config(db, job, "unit").max_output_tokens == 8000
        assert db.scalar(select(func.count()).select_from(Usage)) == 1


@pytest.mark.parametrize(
    "fault",
    [
        "wrong_kind",
        "running",
        "foreign_job",
        "foreign_unit",
        "source_revision",
        "unconfirmed",
        "signature",
        "review_state",
        "published",
        "synthetic",
        "action",
        "practice_number",
    ],
)
def test_unproved_or_stale_request_does_not_claim_graphic_or_recorded_length_need(book, fault, api):
    sibling = (
        create_child(api, book.parent, "coach-foreign-scope") if fault in ("foreign_job", "foreign_unit") else None
    )
    with DB.begin() as db:
        job, page, unit = db.get(Job, book.job), db.get(Material, book.page), db.get(LearningUnit, book.unit)
        item = db.get(UnitCoaching, book.unit)
        data = copy.deepcopy(job.payload)
        if fault == "wrong_kind":
            job.kind = "coach"
        elif fault == "running":
            job.status = "running"
        elif fault == "foreign_job":
            job.child_id = sibling["id"]
        elif fault == "foreign_unit":
            unit.child_id = sibling["id"]
        elif fault == "source_revision":
            page.revision += 1
        elif fault == "unconfirmed":
            page.confirmed = False
        elif fault == "signature":
            data["signature"] = "changed"
        elif fault == "review_state":
            item.status = "failed"
        elif fault == "published":
            item.next_unit_id = unit.id
        elif fault == "synthetic":
            unit.synthetic = True
        elif fault == "action":
            data["next_action"] = "parent_help"
        else:
            data["practice_number"] = True
        job.payload = data
        db.flush()
        with db.no_autoflush:
            assert coach_routing.output_need(db, book.child, job) == {
                "coach_extended_output": False,
                "coach_length_failed": False,
            }
        db.rollback()


@pytest.mark.parametrize(
    "fault",
    [
        None,
        "other_child",
        "other_unit",
        "other_signature",
        "other_action",
        "unknown_error",
        "not_failed",
        "not_coach",
        "number",
        "bool_number",
        "contains_only",
    ],
)
def test_explicit_second_request_uses_only_exact_own_matching_length_failure(book, fault, api):
    sibling = create_child(api, book.parent, "coach-foreign-history") if fault == "other_child" else None
    with DB.begin() as db:
        job = db.get(Job, book.job)
        prior = {**job.payload, "practice_number": 1}
        job.payload = {**job.payload, "practice_number": 2}
        old = Job(
            child_id=book.child,
            kind="coach_practice",
            status="failed",
            payload=prior,
            error="  " + coach_routing.LENGTH_MESSAGE.replace(" ", "\n") + "  ",
            idempotency="artificial-prior-1",
        )
        if fault == "other_child":
            old.child_id = sibling["id"]
        elif fault == "other_unit":
            prior["unit_id"] = "e" * 32
        elif fault == "other_signature":
            prior["signature"] = "old"
        elif fault == "other_action":
            prior["next_action"] = "check"
        elif fault == "unknown_error":
            old.error = "Unbekannte künstliche Störung."
        elif fault == "not_failed":
            old.status = "completed"
        elif fault == "not_coach":
            old.kind = "unit"
        elif fault == "number":
            prior["practice_number"] = 2
        elif fault == "bool_number":
            prior["practice_number"] = True
        elif fault == "contains_only":
            old.error = "Vorsatz: " + coach_routing.LENGTH_MESSAGE
        db.add(old)
        db.flush()
        facts = features_for(db, book.child, job.id)
        assert facts["coach_extended_output"]
        assert facts["coach_length_failed"] is (fault is None)
        if fault is None:
            assert choose_tier("coach_practice", facts, economy=True) == ("sol", "recorded_coach_output_length")


def test_existing_text_only_short_route_and_other_functions_remain_unchanged():
    facts = {"sources_known": True, "source_count": 1, "source_chars": 100, "subject_count": 1}
    assert choose_tier("coach_practice", facts, economy=True) == ("luna", "focused_source_practice")
    assert choose_tier("coach", facts, economy=True) == ("luna", "bounded_source_or_review")
    assert choose_tier("tutor", facts, economy=True)[0] == "luna"


def test_explicit_retry_and_idempotency_preserve_saved_review_attempts_and_two_attempt_cap(
    deferred_review, monkeypatch
):
    client, unit_id, _, parent, kid, original, _ = deferred_review
    configure_route(parent["families"][0]["id"])
    calls = []

    def fail(config, function, payload):
        assert function == "unit" and config.max_output_tokens == 8000 and config.reserve_micros == 250000
        calls.append(True)
        raise ProviderError(
            coach_routing.LENGTH_MESSAGE, billing_result=Result({}, 16694, 4000, 3670, cost_source="reported")
        )

    monkeypatch.setattr(coaching, "request_provider", fail)
    first = stages.ask_practice(client, unit_id, "explicit-138-first")
    assert stages.ask_practice(client, unit_id, "explicit-138-first") == first
    stages.process_next()
    after_failure = client.get(f"/api/units/{unit_id}").json()
    assert after_failure["questions"] == original["questions"]
    assert after_failure["coaching"]["report"] == original["coaching"]["report"]
    second = stages.ask_practice(client, unit_id, "explicit-138-second")
    with DB() as db:
        usage = db.scalar(select(Usage).where(Usage.job_id == second))
        assert usage.route_snapshot["reason"] == "recorded_coach_output_length"
    stages.process_next()
    assert (
        client.post(f"/api/units/{unit_id}/practice", headers={"Idempotency-Key": "blocked-third-138"}).status_code
        == 409
    )
    assert len(calls) == 2
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 1
        assert db.get(UnitCoaching, unit_id).status == "ready"


def test_actual_non_graphic_context_keeps_previous_short_schema_route(book):
    with DB.begin() as db:
        page, unit, job = db.get(Material, book.page), db.get(LearningUnit, book.unit), db.get(Job, book.job)
        page.subject = unit.subject = "Künstlicher Kurs ohne Grafikprofil"
        job.payload = {**job.payload, "signature": coaching.context(db, unit)[0]}
        facts = features_for(db, book.child, job.id)
        assert not facts["coach_extended_output"] and not facts["coach_length_failed"]
        assert choose_tier("coach_practice", facts, economy=True) == ("luna", "focused_source_practice")
