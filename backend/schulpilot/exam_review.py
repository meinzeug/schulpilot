"""Explicit source-bound written-work review through the existing tutor budget."""

import copy
import json
import re
import unicodedata
from itertools import combinations

from fastapi import APIRouter, Depends, Header, HTTPException, Query, UploadFile
from pydantic import ValidationError
from sqlalchemy import delete, select, update

from .commerce import usage_terms
from .db import DB, Family, Job, Material, ProviderConfig, Session, Usage, User, get_db, now, uid
from .exam_models import Exam
from .exam_review_models import (
    ExamReview,
    ExamReviewDraft,
    ExamReviewPage,
    ExamReviewPractice,
    ExamReviewTurn,
    ExamScanBatch,
)
from .exam_review_schemas import (
    ExamReviewOutput,
    ReviewAnalyze,
    ReviewContext,
    ReviewDraftInput,
    ReviewHelp,
    ReviewPractice,
)
from .model_routing import job_config
from .providers import ProviderError, Result, external_allowed, request_provider, reserve, settle
from .security import Principal, audit, authenticated, child_user, digest, rate_limit
from .tutor_schemas import TutorOutput

router = APIRouter(tags=["Schriftliche Arbeiten besprechen"])
KEY = Header(..., alias="Idempotency-Key", min_length=16, max_length=80, pattern=r"^[A-Za-z0-9_-]+$")
MAX_PAGES = 12
MAX_CONTENT = 60_000


def fresh_actor(db, p):
    user = db.get(User, p.user.id, populate_existing=True)
    session = db.get(Session, p.session.id, populate_existing=True)
    if (
        not user
        or user.disabled
        or not user.verified
        or not session
        or session.user_id != user.id
        or session.revoked
        or session.expires <= now()
        or now() - session.seen > 7 * 86400
    ):
        raise HTTPException(401, "Bitte erneut anmelden.")
    return Principal(user, session)


def access(db, p, exam_id, *, write=False):
    from .exams import access_exam

    p = fresh_actor(db, p) if write else p
    exam, child = access_exam(db, p, exam_id, write=write)
    if write and exam.archived:
        raise HTTPException(409, "Diese Arbeit ist archiviert.")
    return exam, child


def page_rows(db, exam):
    return list(
        db.scalars(
            select(ExamReviewPage)
            .where(ExamReviewPage.exam_id == exam.id)
            .order_by(ExamReviewPage.position, ExamReviewPage.id)
        )
    )


def source_context(db, exam, child, *, require_confirmed=False):
    pages = [db.get(Material, row.material_id, populate_existing=True) for row in page_rows(db, exam)]
    if any(not page or page.child_id != child.id or page.purpose != "exam" for page in pages):
        raise HTTPException(409, "Die Seiten dieser Arbeit wurden verändert.")
    if len(pages) > MAX_PAGES:
        raise HTTPException(422, "Bitte höchstens zwölf Seiten besprechen.")
    if require_confirmed and sum(len(page.content or "") for page in pages) > MAX_CONTENT:
        raise HTTPException(
            422, "Die Texte sind für eine Besprechung zu umfangreich. Bitte höchstens 60000 Zeichen auswählen."
        )
    refs = [
        {"id": page.id, "revision": page.revision, "ref": f"p{index + 1}", "label": f"Seite {index + 1}"}
        for index, page in enumerate(pages)
    ]
    signature = digest(
        json.dumps(
            [
                exam.id,
                exam.revision,
                exam.archived,
                child.family_id,
                child.preferences,
                [[page.id, page.revision, page.confirmed, page.content, page.uncertainties] for page in pages],
            ],
            sort_keys=True,
            ensure_ascii=False,
        )
    )
    if require_confirmed and (not pages or any(not p.confirmed or not p.content.strip() for p in pages)):
        raise HTTPException(409, "Bitte zuerst den erkannten Text aller Arbeitsseiten prüfen und bestätigen.")
    return signature, refs, pages


def guard_context(db, p, exam_id, data):
    exam, child = access(db, p, exam_id, write=True)
    signature, refs, pages = source_context(db, exam, child)
    if exam.revision != data.revision or signature != data.context_revision:
        raise HTTPException(409, "Die Arbeit oder ihre Quellen wurden geändert. Bitte neu laden.")
    return exam, child, signature, refs, pages


def draft_data(row):
    return {"text": row.text, "revision": row.revision, "updated": row.updated} if row else None


def turn_data(db, turn):
    job = db.get(Job, turn.job_id) if turn.job_id else None
    status = turn.status
    if status in ("queued", "running"):
        status = job.status if job and job.status in ("queued", "running") else "failed"
    return {
        "id": turn.id,
        "task_id": turn.task_id,
        "job_id": turn.job_id,
        "status": status,
        "action": turn.action,
        "draft": turn.draft,
        "reply": turn.reply if status == "ready" else None,
        "assessment": "ai_opinion" if turn.action == "check" else None,
        "error": turn.error or (job.error if job and status == "failed" else None),
        "created": turn.created,
    }


def same_subject(material, exam):
    return (
        material.subject_id == exam.subject_id
        if material.subject_id and exam.subject_id
        else normalized(material.subject).casefold() == normalized(exam.subject).casefold()
    )


def notebook_sources(db, exam, child):
    from .source_lineage import usable_source

    return [
        {"id": m.id, "revision": m.revision, "subject": m.subject, "topic": m.topic, "title": m.title}
        for m in db.scalars(
            select(Material)
            .where(Material.child_id == child.id, Material.purpose == "notebook", Material.confirmed.is_(True))
            .order_by(Material.created.desc(), Material.id)
            .limit(200)
        )
        if usable_source(db, m) and same_subject(m, exam)
    ]


def arithmetic_warnings(answer):
    """Check only complete literal equations in the transcribed answer.

    A mathematical contradiction is not a judgment about handwriting, the
    teacher's markings, or the entire task. Never modify the original report.
    """
    from .source_lineage import false_equality

    if not isinstance(answer, str):
        return []
    candidates = []
    for line in answer.splitlines():
        # Parenthesized TeX has explicit boundaries even when a teacher's
        # annotation follows it on the same line.
        segments = re.findall(r"\\\((.*?)\\\)|\\\[(.*?)\\\]", line)
        candidates.extend(next(value for value in segment if value) for segment in segments if any(segment))
        if not segments:
            candidates.append(line.strip())
    warnings = []
    for expression in candidates[:16]:
        if false_equality(expression):
            warnings.append({"expression": expression, "message": "Diese Gleichung stimmt rechnerisch nicht. Prüfe auch, ob sie richtig abgeschrieben wurde."})
    return warnings


