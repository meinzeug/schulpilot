"""Opt-in, session-bound FCM. Fixed neutral payloads; no public send endpoint."""

import json
import logging
import threading
from datetime import datetime
from pathlib import Path
from typing import Literal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import httpx
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import Response
from pydantic import Field, model_validator
from sqlalchemy import delete, func, select, update

from . import schemas as s
from .config import runtime_settings
from .db import (
    Activity,
    Child,
    Family,
    Membership,
    Message,
    NotificationRead,
    PushDelivery,
    PushDevice,
    PushTestGrant,
    Session,
    User,
    get_db,
    now,
    uid,
)
from .security import admin, audit, authenticated, decrypt, digest, encrypt, insert_ignore, rate_limit

router = APIRouter(prefix="/notifications", tags=["Benachrichtigungen"])
log = logging.getLogger("schulpilot.push")
_call_dispatch_slots = threading.BoundedSemaphore(4)


def public_config(*, testing=False):
    site = runtime_settings()
    try:
        raw = json.loads(site.fcm_public_config or "{}")
        allowed = {
            k: raw[k]
            for k in (
                "apiKey",
                "appId",
                "messagingSenderId",
                "projectId",
                "authDomain",
                "vapidKey",
                "androidAppId",
                "androidApiKey",
            )
            if isinstance(raw.get(k), str)
        }
        valid = all(allowed.get(k) for k in ("apiKey", "appId", "messagingSenderId", "projectId", "androidAppId"))
    except (ValueError, TypeError):
        allowed, valid = {}, False
    ready = bool(
        valid
        and site.fcm_config_verification
        and ((site.push_approved and site.push_privacy_evidence) or (testing and site.fcm_config_verification))
        and (
            site.fcm_service_account_json
            or (site.fcm_service_account_file and Path(site.fcm_service_account_file).is_file())
        )
    )
    return {
        "available": ready,
        "test_mode": bool(ready and not site.push_approved),
        "firebase": allowed if ready else {},
        "notice": "Push enthält nur neutrale Hinweise. Inhalte öffnest du nach Anmeldung in SchuleSchlau."
        if ready
        else "Push ist vorbereitet. Firebase-Projekt, Dienstkonto und dokumentierte Datenschutzfreigabe sind noch erforderlich.",
    }


@router.get("/config")
def config(request: Request, db=Depends(get_db)):
    # Firebase client identifiers are public, never service account credentials.
    # An isolated synthetic test grant cannot turn production delivery on.
    try:
        p = authenticated(request, db)
        if p.user.role == "child":
            child = db.scalar(select(Child).where(Child.user_id == p.user.id))
            if not child or not s.Preferences(**child.preferences).push_consent:
                return {
                    "available": False,
                    "firebase": {},
                    "notice": "Deine Eltern können Benachrichtigungen für deinen Zugang erlauben.",
                }
        if test_allowed(db, p.user.id):
            return {**public_config(testing=True), "test_access": True}
    except HTTPException:
        pass
    return public_config()


@router.get("/service-worker.js")
def service_worker():
    config = public_config(testing=True)
    if not config["available"]:
        raise HTTPException(503, config["notice"])
    firebase = {
        k: v
        for k, v in config["firebase"].items()
        if k in ("apiKey", "appId", "messagingSenderId", "projectId", "authDomain")
    }
    # Configuration must be present synchronously when the worker starts;
    # fetching it asynchronously can lose the first background push event.
    from .exam_notifications import EXAM_PATH_PATTERN
    from .preparation_notifications import PREPARATION_PATH_PATTERN

    script = r"""self.addEventListener('notificationclick', event => {
  event.stopImmediatePropagation(); event.notification.close();
  const data = event.notification.data || {};
  const payload = data.FCM_MSG && data.FCM_MSG.data ? data.FCM_MSG.data : data;
  const path = payload.exam_path === undefined ? payload.route : payload.exam_path;
  const target = typeof path === 'string' && /^(?:EXAM_PATH|PREPARATION_PATH)(?![\s\S])/.test(path) ? path : '/app';
  event.waitUntil(clients.openWindow(target));
});
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-messaging-compat.js');
firebase.initializeApp(CONFIG); firebase.messaging();
""".replace("CONFIG", json.dumps(firebase).replace("<", "\\u003c")).replace("EXAM_PATH", EXAM_PATH_PATTERN.replace("/", "\\/")).replace("PREPARATION_PATH", PREPARATION_PATH_PATTERN.replace("/", "\\/"))
    return Response(
        script,
        media_type="application/javascript",
        headers={"Service-Worker-Allowed": "/", "Cache-Control": "no-store"},
    )


