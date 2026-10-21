"""Source-bound notebook questions through the existing durable job queue."""

import json
import unicodedata

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from pydantic import ValidationError
from sqlalchemy import delete, or_, select, update

from .commerce import usage_terms
from .db import (
    DB,
    Child,
    Family,
    Job,
    LearningUnit,
    Material,
    ProviderConfig,
    SchoolDay,
    Session,
    TutorTurn,
    UnitSource,
    Usage,
    User,
    get_db,
    now,
    uid,
)
from .learning import record
from .model_routing import job_config
from .providers import ProviderError, Result, external_allowed, request_provider, reserve, settle
from .security import Principal, authenticated, child_access, child_user, digest, rate_limit
from .tutor_schemas import TutorOutput, TutorQuestion, TutorScope

router = APIRouter(tags=["Fragen zum Heft"])
MAX_CONTENT = 60_000
PAGE_SIZE = 20
HISTORY_SIZE = 4


def scope_values(value):
    return {"day_id": value.school_day_id, "material_id": value.material_id, "unit_id": value.unit_id}


def scope_filter(scope):
    return (
        TutorTurn.school_day_id == scope.day_id,
        TutorTurn.material_id == scope.material_id,
        TutorTurn.unit_id == scope.unit_id,
    )


def sources_for(db, child, scope):
    """Resolve owned sources, never a client-supplied family membership."""
    scope_revision = None
    if scope.day_id:
        day = db.get(SchoolDay, scope.day_id)
        if not day or day.child_id != child.id:
            raise HTTPException(404, "Schultag nicht gefunden.")
        scope_revision = day.revision
        materials = list(
            db.scalars(
                select(Material).where(Material.school_day_id == day.id).order_by(Material.page_number, Material.id)
            )
        )
    elif scope.material_id:
        material = db.get(Material, scope.material_id)
        if not material or material.child_id != child.id:
            raise HTTPException(404, "Heftseite nicht gefunden.")
        materials = [material]
    else:
        unit = db.get(LearningUnit, scope.unit_id)
        if not unit or unit.child_id != child.id:
            raise HTTPException(404, "Lerneinheit nicht gefunden.")
        if unit.synthetic:
            raise HTTPException(403, "Eigene Heftfragen sind im Beispielraum nicht verfügbar.")
        rows = list(
            db.scalars(select(UnitSource).where(UnitSource.unit_id == unit.id).order_by(UnitSource.material_id))
        )
        materials = [db.get(Material, row.material_id) for row in rows]
        if any(
            not material or material.revision != row.revision for row, material in zip(rows, materials, strict=True)
        ):
            raise HTTPException(
                409, "Die Heftseiten dieser Einheit wurden geändert. Bitte öffne die aktuelle Heftseite."
            )
        if not rows and unit.material_id:
            materials = [db.get(Material, unit.material_id)]
    if not materials:
        raise HTTPException(409, "Bitte zuerst eine Heftseite hinzufügen und den erkannten Text bestätigen.")
    if any(not m or m.child_id != child.id for m in materials):
        raise HTTPException(404, "Heftseite nicht gefunden.")
    if any(not m.confirmed or not m.content.strip() for m in materials):
        raise HTTPException(409, "Bitte zuerst den erkannten Text aller zugehörigen Heftseiten bestätigen.")
    if len(materials) > 24 or sum(len(m.content) for m in materials) > MAX_CONTENT:
        raise HTTPException(
            422, "Das Material ist für eine gemeinsame Frage zu umfangreich. Wähle eine einzelne Heftseite."
        )
    if any(m.synthetic for m in materials):
        raise HTTPException(403, "Eigene Heftfragen sind im Beispielraum nicht verfügbar.")
    return materials, scope_revision


def snapshots(materials):
    return [
        {
            "id": material.id,
            "revision": material.revision,
            "ref": f"p{index + 1}",
            "label": f"Seite {material.page_number or index + 1} · {material.subject} · {material.topic}",
        }
        for index, material in enumerate(materials)
    ]


