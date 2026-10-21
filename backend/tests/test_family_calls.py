"""Entirely synthetic family-call contracts; no cameras or provider requests."""
import asyncio
import base64
import hashlib
import hmac
import json
from concurrent.futures import ThreadPoolExecutor

import pytest
from conftest import HEADERS, register
from fastapi import HTTPException
from fastapi.testclient import TestClient
from schulpilot import family_calls as calls
from schulpilot import notifications as notifications
from schulpilot.config import settings
from schulpilot.db import DB, Activity, Base, Child, FamilyCall, LearningUnit, Membership, Session, User, engine, now
from schulpilot.families import export_child
from schulpilot.main import app
from schulpilot.security import password_hash
from sqlalchemy import func, select


@pytest.fixture
def turn(monkeypatch):
    object.__setattr__(settings, "family_calls_enabled", True)
    object.__setattr__(settings, "turn_urls", '["turn:school.invalid:3478?transport=udp","turns:school.invalid:5349?transport=tcp"]')
    object.__setattr__(settings, "turn_secret", "synthetic-operator-secret-" + "x" * 32)
    monkeypatch.setattr(notifications, "dispatch_call", lambda _: None)
    with calls.signals.lock:
        calls.signals.calls.clear()


@pytest.fixture
def child_api(household):
    with TestClient(app, headers=HEADERS) as kid:
        login = kid.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"})
        assert login.status_code == 200
        kid.headers["Authorization"] = "Bearer " + login.json()["token"]
        yield kid


def start(kid, key="synthetic-call-01", **context):
    response = kid.post("/api/family-calls", json={"idempotency_key": key, **context})
    assert response.status_code == 201, response.text
    return response.json()


def accepted(api, kid):
    call = start(kid)
    response = api.post(f"/api/family-calls/{call['id']}/accept")
    assert response.status_code == 200, response.text
    assert response.json()["status"] == "accepted"
    return call


def test_configuration_and_role_bounds(api, household, child_api, turn):
    assert child_api.get("/api/family-calls/config").json()["available"] is True
    response = api.post("/api/family-calls", json={"idempotency_key": "parent-cannot-dial"})
    assert response.status_code == 403
    with DB.begin() as db:
        admin = User(username="synthetic-admin", role="admin", verified=True, display_name="Admin", password_hash=password_hash("synthetic-admin-password"))
        db.add(admin)
    with TestClient(app, headers=HEADERS) as admin_api:
        result = admin_api.post("/api/auth/login", json={"username": "synthetic-admin", "password": "synthetic-admin-password"}).json()
        admin_api.headers["Authorization"] = "Bearer " + result["token"]
        assert admin_api.get("/api/family-calls/config").status_code == 403
        assert admin_api.get("/api/family-calls/active").status_code == 403
    object.__setattr__(settings, "turn_secret", "")
    assert child_api.get("/api/family-calls/config").json()["available"] is False
    assert child_api.post("/api/family-calls", json={"idempotency_key": "no-config-call"}).status_code == 503


def test_start_idempotency_and_exact_session_binding(api, household, child_api, turn):
    parent, child = household
    call = start(child_api)
    assert start(child_api)["id"] == call["id"]
    assert child_api.post("/api/family-calls", json={"idempotency_key": "second-call-key"}).status_code == 409
    assert api.get("/api/family-calls/active").json()["calls"][0]["id"] == call["id"]
    assert child_api.get("/api/family-calls/active").json()["calls"][0]["id"] == call["id"]
    with TestClient(app, headers=HEADERS) as another_device:
        login = another_device.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}).json()
        another_device.headers["Authorization"] = "Bearer " + login["token"]
        assert another_device.get("/api/family-calls/active").json() == {"calls": []}
        assert another_device.get("/api/family-calls/" + call["id"]).status_code == 404
        assert another_device.post(f"/api/family-calls/{call['id']}/end").status_code == 404
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(FamilyCall)) == 1
        stored = db.get(FamilyCall, call["id"])
        assert stored.child_id == child["id"] and stored.family_id == parent["families"][0]["id"]
        assert "synthetic-call-01" not in stored.idempotency


def test_unrelated_family_and_admin_cannot_read_or_join(api, household, child_api, turn, mailbox):
    call = start(child_api)
    register(api, mailbox, "unrelated-caller@example.org")
    for suffix, method in (("", "get"), ("/accept", "post"), ("/end", "post"), ("/signals", "get"), ("/ice", "post")):
        assert getattr(api, method)("/api/family-calls/" + call["id"] + suffix).status_code == 404
    assert api.get("/api/family-calls/active").json() == {"calls": []}


