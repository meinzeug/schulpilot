"""Explicit scoped advisory chat using the existing durable, reserved worker.

GETs only project current state. Chat never writes or regrades an Attempt, goal,
mastery or grade. Successful current-task/source help records an explanation
activity; discussion of already-saved feedback does not. Private context is
rebuilt before and after AI.
"""

import json

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from pydantic import ValidationError
from sqlalchemy import delete, func, select, update

from .db import (
    DB,
    Activity,
    Attempt,
    Child,
    Family,
    Job,
    LearningUnit,
    Material,
    Membership,
    ProviderConfig,
    SchoolDay,
    SchulbuddyTurn,
    Session,
    UnitSource,
    Usage,
    User,
    get_db,
    now,
    uid,
)
from .providers import ProviderError, Result, request_provider, reserve, settle
from .schulbuddy_provider import configured
from .schulbuddy_provider import snapshot as provider_snapshot
from .schulbuddy_schemas import BuddyOutput, BuddyQuestion, BuddyScope, PageKind
from .security import Principal, audit, authenticated, child_access, digest, own_child, rate_limit

router = APIRouter(tags=["Schulbuddy"])
LABELS = {"today": "Heute", "learn": "Lernen", "words": "Wörter", "homework": "Hausaufgaben",
          "notebooks": "Hefte", "account": "Zugang", "messages": "Nachrichten", "progress": "Lernstand",
          "plan": "Elternplanung", "settings": "Einstellungen", "admin": "Betriebsansicht", "general": "Schulbuddy"}
NO_CHILD = "Der KI-Chat benötigt einen berechtigten Kinderkontext und dessen Lernbudget. Hier ist nur allgemeine Bedienhilfe verfügbar."
NOTICE = "Schulbuddy erklärt und fragt nach. Chatantworten sind ungeprüfte Hilfe, keine bewerteten Aufgaben oder Kompetenznachweise."


def fingerprint(value):
    return digest(json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":")))


def resolve(db, p, scope):
    """Client IDs name a scope, never grant a role/family or upload free context."""
    if p.user.role == "admin":
        if scope.child_id or scope.unit_id or scope.material_id or scope.day_id or scope.question_id:
            raise HTTPException(403, "Betriebsadministratoren erhalten keinen privaten Kinderkontext.")
        return None, []
    targets = []
    for model, key in ((LearningUnit, "unit_id"), (Material, "material_id"), (SchoolDay, "day_id")):
        if value := getattr(scope, key):
            target = db.get(model, value)
            if not target:
                raise HTTPException(404, "Dieser Schulbuddy-Bereich ist nicht verfügbar.")
            targets.append((key, target))
    if p.user.role == "child":
        child = own_child(db, p)
    elif p.user.role == "parent":
        child_id = scope.child_id or (targets[0][1].child_id if targets else None)
        if not child_id:
            children = list(db.scalars(select(Child).join(Membership, Membership.family_id == Child.family_id)
                .where(Membership.user_id == p.user.id).order_by(Child.id).limit(2)))
            child_id = children[0].id if len(children) == 1 else None
        child = child_access(db, p, child_id) if child_id else None
    else:
        raise HTTPException(403, "Dieser Zugang unterstützt keinen privaten Schulbuddy-Kontext.")
    if scope.child_id and (not child or scope.child_id != child.id):
        raise HTTPException(404, "Kind nicht gefunden.")
    if any(not child or target.child_id != child.id for _, target in targets):
        raise HTTPException(404, "Dieser Schulbuddy-Bereich gehört nicht zu diesem Zugang.")
    by_kind = dict(targets)
    if scope.question_id and not scope.unit_id:
        raise HTTPException(422, "Eine konkrete Aufgabe benötigt ihre gespeicherte Lernrunde.")
    if unit := by_kind.get("unit_id"):
        if scope.day_id and unit.school_day_id != scope.day_id:
            raise HTTPException(409, "Lernrunde und Schultag passen nicht zusammen.")
        if scope.material_id:
            ids = set(db.scalars(select(UnitSource.material_id).where(UnitSource.unit_id == unit.id)))
            if scope.material_id not in ids and scope.material_id != unit.material_id:
                raise HTTPException(409, "Die gewählte Heftseite gehört nicht zu dieser Lernrunde.")
    elif material := by_kind.get("material_id"):
        if scope.day_id and material.school_day_id != scope.day_id:
            raise HTTPException(409, "Heftseite und Schultag passen nicht zusammen.")
    return child, targets


