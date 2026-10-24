"""Explicit metadata administration, with bound previews and family-safe erasure.

Admins never obtain a private material, photo, grade, answer, or chat projection.
Membership permissions and administrator accounts are not editable here.
"""

import hashlib
import json
import re
import unicodedata
from typing import Literal

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from pydantic import Field, field_validator
from sqlalchemy import delete, func, or_, select, update
from sqlalchemy.exc import IntegrityError

from . import schemas as s
from .admin_user_models import AdminUserOperation, AdminUserVersion
from .db import (
    Attempt,
    Child,
    Family,
    LearningUnit,
    Material,
    Membership,
    PushDevice,
    Session,
    Token,
    User,
    get_db,
    now,
    uid,
)
from .security import admin, audit, rate_limit

router = APIRouter(prefix="/admin/users", tags=["Benutzerverwaltung"])
ID = r"^[a-f0-9]{32}$"
REVISION = r"^[a-f0-9]{64}$"
KEY = re.compile(r"[A-Za-z0-9_-]{16,80}")
DAY = 86400
CONFIRMATION = "KONTO LÖSCHEN"


def digest(value):
    return hashlib.sha256(
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()


class Revision(s.Strict):
    revision: str = Field(pattern=REVISION)


class MetadataUpdate(Revision):
    display_name: str = Field(min_length=1, max_length=80)
    username: str = Field(min_length=3, max_length=254)

    @field_validator("display_name", "username")
    @classmethod
    def readable(cls, value):
        value = value.strip()
        if not value or any(unicodedata.category(c).startswith("C") for c in value):
            raise ValueError("Bitte lesbare Angaben ohne Steuerzeichen verwenden.")
        return value


class StatusUpdate(Revision):
    disabled: bool = Field(strict=True)


class SessionUpdate(Revision):
    session_ids: list[str] | None = Field(default=None, max_length=100)

    @field_validator("session_ids")
    @classmethod
    def identifiers(cls, value):
        if value is not None and (
            not value or len(value) != len(set(value)) or any(not re.fullmatch(ID, item) for item in value)
        ):
            raise ValueError("Bitte eindeutige Sitzungseinträge wählen.")
        return value


class DeletePreview(Revision):
    scope: Literal["account_only", "account_and_sole_families"] = "account_only"


class DeleteConfirmation(Revision):
    preview_id: str = Field(pattern=ID)
    preview_digest: str = Field(pattern=REVISION)
    confirmation: Literal["KONTO LÖSCHEN"]


def checked_admin(db, p, account, *, lock=False):
    # Re-read after locks; the original Depends result can predate a revocation.
    user = db.get(User, p.user.id, populate_existing=True)
    session_query = select(Session).where(Session.id == p.session.id)
    if lock:
        session_query = session_query.with_for_update()
    session = db.scalar(session_query.execution_options(populate_existing=True))
    if (
        not user
        or not user.verified
        or user.disabled
        or not session
        or session.user_id != user.id
        or session.revoked
        or session.expires <= now()
        or session.seen < now() - 7 * DAY
    ):
        raise HTTPException(401, "Bitte erneut anmelden.")
    if user.role != "admin":
        raise HTTPException(403, "Nur für Administratoren verfügbar.")
    if account != user.id:
        raise HTTPException(409, "Das angemeldete Konto hat sich geändert. Bitte neu laden.")
    return user


def expected_admin(x_schulpilot_account: str | None = Header(None), p=Depends(admin), db=Depends(get_db)):
    checked_admin(db, p, x_schulpilot_account)
    return p


def target_user(db, identifier):
    if not re.fullmatch(ID, identifier):
        raise HTTPException(404, "Benutzerkonto nicht gefunden.")
    user = db.get(User, identifier, populate_existing=True)
    if not user or user.role not in ("parent", "child"):
        raise HTTPException(404, "Eltern- oder Kinderkonto nicht gefunden.")
    return user


def child_of(db, user):
    return db.scalar(select(Child).where(Child.user_id == user.id).execution_options(populate_existing=True))


def family_ids(db, user):
    if user.role == "child":
        child = child_of(db, user)
        return [child.family_id] if child else []
    return list(
        db.scalars(select(Membership.family_id).where(Membership.user_id == user.id).order_by(Membership.family_id))
    )


def snapshot(db, user):
    child = child_of(db, user)
    memberships = list(
        db.execute(
            select(Membership.id, Membership.family_id, Membership.permission)
            .where(Membership.user_id == user.id)
            .order_by(Membership.id)
        )
    )
    version = db.get(AdminUserVersion, user.id, populate_existing=True)
    return {
        "admin_revision": version.revision if version else 0,
        "id": user.id,
        "role": user.role,
        "username": user.username,
        "display_name": user.display_name,
        "email": user.email,
        "disabled": user.disabled,
        "verified": user.verified,
        "password_digest": hashlib.sha256(user.password_hash.encode()).hexdigest(),
        "memberships": [list(row) for row in memberships],
        "child": {k: getattr(child, k) for k in ("id", "family_id", "grade", "school_type", "region")}
        if child
        else None,
        "sessions": [
            list(row)
            for row in db.execute(
                select(Session.id, Session.revoked, Session.expires)
                .where(Session.user_id == user.id)
                .order_by(Session.id)
            )
        ],
    }


def revision(db, user):
    return digest(snapshot(db, user))


def metadata(db, user):
    return {
        k: getattr(user, k)
        for k in ("id", "role", "username", "display_name", "email", "verified", "disabled", "created")
    } | {"revision": revision(db, user)}


def family_projection(db, user):
    result = []
    for identifier in family_ids(db, user):
        family = db.get(Family, identifier, populate_existing=True)
        if not family:
            continue
        member = (
            db.scalar(select(Membership).where(Membership.user_id == user.id, Membership.family_id == identifier))
            if user.role == "parent"
            else None
        )
        parents = [
            {
                "user_id": u.id,
                "display_name": u.display_name,
                "username": u.username,
                "permission": m.permission,
                "disabled": u.disabled,
            }
            for m, u in db.execute(
                select(Membership, User)
                .join(User, User.id == Membership.user_id)
                .where(Membership.family_id == identifier, User.role == "parent")
                .order_by(Membership.id)
            )
        ]
        children = [
            {
                "id": c.id,
                "user_id": u.id,
                "display_name": u.display_name,
                "username": u.username,
                "disabled": u.disabled,
            }
            for c, u in db.execute(
                select(Child, User)
                .join(User, User.id == Child.user_id)
                .where(Child.family_id == identifier)
                .order_by(Child.id)
            )
        ]
        result.append(
            {
                "id": identifier,
                "name": family.name,
                "permission": member.permission if member else None,
                "parent_count": len(parents),
                "parents": parents,
                "children": children,
                "synthetic": family.synthetic,
            }
        )
    return result


def deletion_shape(db, user, scope):
    blockers, deleted_families, preserved = [], [], []
    children = []
    if user.role == "child":
        child = child_of(db, user)
        if not child:
            blockers.append("Dieses Kinderkonto hat keine eindeutige Kinderzuordnung. Zuerst den Datenbestand klären.")
        else:
            children = [child]
            preserved = [child.family_id]
    else:
        for identifier in family_ids(db, user):
            rows = list(
                db.execute(
                    select(Membership, User)
                    .join(User, User.id == Membership.user_id)
                    .where(Membership.family_id == identifier)
                    .order_by(Membership.id)
                )
            )
            own = next((m for m, u in rows if u.id == user.id), None)
            other = [(m, u) for m, u in rows if u.id != user.id]
            if other:
                preserved.append(identifier)
                if any(u.role != "parent" for _, u in other):
                    blockers.append(f"Familie {identifier}: unerwartete Mitgliedschaft zuerst klären.")
                if own and own.permission == "owner" and not any(m.permission == "owner" for m, _ in other):
                    blockers.append(
                        f"Familie {identifier}: Dieses Konto ist der letzte Familieninhaber. Eine geteilte Familie wird nicht ohne Inhaber zurückgelassen; Inhaberschaft zuerst klären."
                    )
            elif scope != "account_and_sole_families":
                preserved.append(identifier)
                blockers.append(
                    f"Familie {identifier}: Dieses Konto ist das einzige Elternmitglied. Für die gemeinsame Löschung ausdrücklich Konto und allein betreute Familien wählen."
                )
            else:
                deleted_families.append(identifier)
                children.extend(db.scalars(select(Child).where(Child.family_id == identifier).order_by(Child.id)))
    child_ids = sorted(c.id for c in children)
    user_ids = sorted({user.id, *(c.user_id for c in children)})
    materials = sorted(db.scalars(select(Material.id).where(Material.child_id.in_(child_ids)))) if child_ids else []
    units = sorted(db.scalars(select(LearningUnit.id).where(LearningUnit.child_id.in_(child_ids)))) if child_ids else []
    attempts = sorted(db.scalars(select(Attempt.id).where(Attempt.unit_id.in_(units)))) if units else []
    impact = {
        "user_ids": user_ids,
        "family_ids": sorted(deleted_families),
        "child_ids": child_ids,
        "preserved_family_ids": sorted(preserved),
        "counts": {
            "users": len(user_ids),
            "families": len(deleted_families),
            "children": len(child_ids),
            "materials": len(materials),
            "units": len(units),
            "attempts": len(attempts),
        },
    }
    # Stable IDs only, no contents. Detect newly created data even if totals match.
    binding = {
        "impact": impact,
        "materials": [
            list(row)
            for row in db.execute(
                select(Material.id, Material.revision).where(Material.id.in_(materials)).order_by(Material.id)
            )
        ]
        if materials
        else [],
        "units": units,
        "attempts": attempts,
        "memberships": [
            list(row)
            for row in db.execute(
                select(Membership.id, Membership.family_id, Membership.user_id, Membership.permission)
                .where(Membership.family_id.in_(family_ids(db, user)))
                .order_by(Membership.id)
            )
        ],
    }
    return impact, blockers, digest(binding)


def detail(db, user):
    info = metadata(db, user)
    _, blockers, _ = deletion_shape(db, user, "account_and_sole_families")
    child = child_of(db, user)
    return {
        "user": info,
        "revision": info["revision"],
        "families": family_projection(db, user),
        "child": {k: getattr(child, k) for k in ("id", "family_id", "grade", "school_type", "region")}
        if child
        else None,
        "sessions": [
            {k: getattr(row, k) for k in ("id", "device", "created", "seen", "expires", "revoked")}
            for row in db.scalars(
                select(Session)
                .where(Session.user_id == user.id)
                .order_by(Session.created.desc(), Session.id)
                .limit(100)
            )
        ],
        "editable_fields": ["display_name", "username"],
        "delete_blockers": blockers,
        "allowed_actions": {
            "edit_metadata": True,
            "disable": not user.disabled,
            "enable": user.disabled,
            "end_sessions": True,
            "delete": not blockers,
        },
    }


@router.get("")
def list_users(
    role: Literal["all", "parent", "child"] = "all",
    state: Literal["all", "active", "disabled"] = "all",
    q: str = Query(default="", max_length=80),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=25, ge=1, le=100),
    p=Depends(expected_admin),
    db=Depends(get_db),
):
    conditions = [User.role.in_(["parent", "child"])]
    if role != "all":
        conditions.append(User.role == role)
    if state != "all":
        conditions.append(User.disabled.is_(state == "disabled"))
    query = q.strip()
    if query:
        conditions.append(
            or_(
                *(
                    column.icontains(query, autoescape=True)
                    for column in (User.id, User.username, User.display_name, User.email)
                )
            )
        )
    total = db.scalar(select(func.count()).select_from(User).where(*conditions))
    pages = max(1, (total + page_size - 1) // page_size)
    current_page = min(page, pages)
    users = list(
        db.scalars(
            select(User)
            .where(*conditions)
            .order_by(User.created.desc(), User.id)
            .offset((current_page - 1) * page_size)
            .limit(page_size)
        )
    )
    items = []
    for user in users:
        info = metadata(db, user)
        ids = family_ids(db, user)
        info.update(
            family_count=len(ids),
            child_count=db.scalar(select(func.count()).select_from(Child).where(Child.family_id.in_(ids)))
            if user.role == "parent"
            else None,
        )
        items.append(info)
    audit(db, p.user.id, "admin.users_read", "users")
    db.commit()
    return {
        "items": items,
        "pagination": {"page": current_page, "pages": pages, "page_size": page_size, "total": total},
        "filters": {"role": role, "state": state, "q": query},
    }


@router.get("/{user_id}")
def get_user(user_id: str, p=Depends(expected_admin), db=Depends(get_db)):
    result = detail(db, target_user(db, user_id))
    audit(db, p.user.id, "admin.user_read", user_id)
    db.commit()
    return result


def lock_target(db, user_id, *, family_delete=False):
    user = target_user(db, user_id)
    families = family_ids(db, user) if family_delete and user.role == "parent" else []
    token_ids = []
    token_users = [user.id]
    if family_delete:
        if families:
            token_users.extend(db.scalars(select(Child.user_id).where(Child.family_id.in_(families))))
        token_condition = or_(Token.user_id.in_(token_users), Token.family_id.in_(families))
        # Invitations/recovery consume Token before obtaining their parent/FK
        # lock. Match that order so a DELETE cascade never waits on a token
        # whose acceptance is itself waiting for this family or user.
        token_ids = list(db.scalars(select(Token.id).where(token_condition).order_by(Token.id).with_for_update()))
    if families:
        if db.bind.dialect.name == "postgresql":
            # Full row locks conflict with FK KEY SHARE from a new membership
            # or child. A late invitation cannot silently turn a sole family
            # into a shared family between the final preview check and DELETE.
            list(db.scalars(select(Family.id).where(Family.id.in_(families)).order_by(Family.id).with_for_update()))
        else:
            for identifier in families:
                db.execute(update(Family).where(Family.id == identifier).values(name=Family.name))
    child = child_of(db, user)
    child_ids = (
        list(db.scalars(select(Child.id).where(Child.family_id.in_(families)).order_by(Child.id)))
        if families
        else ([child.id] if child else [])
    )
    unit_ids = []
    if family_delete and child_ids:
        # Existing learning requests lock Unit before Child. Cascades must use
        # that same order, globally sorted across every affected child.
        unit_ids = list(
            db.scalars(
                select(LearningUnit.id)
                .where(LearningUnit.child_id.in_(child_ids))
                .order_by(LearningUnit.id)
                .with_for_update()
            )
        )
    if child_ids:
        if family_delete and db.bind.dialect.name == "postgresql":
            list(db.scalars(select(Child.id).where(Child.id.in_(child_ids)).order_by(Child.id).with_for_update()))
        else:
            for identifier in child_ids:
                db.execute(update(Child).where(Child.id == identifier).values(grade=Child.grade))
    statement = select(User).where(User.id == user_id).with_for_update()
    if db.bind.dialect.name == "sqlite":
        db.execute(update(User).where(User.id == user_id).values(disabled=User.disabled))
    db.scalar(statement.execution_options(populate_existing=True))
    user = target_user(db, user_id)
    if family_delete:
        # A unit committed while we were waiting for Child must not be deleted
        # without its preceding Unit lock. No retry or partial deletion.
        current_units = (
            list(
                db.scalars(
                    select(LearningUnit.id).where(LearningUnit.child_id.in_(child_ids)).order_by(LearningUnit.id)
                )
            )
            if child_ids
            else []
        )
        current_tokens = list(db.scalars(select(Token.id).where(token_condition).order_by(Token.id)))
        if (
            current_units != unit_ids
            or current_tokens != token_ids
            or (user.role == "parent" and family_ids(db, user) != families)
        ):
            raise HTTPException(409, "Betroffene Familien oder Lernrunden wurden geändert. Bitte erneut prüfen.")
    return user


def previous(db, p, user_id, action, key, request_digest):
    row = db.scalar(
        select(AdminUserOperation).where(
            AdminUserOperation.actor_id == p.user.id, AdminUserOperation.request_key == key
        )
    )
    if not row:
        return None
    if (
        row.session_id != p.session.id
        or row.target_id != user_id
        or row.action != action
        or row.request_digest != request_digest
        or row.expires <= now()
    ):
        raise HTTPException(409, "Dieser Aktionsschlüssel gehört zu einem anderen oder abgelaufenen Vorgang.")
    return row


def start(db, p, user_id, action, key, data, *, family_delete=False):
    if not key or not KEY.fullmatch(key):
        raise HTTPException(428, "Ein eindeutiger Aktionsschlüssel mit 16 bis 80 Zeichen wird benötigt.")
    request_digest = digest({"action": action, "target": user_id, "data": data.model_dump()})
    actor_id = p.user.id
    # Serialize even a completed DELETE retry before looking up its missing target.
    db.rollback()
    db.execute(update(User).where(User.id == actor_id).values(disabled=User.disabled))
    checked_admin(db, p, actor_id, lock=True)
    row = previous(db, p, user_id, action, key, request_digest)
    if row:
        return None, row, request_digest
    user = lock_target(db, user_id, family_delete=family_delete)
    checked_admin(db, p, actor_id, lock=True)
    if revision(db, user) != data.revision:
        raise HTTPException(
            409, "Dieses Konto wurde inzwischen geändert. Bitte den aktuellen Stand laden; der Entwurf bleibt erhalten."
        )
    rate_limit(db, "admin-user-write:" + p.user.id, 60, 3600, commit=False)
    return user, None, request_digest


def advance_revision(db, user):
    row = db.get(AdminUserVersion, user.id)
    if row:
        row.revision += 1
    else:
        db.add(AdminUserVersion(user_id=user.id, revision=1))
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "Benutzername wurde inzwischen vergeben. Bitte neu laden.") from None


