"""Local operator-only OCR diagnosis; never a synthetic/private-data bypass.

No router. Creating a grant is an explicit local operator command. A grant binds
one named family, <=12 exact image/revision snapshots and two already evaluated
routes. One durable work ledger counts all cases/unknown holds across grants.
"""

import hashlib
import re

from fastapi import HTTPException
from sqlalchemy import select, update

from .config import settings
from .db import Child, Family, Job, Material, ProviderConfig, User, now
from .model_routing import enabled, policy_hash, select_route, validate_ready
from .security import audit, insert_ignore
from .source_lineage_models import SourceEvaluationBudget, SourceEvaluationCase, SourceEvaluationGrant

WORK_ID = "ocr107-20261024"
CAP_MICROS = 250_000
MAX_CASES = 14


def used_micros(db):
    # Cases survive grant/job/source erasure; financial amounts contain no text.
    return sum(
        row.charged_micros if row.charged_micros is not None else row.reserved_micros
        for row in db.scalars(select(SourceEvaluationCase).where(SourceEvaluationCase.work_id == WORK_ID))
    )


def _locked_budget(db):
    insert_ignore(db, SourceEvaluationBudget, {"id": WORK_ID, "limit_micros": CAP_MICROS})
    db.execute(
        update(SourceEvaluationBudget)
        .where(SourceEvaluationBudget.id == WORK_ID)
        .values(limit_micros=SourceEvaluationBudget.limit_micros)
    )
    value = db.get(SourceEvaluationBudget, WORK_ID, populate_existing=True)
    if value.limit_micros != CAP_MICROS:
        raise HTTPException(409, "Der feste Diagnosekostenrahmen ist nicht gültig.")
    return value


def _image(material):
    if not material.path or not re.fullmatch(r"[a-f0-9]{32}\.jpg", material.path):
        raise HTTPException(409, "Für diese Diagnose fehlt ein gültiges privates Original.")
    path = settings.data_dir / "uploads" / material.path
    if not path.is_file() or path.stat().st_size > 10 * 1024 * 1024:
        raise HTTPException(409, "Das gebundene Original ist nicht verfügbar.")
    data = path.read_bytes()
    return data, hashlib.sha256(data).hexdigest()


def create_grant(db, operator_id, family_id, material_ids, *, expires_in=3600):
    """Only local CLI calls this. No endpoint accepts operator/material grants."""
    from .providers import external_allowed

    operator = db.get(User, operator_id, populate_existing=True)
    family = db.get(Family, family_id)
    if not operator or operator.disabled or not operator.verified or operator.role != "admin":
        raise HTTPException(403, "Ein ausdrücklich handelnder lokaler Betreiber ist erforderlich.")
    if not family or family.synthetic or not 60 <= expires_in <= 86400:
        raise HTTPException(403, "Die Diagnosefreigabe benötigt die benannte reguläre Familie.")
    if not 1 <= len(material_ids) <= 12 or len(set(material_ids)) != len(material_ids):
        raise HTTPException(422, "Eine Diagnosefreigabe umfasst höchstens zwölf einzelne Quellen.")
    _locked_budget(db)
    config = db.get(ProviderConfig, 1, populate_existing=True)
    if not enabled(config):
        raise HTTPException(409, "Die Diagnose benötigt den bereits freigegebenen Modellmix.")
    for tier in ("luna", "sol"):
        chosen = select_route(
            config,
            "extract",
            snapshot={
                "policy_hash": policy_hash(config.routing_policy),
                "tier": tier,
                "reason": "explicit_operator_ocr_diagnosis",
            },
        )
        validate_ready(chosen, image=True, synthetic=False)
        external_allowed(chosen, image=True, synthetic_fixture=False)
    sources = []
    for mid in material_ids:
        material = db.get(Material, mid)
        child = db.get(Child, material.child_id) if material else None
        if (
            not material
            or not child
            or child.family_id != family.id
            or material.synthetic
            or material.purpose != "notebook"
        ):
            raise HTTPException(404, "Eine freigegebene Heftquelle gehört nicht zur benannten Familie.")
        _, image_digest = _image(material)
        sources.append({"material_id": material.id, "revision": material.revision, "image_digest": image_digest})
    row = SourceEvaluationGrant(
        work_id=WORK_ID,
        operator_id=operator.id,
        family_id=family.id,
        sources=sources,
        config_revision=config.revision,
        policy_digest=policy_hash(config.routing_policy),
        expires=int(now()) + expires_in,
    )
    db.add(row)
    db.flush()
    audit(db, operator.id, "source.diagnostic_grant_created", row.id)
    return row


