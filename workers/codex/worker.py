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
import selectors
import subprocess
import tempfile
import threading
import time
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
CATALOG_TIMEOUT = 9
CATALOG_CACHE_SECONDS = 30
CATALOG_OUTPUT_LIMIT = 1024 * 1024
CATALOG_RESPONSE_LIMIT = 256 * 1024
catalog_cache = None


def reasoning_effort(body):
    # The pinned CLI defines ReasoningEffort as an advertised nonempty string,
    # not a fixed enum. The backend checks membership when saving a route.
    # Older queued jobs keep their already-tested medium setting without a
    # catalog lookup or a second acquisition of the shared worker slot.
    value = body.get("reasoning_effort", "medium")
    if not isinstance(value, str) or not re.fullmatch(r"[a-z][a-z0-9_-]{0,31}", value):
        raise HTTPException(422, "Ungültige Codex-Denkstufe.")
    return value


def auth_mode(path=None):
    path = AUTH_FILE if path is None else path
    try:
        if path.stat().st_size > 40_000 or path.stat().st_mode & 0o077:
            return "invalid"
        data = json.loads(path.read_text())
        if isinstance(data.get("OPENAI_API_KEY"), str) and data["OPENAI_API_KEY"]:
            return "api_key"
        tokens = data.get("tokens") or {}
        if all(isinstance(tokens.get(name), str) and tokens[name] for name in ("access_token", "refresh_token")):
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
    if set(body) - {"reasoning_effort"} != {
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
    reasoning_effort(body)
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
    content = [{"type": "input_text", "text": json.dumps(body["payload"], ensure_ascii=False, separators=(",", ":"))}]
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
        "reasoning": {"effort": reasoning_effort(body)},
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


def cli_config(port, token, effort="medium"):
    effort = reasoning_effort({"reasoning_effort": effort})
    return f'''model_provider = "schulpilot"
web_search = "live"
model_reasoning_effort = {json.dumps(effort)}
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
        if auth_mode(refreshed) not in ("account", "api_key"):
            return
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


def cli_environment(home, root):
    return {
        "PATH": "/usr/local/bin:/usr/bin:/bin",
        "HOME": str(home),
        "CODEX_HOME": str(home),
        "LANG": "C.UTF-8",
        "TMPDIR": str(root),
    }


def catalog_config():
    # Use the native provider and the worker's own login. A custom Responses
    # gateway can cause model/list to return the bundled fallback catalog.
    # model/list itself is metadata, never proof of inference entitlement.
    return '''cli_auth_credentials_store = "file"
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
unbounded_connection_retries = false
[analytics]
enabled = false
'''


class CatalogRPC:
    """Bounded newline JSON-RPC reader; no server requests are executed."""

    def __init__(self, process, deadline):
        self.process = process
        self.deadline = deadline
        self.buffer = b""
        self.total = 0
        self.messages = 0
        self.selector = selectors.DefaultSelector()
        self.selector.register(process.stdout, selectors.EVENT_READ)

    def close(self):
        self.selector.close()

    def send(self, method, params, request_id=None):
        if method not in ("initialize", "initialized", "model/list"):
            raise ValueError("unsupported metadata method")
        message = {"method": method, "params": params}
        if request_id is not None:
            message["id"] = request_id
        self.process.stdin.write(json.dumps(message, separators=(",", ":")).encode() + b"\n")
        self.process.stdin.flush()

    def result(self, request_id):
        while time.monotonic() < self.deadline:
            if b"\n" not in self.buffer:
                if not self.selector.select(max(0, self.deadline - time.monotonic())):
                    break
                chunk = os.read(self.process.stdout.fileno(), 65_536)
                if not chunk:
                    break
                self.total += len(chunk)
                if self.total > CATALOG_OUTPUT_LIMIT:
                    raise ValueError("metadata output limit")
                self.buffer += chunk
            while b"\n" in self.buffer:
                line, self.buffer = self.buffer.split(b"\n", 1)
                self.messages += 1
                if self.messages > 1000:
                    raise ValueError("metadata message limit")
                message = json.loads(line)
                if not isinstance(message, dict):
                    raise ValueError("invalid metadata message")
                if "method" in message and "id" in message:
                    raise ValueError("unexpected server request")
                if "id" in message:
                    if message["id"] != request_id or "error" in message or "result" not in message:
                        raise ValueError("metadata request failed")
                    return message["result"]
        raise TimeoutError("metadata deadline")


def normalize_catalog(raw_models):
    if not isinstance(raw_models, list) or not 1 <= len(raw_models) <= 200:
        raise ValueError("invalid model count")
    models, seen = [], set()
    for raw in raw_models:
        if not isinstance(raw, dict):
            raise ValueError("invalid model metadata")
        model_id, name = raw.get("model"), raw.get("displayName")
        options, default = raw.get("supportedReasoningEfforts"), raw.get("defaultReasoningEffort")
        # The wire model identifier can differ from the catalog's UI identifier.
        if (
            not isinstance(model_id, str)
            or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._/-]{0,159}", model_id)
            or model_id in seen
            or not isinstance(name, str) or not 1 <= len(name) <= 160 or any(ord(c) < 32 for c in name)
            or not isinstance(options, list) or len(options) > 32
            or type(raw.get("hidden")) is not bool
        ):
            raise ValueError("invalid model metadata")
        efforts = []
        for option in options:
            if not isinstance(option, dict):
                raise ValueError("invalid reasoning option")
            value = reasoning_effort({"reasoning_effort": option.get("reasoningEffort")})
            if value in efforts:
                raise ValueError("duplicate reasoning option")
            efforts.append(value)
        default = reasoning_effort({"reasoning_effort": default})
        if efforts and default not in efforts:
            raise ValueError("invalid default reasoning effort")
        # This is the documented backwards-compatible model/list fallback.
        # An explicit empty/text-only list must not gain image capability.
        modalities = raw.get("inputModalities", ["text", "image"])
        if (
            not isinstance(modalities, list) or len(modalities) > 3
            or any(not isinstance(item, str) or item not in ("text", "image", "audio") for item in modalities)
            or len(set(modalities)) != len(modalities)
        ):
            raise ValueError("invalid input modalities")
        seen.add(model_id)
        models.append({
            "id": model_id, "name": name, "reasoning_efforts": efforts,
            "default_reasoning_effort": default, "input_modalities": modalities,
            "hidden": raw["hidden"],
        })
    result = {"models": models, "source": "codex_cli", "cli_version": CLI_VERSION}
    if len(json.dumps(result, ensure_ascii=False).encode()) > CATALOG_RESPONSE_LIMIT:
        raise ValueError("normalized metadata output limit")
    return result


def read_catalog(original):
    deadline = time.monotonic() + CATALOG_TIMEOUT
    with tempfile.TemporaryDirectory(prefix="catalog-", dir="/tmp") as directory:
        root = Path(directory)
        home = root / "home"
        home.mkdir(mode=0o700)
        (home / "auth.json").write_bytes(original)
        (home / "auth.json").chmod(0o600)
        (home / "config.toml").write_text(catalog_config())
        process, rpc = None, None
        try:
            process = subprocess.Popen(
                ["/usr/local/bin/codex", "app-server", "--listen", "stdio://"],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                cwd=root, env=cli_environment(home, root),
            )
            rpc = CatalogRPC(process, deadline)
            rpc.send("initialize", {"clientInfo": {
                "name": "schulpilot_catalog", "title": "SCHULPILOT model catalog", "version": "1.0",
            }}, 0)
            if not isinstance(rpc.result(0), dict):
                raise ValueError("invalid initialization")
            rpc.send("initialized", {})
            models, cursors = [], set()
            cursor = None
            for page in range(2):
                params = {"limit": 100, "includeHidden": True}
                if cursor is not None:
                    params["cursor"] = cursor
                rpc.send("model/list", params, page + 1)
                result = rpc.result(page + 1)
                if not isinstance(result, dict) or not isinstance(result.get("data"), list):
                    raise ValueError("invalid metadata page")
                models.extend(result["data"])
                if len(result["data"]) > 100 or len(models) > 200:
                    raise ValueError("metadata page limit")
                cursor = result.get("nextCursor")
                if cursor is None:
                    return normalize_catalog(models)
                if not isinstance(cursor, str) or not 1 <= len(cursor) <= 1024 or cursor in cursors:
                    raise ValueError("invalid metadata cursor")
                cursors.add(cursor)
            raise ValueError("metadata pagination limit")
        finally:
            if rpc is not None:
                rpc.close()
            try:
                if process is not None:
                    try:
                        process.terminate()
                        process.wait(timeout=0.25)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=0.25)
                    finally:
                        for stream in (process.stdin, process.stdout):
                            if stream is not None:
                                stream.close()
            finally:
                # A failed/timed-out metadata request can still rotate a valid
                # worker credential. Save it after shutdown, under slot.
                persist_refreshed_auth(home, original)


@app.get("/models")
def models():
    global catalog_cache
    unavailable = "Der Codex-Modellkatalog ist gerade nicht erreichbar. Bitte später erneut laden."
    if not isolated():
        raise HTTPException(503, "Isolierter Containerbetrieb ist erforderlich.")
    if auth_mode() not in ("account", "api_key"):
        raise HTTPException(503, "Separate Codex-Anmeldung fehlt.")
    try:
        original = AUTH_FILE.read_bytes()
        fingerprint = hashlib.sha256(original).digest()
        cached = catalog_cache
        if cached and hmac.compare_digest(cached[0], fingerprint) and time.monotonic() < cached[1]:
            return json.loads(cached[2])
        if not slot.acquire(blocking=False):
            raise HTTPException(429, "Isolierter Worker ist belegt.")
        try:
            # A generation may have refreshed the login between the initial
            # cache check and our acquisition. Never copy that stale login.
            if auth_mode() not in ("account", "api_key"):
                raise ValueError("worker login changed")
            original = AUTH_FILE.read_bytes()
            fingerprint = hashlib.sha256(original).digest()
            result = read_catalog(original)
            catalog_cache = (fingerprint, time.monotonic() + CATALOG_CACHE_SECONDS, json.dumps(result).encode())
            return result
        finally:
            slot.release()
    except HTTPException as error:
        if error.status_code == 429:
            raise
        raise HTTPException(503, unavailable) from None
    except (OSError, ValueError, TypeError, AttributeError, TimeoutError, subprocess.SubprocessError):
        # Metadata/error payloads can include account details; never relay them.
        raise HTTPException(503, unavailable) from None


def run(body):
    global last_failure
    data = upstream_body(body)
    gateway_token = secrets.token_urlsafe(32)
    state = {"calls": 0, "usage": None, "search_calls": None, "completed": False, "http_status": None}
    call_lock = threading.Lock()
    state["failure_code"] = "unknown"

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
            (home / "config.toml").write_text(cli_config(gateway.server_port, gateway_token, reasoning_effort(body)))
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
            environment = cli_environment(home, root)
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
                    state["failure_code"] = "invalid_output" if state["completed"] else "provider_unavailable"
                    raise HTTPException(502, "Codex lieferte keine abgeschlossene gültige Ausgabe. Keine automatische Wiederholung.", headers={"X-Schulpilot-Failure": state["failure_code"]})
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
            except subprocess.TimeoutExpired:
                state["failure_code"] = "provider_timeout"
                raise HTTPException(502, "Der begrenzte Codex-Aufruf hat sein Zeitlimit erreicht.", headers={"X-Schulpilot-Failure":"provider_timeout"}) from None
            except (ValueError, OSError):
                state["failure_code"] = "invalid_output"
                raise HTTPException(502, "Isolierter Codex-Aufruf fehlgeschlagen.", headers={"X-Schulpilot-Failure":"invalid_output"}) from None
            finally:
                persist_refreshed_auth(home, original)
    finally:
        last_failure = None if state.get("success") else {
            "http_status": state["http_status"],
            "upstream_calls": state["calls"],
            "cli_exit": state.get("cli_exit"),
            "parameter": state.get("parameter", "unknown"),
            "failure_code": state["failure_code"],
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
