"""Neutral operational faults and explicit review-only repair requests.

No family/job identifiers, content, provider bodies or exception messages cross
this boundary. Existing job failures are grouped read-only, without backfilling
or re-running their learning work. Repair workers are a separate authority.
"""

import hashlib
import json
import os
import re
import stat
from pathlib import Path
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import Response
from pydantic import Field
from sqlalchemy import JSON, Column, ForeignKey, Integer, String, Text, case, delete, func, select, update
from sqlalchemy.exc import IntegrityError

from . import __version__
from .config import settings
from .db import DB, Base, Job, Session, User, get_db, now, uid
from .job_failures import CODES
from .schemas import Strict
from .security import admin, audit, insert_ignore, rate_limit

router = APIRouter(tags=["Technische Fehler und Reparaturvorschläge"])
RETENTION_SECONDS = 30 * 86400
MAX_PATCH_BYTES = 512 * 1024
MODEL = "gpt-6.1-sol"
EFFORT = "max"
JOB_FUNCTIONS = {
    "extract": "worker.process",
    "unit": "worker.process",
    "package": "worker.process",
    "coach": "coaching.process",
    "coach_practice": "coaching.process_practice",
    "decision": "instructional_decisions.process",
    "controller_check": "controller_jobs.process",
    "study_block": "study_path.process",
    "tutor": "tutor.process",
    "parent_review": "parent_insights.process",
    "vocabulary_import": "vocabulary.process_import",
    "language_unit": "language_projects.process",
    "language_project": "language_projects.process",
    "schulbuddy": "schulbuddy.process",
}
EXCEPTIONS = {
    "ValueError",
    "TypeError",
    "KeyError",
    "AttributeError",
    "ValidationError",
    "ProviderError",
    "TimeoutError",
    "OperationalError",
    "IntegrityError",
    "RuntimeError",
    "DecisionPlanError",
}
API_CODES = {"internal_error", "database_error", "timeout", "invalid_state"}
HEX64 = r"^[a-f0-9]{64}$"
COMMIT = r"^(?:[a-f0-9]{40}|[a-f0-9]{64})$"


class OperatorIncident(Base):
    __tablename__ = "operator_incidents"
    id = Column(String(34), primary_key=True)
    code = Column(String(32), nullable=False)
    kind = Column(String(24), nullable=False)
    function = Column(String(120), nullable=False)
    exception_category = Column(String(32), nullable=False)
    source_commit = Column(String(64))
    release = Column(String(64), nullable=False)
    first_seen = Column(Integer, nullable=False)
    last_seen = Column(Integer, nullable=False, index=True)
    occurrences = Column(Integer, nullable=False)
    trace_id = Column(String(32), nullable=False)


class OperatorRepairRequest(Base):
    __tablename__ = "operator_repair_requests"
    id = Column(String(32), primary_key=True, default=uid)
    source_incident_key = Column(String(34), nullable=False, index=True)
    incident_snapshot = Column(JSON, nullable=False)
    incident_snapshot_digest = Column(String(64), nullable=False)
    source_commit = Column(String(64), nullable=False)
    requested_by = Column(ForeignKey("users.id", ondelete="SET NULL"))
    requested_session_id = Column(ForeignKey("sessions.id", ondelete="SET NULL"))
    idempotency = Column(String(64), nullable=False, unique=True)
    request_digest = Column(String(64), nullable=False)
    active_slot = Column(String(64), unique=True)
    execution_slot = Column(String(8), unique=True)
    model = Column(String(160), nullable=False)
    effort = Column(String(16), nullable=False)
    catalog_binding = Column(JSON, nullable=False)
    status = Column(String(20), nullable=False, default="queued")
    created = Column(Integer, nullable=False, default=lambda: int(now()), index=True)
    started = Column(Integer)
    finished = Column(Integer)
    artifact_path = Column(Text)
    artifact_sha256 = Column(String(64))
    artifact_size = Column(Integer)
    review_status = Column(String(16), nullable=False, default="pending")
    reviewed_by = Column(ForeignKey("users.id", ondelete="SET NULL"))
    reviewed_at = Column(Integer)
    error_code = Column(String(32))
    test_summary = Column(JSON)
    reserved_micros = Column(Integer)
    budget_bucket_ids = Column(JSON)
    cost_micros = Column(Integer)
    cost_source = Column(String(24), default="unknown", nullable=False, server_default="unknown")
    settlement_version = Column(Integer, default=0, nullable=False, server_default="0")


