import secrets

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError

from . import schemas as s
from .config import runtime_settings, settings
from .db import Child, Family, GoogleFlow, Membership, Session, Token, User, get_db, now
from .mail import require_mail, send_link
from .security import audit, authenticated, digest, password_hash, rate_limit, verify_password

router = APIRouter(prefix="/auth", tags=["Accounts"])


def new_token(db, purpose, user_id=None, family_id=None, email=None, permission=None, ttl=3600):
    value = secrets.token_urlsafe(32)
    db.add(
        Token(
            digest=digest(value),
            purpose=purpose,
            user_id=user_id,
            family_id=family_id,
            email=email,
            permission=permission,
            expires=int(now()) + ttl,
        )
    )
    db.flush()
    return value


def consume_token(db, value, purpose):
    token = db.scalar(select(Token).where(Token.digest == digest(value), Token.purpose == purpose))
    if not token or token.used or token.expires < now():
        raise HTTPException(400, "Link ist ungültig oder abgelaufen.")
    result = db.execute(update(Token).where(Token.id == token.id, Token.used.is_(False)).values(used=True))
    if not result.rowcount:
        raise HTTPException(400, "Dieser Link wurde bereits verwendet.")
    return token


def user_data(db, user):
    site = runtime_settings(db)
    result = {
        "id": user.id,
        "role": user.role,
        "display_name": user.display_name,
        "username": user.username,
        "email": user.email,
        "real_data_enabled": bool(site.real_data_approved and site.privacy_evidence),
    }
    from .profile_images import metadata as avatar_metadata

    result.update(avatar_metadata(db, user.id))
    if user.role == "parent":
        result["families"] = [
            {"id": f.id, "name": f.name, "permission": m.permission, "synthetic": f.synthetic}
            for m, f in db.execute(
                select(Membership, Family)
                .join(Family, Family.id == Membership.family_id)
                .where(Membership.user_id == user.id)
            )
        ]
    elif user.role == "child":
        child = db.scalar(select(Child).where(Child.user_id == user.id))
        result["child_id"] = child.id
        family = db.get(Family, child.family_id)
        result["synthetic"] = family.synthetic
    return result


def create_session(db, user, response, request, device):
    # At most ten live devices per account. Older sessions are revoked.
    sessions = list(
        db.scalars(
            select(Session)
            .where(Session.user_id == user.id, Session.revoked.is_(False))
            .order_by(Session.created.desc())
        )
    )
    for old in sessions[9:]:
        old.revoked = True
        from .exam_review import clear_user_drafts

        clear_user_drafts(db, user.id, old.id)
    token = secrets.token_urlsafe(48)
    db.add(
        Session(
            user_id=user.id,
            token_hash=digest(token),
            device=device,
            expires=int(now()) + (86400 if user.role == "admin" else 30 * 86400),
        )
    )
    db.commit()
    response.set_cookie(
        "sp_session",
        token,
        httponly=True,
        secure=settings.environment == "production",
        samesite="strict",
        path="/api",
        max_age=86400 if user.role == "admin" else 30 * 86400,
    )
    result = {"user": user_data(db, user)}
    if request.headers.get("x-client-platform") == "native":
        result["token"] = token
    return result


@router.post("/register", status_code=201)
def register(data: s.Register, request: Request, db=Depends(get_db)):
    require_mail()
    rate_limit(db, "register:" + digest(request.client.host), 5, 3600)
    email = str(data.email).lower()
    from .commerce import registration_notice

    reply = {"message": "Falls diese Adresse registriert werden kann, erhältst du eine Bestätigung per E-Mail.",
             "access_notice": registration_notice(db)}
    if db.scalar(select(User.id).where(User.username == email)):
        # Uniform reply avoids revealing existing registrations.
        return reply
    user = User(
        username=email,
        email=email,
        display_name=data.display_name,
        password_hash=password_hash(data.password),
        role="parent",
        verified=False,
    )
    site = runtime_settings(db)
    family = Family(
        name=data.family_name,
        plan=site.default_plan,
        child_limit=site.default_child_limit,
        call_limit=site.default_call_limit,
        budget_micros=site.default_budget_micros,
    )
    # New public registrations are commercial even while launch flags are off.
    # Only the separately verified trial or a checked payment grants AI access.
    family.commerce_required = True
    family.call_limit = 0
    family.child_limit = 1
    family.plan = "Noch kein Tarif"
    db.add_all([user, family])
    db.flush()
    db.add(Membership(family_id=family.id, user_id=user.id, permission="owner"))
    from .commerce import prepare_trial

    prepare_trial(db, family, user, site)
    token = new_token(db, "verify", user.id, ttl=86400)
    send_link(
        email,
        "SCHULPILOT: Elternkonto bestätigen",
        "Bestätige deine E-Mail-Adresse für deinen Elternzugang.",
        "verify",
        token,
    )
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
    return reply


@router.post("/verify")
def verify(data: s.TokenRequest, db=Depends(get_db)):
    token = consume_token(db, data.token, "verify")
    user = db.get(User, token.user_id)
    user.verified = True
    from .commerce import activate_trials

    activate_trials(db, user)
    db.commit()
    return {"message": "E-Mail bestätigt. Du kannst dich jetzt anmelden."}


