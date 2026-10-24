"""Current-page binding; artificial families and a mocked existing provider only."""

import uuid

import pytest
from schulpilot.db import DB, Child, Material, SchulbuddyTurn
from schulpilot.exam_models import Exam
from schulpilot.exam_review import source_context
from schulpilot.exam_review_models import ExamReview, ExamReviewPage
from schulpilot.schulbuddy import protocol_fields
from schulpilot.schulbuddy_schemas import SYSTEM, BuddyQuestion, BuddyScope
from test_schulbuddy import book as original_book
from test_schulbuddy import counts, finish
from test_schulbuddy import transport as original_transport


@pytest.fixture
def book(api, household, monkeypatch):
    yield from original_book.__wrapped__(api, household, monkeypatch)


@pytest.fixture
def transport(monkeypatch):
    return original_transport.__wrapped__(monkeypatch)


def make_exam(api, book):
    with DB() as db:
        material = db.get(Material, book["material_id"])
        body = {"title": "Künstliche Lernkontrolle", "subject": material.subject, "kind": "test",
                "topics": [{"id": "topic", "label": "Bestätigter Stoff", "question_count": 6,
                            "material_refs": [{"id": material.id, "revision": material.revision}]}],
                "schedule": {"dates": ["2027-01-20"]}}
    result = api.post(f"/api/children/{book['child']['id']}/exams", json=body,
                      headers={"Idempotency-Key": uuid.uuid4().hex})
    assert result.status_code == 201, result.text
    return result.json()


def request(book, exam, **extra):
    return book["client"].post("/api/schulbuddy/questions", json={"page_kind": "exams", "exam_id": exam["id"],
        "exam_tab": "prepare", "question": "Erkläre mir den nächsten Schritt.", **extra},
        headers={"Idempotency-Key": uuid.uuid4().hex})


def paper(book, exam):
    with DB.begin() as db:
        value = db.get(Exam, exam["id"])
        material = Material(child_id=value.child_id, purpose="exam", title="Künstliche geschriebene Arbeit",
            subject=value.subject, topic="Original", confirmed=True, status="confirmed",
            content="Was ist die Sonne? Erde. Bezeichnung prüfen. 0/1 Punkte")
        db.add(material)
        db.flush()
        db.add(ExamReviewPage(exam_id=value.id, material_id=material.id, position=1, upload_revision=value.revision))
        db.flush()
        child = db.get(Child, value.child_id)
        signature, refs, _ = source_context(db, value, child)
        db.add(ExamReview(exam_id=value.id, child_id=value.child_id, status="ready", context_revision=signature,
            source_revisions=refs, report={"summary": "Künstliche Quellenprüfung", "uncertainties": [], "tasks": [{
                "id": "task", "question": "Was ist die Sonne?", "original_answer": "Erde.",
                "teacher_feedback": "Bezeichnung prüfen.", "score_label": "0/1 Punkte", "ai_proposal": "Ungeprüfter Vorschlag",
                "draft": "DARF NICHT IN DEN KONTEXT", "uncertainties": [],
                "sources": [{"ref": "p1", "quote": "Was ist die Sonne?", "material_id": material.id}]}]}))
        return material.id


def test_additive_exam_fields_leave_existing_protocol_history_and_idempotency_unchanged():
    scope = BuddyScope(page_kind="learn", unit_id="a" * 32)
    assert protocol_fields(scope) == {"page_kind": "learn", "child_id": None, "unit_id": "a" * 32,
        "material_id": None, "day_id": None, "question_id": None}
    value = BuddyQuestion(page_kind="learn", unit_id="a" * 32, question="Eigene Frage")
    assert protocol_fields(value) == {**protocol_fields(scope), "question": "Eigene Frage", "reply_to": None}


def test_exam_current_context_is_read_only_and_does_not_reserve(api, book, transport):
    exam = make_exam(api, book)
    before = counts()
    response = book["client"].get("/api/schulbuddy/context", params={"page_kind": "exams", "exam_id": exam["id"],
        "exam_session_id": exam["sessions"][0]["id"], "exam_tab": "prepare"})
    assert response.status_code == 200, response.text
    assert "Lernkontrolle" in response.json()["label"]
    assert counts() == before and transport["calls"] == []


