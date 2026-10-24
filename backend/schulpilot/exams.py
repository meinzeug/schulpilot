"""Explicit school-exam preparation; reads never schedule or reserve work."""

import hashlib
import json
import unicodedata
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from sqlalchemy import func, select, update

from .db import Child, Family, Job, LearningUnit, Material, Session, User, get_db, now
from .exam_models import Exam, ExamRound, ExamSession
from .exam_schemas import ExamArchive, ExamCreate, ExamUpdate
from .providers import ProviderError
from .security import authenticated, child_access, rate_limit

router = APIRouter(tags=["Klassenarbeiten und Lernkontrollen"])
MAX_OPEN_EXAMS = 100


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def lock_child(db, p, child_id, *, write=True):
    child_access(db, p, child_id, write=write)
    db.execute(update(Child).where(Child.id == child_id).values(grade=Child.grade))
    # Membership/session changes committed while waiting for the lock must win.
    db.expire_all()
    session = db.get(Session, p.session.id)
    user = db.get(User, p.user.id)
    if (not session or session.revoked or session.expires <= now() or now() - session.seen > 7 * 86400 or
            not user or session.user_id != user.id or user.disabled or not user.verified):
        raise HTTPException(401, "Bitte erneut anmelden.")
    return child_access(db, p, child_id, write=write)


def access_exam(db, p, exam_id, *, write=False):
    exam = db.get(Exam, exam_id)
    if not exam:
        raise HTTPException(404, "Klassenarbeit nicht gefunden.")
    child = lock_child(db, p, exam.child_id) if write else child_access(db, p, exam.child_id)
    return db.get(Exam, exam_id, populate_existing=write), child


def can_manage(db, p, child):
    from .db import Membership

    return p.user.role == "child" or bool(db.scalar(select(Membership.id).where(
        Membership.user_id == p.user.id, Membership.family_id == child.family_id,
        Membership.permission != "view")))


def sources_data(db, child_id):
    return [{"id": m.id, "revision": m.revision, "subject": m.subject, "topic": m.topic, "title": m.title}
            for m in db.scalars(select(Material).where(Material.child_id == child_id,
                Material.purpose == "notebook", Material.confirmed.is_(True)).order_by(
                    Material.created.desc(), Material.id).limit(200))]


def valid_refs(db, child_id, refs, subject_id, subject):
    pages = []
    for ref in refs:
        material = db.get(Material, ref["id"], populate_existing=True)
        if (not material or material.child_id != child_id or material.purpose != "notebook"
                or not material.confirmed or material.revision != ref["revision"] or not material.content.strip()
                or (material.subject_id != subject_id if subject_id and material.subject_id
                    else material.subject != subject)):
            return False
        pages.append(material)
    return bool(pages) and sum(len(page.content) for page in pages) <= 60_000


def plan_values(db, child, data):
    from .subject_registry import resolve

    subject = resolve(db, data.subject, child.family_id, active_only=True)
    if not subject:
        raise HTTPException(422, "Bitte ein vorhandenes Fach auswählen.")
    values = data.model_dump(mode="json", exclude={"revision"})
    values["subject_id"] = subject.id
    for topic in values["topics"]:
        if not valid_refs(db, child.id, topic["material_refs"], subject.id, data.subject):
            raise HTTPException(409, "Bitte aktuelle bestätigte Heftseiten desselben Fachs auswählen.")
    return values


def split_rounds(count):
    """Balanced 2..5-question rounds; a requested total of one stays one."""
    rounds = (count + 4) // 5
    base, remainder = divmod(count, rounds)
    return [base + (index < remainder) for index in range(rounds)]


