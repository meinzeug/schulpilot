"""Private, single-slot Codex runner. Only hosted search reaches the model.

The rootless container has its own operator login and no development credentials.
Every invocation uses a fresh home; only refreshed login credentials survive.
"""

import base64
import hashlib
import hmac
import json
import math
import os
import re
import secrets
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import httpx
import uvicorn
from fastapi import FastAPI, HTTPException

CLI_VERSION = "0.162.1"
AUTH_FILE = Path("/run/credentials/auth.json")
SEARCH_FEE_MICROS = 10_000  # Official API pricing, checked 2026-10-15.
SEARCH_CONTEXT_TOKENS = 128_000  # Conservative hosted search context ceiling.
app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
slot = threading.Lock()
last_failure = None


def auth_mode(path=None):
    path = AUTH_FILE if path is None else path
    try:
        if path.stat().st_size > 40_000 or path.stat().st_mode & 0o077:
            return "invalid"
        data = json.loads(path.read_text())
        if isinstance(data.get("OPENAI_API_KEY"), str) and data["OPENAI_API_KEY"]:
            return "api_key"
        tokens = data.get("tokens") or {}
        if tokens.get("access_token") and tokens.get("refresh_token"):
            return "account"
    except (OSError, ValueError, TypeError, AttributeError):
        pass
    return "missing"


def isolated():
    return os.getenv("ISOLATED_SCHULPILOT_WORKER") == "1" and Path("/run/.containerenv").is_file()


def web_search_enabled(mode=None):
    """Operator policy, independent of the CLI's fixed --search launch flag."""
    configured = os.getenv("CODEX_WEB_SEARCH")
    return configured == "true" if configured is not None else (mode or auth_mode()) == "api_key"


@app.get("/health")
def health():
    # Credential presence is not an authenticated upstream connection test.
    mode = auth_mode()
    search = web_search_enabled(mode)
    result = {
        "isolated": isolated(), "auth_mode": mode, "cli_version": CLI_VERSION,
        "search": search, "cli_search": True,
        "search_policy": "account_bounded" if mode == "account" and search
        else "single_search" if search else "source_only",
    }
    if last_failure is not None:
        result["last_failure"] = last_failure
    return result


def rejected_parameter(raw):
    """Return only an allowlisted parameter, never an upstream error quotation."""
    try:
        value = json.loads(raw)
    except (ValueError, TypeError):
        value = raw.decode("utf-8", errors="replace") if isinstance(raw, bytes) else raw
    # Account responses may use {"detail": "..."}; API responses normally
    # use {"error": {"message": "...", "param": "..."}}. Inspect only these
    # known error fields in memory. No arbitrary value or quotation escapes.
    messages = []
    candidates = [value]
    if isinstance(value, dict):
        candidates.extend(value.get(name) for name in ("error", "detail"))
    for candidate in candidates:
        if isinstance(candidate, str):
            messages.append(candidate)
        elif isinstance(candidate, dict):
            messages.extend(candidate.get(name) for name in ("message", "param", "detail"))
    for name in (
        "max_tool_calls", "parallel_tool_calls", "max_output_tokens", "search_context_size",
        "external_web_access", "text.format", "model", "tools", "reasoning", "input", "store", "stream",
    ):
        if any(isinstance(message, str) and re.search(r"(?<![\w.])" + re.escape(name) + r"(?![\w.])", message)
               for message in messages):
            return name
    return "unknown"