def test_ringing_does_not_disclose_ice_or_signalling(api, child_api, turn):
    call = start(child_api)
    path = "/api/family-calls/" + call["id"]
    assert child_api.post(path + "/ice").status_code == 409
    assert api.post(path + "/ice").status_code == 404
    assert child_api.post(path + "/accept").status_code == 403
    assert child_api.post(path + "/decline").status_code == 403
    assert api.post(path + "/end").status_code == 404
    assert child_api.post(path + "/heartbeat").json()["status"] == "ringing"


def test_turn_credentials_are_short_lived_opaque_and_different_per_peer(api, child_api, turn):
    call = accepted(api, child_api)
    path = "/api/family-calls/" + call["id"]
    child_ice = child_api.post(path + "/ice").json()
    parent_ice = api.post(path + "/ice").json()
    assert 3600 <= child_ice["expires"] - now() <= 3900
    ice = child_ice["ice_servers"][0]
    assert ice["username"] != parent_ice["ice_servers"][0]["username"]
    assert call["child_id"] not in ice["username"] and call["id"] not in ice["username"]
    expected = base64.b64encode(hmac.new(settings.turn_secret.encode(), ice["username"].encode(), hashlib.sha1).digest()).decode()
    assert ice["credential"] == expected
    assert settings.turn_secret not in json.dumps(child_ice)
    assert child_api.post(path + "/end").json()["status"] == "ended"
    assert child_api.post(path + "/ice").status_code == 409


def test_signals_private_direction_idempotency_and_validation(api, child_api, turn):
    call = accepted(api, child_api)
    path = "/api/family-calls/" + call["id"] + "/signals"
    envelope = {"idempotency_key": "offer-private-01", "kind": "offer", "payload": {"sdp": "v=0\r\nSYNTHETIC-PRIVATE-SDP", "camera_stream_id": "camera_1", "screen_stream_id": "screen-2"}}
    first = child_api.post(path, json=envelope)
    assert first.status_code == 200, first.text
    assert child_api.post(path, json=envelope).json() == first.json()
    assert child_api.get(path).json()["signals"] == []
    incoming = api.get(path).json()
    assert len(incoming["signals"]) == 1 and incoming["signals"][0]["payload"] == envelope["payload"]
    assert api.get(path + "?after=" + str(incoming["cursor"])).json()["signals"] == []
    assert api.post(path, json=envelope).status_code == 403
    envelope["payload"]["sdp"] += "DIFFERENT"
    assert child_api.post(path, json=envelope).status_code == 409
    invalid = child_api.post(path, json={"idempotency_key": "invalid-sdp-key", "kind": "offer", "payload": {"sdp": "PRIVATE-INVALID-VALUE"}})
    assert invalid.status_code == 422 and "PRIVATE-INVALID-VALUE" not in invalid.text
    assert child_api.post(path, json={"idempotency_key": "extra-field-key", "kind": "ice", "payload": {"candidate": "c", "external_url": "https://example.org"}}).status_code == 422
    assert child_api.post(path, json={"idempotency_key": "index-field-key", "kind": "ice", "payload": {"candidate": "c", "sdpMLineIndex": True}}).status_code == 422
    assert child_api.get(path + "?after=-1").status_code == 422
    with DB() as db:
        stored = db.get(FamilyCall, call["id"])
        assert "SDP" not in json.dumps({c.name: getattr(stored, c.name) for c in FamilyCall.__table__.columns})
        assert all("sdp" not in column.name.lower() for table in Base.metadata.tables.values() for column in table.columns)


def test_parent_claim_exact_session_and_idempotent_end(api, household, child_api, turn):
    call = accepted(api, child_api)
    path = "/api/family-calls/" + call["id"]
    assert api.post(path + "/accept").status_code == 200
    with TestClient(app, headers=HEADERS) as second_parent_device:
        login = second_parent_device.post("/api/auth/login", json={"username": "parent@example.org", "password": "secure-parent-pass-123"}).json()
        second_parent_device.headers["Authorization"] = "Bearer " + login["token"]
        assert second_parent_device.post(path + "/accept").status_code == 404
        assert second_parent_device.post(path + "/heartbeat").status_code == 404
        assert second_parent_device.get(path + "/signals").status_code == 404
        assert second_parent_device.get("/api/family-calls/active").json() == {"calls": []}
    assert api.post(path + "/end").json()["status"] == "ended"
    assert api.post(path + "/end").json()["status"] == "ended"
    assert child_api.get("/api/family-calls/active").json() == {"calls": []}


