"""Parent topic planning on existing assignments and generation jobs."""

from datetime import date, datetime, time, timedelta
from typing import Literal
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from sqlalchemy import and_, case, func, or_, select
from sqlalchemy.orm import aliased, load_only

from .db import Assignment, Job, LearningMemory, LearningUnit, Material, Membership, TutorTurn, UnitSource, User, get_db
from .parent_insights import lock_parent
from .security import child_access, parent

router = APIRouter(tags=["Eltern-Lernplan"])


def text_filter(query, text, *columns):
    """Bounded literal search: percent/underscore are school text, not SQL wildcards."""
    text = text.strip()
    return query.where(or_(*(func.lower(column).contains(text.lower(), autoescape=True)
                            for column in columns))) if text else query


def subject_options(db, model, child_id, *conditions):
    return list(db.scalars(select(model.subject).where(model.child_id == child_id, *conditions,
        model.subject != "").distinct().order_by(model.subject).limit(200)))


@router.get("/children/{child_id}/homework-review")
def homework_review(child_id: str, state: Literal["all", "worked", "open", "review"] = "all",
                    cursor: str | None = Query(None, max_length=32), q: str = Query("", max_length=160),
                    subject: str | None = Query(None, max_length=160),
                    start: date | None = None, end: date | None = None,
                    order: Literal["newest", "oldest"] = "newest",
                    progress: Literal["any", "none", "partial", "complete", "unanalyzed"] = "any",
                    p=Depends(parent), db=Depends(get_db)):
    child = child_access(db, p, child_id)
    from .schemas import Preferences

    zone = ZoneInfo(Preferences(**child.preferences).timezone)
    if start and end and start > end:
        raise HTTPException(422, "Der Beginn des Zeitraums muss vor seinem Ende liegen.")
    # Exactly the same current single-source analysis as the visible card. At
    # most eight tasks and eight checklist IDs are allowed by the save schema.
    analysis = aliased(TutorTurn)
    latest = select(TutorTurn.id).where(TutorTurn.child_id == child.id, TutorTurn.material_id == Material.id,
        TutorTurn.status == "ready", TutorTurn.homework_context["action"].as_string() == "analyze",
        TutorTurn.source_revisions[0]["id"].as_string() == Material.id,
        TutorTurn.source_revisions[0]["revision"].as_integer() == Material.revision).order_by(
            TutorTurn.homework_context["sequence"].as_integer().desc(), TutorTurn.created.desc(), TutorTurn.id.desc()
        ).limit(1).correlate(Material).scalar_subquery()
    current_checklist = and_(Material.homework_state["source_revision"].as_integer() == Material.revision,
        Material.homework_state["analysis_id"].as_string() == analysis.id)
    valid_done = sum(case((and_(current_checklist,
        analysis.reply["tasks"][i]["id"].as_string().is_not(None),
        or_(*(Material.homework_state["done"][j].as_string() == analysis.reply["tasks"][i]["id"].as_string()
            for j in range(8)))), 1), else_=0) for i in range(8))
    task_count = func.coalesce(func.json_array_length(analysis.reply["tasks"]), 0)
    complete = and_(task_count > 0, valid_done == task_count, ~func.coalesce(analysis.reply["more_tasks"].as_boolean(), False))
    query = select(Material).outerjoin(analysis, analysis.id == latest).options(load_only(Material.id, Material.child_id, Material.subject, Material.topic,
        Material.title, Material.confirmed, Material.created, Material.revision, Material.homework_state)).where(
            Material.child_id == child.id, Material.purpose == "homework")
    query = text_filter(query, q, Material.subject, Material.topic, Material.title,
        *(analysis.reply["tasks"][i]["title"].as_string() for i in range(8)))
    if subject is not None:
        query = query.where(Material.subject == subject)
    marked = valid_done > 0
    if start or end:
        if start:
            query = query.where(Material.created >= int(datetime.combine(start, time.min, zone).timestamp()))
        if end:
            query = query.where(Material.created < int(datetime.combine(end + timedelta(days=1), time.min, zone).timestamp()))
    if progress == "none":
        query = query.where(valid_done == 0)
    elif progress == "partial":
        query = query.where(marked, ~complete)
    elif progress == "complete":
        query = query.where(complete)
    elif progress == "unanalyzed":
        query = query.where(analysis.id.is_(None))
    if state == "worked":
        query = query.where(marked)
    elif state == "open":
        query = query.where(~func.coalesce(marked, False))
    elif state == "review":
        query = query.where(Material.confirmed.is_(False))
    count = db.scalar(select(func.count()).select_from(query.subquery()))
    if cursor:
        old = db.get(Material, cursor)
        if not old or old.child_id != child.id or old.purpose != "homework":
            raise HTTPException(404, "Foto nicht gefunden.")
        query = query.where((Material.created < old.created) | ((Material.created == old.created) & (Material.id < old.id))) if order == "newest" else query.where(
            (Material.created > old.created) | ((Material.created == old.created) & (Material.id > old.id)))
    ordering = (Material.created.desc(), Material.id.desc()) if order == "newest" else (Material.created, Material.id)
    rows = list(db.scalars(query.order_by(*ordering).limit(21)))
    ids = [m.id for m in rows[:20]]
    analyses = list(db.scalars(select(TutorTurn).where(TutorTurn.child_id == child.id,
        TutorTurn.material_id.in_(ids), TutorTurn.status == "ready", TutorTurn.homework_context["action"].as_string() == "analyze"))) if ids else []
    cards = []
    for m in rows[:20]:
        current = [t for t in analyses if t.material_id == m.id and any(r["id"] == m.id and r["revision"] == m.revision for r in t.source_revisions)]
        analysis = max(current, key=lambda t: (t.homework_context.get("sequence", 0), t.created, t.id), default=None)
        tasks = (analysis.reply or {}).get("tasks", []) if analysis else []
        valid = {t["id"] for t in tasks}
        saved = m.homework_state or {}
        done = set(saved.get("done", [])) & valid if saved.get("source_revision") == m.revision and analysis and saved.get("analysis_id") == analysis.id else set()
        cards.append({"id": m.id, "subject": m.subject, "topic": m.topic, "title": m.title,
            "created": m.created, "created_local": datetime.fromtimestamp(m.created, zone).isoformat(), "confirmed": m.confirmed, "task_count": len(tasks), "marked_done": len(done),
            "more_tasks": bool(analysis and analysis.reply.get("more_tasks")), "completion_source": "child_checklist",
            "tasks": [{"title": t["title"], "marked": t["id"] in done} for t in tasks]})
    collection = select(Material).where(Material.child_id == child.id, Material.purpose == "homework").subquery()
    collection_totals = {"all": db.scalar(select(func.count()).select_from(collection)),
        "needs_review": db.scalar(select(func.count()).select_from(collection).where(collection.c.confirmed.is_(False)))}
    return {"child_name": db.get(User, child.user_id).display_name, "timezone": zone.key, "photos": cards, "total": count,
            "collection_totals": collection_totals,
            "subjects": subject_options(db, Material, child.id, Material.purpose == "homework"),
            "filters": {"q": q.strip(), "subject": subject, "state": state, "start": start, "end": end, "order": order, "progress": progress},
            "next_cursor": rows[19].id if len(rows) > 20 else None,
            "notice": "Häkchen zeigen, was dein Kind als bearbeitet markiert hat. Sie beweisen keine richtige Lösung. Gespeicherte Fragen und Hilfen kannst du im Detail ansehen."}


