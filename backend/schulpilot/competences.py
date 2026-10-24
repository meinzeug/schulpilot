"""Reviewed identities shared across uploads; Attempts remain the sole evidence.

Catalogue discovery and evidence projections are read-only. Binding is called
only while persisting a validated generated unit, never from a list/detail GET.
"""

import hashlib
import json
import re
import unicodedata
from datetime import date, datetime
from pathlib import Path
from types import SimpleNamespace
from zoneinfo import ZoneInfo

from sqlalchemy import select

from .db import Attempt, Child, LearningUnit, Material, Subject, UnitSource
from .schemas import Preferences

VERSION = "competencies-1"
SEED = Path(__file__).with_name("reference") / "competencies-v1.json"
ID = re.compile(r"[a-z][a-z0-9_.-]{2,119}", re.ASCII)


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def normalized(value):
    # Chemistry CO/Co and mathematical superscripts must remain distinct.
    return " ".join(unicodedata.normalize("NFC", value).split())


def catalogue():
    data = json.loads(SEED.read_text())
    if data["version"] != VERSION:
        raise ValueError("Unsupported competence catalogue")
    rows = {row["id"]: row for row in data["competences"]}
    if len(rows) != len(data["competences"]) or any(not ID.fullmatch(key) for key in rows):
        raise ValueError("Invalid competence identities")
    for row in rows.values():
        if not set(row["prerequisites"]) <= set(rows) or row["id"] in row["prerequisites"]:
            raise ValueError("Unknown prerequisite")
        if any(rows[key]["subject_key"] != row["subject_key"] for key in row["prerequisites"]):
            raise ValueError("Unreviewed cross-subject prerequisite")
    def visit(key, seen):
        if key in seen:
            raise ValueError("Cyclic prerequisites")
        for before in rows[key]["prerequisites"]:
            visit(before, seen | {key})
    for key in rows:
        visit(key, set())
    return rows


def seed_connection(connection):
    from .competence_models import CompetenceDefinition
    from .subject_registry import insert_ignore

    rows = catalogue()
    old = list(connection.execute(select(CompetenceDefinition.__table__).where(CompetenceDefinition.version == VERSION)).mappings())
    if any(item["id"] not in rows or item["data"] != rows[item["id"]] for item in old):
        raise ValueError("Eine Kompetenzdefinition wurde ohne neue Katalogversion verändert.")
    insert_ignore(connection, CompetenceDefinition.__table__, [
        {"id": key, "version": VERSION, "subject_key": value["subject_key"], "label": value["label"], "data": value}
        for key, value in rows.items()
    ])


def prerequisite_graph(ids):
    rows = catalogue()
    selected = set(ids) & set(rows)
    return [{"before": before, "after": key, "basis": "reviewed_catalog_rule", "catalog_version": VERSION}
        for key in rows if key in selected for before in rows[key]["prerequisites"] if before in selected]


def source_value(db, material):
    from .source_lineage import learning_source

    value = learning_source(db, material)
    return value if material.confirmed and value.get("content", "").strip() and value.get("factual_status") != "blocked" else None


def matches(db, sources, subject):
    from .subject_registry import resolve

    family_id = db.get(Child, sources[0].child_id).family_id if sources else None
    chosen = resolve(db, subject, family_id)
    if not chosen or chosen.owner_family_id is not None:
        return []  # A private alias never creates a reviewed public competence.
    result = []
    for row in catalogue().values():
        if row["subject_key"] != chosen.key:
            continue
        for material in sources:
            actual = db.get(Subject, material.subject_id) if material.subject_id else resolve(db, material.subject, family_id)
            if not actual or actual.id != chosen.id:
                continue
            value = source_value(db, material)
            if not value:
                continue
            for pattern in row["patterns"]:
                match = re.search(pattern, value["content"], re.I)
                if match:
                    start = max(value["content"].rfind("\n", 0, match.start()) + 1, match.start() - 100)
                    result.append({"id": row["id"], "label": row["label"], "catalog_version": VERSION,
                        "source_ref": {"material_id": material.id, "revision": material.revision},
                        "source_excerpt": value["content"][start:start + 500], "origin": "reviewed_source_rule"})
                    break
            else:
                continue
            break
    return result


def question_digest(question):
    return fingerprint({key: question.get(key) for key in ("id", "type", "prompt", "answer", "options", "accepted")})


