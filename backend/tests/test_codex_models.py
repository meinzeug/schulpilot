"""Codex model metadata and effort selection, using synthetic transports only."""

import copy
import hashlib
import json

import httpx
import pytest
from conftest import HEADERS
from fastapi import HTTPException
from fastapi.testclient import TestClient
from schulpilot import codex_setup, operator_probe, providers, schemas
from schulpilot.config import settings
from schulpilot.db import DB, Audit, OperatorJob, ProviderConfig, Session, Usage, User, now
from schulpilot.main import app
from schulpilot.providers import ProviderError, Result
from schulpilot.security import digest
from sqlalchemy import func, select
from test_codex_provider import setup_codex
from test_codex_provider import transport as codex_transport_fixture


def catalog():
    def model(identifier, efforts, modalities, hidden=False):
        return {
            "id": identifier,
            "name": "Artificial " + identifier,
            "reasoning_efforts": efforts,
            "default_reasoning_effort": "medium",
            "input_modalities": modalities,
            "hidden": hidden,
        }

    return {
        "models": [
            model("model-from-test-fixture", ["low", "medium", "high", "ultra"], ["text", "image"]),
            model("synthetic-text-only", ["low", "medium", "high"], ["text"]),
            model("synthetic-image", ["medium"], ["text", "image"]),
            model("synthetic-hidden", ["medium", "high"], ["text", "image"], True),
        ],
        "source": "codex_cli",
        "cli_version": "0.162.1",
    }


def payload():
    with DB() as db:
        config = db.get(ProviderConfig, 1)
        return {key: getattr(config, key) for key in schemas.ProviderUpdate.model_fields if key != "api_key"}


@pytest.fixture
def transport(api, household, monkeypatch):
    return codex_transport_fixture.__wrapped__(api, household, monkeypatch)


@pytest.fixture
def operator():
    with DB.begin() as db:
        user = User(
            username="catalog-operator",
            display_name="Synthetic operator",
            role="admin",
            verified=True,
            password_hash="synthetic-session-only-no-login",
        )
        db.add(user)
        db.flush()
        db.add(
            Session(
                user_id=user.id,
                token_hash=digest("synthetic-catalog-session"),
                device="synthetic",
                expires=int(now()) + 1000,
            )
        )
    with TestClient(app, headers={**HEADERS, "Authorization": "Bearer synthetic-catalog-session"}) as client:
        yield client


def test_catalog_is_only_for_admin_and_never_reserves_inference(api, household, operator, monkeypatch):
    reads = []
    monkeypatch.setattr(codex_setup, "worker_models", lambda: reads.append(True) or catalog())
    assert api.get("/api/admin/provider/codex/models").status_code == 403
    with TestClient(app, headers=HEADERS) as anonymous:
        assert anonymous.get("/api/admin/provider/codex/models").status_code == 401
        login = anonymous.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"})
        anonymous.headers["Authorization"] = "Bearer " + login.json()["token"]
        assert anonymous.get("/api/admin/provider/codex/models").status_code == 403
    result = operator.get("/api/admin/provider/codex/models")
    assert result.status_code == 200 and result.json() == catalog()
    assert reads == [True]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
        assert db.scalar(select(func.count()).select_from(OperatorJob)) == 0
        assert db.scalar(select(Audit).where(Audit.action == "admin.codex_models_read")).target == "codex_cli"


def test_catalog_rate_limit_avoids_unbounded_cli_metadata_reads(operator, monkeypatch):
    reads = []
    monkeypatch.setattr(codex_setup, "worker_models", lambda: reads.append(True) or catalog())
    for _ in range(12):
        assert operator.get("/api/admin/provider/codex/models").status_code == 200
    assert operator.get("/api/admin/provider/codex/models").status_code == 429
    assert len(reads) == 12


def mock_catalog_transport(monkeypatch, response):
    object.__setattr__(settings, "codex_approved", True)
    object.__setattr__(settings, "codex_socket", "/synthetic/isolated-codex.sock")
    calls = []

    def factory(**kwargs):
        assert kwargs == {"uds": settings.codex_socket}

        def handler(request):
            assert request.method == "GET" and str(request.url) == "http://localhost/models"
            assert not request.content and "authorization" not in request.headers
            calls.append(request.method)
            return response()

        return httpx.MockTransport(handler)

    monkeypatch.setattr(codex_setup.httpx, "HTTPTransport", factory)
    return calls


def test_catalog_uses_only_fixed_private_uds_and_dynamic_actual_efforts(monkeypatch):
    calls = mock_catalog_transport(monkeypatch, lambda: httpx.Response(200, json=catalog()))
    data = codex_setup.worker_models()
    assert data == catalog() and data["models"][0]["reasoning_efforts"][-1] == "ultra"
    assert calls == ["GET"]


