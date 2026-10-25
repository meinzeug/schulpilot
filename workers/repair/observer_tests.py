"""Fixed external assertions. Never import candidate code in this observer."""

import copy

import pytest

RPC = None  # Bound only by trusted broker to offline candidate containers.


def payload():
    return {"questions": [
        {"id": "closed", "closed": True, "attempted": True, "solution_exposed": False, "learning_goal_id": None},
        {"id": "retry", "closed": False, "attempted": True, "solution_exposed": False, "learning_goal_id": None},
        {"id": "fresh", "closed": False, "attempted": False, "solution_exposed": False, "learning_goal_id": None},
        {"id": "shown", "closed": False, "attempted": False, "solution_exposed": True, "learning_goal_id": None}],
        "learning_goals": [], "resources": [], "observations": [
            {"ref": "attempt:closed-first", "question_id": "closed", "outcome": "incorrect", "assisted": False},
            {"ref": "attempt:closed-latest", "question_id": "closed", "outcome": "uncertain", "assisted": False},
            {"ref": "attempt:retry", "question_id": "retry", "outcome": "incorrect", "assisted": False}]}


def test_closed_practice_and_unavailable_resources_excluded_before_transport():
    result = RPC({"method": "schema", "payload": payload()})
    branches = {b["properties"]["kind"]["enum"][0]: b["properties"] for b in result["schema"]["$defs"]["Step"]["anyOf"]}
    assert "recommend_resource" not in branches
    # A closed workflow can have a genuinely unresolved latest verdict.
    assert branches["clarify_assessment"]["question_id"]["enum"] == ["closed"]
    assert branches["clarify_assessment"]["evidence_refs"]["items"]["enum"] == ["attempt:closed-latest"]
    assert branches["practice"]["question_id"]["enum"] == ["retry", "fresh", "shown"]
    assert branches["hint"]["question_id"]["enum"] == ["retry", "fresh", "shown"]
    assert branches["check_understanding"]["question_id"]["enum"] == ["fresh"]
    assert branches["explain"]["question_id"]["enum"] == ["closed", "retry", "fresh", "shown"]


def test_unavailable_actions_are_omitted_without_new_questions():
    value = payload()
    value["questions"] = [value["questions"][0]]
    schema = RPC({"method": "schema", "payload": value})["schema"]
    assert {b["properties"]["kind"]["enum"][0] for b in schema["$defs"]["Step"]["anyOf"]} == {
        "explain", "visual_example", "offer_break", "clarify_assessment"}


@pytest.mark.parametrize("fault,code", [("closed", "decision_closed"), ("not_new", "decision_not_new"), ("flow", "decision_flow")])
def test_strict_assessment_guards(fault, code):
    step = {"kind": "practice", "question_id": "retry", "learning_goal_id": None, "resource_id": None,
            "evidence_refs": ["attempt:retry"], "reason": "Ein kleiner eigener Schritt.",
            "expected_result": "Eine eigene Antwort.", "on_success": None, "on_error": None}
    if fault == "closed":
        step["question_id"] = "closed"
    if fault == "not_new":
        step["kind"] = "check_understanding"
    if fault == "flow":
        step["on_success"] = 1
    answer = RPC({"method": "validate", "payload": payload(), "plan": {"version": 1, "steps": [copy.deepcopy(step)]}})
    assert answer == {"valid": False, "code": code}


def test_valid_open_practice_remains_possible():
    step = {"kind": "practice", "question_id": "retry", "learning_goal_id": None, "resource_id": None,
            "evidence_refs": ["attempt:retry"], "reason": "Ein kleiner eigener Schritt.",
            "expected_result": "Eine eigene Antwort.", "on_success": None, "on_error": None}
    assert RPC({"method": "validate", "payload": payload(), "plan": {"version": 1, "steps": [step]}}) == {"valid": True}
