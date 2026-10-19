"""Private, source-bound school vocabulary on the existing queue and attempts."""

import json
import re
import unicodedata

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from sqlalchemy import func, or_, select, update

from . import language_tasks as s
from . import vocabulary_review as review
from .db import (
    DB,
    Child,
    Family,
    Job,
    LearningUnit,
    Material,
    ProviderConfig,
    Session,
    UnitSource,
    Usage,
    User,
    VocabularyAction,
    VocabularyCollection,
    VocabularyImport,
    VocabularyItem,
    VocabularyMembership,
    VocabularyReview,
    get_db,
    now,
    uid,
)
from .learning import record
from .providers import ProviderError, config_for_function, external_allowed, request_provider, reserve, settle
from .security import Principal, authenticated, child_access, child_user, digest, rate_limit

router = APIRouter(tags=["Eigener Lernwortschatz"])
KEY = Header(..., min_length=16, max_length=80, pattern=r"^[A-Za-z0-9_-]+$")


def fingerprint(data):
    return digest(json.dumps(data, sort_keys=True, ensure_ascii=False))


def lock_child(db, child):
    db.execute(update(Child).where(Child.id == child.id).values(grade=Child.grade))


def current_sources(db, child_id, sources):
    for source in sources:
        material = db.get(Material, source["id"])
        if not material or material.child_id != child_id or not material.confirmed or material.revision != source["revision"]:
            raise HTTPException(409, "Die Heftseite wurde geändert. Bitte Wörter aus der aktuellen Seite neu bestätigen.")


def import_data(db, row):
    status, error = row.status, row.error
    job = db.get(Job, row.job_id) if row.job_id else None
    if status in ("queued", "running") and (not job or job.status == "failed"):
        status, error = "failed", job.error if job else "Auftrag nicht mehr verfügbar. Bitte neu vorbereiten."
    return {"id": row.id, "target_locale": row.target_locale, "title": row.title, "status": status,
            "pairs": row.pairs if status in ("review", "confirmed") else [], "error": error,
            "source_revisions": row.source_revisions, "collection_id": row.collection_id, "job_id": row.job_id,
            "supports_deferred_pairs": True}


@router.get("/language-capabilities")
def capabilities(p=Depends(authenticated)):
    return {"version": 1, "locales": s.TARGETS, "skills": sorted(s.SKILLS), "device_audio": True,
            "audio_assessment": False}


@router.post("/children/{child_id}/vocabulary/imports", status_code=201)
def create_import(child_id: str, data: s.ImportRequest, idempotency_key: str = KEY,
                  p=Depends(authenticated), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=p.user.role == "parent")
    lock_child(db, child)
    value = fingerprint(data.model_dump())
    existing = db.scalar(select(VocabularyImport).where(VocabularyImport.child_id == child.id,
                                                       VocabularyImport.request_key == idempotency_key))
    if existing:
        if existing.request_digest != value:
            raise HTTPException(409, "Dieser Importschlüssel wurde für andere Wörter verwendet.")
        return import_data(db, existing)
    rate_limit(db, "vocabulary-import:" + p.user.id, 20, 3600, commit=False)
    if db.get(Family, child.family_id).synthetic:
        raise HTTPException(403, "Eigene Wörter bitte im normalen Familienzugang anlegen; der Testraum hat feste Inhalte.")
    row = VocabularyImport(id=uid(), child_id=child.id, user_id=p.user.id, session_id=p.session.id,
                           request_key=idempotency_key, request_digest=value, target_locale=data.target_locale,
                           title=data.title.strip(), text=data.text, source_revisions=[],
                           pairs=[pair.model_dump() for pair in data.pairs], status="review")
    if data.material_id:
        material = db.get(Material, data.material_id)
        if not material or material.child_id != child.id:
            raise HTTPException(404, "Heftseite nicht gefunden.")
        if not material.confirmed or not material.content.strip() or material.synthetic:
            raise HTTPException(409, "Zuerst den erkannten Text der eigenen Seite bestätigen.")
        row.source_revisions = [{"id": material.id, "revision": material.revision}]
    db.add(row)
    db.flush()
    if not data.pairs:
        if db.scalar(select(Job.id).where(Job.child_id == child.id, Job.status.in_(["queued", "running"]))):
            raise HTTPException(409, "Eine Verarbeitung läuft noch. Bitte kurz warten.")
        job = Job(id=uid(), child_id=child.id, kind="vocabulary_import",
                  idempotency="vocabulary:" + fingerprint([child.id, idempotency_key]),
                  payload={"import_id": row.id, "family_id": child.family_id})
        db.add(job)
        db.flush()
        row.job_id, row.status = job.id, "queued"
        reserve(db, db.get(Family, child.family_id), child.id, job.id, "vocabulary_import")
    db.commit()
    return import_data(db, row)