class OperatorRepairKey(Base):
    """Every accepted explicit key keeps its result after the active slot ends."""

    __tablename__ = "operator_repair_keys"
    id = Column(String(64), primary_key=True)
    request_id = Column(ForeignKey("operator_repair_requests.id", ondelete="CASCADE"), nullable=False, index=True)
    request_digest = Column(String(64), nullable=False)


def remember_key(db, key, request_hash, repair):
    previous = db.get(OperatorRepairKey, key)
    if previous:
        if previous.request_digest != request_hash or previous.request_id != repair.id:
            raise HTTPException(409, "Dieser Reparaturschlüssel gehört zu einem anderen Stand.")
        return
    count = db.scalar(
        select(func.count()).select_from(OperatorRepairKey).where(OperatorRepairKey.request_id == repair.id)
    )
    if count >= 32:
        raise HTTPException(
            429, "Für diesen Auftrag liegen bereits viele Wiederholungen vor. Bitte den gespeicherten Auftrag öffnen."
        )
    insert_ignore(db, OperatorRepairKey, {"id": key, "request_id": repair.id, "request_digest": request_hash})
    db.expire_all()
    stored = db.get(OperatorRepairKey, key)
    if not stored or (stored.request_digest, stored.request_id) != (request_hash, repair.id):
        raise HTTPException(409, "Dieser Reparaturschlüssel gehört zu einem anderen Stand.")


def digest(value):
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()
    ).hexdigest()


def release_metadata():
    """Deployment-owned manifest only; never shell out or inspect env secrets."""
    try:
        path = Path(__file__).resolve().parents[2] / "release.json"
        if path.stat().st_size > 16384:
            raise ValueError()
        raw = json.loads(path.read_text())
        commit = raw.get("source_commit")
        release = raw.get("release", raw.get("release_id", __version__))
        return {
            "source_commit": commit if isinstance(commit, str) and re.fullmatch(COMMIT, commit) else None,
            "release": release
            if isinstance(release, str) and re.fullmatch(r"[a-zA-Z0-9_.+-]{1,64}", release)
            else __version__,
        }
    except (OSError, ValueError, TypeError, AttributeError):
        return {"source_commit": None, "release": __version__}


def _location(error):
    value = "api.unhandled"
    tb = error.__traceback__
    while tb is not None:
        module = tb.tb_frame.f_globals.get("__name__", "")
        name = tb.tb_frame.f_code.co_name
        if re.fullmatch(r"schulpilot\.[a-z_]{1,50}", module) and re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_]{0,50}", name):
            value = module.removeprefix("schulpilot.") + "." + name
        tb = tb.tb_next
    return value


def record_api_failure(error):
    """Best effort own transaction; invoke off the async event loop.

    Do not pass the Request, URL, user, args, locals, str(error) or provider body.
    A failure here must never obscure the original controlled 500 response.
    """
    meta = release_metadata()
    category = type(error).__name__ if type(error).__name__ in EXCEPTIONS else "UnhandledError"
    code = (
        "database_error"
        if category in ("OperationalError", "IntegrityError")
        else "timeout"
        if category == "TimeoutError"
        else "internal_error"
    )
    function = _location(error)
    identity = "e-" + digest([code, function, category, meta["source_commit"]])[:32]
    tick = int(now())
    try:
        with DB.begin() as db:
            insert_ignore(
                db,
                OperatorIncident,
                {
                    "id": identity,
                    "code": code,
                    "kind": "api",
                    "function": function,
                    "exception_category": category,
                    **meta,
                    "first_seen": tick,
                    "last_seen": tick,
                    "occurrences": 0,
                    "trace_id": uid(),
                },
            )
            db.execute(
                update(OperatorIncident)
                .where(OperatorIncident.id == identity)
                .values(last_seen=tick, occurrences=OperatorIncident.occurrences + 1, trace_id=uid())
            )
    except Exception:
        # No fallback raw logging, retry or provider call.
        return False
    return True


