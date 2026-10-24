"""Synthetic financial boundaries, no inference or real billing requests."""

from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

import httpx
import pytest
from fastapi import HTTPException
from schulpilot import child_cost_controls as costs
from schulpilot.ai_accounting import reconcile_one, settle_child
from schulpilot.child_cost_models import ChildCostControl, ChildCostControlChange, UsageCostBalance
from schulpilot.db import (
    DB,
    Audit,
    Child,
    ChildCostBucket,
    CreditPurchase,
    Family,
    ProviderConfig,
    Usage,
    UsageBucket,
    User,
    uid,
)
from schulpilot.job_failures import generation_availability
from schulpilot.providers import Result, reserve, settle
from sqlalchemy import func, select
from test_codex_models import operator as operator_fixture
from test_model_routing import setup_policy


@pytest.fixture
def operator():
    yield from operator_fixture.__wrapped__()


def configure(api, household, operator, *, day=100_000, month=500_000, revision=0, enabled=True,
              zone="Europe/Berlin", key="cost-control-request-0001"):
    parent, child = household
    if revision == 0:
        setup_policy(parent["families"][0]["id"])
    response = operator.put(f"/api/admin/children/{child['id']}/cost-controls",
        headers={"Idempotency-Key": key}, json={"revision": revision, "enabled": enabled, "timezone": zone,
            "daily_limit_eur_micros": day, "monthly_limit_eur_micros": month})
    assert response.status_code == 200, response.text
    return response.json()


def claim(fid, child_id, job_id=None, *, function="unit"):
    with DB.begin() as db:
        usage = reserve(db, db.get(Family, fid), child_id, job_id or uid(), function)
        return usage.id


def test_default_is_legacy_and_reads_do_not_write_or_reveal_learning(api, household, operator):
    parent, child = household
    setup_policy(parent["families"][0]["id"])
    with DB() as db:
        before = db.scalar(select(func.count()).select_from(Audit))
    for url in ("/api/admin/child-cost-controls?limit=1&query=test-child",
                f"/api/admin/children/{child['id']}/cost-controls"):
        response = operator.get(url)
        assert response.status_code == 200, response.text
        assert not any(key in response.text for key in ('"questions"', '"answers"', '"materials"', '"content"'))
        value = response.json().get("items", [response.json()])[0]
        assert value["mode"] == "legacy" and value["revision"] == 0
        assert value["effective_limits"]["legacy_family_and_routing_caps_apply"]
        assert value["legacy_effective"]["family"]["limit_usd_micros"] == 1_000_000
        assert value["legacy_effective"]["route_child"]["limit_eur_micros"] == 12_000_000
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(ChildCostControl)) == 0
        assert db.scalar(select(func.count()).select_from(UsageCostBalance)) == 0
        assert db.scalar(select(func.count()).select_from(Audit)) == before
    assert api.get(f"/api/admin/children/{child['id']}/cost-controls").status_code == 403


def test_explicit_unlimited_replaces_only_family_and_old_child_caps(api, household, operator):
    parent, child = household
    fid = parent["families"][0]["id"]
    value = configure(api, household, operator, day=None, month=None)
    assert value["mode"] == "configured" and value["day"]["state"] == "unlimited"
    with DB.begin() as db:
        family = db.get(Family, fid)
        family.call_limit = family.budget_micros = 0
        cfg = db.get(ProviderConfig, 1)
        cfg.routing_policy = {**cfg.routing_policy, "budget": {**cfg.routing_policy["budget"],
            "target_eur_micros": 0, "warning_eur_micros": 0, "hard_eur_micros": 0}}
    ident = claim(fid, child["id"])
    with DB() as db:
        usage = db.get(Usage, ident)
        assert usage.child_budget_id is None
        balance = db.get(UsageCostBalance, ident)
        assert balance.held_eur_micros == 20_000 and balance.fee_reserved_eur_micros == 1_600
        assert balance.accounted_eur_micros == 21_600
        assert db.get(UsageBucket, usage.bucket_ids[1]).calls == 1
        assert generation_availability(db, db.get(Family, fid), "unit", child_id=child["id"]) is None
    with DB.begin() as db:
        db.get(ProviderConfig, 1).global_limit_micros = 20_000
    with pytest.raises(HTTPException) as raised:
        claim(fid, child["id"])
    assert raised.value.status_code == 429
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 1


