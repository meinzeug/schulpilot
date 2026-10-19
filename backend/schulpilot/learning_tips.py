"""One private recommendation projection across notebooks, units and tutor."""

from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import Field, model_validator
from sqlalchemy import select, text

from . import schemas as s
from .catalog_import import catalog_url, fingerprint
from .catalog_jobs import MODELS, context_source
from .catalog_models import (
    CatalogContent,
    CatalogLevel,
    CatalogMembership,
    CatalogRefresh,
    CatalogTopic,
    LearningTipContext,
    LearningTipInteraction,
)
from .catalog_search import MATCHER_VERSION, current_snapshot, incompatible, known_class_topics, search_topics
from .db import Attempt, LearningMemory, get_db, now
from .security import authenticated, child_access, family_access, rate_limit
from .subjects import owned_subject, subject_data
from .vocabulary import lock_child

router = APIRouter(tags=["Lerntipps"])
ResourceKind = Literal["material", "unit", "assignment", "tutor"]


def owned_resource(db, p, child_id, kind, resource_id, *, write=False):
    child = child_access(db, p, child_id, write=write)
    resource = db.get(MODELS[kind], resource_id)
    if not resource or resource.child_id != child.id:
        raise HTTPException(404, "Lernstoff nicht gefunden.")
    return child, resource


def contents_for(db, child, subject_id, topic_ids, limit=3, goal=""):
    snapshot = current_snapshot(db)
    topics = {
        row.id: row
        for row in db.scalars(
            select(CatalogTopic).where(
                CatalogTopic.id.in_(topic_ids),
                CatalogTopic.subject_id == subject_id,
                CatalogTopic.snapshot_id == snapshot,
            )
        )
    }
    known = known_class_topics(db, child, subject_id, list(topics))
    rows = list(
        db.execute(
            select(CatalogMembership, CatalogContent)
            .join(CatalogContent, CatalogContent.id == CatalogMembership.content_id)
            .where(
                CatalogMembership.topic_id.in_(list(topics)),
                CatalogMembership.snapshot_id == snapshot,
                CatalogContent.snapshot_id == snapshot,
                CatalogContent.title_verified.is_(True),
            )
            .order_by(CatalogMembership.curated.desc(), CatalogMembership.position.asc().nullslast(), CatalogContent.id)
        )
    )
    recommended, additional, seen = [], [], set()
    # Keep selected/matched topic ordering, rather than letting global IDs choose
    # three videos from one of several different sections.
    grouped = {topic: [] for topic in topics}
    for membership, content in rows:
        topic = topics[membership.topic_id]
        if goal and incompatible(goal, content.title):
            continue
        primary = membership.curated and topic.id in known and not topic.empty_curated
        if not primary and not (membership.curated or membership.general_verified):
            continue
        url = membership.url if primary or not membership.general_url else membership.general_url
        item = {
            "id": content.id,
            "topic_id": topic.id,
            "title": content.title,
            "content_type": content.content_type,
            "url": catalog_url(url),
            "provider": "Sofatutor",
            "relation": "known_level" if primary else "general_topic",
            "topic_title": topic.title,
            "reason": "Passend zum Thema „" + topic.title + "“.",
            "curated_class_membership_verified": bool(primary),
        }
        grouped[topic.id].append((bool(primary), item))
    # Round-robin for multiple topics; deterministic and independent of GET count.
    for primary_pass in (True, False):
        for n in range(max((len(v) for v in grouped.values()), default=0)):
            for topic_id in topic_ids:
                values = grouped.get(topic_id, [])
                if n >= len(values):
                    continue
                primary, item = values[n]
                if primary != primary_pass or item["id"] in seen:
                    continue
                target = recommended if primary else additional
                if len(target) < limit:
                    target.append(item)
                    seen.add(item["id"])
    eligible_ids = {item["id"] for values in grouped.values() for _, item in values}
    return {"recommended": recommended, "additional": additional, "has_more": len(eligible_ids) > len(seen)}


