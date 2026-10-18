"""Local source-bound tips, processed in bounded batches by the existing worker.

Source commits enqueue work, not model calls. GETs never enqueue. Claim the local
queue in a separate short transaction. Per resource: Unit before Child, context,
checkpoint. Never wait for a child while holding a cascading queue row lock.
"""

import logging

from sqlalchemy import event, inspect, select, text, update
from sqlalchemy.orm import Session as SASession

from .catalog_import import fingerprint, upsert
from .catalog_models import CatalogRefresh, LearningTipContext
from .catalog_search import MATCHER_VERSION, current_snapshot, level_for, match_sections
from .db import DB, Assignment, Child, ChildSubject, LearningUnit, Material, TutorTurn, UnitSource, now, uid
from .subject_registry import resolve

MODELS = {"material": Material, "unit": LearningUnit, "assignment": Assignment, "tutor": TutorTurn}
FIELDS = {
    Material: ("revision", "subject", "subject_id", "topic", "content", "confirmed", "status"),
    LearningUnit: ("subject", "subject_id", "topic", "explanation", "material_id", "assignment_id"),
    Assignment: ("revision", "subject", "subject_id", "topic", "note", "material_id"),
    TutorTurn: ("status", "reply", "source_revisions"),
    Child: ("grade",),
    ChildSubject: ("level_type", "level_number"),
}
log = logging.getLogger("schulpilot.catalog")


def enqueue(db, snapshot, *, child_id=None, kind=None, resource_id=None):
    key = fingerprint([snapshot, MATCHER_VERSION, child_id, kind, resource_id])
    upsert(
        db,
        CatalogRefresh,
        [
            {
                "id": key,
                "snapshot_id": snapshot,
                "child_id": child_id,
                "resource_kind": kind,
                "resource_id": resource_id,
                "annotation": None,
                "lease": None,
                "status": "queued",
                "phase": 0,
                "cursor": "",
                "processed": 0,
                "error": None,
                "updated": int(now()),
            }
        ],
        ["id"],
    )


@event.listens_for(SASession, "before_flush")
def changed_sources(db, *_):
    pending = db.info.setdefault("catalog_changed", set())
    for row in list(db.new) + list(db.dirty):
        fields = FIELDS.get(type(row))
        if fields and (row in db.new or any(inspect(row).attrs[f].history.has_changes() for f in fields)):
            pending.add(row)


@event.listens_for(SASession, "after_flush_postexec")
def enqueue_changed_sources(db, *_):
    rows = db.info.pop("catalog_changed", set())
    if not rows:
        return
    snapshot = current_snapshot(db)
    if not snapshot:
        return
    work = set()
    for row in rows:
        if row in db.deleted:
            continue
        if isinstance(row, (Child, ChildSubject)):
            work.add((row.id if isinstance(row, Child) else row.child_id, None, None))
        else:
            kind = next(k for k, model in MODELS.items() if isinstance(row, model))
            work.add((row.child_id, kind, row.id))
    for child_id, kind, resource_id in sorted(work, key=lambda r: (r[0], r[1] or "", r[2] or "")):
        enqueue(db, snapshot, child_id=child_id, kind=kind, resource_id=resource_id)


def context_source(db, kind, resource):
    """All source checks and fingerprint inputs; no solution keys in projection."""
    child = db.get(Child, resource.child_id)
    if not child:
        return None
    subject_id, title, content, revisions = None, "", "", []
    confirmed = True
    if kind == "material":
        subject_id, title, content = resource.subject_id, resource.topic, resource.content
        revisions = [{"id": resource.id, "revision": resource.revision, "confirmed": resource.confirmed}]
        confirmed = resource.status in ("review", "confirmed") and bool(resource.content.strip())
    elif kind == "assignment":
        subject_id, title, content = resource.subject_id, resource.topic, resource.note
        revisions = [{"id": resource.id, "revision": resource.revision}]
    else:
        if kind == "unit":
            subject_id, title = resource.subject_id, resource.topic
            refs = list(db.scalars(select(UnitSource).where(UnitSource.unit_id == resource.id)))
            snapshots = [{"id": r.material_id, "revision": r.revision} for r in refs]
            if not snapshots and resource.material_id:
                material = db.get(Material, resource.material_id)
                snapshots = [{"id": material.id, "revision": material.revision}] if material else []
            if not snapshots and resource.assignment_id:
                assignment = db.get(Assignment, resource.assignment_id)
                if assignment:
                    content = assignment.note
                    revisions.append({"id": assignment.id, "revision": assignment.revision})
            if not snapshots and not revisions:
                confirmed = False
        else:
            if resource.status != "ready":
                confirmed = False
            snapshots = resource.source_revisions
            title = resource.question[:300]
        texts = []
        for ref in snapshots:
            material = db.get(Material, ref.get("id") or ref.get("material_id"))
            if (
                not material
                or material.child_id != child.id
                or not material.confirmed
                or material.revision != ref.get("revision")
            ):
                confirmed = False
                continue
            subject_id = subject_id or material.subject_id
            texts.append(material.content)
            revisions.append({"id": material.id, "revision": material.revision})
        content = content or "\n\n".join(texts)
        if kind == "tutor" and not revisions:
            confirmed = False
    subject = (
        resolve(db, resource.subject, child.family_id) if not subject_id and hasattr(resource, "subject") else None
    )
    subject_id = subject_id or (subject.id if subject else None)
    source_key = fingerprint([kind, resource.id, subject_id, title, content, revisions, confirmed])
    level = level_for(db, child, subject_id)
    return {
        "child": child,
        "subject_id": subject_id,
        "title": title,
        "content": content,
        "source_fingerprint": source_key,
        "ready": confirmed,
        "level": level,
    }


