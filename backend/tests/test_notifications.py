import json
from datetime import datetime
from zoneinfo import ZoneInfo

import httpx
import pytest
from conftest import HEADERS, register
from fastapi.testclient import TestClient
from schulpilot import notifications as n
from schulpilot.config import settings
from schulpilot.db import DB, Child, Message, PushDelivery, PushDevice, Session, now
from schulpilot.main import app
from schulpilot.security import decrypt
from sqlalchemy import func, select


def enable(tmp_path):
    credential = tmp_path / "service-account.json"
    credential.write_text("{}")
    for name, value in {
        "push_approved": True,
        "push_privacy_evidence": "synthetic test fixture",
        "fcm_config_verification": "synthetic fixture: Android/Web app keys and APIs checked",
        "fcm_service_account_file": str(credential),
        "fcm_public_config": json.dumps(
            {
                "apiKey": "public-test-key",
                "appId": "1:123:web:test",
                "androidAppId": "1:123:android:test",
                "messagingSenderId": "123",
                "projectId": "synthetic-project",
                "vapidKey": "synthetic-public-vapid",
            }
        ),
    }.items():
        object.__setattr__(settings, name, value)


def device(api, token="SYNTHETIC_FCM_TOKEN_" + "x" * 40):
    response = api.put(
        "/api/notifications/device", json={"token": token, "platform": "android", "quiet_start": 0, "quiet_end": 0}
    )
    assert response.status_code == 200, response.text
    assert token not in response.text and "encrypted_token" not in response.text
    return response.json()


def test_push_requires_configuration_and_only_owns_devices(api, household, tmp_path, mailbox):
    assert api.get("/api/notifications/config").json()["available"] is False
    assert api.put("/api/notifications/device", json={"token": "x" * 40, "platform": "web"}).status_code == 503
    enable(tmp_path)
    d = device(api)
    with DB() as db:
        stored = db.get(PushDevice, d["id"])
        assert stored.encrypted_token != decrypt(stored.encrypted_token)
    register(api, mailbox, "unrelated@example.org")
    assert api.get("/api/notifications/devices").json() == []
    assert api.delete("/api/notifications/devices/" + d["id"]).status_code == 404


def test_push_bundling_quiet_times_and_revocation(api, household, tmp_path, monkeypatch):
    enable(tmp_path)
    _, child = household
    d = device(api)
    fixed = int(datetime(2026, 10, 14, 17, tzinfo=ZoneInfo("Europe/Berlin")).timestamp())
    # Keep this synthetic session valid at the controlled test timestamp.
    with DB.begin() as db:
        stored = db.get(PushDevice, d["id"])
        session = db.get(Session, stored.session_id)
        session.seen, session.expires = fixed, fixed + 86400
        db.add(Message(child_id=child["id"], kind="help", body="PRIVATE CHILD ANSWER", created=fixed - 10))
        db.get(Child, child["id"]).preferences = {"quiet_start": 20, "quiet_end": 8}
        n.prepare(db, fixed)
        n.prepare(db, fixed)
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(PushDelivery)) == 1
        stored = db.get(PushDevice, d["id"])
        assert n.due_kinds(db, stored, fixed) == ["help"]
        assert n.due_kinds(db, stored, fixed + 4 * 3600) == []
    with DB.begin() as db:
        db.get(Session, db.get(PushDevice, d["id"]).session_id).revoked = True
    sent = []
    monkeypatch.setattr(n, "now", lambda: fixed)
    monkeypatch.setattr(n, "send_fcm", lambda *args: sent.append(args))
    assert n.deliver_one(DB)
    assert sent == []
    with DB() as db:
        assert db.scalar(select(PushDelivery)).status == "suppressed"