@pytest.mark.parametrize("change,reason", [("caller", "session_ended"), ("parent", "parent_access_ended"), ("membership", "parent_access_ended"), ("disabled", "parent_access_ended")])
def test_revocation_removes_media_authority(api, household, child_api, turn, change, reason):
    call = accepted(api, child_api)
    with DB.begin() as db:
        stored = db.get(FamilyCall, call["id"])
        if change == "caller":
            db.get(Session, stored.caller_session_id).revoked = True
        elif change == "parent":
            db.get(Session, stored.parent_session_id).revoked = True
        elif change == "membership":
            db.delete(db.scalar(select(Membership).where(Membership.user_id == stored.parent_user_id)))
        else:
            db.get(User, stored.parent_user_id).disabled = True
    observer = api if change == "caller" else child_api
    result = observer.get("/api/family-calls/" + call["id"])
    assert result.status_code == 200
    assert result.json()["status"] == "ended" and result.json()["reason"] == reason
    assert observer.post(f"/api/family-calls/{call['id']}/ice").status_code == 409
    assert observer.get(f"/api/family-calls/{call['id']}/signals").json()["signals"] == []


@pytest.mark.parametrize("state,reason", [("ring_timeout", "ring_timeout"), ("lease", "connection_interrupted"), ("max", "duration_limit"), ("restart", "server_restarted")])
def test_expiry_is_read_only_and_next_start_can_release_slot(api, child_api, turn, monkeypatch, state, reason):
    call = start(child_api)
    if state != "ring_timeout":
        assert api.post(f"/api/family-calls/{call['id']}/accept").status_code == 200
    with DB.begin() as db:
        stored = db.get(FamilyCall, call["id"])
        if state == "ring_timeout":
            stored.ring_expires = int(now()) - 1
        elif state == "lease":
            stored.parent_seen = int(now()) - 91
        elif state == "max":
            stored.expires = int(now()) - 1
        else:
            stored.instance = "different-synthetic-api-instance"
        original = stored.status
    for _ in range(2):
        result = child_api.get("/api/family-calls/" + call["id"]).json()
        assert result["reason"] == reason
        assert result["status"] in ("missed", "ended")
    with DB() as db:
        stored = db.get(FamilyCall, call["id"])
        assert stored.status == original and stored.ended_at is None
    replacement = start(child_api, key="replacement-synthetic-key")
    assert replacement["id"] != call["id"]
    with DB() as db:
        assert db.get(FamilyCall, call["id"]).active_slot is None


def test_decline_idempotency_and_recovery(api, child_api, turn):
    call = start(child_api)
    path = "/api/family-calls/" + call["id"]
    assert api.post(path + "/decline").json()["status"] == "declined"
    assert api.post(path + "/decline").json()["status"] == "declined"
    assert api.post(path + "/accept").status_code == 409
    assert start(child_api, key="next-after-decline")["status"] == "ringing"


def test_context_ownership_and_supported_learning_evidence(api, household, child_api, turn):
    _, child = household
    with DB.begin() as db:
        unit = LearningUnit(child_id=child["id"], subject="Mathematik", topic="Synthetische Aufgabe", explanation="", questions=[], status="active", provider="synthetic")
        db.add(unit)
        db.flush()
        unit_id = unit.id
    call = start(child_api, context_kind="learning", context_id=unit_id)
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Activity).where(Activity.unit_id == unit_id)) == 0
    assert api.post(f"/api/family-calls/{call['id']}/accept").status_code == 200
    assert api.post(f"/api/family-calls/{call['id']}/accept").status_code == 200
    with DB() as db:
        help_rows = list(db.scalars(select(Activity).where(Activity.unit_id == unit_id, Activity.kind == "explanation")))
        assert len(help_rows) == 1 and help_rows[0].detail == {"via": "family_call", "call_id": call["id"]}
    assert child_api.post(f"/api/family-calls/{call['id']}/end").status_code == 200
    assert child_api.post("/api/family-calls", json={"idempotency_key": "bad-context-key", "context_kind": "learning", "context_id": "f" * 32}).status_code == 404
    assert child_api.post("/api/family-calls", json={"idempotency_key": "incomplete-context", "context_kind": "homework"}).status_code == 422


def test_maintenance_retention_export_and_cascade(api, household, child_api, turn):
    _, child = household
    call = start(child_api)
    with DB.begin() as db:
        stored = db.get(FamilyCall, call["id"])
        stored.ring_expires = int(now()) - 1
        calls.maintenance(db)
    with DB() as db:
        row = db.get(FamilyCall, call["id"])
        assert row.status == "missed" and row.active_slot is None
        exported = export_child(db, db.get(Child, child["id"]))["family_calls"]
        assert len(exported) == 1
        assert set(exported[0]) == {"id", "context_kind", "context_id", "status", "reason", "created", "accepted_at", "ended_at"}
    with DB.begin() as db:
        db.get(FamilyCall, call["id"]).created = int(now()) - 31 * 86400
        calls.maintenance(db)
    with DB() as db:
        assert db.get(FamilyCall, call["id"]) is None
    fresh = start(child_api, key="delete-owned-call")
    with DB.begin() as db:
        db.delete(db.get(Child, child["id"]))
    with DB() as db:
        assert db.get(FamilyCall, fresh["id"]) is None


