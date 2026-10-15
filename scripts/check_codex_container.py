"""Run via podman exec stdin, with fixed fake logins and an in-memory upstream.

Tests the real pinned CLI inside its production container. No provider access,
child data, public endpoint or permanent credential modifications.
"""

import base64
import json
import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, "/app")
import worker  # noqa: E402

assert worker.isolated() and os.geteuid() != 0
capabilities = next(
    line.split()[1] for line in Path("/proc/self/status").read_text().splitlines() if line.startswith("CapEff:")
)
assert int(capabilities, 16) == 0
calls = []


class ArtificialUpstream:
    status_code = 200

    def __enter__(self):
        return self

    def __exit__(self, *_):
        pass

    def stream(self, method, url, headers, json):
        if url.startswith("https://api.openai.com/"):
            assert json["max_tool_calls"] == 1
            assert json["tools"][0]["type"] == "web_search"
        else:
            assert "max_tool_calls" not in json
            assert json["tools"] == [] and json["tool_choice"] == "none"
        calls.append(url)
        return self

    def iter_lines(self):
        message = {
            "id": "msg_synthetic",
            "type": "message",
            "role": "assistant",
            "status": "completed",
            "content": [{"type": "output_text", "text": '{"value":"six"}', "annotations": []}],
        }
        for event in [
            {"type": "response.created", "response": {"id": "resp_synthetic", "status": "in_progress", "output": []}},
            {"type": "response.output_item.done", "output_index": 0, "item": message},
            {
                "type": "response.completed",
                "response": {
                    "id": "resp_synthetic",
                    "status": "completed",
                    "output": [message],
                    "usage": {"input_tokens": 100, "output_tokens": 30, "total_tokens": 130},
                },
            },
        ]:
            yield "data: " + json.dumps(event)
            yield ""


with tempfile.TemporaryDirectory(prefix="synthetic-cli-check-", dir="/tmp") as root:
    auth = Path(root) / "auth.json"
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
    logins = {
        "api_key": {"auth_mode": "apikey", "OPENAI_API_KEY": "SYNTHETIC-NOT-A-REAL-KEY"},
        "account": {
            "auth_mode": "chatgpt",
            "OPENAI_API_KEY": None,
            "tokens": {
                "id_token": token,
                "access_token": token,
                "refresh_token": "synthetic-refresh",
                "account_id": "synthetic-account",
            },
            "last_refresh": datetime.now(timezone.utc).isoformat(),
        },
    }
    for mode, login in logins.items():
        auth.write_text(json.dumps(login))
        auth.chmod(0o600)
        body = {
            "auth_mode": mode,
            "web_search": mode == "api_key",
            "model": "synthetic-model",
            "system": "Synthetic test only.",
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
        with (
            patch.object(worker, "AUTH_FILE", auth),
            patch.object(worker.httpx, "Client", lambda **_: ArtificialUpstream()),
        ):
            result = worker.run(body)
        assert result["data"] == {"value": "six"} and result["search_calls"] == 0
        print(json.dumps({"test": "real_cli_simulated_upstream", "auth_mode": mode, "passed": True}))
assert len(calls) == 2
print(json.dumps({"isolation": "non-root, no capabilities", "live_provider_calls": 0, "passed": True}))