@router.get("/children/{child_id}/vocabulary/imports")
def imports(child_id: str, p=Depends(authenticated), db=Depends(get_db)):
    child_access(db, p, child_id)
    return {"imports": [import_data(db, row) for row in db.scalars(select(VocabularyImport).where(
        VocabularyImport.child_id == child_id).order_by(VocabularyImport.created.desc(), VocabularyImport.id.desc()).limit(30))]}


@router.get("/children/{child_id}/vocabulary/imports/{import_id}")
def get_import(child_id: str, import_id: str, p=Depends(authenticated), db=Depends(get_db)):
    child_access(db, p, child_id)
    row = db.get(VocabularyImport, import_id)
    if not row or row.child_id != child_id:
        raise HTTPException(404, "Wortimport nicht gefunden.")
    return import_data(db, row)


def normalized(value):
    return " ".join(unicodedata.normalize("NFC", value).split())


def literal_present(text, value):
    """A quoted word is not merely a substring of another word/form."""
    value = normalized(value)
    if not value:
        return False
    prefix = r"(?<!\w)" if value[0].isalnum() else ""
    suffix = r"(?!\w)" if value[-1].isalnum() else ""
    return bool(re.search(prefix + re.escape(value) + suffix, normalized(text)))


def identity(locale, pair):
    # Meaning, context and POS are part of identity: bank (seat) != bank (money).
    return fingerprint([locale, *[normalized(getattr(pair, field)) for field in ("word", "meaning", "context", "part_of_speech")]])


def checked_pairs(pairs):
    for pair in pairs:
        if not pair.word.strip() or not pair.meaning.strip() or pair.uncertainty.strip():
            raise HTTPException(422, "Bitte fehlende Bedeutungen und unklare Stellen zuerst klären.")
        if normalized(pair.word).casefold() in ("bank", "bat", "light", "right", "match") and not pair.context.strip():
            raise HTTPException(422, "Dieses Wort hat mehrere Bedeutungen. Bitte einen konkreten Kontext ergänzen.")
        if any(not v.strip() or len(v) > 200 for v in [*pair.variants, *pair.meaning_variants]):
            raise HTTPException(422, "Antwortvarianten müssen ausdrücklich ausgefüllte Wörter oder Wendungen sein.")


@router.post("/children/{child_id}/vocabulary/imports/{import_id}/confirm")
def confirm_import(child_id: str, import_id: str, data: s.ImportConfirm,
                   p=Depends(authenticated), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=p.user.role == "parent")
    lock_child(db, child)
    row = db.get(VocabularyImport, import_id, populate_existing=True)
    result = confirm_import_record(db, p, child, row, data)
    db.commit()
    return result