def scope_context(db, p, scope):
    child, targets = resolve(db, p, scope)
    normalized = scope.model_dump()
    normalized["child_id"] = child.id if child else None
    # Same actor/role/page/actual child: no cross-account or cross-parent history.
    context_key = fingerprint([p.user.id, p.user.role, normalized])
    label = LABELS[scope.page_kind]
    payload = {"role": p.user.role, "page": scope.page_kind,
               "navigation": ["Heute", "Lernen", "Wörter", "Hefte"] if p.user.role == "child"
               else ["Kinderübersicht", "Lernstand", "Elternplanung", "Einstellungen"],
               "sources": [], "knowledge": {}, "history": []}
    refs, current_guard = [], []
    if not child:
        return child, normalized, context_key, label, payload, refs, fingerprint([normalized, p.user.role])
    by_kind = dict(targets)
    materials, unit = [], by_kind.get("unit_id")
    if unit:
        from .learning_controller import source_state

        signature, valid, materials = source_state(db, unit)
        if not valid:
            raise HTTPException(409, "Die Lernquellen wurden geändert. Bitte den aktuellen Bereich öffnen und zuerst prüfen.")
        current_guard.append([unit.id, signature, unit.status, unit.goal_revision])
        label = unit.subject + " · " + unit.topic
        payload["unit"] = {"subject": unit.subject, "topic": unit.topic, "status": unit.status,
                           "round_kind": unit.round_kind}
        # A child must not be able to drop question_id to turn actual help for
        # the same open exercise into an apparently independent later answer.
        # Derive the current question on the server, before context hashing.
        focused, pending = None, None
        attempts = []
        if scope.question_id or p.user.role == "child":
            from .learning import pending_feedback
            from .learning_controller import facts

            # Match unit_data's exact saved order and its latest unread
            # feedback rule. The visible feedback precedes the next open task.
            attempts = list(db.scalars(select(Attempt).where(Attempt.unit_id == unit.id).order_by(
                Attempt.created, func.coalesce(Attempt.evaluation["attempt_number"].as_integer(), 0), Attempt.id)))
            events = list(db.scalars(select(Activity).where(Activity.unit_id == unit.id)))
            pending = pending_feedback(unit, attempts, events)
            if pending:
                focused = next((q for q in unit.questions if q["id"] == pending["question_id"]), None)
            elif scope.question_id or (unit.status in ("active", "paused") and not unit.completed):
                focused = facts(db, unit)["question"]
        question_id = scope.question_id or (focused["id"] if focused else None)
        if question_id:
            question = next((q for q in unit.questions if q["id"] == question_id), None)
            if not question or not focused or focused["id"] != question_id:
                raise HTTPException(409, "Diese Aufgabe ist nicht mehr der aktuelle Lernschritt. Bitte den Lernraum neu öffnen.")
            normalized["question_id"] = question_id
            payload["current_question"] = {k: question[k] for k in ("id", "type", "prompt", "options") if k in question}
            payload["current_question"]["own_work_attempted"] = any(a.question_id == question_id for a in attempts)
            payload["current_question"]["feedback_pending"] = pending is not None
            if pending:
                payload["current_question"]["observed_outcome"] = pending["outcome"]
            current_guard.append(["visible_question", question_id, pending["attempt_id"] if pending else None])
    elif material := by_kind.get("material_id"):
        materials = [material]
        label = material.subject + " · " + material.topic
    elif day := by_kind.get("day_id"):
        current_guard.append([day.id, day.revision])
        materials = list(db.scalars(select(Material).where(Material.child_id == child.id,
            Material.school_day_id == day.id).order_by(Material.page_number, Material.id).limit(7)))
        label = "Schultag " + day.school_date
    if len(materials) > 6 or sum(len(m.content or "") for m in materials) > 18000:
        raise HTTPException(422, "Bitte eine einzelne Heftseite oder kleinere Lernrunde für Schulbuddy auswählen.")
    if any(not m.confirmed or not (m.content or "").strip() for m in materials):
        raise HTTPException(409, "Die zugehörigen Heftseiten zuerst prüfen und bestätigen.")
    # IN-query order is not guaranteed. Stable ref names and guards must not
    # change merely because PostgreSQL returned the same rows differently.
    materials = sorted(materials, key=lambda material: (material.page_number or 0, material.id))
    for index, m in enumerate(materials):
        if m.child_id != child.id:
            raise HTTPException(404, "Heftseite nicht gefunden.")
        refs.append({"id": m.id, "revision": m.revision, "ref": f"p{index+1}",
                     "label": f"{m.subject} · {m.topic}"})
        payload["sources"].append({"ref": f"p{index+1}", "label": refs[-1]["label"], "content": m.content})
    if unit or materials or scope.page_kind in ("today", "learn", "words", "homework", "notebooks", "progress", "plan"):
        from .learning_knowledge import buddy_context

        payload["grade"] = child.grade
        payload["knowledge"] = buddy_context(db, child, unit=unit, material_ids=[m.id for m in materials], limit=12)
    from .schulbuddy_pages import page_context

    payload["page_inventory"] = page_context(db, p, child, scope.page_kind)
    # Never forward display names, grades/notes, arbitrary memory or hidden keys.
    # Include the derived question in both conversation identity and the
    # dispatch guard. Advancing an exercise invalidates its prepared answer.
    context_key = fingerprint([p.user.id, p.user.role, normalized])
    signature = fingerprint([normalized, child.family_id, child.grade, child.preferences,
                             refs, current_guard, payload["knowledge"], payload["page_inventory"]])
    return child, normalized, context_key, label, payload, refs, signature


