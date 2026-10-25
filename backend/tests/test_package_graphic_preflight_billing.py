"""Closed graphic-preflight cancellation versus actually dispatched requests.

Full adapters and the normal worker run only on artificial RAM-backed families.
All HTTP is intercepted; no provider or private production data is used.
"""
import copy

import httpx
import pytest
from schulpilot import package_part_output, providers, school_preparation, worker
from schulpilot.db import DB, Activity, Attempt, Job, LearningUnit, Usage, UsageBucket
from sqlalchemy import func, select
from test_package_parts_worker import artificial_day
from test_package_prepared_graphics import payload_for
from test_package_transport import config

MISSING = (
    "Der Teilauftrag hat keine passende Referenz/Grafik für seine Aufdeckstufe.",
    "Für diesen Teilauftrag ist keine passende Grafik freigegeben.",
)


def transport(monkeypatch, *, reported=False):
    requests, clients = [], []
    real = httpx.Client

    def handle(request):
        requests.append(request)
        body = {"error": {"message": "Synthetic upstream failure", "metadata": {"error_type": "invalid_request"}}}
        if reported:
            body["usage"] = {"prompt_tokens": 7, "completion_tokens": 9, "cost": 0.0123}
        return httpx.Response(400, json=body)

    def client(**_kwargs):
        clients.append(True)
        return real(transport=httpx.MockTransport(handle))

    monkeypatch.setattr(providers.httpx, "Client", client)
    monkeypatch.setattr(providers, "external_allowed", lambda *a, **kw: None)
    monkeypatch.setattr(providers, "decrypt", lambda _: "synthetic-isolated-key")
    return requests, clients


def configured():
    value = config()
    value.max_output_tokens, value.reserve_micros = 8000, 250000
    value.openrouter_require_zdr = True
    return value


def fail_binder(monkeypatch, error):
    reached = []

    def fail(schema, payload):
        assert payload["package_partition"] is not None
        assert schema["properties"]["units"]
        reached.append(True)
        raise error

    monkeypatch.setattr(package_part_output, "bind_schema", fail)
    return reached


@pytest.mark.parametrize("message", MISSING, ids=["missing-disclosure-recipe", "missing-prepared-graphic"])
def test_exact_known_missing_recipe_cancels_before_http_with_zero_billing(monkeypatch, message):
    calls, clients = transport(monkeypatch)
    reached = fail_binder(monkeypatch, ValueError(message))
    payload = payload_for()
    before = copy.deepcopy(payload)
    with pytest.raises(providers.ProviderError) as caught:
        providers.request_provider(configured(), "package", payload)
    error = caught.value
    assert reached == [True] and calls == clients == []
    assert error.code == "invalid_output"
    assert "Fotos und bisherigen Runden bleiben gespeichert" in str(error)
    billed = error.billing_result
    assert billed.cost_source == "cancelled"
    assert (billed.input_tokens, billed.output_tokens, billed.cost_micros) == (0, 0, 0)
    assert billed.data == {} and payload == before


def test_real_unsupported_source_recipe_uses_the_same_free_preflight_path(monkeypatch):
    calls, clients = transport(monkeypatch)
    payload = payload_for("Eine künstliche bestätigte Geschichtsquelle ohne datierte Ereignisse oder sichtbare Pfeilfolge.", "Geschichte")
    payload["visual_context"]["references"] = [r for r in payload["visual_context"]["references"]
        if r["id"] == "general.source_relation.phases"]
    assert payload["visual_context"]["references"]
    with pytest.raises(providers.ProviderError) as caught:
        providers.request_provider(configured(), "package", payload)
    assert caught.value.code == "invalid_output"
    assert caught.value.billing_result.cost_source == "cancelled"
    assert caught.value.billing_result.cost_micros == 0
    assert calls == clients == []


@pytest.mark.parametrize("args", [
    ("SYNTHETIC_UNEXPECTED_BINDER",),
    (MISSING[0] + " ",),
    (MISSING[0], "SYNTHETIC_EXTRA_CONTEXT"),
], ids=["unexpected-error", "near-match-is-not-known", "additional-args-are-not-known"])
def test_unexpected_binder_errors_propagate_without_a_fabricated_zero_receipt(monkeypatch, args):
    calls, clients = transport(monkeypatch)
    problem = ValueError(*args)
    reached = fail_binder(monkeypatch, problem)
    with pytest.raises(ValueError) as caught:
        providers.request_provider(configured(), "package", payload_for())
    assert caught.value is problem and not isinstance(caught.value, providers.ProviderError)
    assert not hasattr(caught.value, "billing_result")
    assert reached == [True] and calls == clients == []


