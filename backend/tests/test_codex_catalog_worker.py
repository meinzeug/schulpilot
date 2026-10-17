"""Private metadata discovery: no inference, real login or provider request."""

import json
import shutil
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from test_codex_worker import worker


@pytest.fixture(autouse=True)
def clean_database():
    # The catalog is private process metadata and has no database dependency.
    yield


def model(model_id="synthetic-model", **changes):
    return {
        "id": "ui-" + model_id, "model": model_id, "displayName": "Synthetic model", "hidden": False,
        "defaultReasoningEffort": "medium",
        "supportedReasoningEfforts": [
            {"reasoningEffort": "medium", "description": "Synthetic"},
            {"reasoningEffort": "future_effort-2", "description": "Synthetic"},
        ], **changes,
    }


@pytest.fixture
def login(tmp_path, monkeypatch):
    path = tmp_path / "auth.json"
    path.write_text(json.dumps({"OPENAI_API_KEY": "SYNTHETIC-NOT-A-REAL-KEY"}))
    path.chmod(0o600)
    monkeypatch.setattr(worker, "AUTH_FILE", path)
    monkeypatch.setattr(worker, "catalog_cache", None)
    monkeypatch.setattr(worker, "last_failure", None)
    monkeypatch.setattr(worker, "isolated", lambda: True)
    return path


# A real bounded subprocess exercises framing, deadlines and cleanup without
# any networking or access to credentials beyond the synthetic test login.
PROGRAM = r'''
import json, os, sys, time
from pathlib import Path
fixture = json.loads(Path("metadata.json").read_text())
if "refresh" in fixture:
    auth = Path(os.environ["CODEX_HOME"]) / "auth.json"
    auth.write_text(json.dumps(fixture["refresh"]))
    auth.chmod(0o600)
page = 0
for line in sys.stdin:
    request = json.loads(line)
    method = request["method"]
    if method == "initialized":
        continue
    if method == "initialize":
        response = {"id": request["id"], "result": {"userAgent": "synthetic"}}
    elif method == "model/list":
        behavior = fixture.get("behavior")
        if behavior == "timeout":
            time.sleep(60)
        if behavior == "oversized":
            sys.stdout.write("X" * 1_100_000)
            sys.stdout.flush()
            continue
        if behavior == "request":
            response = {"id": 33, "method": "item/commandExecution/requestApproval", "params": {}}
        elif behavior == "error":
            response = {"id": request["id"], "error": {"message": "SYNTHETIC-PRIVATE-TOKEN"}}
        elif behavior == "malformed":
            print("not-json", flush=True)
            continue
        elif behavior == "flood":
            for _ in range(1001):
                print(json.dumps({"method": "synthetic/notification"}), flush=True)
            continue
        else:
            response = {"id": request["id"], "result": fixture["pages"][page]}
            page += 1
    else:
        raise RuntimeError("unexpected method")
    print(json.dumps(response), flush=True)
'''


@pytest.fixture
def runner(login, monkeypatch):
    original_popen, original_send = subprocess.Popen, worker.CatalogRPC.send
    fixture = {"pages": [{"data": [model()], "nextCursor": None}]}
    launches, requests = [], []

    def send(self, method, params, request_id=None):
        requests.append({"method": method, "params": params, "id": request_id})
        return original_send(self, method, params, request_id)

    def popen(args, **kwargs):
        assert args == ["/usr/local/bin/codex", "app-server", "--listen", "stdio://"]
        assert set(kwargs["env"]) == {"PATH", "HOME", "CODEX_HOME", "LANG", "TMPDIR"}
        assert kwargs["stdin"] == kwargs["stdout"] == subprocess.PIPE
        assert kwargs["stderr"] == subprocess.DEVNULL and "shell" not in kwargs
        root, home = Path(kwargs["cwd"]), Path(kwargs["env"]["CODEX_HOME"])
        assert home.parent == root and home.stat().st_mode & 0o077 == 0
        assert (home / "auth.json").read_bytes() == login.read_bytes()
        assert (home / "auth.json").stat().st_mode & 0o077 == 0
        config = __import__("tomllib").loads((home / "config.toml").read_text())
        assert "model_provider" not in config and "model_providers" not in config
        assert config["analytics"]["enabled"] is False and config["features"]["shell_tool"] is False
        (root / "metadata.json").write_text(json.dumps(fixture))
        process = original_popen([sys.executable, "-c", PROGRAM], **kwargs)
        launches.append((root, process))
        return process

    monkeypatch.setattr(worker.CatalogRPC, "send", send)
    monkeypatch.setattr(worker.subprocess, "Popen", popen)
    return fixture, launches, requests


