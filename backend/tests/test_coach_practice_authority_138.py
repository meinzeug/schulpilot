"""Synthetic session-bound explicit practice; no real users or provider calls."""

import copy

import pytest
import test_coach_output_routing_138 as routing
import test_coaching_stages as stages
from conftest import create_child
from schulpilot import coaching
from schulpilot.db import DB, Attempt, Child, Family, Job, LearningUnit, Session, UnitCoaching, Usage, now
from schulpilot.providers import Result
from sqlalchemy import func, select

normal_unit = stages.normal_unit
deferred_review = stages.deferred_review
no_network = routing.no_network


def preserved(db, unit_id):
    unit = db.get(LearningUnit, unit_id)
    return (
        copy.deepcopy(unit.questions),
        copy.deepcopy(db.get(UnitCoaching, unit_id).report),
        [
            (a.id, a.question_id, a.answer, a.outcome)
            for a in db.scalars(select(Attempt).where(Attempt.unit_id == unit_id).order_by(Attempt.id))
        ],
    )


@pytest.mark.parametrize("invalid", ["logout", "expired", "revoked", "inactive", "kind_switch", "family_switch"])
def test_invalid_saved_authority_before_call_cancels_without_provider_or_publish(
    deferred_review, monkeypatch, api, invalid
):
    client, unit_id, _, parent, kid, _, _ = deferred_review
    job_id = stages.ask_practice(client, unit_id, "authority-before-138")
    with DB() as db:
        job = db.get(Job, job_id)
        before = preserved(db, unit_id)
        session_id = job.payload["session_id"]
        assert job.payload["family_id"] == db.get(Child, kid["id"]).family_id
    if invalid == "logout":
        assert client.post("/api/auth/logout").status_code == 200
    elif invalid == "kind_switch":
        sibling = create_child(api, parent, "practice-authority-sibling")
        logged = client.post(
            "/api/auth/login", json={"username": sibling["username"], "password": "secure-child-pass-123"}
        )
        assert logged.status_code == 200
    else:
        with DB.begin() as db:
            session = db.get(Session, session_id)
            if invalid == "expired":
                session.expires = int(now()) - 1
            elif invalid == "revoked":
                session.revoked = True
            elif invalid == "inactive":
                session.seen = int(now()) - 8 * 86400
            else:
                family = Family(name="Künstliche andere Familie")
                db.add(family)
                db.flush()
                db.get(Child, kid["id"]).family_id = family.id
    calls = []

    def forbidden(*args, **kwargs):
        calls.append(True)
        raise AssertionError("No provider call for invalid authority")

    monkeypatch.setattr(coaching, "request_provider", forbidden)
    stages.process_next()
    with DB() as db:
        assert db.get(Job, job_id).status == "failed"
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        assert usage.cost_micros == 0 and usage.cost_source == "cancelled"
        assert preserved(db, unit_id) == before
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 1
    assert calls == []


@pytest.mark.parametrize("invalid", ["logout", "family_switch", "kind_switch"])
def test_authority_changed_during_call_discards_output_but_keeps_real_billing(
    deferred_review, monkeypatch, api, invalid
):
    client, unit_id, _, parent, kid, _, _ = deferred_review
    sibling = create_child(api, parent, "during-authority-sibling") if invalid == "kind_switch" else None
    job_id = stages.ask_practice(client, unit_id, "authority-during-138")
    output = stages.practice_output(unit_id)
    with DB() as db:
        before = preserved(db, unit_id)
        session_id = db.get(Job, job_id).payload["session_id"]
    calls = []

    def model(*args, **kwargs):
        calls.append(True)
        if invalid == "logout":
            assert client.post("/api/auth/logout").status_code == 200
        elif invalid == "kind_switch":
            assert (
                client.post(
                    "/api/auth/login", json={"username": sibling["username"], "password": "secure-child-pass-123"}
                ).status_code
                == 200
            )
        else:
            with DB.begin() as db:
                family = Family(name="Künstlicher Familienwechsel")
                db.add(family)
                db.flush()
                db.get(Child, kid["id"]).family_id = family.id
        return Result(output, 16000, 4000, 3000, cost_source="reported")

    monkeypatch.setattr(coaching, "request_provider", model)
    stages.process_next()
    with DB() as db:
        assert db.get(Job, job_id).status == "failed"
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        assert usage.status == "failed_billed" and usage.cost_micros == 3000 and usage.cost_source == "reported"
        assert db.get(Session, session_id) is not None
        assert preserved(db, unit_id) == before
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 1
    assert len(calls) == 1


def test_replay_from_new_session_keeps_original_binding_and_only_explicit_new_key_binds_current_session(
    deferred_review, monkeypatch
):
    client, unit_id, _, _, _, _, _ = deferred_review
    first = stages.ask_practice(client, unit_id, "session-stable-key-138")
    with DB() as db:
        original_payload = copy.deepcopy(db.get(Job, first).payload)
        usages = db.scalar(select(func.count()).select_from(Usage))
    logged = client.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"})
    assert logged.status_code == 200
    client.headers["Authorization"] = "Bearer " + logged.json()["token"]
    assert stages.ask_practice(client, unit_id, "session-stable-key-138") == first
    with DB() as db:
        assert db.get(Job, first).payload == original_payload
        assert db.scalar(select(func.count()).select_from(Usage)) == usages
        assert db.get(Session, original_payload["session_id"]).revoked
    calls = []

    def model(*args, **kwargs):
        calls.append(True)
        return Result(stages.practice_output(unit_id), 100, 200, 1000, cost_source="reported")

    monkeypatch.setattr(coaching, "request_provider", model)
    stages.process_next()
    assert calls == []
    second = stages.ask_practice(client, unit_id, "session-fresh-conscious-key-138")
    with DB() as db:
        fresh = db.get(Job, second).payload
        assert fresh["session_id"] != original_payload["session_id"] and fresh["practice_number"] == 2
        assert not db.get(Session, fresh["session_id"]).revoked
    stages.process_next()
    with DB() as db:
        assert db.get(Job, second).status == "completed"
    assert len(calls) == 1


def test_legacy_unbound_job_replay_is_not_reauthorized_and_worker_refuses_before_call(deferred_review, monkeypatch):
    client, unit_id, _, _, _, _, _ = deferred_review
    first = stages.ask_practice(client, unit_id, "legacy-key-138")
    with DB.begin() as db:
        job = db.get(Job, first)
        job.payload = {k: v for k, v in job.payload.items() if k not in ("session_id", "family_id")}
        legacy = copy.deepcopy(job.payload)
        usages = db.scalar(select(func.count()).select_from(Usage))
        before = preserved(db, unit_id)
    assert stages.ask_practice(client, unit_id, "legacy-key-138") == first
    with DB() as db:
        assert db.get(Job, first).payload == legacy
        assert db.scalar(select(func.count()).select_from(Usage)) == usages
    calls = []

    def forbidden(*args, **kwargs):
        calls.append(True)
        raise AssertionError("Legacy has no session authority")

    monkeypatch.setattr(coaching, "request_provider", forbidden)
    stages.process_next()
    with DB() as db:
        assert db.get(Job, first).status == "failed" and db.get(Job, first).payload == legacy
        usage = db.scalar(select(Usage).where(Usage.job_id == first))
        assert usage.cost_micros == 0 and usage.cost_source == "cancelled"
        assert preserved(db, unit_id) == before
    assert calls == []
    second = stages.ask_practice(client, unit_id, "new-key-after-legacy-138")
    with DB() as db:
        assert db.get(Job, second).payload.get("session_id")
