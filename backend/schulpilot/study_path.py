"""A source-sized course, generated one small, budgeted stage at a time.

The estimate describes planned practice, never mastery or already generated
questions. Existing answers are immutable; missed days do not add workload.
"""

import copy
import hashlib
import json
import logging
import math
import re

from fastapi import APIRouter, Depends, Header, HTTPException
from sqlalchemy import func, select, update

from . import schemas as s
from .db import (
    DB,
    Attempt,
    Child,
    Family,
    Job,
    LearningMemory,
    LearningUnit,
    ProviderConfig,
    SchoolDay,
    UnitSource,
    Usage,
    get_db,
    now,
    uid,
)
from .learning import record
from .model_routing import job_config, selection
from .providers import ProviderError, request_provider, reserve, settle, source_excerpt_candidates
from .school_day import get_day, pages, planning_fingerprint
from .security import authenticated, child_user, rate_limit

router = APIRouter(tags=["Lernreise"])
log = logging.getLogger("schulpilot.study_path")
TECHNICAL_REVIEW_MESSAGE = "Die Vorbereitung dieser Etappe muss technisch geprüft werden. Weitere Versuche sind vorerst gesperrt. Deine gespeicherten Runden bleiben verfügbar."
PHASES = (("understand", "Verstehen"), ("detective", "Fehlerdetektiv"), ("apply", "Anwenden"), ("recall", "Erinnern"))
STAGE_ACTIONS = {
    "understand": (
        "Einen bisher ungeprüften Zusammenhang verstehen und die passende Begründung auswählen.",
        "Zwei Angaben aus dem Heft vergleichen und den entscheidenden Unterschied erkennen.",
        "Eine ausdrücklich als falsch markierte Behauptung mit dem bestätigten Wissen richtigstellen.",
    ),
    "detective": (
        "Eine ausdrücklich als falsch markierte Aussage mit einer richtigen Begründung korrigieren.",
        "Zwei Erklärungen vergleichen und den sachlichen Denkfehler finden.",
        "Den passenden Fachbegriff zur Korrektur eines beschriebenen Irrtums nennen.",
    ),
    "apply": (
        "Das bestätigte Wissen auf einen kleinen neuen, ausdrücklich erfundenen Alltagsfall anwenden.",
        "Eine passende Beobachtung oder Folge anhand der bestätigten Regel vorhersagen.",
        "Den passenden Fachbegriff in einer neuen Situation zuordnen.",
    ),
    "recall": (
        "Einen noch nicht geprüften Zusammenhang ohne vorweggenommene Lösung abrufen.",
        "Eine richtige Begründung für eine bestätigte Beobachtung selbst wiedererkennen.",
        "Einen Begriff gezielt aus dem Gedächtnis abrufen, ohne die Antwort in der Frage zu nennen.",
    ),
}


def task_briefs(items, previous_prompts, phase, count, *, contents=None):
    """Literal source anchors distribute practice beyond already asked facts.

    Lexical overlap only prioritizes passages; it is never a claim of semantic
    coverage or mastery. The model must still create and validate real tasks.
    """
    candidates = source_excerpt_candidates({"materials": [{"content": text} for text in
        (contents if contents is not None else [m.content for m in items])]})
    stopwords = set(
        "der die das den dem des ein eine einer eines einem einen ist sind im in am an auf und oder zu mit für von als es sie er auch nicht wird werden hat haben bei man sich aus zum zur".split()
    )

    def words(value):
        return set(re.findall(r"\w{3,}", value.casefold())) - stopwords

    previous = words(" ".join(previous_prompts))
    selected = set()
    available = list(candidates)
    actions = STAGE_ACTIONS.get(phase, STAGE_ACTIONS["understand"])
    result = []
    for index in range(count):
        if not available:
            available = list(candidates)
        if not available:
            raise ProviderError("Für die Etappe fehlt bestätigter Lernstoff.")
        excerpt = min(
            available,
            key=lambda text: (
                (len(words(text) & previous) + 0.5 * len(words(text) & selected)) / max(1, len(words(text))),
                -min(len(words(text)), 25),
            ),
        )
        available.remove(excerpt)
        selected |= words(excerpt)
        result.append({"number": index + 1, "action": actions[index % len(actions)], "source_excerpt": excerpt})
    return result