def grouped_incidents(db):
    """Projection is grouped before fetching: no personal identifiers/content."""
    cutoff = int(now()) - RETENTION_SECONDS
    kind = case((Job.kind.in_(JOB_FUNCTIONS), Job.kind), else_="other")
    code = case((Job.error_code.in_(CODES), Job.error_code), else_="unknown")
    rows = db.execute(
        select(kind.label("kind"), code.label("code"), func.min(Job.created), func.max(Job.created), func.count())
        .where(Job.status == "failed", Job.created >= cutoff)
        .group_by(kind, code)
    )
    result = []
    for job_kind, job_code, first, last, count in rows:
        result.append(
            {
                "id": "j-" + digest([job_kind, job_code])[:32],
                "code": job_code,
                "kind": job_kind,
                "function": JOB_FUNCTIONS.get(job_kind, "worker.process"),
                "exception_category": "historical_unknown",
                "source_commit": None,
                "release": "historical_unknown",
                "first_seen": first,
                "last_seen": last,
                "occurrences": count,
                "trace_id": None,
                "basis": "job_history",
            }
        )
    for row in db.scalars(select(OperatorIncident).where(OperatorIncident.last_seen >= cutoff)):
        result.append(
            {
                name: getattr(row, name)
                for name in (
                    "id",
                    "code",
                    "kind",
                    "function",
                    "exception_category",
                    "source_commit",
                    "release",
                    "first_seen",
                    "last_seen",
                    "occurrences",
                    "trace_id",
                )
            }
            | {"basis": "code_event"}
        )
    return sorted(result, key=lambda v: (v["last_seen"], v["id"]), reverse=True)


def incident(db, identifier):
    if not re.fullmatch(r"[ej]-[a-f0-9]{32}", identifier):
        raise HTTPException(404, "Technischer Fehler nicht gefunden.")
    selected = next((r for r in grouped_incidents(db) if r["id"] == identifier), None)
    if selected is None:
        raise HTTPException(404, "Technischer Fehler nicht gefunden oder nicht mehr aufbewahrt.")
    return selected


def public_test_summary(value):
    if not isinstance(value, dict) or value.get("source") != "isolated_worker":
        return {"source": "not_run", "executed": False}
    if value.get("verification_kind") == "syntax_only":
        return {
            "source": "not_run",
            "executed": False,
            "verification_kind": "syntax_only",
            "syntax_checked": value.get("syntax_checked") is True,
        }
    if value.get("verification_kind") != "pytest" or value.get("executed") is not True:
        return {"source": "not_run", "executed": False}

    def counts(selected):
        result = {"executed": selected.get("executed") is True}
        if result["executed"]:
            for field in ("passed", "failed", "skipped", "duration_ms"):
                number = selected.get(field)
                if type(number) is int and 0 <= number <= 10_000_000:
                    result[field] = number
        return result

    result = {"source": "isolated_worker", "verification_kind": "pytest", **counts(value)}
    if isinstance(value.get("baseline"), dict):
        result["baseline"] = counts(value["baseline"])
    return result


def public_repair(row):
    fields = (
        "id",
        "source_incident_key",
        "incident_snapshot_digest",
        "source_commit",
        "model",
        "effort",
        "status",
        "created",
        "started",
        "finished",
        "artifact_sha256",
        "artifact_size",
        "review_status",
        "reviewed_at",
    )
    result = {name: getattr(row, name) for name in fields}
    result["error_code"] = (
        row.error_code
        if row.error_code
        in {
            "worker_unavailable",
            "source_unavailable",
            "catalog_changed",
            "run_timeout",
            "invalid_patch",
            "run_failed",
            "interrupted",
            "empty_patch",
            "access_changed",
            "budget_reached",
        }
        else "run_failed"
        if row.error_code
        else None
    )
    result["test_summary"] = public_test_summary(row.test_summary)
    result["reserved_micros"] = row.reserved_micros
    result["cost_micros"] = row.cost_micros
    result["cost_source"] = "unknown" if row.cost_source != "provider_reported" else "provider_reported"
    result["patch_available"] = row.status == "completed" and bool(row.artifact_path and row.artifact_sha256)
    result["revision"] = digest(result)
    return result


