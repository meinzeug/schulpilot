"""Exam notices derive saved facts; push remains opt-in, neutral and bounded."""

import io
import json
import uuid
from datetime import datetime
from zoneinfo import ZoneInfo

import httpx
import pytest
from PIL import Image
from schulpilot import exam_notifications as notices
from schulpilot import exams
from schulpilot import notifications as n
from schulpilot.config import settings
from schulpilot.db import DB, Child, Job, LearningUnit, NotificationRead, PushDelivery, PushDevice, Session, Usage, now
from schulpilot.exam_models import Exam
from sqlalchemy import func, select
from test_exam_reviews import analyze, finish
from test_exam_reviews import paper as paper
from test_exam_reviews import transport as transport
from test_exams import body, create, prepare
from test_exams import book as book
from test_notifications import device, enable
from test_providers import configured


def planned(api, book, *, reminders=True):
    value = body(book, count=3)
    value.update(exam_date=None, reminders=reminders, reminder_time="00:00",
        schedule={"dates": [datetime.fromtimestamp(int(now()), ZoneInfo("Europe/Berlin")).date().isoformat()]})
    return create(api, book, value)


def ready_round(api, book):
    configured(book["parent"]["families"][0]["id"])
    exam = planned(api, book, reminders=False)
    result = prepare(book, exam)
    assert result.status_code == 202, result.text
    with DB.begin() as db:
        job = db.get(Job, result.json()["id"])
        unit = LearningUnit(child_id=book["child"]["id"], subject="Mathematik", topic="Brüche 0",
            explanation="PRIVATE ERKLÄRUNG", questions=[{"prompt": "Private Frage " + str(i),
                "answer": "PRIVATE ANTWORT"} for i in range(3)], provider="synthetic")
        db.add(unit)
        db.flush()
        exams.attach_prepared_unit(db, job, unit)
        job.status, job.finished = "completed", int(now())
    return exam


def push_device(book, tmp_path):
    enable(tmp_path)
    with DB.begin() as db:
        child = db.get(Child, book["child"]["id"])
        child.preferences = {"push_consent": True, "reminders": False, "quiet_start": 0, "quiet_end": 0}
    return device(book["client"])


def test_inbox_reminder_does_not_require_push_and_has_legacy_route(api, book):
    exam = planned(api, book)
    client = book["client"]
    legacy = client.get("/api/notifications/inbox").json()
    assert len(legacy["items"]) == 1 and legacy["items"][0]["route"] == "/app"
    modern = client.get("/api/notifications/inbox", headers={"X-Schulpilot-Capabilities": "messages-v1,exams-v1"}).json()
    item = modern["items"][0]
    assert item["kind"] == "exam_reminder" and item["id"] == legacy["items"][0]["id"]
    assert item["route"] == f"/exams/{book['child']['id']}?exam={exam['id']}&session={exam['sessions'][0]['id']}"
    assert client.post("/api/notifications/inbox/read", json={"ids": [item["id"]]}).status_code == 200
    assert client.get("/api/notifications/inbox").json()["unread"] == 0
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(NotificationRead)) == 1
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
        assert db.scalar(select(func.count()).select_from(Job)) == 0
    parent = api.get("/api/notifications/inbox").json()["items"][0]
    assert parent["route"] == f"/child/{book['child']['id']}"


def test_ready_round_is_revision_bound_private_and_read_only(api, book):
    exam = ready_round(api, book)
    route = "/api/notifications/inbox"
    for _ in range(2):
        response = book["client"].get(route, headers={"X-Schulpilot-Capabilities": "exams-v1"})
        item = response.json()["items"][0]
        assert item["kind"] == "exam_ready" and exam["id"] in item["route"]
        assert all(text not in response.text for text in ["PRIVATE ANTWORT", "PRIVATE ERKLÄRUNG", "Private Frage"])
    with DB.begin() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
        db.get(Exam, exam["id"]).plan_revision += 1
    assert not book["client"].get(route).json()["items"]


