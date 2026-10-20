"""Model planning drives saved UI actions, not just advisory metadata."""

import pytest
from schulpilot import instructional_decisions as decisions
from schulpilot.db import DB, Activity, Attempt, Family, Job, LearningMemory, LearningUnit, Material, Session, Usage
from schulpilot.providers import Result
from sqlalchemy import func, select
from test_coaching import normal_unit as original_fixture
from test_coaching import process_next


@pytest.fixture
def profile(api, household):
    fixture = original_fixture.__wrapped__(api, household)
    client, uid, mid, parent, child = next(fixture)
    with DB.begin() as db:
        unit = db.get(LearningUnit, uid)
        second = dict(
            unit.questions[0],
            id="new_sum",
            prompt="Berechne 1/6 + 2/6.",
            options=["3/6", "3/12", "1/6"],
            answer="3/6",
            explanation="1/6 + 2/6 = 3/6.",
        )
        unit.questions = [unit.questions[0], second]
    assert client.post(f"/api/units/{uid}/start").status_code == 200
    for index in range(2):
        assert (
            client.post(
                f"/api/units/{uid}/questions/sum/answer", json={"answer": "2/8", "request_id": f"wrong-plan-answer-{index:04}"}
            ).status_code
            == 200
        )
    yield client, uid, mid, parent, child
    fixture.close()


def sample_plan(payload):
    evidence = [a["ref"] for a in payload["observations"]]
    goals = {q["id"]: q["learning_goal_id"] for q in payload["questions"]}
    return {
        "version": 1,
        "steps": [
            {
                "kind": "explain",
                "question_id": "sum",
                "learning_goal_id": goals["sum"],
                "resource_id": None,
                "evidence_refs": evidence,
                "reason": "Die bisherigen eigenen Versuche brauchen einen anderen Blick auf die Einteilung.",
                "expected_result": "Eine neue Aufgabe selbst bearbeiten.",
                "on_success": 1,
                "on_error": None,
            },
            {
                "kind": "check_understanding",
                "question_id": "new_sum",
                "learning_goal_id": goals["new_sum"],
                "resource_id": None,
                "evidence_refs": evidence,
                "reason": "Eine noch nicht bearbeitete Rechnung prüft den Schritt.",
                "expected_result": "Eine eigene Antwort ohne eingeblendete Lösung.",
                "on_success": None,
                "on_error": None,
            },
        ],
    }


def request(client, uid, key="instructional-plan-0001"):
    state = client.get(f"/api/units/{uid}/learning-session").json()
    return client.post(
        f"/api/units/{uid}/learning-session/plan",
        json={"request_key": key, "revision": state["revision"], "kind": "practice"},
    )


def execute(client, uid, kind, key):
    state = client.get(f"/api/units/{uid}/learning-session").json()
    result = client.post(
        f"/api/units/{uid}/learning-session/action",
        json={"request_key": key, "revision": state["revision"], "kind": kind},
    )
    assert result.status_code == 200, result.text
    return result.json()


def test_bounded_model_plan_is_reserved_once_executed_and_replanned_from_actual_answer(profile, monkeypatch):
    client, uid, _, _, _ = profile
    calls = []

    def model(config, function, payload):
        assert function == "decision"
        assert "child_id" not in payload and "family_id" not in payload and "name" not in payload
        calls.append(payload)
        return Result(sample_plan(payload), 100, 100, 0)

    monkeypatch.setattr("schulpilot.providers.request_provider", model)
    first = request(client, uid)
    assert first.status_code == 202, first.text
    assert request(client, uid).json()["id"] == first.json()["id"]
    process_next()
    value = client.get(f"/api/units/{uid}").json()
    assert value["learning_session"]["action"]["reason_code"] == "model_short_plan"
    assert value["learning_session"]["action"]["kind"] == "explain"
    assert "explanation" not in value["learning_session"]["instructional_plan"]
    assert "instructional_plan" not in value["learning_session"]["working_memory"]
    value = execute(client, uid, "explain", "model-show-0001")
    assert value["learning_session"]["instructional_plan"]["explanation"]["question_id"] == "sum"
    value = execute(client, uid, "practice", "model-continue-0001")
    assert value["learning_session"]["action"]["question_id"] == "new_sum"
    assert client.post(f"/api/units/{uid}/questions/sum/answer", json={"answer": "2/4"}).status_code == 409
    response = client.post(
        f"/api/units/{uid}/questions/new_sum/answer", json={"answer": "3/6", "request_id": "new-model-answer-0001"}
    )
    assert response.status_code == 200, response.text
    assert response.json()["outcome"] == "correct" and not response.json()["assisted"]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
        assert db.scalar(select(func.count()).select_from(Attempt)) == 3
        assert db.get(LearningMemory, uid).working["instructional_plan"]["outcomes"][0]["outcome"] == "correct"
        assert db.get(Job, first.json()["id"]).status == "completed"
    assert len(calls) == 1


