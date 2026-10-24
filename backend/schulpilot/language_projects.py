"""Bounded language workshops, one explicit action / reservation / worker call."""

import re

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select

from . import language_tasks as s
from .db import (
    DB,
    Audit,
    Child,
    Family,
    Job,
    LanguageProject,
    LearningUnit,
    Material,
    ProviderConfig,
    UnitSource,
    Usage,
    VocabularyItem,
    get_db,
    now,
    uid,
)
from .learning import record
from .model_routing import job_config
from .providers import ProviderError, external_allowed, request_provider, reserve, settle
from .security import authenticated, child_access, child_user, rate_limit
from .vocabulary import KEY, authority, current_sources, fingerprint, literal_present, lock_child, normalized

router = APIRouter(tags=["Quellgebundene Sprachwerkstatt"])
OWN_WORK = {"writing_feedback", "model_text", "translation", "email"}
REQUEUE_ACTIONS = ("language_project.repair", "language_project.retry")
GRAMMAR_MARKERS = {"simple_present": ("simple present", "he, she, it", "third person", "dritte person"),
                   "simple_past": ("simple past", "past tense", "vergangenheit"),
                   "progressive": ("progressive", "present continuous", "verlaufsform")}


def project_data(db, row, *, child_view=True):
    job = db.get(Job, row.job_id) if row.job_id else None
    status, error = row.status, row.error
    if status in ("queued", "running") and (not job or job.status == "failed"):
        status, error = "failed", job.error if job else "Dieser Auftrag ist nicht mehr verfügbar. Bitte neu vorbereiten."
    result = row.result if status == "ready" else None
    unit = db.get(LearningUnit, row.unit_id) if row.unit_id else None
    following = db.scalar(select(LanguageProject.id).where(LanguageProject.previous_id == row.id, LanguageProject.child_id == row.child_id).order_by(LanguageProject.created, LanguageProject.id))
    if row.mode == "exam" and child_view and (not unit or unit.status != "completed"):
        result = {"title": result["title"], "response": "Die Auswertung und Lernhinweise siehst du nach deinem Versuch.",
                  "response_locale": "de-DE"} if result else None
    return {"id": row.id, "mode": row.mode, "target_locale": row.target_locale, "status": status, "error": error,
            "result": result, "unit_id": row.unit_id, "job_id": row.job_id, "step": row.step,
            "goal": row.inputs["goal"], "draft": row.inputs["draft"], "source_revisions": row.source_revisions,
            "previous_id": row.previous_id, "next_id": following, "created": row.created,
            "item_ids": row.inputs["item_ids"], "material_id": row.inputs.get("material_id"),
            "can_continue": row.mode == "dialog" and row.step < 4 and row.status == "ready" and not following,
            "can_retry": bool(child_view and status == "failed" and job and job.status == "failed" and not row.unit_id and not row.result
                              and not db.scalar(select(Audit.id).where(Audit.action.in_(REQUEUE_ACTIONS), Audit.target == row.id)))}


def context(db, row):
    current_sources(db, row.child_id, row.source_revisions)
    words = []
    for snapshot in row.item_revisions:
        item = db.get(VocabularyItem, snapshot["id"])
        if not item or item.child_id != row.child_id or not item.confirmed or item.revision != snapshot["revision"]:
            raise HTTPException(409, "Ausgewählte Wörter wurden korrigiert. Bitte den Auftrag neu vorbereiten.")
        current_sources(db, row.child_id, item.source_revisions)
        if item.origin == "material":
            from .learning_sources import current_values, exact_quote

            texts = [value["content"] for value in current_values(db, row.child_id, item.source_revisions)]
            if any(value and not exact_quote(value, texts) for value in (item.word, item.meaning, item.context)):
                raise HTTPException(409, "Ein ausgewähltes Wort beruht auf einer inzwischen ungeklärten Quellenstelle. Bitte das Wort ausdrücklich neu prüfen und bestätigen.")
        words.append({"id": item.id, "word": item.word, "meaning": item.meaning, "context": item.context,
                      "variants": item.variants, "target_locale": item.target_locale})
    from .learning_sources import current_values, policy

    safe = current_values(db, row.child_id, row.source_revisions)
    materials = [{"content": value["content"], "ref": f"p{index + 1}", "source_policy": policy(value)}
                 for index, value in enumerate(safe) if value["content"].strip()]
    previous = db.get(LanguageProject, row.previous_id) if row.previous_id else None
    if previous and previous.result and any(value["exclusions"] for value in safe):
        from .learning_sources import exact_quote

        current_texts = [value["content"] for value in safe] + [f"{word['word']} = {word['meaning']}" for word in words]
        if not exact_quote(previous.result.get("source_excerpt", ""), current_texts):
            raise HTTPException(409, "Der gespeicherte Gesprächsschritt zitiert eine inzwischen ungeklärte Quellenstelle. Bitte ein neues Gespräch beginnen; der frühere Text bleibt lesbar.")
    return {"grade": db.get(Child, row.child_id).grade, "mode": row.mode, "target_locale": row.target_locale,
            "words": words, "materials": materials, "goal": row.inputs["goal"], "draft": row.inputs["draft"],
            "grammar_topic": row.inputs["grammar_topic"], "step": row.step, "last_step": row.step >= 4,
            "previous_response": previous.result["response"] if previous and previous.result else None}