def validate_fraction_comparison_application(subject, topic, phase, contents, questions):
    """Do not present component-only questions as a sourced comparison stage."""
    from fractions import Fraction

    from .coaching import fraction_task_signature
    from .math_tasks import _comparison_examples

    if subject != "Mathematik" or phase != "apply" or not re.search(r"brüche\s+vergleich", topic, re.I):
        return
    examples = _comparison_examples([{"content": text} for text in contents])
    if not examples:
        return  # No claim that an arbitrary source teaches a comparison rule.
    allowed = {tuple(sorted(((str(n), str(d)), (str(a), str(b))))) for (n, d, a, b), _ in examples}
    for question in questions:
        signature = fraction_task_signature(question.get("prompt", ""))
        if not signature or signature[0] != "compare" or signature[1] not in allowed:
            raise ProviderError("Die Aufgaben passen noch nicht zum Bruchvergleich.", code="invalid_output")
        prompt = question["prompt"].casefold()
        larger = bool(re.search(r"\b(?:grösser|groesser)\b", prompt))
        smaller = bool(re.search(r"\bkleiner\b", prompt))
        if larger == smaller or question.get("type") != "short":
            raise ProviderError("Die Vergleichsaufgabe ist nicht eindeutig.", code="invalid_output")
        candidates = [Fraction(int(n), int(d)) for n, d in signature[1]]
        expected = max(candidates) if larger else min(candidates)
        answer = question.get("answer", "")
        try:
            correct = bool(re.fullmatch(r"\d{1,2}/[1-9]\d?", answer)) and Fraction(answer) == expected
        except (TypeError, ValueError, ZeroDivisionError):
            correct = False
        if not correct:
            raise ProviderError("Die Lösung des Bruchvergleichs ist nicht eindeutig.", code="invalid_output")


def sources(db, day):
    from .material_review import held

    items = [m for m in pages(db, day) if not held(db, m)]
    if not items or any(not m.confirmed or not m.content.strip() for m in items):
        raise ProviderError("Bitte zuerst alle Heftseiten prüfen und bestätigen.")
    from .learning_sources import UnusableSources, project

    try:
        safe = project(db, items)
    except UnusableSources as error:
        raise ProviderError(str(error)) from None
    if sum(len(value["content"]) for value in safe) > 60_000:
        raise ProviderError("Der Stoff ist für eine Lernreise zu umfangreich. Bitte auf mehrere Schultage verteilen.")
    return [material for material, value in zip(items, safe, strict=True) if value["content"].strip()]


def fingerprint(items, db=None):
    from .source_lineage import learning_source

    # Safe content/policy are part of a pending stage, not a retroactive score.
    values = [(m.id, m.revision, {key: value for key, value in learning_source(db, m).items()
                                if key != "policy_version"}) for m in items]
    return hashlib.sha256(json.dumps(values, sort_keys=True).encode()).hexdigest()


def compatible_fingerprints(items, db):
    """Legacy compatibility requires byte-identical eligible text AND exclusions.

    A policy label alone is not a changed source. Recompute historical hashes
    against today's full safe projection; never accept an older quarantine.
    """
    from .source_lineage import learning_source

    rows = [(m.id, m.revision, learning_source(db, m)) for m in items]
    return {fingerprint(items, db), *(
        hashlib.sha256(json.dumps([(mid, revision, {**value, "policy_version": policy})
            for mid, revision, value in rows], sort_keys=True).encode()).hexdigest()
        for policy in ("literal-safety-1", "literal-safety-2"))}


def page_extent(material, *, content=None):
    words = len(re.findall(r"\w+", material.content if content is None else content))
    # Confirmed transcription is a better signal than image size or A4 alone.
    # Diagrams/formulas can be short; they still get more than one exposure.
    target = max(2 if words < 40 else 4, min(12, math.ceil(words / 55)))
    return {"material_id": material.id, "word_count": words, "target_questions": target}