def history_for(db, turn, source_revisions):
    history, seen = [], {turn.id}
    previous_id = turn.reply_to
    while previous_id and len(history) < HISTORY_SIZE:
        previous = db.get(TutorTurn, previous_id)
        if (
            not previous
            or previous.id in seen
            or previous.child_id != turn.child_id
            or previous.user_id != turn.user_id
            or scope_values(previous) != scope_values(turn)
            or bool(previous.homework_context) != bool(turn.homework_context)
            or (turn.homework_context and any((previous.homework_context or {}).get(k) != turn.homework_context.get(k)
                                               for k in ("analysis_id", "task_id")))
            or previous.status != "ready"
            or not previous.reply
        ):
            raise HTTPException(409, "Bitte beginne mit einer neuen Frage zu dieser Heftseite.")
        if previous.source_revisions != source_revisions:
            raise HTTPException(
                409, "Die Heftseiten wurden geändert. Bitte stelle deine Frage neu ohne den alten Verlauf."
            )
        history.append({
            "question": previous.question, "answer": previous.reply["answer"], "kind": previous.reply["kind"],
            **({"next_question": previous.reply["next_question"]} if previous.reply.get("next_question") else {}),
            **({"own_attempt": previous.homework_context.get("draft", ""),
                "next_step": previous.reply.get("next_step", ""), "steps": previous.reply.get("steps", []),
                **({"example": previous.reply["example"]} if previous.reply.get("example") else {})}
               if previous.homework_context else {}),
        })
        seen.add(previous.id)
        previous_id = previous.reply_to
    return list(reversed(history))


def context(db, child, turn):
    scope = TutorScope(**scope_values(turn))
    materials, scope_revision = sources_for(db, child, scope)
    revisions = snapshots(materials)
    if turn.source_revisions and turn.source_revisions != revisions:
        raise ProviderError("Die bestätigten Heftseiten wurden geändert. Bitte stelle deine Frage neu.")
    history = history_for(db, turn, revisions)
    sources = [
        {"ref": source["ref"], "label": source["label"], "subject": m.subject, "topic": m.topic, "content": m.content}
        for source, m in zip(revisions, materials, strict=True)
    ]
    payload = {"grade": child.grade, "question": turn.question, "sources": sources, "history": history}
    from .foundations import for_question

    if foundations := for_question(turn.question + " " + " ".join(h["question"] for h in history), sources):
        payload["foundations"] = foundations
    if turn.homework_context:
        from .homework import enrich_context

        payload = enrich_context(db, child, turn, payload)
    signature = digest(
        json.dumps(
            [payload, revisions, scope_values(turn), scope_revision, child.family_id, child.preferences, turn.reply_to,
             *([turn.homework_context] if turn.homework_context else [])],
            sort_keys=True,
            ensure_ascii=False,
        )
    )
    return signature, payload, revisions


def authority(db, turn, family_id):
    session = db.get(Session, turn.session_id) if turn.session_id else None
    user = db.get(User, turn.user_id)
    if (
        not session
        or session.user_id != turn.user_id
        or session.revoked
        or session.expires <= now()
        or now() - session.seen > 7 * 86400
        or not user
        or user.role != "child"
        or user.disabled
        or not user.verified
    ):
        raise HTTPException(401, "Dieser Zugang wurde abgemeldet oder widerrufen. Deine Frage bleibt gespeichert.")
    child = child_access(db, Principal(user, session), turn.child_id)
    if child.family_id != family_id:
        raise HTTPException(
            403, "Die Familienberechtigung hat sich geändert. Bitte stelle deine Frage nach Anmeldung neu."
        )
    family = db.get(Family, child.family_id)
    if family.synthetic:
        raise HTTPException(403, "Eigene Heftfragen sind im Beispielraum nicht verfügbar.")
    usage_terms(db, family, enforce=True)
    return child, family


