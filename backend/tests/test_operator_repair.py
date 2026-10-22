"""Synthetic dispatcher and isolation policies. Never starts Codex or containers."""

import base64
import importlib.util
import io
import json
import sys
import tarfile
from pathlib import Path

import pytest
from schulpilot import operator_repair as repair
from schulpilot import repair_source
from schulpilot.db import DB, ProviderConfig, Session, UsageBucket, User, now
from schulpilot.operator_incidents import OperatorRepairRequest, digest
from sqlalchemy import select

sys.modules.setdefault("source_policy", repair_source)
MODULE_ROOT = Path(__file__).resolve().parents[2] / "workers/repair"


def module(name):
    spec = importlib.util.spec_from_file_location("repair_" + name, MODULE_ROOT / (name + ".py"))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


policy = module("policy")
COMMIT = "a" * 40
CATALOG = {"available": True, "model": "gpt-6.1-sol", "reasoning_effort": "max", "source": "isolated_repair_cli",
           "cli_version": "0.162.1", "catalog_fingerprint": "c" * 64}
FILES = {"backend/schulpilot/example.py": b"value = 1\n", "backend/tests/test_example.py": b"def test_example():\n    assert True\n"}


@pytest.fixture
def queued(monkeypatch):
    monkeypatch.setattr(repair, "repair_model_catalog", lambda: dict(CATALOG))
    monkeypatch.setattr(repair, "release_metadata", lambda: {"source_commit": COMMIT})
    monkeypatch.setattr(repair, "source_bundle", lambda commit: repair_source.archive_bytes(FILES, commit))
    with DB.begin() as db:
        user = User(username="operator-repair-synthetic", display_name="Synthetisch", password_hash="not-a-login",
                    role="admin", verified=True)
        db.add(user)
        db.flush()
        session = Session(user_id=user.id, token_hash="d" * 64, device="synthetic", expires=int(now()) + 3600)
        db.add(session)
        db.flush()
        config = db.get(ProviderConfig, 1)
        config.emergency_stop, config.reserve_micros, config.global_limit_micros = False, 100, 100000
        incident = {"id": "j-" + "a" * 32, "kind": "decision", "code": "decision_flow", "source_commit": None,
                    "function": "instructional_decisions.process", "trace_id": None}
        row = OperatorRepairRequest(source_incident_key=incident["id"], incident_snapshot=incident,
            incident_snapshot_digest=digest(incident), source_commit=COMMIT, requested_by=user.id,
            requested_session_id=session.id, idempotency="a" * 64, request_digest="b" * 64, active_slot="f" * 64,
            model=repair.MODEL, effort=repair.EFFORT, catalog_binding=dict(CATALOG))
        db.add(row)
        db.flush()
        yield_ids = row.id, session.id, user.id
    return yield_ids


def completed():
    return {"status": "completed", "dispatched": True, "patch": base64.b64encode(
        b"--- a/backend/schulpilot/example.py\n+++ b/backend/schulpilot/example.py\n@@ -1 +1 @@\n-value = 1\n+value = 2\n").decode(),
        "test_summary": {"source": "isolated_worker", "verification_kind": "pytest", "executed": True,
                         "passed": 12, "failed": 0, "skipped": 0, "duration_ms": 100,
                         "baseline": {"executed": True, "passed": 11, "failed": 1, "skipped": 0, "duration_ms": 100}}}


def test_dispatch_is_explicit_bound_accounted_and_review_only(queued, monkeypatch):
    requests = []
    monkeypatch.setattr(repair, "worker_request", lambda method, path, body=None: requests.append(body) or completed())
    assert repair.work_one()
    assert not repair.work_one()
    assert len(requests) == 1 and requests[0]["model"] == repair.MODEL
    assert "requested_session_id" not in requests[0] and "child_id" not in requests[0]
    with DB() as db:
        row = db.get(OperatorRepairRequest, queued[0])
        assert row.status == "completed" and row.review_status == "pending"
        assert row.cost_micros is None and row.reserved_micros == 1200
        assert row.execution_slot is row.active_slot is None
        assert row.test_summary["baseline"]["failed"] == 1
        assert Path(row.artifact_path).read_bytes().startswith(b"--- a/")
        assert {b.encumbered_micros for b in db.scalars(select(UsageBucket))} == {1200}


