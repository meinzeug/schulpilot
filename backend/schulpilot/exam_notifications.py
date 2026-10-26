"""Private saved exam facts for inbox/push; no locks, reservations or writes."""

import re

from fastapi import HTTPException
from sqlalchemy import select

from .db import Job, LearningUnit, Session, User
from .exam_models import Exam, ExamRound, ExamSession
from .exam_review_models import ExamReview, ExamReviewPractice
from .exams import due_reminders, guard_preparation, valid_refs
from .providers import ProviderError
from .security import Principal, child_access

EXAM_PATH_PATTERN = r"(?:/exams/[a-f0-9]{32}\?exam=[a-f0-9]{32}(?:&session=[a-f0-9]{32})?(?:&tab=review)?|/unit/[a-f0-9]{32})"


def valid_exam_path(value):
    return isinstance(value, str) and bool(re.fullmatch(EXAM_PATH_PATTERN, value, flags=re.ASCII))


def live_request(db, child, actor_id, session_id, family_id, current):
    user = db.get(User, actor_id, populate_existing=True) if actor_id else None
    login = db.get(Session, session_id, populate_existing=True) if session_id else None
    if (not user or user.role not in ("parent", "child") or user.disabled or not user.verified or
            not login or login.user_id != user.id or login.revoked or login.expires <= current or
            current - login.seen > 7 * 86400 or child.family_id != family_id):
        return False
    try:
        child_access(db, Principal(user, login), child.id, write=user.role == "parent")
    except HTTPException:
        return False
    return True


def valid_review(db, exam, child, review, current):
    if exam.archived or review.status != "ready":
        return False
    job = db.get(Job, review.job_id) if review.job_id else None
    if (not job or job.status != "completed" or job.payload.get("action") != "analyze" or
            job.payload.get("exam_id") != exam.id or job.payload.get("review_id") != review.id or
            not live_request(db, child, job.payload.get("user_id"), job.payload.get("session_id"),
                job.payload.get("family_id"), current)):
        return False
    from .exam_review import source_context

    try:
        signature, refs, pages = source_context(db, exam, child)
    except HTTPException:
        return False
    batch = next((batch for batch in (review.report or {}).get("analysis_batches", [])
        if batch.get("id") == job.payload.get("analysis_batch_id") and batch.get("job_id") == job.id
        and batch.get("status") == "ready"), None)
    selected = batch.get("page_ids") if batch else None
    if (not isinstance(selected, list) or not 1 <= len(selected) <= 12 or
            any(not isinstance(value, str) for value in selected) or len(set(selected)) != len(selected)):
        return False
    selected_pages = [page for page in pages if page.id in selected]
    return (len(selected_pages) == len(selected) and all(page.confirmed and page.content.strip() for page in selected_pages)
        and signature == review.context_revision == job.payload.get("signature")
        and refs == review.source_revisions == job.payload.get("material_revisions"))


def events_for_child(db, child, current, *, retention=30 * 86400):
    cutoff, result = current - retention, []
    for row in due_reminders(db, child, current):
        result.append({"id": f"exam_reminder:{row['session_id']}:{row['revision']}", "child_id": child.id,
            "created": row["created"], "title": "Dein geplanter Lerntag steht an", "route": row["route"],
            "kind": "exam_reminder"})
    prepared = db.execute(select(Exam, ExamSession, ExamRound, LearningUnit, Job)
        .join(ExamSession, ExamSession.exam_id == Exam.id)
        .join(ExamRound, ExamRound.session_id == ExamSession.id)
        .join(LearningUnit, LearningUnit.id == ExamRound.unit_id).join(Job, Job.id == ExamRound.job_id)
        .where(Exam.child_id == child.id, Exam.archived.is_(False), ExamSession.exam_revision == Exam.plan_revision,
            LearningUnit.child_id == child.id, LearningUnit.status != "completed", Job.status == "completed",
            Job.finished > cutoff, Job.finished <= current).order_by(Job.finished.desc(), Job.id).limit(100))
    for exam, session, row, unit, job in prepared:
        if not live_request(db, child, job.payload.get("exam_actor_id"), job.payload.get("exam_actor_session_id"),
                job.payload.get("exam_family_id"), current):
            continue
        try:
            guard_preparation(db, job)
        except (ProviderError, HTTPException):
            continue
        result.append({"id": f"exam_ready:{row.id}:{job.id}", "child_id": child.id, "created": job.finished,
            "title": "Deine Lernrunde ist bereit", "route": f"/unit/{unit.id}",
            "kind": "exam_ready"})
    reviewed = db.execute(select(Exam, ExamReview, Job).join(ExamReview, ExamReview.exam_id == Exam.id)
        .join(Job, Job.id == ExamReview.job_id).where(Exam.child_id == child.id, Exam.archived.is_(False),
            ExamReview.status == "ready", Job.status == "completed", Job.finished > cutoff, Job.finished <= current)
        .order_by(Job.finished.desc(), Job.id).limit(100))
    for exam, review, job in reviewed:
        if valid_review(db, exam, child, review, current):
            result.append({"id": f"exam_ready:{review.id}:{job.id}", "child_id": child.id,
                "created": job.finished, "title": "Deine Arbeitsbesprechung ist bereit",
                "route": f"/exams/{child.id}?exam={exam.id}&tab=review", "kind": "exam_ready"})
    practices = db.execute(select(Exam, ExamReview, ExamReviewPractice, Job, LearningUnit)
        .join(ExamReview, ExamReview.exam_id == Exam.id)
        .join(ExamReviewPractice, ExamReviewPractice.review_id == ExamReview.id)
        .join(Job, Job.id == ExamReviewPractice.job_id).join(LearningUnit, LearningUnit.id == ExamReviewPractice.unit_id)
        .where(Exam.child_id == child.id, Exam.archived.is_(False), ExamReview.status == "ready",
            Job.status == "completed", Job.finished > cutoff, Job.finished <= current,
            LearningUnit.child_id == child.id, LearningUnit.status != "completed")
        .order_by(Job.finished.desc(), Job.id).limit(100))
    for exam, review, link, job, unit in practices:
        context = job.payload.get("exam_review_practice") or {}
        task = next((task for task in (review.report or {}).get("tasks", []) if task.get("id") == link.task_id), None)
        if (not task or context.get("task_id") != link.task_id or context.get("focus") != task.get("question") or
                not valid_review(db, exam, child, review, current) or link.context_revision != review.context_revision or
                context.get("context_revision") != review.context_revision or
                context.get("exam_id") != exam.id or context.get("review_id") != review.id or
                not live_request(db, child, context.get("user_id"), context.get("session_id"),
                    context.get("family_id"), current) or
                not valid_refs(db, child.id, job.payload.get("sources", []), exam.subject_id, exam.subject)):
            continue
        result.append({"id": f"exam_ready:{link.id}:{job.id}", "child_id": child.id, "created": job.finished,
            "title": "Deine Anschlussübung ist bereit", "route": f"/unit/{unit.id}",
            "kind": "exam_ready"})
    return sorted(result, key=lambda row: (row["created"], row["id"]), reverse=True)[:100]


def delivery_key(device, event):
    return device.id + ":" + event["id"]