def test_removed_membership_is_rechecked_before_push(api, household, tmp_path, mailbox, monkeypatch):
    enable(tmp_path)
    owner, child = household
    fid = owner["families"][0]["id"]
    api.post("/api/families/" + fid + "/invitations", json={"email": "invited@example.org", "permission": "view"})
    token = mailbox[-1]["token"]
    api.post(
        "/api/invitations/accept",
        json={"token": token, "password": "synthetic-guest-pass-123", "display_name": "Guest"},
    )
    with TestClient(app, headers=HEADERS) as guest:
        login = guest.post(
            "/api/auth/login", json={"username": "invited@example.org", "password": "synthetic-guest-pass-123"}
        ).json()
        guest.headers["Authorization"] = "Bearer " + login["token"]
        device(guest)
    fixed = int(now())
    with DB.begin() as db:
        # Disabled quiet hours isolate the membership check from the wall clock.
        db.get(Child, child["id"]).preferences = {"quiet_start": 0, "quiet_end": 0}
        db.add(Message(child_id=child["id"], kind="help", body="Private", created=fixed - 1))
        n.prepare(db, fixed)
    membership = next(m for m in api.get("/api/families/" + fid + "/members").json() if not m["self"])
    api.delete("/api/families/" + fid + "/members/" + membership["id"])
    sent = []
    monkeypatch.setattr(n, "send_fcm", lambda *args: sent.append(args))
    n.deliver_one(DB)
    assert not sent


def test_child_cannot_override_parent_quiet_or_reminder_preferences(api, household, tmp_path):
    enable(tmp_path)
    _, child = household
    with DB.begin() as db:
        db.get(Child, child["id"]).preferences = {"push_consent": True}
    with TestClient(app, headers=HEADERS) as kid:
        login = kid.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}).json()
        kid.headers["Authorization"] = "Bearer " + login["token"]
        d = device(kid)
    with DB.begin() as db:
        db.get(Child, child["id"]).preferences = {
            "push_consent": True,
            "reminders": False,
            "quiet_start": 0,
            "quiet_end": 0,
        }
    with DB() as db:
        assert n.due_kinds(db, db.get(PushDevice, d["id"]), int(now())) == []


def test_service_worker_uses_public_configuration_synchronously(api, tmp_path):
    assert api.get("/api/notifications/service-worker.js").status_code == 503
    enable(tmp_path)
    response = api.get("/api/notifications/service-worker.js")
    assert response.status_code == 200 and response.headers["service-worker-allowed"] == "/"
    assert "firebase.initializeApp({" in response.text and "fetch(" not in response.text
    assert "private_key" not in response.text and "12.19.0" in response.text


def test_fcm_http_v1_neutral_payload_expiry_and_invalid_registration(api, tmp_path, monkeypatch):
    from google.oauth2 import service_account

    enable(tmp_path)
    from pathlib import Path

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
        token = "SYNTHETIC-OAUTH-TOKEN"

        def refresh(self, request):
            pass

    def credentials(info, scopes):
        assert scopes == ["https://www.googleapis.com/auth/firebase.messaging"]
        return Credential()

    monkeypatch.setattr(service_account.Credentials, "from_service_account_info", credentials)
    sent = []
    status = 200

    class Client:
        def __init__(self, **kwargs):
            assert kwargs["follow_redirects"] is False

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def post(self, url, headers, json):
            sent.append(json)
            return httpx.Response(
                status,
                json={"name": "synthetic-message"}
                if status == 200
                else {"error": {"details": [{"errorCode": "UNREGISTERED"}]}},
            )

    monkeypatch.setattr(n.httpx, "Client", Client)
    n.send_fcm("SYNTHETIC-REGISTRATION-TOKEN", "help", ttl=10)
    message = sent[0]["message"]
    assert set(message["data"]) == {"route"} and message["data"]["route"] == "/app"
    assert message["android"]["ttl"] == "10s" and message["android"]["notification"]["visibility"] == "PRIVATE"
    assert message["android"]["priority"] == "high"
    assert message["android"]["notification"]["channel_id"] == "schulpilot_updates_v1"
    assert message["android"]["notification"]["icon"] == "ic_notification"
    assert message["webpush"]["headers"]["TTL"] == "10"
    assert all(k not in json.dumps(message) for k in ["child_id", "family_id", "answer", "topic", "grade"])
    moment = int(datetime(2026, 10, 14, 19, 59, 50, tzinfo=ZoneInfo("Europe/Berlin")).timestamp())
    assert n.seconds_before_quiet(moment, "Europe/Berlin", 20, 8) == 10
    status = 404
    with pytest.raises(n.FcmError) as error:
        n.send_fcm("SYNTHETIC-REGISTRATION-TOKEN", "help")
    assert error.value.unregistered is True