def test_unknown_context_and_csrf_cannot_start(api, child_api, turn):
    body = {"idempotency_key": "untrusted-call-key", "child_id": "f" * 32}
    assert child_api.post("/api/family-calls", json=body).status_code == 422
    assert child_api.post("/api/family-calls", headers={"Origin": "https://evil.invalid"}, json={"idempotency_key": "untrusted-call-key"}).status_code == 403


@pytest.mark.skipif(engine.dialect.name != "postgresql", reason="PostgreSQL row-lock concurrency")
def test_concurrent_start_and_parent_claim(api, child_api, turn):
    with ThreadPoolExecutor(max_workers=2) as pool:
        responses = list(pool.map(lambda key: child_api.post("/api/family-calls", json={"idempotency_key": key}), ["parallel-call-one", "parallel-call-two"]))
    assert sorted(r.status_code for r in responses) == [201, 409]
    cid = next(r.json()["id"] for r in responses if r.status_code == 201)
    with TestClient(app, headers=HEADERS) as parent_device:
        result = parent_device.post("/api/auth/login", json={"username": "parent@example.org", "password": "secure-parent-pass-123"}).json()
        parent_device.headers["Authorization"] = "Bearer " + result["token"]
        with ThreadPoolExecutor(max_workers=2) as pool:
            claimed = list(pool.map(lambda client: client.post(f"/api/family-calls/{cid}/accept"), [api, parent_device]))
        assert sorted(r.status_code for r in claimed) == [200, 404]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(FamilyCall)) == 1


def test_in_app_missed_call_is_private_and_readable_without_push(api, household, child_api, turn, mailbox):
    call = start(child_api)
    with DB.begin() as db:
        db.get(FamilyCall, call["id"]).ring_expires = int(now()) - 1
    result = api.get("/api/notifications/inbox").json()
    entry = next(item for item in result["items"] if item["id"] == "family_call:" + call["id"])
    assert entry["title"] == "Ein Familienanruf wurde verpasst" and entry["route"] == "/family-call/" + call["id"]
    assert entry["read"] is False
    assert api.post("/api/notifications/inbox/read", json={"ids": [entry["id"]]}).status_code == 200
    assert next(item for item in api.get("/api/notifications/inbox").json()["items"] if item["id"] == entry["id"])["read"] is True
    with DB() as db:
        assert db.get(FamilyCall, call["id"]).status == "ringing"
    register(api, mailbox, "separate-call-inbox@example.org")
    assert all(item["id"] != entry["id"] for item in api.get("/api/notifications/inbox").json()["items"])


def test_call_push_requires_explicit_parent_opt_in_and_bound_device(api, household, child_api, turn, tmp_path):
    from test_notifications import enable

    enable(tmp_path)
    _, child = household
    with DB.begin() as db:
        db.get(Child, child["id"]).preferences = {"quiet_start": 0, "quiet_end": 0}
    response = api.put("/api/notifications/device", json={"token": "SYNTHETIC_FCM_TOKEN_" + "x" * 40,
        "platform": "android", "quiet_start": 0, "quiet_end": 0, "family_calls": True})
    assert response.status_code == 422
    child_response = child_api.put("/api/notifications/device", json={"token": "SYNTHETIC_CHILD_FCM_" + "y" * 40,
        "platform": "android", "family_calls": True, "call_binding": "b" * 64})
    assert child_response.status_code == 403
    result = api.put("/api/notifications/device", json={"token": "SYNTHETIC_FCM_TOKEN_" + "x" * 40,
        "platform": "android", "quiet_start": 0, "quiet_end": 0, "family_calls": True, "call_binding": "a" * 64})
    assert result.status_code == 200, result.text
    assert result.json()["family_calls"] is True and result.json()["call_capable"] is True
    assert "call_binding" not in result.text
    call = start(child_api)
    from schulpilot.db import PushDelivery, PushDevice
    with DB() as db:
        queued = list(db.scalars(select(PushDelivery).where(PushDelivery.kind == "family_call_incoming")))
        assert len(queued) == 1 and queued[0].device_id == result.json()["id"]
        assert notifications.call_delivery_allowed(db, db.get(PushDevice, result.json()["id"]), db.get(FamilyCall, call["id"]), "incoming", int(now()))
    # Explicit opt-out invalidates already queued call notifications as well.
    assert api.put("/api/notifications/device", json={"token": "SYNTHETIC_FCM_TOKEN_" + "x" * 40,
        "platform": "android", "quiet_start": 0, "quiet_end": 0, "family_calls": False}).status_code == 200
    with DB() as db:
        device = db.get(PushDevice, result.json()["id"])
        assert device.call_binding is None and not notifications.call_delivery_allowed(db, device, db.get(FamilyCall, call["id"]), "incoming", int(now()))


