"""Small, read-only inventories of the authorized child's current app page.

These are navigation facts, not task sources or competence evidence. They never
contain OCR, questions, solutions, answers, personal notes or messages. Every
query is child-scoped and selects only the fields included in the projection.
"""

import json

from sqlalchemy import func, select

from .db import Assignment, LearningUnit, Material, VocabularyItem
from .security import child_access

VERSION = "schulbuddy-pages-1"
MAX_CHARS = 4000
PAGES = frozenset({"today", "learn", "words", "homework", "notebooks", "plan"})
NOTICE = ("Begrenzter Auszug des gespeicherten Seitenbestands, keine vollständige Liste und keine "
          "Lernbewertung. Überschriften können gekürzt sein. Wörter sind bestätigte Paare; "
          "Metadaten sind keine fachlichen Quellen oder Aufgabenlösungen.")


def short(value, maximum=100):
    value = value or ""
    return value if len(value) <= maximum else value[:maximum-1] + "…"


def tally(db, model, child_id, *conditions):
    return db.scalar(select(func.count()).select_from(model).where(model.child_id == child_id, *conditions))


def materials(db, child_id, purpose):
    conditions = (Material.purpose == purpose,)
    rows = db.execute(select(Material.id, Material.subject, Material.topic, Material.title,
        Material.revision, Material.status, Material.created).where(Material.child_id == child_id,
        *conditions, Material.confirmed.is_(True)).order_by(Material.created.desc(), Material.id).limit(5))
    return {"total": tally(db, Material, child_id, *conditions),
            "confirmed": tally(db, Material, child_id, *conditions, Material.confirmed.is_(True)),
            "unconfirmed": tally(db, Material, child_id, *conditions, Material.confirmed.is_(False)),
            "order": "newest_confirmed_first", "items": [
                {"id": r.id, "subject": short(r.subject, 80), "topic": short(r.topic), "title": short(r.title),
                 "revision": r.revision, "status": r.status, "created": r.created} for r in rows]}


def rounds(db, child_id):
    rows = db.execute(select(LearningUnit.id, LearningUnit.subject, LearningUnit.topic, LearningUnit.status,
        LearningUnit.round_kind, LearningUnit.created, LearningUnit.goal_revision).where(
            LearningUnit.child_id == child_id).order_by(LearningUnit.created.desc(), LearningUnit.id).limit(5))
    return {"total": tally(db, LearningUnit, child_id),
            "unfinished": tally(db, LearningUnit, child_id, LearningUnit.status != "completed"),
            "completed": tally(db, LearningUnit, child_id, LearningUnit.status == "completed"),
            "order": "newest_first", "items": [
                {"id": r.id, "subject": short(r.subject, 80), "topic": short(r.topic), "status": r.status,
                 "round_kind": r.round_kind, "created": r.created, "goal_revision": r.goal_revision} for r in rows]}


def assignments(db, child_id):
    rows = db.execute(select(Assignment.id, Assignment.subject, Assignment.topic, Assignment.revision,
        Assignment.done, Assignment.mandatory, Assignment.due, Assignment.scheduled_for, Assignment.source_status,
        Assignment.kind).where(Assignment.child_id == child_id).order_by(
            Assignment.done, Assignment.mandatory.desc(), Assignment.due.asc().nullslast(),
            Assignment.created.desc(), Assignment.id).limit(5))
    return {"total": tally(db, Assignment, child_id),
            "open": tally(db, Assignment, child_id, Assignment.done.is_(False)),
            "completed": tally(db, Assignment, child_id, Assignment.done.is_(True)),
            "order": "open_mandatory_due_first", "items": [
                {"id": r.id, "subject": short(r.subject, 80), "topic": short(r.topic), "revision": r.revision,
                 "done": r.done, "mandatory": r.mandatory, "due": r.due, "scheduled_for": r.scheduled_for,
                 "source_status": r.source_status, "kind": r.kind} for r in rows]}


def words(db, child_id):
    confirmed = (VocabularyItem.confirmed.is_(True), func.trim(VocabularyItem.word) != "",
                 func.trim(VocabularyItem.meaning) != "")
    rows = db.execute(select(VocabularyItem.id, VocabularyItem.word, VocabularyItem.meaning,
        VocabularyItem.revision, VocabularyItem.target_locale).where(VocabularyItem.child_id == child_id,
        *confirmed).order_by(VocabularyItem.created.desc(), VocabularyItem.id).limit(12))
    return {"total": tally(db, VocabularyItem, child_id),
            "confirmed_pairs": tally(db, VocabularyItem, child_id, *confirmed),
            "order": "newest_confirmed_first", "items": [
                {"id": r.id, "word": r.word, "meaning": r.meaning, "revision": r.revision,
                 "target_locale": r.target_locale} for r in rows]}


def bounded(payload):
    """Keep complete word pairs and trim sample rows, never falsify the totals."""
    sections = [v for v in payload.values() if isinstance(v, dict) and "items" in v]
    for section in sections:
        section["has_more"] = len(section["items"]) < section.get("confirmed_pairs", section.get("confirmed", section["total"]))
    while len(json.dumps(payload, ensure_ascii=False, separators=(",", ":"))) > MAX_CHARS:
        candidate = max(sections, key=lambda section: len(json.dumps(section["items"], ensure_ascii=False)))
        if not candidate["items"]:
            raise ValueError("Schulbuddy page inventory metadata exceeds its fixed limit")
        candidate["items"].pop()
        candidate["has_more"] = True
    return payload


def page_context(db, p, child, page_kind):
    """Reauthorize an already resolved child; never accept a client family ID.

    Account, messages, progress and operator pages intentionally have no extra
    learning inventory. Progress evidence has its own separately scoped helper.
    """
    if page_kind not in PAGES or child is None or p.user.role not in ("child", "parent"):
        return {}
    child = child_access(db, p, child.id)
    payload = {"version": VERSION, "page": page_kind, "is_excerpt": True, "notice": NOTICE}
    if page_kind in ("today", "learn"):
        payload["rounds"] = rounds(db, child.id)
    if page_kind in ("today", "plan"):
        payload["assignments"] = assignments(db, child.id)
    if page_kind in ("today", "notebooks"):
        payload["notebooks"] = materials(db, child.id, "notebook")
    if page_kind == "homework":
        payload["homework"] = materials(db, child.id, "homework")
    if page_kind == "words":
        payload["words"] = words(db, child.id)
    return bounded(payload)
