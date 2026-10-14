import json
import tempfile
import zipfile
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import FileResponse
from sqlalchemy import delete, select, update
from sqlalchemy.exc import IntegrityError
from starlette.background import BackgroundTask

from . import schemas as s
from .auth import consume_token, new_token
from .config import settings
from .db import (
    Activity,
    Assignment,
    Attempt,
    Child,
    Family,
    LearningUnit,
    Mastery,
    Material,
    Membership,
    Message,
    Session,
    Token,
    Usage,
    UsageBucket,
    User,
    get_db,
    now,
)
from .mail import require_mail, send_link
from .security import (
    audit,
    child_access,
    family_access,
    parent,
    password_hash,
    rate_limit,
    verify_password,
)

router = APIRouter(tags=["Familien"])


def child_data(db, child):
    user = db.get(User, child.user_id)
    return {
        "id": child.id,
        "display_name": user.display_name,
        "username": user.username,
        "grade": child.grade,
        "subjects": child.subjects,
        "school_type": child.school_type,
        "region": child.region,
        "preferences": s.Preferences(**child.preferences).model_dump(mode="json"),
    }


@router.get("/families/{family_id}")
def family_detail(family_id: str, p=Depends(parent), db=Depends(get_db)):
    family, membership = family_access(db, p, family_id)
    from .learning import summary

    children = list(db.scalars(select(Child).where(Child.family_id == family.id)))
    return {
        "id": family.id,
        "name": family.name,
        "synthetic": family.synthetic,
        "permission": membership.permission,
        "plan": family.plan,
        "child_limit": family.child_limit,
        "expires": family.expires,
        "children": [{**child_data(db, c), "summary": summary(db, c, 1)} for c in children],
    }


@router.post("/families/{family_id}/children", status_code=201)
def create_child(family_id: str, data: s.ChildCreate, p=Depends(parent), db=Depends(get_db)):
    family, _ = family_access(db, p, family_id, write=True)
    # Lock the family row so concurrent requests cannot exceed the plan.
    if db.bind.dialect.name == "postgresql":
        db.execute(select(Family).where(Family.id == family.id).with_for_update())
    else:
        db.execute(update(Family).where(Family.id == family.id).values(name=Family.name))
    count = len(list(db.scalars(select(Child.id).where(Child.family_id == family.id))))
    if count >= family.child_limit:
        raise HTTPException(409, "Die enthaltene Kinderanzahl ist erreicht.")
    if any(len(x) > 80 for x in data.subjects):
        raise HTTPException(422, "Fachname zu lang.")
    user = User(
        username=data.username.lower(),
        display_name=data.display_name,
        role="child",
        password_hash=password_hash(data.password),
        verified=True,
    )
    db.add(user)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "Benutzername ist bereits vergeben.") from None
    child = Child(
        family_id=family.id,
        user_id=user.id,
        grade=data.grade,
        subjects=data.subjects,
        school_type=data.school_type,
        region=data.region,
    )
    db.add(child)
    db.flush()
    audit(db, p.user.id, "child.create", child.id)
    db.commit()
    return child_data(db, child)


@router.put("/children/{child_id}")
def update_child(child_id: str, data: s.ChildUpdate, p=Depends(parent), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=True)
    if any(len(x) > 80 for x in data.subjects):
        raise HTTPException(422, "Fachname zu lang.")
    db.get(User, child.user_id).display_name = data.display_name
    for key in ("grade", "subjects", "school_type", "region"):
        setattr(child, key, getattr(data, key))
    db.commit()
    return child_data(db, child)


