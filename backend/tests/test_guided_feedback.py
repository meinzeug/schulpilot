"""Saved feedback survives reloads without creating another answer or AI job."""

import pytest
from conftest import HEADERS, create_child, register
from fastapi.testclient import TestClient
from schulpilot.db import DB, Activity, Attempt, Child, Job, LearningUnit, Usage
from schulpilot.main import app
from schulpilot.synthetic import sample_unit
from sqlalchemy import func, select


@pytest.fixture
def guided(api, household):
    _, child = household
    with DB.begin() as db:
        db.get(Child, child["id"]).preferences = {"weekdays": list(range(7))}
        unit = LearningUnit(child_id=child["id"], **sample_unit(), provider="fixture", synthetic=True,
                            status="active", introduction_seen=True)
        db.add(unit)
        db.flush()
        unit_id = unit.id
        questions = unit.questions
    with TestClient(app, headers=HEADERS) as kid:
        login = kid.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"})
        kid.headers["Authorization"] = "Bearer " + login.json()["token"]
        yield kid, api, child["id"], unit_id, questions


def submit(kid, uid, q, answer, *, guided=True):
    return kid.post(f"/api/units/{uid}/questions/{q['id']}/answer",
                    json={"answer": answer, "guided_feedback": guided})


def ack(kid, uid, attempt):
    return kid.post(f"/api/units/{uid}/feedback/acknowledge", json={"attempt_id": attempt})


def test_wrong_feedback_survives_reload_and_pause_without_revealing_solution(guided):
    kid, _, _, uid, questions = guided
    first = submit(kid, uid, questions[0], "definitely not the answer")
    assert first.status_code == 200
    pending = first.json()["unit"]["pending_feedback"]
    assert pending["outcome"] == "incorrect" and pending["explanation"] is None
    assert pending["answer"] == "definitely not the answer"
    assert kid.get(f"/api/units/{uid}").json()["pending_feedback"] == pending
    assert kid.post(f"/api/units/{uid}/pause").json()["pending_feedback"] == pending
    assert ack(kid, uid, pending["attempt_id"]).json()["pending_feedback"] is None
    assert kid.get(f"/api/units/{uid}").json()["status"] == "paused"


def test_acknowledgement_idempotent_and_does_not_earn_time_or_answers(guided):
    kid, _, child_id, uid, questions = guided
    result = submit(kid, uid, questions[0], questions[0]["answer"]).json()
    pending = result["unit"]["pending_feedback"]
    assert pending["explanation"] == questions[0]["explanation"]
    for _ in range(2):
        response = ack(kid, uid, pending["attempt_id"])
        assert response.status_code == 200 and response.json()["pending_feedback"] is None
        assert response.json()["active_seconds_approx"] == 0
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Attempt)) == 1
        assert db.scalar(select(func.count()).select_from(Activity).where(Activity.kind == "feedback_seen")) == 1
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
        assert db.scalar(select(func.count()).select_from(Job)) == 0
        assert db.get(Child, child_id) is not None


def test_guided_retry_requires_feedback_ack_and_keeps_original_attempt(guided):
    kid, _, _, uid, questions = guided
    first = submit(kid, uid, questions[0], "wrong").json()["unit"]["pending_feedback"]
    assert submit(kid, uid, questions[0], questions[0]["answer"]).status_code == 409
    assert ack(kid, uid, first["attempt_id"]).status_code == 200
    second = submit(kid, uid, questions[0], questions[0]["answer"]).json()["unit"]
    assert len(second["questions"][0]["attempts"]) == 2
    assert second["pending_feedback"]["assisted"] is True
    # A delayed duplicate ACK for the old attempt must not clear the new one.
    duplicate = ack(kid, uid, first["attempt_id"])
    assert duplicate.status_code == 200
    assert duplicate.json()["pending_feedback"]["attempt_id"] == second["pending_feedback"]["attempt_id"]


def test_legacy_answers_do_not_create_old_feedback_on_upgrade(guided):
    kid, _, _, uid, questions = guided
    first = submit(kid, uid, questions[0], "wrong", guided=False)
    assert first.status_code == 200 and first.json()["unit"]["pending_feedback"] is None
    assert kid.get(f"/api/units/{uid}").json()["pending_feedback"] is None


