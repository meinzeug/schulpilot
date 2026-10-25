"""Complete small part responses through the real adapter and old validators."""

import copy
import json

import httpx
import pytest
from package_output_helpers import PackageOutputCapture
from schulpilot import package_part_output, providers
from test_package_output_transport import fixture
from test_package_transport import config


def part():
    data, context, _ = fixture()
    data["units"] = data["units"][:1]
    data["units"][0]["questions"] = data["units"][0]["questions"][:2]
    unit = data["units"][0]
    for item in [unit, *unit["questions"]]:
        for step in item["explanation_steps"]:
            for block in step["presentation"]["blocks"]:
                block["scene"]["steps"] = block["scene"]["steps"][:2]
    context["visual_context"]["sources"] = context["visual_context"]["sources"][:1]
    context["visual_context"]["references"] = context["visual_context"]["references"][:1]
    payload = {**context, "materials": [{"subject": unit["subject"], "group_id": unit["group_id"],
        "topic": f"Künstliches Thema {index}", "content": context["visual_context"]["sources"][0]["content"]}
        for index in range(3)], "selected_groups": [{"id": unit["group_id"], "subject": unit["subject"],
        "estimated_minutes": 8}], "package_partition": 0, "package_plan_digest": "a" * 64}
    return data, payload


@pytest.mark.parametrize("fault", [None, "three_questions", "two_steps", "long_prompt", "three_phases"])
def test_actual_part_adapter_uses_two_questions_one_graphic_step_and_rejects_oversize(monkeypatch, fault):
    data, payload = part()
    if fault == "three_questions":
        data["units"][0]["questions"].append({**copy.deepcopy(data["units"][0]["questions"][0]), "id": "extra"})
    elif fault == "two_steps":
        data["units"][0]["questions"][0]["explanation_steps"].append(
            {**copy.deepcopy(data["units"][0]["questions"][0]["explanation_steps"][0]), "id": "extra"})
    elif fault == "long_prompt":
        data["units"][0]["questions"][0]["prompt"] = "x" * 301
    elif fault == "three_phases":
        scene = data["units"][0]["explanation_steps"][0]["presentation"]["blocks"][0]["scene"]
        scene["steps"].append(copy.deepcopy(scene["steps"][0]))
    output, real_client, calls = PackageOutputCapture(monkeypatch), httpx.Client, []

    def handler(request):
        body = json.loads(request.content)
        calls.append(body)
        assert body["max_tokens"] == 8000 and body["reasoning"]["effort"] == "medium"
        return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {
            "content": json.dumps(output.wire(data), ensure_ascii=False)}}],
            "usage": {"prompt_tokens": 100, "completion_tokens": 2000, "cost": 0.0202}})

    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real_client(transport=httpx.MockTransport(handler)))
    monkeypatch.setattr(providers, "external_allowed", lambda *a, **kw: None)
    monkeypatch.setattr(providers, "decrypt", lambda _: "synthetic-no-network-key")
    monkeypatch.setattr("schulpilot.model_routing.selection", lambda _: {"route": {"upstreams": ["azure"]}, "region": "standard"})
    value = config()
    value.max_output_tokens, value.reserve_micros = 8000, 250000
    if fault:
        with pytest.raises(providers.ProviderError):
            providers.request_provider(value, "package", payload)
    else:
        result = providers.request_provider(value, "package", payload)
        assert len(result.data["units"]) == 1 and len(result.data["units"][0]["questions"]) == 2
        assert result.cost_micros == 20200
        assert package_part_output.enabled(payload)  # index zero is a real part.
    assert len(calls) == 1