class DeviceRequest(s.Strict):
    token: str = Field(min_length=32, max_length=4096, pattern=r"^[A-Za-z0-9_:.-]+$")
    platform: Literal["android", "web"]
    timezone: str = Field(default="Europe/Berlin", max_length=64)
    quiet_start: int = Field(default=20, ge=0, le=23)
    quiet_end: int = Field(default=8, ge=0, le=23)
    reminders: bool = True
    help_requests: bool = True
    summaries: bool = False
    family_calls: bool = False
    call_binding: str | None = Field(default=None, min_length=64, max_length=64, pattern=r"^[a-f0-9]{64}$")

    @model_validator(mode="after")
    def valid_zone(self):
        try:
            ZoneInfo(self.timezone)
        except ZoneInfoNotFoundError:
            raise ValueError("Unbekannte Zeitzone.") from None
        if self.family_calls and not self.call_binding:
            raise ValueError("Anrufe benötigen eine aktuelle Gerätefreigabe.")
        return self


def device_data(device, current=None):
    return {
        **{
            k: getattr(device, k)
            for k in (
                "id",
                "platform",
                "timezone",
                "quiet_start",
                "quiet_end",
                "reminders",
                "help_requests",
                "summaries",
                "family_calls",
                "updated",
            )
        },
        "current": device.session_id == current,
    }


@router.get("/devices")
def devices(p=Depends(authenticated), db=Depends(get_db)):
    return [
        device_data(d, p.session.id)
        for d in db.scalars(
            select(PushDevice)
            .join(Session, Session.id == PushDevice.session_id)
            .where(PushDevice.user_id == p.user.id, Session.revoked.is_(False), Session.expires > now())
        )
    ]


@router.put("/device")
def register(data: DeviceRequest, p=Depends(authenticated), db=Depends(get_db)):
    if p.user.role not in ("child", "parent"):
        raise HTTPException(403, "Familienbenachrichtigungen sind für Eltern und Kinder verfügbar.")
    if data.family_calls and p.user.role != "parent":
        raise HTTPException(403, "Eingehende Familienanrufe sind für Eltern verfügbar.")
    if p.user.role == "child":
        child = db.scalar(select(Child).where(Child.user_id == p.user.id))
        if not child or not s.Preferences(**child.preferences).push_consent:
            raise HTTPException(403, "Deine Eltern müssen Benachrichtigungen für deinen Zugang zuerst erlauben.")
    config = public_config(testing=test_allowed(db, p.user.id))
    if not config["available"]:
        raise HTTPException(503, config["notice"])
    rate_limit(db, "push-register:" + p.user.id, 20, 3600)
    if p.user.role == "child":
        db.execute(update(Child).where(Child.user_id == p.user.id).values(grade=Child.grade))
        db.refresh(child)
        if not s.Preferences(**child.preferences).push_consent:
            raise HTTPException(403, "Deine Eltern haben Benachrichtigungen für deinen Zugang nicht freigegeben.")
    token_hash = digest(data.token)
    # One token can belong to one session only. Moving accounts on a shared
    # device destroys all queued deliveries for its former registration.
    existing = db.scalar(select(PushDevice).where(PushDevice.token_hash == token_hash))
    if existing and existing.session_id != p.session.id:
        db.delete(existing)
        db.flush()
        existing = None
    # One active registration per app session; replacements are atomic.
    db.execute(delete(PushDevice).where(PushDevice.session_id == p.session.id, PushDevice.token_hash != token_hash))
    device = existing or PushDevice(user_id=p.user.id, session_id=p.session.id, token_hash=token_hash)
    for name, value in data.model_dump(exclude={"token"}).items():
        setattr(device, name, value)
    if not data.family_calls:
        device.call_binding = None
    device.encrypted_token = encrypt(data.token)
    device.updated = int(now())
    db.add(device)
    db.commit()
    return {**device_data(device, p.session.id), "call_capable": p.user.role == "parent" and device.family_calls}


@router.delete("/devices/{device_id}")
def remove(device_id: str, p=Depends(authenticated), db=Depends(get_db)):
    result = db.execute(delete(PushDevice).where(PushDevice.id == device_id, PushDevice.user_id == p.user.id))
    if not result.rowcount:
        raise HTTPException(404, "Push-Gerät nicht gefunden.")
    db.commit()
    return {"message": "Benachrichtigungen für dieses Gerät abgemeldet."}