def test_foreign_parent_and_revoked_sessions_cannot_acknowledge(guided, mailbox):
    kid, parent, child_id, uid, questions = guided
    pending = submit(kid, uid, questions[0], questions[0]["answer"]).json()["unit"]["pending_feedback"]
    assert ack(parent, uid, pending["attempt_id"]).status_code == 403
    with TestClient(app, headers=HEADERS) as foreign:
        other = register(foreign, mailbox, "other-feedback@example.org")
        other_child = create_child(foreign, other, "foreign-feedback-child")
        login = foreign.post("/api/auth/login", json={"username": "foreign-feedback-child", "password": "secure-child-pass-123"})
        assert login.status_code == 200
        foreign.headers["Authorization"] = "Bearer " + login.json()["token"]
        assert ack(foreign, uid, pending["attempt_id"]).status_code == 404
        assert foreign.get(f"/api/children/{child_id}/overview?compact=true").status_code == 404
        assert foreign.get(f"/api/children/{other_child['id']}/overview?compact=true").json()["feedback_resume"] is None
    assert kid.post("/api/auth/logout").status_code == 200
    assert ack(kid, uid, pending["attempt_id"]).status_code == 401


def test_preparing_job_metadata_is_scoped_and_readonly(guided):
    kid, _, child_id, _, _ = guided
    with DB.begin() as db:
        job = Job(child_id=child_id, kind="unit", status="queued", payload={"private": "never exposed"},
                  idempotency="own-guided-preparation")
        db.add(job)
        db.flush()
        jid = job.id
    for _ in range(2):
        data = kid.get(f"/api/children/{child_id}/overview?compact=true").json()
        assert data["learning_preparation"] == {"id": jid, "status": "queued"}
        assert "never exposed" not in str(data)
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 1
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_completed_round_keeps_last_feedback_until_explicit_continue(guided, monkeypatch):
    from schulpilot import coaching

    monkeypatch.setattr(coaching, "schedule", lambda *_args, **_kwargs: None)
    kid, _, child_id, uid, questions = guided
    with DB.begin() as db:
        db.get(LearningUnit, uid).questions = questions[:1]
    result = submit(kid, uid, questions[0], questions[0]["answer"]).json()["unit"]
    assert result["status"] == "completed"
    pending = result["pending_feedback"]
    assert kid.get(f"/api/units/{uid}").json()["pending_feedback"] == pending
    home = kid.get(f"/api/children/{child_id}/overview?compact=true").json()
    assert home["feedback_resume"]["id"] == uid
    assert home["feedback_resume"]["status"] == "completed"
    assert home["feedback_resume"]["pending_feedback"] is True
    assert "questions" not in home["feedback_resume"]
    assert "answer" not in home["feedback_resume"]
    assert ack(kid, uid, pending["attempt_id"]).json()["status"] == "completed"
    assert kid.get(f"/api/units/{uid}").json()["pending_feedback"] is None
    assert kid.get(f"/api/children/{child_id}/overview?compact=true").json()["feedback_resume"] is None


def test_ack_does_not_mark_another_units_attempt_or_unoffered_feedback(guided):
    kid, _, child_id, uid, questions = guided
    with DB.begin() as db:
        other = LearningUnit(child_id=child_id, **sample_unit(), provider="fixture", synthetic=True)
        db.add(other)
        db.flush()
        other_id = other.id
    result = submit(kid, uid, questions[0], "wrong").json()["unit"]
    attempt = result["pending_feedback"]["attempt_id"]
    assert ack(kid, other_id, attempt).status_code == 404
    assert ack(kid, uid, "invalid").status_code == 422
    assert kid.get(f"/api/units/{uid}").json()["pending_feedback"]["attempt_id"] == attempt
    events = kid.get(f"/api/children/{child_id}/activity").json()
    assert all(e["kind"] not in ("feedback_pending", "feedback_seen") for e in events)


def test_legacy_other_device_answer_cannot_be_cleared_by_stale_feedback(guided):
    kid, _, _, uid, questions = guided
    first = submit(kid, uid, questions[0], "wrong").json()["unit"]["pending_feedback"]
    newer = submit(kid, uid, questions[0], "still wrong", guided=False)
    assert newer.status_code == 200
    assert ack(kid, uid, first["attempt_id"]).status_code == 409
    assert len(kid.get(f"/api/units/{uid}").json()["questions"][0]["attempts"]) == 2


def test_two_devices_acknowledge_exactly_once(guided):
    from concurrent.futures import ThreadPoolExecutor

    kid, _, _, uid, questions = guided
    pending = submit(kid, uid, questions[0], questions[0]["answer"]).json()["unit"]["pending_feedback"]
    authorization = kid.headers["Authorization"]

    def acknowledge_on_device(_):
        with TestClient(app, headers={**HEADERS, "Authorization": authorization}) as device:
            return ack(device, uid, pending["attempt_id"]).status_code

    with ThreadPoolExecutor(max_workers=2) as pool:
        assert list(pool.map(acknowledge_on_device, range(2))) == [200, 200]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Activity).where(Activity.kind == "feedback_seen")) == 1