def projection(db, p, exam, child):
    from .exams import can_manage
    from .materials import material_data

    signature, refs, pages = source_context(db, exam, child)
    row = db.scalar(select(ExamReview).where(ExamReview.exam_id == exam.id))
    status = "empty" if not pages else "unconfirmed" if any(not m.confirmed for m in pages) else "empty"
    report = {}
    if row:
        status = "stale" if row.context_revision != signature else row.status
        if status in ("queued", "running"):
            job = db.get(Job, row.job_id) if row.job_id else None
            status = job.status if job and job.status in ("queued", "running") else "failed"
        if status == "ready":
            report = copy.deepcopy(row.report)
    tasks = report.get("tasks", [])
    for task in tasks:
        task["arithmetic_warnings"] = arithmetic_warnings(task.get("original_answer"))
    batches = (row.report or {}).get("analysis_batches", []) if row and row.context_revision == signature else []
    # The first model summary remains an immutable part of the saved report.
    # Describe the current aggregate from persisted facts instead of presenting
    # that first extract (or a later empty extract) as the whole current result.
    latest_successful_batch = None
    summary = ""
    if status == "ready":
        task_count = len(tasks)
        summary = (
            "Aktuell ist 1 Aufgabe zur Nacharbeit gespeichert."
            if task_count == 1
            else f"Aktuell sind {task_count} Aufgaben zur Nacharbeit gespeichert."
            if task_count
            else "Aktuell sind noch keine Aufgaben zur Nacharbeit gespeichert."
        )
        summary += " Kleiner KI-Auszug · keine vollständige Auswertung."
        for number, batch in reversed(list(enumerate(batches, start=1))):
            if batch.get("status") == "ready":
                latest_successful_batch = {"number": number, **batch_data(batch)}
                added = batch.get("added_tasks")
                summary += f" Letzter erfolgreicher KI-Auszug {number}: "
                if type(added) is int and added >= 0:
                    summary += f"{added} neue Aufgabe" + ("." if added == 1 else "n.")
                else:
                    summary += "gespeichert."
                break
        if not batches:
            summary += " Gespeicherte Altanalyse ohne Einzelverlauf."
    if p.user.role == "child":
        drafts = list(
            db.scalars(
                select(ExamReviewDraft).where(
                    ExamReviewDraft.exam_id == exam.id,
                    ExamReviewDraft.user_id == p.user.id,
                    ExamReviewDraft.session_id == p.session.id,
                    ExamReviewDraft.context_revision == signature,
                    ExamReviewDraft.updated >= int(now()) - 86400,
                )
            )
        )
        by_task = {draft.task_id: draft for draft in drafts}
        for task in tasks:
            task["draft"] = draft_data(by_task.get(task["id"]))
    turns = (
        list(
            db.scalars(
                select(ExamReviewTurn)
                .where(
                    ExamReviewTurn.exam_id == exam.id,
                    ExamReviewTurn.user_id == p.user.id,
                    ExamReviewTurn.session_id == p.session.id,
                    ExamReviewTurn.context_revision == signature,
                )
                .order_by(ExamReviewTurn.created.desc(), ExamReviewTurn.id.desc())
                .limit(20)
            )
        )
        if p.user.role == "child"
        else []
    )
    manage = can_manage(db, p, child) and not exam.archived
    return {
        "exam_id": exam.id,
        "child_id": child.id,
        "revision": exam.revision,
        "context_revision": signature,
        "status": status,
        "pages": [material_data(page) for page in pages],
        "source_revisions": refs,
        "analysis_id": row.id if row else None,
        "analysis_revision": row.revision if row else 0,
        "summary": summary,
        "report_summary": report.get("summary", ""),
        "task_count": len(tasks),
        "latest_successful_batch": latest_successful_batch,
        "uncertainties": report.get("uncertainties", []),
        "tasks": tasks,
        "turns": [turn_data(db, turn) for turn in reversed(turns)],
        "practice_units": [
            {"task_id": link.task_id, "unit_id": link.unit_id}
            for link in db.scalars(
                select(ExamReviewPractice)
                .where(ExamReviewPractice.exam_id == exam.id, ExamReviewPractice.context_revision == signature)
                .order_by(ExamReviewPractice.created)
            )
        ],
        "error": row.error if row else None,
        "can_manage": manage,
        "can_analyze": manage
        and any(m.confirmed and m.content.strip() for m in pages)
        and status not in ("queued", "running")
        and not (row and batch_pending(row)),
        "can_analyze_more": manage
        and status == "ready"
        and len(batches) < 12
        and not batch_pending(row)
        and analysis_choice_available(pages, row.report),
        "analysis_batch": batch_data(batches[-1]) if batches else None,
        "analysis_batches": [batch_data(batch) for batch in batches],
        "notebook_sources": notebook_sources(db, exam, child),
        "scan": scan_data(db, exam, child, manage=manage),
        "notice": (
            "Kleiner KI-Auszug · einzelne Aufgaben je bewusster Analyse, keine vollständige Auswertung. Originalaufgabe, alte Antwort und Lehrermarkierung bleiben getrennt. KI-Hinweise sind Vorschläge, keine Note oder neuen Lernbelege."
            + (
                " Der erkannte Text ist für einen einzelnen Auszug zu umfangreich. Bitte jeweils Arbeitsseiten mit insgesamt höchstens 60000 Zeichen auswählen."
                if sum(len(m.content or "") for m in pages) > MAX_CONTENT
                else ""
            )
        ),
    }


@router.get("/exams/{exam_id}/review")
def read_review(exam_id: str, p=Depends(authenticated), db=Depends(get_db)):
    exam, child = access(db, p, exam_id)
    return projection(db, p, exam, child)


def validate_upload(db, p, child, exam_id, revision, *, existing=None):
    exam, owner = access(db, p, exam_id, write=True)
    if owner.id != child.id:
        raise HTTPException(404, "Arbeit nicht gefunden.")
    if existing:
        link = db.scalar(select(ExamReviewPage).where(ExamReviewPage.material_id == existing.id))
        if not link or link.exam_id != exam.id or link.upload_revision != revision:
            raise HTTPException(409, "Dieser Uploadschlüssel gehört zu einer anderen Arbeitsseite.")
        return exam
    if exam.revision != revision:
        raise HTTPException(409, "Die Arbeit wurde geändert. Bitte neu laden.")
    if len(page_rows(db, exam)) >= MAX_PAGES:
        raise HTTPException(422, "Eine Arbeit kann höchstens zwölf Fotos enthalten.")
    return exam


def attach_uploaded(db, p, child, material, exam_id, revision):
    exam = validate_upload(db, p, child, exam_id, revision)
    rows = page_rows(db, exam)
    db.add(
        ExamReviewPage(
            exam_id=exam.id,
            material_id=material.id,
            position=max((row.position for row in rows), default=0) + 1,
            upload_revision=revision,
        )
    )
    exam.revision += 1
    exam.updated = int(now())


@router.post("/exams/{exam_id}/pages", status_code=201)
def upload_page(
    exam_id: str,
    file: UploadFile,
    revision: int = Query(..., ge=1),
    key: str = KEY,
    p=Depends(authenticated),
    db=Depends(get_db),
):
    from .materials import upload

    exam, child = access(db, p, exam_id, write=True)
    upload(child.id, file, purpose="exam", idempotency_key=key, p=p, db=db, exam_id=exam.id, exam_revision=revision)
    exam = db.get(Exam, exam.id, populate_existing=True)
    return projection(db, p, exam, child)


