"""Artificial profiles: observations -> action -> durable state; no external AI."""


import pytest
from schulpilot import learning_controller as brain
from schulpilot.db import DB, Activity, Attempt, Job, LearningEvent, LearningMemory, LearningUnit, Material
from sqlalchemy import func, select
from test_coaching import normal_unit as _normal_unit


@pytest.fixture
def normal_unit(api, household):
    yield from _normal_unit.__wrapped__(api, household)


def endpoint(unit_id):
    return f"/api/units/{unit_id}/learning-session"


def start(client, unit_id):
    response = client.post(f"/api/units/{unit_id}/start")
    assert response.status_code == 200, response.text
    return response.json()["learning_session"]


def answer(client, unit_id, value, key):
    response = client.post(f"/api/units/{unit_id}/questions/sum/answer", json={"answer": value, "request_id": key})
    assert response.status_code == 200, response.text
    return response.json()


def test_new_goal_has_an_executable_prior_check_and_an_end(normal_unit):
    client, unit_id, *_ = normal_unit
    session = start(client, unit_id)
    assert session["action"]["kind"] == "check_prior"
    body = {"request_key": "check-prior-0001", "revision": session["revision"], "kind": "check_prior"}
    applied = client.post(endpoint(unit_id) + "/action", json=body)
    assert applied.status_code == 200
    assert applied.json()["introduction_seen"]
    assert applied.json()["learning_session"]["action"]["kind"] == "practice"
    assert client.post(endpoint(unit_id) + "/action", json=body).status_code == 200
    answer(client, unit_id, "2/4", "first-answer-001")
    result = client.post(f"/api/units/{unit_id}/questions/reduce/answer", json={"answer": "1/2"}).json()
    assert result["unit"]["learning_session"]["action"]["kind"] == "finish_round"
    assert result["unit"]["learning_session"]["observations"]["independent_first_answers"] == 2


def test_single_error_gets_a_small_hint_not_a_diagnosis(normal_unit):
    client, unit_id, *_ = normal_unit
    start(client, unit_id)
    result = answer(client, unit_id, "2/8", "wrong-answer-001")
    action = result["unit"]["learning_session"]["action"]
    assert action["kind"] == "hint" and action["reason_code"] == "single_error"
    assert "grundsätzliche Lücke" in action["reason"]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 0


def test_repeated_observed_denominator_error_changes_strategy(normal_unit):
    client, unit_id, *_ = normal_unit
    start(client, unit_id)
    answer(client, unit_id, "2/8", "wrong-answer-001")
    value = answer(client, unit_id, "2/8", "wrong-answer-002")
    session = value["unit"]["learning_session"]
    assert session["action"]["kind"] == "review_prerequisite"
    assert len(session["observations"]["misconceptions"]) == 2
    assert "auf 1 Aufgabe(n)" in session["action"]["reason"]  # Do not invent two new tasks.
    assert all("attempt_id" in item for item in session["observations"]["misconceptions"])
    assert value["assisted"]


def test_drafts_resume_and_do_not_count_as_activity_or_answers(normal_unit, api):
    client, unit_id, *_ = normal_unit
    session = start(client, unit_id)
    with DB() as db:
        activities = db.scalar(select(func.count()).select_from(Activity))
    body = {"request_key": "draft-save-0001", "revision": session["draft_revision"],
        "question_id": "sum", "answer": "2/4", "input_method": "typed"}
    first = client.put(endpoint(unit_id) + "/draft", json=body)
    assert first.status_code == 200, first.text
    again = client.put(endpoint(unit_id) + "/draft", json=body)
    assert again.json()["revision"] == first.json()["revision"]
    assert client.get(endpoint(unit_id)).json()["working_memory"]["draft"]["answer"] == "2/4"
    assert "draft" not in api.get(endpoint(unit_id)).json()["working_memory"]
    assert "draft" not in api.get(f"/api/units/{unit_id}").json()["learning_session"]["working_memory"]
    client.post(f"/api/units/{unit_id}/pause")
    assert client.get(endpoint(unit_id)).json()["working_memory"]["draft"]["answer"] == "2/4"
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0
        assert db.get(LearningUnit, unit_id).active_seconds == 0
        events = list(db.scalars(select(LearningEvent).where(LearningEvent.kind == "draft_saved")))
        assert len(events) == 1 and "2/4" not in str(events[0].evidence)
        assert db.scalar(select(func.count()).select_from(Activity)) == activities + 1  # only deliberate pause


def test_two_devices_cannot_overwrite_another_draft(normal_unit):
    client, unit_id, *_ = normal_unit
    session = start(client, unit_id)
    body = {"request_key": "draft-save-0001", "revision": session["draft_revision"], "question_id": "sum", "answer": "2/4"}
    assert client.put(endpoint(unit_id) + "/draft", json=body).status_code == 200
    assert client.put(endpoint(unit_id) + "/draft", json={**body, "request_key": "draft-save-0002", "answer": "2/8"}).status_code == 409
    assert client.put(endpoint(unit_id) + "/draft", json={**body, "answer": "2/8"}).status_code == 409
    answer(client, unit_id, "2/4", "first-answer-001")
    assert client.get(endpoint(unit_id)).json()["working_memory"]["draft"] is None