def turn_data(db, turn):
    status, error = turn.status, turn.error
    job = db.get(Job, turn.job_id) if turn.job_id else None
    if status in ("queued", "running"):
        if not job or job.status == "failed":
            status, error = "failed", "Die Frage konnte nicht beantwortet werden. Du kannst sie erneut stellen."
        elif job.status == "running":
            status = "running"
    changed = any(
        not (material := db.get(Material, source["id"]))
        or material.child_id != turn.child_id
        or not material.confirmed
        or material.revision != source["revision"]
        for source in turn.source_revisions
    )
    return {
        "id": turn.id,
        "job_id": turn.job_id,
        "status": status,
        "question": turn.question,
        "reply_to": turn.reply_to,
        **scope_values(turn),
        "reply": turn.reply if status == "ready" else None,
        "error": error,
        "created": turn.created,
        "source_changed": changed,
        "homework": turn.homework_context,
    }


@router.post("/children/{child_id}/tutor/questions", status_code=202)
def ask(
    child_id: str,
    data: TutorQuestion,
    idempotency_key: str = Header(..., min_length=16, max_length=80, pattern=r"^[A-Za-z0-9_-]+$"),
    p=Depends(child_user),
    db=Depends(get_db),
):
    child = child_access(db, p, child_id)
    rate_limit(db, "tutor-question:" + p.user.id, 12, 60)
    # Reuse the common child lock: no second extraction/package/coach/tutor job.
    db.execute(update(Child).where(Child.id == child.id).values(grade=Child.grade))
    key = "tutor:" + digest(p.user.id + ":" + child.id + ":" + idempotency_key)
    request_data = data.model_dump()
    if data.homework is None:
        request_data.pop("homework")  # preserve legacy request hashes
    request_hash = digest(json.dumps(request_data, sort_keys=True, ensure_ascii=False))
    existing = db.scalar(select(Job).where(Job.idempotency == key))
    if existing:
        if existing.payload.get("request_hash") != request_hash:
            raise HTTPException(409, "Diese Anfrage wurde bereits mit einer anderen Frage verwendet.")
        turn = db.get(TutorTurn, existing.payload["turn_id"])
        if not turn or turn.user_id != p.user.id or turn.child_id != child.id:
            raise HTTPException(409, "Diese frühere Frage ist nicht mehr verfügbar. Bitte beginne eine neue Anfrage.")
        return turn_data(db, turn)
    if db.scalar(select(Job.id).where(Job.child_id == child.id, Job.status.in_(["queued", "running"]))):
        raise HTTPException(409, "Eine Verarbeitung läuft noch. Bitte warte kurz.")
    homework = data.homework.model_dump() if data.homework else None
    if homework:
        if not data.material_id or data.day_id or data.unit_id:
            raise HTTPException(422, "Wähle für die Hausaufgaben genau ein eigenes Foto.")
        candidates = list(db.scalars(select(TutorTurn).where(TutorTurn.child_id == child.id,
            TutorTurn.material_id == data.material_id, TutorTurn.homework_context.is_not(None))
            .order_by(TutorTurn.created.desc(), TutorTurn.id.desc()).limit(100)))
        material = db.get(Material, data.material_id)
        if not material or material.child_id != child.id or material.purpose != "homework":
            raise HTTPException(404, "Hausaufgabenfoto nicht gefunden.")
        current = [t for t in candidates if any(s["id"] == material.id and s["revision"] == material.revision
                                               for s in t.source_revisions)]
        homework["sequence"] = max((t.homework_context.get("sequence", 0) for t in candidates), default=0) + 1
        if homework["action"] == "analyze":
            analyses = [t for t in current if t.homework_context.get("action") == "analyze"]
            ready = next((t for t in analyses if t.status == "ready"), None)
            if ready:
                return turn_data(db, ready)
            if len(analyses) >= 2:
                raise HTTPException(409, "Die Aufgabenübersicht konnte zweimal nicht erstellt werden. Bitte prüfe das Foto oder nimm die Aufgabe näher auf.")
        if homework["action"] == "hint":
            hints = [t for t in current if t.status == "ready" and t.homework_context.get("action") == "hint"
                     and all(t.homework_context.get(k) == homework.get(k) for k in ("analysis_id", "task_id"))]
            if len(hints) >= 3:
                return turn_data(db, max(hints, key=lambda t: t.homework_context.get("hint_level", 0)))
            homework["hint_level"] = len(hints) + 1
    turn = TutorTurn(
        homework_context=homework,
        id=uid(),
        child_id=child.id,
        user_id=p.user.id,
        session_id=p.session.id,
        school_day_id=data.day_id,
        material_id=data.material_id,
        unit_id=data.unit_id,
        reply_to=data.reply_to,
        question=data.question,
        status="queued",
        source_revisions=[],
    )
    authority(db, turn, child.family_id)
    signature, payload, revisions = context(db, child, turn)
    from .homework import deterministic_reply

    local_check = bool(homework and deterministic_reply(payload, revisions))
    turn.source_revisions = revisions
    job = Job(
        id=uid(),
        child_id=child.id,
        kind="tutor",
        idempotency=key,
        payload={
            "turn_id": turn.id,
            "request_hash": request_hash,
            "signature": signature,
            "family_id": child.family_id,
            **({"local_check": "homework_math_v1"} if local_check else {}),
        },
    )
    db.add(job)
    db.flush()
    turn.job_id = job.id
    db.add(turn)
    if not local_check:
        reserve(db, db.get(Family, child.family_id), child.id, job.id, "tutor")
    record(db, child.id, "tutor_question", {"turn_id": turn.id}, unit_id=data.unit_id)
    db.commit()
    return turn_data(db, turn)


