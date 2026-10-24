"""Explicit personal parent checks, server scheduled without AI or progress writes."""

import json
from datetime import datetime, timedelta
from typing import Annotated
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import Field, model_validator
from sqlalchemy import delete, func, select, update

from . import schemas as s
from .db import Activity, Child, Family, LearningUnit, Membership, Session, User, get_db, now, uid
from .exam_models import Exam, ExamRound, ExamSession
from .exams import reminder_instant
from .parent_reminder_models import ParentGoalReminder, ParentGoalReminderChange, ParentGoalReminderEvent
from .security import Principal, audit, child_access, digest, parent, rate_limit

router = APIRouter(tags=["Elternhinweise"])
FIELDS = ("enabled", "weekdays", "time", "timezone", "daily_minimum", "exam_sessions")
KIND = "parent_goal"
RETENTION = 30 * 86400


class ReminderRequest(s.Strict):
    revision: int = Field(ge=0, strict=True)
    enabled: bool
    weekdays: list[Annotated[int, Field(strict=True)]] = Field(max_length=7)
    time: str = Field(pattern=r"^(?:[01][0-9]|2[0-3]):[0-5][0-9]$")
    timezone: str = Field(min_length=1, max_length=64)
    daily_minimum: bool
    exam_sessions: bool

    @model_validator(mode="after")
    def valid(self):
        if any(type(day) is not int or not 0 <= day <= 6 for day in self.weekdays) or len(set(self.weekdays)) != len(self.weekdays):
            raise ValueError("Wochentage müssen eindeutig zwischen 0 und 6 liegen.")
        try:
            ZoneInfo(self.timezone)
        except (ZoneInfoNotFoundError, ValueError):
            raise ValueError("Bitte eine gültige Zeitzone wählen.") from None
        if self.enabled and (not self.weekdays or not (self.daily_minimum or self.exam_sessions)):
            raise ValueError("Bitte mindestens einen Wochentag und einen Anlass auswählen.")
        self.weekdays.sort()
        return self


def rule_data(rule, child):
    prefs = s.Preferences(**child.preferences)
    values = {name: getattr(rule, name) for name in FIELDS} if rule else {
        "enabled": False, "weekdays": [0, 1, 2, 3, 4], "time": "18:00", "timezone": prefs.timezone,
        "daily_minimum": True, "exam_sessions": True}
    return {"child_id": child.id, "revision": rule.revision if rule else 0, **values,
        "updated": rule.updated if rule else None, "can_configure": True}


def access(db, p, child_id, *, lock=False):
    if p.user.role != "parent":
        raise HTTPException(403, "Diese persönlichen Hinweise sind für Eltern verfügbar.")
    child = child_access(db, p, child_id)
    if lock:
        actor_id, session_id = p.user.id, p.session.id
        db.execute(update(Child).where(Child.id == child_id).values(grade=Child.grade))
        db.expire_all()
        actor, login = db.get(User, actor_id), db.get(Session, session_id)
        if (not actor or actor.role != "parent" or actor.disabled or not actor.verified or not login or
                login.user_id != actor_id or login.revoked or login.expires <= now() or now() - login.seen > 7 * 86400):
            raise HTTPException(401, "Bitte erneut anmelden.")
        child = child_access(db, Principal(actor, login), child_id)
    return child


@router.get("/children/{child_id}/parent-goal-reminders")
def get_rule(child_id: str, p=Depends(parent), db=Depends(get_db),
             account: str = Header(..., alias="X-Schulpilot-Account", pattern=r"^[a-f0-9]{32}$")):
    if account != p.user.id:
        raise HTTPException(409, "Der angemeldete Zugang wurde geändert. Bitte neu laden.")
    child = access(db, p, child_id)
    return rule_data(db.get(ParentGoalReminder, (p.user.id, child.id)), child)