@pytest.mark.parametrize("change", ["revoked", "disabled", "role", "release", "catalog", "stop"])
def test_late_authority_or_source_change_discards_patch_and_retains_unknown_hold(queued, monkeypatch, change):
    def worker(*_):
        with DB.begin() as db:
            if change == "revoked":
                db.get(Session, queued[1]).revoked = True
            elif change == "disabled":
                db.get(User, queued[2]).disabled = True
            elif change == "role":
                db.get(User, queued[2]).role = "parent"
            elif change == "stop":
                db.get(ProviderConfig, 1).emergency_stop = True
        if change == "release":
            monkeypatch.setattr(repair, "release_metadata", lambda: {"source_commit": "b" * 40})
        if change == "catalog":
            monkeypatch.setattr(repair, "repair_model_catalog", lambda: {**CATALOG, "catalog_fingerprint": "d" * 64})
        return completed()
    monkeypatch.setattr(repair, "worker_request", worker)
    assert repair.work_one()
    with DB() as db:
        row = db.get(OperatorRepairRequest, queued[0])
        assert row.status == "failed" and not row.artifact_path
        assert row.cost_micros is None and row.settlement_version == 1
        assert all(b.encumbered_micros == 1200 for b in db.scalars(select(UsageBucket)))


def test_proven_no_dispatch_refunds_once_but_keeps_request_count(queued, monkeypatch):
    monkeypatch.setattr(repair, "worker_request", lambda *_: {"status": "failed", "dispatched": False, "error_code": "run_failed"})
    assert repair.work_one()
    assert repair.interrupt_running() == 0
    with DB() as db:
        row = db.get(OperatorRepairRequest, queued[0])
        assert row.status == "failed" and row.cost_micros == 0 and row.settlement_version == 1
        assert all(b.calls == 1 and b.encumbered_micros == b.unknown_calls == 0 for b in db.scalars(select(UsageBucket)))


def test_restart_interrupts_claim_without_requeue_or_refund(queued):
    with DB.begin() as db:
        row = db.get(OperatorRepairRequest, queued[0])
        repair.reserve(db, row)
        row.status, row.execution_slot = "running", "repair"
    assert repair.interrupt_running() == 1
    assert repair.interrupt_running() == 0
    assert not repair.work_one()
    with DB() as db:
        row = db.get(OperatorRepairRequest, queued[0])
        assert row.status == "failed" and row.error_code == "interrupted"
        assert row.active_slot is row.execution_slot is None
        assert row.cost_micros is None
        assert all(b.encumbered_micros == 1200 for b in db.scalars(select(UsageBucket)))


def test_global_cap_blocks_without_inference_or_fabricated_family(queued, monkeypatch):
    with DB.begin() as db:
        db.get(ProviderConfig, 1).global_limit_micros = 1000
    monkeypatch.setattr(repair, "worker_request", lambda *_: pytest.fail("No inference at exhausted global cap"))
    assert repair.work_one()
    with DB() as db:
        row = db.get(OperatorRepairRequest, queued[0])
        assert row.status == "failed" and row.reserved_micros is None
        assert not list(db.scalars(select(UsageBucket)))


@pytest.mark.parametrize("path", ["../auth.json", "backend/schulpilot/../x.py", "backend/schulpilot/x\ny.py", "app/lib/.secret.dart", "/backend/schulpilot/x.py", "backend/schulpilot//x.py", "deploy/install.py", ".git/config"])
def test_source_transport_rejects_secret_traversal_and_header_injection(path):
    assert not repair_source.allowed_path(path)
    with pytest.raises(ValueError):
        repair_source.archive_bytes({path: b"x"}, COMMIT)


def test_source_package_is_reproducible_bound_and_rejects_links():
    raw = repair_source.archive_bytes(FILES, COMMIT)
    assert raw == repair_source.archive_bytes(FILES, COMMIT)
    assert repair_source.read_archive(raw, COMMIT) == FILES
    with pytest.raises(ValueError):
        repair_source.read_archive(raw, "b" * 40)
    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode="w:gz") as archive:
        entry = tarfile.TarInfo("backend/schulpilot/x.py")
        entry.type, entry.linkname = tarfile.SYMTYPE, "/etc/shadow"
        archive.addfile(entry)
    with pytest.raises(ValueError):
        repair_source.read_archive(stream.getvalue(), COMMIT)