@router.get("/children/{child_id}/tutor/questions")
def questions(
    child_id: str,
    day_id: str | None = Query(None, min_length=1, max_length=32),
    material_id: str | None = Query(None, min_length=1, max_length=32),
    unit_id: str | None = Query(None, min_length=1, max_length=32),
    cursor: str | None = Query(None, min_length=1, max_length=32),
    p=Depends(authenticated),
    db=Depends(get_db),
):
    child = child_access(db, p, child_id)
    try:
        scope = TutorScope(day_id=day_id, material_id=material_id, unit_id=unit_id)
    except ValidationError:
        raise HTTPException(422, "Bitte genau einen Schultag, eine Heftseite oder eine Lerneinheit wählen.") from None
    # A history remains readable if a source was corrected or is unconfirmed.
    # Check scope ownership separately from its current eligibility for new AI.
    model, scope_id = (
        (SchoolDay, scope.day_id)
        if scope.day_id
        else (Material, scope.material_id)
        if scope.material_id
        else (LearningUnit, scope.unit_id)
    )
    owner = db.get(model, scope_id)
    if not owner or owner.child_id != child.id:
        raise HTTPException(404, "Heftbereich nicht gefunden.")
    query = select(TutorTurn).where(TutorTurn.child_id == child.id, *scope_filter(scope))
    if p.user.role == "child":
        query = query.where(TutorTurn.user_id == p.user.id)
    if cursor:
        previous = db.get(TutorTurn, cursor)
        if (
            not previous
            or previous.child_id != child.id
            or scope_values(previous) != scope.model_dump()
            or (p.user.role == "child" and previous.user_id != p.user.id)
        ):
            raise HTTPException(404, "Frage nicht gefunden.")
        query = query.where(
            or_(
                TutorTurn.created < previous.created,
                (TutorTurn.created == previous.created) & (TutorTurn.id < previous.id),
            )
        )
    rows = list(db.scalars(query.order_by(TutorTurn.created.desc(), TutorTurn.id.desc()).limit(PAGE_SIZE + 1)))
    return {
        "questions": [turn_data(db, turn) for turn in reversed(rows[:PAGE_SIZE])],
        "next_cursor": rows[PAGE_SIZE - 1].id if len(rows) > PAGE_SIZE else None,
    }


def normalized_quote(value):
    return " ".join(unicodedata.normalize("NFC", value).split())