def validate_job(body):
    if set(body) != {
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
    }:
        raise HTTPException(422, "Ungültiger Providerauftrag.")
    if body["auth_mode"] not in ("api_key", "account"):
        raise HTTPException(422, "Ungültige Codex-Anmeldeart.")
    if type(body["web_search"]) is not bool:
        raise HTTPException(422, "Ungültige Suchrichtlinie.")
    if not isinstance(body["model"], str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._/-]{0,159}", body["model"]):
        raise HTTPException(422, "Ungültige Modell-ID.")
    if type(body["max_output_tokens"]) is not int or not 1000 <= body["max_output_tokens"] <= 8000:
        raise HTTPException(422, "Ungültiges Ausgabelimit.")
    if type(body["reserve_micros"]) is not int or not 1000 <= body["reserve_micros"] <= 10_000_000:
        raise HTTPException(422, "Ungültige Kostenreservierung.")
    if body["auth_mode"] == "api_key" and any(
        type(body[k]) is not int or not 0 < body[k] <= 1_000_000_000 for k in ("input_rate", "output_rate")
    ):
        raise HTTPException(422, "Dokumentierte API-Preisobergrenzen fehlen.")
    if (
        not isinstance(body["system"], str)
        or not isinstance(body["payload"], dict)
        or not isinstance(body["schema"], dict)
    ):
        raise HTTPException(422, "Ungültige Auftragsstruktur.")
    if len(json.dumps(body).encode()) > 4_000_000:
        raise HTTPException(413, "Auftrag zu groß.")
    if body["image"] is not None:
        try:
            if not isinstance(body["image"], str) or not base64.b64decode(body["image"], validate=True).startswith(
                b"\xff\xd8"
            ):
                raise ValueError("invalid image")
        except (ValueError, TypeError):
            raise HTTPException(422, "Ungültiges Lernbild.") from None


@app.post("/generate")
def generate(body: dict):
    if not isolated():
        raise HTTPException(503, "Isolierter Containerbetrieb ist erforderlich.")
    validate_job(body)
    mode = auth_mode()
    if mode != body["auth_mode"]:
        raise HTTPException(503, "Separate Codex-Anmeldung fehlt oder passt nicht zum freigegebenen Abrechnungsweg.")
    if body["web_search"] and not web_search_enabled(mode):
        raise HTTPException(503, "Websuche ist für diesen Worker nicht freigegeben.")
    if not slot.acquire(blocking=False):
        raise HTTPException(429, "Isolierter Worker ist belegt.")
    try:
        return run(body)
    finally:
        slot.release()


def upstream_body(body):
    """Allowlist the actual model request; CLI or uploaded instructions cannot add tools."""
    content = [{"type": "input_text", "text": json.dumps(body["payload"], ensure_ascii=False)}]
    if body["image"]:
        content.append(
            {"type": "input_image", "image_url": "data:image/jpeg;base64," + body["image"], "detail": "high"}
        )
    data = {
        "model": body["model"],
        "instructions": body["system"],
        "input": [{"role": "user", "content": content}],
        "store": False,
        "stream": True,
        "tools": ([{"type": "web_search", "external_web_access": True, "search_context_size": "low"}]
                  if body["web_search"] else []),
        "tool_choice": "auto" if body["web_search"] else "none",
        "parallel_tool_calls": False,
        "reasoning": {"effort": "medium"},
        "text": {"format": {"type": "json_schema", "name": "lesson", "strict": True, "schema": body["schema"]}},
    }
    # ChatGPT-managed Responses explicitly rejects max_tool_calls and
    # max_output_tokens. Source-only is the default account policy. Account
    # search needs an explicit operator decision: one upstream response and
    # timeout remain bounded; counting searches afterwards is not a hard cap.
    if body["auth_mode"] == "api_key":
        data["max_output_tokens"] = body["max_output_tokens"]
        if body["web_search"]:
            data["max_tool_calls"] = 1
        bound = len(json.dumps(data).encode()) + 4096 + SEARCH_CONTEXT_TOKENS
        upper = math.ceil((bound * body["input_rate"] + body["max_output_tokens"] * body["output_rate"]) / 1_000_000)
        if upper + (SEARCH_FEE_MICROS if body["web_search"] else 0) > body["reserve_micros"]:
            raise HTTPException(413, "Kostenreservierung einschließlich Websuche reicht nicht aus.")
    return data


