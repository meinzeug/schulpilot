"""Optional parent OIDC, through our API. Firebase is not an identity provider.

No Google access/refresh tokens are persisted. Browser binding, state, nonce,
server PKCE and an additional native-client proof protect each one-use flow.
"""

import base64
import hashlib
import hmac
import json
import re
import secrets
from pathlib import Path
from typing import Annotated, Literal
from urllib.parse import urlencode

import httpx
from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi.responses import RedirectResponse
from google.auth.transport.requests import Request as GoogleRequest
from google.oauth2 import id_token
from pydantic import EmailStr, Field, StringConstraints, TypeAdapter
from sqlalchemy import delete, select, update
from sqlalchemy.exc import IntegrityError

from . import auth
from . import schemas as s
from .config import runtime_settings, settings
from .db import (
    Family,
    GoogleFlow,
    GoogleIdentity,
    Membership,
    PushDevice,
    Session,
    StoreConfiguration,
    User,
    get_db,
    now,
)
from .security import audit, authenticated, decrypt, digest, encrypt, parent, password_hash, rate_limit, verify_password

router = APIRouter(prefix="/auth/google", tags=["Eltern-Anmeldung"])
COOKIE = "sp_google"
COOKIE_PATH = "/api/auth/google"
TOKEN = r"^[A-Za-z0-9_-]{32,128}$"
FAILURES = {
    "cancelled": "Die Google-Anmeldung wurde abgebrochen.",
    "unavailable": "Google ist gerade nicht erreichbar. Bitte versuche es erneut oder nutze dein Passwort.",
    "invalid": "Die Google-Anmeldung konnte nicht sicher bestätigt werden. Bitte starte erneut.",
    "conflict": "Diese E-Mail gehört zu einem vorhandenen Zugang. Melde dich mit deinem Passwort an und verknüpfe Google in den Einstellungen.",
    "link": "Google konnte nicht verknüpft werden. Verwende dieselbe E-Mail wie in deinem Elternkonto und melde dich gegebenenfalls neu an.",
}


def validate_client(raw, public_url):
    """Only Google's web-client JSON and this installation's fixed callback."""
    try:
        value = json.loads(raw)["web"]
        if (
            not re.fullmatch(r"[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com", value["client_id"])
            or not isinstance(value["client_secret"], str)
            or not 12 <= len(value["client_secret"]) <= 1024
            or value.get("auth_uri") != "https://accounts.google.com/o/oauth2/auth"
            or value.get("token_uri") != "https://oauth2.googleapis.com/token"
            or public_url + "/api/auth/google/callback" not in value["redirect_uris"]
        ):
            raise ValueError
        return value
    except (ValueError, KeyError, TypeError):
        raise ValueError("Google-Webclient oder Rücksprungadresse ist nicht gültig.") from None


def client_config(db):
    site = runtime_settings(db)
    if not site.google_login_enabled:
        raise HTTPException(
            503, "Google-Anmeldung ist derzeit nicht verfügbar. Nutze deinen Benutzernamen und dein Passwort."
        )
    try:
        raw = site.google_oauth_client_json or Path(site.google_oauth_client_file).read_text()
        return validate_client(raw, site.public_url)
    except (OSError, ValueError, TypeError):
        raise HTTPException(503, "Google-Anmeldung ist noch nicht vollständig eingerichtet.") from None


@router.get("/status")
def status(db=Depends(get_db)):
    try:
        client_config(db)
        available = True
    except HTTPException:
        available = False
    return {"available": available, "parents_only": True}


def challenge(value):
    return base64.urlsafe_b64encode(hashlib.sha256(value.encode()).digest()).decode().rstrip("=")


def previous_session(db, request):
    header = request.headers.get("authorization", "")
    value = header[7:] if header.startswith("Bearer ") else request.cookies.get("sp_session", "")
    return db.scalar(
        select(Session).where(Session.token_hash == digest(value), Session.revoked.is_(False), Session.expires > now())
    )


class Prepare(s.Strict):
    intent: Literal["login", "link"] = "login"
    client_challenge: str | None = Field(default=None, pattern=r"^[A-Za-z0-9_-]{43}$")
    password: Annotated[str, StringConstraints(strip_whitespace=False)] = Field(default="", max_length=128)


