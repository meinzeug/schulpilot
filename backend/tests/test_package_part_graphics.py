"""Public synthetic Graphic branches; no child data or real provider requests.

Independent Draft-2020-12 verification uses the system jsonschema separately;
tracked tests need no additional runtime/development dependency.
"""
import copy
import json
from pathlib import Path

import pytest
from pydantic import ValidationError
from schulpilot import package_output_transport, package_part_output, package_transport, providers
from schulpilot.schemas import PackageOutput
from schulpilot.subject_content import PROFILES, Graphic, bind_graphic_schema, generation_context
from test_package_part_output import part
from test_presentation_capability_paths import _config, _submitted, _transport

DATA = Path(__file__).parents[2] / "testdata"


def cases():
    result = []
    for name in ("subject_cases_v1.json", "science_graphics_v1.json", "learning_scenes_v1.json", "text_probes_v1.json"):
        for case in json.loads((DATA / name).read_text())["cases"]:
            for index, block in enumerate((case["question"].get("presentation") or {}).get("blocks", [])):
                result.append((case["id"] + ":" + str(index), case["subject"], block))
    for case in json.loads((DATA / "learning_labs_v1.json").read_text())["cases"]:
        block = {**case["public_presentation"]["blocks"][0], "source_excerpt": "Eigenes kuratiertes synthetisches Lehrmodell."}
        subject = "Physik" if case["id"].startswith("physics.") else "Deutsch"
        result.append((case["id"], subject, block))
    return result


CASES = cases()


def full_schema(subject, *, parts=True, labs=True):
    schema = providers.strict_schema(PackageOutput, preserve_limits=True)
    bind_graphic_schema(schema, [subject], labs_enabled=labs)
    if parts:
        package_part_output.bind_schema(schema)
    return schema


def block_schema(subject, *, parts=True, labs=True):
    full = full_schema(subject, parts=parts, labs=labs)
    return {"type": "object", "properties": {"graphic": {"$ref": "#/$defs/Graphic"}},
            "required": ["graphic"], "additionalProperties": False, "$defs": full["$defs"]}


def normalized(block):
    # These are NEW synthetic request fixtures, not saved provider responses.
    # Select two complete original phases for the existing 2-phase part cap;
    # never crop source text or mutate the shared original public fixture.
    value = Graphic.model_validate(block).model_dump(mode="json")
    if value.get("scene") is not None:
        value["scene"]["steps"] = value["scene"]["steps"][:2]
    return Graphic.model_validate(value).model_dump(mode="json")


def branch_for(schema, kind):
    graphic = schema["$defs"]["Graphic"]
    return next(branch for branch in graphic["anyOf"] if kind in branch["properties"]["kind"]["enum"])


@pytest.mark.parametrize("case_id,subject,block", CASES, ids=[item[0] for item in CASES])
def test_public_graphic_fixtures_roundtrip_kind_selected_full_strict_branch(case_id, subject, block):
    value = {"graphic": normalized(block)}
    schema = block_schema(subject)
    kind = value["graphic"]["kind"]
    branch = branch_for(schema, kind)
    assert branch["type"] == "object" and branch["additionalProperties"] is False
    assert set(branch["required"]) == set(branch["properties"])
    binding = package_output_transport.bind(package_transport.schema_projection(schema))
    wire = binding.encode(value)
    assert binding.decode(wire) == value
    assert Graphic.model_validate(binding.decode(wire)["graphic"]).model_dump(mode="json") == value["graphic"]
    # A coherent ordinary graphic cannot retain any unrelated special payload.
    for key in ("scene", "text_probe", "lab"):
        if key != kind:
            assert branch["properties"][key] == {"type": "null"}


@pytest.mark.parametrize("subject", list(PROFILES))
def test_every_subject_keeps_catalogue_enum_and_only_selected_strict_families(subject):
    schema = full_schema(subject)
    graphic = schema["$defs"]["Graphic"]
    context = generation_context([subject], schema=schema)
    assert context["graphic_kinds"] == sorted(graphic["properties"]["kind"]["enum"])
    assert set(context["graphic_kinds"]) == set(PROFILES[subject])
    actual = [kind for branch in graphic["anyOf"] for kind in branch["properties"]["kind"]["enum"]]
    assert sorted(actual) == context["graphic_kinds"] and len(actual) == len(set(actual))
    assert len(graphic["anyOf"]) <= len(PROFILES[subject]) < 20
    assert context["scene_limits"] == {"objects": 4, "steps": 2, "transition_ms": 800}
    old_context = generation_context([subject], schema=full_schema(subject, parts=False))
    assert old_context["scene_limits"] == {"objects": 12, "steps": 8, "transition_ms": 800}
    assert old_context["graphic_kinds"] == context["graphic_kinds"]