@pytest.mark.parametrize(
    "kind",
    [
        "busy",
        "unavailable",
        "redirect",
        "invalid_json",
        "oversized",
        "wrong_version",
        "extra_secret",
        "effort_injection",
        "duplicate",
    ],
)
def test_catalog_errors_are_bounded_and_do_not_echo_worker_data(monkeypatch, kind):
    data = catalog()
    status, content = 200, None
    if kind == "busy":
        status = 429
    elif kind == "unavailable":
        status = 503
    elif kind == "redirect":
        status = 302
    elif kind == "invalid_json":
        content = b"SYNTHETIC-PRIVATE-WORKER-ECHO"
    elif kind == "oversized":
        content = b"SYNTHETIC-PRIVATE-WORKER-ECHO" * 20000
    elif kind == "wrong_version":
        data["cli_version"] = "other"
    elif kind == "extra_secret":
        data["secret"] = "SYNTHETIC-PRIVATE-WORKER-ECHO"
    elif kind == "effort_injection":
        data["models"][0]["reasoning_efforts"] = ['medium"\nshell=true']
    elif kind == "duplicate":
        data["models"].append(copy.deepcopy(data["models"][0]))
    calls = mock_catalog_transport(
        monkeypatch, lambda: httpx.Response(status, content=content) if content else httpx.Response(status, json=data)
    )
    with pytest.raises(HTTPException) as error:
        codex_setup.worker_models()
    assert error.value.status_code == (429 if kind == "busy" else 503)
    assert "PRIVATE" not in str(error.value.detail) and len(calls) == 1


def test_unknown_model_or_incompatible_text_image_effort_cannot_be_saved(api, household, operator, monkeypatch):
    setup_codex(household)
    monkeypatch.setattr(codex_setup, "worker_models", catalog)
    changes = [
        {"model": "unadvertised-model"},
        {"model": "synthetic-text-only"},
        {"extraction_model": "synthetic-text-only"},
        {"reasoning_effort": "not_advertised"},
        {"extraction_model": "synthetic-image", "reasoning_effort": "high"},
    ]
    original = payload()
    with DB() as db:
        revision = db.get(ProviderConfig, 1).revision
    for change in changes:
        response = operator.put("/api/admin/provider", json={**original, **change})
        assert response.status_code == 422, response.text
    with DB() as db:
        config = db.get(ProviderConfig, 1)
        assert config.revision == revision and config.model == original["model"] and config.reasoning_effort == "medium"


def test_changed_effort_invalidates_probe_and_reaches_private_generate_body(transport, operator, monkeypatch):
    _, _, calls, _ = transport
    monkeypatch.setattr(codex_setup, "worker_models", catalog)
    value = payload()
    saved = operator.put("/api/admin/provider", json={**value, "reasoning_effort": "high"})
    assert saved.status_code == 200 and saved.json()["reasoning_effort"] == "high"
    assert saved.json()["production_block_reason"] and "encrypted_key" not in saved.json()
    with DB() as db:
        config = db.get(ProviderConfig, 1)
        assert config.revision > 1
        with pytest.raises(ProviderError):
            providers.external_allowed(config)
        # The regular artificial probe is allowed through the production gate.
        config.production_block_reason = ""
        assert providers.request_provider(config, "unit", {}).cost_micros is None
    assert len(calls) == 1 and calls[0]["reasoning_effort"] == "high"


def test_medium_generate_keeps_the_legacy_worker_body_during_upgrade(transport):
    config, _, calls, _ = transport
    assert config.reasoning_effort == "medium"
    result = providers.request_provider(config, "unit", {})
    assert result.cost_micros is None and len(calls) == 1
    assert set(calls[0]) == {
        "auth_mode",
        "web_search",
        "model",
        "system",
        "payload",
        "schema",
        "image",
        "max_output_tokens",
        "reserve_micros",
        "input_rate",
        "output_rate",
    }


def test_omission_preserves_existing_high_and_null_is_rejected(api, household, operator, monkeypatch):
    setup_codex(household)
    monkeypatch.setattr(codex_setup, "worker_models", catalog)
    with DB.begin() as db:
        db.get(ProviderConfig, 1).reasoning_effort = "high"
    value = payload()
    value.pop("reasoning_effort")
    result = operator.put("/api/admin/provider", json=value)
    assert result.status_code == 200 and result.json()["reasoning_effort"] == "high"
    assert not result.json()["production_block_reason"]
    assert operator.put("/api/admin/provider", json={**value, "reasoning_effort": None}).status_code == 422