def test_explicit_exam_help_uses_confirmed_notebook_and_bound_session(api, book, transport):
    exam = make_exam(api, book)
    response = request(book, exam, exam_session_id=exam["sessions"][0]["id"])
    assert response.status_code == 202, response.text
    finish()
    payload = transport["calls"][0]
    assert payload["exam"]["session"]["date"] == "2027-01-20"
    assert payload["exam"]["topics"][0]["question_count"] == 6
    with DB() as db:
        assert payload["sources"][0]["content"] == db.get(Material, book["material_id"]).content
    assert "answer" not in payload["exam"]


def test_exam_and_session_from_different_plans_fail_closed(api, book, transport):
    first, second = make_exam(api, book), make_exam(api, book)
    before = counts()
    response = request(book, first, exam_session_id=second["sessions"][0]["id"])
    assert response.status_code == 404
    assert counts() == before and transport["calls"] == []


def test_exam_context_rejects_claimed_other_child(api, book, transport):
    exam = make_exam(api, book)
    response = request(book, exam, child_id="f" * 32)
    assert response.status_code == 404 and transport["calls"] == []


def test_exam_change_before_dispatch_prevents_provider_call(api, book, transport):
    exam = make_exam(api, book)
    response = request(book, exam)
    assert response.status_code == 202, response.text
    with DB.begin() as db:
        db.get(Exam, exam["id"]).revision += 1
    finish()
    assert transport["calls"] == []
    with DB() as db:
        turn = db.get(SchulbuddyTurn, response.json()["id"])
        assert turn.status == "failed" and not turn.reply


def test_exam_change_during_provider_discards_old_answer(api, book, transport):
    exam = make_exam(api, book)
    def change():
        with DB.begin() as db:
            db.get(Exam, exam["id"]).revision += 1
    transport["effect"] = change
    response = request(book, exam)
    assert response.status_code == 202, response.text
    finish()
    with DB() as db:
        turn = db.get(SchulbuddyTurn, response.json()["id"])
        assert turn.status == "failed" and not turn.reply
    assert len(transport["calls"]) == 1


def test_written_paper_separates_original_error_and_teacher_annotation(api, book, transport):
    exam = make_exam(api, book)
    material_id = paper(book, exam)
    transport["output"] = {"answer": "Prüfe die Bezeichnung anhand deiner bestätigten Heftgrundlagen.",
        "sources": [{"ref": "p1", "quote": "Was ist die Sonne?"}], "next_question": None, "starters": []}
    response = request(book, exam, exam_tab="review", review_task_id="task")
    assert response.status_code == 202, response.text
    finish()
    payload = transport["calls"][0]
    assert payload["exam_review"]["original_answer"] == "Erde."
    assert payload["exam_review"]["teacher_feedback"] == "Bezeichnung prüfen."
    assert "ai_proposal" not in payload["exam_review"] and "draft" not in payload["exam_review"]
    assert payload["sources"][0]["evidence_kind"] == "written_work_original"
    assert payload["sources"][0]["authoritative_solution"] is False
    assert "KEINE fachlich bestätigten Lösungen" in SYSTEM
    with DB() as db:
        assert db.get(SchulbuddyTurn, response.json()["id"]).source_revisions[0]["id"] == material_id


def test_unconfirmed_visible_page_offers_review_guidance_without_forwarding_ocr(api, book, transport):
    with DB.begin() as db:
        material = db.get(Material, book["material_id"])
        material.confirmed = False
        material.content = "UNGEPRÜFTER TEXT DARF NICHT VERSENDET WERDEN"
    response = book["client"].get("/api/schulbuddy/context", params={"page_kind": "notebooks", "material_id": book["material_id"]})
    assert response.status_code == 200
    assert any("prüfe und bestätige" in starter for starter in response.json()["starters"])
    transport["output"] = {"answer": "Prüfe zuerst den erkannten Text und bestätige die Seite.", "sources": [], "starters": [], "next_question": None}
    response = book["client"].post("/api/schulbuddy/questions", json={"page_kind": "notebooks", "material_id": book["material_id"],
        "question": "Wie prüfe ich diese Seite?"}, headers={"Idempotency-Key": uuid.uuid4().hex})
    assert response.status_code == 202, response.text
    finish()
    payload = transport["calls"][0]
    assert payload["sources"] == [] and payload["source_review"]["confirmation_required"] is True
    assert "UNGEPRÜFTER" not in str(payload)
