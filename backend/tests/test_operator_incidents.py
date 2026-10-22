"""Synthetic operator metadata/repair rights; no external provider requests."""

import hashlib
import json

import pytest
from conftest import HEADERS
from fastapi.testclient import TestClient
from schulpilot import operator_incidents as incidents
from schulpilot.db import DB, Audit, Child, Job, Session, User, now
from schulpilot.main import app
from schulpilot.operator_incidents import OperatorIncident, OperatorRepairRequest
from sqlalchemy import func, select
from test_codex_models import operator as operator_fixture

COMMIT = "a" * 40


@pytest.fixture
def operator():
    yield from operator_fixture.__wrapped__()


@pytest.fixture
def incident_row(household):
    _, child = household
    with DB.begin() as db:
        db.add_all(
            [
                Job(
                    child_id=child["id"],
                    kind="decision",
                    status="failed",
                    payload={"secret": "PRIVATE-QUESTION"},
                    idempotency="synthetic-fault-" + str(i),
                    error="PRIVATE-ANSWER-PROVIDER-TOKEN",
                    error_code=code,
                    created=int(now()) - i,
                )
                for i, code in enumerate(["decision_closed", "decision_closed", None])
            ]
        )
    return child


@pytest.fixture
def ready(monkeypatch):
    monkeypatch.setattr(
        incidents, "release_metadata", lambda: {"source_commit": COMMIT, "release": "synthetic-release"}
    )
    monkeypatch.setattr(
        incidents,
        "repair_catalog",
        lambda: {
            "available": True,
            "model": "gpt-6.1-sol",
            "reasoning_effort": "max",
            "source": "isolated_repair_cli",
            "cli_version": "0.162.1",
            "catalog_fingerprint": "f" * 64,
            "notice": "Synthetischer Worker",
        },
    )


def selected(operator):
    value = operator.get("/api/admin/operator-incidents").json()
    row = next(i for i in value["items"] if i["code"] == "decision_closed")
    detail = operator.get("/api/admin/operator-incidents/" + row["id"]).json()
    return row, detail


def body(detail, key="synthetic-repair-key0001"):
    return {"request_key": key, "basis_snapshot_digest": detail["snapshot_digest"], "source_commit": COMMIT}


def test_historical_projection_groups_before_read_and_never_exposes_private_context(operator, incident_row):
    with DB() as db:
        before = db.scalar(select(func.count()).select_from(Audit))
    value = operator.get("/api/admin/operator-incidents").json()
    assert value["pagination"]["total"] == 2
    assert sorted(r["occurrences"] for r in value["items"]) == [1, 2]
    encoded = json.dumps(value)
    assert not any(s in encoded for s in ["PRIVATE", "child_id", "family_id", "payload", "question", "answer"])
    for row in value["items"]:
        assert row["basis"] == "job_history" and row["source_commit"] is None and row["trace_id"] is None
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Audit)) == before
        assert db.scalar(select(func.count()).select_from(OperatorIncident)) == 0
        assert db.scalar(select(func.count()).select_from(OperatorRepairRequest)) == 0
    assert (
        operator.get("/api/admin/operator-incidents", params={"code": "decision_closed"}).json()["pagination"]["total"]
        == 1
    )
    assert operator.get("/api/admin/operator-incidents", params={"q": "%"}).json()["items"] == []
    assert operator.get("/api/admin/operator-incidents", params={"kind": "private-user-name"}).status_code == 422


def test_parent_child_and_logged_out_cannot_read_or_repair_operator_faults(operator, incident_row, api):
    row, _ = selected(operator)
    path = "/api/admin/operator-incidents/" + row["id"]
    assert api.get("/api/admin/operator-incidents").status_code == 403
    assert api.get(path).status_code == 403
    assert api.post(path + "/repairs", json={}).status_code == 403
    with TestClient(app, headers=HEADERS) as child:
        assert child.get(path).status_code == 401
        login = child.post(
            "/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}
        ).json()
        child.headers["Authorization"] = "Bearer " + login["token"]
        assert child.get(path).status_code == 403


