"""Native strict-schema projection with canonical, source-safe round trips."""
import copy
import json
from pathlib import Path

import httpx
import pytest
from pydantic import ValidationError
from schulpilot import graphic_transport, providers, subject_content
from schulpilot.graphic_schema import bind_coherent_graphics
from schulpilot.schemas import UnitOutput
from schulpilot.subject_content import Graphic
from test_presentation_capability_paths import _config, _submitted, _transport
from test_unit_graphic_schema import output, payload


def canonical(subject="Mathematik", labs=False):
    schema = providers.strict_schema(UnitOutput, preserve_limits=True)
    subject_content.bind_graphic_schema(schema, [subject], labs_enabled=labs)
    bind_coherent_graphics(schema)
    return schema


def branch(schema, kind):
    return next(item for item in schema["$defs"]["Graphic"]["anyOf"] if kind in item["properties"]["kind"]["enum"])


def subset_record(schema):
    """Conservative documented native forms, counting the ACTUAL wire nodes."""
    record = {"properties": 0, "enum_values": 0, "string_characters": 0}
    forbidden = {"allOf", "not", "if", "then", "else", "oneOf", "dependentRequired", "dependentSchemas"}

    def walk(node):
        if isinstance(node, dict):
            assert not forbidden.intersection(node)
            if "properties" in node:
                assert node["type"] == "object" and node["additionalProperties"] is False
                assert set(node["required"]) == set(node["properties"])
                record["properties"] += len(node["properties"])
                record["string_characters"] += sum(map(len, node["properties"]))
            if "anyOf" in node:
                assert not ({"type", "properties", "required", "additionalProperties"} & node.keys())
            record["string_characters"] += sum(map(len, node.get("$defs", {})))
            if isinstance(node.get("const"), str):
                record["string_characters"] += len(node["const"])
            for value in node.get("enum", []):
                assert value is None or type(value) in (str, int, float, bool)
                record["enum_values"] += 1
                if type(value) is str:
                    record["string_characters"] += len(value)
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(schema)

    def depth(node, active=(), count=0):
        if "$ref" in node:
            ref = node["$ref"]
            assert ref.startswith("#/$defs/") and ref not in active
            return depth(schema["$defs"][ref.removeprefix("#/$defs/")], (*active, ref), count)
        # Alternatives describe the SAME value; they do not add a JSON layer.
        if "anyOf" in node:
            return max(depth(item, active, count) for item in node["anyOf"])
        count += node.get("type") == "object"
        children = list(node.get("properties", {}).values())
        if isinstance(node.get("items"), dict):
            children.append(node["items"])
        return max([count, *(depth(child, active, count) for child in children)])

    record["object_depth"] = depth(schema)
    assert schema.get("type") == "object" and "anyOf" not in schema
    assert record["properties"] <= 5000 and record["enum_values"] <= 1000
    assert record["string_characters"] <= 120000 and record["object_depth"] <= 10
    return record


@pytest.mark.parametrize("numbers", [[0, 1], [1, 4], [1.0, 4.0], [24, 24]])
def test_only_pair_spelling_changes_and_input_canonical_schema_is_untouched(numbers):
    schema, data = canonical(), output(True, numbers=numbers)
    original_schema, original_data = copy.deepcopy(schema), copy.deepcopy(data)
    binding = graphic_transport.bind(schema)
    wire = binding.encode(data)
    assert schema == original_schema and data == original_data
    assert set(binding.wire_schema["$defs"]["Graphic"]) == {"anyOf"}
    assert len(branch(binding.wire_schema, "fraction")["properties"]["numbers"]["enum"]) == 324
    assert binding.decode(wire) == data
    expected = copy.deepcopy(data)
    for question in expected["questions"]:
        block = question["explanation_steps"][0]["presentation"]["blocks"][0]
        block["numbers"] = json.dumps([int(n) for n in block["numbers"]], separators=(",", ":"))
    assert wire == expected  # All answers, quotes, reference IDs and disclosure identical.
    subset_record(binding.wire_schema)


@pytest.mark.parametrize("value", [[1, 4], "[7,4]", "[1,25]", "[true,4]", "[1.0,4.0]", "[1, 4]", "[1]", None, True])
def test_decoder_does_not_guess_normalize_or_repair_malformed_pair(value):
    binding = graphic_transport.bind(canonical())
    wire = binding.encode(output())
    wire["questions"][0]["explanation_steps"][0]["presentation"]["blocks"][0]["numbers"] = value
    before = copy.deepcopy(wire)
    with pytest.raises(ValueError):
        binding.decode(wire)
    assert wire == before


