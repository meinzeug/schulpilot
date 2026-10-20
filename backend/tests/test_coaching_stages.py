"""Review and exercise generation are independent, durably metered stages.

All school content/provider responses below are artificial. HTTP envelopes are
captured locally; these tests never contact an external model.
"""

import copy
import json as jsonlib
from datetime import timedelta

import httpx
import pytest
from conftest import create_child
from schulpilot import coaching, materials, providers
from schulpilot.db import (
    DB,
    Activity,
    Child,
    Family,
    Job,
    LearningUnit,
    Material,
    ProviderConfig,
    SchoolDay,
    UnitCoaching,
    UnitSource,
    Usage,
    now,
)
from schulpilot.learning import local_day
from schulpilot.providers import ProviderError, Result
from schulpilot.synthetic import CONTENT, sample_unit
from sqlalchemy import func, select
from test_coaching import finish, process_next
from test_coaching import normal_unit as normal_unit


@pytest.fixture
def deferred_review(normal_unit, monkeypatch):
    client, unit_id, material_id, parent, kid = normal_unit
    calls = []

    def request(config, function, payload):
        assert function == "coach" and payload["defer_practice"] is True
        calls.append(copy.deepcopy(payload))
        with DB() as db:
            unit = db.get(LearningUnit, unit_id)
            result = coaching.synthetic_report(db, unit, payload["next_action"])
            result["next_unit"] = None
        return Result(result, 100, 100, 0)

    monkeypatch.setattr(coaching, "request_provider", request)
    finish(client, unit_id, help_first=True)
    process_next()
    unit = client.get(f"/api/units/{unit_id}").json()
    assert unit["coaching"]["status"] == "ready"
    assert unit["coaching"]["practice_deferred"] is True
    assert unit["coaching"]["next_unit_id"] is None
    return client, unit_id, material_id, parent, kid, unit, calls


def practice_output(unit_id):
    with DB() as db:
        unit = db.get(LearningUnit, unit_id)
        item = db.get(UnitCoaching, unit_id)
        return coaching.synthetic_report(db, unit, item.decision)["next_unit"]


def ask_practice(client, unit_id, key="explicit-practice-one"):
    response = client.post(f"/api/units/{unit_id}/practice", headers={"Idempotency-Key": key})
    assert response.status_code == 202, response.text
    return response.json()["id"]


def test_deferred_review_is_ready_before_an_exercise_is_requested(deferred_review):
    client, unit_id, _, _, _, before, calls = deferred_review
    assert len(calls) == 1
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 1
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 1
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
    for _ in range(3):
        resumed = client.get(f"/api/units/{unit_id}").json()
        assert resumed["coaching"]["report"] == before["coaching"]["report"]
        assert resumed["coaching"]["request_count"] == 1
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 1


def test_deferred_repair_focus_uses_saved_review_mapping_for_unassigned_first_questions(deferred_review):
    _, unit_id, _, _, _, original, _ = deferred_review
    assisted_question = original["questions"][0]
    assert assisted_question.get("learning_goal_id") is None
    expected = next(
        review["learning_goal_id"]
        for review in original["coaching"]["report"]["question_reviews"]
        if review["question_id"] == assisted_question["id"]
    )
    with DB() as db:
        unit = db.get(LearningUnit, unit_id)
        assert coaching.focus_ids(db, unit, "repair") == [expected]


def test_failed_generator_preserves_finished_review_answers_and_usage(deferred_review, monkeypatch):
    client, unit_id, _, _, _, before, _ = deferred_review
    calls = []

    def unavailable(config, function, payload):
        assert function == "unit" and payload["review"] is True
        assert "completed_questions" not in payload
        calls.append(payload)
        raise ProviderError("Künstlicher Generator ist nicht verfügbar.")

    monkeypatch.setattr(coaching, "request_provider", unavailable)
    job_id = ask_practice(client, unit_id)
    queued = client.get(f"/api/units/{unit_id}").json()["coaching"]
    assert queued["status"] == "ready"
    assert queued["practice_job_id"] == job_id and queued["practice_status"] == "queued"
    process_next()
    after = client.get(f"/api/units/{unit_id}").json()
    assert len(calls) == 1
    assert after["coaching"]["status"] == "ready"
    assert after["coaching"]["report"] == before["coaching"]["report"]
    assert after["coaching"]["request_count"] == 1
    assert after["coaching"]["practice_deferred"] is True
    assert after["coaching"]["practice_status"] == "failed"
    assert after["coaching"]["practice_error"] == "Künstlicher Generator ist nicht verfügbar."
    assert after["questions"] == before["questions"]
    with DB() as db:
        assert db.get(Job, job_id).status == "failed"
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 1
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        assert usage.function == "coach_practice"
        assert usage.cost_micros is None and usage.status == "failed_unknown"