def test_explicit_unlimited_with_already_exhausted_family_and_12eur_counter(api, household, operator):
    from datetime import timezone

    parent, child = household
    fid = parent["families"][0]["id"]
    setup_policy(fid)
    period = datetime.now(timezone.utc).strftime("%Y-%m")
    with DB.begin() as db:
        family = db.get(Family, fid)
        family.call_limit, family.budget_micros = 10_000, 2_000_000
        db.add(UsageBucket(id=f"{fid}:{period}", calls=10_000, encumbered_micros=2_000_000,
            known_cost_micros=400_000, unknown_calls=102))
        db.add(ChildCostBucket(id=child["id"] + ":" + period, child_id=child["id"], period=period,
            calls=100, encumbered_eur_micros=12_000_000, known_eur_micros=400_000, unknown_calls=100))
    with pytest.raises(HTTPException) as blocked:
        claim(fid, child["id"])
    assert blocked.value.status_code == 429
    # Configure explicitly through the authenticated audited admin API; never
    # infer unlimited from absent limits on an unconfigured account.
    value = operator.put(
        f"/api/admin/children/{child['id']}/cost-controls", headers={"Idempotency-Key": "unlimited-exhausted-account"},
        json={"revision": 0, "enabled": True, "timezone": "Europe/Berlin", "daily_limit_eur_micros": None,
            "monthly_limit_eur_micros": None})
    assert value.status_code == 200, value.text
    ident = claim(fid, child["id"])
    with DB() as db:
        usage = db.get(Usage, ident)
        assert usage.child_budget_id is None and usage.route_snapshot["child_cost_control"]["enabled"]
        assert db.get(UsageBucket, f"{fid}:{period}").calls == 10_001
        assert db.get(ChildCostBucket, child["id"] + ":" + period).encumbered_eur_micros == 12_000_000
        assert generation_availability(db, db.get(Family, fid), "unit", child_id=child["id"]) is None


@pytest.mark.parametrize("day,month", [(0, None), (None, 0), (21_599, None), (None, 21_599)])
def test_day_and_month_are_independently_authoritative(api, household, operator, day, month):
    parent, child = household
    configure(api, household, operator, day=day, month=month)
    with pytest.raises(HTTPException) as raised:
        claim(parent["families"][0]["id"], child["id"])
    assert raised.value.status_code == 429
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
        assert db.scalar(select(func.sum(UsageBucket.calls))) in (None, 0)
        blocker = generation_availability(db, db.get(Family, parent["families"][0]["id"]), "unit", child_id=child["id"])
        assert blocker["code"] == "quota_exhausted"


def test_parallel_money_claims_and_replays_are_atomic(api, household, operator):
    parent, child = household
    configure(api, household, operator, day=43_200, month=None)
    fid = parent["families"][0]["id"]
    shared = uid()
    with ThreadPoolExecutor(max_workers=4) as pool:
        replay = list(pool.map(lambda _: claim(fid, child["id"], shared), range(4)))
    assert len(set(replay)) == 1
    def one(_):
        try:
            return claim(fid, child["id"])
        except HTTPException as error:
            return error.status_code
    with ThreadPoolExecutor(max_workers=4) as pool:
        values = list(pool.map(one, range(4)))
    assert sum(isinstance(value, str) for value in values) == 1 and values.count(429) == 3
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 2
        value = costs.projection(db, db.get(Child, child["id"]))
        assert value["day"]["accounted_eur_micros"] == 43_200
        assert value["day"]["unknown_calls"] == 2