@router.put("/children/{child_id}/parent-goal-reminders")
def save_rule(child_id: str, data: ReminderRequest, p=Depends(parent), db=Depends(get_db),
              key: str = Header(..., alias="Idempotency-Key", min_length=16, max_length=80, pattern=r"^[A-Za-z0-9_-]+$"),
              account: str = Header(..., alias="X-Schulpilot-Account", pattern=r"^[a-f0-9]{32}$")):
    if account != p.user.id:
        raise HTTPException(409, "Der angemeldete Zugang wurde geändert. Bitte neu laden.")
    child = access(db, p, child_id, lock=True)
    values = data.model_dump()
    request_digest = digest(json.dumps(values, sort_keys=True, separators=(",", ":")))
    previous = db.scalar(select(ParentGoalReminderChange).where(ParentGoalReminderChange.user_id == p.user.id,
        ParentGoalReminderChange.child_id == child.id, ParentGoalReminderChange.request_key == key))
    if previous:
        if previous.digest != request_digest:
            raise HTTPException(409, "Dieser Speicherversuch gehört zu anderen Einstellungen.")
        # Return current truth, including a later change from another device.
        return rule_data(db.get(ParentGoalReminder, (p.user.id, child.id)), child)
    rule = db.get(ParentGoalReminder, (p.user.id, child.id))
    if data.revision != (rule.revision if rule else 0):
        raise HTTPException(409, "Die Hinweise wurden inzwischen geändert. Bitte neu laden.")
    rate_limit(db, "parent-goal-reminder:" + p.user.id, 30, 3600, commit=False)
    if not rule:
        rule = ParentGoalReminder(user_id=p.user.id, child_id=child.id)
        db.add(rule)
    rule.revision = data.revision + 1
    for name in FIELDS:
        setattr(rule, name, values[name])
    rule.updated, rule.next_check = int(now()), 0
    projection = rule_data(rule, child)
    db.add(ParentGoalReminderChange(user_id=p.user.id, child_id=child.id, request_key=key,
        digest=request_digest, projection=projection))
    audit(db, p.user.id, "parent.goal_reminders_changed", child.id)
    db.commit()
    return projection


def live_parent(db, user_id, child, current):
    user = db.get(User, user_id, populate_existing=True)
    family = db.get(Family, child.family_id, populate_existing=True)
    return bool(user and user.role == "parent" and user.verified and not user.disabled and family
        and (family.expires is None or family.expires > current) and db.scalar(select(Membership.id).where(
            Membership.user_id == user_id, Membership.family_id == child.family_id)))


def open_facts(db, child, rule, current):
    """Exact saved seconds and current session completion, never estimated work."""
    prefs = s.Preferences(**child.preferences)
    local = datetime.fromtimestamp(current, ZoneInfo(prefs.timezone))
    remaining = 0
    if (rule.daily_minimum and local.weekday() in prefs.weekdays and
            not (prefs.pause_until and local.date() <= prefs.pause_until)):
        start = int(local.replace(hour=0, minute=0, second=0, microsecond=0).timestamp())
        end = int(datetime.combine(local.date() + timedelta(days=1), datetime.min.time(), ZoneInfo(prefs.timezone)).timestamp())
        seconds = db.scalar(select(func.coalesce(func.sum(Activity.detail["seconds"].as_integer()), 0)).where(
            Activity.child_id == child.id, Activity.kind == "active_time", Activity.created >= start,
            Activity.created < end, Activity.created <= current))
        remaining = max(0, prefs.daily_minutes * 60 - seconds)
    sessions = []
    if rule.exam_sessions:
        for exam in db.scalars(select(Exam).where(Exam.child_id == child.id, Exam.archived.is_(False))
                .order_by(Exam.id).limit(100)):
            today = datetime.fromtimestamp(current, ZoneInfo(exam.timezone)).date().isoformat()
            if exam.exam_date and exam.exam_date < today:
                continue
            session = db.scalar(select(ExamSession).where(ExamSession.exam_id == exam.id,
                ExamSession.exam_revision == exam.plan_revision, ExamSession.date == today))
            if not session:
                continue
            statuses = list(db.execute(select(ExamRound.unit_id, LearningUnit.status, LearningUnit.child_id)
                .outerjoin(LearningUnit, LearningUnit.id == ExamRound.unit_id)
                .where(ExamRound.session_id == session.id)))
            if statuses and not all(row.status == "completed" and row.child_id == child.id for row in statuses):
                sessions.append({"exam_id": exam.id, "session_id": session.id, "plan_revision": exam.plan_revision})
    return {"daily_remaining_seconds": remaining, "exam_sessions": sessions}


def next_check(rule, current):
    local = datetime.fromtimestamp(current, ZoneInfo(rule.timezone))
    for offset in range(8):
        day = local.date() + timedelta(days=offset)
        target = reminder_instant(day, rule.time, ZoneInfo(rule.timezone))
        if day.weekday() in rule.weekdays and target.timestamp() > current:
            return int(target.timestamp())
    return current + 86400