def checked_reply(data, payload, revisions):
    if payload.get("homework"):
        from .homework import checked_reply as check_homework

        return check_homework(data, payload, revisions)
    try:
        reply = TutorOutput.model_validate(data).model_dump()
    except ValidationError:
        raise ProviderError("Die Antwort konnte nicht sicher geprüft werden. Bitte stelle die Frage erneut.") from None
    by_ref = {source["ref"]: source for source in [*payload["sources"], *payload.get("foundations", [])]}
    metadata = {source["ref"]: source for source in revisions}
    seen = set()
    for citation in reply["sources"]:
        source = by_ref.get(citation["ref"])
        quote = normalized_quote(citation["quote"])
        if not source or quote not in normalized_quote(source["content"]) or (citation["ref"], quote) in seen:
            raise ProviderError("Die Antwort enthält keinen passenden wörtlichen Quellenbeleg. Bitte frage erneut.")
        seen.add((citation["ref"], quote))
        if citation["ref"].startswith("k"):
            citation.update(label=source["label"], foundation_id=source["id"], version=source["version"],
                            reference_title=source["reference_title"], reference_url=source["reference_url"],
                            origin="reviewed_supplement")
            reply["kind"] = "foundation"
        else:
            citation.update(label=metadata[citation["ref"]]["label"], material_id=metadata[citation["ref"]]["id"])
    if reply["kind"] == "foundation" and not any(c.get("origin") == "reviewed_supplement" for c in reply["sources"]):
        raise ProviderError("Die ergänzende Erklärung hat keinen geprüften Grundwissen-Beleg.")
    return reply


def record_tutor_help(db, turn, units, revisions):
    """Count source-backed help for overlapping active or paused practice."""
    source_revisions = {source["id"]: source["revision"] for source in revisions}
    unit_sources = {}
    for source in db.scalars(select(UnitSource).where(UnitSource.unit_id.in_([unit.id for unit in units]))):
        unit_sources.setdefault(source.unit_id, []).append(source)
    for unit in units:
        sources = unit_sources.get(unit.id, [])
        shared_source = any(source_revisions.get(source.material_id) == source.revision for source in sources)
        # Legacy units have only their direct material reference. When explicit
        # UnitSource rows exist, their stored revisions remain authoritative.
        if not sources:
            shared_source = unit.material_id in source_revisions
        if unit.id == turn.unit_id or shared_source:
            record(db, turn.child_id, "explanation", {"via": "tutor", "turn_id": turn.id}, unit_id=unit.id)