def public_turn(db, turn):
    job = db.get(Job, turn.job_id)
    status, error = turn.status, turn.error
    if status in ("queued", "running"):
        status = "failed" if not job or job.status == "failed" else "running" if job.status == "running" else "queued"
        if status == "failed":
            error = error or "Diese Frage konnte nicht beantwortet werden. Kein automatischer weiterer Versuch."
    reply = turn.reply or {}
    changed = any(not (m := db.get(Material, ref["id"])) or m.child_id != turn.child_id
                  or m.revision != ref["revision"] or not m.confirmed for ref in turn.source_revisions)
    return {"id": turn.id, "request_key": turn.request_key, "job_id": turn.job_id, "status": status,
            "question": turn.question, "reply_to": turn.reply_to, "context_key": turn.context_key,
            "answer": reply.get("answer"), "next_question": reply.get("next_question"),
            "sources": reply.get("sources", []), "error": error, "created": turn.created,
            "starters": reply.get("starters", []), "source_changed": changed,
            "model": (job.payload or {}).get("model_binding", {}).get("model") if job else None,
            "reasoning_effort": "high", "notice":
                "Diese gespeicherte Antwort und ihre Zitate gehören zu einer älteren Quellenfassung. Für die aktuelle Fassung eine neue Frage stellen. " + NOTICE if changed else NOTICE}


def starters_for(page_kind, label, payload):
    """Finite local suggestions, based only on this authorized page projection."""
    page = {
        "today": "Was ist heute mein nächster Schritt?",
        "learn": "Wie übe ich dieses Thema?",
        "words": "Wie kann ich mir diese Wörter merken?",
        "homework": "Wie fange ich an, ohne die Lösung zu sehen?",
        "notebooks": "Was kann ich mit meinen Heftseiten machen?",
        "account": "Wie ändere ich meine Einstellungen?",
        "messages": "Wie frage ich nach Hilfe?",
        "progress": "Was kann ich schon gut, was übe ich als Nächstes?",
        "plan": "Was unterscheidet Elterntermine von einem Lernvorschlag?",
        "settings": "Wie prüfe ich meinen Entwurf vor dem Speichern?",
        "admin": "Welche Betriebsprüfung verrät keine privaten Kinderinhalte?",
        "general": "Wo finde ich Hefte, Lernrunden und gespeicherte Rückmeldungen?",
    }[page_kind]
    rows = [page]
    if payload["sources"]:
        rows.insert(0, f"Erkläre mir den bestätigten Stoff zu {label[:100]} in einem kleinen Schritt.")
    goals = payload.get("knowledge", {}).get("goals", [])
    weak = next((g for g in goals if g.get("needs_practice") or g.get("uncertain") or g.get("supported")), None)
    strong = next((g for g in goals if g.get("independent")), None)
    if weak:
        rows.append(f"Welche Grundlage hilft mir bei {str(weak.get('label', 'diesem Lernziel'))[:100]}?")
    elif strong:
        rows.append(f"Wie kann ich auf den belegten Übungen zu {str(strong.get('label', 'diesem Lernziel'))[:100]} aufbauen?")
    elif payload["sources"]:
        rows.append("Welche Voraussetzung ist durch meine bisherigen Übungen wirklich belegt?")
    else:
        rows.append("Wie wähle ich eine eigene bestätigte Heftseite für eine fachliche Frage?")
    return list(dict.fromkeys(rows))[:3]


