"""Private, consent-driven WebRTC signalling for a child and their own parent.

Only bounded short-lived SDP/ICE envelopes live in API process memory. Database
rows contain call lifecycle metadata; neither media nor call contents are stored.
An API restart invalidates the old signalling instance instead of reconnecting a
camera silently. GET endpoints derive expiry without changing state.
"""
import base64
import hashlib
import hmac
import json
import re
import threading
from collections import OrderedDict
from typing import Literal
from urllib.parse import urlsplit

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from pydantic import Field, model_validator
from sqlalchemy import delete, select, update

from . import schemas as s
from .config import settings
from .db import (
    Child,
    Family,
    FamilyCall,
    LearningUnit,
    Material,
    Membership,
    Session,
    TutorTurn,
    User,
    get_db,
    now,
    uid,
)
from .security import audit, authenticated, child_user, digest, own_child, rate_limit

router = APIRouter(prefix="/family-calls", tags=["Familienanrufe"])
INSTANCE = uid()
RING_SECONDS = 45
LEASE_SECONDS = 90
MAX_SECONDS = 3600
TURN_SECONDS = MAX_SECONDS + 300
ACTIVE = ("ringing", "accepted")


class Start(s.Strict):
    idempotency_key: str = Field(min_length=8, max_length=100, pattern=r"^[A-Za-z0-9_-]+$")
    context_kind: Literal["general", "learning", "homework", "tutor"] = "general"
    context_id: str | None = Field(default=None, pattern=r"^[a-f0-9]{32}$")

    @model_validator(mode="after")
    def context_pair(self):
        if (self.context_kind == "general") != (self.context_id is None):
            raise ValueError("Der Lernbezug muss vollständig sein.")
        return self


class Signal(s.Strict):
    idempotency_key: str = Field(min_length=8, max_length=100, pattern=r"^[A-Za-z0-9_-]+$")
    kind: Literal["offer", "answer", "ice", "renegotiate"]
    payload: dict

    @model_validator(mode="after")
    def validate_envelope(self):
        p = self.payload
        if self.kind in ("offer", "answer"):
            if set(p) - {"sdp", "camera_stream_id", "screen_stream_id"}:
                raise ValueError("Unbekannte Verbindungsfelder.")
            if not isinstance(p.get("sdp"), str) or not p["sdp"].startswith("v=0") or len(p["sdp"].encode()) > 48_000:
                raise ValueError("Ungültige Verbindungsbeschreibung.")
            for key in ("camera_stream_id", "screen_stream_id"):
                value = p.get(key)
                if value is not None and (not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,100}", value)):
                    raise ValueError("Ungültige Medienkennung.")
        elif self.kind == "renegotiate":
            if p:
                raise ValueError("Die Neuverbindung enthält keine zusätzlichen Daten.")
        else:
            if set(p) - {"candidate", "sdpMid", "sdpMLineIndex"}:
                raise ValueError("Unbekannte Verbindungsfelder.")
            if not isinstance(p.get("candidate"), str) or len(p["candidate"].encode()) > 2048:
                raise ValueError("Ungültiger Verbindungskandidat.")
            if p.get("sdpMid") is not None and (not isinstance(p["sdpMid"], str) or len(p["sdpMid"]) > 64):
                raise ValueError("Ungültige Medienkennung.")
            if p.get("sdpMLineIndex") is not None and (type(p["sdpMLineIndex"]) is not int or not 0 <= p["sdpMLineIndex"] <= 32):
                raise ValueError("Ungültige Mediennummer.")
        return self