def allocate_sessions(db, exam):
    """Every explicit date gets work, without inferring study or pre-generating it."""
    dates, topics = exam.schedule["dates"], exam.topics
    if not dates:
        return
    groups = [[] for _ in dates]
    if len(dates) <= len(topics):
        for index, topic in enumerate(topics):
            groups[index % len(dates)].append(topic)
    else:
        for index in range(len(dates)):
            groups[index].append(topics[index % len(topics)])
    for day, selected in zip(dates, groups, strict=True):
        session = ExamSession(exam_id=exam.id, exam_revision=exam.plan_revision, date=day,
                              minutes=exam.minutes, topics=selected)
        db.add(session)
        db.flush()
        ordinal = 0
        for topic in selected:
            for count in split_rounds(topic["question_count"]):
                db.add(ExamRound(session_id=session.id, ordinal=ordinal, topic_id=topic["id"],
                    topic_label=topic["label"], question_count=count, source_revisions=topic["material_refs"]))
                ordinal += 1


def round_status(db, exam, row):
    unit = db.get(LearningUnit, row.unit_id) if row.unit_id else None
    job = db.get(Job, row.job_id) if row.job_id else None
    if unit and unit.child_id == exam.child_id and unit.status == "completed":
        return "completed", unit, job
    if not valid_refs(db, exam.child_id, row.source_revisions, exam.subject_id, exam.subject):
        return "stale", None, job
    if unit and unit.child_id == exam.child_id:
        return "ready", unit, job
    return ("preparing" if job and job.status in ("queued", "running") else
            "failed" if job and job.status == "failed" else "planned"), None, job


def session_data(db, exam, session):
    rounds = []
    for row in db.scalars(select(ExamRound).where(ExamRound.session_id == session.id).order_by(ExamRound.ordinal)):
        status, unit, job = round_status(db, exam, row)
        rounds.append({"id": row.id, "ordinal": row.ordinal, "topic_id": row.topic_id,
            "topic_label": row.topic_label, "question_count": row.question_count, "status": status,
            "unit_id": unit.id if unit else None, "unit_status": unit.status if unit else None,
            "job_id": job.id if job else None, "error": job.error if job and job.status == "failed" else None})
    statuses = {row["status"] for row in rounds}
    status = ("completed" if rounds and statuses == {"completed"} else "preparing" if "preparing" in statuses
              else "ready" if "ready" in statuses else "stale" if "stale" in statuses
              else "failed" if "failed" in statuses else "planned")
    return {"id": session.id, "date": session.date, "minutes": session.minutes, "topics": session.topics,
        "status": status, "requested_questions": sum(row["question_count"] for row in rounds),
        "planned_rounds": len(rounds), "completed_rounds": sum(row["status"] == "completed" for row in rounds),
        "rounds": rounds}


def exam_data(db, exam, *, detail=True):
    data = {key: getattr(exam, key) for key in ("id", "child_id", "title", "purpose", "kind", "subject",
        "subject_id", "exam_date", "timezone", "revision", "plan_revision", "minutes", "topics", "schedule", "reminders",
        "reminder_time", "archived", "created", "updated")}
    from .exam_review_models import ExamReviewPage

    data["review_page_count"] = db.scalar(select(func.count()).select_from(ExamReviewPage).where(ExamReviewPage.exam_id == exam.id))
    data["source_status"] = "confirmed" if all(valid_refs(db, exam.child_id, topic["material_refs"],
        exam.subject_id, exam.subject) for topic in exam.topics) else "stale"
    sessions = list(db.scalars(select(ExamSession).where(ExamSession.exam_id == exam.id,
        ExamSession.exam_revision == exam.plan_revision).order_by(ExamSession.date)))
    data["planned_days"] = len(sessions)
    data["requested_questions"] = sum(topic["question_count"] for session in sessions for topic in session.topics)
    if detail:
        data["sessions"] = [session_data(db, exam, session) for session in sessions]
    return data


def response_data(db, p, exam, child):
    return {**exam_data(db, exam), "can_manage": can_manage(db, p, child),
            "can_prepare": p.user.role == "child" and not exam.archived, "sources": sources_data(db, child.id)}