def refresh_context(db, kind, resource, annotation=None):
    snapshot = current_snapshot(db)
    if not snapshot:
        return
    source = context_source(db, kind, resource)
    if not source:
        return
    key = fingerprint([source["source_fingerprint"], source["level"], snapshot, MATCHER_VERSION])
    ref = kind + ":" + resource.id
    if db.bind.dialect.name == "postgresql":
        lock_key = int(fingerprint(["tip-context", ref])[:15], 16)
        db.execute(text("SELECT pg_advisory_xact_lock(:key)"), {"key": lock_key})
    context = db.scalar(select(LearningTipContext).where(LearningTipContext.context_ref == ref))
    if context and context.fingerprint == key and not annotation:
        return
    previous_ai = (
        [m for m in context.matches if m.get("basis") == "ai"]
        if context and context.source_fingerprint == source["source_fingerprint"] and context.snapshot_id == snapshot
        else []
    )
    if context is None:
        context = LearningTipContext(
            child_id=resource.child_id,
            context_ref=ref,
            **{("tutor_id" if kind == "tutor" else kind + "_id"): resource.id},
        )
        db.add(context)
    else:
        context.revision += 1
    context.subject_id = source["subject_id"]
    context.source_fingerprint = source["source_fingerprint"]
    context.fingerprint, context.snapshot_id, context.matcher_version = key, snapshot, MATCHER_VERSION
    context.status = "ready" if source["ready"] else "source_changed"
    context.matches = (
        match_sections(db, source["subject_id"], source["title"], source["content"], source["child"])
        if source["ready"]
        else []
    )
    if previous_ai and source["ready"]:
        previous_ids = {m["topic_id"] for m in previous_ai}
        context.matches = (previous_ai + [m for m in context.matches if m["topic_id"] not in previous_ids])[:8]
    if (
        annotation
        and source["ready"]
        and annotation.get("snapshot_id") == snapshot
        and annotation.get("source_fingerprint") == source["source_fingerprint"]
    ):
        from .catalog_models import CatalogTopic

        allowed = set(
            db.scalars(
                select(CatalogTopic.id).where(
                    CatalogTopic.id.in_([m["topic_id"] for m in annotation.get("matches", [])]),
                    CatalogTopic.snapshot_id == snapshot,
                    CatalogTopic.subject_id == source["subject_id"],
                )
            )
        )
        ai_matches = [m for m in annotation.get("matches", []) if m["topic_id"] in allowed]
        used = {m["topic_id"] for m in ai_matches}
        context.matches = (ai_matches + [m for m in context.matches if m["topic_id"] not in used])[:8]
    context.updated = int(now())
    # Manual IDs and the confirmed source fingerprint remain historical facts.
    # Projection uses them only while the source still agrees and IDs are active.


def _claim():
    with DB.begin() as db:
        # Only local deterministic work may resume after a lost lease. Provider
        # jobs retain their strict no-automatic-retry policy.
        db.execute(
            update(CatalogRefresh)
            .where(CatalogRefresh.status == "running", CatalogRefresh.updated < int(now()) - 120)
            .values(status="queued", lease=None)
        )
        query = (
            select(CatalogRefresh)
            .where(CatalogRefresh.status == "queued")
            .order_by(CatalogRefresh.child_id.is_(None), CatalogRefresh.updated, CatalogRefresh.id)
            .limit(1)
        )
        if db.bind.dialect.name == "postgresql":
            query = query.with_for_update(skip_locked=True)
        row = db.scalar(query)
        if not row:
            return None
        row.status, row.lease, row.updated = "running", uid(), int(now())
        db.flush()
        return {c.name: getattr(row, c.name) for c in CatalogRefresh.__table__.columns}


