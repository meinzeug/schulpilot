"""Conservative local candidate search. Similarity never supplies a class proof."""

import math
import re
import unicodedata
from collections import Counter

from sqlalchemy import func, literal_column, select

from .catalog_models import CatalogLevel, CatalogPlacement, CatalogState, CatalogTopic
from .db import ChildSubject

MATCHER_VERSION = "tips-v1"
STOP = set(
    "der die das des dem den ein eine einer einem einen eines und oder aber auch ist sind wird werden von vom zum zur zu im in am an auf aus mit für als bei durch nach vor nicht nur wir du ihr sie es sich was wie wo warum welche welcher welches dieser diese dieses haben hat sein so kann können soll bitte text seite heft foto lernen thema aufgabe klasse übung übungen verstehen erkläre erklären künstlicher funktionstest the a an of to and or is are in on for it be example".split()
)
STEMS = {
    "brüche": "bruch",
    "brüchen": "bruch",
    "bruchs": "bruch",
    "photosynthese": "fotosynthese",
    "photosynthesis": "fotosynthese",
    "erweitern": "erweit",
    "erweitere": "erweit",
    "erweiterung": "erweit",
    "erweitert": "erweit",
    "kürzen": "kürz",
    "kürze": "kürz",
    "gekürzt": "kürz",
    "kürzung": "kürz",
    "addieren": "addier",
    "addiere": "addier",
    "addition": "addier",
    "addiert": "addier",
    "subtrahieren": "subtrahier",
    "subtrahiere": "subtrahier",
    "subtraktion": "subtrahier",
    "multiplizieren": "multiplizier",
    "multiplikation": "multiplizier",
    "dividieren": "dividier",
    "division": "dividier",
}
OPERATIONS = {"erweit", "kürz", "addier", "subtrahier", "multiplizier", "dividier"}
TENSES = ("simple present", "simple past", "present perfect", "past perfect", "present progressive", "past progressive")


def terms(value):
    words = re.findall(r"[^\W_]+", unicodedata.normalize("NFC", value).casefold(), flags=re.UNICODE)
    return {STEMS.get(w, w) for w in words if len(w) >= 3 and w not in STOP and not w.isdigit()}


def incompatible(goal, candidate):
    goal_ops, candidate_ops = terms(goal) & OPERATIONS, terms(candidate) & OPERATIONS
    if goal_ops and candidate_ops and not goal_ops & candidate_ops:
        return True
    goal_tenses = {tense for tense in TENSES if tense in goal.casefold()}
    candidate_tenses = {tense for tense in TENSES if tense in candidate.casefold()}
    return bool(goal_tenses and candidate_tenses and not goal_tenses & candidate_tenses)


def current_snapshot(db):
    state = db.get(CatalogState, "sofatutor")
    return state.snapshot_id if state else None


def level_for(db, child, subject_id, snapshot=None):
    """Never convert school grade to a language learning year or preschool."""
    snapshot = snapshot or current_snapshot(db)
    row = db.get(ChildSubject, (child.id, subject_id)) if subject_id else None
    if row and row.level_type:
        return row.level_type, None if row.level_type == "vorschule" else row.level_number
    types = set(
        db.scalars(
            select(CatalogLevel.level_type).where(
                CatalogLevel.subject_id == subject_id, CatalogLevel.snapshot_id == snapshot
            )
        )
    )
    if "klasse" in types and "lernjahr" not in types:
        return "klasse", child.grade
    return None, None


def topic_index(db, snapshot, subject_id):
    key = "catalog_index", snapshot, subject_id
    if key not in db.info:
        rows = db.execute(
            select(CatalogTopic.id, CatalogTopic.title, CatalogTopic.search_text).where(
                CatalogTopic.snapshot_id == snapshot, CatalogTopic.subject_id == subject_id
            )
        ).all()
        index = [
            {"id": r.id, "title": r.title, "title_terms": terms(r.title), "terms": terms(r.search_text)} for r in rows
        ]
        counts = Counter(t for row in index for t in row["terms"])
        weights = {t: 1 + math.log((1 + len(index)) / (1 + n)) for t, n in counts.items()}
        db.info[key] = index, weights
    return db.info[key]