@pytest.mark.parametrize("quota_exhausted", [False, True])
def test_voluntary_practice_after_goals_and_pause_still_respects_quota(deferred_review, monkeypatch, quota_exhausted):
    client, unit_id, _, _, kid, original, _ = deferred_review
    with DB.begin() as db:
        child = db.get(Child, kid["id"])
        child.preferences = {
            "weekdays": [],
            "daily_minutes": 5,
            "weekly_minutes": 5,
            "session_minutes": 5,
            "pause_until": (local_day(child) + timedelta(days=2)).isoformat(),
        }
        db.add(Activity(child_id=child.id, kind="active_time", detail={"seconds": 7200}, created=int(now())))
        if quota_exhausted:
            db.get(Family, child.family_id).call_limit = 0
    calls = []

    def provider(config, function, payload):
        assert function == "unit"
        calls.append(True)
        return Result(practice_output(unit_id), 100, 100, 0)

    monkeypatch.setattr(coaching, "request_provider", provider)
    response = client.post(f"/api/units/{unit_id}/practice", headers={"Idempotency-Key": "voluntary-practice"})
    assert response.status_code == (429 if quota_exhausted else 202), response.text
    if not quota_exhausted:
        process_next()
    after = client.get(f"/api/units/{unit_id}").json()
    assert after["questions"] == original["questions"]
    assert after["coaching"]["request_count"] == 1
    assert len(calls) == int(not quota_exhausted)
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == (1 if quota_exhausted else 2)
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == (1 if quota_exhausted else 2)
        if not quota_exhausted:
            assert db.get(LearningUnit, after["coaching"]["next_unit_id"]).status == "not_started"


def test_practice_has_one_explicit_retry_and_idempotent_pending_request(deferred_review, monkeypatch):
    client, unit_id, _, _, _, original, _ = deferred_review

    def fail(config, function, payload):
        raise ProviderError("Künstlicher begrenzter Testfehler.")

    monkeypatch.setattr(coaching, "request_provider", fail)
    first = ask_practice(client, unit_id)
    assert ask_practice(client, unit_id) == first
    assert (
        client.post(
            f"/api/units/{unit_id}/practice", headers={"Idempotency-Key": "simultaneous-other-request"}
        ).status_code
        == 409
    )
    process_next()
    second = ask_practice(client, unit_id, "explicit-practice-retry")
    assert first != second
    process_next()
    assert (
        client.post(
            f"/api/units/{unit_id}/practice", headers={"Idempotency-Key": "forbidden-third-attempt"}
        ).status_code
        == 409
    )
    after = client.get(f"/api/units/{unit_id}").json()
    assert after["coaching"]["report"] == original["coaching"]["report"]
    assert after["coaching"]["status"] == "ready"
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job).where(Job.kind == "coach_practice")) == 2
        assert db.scalar(select(func.count()).select_from(Usage)) == 3
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 1


def test_same_second_retry_reports_the_new_job_instead_of_random_id_order(deferred_review, monkeypatch):
    client, unit_id, _, _, _, _, _ = deferred_review
    identifiers = iter(["f" * 32, "0" * 32])
    monkeypatch.setattr(materials, "uid", lambda: next(identifiers))

    def fail(config, function, payload):
        raise ProviderError("Künstlicher Generatorfehler.")

    monkeypatch.setattr(coaching, "request_provider", fail)
    first = ask_practice(client, unit_id)
    process_next()
    second = ask_practice(client, unit_id, "same-second-explicit-retry")
    with DB.begin() as db:
        db.get(Job, second).created = db.get(Job, first).created
    pending = client.get(f"/api/units/{unit_id}").json()["coaching"]
    assert pending["practice_job_id"] == second and pending["practice_status"] == "queued"
    process_next()
    failed = client.get(f"/api/units/{unit_id}").json()["coaching"]
    assert failed["practice_job_id"] == second and failed["practice_status"] == "failed"