@router.get("/schulbuddy/context")
def read_context(page_kind: PageKind = "general", child_id: str | None = Query(None, max_length=32),
                 unit_id: str | None = Query(None, max_length=32), material_id: str | None = Query(None, max_length=32),
                 day_id: str | None = Query(None, max_length=32), question_id: str | None = Query(None, max_length=80),
                 p=Depends(authenticated), db=Depends(get_db)):
    try:
        scope = BuddyScope(page_kind=page_kind, child_id=child_id, unit_id=unit_id, material_id=material_id, day_id=day_id,
                          question_id=question_id)
    except ValidationError:
        raise HTTPException(422, "Ungültiger Schulbuddy-Bereich.") from None
    child, _, key, label, payload, _, _ = scope_context(db, p, scope)
    available, notice, model = False, NO_CHILD, None
    if child:
        try:
            # Read-only parents retain their own history, but the form must not
            # advertise a paid action which authority(write=True) will reject.
            child_access(db, p, child.id, write=True)
            config = configured(db)
            family = db.get(Family, child.family_id)
            if family.synthetic:
                raise HTTPException(403, "Freie Schulbuddy-Fragen sind im künstlichen Testraum nicht verfügbar.")
            from .commerce import usage_terms

            usage_terms(db, family, enforce=True)
            available, notice, model = True, NOTICE, config.model
        except HTTPException as error:
            notice = str(error.detail)
    rows = list(db.scalars(select(SchulbuddyTurn).where(SchulbuddyTurn.user_id == p.user.id,
        SchulbuddyTurn.context_key == key).order_by(SchulbuddyTurn.created.desc(), SchulbuddyTurn.id.desc()).limit(8)))
    starters = starters_for(scope.page_kind, label, payload)
    return {"context_key": key, "label": label, "starters": starters, "available": available, "notice": notice,
            "model": model, "reasoning_effort": "high", "history": [public_turn(db, row) for row in reversed(rows)]}


def authority(db, turn):
    session = db.get(Session, turn.session_id, populate_existing=True)
    user = db.get(User, turn.user_id, populate_existing=True)
    if (not session or session.user_id != turn.user_id or session.revoked or session.expires <= now()
            or now() - session.seen > 7 * 86400 or not user or user.disabled or not user.verified
            or user.role not in ("child", "parent")):
        raise HTTPException(401, "Dieser Schulbuddy-Zugang wurde beendet oder widerrufen.")
    p = Principal(user, session)
    child = child_access(db, p, turn.child_id, write=True)
    family = db.get(Family, child.family_id)
    if family.synthetic:
        raise HTTPException(403, "Freie Schulbuddy-Fragen sind im künstlichen Testraum nicht verfügbar.")
    from .commerce import usage_terms

    usage_terms(db, family, enforce=True)
    return p, child


def history_for(db, turn):
    history, seen, previous = [], {turn.id}, turn.reply_to
    while previous and len(history) < 4:
        old = db.get(SchulbuddyTurn, previous)
        if (not old or old.id in seen or old.user_id != turn.user_id or old.child_id != turn.child_id
                or old.context_key != turn.context_key or old.source_revisions != turn.source_revisions
                or old.status != "ready" or not old.reply):
            raise HTTPException(409, "Der frühere Chat passt nicht mehr zum aktuellen Bereich. Bitte eine neue Frage stellen.")
        history.append({"question": old.question, "answer": old.reply["answer"]})
        seen.add(old.id)
        previous = old.reply_to
    return list(reversed(history))


