"""A clarification label requires actual, question-bound uncertain evidence."""

import copy

import pytest
from schulpilot import instructional_decisions as decisions
from schulpilot.db import DB, Activity, Attempt, LearningMemory, LearningUnit, Usage
from sqlalchemy import func, select
from test_instructional_decisions import profile as existing_profile


@pytest.fixture
def profile(api, household):
    fixture = existing_profile.__wrapped__(api, household)
    yield next(fixture)
    fixture.close()


def context(observations):
    return {"questions": [{"id": qid, "learning_goal_id": None, "attempted": True,
        "closed": qid == "q1", "solution_exposed": False} for qid in ("q1", "q2")],
        "learning_goals": [], "resources": [], "observations": observations}


def observation(qid="q1", outcome="uncertain", ref="attempt:one"):
    return {"question_id": qid, "outcome": outcome, "ref": ref}


def plan(qid="q1", refs=None):
    return {"version": 1, "steps": [{"kind": "clarify_assessment", "question_id": qid,
        "learning_goal_id": None, "resource_id": None, "evidence_refs": ["attempt:one"] if refs is None else refs,
        "reason": "Eine gespeicherte Antwort ist tatsächlich unklar.", "expected_result": "Die feste Bewertung prüfen.",
        "on_success": None, "on_error": None}]}


@pytest.mark.parametrize("outcome", ["incorrect", "correct"])
def test_clarification_rejects_known_verdicts(outcome):
    with pytest.raises(decisions.DecisionPlanError, match="decision_assessment"):
        decisions.validate(plan(), context([observation(outcome=outcome)]))


@pytest.mark.parametrize("change", ["missing_question", "empty_evidence", "unrelated_question", "old_uncertain", "multiple_evidence", "unattempted"])
def test_clarification_requires_current_same_question_evidence(change):
    payload = context([observation(), observation("q2", "uncertain", "attempt:two")])
    value = plan()
    if change == "missing_question":
        value["steps"][0]["question_id"] = None
    elif change == "empty_evidence":
        value["steps"][0]["evidence_refs"] = []
    elif change == "unrelated_question":
        value["steps"][0]["evidence_refs"] = ["attempt:two"]
    elif change == "old_uncertain":
        payload["observations"].append(observation(outcome="correct", ref="attempt:corrected"))
    elif change == "unattempted":
        payload["observations"] = []
        value["steps"][0]["evidence_refs"] = []
    else:
        value["steps"][0]["evidence_refs"].append("attempt:two")
    with pytest.raises(decisions.DecisionPlanError, match="decision_assessment"):
        decisions.validate(value, payload)


def test_actual_uncertain_verdict_remains_honestly_clarifiable():
    value = plan()
    assert decisions.validate(value, context([observation()])) == value


@pytest.mark.parametrize("observations, expected", [([], []), ([observation(outcome="incorrect")], []),
    ([observation(), observation(outcome="correct", ref="attempt:new")], []),
    ([observation()], [("q1", "attempt:one")]),
    ([observation(), observation("q2", "uncertain", "attempt:two")], [("q1", "attempt:one"), ("q2", "attempt:two")])])
def test_actual_schema_binds_each_clarification_question_to_its_own_current_attempt(observations, expected):
    schema = decisions.DecisionOutput.model_json_schema()
    decisions.schema_refs(schema, context(observations))
    branches = [branch["properties"] for branch in schema["$defs"]["Step"]["anyOf"]
        if branch["properties"]["kind"]["enum"] == ["clarify_assessment"]]
    assert [(fields["question_id"]["enum"][0], fields["evidence_refs"]["items"]["enum"][0]) for fields in branches] == expected
    for fields in branches:
        assert fields["question_id"]["type"] == "string"
        assert fields["evidence_refs"]["minItems"] == fields["evidence_refs"]["maxItems"] == 1


def snapshot(db, uid):
    memory = db.get(LearningMemory, uid)
    return {"attempts": [(a.id, a.question_id, a.answer, a.outcome, a.assisted, a.evaluation)
        for a in db.scalars(select(Attempt).where(Attempt.unit_id == uid).order_by(Attempt.created, Attempt.id))],
        "memory": copy.deepcopy((memory.working, memory.revision, memory.plan_revision)),
        "activity": db.scalar(select(func.count()).select_from(Activity)),
        "usage": db.scalar(select(func.count()).select_from(Usage)), "status": db.get(LearningUnit, uid).status}


@pytest.mark.parametrize("condition", ["incorrect", "correct", "unrelated_evidence", "genuine_uncertain"])
def test_saved_clarification_is_revalidated_readonly_against_real_attempts(profile, monkeypatch, condition):
    client, uid, *_ = profile
    monkeypatch.setattr("schulpilot.providers.request_provider", lambda *_a, **_kw: pytest.fail("GET must not call a provider"))
    with DB.begin() as db:
        attempts = list(db.scalars(select(Attempt).where(Attempt.unit_id == uid).order_by(Attempt.created, Attempt.id)))
        latest = attempts[-1]
        if condition in ("correct", "genuine_uncertain", "unrelated_evidence"):
            latest.outcome = "correct" if condition == "correct" else "uncertain"
        value = plan("sum", ["attempt:" + (attempts[0].id if condition == "unrelated_evidence" else latest.id)])
        value.update(cursor=0, shown=False)
        memory = db.get(LearningMemory, uid)
        memory.working = {**memory.working, "instructional_plan": value}
    with DB() as db:
        before = snapshot(db, uid)
        selected = decisions.current(db, db.get(LearningUnit, uid))
        assert (selected is not None) == (condition == "genuine_uncertain")
    for _ in range(2):
        response = client.get(f"/api/units/{uid}")
        assert response.status_code == 200, response.text
        session = response.json()["learning_session"]
        if condition == "genuine_uncertain":
            assert session["instructional_plan"]["steps"][0]["kind"] == "clarify_assessment"
            assert session["action"]["kind"] == "clarify_assessment"
        else:
            assert session["instructional_plan"] is None
            if condition != "unrelated_evidence":
                assert session["action"]["kind"] != "clarify_assessment"
    with DB() as db:
        assert snapshot(db, uid) == before
