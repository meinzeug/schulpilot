"""Actual private review routes and durable jobs with artificial pages and mocked transport."""

import copy
import io
import json
import uuid

import pytest
from conftest import HEADERS
from fastapi import HTTPException
from fastapi.testclient import TestClient
from PIL import Image
from schulpilot import exam_review, exams, tutor
from schulpilot.config import settings
from schulpilot.db import (
    DB,
    Attempt,
    Family,
    Job,
    LearningUnit,
    Mastery,
    Material,
    Membership,
    SchoolGrade,
    Session,
    Usage,
    User,
    now,
)
from schulpilot.exam_models import Exam
from schulpilot.exam_review_models import ExamReview, ExamReviewDraft, ExamReviewPage
from schulpilot.main import app
from schulpilot.providers import Result
from schulpilot.security import digest
from schulpilot.worker import claim
from sqlalchemy import func, select, update
from test_providers import configured

QUESTION = "Berechne 1/4 + 1/4."
TEXT = "Aufgabe 1: Berechne 1/4 + 1/4.\nAlte Antwort: 1/8.\nLehrermarkierung: Nenner bleibt 4.\nPunkte: 0 von 2."
REPORT = {
    "summary": "Ein vorläufiger Lernhinweis zur sichtbaren Arbeit.",
    "uncertainties": [],
    "tasks": [
        {
            "id": "t1",
            "question": QUESTION,
            "original_answer": "1/8",
            "teacher_feedback": "Nenner bleibt 4.",
            "score_label": "0 von 2",
            "ai_proposal": "Vergleiche den Nenner noch einmal mit deiner Heftregel.",
            "uncertainties": [],
            "sources": [{"ref": "p1", "quote": QUESTION}],
        }
    ],
}


@pytest.fixture
def paper(api, household):
    parent, child = household
    configured(parent["families"][0]["id"])
    with DB.begin() as db:
        family = db.get(Family, parent["families"][0]["id"])
        family.call_limit, family.budget_micros = 50, 50_000
        exam = Exam(
            id=uuid.uuid4().hex,
            child_id=child["id"],
            title="Künstliche korrigierte Arbeit",
            purpose="review",
            kind="test",
            subject="Mathematik",
            timezone="Europe/Berlin",
            minutes=15,
            topics=[],
            schedule={"dates": []},
            create_key=uuid.uuid4().hex,
            request_digest="a" * 64,
        )
        page = Material(
            id=uuid.uuid4().hex,
            child_id=child["id"],
            purpose="exam",
            title="Künstliche Arbeitsseite",
            subject="Mathematik",
            topic="Brüche",
            content=TEXT,
            confirmed=True,
            status="confirmed",
        )
        book = Material(
            id=uuid.uuid4().hex,
            child_id=child["id"],
            purpose="notebook",
            title="Künstliche Regel",
            subject="Mathematik",
            topic="Brüche",
            content="Gleichnamige Brüche: Zähler addieren, Nenner beibehalten.",
            confirmed=True,
            status="confirmed",
        )
        db.add_all([exam, page, book])
        db.flush()
        db.add(ExamReviewPage(exam_id=exam.id, material_id=page.id, position=1, upload_revision=1))
        ids = {"exam_id": exam.id, "material_id": page.id, "book_id": book.id, "child_id": child["id"]}
    with TestClient(app, headers=HEADERS) as client:
        login = client.post(
            "/api/auth/login", json={"username": child["username"], "password": "secure-child-pass-123"}
        )
        assert login.status_code == 200
        client.headers["Authorization"] = "Bearer " + login.json()["token"]
        yield {**ids, "client": client, "parent": parent, "path": f"/api/exams/{ids['exam_id']}/review"}