@pytest.mark.parametrize("mutation", ["branch", "base", "missing", "disclosure"])
def test_unknown_union_or_base_mismatch_is_not_projected(mutation):
    schema = canonical()
    graphic = schema["$defs"]["Graphic"]
    if mutation == "branch":
        graphic["anyOf"][0]["properties"]["source_excerpt"]["maxLength"] = 1
    elif mutation == "base":
        graphic["properties"]["source_excerpt"]["maxLength"] = 1
    elif mutation == "missing":
        graphic["anyOf"][0]["required"].pop()
    else:
        graphic["anyOf"][0]["properties"]["disclosure"]["enum"] = ["given"]
    with pytest.raises(ValueError):
        graphic_transport.bind(schema)


@pytest.mark.parametrize("subject,labs", [("Mathematik", False), ("Physik", False), ("Physik", True), ("Deutsch", True), ("Englisch", False)])
def test_profile_and_disclosure_constraints_survive_every_native_branch(subject, labs):
    schema = canonical(subject, labs)
    binding = graphic_transport.bind(schema)
    allowed = set(schema["$defs"]["Graphic"]["properties"]["kind"]["enum"])
    actual = {kind for item in binding.wire_schema["$defs"]["Graphic"]["anyOf"] for kind in item["properties"]["kind"]["enum"]}
    assert actual == allowed
    for native in binding.wire_schema["$defs"]["Graphic"]["anyOf"]:
        kind = native["properties"]["kind"]["enum"][0]
        original = branch(schema, kind)
        expected = copy.deepcopy(original)
        if kind == "fraction":
            expected["properties"]["numbers"] = {"type": "string", "enum": list(binding.pairs)}
        assert native == expected
    subset_record(binding.wire_schema)


@pytest.mark.parametrize("changed", ["source_excerpt", "disclosure", "numbers"])
def test_native_round_trip_does_not_remove_canonical_domain_checks(changed):
    binding = graphic_transport.bind(canonical())
    data = output()
    block = data["questions"][0]["explanation_steps"][0]["presentation"]["blocks"][0]
    if changed == "numbers":
        block["numbers"] = [7, 4]
        with pytest.raises(ValueError):
            binding.encode(data)
        with pytest.raises(ValidationError):
            Graphic.model_validate(block)
    elif changed == "source_excerpt":
        block[changed] = "A fabricated literal quote."
        assert binding.decode(binding.encode(data)) == data  # Sources still require the separate canonical evidence check.
        with pytest.raises(ValueError):
            question = data["questions"][0]
            subject_content.validate_question(question["explanation_steps"][0]["presentation"], question,
                [payload()["material"]["content"]], subject_content.PROFILES["Mathematik"], subject="Mathematik")
    else:
        block[changed] = "invented"
        decoded = binding.decode(binding.encode(data))
        with pytest.raises(ValidationError):
            UnitOutput.model_validate(decoded)


