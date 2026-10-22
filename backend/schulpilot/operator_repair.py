"""Separate operator repair dispatcher; never a child job or automatic retry.

The external credential broker is a different trust boundary from the tool
container. Only a committed allowlisted source bundle and neutral incident leave
this process. Successful output is a review artifact, never an applied change.
"""

import base64
import hashlib
import json
import os
import re
import stat
import tarfile
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

import httpx
from sqlalchemy import select, text, update
from sqlalchemy.exc import IntegrityError

from .config import settings
from .db import DB, ProviderConfig, Session, UsageBucket, User, engine, now
from .operator_incidents import OperatorRepairRequest, digest, release_metadata
from .repair_source import MAX_ARCHIVE, MAX_PATCH, read_archive
from .security import audit, insert_ignore

MODEL, EFFORT = "gpt-6.1-sol", "max"
MAX_RESPONSES, DEADLINE = 12, 240
SOURCE = "isolated_repair_cli"


class RepairError(Exception):
    def __init__(self, code, *, not_sent=False):
        self.code, self.not_sent = code, not_sent
        super().__init__(code)


def socket_path():
    value = os.getenv("OPERATOR_REPAIR_SOCKET", "")
    if not value or not Path(value).is_absolute():
        raise RepairError("worker_unavailable", not_sent=True)
    return value


def worker_request(method, path, body=None):
    try:
        with httpx.Client(transport=httpx.HTTPTransport(uds=socket_path()), timeout=DEADLINE + 30,
                          follow_redirects=False, trust_env=False) as client:
            with client.stream(method, "http://repair" + path, json=body) as reply:
                content = bytearray()
                for block in reply.iter_bytes():
                    content.extend(block)
                    if len(content) > MAX_PATCH * 2 + 65536:
                        raise RepairError("invalid_patch")
                if reply.status_code != 200:
                    raise RepairError("worker_unavailable")
                value = json.loads(content)
                if not isinstance(value, dict):
                    raise RepairError("run_failed")
                return value
    except (httpx.HTTPError, ValueError, OSError):
        # A timeout is not evidence that no inference happened.
        raise RepairError("worker_unavailable") from None


def repair_model_catalog():
    try:
        value = worker_request("GET", "/catalog")
        if (value.get("available") is not True or value.get("model") != MODEL
                or value.get("reasoning_effort") != EFFORT or value.get("source") != SOURCE
                or value.get("cli_version") != "0.162.1"
                or not re.fullmatch(r"[a-f0-9]{64}", str(value.get("catalog_fingerprint", "")))):
            raise RepairError("catalog_changed")
        # Metadata alone does not attest inference usability.
        return {name: value[name] for name in
                ("available", "model", "reasoning_effort", "source", "cli_version", "catalog_fingerprint")}
    except RepairError:
        return {"available": False, "model": None, "reasoning_effort": EFFORT, "source": SOURCE,
                "cli_version": None, "notice": "Separater Reparaturworker nicht verfügbar."}


def source_bundle(commit):
    path = Path(__file__).resolve().parents[2] / "repair-source.tar.gz"
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        try:
            metadata = os.fstat(descriptor)
            if not stat.S_ISREG(metadata.st_mode) or not 0 < metadata.st_size <= MAX_ARCHIVE:
                raise ValueError()
            with os.fdopen(descriptor, "rb", closefd=False) as stream:
                raw = stream.read(MAX_ARCHIVE + 1)
        finally:
            os.close(descriptor)
        read_archive(raw, commit)
        return raw
    except (OSError, ValueError, TypeError, EOFError, tarfile.TarError, RecursionError):
        raise RepairError("source_unavailable", not_sent=True) from None


def authorized(db, row):
    user = db.get(User, row.requested_by, populate_existing=True) if row.requested_by else None
    session = db.get(Session, row.requested_session_id, populate_existing=True) if row.requested_session_id else None
    if (not user or user.role != "admin" or not user.verified or user.disabled or not session
            or session.user_id != user.id or session.revoked or session.expires <= now()
            or session.seen < now() - 7 * 86400):
        raise RepairError("access_changed", not_sent=True)
    if (release_metadata()["source_commit"] != row.source_commit
            or digest(row.incident_snapshot) != row.incident_snapshot_digest):
        raise RepairError("source_unavailable", not_sent=True)


