"""The supported OpenAI adapter must hydrate prepared IDs before Pydantic."""
import copy
import json

import httpx
import pytest
from schulpilot import providers
from schulpilot.visual_reference_schemas import ExplanationStep
from test_presentation_capability_paths import _config


@pytest.mark.parametrize("kind", ["composition", "expansion"])
def test_actual_openai_adapter_hydrates_only_selected_prepared_ids(household, monkeypatch, kind):
    if kind == "composition":
        from test_unit_fraction_compositions import prepared

        payload, binding, wire = prepared(household)
    else:
        from test_study_fraction_expansions import prepared

        _, payload, _, _, binding, wire = prepared(household)
    original_wire = copy.deepcopy(wire)
    expected = binding.hydrate(wire)
    calls = []
    real = httpx.Client

    def handler(request):
        assert str(request.url) == "https://api.openai.com/v1/responses"
        body = json.loads(request.content)
        calls.append(body)
        assert body["store"] is False
        schema = body["text"]["format"]["schema"]
        # The prepared binding prunes native Graphic transport. Thus this
        # must work without relying on choice-index/native-Graphic decoding.
        assert "Graphic" not in schema.get("$defs", {})
        assert all(isinstance(item["explanation_steps"][0]["presentation"]["blocks"][0], str)
                   for item in [wire, *wire["questions"]])
        assert wire["explanation_steps"][0]["presentation"]["blocks"][0] in json.dumps(schema)
        return httpx.Response(200, json={"status": "completed", "usage": {
            "input_tokens": 100, "output_tokens": 500}, "output": [{"type": "message", "content": [
                {"type": "output_text", "text": json.dumps(wire)}]}]})

    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real(transport=httpx.MockTransport(handler)))
    result = providers.request_provider(_config("openai"), "unit", payload)
    assert len(calls) == 1
    assert (result.input_tokens, result.output_tokens) == (100, 500)
    assert wire == original_wire
    core = ("id", "type", "prompt", "answer", "options", "accepted")
    assert [{key: question[key] for key in core} for question in result.data["questions"]] == [
        {key: question[key] for key in core} for question in wire["questions"]]
    for restored, canonical in zip([result.data, *result.data["questions"]],
                                   [expected, *expected["questions"]], strict=True):
        assert [ExplanationStep.model_validate(step) for step in restored["explanation_steps"]] == [
            ExplanationStep.model_validate(step) for step in canonical["explanation_steps"]]
        assert all(isinstance(block, dict) for block in restored["explanation_steps"][0]["presentation"]["blocks"])
