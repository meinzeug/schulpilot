"""Codex selection, isolated requests and unknown subscription costs."""

import copy
from concurrent.futures import ThreadPoolExecutor

import httpx
import pytest
from fastapi import HTTPException
from schulpilot import codex_setup, operator_probe, providers
from schulpilot.config import settings
from schulpilot.db import DB, Family, OperatorJob, ProviderConfig, Usage, UsageBucket, uid
from schulpilot.providers import ProviderError, Result, request_provider, reserve, settle
from schulpilot.synthetic import sample_unit
from test_providers import configured


def setup_codex(household, mode="account"):
    user, child = household
    configured(user["families"][0]["id"])
    object.__setattr__(settings, "codex_approved", True)
    object.__setattr__(settings, "codex_socket", "/synthetic/private-codex.sock")
    object.__setattr__(settings, "codex_auth_mode", mode)
    object.__setattr__(settings, "codex_web_search", mode == "api_key")
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
    response = {"status": 200, "search_calls": 0}

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
    assert body["web_search"] is False
    assert "Betreiber-Richtlinie deaktiviert" in body["system"]
    assert "Websuche ist für eine fachliche Gegenprüfung erlaubt" not in body["system"]
    assert "Webwissen darf nicht" in body["system"] and "unerklärte Fachbegriffe" in body["system"]
    assert body["schema"]["$defs"]["Question"]["anyOf"][0]["properties"]["answer"]["type"] == "integer"
    assert all("key" not in field for field in body)


def test_followup_transport_sends_identical_sources_once_without_mutating_revision_data(transport):
    config, _, calls, _ = transport
    sources = [{"id": "source-one", "revision": 4, "content": "Künstlicher Bruchstoff. " * 30},
               {"id": "source-two", "revision": 7, "content": "Künstliche Beispiele. " * 30}]
    combined = "\n\n".join(m["content"] for m in sources)
    payload = {"review": True, "materials": sources,
               "material": {"subject": "Mathematik", "content": combined},
               "previous_prompts": ["Vorherige künstliche Frage"]}
    original = copy.deepcopy(payload)
    result = request_provider(config, "unit", payload)
    assert result.data["questions"]
    sent = calls[0]["payload"]
    assert sent["materials"] == sources and sent["previous_prompts"] == original["previous_prompts"]
    assert "content" not in sent["material"] and sent["material"]["content_ref"] == "materials[].content"
    assert payload == original
    import json

    assert len(json.dumps(sent)) < len(json.dumps(original)) - len(combined) + 100
    assert "vollständig enthaltenen Quellen" in calls[0]["system"]


def test_transport_keeps_nonidentical_source_and_initial_unit_content(transport):
    config, _, calls, _ = transport
    payload = {"review": True, "materials": [{"content": "Künstlicher Stoff. " * 30}],
               "material": {"content": "Anderer bestätigter Stoff. " * 30}}
    request_provider(config, "unit", payload)
    assert calls[-1]["payload"]["material"] == payload["material"]
    assert calls[-1]["payload"]["materials"] == payload["materials"]
    payload["review"] = False
    payload["material"]["content"] = payload["materials"][0]["content"]
    request_provider(config, "unit", payload)
    assert calls[-1]["payload"]["material"] == payload["material"]
    assert calls[-1]["payload"]["materials"] == payload["materials"]


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
    object.__setattr__(settings, "codex_web_search", True)
    response["search_calls"] = 1
    config.input_per_million_micros = config.output_per_million_micros = 1
    result = request_provider(config, "unit", {})
    assert result.cost_micros == 10001
    response["search_calls"] = None
    assert request_provider(config, "unit", {}).cost_micros is None


def test_explicit_account_search_policy_is_forwarded_without_invented_pricing(transport):
    config, _, calls, response = transport
    object.__setattr__(settings, "codex_web_search", True)
    response["search_calls"] = 3
    result = request_provider(config, "unit", {})
    assert calls[0]["web_search"] is True and result.cost_micros is None
    assert result.search_calls == 3
    assert "Websuche ist für eine fachliche Gegenprüfung erlaubt" in calls[0]["system"]


@pytest.mark.parametrize("search", [False, True])
def test_worker_health_requires_matching_actual_search_policy(api, household, monkeypatch, search):
    setup_codex(household)
    object.__setattr__(settings, "codex_web_search", search)
    envelope = {
        "isolated": True, "auth_mode": "account", "cli_version": "0.162.1",
        "cli_search": True, "search": search,
    }

    class Client:
        def __init__(self, **_):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *_):
            pass

        def get(self, url):
            assert url == "http://localhost/health"
            return httpx.Response(200, json=envelope)

    monkeypatch.setattr(codex_setup.httpx, "Client", Client)
    status = codex_setup.worker_health()
    assert status["ready"] and status["web_search"] is search
    assert ("Websuche an" if search else "Websuche aus") in status["status"]
    if search:
        assert "keine feste Obergrenze" in status["status"]
    envelope["search"] = not search
    assert not codex_setup.worker_health()["ready"]


def test_codex_probe_uses_only_server_fixtures_and_counts_each_call(api, household, monkeypatch):
    setup_codex(household)
    with DB.begin() as db:
        db.get(ProviderConfig, 1).production_block_reason = "awaiting actual probe"
    monkeypatch.setattr(codex_setup, "worker_health", lambda: {"ready": True, "status": "synthetic worker"})
    calls = []

    def request(config, function, payload, **kwargs):
        calls.append((function, copy.deepcopy(payload), kwargs))
        assert kwargs["synthetic_fixture"] is True and kwargs["private_probe"] is True
        return Result({}, 100, 100, None, search_calls=0 if function == "extract" else 2)

    monkeypatch.setattr(operator_probe, "request_provider", request)
    with DB() as db:
        result = operator_probe.enqueue("synthetic-operator", db)
    assert operator_probe.work_one()
    with DB() as db:
        report = db.get(OperatorJob, result["id"])
        assert report.status == "completed" and len(report.report) == 3
        assert [row["search_calls"] for row in report.report] == [0, 2, 2]
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


def test_public_status_recognizes_approved_codex_fixed_synthetic_route(api, household):
    setup_codex(household)
    status = api.get("/api/status").json()
    assert status["synthetic_ai_available"] is True and status["ai_provider"] == "codex"
    assert status["ai_free_only"] is False and status["ai_data_collection"] is None
    with DB.begin() as db:
        db.get(ProviderConfig, 1).emergency_stop = True
    assert api.get("/api/status").json()["synthetic_ai_available"] is False


@pytest.mark.parametrize("measured", [None, 0, 3])
def test_measured_search_counts_persist_without_invented_cost_and_only_for_own_parents(api, household, measured):
    user, child = setup_codex(household)
    family_id = user["families"][0]["id"]
    with DB.begin() as db:
        usage = reserve(db, db.get(Family, family_id), child["id"], uid(), "tutor")
        usage_id = usage.id
        settle(db, usage, Result({}, 10, 20, None, search_calls=measured))
    with DB() as db:
        row = db.get(Usage, usage_id)
        assert row.search_calls == measured and row.cost_micros is None
    response = api.get(f"/api/families/{family_id}/usage")
    assert response.status_code == 200
    assert response.json()["records"][0]["search_calls"] == measured
    assert api.get(f"/api/families/{uid()}/usage").status_code == 404
