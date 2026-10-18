"""Shared subject definitions; account-scoped activations and learning years."""

import hashlib
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import Field, model_validator
from sqlalchemy import func, or_, select

from . import schemas as s
from .db import ChildSubject, Material, Subject, SubjectProvider, get_db
from .security import audit, authenticated, child_access, family_access, parent, rate_limit
from .subject_registry import child_subject_ids, create_private_connection, normalized, resolve, visible
from .vocabulary import lock_child

router = APIRouter(tags=["Fächer"])


def subject_data(row):
    return {
        "id": row.id,
        "key": row.key,
        "title": row.title,
        "cover_key": row.cover_key,
        "active": row.active,
        "family_subject": row.owner_family_id is not None,
    }


def owned_subject(db, child, subject_id):
    row = db.get(Subject, subject_id)
    if not row or row.owner_family_id not in (None, child.family_id):
        raise HTTPException(404, "Fach nicht gefunden.")
    return row


@router.get("/subjects")
def public_subjects(db=Depends(get_db)):
    # Only fixed/general metadata; no family-specific names or statistics.
    return {"items": [subject_data(row) for row in visible(db)], "seed_version": 1}


@router.get("/children/{child_id}/subjects")
def child_subjects(child_id: str, p=Depends(authenticated), db=Depends(get_db)):
    child = child_access(db, p, child_id)
    rows = list(
        db.scalars(
            select(Subject)
            .where(or_(Subject.owner_family_id.is_(None), Subject.owner_family_id == child.family_id))
            .order_by(func.lower(Subject.title), Subject.title, Subject.id)
        )
    )
    if p.user.role == "child":
        own_ids = child_subject_ids(db, child.id)
        rows = [row for row in rows if row.owner_family_id is None or row.id in own_ids]
    counts = {
        sid: {"page_count": count, "photo_count": photos, "review_count": pending}
        for sid, count, photos, pending in db.execute(
            select(Material.subject_id, func.count(), func.count(Material.path), func.sum(sa_case_pending()))
            .where(Material.child_id == child.id)
            .group_by(Material.subject_id)
        )
    }
    settings = {r.subject_id: r for r in db.scalars(select(ChildSubject).where(ChildSubject.child_id == child.id))}
    provider_map = {}
    for mapping in db.scalars(select(SubjectProvider).where(SubjectProvider.subject_id.in_([r.id for r in rows]))):
        provider_map.setdefault(mapping.subject_id, []).append(mapping.provider)
    profile = {r.id for label in child.subjects if (r := resolve(db, label, child.family_id))}
    items = []
    for row in rows:
        own = settings.get(row.id)
        count = counts.get(row.id, {"page_count": 0, "photo_count": 0, "review_count": 0})
        if not row.active and not count["page_count"]:
            continue
        item = {
            **subject_data(row),
            **count,
            "selected": own.active if own else row.id in profile,
            "setting_revision": own.revision if own else 0,
            "level_type": own.level_type if own else None,
            "level_number": own.level_number if own else None,
        }
        item["providers"] = sorted(set(provider_map.get(row.id, [])))
        items.append(item)
    return {
        "child_id": child.id,
        "items": items,
        "unassigned_count": counts.get(None, {}).get("page_count", 0),
        "can_manage": p.user.role == "parent" and family_access(db, p, child.family_id)[1].permission != "view",
    }


def sa_case_pending():
    from sqlalchemy import case

    return case((Material.confirmed.is_(False), 1), else_=0)


class SubjectSettings(s.Strict):
    active: bool
    revision: int = Field(ge=0)
    level_type: Literal["klasse", "lernjahr", "vorschule"] | None = None
    level_number: int | None = Field(default=None, ge=0, le=20)
    level_confirmed: bool = False

    @model_validator(mode="after")
    def valid_level(self):
        if (self.level_type is None) != (self.level_number is None):
            raise ValueError("Bitte Stufenart und Stufe gemeinsam angeben.")
        if self.level_type is not None and not self.level_confirmed:
            raise ValueError("Bitte die Stufe ausdrücklich bestätigen.")
        return self


@router.put("/children/{child_id}/subjects/{subject_id}")
def settings(child_id: str, subject_id: str, data: SubjectSettings, p=Depends(parent), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=True)
    subject = owned_subject(db, child, subject_id)
    if not subject.active:
        raise HTTPException(409, "Dieses Fach steht für neue Einstellungen nicht zur Verfügung.")
    lock_child(db, child)
    row = db.get(ChildSubject, (child.id, subject.id))
    if (row.revision if row else 0) != data.revision:
        raise HTTPException(409, "Die Facheinstellung wurde inzwischen geändert. Bitte neu laden.")
    if row is None:
        row = ChildSubject(child_id=child.id, subject_id=subject.id, revision=0)
        db.add(row)
    row.active, row.level_type, row.level_number = data.active, data.level_type, data.level_number
    row.revision += 1
    audit(db, p.user.id, "subject.settings", child.id + ":" + subject.id)
    db.commit()
    return {
        "subject_id": subject.id,
        "revision": row.revision,
        "active": row.active,
        "level_type": row.level_type,
        "level_number": row.level_number,
    }


class CustomSubject(s.Strict):
    title: str = Field(min_length=1, max_length=80)
    confirmed: Literal[True]

    @model_validator(mode="after")
    def clean(self):
        self.title = " ".join(self.title.split())
        if not self.title or any(ord(c) < 32 for c in self.title):
            raise ValueError("Bitte einen Fachnamen angeben.")
        return self


@router.post("/children/{child_id}/subjects", status_code=201)
def create_subject(child_id: str, data: CustomSubject, p=Depends(parent), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=True)
    lock_child(db, child)
    row = resolve(db, data.title, child.family_id)
    if row is None:
        if db.scalar(select(func.count()).select_from(Subject).where(Subject.owner_family_id == child.family_id)) >= 40:
            raise HTTPException(409, "Die Familie hat bereits viele eigene Fächer. Bitte ein vorhandenes Fach wählen.")
        rate_limit(db, "subject-create:" + p.user.id, 12, 3600, commit=False)
        subject_id = create_private_connection(db.connection(), data.title, child.family_id)
        row = db.get(Subject, subject_id)
    if not db.get(ChildSubject, (child.id, row.id)):
        db.add(ChildSubject(child_id=child.id, subject_id=row.id, active=True, revision=1))
    audit(db, p.user.id, "subject.custom_confirm", row.id)
    db.commit()
    return subject_data(row)


def registry_revision(db, child):
    rows = db.execute(
        select(ChildSubject.subject_id, ChildSubject.revision)
        .where(ChildSubject.child_id == child.id)
        .order_by(ChildSubject.subject_id)
    ).all()
    return hashlib.sha256(repr([*rows, *sorted(normalized(s) for s in child.subjects)]).encode()).hexdigest()
