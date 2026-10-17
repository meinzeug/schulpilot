"""Private school results and bounded, explainable planning priorities.

Grades never change a saved answer, prove mastery or reach the AI provider.
Five recent observations in 90 days inform weighting inside the same time plan.
"""

import hashlib
import json
import re
from datetime import date, timedelta
from decimal import Decimal
from typing import Literal

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from pydantic import Field, model_validator
from sqlalchemy import func, select, update
from sqlalchemy.orm import defer

from . import schemas as s
from .db import Assignment, Child, Material, SchoolGrade, User, get_db, now
from .security import audit, child_access, family_access, parent, rate_limit

router = APIRouter(tags=["Noten und Lernschwerpunkte"])


def subject_key(value):
    key = " ".join(value.casefold().split())
    return "mathematik" if key == "mathe" else key


class GradeInput(s.Strict):
    subject: str = Field(min_length=1, max_length=80)
    topic: str = Field(default="", max_length=160)
    kind: Literal["classwork", "test", "oral", "homework", "other"] = "test"
    scale: Literal["grade_1_6", "points_0_15"] = "grade_1_6"
    value: Decimal = Field(ge=0, le=15, max_digits=4, decimal_places=2)
    weight: int = Field(default=1, ge=1, le=5)
    assessed_on: date
    note: str = Field(default="", max_length=500)

    @model_validator(mode="after")
    def valid_grade(self):
        self.subject, self.topic, self.note = self.subject.strip(), self.topic.strip(), self.note.strip()
        if not self.subject:
            raise ValueError("Bitte ein Fach angeben.")
        if self.scale == "grade_1_6" and not 1 <= self.value <= 6:
            raise ValueError("Eine Note muss zwischen 1 und 6 liegen.")
        return self


class GradeUpdate(GradeInput):
    revision: int = Field(ge=1)


class GradeSettings(s.Strict):
    enabled: bool


class GradeGoal(s.Strict):
    mandatory: bool = True
    due: date | None = None


def grade_data(row):
    return {key: (float(row.value) if key == "value" else getattr(row, key)) for key in (
        "id", "subject", "topic", "kind", "scale", "value", "weight", "assessed_on", "note", "assignment_id",
        "revision", "created", "updated",
    )}


def focus_summary(db, child, *, today=None):
    from .learning import local_day

    today = today or local_day(child)
    recent = list(db.scalars(select(SchoolGrade).where(
        SchoolGrade.child_id == child.id, SchoolGrade.assessed_on >= (today - timedelta(days=90)).isoformat(),
        SchoolGrade.assessed_on <= today.isoformat(),
    ).order_by(SchoolGrade.assessed_on.desc(), SchoolGrade.created.desc(), SchoolGrade.id.desc())))
    groups = {}
    for row in recent:
        group = groups.setdefault(subject_key(row.subject), [])
        if len(group) < 5:
            group.append(row)
    enabled = child.grade_planning_enabled
    result = []
    for rows in groups.values():
        def average(values):
            return sum((float(r.value) - 1) / 5 * r.weight if r.scale == "grade_1_6"
                       else (15 - float(r.value)) / 15 * r.weight for r in values) / sum(r.weight for r in values)

        need = average(rows)
        trend = "not_enough_data"
        if len(rows) >= 4:
            change = average(rows[:2]) - average(rows[2:4])
            trend = "declining" if change >= 0.15 else "improving" if change <= -0.15 else "stable"
        level = 2 if need >= 0.6 else 1 if need >= 0.4 or trend == "declining" else 0
        scales = {r.scale for r in rows}
        result.append({
            "subject": rows[0].subject, "priority": level if enabled else 0,
            "suggested_priority": level, "trend": trend, "observations": len(rows),
            "scale": next(iter(scales)) if len(scales) == 1 else None,
            "average": round(sum(float(r.value) * r.weight for r in rows) / sum(r.weight for r in rows), 2)
            if len(scales) == 1 else None,
            "latest_date": rows[0].assessed_on,
            "reason": "Mehr angeleitete Übung einplanen" if level == 2 else "Regelmäßig festigen" if level else "Im Plan ausgewogen berücksichtigen",
        })
    return sorted(result, key=lambda row: (-row["priority"], row["subject"].casefold()))


def priorities(db, child):
    return {subject_key(r["subject"]): r["priority"] for r in focus_summary(db, child) if r["priority"]}


def owned_grade(db, child, grade_id, *, lock=False):
    query = select(SchoolGrade).where(SchoolGrade.child_id == child.id, SchoolGrade.id == grade_id)
    if lock:
        if db.bind.dialect.name == "postgresql":
            query = query.with_for_update()
        else:
            db.execute(update(SchoolGrade).where(SchoolGrade.child_id == child.id, SchoolGrade.id == grade_id)
                       .values(revision=SchoolGrade.revision))
    row = db.scalar(query)
    if not row:
        raise HTTPException(404, "Note nicht gefunden.")
    return row


def valid_date(child, value):
    from .learning import local_day

    if value > local_day(child):
        raise HTTPException(422, "Eine erhaltene Note kann nicht in der Zukunft liegen.")