def task_for(db, p, exam_id, task_id, data):
    exam, child, signature, refs, pages = guard_context(db, p, exam_id, data)
    if p.user.role != "child" or child.user_id != p.user.id:
        raise HTTPException(403, "Eigene Berichtigungen und Lernhilfen gehören zum Kinderzugang.")
    review = db.scalar(select(ExamReview).where(ExamReview.exam_id == exam.id))
    task = next((task for task in (review.report.get("tasks", []) if review else []) if task["id"] == task_id), None)
    if not review or review.status != "ready" or review.context_revision != signature or not task:
        raise HTTPException(409, "Bitte die aktuelle Aufgabenbesprechung neu öffnen.")
    cited_ids = {citation["material_id"] for citation in task["sources"]}
    if any(not page.confirmed or not page.content.strip() for page in pages if page.id in cited_ids):
        raise HTTPException(409, "Bitte die aktuellen Originalseiten dieser Aufgabe bestätigen.")
    return exam, child, signature, refs, pages, review, task


def job_request(db, p, exam, child, signature, refs, action, key, *, review, turn=None, request=None, batch=None):
    family = db.get(Family, child.family_id)
    if family.synthetic:
        raise HTTPException(403, "Eigene Arbeitsbesprechungen benötigen ein reguläres Familienkonto.")
    usage_terms(db, family, enforce=True)
    prefix = "exam-review:" + digest(p.user.id + ":" + child.id + ":" + key)
    request_hash = digest(json.dumps(request, sort_keys=True, ensure_ascii=False))
    old = db.scalar(select(Job).where(Job.idempotency == prefix))
    if old:
        if old.payload.get("request_hash") != request_hash or old.child_id != child.id:
            raise HTTPException(409, "Dieser Schlüssel gehört zu einer anderen Anfrage.")
        return old
    if db.scalar(select(Job.id).where(Job.child_id == child.id, Job.status.in_(["queued", "running"]))):
        raise HTTPException(409, "Für dieses Kind wird bereits eine Verarbeitung ausgeführt.")
    job = Job(
        id=uid(),
        child_id=child.id,
        kind="exam_review",
        idempotency=prefix,
        payload={
            "exam_id": exam.id,
            "review_id": review.id,
            "turn_id": turn.id if turn else None,
            "action": action,
            "signature": signature,
            "family_id": child.family_id,
            "user_id": p.user.id,
            "session_id": p.session.id,
            "material_revisions": refs,
            "request_hash": request_hash,
            **({"analysis_batch_id": batch["id"]} if batch else {}),
        },
    )
    db.add(job)
    db.flush()
    reserve(db, family, child.id, job.id, "tutor")
    if turn:
        turn.job_id = job.id
        db.add(turn)
    elif review.status != "ready":
        review.job_id = job.id
    if batch is not None:
        batch["job_id"] = job.id
    exam.updated = int(now())
    audit(db, p.user.id, "exam.review_request", exam.id)
    return job


def batch_data(batch):
    return {key: batch.get(key) for key in ("id", "status", "error", "page_ids", "added_tasks", "summary")}


def analysis_window(report):
    return digest(json.dumps(sorted(task["id"] for task in report.get("tasks", []))))


def window_attempts(batches, selected_ids, window):
    return sum(
        set(batch.get("page_ids", [])) == set(selected_ids) and batch.get("window_hash") == window for batch in batches
    )


def analysis_choice_available(pages, report):
    """At most twelve source pages; this only inspects saved bounded metadata."""
    eligible = [p for p in pages if p.confirmed and p.content.strip() and len(p.content) <= MAX_CONTENT]
    window = analysis_window(report)
    for size in range(1, len(eligible) + 1):
        for selected in combinations(eligible, size):
            if (
                sum(len(p.content) for p in selected) <= MAX_CONTENT
                and window_attempts(report.get("analysis_batches", []), [p.id for p in selected], window) < 2
            ):
                return True
    return False


def batch_pending(review):
    return any(b.get("status") in ("queued", "running") for b in (review.report or {}).get("analysis_batches", []))


@router.post("/exams/{exam_id}/review/analyze", status_code=202)
def analyze(exam_id: str, data: ReviewAnalyze, key: str = KEY, p=Depends(authenticated), db=Depends(get_db)):
    exam, child = access(db, p, exam_id, write=True)
    signature, refs, pages = source_context(db, exam, child)
    if exam.revision != data.revision or signature != data.context_revision:
        raise HTTPException(409, "Die Arbeit oder ihre Quellen wurden geändert. Bitte neu laden.")
    selected_ids = data.page_ids or [page.id for page in pages]
    selected = [page for page in pages if page.id in selected_ids]
    if not selected or len(selected) != len(selected_ids):
        raise HTTPException(409, "Bitte eigene aktuelle Arbeitsseiten für den Auszug auswählen.")
    if any(not page.confirmed or not page.content.strip() for page in selected):
        raise HTTPException(409, "Bitte zuerst den erkannten Text der ausgewählten Arbeitsseiten bestätigen.")
    if sum(len(page.content) for page in selected) > MAX_CONTENT:
        raise HTTPException(422, "Bitte für einen Auszug höchstens 60000 bestätigte Zeichen auswählen.")
    rate_limit(db, "exam-review:" + p.user.id, 12, 3600, commit=False)
    review = db.scalar(select(ExamReview).where(ExamReview.exam_id == exam.id))
    request = {"exam_id": exam.id, "action": "analyze", **data.model_dump()}
    previous = db.scalar(
        select(Job).where(Job.idempotency == "exam-review:" + digest(p.user.id + ":" + child.id + ":" + key))
    )
    if previous:
        if previous.payload.get("request_hash") != digest(json.dumps(request, sort_keys=True, ensure_ascii=False)):
            raise HTTPException(409, "Dieser Schlüssel gehört zu einer anderen Anfrage.")
        return {
            "id": previous.id,
            "job_id": previous.id,
            "status": previous.status,
            "batch_id": previous.payload.get("analysis_batch_id"),
        }
    same = bool(review and review.context_revision == signature)
    has_ready = same and review.status == "ready"
    if data.append and not has_ready:
        raise HTTPException(409, "Bitte zuerst den aktuellen ersten KI-Auszug öffnen.")
    if has_ready and not data.append:
        return {"id": review.job_id, "job_id": review.job_id, "status": "completed"}
    report = copy.deepcopy(review.report) if same else {}
    batches = report.setdefault("analysis_batches", [])
    if len(batches) >= 12:
        raise HTTPException(409, "Die zwölf begrenzten KI-Auszüge für diesen Quellenstand sind ausgeschöpft.")
    selected_ids = [page.id for page in selected]
    window = analysis_window(report)
    if window_attempts(batches, selected_ids, window) >= 2:
        raise HTTPException(
            409,
            "Für diese Seitenauswahl und die bisher gespeicherten Aufgaben gab es zwei Versuche. Bitte die Quelle prüfen oder einen anderen begrenzten Auszug wählen.",
        )
    if same and batch_pending(review):
        raise HTTPException(409, "Ein KI-Auszug wird gerade vorbereitet.")
    batch = {
        "id": uid(),
        "page_ids": selected_ids,
        "status": "queued",
        "error": None,
        "added_tasks": 0,
        "summary": "",
        "job_id": None,
        "append": data.append,
        "window_hash": window,
    }
    if review is None:
        review = ExamReview(
            id=uid(),
            exam_id=exam.id,
            child_id=child.id,
            user_id=p.user.id,
            session_id=p.session.id,
            context_revision=signature,
            source_revisions=refs,
        )
        db.add(review)
    else:
        review.revision += 1
        if not has_ready:
            review.status, review.error = "queued", None
        review.context_revision, review.source_revisions = signature, refs
        review.user_id, review.session_id, review.updated = p.user.id, p.session.id, int(now())
    db.flush()
    job = job_request(db, p, exam, child, signature, refs, "analyze", key, review=review, request=request, batch=batch)
    batches.append(batch)
    review.report = report
    db.commit()
    return {"id": job.id, "job_id": job.id, "status": job.status, "batch_id": batch["id"]}


