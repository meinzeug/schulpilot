"""Artificial own families/units and mocked FCM only; no device delivery claim."""

import pytest
from conftest import HEADERS
from fastapi.testclient import TestClient
from schulpilot import notifications as n
from schulpilot import ready_notifications as ready
from schulpilot import worker
from schulpilot.db import (
    DB,
    Child,
    Job,
    LearningUnit,
    Material,
    Message,
    PushDelivery,
    PushDevice,
    Session,
    UnitSource,
    User,
    now,
    uid,
)
from schulpilot.main import app
from schulpilot.security import Principal
from schulpilot.study_authority import bind
from schulpilot.synthetic import sample_unit
from sqlalchemy import func, select
from test_notifications import device, enable


@pytest.fixture
def case(api, household):
    parent, child = household
    with DB.begin() as db:
        actor = db.get(User, parent["id"])
        session = db.scalar(select(Session).where(Session.user_id == actor.id))
        model = db.get(Child, child["id"])
        origin = bind(db, Principal(actor, session), model)
        material = Material(
            child_id=model.id,
            title="Synthetic notebook",
            subject="Mathematik",
            topic="Brüche",
            content="Ein Bruch besteht aus Zähler und Nenner.",
            confirmed=True,
            status="confirmed",
            legibility="readable",
        )
        db.add(material)
        db.flush()
        unit = LearningUnit(
            child_id=model.id, material_id=material.id, synthetic=False, provider="synthetic-test", **sample_unit()
        )
        db.add(unit)
        db.flush()
        db.add(UnitSource(unit_id=unit.id, material_id=material.id, revision=material.revision))
        job = Job(
            child_id=model.id,
            kind="unit",
            status="completed",
            finished=int(now()),
            idempotency=uid(),
            payload={ready.ORIGIN: origin},
            result={"unit_id": unit.id},
        )
        db.add(job)
        db.flush()
        return dict(
            child=model.id,
            unit=unit.id,
            job=job.id,
            material=material.id,
            session=session.id,
            parent=actor.id,
            created=job.finished,
        )


def remember(case):
    with DB.begin() as db:
        return ready.remember(db, db.get(Job, case["job"]))


def test_inbox_is_created_once_after_real_saved_completion_without_push_opt_in(api, case):
    assert remember(case)
    assert not remember(case)
    for _ in range(2):
        response = api.get("/api/notifications/inbox")
        assert response.status_code == 200
        items = [item for item in response.json()["items"] if item["kind"] == "round_ready"]
        assert len(items) == 1 and items[0]["route"] == "/unit/" + case["unit"]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Message)) == 1
        assert db.scalar(select(func.count()).select_from(PushDelivery)) == 0
        assert db.get(Job, case["job"]).result == {"unit_id": case["unit"]}
        message = db.scalar(select(Message))
        assert message.context == {"unit_id": case["unit"]} and message.body == "Deine Lernrunde ist bereit."
        assert "Sitzung" not in message.body


@pytest.mark.parametrize(
    "change",
    [
        "source",
        "unconfirmed",
        "deleted",
        "completed",
        "foreign",
        "revoked",
        "disabled",
        "legacy",
        "not_completed",
        "wrong_result",
    ],
)
def test_no_unready_stale_foreign_or_unbound_round_notice(case, change):
    with DB.begin() as db:
        unit, job = db.get(LearningUnit, case["unit"]), db.get(Job, case["job"])
        if change == "source":
            db.get(Material, case["material"]).revision += 1
        elif change == "unconfirmed":
            db.get(Material, case["material"]).confirmed = False
        elif change == "deleted":
            db.delete(unit)
        elif change == "completed":
            unit.status = "completed"
        elif change == "foreign":
            user = User(
                username="other-ready-child",
                display_name="Other synthetic child",
                role="child",
                verified=True,
                password_hash="synthetic",
            )
            db.add(user)
            db.flush()
            child = Child(user_id=user.id, family_id=db.get(Child, case["child"]).family_id, grade=6)
            db.add(child)
            db.flush()
            job.child_id = child.id
        elif change == "revoked":
            db.get(Session, case["session"]).revoked = True
        elif change == "disabled":
            db.get(User, case["parent"]).disabled = True
        elif change == "legacy":
            job.payload = {}
        elif change == "not_completed":
            job.status = "running"
        else:
            job.result = {"unit_id": "a" * 32}
    assert not remember(case)
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Message)) == 0