def invalid_mixes():
    scene = next(normalized(block) for _, _, block in CASES if block["kind"] == "scene")
    text = next(normalized(block) for _, _, block in CASES if block["kind"] == "text_probe")
    lab = next(normalized(block) for _, _, block in CASES if block["kind"] == "lab")
    return [("scene_plus_text", "Deutsch", {**scene, "text_probe": text["text_probe"]}),
        ("scene_plus_lab", "Physik", {**scene, "lab": lab["lab"]}),
        ("scene_numbers", "Geographie", {**scene, "numbers": [1]}),
        ("scene_variant", "Geographie", {**scene, "variant": "open"}),
        ("scene_unit", "Geographie", {**scene, "unit": "cm"}),
        ("scene_empty_labels", "Geographie", {**scene, "labels": []}),
        ("scene_missing_payload", "Geographie", {**scene, "scene": None}),
        ("ordinary_foreign_scene", "Englisch", {**scene, "kind": "forms"}),
        ("text_given", "Deutsch", {**text, "disclosure": "given"}),
        ("lab_plus_scene", "Physik", {**lab, "scene": scene["scene"]}),
        ("lab_missing_payload", "Physik", {**lab, "lab": None})]


INVALID = invalid_mixes()


@pytest.mark.parametrize("case_id,subject,block", INVALID, ids=[item[0] for item in INVALID])
def test_formerly_independent_fields_are_bound_and_domain_rejection_is_unchanged(case_id, subject, block):
    schema = block_schema(subject)
    branch = branch_for(schema, block["kind"])["properties"]
    if case_id == "scene_numbers":
        assert branch["numbers"]["maxItems"] == 0
    elif case_id == "scene_empty_labels":
        assert branch["labels"]["minItems"] >= 1
    elif case_id in ("scene_variant", "scene_unit"):
        assert branch[case_id.removeprefix("scene_")]["enum"] == [""]
    elif case_id == "text_given":
        assert "given" not in branch["disclosure"]["enum"]
    elif case_id.endswith("missing_payload"):
        key = "scene" if case_id.startswith("scene") else "lab"
        assert branch[key].get("type") != "null" and "anyOf" not in branch[key]
    else:
        key = "text_probe" if case_id == "scene_plus_text" else "lab" if case_id == "scene_plus_lab" else "scene"
        assert branch[key] == {"type": "null"}
    with pytest.raises(ValidationError):
        Graphic.model_validate(block)


@pytest.mark.parametrize("kind,size,units", [("fraction", 2, None), ("triangle", 2, ["cm", "m"]),
    ("reflection", 1, ["°"]), ("function_graph", 3, [""]), ("technical_drawing", 3, ["mm", "cm"])])
def test_numeric_recipes_have_exact_structural_parameter_count_and_unit(kind, size, units):
    subject = next(subject for subject, kinds in PROFILES.items() if kind in kinds)
    fields = branch_for(block_schema(subject), kind)["properties"]
    assert fields["numbers"]["minItems"] == fields["numbers"]["maxItems"] == size
    if units is not None:
        assert fields["unit"]["enum"] == units
    assert fields["scene"] == fields["text_probe"] == fields["lab"] == {"type": "null"}


def test_client_without_labs_cannot_select_lab_branch_or_receive_lab_catalogue():
    schema = full_schema("Physik", labs=False)
    assert "lab" not in generation_context(["Physik"], schema=schema)["graphic_kinds"]
    assert all("lab" not in branch["properties"]["kind"]["enum"] for branch in schema["$defs"]["Graphic"]["anyOf"])


def test_only_new_part_request_changes_schema_and_old_validated_outputs_still_validate():
    data, payload = part()
    old = copy.deepcopy(data)
    package_part_output.validate(data)
    assert data == old and package_part_output.enabled(payload)
    schema = full_schema("Geographie", parts=False)
    assert "anyOf" not in schema["$defs"]["Graphic"]
    old_frozen = copy.deepcopy(schema)
    package_part_output.bind_schema(schema)
    assert old_frozen != schema
    package_part_output.validate(data)  # Existing saved receipt is still accepted unchanged.
    assert data == old


@pytest.mark.parametrize("provider", ["openai", "openrouter", "codex"])
def test_real_adapter_selected_branch_codec_and_bounds_guide_remain_consistent(monkeypatch, provider):
    data, payload = part()
    calls = _transport(monkeypatch, provider, data)
    config = _config(provider)
    config.max_output_tokens, config.reserve_micros = 8000, 250000
    result = providers.request_provider(config, "package", payload)
    assert len(calls) == 1 and len(result.data["units"][0]["questions"]) == 2
    submitted, schema, instructions = _submitted(provider, calls[0])
    assert submitted["content_context"]["scene_limits"] == {"objects": 4, "steps": 2, "transition_ms": 800}
    assert "package-part-graphics-1" in instructions and "0<=Zähler<=Nenner<=24" in instructions
    # The actual request has only selected-profile, strict full Graphic branches.
    objects = []
    def visit(node):
        if isinstance(node, dict):
            if {"kind", "labels", "numbers", "scene", "text_probe", "lab"} <= node.get("properties", {}).keys():
                objects.append(node)
            for child in node.values():
                visit(child)
        elif isinstance(node, list):
            for child in node:
                visit(child)
    visit(schema)
    assert objects and all(node["additionalProperties"] is False and set(node["required"]) == set(node["properties"]) for node in objects)
