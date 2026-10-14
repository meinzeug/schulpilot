"""Opt-in, session-bound FCM. Fixed neutral payloads; no public send endpoint."""

import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Literal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import httpx
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from pydantic import Field, model_validator
from sqlalchemy import delete, select, update

from . import schemas as s
from .config import settings
from .db import Activity, Child, Membership, Message, PushDelivery, PushDevice, Session, User, get_db, now, uid
from .security import authenticated, decrypt, digest, encrypt, insert_ignore, rate_limit

router = APIRouter(prefix="/notifications", tags=["Benachrichtigungen"])
log = logging.getLogger("schulpilot.push")


def public_config():
    try:
        raw = json.loads(settings.fcm_public_config or "{}")
        allowed = {
            k: raw[k]
            for k in ("apiKey", "appId", "messagingSenderId", "projectId", "authDomain", "vapidKey", "androidAppId")
            if isinstance(raw.get(k), str)
        }
        valid = all(allowed.get(k) for k in ("apiKey", "appId", "messagingSenderId", "projectId", "androidAppId"))
    except (ValueError, TypeError):
        allowed, valid = {}, False
    ready = bool(
        valid
        and settings.push_approved
        and settings.push_privacy_evidence
        and settings.fcm_service_account_file
        and Path(settings.fcm_service_account_file).is_file()
    )
    return {
        "available": ready,
        "firebase": allowed if ready else {},
        "notice": "Push enthält nur neutrale Hinweise. Inhalte öffnest du nach Anmeldung in SCHULPILOT."
        if ready
        else "Push ist vorbereitet. Firebase-Projekt, Dienstkonto und dokumentierte Datenschutzfreigabe sind noch erforderlich.",
    }


@router.get("/config")
def config():
    # Firebase client identifiers are public, never service account credentials.
    return public_config()


@router.get("/service-worker.js")
def service_worker():
    config = public_config()
    if not config["available"]:
        raise HTTPException(503, config["notice"])
    firebase = {
        k: v
        for k, v in config["firebase"].items()
        if k in ("apiKey", "appId", "messagingSenderId", "projectId", "authDomain")
    }
    # Configuration must be present synchronously when the worker starts;
    # fetching it asynchronously can lose the first background push event.
    script = """self.addEventListener('notificationclick', event => {
  event.stopImmediatePropagation(); event.notification.close();
  event.waitUntil(clients.openWindow('/app'));
});
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-messaging-compat.js');
firebase.initializeApp(CONFIG); firebase.messaging();
""".replace("CONFIG", json.dumps(firebase).replace("<", "\\u003c"))
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

    @model_validator(mode="after")
    def valid_zone(self):
        try:
            ZoneInfo(self.timezone)
        except ZoneInfoNotFoundError:
            raise ValueError("Unbekannte Zeitzone.") from None
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
    if not public_config()["available"]:
        raise HTTPException(503, public_config()["notice"])
    rate_limit(db, "push-register:" + p.user.id, 20, 3600)
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
    device.encrypted_token = encrypt(data.token)
    device.updated = int(now())
    db.add(device)
    db.commit()
    return device_data(device, p.session.id)


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
        return list(db.scalars(select(Child).where(Child.user_id == user.id)))
    if user.role == "parent":
        return list(
            db.scalars(
                select(Child)
                .join(Membership, Membership.family_id == Child.family_id)
                .where(Membership.user_id == user.id)
            )
        )
    return []


def due_kinds(db, device, current):
    """Re-evaluated immediately before send, including current membership."""
    user = db.get(User, device.user_id)
    session = db.get(Session, device.session_id)
    if (
        not user
        or user.disabled
        or not user.verified
        or not session
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
            if not db.scalar(
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
    if not public_config()["available"]:
        return
    for device in db.scalars(select(PushDevice)):
        # A daily bundle per category, rather than a notification per answer.
        for kind in due_kinds(db, device, current):
            day = datetime.fromtimestamp(current, ZoneInfo(device.timezone)).strftime("%Y-%m-%d")
            key = device.id + ":" + kind + ":" + day
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


def send_fcm(token, kind, ttl=60):
    if not public_config()["available"]:
        raise FcmError("NOT_CONFIGURED")
    from google.auth.transport.requests import Request
    from google.oauth2 import service_account

    try:
        credential_file = Path(settings.fcm_service_account_file)
        info = json.loads(credential_file.read_text())
        project = public_config()["firebase"]["projectId"]
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
            "Es gibt Neuigkeiten in SCHULPILOT. Öffne deinen Lernraum."
            if kind != "reminder"
            else "Dein Lernplan ist bereit. Öffne ihn, wenn es für dich passt."
        )
        message = {
            "token": token,
            "notification": {"title": "SCHULPILOT", "body": body},
            "data": {"route": "/app"},
            "android": {
                "priority": "normal",
                "ttl": str(ttl) + "s",
                "collapse_key": "schulpilot",
                "notification": {"tag": "schulpilot", "visibility": "PRIVATE"},
            },
            "webpush": {
                "headers": {"TTL": str(ttl), "Urgency": "normal"},
                "fcm_options": {"link": settings.public_url + "/app"},
            },
        }
        with httpx.Client(timeout=20, follow_redirects=False) as client:
            response = client.post(
                "https://fcm.googleapis.com/v1/projects/" + project + "/messages:send",
                headers={"Authorization": "Bearer " + credentials.token},
                json={"message": message},
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


def deliver_one(DB):
    with DB() as db:
        delivery = db.scalar(
            select(PushDelivery).where(PushDelivery.status == "queued").order_by(PushDelivery.created).limit(1)
        )
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
        if not device or kind not in due_kinds(db, device, int(now())):
            delivery.status = "suppressed"
            db.commit()
            return True
        token = decrypt(device.encrypted_token)
        ttl = min(60, seconds_before_quiet(int(now()), device.timezone, device.quiet_start, device.quiet_end))
        for child in children_for(db, db.get(User, device.user_id)):
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
        send_fcm(token, kind, ttl)
    except FcmError as error:
        code, unregistered = error.code, error.unregistered
    with DB.begin() as db:
        delivery = db.get(PushDelivery, delivery_id)
        if delivery:
            delivery.status = "failed" if code else "accepted"
            delivery.error_code, delivery.sent = code, int(now())
        if unregistered:
            db.execute(delete(PushDevice).where(PushDevice.id == device_id))
    # A timeout is not replayed: it may already have been accepted by FCM.
    return True