def bounded_extents(items, db=None):
    from .source_lineage import learning_source

    extents = [page_extent(material, content=learning_source(db, material)["content"])
               if db is not None else page_extent(material) for material in items]
    # A large batch must not spend the entire cap on its first pages.
    # Keep every confirmed page represented while reducing the densest stages.
    while sum(e["target_questions"] for e in extents) > 120:
        max(extents, key=lambda entry: entry["target_questions"])["target_questions"] -= 1
    return extents


def prerequisite_only_sources(db, day, blocks, items):
    """Find a fully evidenced check-only path without altering any learner data.

    Unknown/legacy question roles are deliberately not guessed from IDs or
    text. Pending stages, unrelated units and stale source links also make
    this conservative projection inapplicable.
    """
    if not blocks:
        return []
    if sum(block.get("question_count", 0) for block in blocks) + 2 > 120:
        return []
    allowed = {item.id: item for item in items}
    grouped = {}
    for block in blocks:
        grouped.setdefault(block.get("subject"), []).append(block)
    chosen = []
    for subject, subject_blocks in grouped.items():
        if not subject or any(not block.get("unit_id") for block in subject_blocks):
            continue
        matched = None
        for block in subject_blocks:
            unit = db.get(LearningUnit, block["unit_id"])
            memory = db.get(LearningMemory, block["unit_id"])
            if not unit or unit.child_id != day.child_id or unit.subject != subject or not unit.questions or not memory or memory.child_id != day.child_id:
                break
            entry = (memory.working or {}).get("entry_plan") or {}
            roles = {question.get("id"): question.get("role") for question in entry.get("questions", [])}
            if any(roles.get(question.get("id")) != "prior_check" for question in unit.questions):
                break
            links = list(db.scalars(select(UnitSource).where(UnitSource.unit_id == unit.id)))
            if not links or any(link.material_id not in allowed or allowed[link.material_id].revision != link.revision for link in links):
                break
            source = next((allowed[link.material_id] for link in links if allowed[link.material_id].subject == subject), None)
            if not source:
                break
            matched = matched or source
        else:
            if matched:
                chosen.append(matched)
    return chosen


def append_application_stages(db, day, items, plan):
    """Append bounded planned work only; retain every existing block and job."""
    candidates = prerequisite_only_sources(db, day, plan.get("blocks", []), items)
    if not candidates:
        return plan
    value = copy.deepcopy(plan)
    remaining = 120 - sum(block.get("question_count", 0) for block in value["blocks"])
    for material in candidates:
        if remaining < 2:
            break
        value["blocks"].append({
            "id": uid(), "title": material.topic or f"Seite {material.page_number or 1}",
            "phase": "apply", "label": "Anwenden", "subject": material.subject,
            "material_ids": [material.id], "question_count": 2, "unit_id": None, "job_id": None,
        })
        remaining -= 2
    return value


