"""Explicit local synthetic repair probe; never damages production code/data.

Read one existing admin session token from stdin, never argv/logs. Queue one
regularly reserved repair whose only injected bug exists in the copied bounded
worker workspace. No HTTP client can choose this fixture.
"""

import argparse
import json
import re
import sys

from sqlalchemy import select

from .db import DB, Session, User, now
from .operator_incidents import (
    OperatorIncident,
    OperatorRepairKey,
    OperatorRepairRequest,
    digest,
    release_metadata,
    remember_key,
)
from .operator_repair import EFFORT, MODEL, RepairError, authorized, repair_model_catalog, source_bundle
from .security import audit, rate_limit
from .security import digest as token_digest


def queue_probe(token, request_key):
    if not 16 <= len(token) <= 512 or not re.fullmatch(r"[A-Za-z0-9_-]{16,80}", request_key):
        raise RepairError("access_changed")
    catalog = repair_model_catalog()
    if not catalog["available"]:
        raise RepairError("worker_unavailable")
    commit = release_metadata()["source_commit"]
    source_bundle(commit)
    with DB.begin() as db:
        session = db.scalar(select(Session).where(Session.token_hash == token_digest(token)))
        if not session:
            raise RepairError("access_changed")
        user = db.scalar(select(User).where(User.id == session.user_id).with_for_update())
        session = db.scalar(select(Session).where(Session.id == session.id).with_for_update().execution_options(populate_existing=True))
        identity = "e-" + digest(["synthetic_repair", commit])[:32]
        event = db.get(OperatorIncident, identity)
        if not event:
            event = OperatorIncident(id=identity, code="synthetic_repair", kind="decision", function="instructional_decisions.process",
                exception_category="synthetic", source_commit=commit, release=release_metadata()["release"],
                first_seen=int(now()), last_seen=int(now()), occurrences=1, trace_id=digest(["synthetic", commit])[:32])
            db.add(event)
            db.flush()
        incident = {k: getattr(event, k) for k in ("id", "code", "kind", "function", "exception_category", "source_commit",
                    "release", "first_seen", "last_seen", "occurrences", "trace_id")}
        incident["basis"] = "code_event"
        key, snapshot = digest([user.id, request_key]), digest(incident)
        request_hash = digest([identity, snapshot, commit, "decision-closed-v1"])
        binding = db.get(OperatorRepairKey, key)
        previous = db.get(OperatorRepairRequest, binding.request_id) if binding else db.scalar(
            select(OperatorRepairRequest).where(OperatorRepairRequest.idempotency == key))
        if previous:
            if previous.request_digest != request_hash:
                raise RepairError("source_unavailable")
            authorized(db, previous)
            return {"id": previous.id, "status": previous.status, "synthetic": True}
        row = OperatorRepairRequest(source_incident_key=identity, incident_snapshot=incident, incident_snapshot_digest=snapshot,
            source_commit=commit, requested_by=user.id, requested_session_id=session.id, idempotency=key,
            request_digest=request_hash, active_slot=digest([snapshot, commit]), model=MODEL, effort=EFFORT,
            catalog_binding={**catalog, "synthetic_fixture": "decision-closed-v1"})
        authorized(db, row)
        active = db.scalar(select(OperatorRepairRequest).where(OperatorRepairRequest.active_slot == row.active_slot).with_for_update())
        if active:
            remember_key(db, key, request_hash, active)
            return {"id": active.id, "status": active.status, "synthetic": True}
        rate_limit(db, "operator-repair-hour", 5, 3600, commit=False)
        rate_limit(db, "operator-repair-day", 2, 86400, commit=False)
        db.add(row)
        db.flush()
        remember_key(db, key, request_hash, row)
        audit(db, user.id, "operator.repair_synthetic_requested", row.id)
        return {"id": row.id, "status": row.status, "synthetic": True,
                "notice": "Nur kopierter Worker-Quelltext wird künstlich verändert. Kein Patch wird angewendet."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session-stdin", action="store_true", required=True)
    parser.add_argument("--request-key", required=True)
    args = parser.parse_args()
    token = sys.stdin.readline(514).strip()
    try:
        print(json.dumps(queue_probe(token, args.request_key), ensure_ascii=False))
    except RepairError as error:
        print(json.dumps({"status": "not_queued", "error_code": error.code}))
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