@pytest.mark.parametrize("status", [429, 503])
def test_catalog_outage_only_allows_unchanged_routing(api, household, operator, monkeypatch, status):
    setup_codex(household)

    def unavailable():
        raise HTTPException(status, "Synthetischer Katalogausfall.")

    monkeypatch.setattr(codex_setup, "worker_models", unavailable)
    original = payload()
    same = operator.put("/api/admin/provider", json={**original, "global_limit_micros": 123456})
    assert same.status_code == 200 and not same.json()["production_block_reason"]
    for change in (
        {"reasoning_effort": "high"},
        {"model": "unverified-model"},
        {"extraction_model": "synthetic-image"},
    ):
        result = operator.put("/api/admin/provider", json={**original, **change})
        assert result.status_code == status
    with DB() as db:
        assert db.get(ProviderConfig, 1).model == original["model"]
        assert db.get(ProviderConfig, 1).reasoning_effort == "medium"


def test_catalog_success_validates_even_unchanged_existing_selection(api, household, operator, monkeypatch):
    setup_codex(household)
    data = catalog()
    data["models"] = data["models"][1:]
    monkeypatch.setattr(codex_setup, "worker_models", lambda: data)
    assert operator.put("/api/admin/provider", json=payload()).status_code == 422


def test_emergency_stop_during_catalog_read_cannot_be_undone_by_older_save(api, household, operator, monkeypatch):
    setup_codex(household)
    original = payload()
    assert original["emergency_stop"] is False
    with DB() as db:
        revision = db.get(ProviderConfig, 1).revision

    def catalog_after_emergency_stop():
        with TestClient(app, headers=dict(operator.headers)) as stopping_operator:
            stopped = stopping_operator.post("/api/admin/emergency-stop")
            assert stopped.status_code == 200
        return catalog()

    monkeypatch.setattr(codex_setup, "worker_models", catalog_after_emergency_stop)
    response = operator.put("/api/admin/provider", json={**original, "reasoning_effort": "high"})
    assert response.status_code == 409 and "Notfallstopp" in response.json()["detail"]
    with DB() as db:
        config = db.get(ProviderConfig, 1)
        assert config.emergency_stop is True
        assert config.revision == revision and config.reasoning_effort == "medium"
        assert config.model == original["model"]


def test_available_hidden_selection_is_not_silently_substituted(api, household, operator, monkeypatch):
    setup_codex(household)
    monkeypatch.setattr(codex_setup, "worker_models", catalog)
    response = operator.put(
        "/api/admin/provider", json={**payload(), "model": "synthetic-hidden", "reasoning_effort": "high"}
    )
    assert response.status_code == 200
    assert response.json()["model"] == "synthetic-hidden" and response.json()["reasoning_effort"] == "high"


def test_probe_records_and_activates_exact_high_without_changing_models(api, household, monkeypatch):
    setup_codex(household)
    with DB.begin() as db:
        config = db.get(ProviderConfig, 1)
        config.reasoning_effort, config.production_block_reason = "high", "requires synthetic probe"
    monkeypatch.setattr(codex_setup, "worker_health", lambda: {"ready": True, "status": "synthetic"})
    seen = []

    def request(config, function, payload, **kwargs):
        seen.append((function, config.model, config.reasoning_effort))
        assert kwargs == {"synthetic_fixture": True, "private_probe": True}
        return Result({}, 10, 10, None)

    monkeypatch.setattr(operator_probe, "request_provider", request)
    with DB() as db:
        queued = operator_probe.enqueue("synthetic-operator", db)
    assert operator_probe.work_one()
    with DB() as db:
        config = db.get(ProviderConfig, 1)
        assert config.reasoning_effort == "high" and config.model == "model-from-test-fixture"
        assert not config.production_block_reason
        report = db.get(OperatorJob, queued["id"])
        assert len(report.report) == 3 and all(item["reasoning_effort"] == "high" for item in report.report)
        assert all(item["routing_fingerprint"] for item in report.report)
    assert [function for function, _, _ in seen] == ["extract", "unit", "package"]
    assert all(effort == "high" for _, _, effort in seen)


def test_medium_fingerprint_is_legacy_compatible_but_high_differs():
    legacy = {"provider": "codex", "model": "synthetic-model", "extraction_model": ""}
    expected = hashlib.sha256(json.dumps(legacy, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    config = ProviderConfig(**legacy, reasoning_effort="medium")
    assert providers.routing_fingerprint(config) == expected
    config.reasoning_effort = "high"
    assert providers.routing_fingerprint(config) != expected