def repair_catalog():
    try:
        from .operator_repair import repair_model_catalog

        value = repair_model_catalog()
        if (
            value.get("available") is True
            and re.fullmatch(r"[0-9.]{1,32}", str(value.get("cli_version", "")))
            and re.fullmatch(HEX64, str(value.get("catalog_fingerprint", "")))
            and (value.get("model"), value.get("reasoning_effort"), value.get("source"))
            == (
                MODEL,
                EFFORT,
                "isolated_repair_cli",
            )
        ):
            return {
                "available": True,
                "model": MODEL,
                "reasoning_effort": EFFORT,
                "source": "isolated_repair_cli",
                "cli_version": str(value.get("cli_version", ""))[:32],
                "catalog_fingerprint": value["catalog_fingerprint"],
                "notice": "Separater Reparaturworker verfügbar. Ein Auftrag erstellt nur einen zu prüfenden Patch.",
            }
    except (ImportError, ValueError, TypeError, AttributeError, HTTPException):
        pass
    return {
        "available": False,
        "model": None,
        "reasoning_effort": EFFORT,
        "source": "isolated_repair_cli",
        "cli_version": None,
        "notice": "Der separate Reparaturworker ist noch nicht verfügbar. Es wird kein Lernworker als Ersatz verwendet.",
    }


def reauthorize(db, p, *, lock=False):
    user = db.scalar(
        select(User).where(User.id == p.user.id).with_for_update() if lock else select(User).where(User.id == p.user.id)
    )
    session = (
        db.scalar(
            select(Session)
            .where(Session.id == p.session.id)
            .with_for_update()
            .execution_options(populate_existing=True)
        )
        if lock
        else db.get(Session, p.session.id, populate_existing=True)
    )
    if user is not None:
        db.refresh(user)
    if (
        not session
        or session.revoked
        or session.expires <= now()
        or session.seen < now() - 7 * 86400
        or not user
        or user.disabled
        or not user.verified
    ):
        raise HTTPException(401, "Bitte erneut anmelden.")
    if user.role != "admin":
        raise HTTPException(403, "Nur für Administratoren verfügbar.")


@router.get("/admin/operator-incidents")
def list_incidents(
    p=Depends(admin),
    db=Depends(get_db),
    kind: str = Query("", max_length=24),
    code: str = Query("", max_length=32),
    q: str = Query("", max_length=120),
    page: int = Query(1, ge=1, le=10000),
    page_size: int = Query(30, ge=1, le=100),
):
    if kind and kind not in {*JOB_FUNCTIONS, "api", "other"} or code and code not in CODES | API_CODES:
        raise HTTPException(422, "Bitte einen vorhandenen technischen Filter wählen.")
    all_rows = grouped_incidents(db)
    rows = [
        r
        for r in all_rows
        if (not kind or r["kind"] == kind)
        and (not code or r["code"] == code)
        and (
            not q.strip()
            or q.strip().casefold() in " ".join(str(r[k]) for k in ("code", "kind", "function", "release")).casefold()
        )
    ]
    start = (page - 1) * page_size
    return {
        "items": rows[start : start + page_size],
        "pagination": {"page": page, "page_size": page_size, "total": len(rows)},
        "filters": {"kind": kind, "code": code, "q": q.strip()},
        "kinds": sorted({r["kind"] for r in all_rows}),
        "codes": sorted({r["code"] for r in all_rows}),
        "retention_days": 30,
        "notice": "Nur technische Kategorien. Ältere Aufträge ohne Fehlercode bleiben unbekannt; keine privaten Lerninhalte.",
    }


@router.get("/admin/operator-incidents/repair-capabilities")
def capabilities(p=Depends(admin), db=Depends(get_db)):
    rate_limit(db, "operator-repair-catalog:" + p.user.id, 12, 60)
    db.rollback()
    return repair_catalog()