@router.post("/prepare")
def prepare(data: Prepare, request: Request, db=Depends(get_db)):
    client_config(db)
    rate_limit(db, "google-prepare:" + digest(request.client.host), 20, 900)
    native = request.headers.get("x-client-platform") == "native"
    if native != bool(data.client_challenge):
        raise HTTPException(422, "Die Gerätesicherung fehlt oder ist nicht passend.")
    previous = previous_session(db, request)
    if previous and db.get(User, previous.user_id).role != "parent":
        raise HTTPException(403, "Google ist ausschließlich für Elternzugänge verfügbar. Melde dich zuerst ab.")
    if data.intent == "link":
        p = parent(authenticated(request, db))
        rate_limit(db, "google-link:" + p.user.id, 5, 900)
        if not verify_password(data.password, p.user.password_hash):
            raise HTTPException(403, "Bitte das bisherige Elternpasswort bestätigen.")
        if db.scalar(select(GoogleIdentity.subject).where(GoogleIdentity.user_id == p.user.id)):
            raise HTTPException(409, "Dein Elternkonto ist bereits mit Google verknüpft.")
    secret = secrets.token_urlsafe(48)
    flow = GoogleFlow(
        request_digest=digest(secret),
        platform="native" if native else "web",
        intent=data.intent,
        previous_session_id=previous.id if previous else None,
        client_challenge=data.client_challenge,
        phase="prepared",
        expires=int(now()) + 600,
    )
    db.add(flow)
    db.commit()
    return {"flow_id": flow.id, "request": secret, "expires_in": 600}


class Start(s.Strict):
    request: str = Field(pattern=TOKEN)


@router.post("/start")
def start(data: Start, request: Request, response: Response, db=Depends(get_db)):
    config = client_config(db)
    rate_limit(db, "google-start:" + digest(request.client.host), 30, 900)
    flow = db.scalar(
        select(GoogleFlow).where(GoogleFlow.request_digest == digest(data.request), GoogleFlow.expires > now())
    )
    if not flow or flow.phase != "prepared":
        raise HTTPException(400, FAILURES["invalid"])
    state, nonce, verifier, browser = (secrets.token_urlsafe(48) for _ in range(4))
    changed = db.execute(
        update(GoogleFlow)
        .where(GoogleFlow.id == flow.id, GoogleFlow.phase == "prepared")
        .values(
            phase="authorizing",
            state_digest=digest(state),
            nonce_digest=digest(nonce),
            browser_digest=digest(browser),
            encrypted_verifier=encrypt(verifier),
        )
    )
    if not changed.rowcount:
        raise HTTPException(400, FAILURES["invalid"])
    db.commit()
    response.set_cookie(
        COOKIE,
        browser,
        httponly=True,
        secure=settings.environment == "production",
        samesite="lax",
        path=COOKIE_PATH,
        max_age=600,
    )
    params = {
        "client_id": config["client_id"],
        "redirect_uri": settings.public_url + "/api/auth/google/callback",
        "response_type": "code",
        "scope": "openid email",
        "state": state,
        "nonce": nonce,
        "code_challenge": challenge(verifier),
        "code_challenge_method": "S256",
        "prompt": "select_account",
        "access_type": "online",
    }
    return {"authorization_url": "https://accounts.google.com/o/oauth2/v2/auth?" + urlencode(params)}


def exchange_code(config, code, verifier):
    """Fixed endpoints, bounded timeouts, no redirect and no response logging."""
    with httpx.Client(timeout=20, follow_redirects=False) as client:
        result = client.post(
            "https://oauth2.googleapis.com/token",
            data={
                "grant_type": "authorization_code",
                "code": code,
                "client_id": config["client_id"],
                "client_secret": config["client_secret"],
                "redirect_uri": settings.public_url + "/api/auth/google/callback",
                "code_verifier": verifier,
            },
        )
    if result.status_code != 200:
        raise ValueError("Google exchange rejected")
    jwt = result.json().get("id_token", "")
    if not isinstance(jwt, str) or len(jwt) > 16000:
        raise ValueError("Invalid identity")

    class BoundedRequest(GoogleRequest):
        def __call__(self, *args, **kwargs):
            kwargs["timeout"] = 10
            return super().__call__(*args, **kwargs)

    return id_token.verify_oauth2_token(jwt, BoundedRequest(), audience=config["client_id"])


