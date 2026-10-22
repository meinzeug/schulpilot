"""Credential broker outside the offline model-tool container.

No learning-worker, host Git/SSH/deployment socket or private application data is
mounted in the tool container. The account credential is read only in this
process and its metadata-only Codex subprocess. Never log request/response bodies.
"""

import base64
import contextlib
import hashlib
import hmac
import importlib.util
import io
import json
import os
import re
import secrets
import selectors
import shutil
import socket
import socketserver
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler
from pathlib import Path

import httpx
from catalog import auth_bytes, read_catalog
from policy import EFFORT, MAX_CALLS, MAX_SECONDS, MODEL, patch_bytes, podman_command, request_body, synthetic_fault
from source_policy import MAX_ARCHIVE, read_archive

ROOT = Path("/opt/schulpilot-repair")
HOME = Path("/var/lib/schulpilot-repair")
AUTH = HOME / "credentials/auth.json"
CONTROL = Path("/run/schulpilot-repair/control.sock")
SLOT = threading.Lock()
CATALOG_CACHE = None


class UnixHTTP(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True


class JobHTTP(UnixHTTP):
    def __init__(self, address, handler, deadline):
        self.deadline = deadline
        self.handlers = threading.BoundedSemaphore(4)
        self.connections, self.connections_lock = set(), threading.Lock()
        super().__init__(address, handler)

    def process_request(self, request, address):
        if not self.handlers.acquire(False):
            self.shutdown_request(request)
            return
        request.settimeout(max(.1, min(1, self.deadline - time.monotonic())))
        with self.connections_lock:
            self.connections.add(request)
        try:
            super().process_request(request, address)
        except Exception:
            with self.connections_lock:
                self.connections.discard(request)
            self.handlers.release()
            raise

    def process_request_thread(self, request, address):
        try:
            super().process_request_thread(request, address)
        finally:
            with self.connections_lock:
                self.connections.discard(request)
            self.handlers.release()

    def close_connections(self):
        with self.connections_lock:
            connections = list(self.connections)
        for connection in connections:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            connection.close()


def close_upstreams(state, guard):
    with guard:
        clients = list(state.get("clients", ()))
        responses = list(state.get("responses", ()))
    for value in (*responses, *clients):
        try:
            value.close()
        except (OSError, httpx.HTTPError):
            pass


def bounded_read(stream, length, deadline):
    value = bytearray()
    while len(value) < length:
        if time.monotonic() >= deadline:
            raise TimeoutError()
        block = stream.read1(min(65536, length - len(value)))
        if not block:
            raise ValueError("incomplete_body")
        value.extend(block)
    return bytes(value)


def catalog(*, fresh=False):
    global CATALOG_CACHE
    if not fresh and CATALOG_CACHE is not None and time.monotonic() - CATALOG_CACHE[0] < 30:
        return dict(CATALOG_CACHE[1])
    value = read_catalog(ROOT / "bin/codex", AUTH)
    CATALOG_CACHE = (time.monotonic(), value)
    return dict(value)


def neutral_incident(value):
    allowed = {"code", "kind", "function", "exception_category", "source_commit", "release", "first_seen",
               "last_seen", "occurrences", "trace_id", "basis", "id"}
    if not isinstance(value, dict) or set(value) - allowed:
        raise ValueError("incident_scope")
    for key, data in value.items():
        if data is None and key in ("source_commit", "trace_id"):
            continue
        if type(data) not in (str, int) or isinstance(data, str) and (len(data) > 160 or not re.fullmatch(r"[A-Za-z0-9_.:+/-]*", data)):
            raise ValueError("incident_value")
    return value


def verification(image, job, identifier, scope, source, deadline, phase):
    if not scope:
        return {"source": "isolated_worker", "executed": False, "verification_kind": "not_run",
                "passed": 0, "failed": 0, "skipped": 0, "duration_ms": 0}
    import pytest

    spec = importlib.util.spec_from_file_location("observer_tests", ROOT / "observer_tests.py")
    observer = importlib.util.module_from_spec(spec)
    import sys
    sys.modules["observer_tests"] = observer
    spec.loader.exec_module(observer)
    env = {"HOME": str(HOME), "PATH": "/usr/bin:/bin", "XDG_RUNTIME_DIR": "/run/schulpilot-repair-runtime"}
    sequence = 0

    def rpc(value):
        nonlocal sequence
        sequence += 1
        name = "verify-" + identifier + "-" + phase + str(sequence)
        command = ["/usr/bin/podman", "--cgroup-manager=cgroupfs", "run", "--rm", "--name", name,
                   "--label=schulpilot.repair=true", "--pull=never", "--network=none", "--read-only", "--cap-drop=ALL",
                   "--security-opt=no-new-privileges", "--userns=keep-id", "--user", f"{os.getuid()}:{os.getgid()}",
                   "--pids-limit=32", "--memory=512m", "--cpus=1", "--ipc=none", "--interactive",
                   "--tmpfs=/tmp:rw,nosuid,nodev,size=64m,mode=1777",
                   "--env=PYTHONPATH=/source/backend", "--env=PYTHONDONTWRITEBYTECODE=1",
                   "--env=ENVIRONMENT=test", "--env=DATA_DIR=/tmp/data", "--env=DATABASE_URL=sqlite:////tmp/check.sqlite",
                   "--volume", str(source) + ":/source:ro,nosuid,nodev", "--entrypoint=python", image, "/app/candidate_rpc.py"]
        process = None
        try:
            process = subprocess.Popen(command, env=env, cwd=HOME, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                       stderr=subprocess.DEVNULL)
            process.stdin.write(json.dumps(value).encode())
            process.stdin.close()
            output = bytearray()
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ)
                rpc_deadline = min(deadline, time.monotonic() + 8)
                while True:
                    remaining = rpc_deadline - time.monotonic()
                    if remaining <= 0 or not selector.select(remaining):
                        raise ValueError("verification_timeout")
                    block = os.read(process.stdout.fileno(), 16384)
                    if not block:
                        break
                    output.extend(block)
                    if len(output) > 256000:
                        raise ValueError("verification_output")
            process.wait(timeout=max(.1, rpc_deadline - time.monotonic()))
            if process.returncode:
                raise ValueError("candidate_exit")
            return json.loads(output)
        finally:
            subprocess.run(["/usr/bin/podman", "--cgroup-manager=cgroupfs", "rm", "--force", "--time=1", name], env=env,
                           cwd=HOME, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
            if process is not None:
                if process.poll() is None:
                    process.kill()
                    process.wait(timeout=2)
                if process.stdout is not None:
                    process.stdout.close()

    observer.RPC = rpc

    class Counts:
        passed = failed = skipped = 0

        def pytest_runtest_logreport(self, report):
            if report.failed:
                self.failed += 1
            elif report.when == "call" and report.passed:
                self.passed += 1
            elif report.skipped:
                self.skipped += 1

    counts, started = Counts(), time.monotonic()
    previous = os.environ.get("PYTEST_DISABLE_PLUGIN_AUTOLOAD")
    os.environ["PYTEST_DISABLE_PLUGIN_AUTOLOAD"] = "1"
    try:
        # No candidate imports in this interpreter. Both assertions and counts
        # remain outside its namespaces, filesystem and process tree.
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            code = pytest.main([str(ROOT / "observer_tests.py"), "-q", "-p", "no:cacheprovider", "--confcutdir=" + str(ROOT)],
                               plugins=[counts])
        if code not in (0, 1) or counts.passed + counts.failed + counts.skipped != 6:
            raise ValueError("verification_collection")
    finally:
        if previous is None:
            os.environ.pop("PYTEST_DISABLE_PLUGIN_AUTOLOAD", None)
        else:
            os.environ["PYTEST_DISABLE_PLUGIN_AUTOLOAD"] = previous
    return {"source": "isolated_worker", "executed": True, "verification_kind": "pytest",
            "passed": counts.passed, "failed": counts.failed, "skipped": counts.skipped,
            "duration_ms": int((time.monotonic() - started) * 1000)}


def run(body):
    deadline = time.monotonic() + MAX_SECONDS
    state = {"calls": 0, "dispatched": False, "clients": set(), "responses": set()}
    try:
        identifier, commit = body["id"], body["source_commit"]
        if not re.fullmatch(r"[a-f0-9]{32}", identifier) or (body.get("model"), body.get("reasoning_effort")) != (MODEL, EFFORT):
            raise ValueError("invalid_job")
        incident = neutral_incident(body["incident"])
        encoded = json.dumps(incident, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()
        if hashlib.sha256(encoded).hexdigest() != body["incident_digest"]:
            raise ValueError("incident_digest")
        bound = catalog(fresh=True)
        if bound["catalog_fingerprint"] != body["catalog_fingerprint"]:
            return {"status": "failed", "error_code": "catalog_changed", "dispatched": False}
        raw = base64.b64decode(body["source"], validate=True)
        if hashlib.sha256(raw).hexdigest() != body["source_sha256"]:
            raise ValueError("source_digest")
        files = read_archive(raw, commit)
        if body.get("synthetic_fixture") is not None:
            if incident.get("code") != "synthetic_repair" or incident.get("function") != "instructional_decisions.process":
                raise ValueError("synthetic_scope")
            files = synthetic_fault(files, body["synthetic_fixture"])
        image = (ROOT / "image-id").read_text().strip()
        token = secrets.token_urlsafe(32)
        guard = threading.Lock()
        state["active"] = True
        with tempfile.TemporaryDirectory(prefix="job-", dir=HOME / "jobs") as directory:
            job = Path(directory)
            for name in ("baseline", "workspace", "proxy", "incident"):
                (job / name).mkdir(mode=0o700)
            for root in (job / "baseline",):
                for name, value in files.items():
                    target = root / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(value)
            (job / "incident/incident.json").write_bytes(encoded)
            job_metadata = {"source_commit": commit}
            if body.get("synthetic_fixture"):
                job_metadata["synthetic_fixture"] = body["synthetic_fixture"]
            (job / "incident/job.json").write_text(json.dumps(job_metadata))
            (job / "proxy/token").write_text(token)
            (job / "proxy/token").chmod(0o600)

            scope = "instructional_decisions" if incident.get("function") == "instructional_decisions.process" else None
            baseline_check = verification(image, job, identifier, scope, job / "baseline", deadline, "before")
            # Leave time for the fixed post-run regression; all phases share 240s.
            model_deadline = deadline - (65 if scope else 15)
            job_metadata["seconds"] = max(1, min(165, int(model_deadline - time.monotonic())))
            (job / "incident/job.json").write_text(json.dumps(job_metadata))

            class Proxy(BaseHTTPRequestHandler):
                protocol_version = "HTTP/1.0"

                def log_message(self, *_):
                    pass

                def do_POST(self):
                    try:
                        if (self.path != "/v1/responses" or not hmac.compare_digest(self.headers.get("X-Schulpilot-Job", ""), token)
                                or not state["active"] or time.monotonic() >= model_deadline):
                            self.send_error(403)
                            return
                        length = int(self.headers.get("Content-Length", "0"))
                        if not 0 < length <= 4500000:
                            self.send_error(400)
                            return
                        payload = request_body(bounded_read(self.rfile, length, model_deadline))
                        with guard:
                            if state["calls"] >= MAX_CALLS or not state["active"] or time.monotonic() >= model_deadline:
                                self.send_error(429)
                                return
                            state["calls"] += 1
                        auth = json.loads(auth_bytes(AUTH))["tokens"]
                        headers = {"Authorization": "Bearer " + auth["access_token"], "Content-Type": "application/json",
                                   "OpenAI-Beta": "responses=experimental", "originator": "codex_cli_rs"}
                        if auth.get("account_id"):
                            headers["ChatGPT-Account-Id"] = auth["account_id"]
                        client = httpx.Client(timeout=httpx.Timeout(connect=5, read=5, write=5, pool=1),
                                              trust_env=False, follow_redirects=False)
                        response = None
                        with guard:
                            if not state["active"] or time.monotonic() >= model_deadline:
                                client.close()
                                return
                            state["clients"].add(client)
                        try:
                            # Mark before network dispatch; uncertainty keeps hold.
                            state["dispatched"] = True
                            headers["Accept-Encoding"] = "identity"
                            with client.stream("POST", "https://chatgpt.com/backend-api/codex/responses",
                                               headers=headers, json=payload) as response:
                                with guard:
                                    state["responses"].add(response)
                                if response.status_code != 200:
                                    self.send_error(502)
                                    return
                                self.send_response(200)
                                self.send_header("Content-Type", "text/event-stream")
                                self.send_header("Connection", "close")
                                self.end_headers()
                                total = 0
                                # Raw network fragments avoid waiting for an SSE
                                # newline while enforcing the absolute job lease.
                                for block in response.iter_raw():
                                    total += len(block)
                                    if len(block) > 500000 or total > 32000000 or not state["active"] or time.monotonic() >= model_deadline:
                                        break
                                    self.wfile.write(block)
                                    self.wfile.flush()
                        finally:
                            with guard:
                                state["clients"].discard(client)
                                if response is not None:
                                    state["responses"].discard(response)
                            client.close()
                    except Exception:
                        self.close_connection = True

            proxy_path = job / "proxy/responses.sock"
            proxy = JobHTTP(str(proxy_path), Proxy, model_deadline)
            proxy_path.chmod(0o600)
            thread = threading.Thread(target=proxy.serve_forever, daemon=True)
            thread.start()
            stop_watchdog = threading.Event()

            def expire_proxy():
                if not stop_watchdog.wait(max(0, model_deadline - time.monotonic())):
                    with guard:
                        state["active"] = False
                    proxy.close_connections()
                    close_upstreams(state, guard)

            watchdog = threading.Thread(target=expire_proxy, daemon=True)
            watchdog.start()
            command = podman_command(image, job, identifier, os.getuid(), os.getgid())
            timed_out, result = False, None
            try:
                result = subprocess.Popen(command, env={"HOME": str(HOME), "PATH": "/usr/bin:/bin",
                                        "XDG_RUNTIME_DIR": "/run/schulpilot-repair-runtime", "LANG": "C.UTF-8"},
                                        cwd=HOME, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                output = bytearray()
                with selectors.DefaultSelector() as selector:
                    selector.register(result.stdout, selectors.EVENT_READ)
                    while True:
                        remaining = model_deadline - time.monotonic()
                        if remaining <= 0 or not selector.select(remaining):
                            raise subprocess.TimeoutExpired(command, MAX_SECONDS)
                        block = os.read(result.stdout.fileno(), 65536)
                        if not block:
                            break
                        output.extend(block)
                        if len(output) > MAX_ARCHIVE:
                            raise ValueError("output_limit")
                result.wait(timeout=max(.1, model_deadline - time.monotonic()))
            except subprocess.TimeoutExpired:
                timed_out = True
            finally:
                with guard:
                    state["active"] = False
                stop_watchdog.set()
                close_upstreams(state, guard)
                # Always kill the entire container before inspecting/testing output;
                # no surviving model shell can race patch validation.
                subprocess.run(["/usr/bin/podman", "--cgroup-manager=cgroupfs", "rm", "--force", "--time=1", "repair-" + identifier],
                               env={"HOME": str(HOME), "PATH": "/usr/bin:/bin", "XDG_RUNTIME_DIR": "/run/schulpilot-repair-runtime"},
                               cwd=HOME, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
                if result is not None and result.poll() is None:
                    result.kill()
                    result.wait(timeout=3)
                if result is not None and result.stdout is not None:
                    result.stdout.close()
                proxy.close_connections()
                proxy.shutdown()
                proxy.server_close()
                thread.join(timeout=2)
                watchdog.join(timeout=6)
            if timed_out:
                return {"status": "failed", "error_code": "run_timeout", "dispatched": state["dispatched"]}
            if result.returncode:
                return {"status": "failed", "error_code": "run_failed", "dispatched": state["dispatched"]}
            current = read_archive(bytes(output), commit)
            for name, value in current.items():
                target = job / "workspace" / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(value)
            patch, changed, current = patch_bytes(files, job / "workspace", (token.encode(),))
            if body.get("synthetic_fixture") and changed != ["backend/schulpilot/instructional_decisions.py"]:
                raise ValueError("synthetic_patch_scope")
            summary = verification(image, job, identifier, scope, job / "workspace", deadline, "after")
            summary["baseline"] = baseline_check
            after = catalog(fresh=True)
            if after["catalog_fingerprint"] != bound["catalog_fingerprint"]:
                return {"status": "failed", "error_code": "catalog_changed", "dispatched": state["dispatched"]}
            return {"status": "completed", "patch": base64.b64encode(patch).decode(), "test_summary": summary,
                    "dispatched": state["dispatched"], "responses": state["calls"], "cost_source": "unknown"}
    except Exception as error:
        code = "empty_patch" if str(error) == "empty_patch" else "invalid_patch" if isinstance(error, ValueError) else "run_failed"
        return {"status": "failed", "error_code": code, "dispatched": state["dispatched"]}


class Control(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def reply(self, value, status=200):
        raw = json.dumps(value).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        if self.path != "/catalog" or not SLOT.acquire(False):
            self.reply({"available": False}, 503)
            return
        try:
            self.reply(catalog())
        except Exception:
            self.reply({"available": False}, 503)
        finally:
            SLOT.release()

    def do_POST(self):
        if self.path != "/repair" or not SLOT.acquire(False):
            self.reply({"status": "failed", "dispatched": False}, 503)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= MAX_ARCHIVE * 2 + 65536:
                raise ValueError()
            self.reply(run(json.loads(self.rfile.read(length))))
        except Exception:
            self.reply({"status": "failed", "error_code": "run_failed", "dispatched": True})
        finally:
            SLOT.release()


def cleanup_startup():
    env = {"HOME": str(HOME), "PATH": "/usr/bin:/bin", "XDG_RUNTIME_DIR": "/run/schulpilot-repair-runtime"}
    result = subprocess.run(["/usr/bin/podman", "--cgroup-manager=cgroupfs", "ps", "--all", "--quiet",
                             "--filter=label=schulpilot.repair=true"], env=env, cwd=HOME,
                            capture_output=True, timeout=10, check=True)
    if len(result.stdout) > 16384:
        raise ValueError("stale_container_limit")
    identifiers = result.stdout.decode().splitlines()
    if any(not re.fullmatch(r"[a-f0-9]{12,64}", value) for value in identifiers):
        raise ValueError("stale_container_ids")
    for identifier in identifiers:
        subprocess.run(["/usr/bin/podman", "--cgroup-manager=cgroupfs", "rm", "--force", "--time=1", identifier],
                       env=env, cwd=HOME, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5, check=True)
    for path in (HOME / "jobs").iterdir():
        if path.is_dir() and not path.is_symlink() and re.fullmatch(r"job-[A-Za-z0-9_-]+", path.name):
            shutil.rmtree(path)


def main():
    HOME.joinpath("jobs").mkdir(mode=0o700, exist_ok=True)
    cleanup_startup()
    CONTROL.unlink(missing_ok=True)
    with UnixHTTP(str(CONTROL), Control) as server:
        CONTROL.chmod(0o660)
        server.serve_forever()


if __name__ == "__main__":
    main()
