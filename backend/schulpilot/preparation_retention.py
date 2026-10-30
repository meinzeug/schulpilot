"""Keep an unfinished source-bound day reproducible within learning retention.

Ordinary terminal jobs expire after 30 days and usage after 90. A current
unfinished preparation still needs its job/usage receipts for publication and
explicit repair. This does not extend source retention or authorize a retry.
"""
from sqlalchemy import and_, delete, exists, or_, select

from .db import Job, SchoolDay, Usage


def open_dependency():
    state = SchoolDay.preparation
    return exists(select(SchoolDay.id).where(
        SchoolDay.child_id == Job.child_id,
        SchoolDay.id == Job.payload["school_day_id"].as_string(),
        state["status"].as_string().in_(("processing", "failed", "blocked", "needs_review", "needs_photo")),
        or_(
            state["job_id"].as_string() == Job.id,
            and_(
                Job.kind == "package",
                Job.payload["package_plan_digest"].as_string() == state["package_plan"]["digest"].as_string(),
            ),
        ),
    ))


def purge(db, stamp):
    dependency = open_dependency()
    db.execute(delete(Job).where(
        Job.status.in_(("failed", "completed")),
        Job.created < stamp - 30 * 86400,
        or_(Job.created < stamp - 365 * 86400, ~dependency),
    ).execution_options(synchronize_session=False))
    retained = exists(select(Job.id).where(Job.id == Usage.job_id, Job.child_id == Usage.child_id, dependency))
    db.execute(delete(Usage).where(
        Usage.created < stamp - 90 * 86400,
        or_(Usage.created < stamp - 365 * 86400, ~retained),
    ).execution_options(synchronize_session=False))
