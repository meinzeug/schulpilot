"""Private school results and bounded, explainable planning priorities.

Grades never change a saved answer, prove mastery or reach the AI provider.
Five recent observations in 90 days inform weighting inside the same time plan.
"""

import csv
import hashlib
import io
import json
import re
from datetime import date, timedelta
from decimal import Decimal
from typing import Literal

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from fastapi.responses import Response
from pydantic import Field, model_validator
from sqlalchemy import and_, func, or_, select, update
from sqlalchemy.orm import defer

from . import schemas as s
from .db import Assignment, Child, GradeSourceSlot, Material, SchoolGrade, User, get_db, now
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
    assessed_on: date | None = None
    school_year_start: int | None = Field(default=None, ge=2000, le=2200)
    semester: Literal[1, 2] | None = None
    note: str = Field(default="", max_length=500)

    @model_validator(mode="after")
    def valid_grade(self):
        self.subject, self.topic, self.note = self.subject.strip(), self.topic.strip(), self.note.strip()
        if not self.subject:
            raise ValueError("Bitte ein Fach angeben.")
        if self.scale == "grade_1_6" and not 1 <= self.value <= 6:
            raise ValueError("Eine Note muss zwischen 1 und 6 liegen.")
        if self.assessed_on is None and (self.school_year_start is None or self.semester is None):
            raise ValueError("Bitte ein Datum oder das belegte Schulhalbjahr angeben.")
        return self


class GradeUpdate(GradeInput):
    revision: int = Field(ge=1)


class GradeSettings(s.Strict):
    enabled: bool


class GradeGoal(s.Strict):
    revision: int | None = Field(default=None, ge=1)
    mandatory: bool = True
    due: date | None = None


def grade_data(row):
    return {key: (float(row.value) if key == "value" else getattr(row, key)) for key in (
        "id", "subject", "topic", "kind", "scale", "value", "weight", "assessed_on", "note", "assignment_id",
        "revision", "created", "updated", "school_year_start", "semester",
    )} | {"date_precision": "day" if row.assessed_on else "semester", "date_label": row.assessed_on or
          f"{row.semester}. Halbjahr {row.school_year_start}/{row.school_year_start + 1}"}


def focus_summary(db, child, *, today=None):
    from .learning import local_day

    today = today or local_day(child)
    year = today.year if today.month >= 8 else today.year - 1
    recent = list(db.scalars(select(SchoolGrade).where(
        SchoolGrade.child_id == child.id, or_(and_(SchoolGrade.assessed_on >= (today - timedelta(days=90)).isoformat(),
        SchoolGrade.assessed_on <= today.isoformat()), and_(SchoolGrade.assessed_on.is_(None),
        SchoolGrade.school_year_start == year)),
    ).order_by(SchoolGrade.assessed_on.desc(), SchoolGrade.created.desc(), SchoolGrade.id.desc())))
    groups = {}
    for row in recent:
        group = groups.setdefault(subject_key(row.subject), [])
        if row.assessed_on is None or len([r for r in group if r.assessed_on]) < 5:
            group.append(row)
    enabled = child.grade_planning_enabled
    result = []
    for rows in groups.values():
        def average(values):
            return sum((float(r.value) - 1) / 5 * r.weight if r.scale == "grade_1_6"
                       else (15 - float(r.value)) / 15 * r.weight for r in values) / sum(r.weight for r in values)

        need = average(rows)
        trend = "not_enough_data"
        if len(rows) >= 4 and all(r.assessed_on for r in rows):
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
            "undated_observations": sum(r.assessed_on is None for r in rows),
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

    if value is not None and value > local_day(child):
        raise HTTPException(422, "Eine erhaltene Note kann nicht in der Zukunft liegen.")