@pytest.fixture
def transport(monkeypatch):
    state = {"calls": [], "output": copy.deepcopy(REPORT), "effect": None}

    def request(config, function, payload):
        assert function == "tutor"
        state["calls"].append(copy.deepcopy(payload))
        if state["effect"]:
            state["effect"]()
        output = (
            state["output"]
            if payload["exam_context"]["action"] == "analyze"
            else {
                "kind": "answer",
                "answer": "Vergleiche deine Überarbeitung mit der sichtbaren Markierung.",
                "sources": [{"ref": "p1", "quote": "Nenner bleibt 4."}],
                "next_question": None,
            }
        )
        return Result(copy.deepcopy(output), 30, 60, 0)

    monkeypatch.setattr(exam_review, "request_provider", request)
    return state


def context(paper):
    result = paper["client"].get(paper["path"])
    assert result.status_code == 200, result.text
    return {key: result.json()[key] for key in ("revision", "context_revision")}


def analyze(paper, key=None):
    response = paper["client"].post(
        paper["path"] + "/analyze", json=context(paper), headers={"Idempotency-Key": key or uuid.uuid4().hex}
    )
    assert response.status_code == 202, response.text
    return response.json()


def finish():
    with DB() as db:
        job_id = claim(db)
    assert job_id
    exam_review.process(job_id)
    return job_id


def ready(paper, transport):
    analyze(paper)
    finish()
    response = paper["client"].get(paper["path"]).json()
    assert response["status"] == "ready", response
    if response["tasks"]:
        paper["task_id"] = response["tasks"][0]["id"]
    return response


def no_learning():
    with DB() as db:
        for model in (Attempt, LearningUnit, Mastery):
            assert db.scalar(select(func.count()).select_from(model)) == 0


def test_false_student_equation_is_reported_without_rewriting_the_saved_analysis(api, paper, transport):
    question = "Kürze 6/8 vollständig."
    answer = r"\(\frac{6}{8}=\frac{2}{4}\) weiter kürzen"
    with DB.begin() as db:
        db.get(Material, paper["material_id"]).content = question + "\n" + answer
    transport["output"]["tasks"][0].update(
        question=question, original_answer=answer, teacher_feedback="", score_label="",
        sources=[{"ref": "p1", "quote": question}],
    )
    result = ready(paper, transport)
    task = result["tasks"][0]
    assert task["original_answer"] == answer
    assert len(task["arithmetic_warnings"]) == 1
    assert "rechnerisch nicht" in task["arithmetic_warnings"][0]["message"]
    assert paper["client"].get(paper["path"]).json()["tasks"][0]["arithmetic_warnings"] == task["arithmetic_warnings"]
    with DB() as db:
        stored = db.scalar(select(ExamReview).where(ExamReview.exam_id == paper["exam_id"]))
        assert stored.report["tasks"][0]["original_answer"] == answer
        assert "arithmetic_warnings" not in stored.report["tasks"][0]
    no_learning()


def test_reading_and_explicit_review_keep_original_roles_without_grade_or_competence(api, paper, transport):
    for _ in range(2):
        assert api.get(paper["path"]).status_code == 200
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 0
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
    with DB.begin() as db:
        db.add(
            SchoolGrade(
                child_id=paper["child_id"],
                subject="Mathematik",
                topic="Privat",
                kind="test",
                scale="grade_1_6",
                value=5.37,
                weight=1,
                assessed_on="2026-10-20",
                note="PRIVATE-GRADE-NOTE",
            )
        )
    output = ready(paper, transport)
    task = output["tasks"][0]
    assert task["original_answer"] == "1/8" and task["teacher_feedback"] == "Nenner bleibt 4."
    assert task["score_label"] == "0 von 2" and task["needs_review"] is True
    assert task["sources"][0]["material_id"] == paper["material_id"]
    submitted = json.dumps(transport["calls"][0])
    assert "PRIVATE-GRADE-NOTE" not in submitted and "5.37" not in submitted and "school_grades" not in submitted
    assert analyze(paper)["status"] == "completed"
    assert len(transport["calls"]) == 1
    parent = api.get(paper["path"]).json()
    assert parent["tasks"] and not parent["turns"] and "draft" not in parent["tasks"][0]
    no_learning()
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(SchoolGrade)) == 1