@router.post("/schulbuddy/questions", status_code=202)
def ask(data: BuddyQuestion, idempotency_key: str = Header(..., min_length=16, max_length=80, pattern=r"^[A-Za-z0-9_-]+$"),
        p=Depends(authenticated), db=Depends(get_db)):
    if p.user.role not in ("child", "parent"):
        raise HTTPException(403, NO_CHILD)
    request_hash = fingerprint(data.model_dump())
    # A replay is a read of the original operation, even after the exercise has
    # moved on. It cannot reserve again or reuse a key for another request.
    replay = db.scalar(select(SchulbuddyTurn).where(SchulbuddyTurn.user_id == p.user.id,
        SchulbuddyTurn.request_key == idempotency_key))
    if replay:
        if replay.request_hash != request_hash:
            raise HTTPException(409, "Dieser Anfrage-Schlüssel gehört zu einer anderen Frage oder Seite.")
        child_access(db, p, replay.child_id)
        return public_turn(db, replay)
    scope = BuddyScope(**data.model_dump(exclude={"question", "reply_to"}))
    child, normalized, key, _, _, refs, signature = scope_context(db, p, scope)
    if not child:
        raise HTTPException(403, NO_CHILD)
    if not data.question.strip():
        raise HTTPException(422, "Bitte eine konkrete Frage eingeben.")
    if scope.unit_id:
        # Same order as answering/completing/helping: Unit, then Child.
        statement = select(LearningUnit).where(LearningUnit.id == scope.unit_id, LearningUnit.child_id == child.id)
        if db.bind.dialect.name == "postgresql":
            statement = statement.with_for_update()
        else:
            db.execute(update(LearningUnit).where(LearningUnit.id == scope.unit_id).values(status=LearningUnit.status))
        if not db.scalar(statement.execution_options(populate_existing=True)):
            raise HTTPException(404, "Lernrunde nicht gefunden.")
    db.execute(update(Child).where(Child.id == child.id).values(grade=Child.grade))
    db.expire_all()
    child = db.get(Child, child.id, populate_existing=True)
    session = db.get(Session, p.session.id, populate_existing=True)
    user = db.get(User, p.user.id, populate_existing=True)
    if (not session or session.revoked or session.expires <= now() or now() - session.seen > 7 * 86400
            or not user or user.disabled or not user.verified or user.role not in ("child", "parent")):
        raise HTTPException(401, "Bitte für Schulbuddy erneut anmelden.")
    child_access(db, p, child.id, write=True)
    existing = db.scalar(select(SchulbuddyTurn).where(SchulbuddyTurn.user_id == p.user.id,
        SchulbuddyTurn.request_key == idempotency_key))
    if existing:
        if existing.request_hash != request_hash or existing.context_key != key:
            raise HTTPException(409, "Dieser Anfrage-Schlüssel gehört zu einer anderen Frage oder Seite.")
        return public_turn(db, existing)
    if db.scalar(select(Job.id).where(Job.child_id == child.id, Job.status.in_(["queued", "running"]))):
        raise HTTPException(409, "Eine Verarbeitung läuft noch. Bitte deren Ergebnis abwarten.")
    job_key = "buddy:" + digest(p.user.id + ":" + idempotency_key)
    if db.scalar(select(Job.id).where(Job.idempotency == job_key)):
        raise HTTPException(409, "Diese frühere Frage wurde gelöscht oder ist nicht mehr verfügbar. Bitte eine neue Frage bewusst beginnen.")
    turn = SchulbuddyTurn(id=uid(), job_id=uid(), user_id=p.user.id, child_id=child.id, session_id=p.session.id,
        request_key=idempotency_key, request_hash=request_hash, context_key=key, scope=normalized,
        question=data.question.strip(), reply_to=data.reply_to, source_revisions=refs)
    authority(db, turn)
    # Re-resolve after acquiring Child: no stale pre-lock source/context claim.
    _, normalized, current_key, _, _, refs, current_signature = scope_context(db, p, BuddyScope(**normalized))
    if current_key != key or current_signature != signature:
        raise HTTPException(409, "Der aktuelle Bereich wurde geändert. Bitte vor dem Senden neu öffnen.")
    history_for(db, turn)
    rate_limit(db, "schulbuddy:" + p.user.id, 8, 60, commit=False)
    config = configured(db, verify_catalog=True)
    binding = provider_snapshot(db, config)
    job = Job(id=turn.job_id, child_id=child.id, kind="schulbuddy", idempotency=job_key,
        payload={"turn_id": turn.id, "signature": signature, "family_id": child.family_id, "model_binding": binding})
    db.add_all([job, turn])
    db.flush()
    reserve(db, db.get(Family, child.family_id), child.id, job.id, "schulbuddy")
    audit(db, p.user.id, "schulbuddy.question", turn.id)
    db.commit()
    return public_turn(db, turn)