@router.post("/children/{child_id}/language-projects", status_code=202)
def create(child_id: str, data: s.ProjectRequest, idempotency_key: str = KEY,
           p=Depends(child_user), db=Depends(get_db)):
    child = child_access(db, p, child_id)
    lock_child(db, child)
    body = data.model_dump()
    value = fingerprint(body)
    old = db.scalar(select(LanguageProject).where(LanguageProject.child_id == child.id, LanguageProject.request_key == idempotency_key))
    if old:
        if old.request_digest != value:
            raise HTTPException(409, "Dieser Auftragsschlüssel gehört zu einem anderen Sprachprojekt.")
        return project_data(db, old)
    if data.target_locale not in s.TARGETS or len(set(data.item_ids)) != len(data.item_ids):
        raise HTTPException(422, "Bitte eine Lernsprache und unterschiedliche bestätigte Wörter wählen.")
    if data.mode in OWN_WORK and len(data.draft.strip()) < 10:
        raise HTTPException(422, "Schreibe zuerst deinen eigenen Versuch. Danach erhältst du Unterstützung.")
    rate_limit(db, "language-project:" + p.user.id, 12, 3600, commit=False)
    if db.scalar(select(Job.id).where(Job.child_id == child.id, Job.status.in_(["queued", "running"]))):
        raise HTTPException(409, "Eine Verarbeitung läuft noch. Bitte kurz warten.")
    items = [db.get(VocabularyItem, item_id) for item_id in data.item_ids]
    if any(not item or item.child_id != child.id or item.target_locale != data.target_locale or not item.confirmed for item in items):
        raise HTTPException(404, "Bestätigter Wortschatz nicht gefunden. Bitte eine passende Auswahl treffen.")
    sources = {source["id"]: source["revision"] for item in items for source in item.source_revisions}
    if data.material_id:
        material = db.get(Material, data.material_id)
        if not material or material.child_id != child.id:
            raise HTTPException(404, "Heftseite nicht gefunden.")
        sources[material.id] = material.revision
    source_revisions = [{"id": material_id, "revision": revision} for material_id, revision in sorted(sources.items())]
    current_sources(db, child.id, source_revisions)
    from .learning_sources import current_values

    content = "\n".join(value["content"] for value in current_values(db, child.id, source_revisions))
    if len(content) > 36000:
        raise HTTPException(422, "Bitte eine kleinere Auswahl bestätigter Heftseiten wählen.")
    if data.mode == "grammar":
        if not data.target_locale.startswith("en-") or not data.grammar_confirmed or not data.grammar_topic:
            raise HTTPException(422, "Grammatik zunächst nur für ausdrücklich bestätigten Englischstoff auswählen.")
        if not any(marker in content.casefold() for marker in GRAMMAR_MARKERS[data.grammar_topic]):
            raise HTTPException(422, "Dieses Grammatikthema ist in der ausgewählten Heftseite nicht belegt. Bitte die passende Unterrichtsseite wählen.")
    previous = db.get(LanguageProject, data.previous_id) if data.previous_id else None
    if data.previous_id and (not previous or previous.child_id != child.id or previous.mode != "dialog" or data.mode != "dialog"
                            or previous.status != "ready" or previous.step >= 4 or previous.target_locale != data.target_locale
                            or previous.source_revisions != source_revisions or previous.inputs["item_ids"] != data.item_ids
                            or previous.inputs["goal"] != data.goal):
        raise HTTPException(409, "Dieses Gespräch ist beendet oder die Auswahl wurde geändert. Bitte neu beginnen.")
    if previous and len(data.draft.strip()) < 2:
        raise HTTPException(422, "Schreibe zuerst deine Antwort auf den letzten Gesprächsschritt.")
    if previous and db.scalar(select(LanguageProject.id).where(LanguageProject.previous_id == previous.id)):
        raise HTTPException(409, "Dieser Gesprächsschritt wurde bereits fortgesetzt. Öffne den gespeicherten nächsten Schritt.")
    if previous and previous.item_revisions != [{"id": item.id, "revision": item.revision} for item in items]:
        raise HTTPException(409, "Ein Wort wurde inzwischen korrigiert. Bitte ein neues Gespräch beginnen.")
    row = LanguageProject(id=uid(), child_id=child.id, user_id=p.user.id, session_id=p.session.id,
        request_key=idempotency_key, request_digest=value, target_locale=data.target_locale, mode=data.mode,
        inputs=body, source_revisions=source_revisions, item_revisions=[{"id": item.id, "revision": item.revision} for item in items],
        previous_id=data.previous_id, step=previous.step + 1 if previous else 1, status="queued")
    authority(db, row, child.family_id)
    context(db, row)
    db.add(row)
    db.flush()
    job = Job(id=uid(), child_id=child.id, kind="language_project", idempotency="language:" + fingerprint([child.id, idempotency_key]),
              payload={"project_id": row.id, "family_id": child.family_id})
    db.add(job)
    db.flush()
    row.job_id = job.id
    reserve(db, db.get(Family, child.family_id), child.id, job.id, "language_project")
    record(db, child.id, "language_project", {"project_id": row.id, "mode": row.mode})
    for item in items:
        record(db, child.id, "vocabulary_exposure", {"item_id": item.id, "revision": item.revision, "via": "language_project_selection"})
    db.commit()
    return project_data(db, row)