def ensure_plan(db, day):
    items = sources(db, day)
    source_hash = fingerprint(items, db)
    if day.learning_plan and day.learning_plan.get("source_hash") in compatible_fingerprints(items, db):
        current = {**day.learning_plan, "source_hash": source_hash, "fingerprint_version": 2}
        day.learning_plan = append_application_stages(db, day, items, current)
        return day.learning_plan
    material_ids = {m.id for m in items}
    revisions = {m.id: m.revision for m in items}
    existing = []
    for unit in db.scalars(
        select(LearningUnit).where(LearningUnit.school_day_id == day.id).order_by(LearningUnit.created, LearningUnit.id)
    ):
        links = list(db.scalars(select(UnitSource).where(UnitSource.unit_id == unit.id)))
        if links and all(
            link.material_id in revisions and revisions[link.material_id] == link.revision for link in links
        ):
            existing.append((unit, {link.material_id for link in links}))
    extents = bounded_extents(items, db)
    total = min(120, sum(e["target_questions"] for e in extents))
    blocks = []
    credits = {m.id: 0 for m in items}
    for unit, links in existing:
        blocks.append(
            {
                "id": "unit-" + unit.id,
                "title": unit.topic,
                "phase": "learning",
                "label": "Erste Runde",
                "subject": unit.subject,
                "question_count": len(unit.questions),
                "unit_id": unit.id,
                "job_id": None,
            }
        )
        for _ in unit.questions:
            chosen = min(links & material_ids, key=lambda key: (credits[key], key))
            credits[chosen] += 1
    remaining = max(0, total - sum(b["question_count"] for b in blocks))
    for material, extent in zip(items, extents, strict=True):
        count = min(remaining, max(0, extent["target_questions"] - credits[material.id]))
        while count:
            if count == remaining == 1:
                previous = next(
                    (
                        b
                        for b in reversed(blocks)
                        if not b.get("unit_id") and b.get("subject") == material.subject and b["question_count"] < 5
                    ),
                    None,
                )
                if previous:
                    previous["question_count"] += 1
                    if material.id not in previous["material_ids"]:
                        previous["material_ids"].append(material.id)
                        previous["title"] = (previous["title"] + " · " + material.topic)[:160]
                remaining = count = 0
                break
            take = min(5, count)
            if count - take == 1:
                take -= 1
            # A remaining single question joins a two-task contrast stage.
            take = max(2, take)
            phase, label = PHASES[(len(blocks) - len(existing)) % len(PHASES)]
            blocks.append(
                {
                    "id": uid(),
                    "title": material.topic or f"Seite {material.page_number or 1}",
                    "phase": phase,
                    "label": label,
                    "subject": material.subject,
                    "material_ids": [material.id],
                    "question_count": take,
                    "unit_id": None,
                    "job_id": None,
                }
            )
            count = max(0, count - take)
            remaining = max(0, remaining - take)
    day.learning_plan = {"version": 1, "fingerprint_version": 2, "source_hash": source_hash, "extents": extents, "blocks": blocks}
    day.learning_plan = append_application_stages(db, day, items, day.learning_plan)
    return day.learning_plan


def block_reason(db, child, subject, *, unit_id=None, question_count=2, current_plan=None):
    # Scheduling and remaining goal minutes inform recommendations. An
    # explicit stage request is voluntary and still uses the ordinary budget.
    if unit_id is None:
        return None
    unit = db.get(LearningUnit, unit_id)
    if not unit or unit.child_id != child.id:
        return "Diese Etappe ist nicht verfügbar."
    from .coaching import continuation_block

    return continuation_block(db, unit, child, check_sources=False)


def source_backed_blocks(db, day, *, material_ids=None, unit_ids=None):
    """Read-only projection: no offer from deleted/foreign source snapshots.

    Saved rounds remain available independently. A dangling saved-round ID is
    never converted back into a fresh generation request.
    """
    from .db import Material

    if material_ids is None:
        material_ids = set(db.scalars(select(Material.id).where(
            Material.child_id == day.child_id, Material.school_day_id == day.id,
            Material.confirmed.is_(True))))
    if unit_ids is None:
        unit_ids = set(db.scalars(select(LearningUnit.id).where(LearningUnit.child_id == day.child_id)))
    return [block for block in (day.learning_plan or {}).get("blocks", [])
            if (block.get("unit_id") in unit_ids if block.get("unit_id") else
                bool(block.get("material_ids")) and set(block["material_ids"]) <= material_ids)]


def plan_sources_current(db, day):
    """Shared read-only gate; never rebuild a plan or publish an exercise."""
    value = day.learning_plan or {}
    if not value:
        return False
    try:
        return value.get("source_hash") in compatible_fingerprints(sources(db, day), db)
    except ProviderError:
        return False


