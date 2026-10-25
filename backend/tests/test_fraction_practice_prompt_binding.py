"""Finite new follow-up cores from artificial confirmed sources, zero vendor calls."""
import copy
import json

import httpx
import pytest
from schulpilot import coaching, providers, schemas
from schulpilot import fraction_practice_plan as planner
from schulpilot import unit_fraction_compositions as compositions
from schulpilot.db import DB, Child, LearningUnit, SchoolDay, User
from test_graphic_native_transport import subset_record
from test_presentation_capability_paths import _config
from test_unit_fraction_practice import setup_practice


def candidates(payload):
    return compositions.compile_candidates(payload["visual_context"])


def mock_http(monkeypatch, wire, calls):
    real = httpx.Client

    def handler(request):
        calls.append(json.loads(request.content))
        return httpx.Response(200, json={"choices": [{"message": {"content": json.dumps(wire)}, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": 100, "completion_tokens": 500, "cost": .001}})

    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real(transport=httpx.MockTransport(handler)))


@pytest.mark.parametrize("two_focus", [False, True])
def test_actual_native_request_closes_every_task_prompt_answer_and_goal_before_dispatch(household, monkeypatch, two_focus):
    _, payload, binding, wire = setup_practice(household, two_focus=two_focus)
    calls = []
    mock_http(monkeypatch, wire, calls)
    result = providers.request_provider(_config("openrouter"), "unit", payload)
    assert len(calls) == 1 and result.cost_micros == 1000
    outbound = calls[0]["response_format"]["json_schema"]["schema"]
    subset_record(outbound)
    cores = [c["question_core"] for c in binding.candidates if c.get("planned_practice")]
    found = []

    def resolve(node):
        while "$ref" in node:
            node = outbound["$defs"][node["$ref"].rsplit("/", 1)[-1]]
        return node

    def walk(node):
        if isinstance(node, dict):
            fields = {key: resolve(value) for key, value in node.get("properties", {}).items()}
            if fields.get("prompt", {}).get("enum"):
                for core in cores:
                    if fields["prompt"]["enum"] == [core["prompt"]]:
                        assert fields["id"]["enum"] == [core["id"]]
                        assert fields["learning_goal_id"]["enum"] == [core["learning_goal_id"]]
                        assert fields["type"]["enum"] == ["short"]
                        assert fields["answer"]["enum"] == [core["answer"]]
                        for key in ("options", "accepted"):
                            assert fields[key].get("minItems", 0) == fields[key]["maxItems"] == 0
                        assert len(resolve(fields["explanation_steps"]["items"])["anyOf"]) == 1
                        found.append(core["id"])
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(outbound)
    assert set(found) == {"q1", "q2"}
    assert [q["prompt"] for q in result.data["questions"]] == [core["prompt"] for core in cores]
    assert [q["answer"] for q in result.data["questions"]] == [core["answer"] for core in cores]
    compositions.validate_practice_history(payload, result.data, [])


@pytest.mark.parametrize("change", ["worded", "wrong_fraction", "wrong_answer", "swapped_task"])
def test_model_cannot_substitute_a_worded_core_fraction_answer_or_task(household, monkeypatch, change):
    _, payload, _, wire = setup_practice(household)
    if change == "worded":
        wire["questions"][0]["prompt"] = "Schreibe neun Viertel als gemischte Zahl."
    elif change == "wrong_fraction":
        wire["questions"][0]["prompt"] = "Schreibe 5/4 als gemischte Zahl."
    elif change == "wrong_answer":
        wire["questions"][0]["answer"] = "3 1/4"
    else:
        wire["questions"][0]["id"] = "q2"
    calls = []
    mock_http(monkeypatch, wire, calls)
    with pytest.raises(providers.ProviderError) as error:
        providers.request_provider(_config("openrouter"), "unit", payload)
    assert len(calls) == 1
    assert error.value.billing_result.cost_micros == 1000
    assert error.value.billing_result.cost_source == "reported"


@pytest.mark.parametrize("prompt", ["Schreibe 9 durch 4 als gemischte Zahl.", "Schreibe 9 / 4 als gemischte Zahl.",
    r"Schreibe \frac{9}{4} als gemischte Zahl.", "Schreibe 18/8 als gemischte Zahl.",
    "Schreibe neun Viertel als gemischte Zahl."])
def test_one_used_source_value_or_unknown_old_conversion_refuses_before_http(household, monkeypatch, prompt):
    _, payload, _, wire = setup_practice(household)
    payload = compositions.with_practice_history(payload, [prompt])
    calls = []
    mock_http(monkeypatch, wire, calls)
    with pytest.raises(providers.ProviderError) as error:
        providers.request_provider(_config("openrouter"), "unit", payload)
    assert calls == []
    assert error.value.args == (planner.ERROR,)
    assert error.value.billing_result.cost_micros == 0
    assert error.value.billing_result.cost_source == "cancelled"
    assert "andere bestätigte Heftseite" in str(error.value)


@pytest.mark.parametrize("fault", ["pool_digest", "source_revision", "missing_history", "unknown_flag"])
def test_stale_or_malformed_compact_history_never_dispatches(household, monkeypatch, fault):
    _, payload, _, wire = setup_practice(household)
    payload = copy.deepcopy(payload)
    if fault == "pool_digest":
        payload["fraction_practice_history"]["pool_digest"] = "0" * 64
    elif fault == "source_revision":
        next(s for s in payload["visual_context"]["sources"] if s.get("material_id"))["revision"] += 1
    elif fault == "missing_history":
        payload.pop("fraction_practice_history")
    else:
        payload["fraction_practice_history"]["unknown_conversion"] = "false"
    calls = []
    mock_http(monkeypatch, wire, calls)
    with pytest.raises(providers.ProviderError) as error:
        providers.request_provider(_config("openrouter"), "unit", payload)
    assert calls == [] and error.value.args == (planner.INVALID,)
    assert error.value.billing_result.cost_source == "cancelled"


def test_equivalent_original_fractions_are_not_two_fresh_tasks(household):
    _, payload, _, _ = setup_practice(household)
    rows = candidates(payload)
    first = next(c for c in rows if c["disclosure"] == "solution")
    duplicate = copy.deepcopy(first)
    duplicate["proof"]["input"] = [18, 8]
    duplicate["id"] = "synthetic_equivalent"
    pool = [first, duplicate]
    with pytest.raises(ValueError, match="keine zwei neuen"):
        planner.plan(pool, providers.practice_tasks(payload), planner.history(pool, []))


@pytest.mark.parametrize("fault", ["new_used_value", "question_answer", "task_goal"])
def test_fresh_persistence_check_rejects_changed_history_or_core_without_mutating_result(household, fault):
    _, payload, binding, wire = setup_practice(household)
    data = binding.hydrate(wire)
    prompts = []
    if fault == "new_used_value":
        prompts = ["Schreibe 9 durch 4 als gemischte Zahl."]
    elif fault == "question_answer":
        data["questions"][0]["answer"] = "3 1/4"
    else:
        data["questions"][0]["learning_goal_id"] = "g1"
    before = copy.deepcopy(data)
    with pytest.raises(ValueError) as error:
        compositions.validate_practice_history(payload, data, prompts)
    assert error.value.args == (planner.CURRENT_ERROR,)
    assert data == before
    assert "keine KI-Anfrage" not in planner.CURRENT_ERROR


def test_complete_day_history_keeps_older_than_prompt_window_and_excludes_other_child(household):
    unit_id, payload, _, _ = setup_practice(household)
    with DB.begin() as db:
        unit = db.get(LearningUnit, unit_id)
        child = db.get(Child, unit.child_id)
        day = SchoolDay(child_id=child.id, school_date="2026-01-12")
        db.add(day)
        db.flush()
        unit.school_day_id = day.id
        for index in range(121):
            db.add(LearningUnit(child_id=child.id, school_day_id=day.id, subject="Mathematik", topic="Künstliche Reihe",
                explanation="Künstliche Einführung", questions=[{"prompt": "Schreibe 9 durch 4 als gemischte Zahl." if index == 0 else f"Andere künstliche Frage {index}."}],
                provider="synthetic", model="own-fixture", created=index))
        user = User(username="other-synthetic", display_name="Anderes synthetisches Kind", password_hash="own-fixture", role="child")
        db.add(user)
        db.flush()
        other = Child(family_id=child.family_id, user_id=user.id, grade=6)
        db.add(other)
        db.flush()
        db.add(LearningUnit(child_id=other.id, school_day_id=day.id, subject="Mathematik", topic="Fremde Frage",
            explanation="Künstlich", questions=[{"prompt": "NICHT IM EIGENEN VERLAUF"}], provider="synthetic", model="own-fixture"))
        db.flush()
        all_prompts = coaching._practice_history_prompts(db, unit)
        assert len(all_prompts) == 123 and "NICHT IM EIGENEN VERLAUF" not in all_prompts
        assert "Schreibe 9 durch 4 als gemischte Zahl." not in all_prompts[-120:]
        exclusion = planner.history(candidates(payload), all_prompts)
        assert exclusion["used_values"] == ["9/4"]
        assert set(exclusion) == {"version", "revision", "pool_digest", "used_values", "unknown_conversion"}
        assert "prompt" not in json.dumps(exclusion)


def test_fixed_other_math_plan_is_not_replaced_by_followup_planner(household):
    _, payload, _, _ = setup_practice(household)
    payload["math_tasks"] = [{"id": "q1", "prompt": "Addiere 1/2 und 1/3.", "answer": "5/6", "type": "short"}]
    before = copy.deepcopy(payload)
    assert compositions.with_practice_history(payload, ["Schreibe neun Viertel als gemischte Zahl."]) == before
    schema = providers.strict_schema(schemas.PracticeUnitOutput, preserve_limits=True)
    original = copy.deepcopy(schema)
    assert compositions.bind_schema(schema, payload) is None and schema == original