def cli_config(port, token):
    return f'''model_provider = "schulpilot"
web_search = "live"
model_reasoning_effort = "medium"
cli_auth_credentials_store = "file"
check_for_update_on_startup = false
[features]
shell_tool = false
unified_exec = false
shell_snapshot = false
apps = false
plugins = false
hooks = false
multi_agent = false
browser_use = false
computer_use = false
image_generation = false
enable_request_compression = false
unbounded_connection_retries = false
api_key_model_discovery = false
[model_providers.schulpilot]
name = "SCHULPILOT isolated one-request gateway"
base_url = "http://127.0.0.1:{port}/v1"
wire_api = "responses"
requires_openai_auth = true
request_max_retries = 0
stream_max_retries = 0
supports_websockets = false
[model_providers.schulpilot.http_headers]
X-Schulpilot-Job = "{token}"
'''


def persist_refreshed_auth(home, original):
    """Keep only the login refresh, without overwriting a concurrent manual login."""
    refreshed = home / "auth.json"
    try:
        new = refreshed.read_bytes()
        if new != original and hmac.compare_digest(
            hashlib.sha256(AUTH_FILE.read_bytes()).digest(), hashlib.sha256(original).digest()
        ):
            temporary = AUTH_FILE.with_name("auth.refreshed")
            temporary.write_bytes(new)
            temporary.chmod(0o600)
            temporary.replace(AUTH_FILE)
    except OSError:
        pass