@router.get("/children/{child_id}/language-projects")
def projects(child_id: str, page: int = Query(1, ge=1, le=100000), p=Depends(authenticated), db=Depends(get_db)):
    child_access(db, p, child_id)
    rows = list(db.scalars(select(LanguageProject).where(LanguageProject.child_id == child_id)
        .order_by(LanguageProject.created.desc(), LanguageProject.id).offset((page - 1) * 15).limit(16)))
    return {"projects": [project_data(db, row, child_view=p.user.role == "child") for row in rows[:15]],
            "page": page, "has_more": len(rows) > 15}


@router.get("/children/{child_id}/language-projects/{project_id}")
def get_project(child_id: str, project_id: str, p=Depends(authenticated), db=Depends(get_db)):
    child_access(db, p, child_id)
    row = db.get(LanguageProject, project_id)
    if not row or row.child_id != child_id:
        raise HTTPException(404, "Sprachprojekt nicht gefunden.")
    return project_data(db, row, child_view=p.user.role == "child")


@router.post("/children/{child_id}/language-projects/{project_id}/retry", status_code=202)
def retry_project(child_id: str, project_id: str, data: s.ProjectRetry, idempotency_key: str = KEY,
                  p=Depends(child_user), db=Depends(get_db)):
    from .language_repair import requeue

    child_access(db, p, child_id)
    row = db.get(LanguageProject, project_id)
    if not row or row.child_id != child_id:
        raise HTTPException(404, "Sprachprojekt nicht gefunden.")
    # The original failed job is the canonical operation key even if two
    # devices use different request keys. A read/reload never reaches here.
    requeue(db, project_id, data.failed_job_id, principal=p)
    db.commit()
    return project_data(db, row)