def source_ref(db, material):
    value = source_value(db, material)
    if not value:
        return None
    return {"material_id": material.id, "revision": material.revision,
        "source_digest": fingerprint({key: value.get(key) for key in ("content", "source_refs", "exclusions", "factual_status")})}


def resolve_reference(reference_id, version, digest=None):
    """Server-owned prerequisite rule, explicitly distinct from a photo quote."""
    row = catalogue().get(reference_id)
    if version != VERSION or not row or not row.get("reference"):
        return None
    value = {"reference_id": reference_id, "version": VERSION,
        "content": row["reference"], "subject_key": row["subject_key"], "competence_id": reference_id}
    value["digest"] = fingerprint(value)
    return value if digest is None or digest == value["digest"] else None


def binding_current(db, binding, unit, question):
    if unit.child_id != binding.child_id or question_digest(question) != binding.question_digest:
        return False
    if not binding.source_refs:
        return False  # Public references alone do not establish this child's source context.
    for ref in binding.source_refs:
        material = db.get(Material, ref["material_id"])
        if (not material or material.child_id != binding.child_id or source_ref(db, material) != ref):
            return False
    return binding.competence_id in catalogue() and binding.catalog_version == VERSION


def evidence(db, child_id, competence_ids=None):
    from .competence_models import QuestionCompetence

    rows = catalogue()
    selected = set(rows) if competence_ids is None else set(competence_ids) & set(rows)
    result = {key: {"id": key, "label": rows[key]["label"], "catalog_version": VERSION,
        "tasks": 0, "attempts": 0, "independent": 0, "supported": 0, "needs_practice": 0,
        "uncertain": 0, "reflection_tasks": 0, "historical_tasks": 0,
        "successful_check_dates": [], "evidence_refs": [], "last_observation": None,
        "last_assessment_observation": None,
        "last_independent_success": None, "last_difficulty": None} for key in rows if key in selected}
    bindings = list(db.scalars(select(QuestionCompetence).where(
        QuestionCompetence.child_id == child_id, QuestionCompetence.competence_id.in_(selected),
        QuestionCompetence.catalog_version == VERSION))) if selected else []
    bindings += _legacy_bindings(db, child_id, selected, {(row.unit_id, row.question_id) for row in bindings})
    units = {unit.id: unit for unit in db.scalars(select(LearningUnit).where(
        LearningUnit.child_id == child_id, LearningUnit.id.in_({row.unit_id for row in bindings})))}
    attempts = list(db.scalars(select(Attempt).where(Attempt.unit_id.in_(units)).order_by(
        Attempt.created, Attempt.id))) if units else []
    grouped = {}
    for attempt in attempts:
        grouped.setdefault((attempt.unit_id, attempt.question_id), []).append(attempt)
    child = db.get(Child, child_id)
    zone = ZoneInfo(Preferences(**child.preferences).timezone)
    checks = {}
    for binding in bindings:
        unit = units.get(binding.unit_id)
        question = next((q for q in unit.questions if q["id"] == binding.question_id), None) if unit else None
        values = sorted(grouped.get((binding.unit_id, binding.question_id), []),
            key=lambda a: (a.created, (a.evaluation or {}).get("attempt_number", 0), a.id))
        if not question or not values:
            continue
        state = result[binding.competence_id]
        if not binding_current(db, binding, unit, question):
            state["historical_tasks"] += 1
            continue
        last = values[-1]
        reflection = (last.evaluation or {}).get("method") == "open_learning_v1"
        independent = not reflection and len(values) == 1 and last.outcome == "correct" and not last.assisted
        state["tasks"] += 1
        state["attempts"] += len(values)
        bucket = "reflection_tasks" if reflection else "independent" if independent else "supported" if last.outcome == "correct" else "needs_practice" if last.outcome == "incorrect" else "uncertain"
        state[bucket] += 1
        state["last_observation"] = max(state["last_observation"] or 0, last.created)
        if not reflection:
            state["last_assessment_observation"] = max(state["last_assessment_observation"] or 0, last.created)
        state["evidence_refs"].extend("attempt:" + value.id for value in values)
        if independent:
            state["last_independent_success"] = max(state["last_independent_success"] or 0, last.created)
            if binding.role == "recall" and unit.round_kind in ("check", "spaced_review", "study_recall"):
                signature = normalized(question["prompt"])
                if signature not in checks.setdefault(binding.competence_id, set()):
                    checks[binding.competence_id].add(signature)
                    day = datetime.fromtimestamp(last.created, zone).date().isoformat()
                    if day not in state["successful_check_dates"]:
                        state["successful_check_dates"].append(day)
        elif not reflection:
            state["last_difficulty"] = max(state["last_difficulty"] or 0, last.created)
    from .coaching import planned_review
    from .subject_registry import identity

    for state in result.values():
        days = sorted(state["successful_check_dates"])
        state["successful_check_dates"] = days
        difficulty = datetime.fromtimestamp(state["last_difficulty"], zone).date().isoformat() if state["last_difficulty"] else None
        current = [day for day in days if difficulty is None or day > difficulty]
        secure = len(current) >= 3 and (date.fromisoformat(current[-1]) - date.fromisoformat(current[0])).days >= 7
        subject = db.get(Subject, identity(rows[state["id"]]["subject_key"]))
        stamp = state["last_assessment_observation"]
        state["review_due"] = planned_review(child, subject.title if subject else "", days,
            difficult=bool(state["needs_practice"] or state["supported"]),
            anchor=datetime.fromtimestamp(stamp, zone).date()) if stamp else None
        today = datetime.now(zone).date().isoformat()
        state["status"] = "review_due" if secure and state["review_due"] and state["review_due"] <= today else "repeated_independent" if secure else "building" if state["tasks"] - state["reflection_tasks"] else "unknown"
        state["confidence"] = "repeated_recall" if secure else "initial_evidence" if state["independent"] else "support_needed" if state["supported"] or state["needs_practice"] else "unverified"
        state["evidence_total"] = len(state["evidence_refs"])
        state["evidence_refs"] = state["evidence_refs"][-40:]
    return list(result.values())


