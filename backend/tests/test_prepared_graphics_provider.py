"""Real provider adapter with request-bound IDs and synthetic HTTP responses."""
import copy
import json

import httpx
import pytest
from package_output_helpers import PackageOutputCapture
from schulpilot import package_prepared_graphics, providers
from schulpilot.visual_reference_schemas import ExplanationStep
from test_package_part_output import part
from test_package_prepared_graphics import prepared, wire_step
from test_package_transport import config


@pytest.mark.parametrize("fault", [None, "scene", "foreign_id", "cross_source", "version", "stage", "source_ref", "text", "missing_id", "unrelated_fraction", "unrelated_scene"])
def test_requested_ids_hydrate_before_canonical_validation_and_keep_one_reported_bill(monkeypatch, fault):
    model_data, payload, binding = prepared(scene=fault in ("scene", "unrelated_scene"))
    model_data = copy.deepcopy(model_data)
    original = copy.deepcopy(model_data)
    expected = binding.hydrate(model_data)
    step = model_data["units"][0]["questions"][0]["explanation_steps"][0]
    if fault == "foreign_id":
        step["presentation"]["blocks"] = ["pg_PRIVATE_FOREIGN"]
    elif fault == "cross_source":
        changed = copy.deepcopy(payload)
        changed["visual_context"]["sources"][0]["revision"] += 1
        foreign = next(row for row in package_prepared_graphics.compile_candidates(changed)
            if row["kind"] == "fraction" and row["disclosure"] == "solution")
        step["presentation"]["blocks"] = [foreign["id"]]
    elif fault == "version":
        step["reference"]["version"] += 1
    elif fault == "stage":
        step["disclosure"] = "given"
    elif fault == "source_ref":
        step["source_refs"] = ["PRIVATE_FOREIGN_SOURCE"]
    elif fault == "text":
        step["text"] += " PRIVATE_MODEL_TEXT"
    elif fault == "missing_id":
        step["presentation"]["blocks"] = []
    elif fault == "unrelated_fraction":
        model_data["units"][0]["questions"][0]["prompt"] = "Welchen Nenner hat der Bruch 5/4?"
    elif fault == "unrelated_scene":
        scene = next(row for row in binding.candidates if row["kind"] == "scene" and row["disclosure"] == "solution")
        model_data["units"][0]["questions"][0]["explanation_steps"] = [wire_step(scene)]
    output, real_client, calls = PackageOutputCapture(monkeypatch), httpx.Client, []

    def handler(request):
        body = json.loads(request.content)
        calls.append(body)
        actual_payload = json.loads(body["messages"][1]["content"][0]["text"])
        candidates = actual_payload["prepared_graphics"]["candidates"]
        assert candidates == binding.context["candidates"]
        assert "source_excerpt" not in json.dumps(candidates) and all("block" not in row for row in candidates)
        assert package_prepared_graphics.REVISION in body["messages"][0]["content"]
        assert body["max_tokens"] == 8000 and body["reasoning"]["effort"] == "medium"
        wire_data = output.wire(model_data)
        if fault in (None, "scene", "unrelated_fraction"):
            import sys

            try:
                from jsonschema import Draft202012Validator
            except ModuleNotFoundError:
                sys.path.append("/usr/lib/python3/dist-packages")
                from jsonschema import Draft202012Validator

            actual_schema = body["response_format"]["json_schema"]["schema"]
            Draft202012Validator.check_schema(actual_schema)
            validator = Draft202012Validator(actual_schema)
            if fault == "unrelated_fraction":
                assert not validator.is_valid(wire_data)
            else:
                validator.validate(wire_data)
                decoded_step = output.binding.decode(wire_data)["units"][0]["questions"][0]["explanation_steps"][0]
                assert decoded_step == model_data["units"][0]["questions"][0]["explanation_steps"][0]
        return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {
            "content": json.dumps(wire_data, ensure_ascii=False)}}],
            "usage": {"prompt_tokens": 111, "completion_tokens": 2223, "cost": 0.0321}})

    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real_client(transport=httpx.MockTransport(handler)))
    monkeypatch.setattr(providers, "external_allowed", lambda *a, **kw: None)
    monkeypatch.setattr(providers, "decrypt", lambda _: "synthetic-no-network-key")
    monkeypatch.setattr("schulpilot.model_routing.selection", lambda _: {
        "route": {"upstreams": ["azure"]}, "region": "standard"})
    value = config()
    value.max_output_tokens, value.reserve_micros = 8000, 250000
    if fault not in (None, "scene"):
        with pytest.raises(providers.ProviderError) as caught:
            providers.request_provider(value, "package", payload)
        billed = caught.value.billing_result
        assert billed.telemetry["validation"]["phase"] in ("transport", "prepared_graphics")
        assert "PRIVATE" not in json.dumps(billed.telemetry)
        assert "PRIVATE" not in str(caught.value)
    else:
        billed = providers.request_provider(value, "package", payload)
        actual = billed.data["units"][0]
        wanted = expected["units"][0]
        for actual_item, expected_item in zip([actual, *actual["questions"]], [wanted, *wanted["questions"]], strict=True):
            assert [ExplanationStep.model_validate(step).model_dump() for step in actual_item["explanation_steps"]] == [
                ExplanationStep.model_validate(step).model_dump() for step in expected_item["explanation_steps"]]
            block = actual_item["explanation_steps"][0]["presentation"]["blocks"][0]
            assert isinstance(block, dict)
            assert block["source_excerpt"] in payload["visual_context"]["sources"][0]["content"]
        assert [q["answer"] for q in actual["questions"]] == [q["answer"] for q in original["units"][0]["questions"]]
        if fault == "scene":
            scene = actual["explanation_steps"][0]["presentation"]["blocks"][0]["scene"]
            assert [row["label"] for row in scene["objects"]] == ["Wasser", "Dampf"]
            assert scene["steps"][0]["source_excerpt"] == "Wasser → Dampf."
        else:
            numbers = actual["questions"][0]["explanation_steps"][0]["presentation"]["blocks"][0]["numbers"]
            assert numbers == wanted["questions"][0]["explanation_steps"][0]["presentation"]["blocks"][0]["numbers"]
    assert len(calls) == 1
    assert billed.cost_micros == 32100 and billed.cost_source == "reported"
    assert billed.input_tokens == 111 and billed.output_tokens == 2223


