"""Configured output headroom reaches one package request; no live provider."""

import copy
import json

import httpx
import pytest
from package_output_helpers import PackageOutputCapture
from schulpilot import providers
from schulpilot.db import ProviderConfig
from schulpilot.model_routing import select_route
from test_model_routing import policy
from test_package_output_transport import fixture
from test_package_transport import config


@pytest.mark.parametrize("base_output,route_output,expected", [(4000, 8000, 4000), (8000, 4000, 4000), (8000, 8000, 8000)])
@pytest.mark.parametrize("base_reserve,route_reserve,expected_reserve", [(150000, 250000, 150000), (250000, 150000, 150000), (250000, 250000, 250000)])
def test_package_caps_need_both_base_and_sol_without_changing_luna(
    base_output, route_output, expected, base_reserve, route_reserve, expected_reserve
):
    routes = policy()
    routes["routes"]["sol"].update(max_output_tokens=route_output, reserve_micros=route_reserve)
    before = copy.deepcopy(routes)
    value = ProviderConfig(provider="openrouter", routing_policy=routes,
                           max_output_tokens=base_output, reserve_micros=base_reserve)
    package = select_route(value, "package")
    assert package.max_output_tokens == expected and package.reserve_micros == expected_reserve
    assert package.reasoning_effort == "medium"
    review = select_route(value, "coach")
    assert review.max_output_tokens == routes["routes"]["luna"]["max_output_tokens"]
    assert review.reserve_micros == routes["routes"]["luna"]["reserve_micros"]
    assert routes == before


@pytest.mark.parametrize("finish", ["stop", "length"])
def test_eight_thousand_package_preserves_graphics_and_billing_on_one_call(monkeypatch, finish):
    data, context, _ = fixture()
    payload = {**context, "materials": [
        {"group_id": source["group_id"], "subject": source["subject"], "topic": f"Künstliches Thema {index}",
         "content": source["content"]}
        for source in context["visual_context"]["sources"] for index in range(3)],
        "selected_groups": [{"id": unit["group_id"], "subject": unit["subject"], "estimated_minutes": 6}
                            for unit in data["units"]]}
    output, calls, real_client = PackageOutputCapture(monkeypatch), [], httpx.Client

    def handler(request):
        body = json.loads(request.content)
        calls.append(body)
        assert body["max_tokens"] == 8000
        assert body["reasoning"] == {"effort": "medium", "exclude": True}
        assert body["provider"]["allow_fallbacks"] is False
        return httpx.Response(200, json={"choices": [{"finish_reason": finish,
            "message": {"content": json.dumps(output.wire(data), ensure_ascii=False)}}],
            "usage": {"prompt_tokens": 100, "completion_tokens": 6000, "cost": 0.0602}})

    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real_client(transport=httpx.MockTransport(handler)))
    monkeypatch.setattr(providers, "external_allowed", lambda *a, **kw: None)
    monkeypatch.setattr(providers, "decrypt", lambda _: "synthetic-key-never-sent")
    monkeypatch.setattr("schulpilot.model_routing.selection", lambda _: {"route": {"upstreams": ["azure"]}, "region": "standard"})
    value = config()
    value.max_output_tokens, value.reserve_micros = 8000, 250000
    if finish == "length":
        with pytest.raises(providers.ProviderError, match="Ausgabelänge") as caught:
            providers.request_provider(value, "package", payload)
        result = caught.value.billing_result
    else:
        result = providers.request_provider(value, "package", payload)
        assert len(result.data["units"]) == 2
        assert sum(len(unit["questions"]) for unit in result.data["units"]) == 6
        assert all(question["explanation_steps"] for unit in result.data["units"] for question in unit["questions"])
    assert len(calls) == 1
    assert result.cost_micros == 60200 and result.cost_source == "reported"
    assert result.output_tokens == 6000
