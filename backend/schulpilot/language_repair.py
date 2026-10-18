"""Bounded requeue: local operator or a new explicit authenticated child action.

Original failed job/usage stay immutable. Neither path revives an old session.
"""

import argparse
import json

from fastapi import HTTPException
from sqlalchemy import select

from .db import DB, Audit, Child, Family, Job, LanguageProject, uid
from .language_projects import REQUEUE_ACTIONS, context
from .learning import record
from .providers import reserve
from .security import audit, child_access, rate_limit
from .vocabulary import authority, lock_child

ACTION, RETRY_ACTION = REQUEUE_ACTIONS


def queue_repair(project_id, failed_job_id):
    with DB.begin() as db:
        return requeue(db, project_id, failed_job_id)


def requeue(db, project_id, failed_job_id, *, principal=None):
    row = db.get(LanguageProject, project_id)
    if not row:
        raise HTTPException(404, "Sprachprojekt nicht gefunden.")
    if principal:
        child_access(db, principal, row.child_id)
        if principal.user.role != "child" or principal.user.id != row.user_id:
            raise HTTPException(403, "Nur der eigene Kinderzugang darf diese Vorbereitung erneut starten.")
    child = db.get(Child, row.child_id)
    if not child:
        raise HTTPException(404, "Kinderzugang wurde gelöscht.")
    lock_child(db, child)
    row = db.get(LanguageProject, project_id, populate_existing=True)
    if not row:
        raise HTTPException(404, "Sprachprojekt wurde gelöscht.")
    old = db.get(Job, failed_job_id)
    if (
        not old
        or old.kind != "language_project"
        or old.child_id != row.child_id
        or old.payload.get("project_id") != row.id
    ):
        raise HTTPException(409, "Der angegebene Fehlerauftrag gehört nicht zu diesem Projekt.")
    previous = db.scalar(select(Audit.id).where(Audit.action.in_(REQUEUE_ACTIONS), Audit.target == row.id))
    if previous:
        job = db.get(Job, row.job_id)
        if not job or job.payload.get("repair_of_job_id") != failed_job_id:
            raise HTTPException(409, "Dieses Projekt hat bereits einen erneuten Auftrag.")
        return {"project_id": row.id, "job_id": job.id, "status": row.status, "replayed": True}
    if (
        old.status != "failed"
        or row.job_id != old.id
        or row.status not in ("failed", "queued", "running")
        or row.unit_id
        or row.result
    ):
        raise HTTPException(
            409, "Nur ein fehlgeschlagenes Projekt ohne vorhandene Übung darf erneut vorbereitet werden."
        )
    previous_session = row.session_id
    if principal:
        # A fresh, explicit action may use the caller's validated session. Never
        # reactivate, forge or automatically replace the revoked original one.
        row.session_id = principal.session.id
    authority(db, row, child.family_id)
    context(db, row)
    if db.scalar(select(Job.id).where(Job.child_id == child.id, Job.status.in_(["queued", "running"]))):
        raise HTTPException(409, "Eine Verarbeitung läuft noch. Bitte kurz warten.")
    rate_limit(db, "language-project:" + row.user_id, 12, 3600, commit=False)
    job = Job(
        id=uid(),
        child_id=child.id,
        kind="language_project",
        idempotency=f"language-repair:{row.id}:{old.id}",
        payload={
            "project_id": row.id,
            "family_id": child.family_id,
            "repair_of_job_id": old.id,
            "previous_session_id": previous_session,
        },
    )
    db.add(job)
    db.flush()
    reserve(db, db.get(Family, child.family_id), child.id, job.id, "language_project")
    row.job_id, row.status, row.error = job.id, "queued", None
    audit(db, principal.user.id if principal else "local-operator", RETRY_ACTION if principal else ACTION, row.id)
    record(db, child.id, "language_project", {"project_id": row.id, "repair_of_job_id": old.id})
    return {"project_id": row.id, "job_id": job.id, "status": row.status, "replayed": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True)
    parser.add_argument("--failed-job", required=True)
    parser.add_argument("--confirmed-code-fix", action="store_true", required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(queue_repair(args.project, args.failed_job)))
    except HTTPException as error:
        raise SystemExit(f"Reparatur gesperrt (HTTP {error.status_code}): {error.detail}") from None


if __name__ == "__main__":
    main()
