"""Two new source-bound questions after support, on one deliberate action."""

import copy

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select, update

from . import schemas as s
from .coaching import context, root_and_units, support_check_context, validate_new_round
from .db import DB, Child, Family, Job, LearningMemory, LearningUnit, Session, UnitSource, Usage, User, get_db, now
from .learning import get_unit, record
from .learning_controller import ChooseAction, observe
from .model_routing import job_config
from .providers import ProviderError, external_allowed, request_provider, settle
from .security import Principal, child_access, child_user

router = APIRouter(tags=["Lernbegleitung"])


def authority(db, job):
    session = db.get(Session, job.payload["session_id"])
    user = db.get(User, session.user_id) if session else None
    if not session or session.revoked or session.expires <= now() or session.seen < now() - 7 * 86400 or not user or user.role != "child":
        raise ProviderError("Die Anmeldung wurde beendet. Der Auftrag wird nicht übernommen.")
    p = Principal(user, session)
    child = child_access(db, p, job.child_id)
    if child.family_id != job.payload["family_id"]:
        raise ProviderError("Die Familienzuordnung wurde geändert.")
    from .commerce import usage_terms

    usage_terms(db, db.get(Family, child.family_id), enforce=True)
    return child


@router.post("/units/{unit_id}/learning-session/check", status_code=202)
def prepare(unit_id: str, data: ChooseAction, p=Depends(child_user), db=Depends(get_db)):
    from .db import Activity
    from .learning import pending_feedback
    from .learning_controller import facts
    from .materials import enqueue

    unit = get_unit(db, p, unit_id, True, True)
    if unit.synthetic:
        raise HTTPException(409, "Für eine neue Lernprobe brauchst du eigene bestätigte Heftseiten. Die Beispielrunde bleibt gespeichert.")
    memory = db.get(LearningMemory, unit.id)
    media = (memory.working or {}).get("media") if memory else None
    media_valid = media and media.get("status") in ("watched", "not_helpful", "broken", "skipped") and media.get("user_id") == p.user.id
    support = db.scalar(select(Activity).where(Activity.unit_id == unit.id, Activity.kind == "explanation")
        .order_by(Activity.created.desc(), Activity.id.desc()))
    if not media_valid and not support:
        raise HTTPException(409, "Öffne zuerst eine Erklärung oder kehre von deinem Lerntipp zurück. Deine Runde bleibt verfügbar.")
    key = "media-check:" + media.get("open_id", media["interaction_id"]) if media_valid else "help-check:" + unit.id
    previous = db.scalar(select(Job).where(Job.idempotency == p.user.id + ":" + key))
    if previous:
        return {"id": previous.id, "status": previous.status}
    if memory.revision != data.revision:
        raise HTTPException(409, "Der Lernschritt hat sich geändert. Bitte neu laden.")
    state = facts(db, unit)
    if pending_feedback(unit, state["attempts"], state["activities"]):
        raise HTTPException(409, "Lies zuerst deine gespeicherte Rückmeldung.")
    if data.kind != "check_understanding":
        raise HTTPException(422, "Hier wird eine neue kleine Verständnisrunde vorbereitet.")
    try:
        signature, payload, _ = support_check_context(db, unit)
    except ProviderError as error:
        raise HTTPException(409, str(error)) from None
    goals = payload["learning_goals"]
    question_id = media.get("question_id") if media_valid else support.detail.get("question_id")
    question = next((q for q in unit.questions if q["id"] == question_id), None)
    target = question.get("learning_goal_id") if question else None
    focus = [target] if target in {g["id"] for g in goals} else [g["id"] for g in goals[:2]]
    child = db.get(Child, unit.child_id)
    if unit.status == "active":
        unit.status, unit.heartbeat = "paused", None
    evidence = "tip_interaction:" + media["interaction_id"] if media_valid else "activity:" + support.id
    observe(db, unit, "support_check_requested", "check-request:" + data.request_key, [evidence])
    result = enqueue(db, p, child, "controller_check", {"unit_id": unit.id, "signature": signature,
        "focus_goal_ids": focus, "session_id": p.session.id, "family_id": child.family_id,
        "media_id": media["interaction_id"] if media_valid else None, "support_ref": evidence}, key, commit=False)
    memory.working = {**memory.working, "pending_check_job_id": result["id"]}
    db.commit()
    return result


