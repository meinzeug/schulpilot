"""Synthetic runner contracts, including the installed CLI without a real login."""

import base64
import importlib.util
import json
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace

import httpx
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

spec = importlib.util.spec_from_file_location(
    "isolated_codex_worker", Path(__file__).resolve().parents[2] / "workers/codex/worker.py"
)
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


def job(mode="api_key", web_search=None):
    return {
        "auth_mode": mode,
        "web_search": (mode == "api_key") if web_search is None else web_search,
        "model": "synthetic-model",
        "system": "Only synthetic learning data.",
        "payload": {"material": "The synthetic cube has six faces."},
        "schema": {
            "type": "object",
            "properties": {"value": {"type": "string"}},
            "required": ["value"],
            "additionalProperties": False,
        },
        "image": None,
        "max_output_tokens": 1000,
        "reserve_micros": 100_000,
        "input_rate": 10,
        "output_rate": 10,
    }


@pytest.fixture
def login(tmp_path, monkeypatch):
    path = tmp_path / "auth.json"
    path.write_text(json.dumps({"OPENAI_API_KEY": "SYNTHETIC-NOT-A-REAL-KEY", "auth_mode": "apikey"}))
    path.chmod(0o600)
    monkeypatch.setattr(worker, "AUTH_FILE", path)
    return path


@pytest.fixture(autouse=True)
def isolated_worker_policy(monkeypatch):
    monkeypatch.delenv("CODEX_WEB_SEARCH", raising=False)
    monkeypatch.setattr(worker, "last_failure", None)


def test_worker_rejects_host_missing_login_mode_mismatch_and_busy(login, monkeypatch):
    with TestClient(worker.app) as client:
        monkeypatch.setattr(worker, "isolated", lambda: False)
        assert client.post("/generate", json=job()).status_code == 503
        monkeypatch.setattr(worker, "isolated", lambda: True)
        assert client.get("/health").json() == {
            "isolated": True,
            "auth_mode": "api_key",
            "cli_version": "0.162.1",
            "search": True,
            "cli_search": True,
            "search_policy": "single_search",
        }
        assert client.post("/generate", json=job("account")).status_code == 503
        worker.slot.acquire()
        try:
            assert client.post("/generate", json=job()).status_code == 429
        finally:
            worker.slot.release()
        login.unlink()
        assert client.post("/generate", json=job()).status_code == 503


@pytest.mark.parametrize(
    "change",
    [
        {"command": "cat /etc/passwd"},
        {"model": "x; malicious"},
        {"max_output_tokens": True},
        {"reserve_micros": -1},
        {"input_rate": None},
        {"image": "not-base64"},
        {"system": []},
        {"web_search": "true"},
    ],
)
def test_invalid_worker_contract(change):
    with pytest.raises(HTTPException):
        worker.validate_job({**job(), **change})


@pytest.mark.parametrize(
    "raw, expected",
    [
        (b'{"detail":"Unsupported parameter: max_tool_calls"}', "max_tool_calls"),
        (b'{"error":{"message":"Unsupported parameter: max_tool_calls","param":"max_tool_calls"}}', "max_tool_calls"),
        (b'{"detail":{"message":"Unsupported parameter: parallel_tool_calls"}}', "parallel_tool_calls"),
        (b'"Unsupported parameter: text.format"', "text.format"),
        (b'Unsupported parameter: search_context_size', "search_context_size"),
        (b'{"error":"Unsupported parameter: external_web_access"}', "external_web_access"),
        (b'{"detail":"Private synthetic answer, session secret and credentials"}', "unknown"),
        (b'{"detail":[{"input":"untrusted input"}]}', "unknown"),
        (b'{"unrelated":"max_tool_calls"}', "unknown"),
        (b'{"detail":"upstream input_invented and model_variant"}', "unknown"),
        (b'null', "unknown"),
    ],
)
def test_rejected_parameter_exposes_only_known_parameter_names(raw, expected):
    assert worker.rejected_parameter(raw) == expected


def test_login_permissions_and_refreshed_auth(login, tmp_path):
    assert worker.auth_mode() == "api_key"
    login.chmod(0o644)
    assert worker.auth_mode() == "invalid"
    login.chmod(0o600)
    original = login.read_bytes()
    home = tmp_path / "job-home"
    home.mkdir()
    refreshed = {"tokens": {"access_token": "SYNTHETIC-ACCESS", "refresh_token": "SYNTHETIC-REFRESH"}}
    (home / "auth.json").write_text(json.dumps(refreshed))
    worker.persist_refreshed_auth(home, original)
    assert worker.auth_mode() == "account" and login.stat().st_mode & 0o077 == 0
    # A concurrent new manual login wins over a stale job's refresh.
    worker.persist_refreshed_auth(home, original)
    assert json.loads(login.read_text()) == refreshed


