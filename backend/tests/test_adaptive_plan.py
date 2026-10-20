"""Full source-bound fraction branches, using artificial ordinary accounts."""

import copy

import pytest
from schulpilot.db import DB, Attempt, Job, LearningMemory, LearningUnit, Material
from sqlalchemy import func, select
from test_coaching import normal_unit as original_fixture


@pytest.fixture
def fraction_profile(api, household):
    fixture = original_fixture.__wrapped__(api, household)
    client, uid, mid, parent, child = next(fixture)
    with DB.begin() as db:
        material = db.get(Material, mid)
        material.content = ("Zähler und Nenner benennen. Der Nenner steht unten. "
            "Beim Addieren ungleichnamiger Brüche zuerst auf einen gemeinsamen Nenner erweitern. "
            "Gleichwertige Brüche beschreiben dieselbe Menge. Danach die Zähler addieren. "
            "Kürzen verändert den Wert nicht.")
        unit = db.get(LearningUnit, uid)
        first = dict(unit.questions[0], type="short", options=[], prompt="Berechne 1/3 + 1/6.",
            answer="1/2", accepted=[], hints=["Suche eine gemeinsame Einteilung."],
            explanation="1/3 + 1/6 = 2/6 + 1/6 = 3/6 = 1/2.")
        unit.questions = [first, unit.questions[1]]
        original = copy.deepcopy(unit.questions)
    client.headers["X-Schulpilot-Capabilities"] = "adaptive_controller_v2"
    response = client.post(f"/api/units/{uid}/start")
    assert response.status_code == 200
    yield client, uid, mid, original, parent, child
    fixture.close()


def session(client, uid):
    return client.get(f"/api/units/{uid}/learning-session").raise_for_status().json()


def action(client, uid, kind, key):
    return client.post(f"/api/units/{uid}/learning-session/action", json={"kind": kind,
        "revision": session(client, uid)["revision"], "request_key": key})


def submit(client, uid, qid, answer, *, key="adaptive-answer-0001", guided=False):
    response = client.post(f"/api/units/{uid}/questions/{qid}/answer", json={"answer": answer,
        "request_id": key, "guided_feedback": guided})
    assert response.status_code == 200, response.text
    return response.json()


@pytest.mark.parametrize("prerequisite_correct", [False, True])
def test_complete_fraction_hypothesis_branches_are_executed_and_persisted(fraction_profile, prerequisite_correct):
    client, uid, _, original, _, _ = fraction_profile
    wrong = submit(client, uid, "sum", "2/9")
    assert wrong["outcome"] == "incorrect"
    state = session(client, uid)
    assert state["short_plan"]["phase"] == "offer_probe"
    assert state["short_plan"]["hypothesis"]["status"] == "unconfirmed"
    assert "adaptive_flow" not in state["working_memory"]
    assert "explanation" not in state["short_plan"]
    assert action(client, uid, "review_prerequisite", "adaptive-probe-0001").status_code == 200
    state = session(client, uid)
    assert state["short_plan"]["phase"] == "probe"
    probe_id = state["action"]["question_id"]
    with DB() as db:
        unit = db.get(LearningUnit, uid)
        assert unit.questions[:2] == original
        probe = next(q for q in unit.questions if q["id"] == probe_id)
        assert probe["answer"] == "2/6"
        assert probe.get("learning_goal_id") is None  # recognition is not addition
        assert probe["controller_goal"]["key"] == "equivalent_fractions"
    submit(client, uid, probe_id, "2/6" if prerequisite_correct else "2/9", key="adaptive-probe-answer-0001")
    state = session(client, uid)
    assert state["short_plan"]["phase"] == "explanation"
    assert "explanation" not in state["short_plan"]
    assert action(client, uid, "visual_example", "adaptive-view-example-0001").status_code == 200
    state = session(client, uid)
    assert ("im Zwischenschritt erkannt" in state["short_plan"]["explanation"]["text"]) == prerequisite_correct
    assert client.get(f"/api/units/{uid}").json()["status"] == "active"
    result = action(client, uid, "check_understanding", "adaptive-application-0001")
    assert result.status_code == 200, result.text
    state = session(client, uid)
    application_id = state["action"]["question_id"]
    with DB() as db:
        question = next(q for q in db.get(LearningUnit, uid).questions if q["id"] == application_id)
        assert "1/4 + 1/8" in question["prompt"] and question["answer"] == "3/8"
    answer = submit(client, uid, application_id, "6/16", key="adaptive-fresh-answer-0001")
    assert answer["outcome"] == "correct" and not answer["assisted"]
    assert session(client, uid)["short_plan"]["hypothesis"]["status"] == "new_independent_success"
    with DB() as db:
        assert db.scalar(select(Attempt).where(Attempt.id == wrong["attempt_id"])).outcome == "incorrect"
        assert db.get(LearningMemory, uid).working["adaptive_flow"]["hypothesis"]["application_attempt_refs"]
        assert db.scalar(select(func.count()).select_from(Job)) == 0  # no inference for the entire local branch
        assert len(db.get(LearningUnit, uid).questions) == 4
    # The original additional task remains; the plan does not discard it.
    assert session(client, uid)["action"]["question_id"] == "reduce"


def test_actions_are_cas_idempotent_and_feedback_is_not_silently_discarded(fraction_profile):
    client, uid, _, _, _, _ = fraction_profile
    result = submit(client, uid, "sum", "2/9", guided=True)
    assert action(client, uid, "review_prerequisite", "adaptive-probe-0001").status_code == 409
    attempt = result["attempt_id"]
    response = client.post(f"/api/units/{uid}/feedback/acknowledge", json={"attempt_id": attempt})
    assert response.status_code == 200, response.text
    body = {"kind": "review_prerequisite", "request_key": "adaptive-probe-0001", "revision": session(client, uid)["revision"]}
    assert client.post(f"/api/units/{uid}/learning-session/action", json=body).status_code == 200
    assert client.post(f"/api/units/{uid}/learning-session/action", json=body).status_code == 200
    with DB() as db:
        assert len(db.get(LearningUnit, uid).questions) == 3


def test_corrected_source_and_parent_cannot_execute_a_stale_child_plan(fraction_profile, api):
    client, uid, mid, _, _, _ = fraction_profile
    submit(client, uid, "sum", "2/9")
    assert action(api, uid, "review_prerequisite", "parent-plan-0001").status_code == 403
    with DB.begin() as db:
        db.get(Material, mid).revision += 1
    assert action(client, uid, "review_prerequisite", "changed-source-0001").status_code == 409
    with DB() as db:
        assert len(db.get(LearningUnit, uid).questions) == 2
        assert db.scalar(select(func.count()).select_from(Job)) == 0