def receipt(db, p, user_id, action, key, request_digest, result, *, expires=None):
    row = AdminUserOperation(
        actor_id=p.user.id,
        session_id=p.session.id,
        target_id=user_id,
        action=action,
        request_key=key,
        request_digest=request_digest,
        result=result,
        expires=expires or int(now()) + 30 * DAY,
    )
    db.add(row)
    audit(db, p.user.id, "admin.user_" + action, user_id)
    return row


def finish(db, result):
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            409, "Benutzername oder Aktionsschlüssel wurde inzwischen vergeben. Bitte neu laden."
        ) from None
    return result


@router.put("/{user_id}/metadata")
def update_metadata(
    user_id: str,
    data: MetadataUpdate,
    idempotency_key: str | None = Header(None, max_length=80),
    p=Depends(expected_admin),
    db=Depends(get_db),
):
    user, old, request_digest = start(db, p, user_id, "metadata", idempotency_key, data)
    if old:
        return old.result
    username = data.username.lower()
    if not 3 <= len(username) <= 254:
        raise HTTPException(422, "Der Benutzername muss nach Bereinigung 3 bis 254 Zeichen lang sein.")
    if (user.role == "child" and not re.fullmatch(r"[a-z0-9._-]{5,50}", username)) or any(
        c.isspace() for c in username
    ):
        raise HTTPException(
            422,
            "Kinderbenutzernamen benötigen 5 bis 50 Buchstaben, Ziffern, Punkte, Unterstriche oder Bindestriche; Benutzernamen enthalten keine Leerzeichen.",
        )
    if db.scalar(select(User.id).where(func.lower(User.username) == username, User.id != user.id)):
        raise HTTPException(409, "Dieser Benutzername ist bereits vergeben.")
    user.display_name, user.username = data.display_name, username
    advance_revision(db, user)
    result = {
        "message": "Benutzerangaben gespeichert.",
        "user_id": user.id,
        "revision": revision(db, user),
        "deleted": False,
    }
    receipt(db, p, user.id, "metadata", idempotency_key, request_digest, result)
    return finish(db, result)