def checked_output(raw, payload, row):
    output = s.LanguageProjectOutput.model_validate(raw)
    if output.response_locale not in ("de-DE", row.target_locale):
        raise ProviderError("Die Sprache der Lernhilfe passt nicht zur ausgewählten Lernsprache.")
    if row.mode in OWN_WORK and len(output.criteria) < 2:
        raise ProviderError("Für den eigenen Entwurf fehlen verständliche Rückmeldungskriterien.")
    for criterion in output.criteria:
        if criterion.draft_quote and normalized(criterion.draft_quote) not in normalized(payload["draft"]):
            raise ProviderError("Die Rückmeldung zitiert Text, der nicht im eigenen Entwurf steht.")
    words = {word["id"]: word for word in payload["words"]}
    text = "\n".join(material["content"] for material in payload["materials"])
    # Manual vocabulary is explicitly confirmed too, but cannot activate a
    # grammar course or claim source examples which were never supplied.
    confirmed = normalized(text + "\n" + "\n".join(f"{word['word']} = {word['meaning']}" for word in words.values()))
    if not literal_present(confirmed, output.source_excerpt):
        raise ProviderError("Der Sprachvorschlag hat keinen passenden Beleg im bestätigten Stoff.")
    result = []
    for q in output.questions:
        word = words.get(q.vocabulary_item_id)
        if not word or not literal_present(confirmed, q.source_excerpt):
            raise ProviderError("Eine Sprachaufgabe ist nicht an die ausgewählten Wörter und Quellen gebunden.")
        if not any(re.search(r"(?<!\w)" + re.escape(value) + r"(?!\w)", q.prompt + " " + q.cue + " " + q.answer, re.IGNORECASE)
                   for value in [word["word"], *word["variants"]]):
            raise ProviderError("Die Aufgabe verwendet ihr zugeordnetes Lernwort nicht.")
        if row.mode in ("context_gap", "sentence_order", "grammar") and q.task_kind != row.mode:
            raise ProviderError("Die Sprachaufgabe prüft nicht die ausdrücklich gewählte Fähigkeit.")
        if q.task_kind == "grammar" and row.mode != "grammar":
            raise ProviderError("Ein Grammatikthema wurde nicht ausdrücklich aktiviert.")
        if q.task_kind == "context_gap" and len(re.findall(r"_{2,}|\[Lücke\]", q.prompt + " " + q.cue)) != 1:
            raise ProviderError("Die Kontextaufgabe benötigt genau eine klar erkennbare Lücke.")
        if q.task_kind == "context_gap" and any(normalized(answer) not in {normalized(v) for v in [word["word"], *word["variants"]]}
                                                for answer in [q.answer, *q.accepted]):
            raise ProviderError("Die Wortlücke prüft nicht das zugeordnete bestätigte Lernwort.")
        if q.task_kind == "grammar" and q.type != "choice" and len(re.findall(r"_{2,}|\[Lücke\]", q.prompt + " " + q.cue)) != 1:
            raise ProviderError("Geschlossene Grammatik prüft eine Auswahl oder eine einzelne Lücke. Freie Sätze brauchen eine offene Bewertung.")
        if q.task_kind != "free_sentence":
            for answer in [q.answer, *q.accepted]:
                if not literal_present(confirmed, answer) and answer not in [word["word"], *word["variants"]]:
                    raise ProviderError("Eine Lösung oder Antwortvariante ist nicht im bestätigten Sprachmaterial belegt.")
        elif q.type != "short" or q.accepted:
            raise ProviderError("Freie Sätze benötigen eine offene Texteingabe ohne behauptete Variantenliste.")
        if q.type != "choice" and q.task_kind != "sentence_order" and q.task_kind != "free_sentence":
            if re.search(r"(?<!\w)" + re.escape(q.answer) + r"(?!\w)", q.prompt + " " + q.cue, re.IGNORECASE):
                raise ProviderError("Die Sprachaufgabe verrät bereits ihre Lösung.")
        skill = {"context_gap": "recall", "sentence_order": "sentence", "grammar": "grammar", "free_sentence": "writing"}[q.task_kind]
        criterion = {"context_gap": "meaning", "sentence_order": "sentence", "grammar": "grammar", "free_sentence": "sentence"}[q.task_kind]
        bank = q.answer.split() if q.task_kind == "sentence_order" else []
        if bank and (len(bank) < 2 or len(bank) > 25):
            raise ProviderError("Satzbausteine benötigen zwei bis 25 Wörter.")
        bank = [token for _, token in sorted((fingerprint([q.id, i, token]), token) for i, token in enumerate(bank))]
        snapshot = next(item for item in row.item_revisions if item["id"] == q.vocabulary_item_id)
        meta = s.LanguageTask(target_locale=row.target_locale, answer_locale=row.target_locale,
            task_kind=q.task_kind, skill=skill, direction="target_to_target", vocabulary_item_id=q.vocabulary_item_id,
            vocabulary_revision=snapshot["revision"], source_revisions=row.source_revisions,
            evaluation_policy=s.EvaluationPolicy(criterion=criterion, case_sensitive=True, apostrophe_equivalent=True,
                                                  closed_answers=q.task_kind != "free_sentence",
                                                  terminal_punctuation_optional=q.task_kind in ("grammar", "sentence_order")),
            cue=q.cue, cue_locale=q.cue_locale, word_bank=bank, generated_example=True,
            grammar_topic=row.inputs["grammar_topic"] if q.task_kind == "grammar" else "")
        if q.cue_locale not in ("de-DE", row.target_locale):
            raise ProviderError("Die Beispielsprache passt nicht zur ausgewählten Lernsprache.")
        result.append({key: getattr(q, key) for key in ("id", "type", "prompt", "options", "answer", "accepted", "hints", "explanation")} |
                      {"language": meta.model_dump(), "language_feedback": [{"locale": row.target_locale, "text": q.answer}]})
    return output, result


