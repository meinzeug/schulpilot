"""Actual request_provider + HTTPX MockTransport, synthetic DB/config only."""

import json

import httpx
import pytest
from schulpilot import providers
from schulpilot.db import DB, Child, Family, Usage, UsageBucket, User, uid
from test_presentation_capability_paths import _config


@pytest.mark.parametrize("envelope_location", ["top", "choice"])
@pytest.mark.parametrize("category,expected_code,known_usage", [
    ("provider_overloaded", "provider_busy", True),
    ("timeout", "provider_timeout", True),
    ("future_category", "provider_unavailable", True),
    (None, "provider_unavailable", False),
], ids=["busy_reported", "timeout_reported", "unclassified_reported", "unclassified_unknown_cost"])
def test_http200_error_keeps_single_call_and_billing(monkeypatch, envelope_location,
        category, expected_code, known_usage):
    config = _config("openrouter")
    with DB.begin() as db:
        family = Family(name="Synthetic transport family", commerce_required=False,
            call_limit=10, budget_micros=10_000)
        child_user = User(username="synthetic-transport-child", display_name="Synthetic",
            password_hash="NOT-A-LOGIN-HASH", role="child", verified=True)
        db.add_all([family, child_user])
        db.flush()
        child = Child(family_id=family.id, user_id=child_user.id, grade=6, subjects=["Informatik"])
        db.add(child)
        db.flush()
        usage = providers.reserve(db, family, child.id, uid(), "unit")
        usage_id, reserved = usage.id, usage.reserved_micros
    assert reserved == 1000

    private = "PRIVATE-SYNTHETIC-UPSTREAM-NOT-FOR-DISPLAY"
    error = {"message": private, "metadata": {"raw": private}}
    if category is not None:
        error["metadata"]["error_type"] = category
    envelope = ({"error": error} if envelope_location == "top" else {"choices": [{"error": error}]})
    if known_usage:
        envelope["usage"] = {"prompt_tokens": 17, "completion_tokens": 9,
            "cost": "0.000230", "completion_tokens_details": {"reasoning_tokens": 4}}
    original_client = httpx.Client
    calls = []

    def handler(request):
        assert request.method == "POST" and request.url.host == "openrouter.ai"
        calls.append(request)
        return httpx.Response(200, json=envelope)

    def client(**kwargs):
        return original_client(transport=httpx.MockTransport(handler), **kwargs)

    monkeypatch.setattr(providers.httpx, "Client", client)
    with pytest.raises(providers.ProviderError) as raised:
        providers.request_provider(config, "unit", {"material": {
            "subject": "Informatik", "topic": "Logik", "content": "UND und ODER sind logische Begriffe."}})
    failure = raised.value
    assert len(calls) == 1
    assert failure.code == expected_code
    assert private not in str(failure)
    result = failure.billing_result
    assert result is not None and result.data == {}
    assert private not in json.dumps(result.telemetry, sort_keys=True)
    assert private not in json.dumps(result.request_receipt, sort_keys=True)
    assert result.request_receipt["parameter_basis"] == "actual_transmitted_request"
    assert result.input_tokens == (17 if known_usage else None)
    assert result.output_tokens == (9 if known_usage else None)
    assert result.cost_micros == (230 if known_usage else None)
    assert result.cost_source == ("reported" if known_usage else "unknown")
    assert result.telemetry["reasoning_tokens"] == (4 if known_usage else None)
    with DB.begin() as db:
        providers.settle(db, db.get(Usage, usage_id), result, failed=True)
    with DB() as db:
        saved = db.get(Usage, usage_id)
        assert saved.status == ("failed_billed" if known_usage else "failed_unknown")
        assert saved.cost_micros == (230 if known_usage else None)
        assert saved.cost_source == ("reported" if known_usage else "unknown")
        assert saved.input_tokens == result.input_tokens and saved.output_tokens == result.output_tokens
        assert saved.telemetry["requested_max_output_tokens"] == result.request_receipt["max_output_tokens"]
        assert private not in json.dumps(saved.telemetry, sort_keys=True)
        for bucket_id in saved.bucket_ids:
            bucket = db.get(UsageBucket, bucket_id)
            assert bucket.calls == 1
            assert bucket.encumbered_micros == (230 if known_usage else reserved)
            assert bucket.known_cost_micros == (230 if known_usage else 0)
            assert bucket.unknown_calls == (0 if known_usage else 1)
    assert len(calls) == 1  # Settlement did not repeat inference or retrieve metadata.