def test_photo_attachment_keeps_saved_preparation_plan_and_today_link(api, book):
    configured(book["parent"]["families"][0]["id"])
    exam = planned(api, book)
    request = prepare(book, exam)
    output = io.BytesIO()
    Image.new("RGB", (64, 64), "cyan").save(output, "PNG")
    response = api.post(f"/api/exams/{exam['id']}/pages?revision=1",
        files={"file": ("synthetic.png", output.getvalue(), "image/png")},
        headers={"Idempotency-Key": uuid.uuid4().hex})
    assert response.status_code == 201, response.text
    saved = api.get(f"/api/exams/{exam['id']}").json()
    assert saved["revision"] == 2 and saved["plan_revision"] == 1 and saved["review_page_count"] == 1
    assert [s["id"] for s in saved["sessions"]] == [s["id"] for s in exam["sessions"]]
    with DB() as db:
        job = db.get(Job, request.json()["id"])
        assert exams.guard_preparation(db, job)
        today = exams.today_sessions(db, db.get(Child, book["child"]["id"]))
        assert len(today) == 1 and today[0]["session_id"] == exam["sessions"][0]["id"]
        assert db.scalar(select(func.count()).select_from(Usage)) == 1


def test_ready_written_review_is_source_bound_and_not_a_grade(paper, transport):
    analyze(paper)
    finish()
    response = paper["client"].get("/api/notifications/inbox", headers={"X-Schulpilot-Capabilities": "exams-v1"})
    item = response.json()["items"][0]
    assert item["kind"] == "exam_ready" and item["route"].endswith("&tab=review")
    assert all(text not in response.text for text in ["1/8", "0 von 2", "Nenner bleibt"])
    with DB.begin() as db:
        from schulpilot.db import Material

        db.get(Material, paper["material_id"]).revision += 1
    assert not paper["client"].get("/api/notifications/inbox").json()["items"]


def test_exam_push_is_one_neutral_bundle_without_general_reminder_optin(api, book, tmp_path, monkeypatch):
    exam = planned(api, book)
    push_device(book, tmp_path)
    fixed = int(now())
    with DB.begin() as db:
        n.prepare(db, fixed)
        n.prepare(db, fixed)
    with DB() as db:
        deliveries = list(db.scalars(select(PushDelivery)))
        assert len(deliveries) == 1 and deliveries[0].kind == "exam_reminder"
    sent = []
    monkeypatch.setattr(n, "send_fcm", lambda *args, **kwargs: sent.append((args, kwargs)))
    assert n.deliver_one(DB)
    assert len(sent) == 1 and sent[0][0][1] == "exam_reminder"
    assert sent[0][1]["exam_path"] == f"/exams/{book['child']['id']}?exam={exam['id']}&session={exam['sessions'][0]['id']}"


@pytest.mark.parametrize("change", ["consent", "device", "device_quiet", "child_quiet", "archive", "session"])
def test_queued_exam_push_rechecks_consent_quiet_and_current_scope(api, book, tmp_path, monkeypatch, change):
    exam = planned(api, book)
    value = push_device(book, tmp_path)
    with DB.begin() as db:
        n.prepare(db)
    with DB.begin() as db:
        child = db.get(Child, book["child"]["id"])
        stored = db.get(PushDevice, value["id"])
        if change == "consent":
            child.preferences = {**child.preferences, "push_consent": False}
        elif change == "device":
            stored.reminders = False
        elif change == "device_quiet":
            stored.quiet_start = datetime.now(ZoneInfo(stored.timezone)).hour
            stored.quiet_end = (stored.quiet_start + 1) % 24
        elif change == "child_quiet":
            hour = datetime.now(ZoneInfo("Europe/Berlin")).hour
            child.preferences = {**child.preferences, "quiet_start": hour, "quiet_end": (hour + 1) % 24}
        elif change == "archive":
            db.get(Exam, exam["id"]).archived = True
        else:
            db.get(Session, stored.session_id).revoked = True
    sent = []
    monkeypatch.setattr(n, "send_fcm", lambda *args, **kwargs: sent.append(args))
    assert n.deliver_one(DB) and sent == []
    with DB() as db:
        assert db.scalar(select(PushDelivery)).status == "suppressed"


@pytest.mark.parametrize("path,expected", [
    ("/exams/" + "a" * 32 + "?exam=" + "b" * 32, True),
    ("/exams/" + "a" * 32 + "?exam=" + "b" * 32 + "&session=" + "c" * 32, True),
    ("/exams/" + "a" * 32 + "?exam=" + "b" * 32 + "&tab=review", True),
    ("/unit/" + "a" * 32, True), ("https://evil.invalid/exams/a", False), ("//evil.invalid", False),
    ("/app?exam=anything", False), ("/exams/" + "a" * 32 + "?exam=" + "b" * 32 + "&unexpected=1", False),
    ("/exams/" + "a" * 32 + "?exam=" + "b" * 32 + "#fragment", False),
    ("/unit/" + "a" * 32 + "\n", False),
])
def test_notification_paths_are_strict_local_canonical_targets(path, expected):
    assert notices.valid_exam_path(path) is expected