def prepare_case(db, grant_id, material_id, tier, case_key):
    if tier not in ("luna", "sol") or not re.fullmatch(r"[A-Za-z0-9_-]{8,80}", case_key):
        raise HTTPException(422, "Bitte einen festen Diagnosefall und eine erlaubte Route verwenden.")
    selected = db.get(Material, material_id)
    if selected is None:
        raise HTTPException(404, "Diagnosequelle nicht gefunden.")
    db.execute(update(Child).where(Child.id == selected.child_id).values(grade=Child.grade))
    _locked_budget(db)
    case_id = hashlib.sha256((WORK_ID + ":" + case_key).encode()).hexdigest()[:32]
    if db.get(SourceEvaluationCase, case_id):
        raise HTTPException(409, "Dieser Diagnosefall ist bereits beansprucht. Kein automatischer Wiederholungsaufruf.")
    if (
        len(list(db.scalars(select(SourceEvaluationCase.id).where(SourceEvaluationCase.work_id == WORK_ID))))
        >= MAX_CASES
    ):
        raise HTTPException(429, "Die endliche Zahl der Diagnosefälle ist erreicht.")
    grant = db.get(SourceEvaluationGrant, grant_id)
    material = db.get(Material, material_id)
    if not grant or not material:
        raise HTTPException(404, "Diagnosefreigabe nicht gefunden.")
    job = Job(
        child_id=material.child_id,
        kind="extract",
        status="operator_held",
        attempts=0,
        idempotency="operator-ocr:" + case_id,
        payload={
            "material_id": material.id,
            "material_revision": material.revision,
            "operator_evaluation": case_id,
            "diagnostic_only": True,
        },
    )
    db.add(job)
    db.flush()
    row = SourceEvaluationCase(
        id=case_id,
        work_id=WORK_ID,
        grant_id=grant.id,
        material_id=material.id,
        job_id=job.id,
        tier=tier,
        status="prepared",
        reserved_micros=0,
    )
    db.add(row)
    db.flush()
    reserve_guard(db, db.get(Family, grant.family_id), material.child_id, job.id, "extract", tier, row.id)
    return row


def reserve_guard(db, family, child_id, job_id, function, tier, case_id):
    """Called within normal reserve's transaction, before any usage mutation."""
    db.execute(update(Child).where(Child.id == child_id).values(grade=Child.grade))
    _locked_budget(db)
    row = db.get(SourceEvaluationCase, case_id, populate_existing=True)
    grant = db.get(SourceEvaluationGrant, row.grant_id, populate_existing=True) if row and row.grant_id else None
    operator = db.get(User, grant.operator_id, populate_existing=True) if grant else None
    job = db.get(Job, job_id)
    material = db.get(Material, row.material_id, populate_existing=True) if row and row.material_id else None
    child = db.get(Child, child_id, populate_existing=True)
    config = db.get(ProviderConfig, 1, populate_existing=True)
    if not (
        row
        and grant
        and operator
        and operator.role == "admin"
        and not operator.disabled
        and operator.verified
        and grant.work_id == WORK_ID
        and grant.expires > now()
        and row.job_id == job_id
        and row.tier == tier
        and row.status in ("prepared", "reserved", "dispatched")
        and function == "extract"
        and tier in ("luna", "sol")
        and family.id == grant.family_id
        and not family.synthetic
        and child
        and child.family_id == family.id
        and material
        and not material.synthetic
        and material.child_id == child.id
        and material.purpose == "notebook"
        and config.revision == grant.config_revision
        and policy_hash(config.routing_policy) == grant.policy_digest
        and job
        and job.kind == "extract"
        and job.child_id == child.id
        and job.status == "operator_held"
        and job.payload.get("operator_evaluation") == row.id
        and job.payload.get("diagnostic_only") is True
    ):
        raise HTTPException(409, "Die zeitlich begrenzte Diagnosefreigabe ist nicht mehr aktuell.")
    source = next((item for item in grant.sources if item["material_id"] == material.id), None)
    if (
        not source
        or source["revision"] != material.revision
        or job.payload.get("material_revision") != material.revision
    ):
        raise HTTPException(409, "Die gebundene Quellenfassung wurde geändert.")
    _, actual_digest = _image(material)
    if source["image_digest"] != actual_digest:
        raise HTTPException(409, "Das gebundene Original wurde verändert.")
    return {"policy_hash": grant.policy_digest, "tier": tier, "reason": "explicit_operator_ocr_diagnosis"}


def bind_usage(db, usage, case_id):
    _locked_budget(db)
    row = db.get(SourceEvaluationCase, case_id, populate_existing=True)
    if not row or row.job_id != usage.job_id or row.status != "prepared" or not 0 < usage.reserved_micros <= 150_000:
        raise HTTPException(409, "Der Diagnosefall besitzt keine einmalige gültige Reservierung.")
    if used_micros(db) + usage.reserved_micros > CAP_MICROS:
        raise HTTPException(
            429,
            "Der gemeinsame Diagnosekostenrahmen von0,25USD einschließlich offener Reservierungen ist ausgeschöpft.",
        )
    row.reserved_micros = usage.reserved_micros
    row.status = "reserved"
    audit(db, "local-operator", "source.diagnostic_reserved", row.id)