def test_tool_container_has_only_readonly_public_mounts_network_none_and_bounded_tmpfs(tmp_path):
    command = policy.podman_command("sha256:" + "a" * 64, tmp_path, "b" * 32, 1001, 1001)
    assert "--network=none" in command and "--read-only" in command and "--cap-drop=ALL" in command
    volumes = [command[i + 1] for i, item in enumerate(command[:-1]) if item == "--volume"]
    assert len(volumes) == 3 and all(":ro," in v for v in volumes)
    assert all("credentials" not in v and "/auth" not in v and ".git" not in v and "control.sock" not in v for v in volumes)
    assert "--tmpfs=/workspace:rw,nosuid,nodev,size=96m,mode=1777" in command


@pytest.mark.parametrize("change", ["model", "effort", "search", "mcp", "history"])
def test_proxy_enforces_model_effort_and_denies_hosted_tools_or_remote_history(change):
    value = {"model": policy.MODEL, "reasoning": {"effort": "max"}, "input": [], "tools": []}
    if change == "model":
        value["model"] = "substitute"
    elif change == "effort":
        value["reasoning"]["effort"] = "medium"
    elif change in ("search", "mcp"):
        value["tools"] = [{"type": "web_search" if change == "search" else "mcp"}]
    else:
        value["previous_response_id"] = "other-private-chat"
    with pytest.raises(ValueError):
        policy.request_body(json.dumps(value).encode())


def test_proxy_forwards_local_tools_only_and_cannot_gain_account_limits():
    value = policy.request_body(json.dumps({"model": policy.MODEL, "reasoning": {"effort": "max"}, "input": [],
        "tools": [{"type": "function", "name": "shell_command"}], "store": True,
        "max_tool_calls": 999, "max_output_tokens": 99999, "service_tier": "priority"}).encode())
    assert value["store"] is False and value["stream"] is True
    assert not {"max_tool_calls", "max_output_tokens", "service_tier"} & value.keys()


def test_patch_rejects_symlinks_dependency_changes_and_proxy_token(tmp_path):
    root = tmp_path / "work"
    root.mkdir()
    target = root / "backend/schulpilot/example.py"
    target.parent.mkdir(parents=True)
    target.write_text("value = 2\n")
    patch, changed, _ = policy.patch_bytes({"backend/schulpilot/example.py": b"value = 1\n"}, root)
    assert patch.startswith(b"--- a/") and changed == ["backend/schulpilot/example.py"]
    with pytest.raises(ValueError):
        policy.patch_bytes({}, root, (b"value = 2",))
    target.unlink()
    target.symlink_to("/etc/hosts")
    with pytest.raises(ValueError):
        policy.patch_bytes({}, root)
    target.unlink()
    (root / "pyproject.toml").write_text("changed = true")
    with pytest.raises(ValueError):
        policy.patch_bytes({}, root)


def test_model_prose_or_syntax_counts_are_not_pytest_proof():
    value = completed()
    value["test_summary"]["verification_kind"] = "syntax_only"
    with pytest.raises(repair.RepairError):
        repair.checked_result(value)


def test_compressed_extension_bomb_is_bounded_before_tarfile_parse(monkeypatch):
    import gzip
    monkeypatch.setattr(repair_source, "MAX_SOURCE", 512)
    monkeypatch.setattr(repair_source, "MAX_FILE", 128)
    monkeypatch.setattr(repair_source, "MAX_FILES", 1)
    raw = gzip.compress(b"A" * 20000)
    called = []
    monkeypatch.setattr(repair_source.tarfile, "open", lambda **kwargs: called.append(True))
    with pytest.raises(ValueError, match="expanded_archive_limit"):
        repair_source.read_archive(raw, COMMIT)
    assert not called


