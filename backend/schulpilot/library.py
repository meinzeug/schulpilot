"""Private, bounded reading lists. Browsing never starts a learning/AI job."""

from datetime import date, datetime, time
from typing import Literal
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from sqlalchemy import case, func, or_, select
from sqlalchemy.orm import load_only

from . import schemas as s
from .db import Assignment, Attempt, LearningUnit, Material, SchoolDay, UnitCoaching, get_db
from .security import authenticated, child_access
from .subjects import owned_subject

router = APIRouter(tags=["Bibliothek und Lernraum"])
Sort = Literal["subject", "newest", "oldest"]


def subject_value(column):
    return func.trim(func.coalesce(column, ""))


def contains(column, text):
    # German case folding also works in SQLite/PostgreSQL's C locale.
    for upper, lower in (("Ä", "ä"), ("Ö", "ö"), ("Ü", "ü"), ("ẞ", "ss"), ("ß", "ss")):
        column = func.replace(column, upper, lower)
    escaped = text.casefold().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    return func.lower(column).like("%" + escaped + "%", escape="\\")


def bounds(total, page, size):
    pages = max(1, (total + size - 1) // size)
    actual = min(page, pages)
    return {"total": total, "page": actual, "page_size": size, "pages": pages}


def material_summary(material, school_date=None):
    return {
        key: getattr(material, key)
        for key in (
            "id",
            "child_id",
            "school_day_id",
            "page_number",
            "title",
            "subject",
            "subject_id",
            "revision",
            "topic",
            "status",
            "confirmed",
            "synthetic",
            "created",
        )
    } | {
        "school_date": school_date,
        "has_image": bool(material.path),
        # Keep fixture IDs private while allowing the client to avoid offering
        # destructive controls for fixed examples in the live test family.
        "fixed_example": bool(material.fixture_id),
    }


MATERIAL_FIELDS = (
    Material.id,
    Material.child_id,
    Material.school_day_id,
    Material.page_number,
    Material.title,
    Material.subject,
    Material.subject_id,
    Material.revision,
    Material.path,
    Material.fixture_id,
    Material.topic,
    Material.status,
    Material.confirmed,
    Material.synthetic,
    Material.created,
)


@router.get("/children/{child_id}/materials")
def materials(
    child_id: str,
    q: str = Query("", max_length=120),
    subject: str | None = Query(None, max_length=80),
    subject_id: str | None = Query(None, pattern=r"^(?:[a-f0-9]{32}|unassigned)$"),
    topic: str | None = Query(None, max_length=160),
    status: Literal["all", "review", "confirmed"] = "all",
    sort: Sort = "subject",
    since: date | None = None,
    until: date | None = None,
    page: int = Query(1, ge=1, le=1000000),
    page_size: int = Query(20, ge=1, le=50),
    p=Depends(authenticated),
    db=Depends(get_db),
):
    child = child_access(db, p, child_id)
    if since and until and since > until:
        raise HTTPException(422, "Der Beginn muss vor dem Ende des Zeitraums liegen.")
    conditions = [Material.child_id == child.id, Material.purpose != "exam"]
    if subject_id is not None:
        if subject is not None:
            raise HTTPException(422, "Bitte nur einen Fachfilter verwenden.")
        if subject_id == "unassigned":
            conditions.append(Material.subject_id.is_(None))
        else:
            owned_subject(db, child, subject_id, p)
            conditions.append(Material.subject_id == subject_id)
    if q.strip():
        conditions.append(
            or_(
                *(
                    contains(column, q.strip())
                    for column in (Material.title, Material.topic, Material.subject, Material.content)
                )
            )
        )
    if topic is not None:
        conditions.append(Material.topic == topic)
    if status != "all":
        conditions.append(Material.confirmed.is_(status == "confirmed"))
    zone = ZoneInfo(s.Preferences(**child.preferences).timezone)
    if since:
        start = int(datetime.combine(since, time.min, zone).timestamp())
        conditions.append(
            or_(SchoolDay.school_date >= since.isoformat(), (SchoolDay.id.is_(None) & (Material.created >= start)))
        )
    if until:
        end = int(datetime.combine(until, time.max, zone).timestamp())
        conditions.append(
            or_(SchoolDay.school_date <= until.isoformat(), (SchoolDay.id.is_(None) & (Material.created <= end)))
        )
    # Facets deliberately omit only the selected subject. Their other filters
    # match the result list and can never contain a sibling's subject/count.
    facet = subject_value(Material.subject)
    subjects = [
        {"value": value, "count": count}
        for value, count in db.execute(
            select(facet, func.count())
            .outerjoin(SchoolDay, SchoolDay.id == Material.school_day_id)
            .where(*conditions)
            .group_by(facet)
            .order_by(func.lower(facet), facet)
        )
    ]
    if subject is not None:
        conditions.append(facet == subject.strip())
    total = db.scalar(
        select(func.count())
        .select_from(Material)
        .outerjoin(SchoolDay, SchoolDay.id == Material.school_day_id)
        .where(*conditions)
    )
    pagination = bounds(total, page, page_size)
    order = (
        [Material.created.asc(), Material.id.asc()]
        if sort == "oldest"
        else [Material.created.desc(), Material.id.desc()]
    )
    if sort == "subject":
        order = [case((facet == "", 1), else_=0), func.lower(facet), facet, *order]
    rows = db.execute(
        select(Material, SchoolDay.school_date)
        .outerjoin(SchoolDay, SchoolDay.id == Material.school_day_id)
        .options(load_only(*MATERIAL_FIELDS))
        .where(*conditions)
        .order_by(*order)
        .offset((pagination["page"] - 1) * page_size)
        .limit(page_size)
    )
    return {**pagination, "subjects": subjects, "items": [material_summary(m, day) for m, day in rows]}


def unit_summaries(db, ids):
    if not ids:
        return {}
    columns = (
        LearningUnit.id,
        LearningUnit.child_id,
        LearningUnit.subject,
        LearningUnit.topic,
        LearningUnit.status,
        LearningUnit.created,
        LearningUnit.completed,
        LearningUnit.estimated_minutes,
        LearningUnit.school_day_id,
        LearningUnit.round_kind,
        LearningUnit.synthetic,
        func.json_array_length(LearningUnit.questions).label("question_count"),
        UnitCoaching.status.label("review_status"),
    )
    result = {
        row["id"]: dict(row) | {"kind": "unit", "closed_questions": 0, "attempted_questions": 0}
        for row in db.execute(
            select(*columns)
            .outerjoin(UnitCoaching, UnitCoaching.unit_id == LearningUnit.id)
            .where(LearningUnit.id.in_(ids))
        ).mappings()
    }
    groups = db.execute(
        select(
            Attempt.unit_id,
            Attempt.question_id,
            func.count(),
            func.max(case((Attempt.outcome.in_(("correct", "uncertain")), 1), else_=0)),
        )
        .where(Attempt.unit_id.in_(ids))
        .group_by(Attempt.unit_id, Attempt.question_id)
    )
    for unit_id, _, count, closed in groups:
        if unit_id in result:
            result[unit_id]["attempted_questions"] += 1
            result[unit_id]["closed_questions"] += int(bool(closed) or count >= 3)
    return result


def group_learning_items(items):
    """Group presentation only; every distinct round and date remains available."""
    groups, result = {}, []
    for item in items:
        eligible = item["kind"] in ("unit", "review") and not item.get("mandatory") and item.get("status") not in ("active", "paused", "completed")
        if not eligible:
            result.append(item)
            continue
        key = tuple(" ".join(item.get(field, "").split()).casefold() for field in ("subject", "topic"))
        if key not in groups:
            group = {**item, "kind": "topic_group", "entries": [], "group_count": 0}
            groups[key] = group
            result.append(group)
        group = groups[key]
        group["entries"].append(dict(item))
        group["group_count"] += 1
    return [item["entries"][0] if item.get("group_count") == 1 else item for item in result]


@router.get("/children/{child_id}/learning")
def learning_list(
    child_id: str,
    q: str = Query("", max_length=120),
    subject: str | None = Query(None, max_length=80),
    section: Literal["ready", "later", "completed"] = "ready",
    sort: Sort = "subject",
    page: int = Query(1, ge=1, le=1000000),
    page_size: int = Query(20, ge=1, le=50),
    group_topics: bool = False,
    p=Depends(authenticated),
    db=Depends(get_db),
    capabilities: str | None = Header(None, alias="X-Schulpilot-Capabilities"),
):
    from .coaching import paths
    from .learning import language_supported, plan

    child = child_access(db, p, child_id)
    learning_paths = paths(db, child.id)
    include_language = language_supported(capabilities)
    current = plan(db, child, learning_paths=learning_paths, include_language=include_language)
    ready = []
    ready_ids = set()
    for item in [*current["today"], *current.get("voluntary", [])]:
        identity = (item["kind"], item["id"], item.get("block_id"))
        if identity not in ready_ids:
            ready.append(item)
            ready_ids.add(identity)
    later = [item for item in current["later"] if (item["kind"], item["id"], item.get("block_id")) not in ready_ids]
    # Future retrieval dates must stay visible without generating a new unit.
    for path in learning_paths:
        if path["next_review"] and path["next_review"] > current["date"] and not path["next_unit_id"]:
            later.append(
                {
                    "kind": "review",
                    "id": path["latest_unit_id"],
                    "subject": path["subject"],
                    "topic": path["topic"],
                    "mandatory": False,
                    "status": "planned",
                    "scheduled_for": path["next_review"],
                }
            )
    counts = {
        "ready": len(ready),
        "later": len(later),
        "completed": db.scalar(
            select(func.count())
            .select_from(LearningUnit)
            .where(LearningUnit.child_id == child.id, LearningUnit.status == "completed",
                   True if include_language else LearningUnit.round_kind != "vocabulary")
        ),
    }
    if section == "completed":
        conditions = [LearningUnit.child_id == child.id, LearningUnit.status == "completed"]
        if not include_language:
            conditions.append(LearningUnit.round_kind != "vocabulary")
        if q.strip():
            conditions.append(or_(contains(LearningUnit.topic, q.strip()), contains(LearningUnit.subject, q.strip())))
        facet = subject_value(LearningUnit.subject)
        subjects = [
            {"value": value, "count": count}
            for value, count in db.execute(
                select(facet, func.count()).where(*conditions).group_by(facet).order_by(func.lower(facet), facet)
            )
        ]
        if subject is not None:
            conditions.append(facet == subject.strip())
        total = db.scalar(select(func.count()).select_from(LearningUnit).where(*conditions))
        pagination = bounds(total, page, page_size)
        stamp = func.coalesce(LearningUnit.completed, LearningUnit.created)
        order = [stamp.asc(), LearningUnit.id.asc()] if sort == "oldest" else [stamp.desc(), LearningUnit.id.desc()]
        if sort == "subject":
            order = [func.lower(facet), facet, *order]
        ids = list(
            db.scalars(
                select(LearningUnit.id)
                .where(*conditions)
                .order_by(*order)
                .offset((pagination["page"] - 1) * page_size)
                .limit(page_size)
            )
        )
        summaries = unit_summaries(db, ids)
        items = [summaries[id] for id in ids]
    else:
        items = [dict(item) for item in (ready if section == "ready" else later)]
        needle = q.strip().casefold()
        if needle:
            items = [item for item in items if needle in (item["topic"] + " " + item["subject"]).casefold()]
        values = {}
        for item in items:
            value = item["subject"].strip()
            values[value] = values.get(value, 0) + 1
        subjects = [{"value": value, "count": values[value]} for value in sorted(values, key=str.casefold)]
        if subject is not None:
            items = [item for item in items if item["subject"].strip() == subject.strip()]
        stamps = {}
        for kinds, model in (
            (("unit", "review"), LearningUnit),
            (("assignment",), Assignment),
            (("material",), Material),
            (("study_path",), SchoolDay),
        ):
            ids = [item["id"] for item in items if item["kind"] in kinds]
            if ids:
                for id, created in db.execute(
                    select(model.id, model.created).where(model.child_id == child.id, model.id.in_(ids))
                ):
                    for kind in kinds:
                        stamps[(kind, id)] = created
        for item in items:
            item["created"] = stamps.get((item["kind"], item["id"]), 0)
        if group_topics:
            items = group_learning_items(items)
        # Display sorting never changes the plan or its primary next action.
        if sort == "subject":
            items.sort(
                key=lambda item: (item["subject"].strip().casefold(), -item["created"], item["kind"], item["id"])
            )
        else:
            items.sort(key=lambda item: (item["created"], item["kind"], item["id"]), reverse=sort == "newest")
        pagination = bounds(len(items), page, page_size)
        offset = (pagination["page"] - 1) * page_size
        items = items[offset : offset + page_size]
        flat = [entry for item in items for entry in (item["entries"] if item["kind"] == "topic_group" else [item])]
        summaries = unit_summaries(db, [item["id"] for item in flat if item["kind"] == "unit"])
        def enrich(item):
            return item | summaries.get(item["id"], {}) if item["kind"] == "unit" else item
        items = [{**item, "entries": [enrich(entry) for entry in item["entries"]]}
                 if item["kind"] == "topic_group" else enrich(item) for item in items]
    return {
        **pagination,
        "items": items,
        "subjects": subjects,
        "sections": counts,
        "date": current["date"],
        "paused": current["paused"],
        "free_day": current["free_day"],
        "available_minutes": current["available_minutes"],
        **{
            key: current[key]
            for key in (
                "daily_goal_minutes",
                "weekly_goal_minutes",
                "daily_active_seconds",
                "weekly_active_seconds",
                "daily_goal_met",
                "weekly_goal_met",
                "daily_remaining_minutes",
                "weekly_remaining_minutes",
                "goal_required",
                "can_continue_voluntarily",
                "optional_learning",
            )
            if key in current
        },
    }