def test_private_auth_bound_cache_slot_and_only_metadata_methods(login, monkeypatch, runner):
    _, launches, requests = runner
    with TestClient(worker.app) as client:
        expected = client.get("/models").json()
        assert expected == {
            "models": [{
                "id": "synthetic-model", "name": "Synthetic model", "hidden": False,
                "reasoning_efforts": ["medium", "future_effort-2"], "default_reasoning_effort": "medium",
                "input_modalities": ["text", "image"],
            }], "source": "codex_cli", "cli_version": "0.162.1",
        }
        worker.slot.acquire()
        try:
            assert client.get("/models").json() == expected and len(launches) == 1
            login.write_text(json.dumps({"OPENAI_API_KEY": "SYNTHETIC-NEW-LOGIN"}))
            assert client.get("/models").status_code == 429
        finally:
            worker.slot.release()
        assert client.get("/models").json() == expected and len(launches) == 2
        monkeypatch.setattr(worker, "isolated", lambda: False)
        assert client.get("/models").status_code == 503
        monkeypatch.setattr(worker, "isolated", lambda: True)
        login.unlink()
        assert client.get("/models").status_code == 503
    assert [request["method"] for request in requests] == ["initialize", "initialized", "model/list"] * 2
    assert all(request["params"] == {"limit": 100, "includeHidden": True}
               for request in requests if request["method"] == "model/list")
    assert all(not root.exists() and process.poll() is not None for root, process in launches)


def test_pages_preserve_explicit_capabilities_hidden_and_dynamic_efforts(runner):
    fixture, _, requests = runner
    fixture["pages"] = [
        {"data": [model(inputModalities=["text"], hidden=True)], "nextCursor": "opaque-second-page"},
        {"data": [model("other", inputModalities=[], supportedReasoningEfforts=[])], "nextCursor": None},
    ]
    result = worker.models()
    assert len(result["models"]) == 2
    assert result["models"][0]["hidden"] is True and result["models"][0]["input_modalities"] == ["text"]
    assert result["models"][1]["input_modalities"] == [] and result["models"][1]["reasoning_efforts"] == []
    assert requests[-1] == {
        "method": "model/list", "id": 2,
        "params": {"limit": 100, "includeHidden": True, "cursor": "opaque-second-page"},
    }


@pytest.mark.parametrize("behavior", ["timeout", "oversized", "request", "error", "malformed", "flood"])
def test_errors_bounded_sanitized_release_slot_and_remove_home(monkeypatch, runner, behavior):
    fixture, launches, _ = runner
    fixture["behavior"] = behavior
    if behavior == "timeout":
        monkeypatch.setattr(worker, "CATALOG_TIMEOUT", 0.2)
    with TestClient(worker.app) as client:
        response = client.get("/models")
    assert response.status_code == 503
    assert "SYNTHETIC" not in response.text and "requestApproval" not in response.text
    assert worker.catalog_cache is None and worker.slot.acquire(blocking=False)
    worker.slot.release()
    assert all(not root.exists() and process.poll() is not None for root, process in launches)
    assert worker.last_failure is None


@pytest.mark.parametrize("pages", [
    [{"data": [model()], "nextCursor": "same"}] * 2,
    [{"data": [model()], "nextCursor": "one"}, {"data": [model("two")], "nextCursor": "two"}],
    [{"data": [model()] * 101, "nextCursor": None}],
    [{"data": [model()], "nextCursor": {"private": "untrusted"}}],
    [{"data": [], "nextCursor": None}],
])
def test_rejects_truncation_repeated_cursors_and_invalid_pages(runner, pages):
    fixture, launches, _ = runner
    fixture["pages"] = pages
    with pytest.raises(HTTPException) as error:
        worker.models()
    assert error.value.status_code == 503 and all(not root.exists() for root, _ in launches)


@pytest.mark.parametrize("changes", [
    {"model": "x;command"}, {"displayName": "bad\nname"}, {"hidden": "false"},
    {"inputModalities": ["text", "text"]}, {"inputModalities": ["unknown"]}, {"inputModalities": None},
    {"supportedReasoningEfforts": [{"reasoningEffort": "\"\nmalicious"}]},
    {"supportedReasoningEfforts": [{"reasoningEffort": "high"}], "defaultReasoningEffort": "medium"},
    {"supportedReasoningEfforts": [{"reasoningEffort": "medium"}] * 2},
])
def test_rejects_invalid_model_metadata(runner, changes):
    fixture, _, _ = runner
    fixture["pages"][0]["data"] = [model(**changes)]
    with pytest.raises(HTTPException) as error:
        worker.models()
    assert error.value.status_code == 503


