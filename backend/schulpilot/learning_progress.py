"""Read-only practice evidence: every saved task, independent of plans or quotas.

Fetch metadata and verdicts only; never answer bodies, photos or model opinions.
Retried tasks count once as tasks and separately as attempts. Historic records
are included immediately, without backfilling or changing their assessments.
"""

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import and_, case, func, select

from .db import Activity, Attempt, LearningUnit, User, get_db
from .grades import subject_key
from .security import authenticated, child_access

router = APIRouter(tags=["Lernstand nach Fächern"])
COUNTERS = ("practiced_tasks", "attempts", "independent_tasks", "assisted_tasks", "needs_practice_tasks", "uncertain_tasks", "reflection_tasks")


def read_ledger(db, child_id, unit_ids=None):
    conditions = [LearningUnit.child_id == child_id]
    if unit_ids is not None:
        if not unit_ids:
            return []
        conditions.append(LearningUnit.id.in_(unit_ids))
    partition = (Attempt.unit_id, Attempt.question_id)
    latest = (
        select(
            Attempt.unit_id,
            Attempt.outcome,
            Attempt.assisted,
            Attempt.created,
            func.coalesce(Attempt.evaluation["method"].as_string(), "").label("evaluation_method"),
            func.count().over(partition_by=partition).label("attempts"),
            func.row_number().over(partition_by=partition, order_by=(Attempt.created.desc(), Attempt.id.desc())).label("position"),
        )
        .join(LearningUnit, LearningUnit.id == Attempt.unit_id)
        .where(*conditions)
        .subquery()
    )
    reflection = latest.c.evaluation_method == "open_learning_v1"
    correct = latest.c.outcome == "correct"
    independent = and_(correct, latest.c.assisted.is_(False), latest.c.attempts == 1)
    fields = [LearningUnit.id, LearningUnit.subject, LearningUnit.topic, LearningUnit.status,
              LearningUnit.completed, LearningUnit.active_seconds, LearningUnit.round_kind]
    rows = db.execute(
        select(
            *fields,
            func.count().label("practiced_tasks"),
            func.sum(latest.c.attempts).label("attempts"),
            func.sum(case((independent, 1), else_=0)).label("independent_tasks"),
            func.sum(case((and_(correct, ~independent), 1), else_=0)).label("assisted_tasks"),
            func.sum(case((latest.c.outcome == "incorrect", 1), else_=0)).label("needs_practice_tasks"),
            func.sum(case((and_(latest.c.outcome.not_in(("correct", "incorrect")), ~reflection), 1), else_=0)).label("uncertain_tasks"),
            func.sum(case((reflection, 1), else_=0)).label("reflection_tasks"),
            func.max(latest.c.created).label("last_activity"),
        )
        .join(latest, latest.c.unit_id == LearningUnit.id)
        .where(latest.c.position == 1)
        .group_by(*fields)
        .order_by(func.max(latest.c.created).desc(), LearningUnit.id.desc())
    ).mappings()
    result = [dict(row) for row in rows]
    # The child predicate protects even inconsistent historical activity rows.
    if result:
        hints = dict(db.execute(select(Activity.unit_id, func.count()).where(
            Activity.child_id == child_id, Activity.unit_id.in_([r["id"] for r in result]), Activity.kind == "hint"
        ).group_by(Activity.unit_id)).all())
        for row in result:
            row["hints_used"] = hints.get(row["id"], 0)
    return result


def totals(rows):
    return {
        **{key: sum(int(row.get(key) or 0) for row in rows) for key in COUNTERS},
        "practiced_rounds": len(rows),
        "completed_rounds": sum(row["status"] == "completed" for row in rows),
        "ongoing_rounds": sum(row["status"] != "completed" for row in rows),
        "active_seconds_approx": sum(int(row.get("active_seconds") or 0) for row in rows),
        "hints_used": sum(row.get("hints_used", 0) for row in rows),
        "last_activity": max((row["last_activity"] for row in rows), default=None),
    }


def topic_evidence(ledger, subject, topic):
    # Keep different confirmed topics distinct; do not invent semantic matches.
    return totals([r for r in ledger if subject_key(r["subject"]) == subject_key(subject) and r["topic"].strip().casefold() == topic.strip().casefold()])


def subject_evidence(ledger):
    groups = {}
    for row in ledger:
        groups.setdefault(subject_key(row["subject"]), []).append(row)
    return [{"subject": rows[0]["subject"], **totals(rows),
             "topic_count": len({r["topic"].strip().casefold() for r in rows})}
            for _, rows in sorted(groups.items())]


@router.get("/children/{child_id}/learning-progress")
def learning_progress(
    child_id: str,
    subject: str | None = Query(None, max_length=80),
    topic: str | None = Query(None, max_length=160),
    page: int = Query(1, ge=1, le=1000000),
    page_size: int = Query(20, ge=1, le=50),
    p=Depends(authenticated),
    db=Depends(get_db),
):
    child = child_access(db, p, child_id)
    if topic is not None and subject is None:
        raise HTTPException(422, "Bitte zuerst das Fach auswählen.")
    ledger = read_ledger(db, child.id)
    selected = [r for r in ledger if (subject is None or subject_key(r["subject"]) == subject_key(subject))
                and (topic is None or r["topic"].strip().casefold() == topic.strip().casefold())]
    if topic is not None:
        items = [{**r, "active_seconds_approx": r["active_seconds"]} for r in selected]
        level = "rounds"
    else:
        level, groups = ("topics" if subject is not None else "subjects"), {}
        for row in selected:
            groups.setdefault(row["topic"].strip().casefold() if subject is not None else subject_key(row["subject"]), []).append(row)
        items = [{"subject": rows[0]["subject"], "topic": rows[0]["topic"] if subject is not None else None,
                  **totals(rows), "topic_count": len({r["topic"] for r in rows})}
                 for _, rows in sorted(groups.items(), key=lambda pair: pair[0].casefold())]
    count = len(items)
    pages = max(1, (count + page_size - 1) // page_size)
    actual = min(page, pages)
    return {
        "child_id": child.id, "child_name": db.get(User, child.user_id).display_name,
        "level": level, "subject": subject, "topic": topic,
        "totals": totals(ledger), "selected_totals": totals(selected),
        "items": items[(actual - 1) * page_size:actual * page_size],
        "pagination": {"page": actual, "pages": pages, "page_size": page_size, "total": count},
        "notice": "Jede beantwortete Aufgabe zählt, auch freiwillig und in begonnenen Runden. Weitere Versuche bleiben sichtbar. Spätere Wiederholungen zeigen zusätzlich, was hängen bleibt.",
    }