def test_fcm_keeps_legacy_route_with_validated_exam_extra_and_sw_fallback(api, tmp_path, monkeypatch):
    from pathlib import Path

    from google.oauth2 import service_account

    enable(tmp_path)
    Path(settings.fcm_service_account_file).write_text(json.dumps({"type": "service_account",
        "project_id": "synthetic-project", "token_uri": "https://oauth2.googleapis.com/token"}))

    class Credential:
        token = "SYNTHETIC-OAUTH-TOKEN"

        def refresh(self, request):
            pass

    monkeypatch.setattr(service_account.Credentials, "from_service_account_info", lambda *args, **kwargs: Credential())
    sent = []

    class Client:
        def __init__(self, **kwargs):
            assert kwargs["follow_redirects"] is False

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def post(self, url, headers, json):
            sent.append(json["message"])
            return httpx.Response(200, json={"name": "synthetic-message"})

    path = "/exams/" + "a" * 32 + "?exam=" + "b" * 32
    monkeypatch.setattr(n.httpx, "Client", Client)
    n.send_fcm("SYNTHETIC-TOKEN", "exam_ready", exam_path=path)
    assert sent[0]["data"] == {"route": "/app", "exam_path": path}
    assert sent[0]["webpush"]["fcm_options"]["link"] == settings.public_url + path
    assert set(sent[0]["notification"]) == {"title", "body"}
    for invalid in ("//evil.invalid", "/unit/" + "a" * 32 + "?private=yes"):
        with pytest.raises(n.FcmError, match="INVALID_EXAM_PATH"):
            n.send_fcm("SYNTHETIC-TOKEN", "exam_ready", exam_path=invalid)
    assert len(sent) == 1
    response = api.get("/api/notifications/service-worker.js")
    assert "data.FCM_MSG.data" in response.text and "openWindow(target)" in response.text
    assert "EXAM_PATH" not in response.text and "path : '/app'" in response.text


def test_ready_push_does_not_require_calendar_reminders(api, book, tmp_path, monkeypatch):
    exam = ready_round(api, book)
    push_device(book, tmp_path)
    with DB.begin() as db:
        assert db.get(Exam, exam["id"]).reminders is False
        n.prepare(db)
    with DB() as db:
        assert [row.kind for row in db.scalars(select(PushDelivery))] == ["exam_ready"]
    sent = []
    monkeypatch.setattr(n, "send_fcm", lambda *args, **kwargs: sent.append((args, kwargs)))
    assert n.deliver_one(DB) and len(sent) == 1
    assert sent[0][0][1] == "exam_ready" and exam["id"] in sent[0][1]["exam_path"]


def test_today_metadata_is_bounded_and_independent_of_reminder_and_time(api, book):
    for _ in range(4):
        planned(api, book, reminders=False)
    with DB() as db:
        child = db.get(Child, book["child"]["id"])
        saved = exams.today_sessions(db, child)
        assert len(saved) == 3
        assert all(row["requested_questions"] == 3 and row["minutes"] == 20 for row in saved)
        assert all(key not in str(saved) for key in ("material_refs", "questions\":", "answer"))
        assert not exams.due_reminders(db, child)
        assert db.scalar(select(func.count()).select_from(Job)) == 0
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_ready_event_and_ack_disappear_after_actor_session_revocation(api, book):
    ready_round(api, book)
    modern = {"X-Schulpilot-Capabilities": "exams-v1"}
    item = api.get("/api/notifications/inbox", headers=modern).json()["items"][0]
    with DB.begin() as db:
        job = db.scalar(select(Job))
        db.get(Session, job.payload["exam_actor_session_id"]).revoked = True
    assert api.get("/api/notifications/inbox", headers=modern).json()["items"] == []
    assert api.post("/api/notifications/inbox/read", json={"ids": [item["id"]]}).status_code == 404