@router.put("/exams/{exam_id}/review/tasks/{task_id}/draft")
def save_draft(exam_id: str, task_id: str, data: ReviewDraftInput, p=Depends(child_user), db=Depends(get_db)):
    exam, child, signature, _, _, _, _ = task_for(db, p, exam_id, task_id, data)
    row = db.scalar(
        select(ExamReviewDraft).where(
            ExamReviewDraft.exam_id == exam.id,
            ExamReviewDraft.user_id == p.user.id,
            ExamReviewDraft.session_id == p.session.id,
            ExamReviewDraft.task_id == task_id,
        )
    )
    current = bool(
        row
        and row.session_id == p.session.id
        and row.context_revision == signature
        and row.updated >= int(now()) - 86400
    )
    if (row.revision if current else 0) != data.draft_revision:
        raise HTTPException(409, "Der eigene Entwurf wurde inzwischen geändert.")
    if row is None:
        row = ExamReviewDraft(exam_id=exam.id, child_id=child.id, user_id=p.user.id, task_id=task_id)
        db.add(row)
    row.revision = row.revision + 1 if current else 1
    row.context_revision, row.session_id, row.text, row.updated = signature, p.session.id, data.text, int(now())
    db.flush()
    # Mutations, never GET, enforce the existing eight-draft/one-day bound.
    db.execute(
        delete(ExamReviewDraft).where(
            ExamReviewDraft.child_id == child.id, ExamReviewDraft.updated < int(now()) - 86400
        )
    )
    keep = list(
        db.scalars(
            select(ExamReviewDraft.id)
            .where(ExamReviewDraft.child_id == child.id)
            .order_by(ExamReviewDraft.updated.desc(), ExamReviewDraft.id.desc())
            .limit(8)
        )
    )
    db.execute(delete(ExamReviewDraft).where(ExamReviewDraft.child_id == child.id, ExamReviewDraft.id.not_in(keep)))
    exam.updated = int(now())
    db.commit()
    return {"draft": draft_data(row)}


@router.post("/exams/{exam_id}/review/tasks/{task_id}/help", status_code=202)
def request_help(
    exam_id: str, task_id: str, data: ReviewHelp, key: str = KEY, p=Depends(child_user), db=Depends(get_db)
):
    exam, child, signature, refs, _, review, _ = task_for(db, p, exam_id, task_id, data)
    request = {"exam_id": exam.id, "task_id": task_id, **data.model_dump()}
    previous = db.scalar(
        select(Job).where(Job.idempotency == "exam-review:" + digest(p.user.id + ":" + child.id + ":" + key))
    )
    if previous:
        if previous.payload.get("request_hash") != digest(json.dumps(request, sort_keys=True, ensure_ascii=False)):
            raise HTTPException(409, "Dieser Schlüssel gehört zu einer anderen Anfrage.")
        turn = db.get(ExamReviewTurn, previous.payload.get("turn_id"))
        if not turn or turn.user_id != p.user.id or turn.session_id != p.session.id:
            raise HTTPException(409, "Diese frühere Hilfe ist nicht mehr verfügbar.")
        return turn_data(db, turn)
    if data.action == "check" and not data.draft.strip():
        raise HTTPException(422, "Bitte zuerst einen eigenen Überarbeitungsversuch schreiben.")
    rate_limit(db, "exam-help:" + p.user.id, 12, 600, commit=False)
    turn = ExamReviewTurn(
        id=uid(),
        exam_id=exam.id,
        review_id=review.id,
        child_id=child.id,
        user_id=p.user.id,
        session_id=p.session.id,
        task_id=task_id,
        context_revision=signature,
        source_revisions=refs,
        action=data.action,
        draft=data.draft,
    )
    job_request(db, p, exam, child, signature, refs, data.action, key, review=review, turn=turn, request=request)
    db.commit()
    return turn_data(db, turn)


@router.get("/exams/{exam_id}/review/turns/{turn_id}")
def read_turn(exam_id: str, turn_id: str, p=Depends(child_user), db=Depends(get_db)):
    exam, child = access(db, p, exam_id)
    turn = db.get(ExamReviewTurn, turn_id)
    signature = source_context(db, exam, child)[0]
    if (
        not turn
        or turn.exam_id != exam.id
        or turn.user_id != p.user.id
        or turn.session_id != p.session.id
        or turn.context_revision != signature
    ):
        raise HTTPException(404, "Hilfe nicht gefunden.")
    return turn_data(db, turn)


def normalized(value):
    return " ".join(unicodedata.normalize("NFC", value).split())


def checked_report(data, sources, refs):
    try:
        report = ExamReviewOutput.model_validate(data).model_dump()
    except ValidationError:
        raise ProviderError("Die Aufgabenbesprechung konnte nicht sicher geprüft werden.") from None
    by_ref, metadata = {row["ref"]: row for row in sources}, {row["ref"]: row for row in refs}
    for task in report["tasks"]:
        if len(normalized(task["question"])) < 3:
            raise ProviderError("Die Originalaufgabe fehlt in der Quelle.")
        cited = []
        for citation in task["sources"]:
            source = by_ref.get(citation["ref"])
            if (
                not source
                or len(normalized(citation["quote"])) < 3
                or normalized(citation["quote"]) not in normalized(source["content"])
            ):
                raise ProviderError("Ein Beleg der Arbeitsbesprechung fehlt in der bestätigten Quelle.")
            cited.append(source)
            citation.update(material_id=metadata[citation["ref"]]["id"], label=metadata[citation["ref"]]["label"])
        for field in ("question", "original_answer", "teacher_feedback", "score_label"):
            value = task[field]
            if value and not any(normalized(value) in normalized(source["content"]) for source in cited):
                raise ProviderError("Originalantwort, Lehrermarkierung oder Aufgabe ist nicht wörtlich belegt.")
        task["needs_review"] = True
    return report


