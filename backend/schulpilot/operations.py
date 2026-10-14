"""Content-free operational metrics; private endpoint and local operator CLI."""

import json

from fastapi import APIRouter, Depends
from sqlalchemy import func, select

from .db import DB, ErasureRequest, Job, PushDelivery, ServiceState, get_db, now
from .security import admin, audit

router = APIRouter(tags=["Betrieb"])


def snapshot(db):
    stamp = int(now())
    worker = db.get(ServiceState, "worker")
    counts = dict(db.execute(select(Job.status, func.count()).group_by(Job.status)).all())
    queued = db.scalar(select(func.count()).select_from(Job).where(Job.status == "queued", Job.created < stamp - 300))
    running = db.scalar(select(func.count()).select_from(Job).where(Job.status == "running", Job.started < stamp - 240))
    unpublished = db.scalar(select(func.count()).select_from(ErasureRequest).where(ErasureRequest.published.is_(False)))
    push_errors = db.scalar(
        select(func.count())
        .select_from(PushDelivery)
        .where(PushDelivery.status == "failed", PushDelivery.created >= stamp - 86400)
    )
    return {
        "checked_at": stamp,
        "worker_age_seconds": stamp - worker.updated if worker else None,
        "jobs": counts,
        "stalled_queued": queued,
        "stalled_running": running,
        "pending_erasure_journal": unpublished,
        "push_failures_24h": push_errors,
    }


@router.get("/admin/operations")
def view(p=Depends(admin), db=Depends(get_db)):
    result = snapshot(db)
    audit(db, p.user.id, "admin.operations_read", "platform")
    db.commit()
    return result


if __name__ == "__main__":
    with DB() as db:
        print(json.dumps(snapshot(db)))
