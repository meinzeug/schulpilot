"""Fixed subject identities, explicit aliases and family-private legacy extras.

No AI output can create a subject. Seed/migration and explicit management are
the only writers. Legacy content labels remain snapshots; references converge.
"""

import hashlib
import json
import time
import unicodedata
import uuid
from pathlib import Path

import sqlalchemy as sa
from fastapi import HTTPException
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.orm import Session as SASession

from .db import Assignment, Child, ChildSubject, LearningUnit, Mastery, Material, SchoolGrade, Subject, SubjectAlias

SEED = Path(__file__).with_name("reference") / "subjects-v1.json"
PRIVATE_MODELS = (Material, Assignment, LearningUnit, SchoolGrade, Mastery)


def normalized(value):
    return " ".join(unicodedata.normalize("NFC", value).casefold().split())


def alias_key(value, family_id=None):
    return hashlib.sha256(((family_id or "global") + ":" + normalized(value)).encode()).hexdigest()


def identity(key, family_id=None):
    return uuid.uuid5(
        uuid.NAMESPACE_URL, "https://schulpilot.dorfspy.de/subjects/v1/" + (family_id or "global") + "/" + key
    ).hex


def tables():
    # Freeze these column shapes for the versioned migration/seed. Do not use
    # a future ORM model's defaults against an earlier schema revision.
    return (
        sa.table(
            "subjects",
            sa.column("id", sa.String),
            sa.column("key", sa.String),
            sa.column("title", sa.String),
            sa.column("owner_family_id", sa.String),
            sa.column("cover_key", sa.String),
            sa.column("active", sa.Boolean),
            sa.column("sort_order", sa.Integer),
            sa.column("created", sa.Integer),
        ),
        sa.table(
            "subject_aliases",
            sa.column("key", sa.String),
            sa.column("subject_id", sa.String),
            sa.column("family_id", sa.String),
            sa.column("normalized", sa.String),
        ),
        sa.table(
            "subject_providers",
            sa.column("provider", sa.String),
            sa.column("external_id", sa.String),
            sa.column("subject_id", sa.String),
            sa.column("data", sa.JSON),
        ),
    )


def insert_ignore(connection, table, values):
    insert = sqlite_insert if connection.dialect.name == "sqlite" else pg_insert
    for start in range(0, len(values), 400):
        connection.execute(insert(table).values(values[start : start + 400]).on_conflict_do_nothing())


def seed_connection(connection):
    seed = json.loads(SEED.read_text())
    subjects, aliases, providers = tables()
    known = dict(
        connection.execute(sa.select(subjects.c.key, subjects.c.id).where(subjects.c.owner_family_id.is_(None))).all()
    )
    insert_ignore(
        connection,
        subjects,
        [
            {
                "id": identity(row["key"]),
                "key": row["key"],
                "title": row["title"],
                "owner_family_id": None,
                "cover_key": row["key"],
                "active": True,
                "sort_order": index,
                "created": int(time.time()),
            }
            for index, row in enumerate(seed["subjects"])
            if row["key"] not in known
        ],
    )
    known.update(
        dict(
            connection.execute(
                sa.select(subjects.c.key, subjects.c.id).where(subjects.c.owner_family_id.is_(None))
            ).all()
        )
    )
    alias_rows, provider_rows = [], []
    for row in seed["subjects"]:
        subject_id = known[row["key"]]
        for label in {row["title"], *row["aliases"]}:
            alias_rows.append(
                {"key": alias_key(label), "subject_id": subject_id, "family_id": None, "normalized": normalized(label)}
            )
        if row.get("provider"):
            provider_rows.append(
                {
                    "provider": row["provider"],
                    "external_id": row["provider_id"],
                    "subject_id": subject_id,
                    "data": {
                        "title": row["title"],
                        "url": row["provider_url"],
                        "source": "subjects",
                        "seed_version": 1,
                    },
                }
            )
    insert_ignore(connection, aliases, alias_rows)
    insert_ignore(connection, providers, provider_rows)
    return {"seed_version": 1, "reference_subjects": len(provider_rows), "general_subjects": len(known)}


def create_private_connection(connection, label, family_id, *, legacy=False):
    subjects, aliases, _ = tables()
    key = "custom-" + hashlib.sha256((family_id + ":" + normalized(label)).encode()).hexdigest()[:24]
    subject_id = connection.scalar(
        sa.select(subjects.c.id).where(subjects.c.key == key, subjects.c.owner_family_id == family_id)
    )
    if subject_id is None:
        if (
            not legacy
            and connection.scalar(
                sa.select(sa.func.count()).select_from(subjects).where(subjects.c.owner_family_id == family_id)
            )
            >= 40
        ):
            raise HTTPException(409, "Bitte ein vorhandenes eigenes Fach wählen.")
        subject_id = identity(key, family_id)
    insert_ignore(
        connection,
        subjects,
        [
            {
                "id": subject_id,
                "key": key,
                "title": label.strip(),
                "owner_family_id": family_id,
                "cover_key": "other",
                "active": True,
                "sort_order": 100,
                "created": int(time.time()),
            }
        ],
    )
    insert_ignore(
        connection,
        aliases,
        [
            {
                "key": alias_key(label, family_id),
                "subject_id": subject_id,
                "family_id": family_id,
                "normalized": normalized(label),
            }
        ],
    )
    return subject_id


