from conftest import HEADERS
from fastapi.testclient import TestClient
from schulpilot import notifications as n
from schulpilot.config import settings
from schulpilot.db import DB, Child, Family, PushDelivery, PushDevice, PushTestGrant, Session, now
from schulpilot.main import app
from sqlalchemy import select
from test_notifications import device, enable


def grant(user, child):
    with DB.begin() as db:
        db.get(Family, user["families"][0]["id"]).synthetic = True
        db.get(Child, child["id"]).preferences = {"quiet_start": 0, "quiet_end": 0}
        db.add(PushTestGrant(user_id=user["id"], expires=int(now()) + 3600))


def test_test_grant_does_not_enable_production_or_send_to_real_accounts(api, household, tmp_path):
    enable(tmp_path)
    object.__setattr__(settings, "push_approved", False)
    assert not api.get("/api/notifications/config").json()["available"]
    user, child = household
    with DB.begin() as db:
        db.add(PushTestGrant(user_id=user["id"], expires=int(now()) + 3600))
    assert not api.get("/api/notifications/config").json()["available"]
    assert api.post("/api/notifications/test", json={"mode": "send"}).status_code == 403
    with DB.begin() as db:
        db.get(Family, user["families"][0]["id"]).synthetic = True
        db.get(Child, child["id"]).preferences = {"quiet_start": 0, "quiet_end": 0}
    assert api.get("/api/notifications/config").json()["test_mode"]
    with TestClient(app, headers=HEADERS) as public:
        assert not public.get("/api/notifications/config").json()["available"]
    device(api)
    with DB.begin() as db:
        n.prepare(db)
        assert not list(db.scalars(select(PushDelivery)))


def test_own_session_only_validation_has_distinct_result_and_revocation(api, household, tmp_path, monkeypatch):
    enable(tmp_path)
    object.__setattr__(settings, "push_approved", False)
    user, child = household
    grant(user, child)
    registration = device(api)
    assert api.post("/api/notifications/test", json={"mode": "validate", "token": "arbitrary"}).status_code == 422
    queued = api.post("/api/notifications/test", json={"mode": "validate"})
    assert queued.status_code == 202
    calls = []
    monkeypatch.setattr(n, "send_fcm", lambda *args, **kw: calls.append((args, kw)))
    assert n.deliver_one(DB)
    assert calls[0][1] == {"testing": True, "validate_only": True}
    assert api.get("/api/notifications/tests").json()["results"][0]["status"] == "validated"
    queued = api.post("/api/notifications/test", json={"mode": "send"})
    assert queued.status_code == 202
    with DB.begin() as db:
        db.get(Session, db.get(PushDevice, registration["id"]).session_id).revoked = True
    n.deliver_one(DB)
    assert len(calls) == 1
    with DB() as db:
        assert db.get(PushDelivery, queued.json()["id"]).status == "suppressed"


def test_child_requires_parent_consent_and_later_withdrawal_stops_send(api, household, tmp_path):
    enable(tmp_path)
    user, child = household
    with TestClient(app, headers=HEADERS) as kid:
        login = kid.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}).json()
        kid.headers["Authorization"] = "Bearer " + login["token"]
        assert not kid.get("/api/notifications/config").json()["available"]
        assert kid.put("/api/notifications/device", json={"token": "x" * 50, "platform": "android"}).status_code == 403
        response = api.put(f"/api/children/{child['id']}/preferences", json={"push_consent": True})
        assert response.status_code == 200
        d = device(kid)
        assert kid.put(f"/api/children/{child['id']}/preferences", json={"push_consent": True}).status_code == 403
        assert api.put(f"/api/children/{child['id']}/preferences", json={"push_consent": False}).status_code == 200
        with DB() as db:
            assert db.get(PushDevice, d["id"]) is None
        assert not kid.get("/api/notifications/config").json()["available"]


def test_quiet_time_and_expired_grant_block_synthetic_test(api, household, tmp_path):
    enable(tmp_path)
    object.__setattr__(settings, "push_approved", False)
    user, child = household
    grant(user, child)
    d = device(api)
    with DB.begin() as db:
        current = __import__("datetime").datetime.now(__import__("zoneinfo").ZoneInfo("Europe/Berlin")).hour
        device_row = db.get(PushDevice, d["id"])
        device_row.quiet_start, device_row.quiet_end = current, (current + 1) % 24
    assert api.post("/api/notifications/test", json={"mode": "send"}).status_code == 409
    with DB.begin() as db:
        db.get(PushTestGrant, user["id"]).expires = int(now()) - 1
    assert api.post("/api/notifications/test", json={"mode": "validate"}).status_code == 403


def test_account_switch_revokes_old_session_and_push_without_transferring_optin(api, household, tmp_path):
    enable(tmp_path)
    registration = device(api)
    old_bearer = api.headers["Authorization"]
    login = api.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"})
    assert login.status_code == 200
    with TestClient(app, headers={**HEADERS, "Authorization": old_bearer}) as previous:
        assert previous.get("/api/auth/me").status_code == 401
    api.headers["Authorization"] = "Bearer " + login.json()["token"]
    assert api.get("/api/notifications/devices").json() == []
    assert not api.get("/api/notifications/config").json()["available"]
    with DB() as db:
        assert db.get(PushDevice, registration["id"]) is None