def projection(db, p, child, kind, resource, *, limit=3):
    snapshot = current_snapshot(db)
    base = {
        "state": "unavailable" if not snapshot else "pending",
        "topics": [],
        "recommended": [],
        "additional": [],
        "has_more": False,
        "supports_media_return": True,
    }
    if not snapshot:
        return base
    context = db.scalar(select(LearningTipContext).where(LearningTipContext.context_ref == kind + ":" + resource.id))
    source = context_source(db, kind, resource)
    failed_keys = [fingerprint([snapshot, MATCHER_VERSION, child.id, kind, resource.id]),
                   fingerprint([snapshot, MATCHER_VERSION])]
    failed = db.scalar(select(CatalogRefresh.id).where(CatalogRefresh.snapshot_id == snapshot,
        CatalogRefresh.status == "failed", CatalogRefresh.id.in_(failed_keys)))
    if not context or not source:
        return base | ({"state": "failed"} if failed else {})
    base |= {
        "revision": context.revision,
        "context_id": context.id,
        "subject_id": source["subject_id"],
        "source_confirmed": kind != "material" or resource.confirmed,
        "can_respond": p.user.role == "child" or family_access(db, p, child.family_id)[1].permission != "view",
    }
    if kind == "unit":
        memory = db.get(LearningMemory, resource.id)
        media = (memory.working or {}).get("media") if memory else None
        base["media_return"] = media if media and (p.user.role == "parent" or media.get("user_id") == p.user.id) else None
    # A delayed local job must not expose stale links as a current recommendation.
    if not source["ready"]:
        return base | {"state": "source_changed"}
    if context.source_fingerprint != source["source_fingerprint"] or context.snapshot_id != snapshot:
        return base | ({"state": "failed"} if failed else {})
    manual_active = bool(
        context.confirmed_topic_ids and context.confirmation_fingerprint == source["source_fingerprint"]
    )
    stale = bool(context.confirmed_topic_ids and not manual_active)
    matches = (
        [
            {"topic_id": tid, "quality": "confirmed", "basis": "confirmed", "context_ref": "manual"}
            for tid in context.confirmed_topic_ids
        ]
        if manual_active
        else context.matches
    )
    ids = [m["topic_id"] for m in matches]
    topics = {
        r.id: r
        for r in db.scalars(
            select(CatalogTopic).where(
                CatalogTopic.id.in_(ids),
                CatalogTopic.subject_id == source["subject_id"],
                CatalogTopic.snapshot_id == snapshot,
            )
        )
    }
    if manual_active and set(ids) != set(topics):
        stale = True
    rejected = {
        r.data.get("topic_id")
        for r in db.scalars(
            select(LearningTipInteraction).where(
                LearningTipInteraction.context_id == context.id, LearningTipInteraction.kind == "not_relevant"
            )
        )
        if r.data.get("source_fingerprint") == source["source_fingerprint"]
    }
    ids = [tid for tid in ids if tid in topics and tid not in rejected]
    known = known_class_topics(db, child, source["subject_id"], ids)
    rows = [
        {
            "id": m["topic_id"],
            "title": topics[m["topic_id"]].title,
            "quality": m["quality"],
            "context_ref": m["context_ref"],
            "known_level": m["topic_id"] in known,
            "empty_curated": topics[m["topic_id"]].empty_curated,
        }
        for m in matches
        if m["topic_id"] in ids
    ]
    contents = contents_for(db, child, source["subject_id"], ids, limit, source["title"] + "\n" + source["content"])
    if kind == "unit":
        from .learning_controller import decide

        action, _ = decide(db, resource)
        focused = action["resources"]
        by_id = {item["id"]: item for item in focused + contents["recommended"] + contents["additional"]}
        ordered = list(dict.fromkeys(item["id"] for item in focused + contents["recommended"] + contents["additional"]))
        selected_items = [by_id[key] for key in ordered][:limit]
        contents["recommended"] = [item for item in selected_items if item["relation"] == "known_level"]
        contents["additional"] = [item for item in selected_items if item["relation"] != "known_level"]
        existing = {row["id"] for row in rows}
        for item in focused:
            if item["topic_id"] not in existing:
                rows.append({"id": item["topic_id"], "title": item["topic_title"], "quality": "suggestion",
                    "context_ref": "learning_support", "known_level": item["relation"] == "known_level", "empty_curated": False})
                existing.add(item["topic_id"])
    recent_links = []
    if p.user.role == "parent":
        recent_links = [
            {"title": title, "created": created}
            for title, created in db.execute(
                select(CatalogContent.title, LearningTipInteraction.created)
                .join(LearningTipInteraction, LearningTipInteraction.content_id == CatalogContent.id)
                .where(
                    LearningTipInteraction.child_id == child.id,
                    LearningTipInteraction.context_id == context.id,
                    LearningTipInteraction.kind == "open",
                )
                .order_by(LearningTipInteraction.created.desc(), LearningTipInteraction.id.desc())
                .limit(10)
            )
        ]
    qualities = {row["id"]: row["quality"] for row in rows}
    for item in contents["recommended"] + contents["additional"]:
        item["match_quality"] = qualities.get(item["topic_id"], "suggestion")
    rejected_contents = {event.content_id for event in db.scalars(select(LearningTipInteraction).where(
        LearningTipInteraction.context_id == context.id, LearningTipInteraction.kind.in_(["broken", "not_helpful"])))
        if event.data.get("source_fingerprint") == source["source_fingerprint"]}
    for key in ("recommended", "additional"):
        contents[key] = [item for item in contents[key] if item["id"] not in rejected_contents]
    return base | {
        "state": "ready",
        "selection_needs_confirmation": stale,
        "topics": rows,
        "recent_links": recent_links,
        **contents,
    }