@pytest.mark.parametrize("fault", ["question", "evidence", "resource", "cycle", "shown_check"])
def test_untrusted_model_plan_ids_and_false_independent_checks_are_rejected(profile, fault):
    _, uid, *_ = profile
    with DB() as db:
        _, payload = decisions.context(db, db.get(LearningUnit, uid))
    value = sample_plan(payload)
    if fault == "question":
        value["steps"][0]["question_id"] = "foreign-question"
    elif fault == "evidence":
        value["steps"][0]["evidence_refs"] = ["attempt:invented"]
    elif fault == "resource":
        value["steps"][0]["resource_id"] = "invented-resource"
    elif fault == "cycle":
        value["steps"][0]["on_success"] = 0
    else:
        value["steps"][1]["question_id"] = "sum"
    with pytest.raises(ValueError):
        decisions.validate(value, payload)


@pytest.mark.parametrize("change", ["source", "session", "answer"])
def test_late_model_plan_cannot_overwrite_current_sources_session_or_answers(profile, monkeypatch, change):
    client, uid, mid, _, _ = profile
    first = request(client, uid)
    assert first.status_code == 202

    def model(config, function, payload):
        with DB.begin() as db:
            if change == "source":
                db.get(Material, mid).revision += 1
            elif change == "session":
                db.get(Session, db.get(Job, first.json()["id"]).payload["session_id"]).revoked = True
        if change == "answer":
            assert client.post(f"/api/units/{uid}/questions/new_sum/answer", json={"answer": "3/6"}).status_code == 200
        return Result(sample_plan(payload), 100, 100, 10)

    monkeypatch.setattr("schulpilot.providers.request_provider", model)
    process_next()
    with DB() as db:
        assert db.get(Job, first.json()["id"]).status == "failed"
        assert not db.get(LearningMemory, uid).working.get("instructional_plan")
        assert db.scalar(select(Usage)).status == "failed_billed"


def test_budget_or_parent_access_cannot_create_a_decision_and_gets_are_pure(profile, api):
    client, uid, _, parent, _ = profile
    assert request(api, uid).status_code == 403
    with DB() as db:
        before = (db.scalar(select(func.count()).select_from(Activity)), db.get(LearningMemory, uid).revision)
    for _ in range(3):
        assert client.get(f"/api/units/{uid}/learning-session").status_code == 200
    with DB.begin() as db:
        assert before == (db.scalar(select(func.count()).select_from(Activity)), db.get(LearningMemory, uid).revision)
        db.get(Family, parent["families"][0]["id"]).call_limit = 0
    assert request(client, uid).status_code == 429
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 0


def test_model_selected_real_resource_is_shown_with_its_purpose_and_return_branch(profile, monkeypatch):
    from test_controller_media import tips

    client, uid, _, _, child = profile
    path, _ = tips(client, uid, child["id"])
    selected = {}

    def model(config, function, payload):
        assert payload["resources"]
        candidate = payload["resources"][0]
        selected.update(candidate)
        plan = sample_plan(payload)
        plan["steps"][0].update(kind="recommend_resource", resource_id=candidate["id"],
            reason="Dieser vorhandene Lerntipp zeigt eine andere Erklärung zum gemeinsamen Nenner.")
        return Result(plan, 100, 100, 0)

    monkeypatch.setattr("schulpilot.providers.request_provider", model)
    response = request(client, uid)
    assert response.status_code == 202, response.text
    process_next()
    state = client.get(f"/api/units/{uid}/learning-session").json()
    assert state["action"]["resources"][0]["id"] == selected["id"]
    view = client.get(path).json()
    item = next(r for r in view["recommended"] + view["additional"] if r["id"] == selected["id"])
    assert "andere Erklärung" in item["reason"]
    for kind in ("open", "watched"):
        r = client.post(path + "/interactions", json={"revision": view["revision"], "topic_id": item["topic_id"],
            "content_id": item["id"], "question_id": "sum", "kind": kind, "request_key": "model-tip-" + kind + "-0001"})
        assert r.status_code == 200, r.text
    state = client.get(f"/api/units/{uid}/learning-session").json()
    assert state["instructional_plan"]["cursor"] == 1
    assert state["action"]["kind"] == "check_understanding"
    assert state["action"]["question_id"] == "new_sum"
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Attempt)) == 2  # no understanding inferred from a video