@pytest.mark.parametrize("behavior", [None, "error", "timeout"])
def test_preserves_valid_own_refreshed_auth_even_on_abort(login, monkeypatch, runner, behavior):
    fixture, _, _ = runner
    refreshed = {"OPENAI_API_KEY": "SYNTHETIC-REFRESHED-WORKER-KEY"}
    fixture["refresh"] = refreshed
    if behavior:
        fixture["behavior"] = behavior
        if behavior == "timeout":
            monkeypatch.setattr(worker, "CATALOG_TIMEOUT", 0.2)
        with pytest.raises(HTTPException):
            worker.models()
    else:
        assert worker.models()["models"]
    assert json.loads(login.read_text()) == refreshed and login.stat().st_mode & 0o077 == 0
    assert worker.slot.acquire(blocking=False)
    worker.slot.release()


def test_invalid_refresh_and_concurrent_manual_login_are_not_overwritten(login, runner, tmp_path):
    fixture, _, _ = runner
    original = login.read_bytes()
    fixture["refresh"] = {"tokens": {"access_token": "SYNTHETIC-INCOMPLETE"}}
    assert worker.models()["models"] and login.read_bytes() == original
    home = tmp_path / "refresh-home"
    home.mkdir()
    (home / "auth.json").write_text(json.dumps({"OPENAI_API_KEY": "SYNTHETIC-REFRESHED-OLD-LOGIN"}))
    (home / "auth.json").chmod(0o600)
    manual = {"OPENAI_API_KEY": "SYNTHETIC-NEW-MANUAL-LOGIN"}
    login.write_text(json.dumps(manual))
    worker.persist_refreshed_auth(home, original)
    assert json.loads(login.read_text()) == manual


@pytest.mark.skipif(shutil.which("codex") is None, reason="Pinned CLI is not installed in generic CI")
def test_real_pinned_cli_metadata_with_only_synthetic_local_login(login, monkeypatch, record_property):
    # A reject-only local proxy prevents every remote request. model/list may
    # return the CLI catalog, which is expressly not an entitlement assertion.
    methods = []
    # The deployed rootless worker mounts /tmp as tmpfs. Its pinned CLI opens
    # several SQLite/WAL stores even for initialize. Host ext4 journal/fsync
    # stalls can consume the entire RPC deadline before any metadata request;
    # exercise the real CLI on the same storage type, keeping its 9s limit.
    native_tmpfs = Path("/dev/shm")
    assert native_tmpfs.is_dir(), "The native Linux worker test requires tmpfs, matching its container."
    original_temporary_directory = worker.tempfile.TemporaryDirectory

    def temporary_directory(*args, **kwargs):
        return original_temporary_directory(*args, **{**kwargs, "dir": str(native_tmpfs)})

    monkeypatch.setattr(worker.tempfile, "TemporaryDirectory", temporary_directory)

    class Metadata(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            methods.append("GET")
            self.send_error(503)

        def do_CONNECT(self):
            methods.append("CONNECT")
            self.send_error(403)

        def do_POST(self):
            methods.append("POST")
            self.send_error(403)

    server = ThreadingHTTPServer(("127.0.0.1", 0), Metadata)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    endpoint = f"http://127.0.0.1:{server.server_port}"
    original_environment, original_config = worker.cli_environment, worker.catalog_config

    def environment(home, root):
        return {**original_environment(home, root), "HTTP_PROXY": endpoint,
                "HTTPS_PROXY": endpoint, "ALL_PROXY": endpoint, "NO_PROXY": "127.0.0.1,localhost"}

    monkeypatch.setattr(worker, "cli_environment", environment)
    monkeypatch.setattr(worker, "catalog_config", lambda: f'chatgpt_base_url = "{endpoint}"\n' + original_config())
    try:
        result = worker.models()
        assert result["source"] == "codex_cli" and result["cli_version"] == "0.162.1"
        assert 1 <= len(result["models"]) <= 200
        record_property("normalized_catalog_model_count", len(result["models"]))
        assert all(isinstance(item["reasoning_efforts"], list) for item in result["models"])
        assert "POST" not in methods
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=1)