def revoke_sessions(db, user, session_ids=None):
    conditions = [Session.user_id == user.id]
    if session_ids is not None:
        existing = set(db.scalars(select(Session.id).where(Session.user_id == user.id, Session.id.in_(session_ids))))
        if existing != set(session_ids):
            raise HTTPException(409, "Die Sitzungsauswahl passt nicht mehr zu diesem Konto.")
        conditions.append(Session.id.in_(session_ids))
    identifiers = list(db.scalars(select(Session.id).where(*conditions)))
    count = db.execute(update(Session).where(*conditions, Session.revoked.is_(False)).values(revoked=True)).rowcount
    db.execute(delete(PushDevice).where(PushDevice.session_id.in_(identifiers)))
    from .exam_review import clear_user_drafts

    for identifier in identifiers:
        clear_user_drafts(db, user.id, identifier)
    if user.role == "child":
        from .homework import clear_drafts

        child = child_of(db, user)
        if child:
            clear_drafts(db, child.id)
    return count


@router.post("/{user_id}/status")
def update_status(
    user_id: str,
    data: StatusUpdate,
    idempotency_key: str | None = Header(None, max_length=80),
    p=Depends(expected_admin),
    db=Depends(get_db),
):
    user, old, request_digest = start(db, p, user_id, "status", idempotency_key, data)
    if old:
        return old.result
    revoked = revoke_sessions(db, user) if data.disabled else 0
    user.disabled = data.disabled
    advance_revision(db, user)
    result = {
        "message": "Konto gesperrt und Sitzungen widerrufen."
        if data.disabled
        else "Konto entsperrt; eine neue Anmeldung ist nötig.",
        "user_id": user.id,
        "revision": revision(db, user),
        "deleted": False,
        "revoked_sessions": revoked,
    }
    receipt(db, p, user.id, "status", idempotency_key, request_digest, result)
    return finish(db, result)