def path_data(db, day, child):
    value = day.learning_plan or {}
    from .material_review import held

    pending_review = [m for m in pages(db, day) if not held(db, m) and (not m.confirmed or not m.content.strip())]
    result = {
        "available": bool(value),
        "id": day.id,
        "day_id": day.id,
        "total_questions": 0,
        "completed_questions": 0,
        "ready_questions": 0,
        "blocks": [],
        "next_block_id": None,
        "can_continue": False,
        "technical_review_required": False,
        "block_reason": None,
        "stale": False,
        "pending_review_count": len(pending_review),
        "next_review_material_id": pending_review[0].id if pending_review else None,
        "application_missing": False,
    }
    if not value:
        return result
    result["stale"] = not plan_sources_current(db, day)
    if not result["stale"]:
        result["application_missing"] = bool(prerequisite_only_sources(db, day, value.get("blocks", []), sources(db, day)))
    from .learning_origins import open_rounds

    result["related_rounds"] = open_rounds(db, child.id, day.id)
    for saved in source_backed_blocks(db, day):
        unit = db.get(LearningUnit, saved.get("unit_id")) if saved.get("unit_id") else None
        job = db.get(Job, saved.get("job_id")) if saved.get("job_id") else None
        status = (
            "completed"
            if unit and unit.status == "completed"
            else "ready"
            if unit
            else "generating"
            if job and job.status in ("queued", "running")
            else "planned"
        )
        count = len(unit.questions) if unit else saved["question_count"]
        answered = 0
        if unit:
            attempts = list(db.scalars(select(Attempt).where(Attempt.unit_id == unit.id)))
            for question in unit.questions:
                responses = [a for a in attempts if a.question_id == question["id"]]
                answered += int(len(responses) >= 3 or any(a.outcome in ("correct", "uncertain") for a in responses))
        block = {key: saved.get(key) for key in ("id", "title", "phase", "label", "unit_id", "job_id")}
        block.update(
            status=status,
            question_count=count,
            completed_questions=answered,
            error=job.error if job and job.status == "failed" else None,
        )
        result["blocks"].append(block)
        result["total_questions"] += count
        result["completed_questions"] += answered
        result["ready_questions"] += count - answered if status == "ready" else 0
    # Prefer the suggested portion, then explicitly available voluntary work.
    # Neither a free day nor a reached time goal closes the source-sized path.
    from .learning import plan

    current = plan(db, child)
    open_blocks = [b for b in result["blocks"] if b["status"] != "completed"]
    preferred = next(
        (
            b
            for item in [*current["today"], *current.get("voluntary", [])]
            for b in open_blocks
            if (item["kind"] == "study_path" and item["id"] == day.id and item.get("block_id") == b["id"])
            or (item["kind"] == "unit" and item["id"] == b.get("unit_id"))
        ),
        None,
    )
    next_block = preferred or next(iter(open_blocks), None)
    if next_block:
        saved = next(b for b in value["blocks"] if b["id"] == next_block["id"])
        unit = db.get(LearningUnit, saved.get("unit_id")) if saved.get("unit_id") else None
        result["next_block_id"] = saved["id"]
        result["block_reason"] = block_reason(
            db,
            child,
            unit.subject if unit else saved.get("subject", ""),
            unit_id=unit.id if unit else None,
            question_count=next_block["question_count"],
            current_plan=current,
        )
    if result["stale"]:
        result["block_reason"] = (
            "Bitte zuerst die offenen Heftseiten prüfen. Deine Antworten bleiben erhalten."
            if pending_review else
            "Die Heftseiten wurden geändert. Bitte die Lernreise neu planen. Deine Antworten bleiben erhalten."
        )
    if next_block and not unit and not result["stale"]:
        current_job = db.get(Job, saved.get("job_id")) if saved.get("job_id") else None
        if not current_job or current_job.status not in ("queued", "running"):
            condition = (Job.child_id == child.id, Job.kind == "study_block",
                         Job.payload["day_id"].as_string() == day.id,
                         Job.payload["block_id"].as_string() == saved["id"])
            count = db.scalar(select(func.count()).select_from(Job).where(*condition))
            latest = db.scalar(select(Job).where(*condition).order_by(Job.created.desc(), Job.id.desc()).limit(1))
            if count >= 3 and latest and latest.status == "failed":
                result["technical_review_required"] = True
                result["block_reason"] = TECHNICAL_REVIEW_MESSAGE
    result["can_continue"] = bool(result["next_block_id"] and not result["block_reason"])
    return result


@router.get("/school-days/{day_id}/study-path")
def view(day_id: str, p=Depends(authenticated), db=Depends(get_db)):
    day, child = get_day(db, p, day_id)
    return path_data(db, day, child)