def test_call_push_payload_neutral_short_and_stale_session_suppressed(api, household, child_api, turn, tmp_path, monkeypatch):
    from schulpilot.db import PushDelivery, PushDevice
    from test_notifications import enable

    enable(tmp_path)
    _, child = household
    with DB.begin() as db:
        db.get(Child, child["id"]).preferences = {"quiet_start": 0, "quiet_end": 0}
    device = api.put("/api/notifications/device", json={"token": "SYNTHETIC_PARENT_FCM_" + "z" * 40,
        "platform": "android", "quiet_start": 0, "quiet_end": 0, "family_calls": True, "call_binding": "c" * 64}).json()
    call = start(child_api)
    sent = []
    monkeypatch.setattr(notifications, "send_fcm", lambda *args, **kwargs: sent.append((args, kwargs)))
    assert notifications.deliver_one(DB, call_id=call["id"])
    assert len(sent) == 1
    args, kwargs = sent[0]
    payload = kwargs["call_data"]
    assert args[2] <= 45 and kwargs["testing"] is False
    assert payload["type"] == "family_call" and payload["event"] == "incoming"
    assert payload["call_binding"] == "c" * 64 and payload["device_id"] == device["id"]
    assert payload["call_id"] == call["id"] and int(payload["expires_at"]) == call["ring_expires"] * 1000
    assert "Testkind" not in json.dumps(payload) and child["id"] not in json.dumps(payload)
    assert api.post(f"/api/family-calls/{call['id']}/accept").status_code == 200
    # Revoke the bound parent session after queueing the ring-cancellation.
    with DB.begin() as db:
        db.get(Session, db.get(PushDevice, device["id"]).session_id).revoked = True
    assert notifications.deliver_one(DB, call_id=call["id"])
    assert len(sent) == 1
    with DB() as db:
        ended = db.scalar(select(PushDelivery).where(PushDelivery.kind == "family_call_ended"))
        assert ended.status == "suppressed"


def test_signal_memory_bounds_and_expiry():
    memory = calls.SignalMemory()
    payload = calls.Signal(idempotency_key="memory-offer-01", kind="offer", payload={"sdp": "v=0\r\n" + "x" * 47_000})
    for index in range(5):
        payload.idempotency_key = f"memory-offer-{index:02}"
        memory.put("synthetic-call", "child", "parent", payload, 100)
    payload.idempotency_key = "memory-overflow"
    with pytest.raises(HTTPException) as error:
        memory.put("synthetic-call", "child", "parent", payload, 100)
    assert error.value.status_code == 429
    # Content expires after 90s, but a still-valid call retains its cursor.
    assert memory.read("synthetic-call", "parent", 0, 191) == ([], 5)
    assert memory.calls["synthetic-call"]["items"] == []
    assert len(memory.calls["synthetic-call"]["keys"]) == 5
    assert "v=0" not in json.dumps(memory.calls)
    assert memory.read("synthetic-call", "parent", 5, 100 + calls.MAX_SECONDS + calls.LEASE_SECONDS) == ([], 5)
    assert memory.calls == {}