@pytest.mark.parametrize(
    "field,value",
    [
        ("question", "Erfundene Aufgabe"),
        ("original_answer", "Andere Antwort"),
        ("teacher_feedback", "Erfundenes Lehrerurteil"),
        ("score_label", "Note 1"),
        ("quote", "Nicht in der Quelle"),
        ("quote", "   "),
        ("ref", "p12"),
    ],
)
def test_unquoted_originals_annotations_and_fake_citations_fail_closed(paper, transport, field, value):
    task = transport["output"]["tasks"][0]
    if field in ("quote", "ref"):
        task["sources"][0][field] = value
    else:
        task[field] = value
    analyze(paper)
    finish()
    result = paper["client"].get(paper["path"]).json()
    assert result["status"] == "failed" and not result["tasks"]
    with DB() as db:
        assert db.get(Material, paper["material_id"]).content == TEXT
    no_learning()


@pytest.mark.parametrize("when", ["before", "after"])
@pytest.mark.parametrize("change", ["source", "session", "archive"])
def test_source_session_and_archive_are_rechecked_around_provider(paper, transport, when, change):
    analyze(paper)

    def alter():
        with DB.begin() as db:
            if change == "source":
                db.get(Material, paper["material_id"]).revision += 1
            elif change == "archive":
                db.get(Exam, paper["exam_id"]).archived = True
            else:
                for session in db.scalars(
                    select(Session).where(
                        Session.user_id == select(User.id).where(User.username == "test-child").scalar_subquery()
                    )
                ):
                    session.revoked = True

    if when == "before":
        alter()
    else:
        transport["effect"] = alter
    job_id = finish()
    with DB() as db:
        assert db.get(Job, job_id).status == "failed"
        report = db.scalar(select(ExamReview)).report
        assert not report.get("tasks") and not report.get("summary")
        assert all(batch["status"] == "failed" and not batch["summary"] for batch in report["analysis_batches"])
    assert len(transport["calls"]) == (0 if when == "before" else 1)
    no_learning()


def test_draft_is_child_session_private_cas_bounded_and_help_is_only_ai_opinion(api, paper, transport):
    ready(paper, transport)
    body = {**context(paper), "draft_revision": 0, "text": "Mein neuer Versuch: 2/4"}
    path = paper["path"] + f"/tasks/{paper['task_id']}/draft"
    saved = paper["client"].put(path, json=body)
    assert saved.status_code == 200, saved.text
    assert saved.json()["draft"]["revision"] == 1
    assert paper["client"].put(path, json=body).status_code == 409
    assert api.put(path, json=body).status_code == 403
    assert "draft" not in api.get(paper["path"]).json()["tasks"][0]
    assert paper["client"].get(paper["path"]).json()["tasks"][0]["draft"]["text"] == body["text"]
    response = paper["client"].post(
        paper["path"] + f"/tasks/{paper['task_id']}/help",
        json={**context(paper), "action": "check", "draft": body["text"]},
        headers={"Idempotency-Key": uuid.uuid4().hex},
    )
    assert response.status_code == 202, response.text
    assert response.json()["task_id"] == paper["task_id"]
    finish()
    result = paper["client"].get(paper["path"] + "/turns/" + response.json()["id"]).json()
    assert result["status"] == "ready" and result["assessment"] == "ai_opinion"
    assert result["reply"]["answer"] and result["draft"] == body["text"]
    assert api.get(paper["path"]).json()["turns"] == []
    no_learning()


