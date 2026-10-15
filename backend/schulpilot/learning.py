import unicodedata
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, or_, select, update
from sqlalchemy.orm import defer, load_only

from . import schemas as s
from .daily_planner import completed_portions, distribute, period_starts
from .db import (
    Activity,
    Assignment,
    Attempt,
    Child,
    Family,
    LearningUnit,
    Mastery,
    Material,
    Message,
    SchoolDay,
    UnitCoaching,
    UnitSource,
    User,
    get_db,
    now,
)
from .families import child_data
from .security import authenticated, child_access, child_user, own_child, parent, rate_limit

router = APIRouter(tags=["Lernen und Planung"])


def local_day(child):
    zone = s.Preferences(**child.preferences).timezone
    return datetime.now(ZoneInfo(zone)).date()


def record(db, child_id, kind, detail=None, unit_id=None):
    db.add(Activity(child_id=child_id, kind=kind, detail=detail or {}, unit_id=unit_id))


def material_data(material):
    return {
        k: getattr(material, k)
        for k in (
            "id",
            "child_id",
            "school_day_id",
            "page_number",
            "quality_warnings",
            "legibility",
            "title",
            "status",
            "subject",
            "topic",
            "content",
            "uncertainties",
            "homework",
            "confirmed",
            "synthetic",
            "fixture_id",
            "extraction_provider",
            "extraction_model",
            "created",
        )
    }


def assignment_data(assignment):
    return {
        k: getattr(assignment, k)
        for k in ("id", "kind", "subject", "topic", "note", "due", "scheduled_for", "mandatory", "done", "material_id")
    }


def mastery_data(m):
    return {
        "id": m.id,
        "subject": m.subject,
        "topic": m.topic,
        "independent_units": m.independent,
        "assisted_units": m.assisted,
        "difficult_units": m.difficulties,
        "uncertain_units": m.uncertain_units,
        "later_review_successes": m.review_successes,
        "next_review": m.next_review,
        "last_practiced": m.last_practiced,
        "description": (
            "Bei mehreren späteren Wiederholungen selbstständig gelöst"
            if m.review_successes >= 2
            else "Weiter beobachten und gezielt wiederholen"
        ),
    }


def unit_data(db, unit, include_answers=False, *, include_progress=True):
    from . import coaching

    attempts = list(db.scalars(select(Attempt).where(Attempt.unit_id == unit.id).order_by(Attempt.created, Attempt.id)))
    events = list(db.scalars(select(Activity).where(Activity.unit_id == unit.id)))
    questions = []
    for q in unit.questions:
        value = dict(q)
        if not include_answers:
            value.pop("answer", None)
            value.pop("accepted", None)
            value.pop("hints", None)
            value.pop("explanation", None)
            if q["type"] == "match":
                value["options"] = [pair.split("|")[0] for pair in q["options"]]
                value["choices"] = sorted(pair.split("|")[1] for pair in q["options"])
        value["attempts"] = [
            {"id": a.id, "answer": a.answer, "outcome": a.outcome, "assisted": a.assisted, "created": a.created}
            for a in attempts
            if a.question_id == q["id"]
        ]
        value["hints_used"] = len([e for e in events if e.kind == "hint" and e.detail.get("question_id") == q["id"]])
        if (
            unit.status == "completed"
            or len(value["attempts"]) >= 3
            or any(a["outcome"] in ("correct", "uncertain") for a in value["attempts"])
        ):
            value["feedback_explanation"] = q["explanation"]
        questions.append(value)
    return {
        "id": unit.id,
        "child_id": unit.child_id,
        "subject": unit.subject,
        "topic": unit.topic,
        "explanation": unit.explanation
        if include_answers or unit.round_kind not in coaching.CHECK_KINDS or unit.status == "completed"
        else "",
        "questions": questions,
        "status": unit.status,
        "synthetic": unit.synthetic,
        "active_seconds_approx": unit.active_seconds,
        "break_until": unit.break_until,
        "material_id": unit.material_id,
        "school_day_id": unit.school_day_id,
        "estimated_minutes": unit.estimated_minutes,
        "package_version": unit.package_version,
        "introduction_seen": unit.introduction_seen,
        "source_material_ids": list(db.scalars(select(UnitSource.material_id).where(UnitSource.unit_id == unit.id)))
        or ([unit.material_id] if unit.material_id else []),
        "assignment_id": unit.assignment_id,
        "review_of": unit.review_of,
        "learning_root_id": unit.learning_root_id,
        "followup_of": unit.followup_of,
        "round_kind": unit.round_kind,
        "not_before": unit.not_before,
        "coaching": coaching.view(db, unit),
        "learning_progress": coaching.progress(db, unit)
        if include_progress and (unit.status == "completed" or unit.learning_root_id)
        else None,
        "created": unit.created,
        "completed": unit.completed,
        "provider": unit.provider,
        "model": unit.model,
    }