def _legacy_bindings(db, child_id, selected, existing):
    """Reuse only a deterministic checked legacy fraction task, without writes.

    A historical local g1 label or a model's topic claim never establishes a
    stable identity. Unknown subjects/tasks remain unbound.
    """
    from .coaching import source_goals
    from .learning_entry import verified_math_identity

    if not any(identifier.startswith("math.") for identifier in selected):
        return []
    units = list(db.scalars(select(LearningUnit).where(LearningUnit.child_id == child_id,
        LearningUnit.subject.in_(("Mathematik", "Mathe")))))
    links = list(db.scalars(select(UnitSource).where(UnitSource.unit_id.in_([unit.id for unit in units])))) if units else []
    sources = {material.id: material for material in db.scalars(select(Material).where(
        Material.child_id == child_id, Material.id.in_([link.material_id for link in links])))} if links else {}
    refs_by_unit = {}
    for link in links:
        refs_by_unit.setdefault(link.unit_id, []).append(link)
    result = []
    for unit in units:
        references = refs_by_unit.get(unit.id, [])
        if not references or any(link.material_id not in sources or sources[link.material_id].revision != link.revision for link in references):
            continue
        pages = [sources[link.material_id] for link in references]
        refs = [source_ref(db, material) for material in pages]
        if any(ref is None for ref in refs):
            continue
        goals = source_goals([{"content": source_value(db, material)["content"]} for material in pages], unit.subject, unit.topic)
        allowed = {row["id"] for row in matches(db, pages, unit.subject)}
        for question in unit.questions:
            if (unit.id, question["id"]) in existing or question.get("type") not in ("short", "gap", "choice"):
                continue
            identifier = verified_math_identity(question, goals)
            if identifier not in selected or identifier not in allowed:
                continue
            result.append(SimpleNamespace(unit_id=unit.id, question_id=question["id"], child_id=child_id,
                competence_id=identifier, catalog_version=VERSION, role="recall" if unit.round_kind in
                ("check", "spaced_review", "study_recall") else "practice", question_digest=question_digest(question),
                source_refs=refs, reference_ids=[]))
    return result


def export_child(db, child_id):
    from .competence_models import CompetenceSource, QuestionCompetence

    return {"catalog_version": VERSION, "evidence": evidence(db, child_id),
        "source_bindings": [{"material_id": row.material_id, "revision": row.source_revision,
            "competence_id": row.competence_id, "catalog_version": row.catalog_version, "excerpt": row.excerpt}
            for row in db.scalars(select(CompetenceSource).where(CompetenceSource.child_id == child_id))],
        "question_bindings": [{"unit_id": row.unit_id, "question_id": row.question_id,
            "competence_id": row.competence_id, "catalog_version": row.catalog_version,
            "role": row.role, "source_refs": row.source_refs, "reference_ids": row.reference_ids}
            for row in db.scalars(select(QuestionCompetence).where(QuestionCompetence.child_id == child_id))]}