@router.get("/children/{child_id}/exams")
def list_exams(child_id: str, include_archived: bool = False, cursor: str | None = Query(None, max_length=32),
               p=Depends(authenticated), db=Depends(get_db)):
    child = child_access(db, p, child_id)
    query = select(Exam).where(Exam.child_id == child.id)
    if not include_archived:
        query = query.where(Exam.archived.is_(False))
    total = db.scalar(select(func.count()).select_from(query.subquery()))
    if cursor:
        previous = db.get(Exam, cursor)
        if not previous or previous.child_id != child.id or (previous.archived and not include_archived):
            raise HTTPException(404, "Die Listenseite wurde nicht gefunden.")
        query = query.where((Exam.updated < previous.updated) |
            ((Exam.updated == previous.updated) & (Exam.id > previous.id)))
    rows = list(db.scalars(query.order_by(Exam.updated.desc(), Exam.id).limit(101)))
    more = len(rows) > 100
    rows = rows[:100]
    return {"child_id": child.id, "can_manage": can_manage(db, p, child), "can_prepare": p.user.role == "child",
        "exams": [exam_data(db, exam, detail=False) for exam in rows], "total": total,
        "has_more": more, "next_cursor": rows[-1].id if more else None, "sources": sources_data(db, child.id)}


@router.post("/children/{child_id}/exams", status_code=201)
def create_exam(child_id: str, data: ExamCreate, key: str = Header(default="", alias="Idempotency-Key"),
                p=Depends(authenticated), db=Depends(get_db)):
    if not key or len(key) > 80:
        raise HTTPException(422, "Ein Idempotency-Key mit höchstens 80 Zeichen ist erforderlich.")
    child = lock_child(db, p, child_id)
    digest, request_key = fingerprint(data.model_dump(mode="json")), p.user.id + ":" + key
    old = db.scalar(select(Exam).where(Exam.create_key == request_key))
    if old:
        if old.child_id != child.id or old.request_digest != digest:
            raise HTTPException(409, "Dieser Schlüssel gehört zu einer anderen Klassenarbeit.")
        return response_data(db, p, old, child)
    if db.scalar(select(func.count()).select_from(Exam).where(Exam.child_id == child.id, Exam.archived.is_(False))) >= MAX_OPEN_EXAMS:
        raise HTTPException(409, "Bitte zuerst eine ältere Klassenarbeit archivieren.")
    values = plan_values(db, child, data)
    rate_limit(db, "exam-plan:" + p.user.id, 20, 3600, commit=False)
    exam = Exam(child_id=child.id, create_key=request_key, request_digest=digest, **values)
    db.add(exam)
    db.flush()
    allocate_sessions(db, exam)
    db.commit()
    return response_data(db, p, exam, child)


@router.get("/exams/{exam_id}")
def get_exam(exam_id: str, p=Depends(authenticated), db=Depends(get_db)):
    exam, child = access_exam(db, p, exam_id)
    return response_data(db, p, exam, child)


@router.put("/exams/{exam_id}")
def update_exam(exam_id: str, data: ExamUpdate, p=Depends(authenticated), db=Depends(get_db)):
    exam, child = access_exam(db, p, exam_id, write=True)
    if exam.archived or exam.revision != data.revision or exam.purpose != data.purpose:
        raise HTTPException(409, "Die Klassenarbeit wurde geändert oder archiviert. Bitte neu laden.")
    values = plan_values(db, child, data)
    rate_limit(db, "exam-plan:" + p.user.id, 20, 3600, commit=False)
    changed = db.execute(update(Exam).where(Exam.id == exam.id, Exam.revision == data.revision,
        Exam.archived.is_(False)).values(revision=Exam.revision + 1, plan_revision=Exam.plan_revision + 1), execution_options={"synchronize_session": False})
    if changed.rowcount != 1:
        db.rollback()
        raise HTTPException(409, "Die Klassenarbeit wurde inzwischen geändert. Bitte neu laden.")
    db.refresh(exam)
    for key, value in values.items():
        setattr(exam, key, value)
    exam.updated = int(now())
    allocate_sessions(db, exam)
    db.commit()
    return response_data(db, p, exam, child)