def test_api_error_aggregation_records_category_function_release_trace_without_message(operator, ready):
    try:
        raise ValueError("PRIVATE CHILD PHOTO KEY")
    except Exception as error:
        assert incidents.record_api_failure(error)
        assert incidents.record_api_failure(error)
    value = operator.get("/api/admin/operator-incidents").json()
    assert len(value["items"]) == 1
    item = value["items"][0]
    assert item["occurrences"] == 2 and item["code"] == "internal_error"
    assert item["source_commit"] == COMMIT and item["release"] == "synthetic-release"
    assert len(item["trace_id"]) == 32 and item["exception_category"] == "ValueError"
    assert "PRIVATE" not in json.dumps(value)
    assert item["function"] == "api.unhandled"


def test_explicit_repair_is_revision_bound_idempotent_and_keeps_learning_jobs(operator, incident_row, ready):
    row, detail = selected(operator)
    path = "/api/admin/operator-incidents/" + row["id"] + "/repairs"
    before = operator.get("/api/admin/operator-incidents").json()
    first = operator.post(path, json=body(detail))
    assert first.status_code == 202, first.text
    assert operator.post(path, json=body(detail)).json()["id"] == first.json()["id"]
    assert operator.post(path, json=body(detail, "synthetic-repair-key0002")).json()["id"] == first.json()["id"]
    assert (
        first.json()["status"] == "queued"
        and first.json()["model"] == "gpt-6.1-sol"
        and first.json()["effort"] == "max"
    )
    assert first.json()["test_summary"] == {"source": "not_run", "executed": False}
    with DB() as db:
        repair = db.get(OperatorRepairRequest, first.json()["id"])
        assert repair.requested_session_id is not None and repair.active_slot
        assert repair.catalog_binding["source"] == "isolated_repair_cli"
        assert db.scalar(select(func.count()).select_from(Job)) == 3
        assert db.scalar(select(func.count()).select_from(OperatorRepairRequest)) == 1
        assert "PRIVATE" not in json.dumps(repair.incident_snapshot)
    assert operator.get("/api/admin/operator-incidents").json() == before
    assert operator.post(path, json={**body(detail), "source_commit": "b" * 40}).status_code == 409


@pytest.mark.parametrize("change", ["snapshot", "commit", "catalog", "logout"])
def test_stale_or_unavailable_repair_does_not_queue_or_use_learning_worker(
    operator, incident_row, ready, monkeypatch, change
):
    row, detail = selected(operator)
    path = "/api/admin/operator-incidents/" + row["id"] + "/repairs"
    if change == "snapshot":
        with DB.begin() as db:
            child = db.scalar(select(Child))
            db.add(
                Job(
                    child_id=child.id,
                    kind="decision",
                    status="failed",
                    payload={},
                    idempotency="later-job",
                    error_code="decision_closed",
                )
            )
    elif change == "commit":
        monkeypatch.setattr(
            incidents, "release_metadata", lambda: {"source_commit": "b" * 40, "release": "new-release"}
        )
    elif change == "catalog":
        monkeypatch.setattr(
            incidents, "repair_catalog", lambda: {"available": False, "notice": "Separater Worker nicht bereit"}
        )
    else:
        original = incidents.repair_catalog

        def revoke():
            with DB.begin() as db:
                admin = db.scalar(select(User).where(User.role == "admin"))
                for session in db.scalars(select(Session).where(Session.user_id == admin.id)):
                    session.revoked = True
            return original()

        monkeypatch.setattr(incidents, "repair_catalog", revoke)
    response = operator.post(path, json=body(detail))
    assert response.status_code == {"snapshot": 409, "commit": 409, "catalog": 503, "logout": 401}[change], (
        response.text
    )
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(OperatorRepairRequest)) == 0
        assert all(j.status == "failed" for j in db.scalars(select(Job)))


def completed_patch(operator, detail, row):
    response = operator.post("/api/admin/operator-incidents/" + row["id"] + "/repairs", json=body(detail))
    assert response.status_code == 202, response.text
    identifier = response.json()["id"]
    root = incidents.settings.data_dir / "operator-repairs"
    root.mkdir(exist_ok=True, mode=0o700)
    path = root / (identifier + ".patch")
    content = b"--- a/backend/schulpilot/synthetic.py\n+++ b/backend/schulpilot/synthetic.py\n@@ -1 +1 @@\n-old\n+new\n"
    path.write_bytes(content)
    with DB.begin() as db:
        repair = db.get(OperatorRepairRequest, identifier)
        repair.status = "completed"
        repair.active_slot = None
        repair.artifact_path = str(path)
        repair.artifact_sha256 = hashlib.sha256(content).hexdigest()
        repair.artifact_size = len(content)
        repair.test_summary = {"source": "model_report", "executed": True, "passed": 999, "raw": "PRIVATE"}
    return identifier, path, content


