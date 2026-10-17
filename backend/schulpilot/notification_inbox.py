"""Bounded in-app notices derived from saved facts, independent of FCM opt-in.

GET never creates events or jobs. Read receipts contain no copied private text.
Membership is checked again on every read and acknowledgement.
"""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import Field
from sqlalchemy import select
from sqlalchemy.orm import load_only

from . import schemas as s
from .db import Job, LanguageProject, Message, NotificationRead, User, VocabularyImport, get_db, now
from .notifications import children_for
from .security import audit, authenticated, rate_limit

RETENTION_DAYS = 30
LIMIT = 50
router = APIRouter(prefix="/notifications", tags=["Neuigkeiten"])


def recent_events(db, user, current=None):
    if user.role not in ("child", "parent"):
        if user.role == "admin":
            audit(db, user.id, "admin.private_access_denied", "notification-inbox")
            db.commit()
        raise HTTPException(403, "Neuigkeiten sind für den eigenen Familienzugang verfügbar.")
    current = int(now()) if current is None else current
    children = {c.id: c for c in children_for(db, user)}
    ids = list(children)
    names = dict(
        db.execute(
            select(User.id, User.display_name).where(User.id.in_([child.user_id for child in children.values()]))
        ).all()
    )
    cutoff = current - RETENTION_DAYS * 86400
    result = []

    def add(key, child_id, stamp, title, route, kind):
        result.append(
            {
                "id": key,
                "child_id": child_id,
                "child_name": names[children[child_id].user_id],
                "created": stamp,
                "title": title,
                "route": route,
                "kind": kind,
            }
        )

    kinds = (
        ["reply", "preparation", "reminder"]
        if user.role == "child"
        else ["help", "interest", "plan_change", "preparation"]
    )
    titles = {
        "reply": "Deine Eltern haben geantwortet",
        "preparation": "Neues zu deinen Heftseiten",
        "reminder": "Dein Lernplan ist bereit",
        "help": "Unterstützung gewünscht",
        "interest": "Ein neuer Lernwunsch",
        "plan_change": "Ein Wunsch zum Lernplan",
    }
    for row in db.scalars(
        select(Message)
        .options(load_only(Message.id, Message.child_id, Message.created, Message.kind, Message.sender_id))
        .where(Message.child_id.in_(ids), Message.kind.in_(kinds), Message.created > cutoff, Message.created <= current)
        .order_by(Message.created.desc(), Message.id.desc())
        .limit(LIMIT)
    ):
        if row.sender_id == user.id:
            continue
        route = f"/child/{row.child_id}" if user.role == "parent" else "/settings"
        if user.role == "child":
            route = (
                f"/after-school/{row.child_id}/history"
                if row.kind == "preparation"
                else "/app"
                if row.kind == "reminder"
                else "/settings"
            )
        add("message:" + row.id, row.child_id, row.created, titles[row.kind], route, row.kind)

    for model, kind, title in (
        (LanguageProject, "language_ready", "Deine Sprachübung ist bereit"),
        (VocabularyImport, "words_ready", "Deine Wörter sind bereit zum Prüfen"),
    ):
        rows = db.execute(
            select(model, Job)
            .options(load_only(model.id, model.child_id), load_only(Job.status, Job.finished))
            .join(Job, Job.id == model.job_id)
            .where(
                model.child_id.in_(ids),
                Job.status.in_(["completed", "failed"]),
                Job.finished > cutoff,
                Job.finished <= current,
            )
            .order_by(Job.finished.desc(), Job.id.desc())
            .limit(LIMIT)
        )
        for row, job in rows:
            failed = job.status == "failed"
            route = (
                f"/language-projects/{row.child_id}?project={row.id}"
                if model == LanguageProject
                else f"/vocabulary/{row.child_id}"
            )
            # Parents open their existing read-only child overview, not a child-only tool.
            if user.role == "parent":
                route = f"/child/{row.child_id}"
            add(
                kind + ":" + row.id,
                row.child_id,
                job.finished,
                "Die Vorbereitung braucht einen neuen Versuch" if failed else title,
                route,
                "failed" if failed else kind,
            )
    return sorted(result, key=lambda row: (row["created"], row["id"]), reverse=True)[:LIMIT]


@router.get("/inbox")
def inbox(p=Depends(authenticated), db=Depends(get_db)):
    items = recent_events(db, p.user)
    read = set(
        db.scalars(
            select(NotificationRead.event_key).where(
                NotificationRead.user_id == p.user.id, NotificationRead.event_key.in_([row["id"] for row in items])
            )
        )
    )
    return {
        "items": [{**row, "read": row["id"] in read} for row in items],
        "unread": sum(row["id"] not in read for row in items),
        "retention_days": RETENTION_DAYS,
        "limit": LIMIT,
    }


class Acknowledge(s.Strict):
    ids: list[str] = Field(min_length=1, max_length=LIMIT)


@router.post("/inbox/read")
def acknowledge(data: Acknowledge, p=Depends(authenticated), db=Depends(get_db)):
    events = {row["id"]: row for row in recent_events(db, p.user)}
    if any(key not in events for key in data.ids):
        raise HTTPException(404, "Diese Neuigkeit ist nicht mehr verfügbar.")
    rate_limit(db, "notification-read:" + p.user.id, 120, 3600, commit=False)
    for key in set(data.ids):
        # Composite conflict target protects simultaneous acknowledgements on two devices.
        from sqlalchemy.dialects.postgresql import insert as pg_insert
        from sqlalchemy.dialects.sqlite import insert as sqlite_insert

        insert = sqlite_insert if db.bind.dialect.name == "sqlite" else pg_insert
        db.execute(
            insert(NotificationRead)
            .values(user_id=p.user.id, event_key=key, child_id=events[key]["child_id"], created=int(now()))
            .on_conflict_do_nothing(index_elements=["user_id", "event_key"])
        )
    db.commit()
    return {"message": "Als gelesen markiert."}