def filtered_grades(db, child, *, subject=None, q="", kind="all", scale="all", date_precision="all",
                    start=None, end=None, school_year=None, semester=None, source="all", goal="all"):
    """One authorization-scoped selection for the list and explicit local export."""
    if start and end and start > end:
        raise HTTPException(422, "Der Beginn des Zeitraums muss vor seinem Ende liegen.")
    query = select(SchoolGrade).where(SchoolGrade.child_id == child.id)
    pdf_source = select(GradeSourceSlot.id).where(GradeSourceSlot.child_id == child.id,
        GradeSourceSlot.grade_id == SchoolGrade.id).exists()
    if source != "all":
        query = query.where(pdf_source if source == "pdf" else ~pdf_source)
    if goal != "all":
        query = query.where(SchoolGrade.assignment_id.is_not(None) if goal == "linked" else SchoolGrade.assignment_id.is_(None))
    if subject:
        names = list(db.scalars(select(SchoolGrade.subject).where(SchoolGrade.child_id == child.id).distinct()))
        query = query.where(SchoolGrade.subject.in_([name for name in names if subject_key(name) == subject_key(subject)]))
    search = q.strip()
    if search:
        query = query.where(or_(*(func.lower(column).contains(search.lower(), autoescape=True)
                                  for column in (SchoolGrade.subject, SchoolGrade.topic, SchoolGrade.note))))
    if kind != "all":
        query = query.where(SchoolGrade.kind == kind)
    if scale != "all":
        query = query.where(SchoolGrade.scale == scale)
    if date_precision != "all":
        query = query.where(SchoolGrade.assessed_on.is_not(None) if date_precision == "day"
                            else SchoolGrade.assessed_on.is_(None))
    if start:
        query = query.where(SchoolGrade.assessed_on >= start.isoformat())
    if end:
        query = query.where(SchoolGrade.assessed_on <= end.isoformat())
    if school_year is not None:
        query = query.where(SchoolGrade.school_year_start == school_year)
    if semester is not None:
        query = query.where(SchoolGrade.semester == semester)
    return query


def ordered_grades(query, order):
    if order == "oldest":
        return query.order_by(SchoolGrade.assessed_on.asc().nulls_last(), SchoolGrade.created, SchoolGrade.id)
    if order == "newest":
        return query.order_by(SchoolGrade.assessed_on.desc().nulls_last(), SchoolGrade.created.desc(), SchoolGrade.id.desc())
    if order == "subject":
        return query.order_by(func.lower(SchoolGrade.subject), SchoolGrade.assessed_on.desc().nulls_last(), SchoolGrade.id)
    return query.order_by(SchoolGrade.assessed_on.desc(), SchoolGrade.created.desc(), SchoolGrade.id.desc())


def selected_summary(db, query):
    selected = query.subquery()
    rows = db.execute(select(selected.c.subject, selected.c.scale, func.count(),
        func.sum(selected.c.value * selected.c.weight), func.sum(selected.c.weight))
        .group_by(selected.c.subject, selected.c.scale).order_by(selected.c.subject, selected.c.scale)).all()
    return [{"subject": subject, "scale": scale, "count": count,
             "weight_total": weight, "average": round(float(total) / weight, 2)}
            for subject, scale, count, total, weight in rows]