def test_known_provider_cost_releases_full_hold_without_fabricating_zero_fee(api, household, operator):
    parent, child = household
    configure(api, household, operator)
    ident = claim(parent["families"][0]["id"], child["id"])
    with DB.begin() as db:
        usage = db.get(Usage, ident)
        settle(db, usage, Result({}, 10, 20, 2_000, cost_source="reported"))
    with DB() as db:
        balance = db.get(UsageCostBalance, ident)
        assert (balance.provider_eur_micros, balance.fee_known_eur_micros,
            balance.fee_reserved_eur_micros, balance.held_eur_micros, balance.accounted_eur_micros) == (2000, None, 160, 0, 2160)
        assert db.get(Usage, ident).charged_eur_micros is None
        value = costs.projection(db, db.get(Child, child["id"]))["day"]
        assert value["unknown_calls"] == 0 and value["known_provider_eur_micros"] == 2_000
        assert value["remaining_eur_micros"] == 97_840
    with DB.begin() as db:
        db.add(CreditPurchase(id="synthetic-cost-receipt", credits_micros=10_000, fee_micros=500))
        db.flush()
        settle_child(db, db.get(Usage, ident))
        settle_child(db, db.get(Usage, ident))
    with DB() as db:
        balance = db.get(UsageCostBalance, ident)
        assert (balance.fee_state, balance.fee_known_eur_micros, balance.fee_reserved_eur_micros) == ("actual", 100, 0)
        receipt = db.get(CreditPurchase, "synthetic-cost-receipt")
        assert receipt.consumed_micros == 2000 and receipt.allocated_fee_micros == 100


def test_legacy_known_cost_also_releases_full_generation_reserve(api, household):
    parent, child = household
    fid = parent["families"][0]["id"]
    setup_policy(fid)
    ident = claim(fid, child["id"])
    with DB.begin() as db:
        settle(db, db.get(Usage, ident), Result({}, 10, 20, 2_000, cost_source="reported"))
    with DB() as db:
        usage = db.get(Usage, ident)
        bucket = db.get(ChildCostBucket, usage.child_budget_id)
        assert bucket.encumbered_eur_micros == 2160 and bucket.known_eur_micros == 2000 and bucket.unknown_calls == 0
        assert usage.charged_eur_micros is None
    with DB.begin() as db:
        db.add(CreditPurchase(id="legacy-fee", credits_micros=2000, fee_micros=100))
        db.flush()
        settle_child(db, db.get(Usage, ident))
        settle_child(db, db.get(Usage, ident))
    with DB() as db:
        usage = db.get(Usage, ident)
        bucket = db.get(ChildCostBucket, usage.child_budget_id)
        assert bucket.encumbered_eur_micros == bucket.known_eur_micros == 2100
        assert bucket.unknown_calls == 0 and usage.charged_eur_micros == 2100


def test_cas_idempotency_and_big_integer_limits(api, household, operator):
    _, child = household
    value = configure(api, household, operator, day=1_000_000_000_000, month=None)
    assert value["daily_limit_eur_micros"] == 1_000_000_000_000
    same = configure(api, household, operator, day=1_000_000_000_000, month=None)
    assert same["revision"] == 1
    url = f"/api/admin/children/{child['id']}/cost-controls"
    body = {key: value[key] for key in costs.PolicyUpdate.model_fields}
    assert operator.put(url, headers={"Idempotency-Key": "other-new-request-000"}, json={**body, "revision": 0}).status_code == 409
    assert operator.put(url, headers={"Idempotency-Key": "cost-control-request-0001"}, json={**body, "revision": 0, "enabled": False}).status_code == 409
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(ChildCostControlChange)) == 1
        assert db.scalar(select(func.count()).select_from(Audit).where(Audit.action == "child_cost_control_changed")) == 1


@pytest.mark.parametrize("field,value", [("daily_limit_eur_micros", -1), ("daily_limit_eur_micros", True),
    ("monthly_limit_eur_micros", 1.5), ("monthly_limit_eur_micros", 1_000_000_000_001),
    ("enabled", "true"), ("timezone", "Mars/Invented")])
def test_strict_policy_validation(api, household, operator, field, value):
    _, child = household
    body = {"revision": 0, "enabled": True, "timezone": "Europe/Berlin", "daily_limit_eur_micros": None,
        "monthly_limit_eur_micros": None, field: value}
    response = operator.put(f"/api/admin/children/{child['id']}/cost-controls", json=body,
        headers={"Idempotency-Key": "invalid-cost-policy-request"})
    assert response.status_code == 422


@pytest.mark.parametrize("stamp,hours,day", [("2026-03-29T12:00:00+00:00", 23, "2026-03-29"),
    ("2026-10-25T12:00:00+00:00", 25, "2026-10-25")])
def test_local_calendar_days_handle_dst(stamp, hours, day):
    windows = costs.windows("Europe/Berlin", datetime.fromisoformat(stamp).timestamp())
    assert windows["day"][0] == day and windows["day"][2] - windows["day"][1] == hours * 3600