@router.get("/children/{child_id}/learning-tips/{kind}/{resource_id}")
def tips(
    child_id: str,
    kind: ResourceKind,
    resource_id: str,
    limit: int = Query(3, ge=1, le=12),
    p=Depends(authenticated),
    db=Depends(get_db),
):
    child, resource = owned_resource(db, p, child_id, kind, resource_id)
    return projection(db, p, child, kind, resource, limit=limit)


@router.get("/children/{child_id}/subjects/{subject_id}/topics")
def topics(
    child_id: str,
    subject_id: str,
    q: str = Query("", max_length=160),
    page: int = Query(1, ge=1, le=10000),
    page_size: int = Query(20, ge=1, le=50),
    scope: Literal["all", "known"] = "all",
    p=Depends(authenticated),
    db=Depends(get_db),
):
    child = child_access(db, p, child_id)
    subject = owned_subject(db, child, subject_id, p)
    return search_topics(
        db, subject_id, q, page=page, page_size=page_size, child=child, known_only=scope == "known"
    ) | {
        "subject": subject_data(subject),
        "can_manage": p.user.role == "parent" and family_access(db, p, child.family_id)[1].permission != "view",
    }


@router.get("/children/{child_id}/subjects/{subject_id}/topics/{topic_id}")
def topic_contents(
    child_id: str,
    subject_id: str,
    topic_id: str,
    limit: int = Query(3, ge=1, le=12),
    p=Depends(authenticated),
    db=Depends(get_db),
):
    child = child_access(db, p, child_id)
    owned_subject(db, child, subject_id, p)
    topic = db.get(CatalogTopic, topic_id)
    if not topic or topic.subject_id != subject_id or topic.snapshot_id != current_snapshot(db):
        raise HTTPException(404, "Thema nicht gefunden.")
    return {
        "topic": {"id": topic.id, "title": topic.title, "empty_curated": topic.empty_curated},
        **contents_for(db, child, subject_id, [topic.id], limit),
    }


@router.get("/children/{child_id}/subjects/{subject_id}/levels")
def levels(child_id: str, subject_id: str, p=Depends(authenticated), db=Depends(get_db)):
    child = child_access(db, p, child_id)
    owned_subject(db, child, subject_id, p)
    return {
        "items": [
            {
                "id": row.id,
                "title": row.title,
                "level_type": row.level_type,
                "level_number": row.level_number,
                "has_topics": row.has_topics,
            }
            for row in db.scalars(
                select(CatalogLevel)
                .where(CatalogLevel.subject_id == subject_id, CatalogLevel.snapshot_id == current_snapshot(db))
                .order_by(CatalogLevel.level_type, CatalogLevel.level_number, CatalogLevel.id)
            )
        ]
    }


class Selection(s.Strict):
    revision: int = Field(ge=1)
    topic_ids: list[str] = Field(max_length=8)
    confirmed: Literal[True]