@router.post("/school-days/{day_id}/study-path")
def create(day_id: str, p=Depends(child_user), db=Depends(get_db)):
    day, child = get_day(db, p, day_id)
    db.execute(update(Child).where(Child.id == child.id).values(grade=Child.grade))
    db.refresh(day)
    try:
        if (
            day.learning_plan
            and not plan_sources_current(db, day)
            and db.scalar(select(Job.id).where(Job.child_id == child.id, Job.status.in_(["queued", "running"])))
        ):
            raise HTTPException(409, "Bitte die laufende Vorbereitung zuerst beenden lassen.")
        ensure_plan(db, day)
    except ProviderError as error:
        raise HTTPException(409, str(error)) from None
    db.commit()
    return path_data(db, day, child)


@router.post("/school-days/{day_id}/blocks/{block_id}", status_code=202)
def generate(
    day_id: str,
    block_id: str,
    idempotency: str = Header(alias="Idempotency-Key", default=""),
    p=Depends(child_user),
    db=Depends(get_db),
):
    day, child = get_day(db, p, day_id)
    if not idempotency or len(idempotency) > 80:
        raise HTTPException(422, "Bitte einen eindeutigen Anfrageschlüssel verwenden.")
    db.execute(update(Child).where(Child.id == child.id).values(grade=Child.grade))
    db.refresh(day)
    # Upgrade only a proven metadata-compatible fingerprint; keep every block,
    # failed attempt and saved round. A real source change still needs a replan.
    if plan_sources_current(db, day):
        ensure_plan(db, day)
    value = copy.deepcopy(day.learning_plan or {})
    block = next((b for b in value.get("blocks", []) if b["id"] == block_id), None)
    if not block:
        raise HTTPException(404, "Etappe nicht gefunden.")
    previous = db.scalar(select(Job).where(Job.idempotency == p.user.id + ":" + idempotency))
    if previous:
        if (
            previous.kind != "study_block"
            or previous.child_id != child.id
            or previous.payload.get("block_id") != block_id
            or previous.payload.get("day_id") != day.id
        ):
            raise HTTPException(409, "Dieser Anfrageschlüssel gehört zu einer anderen Etappe.")
        return {"id": previous.id, "status": previous.status}
    state = path_data(db, day, child)
    if state["stale"] or block.get("unit_id"):
        raise HTTPException(409, state["block_reason"] or "Diese Etappe ist nicht mehr verfügbar.")
    # The learner can explicitly choose the first available stage of another
    # subject. The planner's voluntary list retains source order within each
    # subject and excludes future or unavailable stages.
    if state["next_block_id"] != block_id:
        from .learning import plan

        current = plan(db, child)
        if not any(item.get("kind") == "study_path" and item.get("id") == day.id
                   and item.get("block_id") == block_id for item in current.get("voluntary", [])):
            raise HTTPException(409, "Bitte zuerst die vorherige Etappe dieses Fachs abschließen.")
    elif state["block_reason"]:
        raise HTTPException(409, state["block_reason"])
    if db.scalar(select(Job.id).where(Job.child_id == child.id, Job.status.in_(["queued", "running"]))):
        raise HTTPException(409, "Eine Vorbereitung läuft noch. Bitte kurz warten.")
    attempts = db.scalar(
        select(func.count())
        .select_from(Job)
        .where(Job.child_id == child.id, Job.kind == "study_block", Job.payload["block_id"].as_string() == block_id)
    )
    if attempts >= 3:
        raise HTTPException(409, TECHNICAL_REVIEW_MESSAGE)
    from .study_authority import bind as bind_authority

    authority = bind_authority(db, p, child)
    rate_limit(db, "study:" + p.user.id, 12, 600, commit=False)
    job = Job(
        id=uid(),
        child_id=child.id,
        kind="study_block",
        idempotency=p.user.id + ":" + idempotency,
        payload={
            "day_id": day.id,
            "block_id": block_id,
            "source_hash": value["source_hash"],
            "planning": planning_fingerprint(db, child),
            "study_authority": authority,
            "completion_origin": authority,
        },
    )
    db.add(job)
    db.flush()
    family = db.get(Family, child.family_id)
    if family.synthetic or any(m.synthetic for m in sources(db, day)):
        raise HTTPException(
            409,
            "Die Beispielseiten haben feste Beispielaufgaben. Eigene Lernreisen starten mit deinen bestätigten Seiten.",
        )
    reserve(db, family, child.id, job.id, "unit")
    block["job_id"] = job.id
    day.learning_plan = value
    db.commit()
    return {"id": job.id, "status": job.status}


