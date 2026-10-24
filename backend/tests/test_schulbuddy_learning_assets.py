"""Owned synthetic exploration, real chat routes and queue; no external provider."""
import uuid

import pytest
from pydantic import ValidationError
from schulpilot.catalog_models import CatalogSnapshot, CatalogTopic
from schulpilot.db import DB, Child, SchulbuddyTurn, Subject
from schulpilot.learning_asset_models import LearningAssetBuild, LearningAssetInstance
from schulpilot.learning_assets import checked_output, public_spec
from schulpilot.schulbuddy import protocol_fields
from schulpilot.schulbuddy_schemas import SYSTEM, BuddyScope
from schulpilot.visual_reference_models import VisualReference
from schulpilot.visual_references import digest
from sqlalchemy import select
from test_learning_assets import output
from test_schulbuddy import book as original_book
from test_schulbuddy import counts, finish
from test_schulbuddy import operator as original_operator
from test_schulbuddy import transport as original_transport


@pytest.fixture
def book(api, household, monkeypatch):
    yield from original_book.__wrapped__(api, household, monkeypatch)


@pytest.fixture
def transport(monkeypatch):
    return original_transport.__wrapped__(monkeypatch)


@pytest.fixture
def operator():
    yield from original_operator.__wrapped__()


@pytest.fixture
def exploration(book):
    with DB.begin() as db:
        subject = db.scalar(select(Subject).where(Subject.title == "Mathematik", Subject.owner_family_id.is_(None)))
        db.add(CatalogSnapshot(id="buddy-public", provider="test", schema_version="1", metadata_json={}, report={}))
        db.flush()
        db.add(CatalogTopic(id="buddy-topic", subject_id=subject.id, title="Künstliches öffentliches Thema",
                            entry_url="https://example.org/public", search_text="public", empty_curated=True,
                            data={}, snapshot_id="buddy-public"))
        db.flush()
        spec = public_spec(db, {"subject": "Mathematik", "recipe_id": "general.source_relation.phases", "recipe_version": 1,
                               "catalog_topic_id": "buddy-topic", "level_band": "lower_secondary"})
        asset = checked_output(db, output(), spec)
        key = digest(spec)
        recipe = {"id": "generated." + key, "version": 1, "subjects": ["Mathematik"], "kind": "scene",
                  "terms": [], "scope": "exploration_only", "technical_status": "validated", "factual_status": "unassessed",
                  "asset": asset, "public_spec": spec}
        reference = VisualReference(id=recipe["id"], version=1, recipe=recipe, digest=digest(recipe))
        db.add(reference)
        db.flush()
        db.add(LearningAssetBuild(build_key=key, specification=spec, status="ready", technical_status="validated",
            factual_status="unassessed", reference_id=reference.id, reference_version=1, reference_digest=reference.digest))
        db.flush()
        instance = LearningAssetInstance(child_id=book["child"]["id"], user_id=db.get(Child, book["child"]["id"]).user_id,
            build_key=key, request_key=uuid.uuid4().hex, request_digest=digest(spec))
        db.add(instance)
        db.flush()
        return instance.id, reference.id


def query(exploration):
    return {"page_kind": "learn", "learning_asset_instance_id": exploration[0]}


def ask_asset(book, exploration, **extra):
    return book["client"].post("/api/schulbuddy/questions", json={**query(exploration), "question": "Erkläre mir diese Grafik.", **extra},
        headers={"Idempotency-Key": uuid.uuid4().hex})


def test_old_protocol_keys_remain_identical_and_mixed_or_phase_claims_are_rejected():
    assert protocol_fields(BuddyScope(page_kind="learn")) == {
        "page_kind": "learn", "child_id": None, "unit_id": None, "material_id": None, "day_id": None, "question_id": None}
    for extra in ({"unit_id": "a" * 32}, {"material_id": "a" * 32}, {"day_id": "a" * 32},
                  {"exam_id": "a" * 32}, {"graphic_phase": "scene-1"}, {"explanation_kind": "intro"}):
        with pytest.raises(ValidationError):
            BuddyScope(learning_asset_instance_id="b" * 32, **extra)