@router.post("/exams/{exam_id}/archive")
def archive_exam(exam_id: str, data: ExamArchive, p=Depends(authenticated), db=Depends(get_db)):
    exam, child = access_exam(db, p, exam_id, write=True)
    if exam.revision != data.revision:
        raise HTTPException(409, "Die Klassenarbeit wurde inzwischen geändert. Bitte neu laden.")
    if not exam.archived:
        rate_limit(db, "exam-plan:" + p.user.id, 20, 3600, commit=False)
        exam.archived, exam.revision, exam.updated = True, exam.revision + 1, int(now())
        db.commit()
    return response_data(db, p, exam, child)


@router.post("/exams/{exam_id}/sessions/{session_id}/prepare", status_code=202)
def prepare_session(exam_id: str, session_id: str, key: str = Header(default="", alias="Idempotency-Key"),
                    p=Depends(authenticated), db=Depends(get_db)):
    if p.user.role != "child":
        raise HTTPException(403, "Eine Lernrunde startet nur dein eigener Kinderzugang.")
    if not key or len(key) > 80:
        raise HTTPException(422, "Ein Idempotency-Key mit höchstens 80 Zeichen ist erforderlich.")
    exam, child = access_exam(db, p, exam_id, write=True)
    if p.user.role != "child" or child.user_id != p.user.id:
        raise HTTPException(403, "Eine Lernrunde startet nur dein eigener Kinderzugang.")
    if db.get(Family, child.family_id).synthetic:
        raise HTTPException(403, "Eigene Prüfungsvorbereitung benötigt ein reguläres Familienkonto.")
    session = db.get(ExamSession, session_id)
    if (exam.archived or not session or session.exam_id != exam.id or session.exam_revision != exam.plan_revision):
        raise HTTPException(409, "Bitte den aktuellen Lernplan öffnen.")
    previous = db.scalar(select(Job).where(Job.idempotency == p.user.id + ":" + key))
    if previous:
        if (previous.kind != "unit" or previous.child_id != child.id or
                previous.payload.get("exam_session_id") != session.id or
                previous.payload.get("exam_revision") != exam.plan_revision):
            raise HTTPException(409, "Dieser Schlüssel gehört zu einer anderen Vorbereitung.")
        return {"kind": "job", "id": previous.id, "status": previous.status}
    for row in db.scalars(select(ExamRound).where(ExamRound.session_id == session.id).order_by(ExamRound.ordinal)):
        status, unit, job = round_status(db, exam, row)
        if status == "completed":
            continue
        if unit:
            return {"kind": "unit", "id": unit.id, "status": unit.status}
        if status == "preparing":
            return {"kind": "job", "id": job.id, "status": job.status}
        if status == "stale":
            raise HTTPException(409, "Die Quellen wurden geändert. Bitte den Lernplan neu prüfen.")
        from .materials import enqueue

        payload = {"material_id": row.source_revisions[0]["id"], "sources": row.source_revisions,
            "exam_id": exam.id, "exam_revision": exam.plan_revision, "exam_session_id": session.id,
            "exam_round_id": row.id, "exam_actor_id": p.user.id, "exam_actor_session_id": p.session.id,
            "exam_family_id": child.family_id, "requested_question_count": row.question_count}
        result = enqueue(db, p, child, "unit", payload, key, commit=False)
        row.job_id = result["id"]
        db.commit()
        return {"kind": "job", **result}
    return {"kind": "completed", "id": session.id, "status": "completed"}