def test_reported_price_is_verified_with_metadata_only_and_corrected_once(api, household, operator, monkeypatch):
    parent, child = household
    configure(api, household, operator)
    ident = claim(parent["families"][0]["id"], child["id"])
    with DB.begin() as db:
        settle(db, db.get(Usage, ident), Result({}, 10, 20, 2000, cost_source="reported", telemetry={"generation_id": "gen-cost-synthetic"}))
    calls = []
    def metadata(url, **kwargs):
        assert url == "https://openrouter.ai/api/v1/generation" and kwargs["params"] == {"id": "gen-cost-synthetic"}
        assert kwargs["follow_redirects"] is False
        calls.append(url)
        return httpx.Response(200, json={"data": {"id": "gen-cost-synthetic", "total_cost": "0.0015", "tokens_prompt": 10, "tokens_completion": 20}})
    monkeypatch.setattr(httpx, "get", metadata)
    assert reconcile_one() is True and reconcile_one() is False
    assert len(calls) == 1
    with DB() as db:
        usage = db.get(Usage, ident)
        assert usage.cost_micros == 1500 and usage.cost_source == "generation"
        assert usage.telemetry["reported_cost_micros"] == 2000
        assert usage.telemetry["cost_receipt_state"] == "verified_generation"
        assert db.get(UsageBucket, usage.bucket_ids[0]).known_cost_micros == 1500
        balance = db.get(UsageCostBalance, ident)
        assert balance.provider_eur_micros == 1500 and balance.accounted_eur_micros == 1620


def test_metadata_failures_keep_known_cost_and_bounded_retry_without_inference(api, household, operator, monkeypatch):
    parent, child = household
    configure(api, household, operator)
    ident = claim(parent["families"][0]["id"], child["id"])
    with DB.begin() as db:
        settle(db, db.get(Usage, ident), Result({}, 1, 2, 2000, cost_source="reported", telemetry={"generation_id": "gen-retry-synthetic"}))
    calls = []
    monkeypatch.setattr(httpx, "get", lambda *a, **kw: (calls.append(kw), httpx.Response(503))[1])
    for index in range(3):
        assert reconcile_one() is True
        with DB.begin() as db:
            usage = db.get(Usage, ident)
            assert usage.cost_micros == 2000
            usage.telemetry = {**usage.telemetry, "reconcile_after": 0}
    assert reconcile_one() is False and len(calls) == 3
    response = operator.post(f"/api/admin/usage/{ident}/refresh-cost", headers={"Idempotency-Key": "refresh-known-cost-0001"})
    assert response.status_code == 200 and response.json()["status"] == "queued"
    assert operator.post(f"/api/admin/usage/{ident}/refresh-cost", headers={"Idempotency-Key": "refresh-known-cost-0001"}).status_code == 200
    assert reconcile_one() is True and len(calls) == 4
    detail = operator.get(f"/api/admin/children/{child['id']}/cost-calls").json()["items"][0]
    assert detail["provider_usd_micros"] == 2000 and detail["receipt_state"] == "reported"
    assert not any(key in detail for key in ("job_id", "material_id", "question", "answer", "content"))


def test_known_fee_discrepancy_is_explicit_and_never_double_allocates(api, household, operator, monkeypatch):
    parent, child = household
    configure(api, household, operator)
    ident = claim(parent["families"][0]["id"], child["id"])
    with DB.begin() as db:
        db.add(CreditPurchase(id="adjustment-receipt", credits_micros=10_000, fee_micros=500))
        db.flush()
        settle(db, db.get(Usage, ident), Result({}, 1, 2, 2000, cost_source="reported", telemetry={"generation_id": "gen-adjustment-synthetic"}))
    monkeypatch.setattr(httpx, "get", lambda *a, **kw: httpx.Response(200, json={"data": {"id": "gen-adjustment-synthetic", "total_cost": "0.001"}}))
    assert reconcile_one() is True
    with DB.begin() as db:
        usage = db.get(Usage, ident)
        settle_child(db, usage)
    with DB() as db:
        balance = db.get(UsageCostBalance, ident)
        assert balance.fee_state == "adjustment_pending" and balance.fee_known_eur_micros is None
        assert balance.fee_reserved_eur_micros == 100 and balance.provider_eur_micros == 1000
        assert db.get(CreditPurchase, "adjustment-receipt").consumed_micros == 2000
        assert db.get(Usage, ident).charged_eur_micros is None


