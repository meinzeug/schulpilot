import copy
import json

import httpx
import pytest
from catalog_fixture import sample_catalog
from schulpilot import providers
from schulpilot import schemas as s
from schulpilot.catalog_ai import augmented_model, checked_assignment, constrain_schema, remember, with_catalog_context
from schulpilot.catalog_import import import_catalog
from schulpilot.catalog_jobs import work_one
from schulpilot.catalog_models import LearningTipContext
from schulpilot.db import DB, Child, Material, ProviderConfig
from schulpilot.extraction import TranscriptionOutput
from schulpilot.providers import ProviderError, request_provider, strict_schema
from schulpilot.subject_registry import resolve
from schulpilot.synthetic import sample_unit
from sqlalchemy import select
from test_providers import configured


@pytest.fixture
def bound(api, household, monkeypatch):
    parent, child = household
    configured(parent["families"][0]["id"])
    with DB.begin() as db:
        import_catalog(db, sample_catalog())
        kid = db.get(Child, child["id"])
        payload = with_catalog_context(
            db, kid, {"material": {"subject": "Mathe", "topic": "Brüche addieren", "content": "Brüche addieren"}}
        )
        sid = resolve(db, "Mathe").id
        config = db.get(ProviderConfig, 1)
    annotation = {
        "subject_ids": [sid],
        "matches": [
            {
                "context_ref": "section_1",
                "topic_ids": ["topic-add"],
                "learning_goal": "Brüche addieren",
                "quality": "high",
                "reason": "Künstliches Testthema",
            }
        ],
        "unmatched_context_refs": [],
    }
    state = {"output": sample_unit() | {"catalog_assignment": annotation}}
    calls = []

    class Client:
        def __init__(self, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *_):
            pass

        def post(self, url, headers, json):
            calls.append(json)
            return httpx.Response(
                200,
                json={
                    "status": "completed",
                    "output": [
                        {
                            "type": "message",
                            "content": [{"type": "output_text", "text": __import__("json").dumps(state["output"])}],
                        }
                    ],
                    "usage": {"input_tokens": 100, "output_tokens": 200},
                },
            )

    monkeypatch.setattr(providers.httpx, "Client", Client)
    return config, payload, annotation, calls, state, child


def test_existing_call_uses_bounded_candidates_and_returns_no_new_learning_fields(bound):
    config, payload, _, calls, _, _ = bound
    result = request_provider(config, "unit", payload)
    assert result.data == sample_unit() and result.catalog_assignment["matches"][0]["topic_id"] == "topic-add"
    assert len(calls) == 1
    body = calls[0]
    schema = body["text"]["format"]["schema"]
    assert schema["$defs"]["CatalogAssignment"]["properties"]["subject_ids"]["items"]["enum"]
    assert "Keine neuen Fächer" in body["instructions"]
    assert len(payload["catalog_context"]["candidates"]) <= 12
    assert all("url" not in row for row in payload["catalog_context"]["candidates"])


@pytest.mark.parametrize("change", ["subject", "topic", "context", "cross-subject"])
def test_untrusted_annotation_ids_are_rejected_without_retry(bound, change):
    config, payload, annotation, calls, state, _ = bound
    bad = copy.deepcopy(annotation)
    if change == "subject":
        bad["subject_ids"] = ["invented-subject"]
    if change == "topic":
        bad["matches"][0]["topic_ids"] = ["invented-topic"]
    if change == "context":
        bad["matches"][0]["context_ref"] = "invented-section"
    if change == "cross-subject":
        with DB() as db:
            bad["subject_ids"] = [resolve(db, "Englisch").id]
    state["output"]["catalog_assignment"] = bad
    with pytest.raises(ProviderError):
        request_provider(config, "unit", payload)
    assert len(calls) == 1


def test_extraction_preserves_subject_allowlist_but_not_old_learning_history(bound):
    config, payload, annotation, calls, state, child = bound
    with DB() as db:
        request = with_catalog_context(db, db.get(Child, child["id"]), {"task": "transcribe_entire_image_verbatim"})
    annotation = copy.deepcopy(annotation)
    annotation["matches"] = []
    state["output"] = {
        "blocks": [{"kind": "paragraph", "text": "Brüche addieren"}],
        "legibility": "readable",
        "subject": "Mathematik",
        "topic": "Brüche addieren",
        "uncertainties": [],
        "homework": [],
        "catalog_assignment": annotation,
    }
    result = request_provider(
        config, "extract", request | {"recent_outcomes": [{"private": "must not be sent"}]}, b"SYNTHETIC-IMAGE"
    )
    assert result.data["content"] == "Brüche addieren" and result.catalog_assignment["subject_ids"]
    sent = json.loads(calls[0]["input"][0]["content"][0]["text"])
    assert sent["catalog_context"]["subjects"] and not sent["catalog_context"]["candidates"]
    assert "recent_outcomes" not in sent and "private" not in str(sent)


def test_annotation_is_kept_separate_and_ignored_after_snapshot_change(bound):
    config, payload, _, _, _, child = bound
    result = request_provider(config, "unit", payload)
    with DB.begin() as db:
        row = Material(
            child_id=child["id"],
            title="Künstlich",
            subject="Mathe",
            topic="Brüche addieren",
            content="Brüche addieren",
            status="confirmed",
            confirmed=True,
        )
        db.add(row)
        db.flush()
        mid = row.id
        remember(db, "material", row, result.catalog_assignment)
    for _ in range(20):
        if not work_one():
            break
    with DB() as db:
        context = db.scalar(select(LearningTipContext).where(LearningTipContext.material_id == mid))
        assert context.matches[0]["basis"] == "ai"
        assert "reason" not in context.matches[0] and "learning_goal" not in context.matches[0]
        assert context.matcher_version == "tips-v1"


def test_extended_schema_still_enforces_original_question_and_transcription_rules(bound):
    _, payload, annotation, _, _, _ = bound
    model = augmented_model(s.UnitOutput)
    with pytest.raises(ValueError):
        model.model_validate(sample_unit() | {"questions": [], "catalog_assignment": annotation})
    schema = strict_schema(augmented_model(TranscriptionOutput), preserve_limits=True)
    constrain_schema(schema, payload["catalog_context"])
    assert schema["properties"]["blocks"]["maxItems"] == 80
    bad = copy.deepcopy(annotation)
    bad["matches"][0]["topic_ids"] = ["topic-past"]
    with pytest.raises(ValueError):
        checked_assignment(bad, payload["catalog_context"], sample_unit())


def test_parent_goal_without_photo_keeps_exact_existing_subject_label(bound):
    _, _, _, _, _, child = bound
    with DB() as db:
        payload = with_catalog_context(
            db,
            db.get(Child, child["id"]),
            {"goal": {"subject": "Mathe", "topic": "Brüche addieren", "note": "Brüche addieren üben"}},
        )
    schema = strict_schema(augmented_model(s.UnitOutput), preserve_limits=True)
    constrain_schema(schema, payload["catalog_context"])
    assert "Mathe" in schema["properties"]["subject"]["enum"]
    assert any(row["id"] == "topic-add" for row in payload["catalog_context"]["candidates"])