class SignalMemory:
    """Single API process, strict byte/message limits, 90-second envelopes."""
    def __init__(self):
        self.lock = threading.Lock()
        self.calls = OrderedDict()

    def prune(self, current):
        for cid, box in list(self.calls.items()):
            box["items"] = [x for x in box["items"] if x["at"] > current - LEASE_SECONDS]
            if not box["items"] and box["updated"] < current - LEASE_SECONDS:
                del self.calls[cid]

    def put(self, cid, sender, recipient, data, current):
        with self.lock:
            self.prune(current)
            box = self.calls.get(cid)
            if box is None:
                if len(self.calls) >= 128:
                    raise HTTPException(503, "Der Anrufdienst ist gerade ausgelastet.")
                box = self.calls[cid] = {"items": [], "seq": 0, "updated": current}
            key = digest(sender + ":" + data.idempotency_key)
            canonical = json.dumps({"kind": data.kind, "payload": data.payload}, sort_keys=True, separators=(",", ":"))
            fingerprint = digest(canonical)
            for old in box["items"]:
                if old["key"] == key:
                    if old["fingerprint"] != fingerprint:
                        raise HTTPException(409, "Diese Verbindungskennung wurde bereits anders verwendet.")
                    return old["sequence"]
            size = len(canonical.encode())
            local = sum(x["size"] for x in box["items"])
            total = sum(x["size"] for b in self.calls.values() for x in b["items"])
            if len(box["items"]) >= 256 or local + size > 256_000 or total + size > 4_000_000:
                raise HTTPException(429, "Zu viele Verbindungsdaten. Bitte den Anruf neu starten.")
            box["seq"] += 1
            box["updated"] = current
            box["items"].append({"sequence": box["seq"], "kind": data.kind, "payload": data.payload,
                "recipient": recipient, "key": key, "fingerprint": fingerprint, "at": current, "size": size})
            return box["seq"]

    def read(self, cid, recipient, after, current):
        with self.lock:
            self.prune(current)
            box = self.calls.get(cid)
            if not box:
                return [], after
            items = [{k: x[k] for k in ("sequence", "kind", "payload")} for x in box["items"]
                     if x["recipient"] == recipient and x["sequence"] > after]
            return items, max(after, box["seq"])

    def clear(self, cid):
        with self.lock:
            self.calls.pop(cid, None)


signals = SignalMemory()


def turn_urls():
    if not settings.family_calls_enabled:
        return []
    try:
        raw = json.loads(settings.turn_urls) if settings.turn_urls.strip().startswith("[") else settings.turn_urls.split(",")
        urls = [x.strip() for x in raw if isinstance(x, str) and x.strip()]
        if not 1 <= len(urls) <= 8 or len(settings.turn_secret) < 32:
            return []
        for value in urls:
            # Only the operator's explicit TURN endpoints, no public discovery.
            parsed = urlsplit(value)
            if parsed.scheme not in ("turn", "turns") or not parsed.path or any(x in value for x in ("@", "#", " ", "\n")):
                return []
        return urls
    except (ValueError, TypeError):
        return []


def live_session(db, sid, uid_=None):
    # The same ORM session also holds the principal loaded before a row-lock
    # wait. Reload so a concurrent logout/revocation cannot use cached rights.
    session = db.scalar(select(Session).where(Session.id == sid).execution_options(populate_existing=True)) if sid else None
    if not session or session.revoked or session.expires <= now() or session.seen < now() - 7 * 86400:
        return False
    user = db.scalar(select(User).where(User.id == session.user_id).execution_options(populate_existing=True))
    return bool(user and user.verified and not user.disabled and (uid_ is None or user.id == uid_))


def eligible_parents(db, family_id):
    return list(db.scalars(select(User.id).join(Membership, Membership.user_id == User.id).where(
        Membership.family_id == family_id, Membership.permission.in_(["owner", "manage"]),
        User.role == "parent", User.disabled.is_(False), User.verified.is_(True))))