def test_nonmath_part_keeps_canonical_graphic_request_and_answer_contract(monkeypatch):
    data, payload = part()
    output, real_client, calls = PackageOutputCapture(monkeypatch), httpx.Client, []

    def handler(request):
        body = json.loads(request.content)
        calls.append(body)
        assert "prepared_graphics" not in json.loads(body["messages"][1]["content"][0]["text"])
        return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {
            "content": json.dumps(output.wire(data), ensure_ascii=False)}}],
            "usage": {"prompt_tokens": 111, "completion_tokens": 2223, "cost": 0.0321}})

    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real_client(transport=httpx.MockTransport(handler)))
    monkeypatch.setattr(providers, "external_allowed", lambda *a, **kw: None)
    monkeypatch.setattr(providers, "decrypt", lambda _: "synthetic-no-network-key")
    monkeypatch.setattr("schulpilot.model_routing.selection", lambda _: {
        "route": {"upstreams": ["azure"]}, "region": "standard"})
    value = config()
    value.max_output_tokens, value.reserve_micros = 8000, 250000
    result = providers.request_provider(value, "package", payload)
    assert len(calls) == 1 and result.cost_micros == 32100
    assert [q["answer"] for q in result.data["units"][0]["questions"]] == [q["answer"] for q in data["units"][0]["questions"]]
    assert all(isinstance(step["presentation"]["blocks"][0], dict) for unit in result.data["units"]
        for item in [unit, *unit["questions"]] for step in item["explanation_steps"])