def child_device(api, case, tmp_path):
    enable(tmp_path)
    with DB.begin() as db:
        child = db.get(Child, case["child"])
        child.preferences = {"push_consent": True, "reminders": False, "quiet_start": 0, "quiet_end": 0}
    client = TestClient(app, headers=HEADERS)
    client.__enter__()
    response = client.post(
        "/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}
    ).json()
    client.headers["Authorization"] = "Bearer " + response["token"]
    identifier = device(client)["id"]
    return client, identifier


def test_round_push_is_per_event_and_tap_targets_ready_unit(case, api, tmp_path, monkeypatch):
    assert remember(case)
    client, identifier = child_device(api, case, tmp_path)
    sent = []
    monkeypatch.setattr(n, "send_fcm", lambda *args, **kwargs: sent.append((args, kwargs)))
    try:
        with DB.begin() as db:
            n.prepare(db)
            n.prepare(db)
        assert n.deliver_one(DB)
        assert not n.deliver_one(DB)
        assert len(sent) == 1
        assert sent[0][1] == {"unit_path": "/unit/" + case["unit"]}
        assert "Synthetic notebook" not in str(sent) and "Brüche" not in str(sent)
        with DB() as db:
            rows = list(db.scalars(select(PushDelivery)))
            assert len(rows) == 1 and rows[0].status == "accepted"
            assert ready.KIND in rows[0].dedup_key
            assert rows[0].device_id == identifier
    finally:
        client.__exit__(None, None, None)


@pytest.mark.parametrize(
    "change", ["child_consent", "device_category", "source", "session", "child_quiet", "device_quiet", "round_started"]
)
def test_send_rechecks_optin_current_sources_session_and_quiet_time(case, api, tmp_path, monkeypatch, change):
    assert remember(case)
    client, identifier = child_device(api, case, tmp_path)
    try:
        with DB.begin() as db:
            n.prepare(db)
            assert db.scalar(select(func.count()).select_from(PushDelivery)) == 1
        with DB.begin() as db:
            child = db.get(Child, case["child"])
            dev = db.get(PushDevice, identifier)
            if change == "child_consent":
                child.preferences = {**child.preferences, "push_consent": False}
            elif change == "device_category":
                dev.reminders = False
            elif change == "source":
                db.get(Material, case["material"]).revision += 1
            elif change == "session":
                db.get(Session, dev.session_id).revoked = True
            elif change == "round_started":
                db.get(LearningUnit, case["unit"]).status = "active"
            else:
                from datetime import datetime, timezone

                hour = datetime.fromtimestamp(now(), timezone.utc).hour
                if change == "device_quiet":
                    dev.timezone, dev.quiet_start, dev.quiet_end = "UTC", hour, (hour + 1) % 24
                else:
                    child.preferences = {
                        **child.preferences,
                        "timezone": "UTC",
                        "quiet_start": hour,
                        "quiet_end": (hour + 1) % 24,
                    }
        sent = []
        monkeypatch.setattr(n, "send_fcm", lambda *a, **kw: sent.append((a, kw)))
        assert n.deliver_one(DB)
        assert sent == []
        with DB() as db:
            assert db.scalar(select(PushDelivery)).status == "suppressed"
    finally:
        client.__exit__(None, None, None)


@pytest.mark.parametrize(
    "suffix", ["\n", "\u2028", "?extra=1", "#fragment", "/../app", "?redirect=https://example.invalid"]
)
def test_fcm_accepts_only_exact_local_unit_path(suffix):
    with pytest.raises(n.FcmError):
        n.send_fcm("SYNTHETIC", ready.KIND, unit_path="/unit/" + "a" * 32 + suffix)


def test_worker_hook_does_not_undo_completed_unit_if_notifier_fails(case, monkeypatch):
    def failure(*args):
        raise RuntimeError("synthetic closed failure")

    monkeypatch.setattr(ready, "remember", failure)
    worker.process(case["job"])
    with DB() as db:
        assert db.get(Job, case["job"]).status == "completed"
        assert db.get(LearningUnit, case["unit"]).status == "not_started"


def test_recovery_after_worker_crash_creates_only_one_bound_notice(case):
    ready.advance_one()
    ready.advance_one()
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Message)) == 1
        assert db.get(Job, case["job"]).result == {"unit_id": case["unit"]}


def test_incomplete_graphic_is_not_announced_as_a_finished_round(case):
    from schulpilot.visual_reference_models import UnitVisualSnapshot

    with DB.begin() as db:
        db.add(
            UnitVisualSnapshot(
                unit_id=case["unit"],
                source_signature="s" * 64,
                status="incomplete",
                steps=[],
                question_steps={},
                source_bindings=[],
                receipts=[],
            )
        )
    assert not remember(case)
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Message)) == 0