def test_fx_is_frozen_per_call_and_policy_edits_do_not_reset_spending(api, household, operator):
    parent, child = household
    configure(api, household, operator)
    ident = claim(parent["families"][0]["id"], child["id"])
    with DB.begin() as db:
        cfg = db.get(ProviderConfig, 1)
        cfg.routing_policy = {**cfg.routing_policy, "budget": {**cfg.routing_policy["budget"], "eur_per_usd": "2"}}
    value = configure(api, household, operator, revision=1, day=1_000_000, month=None, key="cost-fx-new-revision-0002")
    assert value["day"]["accounted_eur_micros"] == 21_600
    with DB() as db:
        assert db.get(UsageCostBalance, ident).fx_snapshot["eur_per_usd"] == "1"
    second = claim(parent["families"][0]["id"], child["id"])
    with DB() as db:
        assert db.get(UsageCostBalance, second).accounted_eur_micros == 43_200


def test_local_day_rollover_keeps_monthly_spending_and_no_get_mutations(api, household, operator, monkeypatch):
    parent, child = household
    configure(api, household, operator, day=30_000, month=40_000)
    ident = claim(parent["families"][0]["id"], child["id"])
    stamp = datetime.fromisoformat("2026-10-12T12:00:00+00:00").timestamp()
    with DB.begin() as db:
        db.get(Usage, ident).created = int(stamp - 86400)
    monkeypatch.setattr(costs, "now", lambda: stamp)
    with DB() as db:
        value = costs.projection(db, db.get(Child, child["id"]))
        assert value["day"]["calls"] == 0 and value["month"]["calls"] == 1
        assert value["month"]["accounted_eur_micros"] == 21_600
        assert not db.dirty and not db.new
    with pytest.raises(HTTPException) as raised:
        claim(parent["families"][0]["id"], child["id"])
    assert raised.value.status_code == 429 and "Monatskostenlimit" in raised.value.detail


def test_disabling_policy_restores_legacy_limits_without_erasing_money(api, household, operator):
    parent, child = household
    configure(api, household, operator, day=None, month=None)
    claim(parent["families"][0]["id"], child["id"])
    with DB.begin() as db:
        db.get(Family, parent["families"][0]["id"]).budget_micros = 0
    value = configure(api, household, operator, enabled=False, revision=1, key="disable-cost-controls-0002")
    assert value["mode"] == "legacy" and value["day"]["accounted_eur_micros"] == 21_600
    with pytest.raises(HTTPException) as raised:
        claim(parent["families"][0]["id"], child["id"])
    assert raised.value.status_code == 429


def test_role_revocation_at_child_lock_prevents_configuration_change(api, household, operator, monkeypatch):
    parent, child = household
    setup_policy(parent["families"][0]["id"])
    original = costs.fresh_admin
    def revoked(db, principal):
        db.execute(User.__table__.update().where(User.id == principal.user.id).values(role="parent"))
        original(db, principal)
    monkeypatch.setattr(costs, "fresh_admin", revoked)
    response = operator.put(f"/api/admin/children/{child['id']}/cost-controls", headers={"Idempotency-Key": "revoked-cost-control-0001"},
        json={"revision": 0, "enabled": True, "timezone": "Europe/Berlin", "daily_limit_eur_micros": None, "monthly_limit_eur_micros": None})
    assert response.status_code == 403
    with DB() as db:
        assert db.get(ChildCostControl, child["id"]) is None
        assert db.scalar(select(func.count()).select_from(ChildCostControlChange)) == 0


def test_cost_rows_are_exported_and_cascade_with_original_child(api, household, operator):
    parent, child = household
    configure(api, household, operator)
    claim(parent["families"][0]["id"], child["id"])
    with DB.begin() as db:
        value = costs.export_child(db, child["id"])
        assert value["policy"]["revision"] == 1 and len(value["changes"]) == len(value["balances"]) == 1
        db.delete(db.get(Child, child["id"]))
    with DB() as db:
        for table in (ChildCostControl, ChildCostControlChange, UsageCostBalance):
            assert db.scalar(select(func.count()).select_from(table)) == 0