def _checkpoint(db, job, **values):
    return db.execute(
        update(CatalogRefresh)
        .where(CatalogRefresh.id == job["id"], CatalogRefresh.status == "running", CatalogRefresh.lease == job["lease"])
        .values(updated=int(now()), **values)
    ).rowcount


def _locked_resource(db, kind, resource_id):
    model = MODELS[kind]
    if kind == "unit" and db.bind.dialect.name == "postgresql":
        resource = db.scalar(select(model).where(model.id == resource_id).with_for_update(skip_locked=True))
        if resource is None and db.scalar(select(model.id).where(model.id == resource_id)):
            return None, "busy"
    else:
        resource = db.get(model, resource_id)
    if not resource:
        return None, "gone"
    query = select(Child).where(Child.id == resource.child_id)
    if db.bind.dialect.name == "postgresql":
        query = query.with_for_update(skip_locked=True)
    child = db.scalar(query)
    if child is None:
        return None, "busy" if db.scalar(select(Child.id).where(Child.id == resource.child_id)) else "gone"
    resource = db.get(model, resource_id, populate_existing=True)
    return resource, "ready" if resource else "gone"


def _dependents(db, job, resource):
    unit_ids = set(db.scalars(select(UnitSource.unit_id).where(UnitSource.material_id == resource.id)))
    unit_ids.update(db.scalars(select(LearningUnit.id).where(LearningUnit.material_id == resource.id)))
    for unit_id in sorted(unit_ids):
        enqueue(db, job["snapshot_id"], child_id=resource.child_id, kind="unit", resource_id=unit_id)
    turns = db.scalars(select(TutorTurn).where(TutorTurn.child_id == resource.child_id))
    for turn in turns:
        if any(ref.get("id") == resource.id for ref in turn.source_revisions):
            enqueue(db, job["snapshot_id"], child_id=resource.child_id, kind="tutor", resource_id=turn.id)


def work_one():
    """At most20 atomic resources; a renewed source supersedes an old lease."""
    job = _claim()
    if not job:
        return False
    try:
        with DB() as db:
            if current_snapshot(db) != job["snapshot_id"]:
                resources, kind = [], None
            elif job["resource_kind"]:
                resources, kind = [job["resource_id"]], job["resource_kind"]
            else:
                kind = list(MODELS)[job["phase"]]
                model = MODELS[kind]
                query = select(model.id).where(model.id > job["cursor"]).order_by(model.id).limit(20)
                if job["child_id"]:
                    query = query.where(model.child_id == job["child_id"])
                resources = list(db.scalars(query))
        if kind is None:
            with DB.begin() as db:
                _checkpoint(db, job, status="superseded", lease=None)
            return True
        for resource_id in resources:
            with DB.begin() as db:
                if current_snapshot(db) != job["snapshot_id"]:
                    _checkpoint(db, job, status="superseded", lease=None)
                    return True
                resource, status = _locked_resource(db, kind, resource_id)
                if status == "busy":
                    _checkpoint(db, job, status="queued", lease=None)
                    return False
                if resource and (not job["child_id"] or resource.child_id == job["child_id"]):
                    refresh_context(db, kind, resource, job["annotation"] if job["resource_kind"] else None)
                    if job["resource_kind"] == "material":
                        _dependents(db, job, resource)
                if not _checkpoint(db, job, cursor=resource_id, processed=CatalogRefresh.processed + 1):
                    return True
        with DB.begin() as db:
            if job["resource_kind"]:
                _checkpoint(db, job, status="completed", lease=None)
            elif len(resources) < 20:
                phase = job["phase"] + 1
                _checkpoint(
                    db,
                    job,
                    phase=phase,
                    cursor="",
                    status="completed" if phase >= len(MODELS) else "queued",
                    lease=None,
                )
            else:
                _checkpoint(db, job, status="queued", lease=None)
    except Exception as error:
        # Earlier resources/checkpoints stay committed; this resource rolls
        # back. A visible failed job is never replaced by dummy matches.
        with DB.begin() as db:
            _checkpoint(db, job, status="failed", error="catalog_refresh_" + type(error).__name__, lease=None)
        log.warning("catalog_refresh_failed type=%s", type(error).__name__)
    return True