def quiet(moment, start, end):
    if start == end:
        return False
    return moment.hour >= start or moment.hour < end if start > end else start <= moment.hour < end


def seconds_before_quiet(current, zone, start, end):
    from datetime import timedelta

    moment = datetime.fromtimestamp(current, ZoneInfo(zone))
    if quiet(moment, start, end):
        return 0
    if start == end:
        return 86400
    target = moment.replace(hour=start, minute=0, second=0, microsecond=0)
    if target <= moment:
        target += timedelta(days=1)
    return max(0, int(target.timestamp() - current))


def children_for(db, user):
    if user.role == "child":
        return list(db.scalars(select(Child).join(Family).where(Child.user_id == user.id,
            (Family.expires.is_(None)) | (Family.expires > int(now())))))
    if user.role == "parent":
        return list(
            db.scalars(
                select(Child)
                .join(Family, Family.id == Child.family_id)
                .join(Membership, Membership.family_id == Child.family_id)
                .where(Membership.user_id == user.id, (Family.expires.is_(None)) | (Family.expires > int(now())))
            )
        )
    return []


def test_allowed(db, user_id):
    grant = db.get(PushTestGrant, user_id)
    user = db.get(User, user_id)
    if not grant or grant.expires <= now() or not user or user.disabled or not user.verified:
        return False
    if user.role == "parent":
        families = list(
            db.scalars(
                select(Family).join(Membership, Membership.family_id == Family.id).where(Membership.user_id == user_id)
            )
        )
    elif user.role == "child":
        families = list(
            db.scalars(select(Family).join(Child, Child.family_id == Family.id).where(Child.user_id == user_id))
        )
    else:
        return False
    return bool(families and all(f.synthetic and (not f.expires or f.expires > now()) for f in families))


def test_device_allowed(db, device, current):
    session = db.get(Session, device.session_id)
    if not session or session.revoked or session.expires <= current or current - session.seen > 7 * 86400:
        return False
    if not test_allowed(db, device.user_id) or not public_config(testing=True)["available"]:
        return False
    if quiet(datetime.fromtimestamp(current, ZoneInfo(device.timezone)), device.quiet_start, device.quiet_end):
        return False
    for child in children_for(db, db.get(User, device.user_id)):
        prefs = s.Preferences(**child.preferences)
        if db.get(User, device.user_id).role == "child" and not prefs.push_consent:
            return False
        if quiet(datetime.fromtimestamp(current, ZoneInfo(prefs.timezone)), prefs.quiet_start, prefs.quiet_end):
            return False
    return True


@router.get("/admin/status")
def operator_status(p=Depends(admin), db=Depends(get_db)):
    site = runtime_settings(db)
    identity, project, valid = None, None, False
    try:
        raw = json.loads(site.fcm_service_account_json or Path(site.fcm_service_account_file).read_text())
        identity, project = raw.get("client_email"), raw.get("project_id")
        valid = (
            raw.get("type") == "service_account"
            and raw.get("token_uri") == "https://oauth2.googleapis.com/token"
            and bool(raw.get("private_key"))
        )
    except (ValueError, OSError):
        pass
    audit(db, p.user.id, "push.operational_status", "firebase")
    device_counts = dict(db.execute(select(PushDevice.platform, func.count()).group_by(PushDevice.platform)).all())
    delivery_counts = dict(db.execute(select(PushDelivery.status, func.count()).where(
        PushDelivery.created >= int(now()) - 86400).group_by(PushDelivery.status)).all())
    db.commit()
    return {
        "production_approved": site.push_approved,
        "production_available": public_config()["available"],
        "test_available": public_config(testing=True)["available"],
        "project_id": project,
        "sender_identity": identity,
        "credential_configured": valid,
        "config_verification": site.fcm_config_verification,
        "privacy_evidence": site.push_privacy_evidence,
        "device_counts": {platform: device_counts.get(platform, 0) for platform in ("android", "web")},
        "delivery_counts_24h": delivery_counts,
        "delivery_notice": "Konfiguration und Annahme durch FCM beweisen keine am Gerät sichtbare Zustellung.",
    }


class OwnTest(s.Strict):
    mode: Literal["validate", "send"]