def assignment_values(db, child, data, existing=None):
    values = data.model_dump(mode="json", exclude={"revision"})
    unit_id = values.get("source_unit_id")
    if existing and "source_unit_id" not in data.model_fields_set:
        unit_id = existing.source_unit_id
        values["source_unit_id"] = unit_id
    refs = []
    if existing and values["material_id"] == existing.material_id and unit_id == existing.source_unit_id:
        for ref in existing.source_revisions or []:
            m = db.get(Material, ref["id"])
            if not m or m.child_id != child.id or not m.confirmed:
                raise HTTPException(409, "Bitte die Auftragsquellen zuerst prüfen.")
            refs.append({"id": m.id, "revision": m.revision})
    if unit_id and (not existing or unit_id != existing.source_unit_id):
        unit = db.get(LearningUnit, unit_id)
        if not unit or unit.child_id != child.id:
            raise HTTPException(404, "Übungsthema nicht gefunden.")
        refs = [{"id": r.material_id, "revision": r.revision} for r in db.scalars(
            select(UnitSource).where(UnitSource.unit_id == unit.id).order_by(UnitSource.material_id))]
        if not refs and unit.material_id:
            source = db.get(Material, unit.material_id)
            if source:
                refs = [{"id": source.id, "revision": source.revision}]
        for ref in refs:
            m = db.get(Material, ref["id"])
            if not m or m.child_id != child.id or not m.confirmed or m.revision != ref["revision"]:
                raise HTTPException(409, "Bitte die Quellen dieser Übung zuerst prüfen oder eine aktuelle Heftseite auswählen.")
        if refs:
            if values["material_id"] and values["material_id"] not in {ref["id"] for ref in refs}:
                raise HTTPException(422, "Die ausgewählte Heftseite gehört nicht zu dieser Übung.")
            values["material_id"] = values["material_id"] or refs[0]["id"]
    if values["material_id"]:
        m = db.get(Material, values["material_id"])
        if not m or m.child_id != child.id:
            raise HTTPException(404, "Material nicht gefunden.")
        if not m.confirmed:
            raise HTTPException(409, "Bitte die ausgewählte Heftseite zuerst bestätigen.")
        if not refs:
            sources = list(db.scalars(select(Material).where(Material.child_id == child.id,
                Material.school_day_id == m.school_day_id, Material.confirmed.is_(True))
                .order_by(Material.page_number, Material.id))) if m.school_day_id else [m]
            sources = [source for source in sources if source.subject.casefold() == m.subject.casefold()]
            if sum(len(source.content or "") for source in sources) > 60_000:
                raise HTTPException(422, "Die zusammengehörigen Seiten sind für eine Einheit zu umfangreich.")
            refs = [{"id": source.id, "revision": source.revision} for source in sources]
    from .subject_registry import resolve

    subject = resolve(db, values["subject"], child.family_id)
    values["subject_id"] = subject.id if subject else None
    values["source_revisions"] = refs
    return values


