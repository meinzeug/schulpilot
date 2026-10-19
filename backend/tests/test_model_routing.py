"""Synthetic money and routes; these tests never call an external provider."""

from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy

import httpx
import pytest
from fastapi import HTTPException
from pydantic import ValidationError
from schulpilot import providers
from schulpilot.ai_accounting import allocate_fee, response_metrics
from schulpilot.config import settings
from schulpilot.db import DB, ChildCostBucket, CreditPurchase, Family, Job, ProviderConfig, Usage, UsageBucket, now, uid
from schulpilot.model_routing import RoutingPolicy, choose_tier, job_config, select_route
from schulpilot.providers import ProviderError, Result, reserve, settle
from sqlalchemy import func, select
from test_providers import configured


def policy():
    routes = {}
    for tier, model, reserve_cost in [('luna', 'openai/gpt-6-luna', 10000), ('sol', 'openai/gpt-6.1-sol', 20000)]:
        routes[tier] = dict(model=model, upstreams=['azure'], input_per_million_micros=100000,
            output_per_million_micros=500000, max_output_tokens=1000, reserve_micros=reserve_cost,
            image_capable=True, capability_evidence='Synthetic supported parameters',
            pricing_evidence='Synthetic price ceiling', privacy_evidence='Synthetic ZDR route and disabled workspace logging',
            evaluated=True, under13_approved=True, verified_at=int(now()))
    return dict(version=1, enabled=True, revision='test-policy-1', routes=routes,
        budget=dict(eur_per_usd='1', fx_evidence='Synthetic conservative bound, not a market quote',
            fx_checked_at=int(now()), fee_reserve_bps=800))


def setup_policy(family_id, *, hard=None):
    configured(family_id)
    with DB.begin() as db:
        cfg = db.get(ProviderConfig, 1)
        cfg.provider = 'openrouter'
        cfg.model = 'openai/gpt-6.1-sol'
        cfg.routing_policy = policy()
        if hard is not None:
            cfg.routing_policy = {**cfg.routing_policy, 'budget': {**cfg.routing_policy['budget'],
                'target_eur_micros': hard, 'warning_eur_micros': hard, 'hard_eur_micros': hard}}
        cfg.reserve_micros = 100000
        cfg.production_block_reason = ''
        family = db.get(Family, family_id)
        family.call_limit, family.budget_micros = 1000, 1000000


def test_routes_use_recorded_need_and_do_not_fall_back(api, household):
    parent, child = household
    setup_policy(parent['families'][0]['id'])
    assert choose_tier('extract', {}) == ('luna', 'bounded_literal_transcription')
    assert choose_tier('extract', {'poor_image': True})[0] == 'sol'
    assert choose_tier('unit', {})[0] == 'sol'
    with DB() as db:
        cfg = db.get(ProviderConfig, 1)
        with pytest.raises(HTTPException) as raised:
            select_route(cfg, 'coach', {'uncertain': 2, 'errors': 3})
        assert raised.value.status_code == 503  # Missing Astra cannot silently use Sol.
        job = Job(child_id=child['id'], kind='unit', payload={}, idempotency='route-guard-001')
        db.add(job)
        db.flush()
        usage = reserve(db, db.get(Family, parent['families'][0]['id']), child['id'], job.id, 'unit')
        assert usage.model == 'openai/gpt-6.1-sol' and usage.route_snapshot['tier'] == 'sol'
        cfg.routing_policy = {**cfg.routing_policy, 'revision': 'changed-policy'}
        with pytest.raises(HTTPException) as raised:
            job_config(db, job)
        assert raised.value.status_code == 409


def test_invalid_or_stale_route_cannot_be_enabled(api, household):
    value = policy()
    value['routes']['sol']['model'] = value['routes']['luna']['model']
    with pytest.raises(ValidationError):
        RoutingPolicy.model_validate(value)
    value = policy()
    value['routes']['luna']['reasoning'] = 'low'
    with pytest.raises(ValidationError):
        RoutingPolicy.model_validate(value)
    parent, child = household
    fid = parent['families'][0]['id']
    setup_policy(fid)
    with DB.begin() as db:
        cfg = db.get(ProviderConfig, 1)
        value = deepcopy(cfg.routing_policy)
        value['routes']['sol']['under13_approved'] = False
        cfg.routing_policy = value
    with DB() as db, pytest.raises(HTTPException) as raised:
        reserve(db, db.get(Family, fid), child['id'], uid(), 'unit')
    assert raised.value.status_code == 503 and 'Datenschutz' in raised.value.detail