@router.get("/admin/operator-incidents/repairs/{request_id}")
def get_repair(request_id: str, p=Depends(admin), db=Depends(get_db)):
    row = db.get(OperatorRepairRequest, request_id)
    if not row:
        raise HTTPException(404, "Reparaturauftrag nicht gefunden.")
    return public_repair(row)


@router.get("/admin/operator-incidents/{identifier}")
def get_incident(identifier: str, p=Depends(admin), db=Depends(get_db)):
    row = incident(db, identifier)
    repairs = list(
        db.scalars(
            select(OperatorRepairRequest)
            .where(OperatorRepairRequest.source_incident_key == identifier)
            .order_by(OperatorRepairRequest.created.desc(), OperatorRepairRequest.id.desc())
            .limit(20)
        )
    )
    return {
        "incident": row,
        "snapshot_digest": digest(row),
        "current_source": release_metadata(),
        "repairs": [public_repair(r) for r in repairs],
        "repair_scope": "source_patch_review_only",
    }


class RepairInput(Strict):
    request_key: str = Field(min_length=16, max_length=80, pattern=r"^[A-Za-z0-9_-]+$")
    basis_snapshot_digest: str = Field(pattern=HEX64)
    source_commit: str = Field(pattern=COMMIT)


@router.post("/admin/operator-incidents/{identifier}/repairs", status_code=202)
def request_repair(identifier: str, data: RepairInput, p=Depends(admin), db=Depends(get_db)):
    key = digest([p.user.id, data.request_key])
    request_hash = digest([identifier, data.basis_snapshot_digest, data.source_commit])
    binding = db.get(OperatorRepairKey, key)
    previous = (
        db.get(OperatorRepairRequest, binding.request_id)
        if binding
        else db.scalar(select(OperatorRepairRequest).where(OperatorRepairRequest.idempotency == key))
    )
    if previous:
        if previous.request_digest != request_hash:
            raise HTTPException(409, "Dieser Reparaturschlüssel gehört zu einem anderen Stand.")
        return public_repair(previous)
    db.rollback()  # No database lease is held while asking the separate worker for its catalog.
    catalog = repair_catalog()
    if not catalog["available"]:
        raise HTTPException(503, catalog["notice"])
    reauthorize(db, p, lock=True)
    row = incident(db, identifier)
    if data.basis_snapshot_digest != digest(row) or data.source_commit != release_metadata()["source_commit"]:
        raise HTTPException(409, "Fehler- oder Quellstand hat sich geändert. Bitte den technischen Stand neu laden.")
    slot = digest([data.basis_snapshot_digest, data.source_commit])
    active = db.scalar(select(OperatorRepairRequest).where(OperatorRepairRequest.active_slot == slot).with_for_update())
    if active:
        remember_key(db, key, request_hash, active)
        db.commit()
        return public_repair(active)
    # Global operator limits, never billed to a fabricated child/family.
    rate_limit(db, "operator-repair-hour", 5, 3600, commit=False)
    rate_limit(db, "operator-repair-day", 2, 86400, commit=False)
    repair = OperatorRepairRequest(
        source_incident_key=identifier,
        incident_snapshot=row,
        incident_snapshot_digest=data.basis_snapshot_digest,
        source_commit=data.source_commit,
        requested_by=p.user.id,
        requested_session_id=p.session.id,
        idempotency=key,
        request_digest=request_hash,
        active_slot=slot,
        model=catalog["model"],
        effort=EFFORT,
        catalog_binding=catalog,
    )
    try:
        with db.begin_nested():
            db.add(repair)
            db.flush()
            remember_key(db, key, request_hash, repair)
    except IntegrityError:
        active = db.scalar(select(OperatorRepairRequest).where(OperatorRepairRequest.active_slot == slot))
        previous = db.scalar(select(OperatorRepairRequest).where(OperatorRepairRequest.idempotency == key))
        if previous and previous.request_digest != request_hash:
            raise HTTPException(409, "Dieser Reparaturschlüssel gehört zu einem anderen Stand.") from None
        if not (active or previous):
            raise HTTPException(409, "Der Reparaturstand wurde inzwischen geändert. Bitte neu laden.") from None
        selected = active or previous
        remember_key(db, key, request_hash, selected)
        db.commit()
        return public_repair(selected)
    audit(db, p.user.id, "operator.repair_requested", repair.id)
    db.commit()
    return public_repair(repair)