def test_existing_baseline_tests_cannot_be_modified_or_deleted(tmp_path):
    target = tmp_path / "backend/tests/test_protected.py"
    target.parent.mkdir(parents=True)
    target.write_bytes(b"assert False\n")
    baseline = {"backend/tests/test_protected.py": b"assert True\n"}
    with pytest.raises(ValueError, match="baseline_test_change"):
        policy.patch_bytes(baseline, tmp_path)
    target.unlink()
    with pytest.raises(ValueError, match="baseline_test_change"):
        policy.patch_bytes(baseline, tmp_path)
    target.write_bytes(baseline["backend/tests/test_protected.py"])
    (target.parent / "test_new.py").write_bytes(b"assert 1 == 1\n")
    assert policy.patch_bytes(baseline, tmp_path)[1] == ["backend/tests/test_new.py"]


def test_synthetic_fault_only_changes_copied_exact_guard():
    name = "backend/schulpilot/instructional_decisions.py"
    original = Path(name).read_bytes()
    files = {name: original}
    modified = policy.synthetic_fault(files, "decision-closed-v1")
    assert files[name] == original
    assert b"if False and step" in modified[name]
    assert modified[name].replace(b"if False and step", b"if step") == original
    with pytest.raises(ValueError):
        policy.synthetic_fault({name: b"other revision"}, "decision-closed-v1")


def test_external_observer_assertions_detect_fixed_candidate_fault_without_importing_it(monkeypatch):
    from schulpilot import instructional_decisions as decisions
    observer = module("observer_tests")
    def rpc(value):
        if value["method"] == "schema":
            schema = decisions.DecisionOutput.model_json_schema()
            decisions.schema_refs(schema, value["payload"])
            return {"schema": schema}
        try:
            decisions.validate(value["plan"], value["payload"])
            return {"valid": True}
        except decisions.DecisionPlanError as error:
            return {"valid": False, "code": error.code}
    observer.RPC = rpc
    observer.test_closed_practice_and_unavailable_resources_excluded_before_transport()
    observer.test_unavailable_actions_are_omitted_without_new_questions()
    for fault, code in [("closed", "decision_closed"), ("not_new", "decision_not_new"), ("flow", "decision_flow")]:
        observer.test_strict_assessment_guards(fault, code)
    observer.test_valid_open_practice_remains_possible()
    observer.RPC = lambda _: {"valid": True}
    with pytest.raises(AssertionError):
        observer.test_strict_assessment_guards("closed", "decision_closed")
    assert "schulpilot" not in observer.__dict__


def test_proxy_incomplete_body_has_deadline_and_eof_guards(monkeypatch):
    import time
    sys.modules["catalog"] = module("catalog")
    sys.modules["policy"] = policy
    broker = module("broker")
    with pytest.raises(TimeoutError):
        broker.bounded_read(io.BufferedReader(io.BytesIO(b"x")), 10, time.monotonic() - 1)
    with pytest.raises(ValueError, match="incomplete_body"):
        broker.bounded_read(io.BufferedReader(io.BytesIO(b"x")), 10, time.monotonic() + 1)
    assert broker.bounded_read(io.BufferedReader(io.BytesIO(b"abc")), 3, time.monotonic() + 1) == b"abc"


def test_broker_accepts_only_whitelisted_neutral_historical_metadata():
    sys.modules["catalog"] = module("catalog")
    sys.modules["policy"] = policy
    broker = module("broker")
    assert broker.neutral_incident({"id": "j-" + "a" * 32, "source_commit": None, "trace_id": None})
    with pytest.raises(ValueError):
        broker.neutral_incident({"child_id": "private"})
    with pytest.raises(ValueError):
        broker.neutral_incident({"code": "private user message\n"})


def test_source_bundle_and_credentials_reject_fifo_without_reading(tmp_path, monkeypatch):
    import os
    fake = tmp_path / "backend/schulpilot/operator_repair.py"
    fake.parent.mkdir(parents=True)
    monkeypatch.setattr(repair, "__file__", str(fake))
    os.mkfifo(tmp_path / "repair-source.tar.gz", 0o600)
    with pytest.raises(repair.RepairError) as error:
        repair.source_bundle(COMMIT)
    assert error.value.code == "source_unavailable"
    catalog = module("catalog")
    auth = tmp_path / "auth.json"
    os.mkfifo(auth, 0o600)
    with pytest.raises(ValueError, match="invalid_credentials"):
        catalog.auth_bytes(auth)