def test_hints_and_solution_do_not_become_independent_evidence(normal_unit):
    client, unit_id, *_ = normal_unit
    start(client, unit_id)
    assert client.post(f"/api/units/{unit_id}/questions/sum/hint").status_code == 200
    value = answer(client, unit_id, "2/4", "first-answer-001")
    assert value["assisted"]
    assert value["unit"]["learning_session"]["observations"]["independent_first_answers"] == 0


def test_uncertain_assessment_is_not_a_negative_learning_signal(normal_unit):
    client, unit_id, *_ = normal_unit
    with DB.begin() as db:
        unit = db.get(LearningUnit, unit_id)
        unit.questions = [{**unit.questions[0], "type": "short", "options": [], "prompt": "Erkläre gleich große Bruchteile.",
            "answer": "gleich große Teile", "accepted": []}]
    start(client, unit_id)
    value = answer(client, unit_id, "Ich teile das Ganze in gleich große Stücke.", "uncertain-answer-001")
    assert value["outcome"] == "uncertain"
    session = value["unit"]["learning_session"]
    assert session["action"]["kind"] == "clarify_assessment"
    assert session["observations"]["uncertain_answers"] == 1


def test_changed_material_invalidates_decision_without_rewriting_answers(normal_unit):
    client, unit_id, material_id, *_ = normal_unit
    start(client, unit_id)
    answer(client, unit_id, "2/4", "first-answer-001")
    with DB.begin() as db:
        unit = db.scalar(select(LearningUnit).where(LearningUnit.id == unit_id).with_for_update())
        material = db.get(Material, material_id)
        material.revision += 1
        material.content = "Korrigierter künstlicher Stoff."
        brain.observe(db, unit, "material_revised", "source-change-1", ["material:" + material_id])
    session = client.get(endpoint(unit_id)).json()
    assert not session["source_valid"] and session["action"]["kind"] == "confirm_source"
    with DB() as db:
        assert db.scalar(select(Attempt)).outcome == "correct"


def test_parent_read_does_not_change_memory_time_or_progress(normal_unit, api):
    client, unit_id, _, _, _ = normal_unit
    start(client, unit_id)
    def snapshot():
        with DB() as db:
            return (db.scalar(select(func.count()).select_from(Activity)), db.scalar(select(func.count()).select_from(LearningEvent)),
                db.scalar(select(func.count()).select_from(Attempt)), db.get(LearningUnit, unit_id).active_seconds,
                db.get(LearningMemory, unit_id).revision)
    before = snapshot()
    for _ in range(3):
        assert api.get(endpoint(unit_id)).status_code == 200
        assert api.get(f"/api/units/{unit_id}").status_code == 200
    assert snapshot() == before
    assert api.put(endpoint(unit_id) + "/draft", json={"request_key": "parent-draft-001", "revision": 0, "question_id": "sum", "answer": "2/4"}).status_code == 403


def test_repeated_answer_replays_one_attempt_and_controller_event(normal_unit):
    client, unit_id, *_ = normal_unit
    start(client, unit_id)
    one = answer(client, unit_id, "2/4", "first-answer-001")
    two = answer(client, unit_id, "2/4", "first-answer-001")
    assert one["attempt_id"] == two["attempt_id"]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Attempt)) == 1
        assert db.scalar(select(func.count()).select_from(LearningEvent).where(LearningEvent.kind == "answer")) == 1


def test_model_proposal_cannot_turn_a_helped_answer_into_secure_mastery(normal_unit):
    client, unit_id, *_ = normal_unit
    start(client, unit_id)
    client.post(f"/api/units/{unit_id}/questions/sum/hint")
    answer(client, unit_id, "2/4", "helped-answer-0001")
    value = {"kind": "transfer", "learning_goal_id": None, "question_ids": ["sum"],
        "reason": "Künstlicher Vorschlag für die nächste Anwendung.", "expected_result": "Neue eigene Antwort.",
        "on_success": "schedule_review", "on_error": "hint"}
    with DB.begin() as db:
        unit = db.get(LearningUnit, unit_id)
        brain.accept_proposal(db, unit, value, "synthetic-model-job")
    state = client.get(endpoint(unit_id)).json()
    assert state["working_memory"]["model_proposal"]["status"] == "rejected_by_evidence"
    assert state["observations"]["independent_first_answers"] == 0
    assert client.get(endpoint(unit_id) + "/knowledge").json()["source_valid"]


def test_model_proposal_references_are_checked_and_parent_plan_read_is_pure(normal_unit, api):
    client, unit_id, _, _, child = normal_unit
    start(client, unit_id)
    value = {"kind": "check_understanding", "learning_goal_id": "g9", "question_ids": ["invented"],
        "reason": "Ein fremder Beleg ist nicht erlaubt.", "expected_result": "Neue eigene Antwort.",
        "on_success": "schedule_review", "on_error": "hint"}
    with pytest.raises(ValueError):
        brain.checked_proposal(value, {"completed_questions": [{"question_id": "sum"}], "learning_goals": []})
    with DB() as db:
        before = db.scalar(select(func.count()).select_from(LearningEvent))
    for _ in range(2):
        overview = api.get(f"/api/children/{child['id']}/overview?compact=true").json()
        assert overview["learning_guidance"]["unit_id"] == unit_id
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(LearningEvent)) == before
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0