@router.put("/children/{child_id}/preferences")
def preferences(child_id: str, data: s.Preferences, p=Depends(parent), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=True)
    child.preferences = data.model_dump(mode="json")
    # Persist explicit repetition goals as visible, binding parent assignments.
    marker = "Wiederholungsziel aus den Lernvorgaben."
    previous = list(db.scalars(select(Assignment).where(Assignment.child_id == child.id, Assignment.note == marker)))
    wanted = set()
    for spec in data.repeat_topics:
        subject, topic = (
            (x.strip() for x in spec.split(":", 1))
            if ":" in spec
            else ((data.focus_subjects or ["Allgemein"])[0], spec)
        )
        if not subject or not topic or len(subject) > 80 or len(topic) > 160:
            raise HTTPException(422, "Wiederholungsziel als Fach: Thema angeben.")
        wanted.add((subject, topic))
        if not any(a.subject == subject and a.topic == topic and not a.done for a in previous):
            material = db.scalar(
                select(Material).where(
                    Material.child_id == child.id,
                    Material.subject == subject,
                    Material.topic == topic,
                    Material.confirmed.is_(True),
                )
            )
            db.add(
                Assignment(
                    child_id=child.id,
                    subject=subject,
                    topic=topic,
                    note=marker,
                    kind="parent",
                    mandatory=True,
                    material_id=material.id if material else None,
                )
            )
    for a in previous:
        if (a.subject, a.topic) not in wanted and not a.done:
            db.delete(a)
    audit(db, p.user.id, "child.preferences", child.id)
    db.commit()
    return child.preferences


class ChildPassword(s.Strict):
    password: str = s.Field(min_length=12, max_length=128)
    parent_password: str = s.Field(min_length=1, max_length=128)


@router.put("/children/{child_id}/password")
def child_password(child_id: str, data: ChildPassword, p=Depends(parent), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=True)
    rate_limit(db, "child-password:" + p.user.id, 5, 900)
    if not verify_password(data.parent_password, p.user.password_hash):
        raise HTTPException(403, "Elternpasswort ist nicht richtig.")
    db.get(User, child.user_id).password_hash = password_hash(data.password)
    db.execute(update(Session).where(Session.user_id == child.user_id).values(revoked=True))
    audit(db, p.user.id, "child.password_reset", child.id)
    db.commit()
    return {"message": "Kinderpasswort erneuert und alle Kindersitzungen widerrufen."}


@router.get("/children/{child_id}/sessions")
def child_sessions(child_id: str, p=Depends(parent), db=Depends(get_db)):
    child = child_access(db, p, child_id)
    return [
        {"id": x.id, "device": x.device, "seen": x.seen, "created": x.created}
        for x in db.scalars(
            select(Session).where(Session.user_id == child.user_id, Session.revoked.is_(False), Session.expires > now())
        )
    ]


@router.delete("/children/{child_id}/sessions/{session_id}")
def revoke_child_session(child_id: str, session_id: str, p=Depends(parent), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=True)
    result = db.execute(
        update(Session).where(Session.id == session_id, Session.user_id == child.user_id).values(revoked=True)
    )
    if not result.rowcount:
        raise HTTPException(404, "Sitzung nicht gefunden.")
    audit(db, p.user.id, "child.session_revoke", session_id)
    db.commit()
    return {"message": "Sitzung widerrufen."}


@router.post("/families/{family_id}/invitations", status_code=201)
def invite(family_id: str, data: s.InviteCreate, p=Depends(parent), db=Depends(get_db)):
    family, _ = family_access(db, p, family_id, owner=True)
    require_mail()
    rate_limit(db, "invite:" + p.user.id, 5, 3600)
    if family.synthetic:
        raise HTTPException(403, "Synthetische Testräume versenden keine Einladungen.")
    email = str(data.email).lower()
    token = new_token(db, "invite", family_id=family.id, email=email, permission=data.permission, ttl=2 * 86400)
    send_link(
        email,
        "SCHULPILOT: Einladung zur Familie",
        "Du wurdest als berechtigtes Elternteil eingeladen. Der Link gilt zwei Tage.",
        "invite",
        token,
    )
    audit(db, p.user.id, "family.invite", family.id)
    db.commit()
    return {"message": "Einladung wurde per E-Mail versandt."}