def summary(db, child, days, *, learning_paths=None):
    from .coaching import paths

    current = datetime.now(ZoneInfo(s.Preferences(**child.preferences).timezone))
    since = int((current.replace(hour=0, minute=0, second=0, microsecond=0) - timedelta(days=days - 1)).timestamp())
    units = list(db.scalars(select(LearningUnit).where(LearningUnit.child_id == child.id)))
    recent = [u for u in units if u.completed and u.completed >= since]
    unit_ids = [u.id for u in units]
    attempts = list(db.scalars(select(Attempt).where(Attempt.unit_id.in_(unit_ids), Attempt.created >= since)))
    unresolved = list(
        db.scalars(
            select(Message).where(Message.child_id == child.id, Message.kind == "help", Message.resolved.is_(False))
        )
    )
    difficulties = list(db.scalars(select(Mastery).where(Mastery.child_id == child.id, Mastery.difficulties > 0)))
    hints = list(
        db.scalars(
            select(Activity).where(Activity.child_id == child.id, Activity.kind == "hint", Activity.created >= since)
        )
    )
    uncertain = sum(a.outcome == "uncertain" for a in attempts)
    topics = list(dict.fromkeys(f"{u.subject}: {u.topic}" for u in recent))
    coach_support = [
        p for p in (paths(db, child.id) if learning_paths is None else learning_paths) if p["needs_parent"]
    ]
    if unresolved:
        support = f"Ja – {len(unresolved)} offener Hilfewunsch. Bitte gemeinsam das Anliegen ansehen."
    elif coach_support:
        support = (
            "Bitte gemeinsam unterstützen bei: "
            + ", ".join(p["topic"] for p in coach_support[:3])
            + ". Die gespeicherte Lernbegleitung zeigt den Anlass."
        )
    elif uncertain:
        support = f"Bitte {uncertain} nicht sicher bewertbare Antwort(en) gemeinsam ansehen."
    elif any(a.outcome == "incorrect" for a in attempts):
        support = "Ein gemeinsamer Blick auf die zuletzt schwierigen Aufgaben ist sinnvoll."
    elif attempts:
        support = "Aktuell kein ausdrücklicher Hilfebedarf erfasst. Weitere Wiederholungen bleiben sinnvoll."
    else:
        support = "Noch keine Antworten im Zeitraum. Daraus lässt sich kein Verständnis ableiten."
    return {
        "period_days": days,
        "completed_units": len(recent),
        "started_units": sum(u.status in ("active", "paused") for u in units),
        "answer_count": len(attempts),
        "hints_used": len(hints),
        "uncertain_answers": uncertain,
        "active_minutes_approx": round(
            sum(
                e.detail.get("seconds", 0)
                for e in db.scalars(
                    select(Activity).where(
                        Activity.child_id == child.id, Activity.kind == "active_time", Activity.created >= since
                    )
                )
            )
            / 60,
            1,
        ),
        "topics": topics,
        "support": support,
        "help_requests": len(unresolved),
        "coaching_support_topics": [p["topic"] for p in coach_support],
        "recurring_difficulties": [m.topic for m in difficulties if m.difficulties >= 2],
        "notice": "Zeitmessung ist eine Näherung. Eine richtige Antwort beweist noch keine sichere Beherrschung.",
    }