@router.put("/children/{child_id}/learning-tips/{kind}/{resource_id}/selection")
def selection(
    child_id: str, kind: ResourceKind, resource_id: str, data: Selection, p=Depends(authenticated), db=Depends(get_db)
):
    child, resource = owned_resource(db, p, child_id, kind, resource_id, write=True)
    lock_child(db, child)
    context = db.scalar(
        select(LearningTipContext).where(LearningTipContext.context_ref == kind + ":" + resource.id).with_for_update()
    )
    if not context or context.revision != data.revision:
        raise HTTPException(409, "Die Lerntipps wurden geändert. Bitte neu laden.")
    source = context_source(db, kind, resource)
    if (
        not source["ready"]
        or context.source_fingerprint != source["source_fingerprint"]
        or context.snapshot_id != current_snapshot(db)
    ):
        raise HTTPException(409, "Der Lernstoff wurde geändert. Bitte die aktuelle Zuordnung abwarten.")
    found = set(
        db.scalars(
            select(CatalogTopic.id).where(
                CatalogTopic.id.in_(data.topic_ids),
                CatalogTopic.subject_id == source["subject_id"],
                CatalogTopic.snapshot_id == current_snapshot(db),
            )
        )
    )
    if len(set(data.topic_ids)) != len(data.topic_ids) or found != set(data.topic_ids):
        raise HTTPException(422, "Bitte vorhandene Themen aus diesem Fach wählen.")
    context.confirmed_topic_ids, context.confirmation_fingerprint = data.topic_ids, source["source_fingerprint"]
    context.revision, context.updated = context.revision + 1, int(now())
    db.commit()
    return projection(db, p, child, kind, resource)


class Interaction(s.Strict):
    request_key: str = Field(min_length=8, max_length=80)
    kind: Literal["open", "not_relevant", "watched", "skipped", "not_helpful", "broken"]
    revision: int | None = Field(default=None, ge=1)
    content_id: str | None = Field(default=None, max_length=100)
    topic_id: str = Field(min_length=1, max_length=100)
    question_id: str | None = Field(default=None, max_length=60)

    @model_validator(mode="after")
    def needs_content(self):
        if self.kind in ("open", "watched", "skipped", "not_helpful", "broken") and not self.content_id:
            raise ValueError("Der gespeicherte Inhaltsverweis fehlt.")
        return self


@router.post("/children/{child_id}/learning-tips/{kind}/{resource_id}/interactions")
def interaction(
    child_id: str, kind: ResourceKind, resource_id: str, data: Interaction, p=Depends(authenticated), db=Depends(get_db)
):
    child, resource = owned_resource(db, p, child_id, kind, resource_id, write=data.kind != "open")
    if data.kind not in ("open", "not_relevant") and (p.user.role != "child" or kind != "unit"):
        raise HTTPException(403, "Diese Rückmeldung gehört zum eigenen Kinder-Lernschritt.")
    if kind == "unit":
        from .learning import get_unit, question

        resource = get_unit(db, p, resource_id, lock=True)
        if data.question_id:
            question(resource, data.question_id)
    if db.bind.dialect.name == "postgresql":
        db.execute(
            text("SELECT pg_advisory_xact_lock(:key)"),
            {"key": int(fingerprint(["tip-request", p.user.id, data.request_key])[:15], 16)},
        )
    lock_child(db, child)
    digest = fingerprint([child.id, kind, resource_id, data.model_dump()])
    previous = db.scalar(
        select(LearningTipInteraction).where(
            LearningTipInteraction.user_id == p.user.id, LearningTipInteraction.request_key == data.request_key
        )
    )
    if previous:
        if previous.request_digest != digest:
            raise HTTPException(409, "Dieser Vorgang gehört zu einer anderen Rückmeldung.")
        return {"saved": True, "kind": previous.kind}
    rate_limit(db, "tip-actions:" + child.id, 200, 3600, commit=False)
    view = projection(db, p, child, kind, resource, limit=12)
    if view["state"] != "ready" or view.get("revision") != data.revision:
        raise HTTPException(409, "Bitte die aktuellen Lerntipps neu laden.")
    allowed_topics = {t["id"] for t in view["topics"]}
    allowed_contents = {(c["topic_id"], c["id"]) for c in view["recommended"] + view["additional"]}
    if data.topic_id not in allowed_topics or (
        data.content_id and (data.topic_id, data.content_id) not in allowed_contents
    ):
        raise HTTPException(422, "Dieser Verweis gehört nicht zu den aktuellen Lerntipps.")
    source = context_source(db, kind, resource)
    event = LearningTipInteraction(
            child_id=child.id,
            user_id=p.user.id,
            context_id=view["context_id"],
            content_id=data.content_id,
            kind=data.kind,
            request_key=data.request_key,
            request_digest=digest,
            data={"topic_id": data.topic_id, "source_fingerprint": source["source_fingerprint"], "question_id": data.question_id},
        )
    if data.kind not in ("open", "not_relevant"):
        opened = db.scalar(select(LearningTipInteraction).where(
            LearningTipInteraction.context_id == view["context_id"], LearningTipInteraction.user_id == p.user.id,
            LearningTipInteraction.content_id == data.content_id, LearningTipInteraction.kind == "open"
        ).order_by(LearningTipInteraction.created.desc(), LearningTipInteraction.id.desc()).limit(1))
        if not opened or opened.data.get("source_fingerprint") != source["source_fingerprint"]:
            raise HTTPException(409, "Öffne zuerst den aktuellen Lerntipp.")
        if data.question_id != opened.data.get("question_id"):
            raise HTTPException(409, "Diese Rückmeldung gehört zu einer anderen Aufgabe. Bitte den ursprünglichen Lerntipp öffnen.")
        event.data = {**event.data, "open_id": opened.id}
        duplicate = next((r for r in db.scalars(select(LearningTipInteraction).where(
            LearningTipInteraction.context_id == view["context_id"], LearningTipInteraction.user_id == p.user.id,
            LearningTipInteraction.content_id == data.content_id, LearningTipInteraction.kind == data.kind))
            if r.data.get("open_id") == opened.id), None)
        if duplicate:
            return {"saved": True, "kind": duplicate.kind}
    db.add(event)
    db.flush()
    if kind == "unit" and p.user.role == "child" and data.kind != "not_relevant":
        from .learning_controller import observe

        media = {"content_id": data.content_id, "topic_id": data.topic_id, "question_id": data.question_id,
            "status": "opened" if data.kind == "open" else data.kind, "user_id": p.user.id,
            "interaction_id": event.id, "source_fingerprint": source["source_fingerprint"]}
        media["open_id"] = event.id if data.kind == "open" else event.data["open_id"]
        if data.kind == "watched" and resource.status in ("active", "paused"):
            answered = db.scalar(select(Attempt.id).where(Attempt.unit_id == resource.id,
                Attempt.question_id == data.question_id, Attempt.outcome.in_(["correct", "uncertain"])))
            if data.question_id and not answered:
                from .learning import record

                record(db, child.id, "explanation", {"question_id": data.question_id,
                    "via": "self_reported_media", "interaction_id": event.id}, resource.id)
        observe(db, resource, "media_opened" if data.kind == "open" else "media_returned", "media:" + event.id,
            ["tip_interaction:" + event.id], working_patch={"media": media,
                "media_return": data.kind in ("watched", "skipped", "not_helpful", "broken")})
    db.commit()
    return {"saved": True, "kind": data.kind}


