"""Explicit finite graphical sidecars; never replace a begun round or answer."""
from fastapi import APIRouter, Depends, Header, HTTPException
from sqlalchemy import select, update

from .db import DB, Child, Family, Job, LearningUnit, Session, Usage, User, get_db, now
from .security import Principal, authenticated, child_access, rate_limit
from .visual_reference_models import UnitVisualSnapshot
from .visual_reference_schemas import VisualExplanationOutput
from .visual_references import _hydrate, digest, guard_context, source_binding, validate_output, with_visual_context

router = APIRouter(tags=["Grafische Erklärungen"])


def context(db, unit):
    from .learning_controller import source_state

    signature, valid, sources = source_state(db, unit)
    if not valid or not sources:
        raise HTTPException(409, "Prüfe zuerst die aktuellen Heftquellen. Die gespeicherte Runde bleibt erhalten.")
    if not 1 <= len(unit.questions) <= 8:
        raise HTTPException(409, "Für diese lange Runde bitte einen kleineren Erklärabschnitt wählen.")
    child = db.get(Child, unit.child_id)
    try:
        payload = with_visual_context(db, child, {"material": {"subject": unit.subject, "topic": unit.topic,
            "content": ""}, "required_subject": unit.subject, "required_topic": unit.topic, "visual_only": True}, sources)
    except ValueError as error:
        raise HTTPException(409, str(error)) from error
    if not payload["visual_context"]["required"]:
        raise HTTPException(409, "Für diese Quelle fehlt noch eine passende belegte Darstellung. Es wurde kein KI-Auftrag gestartet.")
    if sum(len(row["content"]) for row in payload["visual_context"]["sources"]) > 18000:
        raise HTTPException(409, "Wähle für die Grafikerklärung einen kleineren Quellenumfang.")
    # All of these texts are already saved, not instructions or new source facts.
    payload["saved_explanation"] = unit.explanation
    payload["saved_questions"] = [{key: question[key] for key in ("id", "type", "prompt", "options", "explanation") if key in question}
                                  for question in unit.questions]
    stamp = digest([unit.id, unit.subject, unit.topic, unit.explanation, unit.questions, signature,
                    [[row["material_id"], row["revision"], row["content"]] for row in payload["visual_context"]["sources"]]])
    return stamp, payload


def bind_schema(schema, payload):
    schema["properties"]["subject"]["enum"] = [payload["required_subject"]]
    schema["properties"]["topic"]["enum"] = [payload["required_topic"]]
    ids = [row["id"] for row in payload["saved_questions"]]
    schema["properties"]["questions"].update(minItems=len(ids), maxItems=len(ids))
    schema["$defs"]["VisualQuestionSteps"]["properties"]["id"]["enum"] = ids


def checked_output(db, data, payload):
    value = VisualExplanationOutput.model_validate(data).model_dump()
    saved = {row["id"]: row for row in payload["saved_questions"]}
    if (value["subject"], value["topic"]) != (payload["required_subject"], payload["required_topic"]):
        raise ValueError("Die Grafikerklärung gehört zu einem anderen Thema.")
    if len(value["questions"]) != len(saved) or {row["id"] for row in value["questions"]} != set(saved):
        raise ValueError("Die Grafikerklärung verändert die gespeicherte Fragenauswahl.")
    combined = {**value, "questions": [{**saved[row["id"]], **row} for row in value["questions"]]}
    validate_output(db, combined, payload)
    return value


def authority(db, job):
    session = db.get(Session, job.payload["session_id"])
    user = db.get(User, session.user_id) if session else None
    if (not session or session.revoked or session.expires <= now() or session.seen < now() - 7 * 86400
            or not user or user.disabled or not user.verified or user.id != job.payload["user_id"]):
        raise HTTPException(401, "Die Anmeldung wurde beendet.")
    principal = Principal(user, session)
    child = child_access(db, principal, job.child_id, write=user.role == "parent")
    if child.family_id != job.payload["family_id"]:
        raise HTTPException(409, "Die Familienzuordnung wurde geändert.")
    from .commerce import usage_terms

    usage_terms(db, db.get(Family, child.family_id), enforce=True)
    return child