@router.get("/children/{child_id}/learning-plan")
def view(child_id: str, page: int = Query(1, ge=1, le=1000000), include_completed: bool = False,
         q: str = Query("", max_length=160), subject: str | None = Query(None, max_length=160),
         source: Literal["all", "notebook", "manual", "changed", "confirmed"] = "all",
         obligation: Literal["all", "mandatory", "voluntary"] = "all",
         timing: Literal["all", "today", "past", "future", "undated"] = "all",
         completion: Literal["open", "done", "all"] | None = None,
         order: Literal["default", "due", "oldest", "subject"] = "default",
         assignment_id: str | None = Query(None, min_length=1, max_length=32),
         rounds: Literal["all", "open", "none", "finished"] = "all",
         kind: Literal["all", "parent", "exam", "homework", "interest"] = "all",
         start: Literal["all", "available", "later"] = "all",
         p=Depends(parent), db=Depends(get_db)):
    from .families import child_data
    from .learning import assignment_data, plan

    child = child_access(db, p, child_id)
    if assignment_id:
        exact = db.get(Assignment, assignment_id)
        if not exact or exact.child_id != child.id:
            raise HTTPException(404, "Lernauftrag nicht gefunden.")
    query = select(Assignment).where(Assignment.child_id == child.id)
    if assignment_id:
        query = query.where(Assignment.id == assignment_id)
    if kind != "all":
        query = query.where(func.coalesce(Assignment.origin_kind, Assignment.kind) == kind)
    unit = select(LearningUnit.id).where(LearningUnit.child_id == child.id, LearningUnit.assignment_id == Assignment.id)
    if rounds == "none":
        query = query.where(~unit.exists())
    elif rounds == "open":
        query = query.where(unit.where(LearningUnit.goal_revision == Assignment.revision, LearningUnit.status != "completed").exists())
    elif rounds == "finished":
        query = query.where(unit.where(LearningUnit.status == "completed").exists())
    query = text_filter(query, q, Assignment.subject, Assignment.topic, Assignment.note)
    if subject is not None:
        query = query.where(Assignment.subject == subject)
    if source == "notebook":
        query = query.where(Assignment.material_id.is_not(None))
    elif source == "manual":
        query = query.where(Assignment.material_id.is_(None))
    elif source == "changed":
        query = query.where(Assignment.source_status == "needs_review")
    elif source == "confirmed":
        query = query.where(Assignment.source_status == "confirmed")
    if obligation != "all":
        query = query.where(Assignment.mandatory.is_(obligation == "mandatory"))
    from .learning import local_day

    today = local_day(child).isoformat()
    if timing == "today":
        query = query.where(Assignment.due == today)
    elif timing == "past":
        query = query.where(Assignment.due < today)
    elif timing == "future":
        query = query.where(Assignment.due > today)
    elif timing == "undated":
        query = query.where(Assignment.due.is_(None))
    if start == "available":
        query = query.where(or_(Assignment.scheduled_for.is_(None), Assignment.scheduled_for <= today))
    elif start == "later":
        query = query.where(Assignment.scheduled_for > today)
    if completion == "open" or completion is None and not include_completed:
        query = query.where(Assignment.done.is_(False))
    elif completion == "done":
        query = query.where(Assignment.done.is_(True))
    count = db.scalar(select(func.count()).select_from(query.subquery()))
    pages = max(1, (count + 19) // 20)
    page = min(page, pages)
    ordering = {
        "default": (Assignment.mandatory.desc(), Assignment.created.desc(), Assignment.id),
        "due": (Assignment.due.asc().nulls_last(), Assignment.mandatory.desc(), Assignment.id),
        "oldest": (Assignment.created, Assignment.id),
        "subject": (func.lower(Assignment.subject), func.lower(Assignment.topic), Assignment.id),
    }[order]
    assignments = list(db.scalars(query.order_by(*ordering)
        .offset((page - 1) * 20).limit(20)))
    rows = []
    round_counts = dict(db.execute(select(LearningUnit.assignment_id, func.count()).where(
        LearningUnit.child_id == child.id, LearningUnit.assignment_id.in_([a.id for a in assignments]))
        .group_by(LearningUnit.assignment_id)).all()) if assignments else {}
    for a in assignments:
        units = list(db.scalars(select(LearningUnit).where(LearningUnit.child_id == child.id,
            LearningUnit.assignment_id == a.id).order_by(LearningUnit.created.desc(), LearningUnit.id).limit(10)))
        # The bounded history is a preview, not the source of truth for an open
        # round. An older interrupted round must remain reachable even after
        # many newer completed rounds.
        active = db.scalar(select(LearningUnit).where(LearningUnit.child_id == child.id,
            LearningUnit.assignment_id == a.id, LearningUnit.goal_revision == a.revision,
            LearningUnit.status != "completed").order_by(LearningUnit.created, LearningUnit.id).limit(1))
        pending = db.scalar(select(Job).where(Job.child_id == child.id, Job.kind == "unit",
            Job.payload["assignment_id"].as_string() == a.id, Job.status.in_(["queued", "running"]))
            .order_by(Job.created.desc()).limit(1))
        rows.append({**assignment_data(a), "source_kind": "notebook" if a.material_id else "parent_topic",
            "recent_unit_count": round_counts.get(a.id, 0),
            "available_unit": {"id": active.id, "status": active.status} if active else None,
            "preparation": {"id": pending.id, "status": pending.status} if pending else None,
            "recent_units": [{"id": u.id, "status": u.status, "topic": u.topic, "revision": u.goal_revision} for u in units]})
    active_units = list(db.scalars(select(LearningUnit).join(LearningMemory, LearningMemory.unit_id == LearningUnit.id)
        .where(LearningUnit.child_id == child.id, LearningUnit.status.in_(["active", "paused", "ready"]),
            LearningMemory.working["instructional_plan"]["cursor"].as_integer().is_not(None))
        .order_by(LearningUnit.created.desc(), LearningUnit.id.desc()).limit(20)))
    plans = []
    for unit in active_units:
        memory = db.get(LearningMemory, unit.id)
        saved = (memory.working or {}).get("instructional_plan") if memory else None
        if saved:
            plans.append({"unit_id": unit.id, "subject": unit.subject, "topic": unit.topic,
                          "status": unit.status, "cursor": saved["cursor"], "steps": saved["steps"],
                          "strategy_version": saved.get("strategy_version"), "source": "saved_ai_plan"})
    from .parent_insights import apply_guidance

    saved_plan = plan(db, child)
    conflict_ids = [c["id"] for c in saved_plan.get("conflicts", [])]
    assignment_ids = set(db.scalars(select(Assignment.id).where(Assignment.child_id == child.id,
        Assignment.id.in_(conflict_ids)))) if conflict_ids else set()
    unit_goals = dict(db.execute(select(LearningUnit.id, Assignment.id).join(Assignment,
        LearningUnit.assignment_id == Assignment.id).where(LearningUnit.child_id == child.id,
        Assignment.child_id == child.id, LearningUnit.id.in_(conflict_ids))).all()) if conflict_ids else {}
    for conflict in saved_plan.get("conflicts", []):
        conflict["assignment_id"] = conflict["id"] if conflict["id"] in assignment_ids else unit_goals.get(conflict["id"])
    base = select(Assignment).where(Assignment.child_id == child.id).subquery()
    totals = {"all": db.scalar(select(func.count()).select_from(base)),
        "open": db.scalar(select(func.count()).select_from(base).where(base.c.done.is_(False))),
        "done": db.scalar(select(func.count()).select_from(base).where(base.c.done.is_(True))),
        "overdue": db.scalar(select(func.count()).select_from(base).where(base.c.done.is_(False), base.c.due < today))}
    return {"child": child_data(db, child), "plan": saved_plan, "topics": rows, "assignment_totals": totals,
        "subjects": subject_options(db, Assignment, child.id),
        "filters": {"q": q.strip(), "subject": subject, "source": source, "obligation": obligation, "timing": timing,
            "completion": completion or ("all" if include_completed else "open"), "order": order,
            "assignment_id": assignment_id, "rounds": rounds, "kind": kind, "start": start},
        "ai_guidance": apply_guidance(db, child, []),
        "pagination": {"page": page, "pages": pages, "total": count}, "instructional_plans": plans,
        "recent_round_topics": [{"id": u.id, "subject": u.subject, "topic": u.topic, "material_id": u.material_id}
            for u in db.scalars(select(LearningUnit).where(LearningUnit.child_id == child.id)
                .order_by(LearningUnit.created.desc(), LearningUnit.id).limit(20))],
        "can_manage": db.scalar(select(Membership.permission).where(Membership.user_id == p.user.id,
            Membership.family_id == child.family_id)) != "view"}


@router.post("/children/{child_id}/assignments/{assignment_id}/prepare", status_code=202)
def prepare(child_id: str, assignment_id: str, key: str = Header(alias="Idempotency-Key"),
            p=Depends(parent), db=Depends(get_db)):
    from . import schemas
    from .materials import create_unit

    child = lock_parent(db, p, child_id)
    if not 1 <= len(key) <= 80:
        raise HTTPException(422, "Ein eindeutiger Anfrageschlüssel ist erforderlich.")
    from .db import Family

    if db.get(Family, child.family_id).synthetic:
        raise HTTPException(409, "Eigene KI-Themen werden in einem regulären Familienkonto vorbereitet.")
    a = db.get(Assignment, assignment_id)
    if not a or a.child_id != child.id:
        raise HTTPException(404, "Lernauftrag nicht gefunden.")
    previous = db.scalar(select(Job).where(Job.idempotency == p.user.id + ":" + key))
    if previous:
        if previous.child_id != child.id or previous.kind != "unit" or previous.payload.get("assignment_id") != a.id:
            raise HTTPException(409, "Dieser Schlüssel gehört zu einem anderen Auftrag.")
        return {"kind": "job", "id": previous.id, "status": previous.status}
    existing = db.scalar(select(LearningUnit).where(LearningUnit.child_id == child.id, LearningUnit.assignment_id == a.id,
        LearningUnit.goal_revision == a.revision, LearningUnit.status != "completed").order_by(LearningUnit.created).limit(1))
    if existing:
        return {"kind": "unit", "id": existing.id, "status": existing.status}
    if a.done:
        raise HTTPException(409, "Dieses Lernziel ist bereits abgeschlossen. Lege bewusst einen neuen Auftrag an.")
    result = create_unit(child_id, schemas.UnitCreate(assignment_id=a.id), idempotency=key, p=p, db=db)
    return {"kind": "job", **result}


def deadline_selection(db, child, start, end, obligation):
    from .learning import local_day

    start = start or local_day(child)
    end = end or start + timedelta(days=29)
    if start > end or (end - start).days > 365 or start.year < 2000 or end.year > 2200:
        raise HTTPException(422, "Wähle einen gültigen Zeitraum von höchstens 366 Tagen zwischen 2000 und 2200.")
    query = select(Assignment).where(Assignment.child_id == child.id, Assignment.done.is_(False),
        Assignment.due >= start.isoformat(), Assignment.due <= end.isoformat())
    if obligation != "all":
        query = query.where(Assignment.mandatory.is_(obligation == "mandatory"))
    return start, end, query.order_by(Assignment.due, Assignment.id)


@router.get("/children/{child_id}/learning-deadlines")
def deadlines(child_id: str, start: date | None = None, end: date | None = None,
              obligation: Literal["all", "mandatory", "voluntary"] = "all",
              p=Depends(parent), db=Depends(get_db)):
    from .learning import local_day

    child = child_access(db, p, child_id)
    start, end, query = deadline_selection(db, child, start, end, obligation)
    count = db.scalar(select(func.count()).select_from(query.order_by(None).subquery()))
    return {"child_name": db.get(User, child.user_id).display_name, "today": local_day(child).isoformat(),
        "start": start, "end": end, "obligation": obligation, "total": count, "truncated": count > 200,
        "items": [{"id": row.id, "subject": row.subject, "topic": row.topic, "due": row.due,
            "scheduled_for": row.scheduled_for, "mandatory": row.mandatory, "source_status": row.source_status}
            for row in db.scalars(query.limit(200))],
        "notice": "Ausschließlich gespeicherte offene Elterntermine. Ein KI-Wochenvorschlag ist kein zusätzlicher Termin; abgehakte Ziele beweisen keine Beherrschung."}


def calendar_text(value):
    return str(value).replace("\\", "\\\\").replace("\r\n", "\n").replace("\r", "\n").replace("\n", "\\n").replace(";", "\\;").replace(",", "\\,")


def fold_calendar(lines):
    """RFC5545 content lines, at most75 UTF-8 octets, no split code points."""
    output = []
    for line in lines:
        current = ""
        for character in line:
            if len((current + character).encode("utf-8")) > 75:
                output.append(current)
                current = " "
            current += character
        output.append(current)
    return "\r\n".join(output) + "\r\n"


@router.get("/children/{child_id}/learning-deadlines.ics")
def export_deadlines(child_id: str, start: date | None = None, end: date | None = None,
                     obligation: Literal["all", "mandatory", "voluntary"] = "all",
                     p=Depends(parent), db=Depends(get_db)):
    from datetime import timezone

    from fastapi.responses import Response

    from .db import now

    child = child_access(db, p, child_id)
    _, _, query = deadline_selection(db, child, start, end, obligation)
    rows = list(db.scalars(query.limit(1001)))
    if len(rows) > 1000:
        raise HTTPException(422, "Bitte den Kalenderzeitraum eingrenzen. Eine Datei enthält höchstens 1.000 Termine.")
    stamp = datetime.fromtimestamp(now(), timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Schulpilot//Private Elterntermine//DE", "CALSCALE:GREGORIAN"]
    for row in rows:
        due = date.fromisoformat(row.due)
        label = "Verbindlicher Elternauftrag" if row.mandatory else "Freiwilliges Thema"
        if row.source_status != "confirmed":
            label += ". Geänderte Quelle zuerst prüfen"
        lines.extend(["BEGIN:VEVENT", "UID:" + row.id + "@schulpilot", "DTSTAMP:" + stamp,
            "DTSTART;VALUE=DATE:" + due.strftime("%Y%m%d"),
            "DTEND;VALUE=DATE:" + (due + timedelta(days=1)).strftime("%Y%m%d"),
            "SUMMARY:" + calendar_text(row.subject + ": " + row.topic),
            "DESCRIPTION:" + calendar_text(label + ". Statische private Kopie, keine automatische Synchronisierung mit SchuleSchlau."),
            "TRANSP:TRANSPARENT", "END:VEVENT"])
    lines.append("END:VCALENDAR")
    return Response(fold_calendar(lines), media_type="text/calendar; charset=utf-8",
        headers={"Content-Disposition": 'attachment; filename="schulpilot-termine.ics"', "Cache-Control": "private, no-store"})