def resolve(db, label, family_id=None, *, active_only=False):
    keys = [alias_key(label)] + ([alias_key(label, family_id)] if family_id else [])
    query = (
        sa.select(Subject)
        .join(SubjectAlias, SubjectAlias.subject_id == Subject.id)
        .where(
            SubjectAlias.key.in_(keys),
            sa.or_(Subject.owner_family_id.is_(None), Subject.owner_family_id == family_id),
        )
        .order_by(sa.case((Subject.owner_family_id.is_(None), 0), else_=1))
    )
    if active_only:
        query = query.where(Subject.active.is_(True))
    return db.scalar(query)


def visible(db, family_id=None):
    return list(
        db.scalars(
            sa.select(Subject)
            .where(
                Subject.active.is_(True),
                sa.or_(Subject.owner_family_id.is_(None), Subject.owner_family_id == family_id)
                if family_id
                else Subject.owner_family_id.is_(None),
            )
            .order_by(Subject.sort_order, Subject.title, Subject.id)
        )
    )


def backfill_connection(connection, *, preserve_legacy_extras=False):
    """Repeatable local reference migration; never expose private label values."""
    subjects, aliases, _ = tables()
    children = sa.Table("children", sa.MetaData(), autoload_with=connection)
    existing = {r.key: r.subject_id for r in connection.execute(sa.select(aliases.c.key, aliases.c.subject_id))}
    migrated, private_added = 0, 0

    def find(label, family_id):
        nonlocal private_added
        if not isinstance(label, str) or not label.strip():
            return None
        if alias_key(label) in existing:
            return existing[alias_key(label)]
        key = alias_key(label, family_id)
        if key not in existing:
            if not preserve_legacy_extras:
                return None
            existing[key] = create_private_connection(connection, label, family_id, legacy=True)
            private_added += 1
        return existing[key]

    profile_rows = []
    for row in connection.execute(sa.select(children.c.id, children.c.family_id, children.c.subjects)):
        labels = json.loads(row.subjects) if isinstance(row.subjects, str) else row.subjects
        for label in labels if isinstance(labels, list) else []:
            subject_id = find(label, row.family_id)
            if subject_id:
                profile_rows.append(
                    {
                        "child_id": row.id,
                        "subject_id": subject_id,
                        "active": True,
                        "level_type": None,
                        "level_number": None,
                        "revision": 1,
                    }
                )
    profiles = sa.table(
        "child_subjects",
        sa.column("child_id", sa.String),
        sa.column("subject_id", sa.String),
        sa.column("active", sa.Boolean),
        sa.column("level_type", sa.String),
        sa.column("level_number", sa.Integer),
        sa.column("revision", sa.Integer),
    )
    # Existing explicit activations/learning years always win on a later run.
    insert_ignore(connection, profiles, profile_rows)
    for model in PRIVATE_MODELS:
        table = sa.Table(model.__tablename__, sa.MetaData(), autoload_with=connection)
        for family_id, label in connection.execute(
            sa.select(children.c.family_id, table.c.subject)
            .join(children, children.c.id == table.c.child_id)
            .where(table.c.subject_id.is_(None))
            .distinct()
        ):
            subject_id = find(label, family_id)
            if subject_id:
                ids = sa.select(children.c.id).where(children.c.family_id == family_id)
                result = connection.execute(
                    table.update()
                    .where(table.c.child_id.in_(ids), table.c.subject == label, table.c.subject_id.is_(None))
                    .values(subject_id=subject_id)
                )
                migrated += result.rowcount
    return {"references_migrated": migrated, "family_private_extras_preserved": private_added}


def child_subject_ids(db, child_id):
    queries = [
        sa.select(model.subject_id).where(model.child_id == child_id, model.subject_id.is_not(None))
        for model in PRIVATE_MODELS
    ]
    queries.append(sa.select(ChildSubject.subject_id).where(ChildSubject.child_id == child_id))
    return set(db.scalars(sa.union(*queries)))


def purge_unused_private(db, family_id):
    used = sa.union(
        *(sa.select(model.subject_id).where(model.subject_id.is_not(None)) for model in PRIVATE_MODELS),
        sa.select(ChildSubject.subject_id),
    )
    db.execute(sa.delete(Subject).where(Subject.owner_family_id == family_id, Subject.id.not_in(used)))


def sync_profile(db, child):
    """Only call after an explicit parent profile write, never from AI output."""
    chosen = set()
    for label in child.subjects:
        if not isinstance(label, str) or not normalized(label):
            continue
        row = resolve(db, label, child.family_id)
        if row is None:
            chosen.add(create_private_connection(db.connection(), label, child.family_id))
        else:
            chosen.add(row.id)
    current = {r.subject_id: r for r in db.scalars(sa.select(ChildSubject).where(ChildSubject.child_id == child.id))}
    for subject_id in chosen | current.keys():
        row = current.get(subject_id)
        if row is None:
            db.add(ChildSubject(child_id=child.id, subject_id=subject_id, active=True, revision=1))
        elif row.active != (subject_id in chosen):
            row.active = subject_id in chosen
            row.revision += 1


@sa.event.listens_for(SASession, "before_flush")
def bind_known_subjects(session, *_):
    for row in session.new | session.dirty:
        if (
            isinstance(row, PRIVATE_MODELS)
            and row.subject
            and (row in session.new or sa.inspect(row).attrs.subject.history.has_changes())
        ):
            child = session.get(Child, row.child_id)
            if child:
                subject = resolve(session, row.subject, child.family_id)
                row.subject_id = subject.id if subject else None
