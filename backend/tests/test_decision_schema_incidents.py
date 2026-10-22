"""Synthetic decision contracts; no live provider or real learning data."""

import copy

import pytest
from schulpilot import instructional_decisions as decisions
from schulpilot.db import DB, Attempt, Job, LearningMemory, Usage
from schulpilot.providers import Result
from test_coaching import process_next
from test_instructional_decisions import profile as original_profile
from test_instructional_decisions import request, sample_plan


@pytest.fixture
def profile(api, household):
    yield from original_profile.__wrapped__(api, household)


def minimal_payload():
    return {
        "questions": [
            {"id": "closed", "closed": True, "attempted": True, "solution_exposed": False, "learning_goal_id": None},
            {"id": "retry", "closed": False, "attempted": True, "solution_exposed": False, "learning_goal_id": None},
            {"id": "fresh", "closed": False, "attempted": False, "solution_exposed": False, "learning_goal_id": None},
            {"id": "shown", "closed": False, "attempted": False, "solution_exposed": True, "learning_goal_id": None},
        ],
        "learning_goals": [],
        "resources": [],
        "observations": [{"ref": "attempt:synthetic"}],
    }


def test_schema_excludes_closed_practice_and_false_new_checks_before_provider_call():
    payload = minimal_payload()
    schema = decisions.DecisionOutput.model_json_schema()
    decisions.schema_refs(schema, payload)
    branches = {b["properties"]["kind"]["enum"][0]: b["properties"] for b in schema["$defs"]["Step"]["anyOf"]}
    assert "recommend_resource" not in branches
    assert branches["practice"]["question_id"]["enum"] == ["retry", "fresh", "shown"]
    assert branches["hint"]["question_id"]["enum"] == ["retry", "fresh", "shown"]
    assert branches["check_understanding"]["question_id"]["enum"] == ["fresh"]
    assert branches["explain"]["question_id"]["enum"] == ["closed", "retry", "fresh", "shown"]
    assert all(p["on_success"]["anyOf"][0]["minimum"] == 1 for p in branches.values())
    assert all(p["learning_goal_id"] == {"type": "null"} for p in branches.values())


def test_schema_omits_unavailable_action_without_inventing_new_questions_or_resources():
    payload = minimal_payload()
    payload["questions"] = [payload["questions"][0]]
    schema = decisions.DecisionOutput.model_json_schema()
    decisions.schema_refs(schema, payload)
    kinds = {b["properties"]["kind"]["enum"][0] for b in schema["$defs"]["Step"]["anyOf"]}
    assert kinds == {"explain", "visual_example", "offer_break", "clarify_assessment"}


def test_rejected_plan_gets_specific_neutral_code_without_rewrite_or_second_call(profile, monkeypatch):
    client, uid, *_ = profile
    calls = []

    def invalid_model(_config, _function, payload):
        calls.append(payload)
        plan = sample_plan(payload)
        plan["steps"][0]["evidence_refs"] = ["attempt:PRIVATE-SYNTHETIC-NOT-STORED"]
        return Result(plan, 100, 100, 10)

    monkeypatch.setattr("schulpilot.providers.request_provider", invalid_model)
    response = request(client, uid)
    assert response.status_code == 202
    process_next()
    with DB() as db:
        row = db.get(Job, response.json()["id"])
        assert row.status == "failed" and row.error_code == "decision_refs"
        assert "PRIVATE" not in row.error
        assert not db.get(LearningMemory, uid).working.get("instructional_plan")
        assert len(list(db.query(Attempt).filter(Attempt.unit_id == uid))) == 2
        assert db.query(Usage).one().status == "failed_billed"
    assert len(calls) == 1


@pytest.mark.parametrize(
    "fault,code", [("closed", "decision_closed"), ("not_new", "decision_not_new"), ("flow", "decision_flow")]
)
def test_validator_keeps_strict_assessment_rules_with_diagnostic_codes(fault, code):
    payload = minimal_payload()
    step = {
        "kind": "practice",
        "question_id": "retry",
        "learning_goal_id": None,
        "resource_id": None,
        "evidence_refs": ["attempt:synthetic"],
        "reason": "Ein kleiner eigener Schritt.",
        "expected_result": "Eine eigene Antwort.",
        "on_success": None,
        "on_error": None,
    }
    if fault == "closed":
        step["question_id"] = "closed"
    if fault == "not_new":
        step["kind"] = "check_understanding"
    if fault == "flow":
        step["on_success"] = 1
    with pytest.raises(decisions.DecisionPlanError) as error:
        decisions.validate({"version": 1, "steps": [copy.deepcopy(step)]}, payload)
    assert error.value.code == code