def schedule(db, current=None):
    """Bounded worker sweep, independent of app presence and Firebase config."""
    current = int(now()) if current is None else current
    db.execute(delete(ParentGoalReminderEvent).where(ParentGoalReminderEvent.created < current - RETENTION))
    db.execute(delete(ParentGoalReminderChange).where(ParentGoalReminderChange.created < current - RETENTION))
    # A removed family membership never silently resurrects an old opt-in if
    # the account is invited again later. Other parents' rules are independent.
    for model in (ParentGoalReminder, ParentGoalReminderChange, ParentGoalReminderEvent):
        membership = select(Child.id).join(Membership, Membership.family_id == Child.family_id).where(
            Child.id == model.child_id, Membership.user_id == model.user_id).exists()
        db.execute(delete(model).where(~membership))
    rules = list(db.scalars(select(ParentGoalReminder).where(ParentGoalReminder.enabled.is_(True),
        ParentGoalReminder.next_check <= current).order_by(ParentGoalReminder.next_check, ParentGoalReminder.user_id,
            ParentGoalReminder.child_id).limit(100).with_for_update(skip_locked=True)))
    for rule in rules:
        local = datetime.fromtimestamp(current, ZoneInfo(rule.timezone))
        scheduled = reminder_instant(local.date(), rule.time, ZoneInfo(rule.timezone))
        rule.next_check = next_check(rule, current)
        if local.weekday() not in rule.weekdays or scheduled.timestamp() > current:
            continue
        child = db.get(Child, rule.child_id, populate_existing=True)
        if not child or not live_parent(db, rule.user_id, child, current):
            continue
        facts = open_facts(db, child, rule, current)
        if not facts["daily_remaining_seconds"] and not facts["exam_sessions"]:
            continue
        from sqlalchemy.dialects.postgresql import insert as pg_insert
        from sqlalchemy.dialects.sqlite import insert as sqlite_insert

        insert = sqlite_insert if db.bind.dialect.name == "sqlite" else pg_insert
        db.execute(insert(ParentGoalReminderEvent).values(id=uid(), user_id=rule.user_id, child_id=child.id,
            rule_revision=rule.revision, date=local.date().isoformat(), scheduled=int(scheduled.timestamp()),
            created=current, **facts).on_conflict_do_nothing(index_elements=["user_id", "child_id", "date"]))


def events(db, user_id, current=None):
    current = int(now()) if current is None else current
    return list(db.scalars(select(ParentGoalReminderEvent).where(ParentGoalReminderEvent.user_id == user_id,
        ParentGoalReminderEvent.created > current - RETENTION, ParentGoalReminderEvent.created <= current)
        .order_by(ParentGoalReminderEvent.created.desc(), ParentGoalReminderEvent.id).limit(50)))


def same_child_day(event, child, current):
    zone = ZoneInfo(s.Preferences(**child.preferences).timezone)
    return datetime.fromtimestamp(event.created, zone).date() == datetime.fromtimestamp(current, zone).date()


def due_events(db, user_id, current):
    from .notifications import quiet

    result = []
    for event in events(db, user_id, current):
        child = db.get(Child, event.child_id, populate_existing=True)
        rule = db.get(ParentGoalReminder, (user_id, event.child_id), populate_existing=True)
        if not child or not rule or not rule.enabled or rule.revision != event.rule_revision or not live_parent(db, user_id, child, current):
            continue
        local = datetime.fromtimestamp(current, ZoneInfo(rule.timezone))
        if local.date().isoformat() != event.date or local.weekday() not in rule.weekdays or current < event.scheduled:
            continue
        prefs = s.Preferences(**child.preferences)
        if quiet(datetime.fromtimestamp(current, ZoneInfo(prefs.timezone)), prefs.quiet_start, prefs.quiet_end):
            continue
        facts = open_facts(db, child, rule, current)
        # Source/plan replacement cannot turn an earlier event into another one.
        bound = {(row["exam_id"], row["session_id"], row["plan_revision"]) for row in event.exam_sessions}
        exam_open = any((row["exam_id"], row["session_id"], row["plan_revision"]) in bound for row in facts["exam_sessions"])
        daily_open = bool(event.daily_remaining_seconds and facts["daily_remaining_seconds"] and same_child_day(event, child, current))
        if daily_open or exam_open:
            result.append((event, child, rule))
    return result


def delivery_key(device, event):
    return "parent_goal:" + event.id + ":" + device.id


def export_own(db, user_id, child_ids):
    return {"settings": [{"child_id": row.child_id, "revision": row.revision,
        **{key: getattr(row, key) for key in FIELDS}, "updated": row.updated}
        for row in db.scalars(select(ParentGoalReminder).where(ParentGoalReminder.user_id == user_id,
            ParentGoalReminder.child_id.in_(child_ids)).order_by(ParentGoalReminder.child_id))],
        "events": [{"id": row.id, "child_id": row.child_id, "date": row.date, "scheduled": row.scheduled,
            "created": row.created, "daily_remaining_seconds": row.daily_remaining_seconds,
            "exam_sessions": row.exam_sessions} for row in db.scalars(select(ParentGoalReminderEvent).where(
                ParentGoalReminderEvent.user_id == user_id, ParentGoalReminderEvent.child_id.in_(child_ids))
                .order_by(ParentGoalReminderEvent.created, ParentGoalReminderEvent.id))]}