@pytest.mark.parametrize("dead", ["revoked", "expired", "inactive"])
def test_two_devices_keep_separate_private_drafts_and_dead_sessions_are_pruned(paper, transport, dead):
    ready(paper, transport)
    path = paper["path"] + f"/tasks/{paper['task_id']}/draft"
    body = {**context(paper), "draft_revision": 0, "text": "Gerät eins"}
    assert paper["client"].put(path, json=body).status_code == 200
    with TestClient(app, headers=HEADERS) as second:
        login = second.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"})
        second.headers["Authorization"] = "Bearer " + login.json()["token"]
        assert second.get(paper["path"]).json()["tasks"][0]["draft"] is None
        assert second.put(path, json={**body, "text": "Gerät zwei"}).status_code == 200
        assert paper["client"].get(paper["path"]).json()["tasks"][0]["draft"]["text"] == "Gerät eins"
    with DB.begin() as db:
        drafts = list(db.scalars(select(ExamReviewDraft).order_by(ExamReviewDraft.text)))
        assert len(drafts) == 2
        session = db.get(Session, drafts[0].session_id)
        if dead == "revoked":
            session.revoked = True
        elif dead == "expired":
            session.expires = int(now()) - 1
        else:
            session.seen = int(now()) - 8 * 86400
        db.flush()
        exam_review.purge_expired(db, int(now()) - 365 * 86400)
        assert db.scalar(select(func.count()).select_from(ExamReviewDraft)) == 1


def test_only_confirmed_notebooks_can_supply_followup_ground_truth(paper, transport):
    with DB.begin() as db:
        wrong = Material(
            child_id=paper["child_id"],
            purpose="notebook",
            title="Künstliches Fremdfach",
            subject="Deutsch",
            content="Andere Quelle.",
            confirmed=True,
        )
        blank = Material(
            child_id=paper["child_id"],
            purpose="notebook",
            title="Künstlicher Leertext",
            subject="Mathematik",
            content="   ",
            confirmed=True,
        )
        db.add_all([wrong, blank])
    result = ready(paper, transport)
    assert [source["id"] for source in result["notebook_sources"]] == [paper["book_id"]]
    path = paper["path"] + f"/tasks/{paper['task_id']}/practice"
    body = {**context(paper), "material_ids": [paper["material_id"]]}
    assert paper["client"].post(path, json=body, headers={"Idempotency-Key": uuid.uuid4().hex}).status_code == 409
    response = paper["client"].post(
        path, json={**body, "material_ids": [paper["book_id"]]}, headers={"Idempotency-Key": uuid.uuid4().hex}
    )
    assert response.status_code == 202, response.text
    with DB() as db:
        job = db.get(Job, response.json()["id"])
        assert job.kind == "unit" and job.payload["sources"] == [{"id": paper["book_id"], "revision": 1}]
        exam_review.validate_practice_job(db, job)
        payload = {}
        exam_review.add_practice_context(db, job, payload)
        assert payload["written_review_focus"] == QUESTION
        assert "1/8" not in json.dumps(job.payload)
    no_learning()


def test_source_erasure_cancels_queued_work_and_scrubs_private_report_drafts(paper, transport):
    analyze(paper)
    with DB.begin() as db:
        tutor.purge_source_turns(db, [paper["material_id"]], child_id=paper["child_id"])
        assert db.scalar(select(func.count()).select_from(ExamReview)) == 0
        assert db.scalar(select(Job)).status == "failed"
        assert db.scalar(select(Usage)).cost_micros == 0
    assert not transport["calls"]


def test_upload_is_atomically_attached_and_replay_cannot_move_photo(api, paper):
    with DB.begin() as db:
        exam = db.get(Exam, paper["exam_id"])
        db.execute(__import__("sqlalchemy").delete(ExamReviewPage).where(ExamReviewPage.exam_id == exam.id))
    buffer = io.BytesIO()
    Image.new("RGB", (800, 800), (120, 110, 150)).save(buffer, "PNG")
    route = f"/api/exams/{paper['exam_id']}/pages?revision=1"
    key = uuid.uuid4().hex

    def send():
        return api.post(
            route, files={"file": ("synthetic.png", buffer.getvalue(), "image/png")}, headers={"Idempotency-Key": key}
        )

    response = send()
    assert response.status_code == 201, response.text
    assert response.json()["revision"] == 2 and len(response.json()["pages"]) == 1
    assert send().json()["revision"] == 2
    stale = api.post(
        route,
        files={"file": ("synthetic.png", buffer.getvalue(), "image/png")},
        headers={"Idempotency-Key": uuid.uuid4().hex},
    )
    assert stale.status_code == 409
    with DB() as db:
        links = list(db.scalars(select(ExamReviewPage)))
        assert len(links) == 1 and db.get(Material, links[0].material_id).purpose == "exam"
    no_learning()