def authority(db, job):
    user, session = db.get(User, job.payload["user_id"]), db.get(Session, job.payload["session_id"])
    if not user or not session:
        raise HTTPException(401, "Dieser Zugang ist nicht mehr verfügbar.")
    p = fresh_actor(db, Principal(user, session))
    exam, child = access(db, p, job.payload["exam_id"], write=True)
    if child.id != job.child_id or child.family_id != job.payload["family_id"]:
        raise HTTPException(403, "Der Familienkontext wurde geändert.")
    family = db.get(Family, child.family_id)
    if family.synthetic:
        raise HTTPException(403, "Eigene Arbeitsbesprechungen sind im Beispiel nicht verfügbar.")
    usage_terms(db, family, enforce=True)
    signature, refs, pages = source_context(db, exam, child)
    if signature != job.payload["signature"]:
        raise ProviderError("Die Arbeit oder ihre Quellen wurden geändert.")
    review = db.get(ExamReview, job.payload["review_id"])
    if not review or review.exam_id != exam.id or review.context_revision != signature:
        raise ProviderError("Diese Besprechung ist nicht mehr aktuell.")
    turn = db.get(ExamReviewTurn, job.payload.get("turn_id")) if job.payload.get("turn_id") else None
    if turn and (
        turn.job_id != job.id or turn.user_id != user.id or user.role != "child" or turn.context_revision != signature
    ):
        raise ProviderError("Diese Hilfe ist nicht mehr aktuell.")
    if job.payload["action"] != "analyze" and turn is None:
        raise ProviderError("Die eigene Überarbeitung ist nicht mehr vorhanden.")
    batch = next(
        (
            b
            for b in (review.report or {}).get("analysis_batches", [])
            if b["id"] == job.payload.get("analysis_batch_id")
        ),
        None,
    )
    if job.payload["action"] == "analyze":
        if not batch or batch.get("job_id") != job.id or batch.get("status") not in ("queued", "running"):
            raise ProviderError("Dieser KI-Auszug ist nicht mehr aktuell.")
        selected_ids = set(batch["page_ids"])
    else:
        task = next((t for t in review.report.get("tasks", []) if t["id"] == turn.task_id), None)
        if not task:
            raise ProviderError("Die ursprüngliche Aufgabe wurde geändert.")
        selected_ids = {citation["material_id"] for citation in task["sources"]}
    paired = [(ref, page) for ref, page in zip(refs, pages, strict=True) if page.id in selected_ids]
    if len(paired) != len(selected_ids) or any(not page.confirmed or not page.content.strip() for _, page in paired):
        raise ProviderError("Die ausgewählten Originalseiten wurden geändert.")
    if sum(len(page.content) for _, page in paired) > MAX_CONTENT:
        raise ProviderError("Die ausgewählten Originalseiten sind zu umfangreich.")
    refs = [ref for ref, _ in paired]
    sources = [{"ref": ref["ref"], "label": ref["label"], "content": page.content} for ref, page in paired]
    payload = {
        "grade": child.grade,
        "sources": sources,
        "history": [],
        "exam_context": {
            "action": job.payload["action"],
            "subject": exam.subject,
            **(
                {
                    "previous_questions": previous_questions(review),
                    "scope": "Kleiner KI-Auszug mit einzelnen weiteren Aufgaben, keine Vollständigkeitsbehauptung",
                }
                if job.payload["action"] == "analyze"
                else {}
            ),
            **(
                {
                    "task": next((task for task in review.report.get("tasks", []) if task["id"] == turn.task_id), None),
                    "draft": turn.draft,
                }
                if turn
                else {}
            ),
        },
    }
    if turn and payload["exam_context"]["task"] is None:
        raise ProviderError("Die ursprüngliche Aufgabe wurde geändert.")
    return review, turn, payload, refs


def previous_questions(review):
    """A bounded model hint; all previous questions are still checked server-side."""
    result, length = [], 0
    for task in review.report.get("tasks", []):
        question = task["question"]
        if len(result) >= 32 or length + len(question) > 6000:
            break
        result.append(question)
        length += len(question)
    return result


def merge_report(review, job, checked):
    report = copy.deepcopy(review.report)
    batch = next(b for b in report["analysis_batches"] if b["id"] == job.payload["analysis_batch_id"])
    previous = report.get("tasks", [])
    all_questions = {normalized(t["question"]) for t in previous}
    new_questions = [normalized(t["question"]) for t in checked["tasks"]]
    if len(set(new_questions)) != len(new_questions) or any(q in all_questions for q in new_questions):
        raise ProviderError(
            "Der neue KI-Auszug wiederholt eine bereits gespeicherte Originalaufgabe. Der bisherige Stand bleibt erhalten."
        )
    for task in checked["tasks"]:
        task["id"] = digest(
            json.dumps(
                [
                    review.context_revision,
                    normalized(task["question"]),
                    [(citation["material_id"], normalized(citation["quote"])) for citation in task["sources"]],
                ],
                sort_keys=True,
                ensure_ascii=False,
            )
        )[:32]
    if len(previous) + len(checked["tasks"]) > 96:
        raise ProviderError("Die begrenzten Aufgabenauszüge sind ausgeschöpft.")
    report["tasks"] = [*previous, *checked["tasks"]]
    summary = "Kleiner KI-Auszug · keine vollständige Auswertung. " + checked["summary"]
    report["summary"] = report.get("summary") or summary
    report["uncertainties"] = list(dict.fromkeys([*report.get("uncertainties", []), *checked["uncertainties"]]))
    batch.update(status="ready", error=None, summary=summary, added_tasks=len(checked["tasks"]))
    review.status, review.report, review.error, review.updated, review.job_id = (
        "ready",
        report,
        None,
        int(now()),
        job.id,
    )


def process(job_id):
    result = None
    try:
        with DB() as db:
            job = db.get(Job, job_id)
            if not job or job.kind != "exam_review" or job.status != "running":
                return
            review, turn, payload, refs = authority(db, job)
            config = job_config(db, job, "tutor")
            usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
            if not usage or (usage.provider, usage.model, usage.config_revision) != (
                config.provider,
                config.model,
                config.revision,
            ):
                raise ProviderError("Die KI-Einstellungen wurden geändert.")
            external_allowed(config)
            if turn:
                turn.status = "running"
            else:
                report = copy.deepcopy(review.report)
                batch = next(b for b in report["analysis_batches"] if b["id"] == job.payload["analysis_batch_id"])
                batch["status"] = "running"
                review.report = report
                if review.status != "ready":
                    review.status = "running"
            values = {column.name: getattr(config, column.name) for column in ProviderConfig.__table__.columns}
            db.commit()
        result = request_provider(ProviderConfig(**values), "tutor", payload)
        if payload["exam_context"]["action"] == "analyze":
            checked = checked_report(result.data, payload["sources"], refs)
        else:
            from .tutor import checked_reply

            parsed = TutorOutput.model_validate(result.data).model_dump()
            if any(len(normalized(citation["quote"])) < 3 for citation in parsed["sources"]):
                raise ProviderError("Die Hilfe braucht einen echten wörtlichen Beleg.")
            checked = checked_reply(
                parsed, {key: value for key, value in payload.items() if key != "exam_context"}, refs
            )
        with DB.begin() as db:
            job = db.get(Job, job_id)
            if not job or job.status != "running":
                return
            review, turn, current, current_refs = authority(db, job)
            config = job_config(db, job, "tutor")
            if {name: getattr(config, name) for name in ("provider", "model", "revision")} != {
                name: values[name] for name in ("provider", "model", "revision")
            }:
                raise ProviderError("Die KI-Einstellung wurde während der Besprechung geändert.")
            external_allowed(config)
            if turn:
                turn.status, turn.reply, turn.error = "ready", checked, None
            else:
                merge_report(review, job, checked)
            job.status, job.finished, job.result = (
                "completed",
                int(now()),
                {"exam_id": review.exam_id, "review_id": review.id, **({"turn_id": turn.id} if turn else {})},
            )
            settle(db, db.scalar(select(Usage).where(Usage.job_id == job.id)), result)
    except Exception as error:
        reason = (
            str(error.detail)
            if isinstance(error, HTTPException)
            else str(error)
            if isinstance(error, ProviderError)
            else "Die Arbeit konnte gerade nicht sicher besprochen werden. Die Originale bleiben erhalten."
        )
        with DB.begin() as db:
            job = db.get(Job, job_id)
            if not job or job.status != "running":
                return
            job.status, job.error, job.finished = "failed", reason[:500], int(now())
            turn = db.get(ExamReviewTurn, job.payload.get("turn_id")) if job.payload.get("turn_id") else None
            review = db.get(ExamReview, job.payload.get("review_id"))
            if turn:
                turn.status, turn.error, turn.reply = "failed", reason[:500], None
            elif review:
                report = copy.deepcopy(review.report)
                batch = next(
                    (b for b in report.get("analysis_batches", []) if b["id"] == job.payload.get("analysis_batch_id")),
                    None,
                )
                if batch and batch.get("job_id") == job.id:
                    batch.update(status="failed", error=reason[:500])
                    review.report = report
                if review.status != "ready" and review.job_id == job.id:
                    review.status, review.error = "failed", reason[:500]
            usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
            if usage:
                settle(db, usage, result or getattr(error, "billing_result", None), failed=True)