@router.post("/test", status_code=202)
def own_test(data: OwnTest, p=Depends(authenticated), db=Depends(get_db)):
    if not test_allowed(db, p.user.id):
        raise HTTPException(403, "Push-Tests sind nur für eigens freigegebene künstliche Testkonten verfügbar.")
    device = db.scalar(select(PushDevice).where(PushDevice.session_id == p.session.id, PushDevice.user_id == p.user.id))
    if not device:
        raise HTTPException(409, "Zuerst Benachrichtigungen auf diesem Gerät einschalten.")
    if not test_device_allowed(db, device, int(now())):
        raise HTTPException(409, "Der Test ist derzeit gesperrt. Freigabe, Sitzung und Ruhezeiten prüfen.")
    rate_limit(db, "push-test:" + p.user.id, 6, 86400)
    delivery = PushDelivery(device_id=device.id, dedup_key="test:" + uid(), kind="test_" + data.mode)
    db.add(delivery)
    db.commit()
    return {"id": delivery.id, "status": "queued"}


@router.get("/tests")
def own_tests(p=Depends(authenticated), db=Depends(get_db)):
    return {
        "allowed": test_allowed(db, p.user.id),
        "results": [
            {
                "id": d.id,
                "mode": d.kind.removeprefix("test_"),
                "status": d.status,
                "error": d.error_code,
                "created": d.created,
            }
            for d in db.scalars(
                select(PushDelivery)
                .join(PushDevice, PushDevice.id == PushDelivery.device_id)
                .where(
                    PushDevice.user_id == p.user.id,
                    PushDevice.session_id == p.session.id,
                    PushDelivery.kind.in_(["test_validate", "test_send"]),
                )
                .order_by(PushDelivery.created.desc())
                .limit(12)
            )
        ],
    }


def due_kinds(db, device, current):
    """Re-evaluated immediately before send, including current membership."""
    user = db.get(User, device.user_id)
    session = db.get(Session, device.session_id)
    if (
        not user
        or user.disabled
        or not user.verified
        or not session
        or session.user_id != user.id
        or session.revoked
        or session.expires <= current
        or current - session.seen > 7 * 86400
    ):
        return []
    moment = datetime.fromtimestamp(current, ZoneInfo(device.timezone))
    if quiet(moment, device.quiet_start, device.quiet_end):
        return []
    result = set()
    for child in children_for(db, user):
        prefs = s.Preferences(**child.preferences)
        if user.role == "child" and not prefs.push_consent:
            continue
        local = datetime.fromtimestamp(current, ZoneInfo(prefs.timezone))
        if quiet(local, prefs.quiet_start, prefs.quiet_end):
            continue
        start = int(local.replace(hour=0, minute=0, second=0, microsecond=0).timestamp())
        if user.role == "parent":
            if (
                device.help_requests
                and prefs.notify_help
                and db.scalar(
                    select(Message.id).where(
                        Message.child_id == child.id,
                        Message.kind == "help",
                        Message.resolved.is_(False),
                        Message.created > current - 86400,
                    )
                )
            ):
                result.add("help")
            if (
                device.summaries
                and local.hour >= 18
                and db.scalar(select(Activity.id).where(Activity.child_id == child.id, Activity.created >= start))
            ):
                result.add("summary")
        elif (
            device.reminders
            and prefs.reminders
            and local.hour >= 16
            and local.weekday() in prefs.weekdays
            and not (prefs.pause_until and local.date() <= prefs.pause_until)
        ):
            from .db import VocabularyItem, VocabularyReview

            word_due = db.scalar(select(VocabularyReview.id).join(VocabularyItem).where(
                VocabularyReview.child_id == child.id, VocabularyReview.revision == VocabularyItem.revision,
                VocabularyReview.due <= local.date().isoformat()).limit(1))
            if word_due or not db.scalar(
                select(Activity.id).where(
                    Activity.child_id == child.id, Activity.kind == "unit_completed", Activity.created >= start
                )
            ):
                result.add("reminder")
        if (
            user.role == "child"
            and device.help_requests
            and db.scalar(
                select(Message.id).where(
                    Message.child_id == child.id, Message.kind == "reply", Message.created > current - 3600
                )
            )
        ):
            result.add("reply")
        if user.role == "child" and device.reminders:
            from .exam_notifications import events_for_child

            result.update(event["kind"] for event in events_for_child(db, child, current, retention=86400))
            from .preparation_notifications import events_for_child as preparation_events

            result.update(event["kind"] for event in preparation_events(db, child, current))
            from .ready_notifications import events_for_child as round_events

            result.update(event["kind"] for event in round_events(db, child, current))
            # New language jobs share the same queue. Only a currently valid
            # request/source may trigger a notice, never a generated answer.
            from .db import Job, LanguageProject, VocabularyImport
            from .vocabulary import authority, current_sources

            for model, ready in ((LanguageProject, "ready"), (VocabularyImport, "review")):
                for row in db.scalars(select(model).join(Job, Job.id == model.job_id).where(
                    model.child_id == child.id, model.status == ready, Job.status == "completed",
                    Job.finished > current - 86400, Job.finished <= current).limit(20)):
                    try:
                        authority(db, row, child.family_id)
                        current_sources(db, child.id, row.source_revisions)
                        if model == LanguageProject:
                            from .language_projects import context

                            context(db, row)
                    except HTTPException:
                        continue
                    result.add("learning_ready")
    if user.role == "parent" and device.reminders:
        from .parent_goal_reminders import due_events

        if due_events(db, user.id, current):
            result.add("parent_goal")
    return sorted(result)