def test_parallel_child_budget_and_same_job_are_atomic(api, household):
    parent, child = household
    fid = parent['families'][0]['id']
    setup_policy(fid, hard=45000)  # Two Sol reservations of EUR 0.0216 each.
    def one(job_id):
        try:
            with DB.begin() as db:
                return reserve(db, db.get(Family, fid), child['id'], job_id, 'unit').id
        except HTTPException as e:
            return e.status_code
    shared = uid()
    with ThreadPoolExecutor(max_workers=4) as pool:
        duplicate = list(pool.map(one, [shared] * 4))
    assert len(set(duplicate)) == 1 and isinstance(duplicate[0], str)
    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(one, [uid() for _ in range(4)]))
    assert sum(isinstance(v, str) for v in results) == 1
    assert results.count(429) == 3
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 2
        bucket = db.scalar(select(ChildCostBucket))
        assert (bucket.calls, bucket.encumbered_eur_micros, bucket.unknown_calls) == (2, 43200, 2)


def test_billed_invalid_output_is_counted_once_and_fee_receipts_are_separate(api, household):
    parent, child = household
    fid = parent['families'][0]['id']
    setup_policy(fid)
    with DB.begin() as db:
        db.add(CreditPurchase(id='synthetic-receipt', credits_micros=100000, fee_micros=5500))
        db.flush()
        usage = reserve(db, db.get(Family, fid), child['id'], uid(), 'unit')
        result = Result({}, 100, 200, 10000, telemetry={'reasoning_tokens': 50}, cost_source='reported')
        settle(db, usage, result, failed=True)
        settle(db, usage, result, failed=True)
    with DB() as db:
        usage = db.scalar(select(Usage))
        assert usage.status == 'failed_billed' and usage.cost_micros == 10000
        assert usage.allocated_fee_micros == 550 and usage.charged_eur_micros == 10550
        bucket = db.get(ChildCostBucket, usage.child_budget_id)
        assert bucket.calls == 1 and bucket.encumbered_eur_micros == 10550 and bucket.unknown_calls == 0
        receipt = db.get(CreditPurchase, 'synthetic-receipt')
        assert receipt.consumed_micros == 10000 and receipt.allocated_fee_micros == 550
        assert db.get(UsageBucket, usage.bucket_ids[0]).known_cost_micros == 10000


def test_missing_usage_or_fee_receipt_keeps_hold(api, household):
    parent, child = household
    fid = parent['families'][0]['id']
    setup_policy(fid)
    with DB.begin() as db:
        usage = reserve(db, db.get(Family, fid), child['id'], uid(), 'unit')
        settle(db, usage, Result({}, 100, 200, None, cost_source='unknown'), failed=True)
    with DB() as db:
        usage = db.scalar(select(Usage))
        assert usage.cost_micros is None
        assert db.get(UsageBucket, usage.bucket_ids[0]).encumbered_micros == 20000
        assert db.get(ChildCostBucket, usage.child_budget_id).encumbered_eur_micros == 21600
    with DB.begin() as db:
        usage = reserve(db, db.get(Family, fid), child['id'], uid(), 'unit')
        settle(db, usage, Result({}, 100, 200, 10000, cost_source='reported'))
        assert usage.charged_eur_micros is None  # A missing receipt is not zero fees.


def test_fee_allocation_cumulative_rounding_and_unused_credit(api):
    with DB.begin() as db:
        db.add(CreditPurchase(id='synthetic-tiny-receipt', credits_micros=3, fee_micros=2))
        db.flush()
        assert [allocate_fee(db, 1) for _ in range(3)] == [0, 1, 1]
        assert allocate_fee(db, 1) is None


def test_usage_does_not_double_count_reasoning_and_ignores_private_metadata():
    result = response_metrics({'id': 'gen-test-001', 'provider': 'Azure', 'model': 'openai/gpt-6-luna',
        'secret': 'private', 'usage': {'cost': '0.00000001', 'prompt_tokens': 100,
            'completion_tokens': 200, 'completion_tokens_details': {'reasoning_tokens': 50}}}, 123)
    assert result['cost_micros'] == 1 and result['output_tokens'] == 200
    assert result['telemetry']['reasoning_tokens'] == 50 and 'private' not in str(result)
    assert response_metrics({'usage': {}}, 0)['cost_micros'] is None


