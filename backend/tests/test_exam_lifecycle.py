"""Real auth/export/erasure integration for artificial private exam drafts."""

import io
import json
import uuid
import zipfile
from contextlib import contextmanager

import pytest
from conftest import HEADERS
from fastapi.testclient import TestClient
from schulpilot.config import settings
from schulpilot.db import DB, Child, Material, Session, Usage, now
from schulpilot.erasure import reconcile
from schulpilot.exam_models import Exam
from schulpilot.exam_review_models import ExamReview, ExamReviewDraft, ExamReviewPage, ExamReviewTurn
from schulpilot.main import app
from schulpilot.security import digest
from schulpilot.worker import maintenance
from sqlalchemy import func, select
from test_exam_reviews import context, finish, ready
from test_exam_reviews import paper as paper
from test_exam_reviews import transport as transport

PRIVATE = "UNSUBMITTED-EXAM-PRIVATE-DRAFT"


def save(paper, text=PRIVATE, client=None):
    client = client or paper["client"]
    value = client.get(paper["path"])
    assert value.status_code == 200, value.text
    response = client.put(paper["path"] + "/tasks/" + value.json()["tasks"][0]["id"] + "/draft", json={"revision": value.json()["revision"],
        "context_revision": value.json()["context_revision"], "draft_revision": 0, "text": text})
    assert response.status_code == 200, response.text
    return response.json()["draft"]


@contextmanager
def second_device():
    with TestClient(app, headers=HEADERS) as client:
        login = client.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"})
        assert login.status_code == 200, login.text
        client.headers["Authorization"] = "Bearer " + login.json()["token"]
        yield client


@pytest.mark.parametrize("action", ["logout", "self_revoke", "parent_revoke", "account_switch"])
def test_ending_one_session_erases_only_its_unsubmitted_draft(api, paper, transport, action):
    ready(paper, transport)
    save(paper)
    with DB() as db:
        own_session = db.scalar(select(ExamReviewDraft.session_id))
    with second_device() as second:
        save(paper, "OTHER-DEVICE-PRIVATE", second)
        if action == "logout":
            response = paper["client"].post("/api/auth/logout")
        elif action == "self_revoke":
            response = paper["client"].delete("/api/auth/sessions/" + own_session)
        elif action == "parent_revoke":
            response = api.delete(f"/api/children/{paper['child_id']}/sessions/{own_session}")
        else:
            response = paper["client"].post("/api/auth/login",
                json={"username": "parent@example.org", "password": "secure-parent-pass-123"})
        assert response.status_code == 200, response.text
        assert paper["client"].get("/api/auth/me").status_code == 401
        assert second.get(paper["path"]).json()["tasks"][0]["draft"]["text"] == "OTHER-DEVICE-PRIVATE"
    with DB() as db:
        rows = list(db.scalars(select(ExamReviewDraft)))
        assert len(rows) == 1 and rows[0].text == "OTHER-DEVICE-PRIVATE"
        assert db.get(Session, own_session).revoked
        assert db.scalar(select(func.count()).select_from(ExamReview)) == 1
        assert db.scalar(select(func.count()).select_from(Usage)) == 1


def test_parent_child_password_reset_revokes_all_child_drafts_but_wrong_password_does_not(api, paper, transport):
    ready(paper, transport)
    save(paper)
    with second_device() as second:
        save(paper, "OTHER-DEVICE-PRIVATE", second)
        route = f"/api/children/{paper['child_id']}/password"
        assert api.put(route, json={"password": "new-child-password-123", "parent_password": "incorrect"}).status_code == 403
        with DB() as db:
            assert db.scalar(select(func.count()).select_from(ExamReviewDraft)) == 2
        result = api.put(route, json={"password": "new-child-password-123", "parent_password": "secure-parent-pass-123"})
        assert result.status_code == 200, result.text
        assert second.get("/api/auth/me").status_code == 401
    assert paper["client"].get("/api/auth/me").status_code == 401
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(ExamReviewDraft)) == 0
        assert db.scalar(select(func.count()).select_from(ExamReview)) == 1
        assert db.scalar(select(func.count()).select_from(Usage)) == 1


def test_parent_recovery_ends_parent_sessions_without_erasing_child_private_draft(api, paper, transport, mailbox):
    ready(paper, transport)
    save(paper)
    assert api.post("/api/auth/recovery", json={"email": "parent@example.org"}).status_code == 200
    token = mailbox[-1]["token"]
    assert api.post("/api/auth/reset", json={"token": token, "password": "new-parent-password-123"}).status_code == 200
    assert api.get("/api/auth/me").status_code == 401
    assert paper["client"].get(paper["path"]).json()["tasks"][0]["draft"]["text"] == PRIVATE
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(ExamReviewDraft)) == 1


def test_account_session_cap_erases_evicted_draft_and_preserves_new_device(paper, transport):
    ready(paper, transport)
    save(paper)
    with DB.begin() as db:
        row = db.scalar(select(ExamReviewDraft))
        old_session = row.session_id
        db.get(Session, old_session).created = int(now()) - 3600
    with second_device() as second:
        save(paper, "CURRENT-DEVICE-PRIVATE", second)
        # Existing devices may have signed in on earlier days. Model those
        # saved sessions instead of bypassing the separate login/IP throttle.
        with DB.begin() as db:
            user_id = db.get(Child, paper["child_id"]).user_id
            for index in range(8):
                db.add(Session(user_id=user_id, token_hash=digest("synthetic-existing-" + uuid.uuid4().hex),
                    device="Existing artificial device", created=int(now()) - 100 - index,
                    seen=int(now()), expires=int(now()) + 86400))
        with second_device():
            pass
        assert second.get(paper["path"]).json()["tasks"][0]["draft"]["text"] == "CURRENT-DEVICE-PRIVATE"
    with DB() as db:
        assert db.get(Session, old_session).revoked
        assert db.scalar(select(func.count()).select_from(ExamReviewDraft).where(ExamReviewDraft.session_id == old_session)) == 0
    assert paper["client"].get("/api/auth/me").status_code == 401


