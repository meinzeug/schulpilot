"""Interleaved asset expiry/publication and late financial receipts, no network."""
import copy
import threading
from concurrent.futures import ThreadPoolExecutor

import httpx
import pytest
from schulpilot import ai_accounting, learning_assets, providers, worker
from schulpilot.db import DB, Job, Usage, UsageBucket, now
from schulpilot.learning_asset_models import LearningAssetBuild
from schulpilot.learning_assets import process, reap_interrupted
from schulpilot.providers import ProviderError, Result
from schulpilot.visual_reference_models import VisualReference
from sqlalchemy import select
from sqlalchemy.orm import Session as SQLSession
from sqlalchemy.sql.dml import Update
from test_learning_assets import output, start
from test_learning_assets import prepared as prepared


def running(api, prepared):
    _, child, _ = prepared
    instance = start(api, child["id"]).json()
    with DB.begin() as db:
        build = db.get(LearningAssetBuild, instance["build"]["build_key"])
        job = db.get(Job, build.job_id)
        job.status, job.started = "running", int(now()) - 300
        job_id = job.id
    return instance, job_id


def buckets(db):
    return {row.id: (row.calls, row.encumbered_micros, row.known_cost_micros, row.unknown_calls)
            for row in db.scalars(select(UsageBucket))}


@pytest.mark.parametrize("failure", [False, True])
def test_reaper_wins_late_call_keeps_actual_generation_id_for_existing_price_reconciliation(api, prepared, monkeypatch, failure):
    instance, job_id = running(api, prepared)
    calls = []
    def response(*args, **kwargs):
        calls.append(True)
        assert reap_interrupted() == 1  # No DB locks span this provider boundary.
        with DB() as db:
            usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
            assert usage.status == "failed_unknown" and usage.settlement_version == 1
        result = Result(output(), 22, 33, 12, cost_source="reported", telemetry={
            "generation_id": "gen-artificial-late", "request_id": "request-artificial", "billed_usd": "0.000012",
            "reasoning_tokens": 5, "debug_private_source": "must not persist", "cached_tokens": True})
        if failure:
            raise ProviderError("Synthetic output rejection", billing_result=result)
        return result
    monkeypatch.setattr(providers, "request_provider", response)
    process(job_id)
    with DB() as db:
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        assert db.get(Job, job_id).status == "failed"
        assert db.get(LearningAssetBuild, instance["build"]["build_key"]).status == "failed"
        assert db.query(VisualReference).filter(VisualReference.id.like("generated.%")).count() == 0
        assert usage.status == "failed_unknown" and usage.cost_micros is None and usage.settlement_version == 1
        assert usage.telemetry["generation_id"] == "gen-artificial-late"
        assert usage.telemetry["reasoning_tokens"] == 5 and usage.telemetry["late_input_tokens"] == 22
        assert "debug_private_source" not in usage.telemetry and "cached_tokens" not in usage.telemetry
        assert all(row[1] == usage.reserved_micros for row in buckets(db).values())
    assert reap_interrupted() == 0 and calls == [True]
    requests = []
    def generation(url, **kwargs):
        requests.append((url, kwargs["params"]))
        return httpx.Response(200, json={"data": {"id": "gen-artificial-late", "total_cost": "0.000012",
            "tokens_prompt": 22, "tokens_completion": 33}})
    monkeypatch.setattr(httpx, "get", generation)
    assert ai_accounting.reconcile_one() is True
    with DB() as db:
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        assert usage.cost_source == "generation" and usage.cost_micros == 12
        assert usage.status == "failed_billed" and usage.settlement_version == 1
        assert db.get(Job, job_id).status == "failed"
        assert db.get(LearningAssetBuild, instance["build"]["build_key"]).status == "failed"
        after = buckets(db)
    ai_accounting.reconcile_one()
    with DB() as db:
        assert buckets(db) == after
    assert len(requests) == 1 and requests[0][1] == {"id": "gen-artificial-late"}
    assert calls == [True]  # A metadata GET is never a second inference.


def test_publisher_wins_after_reaper_id_snapshot_and_is_not_expired_after_wait(api, prepared, monkeypatch):
    instance, job_id = running(api, prepared)
    waiting, release = threading.Event(), threading.Event()
    original = SQLSession.execute
    def execute(self, statement, *args, **kwargs):
        if (threading.current_thread().name.startswith("asset-reaper") and isinstance(statement, Update)
                and statement.table.name == "children" and not waiting.is_set()):
            waiting.set()
            assert release.wait(10), "Publisher did not complete while reaper had no lock"
        return original(self, statement, *args, **kwargs)
    monkeypatch.setattr(SQLSession, "execute", execute)
    with ThreadPoolExecutor(max_workers=1, thread_name_prefix="asset-reaper") as pool:
        expired = pool.submit(reap_interrupted)
        assert waiting.wait(10), "Reaper did not capture its candidate"
        try:
            process(job_id)
            with DB() as db:
                assert db.get(Job, job_id).status == "completed"
                usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
                saved = usage.status, usage.settlement_version, copy.deepcopy(usage.telemetry), buckets(db)
        finally:
            release.set()
        assert expired.result(timeout=10) == 0
    with DB() as db:
        assert db.get(Job, job_id).status == "completed"
        assert db.get(LearningAssetBuild, instance["build"]["build_key"]).status == "ready"
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        assert (usage.status, usage.settlement_version, usage.telemetry, buckets(db)) == saved


def test_generic_maintenance_cannot_reap_an_asset_in_its_unordered_transaction(api, prepared, monkeypatch):
    _, job_id = running(api, prepared)
    calls = []
    monkeypatch.setattr(learning_assets, "reap_interrupted", lambda: calls.append(True))
    with DB.begin() as db:
        job = db.get(Job, job_id)
        normal = Job(child_id=job.child_id, kind="unit", payload={}, status="running", started=int(now()) - 300,
                     idempotency="synthetic-generic-job")
        db.add(normal)
        db.flush()
        normal_id = normal.id
    worker.maintenance()
    with DB() as db:
        assert db.get(Job, job_id).status == "running"
        assert db.get(Job, normal_id).status == "failed"
    assert calls == [True]


@pytest.mark.parametrize("change", ["generation", "tokens", "cost"])
def test_late_receipt_drops_malformed_metadata_without_touching_financial_state(api, prepared, change):
    _, job_id = running(api, prepared)
    assert reap_interrupted() == 1
    raw = {"generation_id": "gen-artificial", "billed_usd": "0.000001", "reasoning_tokens": 3,
           "secret": "never stored"}
    if change == "generation":
        raw["generation_id"] = "<script>private</script>"
    elif change == "tokens":
        raw["reasoning_tokens"] = True
    else:
        raw["billed_usd"] = "NaN"
    with DB.begin() as db:
        job = db.get(Job, job_id)
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        old = usage.status, usage.settlement_version, usage.cost_micros, buckets(db)
        learning_assets.remember_late_receipt(db, job, Result({}, -1, True, None, telemetry=raw))
        assert (usage.status, usage.settlement_version, usage.cost_micros, buckets(db)) == old
        assert "secret" not in usage.telemetry and "late_input_tokens" not in usage.telemetry and "late_output_tokens" not in usage.telemetry
        if change == "generation":
            assert "generation_id" not in usage.telemetry
        elif change == "tokens":
            assert "reasoning_tokens" not in usage.telemetry
        else:
            assert "billed_usd" not in usage.telemetry
