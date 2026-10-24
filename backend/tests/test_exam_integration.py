"""Cross-module release checks; no external provider or real child input."""
import copy
import io
import uuid

import pytest
import test_exam_reviews
import test_exams
from PIL import Image
from schulpilot import families, worker
from schulpilot.db import DB, Attempt, Child, Job, LearningUnit, Material
from schulpilot.exam_models import ExamRound
from schulpilot.exam_review_models import ExamReviewDraft
from schulpilot.main import request_body_limit
from schulpilot.providers import Result
from schulpilot.synthetic import sample_unit
from sqlalchemy import func, select
from test_exam_reviews import context, ready
from test_exams import body, create, prepare
from test_providers import configured

book = test_exams.book
paper = test_exam_reviews.paper
transport = test_exam_reviews.transport


@pytest.mark.parametrize("count", [1, 4, 6, 11, 50])
def test_real_worker_binds_exact_first_round_and_keeps_selected_sources(api, book, monkeypatch, count):
    configured(book["parent"]["families"][0]["id"])
    exam = create(api, book, body(book, count=count))
    response = prepare(book, exam)
    assert response.status_code == 202, response.text
    seen = []

    def request(config, function, payload, image_bytes, **kwargs):
        seen.append(payload)
        data = sample_unit()
        data["topic"] = payload["required_topic"]
        source_questions = data["questions"]
        data["questions"] = []
        for index in range(payload["requested_question_count"]):
            question = copy.deepcopy(source_questions[index % len(source_questions)])
            question["id"] = "q" + str(index)
            question["prompt"] = f"Übung {index + 1}: " + question["prompt"]
            data["questions"].append(question)
        return Result(data, 30, 60, 0)

    monkeypatch.setattr(worker, "request_provider", request)
    with DB() as db:
        job_id = worker.claim(db)
    worker.process(job_id)
    with DB() as db:
        job = db.get(Job, job_id)
        assert job.status == "completed", job.error
        unit = db.get(LearningUnit, job.result["unit_id"])
        first = exam["sessions"][0]["rounds"][0]["question_count"]
        assert len(unit.questions) == first
        assert unit.material_id == book["ref"]["id"]
        assert db.scalar(select(ExamRound).where(ExamRound.job_id == job_id)).unit_id == unit.id
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0
    assert len(seen) == 1 and seen[0]["exam_preparation"] is True
    assert seen[0]["study_block"]["question_count"] == first


def test_family_export_includes_review_but_never_unsubmitted_draft(api, paper, transport):
    report = ready(paper, transport)
    task_id = report["tasks"][0]["id"]
    response = paper["client"].put(paper["path"] + f"/tasks/{task_id}/draft", json={
        **context(paper), "draft_revision": 0, "text": "PRIVATE-UNSUBMITTED-SYNTHETIC"})
    assert response.status_code == 200, response.text
    with DB() as db:
        result = families.export_child(db, db.get(Child, paper["child_id"]))
        assert result["exams"][0]["id"] == paper["exam_id"]
        assert result["exam_reviews"][0]["report"]["tasks"][0]["original_answer"] == "1/8"
        assert "PRIVATE-UNSUBMITTED-SYNTHETIC" not in str(result)
        assert "exam_review_drafts" not in result


def test_child_logout_removes_only_own_review_session_draft(paper, transport):
    report = ready(paper, transport)
    task_id = report["tasks"][0]["id"]
    response = paper["client"].put(paper["path"] + f"/tasks/{task_id}/draft", json={
        **context(paper), "draft_revision": 0, "text": "Temporary synthetic draft"})
    assert response.status_code == 200
    assert paper["client"].post("/api/auth/logout").status_code == 200
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(ExamReviewDraft)) == 0