def test_eight_prepared_bases_keep_actual_outbound_request_within_existing_reservation(monkeypatch, record_property):
    import test_package_transport
    from schulpilot import provider_cost_preflight
    from test_package_prepared_graphics import payload_for

    source = "\n".join(f"Ein Bruch {n}/{n + 1} beschreibt {n} von {n + 1} gleich großen Teilen." for n in range(1, 9))
    source = (source + "\nEigener künstlicher Quellenkontext. " * 300)[:6000]
    payload = payload_for(source)
    original_projection, measured = provider_cost_preflight.projection, []

    def project(*args):
        value = original_projection(*args)
        measured.append(value)
        record_property("preflight_text_bytes", value["text_bytes"])
        record_property("preflight_projected_micros", value["projected_micros"])
        record_property("preflight_schema_bytes", len(json.dumps(output.binding.wire_schema, ensure_ascii=False, separators=(",", ":")).encode()))
        return value

    def configured(provider="openrouter"):
        value = config(provider)
        value.max_output_tokens, value.reserve_micros = 8000, 250000
        return value

    monkeypatch.setattr(provider_cost_preflight, "projection", project)
    monkeypatch.setattr(test_package_transport, "config", configured)
    output = PackageOutputCapture(monkeypatch)
    captured = test_package_transport.wire(monkeypatch, payload)
    candidates = captured["payload"]["prepared_graphics"]["candidates"]
    assert len(candidates) == 40  # Eight literal fractions, five existing disclosure stages.
    assert len(source) == 6000 and len(measured) == 1
    assert measured[0]["projected_micros"] <= measured[0]["reserved_micros"] == 250000
    assert captured["body"]["max_tokens"] == 8000
    record_property("artificial_source_chars", len(source))
    record_property("base_candidates", 8)
    record_property("wire_candidates", len(candidates))
    record_property("text_bytes", measured[0]["text_bytes"])
    record_property("projected_micros", measured[0]["projected_micros"])
    record_property("schema_bytes", len(json.dumps(captured["schema"], ensure_ascii=False, separators=(",", ":")).encode()))
    record_property("http_body_bytes", len(captured["raw"]))


    # Validate the EXACT schema sent in the HTTP body with the independent
    # system jsonschema dependency; no model/network or raw payload files.
    import sys

    try:
        from jsonschema import Draft202012Validator
    except ModuleNotFoundError:
        sys.path.append("/usr/lib/python3/dist-packages")
        from jsonschema import Draft202012Validator

    schema = captured["body"]["response_format"]["json_schema"]["schema"]
    assert schema == captured["schema"] == output.binding.wire_schema
    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema)
    data, _, _ = prepared()
    rows = package_prepared_graphics.compile_candidates(payload)
    unit = data["units"][0]
    unit["explanation_steps"] = [wire_step(next(row for row in rows if row["kind"] == "fraction" and row["disclosure"] == "given"))]
    solutions = [row for row in rows if row["kind"] == "fraction" and row["disclosure"] == "solution"]
    for question, candidate in zip(unit["questions"], solutions, strict=False):
        question["explanation_steps"] = [wire_step(candidate)]
    actual_wire = output.wire(data)
    validator.validate(actual_wire)
    decoded = output.binding.decode(actual_wire)
    assert decoded["units"][0]["questions"][1]["prompt"] == unit["questions"][1]["prompt"]
    assert decoded["units"][0]["questions"][1]["explanation_steps"] == unit["questions"][1]["explanation_steps"]
    bad_wire = copy.deepcopy(actual_wire)
    alias = output.binding.aliases
    bad_wire[alias["units"]]["v0"][alias["questions"]]["v1"][alias["prompt"]] = "Was beschreibt der Bruch 5/4?"
    assert not validator.is_valid(bad_wire)  # Keeps the selected 2/3 graphic ID.
    assert output.binding.decode(bad_wire)["units"][0]["questions"][1]["prompt"] == "Was beschreibt der Bruch 5/4?"

    def nodes(value):
        if isinstance(value, dict):
            yield value
            for child in value.values():
                yield from nodes(child)
        elif isinstance(value, list):
            for child in value:
                yield from nodes(child)

    definitions = schema.get("$defs", {})

    def depth(node, *, objects_only=False):
        if "$ref" in node:
            return depth(definitions[node["$ref"].rsplit("/", 1)[-1]], objects_only=objects_only)
        children = [*node.get("properties", {}).values(), *node.get("anyOf", [])]
        if isinstance(node.get("items"), dict):
            children.append(node["items"])
        increment = int(node.get("type") == "object" or (not objects_only and node.get("type") == "array"))
        return increment + max((depth(child, objects_only=objects_only) for child in children), default=0)

    all_nodes = list(nodes(schema))
    metrics = {
        "object_properties": sum(len(node.get("properties", {})) for node in all_nodes),
        "nesting_containers": depth(schema),
        "nesting_objects": depth(schema, objects_only=True),
        "schema_string_characters": sum(sum(map(len, node.get("properties", {})))
            + sum(map(len, node.get("$defs", {})))
            + sum(len(value) for value in node.get("enum", []) if isinstance(value, str))
            + (len(node["const"]) if isinstance(node.get("const"), str) else 0) for node in all_nodes),
        "enum_values": sum(len(node.get("enum", [])) for node in all_nodes),
        "prompt_patterns": sum("pattern" in node for node in all_nodes),
    }
    for key, value in metrics.items():
        record_property(key, value)
    assert metrics["object_properties"] <= 5000
    assert metrics["nesting_containers"] <= 10
    assert metrics["schema_string_characters"] <= 120000
    assert metrics["enum_values"] <= 1000
    assert metrics["prompt_patterns"] >= 8