@pytest.mark.parametrize("reported", [False, True], ids=["unknown-charge-keeps-hold", "reported-charge-kept"])
def test_http_error_after_dispatch_is_never_relabelled_as_free_preflight(monkeypatch, reported):
    calls, clients = transport(monkeypatch, reported=reported)
    with pytest.raises(providers.ProviderError) as caught:
        providers.request_provider(configured(), "package", payload_for())
    assert len(calls) == len(clients) == 1
    assert "HTTP 400" in str(caught.value)
    billed = caught.value.billing_result
    assert billed is not None and billed.cost_source != "cancelled"
    if reported:
        assert (billed.input_tokens, billed.output_tokens, billed.cost_micros) == (7, 9, 12300)
        assert billed.cost_source == "reported"
    else:
        assert billed.cost_micros is None and billed.cost_source == "unknown"


@pytest.mark.parametrize("stage", ["known", "unexpected", "dispatched"],
    ids=["known-releases-reservation", "unexpected-keeps-reservation", "dispatched-keeps-reservation"])
def test_real_worker_settles_only_proven_local_missing_recipe_as_not_sent(api, household, monkeypatch, stage):
    day_id, _, old = artificial_day(api, household)
    calls, _ = transport(monkeypatch)
    reached = None
    if stage != "dispatched":
        reached = fail_binder(monkeypatch, ValueError(MISSING[0] if stage == "known" else "SYNTHETIC_UNEXPECTED_BINDER"))
    response = api.post(f"/api/school-days/{day_id}/prepare", headers={
        "Idempotency-Key": "synthetic-graphic-preflight-billing", "X-Schulpilot-Capabilities": "visual-v1"})
    assert response.status_code == 202, response.text
    school_preparation.advance_one()
    with DB() as db:
        job_id = worker.claim(db)
        assert job_id is not None
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        assert usage is not None and usage.status == "reserved"
        held, bucket_ids = usage.reserved_micros, list(usage.bucket_ids)
        assert held > 0
        before = {key: (db.get(UsageBucket, key).calls, db.get(UsageBucket, key).encumbered_micros,
            db.get(UsageBucket, key).unknown_calls, db.get(UsageBucket, key).known_cost_micros) for key in bucket_ids}
    # No request_provider mock: the actual function reaches the actual local
    # binder or the local HTTP transport, then the ordinary worker catch settles.
    assert worker.request_provider is providers.request_provider
    worker.process(job_id)
    with DB() as db:
        job = db.get(Job, job_id)
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        assert job.status == "failed" and usage.settlement_version == 1
        assert "SYNTHETIC_UNEXPECTED_BINDER" not in job.error
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 1
        assert db.scalar(select(func.count()).select_from(Attempt)) == 1
        assert db.get(Attempt, old["attempt"]).answer == "Künstliche Altantwort"
        assert db.get(LearningUnit, old["unit"]).active_seconds == 17
        assert db.scalar(select(func.count()).select_from(Activity).where(Activity.unit_id.is_not(None))) == 0
        if stage == "known":
            assert job.error_code == "invalid_output"
            assert usage.status == "failed_not_sent" and usage.cost_source == "cancelled"
            assert (usage.input_tokens, usage.output_tokens, usage.cost_micros) == (0, 0, 0)
        else:
            assert usage.status == "failed_unknown" and usage.cost_micros is None
            assert usage.cost_source != "cancelled"
        for key, (count, amount, unknown, known) in before.items():
            bucket = db.get(UsageBucket, key)
            assert bucket.calls == count and bucket.known_cost_micros == known
            assert bucket.encumbered_micros == amount - (held if stage == "known" else 0)
            assert bucket.unknown_calls == unknown - (1 if stage == "known" else 0)
        snapshot = (usage.status, usage.cost_source, usage.cost_micros, usage.settlement_version)
    if reached is not None:
        assert reached == [True]
    assert len(calls) == (1 if stage == "dispatched" else 0)
    worker.process(job_id)  # A failed terminal job does not dispatch or settle twice.
    with DB() as db:
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        assert (usage.status, usage.cost_source, usage.cost_micros, usage.settlement_version) == snapshot
    assert len(calls) == (1 if stage == "dispatched" else 0)