@router.post("/invitations/accept")
def accept_invite(data: s.InviteAccept, request: Request, db=Depends(get_db)):
    rate_limit(db, "accept:" + request.client.host, 10, 900)
    token = consume_token(db, data.token, "invite")
    user = db.scalar(select(User).where(User.email == token.email))
    if user:
        if user.role != "parent" or not verify_password(data.password, user.password_hash) or user.disabled:
            raise HTTPException(403, "Für das bestehende Elternkonto ist das aktuelle Passwort erforderlich.")
    else:
        if not data.display_name:
            raise HTTPException(422, "Anzeigename ist erforderlich.")
        user = User(
            username=token.email,
            email=token.email,
            display_name=data.display_name,
            password_hash=password_hash(data.password),
            role="parent",
            verified=True,
        )
        db.add(user)
        db.flush()
    if db.scalar(select(Membership).where(Membership.family_id == token.family_id, Membership.user_id == user.id)):
        raise HTTPException(409, "Dieses Elternkonto gehört bereits zur Familie.")
    user.verified = True  # Possession of the mail invitation verifies that address.
    db.add(Membership(family_id=token.family_id, user_id=user.id, permission=token.permission))
    audit(db, user.id, "family.invite_accept", token.family_id)
    db.commit()
    return {"message": "Einladung angenommen. Du kannst dich jetzt anmelden."}


@router.get("/families/{family_id}/members")
def members(family_id: str, p=Depends(parent), db=Depends(get_db)):
    family_access(db, p, family_id)
    return [
        {"id": m.id, "display_name": u.display_name, "permission": m.permission, "self": u.id == p.user.id}
        for m, u in db.execute(
            select(Membership, User).join(User, User.id == Membership.user_id).where(Membership.family_id == family_id)
        )
    ]


@router.get("/families/{family_id}/invitations")
def invitations(family_id: str, p=Depends(parent), db=Depends(get_db)):
    family_access(db, p, family_id, owner=True)
    return [
        {"id": t.id, "email": t.email, "permission": t.permission, "expires": t.expires}
        for t in db.scalars(
            select(Token).where(
                Token.family_id == family_id, Token.purpose == "invite", Token.used.is_(False), Token.expires > now()
            )
        )
    ]


@router.delete("/families/{family_id}/invitations/{invitation_id}")
def revoke_invite(family_id: str, invitation_id: str, p=Depends(parent), db=Depends(get_db)):
    family_access(db, p, family_id, owner=True)
    db.execute(
        update(Token)
        .where(Token.id == invitation_id, Token.family_id == family_id, Token.purpose == "invite")
        .values(used=True)
    )
    audit(db, p.user.id, "family.invite_revoke", invitation_id)
    db.commit()
    return {"message": "Einladung widerrufen."}


@router.delete("/families/{family_id}/members/{membership_id}")
def revoke_member(family_id: str, membership_id: str, p=Depends(parent), db=Depends(get_db)):
    family_access(db, p, family_id, owner=True)
    membership = db.scalar(select(Membership).where(Membership.id == membership_id, Membership.family_id == family_id))
    if not membership or membership.permission == "owner":
        raise HTTPException(403, "Familieninhaber kann hier nicht entfernt werden.")
    db.delete(membership)
    # Revoke sessions as well as checking membership on every request.
    db.execute(update(Session).where(Session.user_id == membership.user_id).values(revoked=True))
    audit(db, p.user.id, "family.member_revoke", membership_id)
    db.commit()
    return {"message": "Familienrechte und Sitzungen widerrufen."}


def remove_child(db, child):
    paths = list(db.scalars(select(Material.path).where(Material.child_id == child.id, Material.path.is_not(None))))
    user = db.get(User, child.user_id)
    db.delete(child)
    db.flush()
    if user:
        db.delete(user)
    return paths


