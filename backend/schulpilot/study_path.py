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
    LearningUnit,
    ProviderConfig,
    SchoolDay,
    UnitSource,
    Usage,
    get_db,
    now,
    uid,
)
from .learning import local_day, plan, record
from .providers import ProviderError, config_for_function, request_provider, reserve, settle, source_excerpt_candidates
from .school_day import get_day, pages, planning_fingerprint
from .security import authenticated, child_user, rate_limit

router = APIRouter(tags=["Lernreise"])
log = logging.getLogger("schulpilot.study_path")
PHASES = (("understand", "Verstehen"), ("detective", "Fehlerdetektiv"), ("apply", "Anwenden"), ("recall", "Erinnern"))
STAGE_ACTIONS = {
    "understand": (
        "Einen bisher ungeprüften Zusammenhang verstehen und die passende Begründung auswählen.",
        "Zwei Angaben aus dem Heft vergleichen und den entscheidenden Unterschied erkennen.",
        "Einen Fachbegriff aus einem bisher ungeprüften Satz gezielt abrufen.",
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


def task_briefs(items, previous_prompts, phase, count):
    """Literal source anchors distribute practice beyond already asked facts.

    Lexical overlap only prioritizes passages; it is never a claim of semantic
    coverage or mastery. The model must still create and validate real tasks.
    """
    candidates = source_excerpt_candidates({"materials": [{"content": m.content} for m in items]})
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


def sources(db, day):
    items = pages(db, day)
    if not items or any(not m.confirmed or not m.content.strip() for m in items):
        raise ProviderError("Bitte zuerst alle Heftseiten prüfen und bestätigen.")
    if sum(len(m.content) for m in items) > 60_000:
        raise ProviderError("Der Stoff ist für eine Lernreise zu umfangreich. Bitte auf mehrere Schultage verteilen.")
    return items


def fingerprint(items):
    return hashlib.sha256(json.dumps([(m.id, m.revision) for m in items]).encode()).hexdigest()


def page_extent(material):
    words = len(re.findall(r"\w+", material.content))
    # Confirmed transcription is a better signal than image size or A4 alone.
    # Diagrams/formulas can be short; they still get more than one exposure.
    target = max(2 if words < 40 else 4, min(12, math.ceil(words / 55)))
    return {"material_id": material.id, "word_count": words, "target_questions": target}


def bounded_extents(items):
    extents = [page_extent(material) for material in items]
    # A large batch must not spend the entire cap on its first pages.
    # Keep every confirmed page represented while reducing the densest stages.
    while sum(e["target_questions"] for e in extents) > 120:
        max(extents, key=lambda entry: entry["target_questions"])["target_questions"] -= 1
    return extents


def ensure_plan(db, day):
    items = sources(db, day)
    source_hash = fingerprint(items)
    if day.learning_plan and day.learning_plan.get("source_hash") == source_hash:
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
    extents = bounded_extents(items)
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
    day.learning_plan = {"version": 1, "source_hash": source_hash, "extents": extents, "blocks": blocks}
    return day.learning_plan


def block_reason(db, child, subject, *, unit_id=None, question_count=2):
    prefs = s.Preferences(**child.preferences)
    today = local_day(child)
    if prefs.pause_until and today <= prefs.pause_until:
        return "Du hast gerade Lernpause. Deine Lernreise bleibt gespeichert."
    if today.weekday() not in prefs.weekdays or (
        prefs.subject_days.get(subject) and today.weekday() not in prefs.subject_days[subject]
    ):
        return "Heute ist dafür kein Lerntag. Die nächste Etappe bleibt für später da."
    current = plan(db, child)
    reserved = sum(
        (item.get("estimated_minutes") or current["session_minutes"])
        for item in current["today"]
        if item.get("id") != unit_id and item.get("kind") != "study_path"
    )
    needed = min(prefs.session_minutes, max(5, question_count * 2))
    if current["available_minutes"] - reserved < needed:
        return "Für heute reicht es. Deine nächste Etappe bleibt gespeichert."
    from .coaching import continuation_block

    probe = LearningUnit(child_id=child.id, subject=subject, questions=[], round_kind="study_block")
    return continuation_block(db, probe, child, check_sources=False)


def path_data(db, day, child):
    value = day.learning_plan or {}
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
        "block_reason": None,
        "stale": False,
    }
    if not value:
        return result
    try:
        result["stale"] = value.get("source_hash") != fingerprint(sources(db, day))
    except ProviderError:
        result["stale"] = True
    for saved in value.get("blocks", []):
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
        if status != "completed" and result["next_block_id"] is None:
            result["next_block_id"] = saved["id"]
            result["block_reason"] = block_reason(
                db,
                child,
                unit.subject if unit else saved.get("subject", ""),
                unit_id=unit.id if unit else None,
                question_count=count,
            )
    if result["stale"]:
        result["block_reason"] = (
            "Die Heftseiten wurden geändert. Bitte die Lernreise neu planen. Deine Antworten bleiben erhalten."
        )
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
            and day.learning_plan.get("source_hash") != fingerprint(sources(db, day))
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
    if state["stale"] or state["next_block_id"] != block_id or block.get("unit_id"):
        raise HTTPException(409, state["block_reason"] or "Bitte zuerst die aktuelle Etappe abschließen.")
    if state["block_reason"]:
        raise HTTPException(409, state["block_reason"])
    if db.scalar(select(Job.id).where(Job.child_id == child.id, Job.status.in_(["queued", "running"]))):
        raise HTTPException(409, "Eine Vorbereitung läuft noch. Bitte kurz warten.")
    attempts = db.scalar(
        select(func.count())
        .select_from(Job)
        .where(Job.child_id == child.id, Job.kind == "study_block", Job.payload["block_id"].as_string() == block_id)
    )
    if attempts >= 3:
        raise HTTPException(409, "Die Vorbereitung hat mehrfach nicht geklappt. Bitte deine Eltern um Hilfe bitten.")
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
        or fingerprint(items) != job.payload["source_hash"]
        or value.get("source_hash") != job.payload["source_hash"]
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
    result = None
    try:
        with DB() as db:
            job = db.get(Job, job_id)
            if not job or job.status != "running":
                return
            day, child, block, items = job_context(db, job)
            config = config_for_function(db.get(ProviderConfig, 1), "unit")
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
            payload = {
                "grade": child.grade,
                "required_subject": block["subject"],
                "required_topic": block["title"],
                "material": {
                    "subject": block["subject"],
                    "topic": block["title"],
                    "content": "\n\n".join(m.content for m in items),
                },
                "study_block": {
                    "mode": block["phase"],
                    "question_count": block["question_count"],
                    "tasks": task_briefs(items, previous_prompts, block["phase"], block["question_count"]),
                },
                "previous_prompts": previous_prompts,
            }
            values = {c.name: getattr(config, c.name) for c in ProviderConfig.__table__.columns}
            db.rollback()
        result = request_provider(ProviderConfig(**values), "unit", payload)
        data = s.UnitOutput.model_validate(result.data).model_dump()
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
            from .commerce import usage_terms
            from .providers import external_allowed

            current_config = config_for_function(db.get(ProviderConfig, 1), "unit")
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
                **data,
            )
            db.add(unit)
            db.flush()
            for material in items:
                db.add(UnitSource(unit_id=unit.id, material_id=material.id, revision=material.revision))
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
                job.status, job.error, job.finished = "failed", reason[:500], int(now())
                usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
                if usage:
                    settle(db, usage, result, failed=True)
        log.warning("study_block_failed type=%s", type(error).__name__)
