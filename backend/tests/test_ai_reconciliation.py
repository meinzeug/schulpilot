"""Synthetic metadata-only accounting checks; no external inference or money."""

import httpx
from schulpilot.ai_accounting import reconcile_one, response_metrics
from schulpilot.db import DB, ProviderConfig, Usage, now, uid
from test_model_routing import setup_policy


def pending(family_id, child_id, telemetry, *, created):
    return Usage(family_id=family_id, child_id=child_id, job_id=uid(), provider="openrouter",
        model="openai/gpt-6-luna", config_revision=1, function="unit", status="failed_unknown",
        cost_micros=None, reserved_micros=10000, bucket_ids=[], telemetry=telemetry, created=created)


def test_old_ineligible_rows_do_not_starve_generation_reconciliation(api, household, monkeypatch):
    parent, child = household
    family_id = parent["families"][0]["id"]
    setup_policy(family_id)
    timestamp = int(now())
    with DB.begin() as db:
        db.add_all(pending(family_id, child["id"], [
            {}, {"generation_id": "gen-exhausted", "reconcile_attempts": 3},
            {"generation_id": "gen-later", "reconcile_after": timestamp + 300},
            {"generation_id": None},
        ][index % 4], created=timestamp - 200 + index) for index in range(100))
        target = pending(family_id, child["id"], {"generation_id": "gen-synthetic-target"}, created=timestamp)
        db.add(target)
        db.flush()
        target_id = target.id
    calls = []

    def metadata(url, **kwargs):
        assert url == "https://openrouter.ai/api/v1/generation"
        assert kwargs["params"] == {"id": "gen-synthetic-target"}
        assert kwargs["follow_redirects"] is False
        calls.append(url)
        return httpx.Response(200, json={"data": {"id": "gen-synthetic-target", "total_cost": "0.0004",
            "tokens_prompt": 100, "tokens_completion": 50, "native_tokens_reasoning": 20,
            "native_tokens_completion": 32, "native_finish_reason": "max_output_tokens",
            "provider_name": "Azure"}})

    monkeypatch.setattr(httpx, "get", metadata)
    assert reconcile_one() is True
    assert reconcile_one() is False
    assert len(calls) == 1
    with DB() as db:
        result = db.get(Usage, target_id)
        assert result.cost_micros == 400 and result.cost_source == "generation"
        assert result.output_tokens == 50 and result.telemetry["reasoning_tokens"] == 20
        assert result.telemetry["native_completion_tokens"] == 32
        assert result.telemetry["native_finish_reason"] == "max_output_tokens"
        assert result.status == "failed_billed"
        assert not db.get(ProviderConfig, 1).emergency_stop


def test_finish_reason_uses_allowlist_without_retaining_provider_content():
    raw = {'choices': [{'finish_reason': 'length', 'message': {'content': 'synthetic-private-text'}}],
           'usage': {'completion_tokens': 25}}
    metrics = response_metrics(raw, 10)
    assert metrics['telemetry']['finish_reason'] == 'length'
    assert 'synthetic-private-text' not in str(metrics)
    raw['choices'][0]['finish_reason'] = 'synthetic-private-text'
    assert response_metrics(raw, 10)['telemetry']['finish_reason'] is None


def test_malformed_historical_generation_keeps_hold_and_does_not_block_next_tick(api, household, monkeypatch):
    parent, child = household
    family_id = parent["families"][0]["id"]
    setup_policy(family_id)
    with DB.begin() as db:
        invalid = pending(family_id, child["id"], {"generation_id": "invalid?metadata"}, created=int(now()))
        db.add(invalid)
        db.flush()
        usage_id = invalid.id
    monkeypatch.setattr(httpx, "get", lambda *args, **kwargs: (_ for _ in ()).throw(AssertionError("No HTTP expected")))
    assert reconcile_one() is True
    assert reconcile_one() is False
    with DB() as db:
        result = db.get(Usage, usage_id)
        assert result.cost_micros is None and result.reserved_micros == 10000
        assert result.telemetry["reconcile_attempts"] == 3
        assert result.telemetry["reconcile_error"] == "invalid_generation_id"