@router.post("/units/{unit_id}/visual-explanation", status_code=202)
def prepare(unit_id: str, key: str = Header(default="", alias="Idempotency-Key"),
            p=Depends(authenticated), db=Depends(get_db)):
    from .learning import get_unit
    from .providers import reserve

    if not 16 <= len(key) <= 80 or not key.isascii():
        raise HTTPException(422, "Bitte einen eindeutigen Anfrageschlüssel verwenden.")
    unit = get_unit(db, p, unit_id, lock=True)
    child = child_access(db, p, unit.child_id, write=p.user.role == "parent")
    if unit.synthetic:
        raise HTTPException(409, "Für die vorbereitete Demo wird keine zusätzliche KI gestartet.")
    db.execute(update(Child).where(Child.id == child.id).values(grade=Child.grade))
    child_access(db, p, child.id, write=p.user.role == "parent")
    signature, _ = context(db, unit)
    values = {"unit_id": unit.id, "signature": signature, "session_id": p.session.id,
              "user_id": p.user.id, "family_id": child.family_id}
    previous = db.scalar(select(Job).where(Job.idempotency == p.user.id + ":" + key))
    if previous:
        if previous.kind != "unit_visuals" or previous.child_id != child.id or previous.payload != values:
            raise HTTPException(409, "Dieser Schlüssel gehört zu einer anderen Erklärung.")
        return {"id": previous.id, "status": previous.status}
    old = list(db.scalars(select(Job).where(Job.child_id == child.id, Job.kind == "unit_visuals",
        Job.payload["unit_id"].as_string() == unit.id, Job.payload["signature"].as_string() == signature)))
    if any(row.status in ("queued", "running", "completed") for row in old) or len(old) >= 2:
        raise HTTPException(409, "Die vorhandene Grafikvorbereitung bleibt gespeichert. Lade ihren Stand, statt sie erneut zu starten.")
    if db.scalar(select(Job.id).where(Job.child_id == child.id, Job.status.in_(["queued", "running"]))):
        raise HTTPException(409, "Für dieses Kind wird bereits ein Auftrag verarbeitet.")
    rate_limit(db, "job:" + p.user.id, 30, 60, commit=False)
    job = Job(child_id=child.id, kind="unit_visuals", payload=values, idempotency=p.user.id + ":" + key)
    db.add(job)
    db.flush()
    # Reuse the ordinary selected unit route, budgets and reservation exactly.
    reserve(db, db.get(Family, child.family_id), child.id, job.id, "unit")
    db.commit()
    return {"id": job.id, "status": job.status}


def process(job_id):
    from .model_routing import job_config
    from .providers import ProviderError, external_allowed, request_provider, settle

    result = None
    provider_requested = False
    try:
        with DB() as db:
            job = db.get(Job, job_id)
            if not job or job.status != "running":
                return
            authority(db, job)
            unit = db.get(LearningUnit, job.payload["unit_id"])
            if not unit or unit.child_id != job.child_id:
                raise ProviderError("Die gespeicherte Runde fehlt.")
            signature, payload = context(db, unit)
            if signature != job.payload["signature"]:
                raise ProviderError("Die Quellen oder Aufgaben wurden geändert.")
            config = job_config(db, job, "unit")
            external_allowed(config)
            config_values = {column.name: getattr(config, column.name) for column in config.__table__.columns}
        provider_requested = True
        result = request_provider(type(config)(**config_values), "unit_visuals", payload)
        with DB.begin() as db:
            job = db.get(Job, job_id)
            if not job or job.status != "running":
                return
            unit = db.scalar(select(LearningUnit).where(LearningUnit.id == job.payload["unit_id"]).with_for_update())
            child = authority(db, job)
            db.execute(update(Child).where(Child.id == child.id).values(grade=Child.grade))
            db.expire_all()
            authority(db, job)
            if unit is None or unit.child_id != job.child_id or context(db, unit)[0] != job.payload["signature"]:
                raise ProviderError("Die Runde wurde während der Grafikvorbereitung geändert.")
            current = job_config(db, job, "unit")
            external_allowed(current)
            if (current.revision, current.model) != (config_values["revision"], config_values["model"]):
                raise ProviderError("Die KI-Einstellung wurde geändert.")
            guard_context(db, unit.child_id, payload["visual_context"])
            value = checked_output(db, result.data, payload)
            old = db.get(UnitVisualSnapshot, unit.id)
            if old is not None:
                db.delete(old)
                db.flush()
            steps = _hydrate(value["explanation_steps"], payload["visual_context"])
            db.add(UnitVisualSnapshot(unit_id=unit.id, source_signature=job.payload["signature"], status="ready", reason=None,
                steps=steps, question_steps={row["id"]: _hydrate(row["explanation_steps"], payload["visual_context"]) for row in value["questions"]},
                receipts=[{"reference": row["reference"], "source_refs": row["source_refs"]} for row in steps],
                source_bindings=[source_binding(ref) for ref in payload["visual_context"]["sources"]], notice=""))
            settle(db, db.scalar(select(Usage).where(Usage.job_id == job.id)), result)
            job.status, job.finished, job.result = "completed", int(now()), {"unit_id": unit.id, "visual_status": "ready"}
    except Exception as error:
        with DB.begin() as db:
            job = db.get(Job, job_id)
            if not job or job.status != "running":
                return
            from .job_failures import failure_code

            job.status, job.finished, job.error_code = "failed", int(now()), failure_code(error)
            job.error = str(error)[:450] if isinstance(error, ProviderError) else "Die Grafik konnte nicht sicher vorbereitet werden. Gespeicherte Aufgaben und Antworten bleiben erhalten."
            billed = result or getattr(error, "billing_result", None)
            if billed is None and not provider_requested:
                from .providers import Result

                billed = Result({}, 0, 0, 0, cost_source="cancelled")
            settle(db, db.scalar(select(Usage).where(Usage.job_id == job.id)), billed, failed=True)
