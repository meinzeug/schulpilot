"""Experimental isolated Codex provider. No public listener, one upstream call.

Run only in the supplied container, never alongside the development agent.
The CLI gets a one-use local gateway token, never the upstream provider key.
"""

import base64
import json
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

app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
slot = threading.Lock()


@app.post("/generate")
def generate(body: dict):
    if os.getenv("ISOLATED_SCHULPILOT_WORKER") != "1" or not Path("/run/.containerenv").exists():
        raise HTTPException(503, "Isolierter Containerbetrieb ist erforderlich.")
    key_path = Path("/run/secrets/codex_provider_key")
    if not key_path.is_file():
        raise HTTPException(503, "Separate Provider-Authentifizierung fehlt.")
    if set(body) != {
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
    if not isinstance(body["model"], str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._/-]{0,159}", body["model"]):
        raise HTTPException(422, "Ungültige Modell-ID.")
    if not isinstance(body["max_output_tokens"], int) or not 1000 <= body["max_output_tokens"] <= 8000:
        raise HTTPException(422, "Ungültiges Ausgabelimit.")
    if len(json.dumps(body)) > 4_000_000:
        raise HTTPException(413, "Auftrag zu groß.")
    if not slot.acquire(blocking=False):
        raise HTTPException(429, "Isolierter Worker ist belegt.")
    try:
        return run(body, key_path.read_text().strip())
    finally:
        slot.release()


def run(body, api_key):
    gateway_token = secrets.token_urlsafe(32)
    state = {"calls": 0, "usage": None}

    class Gateway(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_POST(self):
            if self.path != "/v1/responses" or self.headers.get("Authorization") != "Bearer " + gateway_token:
                self.send_error(403)
                return
            if state["calls"]:
                self.send_error(429, "One upstream request per job; no retries")
                return
            state["calls"] += 1
            length = int(self.headers.get("Content-Length", "0"))
            if length < 1 or length > 4_500_000:
                self.send_error(413)
                return
            try:
                data = json.loads(self.rfile.read(length))
                # The gateway enforces the model, output cap and absence of ALL
                # tools irrespective of user prompt or CLI defaults.
                data.update(
                    {
                        "model": body["model"],
                        "store": False,
                        "tools": [],
                        "max_output_tokens": body["max_output_tokens"],
                    }
                )
                data.pop("tool_choice", None)
                data.pop("parallel_tool_calls", None)
                data.pop("previous_response_id", None)
                data.pop("conversation", None)
                data["text"] = {
                    "format": {"type": "json_schema", "name": "lesson", "strict": True, "schema": body["schema"]}
                }
                bound = len(json.dumps(data).encode()) + 4096
                upper = (
                    bound * body["input_rate"] + body["max_output_tokens"] * body["output_rate"] + 999999
                ) // 1000000
                if upper > body["reserve_micros"]:
                    self.send_error(413, "Reservation would be exceeded")
                    return
                with httpx.Client(timeout=110, follow_redirects=False) as client:
                    # CLI streaming is handled transparently. Usage is parsed
                    # only from the final completed event, never fabricated.
                    data["stream"] = True
                    with client.stream(
                        "POST",
                        "https://api.openai.com/v1/responses",
                        headers={"Authorization": "Bearer " + api_key},
                        json=data,
                    ) as response:
                        self.send_response(response.status_code)
                        self.send_header("Content-Type", response.headers.get("Content-Type", "text/event-stream"))
                        self.send_header("Connection", "close")
                        self.end_headers()
                        for line in response.iter_lines():
                            if line.startswith("data: "):
                                try:
                                    event = json.loads(line[6:])
                                    if event.get("type") == "response.completed":
                                        state["usage"] = event.get("response", {}).get("usage")
                                except ValueError:
                                    pass
                            self.wfile.write((line + "\n").encode())
                            self.wfile.flush()
            except (httpx.HTTPError, ValueError, OSError, TypeError):
                self.close_connection = True

    gateway = ThreadingHTTPServer(("127.0.0.1", 0), Gateway)
    thread = threading.Thread(target=gateway.serve_forever, daemon=True)
    thread.start()
    try:
        with tempfile.TemporaryDirectory(prefix="lesson-", dir="/tmp") as directory:
            root = Path(directory)
            home = root / "home"
            home.mkdir(mode=0o700)
            schema = root / "schema.json"
            schema.write_text(json.dumps(body["schema"]))
            output = root / "output.json"
            config = f"""model_provider = "schulpilot"
web_search = "disabled"
[features]
shell_tool = false
unified_exec = false
shell_snapshot = false
[model_providers.schulpilot]
name = "SCHULPILOT isolated one-request gateway"
base_url = "http://127.0.0.1:{gateway.server_port}/v1"
wire_api = "responses"
env_key = "SCHULPILOT_GATEWAY_TOKEN"
request_max_retries = 0
stream_max_retries = 0
supports_websockets = false
"""
            (home / "config.toml").write_text(config)
            args = [
                "/usr/local/bin/codex",
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
            ]
            if body["image"]:
                image = root / "material.jpg"
                image.write_bytes(base64.b64decode(body["image"], validate=True))
                args.extend(["--image", str(image)])
            args.append("-")
            environment = {
                "PATH": "/usr/local/bin:/usr/bin:/bin",
                "HOME": str(home),
                "CODEX_HOME": str(home),
                "SCHULPILOT_GATEWAY_TOKEN": gateway_token,
                "LANG": "C.UTF-8",
            }
            prompt = body["system"] + "\nUNTRUSTED_LEARNING_DATA:\n" + json.dumps(body["payload"], ensure_ascii=False)
            try:
                # argv + stdin only. Never shell=True, no interpolation, no
                # developer auth.json, no host home or project configuration.
                with (root / "events.jsonl").open("wb") as events:
                    completed = subprocess.run(
                        args,
                        input=prompt.encode(),
                        stdout=events,
                        stderr=subprocess.DEVNULL,
                        cwd=root,
                        env=environment,
                        timeout=145,
                        check=False,
                    )
                if completed.returncode != 0 or not output.exists() or output.stat().st_size > 200_000:
                    raise HTTPException(502, "Codex lieferte keine gültige Ausgabe. Keine automatische Wiederholung.")
                return {"data": json.loads(output.read_text()), "usage": state["usage"] or {}}
            except (subprocess.TimeoutExpired, ValueError, OSError):
                raise HTTPException(502, "Isolierter Codex-Aufruf fehlgeschlagen.") from None
    finally:
        gateway.shutdown()
        gateway.server_close()
        thread.join(timeout=2)


if __name__ == "__main__":
    uvicorn.run(app, uds="/run/provider/codex.sock", access_log=False, log_level="warning")
