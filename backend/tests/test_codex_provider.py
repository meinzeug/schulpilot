"""Codex selection, isolated requests and unknown subscription costs."""

import copy
from concurrent.futures import ThreadPoolExecutor

import httpx
import pytest
from fastapi import HTTPException
from schulpilot import codex_setup, operator_probe, providers
from schulpilot.config import settings
from schulpilot.db import DB, Family, OperatorJob, ProviderConfig, UsageBucket, uid
from schulpilot.providers import ProviderError, Result, request_provider, reserve, settle
from schulpilot.synthetic import sample_unit
from test_providers import configured


def setup_codex(household, mode="account"):
    user, child = household
    configured(user["families"][0]["id"])
    object.__setattr__(settings, "codex_approved", True)
    object.__setattr__(settings, "codex_socket", "/synthetic/private-codex.sock")
    object.__setattr__(settings, "codex_auth_mode", mode)
    object.__setattr__(settings, "synthetic_ai_enabled", True)
    with DB.begin() as db:
        config = db.get(ProviderConfig, 1)
        config.provider = "codex"
        if mode == "account":
            config.input_per_million_micros = config.output_per_million_micros = None
    return user, child


def test_operator_selection_persists_but_does_not_claim_activation(api, household):
    user, _ = setup_codex(household)
    with DB() as db:
        before = db.get(ProviderConfig, 1)
        revision = before.revision
        reserve_before, global_before = before.reserve_micros, before.global_limit_micros
        family_before = db.get(Family, user["families"][0]["id"]).budget_micros
    codex_setup.configure()
    with DB() as db:
        config = db.get(ProviderConfig, 1)
        assert config.provider == "codex" and config.model == config.extraction_model == "gpt-6.1-sol"
        assert config.revision == revision + 1 and config.production_block_reason
        assert config.encrypted_key is None
        assert config.input_per_million_micros is config.output_per_million_micros is None
        assert (config.reserve_micros, config.global_limit_micros) == (reserve_before, global_before)
        assert db.get(Family, user["families"][0]["id"]).budget_micros == family_before
        with pytest.raises(ProviderError):
            providers.external_allowed(config)


def test_unknown_account_costs_keep_atomic_limits(api, household):
    user, child = setup_codex(household)
    fid = user["families"][0]["id"]

    def attempt(_):
        try:
            with DB.begin() as db:
                usage = reserve(db, db.get(Family, fid), child["id"], uid(), "unit")
                settle(db, usage, Result({}, 300, 30, None))
            return True
        except HTTPException as error:
            assert error.status_code == 429
            return False

    with ThreadPoolExecutor(max_workers=6) as pool:
        assert sum(pool.map(attempt, range(9))) == 3
    with DB() as db:
        bucket = db.query(UsageBucket).filter(UsageBucket.id.like(fid + ":%")).one()
        assert bucket.calls == 3 and bucket.unknown_calls == 3 and bucket.encumbered_micros == 3000
    with DB.begin() as db:
        db.get(ProviderConfig, 1).emergency_stop = True
    with DB() as db:
        with pytest.raises(HTTPException) as error:
            reserve(db, db.get(Family, fid), child["id"], uid(), "unit")
        assert error.value.status_code == 503


@pytest.fixture
def transport(api, household, monkeypatch):
    setup_codex(household)
    with DB() as db:
        config = db.get(ProviderConfig, 1)
    output = sample_unit()
    for question in output["questions"]:
        if question["type"] == "choice":
            question["answer"] = question["options"].index(question["answer"])
    calls = []
    response = {"status": 200, "search_calls": 1}

    class Client:
        def __init__(self, **kwargs):
            assert "transport" in kwargs and kwargs["follow_redirects"] is False

        def __enter__(self):
            return self

        def __exit__(self, *_):
            pass

        def post(self, url, json):
            assert url == "http://localhost/generate"
            calls.append(json)
            return httpx.Response(
                response["status"],
                json={
                    "data": output,
                    "usage": {"input_tokens": 100, "output_tokens": 200},
                    "search_calls": response["search_calls"],
                    "detail": "SYNTHETIC-PRIVATE-ECHO",
                },
            )

    monkeypatch.setattr(providers.httpx, "Client", Client)
    return config, output, calls, response


def test_codex_schema_indexes_and_account_usage(transport):
    config, output, calls, _ = transport
    result = request_provider(config, "unit", {"material": {"content": "Synthetic fractions."}})
    assert result.data["questions"][0]["answer"] == sample_unit()["questions"][0]["answer"]
    assert result.cost_micros is None and result.input_tokens == 100 and len(calls) == 1
    body = calls[0]
    assert body["auth_mode"] == "account" and body["input_rate"] is body["output_rate"] is None
    assert "Webwissen darf nicht" in body["system"] and "unerklärte Fachbegriffe" in body["system"]
    assert body["schema"]["$defs"]["Question"]["anyOf"][0]["properties"]["answer"]["type"] == "integer"
    assert all("key" not in field for field in body)


@pytest.mark.parametrize("status", [413, 429, 502, 503, 500])
def test_worker_errors_never_echo_credentials_or_fallback(transport, status):
    config, _, calls, response = transport
    response["status"] = status
    with pytest.raises(ProviderError) as error:
        request_provider(config, "unit", {})
    assert "SYNTHETIC-PRIVATE-ECHO" not in str(error.value) and len(calls) == 1


def test_paid_api_includes_search_fees_and_missing_usage_stays_unknown(transport):
    config, _, _, response = transport
    object.__setattr__(settings, "codex_auth_mode", "api_key")
    config.input_per_million_micros = config.output_per_million_micros = 1
    result = request_provider(config, "unit", {})
    assert result.cost_micros == 10001
    response["search_calls"] = None
    assert request_provider(config, "unit", {}).cost_micros is None


def test_codex_probe_uses_only_server_fixtures_and_counts_each_call(api, household, monkeypatch):
    setup_codex(household)
    with DB.begin() as db:
        db.get(ProviderConfig, 1).production_block_reason = "awaiting actual probe"
    monkeypatch.setattr(codex_setup, "worker_health", lambda: {"ready": True, "status": "synthetic worker"})
    calls = []

    def request(config, function, payload, **kwargs):
        calls.append((function, copy.deepcopy(payload), kwargs))
        assert kwargs["synthetic_fixture"] is True and kwargs["private_probe"] is True
        return Result({}, 100, 100, None)

    monkeypatch.setattr(operator_probe, "request_provider", request)
    with DB() as db:
        result = operator_probe.enqueue("synthetic-operator", db)
    assert operator_probe.work_one()
    with DB() as db:
        report = db.get(OperatorJob, result["id"])
        assert report.status == "completed" and len(report.report) == 3
        assert not db.get(ProviderConfig, 1).production_block_reason
        bucket = db.query(UsageBucket).filter(UsageBucket.id.like("global:%")).one()
        assert bucket.calls == bucket.unknown_calls == 3 and bucket.encumbered_micros == 3000
    assert [call[0] for call in calls] == ["extract", "unit", "package"]
    assert all(call[1] == {} for call in calls)


def test_probe_requires_separate_login(api, household, monkeypatch):
    setup_codex(household)
    monkeypatch.setattr(codex_setup, "worker_health", lambda: {"ready": False, "status": "Separate Anmeldung fehlt."})
    with DB() as db:
        with pytest.raises(HTTPException, match="Anmeldung"):
            operator_probe.enqueue("synthetic-operator", db)
    assert not operator_probe.work_one()
