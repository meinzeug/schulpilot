"""Metadata-only native Codex catalog in the credential broker, never tools."""

import hashlib
import hmac
import json
import os
import selectors
import stat
import subprocess
import tempfile
import time
from pathlib import Path

CLI_VERSION = "0.162.1"
MODEL = "gpt-6.1-sol"
EFFORT = "max"


def auth_bytes(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or not 0 < metadata.st_size <= 40000 or metadata.st_mode & 0o077:
            raise ValueError("invalid_credentials")
        with os.fdopen(descriptor, "rb", closefd=False) as stream:
            value = stream.read(40001)
        if len(value) != metadata.st_size:
            raise ValueError("invalid_credentials")
        return value
    finally:
        os.close(descriptor)


def read_catalog(binary, auth_path):
    original = auth_bytes(auth_path)
    data = json.loads(original)
    tokens = data.get("tokens") or {}
    if not all(isinstance(tokens.get(k), str) and tokens[k] for k in ("access_token", "refresh_token")):
        raise ValueError("account_credentials_required")
    if subprocess.run([str(binary), "--version"], capture_output=True, timeout=3, check=True).stdout.strip() != b"codex-cli 0.162.1":
        raise ValueError("cli_version")
    with tempfile.TemporaryDirectory(prefix="catalog-", dir=auth_path.parent) as directory:
        root = Path(directory)
        home = root / "home"
        home.mkdir(mode=0o700)
        (home / "auth.json").write_bytes(original)
        (home / "auth.json").chmod(0o600)
        (home / "config.toml").write_text('''check_for_update_on_startup = false
cli_auth_credentials_store = "file"
web_search = "disabled"
[features]
shell_tool = false
unified_exec = false
apps = false
plugins = false
hooks = false
multi_agent = false
browser_use = false
computer_use = false
image_generation = false
''')
        environment = {"PATH": "/usr/bin:/bin", "HOME": str(home), "CODEX_HOME": str(home), "LANG": "C.UTF-8"}
        process = subprocess.Popen([str(binary), "app-server", "--listen", "stdio://"], cwd=root, env=environment,
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        selector, buffer, total, sequence = selectors.DefaultSelector(), bytearray(), 0, 0
        selector.register(process.stdout, selectors.EVENT_READ)
        deadline = time.monotonic() + 9

        def rpc(method, params, expect=True):
            nonlocal buffer, total, sequence
            identifier = sequence
            sequence += 1
            request = {"jsonrpc": "2.0", "method": method, "params": params}
            if expect:
                request["id"] = identifier
            process.stdin.write(json.dumps(request).encode() + b"\n")
            process.stdin.flush()
            if not expect:
                return None
            while time.monotonic() < deadline:
                while b"\n" in buffer:
                    line, _, rest = buffer.partition(b"\n")
                    buffer = bytearray(rest)
                    message = json.loads(line)
                    if "method" in message and "id" in message:
                        raise ValueError("unexpected_rpc")
                    if "id" in message:
                        if message["id"] != identifier or "error" in message:
                            raise ValueError("catalog_rpc")
                        return message["result"]
                if selector.select(max(0, deadline - time.monotonic())):
                    block = os.read(process.stdout.fileno(), 65536)
                    if not block:
                        break
                    total += len(block)
                    if total > 1024 * 1024:
                        raise ValueError("catalog_limit")
                    buffer.extend(block)
            raise ValueError("catalog_timeout")
        try:
            rpc("initialize", {"clientInfo": {"name": "schulpilot_repair_catalog", "version": "1.0"}})
            rpc("initialized", {}, False)
            models, cursor = [], None
            for _ in range(2):
                params = {"limit": 100, "includeHidden": True}
                if cursor:
                    params["cursor"] = cursor
                page = rpc("model/list", params)
                batch = page.get("data")
                if not isinstance(batch, list) or len(batch) > 100:
                    raise ValueError("catalog_limit")
                models.extend(batch)
                cursor = page.get("nextCursor")
                if cursor is None:
                    break
                if not isinstance(cursor, str) or not 1 <= len(cursor) <= 1024:
                    raise ValueError("catalog_cursor")
            if cursor is not None:
                raise ValueError("catalog_pagination")
            matches = [m for m in models if m.get("model") == MODEL and m.get("hidden") is False
                       and "text" in m.get("inputModalities", ["text", "image"])
                       and any(e.get("reasoningEffort") == EFFORT for e in m.get("supportedReasoningEfforts", []))]
            if len(matches) != 1:
                raise ValueError("model_not_offered")
            bound = {"model": MODEL, "effort": EFFORT, "cli_version": CLI_VERSION,
                     "metadata": matches[0]}
            return {"available": True, "model": MODEL, "reasoning_effort": EFFORT,
                    "source": "isolated_repair_cli", "cli_version": CLI_VERSION,
                    "catalog_fingerprint": hashlib.sha256(json.dumps(bound, sort_keys=True, separators=(",", ":")).encode()).hexdigest()}
        finally:
            selector.close()
            process.terminate()
            try:
                process.wait(timeout=.3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=1)
            for stream in (process.stdin, process.stdout):
                stream.close()
            refreshed = home / "auth.json"
            if refreshed.is_file() and hmac.compare_digest(hashlib.sha256(original).digest(), hashlib.sha256(auth_bytes(auth_path)).digest()):
                new = refreshed.read_bytes()
                if new != original and len(new) < 40000 and isinstance(json.loads(new).get("tokens"), dict):
                    temporary = auth_path.with_suffix(".refreshed")
                    temporary.write_bytes(new)
                    temporary.chmod(0o600)
                    temporary.replace(auth_path)