def prepare(db, current=None):
    current = int(now()) if current is None else current
    # Revocation immediately disables delivery even before maintenance cleanup.
    dead_sessions = select(Session.id).where(
        (Session.revoked.is_(True)) | (Session.expires <= current) | (Session.seen < current - 7 * 86400)
    )
    db.execute(delete(PushDevice).where(PushDevice.session_id.in_(dead_sessions)))
    db.execute(delete(PushDevice).where(PushDevice.updated < current - 60 * 86400))
    db.execute(delete(PushDelivery).where(PushDelivery.created < current - 14 * 86400))
    db.execute(delete(NotificationRead).where(NotificationRead.created < current - 30 * 86400))
    from .parent_goal_reminders import schedule

    schedule(db, current)
    if not public_config()["available"]:
        return
    for device in db.scalars(select(PushDevice)):
        # A daily bundle per category, rather than a notification per answer.
        for kind in due_kinds(db, device, current):
            day = datetime.fromtimestamp(current, ZoneInfo(device.timezone)).strftime("%Y-%m-%d")
            key = device.id + ":" + kind + ":" + day
            if kind == "parent_goal":
                from .parent_goal_reminders import delivery_key, due_events

                for event, _, _ in due_events(db, device.user_id, current):
                    insert_ignore(db, PushDelivery, {"id": uid(), "device_id": device.id,
                        "dedup_key": delivery_key(device, event), "kind": kind,
                        "status": "queued", "created": current}, key="dedup_key")
                continue
            if kind == "exam_ready":
                from .exam_notifications import delivery_key, events_for_child

                for child in children_for(db, db.get(User, device.user_id)):
                    for event in events_for_child(db, child, current, retention=86400):
                        if event["kind"] == kind:
                            insert_ignore(db, PushDelivery, {"id": uid(), "device_id": device.id,
                                "dedup_key": delivery_key(device, event), "kind": kind,
                                "status": "queued", "created": current}, key="dedup_key")
                continue
            if kind == "round_ready":
                from .ready_notifications import delivery_key, events_for_child

                for child in children_for(db, db.get(User, device.user_id)):
                    for event in events_for_child(db, child, current):
                        insert_ignore(db, PushDelivery, {"id": uid(), "device_id": device.id,
                            "dedup_key": delivery_key(device, event), "kind": kind,
                            "status": "queued", "created": current}, key="dedup_key")
                continue
            if kind in ("preparation_ready", "preparation_review"):
                from .preparation_notifications import delivery_key, events_for_child

                for child in children_for(db, db.get(User, device.user_id)):
                    for event in events_for_child(db, child, current):
                        if event["kind"] == kind:
                            insert_ignore(db, PushDelivery, {"id": uid(), "device_id": device.id,
                                "dedup_key": delivery_key(device, event), "kind": kind,
                                "status": "queued", "created": current}, key="dedup_key")
                continue
            insert_ignore(
                db,
                PushDelivery,
                {
                    "id": uid(),
                    "device_id": device.id,
                    "dedup_key": key,
                    "kind": kind,
                    "status": "queued",
                    "created": current,
                },
                key="dedup_key",
            )


class FcmError(Exception):
    def __init__(self, code, unregistered=False):
        self.code, self.unregistered = code, unregistered