@router.post("/{user_id}/sessions/revoke")
def end_sessions(
    user_id: str,
    data: SessionUpdate,
    idempotency_key: str | None = Header(None, max_length=80),
    p=Depends(expected_admin),
    db=Depends(get_db),
):
    user, old, request_digest = start(db, p, user_id, "sessions", idempotency_key, data)
    if old:
        return old.result
    count = revoke_sessions(db, user, data.session_ids)
    advance_revision(db, user)
    result = {
        "message": "Ausgewählte Sitzungen widerrufen.",
        "user_id": user.id,
        "revision": revision(db, user),
        "deleted": False,
        "revoked_sessions": count,
    }
    receipt(db, p, user.id, "sessions", idempotency_key, request_digest, result)
    return finish(db, result)


@router.post("/{user_id}/delete-preview")
def preview_delete(
    user_id: str,
    data: DeletePreview,
    idempotency_key: str | None = Header(None, max_length=80),
    p=Depends(expected_admin),
    db=Depends(get_db),
):
    user, old, request_digest = start(db, p, user_id, "delete_preview", idempotency_key, data, family_delete=True)
    if old:
        return old.result
    impact, blockers, binding = deletion_shape(db, user, data.scope)
    identifier, expires = uid(), int(now()) + 600
    result = {
        "preview_id": identifier,
        "preview_digest": digest({"revision": data.revision, "scope": data.scope, "binding": binding}),
        "revision": data.revision,
        "expires": expires,
        "scope": data.scope,
        "confirmation": CONFIRMATION,
        "impact": impact,
        "can_delete": not blockers,
        "blockers": blockers,
        "warnings": [
            "Nur die ausdrücklich genannten Konten und allein betreuten Familien werden gelöscht. Geteilte Familien bleiben erhalten.",
            "Lerndaten und Fotos der genannten Kinder werden entfernt. Gesetzlich erforderliche Zahlungsbelege bleiben ohne Kontozuordnung; Backups verfallen spätestens nach 14 Tagen.",
        ],
    }
    row = receipt(db, p, user.id, "delete_preview", idempotency_key, request_digest, result, expires=expires)
    row.id = identifier
    return finish(db, result)