def guard_preparation(db, job):
    """Both pre-call and pre-persist guard for the existing unit worker."""
    if not job.payload.get("exam_round_id"):
        return None
    row = db.get(ExamRound, job.payload["exam_round_id"], populate_existing=True)
    session = db.get(ExamSession, row.session_id, populate_existing=True) if row else None
    exam = db.get(Exam, session.exam_id, populate_existing=True) if session else None
    child = db.get(Child, job.child_id, populate_existing=True)
    actor = db.get(User, job.payload.get("exam_actor_id"), populate_existing=True)
    login = db.get(Session, job.payload.get("exam_actor_session_id"), populate_existing=True)
    if (not exam or exam.archived or not child or exam.child_id != child.id or
            exam.plan_revision != job.payload.get("exam_revision") or session.exam_revision != exam.plan_revision or
            exam.id != job.payload.get("exam_id") or session.id != job.payload.get("exam_session_id") or
            row.job_id != job.id or row.question_count != job.payload.get("requested_question_count") or
            row.source_revisions != job.payload.get("sources") or
            job.payload.get("material_id") != row.source_revisions[0]["id"] or
            job.payload.get("material_revision") != row.source_revisions[0]["revision"] or
            not valid_refs(db, child.id, row.source_revisions, exam.subject_id, exam.subject) or
            not actor or actor.disabled or not actor.verified or actor.role != "child" or child.user_id != actor.id or
            not login or login.user_id != actor.id or login.revoked or login.expires <= now() or
            now() - login.seen > 7 * 86400 or
            child.family_id != job.payload.get("exam_family_id")):
        raise ProviderError("Prüfungsplan, Quellen oder Zugang wurden geändert. Bitte neu vorbereiten.")
    return exam, session, row


def previous_questions(db, exam, row):
    query = (select(LearningUnit.questions).join(ExamRound, ExamRound.unit_id == LearningUnit.id)
        .join(ExamSession, ExamRound.session_id == ExamSession.id).where(
            ExamSession.exam_id == exam.id, ExamRound.topic_id == row.topic_id,
            LearningUnit.child_id == exam.child_id).order_by(ExamSession.date.desc(), ExamRound.ordinal))
    for questions in db.scalars(query.execution_options(yield_per=100)):
        yield from questions


def preparation_context(db, job):
    guarded = guard_preparation(db, job)
    if not guarded:
        return {}
    exam, session, row = guarded
    prompts, remaining = [], 12_000
    for question in previous_questions(db, exam, row):
        prompt = question.get("prompt")
        if not isinstance(prompt, str):
            continue
        prompt = prompt[:1600]
        if len(prompt) > remaining:
            continue
        prompts.append(prompt)
        remaining -= len(prompt)
        if len(prompts) == 80 or remaining == 0:
            break
    return {"required_subject": exam.subject, "required_topic": row.topic_label,
        "session_minutes": session.minutes, "requested_question_count": row.question_count,
        "previous_prompts": prompts}


def validate_requested_count(job, data):
    if job.payload.get("exam_round_id"):
        expected = job.payload.get("requested_question_count")
        questions = data.get("questions") if isinstance(data, dict) else getattr(data, "questions", None)
        if expected not in (1, 2, 3, 4, 5) or not isinstance(questions, list) or len(questions) != expected:
            raise ProviderError("Die vorbereitete Runde hat nicht die ausdrücklich geplante Aufgabenanzahl.")


def normalized_prompt(text):
    return " ".join(unicodedata.normalize("NFC", text).split())


def validate_prepared_output(db, job, data):
    validate_requested_count(job, data)
    guarded = guard_preparation(db, job)
    if not guarded:
        return
    exam, _, row = guarded
    value = data if isinstance(data, dict) else data.model_dump()
    if value.get("subject") != exam.subject or value.get("topic") != row.topic_label:
        raise ProviderError("Fach oder Thema der vorbereiteten Runde weicht vom Lernplan ab.")
    prompts = [q.get("prompt") for q in value["questions"]]
    if any(not isinstance(p, str) or not p.strip() for p in prompts):
        raise ProviderError("Die vorbereitete Runde enthält keine gültigen Aufgaben.")
    normalized = {normalized_prompt(p) for p in prompts}
    if len(normalized) != len(prompts) or any(isinstance(q.get("prompt"), str) and
            normalized_prompt(q["prompt"]) in normalized for q in previous_questions(db, exam, row)):
        raise ProviderError("Eine Frage wurde bereits verwendet. Bitte neue Aufgaben vorbereiten.")