def test_late_screen_offer_after_heartbeat_only_quiet_period_keeps_both_cursors(api, child_api, turn, monkeypatch):
    clock = [int(now())]
    monkeypatch.setattr(calls, "now", lambda: clock[0])
    call = accepted(api, child_api)
    path = "/api/family-calls/" + call["id"]
    offer = {"idempotency_key": "initial-camera-offer", "kind": "offer",
        "payload": {"sdp": "v=0\r\nSYNTHETIC-INITIAL-CAMERA", "camera_stream_id": "camera"}}
    answer = {"idempotency_key": "initial-camera-answer", "kind": "answer",
        "payload": {"sdp": "v=0\r\nSYNTHETIC-INITIAL-ANSWER"}}
    assert child_api.post(path + "/signals", json=offer).json()["sequence"] == 1
    assert api.post(path + "/signals", json=answer).json()["sequence"] == 2
    parent_cursor = api.get(path + "/signals").json()["cursor"]
    child_cursor = child_api.get(path + "/signals").json()["cursor"]
    assert parent_cursor == child_cursor == 2
    # Neither peer reads/writes signalling for more than one envelope lease.
    for _ in range(4):
        clock[0] += 30
        assert child_api.post(path + "/heartbeat").json()["status"] == "accepted"
        assert api.post(path + "/heartbeat").json()["status"] == "accepted"
    screen = {"idempotency_key": "late-screen-offer", "kind": "offer",
        "payload": {"sdp": "v=0\r\nSYNTHETIC-LATE-SCREEN", "camera_stream_id": "camera", "screen_stream_id": "screen"}}
    first = child_api.post(path + "/signals", json=screen)
    assert first.status_code == 200 and first.json()["sequence"] == 3
    assert child_api.post(path + "/signals", json=screen).json() == first.json()
    incoming = api.get(path + "/signals", params={"after": parent_cursor}).json()
    assert incoming["cursor"] == 3 and len(incoming["signals"]) == 1
    assert incoming["signals"][0]["payload"] == screen["payload"]
    answer["idempotency_key"] = "late-screen-answer"
    assert api.post(path + "/signals", json=answer).json()["sequence"] == 4
    returned = child_api.get(path + "/signals", params={"after": child_cursor}).json()
    assert returned["cursor"] == 4 and [row["sequence"] for row in returned["signals"]] == [4]
    box = calls.signals.calls[call["id"]]
    assert box["expires"] == call["expires"] + calls.LEASE_SECONDS
    assert "SYNTHETIC-INITIAL-CAMERA" not in json.dumps(box)
    assert child_api.post(path + "/end").status_code == 200
    assert call["id"] not in calls.signals.calls


def test_expired_signal_retry_is_idempotent_without_retaining_private_payload():
    memory = calls.SignalMemory()
    initial = calls.Signal(idempotency_key="initial-private-offer", kind="offer", payload={"sdp": "v=0\r\nSYNTHETIC-OLD-CONTENT"})
    assert memory.put("call", "child", "parent", initial, 100) == 1
    assert memory.read("call", "parent", 1, 191) == ([], 1)
    # No GET/heartbeat/write can revive an expired envelope on HTTP retry.
    assert memory.put("call", "child", "parent", initial, 191) == 1
    assert memory.read("call", "parent", 0, 191) == ([], 1)
    assert "SYNTHETIC-OLD-CONTENT" not in json.dumps(memory.calls)
    changed = initial.model_copy(update={"payload": {"sdp": "v=0\r\nDIFFERENT"}})
    with pytest.raises(HTTPException) as error:
        memory.put("call", "child", "parent", changed, 191)
    assert error.value.status_code == 409
    later = calls.Signal(idempotency_key="new-screen-offer", kind="offer", payload={"sdp": "v=0\r\nSCREEN"})
    assert memory.put("call", "child", "parent", later, 191) == 2
    assert memory.read("call", "parent", 1, 191)[0][0]["sequence"] == 2


def test_signal_cursor_tombstones_have_fixed_deadlines_and_bounded_capacity():
    memory = calls.SignalMemory()
    payload = calls.Signal(idempotency_key="initial-offer-key", kind="offer", payload={"sdp": "v=0"})
    for index in range(memory.MAX_CALLS):
        assert memory.put(f"call-{index}", "child", "parent", payload, 100) == 1
    # Payload expiry must not evict an active call merely to admit a new one.
    assert memory.read("call-0", "parent", 1, 191) == ([], 1)
    assert len(memory.calls) == memory.MAX_CALLS and all(not row["items"] for row in memory.calls.values())
    with pytest.raises(HTTPException) as error:
        memory.put("new-call", "child", "parent", payload, 191)
    assert error.value.status_code == 503
    later = payload.model_copy(update={"idempotency_key": "late-offer-key"})
    assert memory.put("call-0", "child", "parent", later, 191) == 2
    assert memory.calls["call-0"]["expires"] == 100 + calls.MAX_SECONDS + calls.LEASE_SECONDS
    memory.clear("call-1")
    assert memory.put("new-call", "child", "parent", payload, 191) == 1
    end = 100 + calls.MAX_SECONDS + calls.LEASE_SECONDS
    assert memory.read("call-0", "parent", 2, end - 1) == ([], 2)
    assert memory.read("call-0", "parent", 2, end) == ([], 2)
    assert list(memory.calls) == ["new-call"]
    memory.clear("new-call")
    assert not memory.calls