def confirm_import_record(db, p, child, row, data):
    """Persist checked pairs in the caller's transaction, with Child locked."""
    if not row or row.child_id != child.id:
        raise HTTPException(404, "Wortimport nicht gefunden.")
    if row.target_locale != data.target_locale:
        raise HTTPException(409, "Die Lernsprache hat sich geändert. Bitte einen neuen Import beginnen.")
    pairs = [pair.model_dump() for pair in data.pairs]
    deferred = [pair.model_dump() for pair in data.deferred_pairs]
    pending = db.scalar(select(VocabularyImport).where(VocabularyImport.child_id == child.id,
        VocabularyImport.request_key == "deferred-" + row.id))
    if row.status == "confirmed":
        if row.pairs != pairs or (pending.request_digest if pending else fingerprint([])) != fingerprint(deferred):
            raise HTTPException(409, "Bereits bestätigte Wörter einzeln revisionsgebunden korrigieren.")
        return import_data(db, row)
    if row.status != "review":
        raise HTTPException(409, "Die Worterkennung ist noch nicht zum Prüfen bereit.")
    current_sources(db, child.id, row.source_revisions)
    checked_pairs(data.pairs)
    if {fingerprint(pair) for pair in pairs} & {fingerprint(pair) for pair in deferred}:
        raise HTTPException(422, "Ein Wort kann nicht zugleich bestätigt und zurückgestellt werden.")
    collection = VocabularyCollection(id=uid(), child_id=child.id, title=row.title, target_locale=row.target_locale)
    db.add(collection)
    db.flush()
    for pair in data.pairs:
        value = identity(row.target_locale, pair)
        source_text = normalized("\n".join(db.get(Material, source["id"]).content for source in row.source_revisions)
                                 if row.source_revisions else row.text)
        literal = literal_present(source_text, pair.word) and literal_present(source_text, pair.meaning)
        item = db.scalar(select(VocabularyItem).where(VocabularyItem.child_id == child.id, VocabularyItem.identity == value))
        if not item:
            item = VocabularyItem(id=uid(), child_id=child.id, identity=value, target_locale=row.target_locale,
                                  word=pair.word.strip(), meaning=pair.meaning.strip(), context=pair.context.strip(),
                                  part_of_speech=pair.part_of_speech.strip(), variants=pair.variants,
                                  meaning_variants=pair.meaning_variants,
                                  source_revisions=row.source_revisions, origin="material" if row.source_revisions and literal else "text" if row.text and literal else "manual",
                                  revision=1, confirmed=True, history=[])
            db.add(item)
            db.flush()
        else:
            variants = list(dict.fromkeys([*item.variants, *pair.variants]))
            meanings = list(dict.fromkeys([*item.meaning_variants, *pair.meaning_variants]))
            if len(variants) > 8 or len(meanings) > 8:
                raise HTTPException(422, "Bitte höchstens acht eindeutige Varianten je Wortseite bestätigen.")
            rebind = bool(row.source_revisions and literal and item.source_revisions != row.source_revisions)
            if rebind or variants != item.variants or meanings != item.meaning_variants:
                item.history = [*item.history, {"revision": item.revision, "word": item.word, "meaning": item.meaning,
                    "context": item.context, "part_of_speech": item.part_of_speech, "variants": item.variants,
                    "meaning_variants": item.meaning_variants, "source_revisions": item.source_revisions}]
                item.revision += 1
                item.variants, item.meaning_variants = variants, meanings
                if rebind:
                    item.source_revisions, item.origin = row.source_revisions, "material"
        if not db.get(VocabularyMembership, (collection.id, item.id)):
            db.add(VocabularyMembership(collection_id=collection.id, item_id=item.id))
        if p.user.role == "child":
            record(db, child.id, "vocabulary_exposure", {"item_id": item.id, "revision": item.revision, "via": "pair_confirmation"})
    row.collection_id, row.pairs, row.status = collection.id, pairs, "confirmed"
    if deferred:
        db.add(VocabularyImport(child_id=child.id, user_id=row.user_id, session_id=row.session_id,
            request_key="deferred-" + row.id, request_digest=fingerprint(deferred), target_locale=row.target_locale,
            title=row.title[:140] + " · später prüfen", text=row.text, source_revisions=row.source_revisions,
            pairs=deferred, status="review"))
    record(db, child.id, "vocabulary_confirmed", {"collection_id": collection.id, "count": len(data.pairs)})
    return import_data(db, row)


def item_data(db, item):
    changed = False
    try:
        current_sources(db, item.child_id, item.source_revisions)
    except HTTPException:
        changed = True
    cue_context = item.context
    for variant in sorted([item.word, *item.variants], key=len, reverse=True):
        cue_context = re.sub(r"(?<!\w)" + re.escape(variant) + r"(?!\w)", "___", cue_context, flags=re.IGNORECASE)
    return {"id": item.id, "word": item.word, "meaning": item.meaning, "context": item.context, "cue_context": cue_context,
            "part_of_speech": item.part_of_speech, "variants": item.variants, "meaning_variants": item.meaning_variants,
            "target_locale": item.target_locale,
            "revision": item.revision, "origin": item.origin, "confirmed": item.confirmed, "source_changed": changed,
            "source_revisions": item.source_revisions, "reviews": review.states(db, item)}


def item_query(child_id, locale=None, collection=None, search=None):
    query = select(VocabularyItem).where(VocabularyItem.child_id == child_id)
    if locale:
        query = query.where(VocabularyItem.target_locale == locale)
    if collection:
        query = query.join(VocabularyMembership).where(VocabularyMembership.collection_id == collection)
    if search:
        text = search.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        query = query.where(or_(VocabularyItem.word.ilike("%" + text + "%", escape="\\"),
                               VocabularyItem.meaning.ilike("%" + text + "%", escape="\\")))
    return query