@pytest.mark.parametrize("role", ["admin", "foreign", "view", "sibling"])
def test_private_review_role_guards_are_not_bypassed_by_exam_identifier(api, paper, role):
    token = uuid.uuid4().hex
    with DB.begin() as db:
        user = User(
            id=uuid.uuid4().hex,
            username="review-" + role,
            display_name="Künstlicher Zugang",
            password_hash="not-a-login-fixture",
            role="child" if role == "sibling" else "admin" if role == "admin" else "parent",
            verified=True,
        )
        db.add(user)
        db.flush()
        db.add(
            Session(
                user_id=user.id,
                token_hash=digest(token),
                device="synthetic-role-test",
                expires=int(now()) + 3600,
                seen=int(now()),
            )
        )
        if role == "view":
            db.add(Membership(user_id=user.id, family_id=paper["parent"]["families"][0]["id"], permission="view"))
    with TestClient(app, headers={**HEADERS, "Authorization": "Bearer " + token}) as other:
        result = other.get(paper["path"])
        assert result.status_code == (200 if role == "view" else 403 if role == "admin" else 404)
        mutation = other.post(
            paper["path"] + "/analyze", json=context(paper), headers={"Idempotency-Key": uuid.uuid4().hex}
        )
        assert mutation.status_code == (403 if role in ("view", "admin") else 404)
    no_learning()


def test_exam_pages_cannot_become_ordinary_homework_vocabulary_or_unit_truth(api, paper):
    body = {
        "revision": 1,
        "subject": "Mathematik",
        "topic": "Brüche",
        "content": TEXT,
        "homework": [QUESTION],
        "uncertainties_resolved": True,
        "task_decisions": [],
    }
    with DB.begin() as db:
        page = db.get(Material, paper["material_id"])
        page.confirmed, page.status = False, "review"
    preview = api.post(f"/api/materials/{paper['material_id']}/task-preview", json=body)
    assert preview.status_code == 200 and preview.json()["items"] == []
    confirmed = api.put(f"/api/materials/{paper['material_id']}/confirm", json=body)
    assert confirmed.status_code == 200, confirmed.text
    assert confirmed.json()["task_transfer"]["added"] == 0
    request = paper["client"].post(
        f"/api/children/{paper['child_id']}/units",
        json={"material_id": paper["material_id"]},
        headers={"Idempotency-Key": uuid.uuid4().hex},
    )
    assert request.status_code == 409
    request = paper["client"].post(
        f"/api/children/{paper['child_id']}/tutor/questions",
        json={"material_id": paper["material_id"], "question": "Ist meine alte Antwort richtig?"},
        headers={"Idempotency-Key": uuid.uuid4().hex},
    )
    assert request.status_code == 409
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 0
    no_learning()


def test_preparation_exam_can_later_have_written_review_without_changing_its_plan(paper, transport):
    with DB.begin() as db:
        exam = db.get(Exam, paper["exam_id"])
        exam.purpose = "preparation"
    result = ready(paper, transport)
    assert result["tasks"]
    with DB() as db:
        assert db.get(Exam, paper["exam_id"]).purpose == "preparation"
        assert db.get(Exam, paper["exam_id"]).schedule == {"dates": []}


def test_export_excludes_unsubmitted_drafts_and_source_change_rejects_stale_save(paper, transport):
    ready(paper, transport)
    before = context(paper)
    response = paper["client"].put(
        paper["path"] + f"/tasks/{paper['task_id']}/draft",
        json={**before, "draft_revision": 0, "text": "UNSUBMITTED-PRIVATE"},
    )
    assert response.status_code == 200
    with DB() as db:
        exported = exam_review.export_review(db, paper["child_id"])
        assert "exam_review_drafts" not in exported and "UNSUBMITTED-PRIVATE" not in json.dumps(exported)
        assert "session_id" not in json.dumps(exported)
    with DB.begin() as db:
        db.get(Material, paper["material_id"]).revision += 1
    assert (
        paper["client"]
        .put(
            paper["path"] + f"/tasks/{paper['task_id']}/draft",
            json={**before, "draft_revision": 1, "text": "Alter Callback"},
        )
        .status_code
        == 409
    )