def test_actual_child_export_contains_submitted_turn_but_not_private_unsubmitted_draft(api, paper, transport):
    ready(paper, transport)
    save(paper)
    explicit = "EXPLICIT-SUBMITTED-REVIEW-DRAFT"
    task_id = paper["client"].get(paper["path"]).json()["tasks"][0]["id"]
    request = paper["client"].post(paper["path"] + "/tasks/" + task_id + "/help",
        json={**context(paper), "action": "check", "draft": explicit}, headers={"Idempotency-Key": uuid.uuid4().hex})
    assert request.status_code == 202, request.text
    finish()
    response = api.get(f"/api/children/{paper['child_id']}/export?include_photos=false")
    assert response.status_code == 200, response.text
    with zipfile.ZipFile(io.BytesIO(response.content)) as archive:
        assert archive.namelist() == ["child.json"]
        exported = json.loads(archive.read("child.json"))
    serialized = json.dumps(exported)
    assert PRIVATE not in serialized and "exam_review_drafts" not in exported
    assert explicit in serialized and exported["exam_review_turns"][0]["draft"] == explicit
    assert "session_id" not in json.dumps({key: value for key, value in exported.items() if key.startswith("exam_")})


def test_actual_source_delete_and_restore_replay_remove_private_review_derived_rows(api, paper, transport):
    ready(paper, transport)
    save(paper)
    route = f"/api/children/{paper['child_id']}/materials"
    preview = api.post(route + "/delete-preview", json={"ids": [paper["material_id"]]})
    assert preview.status_code == 200, preview.text
    result = api.post(route + "/bulk-delete", json={"selection_token": preview.json()["selection_token"],
        "delete_linked_units": True})
    assert result.status_code == 200, result.text
    with DB() as db:
        assert db.get(Material, paper["material_id"]) is None
        assert db.scalar(select(func.count()).select_from(ExamReview)) == 0
        assert db.scalar(select(func.count()).select_from(ExamReviewDraft)) == 0
        assert db.get(Material, paper["book_id"]) is not None
        assert db.scalar(select(func.count()).select_from(Usage)) == 1


def test_journal_reconcile_uses_same_source_cleanup_without_changing_billing(paper, transport):
    ready(paper, transport)
    save(paper)
    with DB.begin() as db:
        assert reconcile(db, [{"scope": "material", "target": paper["material_id"]}]) == []
    with DB() as db:
        assert db.get(Material, paper["material_id"]) is None
        assert db.get(Material, paper["book_id"]) is not None
        assert db.scalar(select(func.count()).select_from(ExamReview)) == 0
        assert db.scalar(select(func.count()).select_from(ExamReviewDraft)) == 0
        assert db.scalar(select(func.count()).select_from(Usage)) == 1


def test_worker_retention_removes_old_exam_private_photo_and_review_only(paper, transport):
    ready(paper, transport)
    save(paper)
    filename = uuid.uuid4().hex + ".jpg"
    directory = settings.data_dir / "uploads"
    directory.mkdir(exist_ok=True, mode=0o700)
    photo = directory / filename
    photo.write_bytes(b"SYNTHETIC-PRIVATE-PHOTO")
    with DB.begin() as db:
        cutoff = int(now()) - 366 * 86400
        exam = db.get(Exam, paper["exam_id"])
        exam.updated = cutoff
        page = db.get(Material, paper["material_id"])
        page.created, page.path = cutoff, filename
    maintenance()
    assert not photo.exists()
    with DB() as db:
        assert db.get(Exam, paper["exam_id"]) is None
        assert db.get(Material, paper["material_id"]) is None
        assert db.get(Material, paper["book_id"]) is not None
        assert db.get(Child, paper["child_id"]) is not None
        for model in (ExamReview, ExamReviewPage, ExamReviewDraft, ExamReviewTurn):
            assert db.scalar(select(func.count()).select_from(model)) == 0
        assert db.scalar(select(func.count()).select_from(Usage)) == 1


def test_member_revocation_ends_parent_access_without_touching_child_private_draft(api, paper, transport, mailbox):
    ready(paper, transport)
    save(paper)
    family_id = paper["parent"]["families"][0]["id"]
    invitation = api.post(f"/api/families/{family_id}/invitations",
        json={"email": "exam-guest@example.org", "permission": "view"})
    assert invitation.status_code == 201, invitation.text
    accepted = api.post("/api/invitations/accept", json={"token": mailbox[-1]["token"],
        "password": "guest-parent-password-123", "display_name": "Synthetic viewer"})
    assert accepted.status_code == 200, accepted.text
    with TestClient(app, headers=HEADERS) as guest:
        login = guest.post("/api/auth/login", json={"username": "exam-guest@example.org",
            "password": "guest-parent-password-123"})
        assert login.status_code == 200, login.text
        guest.headers["Authorization"] = "Bearer " + login.json()["token"]
        response = guest.get(paper["path"])
        assert response.status_code == 200 and PRIVATE not in response.text
        membership = next(row for row in api.get(f"/api/families/{family_id}/members").json() if not row["self"])
        assert api.delete(f"/api/families/{family_id}/members/{membership['id']}").status_code == 200
        assert guest.get(paper["path"]).status_code == 401
    assert paper["client"].get(paper["path"]).json()["tasks"][0]["draft"]["text"] == PRIVATE
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(ExamReviewDraft)) == 1
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