@router.post("/resend-verification")
def resend(data: s.EmailRequest, request: Request, db=Depends(get_db)):
    require_mail()
    rate_limit(db, "verify:" + digest(request.client.host), 5, 3600)
    user = db.scalar(select(User).where(User.email == str(data.email).lower(), User.verified.is_(False)))
    if user:
        token = new_token(db, "verify", user.id, ttl=86400)
        send_link(user.email, "SCHULPILOT: E-Mail bestätigen", "Bestätige deinen Elternzugang.", "verify", token)
        db.commit()
    return {"message": "Falls ein unbestätigtes Konto existiert, wurde ein neuer Link versandt."}


@router.post("/login")
def login(data: s.Login, request: Request, response: Response, db=Depends(get_db)):
    rate_limit(db, "login-ip:" + digest(request.client.host), 30, 900)
    rate_limit(db, "login-user:" + digest(data.username.lower()), 10, 900)
    user = db.scalar(select(User).where(User.username == data.username.lower()))
    valid = verify_password(data.password, user.password_hash if user else None)
    if not user or not valid or user.disabled:
        raise HTTPException(401, "Benutzername oder Passwort ist nicht richtig.")
    if not user.verified:
        raise HTTPException(403, "Bitte zuerst die E-Mail-Adresse bestätigen.")
    if user.role == "admin":
        audit(db, user.id, "admin.login", user.id)
    # Successful account switches on a shared browser/device terminate the
    # previous session before any new push registration can be associated.
    header = request.headers.get("authorization", "")
    previous_token = header[7:] if header.startswith("Bearer ") else request.cookies.get("sp_session", "")
    if previous_token:
        previous = db.scalar(select(Session).where(Session.token_hash == digest(previous_token)))
        if previous:
            previous.revoked = True
            from .exam_review import clear_user_drafts

            clear_user_drafts(db, previous.user_id, previous.id)
            from sqlalchemy import delete

            from .db import PushDevice

            db.execute(delete(PushDevice).where(PushDevice.session_id == previous.id))
    return create_session(db, user, response, request, data.device)


@router.get("/me")
def me(p=Depends(authenticated), db=Depends(get_db)):
    return user_data(db, p.user)


@router.post("/logout")
def logout(response: Response, p=Depends(authenticated), db=Depends(get_db)):
    from sqlalchemy import delete

    db.execute(delete(GoogleFlow).where(GoogleFlow.previous_session_id == p.session.id))
    if p.user.role == "child":
        db.execute(update(Child).where(Child.user_id == p.user.id).values(grade=Child.grade))
    db.execute(update(Session).where(Session.id == p.session.id).values(revoked=True))
    from .exam_review import clear_user_drafts

    clear_user_drafts(db, p.user.id, p.session.id)
    if p.user.role == "child":
        from .homework import clear_drafts

        child = db.scalar(select(Child).where(Child.user_id == p.user.id))
        if child:
            clear_drafts(db, child.id)
    db.commit()
    response.delete_cookie("sp_session", path="/api", secure=settings.environment == "production", samesite="strict")
    response.delete_cookie("sp_google", path="/api/auth/google")
    return {"message": "Abgemeldet."}


@router.get("/sessions")
def sessions(p=Depends(authenticated), db=Depends(get_db)):
    return [
        {"id": x.id, "device": x.device, "created": x.created, "seen": x.seen, "current": x.id == p.session.id}
        for x in db.scalars(
            select(Session).where(Session.user_id == p.user.id, Session.revoked.is_(False), Session.expires > now())
        )
    ]


@router.delete("/sessions/{session_id}")
def revoke(session_id: str, p=Depends(authenticated), db=Depends(get_db)):
    result = db.execute(
        update(Session).where(Session.id == session_id, Session.user_id == p.user.id).values(revoked=True)
    )
    if not result.rowcount:
        raise HTTPException(404, "Sitzung nicht gefunden.")
    from .exam_review import clear_user_drafts

    clear_user_drafts(db, p.user.id, session_id)
    db.commit()
    return {"message": "Zugang auf diesem Gerät widerrufen."}


@router.post("/recovery")
def recovery(data: s.EmailRequest, request: Request, db=Depends(get_db)):
    require_mail()
    rate_limit(db, "recovery:" + digest(request.client.host), 5, 3600)
    user = db.scalar(select(User).where(User.email == str(data.email).lower(), User.role == "parent"))
    if user:
        token = new_token(db, "recovery", user.id)
        send_link(
            user.email,
            "SCHULPILOT: Passwort zurücksetzen",
            "Setze dein Elternpasswort über diesen einmaligen Link zurück.",
            "reset",
            token,
        )
        db.commit()
    return {"message": "Falls ein Elternkonto existiert, wurde ein Wiederherstellungslink versandt."}


@router.post("/reset")
def reset(data: s.ResetRequest, db=Depends(get_db)):
    token = consume_token(db, data.token, "recovery")
    user = db.get(User, token.user_id)
    user.password_hash = password_hash(data.password)
    user.verified = True
    db.execute(update(Session).where(Session.user_id == user.id).values(revoked=True))
    from .exam_review import clear_user_drafts

    clear_user_drafts(db, user.id)
    db.execute(update(Token).where(Token.user_id == user.id, Token.purpose == "recovery").values(used=True))
    db.commit()
    return {"message": "Passwort erneuert. Alle bisherigen Sitzungen wurden beendet."}