@router.post("/exams/{exam_id}/review/tasks/{task_id}/practice", status_code=202)
def request_practice(
    exam_id: str, task_id: str, data: ReviewPractice, key: str = KEY, p=Depends(child_user), db=Depends(get_db)
):
    from .materials import enqueue

    exam, child, signature, _, _, review, task = task_for(db, p, exam_id, task_id, data)
    pages = [db.get(Material, material_id, populate_existing=True) for material_id in data.material_ids]
    if any(
        not m
        or m.child_id != child.id
        or m.purpose != "notebook"
        or not m.confirmed
        or not m.content.strip()
        or not same_subject(m, exam)
        for m in pages
    ):
        raise HTTPException(409, "Bitte bestätigte eigene Heftseiten desselben Fachs auswählen.")
    from .learning_sources import UnusableSources, project

    try:
        safe = project(db, pages)
    except UnusableSources as error:
        raise HTTPException(409, str(error)) from None
    if any(not value["content"].strip() for value in safe):
        raise HTTPException(409, "Bitte nur Heftseiten mit nutzbaren Quellenstellen auswählen.")
    if sum(len(value["content"]) for value in safe) > MAX_CONTENT:
        raise HTTPException(422, "Die ausgewählten Heftseiten sind zu umfangreich.")
    payload = {
        "material_id": pages[0].id,
        "sources": [{"id": m.id, "revision": m.revision} for m in pages],
        "exam_review_practice": {
            "exam_id": exam.id,
            "context_revision": signature,
            "review_id": review.id,
            "task_id": task["id"],
            "focus": task["question"],
            "user_id": p.user.id,
            "session_id": p.session.id,
            "family_id": child.family_id,
        },
    }
    exam.updated = int(now())
    return enqueue(db, p, child, "unit", payload, key)


def validate_practice_job(db, job):
    value = job.payload.get("exam_review_practice")
    if not value:
        return
    user, session = db.get(User, value["user_id"]), db.get(Session, value["session_id"])
    if not user or not session:
        raise ProviderError("Der Kinderzugang ist nicht mehr verfügbar.")
    p = fresh_actor(db, Principal(user, session))
    if user.role != "child":
        raise ProviderError("Diese Überarbeitung gehört zum Kinderzugang.")
    exam, child = access(db, p, value["exam_id"], write=True)
    if child.id != job.child_id or child.family_id != value["family_id"]:
        raise ProviderError("Der Familienkontext wurde geändert.")
    signature = source_context(db, exam, child)[0]
    review = db.get(ExamReview, value["review_id"])
    task = next(
        (task for task in (review.report.get("tasks", []) if review else []) if task["id"] == value["task_id"]), None
    )
    if (
        signature != value["context_revision"]
        or not review
        or review.status != "ready"
        or not task
        or task["question"] != value["focus"]
    ):
        raise ProviderError("Die Arbeitsbesprechung wurde geändert.")
    for ref in job.payload.get("sources", []):
        material = db.get(Material, ref["id"])
        if (
            not material
            or material.child_id != child.id
            or material.purpose != "notebook"
            or not material.confirmed
            or material.revision != ref["revision"]
        ):
            raise ProviderError("Die ausgewählte Heftquelle wurde geändert.")
        from .source_lineage import usable_source

        if not usable_source(db, material, revision=ref["revision"]):
            raise ProviderError("Die ausgewählte Heftquelle enthält keine nutzbare Lehrgrundlage mehr.")


def add_practice_context(db, job, payload):
    value = job.payload.get("exam_review_practice")
    if value:
        validate_practice_job(db, job)
        payload["written_review_focus"] = value["focus"]
    return payload


def cancel_jobs(db, exam_id):
    for job in db.scalars(select(Job).where(Job.status.in_(["queued", "running"]))):
        if job.payload.get("exam_id") != exam_id or not (job.kind == "exam_review" or job.payload.get("exam_scan_id")):
            continue
        cancelled = db.execute(
            update(Job)
            .where(Job.id == job.id, Job.status == "queued")
            .values(status="failed", error="Die Arbeitsquelle wurde entfernt.", finished=int(now()))
        )
        usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
        if cancelled.rowcount and usage:
            settle(db, usage, Result({}, 0, 0, 0), failed=True)
        elif not cancelled.rowcount:
            db.execute(
                update(Job)
                .where(Job.id == job.id, Job.status == "running")
                .values(status="failed", error="Die Arbeitsquelle wurde entfernt.", finished=int(now()))
            )


def purge_exam_review(db, exam_id):
    cancel_jobs(db, exam_id)
    # The original question is private report text even though the practice
    # round's factual sources are ordinary notebooks. Remove this extra copy
    # while preserving completed notebook rounds and actual billing records.
    for job in db.scalars(select(Job).where(Job.payload["exam_review_practice"]["exam_id"].as_string() == exam_id)):
        if job.status in ("queued", "running"):
            cancelled = db.execute(
                update(Job)
                .where(Job.id == job.id, Job.status == "queued")
                .values(status="failed", error="Die Arbeitsquelle wurde entfernt.", finished=int(now()))
            )
            usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
            if cancelled.rowcount and usage:
                settle(db, usage, Result({}, 0, 0, 0), failed=True)
            elif not cancelled.rowcount:
                db.execute(
                    update(Job)
                    .where(Job.id == job.id, Job.status == "running")
                    .values(status="failed", error="Die Arbeitsquelle wurde entfernt.", finished=int(now()))
                )
        job.payload = {key: value for key, value in job.payload.items() if key != "exam_review_practice"}
    db.execute(delete(ExamScanBatch).where(ExamScanBatch.exam_id == exam_id))
    db.execute(delete(ExamReviewPractice).where(ExamReviewPractice.exam_id == exam_id))
    db.execute(delete(ExamReviewDraft).where(ExamReviewDraft.exam_id == exam_id))
    db.execute(delete(ExamReviewTurn).where(ExamReviewTurn.exam_id == exam_id))
    db.execute(delete(ExamReview).where(ExamReview.exam_id == exam_id))


def source_removed(db, child_id, material_ids):
    ids = set(material_ids)
    query = (
        select(ExamReviewPage.exam_id)
        .join(Exam, Exam.id == ExamReviewPage.exam_id)
        .where(ExamReviewPage.material_id.in_(ids))
    )
    if child_id is not None:
        query = query.where(Exam.child_id == child_id)
    affected = set(db.scalars(query))
    for exam_id in affected:
        purge_exam_review(db, exam_id)
    return len(affected)