@router.get("/children/{child_id}/vocabulary")
def listing(child_id: str, locale: str | None = None, collection: str | None = None,
            search: str | None = Query(None, max_length=100), due: bool = False,
            page: int = Query(1, ge=1, le=100000), page_size: int = Query(20, ge=1, le=50),
            p=Depends(authenticated), db=Depends(get_db)):
    child = child_access(db, p, child_id)
    query = item_query(child.id, locale, collection, search)
    if due:
        query = query.where(or_(~select(VocabularyReview.id).where(
            VocabularyReview.item_id == VocabularyItem.id, VocabularyReview.revision == VocabularyItem.revision,
            VocabularyReview.direction == "de_to_target", VocabularyReview.skill == "spelling").exists(),
            ~select(VocabularyReview.id).where(VocabularyReview.item_id == VocabularyItem.id,
                VocabularyReview.revision == VocabularyItem.revision, VocabularyReview.direction == "target_to_de",
                VocabularyReview.skill == "recognition").exists(),
            select(VocabularyReview.id).where(VocabularyReview.item_id == VocabularyItem.id,
                VocabularyReview.revision == VocabularyItem.revision, VocabularyReview.due <= review.local_day(child).isoformat()).exists()))
    total = db.scalar(select(func.count()).select_from(query.subquery()))
    rows = list(db.scalars(query.order_by(VocabularyItem.created.desc(), VocabularyItem.id).offset((page - 1) * page_size).limit(page_size)))
    open_rounds = list(db.scalars(select(LearningUnit).where(LearningUnit.child_id == child.id,
        LearningUnit.round_kind == "vocabulary", LearningUnit.status != "completed")
        .order_by(LearningUnit.created.desc(), LearningUnit.id).limit(8)))
    return {"child": {"id": child.id, "display_name": db.get(User, child.user_id).display_name},
            "items": [item_data(db, row) for row in rows], "pagination": {"page": page, "page_size": page_size, "total": total},
            "open_rounds": [{"id": unit.id, "topic": unit.topic, "status": unit.status} for unit in open_rounds],
            "collections": [{"id": row.id, "title": row.title, "target_locale": row.target_locale} for row in db.scalars(
                select(VocabularyCollection).where(VocabularyCollection.child_id == child.id).order_by(VocabularyCollection.created.desc(), VocabularyCollection.id))],
            "summary": summary(db, child)}


@router.put("/children/{child_id}/vocabulary/{item_id}")
def edit(child_id: str, item_id: str, data: s.ItemUpdate, p=Depends(authenticated), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=p.user.role == "parent")
    lock_child(db, child)
    rate_limit(db, "vocabulary-edit:" + p.user.id, 60, 3600, commit=False)
    item = db.get(VocabularyItem, item_id, populate_existing=True)
    if not item or item.child_id != child.id:
        raise HTTPException(404, "Wort nicht gefunden.")
    if item.revision != data.revision:
        raise HTTPException(409, "Das Wort wurde inzwischen geändert. Bitte neu laden.")
    checked_pairs([data])
    value = identity(item.target_locale, data)
    other = db.scalar(select(VocabularyItem.id).where(VocabularyItem.child_id == child.id, VocabularyItem.identity == value, VocabularyItem.id != item.id))
    if other:
        raise HTTPException(409, "Dieser Eintrag ist bereits vorhanden. Unterschiedliche Bedeutungen mit Kontext trennen.")
    item.history = [*item.history, {"revision": item.revision, "word": item.word, "meaning": item.meaning,
                                  "context": item.context, "part_of_speech": item.part_of_speech,
                                  "variants": item.variants, "meaning_variants": item.meaning_variants, "source_revisions": item.source_revisions}]
    # A deliberate correction is its own confirmed manual revision. Existing
    # begun rounds keep their saved snapshot; new rounds use this revision.
    for field in ("word", "meaning", "context", "part_of_speech", "variants", "meaning_variants"):
        setattr(item, field, getattr(data, field))
    item.revision += 1
    item.identity, item.confirmed, item.origin, item.source_revisions = value, True, "manual", []
    if p.user.role == "child":
        record(db, child.id, "vocabulary_exposure", {"item_id": item.id, "revision": item.revision, "via": "correction"})
    db.commit()
    return item_data(db, item)


