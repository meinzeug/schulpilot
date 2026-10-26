"""Actual provider attempts, distinct from zero-cost rejected dispatches."""

from sqlalchemy import select

from .db import Job, Usage


def counts(db, child_id, kind, sources, stored, *, partition=None):
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
    if kind == "extract":
        matching = [job for job in matching if not job.payload.get("material_check")]
    if kind == "package":
        # A deliberate new finite contract does not erase legacy starts. Each
        # source/config-bound part has its own normal two-attempt allowance.
        if partition is None:
            matching = [job for job in matching if job.payload.get("package_partition") is None]
        else:
            plan_digest, index = partition
            if (not isinstance(plan_digest, str) or len(plan_digest) != 64
                    or any(c not in "0123456789abcdef" for c in plan_digest)
                    or type(index) is not int or index < 0):
                raise ValueError("Ungültige Teilrundenbindung.")
            matching = [job for job in matching if job.payload.get("package_plan_digest") == plan_digest
                        and type(job.payload.get("package_partition")) is int
                        and job.payload["package_partition"] == index]
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