def candidates(db, subject_id, title, content="", *, limit=12, automatic=False, child=None):
    snapshot = current_snapshot(db)
    if not snapshot or not subject_id:
        return []
    index, weights = topic_index(db, snapshot, subject_id)
    class_topics = known_class_topics(db, child, subject_id, [r["id"] for r in index]) if child else set()
    target, heading = terms(title + "\n" + content[:24000]), terms(title)
    if not target:
        return []
    result = []
    for row in index:
        if incompatible(title + "\n" + content, row["title"]):
            continue
        overlap = target & row["title_terms"]
        body_overlap = target & row["terms"]
        if not body_overlap:
            continue
        complete = bool(row["title_terms"] and row["title_terms"] <= target)
        coverage = len(overlap) / max(1, len(row["title_terms"]))
        # Broad one-word overlaps ("Brüche", "Present") do not prove the goal.
        strong = complete and (len(overlap) >= 2 or any(weights.get(t, 0) >= 2.3 or len(t) >= 9 for t in overlap))
        plausible = len(overlap) >= 2 and coverage >= 0.55
        if automatic and not (strong or plausible):
            continue
        score = sum(weights.get(t, 1) * (3 if t in heading else 1) for t in overlap)
        score += 0.2 * sum(weights.get(t, 1) for t in body_overlap - overlap)
        score += 4 if complete else 0
        score += 1.5 if row["id"] in class_topics else 0
        result.append(
            {"id": row["id"], "title": row["title"], "quality": "high" if strong else "suggestion", "score": score}
        )
    result.sort(key=lambda r: (-r["score"], r["id"]))
    return result[:limit]


def match_sections(db, subject_id, title, content, child=None):
    sections = [title] + [p.strip() for p in re.split(r"\n\s*\n", content[:24000]) if p.strip()][:16]
    matches, seen = [], set()
    for n, section in enumerate(sections):
        # The whole heading is not copied into every paragraph: that would
        # erase the distinction between different goals on the same page.
        for candidate in candidates(db, subject_id, section[:300], section[300:], limit=2, automatic=True, child=child):
            if candidate["id"] in seen:
                continue
            seen.add(candidate["id"])
            matches.append(
                {
                    "context_ref": f"section_{n + 1}",
                    "topic_id": candidate["id"],
                    "quality": candidate["quality"],
                    "basis": "local",
                }
            )
        if len(matches) >= 8:
            break
    return matches[:8]


def known_class_topics(db, child, subject_id, topic_ids):
    snapshot = current_snapshot(db)
    kind, number = level_for(db, child, subject_id, snapshot)
    if not kind or not topic_ids:
        return set()
    query = (
        select(CatalogPlacement.topic_id)
        .join(CatalogLevel, CatalogLevel.id == CatalogPlacement.level_id)
        .where(
            CatalogPlacement.topic_id.in_(topic_ids),
            CatalogPlacement.snapshot_id == snapshot,
            CatalogLevel.snapshot_id == snapshot,
            CatalogLevel.subject_id == subject_id,
            CatalogLevel.level_type == kind,
            CatalogLevel.level_number.is_(None) if number is None else CatalogLevel.level_number == number,
        )
    )
    return set(db.scalars(query))


def search_topics(db, subject_id, query="", *, page=1, page_size=20, child=None, known_only=False):
    snapshot = current_snapshot(db)
    conditions = [CatalogTopic.snapshot_id == snapshot, CatalogTopic.subject_id == subject_id]
    level = level_for(db, child, subject_id, snapshot) if child else (None, None)
    if known_only:
        if not level[0]:
            return {"items": [], "total": 0, "page": page, "page_size": page_size, "has_known_level": False}
        conditions.append(
            CatalogTopic.id.in_(
                select(CatalogPlacement.topic_id)
                .join(CatalogLevel, CatalogLevel.id == CatalogPlacement.level_id)
                .where(
                    CatalogPlacement.snapshot_id == snapshot,
                    CatalogLevel.snapshot_id == snapshot,
                    CatalogLevel.subject_id == subject_id,
                    CatalogLevel.level_type == level[0],
                    CatalogLevel.level_number.is_(None) if level[1] is None else CatalogLevel.level_number == level[1],
                )
            )
        )
    if query.strip():
        if db.bind.dialect.name == "postgresql":
            conditions.append(
                func.to_tsvector(literal_column("'german'"), CatalogTopic.search_text).op("@@")(
                    func.plainto_tsquery(literal_column("'german'"), query)
                )
            )
        else:
            # Test/development fallback. Escape wildcards; exact user strings
            # must not turn into an unconstrained query.
            escaped = query.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
            conditions.append(func.lower(CatalogTopic.search_text).like("%" + escaped.lower() + "%", escape="\\"))
    total = db.scalar(select(func.count()).select_from(CatalogTopic).where(*conditions))
    rows = db.scalars(
        select(CatalogTopic)
        .where(*conditions)
        .order_by(CatalogTopic.title, CatalogTopic.id)
        .offset((page - 1) * page_size)
        .limit(page_size)
    )
    result = [{"id": row.id, "title": row.title, "empty_curated": row.empty_curated} for row in rows]
    class_ids = known_class_topics(db, child, subject_id, [r["id"] for r in result]) if child else set()
    for row in result:
        row["known_level"] = row["id"] in class_ids
    return {"items": result, "total": total, "page": page, "page_size": page_size, "has_known_level": bool(level[0])}