@pytest.mark.parametrize("chunked", [False, True])
def test_photo_route_accepts_realistic_image_sizes_without_relaxing_json(api, paper, chunked):
    image = Image.effect_noise((900, 900), 70).convert("RGB")
    stream = io.BytesIO()
    image.save(stream, format="PNG")
    raw = stream.getvalue()
    assert len(raw) > 234_106
    path = f"/api/exams/{paper['exam_id']}/pages"
    assert request_body_limit(path) == 12 * 1024 * 1024
    assert request_body_limit(paper["path"] + "/analyze") == 64 * 1024
    headers = {"Idempotency-Key": uuid.uuid4().hex}
    if chunked:
        boundary = "synthetic-exam-boundary"
        def chunks():
            yield f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="test.png"\r\nContent-Type: image/png\r\n\r\n'.encode()
            for offset in range(0, len(raw), 16_384):
                yield raw[offset:offset + 16_384]
            yield f'\r\n--{boundary}--\r\n'.encode()
        headers["Content-Type"] = f"multipart/form-data; boundary={boundary}"
        result = api.post(path + "?revision=1", content=chunks(), headers=headers)
    else:
        result = api.post(path + "?revision=1", files={"file": ("test.png", raw)}, headers=headers)
    assert result.status_code == 201, result.text
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 0
        assert len(list(db.scalars(select(Material).where(Material.purpose == "exam")))) == 2


def test_photo_route_actual_chunks_remain_bounded(api, paper):
    path = f"/api/exams/{paper['exam_id']}/pages?revision=1"
    def chunks():
        yield b'--boundary\r\nContent-Disposition: form-data; name="file"; filename="test.png"\r\n\r\n'
        for _ in range(13):
            yield b"x" * (1024 * 1024)
        yield b'\r\n--boundary--\r\n'
    result = api.post(path, content=chunks(), headers={
        "Idempotency-Key": uuid.uuid4().hex, "Content-Type": "multipart/form-data; boundary=boundary"})
    assert result.status_code == 413
    assert "x" * 100 not in result.text


@pytest.mark.parametrize("confirmed", [False, True])
def test_paper_pages_never_enter_hefte_today_or_notebook_bulk_filters(api, paper, confirmed):
    from schulpilot.db import Session, User
    from schulpilot.material_actions import DeletePreview, selection_rows
    from schulpilot.security import Principal

    with DB.begin() as db:
        db.get(Material, paper["material_id"]).confirmed = confirmed
    child_id = paper["child_id"]
    listed = api.get(f"/api/children/{child_id}/materials").json()
    assert listed["total"] == 1
    assert [row["id"] for row in listed["items"]] == [paper["book_id"]]
    subjects = api.get(f"/api/children/{child_id}/subjects").json()
    assert subjects["unassigned_count"] + sum(row["page_count"] for row in subjects["items"]) == 1
    for compact in (False, True):
        overview = api.get(f"/api/children/{child_id}/overview?compact={str(compact).lower()}").json()
        assert paper["material_id"] not in {row["id"] for row in overview["materials"]}
        assert paper["material_id"] not in {row["id"] for row in overview["plan"].get("voluntary", [])}
        if compact:
            assert overview["material_count"] == 1
    with DB() as db:
        child = db.get(Child, child_id)
        parent = db.get(User, paper["parent"]["id"])
        session = db.scalar(select(Session).where(Session.user_id == parent.id, Session.revoked.is_(False)))
        rows = selection_rows(db, Principal(parent, session), child, DeletePreview(all_matching=True))
        assert [row.id for row in rows] == [paper["book_id"]]
        explicit = selection_rows(db, Principal(parent, session), child, DeletePreview(ids=[paper["material_id"]]))
        assert explicit[0].id == paper["material_id"]


def test_exam_originals_cannot_become_vocabulary_sources_via_shared_import(api, paper):
    from fastapi import HTTPException
    from schulpilot.vocabulary import current_sources

    result = api.post(f"/api/children/{paper['child_id']}/vocabulary/imports", json={
        "title": "Synthetic source boundary", "target_locale": "en-GB", "language_confirmed": True, "material_id": paper["material_id"]
    }, headers={"Idempotency-Key": uuid.uuid4().hex})
    assert result.status_code == 409, result.text
    with DB() as db:
        with pytest.raises(HTTPException) as error:
            current_sources(db, paper["child_id"], [{"id": paper["material_id"], "revision": 1}])
        assert error.value.status_code == 409