def test_signal_dedupe_index_is_bounded_without_resetting_old_sequences():
    memory = calls.SignalMemory()
    payload = calls.Signal(idempotency_key="initial-offer-key", kind="offer", payload={"sdp": "v=0"})
    for index in range(memory.MAX_KEYS):
        # Renew the payload window in bounded batches, within the call lifetime.
        current = 100 + (index // memory.MAX_ITEMS) * (calls.LEASE_SECONDS + 1)
        event = payload.model_copy(update={"idempotency_key": f"offer-key-{index:04}"})
        assert memory.put("call", "child", "parent", event, current) == index + 1
    later = current + calls.LEASE_SECONDS + 1
    with pytest.raises(HTTPException) as error:
        memory.put("call", "child", "parent", payload, later)
    assert error.value.status_code == 429
    original = payload.model_copy(update={"idempotency_key": "offer-key-0000"})
    assert memory.put("call", "child", "parent", original, later) == 1
    assert memory.read("call", "parent", memory.MAX_KEYS, later) == ([], memory.MAX_KEYS)
    assert len(memory.calls["call"]["keys"]) == memory.MAX_KEYS


def test_signal_global_byte_budget_includes_metadata_and_releases_only_expired_content():
    memory = calls.SignalMemory()
    payload = calls.Signal(idempotency_key="large-offer-key", kind="offer", payload={"sdp": "v=0\r\n" + "x" * 47_000})
    rejected = False
    for index in range(128):
        event = payload.model_copy(update={"idempotency_key": f"large-offer-{index:04}"})
        try:
            memory.put(f"call-{index // 5}", "child", "parent", event, 100)
        except HTTPException as error:
            assert error.status_code == 429
            rejected = True
            break
    assert rejected and sum(box["bytes"] for box in memory.calls.values()) <= memory.MAX_BYTES
    for box in memory.calls.values():
        assert box["bytes"] == memory.BOX_BYTES + len(box["keys"]) * memory.KEY_BYTES + sum(item["size"] for item in box["items"])
    memory.read("call-0", "parent", 0, 191)
    before = sum(box["bytes"] for box in memory.calls.values())
    assert before == sum(memory.BOX_BYTES + len(box["keys"]) * memory.KEY_BYTES for box in memory.calls.values())
    assert memory.put("call-0", "child", "parent", payload, 191) == 6
    assert before < sum(box["bytes"] for box in memory.calls.values()) <= memory.MAX_BYTES
    # A budget failure cannot leave an empty reserved slot behind.
    tiny = calls.SignalMemory()
    tiny.MAX_BYTES = memory.BOX_BYTES
    with pytest.raises(HTTPException) as error:
        tiny.put("failed-call", "child", "parent", payload, 100)
    assert error.value.status_code == 429 and not tiny.calls


@pytest.mark.parametrize("interrupted", [False, True])
def test_signal_cleanup_lifespan_expires_without_requests_and_stops(monkeypatch, interrupted):
    memory = calls.SignalMemory()
    clock = [100]
    monkeypatch.setattr(calls, "signals", memory)
    monkeypatch.setattr(calls, "now", lambda: clock[0])
    assert 0 < calls.SIGNAL_CLEANUP_SECONDS <= 1
    monkeypatch.setattr(calls, "SIGNAL_CLEANUP_SECONDS", 0.01)
    payload = calls.Signal(idempotency_key="idle-private-offer", kind="offer", payload={"sdp": "v=0\r\nPRIVATE-IDLE-CONTENT"})
    memory.put("idle-call", "child", "parent", payload, clock[0])

    class StopLifecycle(Exception):
        pass

    async def scenario():
        tick = asyncio.Event()
        observations = []
        original = memory.expire

        def expire(current):
            original(current)
            observations.append(current)
            tick.set()

        monkeypatch.setattr(memory, "expire", expire)
        try:
            async with calls.signal_memory_lifespan() as task:
                # No read, write or heartbeat triggers these expiry operations.
                clock[0] = 100 + calls.LEASE_SECONDS
                await asyncio.wait_for(tick.wait(), 1)
                assert memory.calls["idle-call"]["items"] == []
                assert memory.calls["idle-call"]["seq"] == 1
                assert "PRIVATE-IDLE-CONTENT" not in json.dumps(memory.calls)
                tick.clear()
                clock[0] = 100 + calls.MAX_SECONDS + calls.LEASE_SECONDS
                await asyncio.wait_for(tick.wait(), 1)
                assert not memory.calls
                if interrupted:
                    raise StopLifecycle
        except StopLifecycle:
            assert interrupted
        assert task.done() and task.cancelled()
        stopped_count = len(observations)
        await asyncio.sleep(0.03)
        assert len(observations) == stopped_count

    asyncio.run(scenario())


def test_parent_camera_renegotiation_is_explicit_and_bounded(api, child_api, turn):
    call = accepted(api, child_api)
    path = "/api/family-calls/" + call["id"] + "/signals"
    action = {"idempotency_key": "parent-camera-on", "kind": "renegotiate", "payload": {}}
    assert api.post(path, json=action).status_code == 200
    assert child_api.get(path).json()["signals"][0]["kind"] == "renegotiate"
    assert child_api.post(path, json=action).status_code == 403
    action["payload"] = {"auto_camera": True}
    assert api.post(path, json=action).status_code == 422


def test_watchdog_deadline_uses_both_peers_without_get_renewal(api, child_api, turn):
    call = accepted(api, child_api)
    path = "/api/family-calls/" + call["id"]
    with DB.begin() as db:
        stored = db.get(FamilyCall, call["id"])
        stored.parent_seen = int(now()) - 30
        deadline = stored.parent_seen + calls.LEASE_SECONDS
    first = child_api.get(path).json()
    assert first["valid_until"] == deadline and first["server_now"] <= deadline
    assert child_api.get(path).json()["valid_until"] == deadline
    # The child's own heartbeat cannot renew the other peer's authority.
    assert child_api.post(path + "/heartbeat").json()["valid_until"] == deadline
    renewed = api.post(path + "/heartbeat").json()
    assert renewed["valid_until"] > deadline


def test_answers_during_live_support_are_assisted_without_rewriting_history(api, household, child_api, turn):
    from schulpilot.db import Attempt, Material

    _, child = household
    with DB.begin() as db:
        material = Material(child_id=child["id"], title="Künstlicher Rechenstoff", subject="Mathematik",
            topic="Multiplizieren", content="3 mal 15 ist 45.", confirmed=True, status="confirmed")
        db.add(material)
        db.flush()
        questions = [{"id": f"q{i}", "type": "short", "prompt": "Berechne 3 mal 15.", "answer": "45", "options": [], "accepted": [], "hints": ["Dreimal fünfzehn."], "explanation": "15 + 15 + 15 = 45."} for i in range(3)]
        unit = LearningUnit(child_id=child["id"], material_id=material.id, subject="Mathematik", topic="Multiplizieren",
            explanation="Künstliche Einheit.", questions=questions, provider="synthetic", status="active")
        db.add(unit)
        db.flush()
        old = Attempt(unit_id=unit.id, question_id="q0", answer="45", outcome="correct", assisted=False,
            evaluation={"method": "synthetic-preserved", "independent_evidence": True})
        db.add(old)
        db.flush()
        unit_id, old_id = unit.id, old.id
    call = accepted(api, child_api)  # General help also applies to a new exercise.
    response = child_api.post(f"/api/units/{unit_id}/questions/q1/answer", json={"answer": "45"})
    assert response.status_code == 200, response.text
    assert response.json()["outcome"] == "correct"
    with DB() as db:
        old = db.get(Attempt, old_id)
        assert old.answer == "45" and old.assisted is False and old.evaluation == {"method": "synthetic-preserved", "independent_evidence": True}
        current = db.scalar(select(Attempt).where(Attempt.unit_id == unit_id, Attempt.question_id == "q1"))
        assert current.assisted is True and current.evaluation["independent_evidence"] is False
        marker = db.scalar(select(Activity).where(Activity.unit_id == unit_id, Activity.kind == "explanation"))
        assert marker.detail == {"via": "family_call", "call_id": call["id"]}


@pytest.mark.skipif(engine.dialect.name != "postgresql", reason="PostgreSQL row-lock concurrency")
def test_same_parent_device_accepting_different_children_has_one_winner(api, household, child_api, turn):
    from conftest import create_child

    parent, _ = household
    create_child(api, parent, "synthetic-second-child")
    first = start(child_api)
    with TestClient(app, headers=HEADERS) as second_child:
        result = second_child.post("/api/auth/login", json={"username": "synthetic-second-child", "password": "secure-child-pass-123"}).json()
        second_child.headers["Authorization"] = "Bearer " + result["token"]
        second = start(second_child, key="second-child-call")
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda cid: api.post(f"/api/family-calls/{cid}/accept"), [first["id"], second["id"]]))
        assert sorted(r.status_code for r in results) == [200, 409]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(FamilyCall).where(FamilyCall.status == "accepted")) == 1


def test_operator_disable_ends_authority_without_get_writes(api, child_api, turn):
    call = accepted(api, child_api)
    object.__setattr__(settings, "family_calls_enabled", False)
    path = "/api/family-calls/" + call["id"]
    assert child_api.get("/api/family-calls/config").json()["available"] is False
    assert child_api.get(path).json()["reason"] == "calls_disabled"
    assert child_api.get(path + "/signals").json()["signals"] == []
    assert child_api.post(path + "/ice").status_code == 409
    assert child_api.post("/api/family-calls", json={"idempotency_key": "cannot-after-disable"}).status_code == 503
    with DB() as db:
        assert db.get(FamilyCall, call["id"]).status == "accepted"