@router.get("/children/{child_id}/grades")
def list_grades(child_id: str, subject: str | None = Query(None, max_length=80),
                page: int = Query(1, ge=1, le=1000000), page_size: int = Query(20, ge=1, le=50),
                p=Depends(parent), db=Depends(get_db)):
    from .learning import local_day
    from .library import bounds

    child = child_access(db, p, child_id)
    query = select(SchoolGrade).where(SchoolGrade.child_id == child.id)
    if subject:
        query = query.where(SchoolGrade.subject == subject)
    count = db.scalar(select(func.count()).select_from(query.subquery()))
    pagination = bounds(count, page, page_size)
    rows = db.scalars(query.order_by(SchoolGrade.assessed_on.desc(), SchoolGrade.created.desc(), SchoolGrade.id.desc())
                      .offset((pagination["page"] - 1) * page_size).limit(page_size))
    return {"child_id": child.id, "items": [grade_data(r) for r in rows], "pagination": pagination,
            "today": local_day(child).isoformat(),
            "child_name": db.get(User, child.user_id).display_name,
            "can_manage": family_access(db, p, child.family_id)[1].permission != "view",
            "planning_enabled": child.grade_planning_enabled,
            "subjects": sorted(set(child.subjects) | set(db.scalars(select(SchoolGrade.subject).where(SchoolGrade.child_id == child.id))), key=str.casefold),
            "focus": focus_summary(db, child),
            "notice": "Der Schnitt gilt nur für diese Einträge, nicht als Zeugnisnote. Der Lernplan berücksichtigt höchstens fünf Noten je Fach aus 90 Tagen; bestehende Zeitziele und Elternaufträge bleiben erhalten."}


@router.post("/children/{child_id}/grades", status_code=201)
def create_grade(child_id: str, data: GradeInput, idempotency_key: str | None = Header(None), p=Depends(parent), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=True)
    valid_date(child, data.assessed_on)
    digest = hashlib.sha256(json.dumps(data.model_dump(mode="json") | {"value": format(data.value, ".2f")}, sort_keys=True).encode()).hexdigest()
    if idempotency_key is not None:
        if not re.fullmatch(r"[A-Za-z0-9_-]{16,80}", idempotency_key):
            raise HTTPException(422, "Bitte einen gültigen Anfrageschlüssel verwenden.")
        db.execute(update(Child).where(Child.id == child.id).values(grade=Child.grade))
        previous = db.scalar(select(SchoolGrade).where(SchoolGrade.child_id == child.id, SchoolGrade.request_key == idempotency_key))
        if previous:
            if previous.request_digest != digest:
                raise HTTPException(409, "Diese Anfrage wurde bereits mit anderen Angaben gespeichert. Bitte die Notenliste neu laden.")
            return grade_data(previous)
    rate_limit(db, "grade-save:" + p.user.id, 60, 60, commit=False)
    row = SchoolGrade(child_id=child.id, **data.model_dump(exclude={"assessed_on"}), assessed_on=data.assessed_on.isoformat(),
                      request_key=idempotency_key, request_digest=digest if idempotency_key else None)
    db.add(row)
    db.flush()
    audit(db, p.user.id, "grade.create", row.id)
    db.commit()
    return grade_data(row)


@router.put("/children/{child_id}/grades/{grade_id}")
def update_grade(child_id: str, grade_id: str, data: GradeUpdate, p=Depends(parent), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=True)
    valid_date(child, data.assessed_on)
    row = owned_grade(db, child, grade_id, lock=True)
    if row.revision != data.revision:
        raise HTTPException(409, "Die Note wurde inzwischen geändert. Bitte neu laden.")
    for key, value in data.model_dump(exclude={"revision", "assessed_on"}).items():
        setattr(row, key, value)
    row.assessed_on, row.updated, row.revision = data.assessed_on.isoformat(), int(now()), row.revision + 1
    audit(db, p.user.id, "grade.update", row.id)
    db.commit()
    return grade_data(row)


@router.delete("/children/{child_id}/grades/{grade_id}")
def delete_grade(child_id: str, grade_id: str, p=Depends(parent), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=True)
    row = owned_grade(db, child, grade_id, lock=True)
    # A previously accepted parent goal has its own lifecycle, not a hidden cascade.
    db.delete(row)
    audit(db, p.user.id, "grade.delete", grade_id)
    db.commit()
    return {"deleted": True}


@router.put("/children/{child_id}/grade-settings")
def grade_settings(child_id: str, data: GradeSettings, p=Depends(parent), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=True)
    db.execute(update(Child).where(Child.id == child.id).values(grade_planning_enabled=data.enabled))
    audit(db, p.user.id, "grade.planning", child.id)
    db.commit()
    return {"enabled": data.enabled}


@router.post("/children/{child_id}/grades/{grade_id}/goal")
def create_goal(child_id: str, grade_id: str, data: GradeGoal, p=Depends(parent), db=Depends(get_db)):
    from .learning import assignment_data

    child = child_access(db, p, child_id, write=True)
    row = owned_grade(db, child, grade_id, lock=True)
    if row.assignment_id:
        return assignment_data(db.get(Assignment, row.assignment_id))
    candidates = list(db.scalars(select(Material).where(Material.child_id == child.id, Material.confirmed.is_(True))
                                .options(defer(Material.content), defer(Material.homework), defer(Material.uncertainties))
                                .order_by(Material.created.desc(), Material.id.desc())))
    candidates = [m for m in candidates if subject_key(m.subject) == subject_key(row.subject)]
    material = next((m for m in candidates if not row.topic or m.topic.casefold() == row.topic.casefold()), None)
    if not material:
        raise HTTPException(409, "Bitte zuerst eine passende Heftseite zum Fach und Thema hinzufügen und prüfen.")
    assignment = Assignment(child_id=child.id, subject=material.subject, topic=material.topic, material_id=material.id,
                            kind="parent", mandatory=data.mandatory, due=data.due.isoformat() if data.due else None,
                            note="Den bestätigten Schulstoff verstehen, angeleitet üben und später selbstständig wiederholen.")
    db.add(assignment)
    db.flush()
    row.assignment_id = assignment.id
    row.revision, row.updated = row.revision + 1, int(now())
    audit(db, p.user.id, "grade.learning_goal", assignment.id)
    db.commit()
    return assignment_data(assignment)