@pytest.mark.parametrize("flow", ["study2", "study4", "study5", "entry", "coach_practice"])
def test_actual_final_native_request_uses_documented_shapes_and_exact_cost_inputs(monkeypatch, household, flow):
    from schulpilot import learning_entry, provider_cost_preflight, visual_references
    from schulpilot.db import DB, Child, Material
    from schulpilot.synthetic import CONTENT

    class Captured(BaseException):
        pass

    requested = payload(flow == "coach_practice")
    requested["grade"] = 6
    if flow.startswith("study"):
        requested = {"grade": 6, "required_subject": "Mathematik", "required_topic": "Brüche",
            "material": {"subject": "Mathematik", "topic": "Brüche", "content": CONTENT},
            "study_block": {"mode": "understand", "question_count": int(flow[-1]), "tasks": []}, "previous_prompts": []}
    with DB.begin() as db:
        child = db.get(Child, household[1]["id"])
        material = Material(child_id=child.id, title="PUBLIC SYNTHETIC", subject="Mathematik", topic="Brüche",
            content=CONTENT, confirmed=True, status="confirmed")
        db.add(material)
        db.flush()
        requested = visual_references.with_visual_context(db, child, requested, [material])
        if flow == "entry":
            requested = learning_entry.with_learning_entry(db, child, requested, [material], enabled=True)
    calls, projections = [], []
    original_projection = provider_cost_preflight.projection

    def observed(*args, **kwargs):
        result = original_projection(*args, **kwargs)
        projections.append(result)
        return result

    monkeypatch.setattr(provider_cost_preflight, "projection", observed)
    real_client = httpx.Client

    def handler(request):
        calls.append(json.loads(request.content))
        raise Captured

    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real_client(transport=httpx.MockTransport(handler)))
    config = _config("openrouter")
    config.max_output_tokens, config.reserve_micros = 4000, 150000
    # HTTP contracts use the existing artificial adapter prices. Real-route
    # price projections below are explicit sizing estimates, never a pass claim.
    with pytest.raises(Captured):
        providers.request_provider(config, "unit", requested)
    assert len(calls) == 1
    sent, wire_schema, instructions = _submitted("openrouter", calls[0])
    record = subset_record(wire_schema)
    assert set(wire_schema["$defs"]["Graphic"]) == {"anyOf"}
    assert branch(wire_schema, "fraction")["properties"]["numbers"]["type"] == "string"
    assert "native-graphic-1" in instructions
    assert sent["grade"] == 6
    assert calls[0]["max_tokens"] == 4000 and calls[0]["reasoning"]["effort"] == "medium"
    text_bytes = len((instructions + json.dumps(sent, ensure_ascii=False, separators=(",", ":")) + json.dumps(wire_schema)).encode())
    assert len(projections) == 1 and projections[0]["text_bytes"] == text_bytes
    assert projections[0]["projected_micros"] <= 150000
    priced = copy.copy(config)
    priced.input_per_million_micros, priced.output_per_million_micros = 2000000, 10000000
    sol_projection = original_projection(priced, "unit", text_bytes, None, 0)
    path = Path("/tmp/schulpilot123-native-schema-record.json")
    values = json.loads(path.read_text()) if path.exists() else {}
    values[flow] = {**record, "text_bytes": text_bytes, "schema_bytes": len(json.dumps(wire_schema).encode()),
        "artificial_projected_micros": projections[0]["projected_micros"], "output_token_cap": 4000, "reserve_micros": 150000,
        "sizing_at_2usd_input_10usd_output": sol_projection,
        "provider_calls": 0, "http_mock_boundaries": 1}
    path.write_text(json.dumps(values, sort_keys=True, indent=2))


@pytest.mark.parametrize("provider", ["openai", "openrouter", "codex"])
def test_native_round_trip_does_not_accept_wire_arrays_or_change_billing(monkeypatch, provider):
    from package_output_helpers import PackageOutputCapture

    actual_wire = PackageOutputCapture.wire

    def stale_response(self, data):
        result = actual_wire(self, data)
        block = result["questions"][0]["explanation_steps"][0]["presentation"]["blocks"][0]
        if isinstance(block, str):
            block = next(row["graphic"] for row in result["graphic_catalog"] if row["id"] == block)
        block["numbers"] = [1, 4]
        return result

    monkeypatch.setattr(PackageOutputCapture, "wire", stale_response)
    calls = _transport(monkeypatch, provider, output(True))
    with pytest.raises(providers.ProviderError) as caught:
        providers.request_provider(_config(provider), "unit", payload(True))
    assert len(calls) == 1
    result = caught.value.billing_result
    if provider == "openrouter":
        assert result is not None and result.input_tokens == 123 and result.output_tokens == 234
        assert result.telemetry["validation"]["phase"] == "transport"
    else:
        assert result is None  # Existing non-OR failure-accounting contract unchanged.


@pytest.mark.parametrize("numbers", [[True, 4], [float("nan"), 4], [float("inf"), 4], [7, 4]])
def test_encoder_refuses_nonfinite_boolean_and_domain_invalid_pairs(numbers):
    binding = graphic_transport.bind(canonical())
    with pytest.raises(ValueError):
        binding.encode(output(numbers=numbers))


def test_literal_pair_like_strings_are_opaque_in_answers_quotes_and_sources():
    data = output()
    data["questions"][0].update(answer="[1,4]", options=["[1,4]", "[3,4]"], prompt="The literal [1,4] stays exactly unchanged.")
    data["questions"][0]["explanation_steps"][0]["presentation"]["blocks"][0]["source_excerpt"] = "Original [1,4] and\n1/4."
    binding = graphic_transport.bind(canonical())
    decoded = binding.decode(binding.encode(data))
    assert decoded == data