def test_failed_report_attachment_does_not_leave_an_orphaned_photo(api, paper, monkeypatch):
    before = set((settings.data_dir / "uploads").glob("*.jpg"))
    with DB() as db:
        material_count = db.scalar(select(func.count()).select_from(Material))
    buffer = io.BytesIO()
    Image.new("RGB", (800, 800), (125, 100, 140)).save(buffer, "PNG")

    def reject(*args, **kwargs):
        raise HTTPException(409, "Künstlich veränderte Arbeit.")

    monkeypatch.setattr(exam_review, "attach_uploaded", reject)
    response = api.post(
        f"/api/exams/{paper['exam_id']}/pages?revision=1",
        files={"file": ("synthetic.png", buffer.getvalue(), "image/png")},
        headers={"Idempotency-Key": uuid.uuid4().hex},
    )
    assert response.status_code == 409
    assert set((settings.data_dir / "uploads").glob("*.jpg")) == before
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Material)) == material_count
        assert db.get(Exam, paper["exam_id"]).revision == 1


def test_source_removed_during_claimed_work_keeps_unknown_cost_reserved(paper, transport):
    job_id = analyze(paper)["id"]
    with DB() as db:
        assert claim(db) == job_id
    with DB.begin() as db:
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        assert usage.status == "reserved" and usage.cost_micros is None
        tutor.purge_source_turns(db, [paper["material_id"]], child_id=paper["child_id"])
        assert db.get(Job, job_id).status == "failed"
        assert usage.status == "reserved" and usage.cost_micros is None
    exam_review.process(job_id)
    assert not transport["calls"]


@pytest.mark.parametrize("status", ["queued", "completed"])
def test_source_erasure_scrubs_original_question_from_practice_jobs(paper, transport, status):
    ready(paper, transport)
    response = paper["client"].post(
        paper["path"] + f"/tasks/{paper['task_id']}/practice",
        json={**context(paper), "material_ids": [paper["book_id"]]},
        headers={"Idempotency-Key": uuid.uuid4().hex},
    )
    assert response.status_code == 202
    with DB.begin() as db:
        job = db.get(Job, response.json()["id"])
        job.status = status
        before = db.scalar(select(Usage).where(Usage.job_id == job.id))
        reservation = before.reserved_micros
        tutor.purge_source_turns(db, [paper["material_id"]], child_id=paper["child_id"])
        assert "exam_review_practice" not in job.payload and QUESTION not in json.dumps(job.payload)
        assert job.status == ("failed" if status == "queued" else "completed")
        assert before.reserved_micros == reservation
        assert db.get(Material, paper["book_id"]).confirmed


def test_exam_vocabulary_routes_cannot_promote_an_old_incorrect_translation(api, paper):
    with DB.begin() as db:
        page = db.get(Material, paper["material_id"])
        page.subject, page.topic, page.content = "Englisch", "Alte Übersetzung", "cat – Hund"
    result = api.get(f"/api/materials/{paper['material_id']}")
    assert result.status_code == 200
    assert result.json()["vocabulary_preview"] is None
    assert result.json()["supports_task_confirmation"] is False
    preview = api.post(
        f"/api/materials/{paper['material_id']}/vocabulary-preview",
        json={"subject": "Englisch", "topic": "Alte Übersetzung", "content": "cat – Hund"},
    )
    assert preview.status_code == 200 and preview.json()["preview"] is None
    response = api.post(
        f"/api/materials/{paper['material_id']}/vocabulary",
        json={"revision": 1, "target_locale": "en-GB", "language_confirmed": True},
    )
    assert response.status_code == 409
    assert api.get(f"/api/materials/{paper['material_id']}/vocabulary").json()["imports"] == []