def clear_user_drafts(db, user_id, session_id=None):
    query = delete(ExamReviewDraft).where(ExamReviewDraft.user_id == user_id)
    if session_id is not None:
        query = query.where(ExamReviewDraft.session_id == session_id)
    db.execute(query)


def purge_expired(db, cutoff):
    exam_ids = list(db.scalars(select(Exam.id).where(Exam.updated < cutoff)))
    for exam_id in exam_ids:
        purge_exam_review(db, exam_id)
    live_sessions = select(Session.id).where(
        Session.revoked.is_(False), Session.expires > int(now()), Session.seen >= int(now()) - 7 * 86400
    )
    db.execute(delete(ExamReviewDraft).where(ExamReviewDraft.updated < int(now()) - 86400))
    db.execute(delete(ExamReviewDraft).where(ExamReviewDraft.session_id.not_in(live_sessions)))
    return len(exam_ids)


def export_review(db, child_id):
    exam_ids = select(Exam.id).where(Exam.child_id == child_id)
    result = {
        model.__tablename__: [
            {
                column.name: getattr(row, column.name)
                for column in model.__table__.columns
                if column.name != "session_id"
            }
            for row in db.scalars(select(model).where(model.exam_id.in_(exam_ids)))
        ]
        for model in (ExamReviewPage, ExamReview, ExamReviewTurn, ExamReviewPractice)
    }
    result["exam_scan_batches"] = [
        {
            "id": row.id,
            "exam_id": row.exam_id,
            "created": row.created,
            "updated": row.updated,
            **scan_data(db, db.get(Exam, row.exam_id), None),
        }
        for row in db.scalars(select(ExamScanBatch).where(ExamScanBatch.exam_id.in_(exam_ids)))
    ]
    return result


def validate_practice_output(db, job, output):
    value = job.payload.get("exam_review_practice")
    if not value:
        return
    validate_practice_job(db, job)
    material = db.get(Material, job.payload["material_id"])
    if output.get("subject", "").casefold() != material.subject.casefold():
        raise ProviderError("Die neue Übung gehört nicht zum ausgewählten Heftfach.")
    prompts = [normalized(question["prompt"]) for question in output.get("questions", [])]
    if len(set(prompts)) != len(prompts) or normalized(value["focus"]) in prompts:
        raise ProviderError("Die Anschlussübung enthält eine alte oder doppelte Frage.")


def attach_practice_unit(db, job, unit):
    value = job.payload.get("exam_review_practice")
    if not value:
        return
    validate_practice_job(db, job)
    old = db.scalar(select(ExamReviewPractice).where(ExamReviewPractice.job_id == job.id))
    if old:
        if old.unit_id != unit.id:
            raise ProviderError("Dieser Auftrag hat bereits eine andere Anschlussrunde.")
        return
    db.add(
        ExamReviewPractice(
            exam_id=value["exam_id"],
            review_id=value["review_id"],
            child_id=job.child_id,
            task_id=value["task_id"],
            context_revision=value["context_revision"],
            job_id=job.id,
            unit_id=unit.id,
        )
    )


def scan_sources(db, exam):
    return [
        {"id": m.id, "revision": m.revision}
        for m in (db.get(Material, row.material_id, populate_existing=True) for row in page_rows(db, exam))
        if m
    ]


def scan_data(db, exam, child, *, manage=False):
    """Read-only progress; neither a browser read nor export advances the batch."""
    row = db.scalar(select(ExamScanBatch).where(ExamScanBatch.exam_id == exam.id))
    state = row.state if row else {}
    sources = scan_sources(db, exam)
    pages = [db.get(Material, ref["id"]) for ref in sources]
    status = state.get("status", "idle")
    if state and (state.get("sources") != sources or state.get("exam_revision") != exam.revision):
        status = "stale"
    job = db.get(Job, state["job_id"]) if state.get("job_id") else None
    if status == "processing" and job and job.status == "failed":
        status = "failed"
    retry_allowed = state.get("retry_allowed", True)
    if not retry_allowed and status == "blocked":
        from .provider_attempts import counts as provider_attempt_counts

        waiting = next((m for m in pages if m.status == "uploaded" and not m.confirmed), None)
        retry_allowed = bool(waiting and provider_attempt_counts(db, child.id, "extract",
            [{"id": waiting.id, "revision": waiting.revision}], 0)[1] < 2)
    return {
        "id": row.id if row else None,
        "status": status,
        "completed_pages": sum(m.status in ("review", "confirmed", "unreadable") or m.confirmed for m in pages),
        "total_pages": len(pages),
        "job": {"id": job.id, "status": job.status} if job else None,
        "error": job.error if job and status == "failed" else state.get("error"),
        "can_submit": bool(
            manage
            and status != "processing"
            and (retry_allowed or state.get("sources") != sources)
            and any(m.status == "uploaded" and not m.confirmed for m in pages)
        ),
    }


@router.post("/exams/{exam_id}/pages/submit", status_code=202)
def submit_scan(exam_id: str, data: ReviewContext, key: str = KEY, p=Depends(authenticated), db=Depends(get_db)):
    exam, child = access(db, p, exam_id, write=True)
    signature, _, pages = source_context(db, exam, child)
    row = db.scalar(select(ExamScanBatch).where(ExamScanBatch.exam_id == exam.id))
    state = copy.deepcopy(row.state) if row else {}
    key_hash = digest(p.user.id + ":" + key)
    request_hash = digest(json.dumps({"exam_id": exam.id, **data.model_dump()}, sort_keys=True))
    previous = next((r for r in state.get("requests", []) if r["key"] == key_hash), None)
    if previous:
        if previous["request"] != request_hash:
            raise HTTPException(409, "Dieser Abgabeschlüssel gehört zu einem anderen Stand.")
        return projection(db, p, exam, child)
    if exam.revision != data.revision or signature != data.context_revision:
        raise HTTPException(409, "Die Arbeit oder ihre Fotos wurden geändert. Bitte neu laden.")
    if not pages:
        raise HTTPException(409, "Bitte zuerst mindestens ein Foto hinzufügen.")
    if len(pages) > MAX_PAGES:
        raise HTTPException(422, "Bitte höchstens zwölf Fotos abgeben.")
    if (
        state.get("status") == "processing"
        and state.get("sources") == scan_sources(db, exam)
        and state.get("exam_revision") == exam.revision
    ):
        return projection(db, p, exam, child)
    if db.scalar(select(Job.id).where(Job.child_id == child.id, Job.status.in_(["queued", "running"]))):
        raise HTTPException(409, "Für dieses Kind wird bereits eine Verarbeitung ausgeführt.")
    family = db.get(Family, child.family_id)
    if family.synthetic:
        raise HTTPException(403, "Eigene Arbeitsfotos benötigen ein reguläres Familienkonto.")
    usage_terms(db, family, enforce=True)
    config = db.get(ProviderConfig, 1)
    if not config:
        raise HTTPException(503, "Die Bilderkennung ist noch nicht eingerichtet.")
    rate_limit(db, "exam-scan:" + p.user.id, 10, 60, commit=False)
    if row is None:
        row = ExamScanBatch(exam_id=exam.id, child_id=child.id)
        db.add(row)
    row.state = {
        "run_id": uid(),
        "status": "processing",
        "job_id": None,
        "error": None,
        "user_id": p.user.id,
        "session_id": p.session.id,
        "family_id": child.family_id,
        "sources": scan_sources(db, exam),
        "exam_revision": exam.revision,
        "preferences": digest(json.dumps(child.preferences, sort_keys=True)),
        "config_revision": config.revision,
        "requests": [*state.get("requests", []), {"key": key_hash, "request": request_hash}][-128:],
    }
    row.updated = exam.updated = int(now())
    audit(db, p.user.id, "exam.photos_submitted", exam.id)
    db.commit()  # Persist intent before any worker reservation.
    return projection(db, p, exam, child)


