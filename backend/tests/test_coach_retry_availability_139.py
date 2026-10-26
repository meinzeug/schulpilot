"""Explicit practice availability is read-only and retains the existing two-attempt cap."""

import copy

import pytest
import test_coaching_stages as stages
from conftest import create_child
from schulpilot import coaching
from schulpilot.db import DB, Activity, Attempt, Job, LearningUnit, UnitCoaching, Usage, User
from schulpilot.providers import ProviderError
from sqlalchemy import func, select

normal_unit = stages.normal_unit
deferred_review = stages.deferred_review


def preserved(db, unit_id):
    unit = db.get(LearningUnit, unit_id)
    item = db.get(UnitCoaching, unit_id)
    return (copy.deepcopy(unit.questions), copy.deepcopy(item.report), item.request_count,
        [(a.id, a.question_id, a.answer, a.outcome) for a in db.scalars(
            select(Attempt).where(Attempt.unit_id == unit_id).order_by(Attempt.id))])


def counts(db):
    return tuple(db.scalar(select(func.count()).select_from(model))
        for model in (Job, Usage, Activity, Attempt, LearningUnit))


def test_get_reflects_two_attempt_cap_without_cost_or_losing_saved_work(deferred_review, monkeypatch):
    client, unit_id, _, _, _, original, _ = deferred_review
    calls = []

    def failed(*_args, **_kwargs):
        calls.append(True)
        raise ProviderError("Künstlicher technischer Fehler.")

    monkeypatch.setattr(coaching, "request_provider", failed)
    with DB() as db:
        before = preserved(db, unit_id)
        expected_counts = counts(db)
    for _ in range(2):
        assert client.get(f"/api/units/{unit_id}").json()["coaching"]["practice_can_retry"] is True
    with DB() as db:
        assert counts(db) == expected_counts
        assert preserved(db, unit_id) == before
    first = stages.ask_practice(client, unit_id, "retry-139-first")
    assert client.get(f"/api/units/{unit_id}").json()["coaching"]["practice_can_retry"] is False
    stages.process_next()
    assert client.get(f"/api/units/{unit_id}").json()["coaching"]["practice_can_retry"] is True
    second = stages.ask_practice(client, unit_id, "retry-139-second")
    assert client.get(f"/api/units/{unit_id}").json()["coaching"]["practice_can_retry"] is False
    stages.process_next()
    with DB() as db:
        expected_counts = counts(db)
    for _ in range(2):
        saved = client.get(f"/api/units/{unit_id}").json()
        assert saved["coaching"]["practice_can_retry"] is False
        assert saved["coaching"]["practice_status"] == "failed"
        assert saved["coaching"]["report"] == original["coaching"]["report"]
        assert saved["questions"] == original["questions"]
    # Same key is still a replay even after the attempt cap, never a new hold.
    assert stages.ask_practice(client, unit_id, "retry-139-second") == second
    assert stages.ask_practice(client, unit_id, "retry-139-first") == first
    refused = client.post(f"/api/units/{unit_id}/practice", headers={"Idempotency-Key": "retry-139-third"})
    assert refused.status_code == 409 and refused.json()["detail"] == coaching.PRACTICE_LIMIT_MESSAGE
    assert "Eltern" not in refused.json()["detail"] and "vorhandene Runde" in refused.json()["detail"]
    with DB() as db:
        assert counts(db) == expected_counts
        assert preserved(db, unit_id) == before
        assert db.scalar(select(func.count()).select_from(Job).where(Job.kind == "coach_practice")) == 2
    assert calls == [True, True]


@pytest.mark.parametrize("state", ["pending_review", "not_deferred", "existing_next", "later_review", "unfinished_unit"])
def test_nonpreparation_states_report_false_without_creating_jobs(deferred_review, state):
    client, unit_id, _, _, _, _, _ = deferred_review
    with DB.begin() as db:
        item = db.get(UnitCoaching, unit_id)
        if state == "pending_review":
            item.status = "pending"
        elif state == "not_deferred":
            item.report = {**item.report, "practice_deferred": False}
        elif state == "existing_next":
            item.next_unit_id = unit_id
        elif state == "later_review":
            item.decision = "spaced"
        else:
            db.get(LearningUnit, unit_id).status = "active"
    with DB() as db:
        before = counts(db)
    response = client.get(f"/api/units/{unit_id}")
    assert response.status_code == 200
    assert response.json()["coaching"]["practice_can_retry"] is False
    with DB() as db:
        assert counts(db) == before


def test_count_is_bound_to_child_unit_and_practice_kind(deferred_review, api):
    client, unit_id, _, parent, kid, _, _ = deferred_review
    sibling = create_child(api, parent, "retry139-sibling")
    with DB.begin() as db:
        db.add_all([
            Job(child_id=kid["id"], kind="coach_practice", payload={"unit_id": "f" * 32},
                status="failed", idempotency="139-other-unit"),
            Job(child_id=sibling["id"], kind="coach_practice", payload={"unit_id": unit_id},
                status="failed", idempotency="139-other-child"),
            Job(child_id=kid["id"], kind="unit", payload={"unit_id": unit_id},
                status="failed", idempotency="139-other-kind"),
        ])
    assert client.get(f"/api/units/{unit_id}").json()["coaching"]["practice_can_retry"] is True
    with DB() as db:
        assert coaching.practice_attempt_count(db, db.get(LearningUnit, unit_id)) == 0


def test_authorized_read_does_not_add_parent_admin_or_sibling_practice_rights(deferred_review, api):
    client, unit_id, _, parent, _, _, _ = deferred_review
    assert api.get(f"/api/units/{unit_id}").status_code == 200
    assert api.post(f"/api/units/{unit_id}/practice", headers={"Idempotency-Key": "139-parent"}).status_code == 403
    sibling = create_child(api, parent, "retry139-other-owner")
    response = client.post("/api/auth/login", json={"username": sibling["username"], "password": "secure-child-pass-123"})
    client.headers["Authorization"] = "Bearer " + response.json()["token"]
    assert client.get(f"/api/units/{unit_id}").status_code == 404
    assert client.post(f"/api/units/{unit_id}/practice", headers={"Idempotency-Key": "139-sibling"}).status_code == 404
    with DB.begin() as db:
        db.get(User, parent["id"]).role = "admin"
    assert api.get(f"/api/units/{unit_id}").status_code == 403
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job).where(Job.kind == "coach_practice")) == 0
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