def effective(db, call, current=None, *, instance=True):
    current = int(now()) if current is None else current
    if call.status not in ACTIVE:
        return call.status, call.reason
    if not settings.family_calls_enabled:
        return "ended", "calls_disabled"
    child = db.scalar(select(Child).where(Child.id == call.child_id).execution_options(populate_existing=True))
    family = db.scalar(select(Family).where(Family.id == call.family_id).execution_options(populate_existing=True))
    if not child or not family or child.family_id != call.family_id or (family.expires and family.expires <= current):
        return "ended", "access_ended"
    if instance and call.instance != INSTANCE:
        return "ended", "server_restarted"
    if not live_session(db, call.caller_session_id, child.user_id):
        return "ended", "session_ended"
    if current >= call.expires:
        return "ended", "duration_limit"
    if current - call.caller_seen >= LEASE_SECONDS:
        return "ended", "connection_interrupted"
    if call.status == "ringing":
        return ("missed", "ring_timeout") if current >= call.ring_expires else ("ringing", None)
    if not live_session(db, call.parent_session_id, call.parent_user_id) or call.parent_user_id not in eligible_parents(db, call.family_id):
        return "ended", "parent_access_ended"
    if current - (call.parent_seen or 0) >= LEASE_SECONDS:
        return "ended", "connection_interrupted"
    return "accepted", None


def authorize(db, p, call, *, participant=False):
    if p.user.role == "child":
        child = db.get(Child, call.child_id)
        allowed = child and child.user_id == p.user.id and call.caller_session_id == p.session.id
    elif p.user.role == "parent":
        allowed = p.user.id in eligible_parents(db, call.family_id)
        if participant:
            allowed = allowed and call.parent_user_id == p.user.id and call.parent_session_id == p.session.id
    else:
        allowed = False
    if not allowed:
        raise HTTPException(404, "Anruf nicht gefunden.")
    if not live_session(db, p.session.id, p.user.id):
        raise HTTPException(401, "Bitte erneut anmelden.")
    return call


def data(db, p, call):
    status, reason = effective(db, call)
    child = db.get(Child, call.child_id)
    user = db.get(User, child.user_id) if child else None
    valid_until = min(call.expires, call.caller_seen + LEASE_SECONDS,
        (call.parent_seen or 0) + LEASE_SECONDS if call.status == "accepted" else call.ring_expires)
    return {"id": call.id, "child_id": call.child_id, "child_name": user.display_name if user else "Kind",
        "status": status, "reason": reason, "created": call.created, "ring_expires": call.ring_expires,
        "expires": call.expires, "valid_until": valid_until, "server_now": int(now()),
        "accepted_at": call.accepted_at, "ended_at": call.ended_at,
        "role": p.user.role, "is_participant": p.session.id in (call.caller_session_id, call.parent_session_id),
        "context_kind": call.context_kind, "context_id": call.context_id}


def fetch(db, p, cid, *, participant=False):
    call = db.get(FamilyCall, cid)
    if not call:
        raise HTTPException(404, "Anruf nicht gefunden.")
    return authorize(db, p, call, participant=participant)


def lock(db, call, *, unit=False):
    # Every operation taking both locks uses Unit -> Child -> Call. No call lock
    # is held while the existing learning paths wait for a unit lock.
    if unit and call.context_kind == "learning" and call.context_id:
        db.scalar(select(LearningUnit).where(LearningUnit.id == call.context_id).with_for_update())
    db.execute(update(Child).where(Child.id == call.child_id).values(grade=Child.grade))
    db.refresh(call, with_for_update=True)


def finish(db, call, status, reason):
    call.status, call.reason, call.ended_at = status, reason, int(now())
    call.active_slot = call.parent_active_slot = None
    signals.clear(call.id)
    from .notifications import queue_call
    queue_call(db, call, "ended")


def ensure_active(db, call):
    status, reason = effective(db, call)
    if status not in ACTIVE:
        if call.status in ACTIVE:
            finish(db, call, status, reason)
            db.commit()
        raise HTTPException(409, "Dieser Anruf ist bereits beendet.")
    return status


@router.get("/config")
def config(p=Depends(authenticated)):
    if p.user.role not in ("child", "parent"):
        raise HTTPException(403, "Familienanrufe sind für Kinder und Eltern verfügbar.")
    available = bool(turn_urls())
    return {"available": available, "notice": "Kamera, Mikrofon und Bildschirm werden erst nach deiner Freigabe geteilt. Es wird nichts aufgezeichnet."
            if available else "Familienanrufe werden auf diesem Server noch eingerichtet.",
        "ring_seconds": RING_SECONDS, "heartbeat_seconds": 15, "lease_seconds": LEASE_SECONDS, "max_duration_seconds": MAX_SECONDS}