def test_openrouter_payload_locks_privacy_model_and_reasoning_and_accounts_invalid_json(api, household, monkeypatch):
    parent, _ = household
    setup_policy(parent['families'][0]['id'])
    calls = []
    class Client:
        def __init__(self, **kwargs): pass
        def __enter__(self): return self
        def __exit__(self, *args): pass
        def post(self, url, *, headers, json):
            assert headers['X-OpenRouter-Cache'] == 'false'
            calls.append((url, json))
            return httpx.Response(200, json={'id': 'gen-artificial-001', 'model': json['model'], 'provider': 'Azure',
                'usage': {'prompt_tokens': 100, 'completion_tokens': 20, 'cost': .00002},
                'choices': [{'finish_reason': 'stop', 'message': {'content': 'invalid JSON'}}]})
    monkeypatch.setattr(providers.httpx, 'Client', Client)
    with DB() as db:
        cfg = select_route(db.get(ProviderConfig, 1), 'unit')
    with pytest.raises(ProviderError) as raised:
        providers.request_provider(cfg, 'unit', {'material': {'content': 'Synthetic confirmed material'}})
    assert raised.value.billing_result.cost_micros == 20
    url, body = calls[0]
    assert url == 'https://openrouter.ai/api/v1/chat/completions'
    assert body['model'] == 'openai/gpt-6.1-sol'
    assert body['reasoning'] == {'effort': 'medium', 'exclude': True}
    assert body['provider']['only'] == ['azure']
    assert body['provider']['allow_fallbacks'] is False and body['provider']['zdr'] is True
    assert body['provider']['data_collection'] == 'deny' and body['provider']['require_parameters'] is True
    assert not any(k in body for k in ('tools', 'plugins', 'audio'))


def test_paid_operator_probe_uses_fixed_templates_is_metered_and_does_not_approve_astra(api, household, monkeypatch):
    from schulpilot import operator_probe
    from schulpilot.db import OperatorJob

    parent, _ = household
    setup_policy(parent['families'][0]['id'])
    object.__setattr__(settings, 'synthetic_ai_enabled', True)
    calls = []
    def fixed(config, function, payload, **kwargs):
        assert kwargs == {'synthetic_fixture': True, 'private_probe': True}
        assert payload == {}
        calls.append((function, config.model))
        return Result({}, 100, 50, 1000, telemetry={'upstream': 'Azure'}, cost_source='reported')
    monkeypatch.setattr(operator_probe, 'request_provider', fixed)
    with DB() as db:
        job_id = operator_probe.enqueue('synthetic-operator', db)['id']
    assert operator_probe.work_one()
    with DB() as db:
        job = db.get(OperatorJob, job_id)
        assert job.status == 'completed'
        assert len(job.report) == 3 and all(r['available'] for r in job.report)
        assert sum(r['cost_micros_usd'] for r in job.report) == 3000
        assert db.get(UsageBucket, 'routing-probe:' + job_id).encumbered_micros == 3000
        assert db.get(ProviderConfig, 1).production_block_reason == ''
    assert calls == [('extract', 'openai/gpt-6-luna'), ('unit', 'openai/gpt-6.1-sol'), ('package', 'openai/gpt-6.1-sol')]


def test_chargeable_invalid_operator_output_is_not_a_success(api, household, monkeypatch):
    from schulpilot import operator_probe
    from schulpilot.db import OperatorJob

    parent, _ = household
    setup_policy(parent['families'][0]['id'])
    object.__setattr__(settings, 'synthetic_ai_enabled', True)
    def invalid(*args, **kwargs):
        raise ProviderError('Synthetic invalid schema', billing_result=Result({}, 100, 20, 1000, cost_source='reported'))
    monkeypatch.setattr(operator_probe, 'request_provider', invalid)
    with DB() as db:
        job_id = operator_probe.enqueue('synthetic-operator', db)['id']
    operator_probe.work_one()
    with DB() as db:
        job = db.get(OperatorJob, job_id)
        assert job.status == 'failed' and not any(r['available'] for r in job.report)
        assert all(r['cost_micros_usd'] == 1000 for r in job.report)
        assert db.get(UsageBucket, 'routing-probe:' + job_id).known_cost_micros == 3000
        assert db.get(ProviderConfig, 1).production_block_reason


def test_local_switch_needs_server_key_and_preserves_stricter_limits(api, household, monkeypatch):
    import io
    import json

    from schulpilot import openrouter_setup

    parent, _ = household
    fid = parent['families'][0]['id']
    configured(fid)
    document = json.dumps({'policy': policy(), 'evidence': 'Synthetic explicit operator switch for a local test.'})
    monkeypatch.setattr('sys.stdin', io.StringIO(document))
    with pytest.raises(SystemExit):
        openrouter_setup.configure()
    object.__setattr__(settings, 'openrouter_api_key', 'SYNTHETIC-NOT-A-REAL-KEY')
    monkeypatch.setattr('sys.stdin', io.StringIO(document))
    openrouter_setup.configure()
    with DB() as db:
        cfg = db.get(ProviderConfig, 1)
        assert cfg.provider == 'openrouter' and cfg.reasoning_effort == 'medium'
        assert cfg.global_limit_micros == 1000000 and cfg.reserve_micros == 1000
        assert cfg.production_block_reason
        assert db.get(Family, fid).call_limit == 3 and db.get(Family, fid).budget_micros == 3000