@router.get("/children/{child_id}/grades")
def list_grades(child_id: str, subject: str | None = Query(None, max_length=80),
                q: str = Query("", max_length=160),
                kind: Literal["all", "classwork", "test", "oral", "homework", "other"] = "all",
                scale: Literal["all", "grade_1_6", "points_0_15"] = "all",
                date_precision: Literal["all", "day", "semester"] = "all",
                start: date | None = None, end: date | None = None,
                school_year: int | None = Query(None, ge=2000, le=2200), semester: int | None = Query(None, ge=1, le=2),
                order: Literal["default", "oldest", "newest", "subject"] = "default",
                source: Literal["all", "pdf", "manual"] = "all", goal: Literal["all", "linked", "none"] = "all",
                page: int = Query(1, ge=1, le=1000000), page_size: int = Query(20, ge=1, le=50),
                p=Depends(parent), db=Depends(get_db)):
    from .learning import local_day
    from .library import bounds

    child = child_access(db, p, child_id)
    names = sorted(set(child.subjects) | set(db.scalars(select(SchoolGrade.subject).where(
        SchoolGrade.child_id == child.id).distinct())), key=lambda name: (name.casefold(), name))
    subjects = {}
    for name in names:
        key = subject_key(name)
        subjects.setdefault(key, "Mathematik" if key == "mathematik" else name)
    query = filtered_grades(db, child, subject=subject, q=q, kind=kind, scale=scale,
        date_precision=date_precision, start=start, end=end, school_year=school_year, semester=semester, source=source, goal=goal)
    count = db.scalar(select(func.count()).select_from(query.subquery()))
    pagination = bounds(count, page, page_size)
    rows = list(db.scalars(ordered_grades(query, order).offset((pagination["page"] - 1) * page_size).limit(page_size)))
    source_slots = {slot.grade_id: slot for slot in db.scalars(select(GradeSourceSlot).where(
        GradeSourceSlot.child_id == child.id, GradeSourceSlot.grade_id.in_([row.id for row in rows])))}
    items = []
    for row in rows:
        slot = source_slots.get(row.id)
        provenance = {"kind": "pdf" if slot else "without_pdf"}
        if slot:
            provenance.update({"school_year_start": slot.school_year_start, "last_pdf_value": slot.last_value})
        items.append(grade_data(row) | {"provenance": provenance})
    options = set(subjects.values()) | ({subject} if subject is not None else set())
    years = list(db.scalars(select(SchoolGrade.school_year_start).where(SchoolGrade.child_id == child.id,
        SchoolGrade.school_year_start.is_not(None)).distinct().order_by(SchoolGrade.school_year_start.desc())))
    return {"child_id": child.id, "items": items, "pagination": pagination,
            "today": local_day(child).isoformat(), "school_years": years,
            "selected_summary": selected_summary(db, query),
            "child_name": db.get(User, child.user_id).display_name,
            "can_manage": family_access(db, p, child.family_id)[1].permission != "view",
            "planning_enabled": child.grade_planning_enabled,
            "subjects": sorted(options, key=lambda name: (name.casefold(), name)),
            "focus": focus_summary(db, child),
            "filters": {"q": q.strip(), "kind": kind, "scale": scale, "date_precision": date_precision,
                "start": start, "end": end, "school_year": school_year, "semester": semester, "order": order, "source": source, "goal": goal},
            "notice": "Der Schnitt gilt nur für diese Einträge, nicht als Zeugnisnote. Im Plan zählen bis zu fünf datierte Noten je Fach aus 90 Tagen sowie undatierte PDF-Noten des aktuellen Schuljahres. Ohne Einzeldaten wird kein zeitlicher Trend behauptet. Zeitziele und Elternaufträge bleiben erhalten."}


def csv_cell(value):
    """Keep user text literal in spreadsheet programs, including leading whitespace."""
    value = str(value or "")
    return "'" + value if value.startswith(("\t", "\r", "\n")) or re.match(r"^\s*[=+@-]", value) else value