def summary(db, child):
    items = list(db.execute(select(VocabularyItem.id, VocabularyItem.target_locale).where(
        VocabularyItem.child_id == child.id, VocabularyItem.confirmed.is_(True))))
    today = review.local_day(child).isoformat()
    rows = list(db.scalars(select(VocabularyReview).join(VocabularyItem).where(
        VocabularyReview.child_id == child.id, VocabularyReview.revision == VocabularyItem.revision)))
    due_ids = {row.item_id for row in rows if row.due <= today}
    practiced_ids = {row.item_id for row in rows}
    missing_spelling = {item.id for item in items} - {row.item_id for row in rows if row.skill == "spelling" and row.direction == "de_to_target"}
    missing_recognition = {item.id for item in items} - {row.item_id for row in rows if row.skill == "recognition" and row.direction == "target_to_de"}
    by_locale = [{"locale": locale, "subject": s.TARGETS[locale].split(" · ")[0],
                  "due_words": sum(item.id in due_ids for item in items if item.target_locale == locale),
                  "new_words": sum(item.id not in practiced_ids for item in items if item.target_locale == locale),
                  "unpracticed_skills": sum(item.id in missing_spelling | missing_recognition for item in items if item.target_locale == locale)}
                 for locale in sorted({item.target_locale for item in items})]
    return {"confirmed_words": len(items), "due_words": len(due_ids), "by_locale": by_locale,
            "new_words": len({item.id for item in items} - {row.item_id for row in rows}),
            "skills": [{"direction": direction, "skill": skill, "practiced_words": len(group),
                        "unpracticed_words": len(items) - len(group),
                        "due_words": sum(row.due <= today for row in group),
                        "needs_clarification": sum(row.needs_clarification for row in group)}
                       for direction, skill in sorted({(row.direction, row.skill) for row in rows}
                         | ({("de_to_target", "spelling"), ("target_to_de", "recognition")} if items else set()))
                       for group in [[row for row in rows if row.direction == direction and row.skill == skill]]]}


def task_for(item, data, index, alternatives):
    reverse = data.direction == "target_to_de"
    expected = item.meaning if reverse else item.word
    cue = item.word if reverse else item.meaning
    context_text = item.context
    hidden = [item.meaning, *item.meaning_variants] if reverse else [item.word, *item.variants]
    if data.skill == "listening":
        hidden.extend([item.word, *item.variants])
    for value in sorted(hidden, key=len, reverse=True):
        context_text = re.sub(r"(?<!\w)" + re.escape(value) + r"(?!\w)", "___", context_text, flags=re.IGNORECASE)
    kind = {"recognition": "meaning_choice", "recall": "recall", "spelling": "spelling", "listening": "listening"}[data.skill]
    if data.skill == "recognition" and not reverse:
        raise HTTPException(422, "Bedeutung erkennen übt Lernsprache → Deutsch. Für die Gegenrichtung Wortabruf wählen.")
    if data.skill == "listening" and not reverse:
        raise HTTPException(422, "Hören übt Lernsprache → Deutsch. Für Englisch schreiben die Schreibübung wählen.")
    policy = s.EvaluationPolicy(criterion={"recognition": "meaning", "recall": "meaning", "spelling": "spelling", "listening": "listening"}[data.skill],
                                case_sensitive=data.skill == "spelling" or not reverse, apostrophe_equivalent=True,
                                sentence_initial_optional=not reverse and item.target_locale in ("en-GB", "en-US"))
    meta = s.LanguageTask(target_locale=item.target_locale, answer_locale="de-DE" if reverse else item.target_locale,
        task_kind=kind, skill=data.skill, direction=data.direction, vocabulary_item_id=item.id, vocabulary_revision=item.revision,
        source_revisions=item.source_revisions, evaluation_policy=policy, stimulus=item.word if data.skill == "listening" else "",
        cue="" if data.skill == "listening" else cue, cue_locale=item.target_locale if reverse else "de-DE", context=context_text)
    from .language_evaluation import canonical

    correct_meanings = {canonical(value, policy) for value in [expected, *item.meaning_variants]}
    options = sorted({other.meaning for other in alternatives if canonical(other.meaning, policy) not in correct_meanings})[:3] + [expected]
    if data.skill == "recognition" and len(options) < 2:
        raise HTTPException(409, "Für eine Bedeutungsauswahl sind mindestens zwei verschiedene bestätigte Bedeutungen nötig. Du kannst Wörter schreiben üben.")
    options.sort(key=lambda word: fingerprint([item.id, index, word]))
    return {"id": "v" + str(index + 1), "type": "choice" if data.skill == "recognition" else "short",
            "prompt": ("Höre zu. Was bedeutet das Wort auf Deutsch?" if data.skill == "listening" else
                       "Was bedeutet dieses Wort auf Deutsch?" if reverse else f"Schreibe das Wort aus deinem Heft auf {s.TARGETS[item.target_locale].split(' · ')[0]}:"),
            "options": options if data.skill == "recognition" else [], "answer": expected,
            "accepted": [] if data.skill == "recognition" else item.meaning_variants if reverse else item.variants,
            "hints": [f"Gesucht ist {'die deutsche Bedeutung' if reverse else 'das Wort für „' + item.meaning + '“'}." + (f" Denk an: {context_text}" if context_text else ""),
                      f"Die Antwort beginnt mit „{expected[0]}“ und besteht aus {len(expected.split())} {'Wort' if len(expected.split()) == 1 else 'Wörtern'}."],
            "explanation": f"{item.word} bedeutet hier: {item.meaning}.", "language": meta.model_dump(),
            "language_feedback": [{"locale": item.target_locale, "text": item.word}, {"locale": "de-DE", "text": item.meaning}]}