@router.get("/active")
def active(p=Depends(authenticated), db=Depends(get_db)):
    if p.user.role == "child":
        query = select(FamilyCall).where(FamilyCall.caller_session_id == p.session.id, FamilyCall.status.in_(ACTIVE))
    elif p.user.role == "parent":
        families = select(Membership.family_id).where(Membership.user_id == p.user.id, Membership.permission.in_(["owner", "manage"]))
        query = select(FamilyCall).where(FamilyCall.family_id.in_(families), FamilyCall.status.in_(ACTIVE))
    else:
        raise HTTPException(403, "Familienanrufe sind für Kinder und Eltern verfügbar.")
    result = []
    for call in db.scalars(query.order_by(FamilyCall.created.desc()).limit(32)):
        status, _ = effective(db, call)
        if status not in ACTIVE or p.user.id in call.declined_users:
            continue
        if status == "accepted" and p.user.role == "parent" and call.parent_session_id != p.session.id:
            continue
        authorize(db, p, call)
        result.append(data(db, p, call))
    return {"calls": result}


@router.post("", status_code=201)
def start(body: Start, background: BackgroundTasks, p=Depends(child_user), db=Depends(get_db)):
    child = own_child(db, p)
    if not turn_urls():
        raise HTTPException(503, "Familienanrufe sind auf diesem Server noch nicht eingerichtet.")
    db.execute(update(Child).where(Child.id == child.id).values(grade=Child.grade))
    db.refresh(child)
    own_child(db, p)
    if not live_session(db, p.session.id, p.user.id):
        raise HTTPException(401, "Bitte erneut anmelden.")
    key = digest(p.session.id + ":" + body.idempotency_key)
    existing = db.scalar(select(FamilyCall).where(FamilyCall.idempotency == key))
    if existing:
        if (existing.context_kind, existing.context_id) != (body.context_kind, body.context_id):
            raise HTTPException(409, "Diese Anrufkennung wurde bereits anders verwendet.")
        return data(db, p, existing)
    previous = db.scalar(select(FamilyCall).where(FamilyCall.active_slot == child.id))
    if previous:
        status, reason = effective(db, previous)
        if status in ACTIVE:
            raise HTTPException(409, "Es läuft bereits ein Anruf. Öffne ihn zuerst.")
        finish(db, previous, status, reason)
    if body.context_id:
        model = {"learning": LearningUnit, "homework": Material, "tutor": TutorTurn}[body.context_kind]
        context = db.get(model, body.context_id)
        if not context or context.child_id != child.id:
            raise HTTPException(404, "Der Lernbezug ist nicht mehr verfügbar.")
    if not eligible_parents(db, child.family_id):
        raise HTTPException(409, "Für diesen Zugang ist gerade kein Elternkontakt verfügbar.")
    rate_limit(db, "family-call-start:" + child.id, 6, 300, commit=False)
    current = int(now())
    call = FamilyCall(family_id=child.family_id, child_id=child.id, caller_session_id=p.session.id,
        active_slot=child.id, idempotency=key, instance=INSTANCE, context_kind=body.context_kind,
        context_id=body.context_id, ring_expires=current + RING_SECONDS, expires=current + MAX_SECONDS,
        caller_seen=current, created=current, declined_users=[])
    db.add(call)
    db.flush()
    from .notifications import queue_call
    queue_call(db, call, "incoming")
    audit(db, p.user.id, "family_call.started", call.id)
    db.commit()
    from .notifications import dispatch_call
    background.add_task(dispatch_call, call.id)
    return data(db, p, call)


@router.get("/{cid}")
def get_call(cid: str, p=Depends(authenticated), db=Depends(get_db)):
    return data(db, p, fetch(db, p, cid))