@router.post("/children/{child_id}/subjects/{subject_id}/topic-interactions")
def browse_interaction(child_id: str, subject_id: str, data: Interaction, p=Depends(authenticated), db=Depends(get_db)):
    child = child_access(db, p, child_id)
    owned_subject(db, child, subject_id, p)
    if data.kind != "open":
        raise HTTPException(422, "Rückmeldungen gehören zum jeweiligen Lernstoff.")
    digest = fingerprint([child.id, "subject", subject_id, data.model_dump()])
    if db.bind.dialect.name == "postgresql":
        db.execute(
            text("SELECT pg_advisory_xact_lock(:key)"),
            {"key": int(fingerprint(["tip-request", p.user.id, data.request_key])[:15], 16)},
        )
    lock_child(db, child)
    previous = db.scalar(
        select(LearningTipInteraction).where(
            LearningTipInteraction.user_id == p.user.id, LearningTipInteraction.request_key == data.request_key
        )
    )
    if previous:
        if previous.request_digest != digest:
            raise HTTPException(409, "Dieser Vorgang gehört zu einem anderen Linkaufruf.")
        return {"saved": True, "kind": "open"}
    rate_limit(db, "tip-actions:" + child.id, 200, 3600, commit=False)
    topic = db.get(CatalogTopic, data.topic_id)
    if not topic or topic.subject_id != subject_id or topic.snapshot_id != current_snapshot(db):
        raise HTTPException(404, "Thema nicht gefunden.")
    view = contents_for(db, child, subject_id, [topic.id], limit=12)
    if data.content_id not in {r["id"] for r in view["recommended"] + view["additional"]}:
        raise HTTPException(422, "Dieser Inhaltsverweis gehört nicht zum Thema.")
    db.add(
        LearningTipInteraction(
            child_id=child.id,
            user_id=p.user.id,
            kind="open",
            content_id=data.content_id,
            request_key=data.request_key,
            request_digest=digest,
            data={
                "topic_id": topic.id,
                "subject_id": subject_id,
                "source": "subject_browser",
                "snapshot_id": current_snapshot(db),
            },
        )
    )
    db.commit()
    return {"saved": True, "kind": "open"}