@router.get("/callback")
def callback(request: Request, db=Depends(get_db)):
    config = client_config(db)
    state = request.query_params.get("state", "")
    browser = request.cookies.get(COOKIE, "")
    flow = db.scalar(select(GoogleFlow).where(GoogleFlow.state_digest == digest(state), GoogleFlow.expires > now()))
    if (
        not flow
        or not browser
        or not flow.browser_digest
        or flow.phase != "authorizing"
        or not hmac.compare_digest(flow.browser_digest, digest(browser))
    ):
        return RedirectResponse(settings.public_url + "/auth/google/complete#error=invalid", status_code=303)
    claimed = db.execute(
        update(GoogleFlow).where(GoogleFlow.id == flow.id, GoogleFlow.phase == "authorizing").values(phase="exchanging")
    )
    if not claimed.rowcount:
        return RedirectResponse(settings.public_url + "/auth/google/complete#error=invalid", status_code=303)
    verifier, nonce_digest = decrypt(flow.encrypted_verifier), flow.nonce_digest
    flow.encrypted_verifier = None
    db.commit()  # A callback can never cause a second Google exchange.
    failure = "invalid"
    if request.query_params.get("error"):
        failure = "cancelled"
    else:
        try:
            code = request.query_params.get("code", "")
            if not code or len(code) > 4096:
                raise ValueError("Invalid code")
            claims = exchange_code(config, code, verifier)
            email = str(TypeAdapter(EmailStr).validate_python(claims.get("email", ""))).lower()
            if (
                claims.get("iss") not in ("https://accounts.google.com", "accounts.google.com")
                or claims.get("aud") != config["client_id"]
                or claims.get("azp", config["client_id"]) != config["client_id"]
                or claims.get("email_verified") is not True
                or not isinstance(claims.get("sub"), str)
                or not 1 <= len(claims["sub"]) <= 255
                or not isinstance(claims.get("nonce"), str)
                or not hmac.compare_digest(digest(claims["nonce"]), nonce_digest)
            ):
                raise ValueError("Invalid claims")
            flow.subject, flow.email, flow.phase = claims["sub"], email, "verified"
            # For a third-party address Google can confirm an old ownership
            # check, without being authoritative for its current mailbox.
            flow.email_authoritative = bool(email.endswith(("@gmail.com", "@googlemail.com")) or claims.get("hd"))
            failure = None
        except (httpx.HTTPError, OSError):
            failure = "unavailable"
        except Exception:
            # Never expose a Google token, response, SQL parameter or traceback.
            failure = "invalid"
    if failure:
        flow.phase, flow.failure = "failed", failure
    ticket = secrets.token_urlsafe(48) if flow.platform == "native" else None
    flow.ticket_digest = digest(ticket) if ticket else None
    db.commit()
    fragment = urlencode({"flow": flow.id, **({"ticket": ticket} if ticket else {})})
    return RedirectResponse(settings.public_url + "/auth/google/complete#" + fragment, status_code=303)


class Result(s.Strict):
    flow_id: str = Field(pattern=r"^[a-f0-9]{32}$")
    client_verifier: str | None = Field(default=None, min_length=43, max_length=128, pattern=r"^[A-Za-z0-9_-]+$")
    ticket: str | None = Field(default=None, pattern=TOKEN)
    registration: s.Register | None = None


def revoke_previous(db, flow):
    if flow.previous_session_id:
        db.execute(update(Session).where(Session.id == flow.previous_session_id).values(revoked=True))
        db.execute(delete(PushDevice).where(PushDevice.session_id == flow.previous_session_id))


def finish(db, flow):
    result = db.execute(
        update(GoogleFlow)
        .where(GoogleFlow.id == flow.id, GoogleFlow.phase == "verified")
        .values(phase="consumed", email=None, subject=None, browser_digest=None, nonce_digest=None, ticket_digest=None)
    )
    if not result.rowcount:
        raise HTTPException(400, FAILURES["invalid"])