@router.get("/schulbuddy/questions/{turn_id}")
def read_turn(turn_id: str, p=Depends(authenticated), db=Depends(get_db)):
    turn = db.get(SchulbuddyTurn, turn_id)
    if not turn or turn.user_id != p.user.id or p.user.role not in ("child", "parent"):
        raise HTTPException(404, "Schulbuddy-Frage nicht gefunden.")
    child_access(db, p, turn.child_id)
    return public_turn(db, turn)


def checked_reply(value, payload, refs):
    reply = BuddyOutput.model_validate(value).model_dump()
    by_ref = {s["ref"]: s for s in payload["sources"]}
    metadata = {s["ref"]: s for s in refs}
    seen = set()
    for citation in reply["sources"]:
        source = by_ref.get(citation["ref"])
        if (not source or citation["quote"] not in source["content"]
                or (citation["ref"], citation["quote"]) in seen):
            raise ProviderError("Schulbuddy konnte den Quellenbeleg nicht prüfen. Keine Antwort übernommen.")
        seen.add((citation["ref"], citation["quote"]))
        citation.update(material_id=metadata[citation["ref"]]["id"], label=metadata[citation["ref"]]["label"])
    return reply


def record_help(db, turn, units, refs, reply, *, feedback_only=False):
    """Record source-backed child assistance; never rewrite an old Attempt.

    Caller already holds every active/paused Unit in stable order, then Child.
    A material/day explanation uses exactly the established tutor overlap
    rule. A focused question only marks that question in its own unit.
    """
    # Discussing an already saved answer is not help for the unseen next
    # exercise and must never rewrite the competence of the saved attempt.
    if not units or feedback_only:
        return
    revisions = {source["id"]: source["revision"] for source in refs}
    by_unit = {}
    for source in db.scalars(select(UnitSource).where(UnitSource.unit_id.in_([unit.id for unit in units]))):
        by_unit.setdefault(source.unit_id, []).append(source)
    from .learning import record

    for unit in units:
        focused = unit.id == turn.scope.get("unit_id") and turn.scope.get("question_id")
        sources = by_unit.get(unit.id, [])
        shared = any(revisions.get(source.material_id) == source.revision for source in sources)
        if not sources:
            shared = unit.material_id in revisions
        if not focused and not (shared and reply["sources"]):
            continue
        detail = {"via": "schulbuddy", "turn_id": turn.id}
        if focused:
            detail["question_id"] = turn.scope["question_id"]
        record(db, turn.child_id, "explanation", detail, unit_id=unit.id)


