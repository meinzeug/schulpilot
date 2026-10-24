"""Synthetic persisted photo batches; no real OCR, providers, or private photos."""

import copy
import json
import uuid
from concurrent.futures import ThreadPoolExecutor

import pytest
from conftest import HEADERS
from fastapi.testclient import TestClient
from schulpilot import exam_review
from schulpilot.db import DB, Child, Family, Job, Material, ProviderConfig, Session, Usage
from schulpilot.exam_models import Exam
from schulpilot.exam_review_models import ExamReviewPage, ExamScanBatch
from schulpilot.main import app
from schulpilot.providers import ProviderError, Result
from schulpilot.worker import claim, process
from sqlalchemy import delete, func, select
from test_exam_reviews import context, no_learning
from test_exam_reviews import paper as paper
from test_school_day import image_bytes


def capture(api, paper, monkeypatch, count=2):
    with DB.begin() as db:
        db.execute(delete(ExamReviewPage).where(ExamReviewPage.exam_id == paper["exam_id"]))
    for _ in range(count):
        revision = api.get(paper["path"]).json()["revision"]
        response = api.post(
            f"/api/exams/{paper['exam_id']}/pages?revision={revision}",
            files={"file": ("synthetic.jpg", image_bytes(), "image/jpeg")},
            headers={"Idempotency-Key": uuid.uuid4().hex},
        )
        assert response.status_code == 201, response.text
    state = {"calls": [], "effect": None, "fail": False}

    def provider(config, function, payload, image_bytes=None, *, synthetic_fixture=False):
        assert function == "extract"
        state["calls"].append(function)
        if state["effect"]:
            state["effect"]()
        if state["fail"]:
            raise ProviderError("Künstlicher Erkennungsfehler.")
        return Result(
            {
                "subject": "Mathematik",
                "topic": "Brüche",
                "content": "Künstliche Aufgabe: 1/4 + 1/4.",
                "uncertainties": ["Die künstliche Markierung bitte prüfen."],
                "homework": [],
            },
            20,
            30,
            0,
        )

    monkeypatch.setattr("schulpilot.worker.request_provider", provider)
    return state


def submit(client, paper, key=None, body=None):
    return client.post(
        f"/api/exams/{paper['exam_id']}/pages/submit",
        json=body or context(paper),
        headers={"Idempotency-Key": key or uuid.uuid4().hex},
    )


def tick():
    exam_review.advance_scan_one()
    with DB() as db:
        job_id = claim(db)
    if job_id:
        process(job_id)
    exam_review.advance_scan_one()
    return job_id


def test_explicit_photo_batch_is_persistent_and_gets_never_reserve(api, paper, monkeypatch):
    state = capture(api, paper, monkeypatch, 3)
    for _ in range(3):
        assert api.get(paper["path"]).json()["scan"]["status"] == "idle"
        exam_review.advance_scan_one()
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 0
    key, body = uuid.uuid4().hex, context(paper)
    response = submit(paper["client"], paper, key, body)
    assert response.status_code == 202, response.text
    assert response.json()["scan"]["status"] == "processing"
    # Browser may disappear here. Durable intent has no charge before worker.
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 0
    assert all(tick() for _ in range(3))
    value = api.get(paper["path"]).json()
    assert value["scan"]["status"] == "needs_review"
    assert value["scan"]["completed_pages"] == 3 and all(not p["confirmed"] for p in value["pages"])
    assert tick() is None and state["calls"] == ["extract"] * 3
    assert submit(paper["client"], paper, key, body).status_code == 202
    assert "session_id" not in json.dumps(value["scan"]) and "user_id" not in json.dumps(value["scan"])
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 3
        assert "session_id" not in json.dumps(exam_review.export_review(db, paper["child_id"]))
    no_learning()


def test_second_page_quota_failure_keeps_first_ocr_and_actual_usage(api, paper, monkeypatch):
    state = capture(api, paper, monkeypatch)
    with DB.begin() as db:
        db.get(Family, paper["parent"]["families"][0]["id"]).call_limit = 1
    assert submit(api, paper).status_code == 202
    assert tick()
    value = api.get(paper["path"]).json()
    assert value["scan"]["status"] == "blocked" and value["scan"]["completed_pages"] == 1
    assert state["calls"] == ["extract"]
    assert tick() is None
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
        assert db.scalar(select(Usage)).status == "completed"


def test_failed_ocr_needs_explicit_retry_and_same_revision_has_two_attempt_limit(api, paper, monkeypatch):
    state = capture(api, paper, monkeypatch, 1)
    state["fail"] = True
    assert submit(api, paper).status_code == 202
    assert tick()
    assert api.get(paper["path"]).json()["scan"]["status"] == "failed"
    assert tick() is None and state["calls"] == ["extract"]
    assert submit(api, paper).status_code == 202
    assert tick()
    assert submit(api, paper).status_code == 202
    assert tick() is None
    value = api.get(paper["path"]).json()
    assert value["scan"]["status"] == "blocked" and "zweimal" in value["scan"]["error"]
    assert state["calls"] == ["extract", "extract"] and value["scan"]["can_submit"] is False


@pytest.mark.parametrize("change", ["session", "source", "provider", "archive", "family"])
@pytest.mark.parametrize("when", ["before", "during"])
def test_scan_rechecks_identity_sources_and_provider_before_and_after_ocr(api, paper, monkeypatch, change, when):
    state = capture(api, paper, monkeypatch, 1)
    assert submit(paper["client"], paper).status_code == 202
    exam_review.advance_scan_one()
    with DB() as db:
        job_id = claim(db)
        job_payload = copy.deepcopy(db.get(Job, job_id).payload)

    def alter():
        with DB.begin() as db:
            batch = db.get(ExamScanBatch, job_payload["exam_scan_id"])
            if change == "session":
                db.get(Session, batch.state["session_id"]).revoked = True
            elif change == "source":
                db.get(Material, job_payload["material_id"]).revision += 1
            elif change == "provider":
                db.get(ProviderConfig, 1).revision += 1
            elif change == "archive":
                db.get(Exam, paper["exam_id"]).archived = True
            else:
                child = db.get(Child, paper["child_id"])
                child.preferences = {**child.preferences, "new_context": True}

    if when == "before":
        alter()
    else:
        state["effect"] = alter
    process(job_id)
    exam_review.advance_scan_one()
    with DB() as db:
        job = db.get(Job, job_id)
        assert job.status == "failed"
        assert db.get(Material, job_payload["material_id"]).status == "uploaded"
    assert len(state["calls"]) == (0 if when == "before" else 1)
    no_learning()


def test_parallel_explicit_submissions_and_ticks_create_exactly_one_page_job(api, paper, monkeypatch):
    state = capture(api, paper, monkeypatch, 1)
    body = context(paper)
    headers = dict(paper["client"].headers)

    def request(_):
        with TestClient(app, headers={**HEADERS, **headers}) as client:
            return submit(client, paper, body=body).status_code

    with ThreadPoolExecutor(max_workers=2) as pool:
        assert list(pool.map(request, range(2))) == [202, 202]
    with ThreadPoolExecutor(max_workers=2) as pool:
        list(pool.map(lambda _: exam_review.advance_scan_one(), range(2)))
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 1
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
    assert state["calls"] == []
