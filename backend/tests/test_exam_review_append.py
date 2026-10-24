"""Further explicit bounded extracts preserve saved work; synthetic mocked transport only."""

import copy
import re
import uuid

import pytest
from schulpilot import exam_review
from schulpilot.db import DB, Job, Material, Usage
from schulpilot.exam_review_models import ExamReview, ExamReviewPage
from schulpilot.providers import ProviderError
from sqlalchemy import func, select
from test_exam_reviews import REPORT, context, finish, no_learning, ready
from test_exam_reviews import paper as paper
from test_exam_reviews import transport as transport

SECOND = "Berechne 2/4 + 1/4."
THIRD = "Berechne 3/4 + 1/4."


def start(paper, transport):
    with DB.begin() as db:
        db.get(Material, paper["material_id"]).content += "\nAufgabe 2: " + SECOND + "\nAufgabe 3: " + THIRD
    return ready(paper, transport)


def request(paper, key=None, pages=None):
    return paper["client"].post(
        paper["path"] + "/analyze",
        json={
            **context(paper),
            "append": True,
            "page_ids": pages or [paper["material_id"]],
        },
        headers={"Idempotency-Key": key or uuid.uuid4().hex},
    )


def second_report(transport):
    transport["output"] = copy.deepcopy(REPORT)
    transport["output"]["tasks"][0]["question"] = SECOND
    transport["output"]["tasks"][0]["sources"][0]["quote"] = SECOND


def test_append_has_stable_server_ids_and_preserves_drafts_turns_and_prior_receipt(paper, transport):
    before = start(paper, transport)
    first_task = before["tasks"][0]
    assert re.fullmatch(r"[a-f0-9]{32}", first_task["id"])
    path = paper["path"] + f"/tasks/{first_task['id']}"
    draft = {**context(paper), "draft_revision": 0, "text": "Mein eigener gespeicherter Versuch."}
    assert paper["client"].put(path + "/draft", json=draft).status_code == 200
    response = paper["client"].post(
        path + "/help",
        json={**context(paper), "action": "hint", "draft": draft["text"]},
        headers={"Idempotency-Key": uuid.uuid4().hex},
    )
    assert response.status_code == 202
    finish()
    before = paper["client"].get(paper["path"]).json()
    with DB() as db:
        receipt = db.scalar(select(ExamReview)).job_id
    second_report(transport)
    queued = request(paper)
    assert queued.status_code == 202, queued.text
    pending = paper["client"].get(paper["path"]).json()
    assert pending["status"] == "ready" and pending["tasks"] == before["tasks"]
    assert pending["analysis_batch"]["status"] == "queued" and not pending["can_analyze_more"]
    assert pending["turns"] == before["turns"]
    with DB() as db:
        assert db.scalar(select(ExamReview)).job_id == receipt
    finish()
    after = paper["client"].get(paper["path"]).json()
    assert after["tasks"][0] == before["tasks"][0] and len(after["tasks"]) == 2
    assert after["tasks"][1]["question"] == SECOND and re.fullmatch(r"[a-f0-9]{32}", after["tasks"][1]["id"])
    assert after["tasks"][0]["id"] != after["tasks"][1]["id"]
    assert after["turns"] == before["turns"] and after["analysis_batch"]["added_tasks"] == 1
    assert "KI-Auszug" in after["summary"] and "keine vollständige" in after["summary"]
    with DB() as db:
        assert db.scalar(select(ExamReview)).job_id == queued.json()["id"]
    no_learning()


@pytest.mark.parametrize("failure", ["duplicate", "unquoted", "empty_claim"])
def test_failed_append_preserves_ready_corrections_and_separate_error(paper, transport, failure, monkeypatch):
    before = start(paper, transport)
    with DB() as db:
        receipt = db.scalar(select(ExamReview)).job_id
    if failure == "duplicate":
        # Simulate a context cap omitting all old question hints. The actual
        # persistence validator must still reject duplicates against ALL tasks.
        original = exam_review.authority

        def capped(db, job):
            row, turn, payload, refs = original(db, job)
            payload["exam_context"]["previous_questions"] = []
            return row, turn, payload, refs

        monkeypatch.setattr(exam_review, "authority", capped)
    elif failure == "unquoted":
        second_report(transport)
        transport["output"]["tasks"][0]["sources"][0]["quote"] = "Erfundener Beleg"
    else:
        transport["output"] = {"summary": "Fertig", "tasks": [], "uncertainties": []}
    queued = request(paper)
    assert queued.status_code == 202
    finish()
    after = paper["client"].get(paper["path"]).json()
    assert after["status"] == "ready" and after["tasks"] == before["tasks"]
    assert after["summary"] == before["summary"] and after["error"] is None
    assert after["analysis_batch"]["status"] == "failed" and after["analysis_batch"]["error"]
    with DB() as db:
        assert db.get(Job, queued.json()["id"]).status == "failed"
        assert db.scalar(select(ExamReview)).job_id == receipt
    no_learning()