def process(job_id):
    result, dispatched = None, False
    try:
        with DB() as db:
            job = db.get(Job, job_id)
            if not job or job.kind != "schulbuddy" or job.status != "running":
                return
            turn = db.get(SchulbuddyTurn, job.payload["turn_id"])
            if not turn or turn.job_id != job.id:
                raise ProviderError("Die Schulbuddy-Frage ist nicht mehr verfügbar.")
            p, child = authority(db, turn)
            _, _, key, _, payload, refs, signature = scope_context(db, p, BuddyScope(**turn.scope))
            config = configured(db, verify_catalog=True)
            if (key != turn.context_key or signature != job.payload["signature"]
                    or child.family_id != job.payload["family_id"]
                    or provider_snapshot(db, config) != job.payload["model_binding"]):
                raise ProviderError("Bereich, Lernbelege oder KI-Einstellung wurden geändert. Bitte bewusst neu fragen.")
            usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
            if not usage or (usage.provider, usage.model, usage.config_revision) != (config.provider, config.model, config.revision):
                raise ProviderError("Die gespeicherte Schulbuddy-Reservierung passt nicht mehr zur gewählten Route.")
            payload.update(question=turn.question, history=history_for(db, turn))
            turn.status = "running"
            values = {c.name: getattr(config, c.name) for c in ProviderConfig.__table__.columns}
            db.commit()
        dispatched = True
        result = request_provider(ProviderConfig(**values), "schulbuddy", payload)
        reply = checked_reply(result.data, payload, refs)
        with DB.begin() as db:
            job = db.get(Job, job_id)
            if not job or job.status != "running":
                return
            # Completion/answers also lock Unit before Child. Acquire the full
            # affected set in stable order, as the notebook tutor does.
            ongoing_units = list(db.scalars(select(LearningUnit).where(
                LearningUnit.child_id == job.child_id, LearningUnit.status.in_(("active", "paused")),
                LearningUnit.completed.is_(None), LearningUnit.synthetic.is_(False))
                .order_by(LearningUnit.id).with_for_update().execution_options(populate_existing=True))) \
                if payload["role"] == "child" else []
            db.execute(update(Child).where(Child.id == job.child_id).values(grade=Child.grade))
            turn = db.get(SchulbuddyTurn, job.payload["turn_id"])
            if not turn:
                raise ProviderError("Die Schulbuddy-Frage wurde gelöscht.")
            p, child = authority(db, turn)
            config = configured(db, verify_catalog=True)
            if (scope_context(db, p, BuddyScope(**turn.scope))[6] != job.payload["signature"]
                    or child.family_id != job.payload["family_id"]
                    or provider_snapshot(db, config) != job.payload["model_binding"]):
                raise ProviderError("Bereich, Rechte, Lernbelege oder Modellbindung wurden während der Antwort geändert.")
            turn.status, turn.reply, turn.error = "ready", reply, None
            job.status, job.finished, job.result = "completed", int(now()), {"question_id": turn.id}
            usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
            if usage:
                settle(db, usage, result)
            if p.user.role == "child":
                record_help(db, turn, ongoing_units, refs, reply,
                            feedback_only=payload.get("current_question", {}).get("feedback_pending", False))
            audit(db, p.user.id, "schulbuddy.answer", turn.id)
    except Exception as error:
        reason = str(error.detail) if isinstance(error, HTTPException) else str(error) if isinstance(error, ProviderError) else "Schulbuddy konnte diese Frage nicht sicher beantworten. Kein automatischer weiterer Versuch."
        with DB.begin() as db:
            job = db.get(Job, job_id)
            if not job or job.status != "running":
                return
            job.status, job.finished, job.error = "failed", int(now()), reason[:500]
            from .job_failures import failure_code

            job.error_code = failure_code(error)
            turn = db.get(SchulbuddyTurn, job.payload.get("turn_id"))
            if turn:
                turn.status, turn.reply, turn.error = "failed", None, reason[:500]
            usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
            if usage:
                billing = result or getattr(error, "billing_result", None)
                if not dispatched:
                    billing = Result({}, 0, 0, 0, cost_source="cancelled", telemetry={"pre_dispatch": True})
                settle(db, usage, billing, failed=True)


def purge_sources(db, material_ids, *, child_id=None):
    """Source erasure removes all stored quotes/history referring to that source."""
    ids = set(material_ids)
    children = {child_id} if child_id else set(db.scalars(select(Material.child_id).where(Material.id.in_(ids))))
    query = select(SchulbuddyTurn).where(SchulbuddyTurn.child_id.in_(children))
    turns = [t for t in db.scalars(query) if any(s["id"] in ids for s in t.source_revisions)
             or t.scope.get("page_kind") not in ("account", "settings", "general", "admin")]
    erase_turns(db, turns)


def purge_units(db, child_id, unit_ids):
    """Erase derived advice as well as source quotes when learning evidence goes."""
    ids = set(unit_ids)
    turns = [t for t in db.scalars(select(SchulbuddyTurn).where(SchulbuddyTurn.child_id == child_id))
             if t.scope.get("unit_id") in ids or t.scope.get("page_kind") not in ("account", "settings", "general", "admin")]
    erase_turns(db, turns)


def erase_turns(db, turns):
    for turn in turns:
        changed = db.execute(update(Job).where(Job.id == turn.job_id, Job.status == "queued")
            .values(status="failed", finished=int(now()), error="Die Schulbuddy-Quelle wurde gelöscht."))
        if changed.rowcount:
            usage = db.scalar(select(Usage).where(Usage.job_id == turn.job_id))
            if usage:
                settle(db, usage, Result({}, 0, 0, 0, cost_source="cancelled"), failed=True)
    if turns:
        db.execute(delete(SchulbuddyTurn).where(SchulbuddyTurn.id.in_([t.id for t in turns])))