def patch_bytes(row):
    root = (settings.data_dir / "operator-repairs").resolve()
    path = Path(row.artifact_path or "")
    if row.status != "completed" or not row.artifact_sha256 or not re.fullmatch(HEX64, row.artifact_sha256):
        raise HTTPException(409, "Für diesen Auftrag liegt noch kein geprüfter Patch vor.")
    try:
        if path.is_symlink() or path.resolve().parent != root or path.name != row.id + ".patch":
            raise ValueError()
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        try:
            metadata = os.fstat(fd)
            if (
                not stat.S_ISREG(metadata.st_mode)
                or not 0 < metadata.st_size <= MAX_PATCH_BYTES
                or metadata.st_size != row.artifact_size
            ):
                raise ValueError()
            with os.fdopen(fd, "rb", closefd=False) as stream:
                content = stream.read(MAX_PATCH_BYTES + 1)
        finally:
            os.close(fd)
        if (
            not content
            or len(content) > MAX_PATCH_BYTES
            or len(content) != row.artifact_size
            or hashlib.sha256(content).hexdigest() != row.artifact_sha256
        ):
            raise ValueError()
        content.decode("utf-8")
        return content
    except (OSError, ValueError, UnicodeError):
        raise HTTPException(409, "Das Patchartefakt ist nicht mehr unverändert verfügbar.") from None


@router.get("/admin/operator-incidents/repairs/{request_id}/patch")
def download_patch(request_id: str, p=Depends(admin), db=Depends(get_db)):
    row = db.get(OperatorRepairRequest, request_id)
    if not row:
        raise HTTPException(404, "Reparaturauftrag nicht gefunden.")
    content = patch_bytes(row)
    audit(db, p.user.id, "operator.patch_download", row.id)
    db.commit()
    return Response(
        content,
        media_type="text/x-diff",
        headers={"Content-Disposition": f'attachment; filename="repair-{row.id}.patch"', "Cache-Control": "no-store"},
    )


class ReviewInput(Strict):
    revision: str = Field(pattern=HEX64)
    artifact_sha256: str = Field(pattern=HEX64)
    decision: Literal["approved", "rejected"]


@router.post("/admin/operator-incidents/repairs/{request_id}/review")
def review_patch(request_id: str, data: ReviewInput, p=Depends(admin), db=Depends(get_db)):
    row = db.scalar(select(OperatorRepairRequest).where(OperatorRepairRequest.id == request_id).with_for_update())
    if not row:
        raise HTTPException(404, "Reparaturauftrag nicht gefunden.")
    reauthorize(db, p)
    if data.revision != public_repair(row)["revision"] or data.artifact_sha256 != row.artifact_sha256:
        raise HTTPException(409, "Der Patchstand hat sich geändert. Bitte neu laden.")
    patch_bytes(row)
    row.review_status, row.reviewed_by, row.reviewed_at = data.decision, p.user.id, int(now())
    audit(db, p.user.id, "operator.patch_" + data.decision, row.id)
    db.commit()
    return public_repair(row)


def maintenance(db):
    """Call from the existing bounded maintenance, never execute a repair here."""
    cutoff = int(now()) - RETENTION_SECONDS
    rows = list(
        db.scalars(
            select(OperatorRepairRequest)
            .where(
                OperatorRepairRequest.created < cutoff,
                OperatorRepairRequest.status.in_(["completed", "failed", "cancelled"]),
            )
            .order_by(OperatorRepairRequest.created, OperatorRepairRequest.id)
            .limit(100)
        )
    )
    root = (settings.data_dir / "operator-repairs").resolve()
    paths = [
        str(root / (row.id + ".patch"))
        for row in rows
        if row.artifact_path
        and Path(row.artifact_path).resolve() == root / (row.id + ".patch")
        and not Path(row.artifact_path).is_symlink()
    ]
    db.execute(delete(OperatorRepairRequest).where(OperatorRepairRequest.id.in_([row.id for row in rows])))
    db.execute(delete(OperatorIncident).where(OperatorIncident.last_seen < cutoff))
    return paths