def remove_family(db, family):
    paths = []
    for child in list(db.scalars(select(Child).where(Child.family_id == family.id))):
        paths.extend(remove_child(db, child))
    db.execute(delete(UsageBucket).where(UsageBucket.id.like(f"{family.id}:%")))
    db.delete(family)
    return paths


def unlink_uploads(paths):
    for path in paths:
        (settings.data_dir / "uploads" / path).unlink(missing_ok=True)


@router.delete("/children/{child_id}")
def delete_child(child_id: str, data: s.ConfirmPassword, p=Depends(parent), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=True)
    if not verify_password(data.password, p.user.password_hash):
        raise HTTPException(403, "Elternpasswort ist nicht richtig.")
    paths = remove_child(db, child)
    audit(db, p.user.id, "child.delete", child_id)
    db.commit()
    unlink_uploads(paths)
    return {"message": "Kinderkonto, Sitzungen und Lerndaten gelöscht. Backups verfallen spätestens nach 14 Tagen."}


@router.delete("/account")
def delete_account(data: s.ConfirmPassword, p=Depends(parent), db=Depends(get_db)):
    if not verify_password(data.password, p.user.password_hash):
        raise HTTPException(403, "Elternpasswort ist nicht richtig.")
    paths = []
    owned = list(
        db.scalars(
            select(Family)
            .join(Membership, Membership.family_id == Family.id)
            .where(Membership.user_id == p.user.id, Membership.permission == "owner")
        )
    )
    for family in owned:
        paths.extend(remove_family(db, family))
    db.execute(delete(User).where(User.id == p.user.id))
    audit(db, p.user.id, "account.delete", p.user.id)
    db.commit()
    unlink_uploads(paths)
    return {"message": "Konto und eigene Familien gelöscht. Backups verfallen spätestens nach 14 Tagen."}


def export_child(db, child):
    result = {"child": child_data(db, child)}
    for model in (Material, Assignment, LearningUnit, Activity, Mastery, Message):
        rows = list(db.scalars(select(model).where(model.child_id == child.id)))
        result[model.__tablename__] = [{c.name: getattr(row, c.name) for c in model.__table__.columns} for row in rows]
    units = [u["id"] for u in result["learning_units"]]
    result["attempts"] = [
        {c.name: getattr(row, c.name) for c in Attempt.__table__.columns}
        for row in db.scalars(select(Attempt).where(Attempt.unit_id.in_(units)))
    ]
    return result


@router.get("/families/{family_id}/export")
def export_family(family_id: str, p=Depends(parent), db=Depends(get_db)):
    family, _ = family_access(db, p, family_id)
    children = list(db.scalars(select(Child).where(Child.family_id == family.id)))
    directory = settings.data_dir / "exports"
    directory.mkdir(exist_ok=True, mode=0o700)
    with tempfile.NamedTemporaryFile(prefix="family-", suffix=".zip", dir=directory, delete=False) as temporary:
        output = Path(temporary.name)
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(
            "family.json",
            json.dumps(
                {
                    "name": family.name,
                    "account": {
                        "id": p.user.id,
                        "username": p.user.username,
                        "email": p.user.email,
                        "display_name": p.user.display_name,
                        "role": p.user.role,
                    },
                    "children": [export_child(db, c) for c in children],
                    "usage": [
                        {column.name: getattr(record, column.name) for column in Usage.__table__.columns}
                        for record in db.scalars(select(Usage).where(Usage.family_id == family.id))
                    ],
                },
                ensure_ascii=False,
                indent=2,
            ),
        )
        for c in children:
            for m in db.scalars(select(Material).where(Material.child_id == c.id, Material.path.is_not(None))):
                path = settings.data_dir / "uploads" / m.path
                if path.is_file():
                    archive.write(path, "materials/" + m.path)
    audit(db, p.user.id, "family.export", family.id)
    db.commit()
    return FileResponse(
        output,
        media_type="application/zip",
        filename="schulpilot-export.zip",
        background=BackgroundTask(output.unlink, missing_ok=True),
    )
