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
    reviews = []
    monkeypatch.setattr("schulpilot.coaching.schedule", lambda unit_id, **kw: reviews.append((unit_id, kw)))

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
        f"/api/units/{uid}/questions/new_sum/answer", json={"answer": "3/6", "request_id": "new-model-answer-0001", "guided_feedback": True}
    )
    assert response.status_code == 200, response.text
    assert response.json()["outcome"] == "correct" and not response.json()["assisted"]
    assert response.json()["unit"]["status"] == "completed"
    assert response.json()["unit"]["pending_feedback"]["attempt_id"] == response.json()["attempt_id"]
    assert client.get(f"/api/units/{uid}").json()["pending_feedback"]["outcome"] == "correct"
    assert client.post(f"/api/units/{uid}/feedback/acknowledge", json={"attempt_id": response.json()["attempt_id"]}).json()["pending_feedback"] is None
    assert next(q for q in response.json()["unit"]["questions"] if q["id"] == "sum")["controller_deferred"]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
        assert db.scalar(select(func.count()).select_from(Attempt)) == 3
        assert db.get(LearningMemory, uid).working["instructional_plan"]["outcomes"][0]["outcome"] == "correct"
        assert db.get(Job, first.json()["id"]).status == "completed"
        assert [a.outcome for a in db.scalars(select(Attempt).where(Attempt.unit_id == uid, Attempt.question_id == "sum").order_by(Attempt.created))] == ["incorrect", "incorrect"]
        assert db.get(LearningMemory, uid).working["instructional_deferrals"]["question_ids"] == ["sum"]
        assert db.scalar(select(func.count()).select_from(Activity).where(Activity.unit_id == uid, Activity.kind == "unit_completed")) == 1
    assert len(calls) == 1
    assert reviews == [(uid, {"automatic": True})]


@pytest.mark.parametrize("same_question", [False, True])
def test_hint_or_return_to_shown_question_does_not_defer_an_incorrect_answer(profile, monkeypatch, same_question):
    client, uid, *_ = profile

    def model(_c, _f, payload):
        plan = sample_plan(payload)
        if same_question:
            plan["steps"][1].update(kind="practice", question_id="sum", learning_goal_id=plan["steps"][0]["learning_goal_id"])
        else:
            plan["steps"][0]["kind"] = "hint"
        return Result(plan, 100, 100, 0)

    monkeypatch.setattr("schulpilot.providers.request_provider", model)
    assert request(client, uid).status_code == 202
    process_next()
    if same_question:
        execute(client, uid, "explain", "same-question-show-0001")
    else:
        assert client.post(f"/api/units/{uid}/questions/sum/hint").status_code == 200
    execute(client, uid, "practice", "not-deferred-next-0001")
    with DB() as db:
        assert not decisions.deferred(db, db.get(LearningUnit, uid))
        assert "instructional_deferrals" not in db.get(LearningMemory, uid).working