def test_new_generator_keeps_original_review_provenance_and_source_links(deferred_review, monkeypatch):
    client, unit_id, material_id, _, _, original, _ = deferred_review
    with DB.begin() as db:
        config = db.get(ProviderConfig, 1)
        config.model = "different-explicit-practice-fixture"
        config.revision += 1

    def generate(config, function, payload):
        assert function == "unit" and config.model == "different-explicit-practice-fixture"
        return Result(practice_output(unit_id), 100, 150, 0)

    monkeypatch.setattr(coaching, "request_provider", generate)
    ask_practice(client, unit_id)
    process_next()
    after = client.get(f"/api/units/{unit_id}").json()
    assert after["coaching"]["status"] == "ready"
    assert after["coaching"]["practice_status"] == "completed", after["coaching"]["practice_error"]
    assert after["coaching"]["provider"] == original["coaching"]["provider"]
    assert after["coaching"]["model"] == original["coaching"]["model"]
    assert after["coaching"]["practice_deferred"] is False
    assert after["coaching"]["report"]["question_reviews"] == original["coaching"]["report"]["question_reviews"]
    assert after["coaching"]["report"]["explanation"] == original["coaching"]["report"]["explanation"]
    next_id = after["coaching"]["next_unit_id"]
    assert next_id
    followup = client.get(f"/api/units/{next_id}").json()
    assert followup["followup_of"] == unit_id and followup["learning_root_id"] == unit_id
    assert followup["provider"] == "openai" and followup["model"] == "different-explicit-practice-fixture"
    assert followup["source_material_ids"] == [material_id]
    assert len(followup["questions"]) == 2
    with DB() as db:
        assert db.scalar(select(UnitSource).where(UnitSource.unit_id == next_id)).material_id == material_id
        assert db.scalar(select(func.count()).select_from(Usage)) == 2


def test_practice_avoids_other_stage_chains_from_the_same_day(deferred_review, monkeypatch):
    client, unit_id, _, _, _, _, _ = deferred_review
    extra_prompt = "Kürze den Bruch 20/30 vollständig."
    unrelated_prompt = "Diese künstliche Frage gehört zu einem anderen Tag."
    with DB.begin() as db:
        unit = db.get(LearningUnit, unit_id)
        today = SchoolDay(child_id=unit.child_id, school_date="2026-10-15", stage="ready")
        other_day = SchoolDay(child_id=unit.child_id, school_date="2026-10-14", stage="ready")
        db.add_all([today, other_day])
        db.flush()
        unit.school_day_id = today.id
        for day, prompt in ((today, extra_prompt), (other_day, unrelated_prompt)):
            question = copy.deepcopy(unit.questions[0])
            question["prompt"] = prompt
            db.add(
                LearningUnit(
                    child_id=unit.child_id,
                    school_day_id=day.id,
                    subject=unit.subject,
                    topic=unit.topic,
                    explanation="Künstliche unabhängige Tagesetappe.",
                    questions=[question],
                    provider="openai",
                    model="synthetic-test-model",
                    estimated_minutes=2,
                    status="not_started",
                )
            )

    def generate(config, function, payload):
        assert function == "unit" and payload["practice_kind"] == "repair"
        assert extra_prompt in payload["previous_prompts"]
        assert unrelated_prompt not in payload["previous_prompts"]
        assert len(payload["previous_prompts"]) == 3
        return Result(practice_output(unit_id), 100, 150, 0)

    monkeypatch.setattr(coaching, "request_provider", generate)
    with DB() as db:
        assert coaching.plan_review(db, db.get(LearningUnit, unit_id))["next_action"] == "repair"
    ask_practice(client, unit_id)
    process_next()
    after = client.get(f"/api/units/{unit_id}").json()["coaching"]
    assert after["practice_status"] == "completed", after["practice_error"]