def reserve(db, row):
    config = db.get(ProviderConfig, 1, populate_existing=True)
    if not config or config.emergency_stop or not config.reserve_micros or config.reserve_micros <= 0:
        raise RepairError("run_failed", not_sent=True)
    # One account call has unknown USD. Conservatively hold twelve existing
    # per-call reservations; never invent a household or change the global cap.
    amount = config.reserve_micros * MAX_RESPONSES
    period = datetime.now(timezone.utc)
    buckets = ["global:" + period.strftime("%Y-%m"), "operator-repair:" + period.strftime("%Y-%m-%d")]
    for name, limit, calls in ((buckets[0], config.global_limit_micros, 1000000), (buckets[1], amount * 2, 2)):
        insert_ignore(db, UsageBucket, {"id": name, "calls": 0, "encumbered_micros": 0,
                                      "known_cost_micros": 0, "unknown_calls": 0})
        if not db.execute(update(UsageBucket).where(UsageBucket.id == name, UsageBucket.calls < calls,
                UsageBucket.encumbered_micros + amount <= limit).values(calls=UsageBucket.calls + 1,
                encumbered_micros=UsageBucket.encumbered_micros + amount,
                unknown_calls=UsageBucket.unknown_calls + 1)).rowcount:
            raise RepairError("budget_reached", not_sent=True)
    row.reserved_micros, row.budget_bucket_ids = amount, buckets
    row.cost_source = "unknown"
    row.catalog_binding = {**row.catalog_binding, "provider_revision": config.revision}


def finish(db, row, *, code=None, not_sent=False):
    if row.settlement_version == 0 and row.reserved_micros:
        row.settlement_version = 1
        if not_sent:
            for identifier in row.budget_bucket_ids or []:
                db.execute(update(UsageBucket).where(UsageBucket.id == identifier).values(
                    encumbered_micros=UsageBucket.encumbered_micros - row.reserved_micros,
                    unknown_calls=UsageBucket.unknown_calls - 1))
            row.cost_micros, row.cost_source = 0, "cancelled"
    row.status, row.error_code = ("failed" if code else "completed"), code
    row.finished, row.active_slot, row.execution_slot = int(now()), None, None
    audit(db, row.requested_by, "operator.repair_finished", row.id)


def interrupt_running():
    """Call once in the exclusive dispatcher at startup; no requeue/retry."""
    with DB.begin() as db:
        rows = db.scalars(select(OperatorRepairRequest).where(OperatorRepairRequest.status == "running")
                          .with_for_update()).all()
        for row in rows:
            finish(db, row, code="interrupted")
        return len(rows)


def checked_result(value):
    if value.get("status") != "completed":
        code = value.get("error_code")
        if code not in {"run_timeout", "invalid_patch", "empty_patch", "catalog_changed", "run_failed"}:
            code = "run_failed"
        raise RepairError(code, not_sent=value.get("dispatched") is False)
    try:
        patch = base64.b64decode(value["patch"], validate=True)
        if not 1 <= len(patch) <= MAX_PATCH or b"\x00" in patch:
            raise ValueError()
        patch.decode("utf-8")
        summary = value["test_summary"]
        if (not isinstance(summary, dict) or summary.get("source") != "isolated_worker"
                or type(summary.get("executed")) is not bool
                or any(type(summary.get(k)) is not int or not 0 <= summary[k] <= 1000000
                       for k in ("passed", "failed", "skipped", "duration_ms"))):
            raise ValueError()
        public = {k: summary[k] for k in ("source", "executed", "passed", "failed", "skipped", "duration_ms")}
        kind = summary.get("verification_kind")
        if kind not in ("pytest", "not_run", "syntax_only") or (summary["executed"] and kind != "pytest"):
            raise ValueError()
        public["verification_kind"] = kind
        baseline = summary.get("baseline")
        if isinstance(baseline, dict):
            if (type(baseline.get("executed")) is not bool or any(type(baseline.get(k)) is not int
                    or not 0 <= baseline[k] <= 1000000 for k in ("passed", "failed", "skipped", "duration_ms"))):
                raise ValueError()
            public["baseline"] = {k: baseline[k] for k in ("executed", "passed", "failed", "skipped", "duration_ms")}
        return patch, public
    except (KeyError, TypeError, ValueError):
        raise RepairError("invalid_patch") from None


def artifact(identifier, patch):
    root = settings.data_dir / "operator-repairs"
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    if root.is_symlink():
        raise RepairError("invalid_patch")
    target = root / (identifier + ".patch")
    if not re.fullmatch(r"[a-f0-9]{32}", identifier) or target.exists() or target.is_symlink():
        raise RepairError("invalid_patch")
    descriptor, temporary = tempfile.mkstemp(prefix=".patch-", dir=root)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(patch)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, target)
    finally:
        Path(temporary).unlink(missing_ok=True)
    return str(target.resolve())