@router.post("/{cid}/accept")
def accept(cid: str, background: BackgroundTasks, p=Depends(authenticated), db=Depends(get_db)):
    call = fetch(db, p, cid)
    if p.user.role != "parent":
        raise HTTPException(403, "Nur deine Eltern können den Anruf annehmen.")
    # Serialize claims on this parent device before any child/call locks. This
    # also prevents two simultaneous accepts across different children from
    # waiting on each other's call row while one holds the parent session.
    db.scalar(select(Session).where(Session.id == p.session.id).with_for_update())
    lock(db, call, unit=True)
    authorize(db, p, call)
    status = ensure_active(db, call)
    if status == "accepted":
        authorize(db, p, call, participant=True)
        return data(db, p, call)
    if p.user.id in call.declined_users:
        raise HTTPException(409, "Du hast diesen Anruf bereits abgelehnt.")
    occupied = db.scalar(select(FamilyCall).where(FamilyCall.parent_active_slot == p.session.id))
    if occupied and occupied.id != call.id:
        state, reason = effective(db, occupied)
        if state in ACTIVE:
            raise HTTPException(409, "Auf diesem Gerät läuft bereits ein Familienanruf.")
        finish(db, occupied, state, reason)
    current = int(now())
    call.status, call.accepted_at, call.parent_seen = "accepted", current, current
    call.parent_user_id, call.parent_session_id, call.parent_active_slot = p.user.id, p.session.id, p.session.id
    if call.context_kind == "learning" and call.context_id:
        unit = db.get(LearningUnit, call.context_id)
        if unit and unit.child_id == call.child_id and unit.status in ("active", "paused"):
            from .learning import record
            record(db, call.child_id, "explanation", {"via": "family_call", "call_id": call.id}, unit_id=unit.id)
    from .notifications import queue_call
    queue_call(db, call, "ended")
    audit(db, p.user.id, "family_call.accepted", call.id)
    db.commit()
    from .notifications import dispatch_call
    background.add_task(dispatch_call, call.id)
    return data(db, p, call)


@router.post("/{cid}/decline")
def decline(cid: str, background: BackgroundTasks, p=Depends(authenticated), db=Depends(get_db)):
    call = fetch(db, p, cid)
    if p.user.role != "parent":
        raise HTTPException(403, "Nur deine Eltern können den Anruf ablehnen.")
    lock(db, call)
    authorize(db, p, call)
    status, _ = effective(db, call)
    if status != "ringing":
        return data(db, p, call)
    if p.user.id in call.declined_users:
        return data(db, p, call)
    call.declined_users = sorted(set(call.declined_users + [p.user.id]))
    if not set(eligible_parents(db, call.family_id)) - set(call.declined_users):
        finish(db, call, "declined", "parent_declined")
    else:
        from .notifications import queue_call
        queue_call(db, call, "ended", user_id=p.user.id)
    audit(db, p.user.id, "family_call.declined", call.id)
    db.commit()
    from .notifications import dispatch_call
    background.add_task(dispatch_call, call.id)
    return data(db, p, call)


@router.post("/{cid}/end")
def end(cid: str, background: BackgroundTasks, p=Depends(authenticated), db=Depends(get_db)):
    call = fetch(db, p, cid)
    # Ringing may be cancelled by the child, accepted calls by their two peers.
    if p.user.role == "parent":
        authorize(db, p, call, participant=True)
    lock(db, call)
    authorize(db, p, call, participant=p.user.role == "parent")
    if call.status in ACTIVE:
        status, reason = effective(db, call)
        finish(db, call, "ended" if status in ACTIVE else status, "hangup" if status in ACTIVE else reason)
        audit(db, p.user.id, "family_call.ended", call.id)
    db.commit()
    from .notifications import dispatch_call
    background.add_task(dispatch_call, call.id)
    return data(db, p, call)


@router.post("/{cid}/heartbeat")
def heartbeat(cid: str, p=Depends(authenticated), db=Depends(get_db)):
    call = fetch(db, p, cid, participant=True)
    lock(db, call)
    authorize(db, p, call, participant=True)
    ensure_active(db, call)
    if p.user.role == "child":
        call.caller_seen = int(now())
    else:
        call.parent_seen = int(now())
    db.commit()
    return data(db, p, call)