def process(job_id):
    result = None
    try:
        with DB() as db:
            job = db.get(Job, job_id)
            if not job or job.kind != "tutor" or job.status != "running":
                return
            turn = db.get(TutorTurn, job.payload["turn_id"])
            if not turn or turn.job_id != job.id or turn.child_id != job.child_id:
                raise ProviderError("Die Frage oder ihr Heftmaterial ist nicht mehr verfügbar.")
            child, _ = authority(db, turn, job.payload["family_id"])
            signature, payload, revisions = context(db, child, turn)
            if signature != job.payload["signature"]:
                raise ProviderError("Die Frage, Heftseiten oder Lernvorgaben wurden geändert. Bitte frage erneut.")
            local = job.payload.get("local_check")
            from .homework import deterministic_reply

            local_reply = deterministic_reply(payload, revisions) if local == "homework_math_v1" else None
            if local and not local_reply:
                raise ProviderError("Die gespeicherte Rechenprüfung passt nicht mehr zur Aufgabe.")
            config = job_config(db, job, "tutor") if not local else None
            usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
            if not local and (not usage or (usage.provider, usage.model, usage.config_revision) != (
                config.provider,
                config.model,
                config.revision,
            )):
                raise ProviderError("Die KI-Einstellung wurde geändert. Kein anderer Anbieter wurde aufgerufen.")
            if not local:
                external_allowed(config)
            turn.status = "running"
            from .catalog_ai import with_catalog_context

            if not turn.homework_context:
                payload = with_catalog_context(db, child, payload)
            values = {c.name: getattr(config, c.name) for c in ProviderConfig.__table__.columns} if config else None
            db.commit()
        if local:
            result, reply = Result({}, 0, 0, 0), local_reply
        else:
            result = request_provider(ProviderConfig(**values), "tutor", payload)
            reply = checked_reply(result.data, payload, revisions)
        with DB.begin() as db:
            job = db.get(Job, job_id)
            if not job or job.status != "running":
                return
            # Answers lock their unit before updating the child's mastery.
            # Keep that lock order and wait for any simultaneous completion:
            # completed units must never gain a retrospective help marker.
            ongoing_units = (
                list(
                    db.scalars(
                        select(LearningUnit)
                        .where(
                            LearningUnit.child_id == job.child_id,
                            LearningUnit.status.in_(["active", "paused"]),
                            LearningUnit.completed.is_(None),
                            LearningUnit.synthetic.is_(False),
                        )
                        .order_by(LearningUnit.id)
                        .with_for_update()
                    )
                )
                if reply["kind"] in ("answer", "foundation")
                else []
            )
            db.execute(update(Child).where(Child.id == job.child_id).values(grade=Child.grade))
            turn = db.get(TutorTurn, job.payload["turn_id"])
            if not turn or turn.job_id != job.id or turn.child_id != job.child_id:
                raise ProviderError("Die Frage oder ihr Heftmaterial ist nicht mehr verfügbar.")
            child, _ = authority(db, turn, job.payload["family_id"])
            if context(db, child, turn)[0] != job.payload["signature"]:
                raise ProviderError("Die Frage, Heftseiten oder Lernvorgaben wurden geändert. Bitte frage erneut.")
            config = job_config(db, job, "tutor") if not local else None
            usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
            if not local and (not usage or (usage.provider, usage.model, usage.config_revision) != (
                config.provider,
                config.model,
                config.revision,
            )):
                raise ProviderError("Die KI-Einstellung wurde während der Antwort geändert. Bitte frage erneut.")
            if not local:
                external_allowed(config)
            if reply["kind"] in ("answer", "foundation"):
                record_tutor_help(db, turn, ongoing_units, revisions)
            turn.status, turn.reply, turn.error = "ready", reply, None
            if result.catalog_assignment:
                from .catalog_ai import remember

                remember(db, "tutor", turn, result.catalog_assignment)
            job.status, job.finished, job.result = "completed", int(now()), {"question_id": turn.id}
            if usage:
                settle(db, usage, result)
            record(db, child.id, "tutor_answer", {"turn_id": turn.id}, unit_id=turn.unit_id)
    except Exception as error:
        reason = (
            str(error.detail)
            if isinstance(error, HTTPException)
            else str(error)
            if isinstance(error, ProviderError)
            else "Die Frage konnte gerade nicht beantwortet werden. Dein bisheriger Lernstand bleibt erhalten."
        )
        with DB.begin() as db:
            job = db.get(Job, job_id)
            if not job or job.status != "running":
                return
            job.status, job.finished, job.error = "failed", int(now()), reason[:500]
            from .job_failures import failure_code

            job.error_code = failure_code(error)
            if getattr(error, "validation_reason", None):
                job.result = {"validation_reason": error.validation_reason}
            turn = db.get(TutorTurn, job.payload.get("turn_id"))
            if turn and turn.job_id == job.id:
                turn.status, turn.error, turn.reply = "failed", reason[:500], None
            usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
            if usage:
                settle(db, usage, result or getattr(error, "billing_result", None), failed=True)


def purge_source_turns(db, material_ids, *, child_id=None):
    """Delete source quotes even when their turn was opened for a day or unit.

    Call before deleting materials; the normal erasure journal remains owned by
    the material/account deletion workflow. Job payloads contain no private text.
    """
    material_ids = set(material_ids)
    if child_id:
        from .vocabulary import purge_sources

        purge_sources(db, material_ids, child_id)
    query = select(TutorTurn.id, TutorTurn.source_revisions)
    if child_id:
        query = query.where(TutorTurn.child_id == child_id)
    ids = [turn_id for turn_id, sources in db.execute(query) if any(s["id"] in material_ids for s in sources)]
    if not ids:
        return 0
    for job in db.scalars(select(Job).where(Job.kind == "tutor", Job.status == "queued")):
        if job.payload.get("turn_id") in ids:
            cancelled = db.execute(
                update(Job)
                .where(Job.id == job.id, Job.status == "queued")
                .values(status="failed", finished=int(now()), error="Die Heftquelle wurde gelöscht.")
            )
            if cancelled.rowcount:
                # A racing worker may already have claimed the job. Only a
                # successful queued->failed CAS proves that no request ran.
                usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
                if usage:
                    settle(db, usage, Result({}, 0, 0, 0), failed=True)
    db.execute(delete(TutorTurn).where(TutorTurn.id.in_(ids)))
    return len(ids)
