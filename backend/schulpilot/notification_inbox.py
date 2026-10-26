"""Bounded in-app notices derived from saved facts, independent of FCM opt-in.

GET never creates events or jobs. Read receipts contain no copied private text.
Membership is checked again on every read and acknowledgement.
"""

from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import Field
from sqlalchemy import select
from sqlalchemy.orm import load_only

from . import schemas as s
from .db import (
    FamilyCall,
    Job,
    LanguageProject,
    Material,
    Message,
    NotificationRead,
    SchoolDay,
    User,
    VocabularyImport,
    get_db,
    now,
)
from .notifications import children_for
from .security import audit, authenticated, rate_limit

RETENTION_DAYS = 30
LIMIT = 50
router = APIRouter(prefix="/notifications", tags=["Neuigkeiten"])


def recent_events(db, user, current=None, *, direct_messages=False, direct_exams=False):
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
    seen_preparations = set()
    if user.role == "parent":
        from .family_calls import effective, eligible_parents

        for call in db.scalars(select(FamilyCall).where(FamilyCall.child_id.in_(ids),
            FamilyCall.created > cutoff, FamilyCall.created <= current).order_by(FamilyCall.created.desc()).limit(LIMIT)):
            if user.id not in eligible_parents(db, call.family_id):
                continue
            status, _ = effective(db, call, current)
            title = {"ringing": "Dein Kind möchte live Hilfe", "accepted": "Familienanruf verbunden",
                "missed": "Ein Familienanruf wurde verpasst", "declined": "Familienanruf abgelehnt",
                "ended": "Familienanruf beendet"}[status]
            add("family_call:" + call.id, call.child_id, call.created, title, "/family-call/" + call.id, "family_call")
    messages = list(db.scalars(
        select(Message)
        .options(load_only(Message.id, Message.child_id, Message.created, Message.kind, Message.sender_id, Message.context))
        .where(Message.child_id.in_(ids), Message.kind.in_(kinds), Message.created > cutoff, Message.created <= current)
        .order_by(Message.created.desc(), Message.id.desc())
        .limit(LIMIT)
    ))
    from .learning import message_context_targets

    targets = message_context_targets(db, messages)
    for row in messages:
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
        context = row.context if isinstance(row.context, dict) and len(row.context) == 1 else {}
        context = {key: target for key, target in context.items()
                   if isinstance(target, str) and (row.child_id, key, target) in targets}
        if row.kind == "preparation" and row.context and not context:
            continue
        # Human messages open the actual reply/request first. Context remains a
        # separate explicit link there; opening a notice must not start a round.
        if direct_messages and row.kind in ("reply", "help", "interest", "plan_change"):
            route = f"/messages/{row.child_id}"
        elif context.get("unit_id"):
            route = f"/unit/{context['unit_id']}"
        elif context.get("material_id"):
            route = f"/material/{context['material_id']}"
        elif context.get("day_id"):
            route = f"/after-school/{row.child_id}?day={context['day_id']}"
        elif row.kind == "preparation":
            route = f"/after-school/{row.child_id}/history"
        title = titles[row.kind]
        if row.kind == "preparation" and context.get("day_id"):
            day_id = context["day_id"]
            day = db.get(SchoolDay, day_id)
            if not day or day.child_id != row.child_id or day_id in seen_preparations:
                continue
            seen_preparations.add(day_id)
            source_rows = list(db.execute(select(Material.subject, Material.confirmed).where(Material.school_day_id == day_id, Material.child_id == row.child_id)))
            count = len(source_rows)
            if count == 0:
                continue
            subjects = sorted({r.subject for r in source_rows if r.subject})
            prefix = f"{count} Heftseite{'n' if count != 1 else ''}" + (" · " + ", ".join(subjects[:2]) + (" …" if len(subjects) > 2 else "") if subjects else "")
            from .ready_notifications import day_route

            route = day_route(db, day, children[row.child_id]) or route
            current_status = (day.preparation or {}).get("status")
            suffix = {"needs_review":"Bitte prüfen", "needs_photo":"Ein Foto neu aufnehmen", "processing":"Wird vorbereitet",
                      "ready":"Lernpaket bereit", "saved":"Für später gespeichert", "failed":"Vorbereitung noch offen", "blocked":"Vorbereitung noch offen"}.get(current_status, "Heftseiten öffnen")
            if current_status == "ready" and (ready_count := sum(r.confirmed for r in source_rows)) < count:
                suffix = f"Lernpaket aus {ready_count} von {count} Seiten bereit · {count - ready_count} noch offen"
            title = f"{prefix} · {suffix}"
        add("message:" + row.id, row.child_id, row.created, title, route, row.kind)

    from .ready_notifications import events_for_child as round_events

    for child in children.values():
        for event in round_events(db, child, current, retention=RETENTION_DAYS*86400):
            add(event["id"], child.id, event["created"], event["title"], event["route"], event["kind"])

    for model, kind, title in (
        (LanguageProject, "language_ready", "Deine Sprachübung ist bereit"),
        (VocabularyImport, "words_ready", "Deine Wörter sind bereit zum Prüfen"),
    ):
        rows = db.execute(
            select(model, Job)
            .options(load_only(model.id, model.child_id, model.status), load_only(Job.status, Job.finished))
            .join(Job, Job.id == model.job_id)
            .where(
                model.child_id.in_(ids),
                Job.status.in_(["completed", "failed"]),
                Job.finished > cutoff,
                Job.finished <= current,
                Job.result["deleted"].as_boolean().is_not(True),
            )
            .order_by(Job.finished.desc(), Job.id.desc())
            .limit(LIMIT)
        )
        for row, job in rows:
            if model == VocabularyImport and row.status == "confirmed":
                continue
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
    if user.role == "parent":
        from .parent_goal_reminders import events

        for event in events(db, user.id, current):
            if event.child_id in children:
                # A dated, saved check, not a claim that work remains open now.
                add("parent_goal:" + event.id, event.child_id, event.created,
                    "Tagescheck: Lernziele waren noch offen", f"/child/{event.child_id}", "parent_goal")
    from .exam_notifications import events_for_child

    for child in children.values():
        for event in events_for_child(db, child, current):
            route = event["route"] if direct_exams else f"/child/{child.id}" if user.role == "parent" else "/app"
            add(event["id"], child.id, event["created"], event["title"], route, event["kind"])
    return sorted(result, key=lambda row: (row["created"], row["id"]), reverse=True)[:LIMIT]


@router.get("/inbox")
def inbox(p=Depends(authenticated), db=Depends(get_db),
          capabilities: str | None = Header(None, alias="X-Schulpilot-Capabilities")):
    items = recent_events(db, p.user, direct_messages="messages-v1" in (capabilities or "").split(","),
        direct_exams="exams-v1" in (capabilities or "").split(","))
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
