"""Artificial ordinary units keep references, kinds and disclosure together."""
import copy
import json

import pytest
from schulpilot import providers, unit_reference_graphics, visual_references
from schulpilot.db import DB, Material
from schulpilot.subject_content import Graphic
from sqlalchemy import select
from test_german_original_comparison_132 import EXAMPLES, REFERENCE, SOURCE, output
from test_graphic_native_transport import subset_record
from test_model_routing import policy
from test_presentation_capability_paths import _config, _submitted, _transport


def context():
    with DB() as db:
        return {"required": True, "references": visual_references.candidates(db, "Deutsch", SOURCE),
            "sources": [{"ref": "p1", "subject": "Deutsch", "group_id": None, "content": SOURCE}]}


def branches(schema, node):
    if "$ref" in node:
        yield from branches(schema, schema["$defs"][node["$ref"].removeprefix("#/$defs/")])
    elif "anyOf" in node:
        for child in node["anyOf"]:
            yield from branches(schema, child)
    else:
        yield node


@pytest.mark.parametrize("count", [2, 5, 17])
def test_ordinary_schema_pairs_recipe_kind_source_and_stage_without_changing_count(count):
    from schulpilot.graphic_schema import bind_coherent_graphics
    from schulpilot.schemas import UnitOutput
    from schulpilot.subject_content import bind_graphic_schema

    schema = providers.strict_schema(UnitOutput, preserve_limits=True)
    bind_graphic_schema(schema, ["Deutsch"])
    bind_coherent_graphics(schema)
    schema["properties"]["questions"].update(minItems=count, maxItems=count)
    payload = {"material": {"subject": "Deutsch", "content": SOURCE}, "visual_context": context()}
    original = copy.deepcopy(payload)
    assert unit_reference_graphics.bind_schema(schema, payload)
    assert payload == original
    assert schema["properties"]["questions"]["minItems"] == schema["properties"]["questions"]["maxItems"] == count
    assert all(question["properties"]["presentation"] == {"type": "null"}
        for question in branches(schema, schema["properties"]["questions"]["items"]))
    for owner, given in [(schema, True), *[(question, False) for question in branches(schema, schema["properties"]["questions"]["items"])]]:
        steps = owner["properties"]["explanation_steps"]
        for step in branches(schema, steps["items"]):
            props = step["properties"]
            ref = next(branches(schema, props["reference"]))["properties"]
            presentation = next(branches(schema, props["presentation"]))["properties"]
            for graphic in branches(schema, presentation["blocks"]["items"]):
                assert ref["id"]["enum"] == [REFERENCE]
                assert graphic["properties"]["kind"]["enum"] == ["sentence"]
                assert graphic["properties"]["variant"]["enum"] == ["classification"]
                assert props["disclosure"]["enum"] == (["given"] if given else graphic["properties"]["disclosure"]["enum"])
                assert ("given" in props["disclosure"]["enum"]) is given
                assert props["source_refs"]["items"]["enum"] == ["p1"]


@pytest.mark.parametrize("fault", [None, "invented_label"])
def test_real_ordinary_adapter_round_trip_preserves_valid_output_and_rejects_fabricated_labels(monkeypatch, fault):
    value = output()["units"][0]
    value.pop("group_id")
    if fault:
        value["questions"][0]["explanation_steps"][0]["presentation"]["blocks"][0]["labels"][0] = "Ein erfundener Satz."
    before = copy.deepcopy(value)
    payload = {"material": {"subject": "Deutsch", "topic": "Originalbeispiele", "content": SOURCE},
        "visual_context": context()}
    calls = _transport(monkeypatch, "openrouter", value)
    config = _config("openrouter")
    config.max_output_tokens, config.reserve_micros = 8000, 250000
    approved = policy()
    config._selected_route = {"reason": "material_graphic_teaching", "tier": "sol", "region": "standard",
        "route": {**approved["routes"]["sol"], "upstreams": ["fixture-upstream"]}, "budget": approved["budget"]}
    if fault:
        with pytest.raises(providers.ProviderError) as caught:
            providers.request_provider(config, "unit", payload)
        assert caught.value.billing_result.telemetry["validation"]["errors"][0]["reason"] == "label_evidence"
    else:
        result = providers.request_provider(config, "unit", payload)
        assert [q["answer"] for q in result.data["questions"]] == ["liegen", "Heft"]
        assert result.data["questions"][0]["explanation_steps"][0]["presentation"]["blocks"][0]["labels"] == EXAMPLES
    assert len(calls) == 1 and value == before
    _, schema, instructions = _submitted("openrouter", calls[0])
    assert "unit-reference-graphics-1" in instructions and REFERENCE in json.dumps(schema)
    subset_record(schema)
    with DB() as db:
        assert list(db.scalars(select(Material))) == []


@pytest.mark.parametrize("special", ["review", "study_block", "homework_practice", "exam_preparation", "exam_review_practice", "selected_groups"])
def test_specialized_contracts_are_not_rebound(special):
    schema = {"unchanged": True}
    assert unit_reference_graphics.bind_schema(schema, {special: True,
        "material": {"subject": "Deutsch"}, "visual_context": context()}) is False
    assert schema == {"unchanged": True}


def test_scene_evidence_guard_remains_independent_and_strict():
    from schulpilot.learning_scenes import validate

    block = Graphic.model_validate({"kind": "scene", "title": "Start", "disclosure": "hint1",
        "source_excerpt": SOURCE, "labels": ["Start"], "numbers": [], "connections": [], "marks": [],
        "unit": "", "variant": "", "scene": {"version": 1, "layout": "row", "transition_ms": 0,
            "objects": [{"id": "o1", "label": "Start", "shape": "box", "tone": "neutral"}],
            "steps": [{"caption": EXAMPLES[0], "source_excerpt": SOURCE,
                "placements": [{"object_id": "o1", "slot": 0}], "highlight": ["o1"], "edges": []}]}})
    with pytest.raises(ValueError, match="Szenenbeschriftung fehlt"):
        validate(block, {"prompt": "Vergleiche die Beispiele."}, [SOURCE])


@pytest.mark.parametrize("subject", ["Mathematik", "Privates neues Fach", "Maths"])
def test_mathematics_and_unknown_private_subjects_keep_their_existing_contract(subject):
    schema = {"unchanged": True}
    assert unit_reference_graphics.bind_schema(schema, {"material": {"subject": subject},
        "visual_context": context()}) is False
    assert schema == {"unchanged": True}