def process(job_id):
    from .learning_sources import failure_billing

    result = None
    provider_requested = False
    try:
        with DB() as db:
            job = db.get(Job, job_id)
            if not job or job.status != "running":
                return
            authority(db, job)
            unit = db.get(LearningUnit, job.payload["unit_id"])
            if not unit or unit.child_id != job.child_id or unit.synthetic:
                raise ProviderError("Die ursprüngliche Lernrunde fehlt.")
            signature, payload, sources = context(db, unit)
            if signature != job.payload["signature"]:
                raise ProviderError("Die Quellen oder Antworten wurden geändert.")
            config = job_config(db, job, "unit")
            usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
            if not usage or (usage.provider, usage.model, usage.config_revision) != (
                config.provider, config.model, config.revision
            ):
                raise ProviderError("Die KI-Einstellung wurde seit Auftragserstellung geändert. Bitte den aktuellen Lernschritt öffnen.")
            external_allowed(config)
            values = {c.name: getattr(config, c.name) for c in config.__table__.columns}
            payload.update(review=True, practice_kind="check", focus_goal_ids=job.payload["focus_goal_ids"],
                material={"subject": unit.subject, "topic": unit.topic,
                    "content": "\n\n".join(m["content"] for m in payload["materials"])})
            payload.pop("completed_questions", None)
            # Only catalog titles are available; do not ask about unseen video details.
            payload["support_context"] = "Neue Aufgaben prüfen das bestätigte Lernziel, nicht den Inhalt eines externen Videos."
            from .catalog_ai import with_catalog_context

            payload = with_catalog_context(db, db.get(Child, job.child_id), payload)
            from .db import Material
            from .visual_references import with_visual_context

            payload = with_visual_context(db, db.get(Child, job.child_id), payload,
                                          [db.get(Material, source["id"]) for source in sources])
        provider_requested = True
        result = request_provider(type(config)(**values), "unit", payload)
        with DB.begin() as db:
            job = db.get(Job, job_id)
            if not job or job.status != "running":
                return
            unit = db.scalar(select(LearningUnit).where(LearningUnit.id == job.payload["unit_id"]).with_for_update())
            child = authority(db, job)
            db.execute(update(Child).where(Child.id == child.id).values(grade=Child.grade))
            db.expire_all()
            child = authority(db, job)
            current = job_config(db, job, "unit")
            external_allowed(current)
            if (current.revision, current.model) != (values["revision"], values["model"]) or context(db, unit)[0] != job.payload["signature"]:
                raise ProviderError("Der Lernplan wurde während der Vorbereitung geändert.")
            data = s.PracticeUnitOutput.model_validate(result.data).model_dump()
            if {q["learning_goal_id"] for q in data["questions"]} != set(job.payload["focus_goal_ids"]):
                raise ProviderError("Die Lernprobe verwendet nicht die zuvor ausgewählten Lernziele.")
            validate_new_round(db, unit, data, desired_ids=set(job.payload["focus_goal_ids"]))
            root, _ = root_and_units(db, unit)
            followup = LearningUnit(child_id=child.id, subject=unit.subject, subject_id=unit.subject_id,
                topic=unit.topic, explanation=data["explanation"], questions=copy.deepcopy(data["questions"]),
                material_id=unit.material_id, assignment_id=unit.assignment_id, goal_revision=unit.goal_revision,
                school_day_id=unit.school_day_id, learning_root_id=root.id, followup_of=unit.id,
                round_kind="check", introduction_seen=True, estimated_minutes=4,
                provider=values["provider"], model=values["model"], synthetic=False)
            db.add(followup)
            db.flush()
            from .visual_references import remember as remember_visuals

            remember_visuals(db, followup, result.data, payload)
            for source in sources:
                db.add(UnitSource(unit_id=followup.id, material_id=source["id"], revision=source["revision"]))
            record(db, child.id, "unit_created", {"via": "media_return", "previous_unit_id": unit.id}, followup.id)
            memory = db.get(LearningMemory, unit.id)
            memory.working = {**memory.working, "prepared_check_unit_id": followup.id, "media_return": None}
            observe(db, unit, "support_check_ready", "check-ready:" + job.id, ["unit:" + followup.id])
            if result.catalog_assignment:
                from .catalog_ai import remember

                remember(db, "unit", followup, result.catalog_assignment)
            settle(db, db.scalar(select(Usage).where(Usage.job_id == job.id)), result)
            job.status, job.finished, job.result = "completed", int(now()), {"unit_id": followup.id}
    except Exception as error:
        with DB.begin() as db:
            job = db.get(Job, job_id)
            if not job or job.status != "running":
                return
            from .job_failures import failure_code

            job.status, job.finished, job.error_code = "failed", int(now()), failure_code(error)
            job.error = (str(error.detail) if isinstance(error, HTTPException) else str(error) if isinstance(error, ProviderError)
                else "Die neue Runde konnte nicht vorbereitet werden. Deine gespeicherten Übungen bleiben nutzbar.")[:500]
            usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
            if usage:
                settle(db, usage, failure_billing(result, error, provider_requested=provider_requested), failed=True)