@router.post("/{user_id}/delete")
def confirm_delete(
    user_id: str,
    data: DeleteConfirmation,
    idempotency_key: str | None = Header(None, max_length=80),
    p=Depends(expected_admin),
    db=Depends(get_db),
):
    user, old, request_digest = start(db, p, user_id, "delete", idempotency_key, data, family_delete=True)
    if old:
        return old.result
    preview = db.get(AdminUserOperation, data.preview_id, populate_existing=True)
    if (
        not preview
        or preview.action != "delete_preview"
        or preview.actor_id != p.user.id
        or preview.session_id != p.session.id
        or preview.target_id != user_id
        or preview.expires <= now()
        or preview.result.get("preview_digest") != data.preview_digest
        or preview.result.get("revision") != data.revision
    ):
        raise HTTPException(
            409, "Diese Löschvorschau ist abgelaufen oder gehört zu einem anderen Konto oder Gerät. Bitte neu prüfen."
        )
    scope = preview.result["scope"]
    impact, blockers, binding = deletion_shape(db, user, scope)
    if blockers or digest({"revision": data.revision, "scope": scope, "binding": binding}) != data.preview_digest:
        raise HTTPException(
            409, "Betroffene Familien, Kinder oder Daten wurden geändert. Bitte eine neue Löschvorschau prüfen."
        )
    from .erasure import flush_journal
    from .erasure import request as erase
    from .families import remove_child, remove_family, unlink_uploads
    from .profile_images import deletion_paths

    paths = []
    if user.role == "child":
        paths.extend(remove_child(db, child_of(db, user)))
    else:
        for identifier in impact["family_ids"]:
            paths.extend(remove_family(db, db.get(Family, identifier)))
        # Explicit membership journal protects a shared family on restore too.
        for member in db.scalars(select(Membership).where(Membership.user_id == user_id)):
            erase(db, "membership", member.id)
        erase(db, "user", user_id)
        paths.extend(deletion_paths(db, user_id))
        db.execute(delete(User).where(User.id == user_id))
    result = {
        "message": "Die bestätigten Konten und Daten wurden gelöscht; geteilte Familien bleiben erhalten.",
        "user_id": user_id,
        "deleted": True,
        "revision": None,
        "impact": impact,
    }
    # Minimal IDs/counts only; remove older previews for this deleted target.
    db.execute(delete(AdminUserOperation).where(AdminUserOperation.target_id.in_(impact["user_ids"])))
    receipt(db, p, user_id, "delete", idempotency_key, request_digest, result)
    finish(db, result)
    unlink_uploads(paths)
    flush_journal()
    return result


def purge_expired(db):
    """Called by maintenance; previews ten minutes, receipts at most 30 days."""
    return db.execute(delete(AdminUserOperation).where(AdminUserOperation.expires <= now())).rowcount