def test_proxy_limits_incomplete_handlers_and_closes_all_at_job_end(tmp_path):
    import socket
    import threading
    import time
    from http.server import BaseHTTPRequestHandler
    sys.modules["catalog"] = module("catalog")
    sys.modules["policy"] = policy
    broker = module("broker")
    deadline = time.monotonic() + 3
    class Slow(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass
        def do_POST(self):
            try:
                broker.bounded_read(self.rfile, 100, deadline)
            except (OSError, ValueError, TimeoutError):
                pass
    path = tmp_path / "proxy.sock"
    server = broker.JobHTTP(str(path), Slow, deadline)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    clients = []
    try:
        for _ in range(8):
            connection = socket.socket(socket.AF_UNIX)
            connection.settimeout(1)
            try:
                connection.connect(str(path))
            except BlockingIOError:
                connection.close()
                continue
            try:
                connection.sendall(b"POST /v1/responses HTTP/1.0\r\nContent-Length: 100\r\n\r\nx")
            except BrokenPipeError:
                pass
            clients.append(connection)
            time.sleep(.01)
        assert len(clients) >= 4
        until = time.monotonic() + .3
        while time.monotonic() < until:
            with server.connections_lock:
                assert len(server.connections) <= 4
            time.sleep(.01)
        server.close_connections()
        until = time.monotonic() + 1
        while time.monotonic() < until:
            with server.connections_lock:
                if not server.connections:
                    break
            time.sleep(.01)
        with server.connections_lock:
            assert not server.connections
    finally:
        for connection in clients:
            connection.close()
        server.shutdown()
        server.server_close()
        thread.join(timeout=1)


def test_local_probe_requires_existing_admin_and_is_idempotent_without_source_writes(queued, monkeypatch):
    from schulpilot import operator_repair_probe as probe
    from schulpilot.security import digest as token_hash
    monkeypatch.setattr(probe, "repair_model_catalog", lambda: dict(CATALOG))
    monkeypatch.setattr(probe, "release_metadata", lambda: {"source_commit": COMMIT, "release": "synthetic-release"})
    monkeypatch.setattr(probe, "source_bundle", lambda _: repair_source.archive_bytes(FILES, COMMIT))
    token = "synthetic-existing-admin-token"
    with DB.begin() as db:
        db.get(Session, queued[1]).token_hash = token_hash(token)
    first = probe.queue_probe(token, "synthetic-local-probe-0001")
    second = probe.queue_probe(token, "synthetic-local-probe-0001")
    assert first["id"] == second["id"]
    with DB() as db:
        row = db.get(OperatorRepairRequest, first["id"])
        assert row.catalog_binding["synthetic_fixture"] == "decision-closed-v1"
        assert row.requested_session_id == queued[1]
        assert row.incident_snapshot["code"] == "synthetic_repair"
    with DB.begin() as db:
        db.get(Session, queued[1]).revoked = True
    with pytest.raises(repair.RepairError):
        probe.queue_probe(token, "synthetic-local-probe-0002")


def test_empty_dispatch_poll_never_starts_catalog_or_worker(monkeypatch):
    monkeypatch.setattr(repair, "repair_model_catalog", lambda: pytest.fail("No CLI catalog for empty queue"))
    monkeypatch.setattr(repair, "worker_request", lambda *_: pytest.fail("No worker for empty queue"))
    assert not repair.work_one()


def test_proxy_cleanup_closes_upstream_response_and_client_outside_tool_scope():
    import threading
    sys.modules["catalog"] = module("catalog")
    sys.modules["policy"] = policy
    broker = module("broker")
    closed = []
    class Stream:
        def __init__(self, name):
            self.name = name
        def close(self):
            closed.append(self.name)
    broker.close_upstreams({"clients": {Stream("client")}, "responses": {Stream("response")}}, threading.Lock())
    assert closed == ["response", "client"]


def test_external_pytest_observer_records_real_assertions_and_cannot_read_candidate_report(monkeypatch, tmp_path):
    import os
    import threading
    import time
    from types import SimpleNamespace

    from schulpilot import instructional_decisions as decisions
    sys.modules["catalog"] = module("catalog")
    sys.modules["policy"] = policy
    broker = module("broker")
    monkeypatch.setattr(broker, "ROOT", MODULE_ROOT)
    commands, broken = [], [True]
    class Process:
        returncode = 0
        def __init__(self, command, **kwargs):
            commands.append(command)
            read, self.write = os.pipe()
            self.stdout = os.fdopen(read, "rb")
            process = self
            class Input(io.BytesIO):
                def close(self):
                    value = json.loads(self.getvalue())
                    if value["method"] == "schema":
                        schema = decisions.DecisionOutput.model_json_schema()
                        decisions.schema_refs(schema, value["payload"])
                        answer = {"schema": schema}
                    elif broken[0] and value["plan"]["steps"][0]["question_id"] == "closed":
                        answer = {"valid": True}
                    else:
                        try:
                            decisions.validate(value["plan"], value["payload"])
                            answer = {"valid": True}
                        except decisions.DecisionPlanError as error:
                            answer = {"valid": False, "code": error.code}
                    def write_reply():
                        with os.fdopen(process.write, "wb") as stream:
                            stream.write(json.dumps(answer).encode())
                    process.writer = threading.Thread(target=write_reply, daemon=True)
                    process.writer.start()
                    super().close()
            self.stdin = Input()
        def wait(self, **kwargs):
            self.writer.join(timeout=2)
            assert not self.writer.is_alive()
            return 0
        def poll(self):
            return 0
    monkeypatch.setattr(broker.subprocess, "Popen", Process)
    monkeypatch.setattr(broker.subprocess, "run", lambda *args, **kwargs: SimpleNamespace(returncode=0))
    first = broker.verification("sha256:" + "a" * 64, tmp_path, "b" * 32, "instructional_decisions", tmp_path, time.monotonic() + 30, "before")
    broken[0] = False
    second = broker.verification("sha256:" + "a" * 64, tmp_path, "b" * 32, "instructional_decisions", tmp_path, time.monotonic() + 30, "after")
    assert (first["passed"], first["failed"]) == (5, 1)
    assert (second["passed"], second["failed"]) == (6, 0)
    assert len(commands) == 12
    for command in commands:
        assert "--network=none" in command
        mounts = [command[i + 1] for i, value in enumerate(command[:-1]) if value == "--volume"]
        assert mounts == [str(tmp_path) + ":/source:ro,nosuid,nodev"]
        assert "observer_tests.py" not in str(command) and "verification.xml" not in str(command)


def guarded_runtime():
    return {"container": True, "root_readonly": True, "workspace_fs": "tmpfs", "temporary_fs": "tmpfs",
            "no_new_privs": "1", "cap_eff": 0, "cap_bound": 0, "default_route": False, "interfaces": ["lo"],
            "workspace_size": 96 * 1024 * 1024, "temporary_size": 128 * 1024 * 1024, "readonly_inputs": True}


@pytest.mark.parametrize("key,value", [("container", False), ("root_readonly", False), ("workspace_fs", "ext4"),
    ("temporary_fs", "overlay"), ("no_new_privs", "0"), ("cap_eff", 1), ("cap_bound", 1),
    ("default_route", True), ("interfaces", ["lo", "eth0"]), ("workspace_size", 97 * 1024 * 1024),
    ("temporary_size", 129 * 1024 * 1024), ("readonly_inputs", False)])
def test_container_only_mode_fails_closed_for_missing_outer_guards(key, value):
    agent = module("agent")
    agent.validate_runtime(guarded_runtime())
    with pytest.raises(ValueError, match="outer_container_guard"):
        agent.validate_runtime({**guarded_runtime(), key: value})


def test_agent_rejects_missing_runtime_boundary_before_cli_or_source_copy(monkeypatch):
    agent = module("agent")
    monkeypatch.setattr(agent, "runtime_guards", lambda: (_ for _ in ()).throw(ValueError("outer_container_guard")))
    monkeypatch.setattr(agent.shutil, "copytree", lambda *_a, **_k: pytest.fail("No source copy before guard"))
    monkeypatch.setattr(agent.subprocess, "run", lambda *_a, **_k: pytest.fail("No CLI before guard"))
    with pytest.raises(ValueError, match="outer_container_guard"):
        agent.main()