@router.post("/children/{child_id}/vocabulary/rounds", status_code=201)
def create_round(child_id: str, data: s.RoundRequest, idempotency_key: str = KEY,
                 p=Depends(child_user), db=Depends(get_db)):
    child = child_access(db, p, child_id)
    lock_child(db, child)
    value = fingerprint(data.model_dump())
    old = db.scalar(select(VocabularyAction).where(VocabularyAction.child_id == child.id, VocabularyAction.request_key == idempotency_key))
    if old:
        if old.request_digest != value:
            raise HTTPException(409, "Dieser Rundenschlüssel gehört zu einer anderen Auswahl.")
        return {"unit_id": old.unit_id}
    rate_limit(db, "vocabulary-round:" + p.user.id, 30, 3600, commit=False)
    items = list(db.scalars(item_query(child.id, data.target_locale, data.collection_id).where(VocabularyItem.confirmed.is_(True))
                           .order_by(VocabularyItem.created, VocabularyItem.id)))
    item_ids = {item.id: item.revision for item in items}
    for unit in db.scalars(select(LearningUnit).where(LearningUnit.child_id == child.id,
            LearningUnit.round_kind == "vocabulary", LearningUnit.provider == "vocabulary", LearningUnit.status != "completed")
            .order_by(LearningUnit.created, LearningUnit.id)):
        if unit.questions and all(q.get("language", {}).get("skill") == data.skill
            and q["language"]["direction"] == data.direction
            and item_ids.get(q["language"]["vocabulary_item_id"]) == q["language"]["vocabulary_revision"] for q in unit.questions):
            try:
                current_sources(db, child.id, [{"id": row.material_id, "revision": row.revision} for row in db.scalars(
                    select(UnitSource).where(UnitSource.unit_id == unit.id))])
            except HTTPException:
                continue
            db.add(VocabularyAction(child_id=child.id, request_key=idempotency_key, request_digest=value, unit_id=unit.id))
            db.commit()
            return {"unit_id": unit.id, "resumed": True}
    eligible = []
    for item in items:
        current_sources(db, child.id, item.source_revisions)
        state = db.scalar(select(VocabularyReview).where(VocabularyReview.item_id == item.id, VocabularyReview.revision == item.revision,
            VocabularyReview.direction == data.direction, VocabularyReview.skill == data.skill))
        if data.voluntary or not state or state.due <= review.local_day(child).isoformat():
            eligible.append(((0 if state and state.due <= review.local_day(child).isoformat() else 1 if not state else 2,
                              state.due if state else ""), item.id, item))
    selected = [row[2] for row in sorted(eligible, key=lambda row: row[:2])[:data.count]]
    if not selected:
        raise HTTPException(409, "Für diese Fähigkeit ist gerade nichts fällig. Du kannst bewusst eine zusätzliche Runde wählen.")
    unit = LearningUnit(id=uid(), child_id=child.id, subject=s.TARGETS[data.target_locale].split(" · ")[0],
        topic="Mein Wortschatz", explanation="Rufe die Wörter aus deinem eigenen Wortschatz ab. Du erhältst nach jeder Antwort eine Rückmeldung.",
        questions=[task_for(item, data, index, items) for index, item in enumerate(selected)],
        estimated_minutes=min(8, max(2, len(selected))), round_kind="vocabulary", provider="vocabulary", model="confirmed-words-v1",
        introduction_seen=True, synthetic=False)
    db.add(unit)
    db.flush()
    sources = {source["id"]: source["revision"] for item in selected for source in item.source_revisions}
    for material_id, revision in sorted(sources.items()):
        db.add(UnitSource(unit_id=unit.id, material_id=material_id, revision=revision))
    db.add(VocabularyAction(child_id=child.id, request_key=idempotency_key, request_digest=value, unit_id=unit.id))
    record(db, child.id, "vocabulary_round", {"count": len(selected), "skill": data.skill, "direction": data.direction}, unit.id)
    db.commit()
    return {"unit_id": unit.id}