@pytest.mark.parametrize("trigger", ["paused_resume", "active_resume", "seen_ack", "finish_action"])
def test_exhausted_legacy_plan_recovers_only_on_conscious_post_and_preserves_answers(profile, monkeypatch, trigger):
    from schulpilot import learning

    client, uid, _, _, _ = profile
    monkeypatch.setattr("schulpilot.providers.request_provider", lambda _c, _f, payload: Result(sample_plan(payload), 100, 100, 0))
    reviews = []
    monkeypatch.setattr("schulpilot.coaching.schedule", lambda unit_id, **kw: reviews.append((unit_id, kw)))
    assert request(client, uid).status_code == 202
    process_next()
    execute(client, uid, "explain", "legacy-explanation-0001")
    execute(client, uid, "practice", "legacy-continue-0001")
    # Reproduce release76: the answer and its acknowledgement were saved, but
    # no deferral/round completion was persisted by the old implementation.
    with monkeypatch.context() as old:
        old.setattr(learning, "complete_round", lambda *_a, **_kw: False)
        response = client.post(f"/api/units/{uid}/questions/new_sum/answer",
            json={"answer": "3/6", "request_id": "legacy-independent-0001", "guided_feedback": True})
        assert response.status_code == 200, response.text
        attempt_id = response.json()["attempt_id"]
        assert client.post(f"/api/units/{uid}/feedback/acknowledge", json={"attempt_id": attempt_id}).status_code == 200
    with DB.begin() as db:
        memory = db.get(LearningMemory, uid)
        working = dict(memory.working)
        working.pop("instructional_deferrals")
        working["instructional_plan"].pop("source_signature")
        memory.working = working
        if trigger == "paused_resume":
            db.get(LearningUnit, uid).status = "paused"
        before = [(a.id, a.question_id, a.outcome, a.assisted, a.answer) for a in db.scalars(select(Attempt).where(Attempt.unit_id == uid).order_by(Attempt.created))]
        counts = (db.scalar(select(func.count()).select_from(Activity)), db.scalar(select(func.count()).select_from(Usage)), memory.revision)
    for _ in range(2):
        value = client.get(f"/api/units/{uid}").json()
        assert value["status"] != "completed"
        assert value["learning_session"]["action"]["kind"] == "finish_round"
        assert not value["learning_session"]["can_request_decision"]
        assert value["pending_feedback"] is None
    with DB() as db:
        assert counts == (db.scalar(select(func.count()).select_from(Activity)), db.scalar(select(func.count()).select_from(Usage)), db.get(LearningMemory, uid).revision)
        assert "instructional_deferrals" not in db.get(LearningMemory, uid).working
    if trigger.endswith("resume"):
        response = client.post(f"/api/units/{uid}/start")
    elif trigger == "seen_ack":
        response = client.post(f"/api/units/{uid}/feedback/acknowledge", json={"attempt_id": attempt_id})
    else:
        response = client.post(f"/api/units/{uid}/learning-session/action", json={
            "kind": "finish_round", "request_key": "legacy-finish-0001", "revision": value["learning_session"]["revision"]})
    assert response.status_code == 200, response.text
    assert response.json()["status"] == "completed"
    assert response.json()["pending_feedback"] is None
    assert client.post(f"/api/units/{uid}/start").json()["status"] == "completed"
    with DB() as db:
        assert before == [(a.id, a.question_id, a.outcome, a.assisted, a.answer) for a in db.scalars(select(Attempt).where(Attempt.unit_id == uid).order_by(Attempt.created))]
        assert db.get(LearningMemory, uid).working["instructional_deferrals"]["question_ids"] == ["sum"]
        assert db.scalar(select(func.count()).select_from(Usage)) == counts[1]
        assert db.scalar(select(func.count()).select_from(Activity).where(Activity.unit_id == uid, Activity.kind == "unit_completed")) == 1
    assert reviews == [(uid, {"automatic": True})]


@pytest.mark.parametrize("change", ["source", "unshown", "hint", "foreign_outcome"])
def test_legacy_deferral_requires_current_sources_shown_solution_and_actual_successor(profile, monkeypatch, change):
    from schulpilot import learning

    client, uid, mid, _, _ = profile
    monkeypatch.setattr("schulpilot.providers.request_provider", lambda _c, _f, payload: Result(sample_plan(payload), 100, 100, 0))
    assert request(client, uid).status_code == 202
    process_next()
    execute(client, uid, "explain", "legacy-guard-show-0001")
    execute(client, uid, "practice", "legacy-guard-next-0001")
    with monkeypatch.context() as old:
        old.setattr(learning, "complete_round", lambda *_a, **_kw: False)
        assert client.post(f"/api/units/{uid}/questions/new_sum/answer", json={"answer": "3/6"}).status_code == 200
    with DB.begin() as db:
        memory = db.get(LearningMemory, uid)
        working = dict(memory.working)
        working.pop("instructional_deferrals")
        working["instructional_plan"].pop("source_signature")
        if change == "source":
            db.get(Material, mid).revision += 1
        elif change == "unshown":
            for event in db.scalars(select(Activity).where(Activity.unit_id == uid, Activity.kind == "explanation")):
                db.delete(event)
        elif change == "hint":
            working["instructional_plan"]["steps"][0]["kind"] = "hint"
        else:
            working["instructional_plan"]["outcomes"][0]["attempt_ref"] = "attempt:another-unit"
        memory.working = working
    with DB() as db:
        assert not decisions.deferred(db, db.get(LearningUnit, uid))
    assert client.get(f"/api/units/{uid}").json()["learning_session"]["action"]["kind"] != "finish_round"


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