@router.post("/result")
def result(data: Result, request: Request, response: Response, db=Depends(get_db)):
    client_config(db)
    rate_limit(db, "google-result:" + digest(request.client.host), 60, 60)
    flow = db.get(GoogleFlow, data.flow_id)
    if not flow or flow.expires <= now() or flow.phase == "consumed":
        raise HTTPException(400, "Die Google-Anmeldung ist abgelaufen oder bereits abgeschlossen. Bitte starte erneut.")
    if flow.platform == "web" and request.headers.get("x-client-platform") == "native":
        raise HTTPException(403, FAILURES["invalid"])
    if flow.platform == "native":
        valid = bool(
            data.client_verifier and hmac.compare_digest(challenge(data.client_verifier), flow.client_challenge)
        )
        if not valid:
            # Browser callback can only offer return to the app, never a session.
            if (
                request.cookies.get(COOKIE)
                and flow.browser_digest
                and hmac.compare_digest(digest(request.cookies[COOKIE]), flow.browser_digest)
            ):
                return {"status": "return_to_app", "flow_id": flow.id}
            raise HTTPException(403, FAILURES["invalid"])
        if request.headers.get("x-client-platform") != "native":
            raise HTTPException(403, FAILURES["invalid"])
        if flow.phase in ("verified", "failed"):
            # Proof alone is insufficient: an attacker could start a flow and
            # send its browser URL to somebody else. Only the callback recipient
            # receives this additional ticket, which never goes into HTTP logs.
            if not data.ticket:
                return {"status": "awaiting_return"}
            if not flow.ticket_digest or not hmac.compare_digest(digest(data.ticket), flow.ticket_digest):
                raise HTTPException(403, FAILURES["invalid"])
    elif not (
        flow.browser_digest
        and request.cookies.get(COOKIE)
        and hmac.compare_digest(digest(request.cookies[COOKIE]), flow.browser_digest)
    ):
        raise HTTPException(403, FAILURES["invalid"])
    if flow.phase == "failed":
        raise HTTPException(400, FAILURES.get(flow.failure, FAILURES["invalid"]))
    if flow.phase != "verified":
        return {"status": "pending"}
    subject, email = flow.subject, flow.email
    identity = db.get(GoogleIdentity, subject)
    needs_verification = False
    if flow.intent == "link":
        previous = db.get(Session, flow.previous_session_id) if flow.previous_session_id else None
        user = db.get(User, previous.user_id) if previous else None
        if (
            not previous
            or previous.revoked
            or previous.expires <= now()
            or now() - previous.seen > 7 * 86400
            or not user
            or user.role != "parent"
            or user.disabled
            or not user.verified
            or user.email != email
            or identity
            or db.scalar(select(GoogleIdentity.subject).where(GoogleIdentity.user_id == user.id))
        ):
            raise HTTPException(409, FAILURES["link"])
        finish(db, flow)
        db.add(GoogleIdentity(subject=subject, user_id=user.id))
        audit(db, user.id, "account.google_linked", user.id)
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(409, FAILURES["link"]) from None
        response.delete_cookie(COOKIE, path=COOKIE_PATH)
        return {"status": "linked"}
    if identity:
        user = db.get(User, identity.user_id)
        if not user or user.role != "parent" or not user.verified or user.disabled:
            raise HTTPException(403, "Dieser Elternzugang ist nicht freigeschaltet.")
    else:
        if db.scalar(select(User.id).where((User.email == email) | (User.username == email))):
            raise HTTPException(409, FAILURES["conflict"])
        if not data.registration:
            return {"status": "registration_required", "email": email}
        if str(data.registration.email).lower() != email:
            raise HTTPException(422, "Bitte die von Google bestätigte E-Mail-Adresse verwenden.")
        rate_limit(db, "google-register:" + digest(request.client.host), 5, 3600)
        needs_verification = not flow.email_authoritative
        if needs_verification:
            auth.require_mail()
        site = runtime_settings(db)
        user = User(
            username=email,
            email=email,
            display_name=data.registration.display_name,
            password_hash=password_hash(data.registration.password),
            role="parent",
            verified=not needs_verification,
        )
        family = Family(
            name=data.registration.family_name,
            plan=site.default_plan,
            child_limit=site.default_child_limit,
            call_limit=site.default_call_limit,
            budget_micros=site.default_budget_micros,
        )
        shop = db.get(StoreConfiguration, 1)
        if shop and shop.ever_enabled:
            family.commerce_required, family.call_limit, family.child_limit, family.plan = True, 0, 1, "Noch kein Tarif"
        db.add_all([user, family])
        try:
            db.flush()
            db.add(Membership(family_id=family.id, user_id=user.id, permission="owner"))
            db.add(GoogleIdentity(subject=subject, user_id=user.id))
            db.flush()
        except IntegrityError:
            db.rollback()
            raise HTTPException(409, FAILURES["conflict"]) from None
    finish(db, flow)
    if needs_verification:
        token = auth.new_token(db, "verify", user.id, ttl=86400)
        auth.send_link(
            email,
            "SCHULPILOT: Elternkonto bestätigen",
            "Bestätige deine E-Mail-Adresse für deinen Elternzugang.",
            "verify",
            token,
        )
        db.commit()
        response.delete_cookie(COOKIE, path=COOKIE_PATH)
        return {"status": "verification_required"}
    revoke_previous(db, flow)
    audit(db, user.id, "account.google_login", user.id)
    response.delete_cookie(COOKIE, path=COOKIE_PATH)
    return {
        "status": "authenticated",
        **auth.create_session(
            db, user, response, request, "Android · Google" if flow.platform == "native" else "Browser · Google"
        ),
    }


@router.get("/identity")
def identity(p=Depends(parent), db=Depends(get_db)):
    return {
        "linked": bool(db.scalar(select(GoogleIdentity.subject).where(GoogleIdentity.user_id == p.user.id))),
        **status(db),
    }


@router.delete("/identity")
def unlink(data: s.ConfirmPassword, p=Depends(parent), db=Depends(get_db)):
    rate_limit(db, "google-unlink:" + p.user.id, 5, 900)
    if not verify_password(data.password, p.user.password_hash):
        raise HTTPException(403, "Bitte das bisherige Elternpasswort bestätigen.")
    db.execute(delete(GoogleIdentity).where(GoogleIdentity.user_id == p.user.id))
    db.execute(
        delete(GoogleFlow).where(
            GoogleFlow.previous_session_id.in_(select(Session.id).where(Session.user_id == p.user.id))
        )
    )
    audit(db, p.user.id, "account.google_unlinked", p.user.id)
    db.commit()
    return {"message": "Google wurde getrennt. Dein Elternpasswort bleibt gültig."}
