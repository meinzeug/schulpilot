"""Synthetic ordinary/practice graphics on the real outbound adapter contract."""
import copy
import json
from pathlib import Path

import httpx
import pytest
from pydantic import ValidationError
from schulpilot import providers
from schulpilot.package_output_transport import bind as bind_output
from schulpilot.schemas import Question
from schulpilot.subject_content import Graphic
from test_presentation_capability_paths import _config, _submitted, _transport

DATA = Path(__file__).parents[2] / "testdata"
MATH = next(case for case in json.loads((DATA / "subject_cases_v1.json").read_text())["cases"] if case["id"] == "MAT01")


def output(practice=False, numbers=None):
    question = copy.deepcopy(MATH["question"])
    block = Graphic.model_validate(question.pop("presentation")["blocks"][0]).model_dump(mode="json")
    block["disclosure"] = "solution"
    if numbers is not None:
        block["numbers"] = numbers
    question["explanation_steps"] = [{"id": "step1", "text": "1 von 4 gleich großen Teilen.",
        "competence_id": None, "disclosure": "solution", "presentation": {
            "version": 1, "evidence_kind": "application", "blocks": [block]},
        "reference": {"id": "math.fraction.part_whole", "version": 1}, "source_refs": ["p1"]}]
    if practice:
        question["learning_goal_id"] = "g1"
    second = {**copy.deepcopy(question), "id": "second", "prompt": "Welcher Bruch steht vor dem Pluszeichen in 1/4 + 1/8?",
        "answer": "1/4"}
    return {"subject": "Mathematik", "topic": "Brüche", "explanation": MATH["source"],
        "questions": [question, second]}


def payload(practice=False):
    result = {"material": {"subject": "Mathematik", "topic": "Brüche", "content": MATH["source"]}}
    if practice:
        result.update(review=True, learning_goals=[{"id": "g1", "label": "Brüche addieren", "source_excerpt": MATH["source"]}])
    return result


def fraction_branch(schema):
    graphic = schema["$defs"]["Graphic"]
    return next(branch for branch in graphic["anyOf"] if "fraction" in branch["properties"]["kind"]["enum"])


@pytest.mark.parametrize("provider", ["openai", "openrouter", "codex"])
@pytest.mark.parametrize("practice", [False, True], ids=["material", "coach_practice"])
def test_actual_unit_request_binds_proper_fraction_pairs_before_model(monkeypatch, provider, practice):
    original = output(practice)
    calls = _transport(monkeypatch, provider, original)
    config = _config(provider)
    before = (config.max_output_tokens, config.reserve_micros)
    result = providers.request_provider(config, "unit", payload(practice))
    assert len(calls) == 1
    sent, schema, instructions = _submitted(provider, calls[0])
    branch = fraction_branch(schema)
    field = branch["properties"]["numbers"]
    assert field["minItems"] == field["maxItems"] == 2
    assert field["enum"] == [[n, d] for d in range(1, 25) for n in range(d + 1)]
    assert [7, 4] not in field["enum"] and [3, 4] in field["enum"]
    assert all(branch["properties"][key] == {"type": "null"} for key in ("scene", "text_probe", "lab"))
    assert "0 <= n <= d <= 24" in instructions
    assert "fraction" in sent["content_context"]["graphic_kinds"]
    assert (config.max_output_tokens, config.reserve_micros) == before
    for actual, expected in zip(result.data["questions"], original["questions"], strict=True):
        for key in ("id", "type", "prompt", "answer", "options", "accepted"):
            assert actual[key] == expected[key]


@pytest.mark.parametrize("numbers", [[7, 4], [1, 0], [1, 25], [-1, 4], [1.5, 4], [1]])
def test_invalid_returned_fraction_is_still_rejected_once_with_billing(monkeypatch, numbers):
    response = output(True, numbers=numbers)
    calls = _transport(monkeypatch, "openrouter", response)
    with pytest.raises(providers.ProviderError) as caught:
        providers.request_provider(_config("openrouter"), "unit", payload(True))
    assert len(calls) == 1
    billed = caught.value.billing_result
    assert billed is not None
    validation = billed.telemetry["validation"]
    assert validation["phase"] == "schema"
    assert validation["errors"][0] == {"location": "questions.0.explanation_steps.0.presentation.blocks.0", "reason": "fraction_bounds"}
    schema = _submitted("openrouter", calls[0])[1]
    assert numbers not in fraction_branch(schema)["properties"]["numbers"]["enum"]