def process(job_id):
    from .learning_sources import failure_billing

    result = None
    provider_requested = False
    try:
        with DB() as db:
            job = db.get(Job, job_id)
            if not job or job.status != "running":
                return
            row = db.get(LanguageProject, job.payload["project_id"])
            if not row or row.job_id != job.id:
                raise ProviderError("Sprachprojekt nicht mehr vorhanden.")
            authority(db, row, job.payload["family_id"])
            payload = context(db, row)
            signature = fingerprint([payload, db.get(Child, row.child_id).preferences])
            config = job_config(db, job, "language_project")
            usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
            if not usage or (usage.provider, usage.model, usage.config_revision) != (config.provider, config.model, config.revision):
                raise ProviderError("Die KI-Einstellung wurde geändert. Bitte neu vorbereiten.")
            external_allowed(config)
            values = {c.name: getattr(config, c.name) for c in ProviderConfig.__table__.columns}
            row.status = "running"
            from .catalog_ai import with_catalog_context

            payload = with_catalog_context(db, db.get(Child, row.child_id), payload | {
                "materials": [source | {"subject": s.TARGETS[row.target_locale].split(" · ")[0],
                    "topic": row.inputs["grammar_topic"] or row.inputs["goal"]} for source in payload["materials"]]})
            db.commit()
        provider_requested = True
        result = request_provider(ProviderConfig(**values), "language_project", payload)
        with DB.begin() as db:
            job = db.get(Job, job_id)
            if not job or job.status != "running":
                return
            lock_child(db, db.get(Child, job.child_id))
            row = db.get(LanguageProject, job.payload["project_id"], populate_existing=True)
            if not row:
                raise ProviderError("Das Sprachprojekt wurde gelöscht.")
            authority(db, row, job.payload["family_id"])
            if signature != fingerprint([context(db, row), db.get(Child, row.child_id).preferences]):
                raise ProviderError("Wörter, Quellen oder Lernvorgaben wurden geändert. Bitte neu vorbereiten.")
            config = job_config(db, job, "language_project")
            usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
            if not usage or (usage.provider, usage.model, usage.config_revision) != (config.provider, config.model, config.revision):
                raise ProviderError("Die KI-Einstellung wurde während der Verarbeitung geändert.")
            external_allowed(config)
            output, questions = checked_output(result.data, payload, row)
            unit = LearningUnit(id=uid(), child_id=row.child_id, subject=s.TARGETS[row.target_locale].split(" · ")[0],
                topic=output.title, explanation="Bearbeite die Aufgaben in Ruhe. Deine Antworten bleiben gespeichert." if row.mode == "exam" else output.explanation,
                questions=questions, round_kind="vocabulary", estimated_minutes=min(10, len(questions) * 2),
                introduction_seen=row.mode == "exam", provider=config.provider, model=config.model)
            db.add(unit)
            db.flush()
            if row.mode != "exam":
                # A scaffolded workshop is not an independent spelling test
                # immediately after a model example.
                record(db, row.child_id, "explanation", {"via": "language_project", "project_id": row.id}, unit.id)
            for source in row.source_revisions:
                db.add(UnitSource(unit_id=unit.id, material_id=source["id"], revision=source["revision"]))
            if result.catalog_assignment:
                from .catalog_ai import remember

                remember(db, "unit", unit, result.catalog_assignment)
            row.unit_id = unit.id
            row.result = {"title": output.title, "response": output.response, "response_locale": output.response_locale,
                          "explanation": output.explanation, "source_excerpt": output.source_excerpt,
                          "generated": True, "is_student_work": False,
                          "criteria": [criterion.model_dump() for criterion in output.criteria]}
            row.status, row.error = "ready", None
            job.status, job.finished, job.result = "completed", int(now()), {"project_id": row.id, "unit_id": unit.id}
            settle(db, usage, result)
    except Exception as error:
        reason = str(error.detail) if isinstance(error, HTTPException) else str(error) if isinstance(error, ProviderError) else "Das Sprachprojekt konnte nicht sicher geprüft werden. Bitte neu vorbereiten."
        with DB.begin() as db:
            job = db.get(Job, job_id)
            if not job or job.status != "running":
                return
            job.status, job.finished, job.error = "failed", int(now()), reason[:500]
            row = db.get(LanguageProject, job.payload.get("project_id"))
            if row:
                row.status, row.error = "failed", reason[:500]
            usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
            if usage:
                settle(db, usage, failure_billing(result, error, provider_requested=provider_requested), failed=True)