def plan(db, child, *, learning_paths=None):
    from .coaching import paths

    prefs = s.Preferences(**child.preferences)
    today = local_day(child)
    units = list(
        db.scalars(
            select(LearningUnit)
            .options(defer(LearningUnit.questions), defer(LearningUnit.explanation))
            .where(LearningUnit.child_id == child.id)
            .order_by(LearningUnit.created)
        )
    )
    assignments = list(
        db.scalars(select(Assignment).where(Assignment.child_id == child.id, Assignment.done.is_(False)))
    )
    reviews = list(
        db.scalars(select(Mastery).where(Mastery.child_id == child.id, Mastery.next_review <= today.isoformat()))
    )
    start, week = period_starts(today, prefs.timezone)
    timed = list(
        db.scalars(
            select(Activity).where(
                Activity.child_id == child.id, Activity.kind == "active_time", Activity.created >= week
            )
        )
    )
    daily_seconds = sum(e.detail.get("seconds", 0) for e in timed if e.created >= start)
    weekly_seconds = sum(e.detail.get("seconds", 0) for e in timed)
    daily_used = (daily_seconds + 59) // 60
    weekly_used = (weekly_seconds + 59) // 60
    completed_daily, completed_weekly = completed_portions(units, prefs, start, week)
    daily_load, weekly_load = max(daily_used, completed_daily), max(weekly_used, completed_weekly)
    available = max(0, min(prefs.daily_minutes - daily_load, prefs.weekly_minutes - weekly_load))
    notices = []
    paused = bool(prefs.pause_until and today <= prefs.pause_until)
    free_day = today.weekday() not in prefs.weekdays
    if paused:
        notices.append(f"Lernpause bis {prefs.pause_until.isoformat()}. Offene Ziele bleiben erhalten.")
        available = 0
    elif free_day:
        notices.append("Heute ist ein lernfreier Tag. Neue Heftseiten kannst du trotzdem speichern.")
        available = 0
    if prefs.session_minutes > prefs.daily_minutes:
        notices.append("Die Einheit wird auf das Tagesziel gekürzt.")
    if len(prefs.weekdays) * prefs.daily_minutes < prefs.weekly_minutes:
        notices.append(
            "Das Wochenziel passt nicht in die gewählten Lerntage. Vorschlag: Wochenziel reduzieren oder einen weiteren Lerntag wählen."
        )
    days = list(db.scalars(select(SchoolDay).where(SchoolDay.child_id == child.id).order_by(SchoolDay.school_date)))
    source_dates = {d.id: d.school_date for d in days}
    practiced = {}
    for unit in units:
        if unit.completed and unit.school_day_id:
            practiced[unit.school_day_id] = max(practiced.get(unit.school_day_id, 0), unit.completed)
    chains = {
        block["unit_id"]: (f"{day.id}:{block.get('subject', '')}", index)
        for day in days
        for index, block in enumerate((day.learning_plan or {}).get("blocks", []))
        if block.get("unit_id")
    }
    units_by_id = {u.id: u for u in units}
    synthetic_family = db.get(Family, child.family_id).synthetic
    synthetic_days = set(
        db.scalars(
            select(Material.school_day_id).where(
                Material.child_id == child.id, Material.synthetic.is_(True), Material.school_day_id.is_not(None)
            )
        )
    )
    assignments_by_id = {a.id: a for a in assignments}
    minutes = min(prefs.session_minutes, max(5, available))
    candidates = []
    for unit in units:
        if unit.status != "completed":
            goal = assignments_by_id.get(unit.assignment_id)
            chain = chains.get(unit.id)
            candidates.append(
                {
                    "kind": "unit",
                    "id": unit.id,
                    "topic": unit.topic,
                    "subject": unit.subject,
                    "mandatory": bool(goal and goal.mandatory),
                    "status": unit.status,
                    "estimated_minutes": max(1, (unit.estimated_minutes or minutes) - unit.active_seconds // 60),
                    "scheduled_for": goal.scheduled_for if goal else None,
                    "due": goal.due if goal else None,
                    "not_before": unit.not_before,
                    "source_date": source_dates.get(unit.school_day_id),
                    "_chain": chain[0] if chain else None,
                    "_sequence": chain[1] if chain else 0,
                }
            )
    for a in sorted(assignments, key=lambda a: (not a.mandatory, a.due or "9999", a.created)):
        if any(u.assignment_id == a.id and u.status != "completed" for u in units):
            continue
        candidates.append(
            {
                "kind": "assignment",
                "id": a.id,
                "topic": a.topic,
                "subject": a.subject,
                "mandatory": a.mandatory,
                "due": a.due,
                "scheduled_for": a.scheduled_for,
                "assignment_kind": a.kind,
                "material_id": a.material_id,
                "estimated_minutes": min(prefs.session_minutes, prefs.daily_minutes, max(5, available)),
                "status": "practiced_today"
                if any(u.assignment_id == a.id and u.completed and u.completed >= start for u in units)
                else "not_started",
            }
        )
    if learning_paths is None:
        learning_paths = paths(db, child.id)
    for path in learning_paths:
        if path["next_unit_id"] or not path["next_review"]:
            continue
        candidates.append(
            {
                "kind": "review",
                "id": path["latest_unit_id"],
                "learning_root_id": path["root_unit_id"],
                "topic": path["topic"],
                "subject": path["subject"],
                "mandatory": False,
                "status": "not_started",
                "due": path["next_review"],
                "not_before": path["next_review"],
                "estimated_minutes": min(8, prefs.session_minutes, prefs.daily_minutes),
            }
        )
    for mastery in reviews:
        if any(p["subject"] == mastery.subject and p["topic"] == mastery.topic for p in learning_paths):
            continue
        if any(x["topic"] == mastery.topic for x in candidates):
            continue
        old = next((u for u in reversed(units) if u.topic == mastery.topic and u.status == "completed"), None)
        if old:
            candidates.append(
                {
                    "kind": "review",
                    "id": old.id,
                    "topic": old.topic,
                    "subject": old.subject,
                    "mandatory": False,
                    "status": "not_started",
                    "due": mastery.next_review,
                    "not_before": mastery.next_review,
                    "estimated_minutes": min(8, prefs.session_minutes, prefs.daily_minutes),
                }
            )
    for m in db.scalars(
        select(Material)
        .where(Material.child_id == child.id, Material.confirmed.is_(True), Material.school_day_id.is_(None))
        .options(defer(Material.content), defer(Material.homework), defer(Material.uncertainties))
    ):
        if not any(x["topic"] == m.topic for x in candidates) and not any(u.material_id == m.id for u in units):
            candidates.append(
                {
                    "kind": "material",
                    "id": m.id,
                    "topic": m.topic,
                    "subject": m.subject,
                    "mandatory": False,
                    "status": "not_started",
                    "estimated_minutes": min(8, prefs.session_minutes, prefs.daily_minutes),
                }
            )
    for school_day in days:
        for index, block in enumerate((school_day.learning_plan or {}).get("blocks", [])):
            saved_unit = units_by_id.get(block.get("unit_id"))
            if saved_unit and saved_unit.status == "completed":
                continue
            if not saved_unit and school_day.id not in synthetic_days and not synthetic_family:
                candidates.append(
                    {
                        "kind": "study_path",
                        "id": school_day.id,
                        "block_id": block["id"],
                        "topic": block["title"],
                        "subject": block.get("subject", "Lernreise"),
                        "mandatory": False,
                        "status": "planned",
                        "estimated_minutes": min(prefs.session_minutes, max(5, block["question_count"] * 2)),
                        "source_date": school_day.school_date,
                        "not_before": school_day.school_date,
                        "_chain": f"{school_day.id}:{block.get('subject', '')}",
                        "_sequence": index,
                        "_last_practiced": (
                            datetime.fromtimestamp(practiced[school_day.id], ZoneInfo(prefs.timezone))
                            .date()
                            .isoformat()
                            if school_day.id in practiced
                            else None
                        ),
                    }
                )
    completed_chains = {}
    for unit in units:
        if unit.completed and unit.completed >= start and unit.school_day_id:
            key = f"{unit.school_day_id}:{unit.subject}"
            completed_chains[key] = completed_chains.get(key, 0) + 1
    proposal = distribute(
        candidates,
        prefs,
        today,
        daily_seconds=daily_load * 60,
        weekly_seconds=weekly_load * 60,
        completed_chains=completed_chains,
    )
    if proposal["later"]:
        notices.append("Weiterer Stoff wird auf die nächsten Lerntage verteilt. Das Tagesziel bleibt gleich.")
    if proposal["beyond_week_steps"]:
        notices.append(
            "Nicht der ganze gespeicherte Stoff passt in die nächsten sieben Tage. Bitte bei Bedarf gemeinsam Schwerpunkte setzen."
        )
    if proposal["conflicts"]:
        notices.append(
            "Ein Elterntermin passt voraussichtlich nicht in die Lernzeit. Bitte Termin oder Schwerpunkte gemeinsam prüfen."
        )
    return {
        **proposal,
        "date": today.isoformat(),
        "available_minutes": available,
        "session_minutes": minutes,
        "break_minutes": prefs.break_minutes,
        "daily_limit_minutes": prefs.daily_minutes,
        "weekly_limit_minutes": prefs.weekly_minutes,
        "daily_used_minutes_approx": round(daily_seconds / 60, 1),
        "weekly_used_minutes_approx": round(weekly_seconds / 60, 1),
        "weekly_remaining_minutes": max(0, prefs.weekly_minutes - weekly_load),
        "completed_portion_minutes": completed_daily,
        "weekly_portion_minutes": completed_weekly,
        "notices": notices,
        "completed_today": sum(bool(u.completed and u.completed >= start) for u in units),
        "free_day": free_day,
        "paused": paused,
        "forecast_notice": "Vorschlag für sieben Tage: Neue Seiten, Antworten und Elternvorgaben passen ihn an. Zeiten sind Schätzungen; weitere Hilfen und Wiederholungen kommen nach Bedarf hinzu.",
        "notice": "Versäumte Tage vergrößern das Tagesziel nicht. Eltern sehen ausschließlich Aktivitäten innerhalb von SCHULPILOT.",
    }


def capture_status(db, child, current_plan):
    from .school_preparation import preparation_data

    day = db.scalar(
        select(SchoolDay).where(SchoolDay.child_id == child.id, SchoolDay.school_date == current_plan["date"])
    )
    count = db.scalar(select(func.count()).select_from(Material).where(Material.school_day_id == day.id)) if day else 0
    skipped = db.scalar(
        select(Activity.id)
        .where(
            Activity.child_id == child.id,
            Activity.kind == "daily_checkin",
            Activity.detail["date"].as_string() == current_plan["date"],
        )
        .limit(1)
    )
    return {
        "date": current_plan["date"],
        "day_id": day.id if day else None,
        "page_count": count,
        "status": day.stage if count else "skipped" if skipped else "empty",
        "preparation": preparation_data(db, day, child) if day and day.preparation else None,
    }


@router.post("/children/{child_id}/day-check-in")
def no_new_pages(child_id: str, p=Depends(child_user), db=Depends(get_db)):
    child = child_access(db, p, child_id)
    db.execute(update(Child).where(Child.id == child.id).values(grade=Child.grade))
    day = local_day(child).isoformat()
    existing = db.scalar(
        select(Activity.id)
        .where(
            Activity.child_id == child.id, Activity.kind == "daily_checkin", Activity.detail["date"].as_string() == day
        )
        .limit(1)
    )
    if not existing:
        record(db, child.id, "daily_checkin", {"date": day, "new_pages": False})
    db.commit()
    return {"date": day, "status": "skipped"}


@router.get("/children/{child_id}/overview")
def overview(child_id: str, p=Depends(authenticated), db=Depends(get_db), *, compact: bool = False):
    from .coaching import paths

    child = child_access(db, p, child_id)
    learning_paths = paths(db, child.id)
    days = list(
        db.scalars(
            select(SchoolDay).where(SchoolDay.child_id == child.id).order_by(SchoolDay.school_date.desc()).limit(30)
        )
    )
    current_plan = plan(db, child, learning_paths=learning_paths)
    capture = capture_status(db, child, current_plan)
    from .school_preparation import preparation_data

    preparations = [
        {"day_id": day.id, "date": day.school_date, **preparation_data(db, day, child)}
        for day in db.scalars(
            select(SchoolDay)
            .where(
                SchoolDay.child_id == child.id,
                SchoolDay.preparation["status"]
                .as_string()
                .in_(["processing", "needs_review", "needs_photo", "failed", "blocked"]),
            )
            .order_by(SchoolDay.school_date.desc())
            .limit(3)
        )
    ]
    if compact:
        from .library import MATERIAL_FIELDS, material_summary, unit_summaries

        material_count = db.scalar(select(func.count()).select_from(Material).where(Material.child_id == child.id))
        pending = list(
            db.scalars(
                select(Material)
                .outerjoin(SchoolDay, SchoolDay.id == Material.school_day_id)
                .options(load_only(*MATERIAL_FIELDS))
                .where(
                    Material.child_id == child.id,
                    Material.confirmed.is_(False),
                    or_(Material.school_day_id.is_(None), SchoolDay.school_date == current_plan["date"]),
                )
                .order_by(Material.created.desc(), Material.id.desc())
                .limit(24)
            )
        )
        pending_review_ids = list(
            db.scalars(
                select(LearningUnit.id)
                .join(UnitCoaching, UnitCoaching.unit_id == LearningUnit.id)
                .where(
                    LearningUnit.child_id == child.id,
                    LearningUnit.status == "completed",
                    UnitCoaching.status == "pending",
                )
                .order_by(LearningUnit.created.desc(), LearningUnit.id.desc())
                .limit(3)
            )
        )
        unit_previews = list(unit_summaries(db, pending_review_ids).values())
        for preview in unit_previews:
            preview["coaching"] = {"status": preview["review_status"]}
        later = current_plan["later"]
        current_plan = current_plan | {
            "today_count": len(current_plan["today"]),
            "later_count": len(later),
            "today": current_plan["today"][:3],
            "later": [
                item for item in later if not item.get("scheduled_for") or item["scheduled_for"] <= current_plan["date"]
            ][:1],
            "week": [
                day | {"item_count": len(day["items"]), "items": day["items"][:3]} for day in current_plan["week"]
            ],
        }
    else:
        material_count = None
    return {
        "child": child_data(db, child),
        "school_days": [
            {
                "id": d.id,
                "date": d.school_date,
                "stage": d.stage,
                "page_count": len(list(db.scalars(select(Material.id).where(Material.school_day_id == d.id)))),
            }
            for d in days
        ],
        "plan": current_plan,
        "daily_capture": capture,
        "pending_preparations": preparations,
        "day_summary": summary(db, child, 1, learning_paths=learning_paths),
        "week_summary": summary(db, child, 7, learning_paths=learning_paths),
        "material_count": material_count,
        "materials": [material_summary(m) for m in pending]
        if compact
        else [
            material_data(m)
            for m in db.scalars(select(Material).where(Material.child_id == child.id).order_by(Material.created.desc()))
        ],
        "assignments": [
            assignment_data(a)
            for a in db.scalars(
                select(Assignment).where(Assignment.child_id == child.id).order_by(Assignment.created.desc())
            )
        ],
        "units": unit_previews
        if compact
        else [
            unit_data(db, u, include_answers=p.user.role == "parent", include_progress=False)
            for u in db.scalars(
                select(LearningUnit).where(LearningUnit.child_id == child.id).order_by(LearningUnit.created.desc())
            )
        ],
        "mastery": [
            mastery_data(m)
            for m in db.scalars(select(Mastery).where(Mastery.child_id == child.id).limit(3 if compact else None))
        ],
        "learning_paths": learning_paths[:3] if compact else learning_paths,
        "messages": [
            {
                "id": m.id,
                "kind": m.kind,
                "body": m.body,
                "resolved": m.resolved,
                "sender_role": db.get(User, m.sender_id).role
                if m.sender_id and db.get(User, m.sender_id)
                else "parent",
                "created": m.created,
            }
            for m in db.scalars(
                select(Message).where(Message.child_id == child.id).order_by(Message.created.desc()).limit(100)
            )
        ],
    }


@router.get("/children/{child_id}/activity")
def activity(child_id: str, before: int | None = None, p=Depends(authenticated), db=Depends(get_db)):
    child_access(db, p, child_id)
    query = select(Activity).where(Activity.child_id == child_id)
    if before:
        query = query.where(Activity.created < before)
    return [
        {"id": a.id, "kind": a.kind, "detail": a.detail, "unit_id": a.unit_id, "created": a.created}
        for a in db.scalars(query.order_by(Activity.created.desc(), Activity.id).limit(200))
    ]


@router.post("/children/{child_id}/assignments", status_code=201)
def add_assignment(child_id: str, data: s.AssignmentCreate, p=Depends(parent), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=True)
    db.execute(update(Child).where(Child.id == child.id).values(grade=Child.grade))
    if data.material_id:
        material = db.get(Material, data.material_id)
        if not material or material.child_id != child.id:
            raise HTTPException(404, "Material nicht gefunden.")
    a = Assignment(child_id=child.id, **data.model_dump(mode="json"))
    db.add(a)
    record(db, child.id, "parent_assignment", {"subject": data.subject, "topic": data.topic, "due": a.due})
    db.commit()
    return assignment_data(a)


@router.put("/children/{child_id}/assignments/{assignment_id}")
def edit_assignment(child_id: str, assignment_id: str, data: s.AssignmentCreate, p=Depends(parent), db=Depends(get_db)):
    child_access(db, p, child_id, write=True)
    db.execute(update(Child).where(Child.id == child_id).values(grade=Child.grade))
    a = db.get(Assignment, assignment_id)
    if not a or a.child_id != child_id:
        raise HTTPException(404, "Lernauftrag nicht gefunden.")
    if data.material_id:
        material = db.get(Material, data.material_id)
        if not material or material.child_id != child_id:
            raise HTTPException(404, "Material nicht gefunden.")
    values = data.model_dump(mode="json")
    if "scheduled_for" not in data.model_fields_set:
        # Older clients cannot see the new start-date field; preserve the
        # binding date unless a managing parent explicitly sends a new value.
        values.pop("scheduled_for")
    for key, value in values.items():
        setattr(a, key, value)
    a.done = False
    a.revision += 1
    record(db, child_id, "assignment_changed", {"topic": a.topic})
    db.commit()
    return assignment_data(a)


@router.delete("/children/{child_id}/assignments/{assignment_id}")
def delete_assignment(child_id: str, assignment_id: str, p=Depends(parent), db=Depends(get_db)):
    child_access(db, p, child_id, write=True)
    db.execute(update(Child).where(Child.id == child_id).values(grade=Child.grade))
    a = db.get(Assignment, assignment_id)
    if not a or a.child_id != child_id:
        raise HTTPException(404, "Lernauftrag nicht gefunden.")
    db.delete(a)
    record(db, child_id, "assignment_removed", {"topic": a.topic})
    db.commit()
    return {"message": "Lernauftrag entfernt."}


@router.post("/children/{child_id}/assignments/{assignment_id}/complete")
def complete_assignment(child_id: str, assignment_id: str, p=Depends(parent), db=Depends(get_db)):
    child_access(db, p, child_id, write=True)
    db.execute(update(Child).where(Child.id == child_id).values(grade=Child.grade))
    assignment = db.get(Assignment, assignment_id)
    if not assignment or assignment.child_id != child_id:
        raise HTTPException(404, "Lernauftrag nicht gefunden.")
    assignment.done = True
    assignment.revision += 1
    record(db, child_id, "parent_goal_completed", {"topic": assignment.topic})
    db.commit()
    return {"message": "Elternziel als erledigt markiert. Dies ist keine automatische Aussage über die Beherrschung."}


def get_unit(db, p, unit_id, child_only=False, lock=False):
    unit = db.get(LearningUnit, unit_id)
    if not unit:
        raise HTTPException(404, "Lerneinheit nicht gefunden.")
    child_access(db, p, unit.child_id)
    if child_only and p.user.role != "child":
        raise HTTPException(403, "Aufgaben werden mit dem Kinderzugang bearbeitet.")
    if lock:
        db.execute(update(LearningUnit).where(LearningUnit.id == unit.id).values(status=LearningUnit.status))
        db.refresh(unit)
    return unit


@router.get("/units/{unit_id}")
def unit_view(unit_id: str, p=Depends(authenticated), db=Depends(get_db)):
    unit = get_unit(db, p, unit_id)
    return unit_data(db, unit, p.user.role == "parent")


@router.post("/units/{unit_id}/start")
def start(unit_id: str, p=Depends(child_user), db=Depends(get_db)):
    unit = get_unit(db, p, unit_id, True, True)
    if unit.status == "completed":
        return unit_data(db, unit)
    if reason := learning_block(db, unit):
        raise HTTPException(409, reason)
    child = db.get(Child, unit.child_id)
    assignment = db.get(Assignment, unit.assignment_id) if unit.assignment_id else None
    if assignment and assignment.scheduled_for and assignment.scheduled_for > local_day(child).isoformat():
        raise HTTPException(
            409, f"Dieser Lernauftrag beginnt am {assignment.scheduled_for}. Deine Eltern können ihn neu planen."
        )
    prefs = s.Preferences(**child.preferences)
    if prefs.pause_until and local_day(child) <= prefs.pause_until:
        raise HTTPException(
            409, "Deine Eltern haben eine Lernpause eingestellt. Du kannst eine Planänderung vorschlagen."
        )
    if unit.break_until and unit.break_until > now():
        raise HTTPException(409, "Zeit für deine Pause. Du kannst diese Einheit danach fortsetzen.")
    if unit.break_until:
        unit.segment_seconds = 0
        unit.break_until = None
    elif unit.heartbeat and now() - unit.heartbeat >= prefs.break_minutes * 60:
        unit.segment_seconds = 0
    unit.status = "active"
    unit.heartbeat = int(now())
    record(db, unit.child_id, "unit_started", {"topic": unit.topic}, unit.id)
    db.commit()
    return unit_data(db, unit)


@router.post("/units/{unit_id}/pause")
def pause(unit_id: str, p=Depends(child_user), db=Depends(get_db)):
    unit = get_unit(db, p, unit_id, True, True)
    if unit.status == "active":
        unit.status = "paused"
        unit.heartbeat = int(now())
        record(db, unit.child_id, "unit_paused", unit_id=unit.id)
        db.commit()
    return unit_data(db, unit)


@router.post("/units/{unit_id}/heartbeat")
def heartbeat(unit_id: str, p=Depends(child_user), db=Depends(get_db)):
    unit = get_unit(db, p, unit_id, True, True)
    prefs = s.Preferences(**db.get(Child, unit.child_id).preferences)
    stamp = int(now())
    if unit.status == "active":
        if learning_block(db, unit):
            unit.status = "paused"
            unit.heartbeat = None
            record(db, unit.child_id, "plan_paused", unit_id=unit.id)
            db.commit()
            return {
                "active_seconds_approx": unit.active_seconds,
                "status": unit.status,
                "break_until": unit.break_until,
            }
        elapsed = stamp - (unit.heartbeat or stamp)
        if 0 < elapsed <= 45:
            child = db.get(Child, unit.child_id)
            start, week = period_starts(local_day(child), prefs.timezone)
            events = list(
                db.scalars(
                    select(Activity).where(
                        Activity.child_id == child.id, Activity.kind == "active_time", Activity.created >= week
                    )
                )
            )
            day_left = max(
                0, prefs.daily_minutes * 60 - sum(e.detail.get("seconds", 0) for e in events if e.created >= start)
            )
            week_left = max(0, prefs.weekly_minutes * 60 - sum(e.detail.get("seconds", 0) for e in events))
            seconds = min(elapsed, 25, day_left, week_left, max(0, prefs.session_minutes * 60 - unit.segment_seconds))
            unit.active_seconds += seconds
            unit.segment_seconds += seconds
            if seconds:
                record(db, unit.child_id, "active_time", {"seconds": seconds}, unit.id)
        unit.heartbeat = stamp
        if unit.segment_seconds >= prefs.session_minutes * 60:
            unit.status = "paused"
            unit.break_until = stamp + prefs.break_minutes * 60
            unit.heartbeat = None
            record(db, unit.child_id, "scheduled_break", {"minutes": prefs.break_minutes}, unit.id)
        db.commit()
    return {"active_seconds_approx": unit.active_seconds, "status": unit.status, "break_until": unit.break_until}


@router.post("/units/{unit_id}/explanation")
def explanation(unit_id: str, p=Depends(child_user), db=Depends(get_db)):
    unit = get_unit(db, p, unit_id, True)
    rate_limit(db, "explain:" + p.user.id, 30)
    record(db, unit.child_id, "explanation", {"text": unit.explanation}, unit.id)
    db.commit()
    return {"explanation": unit.explanation}


@router.post("/units/{unit_id}/introduction")
def introduction(unit_id: str, p=Depends(child_user), db=Depends(get_db)):
    unit = get_unit(db, p, unit_id, True, True)
    if unit.status != "active":
        raise HTTPException(409, "Bitte die Einheit zuerst starten oder fortsetzen.")
    if not unit.introduction_seen:
        unit.introduction_seen = True
        record(db, unit.child_id, "introduction_read", unit_id=unit.id)
        db.commit()
    return unit_data(db, unit)


def question(unit, question_id):
    q = next((q for q in unit.questions if q["id"] == question_id), None)
    if not q:
        raise HTTPException(404, "Aufgabe nicht gefunden.")
    return q


@router.post("/units/{unit_id}/questions/{question_id}/hint")
def hint(unit_id: str, question_id: str, p=Depends(child_user), db=Depends(get_db)):
    unit = get_unit(db, p, unit_id, True, True)
    q = question(unit, question_id)
    count = len(list(db.scalars(select(Activity.id).where(Activity.unit_id == unit.id, Activity.kind == "hint"))))
    if count >= len(unit.questions) * 3:
        raise HTTPException(409, "Alle Hinweise wurden bereits angezeigt. Du kannst deine Eltern um Hilfe bitten.")
    used = len(
        [
            e
            for e in db.scalars(select(Activity).where(Activity.unit_id == unit.id, Activity.kind == "hint"))
            if e.detail.get("question_id") == question_id
        ]
    )
    text = q["hints"][min(used, len(q["hints"]) - 1)]
    record(db, unit.child_id, "hint", {"question_id": question_id, "text": text}, unit.id)
    db.commit()
    return {"hint": text}


def normalized(text):
    return " ".join(unicodedata.normalize("NFKC", text).casefold().strip().replace(",", ".").split())


def evaluate(q, answer):
    from .checks import expanded_fraction, fraction_parts

    expected_form = expanded_fraction(q["prompt"]) if q["type"] in ("choice", "gap", "short") else None
    if expected_form:
        parts = fraction_parts(answer)
        if parts is not None:
            return "correct" if parts == expected_form else "incorrect"
        return "uncertain" if q["type"] == "short" else "incorrect"
    valid = {normalized(v) for v in [q["answer"], *q["accepted"]]}
    if normalized(answer) in valid:
        return "correct"
    if q["type"] == "short":
        return "uncertain"
    return "incorrect"


def learning_block(db, unit):
    child = db.get(Child, unit.child_id)
    today = local_day(child)
    prefs = s.Preferences(**child.preferences)
    if prefs.pause_until and today <= prefs.pause_until:
        return "Deine Eltern haben eine Lernpause eingestellt. Du kannst eine Planänderung vorschlagen."
    if unit.not_before and unit.not_before > today.isoformat():
        return f"Diese spätere Abrufprobe beginnt frühestens am {unit.not_before}."
    from .coaching import continuation_block

    if reason := continuation_block(db, unit, child, check_sources=False):
        return reason
    if unit.round_kind in ("study_block", "study_recall"):
        from .coaching import context
        from .study_path import block_reason

        try:
            context(db, unit)
        except Exception:
            return "Eine Heftseite wurde geändert. Bitte die aktuelle Lernreise öffnen."
        if reason := block_reason(db, child, unit.subject, unit_id=unit.id, question_count=len(unit.questions)):
            return reason
    if unit.learning_root_id or unit.followup_of:
        from .coaching import continuation_block

        if reason := continuation_block(db, unit, child):
            return reason
    assignment = db.get(Assignment, unit.assignment_id) if unit.assignment_id else None
    if assignment and assignment.scheduled_for and assignment.scheduled_for > today.isoformat():
        return f"Dieser Lernauftrag beginnt am {assignment.scheduled_for}. Deine Eltern können ihn neu planen."
    return None


def update_mastery(db, unit, attempts):
    child = db.get(Child, unit.child_id)
    today = local_day(child)
    mastery = db.scalar(
        select(Mastery).where(
            Mastery.child_id == unit.child_id, Mastery.subject == unit.subject, Mastery.topic == unit.topic
        )
    )
    if not mastery:
        mastery = Mastery(
            child_id=unit.child_id,
            subject=unit.subject,
            topic=unit.topic,
            next_review=(today + timedelta(days=1)).isoformat(),
            last_practiced=today.isoformat(),
            independent=0,
            assisted=0,
            difficulties=0,
            uncertain_units=0,
            review_successes=0,
        )
        db.add(mastery)
    final = [next(a for a in reversed(attempts) if a.question_id == q["id"]) for q in unit.questions]
    independent = all(a.outcome == "correct" and not a.assisted for a in final)
    if independent:
        mastery.independent += 1
        if unit.review_of and mastery.last_practiced < today.isoformat():
            mastery.review_successes += 1
        interval = min(14, 2 ** min(mastery.review_successes, 3))
    elif all(a.outcome == "correct" for a in final):
        mastery.assisted += 1
        interval = 1
    elif any(a.outcome == "incorrect" for a in final):
        mastery.difficulties += 1
        interval = 1
    else:
        mastery.uncertain_units += 1
        interval = 1
    mastery.next_review = (today + timedelta(days=interval)).isoformat()
    mastery.last_practiced = today.isoformat()


@router.post("/units/{unit_id}/questions/{question_id}/answer")
def answer(unit_id: str, question_id: str, data: s.AnswerRequest, p=Depends(child_user), db=Depends(get_db)):
    unit = get_unit(db, p, unit_id, True, True)
    if unit.status != "active":
        raise HTTPException(409, "Bitte die Lerneinheit zuerst starten oder fortsetzen.")
    if reason := learning_block(db, unit):
        raise HTTPException(409, reason)
    q = question(unit, question_id)
    existing = list(db.scalars(select(Attempt).where(Attempt.unit_id == unit.id).order_by(Attempt.created, Attempt.id)))
    previous = [a for a in existing if a.question_id == question_id]
    if previous and (previous[-1].outcome in ("correct", "uncertain") or len(previous) >= 3):
        raise HTTPException(409, "Diese Aufgabe wurde bereits abgeschlossen.")
    hinted = bool(
        db.scalar(select(Activity.id).where(Activity.unit_id == unit.id, Activity.kind == "explanation"))
    ) or any(
        e.detail.get("question_id") == question_id
        for e in db.scalars(select(Activity).where(Activity.unit_id == unit.id, Activity.kind == "hint"))
    )
    outcome = evaluate(q, data.answer)
    attempt = Attempt(
        unit_id=unit.id, question_id=question_id, answer=data.answer, outcome=outcome, assisted=bool(hinted or previous)
    )
    db.add(attempt)
    db.flush()
    record(db, unit.child_id, "answer", {"question_id": question_id, "outcome": outcome}, unit.id)
    attempts = [*existing, attempt]
    done = all(
        any(a.question_id == x["id"] and a.outcome in ("correct", "uncertain") for a in attempts)
        or sum(a.question_id == x["id"] for a in attempts) >= 3
        for x in unit.questions
    )
    if done:
        # Serialize mastery updates across units of the same child.
        db.execute(update(Child).where(Child.id == unit.child_id).values(grade=Child.grade))
        unit.status = "completed"
        unit.completed = int(now())
        unit.heartbeat = None
        update_mastery(db, unit, attempts)
        # An exercise is evidence of practice. Only a parent can close the
        # binding goal; a single completed unit cannot establish full mastery.
        record(db, unit.child_id, "unit_completed", {"topic": unit.topic}, unit.id)
    db.commit()
    if done:
        from .coaching import schedule

        schedule(unit.id, automatic=True)
        db.expire_all()
        unit = db.get(LearningUnit, unit_id)
    text = {
        "correct": "Gut gelöst. Wiederholen hilft dir, das Wissen zu festigen.",
        "incorrect": "Das passt noch nicht. Schau dir den Hinweis an und versuche es noch einmal.",
        "uncertain": "Diese Antwort kann ich nicht sicher bewerten. Sie bleibt zur gemeinsamen Durchsicht gespeichert.",
    }[outcome]
    return {
        "outcome": outcome,
        "assisted": attempt.assisted,
        "feedback": text,
        "explanation": q["explanation"] if outcome != "incorrect" or len(previous) >= 2 else None,
        "unit": unit_data(db, unit),
    }


@router.post("/units/{unit_id}/feedback")
def feedback(unit_id: str, data: s.FeedbackRequest, p=Depends(child_user), db=Depends(get_db)):
    unit = get_unit(db, p, unit_id, True)
    rate_limit(db, "feedback:" + p.user.id, 10)
    record(db, unit.child_id, "feedback", {"kind": data.kind}, unit.id)
    db.commit()
    return {
        "message": "Deine Rückmeldung wurde gespeichert und wird bei der nächsten Einheit berücksichtigt. Das Lernziel bleibt erhalten."
    }


@router.post("/children/{child_id}/messages", status_code=201)
def send_message(child_id: str, data: s.MessageRequest, p=Depends(authenticated), db=Depends(get_db)):
    child_access(db, p, child_id, write=p.user.role == "parent")
    if (p.user.role == "child" and data.kind == "reply") or (p.user.role == "parent" and data.kind != "reply"):
        raise HTTPException(403, "Nachrichtentyp für diesen Zugang nicht erlaubt.")
    rate_limit(db, "message:" + p.user.id, 10, 600)
    message = Message(child_id=child_id, sender_id=p.user.id, kind=data.kind, body=data.body)
    db.add(message)
    record(db, child_id, "message", {"kind": data.kind})
    db.commit()
    return {"id": message.id, "message": "Nachricht innerhalb deiner Familie gespeichert."}


@router.post("/children/{child_id}/messages/{message_id}/resolve")
def resolve(child_id: str, message_id: str, p=Depends(parent), db=Depends(get_db)):
    child_access(db, p, child_id, write=True)
    message = db.get(Message, message_id)
    if not message or message.child_id != child_id:
        raise HTTPException(404, "Nachricht nicht gefunden.")
    message.resolved = True
    db.commit()
    return {"message": "Anliegen als besprochen markiert."}


@router.get("/child/home")
def child_home(p=Depends(child_user), db=Depends(get_db)):
    child = own_child(db, p)
    return overview(child.id, p, db)