def attach_prepared_unit(db, job, unit):
    guarded = guard_preparation(db, job)
    if guarded:
        _, _, row = guarded
        if unit.child_id != job.child_id:
            raise ProviderError("Die vorbereitete Runde gehört nicht zu diesem Kind.")
        validate_prepared_output(db, job, {"subject": unit.subject, "topic": unit.topic, "questions": unit.questions})
        row.unit_id = unit.id


def reminder_instant(day, clock, zone):
    value = datetime.combine(day, datetime.strptime(clock, "%H:%M").time(), zone)
    # A spring-forward clock gap has no such instant. Use the first real local
    # minute after it, rather than returning a future-created notification.
    while value.astimezone(timezone.utc).astimezone(zone).replace(tzinfo=None) != value.replace(tzinfo=None):
        value += timedelta(minutes=1)
    return value


def due_reminders(db, child, current=None):
    """Neutral notification candidates only; no catch-up backlog or queue side effect."""
    instant = datetime.now(timezone.utc) if current is None else current
    if isinstance(instant, (int, float)):
        instant = datetime.fromtimestamp(instant, timezone.utc)
    if instant.tzinfo is None:
        raise ValueError("Reminder time must be timezone-aware")
    result = []
    for exam in db.scalars(select(Exam).where(Exam.child_id == child.id, Exam.archived.is_(False),
            Exam.reminders.is_(True)).order_by(Exam.id).limit(MAX_OPEN_EXAMS)):
        local = instant.astimezone(ZoneInfo(exam.timezone))
        scheduled = reminder_instant(local.date(), exam.reminder_time, ZoneInfo(exam.timezone))
        if instant.timestamp() < scheduled.timestamp():
            continue
        session = db.scalar(select(ExamSession).where(ExamSession.exam_id == exam.id,
            ExamSession.exam_revision == exam.plan_revision, ExamSession.date == local.date().isoformat()))
        if not session or session_data(db, exam, session)["status"] == "completed":
            continue
        result.append({"exam_id": exam.id, "session_id": session.id, "scheduled_date": session.date,
            "created": int(scheduled.timestamp()), "revision": exam.plan_revision,
            "route": f"/exams/{child.id}?exam={exam.id}&session={session.id}"})
    return result


def today_sessions(db, child, current=None):
    """Today's finite saved plan, independent of notification preferences."""
    instant = datetime.now(timezone.utc) if current is None else current
    if isinstance(instant, (int, float)):
        instant = datetime.fromtimestamp(instant, timezone.utc)
    if instant.tzinfo is None:
        raise ValueError("Overview time must be timezone-aware")
    result = []
    for exam in db.scalars(select(Exam).where(Exam.child_id == child.id, Exam.archived.is_(False))
            .order_by(Exam.updated.desc(), Exam.id).limit(MAX_OPEN_EXAMS)):
        day = instant.astimezone(ZoneInfo(exam.timezone)).date().isoformat()
        session = db.scalar(select(ExamSession).where(ExamSession.exam_id == exam.id,
            ExamSession.exam_revision == exam.plan_revision, ExamSession.date == day))
        if not session:
            continue
        value = session_data(db, exam, session)
        if value["status"] == "completed":
            continue
        result.append({"exam_id": exam.id, "session_id": session.id, "title": exam.title,
            "subject": exam.subject, "minutes": session.minutes, "requested_questions": value["requested_questions"],
            "route": f"/exams/{child.id}?exam={exam.id}&session={session.id}"})
        if len(result) == 3:
            break
    return result


def export_exams(db, child_id):
    """Caller must already have export authority; no raw answers or file paths added."""
    result = []
    for exam in db.scalars(select(Exam).where(Exam.child_id == child_id).order_by(Exam.created, Exam.id)):
        value = exam_data(db, exam)
        value["session_history"] = [{**session_data(db, exam, session), "exam_revision": session.exam_revision}
            for session in db.scalars(select(ExamSession).where(ExamSession.exam_id == exam.id,
                ExamSession.exam_revision != exam.plan_revision).order_by(ExamSession.exam_revision, ExamSession.date))]
        result.append(value)
    return result