@router.get("/children/{child_id}/grades-export.csv")
def export_grades(child_id: str, subject: str | None = Query(None, max_length=80),
                q: str = Query("", max_length=160),
                kind: Literal["all", "classwork", "test", "oral", "homework", "other"] = "all",
                scale: Literal["all", "grade_1_6", "points_0_15"] = "all",
                date_precision: Literal["all", "day", "semester"] = "all",
                start: date | None = None, end: date | None = None,
                school_year: int | None = Query(None, ge=2000, le=2200), semester: int | None = Query(None, ge=1, le=2),
                order: Literal["default", "oldest", "newest", "subject"] = "default",
                source: Literal["all", "pdf", "manual"] = "all", goal: Literal["all", "linked", "none"] = "all",
                p=Depends(parent), db=Depends(get_db)):
    child = child_access(db, p, child_id)
    query = filtered_grades(db, child, subject=subject, q=q, kind=kind, scale=scale,
        date_precision=date_precision, start=start, end=end, school_year=school_year, semester=semester, source=source, goal=goal)
    rows = list(db.scalars(ordered_grades(query, order).limit(10001)))
    if len(rows) > 10000:
        raise HTTPException(422, "Bitte den Zeitraum oder das Fach eingrenzen. Ein Export umfasst höchstens 10.000 Noten.")
    output = io.StringIO(newline="")
    writer = csv.writer(output, delimiter=";")
    writer.writerow(["Fach", "Thema", "Leistungsart", "Notensystem", "Wert", "Gewichtung", "Einzeldatum", "Schuljahr Beginn", "Halbjahr", "Notiz"])
    for row in rows:
        writer.writerow([csv_cell(row.subject), csv_cell(row.topic), row.kind, row.scale, str(row.value),
            row.weight, row.assessed_on or "", row.school_year_start or "", row.semester or "", csv_cell(row.note)])
    return Response(content="\ufeff" + output.getvalue(), media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": 'attachment; filename="schulpilot-noten.csv"', "Cache-Control": "private, no-store"})


@router.post("/children/{child_id}/grades", status_code=201)
def create_grade(child_id: str, data: GradeInput, idempotency_key: str | None = Header(None), p=Depends(parent), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=True)
    valid_date(child, data.assessed_on)
    digest = hashlib.sha256(json.dumps(data.model_dump(mode="json", exclude_none=True) | {"value": format(data.value, ".2f")}, sort_keys=True).encode()).hexdigest()
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
    row = SchoolGrade(child_id=child.id, **data.model_dump(exclude={"assessed_on"}), assessed_on=data.assessed_on.isoformat() if data.assessed_on else None,
                      request_key=idempotency_key, request_digest=digest if idempotency_key else None)
    db.add(row)
    db.flush()
    audit(db, p.user.id, "grade.create", row.id)
    db.commit()
    return grade_data(row)


@router.put("/children/{child_id}/grades/{grade_id}")
def update_grade(child_id: str, grade_id: str, data: GradeUpdate,
                 capabilities: str | None = Header(None, alias="X-Schulpilot-Capabilities"), p=Depends(parent), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=True)
    valid_date(child, data.assessed_on)
    row = owned_grade(db, child, grade_id, lock=True)
    if row.assessed_on is None and "grade-pdf-v1" not in (capabilities or "").split(","):
        raise HTTPException(409, "Bitte die App aktualisieren, um eine PDF-Note ohne Einzeldatum zu bearbeiten.")
    if row.revision != data.revision:
        raise HTTPException(409, "Die Note wurde inzwischen geändert. Bitte neu laden.")
    for key, value in data.model_dump(exclude={"revision", "assessed_on"}).items():
        setattr(row, key, value)
    row.assessed_on, row.updated, row.revision = data.assessed_on.isoformat() if data.assessed_on else None, int(now()), row.revision + 1
    audit(db, p.user.id, "grade.update", row.id)
    db.commit()
    return grade_data(row)


@router.delete("/children/{child_id}/grades/{grade_id}")
def delete_grade(child_id: str, grade_id: str, revision: int | None = Query(None, ge=1), p=Depends(parent), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=True)
    row = owned_grade(db, child, grade_id, lock=True)
    if revision is not None and revision != row.revision:
        raise HTTPException(409, "Diese Note wurde inzwischen geändert. Bitte zuerst neu laden.")
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
    if data.revision is not None and data.revision != row.revision:
        raise HTTPException(409, "Diese Note wurde inzwischen geändert. Bitte zuerst neu laden.")
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