def work_one():
    # Empty polling never starts a CLI/catalog process or touches credentials.
    # Do not keep a lease while the separate broker reads model metadata.
    with DB() as db:
        if not db.scalar(select(OperatorRepairRequest.id).where(OperatorRepairRequest.status == "queued").limit(1)):
            return False
    catalog = repair_model_catalog()
    if not catalog["available"]:
        return False
    try:
        with DB.begin() as db:
            row = db.scalar(select(OperatorRepairRequest).where(OperatorRepairRequest.status == "queued")
                            .order_by(OperatorRepairRequest.created, OperatorRepairRequest.id)
                            .with_for_update(skip_locked=True).limit(1))
            if not row:
                return False
            identifier = row.id
            try:
                authorized(db, row)
                if ((row.model, row.effort) != (MODEL, EFFORT)
                        or row.catalog_binding.get("catalog_fingerprint") != catalog["catalog_fingerprint"]):
                    raise RepairError("catalog_changed", not_sent=True)
                raw = source_bundle(row.source_commit)
                row.execution_slot = "repair"
                db.flush()  # Unique execution slot: no concurrent inference.
                with db.begin_nested():
                    reserve(db, row)
                row.status, row.started = "running", int(now())
                audit(db, row.requested_by, "operator.repair_started", identifier)
                request = {"id": identifier, "source_commit": row.source_commit,
                           "incident": row.incident_snapshot, "incident_digest": row.incident_snapshot_digest,
                           "model": MODEL, "reasoning_effort": EFFORT,
                           "catalog_fingerprint": catalog["catalog_fingerprint"],
                           "source": base64.b64encode(raw).decode(), "source_sha256": hashlib.sha256(raw).hexdigest()}
                if row.catalog_binding.get("synthetic_fixture") == "decision-closed-v1":
                    request["synthetic_fixture"] = "decision-closed-v1"
            except RepairError as error:
                finish(db, row, code=error.code, not_sent=error.not_sent)
                return True
    except IntegrityError:
        return False
    result, failure, patch_path = None, None, None
    try:
        result = worker_request("POST", "/repair", request)
        patch, summary = checked_result(result)
        after = repair_model_catalog()
        if not after["available"] or after["catalog_fingerprint"] != catalog["catalog_fingerprint"]:
            raise RepairError("catalog_changed")
        with DB.begin() as db:
            row = db.scalar(select(OperatorRepairRequest).where(OperatorRepairRequest.id == identifier)
                            .with_for_update().execution_options(populate_existing=True))
            if not row or row.status != "running":
                raise RepairError("interrupted")
            authorized(db, row)
            config = db.get(ProviderConfig, 1, populate_existing=True)
            if not config or config.emergency_stop or config.revision != row.catalog_binding.get("provider_revision"):
                raise RepairError("access_changed")
            patch_path = artifact(identifier, patch)
            row.artifact_path, row.artifact_sha256, row.artifact_size = patch_path, hashlib.sha256(patch).hexdigest(), len(patch)
            row.test_summary = summary
            finish(db, row)
    except RepairError as error:
        failure = error
    except Exception:
        failure = RepairError("run_failed")
    if failure:
        if patch_path:
            Path(patch_path).unlink(missing_ok=True)
        with DB.begin() as db:
            row = db.scalar(select(OperatorRepairRequest).where(OperatorRepairRequest.id == identifier).with_for_update())
            if row and row.status == "running":
                # Only broker proof of zero dispatch refunds; late reauth failure
                # does not turn an already spent request into a free operation.
                finish(db, row, code=failure.code, not_sent=(result is not None and result.get("dispatched") is False))
    return True


def main():
    # A session advisory lease prevents a second dispatcher from mistaking an
    # actually running first process for a crashed predecessor during recovery.
    with engine.connect() as lease:
        if lease.dialect.name == "postgresql" and not lease.scalar(
                text("SELECT pg_try_advisory_lock(:key)"), {"key": 0x5350554C52455041}):
            return
        interrupt_running()
        while True:
            try:
                if not work_one():
                    time.sleep(2)
            except Exception:
                # Never print model input, credentials or provider diagnostics.
                time.sleep(3)


if __name__ == "__main__":
    main()
