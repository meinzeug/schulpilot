"""Read-only exam context, rebuilt under the existing Schulbuddy authority guards.

Written answers and teacher annotations are original evidence, never a solution
key or permission to regrade. No drafts, pixels or future task answers enter it.
"""

from fastapi import HTTPException
from sqlalchemy import select

from .db import Material
from .exam_models import Exam, ExamSession
from .security import child_access


def resolve_exam(db, p, scope):
    if not scope.exam_id:
        if scope.exam_session_id or scope.review_task_id or scope.exam_revision is not None:
            raise HTTPException(422, "Wähle zuerst die zugehörige Klassenarbeit.")
        return None
    if scope.unit_id or scope.material_id or scope.day_id or scope.question_id:
        raise HTTPException(422, "Wähle genau einen geöffneten Lernbereich.")
    exam = db.get(Exam, scope.exam_id, populate_existing=True)
    if not exam:
        raise HTTPException(404, "Klassenarbeit nicht gefunden.")
    child_access(db, p, exam.child_id)
    if scope.exam_revision is not None and scope.exam_revision != exam.revision:
        raise HTTPException(409, "Die Klassenarbeit wurde geändert. Öffne den aktuellen Bereich erneut.")
    if scope.exam_session_id:
        session = db.get(ExamSession, scope.exam_session_id, populate_existing=True)
        if not session or session.exam_id != exam.id:
            raise HTTPException(404, "Dieser Lerntag gehört nicht zu dieser Klassenarbeit.")
    if scope.review_task_id and scope.exam_tab != "review":
        raise HTTPException(422, "Die Aufgabe gehört zur Nacharbeit der Klassenarbeit.")
    return exam


def inventory(db, p, child):
    if child is None:
        return {}
    child_access(db, p, child.id)
    rows = list(db.scalars(select(Exam).where(Exam.child_id == child.id).order_by(Exam.updated.desc(), Exam.id).limit(5)))
    return {"page": "exams", "is_excerpt": True,
            "notice": "Begrenzte gespeicherte Planmetadaten, keine fachlichen Quellen oder Lernerfolge.",
            "items": [{"id": row.id, "title": row.title[:160], "subject": row.subject[:80],
                       "kind": row.kind, "purpose": row.purpose, "exam_date": row.exam_date,
                       "archived": row.archived, "revision": row.revision} for row in rows]}


def bind(db, p, child, scope, exam, payload, normalized, guards):
    from .exams import valid_refs

    normalized["exam_revision"] = exam.revision
    payload["exam"] = {"title": exam.title, "subject": exam.subject, "kind": exam.kind,
                       "purpose": exam.purpose, "exam_date": exam.exam_date, "minutes": exam.minutes,
                       "archived": exam.archived, "tab": scope.exam_tab or "prepare"}
    guards.append(["exam", exam.id, exam.revision, exam.archived])
    if scope.exam_tab == "review":
        from .exam_review import source_context
        from .exam_review_models import ExamReview

        signature, refs, pages = source_context(db, exam, child)
        row = db.scalar(select(ExamReview).where(ExamReview.exam_id == exam.id))
        guards.append(["exam_review", signature, row.id if row else None, row.revision if row else None,
                       row.status if row else None])
        if any(not page.confirmed or not (page.content or "").strip() for page in pages):
            payload["source_review"] = {"confirmation_required": True,
                "notice": "Die Arbeit ist noch nicht vollständig geprüft. Erst den erkannten Originaltext prüfen und bestätigen; keine fachliche Erklärung ungeprüfter Inhalte."}
            return []
        if scope.review_task_id:
            if not row or row.status != "ready" or row.context_revision != signature:
                raise HTTPException(409, "Bitte die aktuelle Aufgabenbesprechung neu öffnen.")
            task = next((task for task in row.report.get("tasks", []) if task["id"] == scope.review_task_id), None)
            if not task:
                raise HTTPException(404, "Aufgabe in dieser Arbeit nicht gefunden.")
            payload["exam_review"] = {key: task.get(key, "") for key in
                ("id", "question", "original_answer", "teacher_feedback", "score_label", "uncertainties")}
            payload["exam_review"]["notice"] = (
                "Originalantwort und Lehrermarkierung sind wörtliche Beobachtungen, keine bestätigten richtigen Lösungen. "
                "Keine Note ändern, keine Beherrschung behaupten; eigene Überarbeitung und Heftgrundlagen getrennt behandeln.")
            ids = {source["material_id"] for source in task.get("sources", []) if source.get("material_id")}
            pages = [page for page in pages if page.id in ids]
            if not pages:
                raise HTTPException(409, "Der Quellenbeleg dieser Aufgabe fehlt. Prüfe die aktuelle Arbeit.")
        return bounded_materials(pages, payload, guards)
    session = db.get(ExamSession, scope.exam_session_id) if scope.exam_session_id else None
    topics = session.topics if session else exam.topics
    payload["exam"]["topics"] = [{"label": topic["label"], "question_count": topic["question_count"]} for topic in topics]
    if session:
        payload["exam"]["session"] = {"id": session.id, "date": session.date, "minutes": session.minutes,
                                       "current_plan": session.exam_revision == exam.plan_revision}
        guards.append(["exam_session", session.id, session.exam_revision, session.date, session.topics])
    if any(not valid_refs(db, child.id, topic["material_refs"], exam.subject_id, exam.subject) for topic in topics):
        raise HTTPException(409, "Die Heftquellen dieses Plans wurden geändert. Prüfe zuerst den Plan.")
    ids = {ref["id"] for topic in topics for ref in topic["material_refs"]}
    pages = [db.get(Material, identifier, populate_existing=True) for identifier in sorted(ids)]
    return bounded_materials(pages, payload, guards)


def bounded_materials(pages, payload, guards):
    # Keep the existing chat's source/context budget, including on large plans.
    guards.append(["exam_materials", [[page.id, page.revision, page.confirmed] for page in pages]])
    if len(pages) > 6 or sum(len(page.content or "") for page in pages) > 18000:
        payload["source_review"] = {"selection_required": True,
            "notice": "Dieser Bereich ist zu umfangreich für den Chat. Öffne eine einzelne Heftseite oder eine kleinere Aufgabe; hier nur Plan- und Bedienhilfe geben."}
        return []
    return pages