def test_search_allowlist_and_api_reservation():
    data = worker.upstream_body(job())
    assert data["tools"] == [{"type": "web_search", "external_web_access": True, "search_context_size": "low"}]
    assert data["max_tool_calls"] == 1 and data["parallel_tool_calls"] is False
    assert data["store"] is False and data["max_output_tokens"] == 1000
    assert "previous_response_id" not in data and "conversation" not in data
    assert data["input"][0]["content"][0]["text"] == json.dumps(job()["payload"])
    with pytest.raises(HTTPException) as error:
        worker.upstream_body({**job(), "input_rate": 1_000_000, "reserve_micros": 10_000})
    assert error.value.status_code == 413
    account = worker.upstream_body({**job("account"), "input_rate": None, "output_rate": None})
    assert "max_output_tokens" not in account and "max_tool_calls" not in account
    assert account["tools"] == [] and account["tool_choice"] == "none"


def test_search_policy_defaults_and_explicit_account_choice(login, monkeypatch):
    assert worker.web_search_enabled("account") is False
    assert worker.web_search_enabled("api_key") is True
    monkeypatch.setenv("CODEX_WEB_SEARCH", "false")
    assert worker.health()["search"] is False and worker.health()["cli_search"] is True
    assert worker.health()["search_policy"] == "source_only"
    monkeypatch.setenv("CODEX_WEB_SEARCH", "true")
    data = worker.upstream_body(job("account", web_search=True))
    assert data["tools"][0]["type"] == "web_search" and "max_tool_calls" not in data
    assert "max_output_tokens" not in data


def test_denied_web_search_cannot_be_enabled_by_job(login, monkeypatch):
    monkeypatch.setattr(worker, "isolated", lambda: True)
    monkeypatch.setenv("CODEX_WEB_SEARCH", "false")
    with TestClient(worker.app) as client:
        response = client.post("/generate", json=job(web_search=True))
    assert response.status_code == 503


def events(value, search_calls=0):
    message = {
        "id": "msg_synthetic",
        "type": "message",
        "role": "assistant",
        "status": "completed",
        "content": [{"type": "output_text", "text": json.dumps(value), "annotations": []}],
    }
    response = {
        "id": "resp_synthetic",
        "object": "response",
        "status": "completed",
        "output": [
            message,
            *[{"id": "ws_synthetic", "type": "web_search_call", "status": "completed"} for _ in range(search_calls)],
        ],
        "usage": {"input_tokens": 100, "output_tokens": 30, "total_tokens": 130},
    }
    return [
        {"type": "response.created", "response": {"id": "resp_synthetic", "status": "in_progress", "output": []}},
        {
            "type": "response.output_item.added",
            "output_index": 0,
            "item": {
                "id": "msg_synthetic",
                "type": "message",
                "role": "assistant",
                "status": "in_progress",
                "content": [],
            },
        },
        {
            "type": "response.output_text.delta",
            "item_id": "msg_synthetic",
            "output_index": 0,
            "content_index": 0,
            "delta": json.dumps(value),
        },
        {"type": "response.output_item.done", "output_index": 0, "item": message},
        {"type": "response.completed", "response": response},
    ]


class Upstream:
    def __init__(self, record, status=200, search_calls=0):
        self.record = record
        self.status_code = status
        self.search_calls = search_calls

    def __enter__(self):
        return self

    def __exit__(self, *_):
        pass

    def stream(self, method, url, headers, json):
        self.record.append({"method": method, "url": url, "headers": headers, "body": json})
        return self

    def read(self):
        return b'{"detail":"Unsupported parameter: max_tool_calls; SYNTHETIC-PRIVATE-ECHO"}'

    def iter_lines(self):
        for event in events({"value": "six"}, self.search_calls):
            yield "data: " + json.dumps(event)
            yield ""


def fake_cli(args, input, stdout, stderr, cwd, env, timeout, check):
    assert args[:5] == ["/usr/local/bin/codex", "--search", "--ask-for-approval", "never", "exec"]
    assert "--ephemeral" in args and "--sandbox" in args and args[args.index("--sandbox") + 1] == "read-only"
    assert set(env) == {"PATH", "HOME", "CODEX_HOME", "LANG", "TMPDIR"}
    assert stdout == stderr == subprocess.DEVNULL
    config = __import__("tomllib").loads((Path(env["CODEX_HOME"]) / "config.toml").read_text())
    assert config["web_search"] == "live" and config["features"]["shell_tool"] is False
    gateway = config["model_providers"]["schulpilot"]
    request = httpx.Request(
        "POST",
        gateway["base_url"] + "/responses",
        headers={
            **gateway["http_headers"],
            "Authorization": "Bearer SYNTHETIC-NOT-A-REAL-KEY",
        },
        json={
            "tools": [{"type": "function", "name": "malicious_shell"}],
            "model": "wrong",
            "previous_response_id": "foreign",
        },
    )
    # Use an independent real transport; worker's upstream client is replaced.
    with httpx.HTTPTransport() as transport:
        response = transport.handle_request(request)
        response.read()
        assert response.status_code == 200
        # Additional CLI turns or retries cannot create additional upstream calls.
        second = transport.handle_request(request)
        second.read()
        assert second.status_code == 429
    Path(args[args.index("--output-last-message") + 1]).write_text(json.dumps({"value": "six"}))
    return SimpleNamespace(returncode=0)