def job_context(db, job):
    day = db.get(SchoolDay, job.payload["day_id"])
    child = db.get(Child, job.child_id)
    if not day or day.child_id != job.child_id or not child:
        raise ProviderError("Der Schultag ist nicht mehr verfügbar.")
    from .study_authority import validate as validate_authority

    validate_authority(db, child, job.payload.get("study_authority"))
    family = db.get(Family, child.family_id)
    if not family or (family.expires and family.expires < now()):
        raise ProviderError("Dieser Zugang ist abgelaufen. Die Antworten bleiben gespeichert.")
    items = sources(db, day)
    value = day.learning_plan or {}
    block = next((b for b in value.get("blocks", []) if b["id"] == job.payload["block_id"]), None)
    if (
        not block
        or block.get("job_id") != job.id
        or block.get("unit_id")
        or job.payload["source_hash"] not in compatible_fingerprints(items, db)
        or value.get("source_hash") not in compatible_fingerprints(items, db)
    ):
        raise ProviderError("Die Heftseiten oder die Lernreise wurden verändert. Bitte neu planen.")
    if planning_fingerprint(db, child) != job.payload["planning"]:
        raise ProviderError("Deine Eltern haben die Planung geändert. Bitte die neue Planung öffnen.")
    if reason := block_reason(db, child, block["subject"], question_count=block["question_count"]):
        raise ProviderError(reason)
    selected = [m for m in items if m.id in block["material_ids"]]
    if len(selected) != len(block["material_ids"]):
        raise ProviderError("Eine Heftseite fehlt. Bitte die Lernreise neu planen.")
    return day, child, block, selected


