"""Parent topic planning on existing assignments and generation jobs."""

from typing import Literal

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from sqlalchemy import func, or_, select
from sqlalchemy.orm import load_only

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
                    p=Depends(parent), db=Depends(get_db)):
    child = child_access(db, p, child_id)
    query = select(Material).options(load_only(Material.id, Material.child_id, Material.subject, Material.topic,
        Material.title, Material.confirmed, Material.created, Material.revision, Material.homework_state)).where(
            Material.child_id == child.id, Material.purpose == "homework")
    query = text_filter(query, q, Material.subject, Material.topic, Material.title)
    if subject is not None:
        query = query.where(Material.subject == subject)
    marked = (Material.homework_state["source_revision"].as_integer() == Material.revision) & (
        func.coalesce(func.json_array_length(Material.homework_state["done"]), 0) > 0)
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
        query = query.where((Material.created < old.created) | ((Material.created == old.created) & (Material.id < old.id)))
    rows = list(db.scalars(query.order_by(Material.created.desc(), Material.id.desc()).limit(21)))
    ids = [m.id for m in rows[:20]]
    analyses = list(db.scalars(select(TutorTurn).where(TutorTurn.child_id == child.id,
        TutorTurn.material_id.in_(ids), TutorTurn.status == "ready", TutorTurn.homework_context["action"].as_string() == "analyze"))) if ids else []
    cards = []
    for m in rows[:20]:
        current = [t for t in analyses if t.material_id == m.id and any(r["id"] == m.id and r["revision"] == m.revision for r in t.source_revisions)]
        analysis = max(current, key=lambda t: t.homework_context.get("sequence", 0), default=None)
        tasks = (analysis.reply or {}).get("tasks", []) if analysis else []
        valid = {t["id"] for t in tasks}
        saved = m.homework_state or {}
        done = set(saved.get("done", [])) & valid if saved.get("source_revision") == m.revision and analysis and saved.get("analysis_id") == analysis.id else set()
        cards.append({"id": m.id, "subject": m.subject, "topic": m.topic, "title": m.title,
            "created": m.created, "confirmed": m.confirmed, "task_count": len(tasks), "marked_done": len(done),
            "more_tasks": bool(analysis and analysis.reply.get("more_tasks")), "completion_source": "child_checklist",
            "tasks": [{"title": t["title"], "marked": t["id"] in done} for t in tasks]})
    return {"child_name": db.get(User, child.user_id).display_name, "photos": cards, "total": count,
            "subjects": subject_options(db, Material, child.id, Material.purpose == "homework"),
            "filters": {"q": q.strip(), "subject": subject, "state": state},
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
         source: Literal["all", "notebook", "manual", "changed"] = "all",
         obligation: Literal["all", "mandatory", "voluntary"] = "all",
         timing: Literal["all", "today", "past", "future", "undated"] = "all",
         p=Depends(parent), db=Depends(get_db)):
    from .families import child_data
    from .learning import assignment_data, plan

    child = child_access(db, p, child_id)
    query = select(Assignment).where(Assignment.child_id == child.id)
    query = text_filter(query, q, Assignment.subject, Assignment.topic, Assignment.note)
    if subject is not None:
        query = query.where(Assignment.subject == subject)
    if source == "notebook":
        query = query.where(Assignment.material_id.is_not(None))
    elif source == "manual":
        query = query.where(Assignment.material_id.is_(None))
    elif source == "changed":
        query = query.where(Assignment.source_status == "needs_review")
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
    if not include_completed:
        query = query.where(Assignment.done.is_(False))
    count = db.scalar(select(func.count()).select_from(query.subquery()))
    pages = max(1, (count + 19) // 20)
    page = min(page, pages)
    assignments = list(db.scalars(query.order_by(Assignment.mandatory.desc(), Assignment.created.desc(), Assignment.id)
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

    return {"child": child_data(db, child), "plan": plan(db, child), "topics": rows,
        "subjects": subject_options(db, Assignment, child.id),
        "filters": {"q": q.strip(), "subject": subject, "source": source, "obligation": obligation, "timing": timing},
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