def test_get_is_owned_read_only_with_graphic_starter_and_no_private_unit_context(api, book, exploration, transport):
    before = counts()
    response = book["client"].get("/api/schulbuddy/context", params=query(exploration))
    assert response.status_code == 200, response.text
    assert response.json()["starters"][0] == "Erkläre mir diese Grafik."
    assert counts() == before and transport["calls"] == []
    assert api.get("/api/schulbuddy/context", params=query(exploration)).status_code == 404
    assert book["client"].get("/api/schulbuddy/context", params={**query(exploration), "child_id": "f" * 32}).status_code == 404


def test_explicit_chat_uses_rendered_unassessed_asset_without_sources_or_learning_evidence(book, exploration, transport):
    before = counts()
    transport["output"] = {"answer": "Im ungeprüften Beispiel wechselt die Hervorhebung.", "sources": [], "next_question": None, "starters": []}
    response = ask_asset(book, exploration)
    assert response.status_code == 202, response.text
    finish()
    payload = transport["calls"][0]
    assert payload["sources"] == [] and payload["knowledge"] == {} and payload["page_inventory"] == {}
    assert "unit" not in payload and "current_question" not in payload
    current = payload["current_learning_asset"]
    assert current["factual_status"] == "unassessed" and current["mode"] == "unassessed_exploration"
    block = current["presentation"]["blocks"][0]
    assert block["scene"]["steps"][1]["highlight"] == ["b"]
    assert "source_excerpt" not in block and "source_excerpt" not in block["scene"]["steps"][0]
    assert counts()[2:] == before[2:]
    with DB() as db:
        assert db.get(SchulbuddyTurn, response.json()["id"]).status == "ready"
    assert "KEINE fachlich geprüfte Quelle" in SYSTEM


@pytest.mark.parametrize("timing", ["before", "during"])
def test_reference_change_before_or_during_dispatch_discards_chat(book, exploration, transport, timing):
    transport["output"] = {"answer": "Ein ungeprüftes Beispiel.", "sources": [], "next_question": None, "starters": []}
    response = ask_asset(book, exploration)
    assert response.status_code == 202
    def change():
        with DB.begin() as db:
            db.get(VisualReference, (exploration[1], 1)).digest = "0" * 64
    if timing == "before":
        change()
    else:
        transport["effect"] = change
    finish()
    assert len(transport["calls"]) == (1 if timing == "during" else 0)
    with DB() as db:
        turn = db.get(SchulbuddyTurn, response.json()["id"])
        assert turn.status == "failed" and turn.reply is None
    assert counts()[2:] == (0, 0)


def test_forged_grounded_citation_from_exploration_is_rejected(book, exploration, transport):
    response = ask_asset(book, exploration)
    assert response.status_code == 202
    finish()  # Existing mocked p1 citation cannot claim the public example as a source.
    with DB() as db:
        turn = db.get(SchulbuddyTurn, response.json()["id"])
        assert turn.status == "failed" and turn.reply is None
    assert counts()[2:] == (0, 0)


def test_deleted_instance_marks_saved_history_old_and_admin_cannot_access(book, exploration, transport, operator):
    transport["output"] = {"answer": "Ein ungeprüftes Beispiel.", "sources": [], "next_question": None, "starters": []}
    response = ask_asset(book, exploration)
    assert response.status_code == 202
    finish()
    assert operator.get("/api/schulbuddy/context", params=query(exploration)).status_code == 403
    with DB.begin() as db:
        db.delete(db.get(LearningAssetInstance, exploration[0]))
    saved = book["client"].get("/api/schulbuddy/questions/" + response.json()["id"])
    assert saved.status_code == 200 and saved.json()["source_changed"] is True
    assert book["client"].get("/api/schulbuddy/context", params=query(exploration)).status_code == 404
