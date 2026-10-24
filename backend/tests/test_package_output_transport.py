"""Reversible synthetic output spelling; no real model or private source data."""
import copy
import json
from pathlib import Path

import pytest
from pydantic import ValidationError
from schulpilot import package_output_transport as transport
from schulpilot import providers, visual_references
from schulpilot.db import DB
from schulpilot.schemas import PackageOutput

SCENES = json.loads((Path(__file__).parents[2] / "testdata/learning_scenes_v1.json").read_text())["cases"]
FIELDS = json.loads((Path(__file__).parents[2] / "testdata/learning_fields_v1.json").read_text())["cases"][0]


def fixture(groups=2, steps=1):
    units, sources, references = [], [], []
    for index in range(groups):
        case = SCENES[index % 2]
        subject, group, ref = case["subject"], f"g{index + 1}", f"p{index + 1}"
        def step(stage, number=1):
            p = copy.deepcopy(case["question"]["presentation"])
            for block in p["blocks"]:
                block["disclosure"] = stage
            return {"id": f"e{number}", "text": case["source"], "disclosure": stage, "competence_id": None,
                    "reference": {"id": "general.source_relation.phases", "version": 1},
                    "source_refs": [ref], "presentation": p}
        questions = []
        for number in range(6 // groups):
            q = copy.deepcopy(case["question"])
            q.update(id=f"q{number + 1}", presentation=None,
                     explanation_steps=[step("solution", i + 1) for i in range(steps)])
            questions.append(q)
        units.append({"group_id": group, "subject": subject, "topic": "Künstlicher Transporttest",
                      "explanation": case["source"], "explanation_steps": [step("given")], "questions": questions})
        sources.append({"ref": ref, "subject": subject, "group_id": group, "content": case["source"]})
        references.append({"id": "general.source_relation.phases", "version": 1, "subject": subject})
    data = PackageOutput.model_validate({"units": units}).model_dump(mode="json")
    context = {"visual_context": {"required": True, "sources": sources, "references": references}}
    schema = providers.strict_schema(PackageOutput, preserve_limits=True)
    visual_references.bind_schema(schema, context)
    return data, context, schema


def _bytes(value):
    return len(json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode())


@pytest.mark.parametrize("groups", [2, 3])
@pytest.mark.parametrize("steps", [1, 2])
def test_validated_six_question_graphic_package_roundtrip_and_measured_size(groups, steps, record_property):
    data, context, schema = fixture(groups, steps)
    with DB() as db:
        visual_references.validate_output(db, data, context)
    binding = transport.bind(schema)
    saved_schema = copy.deepcopy(schema)
    encoded = binding.encode(data)
    decoded = binding.decode(encoded)
    assert decoded == data and schema == saved_schema
    assert PackageOutput.model_validate(decoded).model_dump(mode="json") == data
    with DB() as db:
        visual_references.validate_output(db, decoded, context)
    assert _bytes(encoded) < _bytes(data) * 0.8
    record_property("canonical_output_bytes", _bytes(data))
    record_property("wire_output_bytes", _bytes(encoded))
    record_property("final_wire_schema_bytes", _bytes(binding.wire_schema))
    assert binding.constants["version"] == 1 and binding.constants["competence_id"] is None
    assert len({q["id"] for q in decoded["units"][0]["questions"]}) == 6 // groups


def test_aliases_are_injective_and_only_schema_properties_change():
    schema = {"type": "object", "properties": {
        "description": {"type": "string", "description": "Property title is CONTENT, not an alias."},
        "title": {"type": "string"}, "a": {"type": "string"}},
        "required": ["description", "title", "a"], "additionalProperties": False}
    binding = transport.bind(schema)
    value = {"description": "title", "title": 'CO ≠ Co; e\u0301 é 😀\n  {"fields":{"title":"x"}}', "a": "a"}
    assert len(set(binding.aliases.values())) == len(binding.aliases)
    assert binding.decode(binding.encode(value)) == value
    assert "Property title is CONTENT" in json.dumps(binding.wire_schema)
    assert schema["required"] == ["description", "title", "a"]


def test_global_constant_requires_all_occurrences_to_match_and_be_required():
    schema = {"type": "object", "properties": {
        "version": {"const": 1}, "other": {"type": "object", "properties": {"version": {"enum": [2]}}, "required": ["version"]},
        "optional": {"type": "null"}}, "required": ["version", "other"]}
    binding = transport.bind(schema)
    assert "version" not in binding.constants and "optional" not in binding.constants
    value = {"version": 1, "other": {"version": 2}}
    assert binding.decode(binding.encode(value)) == value


@pytest.mark.parametrize("constant", [None, True, "fixed", 1])
def test_only_explicit_scalar_constants_are_restored(constant):
    schema = {"type": "object", "properties": {"value": {"const": constant}, "variable": {"type": "string"}},
              "required": ["value", "variable"], "additionalProperties": False}
    binding = transport.bind(schema)
    encoded = binding.encode({"value": constant, "variable": "unchanged"})
    assert set(encoded) == {binding.aliases["variable"]}
    assert binding.decode(encoded) == {"value": constant, "variable": "unchanged"}
    with pytest.raises(ValueError):
        binding.decode({**encoded, binding.aliases["value"]: constant})


@pytest.mark.parametrize("fault", ["missing", "unknown", "canonical_keys", "wrong_type", "null_override"])
def test_decoder_rejects_malformed_wire_without_guessing_or_partial_data(fault):
    data, _, schema = fixture()
    binding = transport.bind(schema)
    value = binding.encode(data)
    if fault == "missing":
        value.clear()
    elif fault == "unknown":
        value["not_in_schema"] = "untrusted"
    elif fault == "canonical_keys":
        value = data
    elif fault == "wrong_type":
        value[binding.aliases["units"]] = "not a list"
    else:
        step = value[binding.aliases["units"]][0][binding.aliases["explanation_steps"]][0]
        step[binding.aliases["competence_id"]] = "invented.competence"
    with pytest.raises(ValueError):
        binding.decode(value)


def test_all_source_text_and_graphic_fields_remain_identical_and_invalid_source_still_fails():
    data, context, schema = fixture()
    binding = transport.bind(schema)
    data["units"][0]["explanation_steps"][0]["presentation"]["blocks"][0]["source_excerpt"] = "Erfundene Quelle"
    decoded = binding.decode(binding.encode(data))
    assert decoded == data
    with DB() as db, pytest.raises(ValueError):
        visual_references.validate_output(db, decoded, context)


@pytest.mark.parametrize("fault", ["duplicate_id", "unknown_reference", "wrong_disclosure", "scene_reference"])
def test_existing_canonical_graphic_and_question_guards_remain_authoritative(fault):
    data, context, schema = fixture()
    if fault == "duplicate_id":
        data["units"][0]["questions"][1]["id"] = data["units"][0]["questions"][0]["id"]
    else:
        step = data["units"][0]["explanation_steps"][0]
        if fault == "unknown_reference":
            step["reference"]["id"] = "unknown.reference"
        elif fault == "wrong_disclosure":
            step["presentation"]["blocks"][0]["disclosure"] = "solution"
        else:
            step["presentation"]["blocks"][0]["scene"]["steps"][0]["placements"][0]["object_id"] = "missing"
    # The transport never repairs invalid semantic values. A schema enum can
    # reject an unknown ref sooner; otherwise the unchanged canonical validators do.
    binding = transport.bind(schema)
    with pytest.raises((ValueError, ValidationError)):
        decoded = binding.decode(binding.encode(data))
        PackageOutput.model_validate(decoded)
        with DB() as db:
            visual_references.validate_output(db, decoded, context)


@pytest.mark.parametrize("answer", [0, 1, 99, -1, True, "0"])
def test_indexed_choice_wire_keeps_actual_type_and_never_guesses_an_option(answer):
    data, _, schema = fixture()
    q = data["units"][0]["questions"][0]
    q.update(type="choice", options=["Verdunstung", "Kondensation"], answer=answer, accepted=[])
    providers.indexed_choice_schema(schema, bounded_matches=True)
    binding = transport.bind(schema)
    if answer in (0, 1) and type(answer) is int:
        decoded = binding.decode(binding.encode(data))
        assert decoded["units"][0]["questions"][0]["answer"] == answer
        actual = providers.decode_choice_indices(decoded)
        assert actual["units"][0]["questions"][0]["answer"] == q["options"][answer]
    else:
        with pytest.raises((ValueError, providers.ProviderError)):
            decoded = binding.decode(binding.encode(data))
            providers.decode_choice_indices(decoded)


def test_match_and_grouped_answer_strings_are_not_reinterpreted_by_aliases():
    data, _, schema = fixture()
    q = data["units"][0]["questions"][0]
    q.update(type="match", options=["a|x", "b|y"], answer="x;y", accepted=[])
    binding = transport.bind(schema)
    assert binding.decode(binding.encode(data))["units"][0]["questions"][0]["answer"] == "x;y"
    q["options"] = ["a|x", "a|y"]
    with pytest.raises(ValidationError):
        PackageOutput.model_validate(binding.decode(binding.encode(data)))
    grouped = PackageOutput.model_validate({"units": [{"group_id": "g1", "subject": FIELDS["subject"],
        "topic": "Künstlich", "explanation": FIELDS["source"], "questions": [FIELDS["question"],
        {**copy.deepcopy(FIELDS["question"]), "id": "fields2"}]}]}).model_dump(mode="json")
    binding = transport.bind(providers.strict_schema(PackageOutput, preserve_limits=True))
    assert binding.decode(binding.encode(grouped)) == grouped
    assert grouped["units"][0]["questions"][0]["answer"] == FIELDS["question"]["answer"]


@pytest.mark.parametrize("place", ["schema", "data"])
def test_cycles_and_nonfinite_values_cannot_trigger_unbounded_reconstruction(place):
    data, _, schema = fixture()
    if place == "schema":
        schema["loop"] = schema
        with pytest.raises(ValueError):
            transport.bind(schema)
    else:
        binding = transport.bind(schema)
        data["units"].append(data)
        with pytest.raises(ValueError):
            binding.encode(data)
        with pytest.raises(ValueError):
            binding.decode({"arbitrary": float("nan")})


@pytest.mark.parametrize("finish", ["stop", "length"])
def test_actual_openrouter_adapter_compact_graphics_keeps_cap_reasoning_and_rejects_truncation(monkeypatch, finish):
    import httpx
    from package_output_helpers import PackageOutputCapture
    from test_package_transport import config

    data, context, _ = fixture()
    payload = {**context, "materials": [
        {"group_id": source["group_id"], "subject": source["subject"], "topic": f"Künstliches Thema {i}",
         "content": source["content"]}
        for source in context["visual_context"]["sources"] for i in range(3)],
        "selected_groups": [{"id": unit["group_id"], "subject": unit["subject"], "estimated_minutes": 6}
                            for unit in data["units"]]}
    captured, output = [], PackageOutputCapture(monkeypatch)
    real_client = httpx.Client
    def handler(request):
        body = json.loads(request.content)
        captured.append(body)
        assert body["max_tokens"] == 4000 and body["reasoning"] == {"effort": "medium", "exclude": True}
        assert body["provider"]["allow_fallbacks"] is False
        assert body["response_format"]["json_schema"]["schema"] == output.binding.wire_schema
        wire = output.wire(data)
        text = json.dumps(wire, ensure_ascii=False)
        # A length response cannot be recovered, including when the body happens
        # to end at a valid JSON boundary. Never start another adapter call.
        return httpx.Response(200, json={"choices": [{"finish_reason": finish, "message": {"content": text}}],
            "usage": {"prompt_tokens": 100, "completion_tokens": 4000, "cost": 0}})
    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real_client(transport=httpx.MockTransport(handler)))
    monkeypatch.setattr(providers, "external_allowed", lambda *a, **kw: None)
    monkeypatch.setattr(providers, "decrypt", lambda _: "synthetic-key-never-sent")
    monkeypatch.setattr("schulpilot.model_routing.selection", lambda _: {"route": {"upstreams": ["azure"]}, "region": "standard"})
    if finish == "length":
        with pytest.raises(providers.ProviderError, match="Ausgabelänge"):
            providers.request_provider(config(), "package", payload)
    else:
        result = providers.request_provider(config(), "package", payload)
        assert len(result.data["units"]) == 2 and sum(len(u["questions"]) for u in result.data["units"]) == 6
        with DB() as db:
            visual_references.validate_output(db, result.data, context)
    assert len(captured) == 1


@pytest.mark.parametrize("fault", ["unknown", "remote", "ref_cycle", "oneOf", "dependentRequired"])
def test_unsupported_or_unknown_schema_is_refused_before_any_adapter_call(fault):
    schema = {"type": "object", "properties": {"value": {"type": "string"}}, "required": ["value"]}
    if fault == "unknown":
        schema["properties"]["value"] = {"$ref": "#/$defs/missing"}
    elif fault == "remote":
        schema["properties"]["value"] = {"$ref": "https://example.invalid/schema"}
    elif fault == "ref_cycle":
        schema["$defs"] = {"recursive": {"$ref": "#/$defs/recursive"}}
        schema["properties"]["value"] = {"$ref": "#/$defs/recursive"}
    else:
        schema[fault] = [] if fault == "oneOf" else {"value": ["other"]}
    with pytest.raises(ValueError):
        transport.bind(schema)