def test_source_change_during_generator_does_not_replace_saved_review(deferred_review, monkeypatch):
    client, unit_id, material_id, _, _, original, _ = deferred_review
    output = practice_output(unit_id)

    def source_changed(config, function, payload):
        with DB.begin() as db:
            source = db.get(Material, material_id)
            source.content += " Künstliche spätere Änderung."
            source.revision += 1
        return Result(copy.deepcopy(output), 100, 150, 0)

    monkeypatch.setattr(coaching, "request_provider", source_changed)
    job_id = ask_practice(client, unit_id)
    process_next()
    after = client.get(f"/api/units/{unit_id}").json()
    assert after["coaching"]["status"] == "ready"
    assert after["coaching"]["report"] == original["coaching"]["report"]
    assert after["coaching"]["next_unit_id"] is None
    assert after["questions"] == original["questions"]
    with DB() as db:
        assert db.get(Job, job_id).status == "failed"
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 1
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        assert usage.cost_micros == 0  # known valid call, rejected stale result


def test_source_changed_before_preparation_is_a_clear_conflict_without_ai_reservation(deferred_review):
    client, unit_id, material_id, _, _, original, _ = deferred_review
    with DB.begin() as db:
        material = db.get(Material, material_id)
        material.content += " Künstliche Änderung vor dem Klick."
        material.revision += 1
    response = client.post(f"/api/units/{unit_id}/practice", headers={"Idempotency-Key": "stale-source"})
    assert response.status_code == 409, response.text
    after = client.get(f"/api/units/{unit_id}").json()
    assert after["coaching"]["report"] == original["coaching"]["report"]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 1


def test_provider_revision_change_during_practice_keeps_review_and_rejects_result(deferred_review, monkeypatch):
    client, unit_id, _, _, _, original, _ = deferred_review
    output = practice_output(unit_id)

    def changed_provider(config, function, payload):
        with DB.begin() as db:
            db.get(ProviderConfig, 1).revision += 1
        return Result(copy.deepcopy(output), 100, 100, 0)

    monkeypatch.setattr(coaching, "request_provider", changed_provider)
    job_id = ask_practice(client, unit_id)
    process_next()
    after = client.get(f"/api/units/{unit_id}").json()
    assert after["coaching"]["status"] == "ready"
    assert after["coaching"]["report"] == original["coaching"]["report"]
    assert after["coaching"]["model"] == original["coaching"]["model"]
    with DB() as db:
        assert db.get(Job, job_id).status == "failed"
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 1


def test_parent_and_sibling_cannot_generate_another_childs_practice(deferred_review, api):
    client, unit_id, _, parent, _, _, _ = deferred_review
    assert (
        api.post(f"/api/units/{unit_id}/practice", headers={"Idempotency-Key": "parent-is-not-child"}).status_code
        == 403
    )
    create_child(api, parent, username="different-child")
    login = client.post("/api/auth/login", json={"username": "different-child", "password": "secure-child-pass-123"})
    assert login.status_code == 200
    client.headers["Authorization"] = "Bearer " + login.json()["token"]
    assert (
        client.post(f"/api/units/{unit_id}/practice", headers={"Idempotency-Key": "sibling-is-not-owner"}).status_code
        == 404
    )
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 1


def test_preparing_practice_is_not_a_second_ai_review(deferred_review, monkeypatch):
    client, unit_id, _, _, _, _, _ = deferred_review
    monkeypatch.setattr(
        coaching,
        "request_provider",
        lambda config, function, payload: Result(practice_output(unit_id), 100, 100, 0),
    )
    with DB() as db:
        before = db.scalar(select(func.count()).select_from(Activity).where(Activity.kind == "coach_review"))
    ask_practice(client, unit_id)
    process_next()
    after = client.get(f"/api/units/{unit_id}").json()
    assert after["coaching"]["practice_status"] == "completed", after["coaching"]["practice_error"]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Activity).where(Activity.kind == "coach_review")) == before
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 2