def test_append_replay_two_attempts_and_twelve_batch_caps_do_not_create_extra_calls(paper, transport):
    start(paper, transport)
    second_report(transport)
    key = uuid.uuid4().hex
    first = request(paper, key)
    assert first.status_code == 202
    assert request(paper, key).json()["id"] == first.json()["id"]
    finish()
    # Successful extracts advance the server-bound exclusion window. The same
    # physical photo may therefore yield a third distinct group of tasks.
    transport["output"]["tasks"][0]["question"] = THIRD
    transport["output"]["tasks"][0]["sources"][0]["quote"] = THIRD
    assert request(paper).status_code == 202
    finish()
    value = paper["client"].get(paper["path"]).json()
    assert len(value["tasks"]) == 3 and value["analysis_batch"]["status"] == "ready"
    assert value["can_analyze_more"]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 3
        assert db.scalar(select(func.count()).select_from(Usage)) == 3
    with DB.begin() as db:
        row = db.scalar(select(ExamReview))
        report = copy.deepcopy(row.report)
        report["analysis_batches"] += [
            {"id": uuid.uuid4().hex, "page_ids": [], "status": "failed", "error": "Künstlicher begrenzter Altversuch"}
            for _ in range(9)
        ]
        row.report = report
    assert request(paper).status_code == 409
    assert not paper["client"].get(paper["path"]).json()["can_analyze_more"]
    assert len(transport["calls"]) == 3


def test_selected_excerpt_never_sends_an_unselected_page_and_partial_task_help_remains_usable(paper, transport):
    with DB.begin() as db:
        page = Material(
            id=uuid.uuid4().hex,
            child_id=paper["child_id"],
            purpose="exam",
            title="Künstliche noch unklare Seite",
            subject="Mathematik",
            content="UNSELECTED-PRIVATE-PAGE",
            confirmed=False,
            status="unreadable",
        )
        db.add(page)
        db.flush()
        db.add(ExamReviewPage(exam_id=paper["exam_id"], material_id=page.id, position=2, upload_revision=1))
    response = paper["client"].post(
        paper["path"] + "/analyze",
        json={**context(paper), "page_ids": [paper["material_id"]]},
        headers={"Idempotency-Key": uuid.uuid4().hex},
    )
    assert response.status_code == 202, response.text
    finish()
    assert len(transport["calls"][0]["sources"]) == 1
    assert "UNSELECTED-PRIVATE-PAGE" not in str(transport["calls"][0])
    value = paper["client"].get(paper["path"]).json()
    task_id = value["tasks"][0]["id"]
    response = paper["client"].put(
        paper["path"] + f"/tasks/{task_id}/draft",
        json={**context(paper), "draft_revision": 0, "text": "Eigener Entwurf"},
    )
    assert response.status_code == 200
    practice = paper["client"].post(
        paper["path"] + f"/tasks/{task_id}/practice",
        json={**context(paper), "material_ids": [paper["book_id"]]},
        headers={"Idempotency-Key": uuid.uuid4().hex},
    )
    assert practice.status_code == 202
    with DB() as db:
        exam_review.validate_practice_job(db, db.get(Job, practice.json()["id"]))


def test_append_source_change_after_inference_discards_only_new_batch(paper, transport):
    before = start(paper, transport)
    second_report(transport)

    def alter():
        with DB.begin() as db:
            db.get(Material, paper["material_id"]).revision += 1

    transport["effect"] = alter
    queued = request(paper)
    assert queued.status_code == 202
    finish()
    with DB() as db:
        row = db.scalar(select(ExamReview))
        assert row.status == "ready" and row.report["tasks"][0]["id"] == before["tasks"][0]["id"]
        assert len(row.report["tasks"]) == 1 and row.report["analysis_batches"][-1]["status"] == "failed"
        assert db.get(Job, queued.json()["id"]).status == "failed"
    # Current projection still prevents stale source content from being shown.
    assert paper["client"].get(paper["path"]).json()["tasks"] == []


def test_model_exclusion_hint_is_bounded_but_persistence_compares_every_previous_question():
    class Review:
        context_revision = "a" * 64
        report = {
            "tasks": [{"question": f"Question {index}"} for index in range(80)],
            "analysis_batches": [{"id": "batch"}],
        }

    class Work:
        id = "job"
        payload = {"analysis_batch_id": "batch"}

    review = Review()
    assert len(exam_review.previous_questions(review)) == 32
    assert "Question 79" not in exam_review.previous_questions(review)
    with pytest.raises(ProviderError, match="wiederholt"):
        exam_review.merge_report(
            review, Work(), {"tasks": [{"question": "Question 79"}], "summary": "x", "uncertainties": []}
        )


@pytest.mark.parametrize("first,second", [("CO", "Co"), ("X", "x")])
def test_literal_original_questions_keep_case_sensitive_science_symbols(paper, transport, first, second):
    q1, q2 = f"Was bedeutet {first}?", f"Was bedeutet {second}?"
    with DB.begin() as db:
        db.get(Material, paper["material_id"]).content += "\n" + q1 + "\n" + q2
    transport["output"]["tasks"][0]["question"] = q1
    transport["output"]["tasks"][0]["sources"][0]["quote"] = q1
    before = ready(paper, transport)
    transport["output"]["tasks"][0]["question"] = q2
    transport["output"]["tasks"][0]["sources"][0]["quote"] = q2
    assert request(paper).status_code == 202
    finish()
    after = paper["client"].get(paper["path"]).json()
    assert [task["question"] for task in after["tasks"]] == [q1, q2]
    assert after["tasks"][0]["id"] == before["tasks"][0]["id"]


def test_two_failed_attempts_for_the_same_exclusion_window_require_a_new_scope(paper, transport):
    before = start(paper, transport)
    for _ in range(2):
        assert request(paper).status_code == 202
        finish()  # Unchanged model output repeats the old task and is rejected.
        after = paper["client"].get(paper["path"]).json()
        assert after["tasks"] == before["tasks"] and after["analysis_batch"]["status"] == "failed"
    assert request(paper).status_code == 409
    value = paper["client"].get(paper["path"]).json()
    assert not value["can_analyze_more"] and value["status"] == "ready"
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 3
        assert db.scalar(select(func.count()).select_from(Usage)) == 3
    assert len(transport["calls"]) == 3
