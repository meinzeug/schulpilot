import io
import json

import httpx
import pytest
from schulpilot import free_standard_setup, provider_probe, providers
from schulpilot.db import DB, ProviderConfig, User
from schulpilot.providers import ProviderError, Result, config_for_function, external_allowed, request_provider
from schulpilot.schemas import ProviderUpdate
from schulpilot.synthetic import sample_unit
from test_providers import configured


def free_config(user):
    configured(user["families"][0]["id"])
    with DB.begin() as db:
        config = db.get(ProviderConfig, 1)
        config.provider = "openrouter"
        config.model = config.extraction_model = "fixture/model:free"
        config.capability_evidence = config.extraction_capability_evidence = "upstream=fixture-endpoint"
        config.input_per_million_micros = config.output_per_million_micros = 0
        config.openrouter_free_only = True
        config.openrouter_require_zdr = False


def test_new_default_is_free_openrouter_but_never_enabled_without_credentials(api):
    with DB() as db:
        config = db.get(ProviderConfig, 1)
        assert config.provider == "openrouter" and config.openrouter_free_only
        assert config.emergency_stop and not config.encrypted_key
    assert api.get("/api/status").json()["ai_available"] is False


@pytest.mark.parametrize("require_zdr", [False, True])
def test_real_free_route_keeps_deny_fixed_endpoint_and_zero_price(api, household, monkeypatch, require_zdr):
    user, _ = household
    free_config(user)
    calls, catalog = [], []
    output = sample_unit()
    output["questions"] = output["questions"][:2]
    monkeypatch.setattr(providers, "verify_free_endpoint", lambda *args: catalog.append(args))

    class Client:
        def __init__(self, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def post(self, url, headers, json):
            calls.append(json)
            return httpx.Response(
                200,
                json={
                    "choices": [
                        {"finish_reason": "stop", "message": {"content": __import__("json").dumps(output)}}
                    ],
                    "usage": {"prompt_tokens": 100, "completion_tokens": 200, "cost": 0},
                },
            )

    monkeypatch.setattr(providers.httpx, "Client", Client)
    with DB() as db:
        config = db.get(ProviderConfig, 1)
        config.openrouter_require_zdr = require_zdr
        source = "Arbitrary synthetic school material. " + output["explanation"]
        result = request_provider(config, "unit", {"material": {"content": source}})
    route = calls[0]["provider"]
    assert calls[0]["temperature"] == 0
    assert calls[0]["reasoning"] == {"enabled": False, "exclude": True}
    question_schema = calls[0]["response_format"]["json_schema"]["schema"]["$defs"]["Question"]
    assert all(branch["properties"]["hints"]["maxItems"] == 2 for branch in question_schema["anyOf"])
    assert question_schema["anyOf"][0]["properties"]["type"]["enum"] == ["choice"]
    assert question_schema["anyOf"][1]["properties"]["type"]["enum"] == ["gap", "short"]
    assert calls[0]["response_format"]["json_schema"]["schema"]["properties"]["questions"]["maxItems"] == 2
    assert all(branch["properties"]["prompt"]["maxLength"] == 1000 for branch in question_schema["anyOf"])
    assert route == {
        "only": ["fixture-endpoint"],
        "allow_fallbacks": False,
        "require_parameters": True,
        "data_collection": "deny",
        "zdr": require_zdr,
        "max_price": {"prompt": 0, "completion": 0, "request": 0},
    }
    assert catalog == [("fixture/model:free", "fixture-endpoint", False)]
    assert len(result.data["questions"]) == 2
    assert [q["type"] for q in result.data["questions"]] == ["choice", "gap"]
    assert result.cost_micros == 0
    assert "Arbitrary synthetic school material" in calls[0]["messages"][1]["content"][0]["text"]


@pytest.mark.parametrize("function", ["unit", "extract"])
def test_free_only_rejects_paid_models_before_sending_or_reserving(api, household, function):
    user, _ = household
    free_config(user)
    with DB() as db:
        config = db.get(ProviderConfig, 1)
        if function == "extract":
            config.extraction_model = "fixture/paid"
        else:
            config.model = "fixture/paid"
        with pytest.raises(ProviderError, match="kostenlose"):
            external_allowed(config_for_function(config, function), image=function == "extract")


def test_admin_preserves_omitted_policy_and_invalidates_changed_route(api, household):
    user, _ = household
    free_config(user)
    with DB.begin() as db:
        db.get(User, user["id"]).role = "admin"
        config = db.get(ProviderConfig, 1)
        payload = ProviderUpdate(
            **{c: getattr(config, c) for c in ProviderUpdate.model_fields if c not in {"api_key", "expected_revision"}}
        ).model_dump()
    payload.pop("openrouter_free_only")
    payload.pop("openrouter_require_zdr")
    saved = api.put("/api/admin/provider", json=payload)
    assert saved.status_code == 200
    assert saved.json()["openrouter_free_only"] and not saved.json()["openrouter_require_zdr"]
    assert not saved.json()["production_block_reason"]
    saved = api.put("/api/admin/provider", json={**payload, "openrouter_require_zdr": True})
    assert saved.status_code == 200 and saved.json()["production_block_reason"]
    assert api.put("/api/admin/provider", json={**payload, "extraction_model": "fixture/paid"}).status_code == 422
    assert api.put("/api/admin/provider", json={**payload, "input_per_million_micros": 1}).status_code == 422


def test_operator_standard_reuses_key_and_waits_for_complete_probe(api, household, monkeypatch):
    user, _ = household
    free_config(user)
    with DB() as db:
        encrypted_key = db.get(ProviderConfig, 1).encrypted_key
    monkeypatch.setattr(free_standard_setup, "verify_free_endpoint", lambda *args, **kwargs: None)
    monkeypatch.setattr(
        free_standard_setup.sys,
        "stdin",
        io.StringIO(json.dumps({"evidence": "Explicit synthetic operator approval for OpenRouter free standard"})),
    )
    free_standard_setup.configure()
    with DB() as db:
        config = db.get(ProviderConfig, 1)
        assert config.encrypted_key == encrypted_key and config.model == free_standard_setup.FREE_MODEL
        assert not config.openrouter_require_zdr and config.openrouter_free_only
        assert config.production_block_reason
    calls = []

    def request(config, function, payload, **kwargs):
        assert kwargs == {"synthetic_fixture": True, "private_probe": True}
        calls.append(function)
        if function == "package":
            raise ProviderError("Synthetic package rejection")
        return Result({}, cost_micros=0)

    monkeypatch.setattr(provider_probe, "request_provider", request)
    assert provider_probe.run() is False
    assert calls == ["extract", "unit", "package"]
    assert api.get("/api/status").json()["ai_available"] is False
    monkeypatch.setattr(provider_probe, "request_provider", lambda *args, **kwargs: Result({}, cost_micros=0))
    assert provider_probe.run() is True
    assert api.get("/api/status").json()["ai_available"] is True