def test_patch_download_and_review_are_hash_bound_never_apply_and_hide_internal_paths(operator, incident_row, ready):
    row, detail = selected(operator)
    identifier, path, content = completed_patch(operator, detail, row)
    endpoint = "/api/admin/operator-incidents/repairs/" + identifier
    value = operator.get(endpoint).json()
    assert value["test_summary"] == {"source": "not_run", "executed": False}
    assert "artifact_path" not in value and "requested_session_id" not in value
    download = operator.get(endpoint + "/patch")
    assert download.status_code == 200 and download.content == content
    result = operator.post(
        endpoint + "/review",
        json={"revision": value["revision"], "artifact_sha256": value["artifact_sha256"], "decision": "approved"},
    )
    assert result.status_code == 200 and result.json()["review_status"] == "approved"
    assert path.read_bytes() == content
    assert (
        operator.post(
            endpoint + "/review",
            json={"revision": value["revision"], "artifact_sha256": value["artifact_sha256"], "decision": "rejected"},
        ).status_code
        == 409
    )
    path.write_bytes(b"changed")
    assert operator.get(endpoint + "/patch").status_code == 409


@pytest.mark.parametrize("unsafe", ["outside", "symlink", "oversized"])
def test_patch_cannot_escape_private_directory_or_size_limit(operator, incident_row, ready, tmp_path, unsafe):
    row, detail = selected(operator)
    identifier, path, content = completed_patch(operator, detail, row)
    if unsafe == "outside":
        outside = tmp_path / path.name
        outside.write_bytes(content)
        with DB.begin() as db:
            db.get(OperatorRepairRequest, identifier).artifact_path = str(outside)
    elif unsafe == "symlink":
        outside = tmp_path / "outside.patch"
        outside.write_bytes(content)
        path.unlink()
        path.symlink_to(outside)
    else:
        path.write_bytes(b"x" * (incidents.MAX_PATCH_BYTES + 1))
    assert operator.get("/api/admin/operator-incidents/repairs/" + identifier + "/patch").status_code == 409


def test_only_actual_worker_test_metadata_is_displayed_without_arbitrary_report_text():
    assert incidents.public_test_summary({"source": "model_report", "executed": True, "passed": 100}) == {
        "source": "not_run",
        "executed": False,
    }
    assert incidents.public_test_summary(
        {
            "source": "isolated_worker",
            "verification_kind": "pytest",
            "executed": True,
            "passed": 4,
            "failed": 0,
            "raw": "PRIVATE",
            "suite": "PRIVATE",
        }
    ) == {"source": "isolated_worker", "verification_kind": "pytest", "executed": True, "passed": 4, "failed": 0}


def test_new_daily_repair_limit_excludes_existing_idempotent_and_active_requests(operator, incident_row, ready):
    row, detail = selected(operator)
    endpoint = "/api/admin/operator-incidents/" + row["id"] + "/repairs"
    first = operator.post(endpoint, json=body(detail))
    assert first.status_code == 202
    assert operator.post(endpoint, json=body(detail, "same-active-different-key")).json()["id"] == first.json()["id"]
    with DB.begin() as db:
        previous = db.get(OperatorRepairRequest, first.json()["id"])
        previous.status, previous.active_slot = "failed", None
    second = operator.post(endpoint, json=body(detail, "second-deliberate-key"))
    assert second.status_code == 202
    with DB.begin() as db:
        previous = db.get(OperatorRepairRequest, second.json()["id"])
        previous.status, previous.active_slot = "failed", None
    assert operator.post(endpoint, json=body(detail, "third-deliberate-key")).status_code == 429
    assert operator.post(endpoint, json=body(detail)).json()["id"] == first.json()["id"]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(OperatorRepairRequest)) == 2


def test_parallel_deliberate_repair_clicks_reuse_one_active_snapshot(operator, incident_row, ready):
    from concurrent.futures import ThreadPoolExecutor

    row, detail = selected(operator)
    endpoint = "/api/admin/operator-incidents/" + row["id"] + "/repairs"

    def submit(index):
        response = operator.post(endpoint, json=body(detail, f"concurrent-deliberate-key{index}"))
        assert response.status_code == 202, response.text
        return response.json()["id"]

    with ThreadPoolExecutor(max_workers=2) as pool:
        identifiers = list(pool.map(submit, [1, 2]))
    assert len(set(identifiers)) == 1
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(OperatorRepairRequest)) == 1