def add_report_page(paper, *, confirmed):
    from schulpilot.db import Material
    from schulpilot.exam_review_models import ExamReviewPage

    with DB.begin() as db:
        page = Material(child_id=paper["child_id"], purpose="exam", title="Zweite künstliche Arbeitsseite",
            subject="Mathematik", topic="Brüche", confirmed=confirmed,
            status="confirmed" if confirmed else "uploaded",
            content="Aufgabe 2: Berechne 2/5 + 1/5. Alte Antwort: 1/5. Lehrermarkierung: Zähler addieren." if confirmed else "")
        db.add(page)
        db.flush()
        db.add(ExamReviewPage(exam_id=paper["exam_id"], material_id=page.id, position=2, upload_revision=1))
        db.get(Exam, paper["exam_id"]).revision += 1
        return page.id


def test_ready_excerpt_requires_its_selected_pages_but_not_other_unconfirmed_photos(paper, transport):
    from test_exam_reviews import context

    add_report_page(paper, confirmed=False)
    response = paper["client"].post(paper["path"] + "/analyze",
        json={**context(paper), "page_ids": [paper["material_id"]]},
        headers={"Idempotency-Key": uuid.uuid4().hex})
    assert response.status_code == 202, response.text
    finish()
    notice = paper["client"].get("/api/notifications/inbox", headers={"X-Schulpilot-Capabilities": "exams-v1"})
    assert len(notice.json()["items"]) == 1, notice.text
    assert notice.json()["items"][0]["kind"] == "exam_ready"


def test_append_ready_receipt_is_new_only_after_success_and_keeps_previous_draft(paper, transport):
    from schulpilot.providers import ProviderError
    from test_exam_reviews import context, ready

    second_page = add_report_page(paper, confirmed=True)
    initial = ready(paper, transport)
    client = paper["client"]
    headers = {"X-Schulpilot-Capabilities": "exams-v1"}
    task_id = initial["tasks"][0]["id"]
    saved = client.put(paper["path"] + "/tasks/" + task_id + "/draft",
        json={**context(paper), "draft_revision": 0, "text": "UNSUBMITTED-APPEND-DRAFT"})
    assert saved.status_code == 200, saved.text
    original = client.get("/api/notifications/inbox", headers=headers).json()["items"][0]
    assert client.post("/api/notifications/inbox/read", json={"ids": [original["id"]]}).status_code == 200

    def fail():
        raise ProviderError("Synthetischer Abbruch ohne weitere Wiederholung.")

    transport["effect"] = fail
    request = {**context(paper), "append": True, "page_ids": [second_page]}
    pending = client.post(paper["path"] + "/analyze", json=request, headers={"Idempotency-Key": uuid.uuid4().hex})
    assert pending.status_code == 202, pending.text
    while_pending = client.get("/api/notifications/inbox", headers=headers).json()
    assert [row["id"] for row in while_pending["items"]] == [original["id"]]
    assert while_pending["unread"] == 0
    finish()
    failed = client.get("/api/notifications/inbox", headers=headers).json()
    assert [row["id"] for row in failed["items"]] == [original["id"]] and failed["unread"] == 0
    assert client.get(paper["path"]).json()["tasks"][0]["draft"]["text"] == "UNSUBMITTED-APPEND-DRAFT"
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 2
        assert db.scalar(select(func.count()).select_from(Usage)) == 2
    transport["effect"] = None
    transport["output"] = {"summary": "Ein weiterer ausdrücklich begrenzter KI-Auszug.", "uncertainties": [],
        "tasks": [{"id": "t1", "question": "Berechne 2/5 + 1/5.", "original_answer": "1/5",
            "teacher_feedback": "Zähler addieren.", "score_label": "", "ai_proposal": "Vergleiche mit der Heftregel.",
            "uncertainties": [], "sources": [{"ref": "p2", "quote": "Berechne 2/5 + 1/5."}]}]}
    retry = client.post(paper["path"] + "/analyze", json=request, headers={"Idempotency-Key": uuid.uuid4().hex})
    assert retry.status_code == 202, retry.text
    finish()
    final = client.get("/api/notifications/inbox", headers=headers).json()
    assert len(final["items"]) == 1 and final["items"][0]["id"] != original["id"] and final["unread"] == 1
    visible = client.get(paper["path"]).json()
    assert len(visible["tasks"]) == 2 and visible["tasks"][0]["id"] == task_id
    assert visible["tasks"][0]["draft"]["text"] == "UNSUBMITTED-APPEND-DRAFT"
    assert "UNSUBMITTED-APPEND-DRAFT" not in json.dumps(final)
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 3
        assert db.scalar(select(func.count()).select_from(Usage)) == 3
