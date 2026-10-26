"""Invented annotated sources and mocked chat; no actual child/provider access."""

import copy

import pytest
from schulpilot import schulbuddy
from schulpilot.db import DB, Attempt, Job, Material, SchulbuddyTurn
from schulpilot.schulbuddy_schemas import SYSTEM
from schulpilot.source_lineage import learning_source
from sqlalchemy import func, select
from test_schulbuddy import ask, counts, finish
from test_schulbuddy import book as book_fixture
from test_schulbuddy import transport as transport_fixture


@pytest.fixture
def book(api, household, monkeypatch):
    yield from book_fixture.__wrapped__(api, household, monkeypatch)


@pytest.fixture
def transport(monkeypatch):
    return transport_fixture.__wrapped__(monkeypatch)


def marked(book, *, wrong=False, partial=False):
    text = "1 + 1 = 3" if wrong else "Die Sonne ist ein Stern."
    with DB.begin() as db:
        material = db.get(Material, book["material_id"])
        material.content = text
        material.source_blocks = [{"kind": "paragraph", "text": text, "literal_role": "example",
            "annotations": [{"kind": "correction", "quote": text, "color": "purple", "author": "unknown"}],
            "reading_uncertainties": ["Das letzte Wort ist nicht sicher lesbar."] if partial else []}]
        material.uncertainties = ["Das letzte Wort ist nicht sicher lesbar."] if partial else []
        material.legibility = "partial" if partial else "readable"
    return text


def submit(book, **kwargs):
    return ask(book, unit_id=None, page_kind="notebooks", material_id=book["material_id"],
        question="Erkläre mir den Inhalt dieser Seite.", **kwargs)


def test_whole_marked_page_is_readable_in_chat_without_changing_grading_sources(api, book, transport):
    text = marked(book)
    with DB() as db:
        before = learning_source(db, db.get(Material, book["material_id"]))
        assert before["content"] == "" and before["factual_status"] == "blocked"
    before_counts = counts()
    context = book["client"].get("/api/schulbuddy/context", params={"page_kind": "notebooks", "material_id": book["material_id"]})
    assert context.status_code == 200 and counts() == before_counts
    assert "Erklär mir den Inhalt der Seite" in context.json()["starters"]
    assert submit(book).status_code == 202
    finish()
    payload = transport["calls"][0]
    source = payload["sources"][0]
    assert source["content"] == text and source["evidence_kind"] == "notebook_literal_reading"
    assert source["authoritative_solution"] is False
    assert source["literal_blocks"][0]["annotations"][0]["color"] == "purple"
    assert source["learning_exclusions"][0]["reason"] == "visible_annotation"
    assert payload["source_view"]["provider_has_photo"] is False and "source_review" not in payload
    with DB() as db:
        assert learning_source(db, db.get(Material, book["material_id"])) == before
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0


@pytest.mark.parametrize("wrong,partial", [(True, False), (False, True), (True, True)])
def test_literal_error_and_uncertainty_travel_unchanged_without_becoming_a_solution(api, book, transport, wrong, partial):
    text = marked(book, wrong=wrong, partial=partial)
    transport["output"] = {"answer": "Ich erkläre den gespeicherten Wortlaut als ungeprüfte Hilfe.",
        "next_question": None, "sources": [{"ref": "p1", "quote": text}], "starters": []}
    assert submit(book).status_code == 202
    finish()
    source = transport["calls"][0]["sources"][0]
    assert source["content"] == text and source["authoritative_solution"] is False
    if partial:
        assert source["uncertainties"] and source["literal_blocks"][0]["reading_uncertainties"]
    with DB() as db:
        assert learning_source(db, db.get(Material, book["material_id"]))["content"] == ""
        turn = db.scalar(select(SchulbuddyTurn).order_by(SchulbuddyTurn.created.desc()))
        assert turn.status == "ready" and schulbuddy.source_changed(db, turn) is False


def test_parent_page_reading_keeps_the_same_literal_boundary(api, book, transport):
    marked(book)
    assert submit(book, client=api).status_code == 202
    finish()
    assert transport["calls"][0]["role"] == "parent"
    assert transport["calls"][0]["sources"][0]["evidence_kind"] == "notebook_literal_reading"


def test_mark_only_change_during_dispatch_rejects_late_answer_without_editing_source(api, book, transport):
    marked(book)
    def changed():
        with DB.begin() as db:
            page = db.get(Material, book["material_id"])
            blocks = copy.deepcopy(page.source_blocks)
            blocks[0]["annotations"][0]["color"] = "red"
            page.source_blocks = blocks
    transport["effect"] = changed
    submitted = submit(book)
    assert submitted.status_code == 202
    job_id = finish()
    with DB() as db:
        assert db.get(Job, job_id).status == "failed"
        assert db.get(SchulbuddyTurn, submitted.json()["id"]).reply is None
        assert db.get(Material, book["material_id"]).source_blocks[0]["annotations"][0]["color"] == "red"


def test_old_literal_quote_is_marked_after_a_source_revision_changes(api, book, transport):
    marked(book)
    submitted = submit(book)
    assert submitted.status_code == 202
    finish()
    with DB.begin() as db:
        turn = db.get(SchulbuddyTurn, submitted.json()["id"])
        assert not schulbuddy.source_changed(db, turn)
        db.get(Material, book["material_id"]).revision += 1
        db.flush()
        assert schulbuddy.source_changed(db, turn)


def test_combined_material_and_day_context_keeps_filtered_sources(api, book, transport):
    marked(book)
    transport["output"]["sources"] = []
    assert submit(book, day_id=book["day_id"]).status_code == 202
    finish()
    assert transport["calls"][0]["sources"] == []
    assert transport["calls"][0]["source_review"]["confirmation_required"]
    with DB() as db:
        turn = db.scalar(select(SchulbuddyTurn))
        assert turn.status == "ready" and turn.source_revisions == []
        assert not schulbuddy.source_changed(db, turn)


def test_saved_literal_reply_becomes_stale_after_annotation_only_change(api, book, transport):
    marked(book)
    submitted = submit(book)
    assert submitted.status_code == 202
    finish()
    with DB.begin() as db:
        turn = db.get(SchulbuddyTurn, submitted.json()["id"])
        assert turn.source_revisions[0]["reading_fingerprint"]
        assert not schulbuddy.source_changed(db, turn)
        page = db.get(Material, book["material_id"])
        old_revision = page.revision
        blocks = copy.deepcopy(page.source_blocks)
        blocks[0]["annotations"][0]["color"] = "red"
        page.source_blocks = blocks
        db.flush()
        assert page.revision == old_revision and schulbuddy.source_changed(db, turn)
    response = submit(book, reply_to=submitted.json()["id"])
    assert response.status_code == 409
    assert len(transport["calls"]) == 1


def test_prompt_separates_reading_marks_from_visual_sight_and_grading():
    assert "notebook_literal_reading" in SYSTEM
    assert "ohne die Aufgabenfreigabe aufzuheben" in SYSTEM
    assert "keine Bildpixel" in SYSTEM
    assert "aus annotations" in SYSTEM