def test_gateway_filters_cli_tools_context_and_keeps_one_call(login, monkeypatch):
    calls = []
    monkeypatch.setattr(worker.httpx, "Client", lambda **_: Upstream(calls, search_calls=1))
    monkeypatch.setattr(worker.subprocess, "run", fake_cli)
    result = worker.run(job())
    assert len(calls) == 1 and calls[0]["url"] == "https://api.openai.com/v1/responses"
    assert calls[0]["body"]["model"] == "synthetic-model"
    assert calls[0]["body"]["tools"][0]["type"] == "web_search"
    assert "previous_response_id" not in calls[0]["body"]
    assert result == {
        "data": {"value": "six"},
        "usage": {"input_tokens": 100, "output_tokens": 30, "total_tokens": 130},
        "search_calls": 1,
        "web_search": True,
    }
    assert not list(login.parent.glob("lesson-*"))


def test_private_failure_health_never_contains_echoed_payload_or_credentials(login, monkeypatch):
    calls = []
    monkeypatch.setattr(worker.httpx, "Client", lambda **_: Upstream(calls, status=400))

    def rejected_cli(args, **kwargs):
        config = __import__("tomllib").loads((Path(kwargs["env"]["CODEX_HOME"]) / "config.toml").read_text())
        gateway = config["model_providers"]["schulpilot"]
        request = httpx.Request(
            "POST", gateway["base_url"] + "/responses",
            headers={**gateway["http_headers"], "Authorization": "Bearer SYNTHETIC-NOT-A-REAL-KEY"},
            json={"private": "SYNTHETIC-PRIVATE-ECHO"},
        )
        with httpx.HTTPTransport() as transport:
            response = transport.handle_request(request)
            assert response.status_code == 400
            assert b"SYNTHETIC-PRIVATE-ECHO" not in response.read()
        return SimpleNamespace(returncode=1)

    monkeypatch.setattr(worker.subprocess, "run", rejected_cli)
    with pytest.raises(HTTPException):
        worker.run(job())
    assert len(calls) == 1
    assert worker.health()["last_failure"] == {
        "http_status": 400, "upstream_calls": 1, "cli_exit": 1, "parameter": "max_tool_calls",
    }
    rendered = json.dumps(worker.health())
    assert "SYNTHETIC" not in rendered and "Bearer" not in rendered and "PRIVATE" not in rendered


@pytest.mark.parametrize("mode, enabled, count, accepted", [
    ("account", False, 0, True),
    ("account", False, 1, False),
    ("account", True, 3, True),
    ("api_key", True, 2, False),
])
def test_actual_tool_policy_and_measured_search_count(login, monkeypatch, mode, enabled, count, accepted):
    calls = []
    monkeypatch.setattr(worker.httpx, "Client", lambda **_: Upstream(calls, search_calls=count))
    monkeypatch.setattr(worker.subprocess, "run", fake_cli)
    if accepted:
        result = worker.run(job(mode, web_search=enabled))
        assert result["search_calls"] == count and result["web_search"] is enabled
    else:
        with pytest.raises(HTTPException, match="Suchgrenze"):
            worker.run(job(mode, web_search=enabled))
        assert worker.health()["last_failure"] is not None
    assert len(calls) == 1


@pytest.mark.skipif(shutil.which("codex") is None, reason="Pinned CLI is not installed in generic CI")
@pytest.mark.parametrize("mode", ["api_key", "account"])
def test_real_installed_cli_against_fake_upstream(login, monkeypatch, mode):
    if mode == "account":
        claims = {
            "exp": 4_000_000_000,
            "email": "synthetic@example.org",
            "https://api.openai.com/auth": {"chatgpt_account_id": "synthetic-account"},
        }
        token = (
            ".".join(
                base64.urlsafe_b64encode(json.dumps(part).encode()).decode().rstrip("=")
                for part in ({"alg": "none"}, claims)
            )
            + ".synthetic"
        )
        login.write_text(
            json.dumps(
                {
                    "auth_mode": "chatgpt",
                    "OPENAI_API_KEY": None,
                    "tokens": {
                        "id_token": token,
                        "access_token": token,
                        "refresh_token": "synthetic-refresh",
                        "account_id": "synthetic-account",
                    },
                    "last_refresh": datetime.now(timezone.utc).isoformat(),
                }
            )
        )
    calls = []
    monkeypatch.setattr(worker.httpx, "Client", lambda **_: Upstream(calls))
    assert worker.run(job(mode))["data"] == {"value": "six"}
    assert len(calls) == 1
    assert calls[0]["url"] == (
        "https://api.openai.com/v1/responses"
        if mode == "api_key"
        else "https://chatgpt.com/backend-api/codex/responses"
    )
    if mode == "account":
        assert calls[0]["headers"]["ChatGPT-Account-Id"] == "synthetic-account"