def dispatched(db, case_id):
    row = db.get(SourceEvaluationCase, case_id)
    if not row or row.status != "reserved":
        raise HTTPException(409, "Dieser Diagnosefall wurde bereits gestartet oder nicht reserviert.")
    grant = db.get(SourceEvaluationGrant, row.grant_id)
    job = db.get(Job, row.job_id)
    reserve_guard(db, db.get(Family, grant.family_id), job.child_id, job.id, "extract", row.tier, row.id)
    if not db.execute(
        update(SourceEvaluationCase)
        .where(SourceEvaluationCase.id == case_id, SourceEvaluationCase.status == "reserved")
        .values(status="dispatched")
    ).rowcount:
        raise HTTPException(409, "Dieser Diagnosefall ist bereits gestartet.")
    return row


def settled(db, case_id, usage):
    """Normal settle runs first; unknown charges retain their full hold."""
    _locked_budget(db)
    row = db.get(SourceEvaluationCase, case_id)
    if not row or row.job_id != usage.job_id:
        raise HTTPException(409, "Die Diagnoseabrechnung gehört zu einem anderen Fall.")
    row.status = "finished"
    row.charged_micros = usage.cost_micros if usage.cost_micros is not None else None
    if usage.status == "failed_not_sent":
        row.charged_micros = 0
    audit(db, "local-operator", "source.diagnostic_finished", row.id)


def run_case(grant_id, material_id, tier, case_key):
    """Exactly one explicit dispatch; errors retain billed/unknown normal Usage."""
    import json
    import os

    from .catalog_ai import with_catalog_context
    from .db import DB, Usage
    from .extraction import request_payload, validate_material
    from .model_routing import job_config
    from .providers import Result, request_provider, reserve, settle
    from .source_lineage import extraction_receipt

    with DB.begin() as db:
        row = prepare_case(db, grant_id, material_id, tier, case_key)
        case_id, job_id = row.id, row.job_id
    # A committed finite intent exists before reserving and before dispatch.
    with DB.begin() as db:
        row = db.get(SourceEvaluationCase, case_id)
        grant = db.get(SourceEvaluationGrant, row.grant_id)
        job = db.get(Job, row.job_id)
        usage = reserve(
            db,
            db.get(Family, grant.family_id),
            job.child_id,
            job.id,
            "extract",
            synthetic_fixture=False,
            probe_tier=tier,
            operator_evaluation=case_id,
        )
        usage_id = usage.id
    result, output, error_kind, sent = None, None, None, False
    try:
        with DB.begin() as db:
            row = dispatched(db, case_id)
            job = db.get(Job, job_id)
            config = job_config(db, job, "extract")
            values = {column.name: getattr(config, column.name) for column in ProviderConfig.__table__.columns}
            material = db.get(Material, material_id)
            image_bytes, _ = _image(material)
            payload = with_catalog_context(db, db.get(Child, job.child_id), request_payload())
        sent = True
        result = request_provider(ProviderConfig(**values), "extract", payload, image_bytes, synthetic_fixture=False)
        data = validate_material(result.data, image_bytes)
        with DB.begin() as db:
            row = db.get(SourceEvaluationCase, case_id)
            grant = db.get(SourceEvaluationGrant, row.grant_id)
            job = db.get(Job, job_id)
            reserve_guard(db, db.get(Family, grant.family_id), job.child_id, job_id, "extract", tier, case_id)
            output = {
                "case_id": case_id,
                "diagnostic_only": True,
                "data": data,
                "receipt": extraction_receipt(db, job, values, image_bytes, result),
            }
            directory = settings.data_dir / "operator-diagnostics" / WORK_ID
            directory.mkdir(parents=True, exist_ok=True, mode=0o700)
            directory.chmod(0o700)
            target = directory / (case_id + ".json")
            descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, "w") as stream:
                json.dump(output, stream, ensure_ascii=False)
    except Exception as error:
        # Never print upstream bodies, image data, transcripts or credentials.
        error_kind = type(error).__name__
        result = result or getattr(error, "billing_result", None)
        if not sent:
            result = Result({}, input_tokens=0, output_tokens=0, cost_micros=0, cost_source="cancelled")
    finally:
        with DB.begin() as db:
            usage = db.get(Usage, usage_id)
            settle(db, usage, result, failed=error_kind is not None)
            settled(db, case_id, usage)
            job = db.get(Job, job_id)
            job.status = "failed" if error_kind else "completed"
            job.finished = int(now())
            job.result = {"diagnostic_only": True, "case_id": case_id, "accepted": output is not None}
            job.error = "Operator-Diagnose nicht übernommen." if error_kind else None
            summary = {
                "case_id": case_id,
                "diagnostic_only": True,
                "accepted": output is not None,
                "error_kind": error_kind,
                "used_or_held_micros": used_micros(db),
                "cap_micros": CAP_MICROS,
                "cost_micros": usage.cost_micros,
                "reserved_micros": usage.reserved_micros,
                "billing_status": usage.status,
            }
    if output is not None:
        summary["private_output"] = "server-private-diagnostic-only"
    return summary