def send_fcm(token, kind, ttl=60, *, testing=False, validate_only=False, call_data=None, exam_path=None, preparation_path=None, unit_path=None):
    from .exam_notifications import valid_exam_path

    if exam_path is not None and not valid_exam_path(exam_path):
        raise FcmError("INVALID_EXAM_PATH")
    from .preparation_notifications import valid_preparation_path
    from .ready_notifications import valid_unit_path

    if preparation_path is not None and (exam_path is not None or not (valid_preparation_path(preparation_path) or valid_unit_path(preparation_path))):
        raise FcmError("INVALID_PREPARATION_PATH")

    if unit_path is not None and (exam_path is not None or preparation_path is not None or not valid_unit_path(unit_path)):
        raise FcmError("INVALID_UNIT_PATH")
    site = runtime_settings()
    config = public_config(testing=testing)
    if not config["available"]:
        raise FcmError("NOT_CONFIGURED")
    from google.auth.transport.requests import Request
    from google.oauth2 import service_account

    try:
        info = json.loads(site.fcm_service_account_json or Path(site.fcm_service_account_file).read_text())
        project = config["firebase"]["projectId"]
        if (
            info.get("type") != "service_account"
            or info.get("project_id") != project
            or info.get("token_uri") != "https://oauth2.googleapis.com/token"
        ):
            raise FcmError("INVALID_SERVICE_ACCOUNT")
        credentials = service_account.Credentials.from_service_account_info(
            info, scopes=["https://www.googleapis.com/auth/firebase.messaging"]
        )

        class TimedRequest(Request):
            def __call__(self, *args, **kwargs):
                kwargs["timeout"] = 20
                return super().__call__(*args, **kwargs)

        credentials.refresh(TimedRequest())
        body = (
            "Es gibt Neuigkeiten in SchuleSchlau. Öffne deinen Lernraum."
            if kind != "reminder"
            else "Dein Lernplan ist bereit. Öffne ihn, wenn es für dich passt."
        )
        if kind == "parent_goal":
            body = "Ein geplanter Tagescheck ist da. Öffne SchuleSchlau."
        message = {
            "token": token,
            "notification": {"title": "SchuleSchlau", "body": body},
            "data": {"route": "/app"},
            "android": {
                # User-visible, already bundled notifications should arrive
                # during Doze too. Keep the short privacy/quiet-hours TTL.
                "priority": "high",
                "ttl": str(ttl) + "s",
                "collapse_key": "schulpilot",
                "notification": {"tag": "schulpilot", "visibility": "PRIVATE",
                                 "channel_id": "schulpilot_updates_v1", "icon": "ic_notification"},
            },
            "webpush": {
                "headers": {"TTL": str(ttl), "Urgency": "normal"},
                "fcm_options": {"link": site.public_url + "/app"},
            },
        }
        if exam_path is not None:
            message["data"]["exam_path"] = exam_path
            message["webpush"]["fcm_options"]["link"] = site.public_url + exam_path
        if preparation_path is not None:
            message["data"]["route"] = preparation_path
            message["webpush"]["fcm_options"]["link"] = site.public_url + preparation_path
        if unit_path is not None:
            message["data"]["route"] = unit_path
            message["webpush"]["fcm_options"]["link"] = site.public_url + unit_path
        if call_data is not None:
            # Data-only: Android's own call notification owns the ringtone and
            # call-style actions. Never include a private name, subject or text.
            message = {"token": token, "data": call_data,
                "android": {"priority": "high", "ttl": str(min(45, ttl)) + "s",
                    "collapse_key": "family_call_" + call_data["call_id"]}}
        with httpx.Client(timeout=20, follow_redirects=False) as client:
            response = client.post(
                "https://fcm.googleapis.com/v1/projects/" + project + "/messages:send",
                headers={"Authorization": "Bearer " + credentials.token},
                json={"message": message, **({"validate_only": True} if validate_only else {})},
            )
        if response.status_code != 200:
            raw = response.json().get("error", {})
            codes = [d.get("errorCode") for d in raw.get("details", []) if isinstance(d, dict)]
            raise FcmError(
                "UNREGISTERED" if "UNREGISTERED" in codes else "HTTP_" + str(response.status_code),
                "UNREGISTERED" in codes,
            )
    except FcmError:
        raise
    except Exception:
        # Never log an HTTP body, registration token, credential or traceback.
        raise FcmError("TRANSPORT_OR_AUTH_ERROR") from None