def test_finite_pair_enum_preserves_json_numeric_equality_and_rejects_boolean_or_improper():
    schema = {"type": "object", "properties": {"numbers": {"type": "array", "items": {"type": "number"},
        "minItems": 2, "maxItems": 2, "enum": [[1, 4], [3, 4]]}}, "required": ["numbers"], "additionalProperties": False}
    binding = bind_output(schema)
    for numbers in ([1, 4], [1.0, 4.0], [3, 4.0]):
        value = {"numbers": numbers}
        assert binding.decode(binding.encode(value)) == value
    for numbers in ([7, 4], [True, 4]):
        with pytest.raises(ValueError):
            binding.decode({binding.aliases["numbers"]: numbers})


@pytest.mark.parametrize("answer", [0.0, True, "0", -1, 2])
def test_numeric_array_equivalence_does_not_relax_scalar_choice_integer(answer):
    schema = {"type": "object", "properties": {"answer": {"type": "integer", "enum": [0, 1]}},
        "required": ["answer"], "additionalProperties": False}
    binding = bind_output(schema)
    assert binding.decode(binding.encode({"answer": 0})) == {"answer": 0}
    with pytest.raises(ValueError):
        binding.decode({binding.aliases["answer"]: answer})


def test_canonical_improper_fraction_and_valid_answer_remain_separate():
    original = output()
    block = original["questions"][0]["explanation_steps"][0]["presentation"]["blocks"][0]
    with pytest.raises(ValidationError):
        Graphic.model_validate({**block, "numbers": [7, 4]})
    assert Graphic.model_validate({**block, "numbers": [3, 4]}).numbers == [3.0, 4.0]
    assert original["questions"][0]["answer"] == "3/8"
    mixed = Question.model_validate({"id": "mixed", "type": "short", "prompt": "Schreibe7/4 als gemischte Zahl.",
        "answer": "1¾", "accepted": [], "options": [], "hints": ["Ein Ganzes hat vier Viertel."],
        "explanation": "7/4 sind ein Ganzes und drei Viertel."})
    assert mixed.answer == "1¾" and mixed.prompt == "Schreibe7/4 als gemischte Zahl."


def test_actual_unit_request_large_public_source_stays_in_unchanged_sol_preflight(monkeypatch):
    class Captured(BaseException):
        pass

    captures, projections = [], []
    from schulpilot import provider_cost_preflight

    project = provider_cost_preflight.projection

    def observed_projection(*args, **kwargs):
        result = project(*args, **kwargs)
        projections.append(result)
        return result

    monkeypatch.setattr(provider_cost_preflight, "projection", observed_projection)
    real = httpx.Client

    def handler(request):
        body = json.loads(request.content)
        captures.append(body)
        assert body["max_tokens"] == 8000 and body["reasoning"]["effort"] == "medium"
        raise Captured

    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real(transport=httpx.MockTransport(handler)))
    config = _config("openrouter")
    config.max_output_tokens, config.reserve_micros = 8000, 250000
    config.input_per_million_micros, config.output_per_million_micros = 2000000, 10000000
    source = payload(True)
    source["material"]["content"] = (MATH["source"] + "\n") * 300
    with pytest.raises(Captured):
        providers.request_provider(config, "unit", source)
    assert len(captures) == 1  # The real preflight accepted before this HTTP stub boundary.
    body = captures[0]
    instructions = body["messages"][0]["content"]
    text_payload = body["messages"][1]["content"][0]["text"]
    schema = body["response_format"]["json_schema"]["schema"]
    count = len(instructions.encode()) + len(text_payload.encode()) + len(json.dumps(schema).encode())
    assert count <= 80904
    assert len(projections) == 1 and projections[0]["text_bytes"] == count
    assert projections[0]["projected_micros"] <= 250000
    # Public synthetic sizing receipt only; no model success or real price.
    Path("/tmp/schulpilot122-unit-graphic-wire.json").write_text(json.dumps({
        "fixture": "public_MAT01_300_repeats", "provider_calls": 0, "mock_http_boundaries": 1,
        "instructions_bytes": len(instructions.encode()), "payload_bytes": len(text_payload.encode()),
        "schema_bytes": len(json.dumps(schema).encode()), "text_bytes": count,
        "preflight": projections[0], "limits_unchanged": {"output_tokens": 8000, "reserve_microusd": 250000,
            "input_per_million_microusd": 2000000, "output_per_million_microusd": 10000000, "reasoning": "medium"}},
        sort_keys=True, indent=2))
    block = output(True)["questions"][0]["explanation_steps"][0]["presentation"]["blocks"][0]
    Path("/tmp/schulpilot122-graphic-jsonschema-proof-input.json").write_text(json.dumps({
        "schema": {"$ref": "#/$defs/Graphic", "$defs": schema["$defs"]}, "valid": [block,
            {**block, "numbers": [0, 1]}, {**block, "numbers": [24, 24]}, {**block, "numbers": [1.0, 4.0]}],
        "invalid": [{**block, "numbers": values} for values in ([7, 4], [1, 0], [1, 25], [-1, 4], [1.5, 4], [True, 4], [1])]}
        , ensure_ascii=False))
    assert config.max_output_tokens == 8000 and config.reserve_micros == 250000


