"""Durable, bounded operator checks using fixed artificial data, never a child."""

from datetime import datetime, timezone
from types import SimpleNamespace

from fastapi import HTTPException
from sqlalchemy import select, update

from .db import DB, Installation, OperatorJob, ProviderConfig, ServiceState, UsageBucket, now
from .model_routing import enabled, selection
from .providers import (
    ProviderError,
    config_for_function,
    external_allowed,
    request_provider,
    routing_fingerprint,
    settle,
)
from .security import audit, insert_ignore, rate_limit


def enqueue(actor, db):
    db.execute(update(Installation).where(Installation.id == 1).values(revision=Installation.revision))
    active = db.scalar(select(OperatorJob).where(OperatorJob.status.in_(["queued", "running"])))
    if active:
        return {"id": active.id, "status": active.status}
    config = db.get(ProviderConfig, 1)
    if not enabled(config) and config.provider != "codex" and (
        config.provider != "openrouter"
        or not config.openrouter_free_only
        or not config.model.endswith(":free")
        or (config.extraction_model and not config.extraction_model.endswith(":free"))
    ):
        raise HTTPException(
            422,
            "Der automatische Bild-/Aufgabentest ist für OpenRouter Free und den isolierten Codex-Worker verfügbar.",
        )
    if config.provider == "codex":
        from .codex_setup import worker_health

        status = worker_health()
        if not status["ready"]:
            raise HTTPException(422, status["status"])
    try:
        for function in ("extract", "unit", "package"):
            external_allowed(config_for_function(config, function), function == "extract", True, operator_probe=True)
    except ProviderError as error:
        raise HTTPException(422, str(error)) from None
    rate_limit(db, "operator-probe-hour", 3, 3600, commit=False)
    rate_limit(db, "operator-probe-day", 10, 86400, commit=False)
    job = OperatorJob(actor=actor, config_revision=config.revision)
    db.add(job)
    db.flush()
    audit(db, actor, "provider.probe_queued", job.id)
    db.commit()
    return {"id": job.id, "status": job.status}