def test_large_recognized_papers_stay_readable_but_cannot_start_unbounded_analysis(paper):
    with DB.begin() as db:
        db.get(Material, paper["material_id"]).content = "Künstlicher Text " * 1200
        for position in (2, 3):
            page = Material(
                id=uuid.uuid4().hex,
                child_id=paper["child_id"],
                purpose="exam",
                title="Künstliche umfangreiche Seite",
                subject="Mathematik",
                content="Künstlicher Text " * 1200,
                confirmed=True,
                status="confirmed",
            )
            db.add(page)
            db.flush()
            db.add(ExamReviewPage(exam_id=paper["exam_id"], material_id=page.id, position=position, upload_revision=1))
    response = paper["client"].get(paper["path"])
    assert response.status_code == 200, response.text
    value = response.json()
    assert len(value["pages"]) == 3 and value["can_analyze"]
    assert "umfangreich" in value["notice"]
    response = paper["client"].post(
        paper["path"] + "/analyze", json=context(paper), headers={"Idempotency-Key": uuid.uuid4().hex}
    )
    assert response.status_code == 422
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 0


@pytest.mark.parametrize("action", ["draft", "help", "practice"])
def test_child_only_review_mutations_recheck_role_after_waiting_for_child_lock(paper, transport, monkeypatch, action):
    ready(paper, transport)
    with DB() as db:
        jobs_before = db.scalar(select(func.count()).select_from(Job))
    original = exams.lock_child

    def change_role(db, p, child_id, *, write=True):
        db.execute(update(User).where(User.id == p.user.id).values(role="parent"))
        db.add(Membership(user_id=p.user.id, family_id=paper["parent"]["families"][0]["id"], permission="manage"))
        db.flush()
        return original(db, p, child_id, write=write)

    monkeypatch.setattr(exams, "lock_child", change_role)
    path = paper["path"] + f"/tasks/{paper['task_id']}/{action}"
    snapshot = context(paper)
    if action == "draft":
        result = paper["client"].put(
            path, json={**snapshot, "draft_revision": 0, "text": "Keine fremde Elternspeicherung"}
        )
    else:
        body = {
            **snapshot,
            **({"action": "hint", "draft": ""} if action == "help" else {"material_ids": [paper["book_id"]]}),
        }
        result = paper["client"].post(path, json=body, headers={"Idempotency-Key": uuid.uuid4().hex})
    assert result.status_code == 403, result.text
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == jobs_before
        assert db.scalar(select(func.count()).select_from(ExamReviewDraft)) == 0


@pytest.mark.parametrize("action", ["extract", "reprocess"])
def test_exam_photos_only_use_persistent_submit_and_never_create_unlinked_clones(api, paper, action):
    stream = io.BytesIO()
    Image.new("RGB", (800, 800), (110, 100, 150)).save(stream, "PNG")
    uploaded = api.post(
        f"/api/exams/{paper['exam_id']}/pages?revision=1",
        files={"file": ("synthetic.png", stream.getvalue(), "image/png")},
        headers={"Idempotency-Key": uuid.uuid4().hex},
    )
    assert uploaded.status_code == 201, uploaded.text
    page = next(p for p in uploaded.json()["pages"] if p["id"] != paper["material_id"])
    before_files = set((settings.data_dir / "uploads").glob("*.jpg"))
    with DB() as db:
        before_materials = db.scalar(select(func.count()).select_from(Material))
        assert db.get(Material, page["id"]).path
    result = api.post(
        f"/api/materials/{page['id']}/{action}",
        json={"revision": page["revision"]} if action == "reprocess" else None,
        headers={"Idempotency-Key": uuid.uuid4().hex},
    )
    assert result.status_code == 409 and "Fotoabgabe" in result.json()["detail"], result.text
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 0
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
        assert db.scalar(select(func.count()).select_from(Material)) == before_materials
        assert db.get(Exam, paper["exam_id"]).revision == uploaded.json()["revision"]
    assert set((settings.data_dir / "uploads").glob("*.jpg")) == before_files