def process(job_id):
    from .learning_sources import failure_billing

    result = None
    provider_requested = False
    try:
        with DB() as db:
            job = db.get(Job, job_id)
            if not job or job.status != "running":
                return
            day, child, block, items = job_context(db, job)
            config = job_config(db, job, "unit")
            usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
            if not usage or (usage.provider, usage.model, usage.config_revision) != (
                config.provider,
                config.model,
                config.revision,
            ):
                raise ProviderError("Die KI-Einstellungen wurden geändert. Bitte erneut vorbereiten.")
            from .commerce import usage_terms

            usage_terms(db, db.get(Family, child.family_id), enforce=True)
            previous_prompts = [
                q["prompt"]
                for u in db.scalars(select(LearningUnit).where(LearningUnit.school_day_id == day.id))
                for q in u.questions
            ][-120:]
            from .grades import subject_key
            from .learning_guidance import strategies
            from .learning_sources import project

            safe = project(db, items)
            payload = {
                "grade": child.grade,
                "instructional_support": strategies(db, child).get(subject_key(block["subject"]), "practice_and_retrieval"),
                "required_subject": block["subject"],
                "required_topic": block["title"],
                "material": {
                    "subject": block["subject"],
                    "topic": block["title"],
                    "content": "\n\n".join(value["content"] for value in safe),
                    "uncertainties": [warning for m in items for warning in m.uncertainties],
                },
                "study_block": {
                    "mode": block["phase"],
                    "question_count": block["question_count"],
                    "tasks": task_briefs(items, previous_prompts, block["phase"], block["question_count"],
                                         contents=[value["content"] for value in safe]),
                },
                "previous_prompts": previous_prompts,
            }
            from .catalog_ai import with_catalog_context

            payload = with_catalog_context(db, child, payload)
            from .visual_references import with_visual_context

            payload = with_visual_context(db, child, payload, items)
            from .package_decimal_addition import HISTORY, REFERENCE
            from .package_decimal_addition import history as decimal_history

            if any(r.get("id") == REFERENCE for r in (payload.get("visual_context") or {}).get("references", [])):
                payload[HISTORY] = decimal_history(db, child.id)
            from .unit_multiples_common import with_history

            payload = with_history(payload, previous_prompts)
            values = {c.name: getattr(config, c.name) for c in ProviderConfig.__table__.columns}
            route_snapshot = copy.deepcopy(selection(config))
            db.rollback()
        provider_requested = True
        request_config = ProviderConfig(**values)
        request_config._selected_route = route_snapshot
        result = request_provider(request_config, "unit", payload)
        data = s.UnitOutput.model_validate(result.data).model_dump()
        validate_fraction_comparison_application(
            payload["required_subject"], payload["required_topic"], payload["study_block"]["mode"],
            [value["content"] for value in safe], data["questions"],
        )
        from .coaching import normalized_prompt

        if (
            data["subject"] != payload["required_subject"]
            or data["topic"] != payload["required_topic"]
            or len(data["questions"]) != payload["study_block"]["question_count"]
        ):
            raise ProviderError("Die Etappe passt nicht zum geplanten Stoffumfang.")
        prompts = [normalized_prompt(q["prompt"]) for q in data["questions"]]
        if len(set(prompts)) != len(prompts) or set(prompts) & {
            normalized_prompt(p) for p in payload["previous_prompts"]
        }:
            raise ProviderError("Die KI hat bereits gestellte Fragen wiederholt. Bitte neu vorbereiten.")
        with DB.begin() as db:
            job = db.get(Job, job_id)
            if not job or job.status != "running":
                return
            db.execute(update(Child).where(Child.id == job.child_id).values(grade=Child.grade))
            day, child, block, items = job_context(db, job)
            from .package_decimal_addition import validate_history as validate_decimal_history

            validate_decimal_history(db, child.id, {"units": [data]})
            from .commerce import usage_terms
            from .providers import external_allowed

            current_config = job_config(db, job, "unit")
            if (
                current_config.revision != values["revision"]
                or current_config.provider != values["provider"]
                or current_config.model != values["model"]
            ):
                raise ProviderError("Die KI-Einstellungen wurden während der Vorbereitung geändert.")
            external_allowed(current_config)
            usage_terms(db, db.get(Family, child.family_id), enforce=True)
            unit = LearningUnit(
                child_id=child.id,
                school_day_id=day.id,
                material_id=items[0].id,
                estimated_minutes=min(
                    s.Preferences(**child.preferences).session_minutes, max(5, block["question_count"] * 2)
                ),
                package_version=day.package_version,
                round_kind="study_recall" if block["phase"] == "recall" else "study_block",
                introduction_seen=block["phase"] == "recall",
                synthetic=False,
                provider=values["provider"],
                model=values["model"],
                **{key: data[key] for key in ("subject", "topic", "explanation", "questions")},
            )
            db.add(unit)
            db.flush()
            from .visual_references import remember as remember_visuals

            remember_visuals(db, unit, data, payload)
            for material in items:
                db.add(UnitSource(unit_id=unit.id, material_id=material.id, revision=material.revision))
            if result.catalog_assignment:
                from .catalog_ai import remember

                remember(db, "unit", unit, result.catalog_assignment)
            value = copy.deepcopy(day.learning_plan)
            next(b for b in value["blocks"] if b["id"] == block["id"])["unit_id"] = unit.id
            day.learning_plan = value
            record(
                db,
                child.id,
                "unit_created",
                {"subject": unit.subject, "topic": unit.topic, "school_day_id": day.id, "phase": block["phase"]},
                unit.id,
            )
            settle(db, db.scalar(select(Usage).where(Usage.job_id == job.id)), result)
            job.status, job.finished, job.result = "completed", int(now()), {"unit_id": unit.id}
    except Exception as error:
        reason = (
            str(error)
            if isinstance(error, ProviderError)
            else "Die Etappe konnte nicht sicher vorbereitet werden. Deine Antworten bleiben gespeichert."
        )
        with DB.begin() as db:
            job = db.get(Job, job_id)
            if job:
                from .job_failures import failure_code

                job.status, job.error, job.finished = "failed", reason[:500], int(now())
                job.error_code = failure_code(error)
                usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
                if usage:
                    settle(db, usage, failure_billing(result, error, provider_requested=provider_requested), failed=True)
        log.warning("study_block_failed type=%s", type(error).__name__)