def work_one(should_continue=lambda: True):
    with DB.begin() as db:
        query = select(OperatorJob).where(OperatorJob.status == "queued").order_by(OperatorJob.created).limit(1)
        if db.bind.dialect.name == "postgresql":
            query = query.with_for_update(skip_locked=True)
        job = db.scalar(query)
        if not job:
            return False
        if not db.execute(
            update(OperatorJob)
            .where(OperatorJob.id == job.id, OperatorJob.status == "queued")
            .values(status="running", started=int(now()))
        ).rowcount:
            return False
        job_id = job.id
    try:
        for function in ("extract", "unit", "package"):
            if not should_continue():
                raise ProviderError("Prüfung beim Dienstwechsel beendet. Bereits erfolgte Aufrufe bleiben mitgezählt.")
            with DB.begin() as db:
                job = db.get(OperatorJob, job_id)
                config = config_for_function(db.get(ProviderConfig, 1), function)
                if config.revision != job.config_revision:
                    raise ProviderError("Anbieterkonfiguration wurde geändert. Prüfung bitte neu starten.")
                external_allowed(config, function == "extract", True, operator_probe=True)
                values = {c.name: getattr(config, c.name) for c in ProviderConfig.__table__.columns}
                period = datetime.now(timezone.utc).strftime("%Y-%m")
                bucket = "global:" + period
                insert_ignore(
                    db,
                    UsageBucket,
                    {"id": bucket, "calls": 0, "encumbered_micros": 0, "known_cost_micros": 0, "unknown_calls": 0},
                )
                if not db.execute(
                    update(UsageBucket)
                    .where(
                        UsageBucket.id == bucket,
                        UsageBucket.encumbered_micros + config.reserve_micros <= config.global_limit_micros,
                    )
                    .values(
                        calls=UsageBucket.calls + 1,
                        encumbered_micros=UsageBucket.encumbered_micros + config.reserve_micros,
                        unknown_calls=UsageBucket.unknown_calls + 1,
                    )
                ).rowcount:
                    raise ProviderError("Das unternehmensweite Kostenlimit ist erreicht.")
                buckets = [bucket]
                if enabled(config):
                    test_bucket = "routing-probe:" + job.id
                    insert_ignore(db, UsageBucket, {"id": test_bucket, "calls": 0, "encumbered_micros": 0,
                        "known_cost_micros": 0, "unknown_calls": 0})
                    if not db.execute(update(UsageBucket).where(UsageBucket.id == test_bucket,
                        UsageBucket.encumbered_micros + config.reserve_micros <= 250000).values(
                            calls=UsageBucket.calls + 1, encumbered_micros=UsageBucket.encumbered_micros + config.reserve_micros,
                            unknown_calls=UsageBucket.unknown_calls + 1)).rowcount:
                        raise ProviderError("Das begrenzte Prüfbudget von 0,25 USD ist erreicht.")
                    buckets.append(test_bucket)
                report = {
                    "function": function,
                    "provider": config.provider,
                    "model": config.model,
                    "reasoning_effort": config.reasoning_effort or "medium",
                    "routing_fingerprint": routing_fingerprint(config),
                    "available": False,
                    "cost_micros_usd": None,
                    "status": "reserved",
                    "route": selection(config),
                }
                job.report = [*job.report, report]
                state = db.get(ServiceState, "worker")
                if state:
                    state.updated = int(now())
            result, error = None, None
            try:
                result = request_provider(
                    ProviderConfig(**values), function, {}, synthetic_fixture=True, private_probe=True
                )
            except ProviderError as failure:
                error, result = str(failure), failure.billing_result
            with DB.begin() as db:
                job = db.get(OperatorJob, job_id)
                settle(
                    db,
                    SimpleNamespace(bucket_ids=buckets, reserved_micros=config.reserve_micros, provider=config.provider),
                    result,
                    failed=bool(error),
                )
                report = {
                    **report,
                    "available": result is not None and not error,
                    "status": "failed" if error else "completed",
                    "cost_micros_usd": result.cost_micros if result and
                        (config.provider != "openrouter" or result.cost_source in ("reported", "generation", "cancelled")) else None,
                    "cost_source": result.cost_source if result else "unknown",
                    "input_tokens": result.input_tokens if result else None,
                    "output_tokens": result.output_tokens if result else None,
                    "search_calls": result.search_calls if result else None,
                    "telemetry": result.telemetry if result else None,
                }
                if error:
                    report["error"] = error[:500]
                job.report = [*job.report[:-1], report]
        with DB.begin() as db:
            job = db.get(OperatorJob, job_id)
            config = db.get(ProviderConfig, 1)
            if config.revision != job.config_revision:
                raise ProviderError("Konfiguration während der Prüfung geändert; Ergebnis nicht aktiviert.")
            ready = len(job.report) == 3 and all(r["available"] for r in job.report)
            if ready and enabled(config):
                policy = {**config.routing_policy, "routes": {k: dict(v) for k, v in config.routing_policy["routes"].items()}}
                tested = {r["model"] for r in job.report}
                for route in policy["routes"].values():
                    if route["model"] in tested:
                        route["evaluated"] = True
                        route["capability_evidence"] = (route["capability_evidence"][:350]
                            + "; actual fixed image/unit/package probe=" + job.id)
                config.routing_policy = policy
            config.production_block_reason = (
                ""
                if ready
                else "Die Bild-/Aufgabenprüfung ist fehlgeschlagen. Gespeicherte Lerninhalte bleiben nutzbar."
            )
            config.status = (
                "Bild-, Aufgaben- und Tagespaketprüfung erfolgreich." if ready else config.production_block_reason
            )
            if config.provider == "codex":
                from .codex_setup import search_policy_status

                config.status += " " + search_policy_status()
            config.revision += 1
            job.status, job.finished = "completed" if ready else "failed", int(now())
            audit(db, job.actor, "provider.probe_completed", "ready" if ready else "failed")
    except Exception as error:
        with DB.begin() as db:
            job = db.get(OperatorJob, job_id)
            job.status, job.finished = "failed", int(now())
            job.error = (
                str(error)[:500]
                if isinstance(error, ProviderError)
                else "Prüfung abgebrochen. Keine automatische Wiederholung."
            )
    return True