def test_maintenance_preserves_active_repair_and_never_returns_unsafe_patch_path(
    operator, incident_row, ready, tmp_path
):
    row, detail = selected(operator)
    identifier, path, _ = completed_patch(operator, detail, row)
    with DB.begin() as db:
        old = db.get(OperatorRepairRequest, identifier)
        old.created = int(now()) - incidents.RETENTION_SECONDS - 10
        old.artifact_path = str(tmp_path / "not-ours.patch")
    with DB.begin() as db:
        assert incidents.maintenance(db) == []
    with DB() as db:
        assert db.get(OperatorRepairRequest, identifier) is None
    assert path.exists()


def test_coalesced_second_key_keeps_original_result_after_worker_releases_active_slot(operator, incident_row, ready):
    row, detail = selected(operator)
    endpoint = "/api/admin/operator-incidents/" + row["id"] + "/repairs"
    first = operator.post(endpoint, json=body(detail))
    reused = operator.post(endpoint, json=body(detail, "different-client-deliberate-key"))
    assert first.status_code == reused.status_code == 202 and first.json()["id"] == reused.json()["id"]
    with DB.begin() as db:
        repair = db.get(OperatorRepairRequest, first.json()["id"])
        repair.status, repair.active_slot = "completed", None
    replay = operator.post(endpoint, json=body(detail, "different-client-deliberate-key"))
    assert (
        replay.status_code == 202
        and replay.json()["id"] == first.json()["id"]
        and replay.json()["status"] == "completed"
    )
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(OperatorRepairRequest)) == 1


def test_syntax_only_is_not_a_pytest_result_and_baseline_never_leaks_raw_output():
    assert incidents.public_test_summary(
        {
            "source": "isolated_worker",
            "verification_kind": "syntax_only",
            "executed": True,
            "passed": 99,
            "syntax_checked": True,
        }
    ) == {"source": "not_run", "verification_kind": "syntax_only", "executed": False, "syntax_checked": True}
    assert incidents.public_test_summary(
        {
            "source": "isolated_worker",
            "verification_kind": "pytest",
            "executed": True,
            "passed": 4,
            "failed": 0,
            "baseline": {"executed": True, "passed": 3, "failed": 1, "raw": "PRIVATE"},
            "stdout": "PRIVATE",
        }
    ) == {
        "source": "isolated_worker",
        "verification_kind": "pytest",
        "executed": True,
        "passed": 4,
        "failed": 0,
        "baseline": {"executed": True, "passed": 3, "failed": 1},
    }


def test_repair_budget_error_is_neutral_and_arbitrary_worker_error_is_not_exposed():
    row = OperatorRepairRequest(
        id="1" * 32,
        source_incident_key="j-" + "2" * 32,
        incident_snapshot_digest="3" * 64,
        source_commit="4" * 40,
        model="gpt-6.1-sol",
        effort="max",
        status="failed",
        created=1,
        review_status="pending",
        error_code="budget_reached",
    )
    assert incidents.public_repair(row)["error_code"] == "budget_reached"
    row.error_code = "PRIVATE-RUNNER-TRACE"
    assert incidents.public_repair(row)["error_code"] == "run_failed"


@pytest.mark.parametrize("nonregular", ["fifo", "directory"])
def test_patch_special_files_fail_quickly_in_an_independently_bounded_process(tmp_path, nonregular):
    import os
    import subprocess
    import sys

    root = incidents.settings.data_dir / "operator-repairs"
    root.mkdir(exist_ok=True)
    identifier = incidents.uid()
    path = root / (identifier + ".patch")
    if nonregular == "fifo":
        os.mkfifo(path)
    else:
        path.mkdir()
    source = """
import sys
from types import SimpleNamespace
from fastapi import HTTPException
from schulpilot.operator_incidents import patch_bytes
row=SimpleNamespace(id=sys.argv[2],status='completed',artifact_path=sys.argv[1],artifact_sha256='b'*64,artifact_size=100)
try:
    patch_bytes(row)
except HTTPException as error:
    print(error.status_code)
else:
    raise SystemExit('special file accepted')
"""
    result = subprocess.run([sys.executable, "-c", source, str(path), identifier], capture_output=True, timeout=5)
    assert result.returncode == 0 and result.stdout.strip() == b"409"