@router.post("/{cid}/ice")
def ice(cid: str, p=Depends(authenticated), db=Depends(get_db)):
    call = fetch(db, p, cid, participant=True)
    if effective(db, call)[0] != "accepted":
        raise HTTPException(409, "Der Anruf ist noch nicht verbunden oder bereits beendet.")
    urls = turn_urls()
    if not urls:
        raise HTTPException(503, "Die sichere Medienverbindung ist noch nicht eingerichtet.")
    rate_limit(db, "family-call-ice:" + p.session.id, 10, 60)
    db.refresh(call)
    authorize(db, p, call, participant=True)
    if effective(db, call)[0] != "accepted":
        raise HTTPException(409, "Dieser Anruf ist bereits beendet.")
    # REST credentials cannot revoke an already established media connection;
    # clients must stop all tracks when the independent 90s authority lease ends.
    expires = min(int(now()) + TURN_SECONDS, call.expires + 300)
    opaque = digest(call.id + ":" + p.session.id)[:24]
    username = f"{expires}:{opaque}"
    credential = base64.b64encode(hmac.new(settings.turn_secret.encode(), username.encode(), hashlib.sha1).digest()).decode()
    return {"ice_servers": [{"urls": urls, "username": username, "credential": credential}], "expires": expires}


@router.post("/{cid}/signals")
def send_signal(cid: str, body: Signal, p=Depends(authenticated), db=Depends(get_db)):
    call = fetch(db, p, cid, participant=True)
    if effective(db, call)[0] != "accepted":
        raise HTTPException(409, "Der Anruf ist nicht verbunden.")
    if (body.kind == "offer" and p.user.role != "child") or (body.kind in ("answer", "renegotiate") and p.user.role != "parent"):
        raise HTTPException(403, "Diese Verbindungsaktion ist hier nicht erlaubt.")
    rate_limit(db, "family-call-signal:" + p.session.id, 100, 10)
    db.refresh(call)
    authorize(db, p, call, participant=True)
    if effective(db, call)[0] != "accepted":
        raise HTTPException(409, "Dieser Anruf ist bereits beendet.")
    recipient = call.parent_session_id if p.user.role == "child" else call.caller_session_id
    sequence = signals.put(call.id, p.session.id, recipient, body, int(now()))
    return {"sequence": sequence, "status": "accepted"}


@router.get("/{cid}/signals")
def read_signals(cid: str, after: int = 0, p=Depends(authenticated), db=Depends(get_db)):
    if after < 0 or after > 2_147_483_647:
        raise HTTPException(422, "Ungültiger Verbindungsstand.")
    call = fetch(db, p, cid, participant=True)
    status, _ = effective(db, call)
    if status != "accepted":
        return {"signals": [], "cursor": after, "status": status}
    items, cursor = signals.read(call.id, p.session.id, after, int(now()))
    return {"signals": items, "cursor": cursor, "status": status}


def maintenance(db, current=None):
    """Worker expiry/retention; never creates a call or reads private contents."""
    current = int(now()) if current is None else current
    for call in db.scalars(select(FamilyCall).where(FamilyCall.status.in_(ACTIVE)).order_by(FamilyCall.id).limit(256).with_for_update(skip_locked=True)):
        # The worker has its own Python process ID; API instance affinity is only
        # checked by API endpoints, not this independent maintenance process.
        status, reason = effective(db, call, current, instance=False)
        if status not in ACTIVE:
            finish(db, call, status, reason)
    db.execute(delete(FamilyCall).where(FamilyCall.created < current - 30 * 86400))


def record_answer_help(db, p, unit):
    from .db import Activity

    call = db.scalar(select(FamilyCall).where(FamilyCall.child_id == unit.child_id,
        FamilyCall.caller_session_id == p.session.id, FamilyCall.status == "accepted"))
    if call and effective(db, call)[0] == "accepted" and not any(
        (row.detail or {}).get("call_id") == call.id
        for row in db.scalars(select(Activity).where(Activity.unit_id == unit.id, Activity.kind == "explanation"))
    ):
        from .learning import record

        record(db, unit.child_id, "explanation", {"via": "family_call", "call_id": call.id}, unit_id=unit.id)
