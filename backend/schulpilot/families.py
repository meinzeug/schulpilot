import hashlib
import json
import tempfile
import zipfile
from pathlib import Path

from fastapi import APIRouter, Depends, Header, HTTPException, Request
from fastapi.responses import FileResponse
from sqlalchemy import delete, func, select, update
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
    SchoolDay,
    Session,
    Token,
    TutorTurn,
    UnitCoaching,
    UnitSource,
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
    profile = {"display_name": user.display_name, "grade": child.grade, "subjects": child.subjects,
               "school_type": child.school_type, "region": child.region}
    revision = hashlib.sha256(json.dumps(profile, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
    return {
        "profile_revision": revision,
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
    from .commerce import effective_child_limit
    from .learning import learning_times, summary

    children = list(db.scalars(select(Child).where(Child.family_id == family.id)))
    measured = learning_times(db, children)
    open_assignments = dict(
        db.execute(
            select(Assignment.child_id, func.count())
            .where(Assignment.child_id.in_([c.id for c in children]), Assignment.done.is_(False),
                   Assignment.mandatory.is_(True), Assignment.source_status == "confirmed")
            .group_by(Assignment.child_id)
        ).all()
    )
    return {
        "id": family.id,
        "name": family.name,
        "synthetic": family.synthetic,
        "permission": membership.permission,
        "plan": family.plan,
        "child_limit": effective_child_limit(db, family),
        "expires": family.expires,
        "children": [
            {
                **child_data(db, c),
                "summary": summary(db, c, 1),
                "learning_time": measured[c.id],
                "open_assignments": open_assignments.get(c.id, 0),
            }
            for c in children
        ],
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
    from .commerce import effective_child_limit

    if count >= effective_child_limit(db, family):
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
    from .subject_registry import sync_profile

    sync_profile(db, child)
    audit(db, p.user.id, "child.create", child.id)
    db.commit()
    return child_data(db, child)


@router.put("/children/{child_id}")
def update_child(child_id: str, data: s.ChildUpdate,
                 if_match: str | None = Header(None, max_length=66, pattern=r'^"?[a-f0-9]{64}"?$'),
                 p=Depends(parent), db=Depends(get_db)):
    from .parent_insights import lock_parent

    child = lock_parent(db, p, child_id)
    # All explicit profile writes lock Child before its User. No learning unit
    # is modified or locked by sync_profile; historical subject snapshots stay.
    db.execute(update(User).where(User.id == child.user_id).values(display_name=User.display_name))
    db.get(User, child.user_id, populate_existing=True)
    # The user row can have waited for a concurrent account operation. Recheck
    # the parent session and family membership after that wait, before writing.
    child = lock_parent(db, p, child_id)
    if if_match is not None and if_match.strip('"') != child_data(db, child)["profile_revision"]:
        raise HTTPException(409, "Diese Kinderangaben wurden inzwischen geändert. Vergleiche zuerst den gespeicherten Stand; dein Entwurf bleibt erhalten.")
    if any(len(x) > 80 for x in data.subjects):
        raise HTTPException(422, "Fachname zu lang.")
    db.get(User, child.user_id).display_name = data.display_name
    for key in ("grade", "subjects", "school_type", "region"):
        setattr(child, key, getattr(data, key))
    from .subject_registry import sync_profile

    sync_profile(db, child)
    audit(db, p.user.id, "child.profile_update", child.id)
    db.commit()
    return child_data(db, child)


@router.put("/children/{child_id}/preferences")
def preferences(child_id: str, data: s.Preferences, p=Depends(parent), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=True)
    db.execute(update(Child).where(Child.id == child.id).values(grade=Child.grade))
    child.preferences = data.model_dump(mode="json")
    if not data.push_consent:
        from .db import PushDevice

        db.execute(delete(PushDevice).where(PushDevice.user_id == child.user_id))
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
    password: s.PasswordText = s.Field(min_length=12, max_length=128)
    parent_password: s.PasswordText = s.Field(min_length=1, max_length=128)


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
    from .erasure import flush_journal, request

    request(db, "membership", membership.id)
    db.delete(membership)
    # Revoke sessions as well as checking membership on every request.
    db.execute(update(Session).where(Session.user_id == membership.user_id).values(revoked=True))
    audit(db, p.user.id, "family.member_revoke", membership_id)
    db.commit()
    flush_journal()
    return {"message": "Familienrechte und Sitzungen widerrufen."}


def remove_child(db, child):
    from .erasure import request

    request(db, "child", child.id)
    request(db, "user", child.user_id)
    paths = list(db.scalars(select(Material.path).where(Material.child_id == child.id, Material.path.is_not(None))))
    user = db.get(User, child.user_id)
    db.delete(child)
    db.flush()
    from .subject_registry import purge_unused_private

    purge_unused_private(db, child.family_id)
    if user:
        db.delete(user)
    return paths


def remove_family(db, family):
    from .commerce import erase_family_orders

    erase_family_orders(db, family.id)
    from .erasure import request

    request(db, "family", family.id)
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
    from .erasure import flush_journal

    flush_journal()
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
    from .erasure import flush_journal, request

    request(db, "user", p.user.id)
    db.execute(delete(User).where(User.id == p.user.id))
    audit(db, p.user.id, "account.delete", p.user.id)
    db.commit()
    unlink_uploads(paths)
    flush_journal()
    return {
        "message": "Konto und eigene Familien gelöscht. Backups verfallen spätestens nach 14 Tagen. Gesetzlich erforderliche Zahlungsbelege bleiben ohne Kontozuordnung aufbewahrt."
    }


def export_child(db, child):
    from .catalog_models import CatalogRefresh, LearningTipContext, LearningTipInteraction
    from .db import (
        ChildCostBucket,
        ChildSubject,
        GradeImport,
        GradeSourceSlot,
        LanguageProject,
        LearningEvent,
        LearningMemory,
        NotificationRead,
        SchoolGrade,
        VocabularyAction,
        VocabularyCollection,
        VocabularyImport,
        VocabularyItem,
        VocabularyMembership,
        VocabularyReview,
        VocabularyReviewEvent,
    )

    result = {"child": child_data(db, child), "grade_settings": {"planning_enabled": child.grade_planning_enabled}}
    for model in (LearningMemory, LearningEvent, ChildCostBucket):
        result[model.__tablename__] = [{c.name: getattr(row, c.name) for c in model.__table__.columns}
            for row in db.scalars(select(model).where(model.child_id == child.id))]
    for model in (LearningTipContext, LearningTipInteraction, CatalogRefresh):
        result[model.__tablename__] = [{c.name: getattr(row, c.name) for c in model.__table__.columns}
            for row in db.scalars(select(model).where(model.child_id == child.id))]
    from .db import FamilyCall, ParentLearningReview

    result["parent_review_settings"] = child.parent_review_settings
    # No signalling, IP addresses, media or device credentials are recorded.
    result["family_calls"] = [
        {key: getattr(row, key) for key in ("id", "context_kind", "context_id", "status", "reason", "created", "accepted_at", "ended_at")}
        for row in db.scalars(select(FamilyCall).where(FamilyCall.child_id == child.id))
    ]
    for model in (Material, Assignment, LearningUnit, Activity, Mastery, Message, SchoolDay, TutorTurn, ParentLearningReview):
        rows = list(db.scalars(select(model).where(model.child_id == child.id)))
        result[model.__tablename__] = [{c.name: getattr(row, c.name) for c in model.__table__.columns} for row in rows]
    from .grades import grade_data

    result["school_grades"] = [grade_data(row) for row in db.scalars(select(SchoolGrade).where(SchoolGrade.child_id == child.id))]
    from .db import SchulbuddyTurn

    # Each parent's chat remains private to its author. The child's own chat
    # belongs to this child export; account export adds the requester's rows.
    result["schulbuddy_turns"] = [{c.name: getattr(row, c.name) for c in SchulbuddyTurn.__table__.columns
                                  if c.name != "session_id"}
        for row in db.scalars(select(SchulbuddyTurn).where(SchulbuddyTurn.child_id == child.id,
            SchulbuddyTurn.user_id == child.user_id))]
    for model in (GradeImport, GradeSourceSlot):
        result[model.__tablename__] = [{c.name: getattr(row, c.name) for c in model.__table__.columns}
                                     for row in db.scalars(select(model).where(model.child_id == child.id))]
    from .db import Subject
    from .subject_registry import child_subject_ids

    result["child_subjects"] = [{c.name: getattr(row, c.name) for c in ChildSubject.__table__.columns}
                                for row in db.scalars(select(ChildSubject).where(ChildSubject.child_id == child.id))]
    result["subject_definitions"] = [{c.name: getattr(row, c.name) for c in Subject.__table__.columns}
                                     for row in db.scalars(select(Subject).where(Subject.id.in_(child_subject_ids(db, child.id))))]
    units = [u["id"] for u in result["learning_units"]]
    result["attempts"] = [
        {c.name: getattr(row, c.name) for c in Attempt.__table__.columns}
        for row in db.scalars(select(Attempt).where(Attempt.unit_id.in_(units)))
    ]
    from .db import AttemptAssessment

    result["attempt_assessments"] = [
        {c.name: getattr(row, c.name) for c in AttemptAssessment.__table__.columns}
        for row in db.scalars(select(AttemptAssessment).where(
            AttemptAssessment.attempt_id.in_([row["id"] for row in result["attempts"]])))
    ]
    result["unit_sources"] = [
        {c.name: getattr(row, c.name) for c in UnitSource.__table__.columns}
        for row in db.scalars(select(UnitSource).where(UnitSource.unit_id.in_(units)))
    ]
    result["unit_coaching"] = [
        {c.name: getattr(row, c.name) for c in UnitCoaching.__table__.columns}
        for row in db.scalars(select(UnitCoaching).where(UnitCoaching.unit_id.in_(units)))
    ]
    for model in (VocabularyCollection, VocabularyItem, VocabularyImport, VocabularyReview, VocabularyAction, LanguageProject):
        result[model.__tablename__] = [{c.name: getattr(row, c.name) for c in model.__table__.columns}
            for row in db.scalars(select(model).where(model.child_id == child.id))]
    # A parent's own read receipts are private to that parent. Child receipts
    # belong to the child's export; another parent's reading is not disclosed.
    result["notification_reads"] = [{"event_key": row.event_key, "created": row.created}
        for row in db.scalars(select(NotificationRead).where(
            NotificationRead.child_id == child.id, NotificationRead.user_id == child.user_id))]
    for model, column, ids in ((VocabularyMembership, VocabularyMembership.item_id, [row["id"] for row in result["vocabulary_items"]]),
                              (VocabularyReviewEvent, VocabularyReviewEvent.review_id, [row["id"] for row in result["vocabulary_reviews"]])):
        result[model.__tablename__] = [{c.name: getattr(row, c.name) for c in model.__table__.columns}
                                      for row in db.scalars(select(model).where(column.in_(ids)))]
    return result


@router.get("/children/{child_id}/export")
def export_one_child(child_id: str, include_photos: bool = True, p=Depends(parent), db=Depends(get_db)):
    """Explicit private child export; no other child, account, billing or receipts."""
    child = child_access(db, p, child_id)
    directory = settings.data_dir / "exports"
    directory.mkdir(exist_ok=True, mode=0o700)
    with tempfile.NamedTemporaryFile(prefix="child-", suffix=".zip", dir=directory, delete=False) as temporary:
        output = Path(temporary.name)
    try:
        with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("child.json", json.dumps(export_child(db, child) | {"export_scope": {"include_photos": include_photos}}, ensure_ascii=False, indent=2))
            for material in db.scalars(select(Material).where(Material.child_id == child.id, Material.path.is_not(None))):
                path = settings.data_dir / "uploads" / material.path
                if include_photos and path.is_file():
                    archive.write(path, "materials/" + material.path)
        audit(db, p.user.id, "child.export" if include_photos else "child.export_without_photos", child.id)
        db.commit()
        return FileResponse(output, media_type="application/zip", filename="schulpilot-kinderexport.zip",
            background=BackgroundTask(output.unlink, missing_ok=True))
    except BaseException:
        output.unlink(missing_ok=True)
        raise


@router.get("/families/{family_id}/export")
def export_family(family_id: str, p=Depends(parent), db=Depends(get_db)):
    from .commerce import orders_export, trial_data
    from .db import FamilyTrial, NotificationRead, SchulbuddyTurn

    family, membership = family_access(db, p, family_id)
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
                    "schulbuddy_turns": [{column.name: getattr(row, column.name)
                        for column in SchulbuddyTurn.__table__.columns if column.name != "session_id"}
                        for row in db.scalars(select(SchulbuddyTurn).where(SchulbuddyTurn.user_id == p.user.id,
                            SchulbuddyTurn.child_id.in_([c.id for c in children])))],
                    "orders": orders_export(db, family.id, include_withdrawals=True) if membership.permission == "owner" else [],
                    "trial": trial_data(db.get(FamilyTrial, family.id)),
                    "notification_reads": [{"event_key": row.event_key, "created": row.created}
                        for row in db.scalars(select(NotificationRead).where(
                            NotificationRead.user_id == p.user.id, NotificationRead.child_id.in_([c.id for c in children])))],
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