def deliver_one(DB, *, call_id=None):
    with DB() as db:
        query = select(PushDelivery).where(PushDelivery.status == "queued")
        if call_id is not None:
            query = query.where(PushDelivery.dedup_key.like("family_call:" + call_id + ":%"))
        delivery = db.scalar(query.order_by(PushDelivery.created).limit(1))
        if not delivery:
            return False
        if not db.execute(
            update(PushDelivery)
            .where(PushDelivery.id == delivery.id, PushDelivery.status == "queued")
            .values(status="sending")
        ).rowcount:
            db.rollback()
            return True
        delivery_id, device_id, kind = delivery.id, delivery.device_id, delivery.kind
        db.commit()
        device = db.get(PushDevice, device_id)
        testing = kind in ("test_validate", "test_send")
        call_data, exam_path, preparation_path, parent_goal, unit_path = None, None, None, None, None
        if kind in ("family_call_incoming", "family_call_ended"):
            from .db import FamilyCall

            pieces = delivery.dedup_key.split(":")
            call = db.get(FamilyCall, pieces[1]) if len(pieces) == 4 else None
            event = kind.removeprefix("family_call_")
            allowed = call_delivery_allowed(db, device, call, event, int(now()))
            if allowed:
                expiry = call.ring_expires if event == "incoming" else int(now()) + 45
                call_data = {"type": "family_call", "event": event, "call_id": call.id,
                    "call_binding": device.call_binding, "device_id": device.id,
                    "expires_at": str(expiry * 1000), "route": "/family-call/" + call.id}
                testing = not public_config()["available"] and test_allowed(db, device.user_id)
        else:
            allowed = device and (
                test_device_allowed(db, device, int(now())) if testing else kind in due_kinds(db, device, int(now()))
            )
        if not allowed:
            delivery.status = "suppressed"
            db.commit()
            return True
        if kind == "parent_goal":
            from .parent_goal_reminders import delivery_key, due_events

            parent_goal = next((value for value in due_events(db, device.user_id, int(now()))
                if delivery_key(device, value[0]) == delivery.dedup_key), None)
            if parent_goal is None:
                delivery.status = "suppressed"
                db.commit()
                return True
        if kind in ("exam_reminder", "exam_ready"):
            from .exam_notifications import events_for_child

            user = db.get(User, device.user_id)
            candidates = [event for child in children_for(db, user)
                for event in events_for_child(db, child, int(now()), retention=86400) if event["kind"] == kind]
            today = datetime.fromtimestamp(int(now()), ZoneInfo(device.timezone)).strftime("%Y-%m-%d")
            if kind == "exam_ready":
                from .exam_notifications import delivery_key

                event = next((event for event in candidates if delivery_key(device, event) == delivery.dedup_key), None)
            else:
                event = (max(candidates, key=lambda event: (event["created"], event["id"]))
                    if candidates and delivery.dedup_key == device.id + ":" + kind + ":" + today else None)
            if event is None:
                delivery.status = "suppressed"
                db.commit()
                return True
            exam_path = event["route"]
        if kind in ("preparation_ready", "preparation_review"):
            from .preparation_notifications import delivery_key, events_for_child

            event = next((event for child in children_for(db, db.get(User, device.user_id))
                for event in events_for_child(db, child, int(now()))
                if event["kind"] == kind and delivery_key(device, event) == delivery.dedup_key), None)
            if not event:
                delivery.status = "suppressed"
                db.commit()
                return True
            preparation_path = event["route"]
        if kind == "round_ready":
            from .ready_notifications import delivery_key, events_for_child

            event = next((event for child in children_for(db, db.get(User, device.user_id))
                for event in events_for_child(db, child, int(now()))
                if delivery_key(device, event) == delivery.dedup_key), None)
            if not event:
                delivery.status = "suppressed"
                db.commit()
                return True
            unit_path = event["route"]
        token = decrypt(device.encrypted_token)
        maximum_ttl = 3600 if kind == "parent_goal" else 60
        ttl = min(maximum_ttl, seconds_before_quiet(int(now()), device.timezone, device.quiet_start, device.quiet_end))
        if parent_goal is not None:
            event, _, rule = parent_goal
            local = datetime.fromtimestamp(int(now()), ZoneInfo(rule.timezone))
            from datetime import timedelta

            midnight = datetime.combine(local.date() + timedelta(days=1), datetime.min.time(), ZoneInfo(rule.timezone))
            ttl = min(ttl, int(midnight.timestamp()) - int(now()))
            from .parent_goal_reminders import same_child_day

            if event.daily_remaining_seconds and same_child_day(event, parent_goal[1], int(now())):
                zone = ZoneInfo(s.Preferences(**parent_goal[1].preferences).timezone)
                child_local = datetime.fromtimestamp(int(now()), zone)
                child_midnight = datetime.combine(child_local.date() + timedelta(days=1), datetime.min.time(), zone)
                ttl = min(ttl, int(child_midnight.timestamp()) - int(now()))
        if call_data is not None:
            ttl = min(ttl, 45, int(call_data["expires_at"]) // 1000 - int(now()))
        ttl_children = [parent_goal[1]] if parent_goal is not None else children_for(db, db.get(User, device.user_id))
        for child in ttl_children:
            preferences = s.Preferences(**child.preferences)
            ttl = min(
                ttl,
                seconds_before_quiet(int(now()), preferences.timezone, preferences.quiet_start, preferences.quiet_end),
            )
        if ttl < 1:
            delivery.status = "suppressed"
            db.commit()
            return True
        db.rollback()
    code, unregistered = None, False
    try:
        if call_data is not None:
            send_fcm(token, kind, ttl, testing=testing, call_data=call_data)
        elif exam_path is not None:
            send_fcm(token, kind, ttl, exam_path=exam_path)
        elif unit_path is not None:
            send_fcm(token, kind, ttl, unit_path=unit_path)
        elif preparation_path is not None:
            send_fcm(token, kind, ttl, preparation_path=preparation_path)
        elif testing:
            send_fcm(token, kind, ttl, testing=True, validate_only=kind == "test_validate")
        else:
            send_fcm(token, kind, ttl)
    except FcmError as error:
        code, unregistered = error.code, error.unregistered
    with DB.begin() as db:
        delivery = db.get(PushDelivery, delivery_id)
        if delivery:
            delivery.status = "failed" if code else "validated" if kind == "test_validate" else "accepted"
            delivery.error_code, delivery.sent = code, int(now())
        if unregistered:
            db.execute(delete(PushDevice).where(PushDevice.id == device_id))
    # A timeout is not replayed: it may already have been accepted by FCM.
    return True


def call_delivery_allowed(db, device, call, event, current):
    """Explicit parent call opt-in, live memberships and both device sessions."""
    from .family_calls import effective, eligible_parents, live_session

    if not device or not call or not device.family_calls or not device.call_binding or device.platform != "android":
        return False
    user = db.get(User, device.user_id)
    if not user or user.role != "parent" or user.id not in eligible_parents(db, call.family_id):
        return False
    if not live_session(db, device.session_id, user.id):
        return False
    if not public_config(testing=test_allowed(db, user.id))["available"]:
        return False
    if quiet(datetime.fromtimestamp(current, ZoneInfo(device.timezone)), device.quiet_start, device.quiet_end):
        return False
    child = db.get(Child, call.child_id)
    if not child:
        return False
    prefs = s.Preferences(**child.preferences)
    if quiet(datetime.fromtimestamp(current, ZoneInfo(prefs.timezone)), prefs.quiet_start, prefs.quiet_end):
        return False
    status, _ = effective(db, call, current, instance=False)
    if event == "incoming":
        return status == "ringing" and user.id not in call.declined_users
    return event == "ended" and (status != "ringing" or user.id in call.declined_users)


def queue_call(db, call, event, *, user_id=None):
    """Opaque, short lived call notices use the existing session-bound queue."""
    from .family_calls import eligible_parents

    current = int(now())
    parents = eligible_parents(db, call.family_id)
    if user_id is not None:
        parents = [pid for pid in parents if pid == user_id]
    for device in db.scalars(select(PushDevice).where(PushDevice.user_id.in_(parents), PushDevice.family_calls.is_(True)).limit(100)):
        if not call_delivery_allowed(db, device, call, event, current):
            continue
        insert_ignore(db, PushDelivery, {"id": uid(), "device_id": device.id,
            "dedup_key": f"family_call:{call.id}:{event}:{device.id}", "kind": "family_call_" + event,
            "status": "queued", "created": current}, key="dedup_key")


def dispatch_call(call_id):
    """An incoming call must not wait behind a 145s learning-provider job.

    Four bounded background senders claim the normal durable queue. Expiry is
    checked before every send; failed or ambiguous sends are never retried.
    """
    from concurrent.futures import ThreadPoolExecutor

    from .db import DB

    if not _call_dispatch_slots.acquire(blocking=False):
        # The durable worker remains the bounded fallback; do not create an
        # unbounded thread/HTTP pool under many simultaneous help requests.
        return
    try:
        def run():
            for _ in range(25):
                if not deliver_one(DB, call_id=call_id):
                    break
        with ThreadPoolExecutor(max_workers=4, thread_name_prefix="family-call-push") as pool:
            list(pool.map(lambda _: run(), range(4)))
    finally:
        _call_dispatch_slots.release()