def test_inbox_does_not_retain_stale_click_target_after_source_change(api, case):
    assert remember(case)
    with DB.begin() as db:
        db.get(Material, case["material"]).revision += 1
    response = api.get("/api/notifications/inbox")
    assert response.status_code == 200
    assert not any(item["kind"] == "round_ready" for item in response.json()["items"])
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Message)) == 1


def test_actual_fcm_adapter_contains_only_neutral_text_and_allowlisted_unit_route(api, tmp_path, monkeypatch):
    import json
    from pathlib import Path

    import httpx
    from google.oauth2 import service_account
    from schulpilot.config import settings

    enable(tmp_path)
    Path(settings.fcm_service_account_file).write_text(
        json.dumps(
            {
                "type": "service_account",
                "project_id": "synthetic-project",
                "token_uri": "https://oauth2.googleapis.com/token",
            }
        )
    )

    class Credential:
        token = "SYNTHETIC_ACCESS_TOKEN"
        valid = True

        def refresh(self, request):
            pass

    monkeypatch.setattr(service_account.Credentials, "from_service_account_info", lambda *a, **kw: Credential())
    captured = []
    real = httpx.Client

    def handler(request):
        captured.append(json.loads(request.content))
        return httpx.Response(200, json={"name": "projects/synthetic/messages/accepted"})

    monkeypatch.setattr(n.httpx, "Client", lambda **kw: real(transport=httpx.MockTransport(handler)))
    target = "/unit/" + "a" * 32
    n.send_fcm("SYNTHETIC_FCM_TOKEN", ready.KIND, unit_path=target)
    assert len(captured) == 1
    message = captured[0]["message"]
    assert message["data"] == {"route": target}
    assert message["notification"] == {
        "title": "SchuleSchlau",
        "body": "Es gibt Neuigkeiten in SchuleSchlau. Öffne deinen Lernraum.",
    }
    assert message["webpush"]["fcm_options"]["link"] == settings.public_url + target
    assert message["android"]["priority"] == "high"
    assert message["android"]["ttl"] == "60s"


def test_parallel_local_notice_recovery_creates_exactly_one_receipt(case):
    from concurrent.futures import ThreadPoolExecutor

    from schulpilot.db import engine

    if engine.dialect.name != "postgresql":
        pytest.skip("Real row-lock ready-notice race is covered on PostgreSQL")
    with ThreadPoolExecutor(max_workers=2) as pool:
        list(pool.map(lambda _: ready.advance_one(), range(2)))
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Message)) == 1
        assert len(db.get(Job, case["job"]).payload[ready.RECEIPTS]) == 1


@pytest.mark.parametrize("creator_kind", ["unit", "coach_practice", "study_block", "controller_check"])
def test_visual_sidecar_completion_notifies_original_round_immediately(case, monkeypatch, creator_kind):
    from schulpilot.visual_reference_models import UnitVisualSnapshot

    with DB.begin() as db:
        original = db.get(Job, case["job"])
        original.kind, original.finished = creator_kind, int(now()) - 2
        db.add(UnitVisualSnapshot(
            unit_id=case["unit"], source_signature="v" * 64, status="incomplete", steps=[],
            question_steps={}, receipts=[],
            source_bindings=[{"material_id": case["material"], "revision": 1}],
        ))
        sidecar = Job(
            child_id=case["child"], kind="unit_visuals", status="running", idempotency=uid(),
            payload={"unit_id": case["unit"]},
        )
        db.add(sidecar)
        db.flush()
        sidecar_id = sidecar.id
    assert not remember(case)

    def finish_graphic(identifier):
        assert identifier == sidecar_id
        with DB.begin() as db:
            db.get(UnitVisualSnapshot, case["unit"]).status = "ready"
            job = db.get(Job, identifier)
            job.status, job.finished = "completed", int(now())
            # The sidecar has the same output unit_id and a later finish time.
            # It must not shadow the bound original round in the lookup.
            job.result = {"unit_id": case["unit"], "visual_status": "ready"}

    monkeypatch.setattr(worker, "_process", finish_graphic)
    worker.process(sidecar_id)
    worker.process(sidecar_id)
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Message)) == 1
        original = db.get(Job, case["job"])
        assert len(original.payload[ready.RECEIPTS]) == 1
        assert not db.get(Job, sidecar_id).payload.get(ready.RECEIPTS)
        events = ready.events_for_child(db, db.get(Child, case["child"]), int(now()))
        assert len(events) == 1 and events[0]["route"] == "/unit/" + case["unit"]