def _capture_provider(monkeypatch, output):
    sent = []

    class Client:
        def __init__(self, *args, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def post(self, url, *, json: dict, **kwargs):
            sent.append(copy.deepcopy(json))
            return httpx.Response(
                200,
                request=httpx.Request("POST", url),
                json={
                    "choices": [{"finish_reason": "stop", "message": {"content": jsonlib.dumps(output)}}],
                    "usage": {"prompt_tokens": 100, "completion_tokens": 100, "cost": 0},
                },
            )

    monkeypatch.setattr(providers.httpx, "Client", Client)
    monkeypatch.setattr(providers, "verify_free_endpoint", lambda *args: None)
    return sent


def _provider_context(normal_unit, *, assigned=True):
    with DB() as db:
        config = db.get(ProviderConfig, 1)
        values = {column.name: getattr(config, column.name) for column in ProviderConfig.__table__.columns}
    values.update(
        provider="openrouter",
        model="artificial-review-model:free",
        input_per_million_micros=0,
        output_per_million_micros=0,
        capability_evidence="synthetic fixture upstream=artificial-upstream",
    )
    payload = {
        "defer_practice": True,
        "next_action": "repair",
        "required_subject": "Mathematik",
        "required_topic": "Brüche",
        "materials": [{"subject": "Mathematik", "topic": "Brüche", "content": CONTENT}],
        "learning_goals": [
            {
                "id": "g1",
                "label": "Gleichnamige Brüche addieren",
                "source_excerpt": "Brüche mit gleichem Nenner werden addiert, indem man die Zähler addiert.",
            }
        ],
        "completed_questions": [
            {"question_id": "q1", "learning_goal_id": "g1" if assigned else None, "deterministic_outcome": "correct"}
        ],
        "focus_goal_ids": ["g1"],
        "previous_prompts": [],
    }
    feedback = {"question_id": "q1", "outcome": "correct", "feedback": "Die gespeicherte Antwort passt."}
    if not assigned:
        feedback["learning_goal_id"] = "g1"
    output = {"explanation": "Ein bestätigter Schritt wird erklärt.", "question_reviews": [feedback], "next_unit": None}
    return ProviderConfig(**values), payload, output


@pytest.mark.parametrize("assigned", [True, False])
def test_real_deferred_provider_request_has_only_review_instructions(normal_unit, monkeypatch, assigned):
    config, payload, output = _provider_context(normal_unit, assigned=assigned)
    sent = _capture_provider(monkeypatch, output)
    result = providers.request_provider(config, "coach", payload)
    assert result.data["next_unit"] is None
    assert result.data["question_reviews"][0]["learning_goal_id"] == "g1"
    assert len(sent) == 1
    instructions = sent[0]["messages"][0]["content"]
    schema = sent[0]["response_format"]["json_schema"]["schema"]
    # OpenRouter's fixed strict adapter omits unused round output entirely.
    assert 'next_unit' not in schema['properties']
    assert 'next_unit' not in schema['required']
    assert 'Fachdarstellung presentation' not in instructions
    for generator_instruction in [
        "Bei repair: zwei leichtere Aufgaben",
        "Bei check: zwei NEUE",
        "Ordne jede neue Aufgabe",
        "Neue Aufgaben in next_unit benötigen",
        "GENAU 2 Aufgaben",
        "AUSGABEFORMAT FÜR AUSWAHLAUFGABEN",
        "NUR FÜR MATHEMATIK-AUFGABEN",
    ]:
        assert generator_instruction not in instructions


def test_real_deferred_provider_rejects_exercises_even_if_upstream_ignores_review_schema(normal_unit, monkeypatch):
    config, payload, output = _provider_context(normal_unit)
    practice = sample_unit(variant=1)
    practice["questions"] = practice["questions"][:2]
    for question in practice["questions"]:
        question["learning_goal_id"] = "g1"
    output["next_unit"] = practice
    sent = _capture_provider(monkeypatch, output)
    with pytest.raises(ProviderError):
        providers.request_provider(config, "coach", payload)
    assert len(sent) == 1  # no retry, no fallback, no second generation