def scan_authority(db, row):
    state = copy.deepcopy(row.state)
    expected_run = state.get("run_id")
    user, session = db.get(User, state.get("user_id")), db.get(Session, state.get("session_id"))
    if not user or not session:
        raise HTTPException(401, "Die Fotoabgabe wurde unterbrochen. Bitte erneut anmelden.")
    p = fresh_actor(db, Principal(user, session))
    exam, child = access(db, p, row.exam_id, write=True)
    db.refresh(row)
    if row.state.get("run_id") != expected_run or row.state.get("status") != "processing":
        raise ProviderError("Die Fotoabgabe wurde inzwischen geändert.")
    if row.state.get("user_id") != p.user.id or row.state.get("session_id") != p.session.id:
        raise ProviderError("Die abgebende Sitzung wurde inzwischen geändert.")
    state = row.state
    if child.id != row.child_id or child.family_id != state.get("family_id"):
        raise HTTPException(403, "Der Familienkontext wurde geändert.")
    if (
        exam.revision != state.get("exam_revision")
        or scan_sources(db, exam) != state.get("sources")
        or digest(json.dumps(child.preferences, sort_keys=True)) != state.get("preferences")
    ):
        raise ProviderError("Die abgegebenen Fotos oder die Arbeit wurden geändert.")
    # Same page IDs/revisions are safe across OCR: only explicit confirmation
    # changes their revision. Every OCR result is independently saved first.
    if any(
        m.child_id != child.id or m.purpose != "exam" for m in (db.get(Material, ref["id"]) for ref in state["sources"])
    ):
        raise ProviderError("Die Arbeitsfotos gehören nicht mehr zu dieser Abgabe.")
    family = db.get(Family, child.family_id)
    if family.synthetic:
        raise HTTPException(403, "Eigene Arbeitsfotos sind im Beispiel nicht verfügbar.")
    usage_terms(db, family, enforce=True)
    config = db.get(ProviderConfig, 1, populate_existing=True)
    if not config or config.revision != state.get("config_revision"):
        raise ProviderError("Die Bilderkennung wurde geändert. Bitte die Fotoabgabe erneut anstoßen.")
    return p, exam, child


def validate_scan_job(db, job):
    if not job.payload.get("exam_scan_id"):
        return
    row = db.get(ExamScanBatch, job.payload["exam_scan_id"])
    if (
        not row
        or row.child_id != job.child_id
        or row.state.get("status") != "processing"
        or row.state.get("run_id") != job.payload.get("exam_scan_run")
        or row.state.get("job_id") != job.id
    ):
        raise ProviderError("Dieser Erkennungsauftrag ist nicht mehr aktuell.")
    scan_authority(db, row)
    if (
        job.status != "running"
        or row.state.get("job_id") != job.id
        or row.state.get("run_id") != job.payload.get("exam_scan_run")
    ):
        raise ProviderError("Dieser Erkennungsauftrag wurde inzwischen beendet.")
    config = job_config(db, job)
    usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
    if not usage or (usage.provider, usage.model, usage.config_revision) != (
        config.provider,
        config.model,
        config.revision,
    ):
        raise ProviderError("Die reservierte Bilderkennung wurde geändert.")
    external_allowed(config, image=True)


def _advance_scan(db, row):
    from .materials import enqueue

    p, exam, child = scan_authority(db, row)
    state = copy.deepcopy(row.state)
    job = db.get(Job, state["job_id"]) if state.get("job_id") else None
    if job and job.status in ("queued", "running"):
        return
    if job and job.status == "failed":
        state.update(status="failed", error=job.error)
    else:
        if db.scalar(select(Job.id).where(Job.child_id == child.id, Job.status.in_(["queued", "running"]))):
            raise ProviderError("Für dieses Kind läuft bereits ein anderer Auftrag. Bitte später erneut abgeben.")
        pages = [db.get(Material, ref["id"]) for ref in state["sources"]]
        waiting = next((m for m in pages if m.status == "uploaded" and not m.confirmed), None)
        if waiting:
            from .provider_attempts import counts as provider_attempt_counts

            _, attempts = provider_attempt_counts(db, child.id, "extract",
                [{"id": waiting.id, "revision": waiting.revision}], 0)
            if attempts >= 2:
                state.update(
                    status="blocked",
                    retry_allowed=False,
                    error="Die Erkennung hat zweimal nicht geklappt. Bitte fotografiere diese Seite neu.",
                )
                row.state, row.updated = state, int(now())
                return
            value = enqueue(
                db,
                p,
                child,
                "extract",
                {
                    "material_id": waiting.id,
                    "exam_id": exam.id,
                    "exam_scan_id": row.id,
                    "exam_scan_run": state["run_id"],
                },
                "exam-scan-" + state["run_id"] + "-" + waiting.id,
                commit=False,
            )
            state.update(job_id=value["id"], error=None)
        else:
            state.update(
                status="needs_photo" if any(m.status == "unreadable" for m in pages) else "needs_review",
                job_id=None,
                error=None,
            )
    row.state, row.updated = state, int(now())


def advance_scan(batch_id):
    """Worker-only continuation; a failed provider job is never retried here."""
    run_id = None
    try:
        with DB.begin() as db:
            row = db.get(ExamScanBatch, batch_id)
            if not row or row.state.get("status") != "processing":
                return
            run_id = row.state.get("run_id")
            _advance_scan(db, row)
    except Exception as error:
        message = (
            str(error.detail)
            if isinstance(error, HTTPException)
            else str(error)
            if isinstance(error, ProviderError)
            else "Die Fotoabgabe wurde unterbrochen. Deine Fotos sind gespeichert."
        )
        with DB.begin() as db:
            row = db.get(ExamScanBatch, batch_id)
            if not row:
                return
            from .db import Child

            db.execute(update(Child).where(Child.id == row.child_id).values(grade=Child.grade))
            db.refresh(row)
            state = copy.deepcopy(row.state)
            if state.get("run_id") == run_id and state.get("status") == "processing":
                state.update(status="blocked", error=message[:500])
                row.state, row.updated = state, int(now())


def advance_scan_one():
    """Persistent bounded coordinator, independent of all browser polling."""
    with DB() as db:
        ids = list(
            db.scalars(
                select(ExamScanBatch.id)
                .where(ExamScanBatch.state["status"].as_string() == "processing")
                .order_by(ExamScanBatch.created, ExamScanBatch.id)
                .limit(100)
            )
        )
    for batch_id in ids:
        advance_scan(batch_id)