def context(db, row):
    current_sources(db, row.child_id, row.source_revisions)
    content = "\n\n".join(db.get(Material, source["id"]).content for source in row.source_revisions) if row.source_revisions else row.text
    return {"target_locale": row.target_locale, "confirmed_text": content}


def authority(db, row, family_id):
    session = db.get(Session, row.session_id) if row.session_id else None
    user = db.get(User, row.user_id)
    if not session or session.revoked or session.expires <= now() or now() - session.seen > 7 * 86400 or not user or user.disabled or not user.verified:
        raise HTTPException(401, "Dieser Zugang wurde abgemeldet. Bitte nach der Anmeldung neu vorbereiten.")
    child = child_access(db, Principal(user, session), row.child_id, write=user.role == "parent")
    if child.family_id != family_id or db.get(Family, family_id).synthetic:
        raise HTTPException(403, "Die Familienberechtigung hat sich geändert.")
    from .commerce import usage_terms

    usage_terms(db, db.get(Family, family_id), enforce=True)
    return child


def process(job_id):
    result = None
    try:
        with DB() as db:
            job = db.get(Job, job_id)
            if not job or job.status != "running":
                return
            row = db.get(VocabularyImport, job.payload["import_id"])
            if not row or row.job_id != job.id:
                raise ProviderError("Wortimport nicht mehr vorhanden.")
            authority(db, row, job.payload["family_id"])
            payload = context(db, row)
            signature = fingerprint([payload, db.get(Child, row.child_id).preferences])
            config = config_for_function(db.get(ProviderConfig, 1), "vocabulary_import")
            usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
            if not usage or (usage.provider, usage.model, usage.config_revision) != (config.provider, config.model, config.revision):
                raise ProviderError("Die KI-Einstellung wurde geändert. Bitte neu vorbereiten.")
            external_allowed(config)
            values = {c.name: getattr(config, c.name) for c in ProviderConfig.__table__.columns}
            row.status = "running"
            db.commit()
        result = request_provider(ProviderConfig(**values), "vocabulary_import", payload)
        output = s.VocabularyOutput.model_validate(result.data)
        for pair in output.pairs:
            # Only literal pairs may be proposed as extracted vocabulary. A
            # missing meaning stays empty, never dictionary/web-completed.
            if not literal_present(payload["confirmed_text"], pair.word) or (pair.meaning and not literal_present(payload["confirmed_text"], pair.meaning)):
                raise ProviderError("Der Wortvorschlag enthält Wörter oder Bedeutungen, die nicht im bestätigten Text stehen.")
            if any(value and not literal_present(payload["confirmed_text"], value) for value in (pair.context, pair.part_of_speech)):
                raise ProviderError("Kontext oder Wortart sind nicht im bestätigten Text belegt. Bitte manuell bestätigen.")
            if pair.variants or pair.meaning_variants:
                raise ProviderError("Zusätzliche Wortformen müssen ausdrücklich bestätigt werden; der Import ergänzt keine Formen.")
            if pair.meaning and not any(normalized(pair.word) in normalized(line) and normalized(pair.meaning) in normalized(line)
                                        for line in payload["confirmed_text"].splitlines() if len(line) <= 700):
                pair.uncertainty = (pair.uncertainty + " Zuordnung auf der Heftseite bitte ausdrücklich prüfen.").strip()[:500]
        with DB.begin() as db:
            job = db.get(Job, job_id)
            if not job or job.status != "running":
                return
            lock_child(db, db.get(Child, job.child_id))
            row = db.get(VocabularyImport, job.payload["import_id"], populate_existing=True)
            if not row:
                raise ProviderError("Wortimport wurde gelöscht.")
            authority(db, row, job.payload["family_id"])
            if signature != fingerprint([context(db, row), db.get(Child, row.child_id).preferences]):
                raise ProviderError("Die Quelle wurde während der Verarbeitung geändert.")
            config = config_for_function(db.get(ProviderConfig, 1), "vocabulary_import")
            usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
            if not usage or (usage.provider, usage.model, usage.config_revision) != (config.provider, config.model, config.revision):
                raise ProviderError("Die KI-Einstellung wurde während der Verarbeitung geändert.")
            external_allowed(config)
            row.status, row.pairs, row.error = "review", output.model_dump()["pairs"], None
            job.status, job.finished, job.result = "completed", int(now()), {"import_id": row.id}
            settle(db, usage, result)
    except Exception as error:
        reason = str(error.detail) if isinstance(error, HTTPException) else str(error) if isinstance(error, ProviderError) else "Die Wörter konnten nicht sicher erkannt werden. Bitte manuell prüfen oder neu vorbereiten."
        with DB.begin() as db:
            job = db.get(Job, job_id)
            if not job or job.status != "running":
                return
            job.status, job.finished, job.error = "failed", int(now()), reason[:500]
            row = db.get(VocabularyImport, job.payload.get("import_id"))
            if row:
                row.status, row.error = "failed", reason[:500]
            usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
            if usage:
                settle(db, usage, result, failed=True)