def run(body):
    global last_failure
    data = upstream_body(body)
    gateway_token = secrets.token_urlsafe(32)
    state = {"calls": 0, "usage": None, "search_calls": None, "completed": False, "http_status": None}
    call_lock = threading.Lock()

    class Gateway(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_POST(self):
            if self.path != "/v1/responses" or not hmac.compare_digest(
                self.headers.get("X-Schulpilot-Job", ""), gateway_token
            ):
                self.send_error(403)
                return
            with call_lock:
                if state["calls"]:
                    self.send_error(429, "One upstream request per job; no retries")
                    return
                state["calls"] += 1
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                self.send_error(400)
                return
            authorization = self.headers.get("Authorization", "")
            if length < 1 or length > 4_500_000 or not authorization.startswith("Bearer "):
                self.send_error(400)
                return
            self.rfile.read(length)
            headers = {"Authorization": authorization, "Content-Type": "application/json"}
            if body["auth_mode"] == "account":
                account = self.headers.get("ChatGPT-Account-Id")
                if account:
                    headers["ChatGPT-Account-Id"] = account
                # Fixed ChatGPT Codex route used by the pinned official CLI.
                url = "https://chatgpt.com/backend-api/codex/responses"
                headers["OpenAI-Beta"] = "responses=experimental"
                headers["originator"] = "codex_cli_rs"
            else:
                url = "https://api.openai.com/v1/responses"
            try:
                with httpx.Client(timeout=125, follow_redirects=False) as client:
                    with client.stream("POST", url, headers=headers, json=data) as response:
                        state["http_status"] = response.status_code
                        self.send_response(response.status_code)
                        self.send_header("Content-Type", "text/event-stream")
                        self.send_header("Connection", "close")
                        self.end_headers()
                        if response.status_code != 200:
                            state["parameter"] = rejected_parameter(response.read()[:8000])
                            # Never send echoed input or credentials into CLI diagnostics.
                            self.wfile.write(b'data: {"type":"error","message":"Codex provider unavailable"}\n\n')
                            return
                        for line in response.iter_lines():
                            if len(line) > 500_000:
                                return
                            if line.startswith("data: "):
                                try:
                                    event = json.loads(line[6:])
                                    if event.get("type") == "response.completed":
                                        result = event.get("response", {})
                                        state["usage"] = result.get("usage")
                                        state["search_calls"] = sum(
                                            item.get("type") == "web_search_call" for item in result.get("output", [])
                                        )
                                        state["completed"] = result.get("status") == "completed"
                                except (ValueError, TypeError, AttributeError):
                                    pass
                            self.wfile.write((line + "\n").encode())
                            self.wfile.flush()
            except (httpx.HTTPError, OSError):
                self.close_connection = True

    gateway = ThreadingHTTPServer(("127.0.0.1", 0), Gateway)
    gateway.daemon_threads = True
    thread = threading.Thread(target=gateway.serve_forever, daemon=True)
    thread.start()
    try:
        with tempfile.TemporaryDirectory(prefix="lesson-", dir="/tmp") as directory:
            root = Path(directory)
            home = root / "home"
            home.mkdir(mode=0o700)
            original = AUTH_FILE.read_bytes()
            (home / "auth.json").write_bytes(original)
            (home / "auth.json").chmod(0o600)
            (home / "config.toml").write_text(cli_config(gateway.server_port, gateway_token))
            schema = root / "schema.json"
            schema.write_text(json.dumps(body["schema"]))
            output = root / "output.json"
            args = [
                "/usr/local/bin/codex",
                "--search",
                "--ask-for-approval",
                "never",
                "exec",
                "--skip-git-repo-check",
                "--ephemeral",
                "--ignore-rules",
                "--sandbox",
                "read-only",
                "--model",
                body["model"],
                "--json",
                "--output-schema",
                str(schema),
                "--output-last-message",
                str(output),
                "--cd",
                str(root),
                "-",
            ]
            environment = {
                "PATH": "/usr/local/bin:/usr/bin:/bin",
                "HOME": str(home),
                "CODEX_HOME": str(home),
                "LANG": "C.UTF-8",
                "TMPDIR": str(root),
            }
            try:
                # No shell, no inherited environment, no sessions or event logs.
                completed = subprocess.run(
                    args,
                    input=b"Return the requested structured lesson.",
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    cwd=root,
                    env=environment,
                    timeout=145,
                    check=False,
                )
                state["cli_exit"] = completed.returncode
                if state["http_status"] in (401, 403):
                    raise HTTPException(503, "Codex-Anmeldung oder Modellberechtigung bitte auf dem Server erneuern.")
                if (
                    not state["completed"]
                    or completed.returncode != 0
                    or not output.exists()
                    or output.stat().st_size > 200_000
                ):
                    raise HTTPException(
                        502, "Codex lieferte keine abgeschlossene gültige Ausgabe. Keine automatische Wiederholung."
                    )
                if (
                    type(state["search_calls"]) is not int
                    or state["search_calls"] < 0
                    or (not body["web_search"] and state["search_calls"] != 0)
                    or (body["auth_mode"] == "api_key" and state["search_calls"] > 1)
                ):
                    raise HTTPException(502, "Codex hat die freigegebene Suchgrenze nicht eingehalten.")
                data = json.loads(output.read_text())
                state["success"] = True
                return {
                    "data": data,
                    "usage": state["usage"] or {},
                    "search_calls": state["search_calls"],
                    "web_search": body["web_search"],
                }
            except (subprocess.TimeoutExpired, ValueError, OSError):
                raise HTTPException(502, "Isolierter Codex-Aufruf fehlgeschlagen.") from None
            finally:
                persist_refreshed_auth(home, original)
    finally:
        last_failure = None if state.get("success") else {
            "http_status": state["http_status"],
            "upstream_calls": state["calls"],
            "cli_exit": state.get("cli_exit"),
            "parameter": state.get("parameter", "unknown"),
        }
        gateway.shutdown()
        gateway.server_close()
        thread.join(timeout=2)


if __name__ == "__main__":
    os.umask(0o007)
    Path("/run/provider/codex.sock").unlink(missing_ok=True)
    config = uvicorn.Config(app, uds="/run/provider/codex.sock", access_log=False, log_level="critical")
    listener = config.bind_socket()
    Path("/run/provider/codex.sock").chmod(0o660)
    uvicorn.Server(config).run(sockets=[listener])