@pytest.mark.parametrize("subject", ["Mathematik", "Physik", "Deutsch"])
@pytest.mark.parametrize("labs", [False, True], ids=["no_labs", "labs_capability"])
def test_actual_unit_profile_capability_precedes_copied_branches_and_later_passes_do_not_mutate_them(monkeypatch, subject, labs):
    from schulpilot import graphic_schema, subject_content, visual_references
    from schulpilot.learning_labs import RECIPES

    class Captured(BaseException):
        pass

    order, snapshots, calls = [], {}, []
    profile_bind = subject_content.bind_graphic_schema
    coherent_bind = graphic_schema.bind_coherent_graphics
    describe = subject_content.generation_context
    visual_bind = visual_references.bind_schema

    def profile(schema, subjects, **kwargs):
        result = profile_bind(schema, subjects, **kwargs)
        order.append("profile")
        assert "anyOf" not in schema["$defs"]["Graphic"]
        snapshots["profile"] = copy.deepcopy(schema["$defs"]["Graphic"])
        return result

    def coherent(schema):
        assert order == ["profile"]
        assert schema["$defs"]["Graphic"] == snapshots["profile"]
        coherent_bind(schema)
        order.append("coherent")
        snapshots["coherent"] = copy.deepcopy(schema["$defs"]["Graphic"])

    def context(subjects, **kwargs):
        assert order == ["profile", "coherent"]
        before = copy.deepcopy(kwargs["schema"]["$defs"]["Graphic"])
        result = describe(subjects, **kwargs)
        assert kwargs["schema"]["$defs"]["Graphic"] == before == snapshots["coherent"]
        order.append("context")
        return result

    def visual(schema, requested):
        assert order == ["profile", "coherent", "context"]
        before = copy.deepcopy(schema["$defs"]["Graphic"])
        visual_bind(schema, requested)
        assert schema["$defs"]["Graphic"] == before == snapshots["coherent"]
        order.append("visual")

    monkeypatch.setattr(subject_content, "bind_graphic_schema", profile)
    monkeypatch.setattr(graphic_schema, "bind_coherent_graphics", coherent)
    monkeypatch.setattr(subject_content, "generation_context", context)
    monkeypatch.setattr(visual_references, "bind_schema", visual)
    real = httpx.Client

    def handler(request):
        calls.append(json.loads(request.content))
        raise Captured

    monkeypatch.setattr(providers.httpx, "Client", lambda **kwargs: real(transport=httpx.MockTransport(handler)))
    requested = {"material": {"subject": subject, "topic": "Künstlicher Vertrag", "content": "Quelle → Ziel."},
        "labs_enabled": labs, "visual_context": {"required": True, "references": [
            {"id": "general.source_relation.phases", "version": 1, "subject": subject, "kind": "scene"}],
            "sources": [{"ref": "p1", "subject": subject, "group_id": None, "content": "Quelle → Ziel.",
                "material_id": "a" * 32, "revision": 1}]}}
    with pytest.raises(Captured):
        providers.request_provider(_config("openrouter"), "unit", requested)
    assert len(calls) == 1 and order == ["profile", "coherent", "context", "visual"]
    sent, schema, _ = _submitted("openrouter", calls[0])
    graphic = schema["$defs"]["Graphic"]
    assert graphic == snapshots["coherent"]
    allowed = set(graphic["properties"]["kind"]["enum"])
    assert {kind for branch in graphic["anyOf"] for kind in branch["properties"]["kind"]["enum"]} == allowed
    assert set(sent["content_context"]["graphic_kinds"]) == allowed
    actual_recipes = {key for key, recipe in RECIPES.items() if labs and subject in recipe["subjects"]}
    assert ("lab" in allowed) == bool(actual_recipes)
    for branch in graphic["anyOf"]:
        fields = branch["properties"]
        kinds = fields["kind"]["enum"]
        for key in ("scene", "text_probe", "lab"):
            if key not in kinds:
                assert fields[key] == {"type": "null"}
        if "text_probe" in kinds:
            assert "given" not in fields["disclosure"]["enum"]
        if "lab" in kinds:
            assert fields["lab"] != {"type": "null"}
            assert set(schema["$defs"]["LabV1"]["properties"]["recipe_id"]["enum"]) == actual_recipes
