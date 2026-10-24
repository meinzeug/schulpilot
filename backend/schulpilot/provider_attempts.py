"""Actual provider attempts, distinct from zero-cost rejected dispatches."""

from sqlalchemy import select

from .db import Job, Usage


def counts(db, child_id, kind, sources, stored):
    """Keep all historical starts; only proven zero-cost non-dispatch is free.

    Unknown transports, billed invalid output and timeouts still consume a
    provider attempt. No history or old counter is rewritten by this projection.
    """
    query = select(Job).where(Job.child_id == child_id, Job.kind == kind)
    if kind == "extract":
        query = query.where(Job.payload["material_id"].as_string() == sources[0]["id"],
                            Job.payload["material_revision"].as_integer() == sources[0]["revision"])
    elif sources:
        query = query.where(Job.payload["sources"][0]["id"].as_string() == sources[0]["id"])
    jobs = list(db.scalars(query))
    matching = [job for job in jobs if (
        job.payload.get("material_id") == sources[0]["id"]
        and job.payload.get("material_revision") == sources[0]["revision"]
    )] if kind == "extract" else [job for job in jobs if job.payload.get("sources") == sources]
    usages = {usage.job_id: usage for usage in db.scalars(select(Usage).where(
        Usage.job_id.in_([job.id for job in matching])))} if matching else {}
    exempt = 0
    for job in matching:
        if job.status != "failed" or job.error_code not in ("cost_preflight", "unknown", None):
            continue
        usage = usages.get(job.id)
        if (usage and usage.status == "failed_not_sent" and usage.cost_source == "cancelled"
                and usage.cost_micros == 0 and usage.input_tokens == 0 and usage.output_tokens == 0
                and (usage.telemetry or {}).get("pre_dispatch") is True):
            exempt += 1
    starts = max(stored, len(matching))
    return starts, max(0, starts - exempt)

