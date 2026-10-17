import io
import json
import zipfile
from concurrent.futures import ThreadPoolExecutor

from conftest import HEADERS, create_child, register
from fastapi.testclient import TestClient
from schulpilot import notifications as n
from schulpilot.db import (
    DB,
    Child,
    Job,
    Membership,
    Message,
    NotificationRead,
    PushDevice,
    Session,
    User,
    VocabularyImport,
    now,
    uid,
)
from schulpilot.main import app
from sqlalchemy import delete, func, select
from test_notifications import device, enable


def test_two_devices_acknowledge_one_event_once(api, household):
    _, child = household
    with DB.begin() as db:
        message = Message(id=uid(), child_id=child["id"], kind="help", body="Synthetic request")
        db.add(message)
        key = "message:" + message.id
    authorization = api.headers["Authorization"]

    def acknowledge(_):
        with TestClient(app, headers={**HEADERS, "Authorization": authorization}) as device_client:
            return device_client.post("/api/notifications/inbox/read", json={"ids": [key]}).status_code

    with ThreadPoolExecutor(max_workers=2) as pool:
        assert list(pool.map(acknowledge, range(2))) == [200, 200]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(NotificationRead)) == 1


def test_inbox_is_real_private_and_acknowledgements_idempotent(api, household):
    owner, child = household
    with DB.begin() as db:
        message = Message(id=uid(), child_id=child["id"], kind="help", body="PRIVATE WORDS NEVER IN THE FEED")
        db.add(message)
        key = "message:" + message.id
    for _ in range(3):
        response = api.get("/api/notifications/inbox")
        assert response.status_code == 200
        assert response.json()["unread"] == 1
        assert "PRIVATE WORDS" not in response.text
    assert api.post("/api/notifications/inbox/read", json={"ids": [key, key]}).status_code == 200
    assert api.post("/api/notifications/inbox/read", json={"ids": [key]}).status_code == 200
    assert api.get("/api/notifications/inbox").json()["unread"] == 0
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(NotificationRead)) == 1
        assert db.scalar(select(func.count()).select_from(Job)) == 0
    with TestClient(app, headers=HEADERS) as kid:
        token = kid.post(
            "/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}
        ).json()["token"]
        kid.headers["Authorization"] = "Bearer " + token
        assert kid.get("/api/notifications/inbox").json()["items"] == []
        assert kid.post("/api/notifications/inbox/read", json={"ids": [key]}).status_code == 404
    archive = api.get(f"/api/families/{owner['families'][0]['id']}/export")
    with zipfile.ZipFile(io.BytesIO(archive.content)) as file:
        assert json.loads(file.read("family.json"))["notification_reads"][0]["event_key"] == key
    with DB.begin() as db:
        db.execute(delete(Child).where(Child.id == child["id"]))
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(NotificationRead)) == 0


def test_inbox_denies_other_families_admin_and_revoked_membership(api, household, mailbox):
    owner, child = household
    with DB.begin() as db:
        db.add(Message(child_id=child["id"], kind="help", body="PRIVATE", created=int(now())))
    assert api.get("/api/notifications/inbox").json()["unread"] == 1
    register(api, mailbox, "other@example.org")
    assert api.get("/api/notifications/inbox").json()["items"] == []
    with DB.begin() as db:
        other = db.scalar(select(User).where(User.email == "other@example.org"))
        other.role = "admin"
    assert api.get("/api/notifications/inbox").status_code == 403
    with DB.begin() as db:
        other.role = "parent"
        db.merge(other)
        db.add(Membership(user_id=other.id, family_id=owner["families"][0]["id"], permission="view"))
    key = api.get("/api/notifications/inbox").json()["items"][0]["id"]
    with DB.begin() as db:
        db.execute(
            delete(Membership).where(Membership.user_id == other.id, Membership.family_id == owner["families"][0]["id"])
        )
    assert api.get("/api/notifications/inbox").json()["items"] == []
    assert api.post("/api/notifications/inbox/read", json={"ids": [key]}).status_code == 404


def test_child_reply_bell_does_not_require_push_consent_and_is_bounded(api, household):
    owner, child = household
    sibling = create_child(api, owner, "sibling")
    with DB.begin() as db:
        db.add(Message(child_id=sibling["id"], kind="reply", body="SIBLING PRIVATE"))
        db.add(Message(child_id=child["id"], kind="reply", body="OLD", created=int(now()) - 31 * 86400))
        for index in range(60):
            db.add(Message(child_id=child["id"], kind="reply", body="PRIVATE", created=int(now()) - index))
    login = api.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}).json()
    api.headers["Authorization"] = "Bearer " + login["token"]
    assert api.get("/api/notifications/config").json()["available"] is False
    data = api.get("/api/notifications/inbox").json()
    assert data["unread"] == len(data["items"]) == data["limit"] == 50
    assert all(row["child_id"] == child["id"] for row in data["items"])
    assert api.post("/api/auth/logout").status_code == 200
    assert api.get("/api/notifications/inbox").status_code == 401


def test_completed_word_import_notifies_with_consent_quiet_and_source_session_recheck(api, household, tmp_path):
    owner, child = household
    enable(tmp_path)
    parent_session = None
    with DB() as db:
        parent_session = db.scalar(select(Session).where(Session.user_id == owner["id"])).id
    with TestClient(app, headers=HEADERS) as separate_device:
        login = separate_device.post(
            "/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}
        ).json()
    api.headers["Authorization"] = "Bearer " + login["token"]
    with DB.begin() as db:
        db.get(Child, child["id"]).preferences = {
            "push_consent": True,
            "reminders": False,
            "quiet_start": 0,
            "quiet_end": 0,
        }
        job = Job(
            id=uid(),
            child_id=child["id"],
            kind="vocabulary_import",
            status="completed",
            payload={},
            finished=int(now()),
            idempotency=uid(),
        )
        db.add(job)
        db.flush()
        row = VocabularyImport(
            id=uid(),
            child_id=child["id"],
            user_id=owner["id"],
            session_id=parent_session,
            request_key=uid(),
            request_digest="x" * 64,
            target_locale="en-GB",
            title="Synthetic words",
            status="review",
            job_id=job.id,
        )
        db.add(row)
    d = device(api)
    with DB.begin() as db:
        stored = db.get(PushDevice, d["id"])
        assert "learning_ready" in n.due_kinds(db, stored, int(now()))
        n.prepare(db)
        n.prepare(db)
        from schulpilot.db import PushDelivery

        assert (
            db.scalar(select(func.count()).select_from(PushDelivery).where(PushDelivery.kind == "learning_ready")) == 1
        )
        db.get(Session, parent_session).revoked = True
        assert "learning_ready" not in n.due_kinds(db, stored, int(now()))
        db.get(Session, parent_session).revoked = False
        db.get(Child, child["id"]).preferences = {"push_consent": False, "quiet_start": 0, "quiet_end": 0}
        assert n.due_kinds(db, stored, int(now())) == []
    assert any(row["kind"] == "words_ready" for row in api.get("/api/notifications/inbox").json()["items"])