def purge_sources(db, material_ids, child_id):
    ids = set(material_ids)
    from .db import LanguageProject

    for model in (VocabularyImport, VocabularyItem, LanguageProject):
        for row in db.scalars(select(model).where(model.child_id == child_id)):
            historical = [source for version in getattr(row, "history", []) for source in version.get("source_revisions", [])]
            if any(source["id"] in ids for source in [*row.source_revisions, *historical]):
                db.delete(row)
    # Preserve generated units/immutable answers under the existing private
    # learning-history retention policy. Deleting a source is not deletion of
    # the learning history. JSON snapshots still block further source use.


@router.post("/children/{child_id}/vocabulary/{item_id}/reveal")
def reveal(child_id: str, item_id: str, p=Depends(child_user), db=Depends(get_db)):
    child = child_access(db, p, child_id)
    lock_child(db, child)
    rate_limit(db, "vocabulary-reveal:" + p.user.id, 120, 3600, commit=False)
    item = db.get(VocabularyItem, item_id)
    if not item or item.child_id != child.id:
        raise HTTPException(404, "Wort nicht gefunden.")
    record(db, child.id, "vocabulary_exposure", {"item_id": item.id, "revision": item.revision, "via": "card"})
    db.commit()
    return {"word": item.word, "meaning": item.meaning, "context": item.context}


@router.delete("/children/{child_id}/vocabulary/{item_id}")
def delete_item(child_id: str, item_id: str, p=Depends(authenticated), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=p.user.role == "parent")
    lock_child(db, child)
    rate_limit(db, "vocabulary-delete:" + p.user.id, 60, 3600, commit=False)
    item = db.get(VocabularyItem, item_id)
    if not item or item.child_id != child.id:
        raise HTTPException(404, "Wort nicht gefunden.")
    db.delete(item)
    db.commit()
    return {"message": "Wort und Wiederholungszustand gelöscht. Bereits abgegebene Antworten bleiben im Lernverlauf."}


@router.post("/units/{unit_id}/questions/{question_id}/language-stimulus")
def stimulus(unit_id: str, question_id: str, data: s.StimulusRequest,
             p=Depends(child_user), db=Depends(get_db)):
    from .learning import get_unit, learning_block, question

    unit = get_unit(db, p, unit_id, True, True)
    q = question(unit, question_id)
    if not q.get("language") or unit.status != "active":
        raise HTTPException(409, "Bitte die Sprachrunde zuerst starten.")
    if reason := learning_block(db, unit):
        raise HTTPException(409, reason)
    child = db.get(Child, unit.child_id)
    lock_child(db, child)
    rate_limit(db, "language-stimulus:" + p.user.id, 120, 3600, commit=False)
    task = q["language"]
    if data.kind == "listen" and task["skill"] != "listening":
        raise HTTPException(422, "Diese Aufgabe ist keine Hörübung.")
    detail = {"question_id": question_id, "kind": data.kind, "item_id": task["vocabulary_item_id"]}
    record(db, unit.child_id, "language_stimulus", detail, unit.id)
    if data.kind in ("solution", "word_bank", "speech_input"):
        record(db, unit.child_id, "hint", {**detail, "text": "Sprachhilfe verwendet"}, unit.id)
        record(db, unit.child_id, "vocabulary_exposure", detail, unit.id)
    db.commit()
    bank = []
    if data.kind == "word_bank":
        tokens = list(q["answer"]) if len(q["answer"]) <= 25 and " " not in q["answer"] else q["answer"].split()
        bank = [token for _, token in sorted((fingerprint([q["id"], index, token]), token) for index, token in enumerate(tokens))]
    return {"recorded": True, "solution": q["answer"] if data.kind == "solution" else None, "word_bank": bank,
            "joiner": "" if " " not in q["answer"] and len(q["answer"]) <= 25 else " "}
