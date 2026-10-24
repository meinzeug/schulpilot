"""Private, source-bound school vocabulary on the existing queue and attempts."""

import json
import re
import unicodedata
from typing import Literal

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from pydantic import Field
from sqlalchemy import and_, func, or_, select, update

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
from .model_routing import job_config
from .providers import ProviderError, external_allowed, request_provider, reserve, settle
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
        if (not material or material.child_id != child_id or not material.confirmed
                or material.purpose == "exam" or material.revision != source["revision"]):
            raise HTTPException(409, "Die Heftseite wurde geändert. Bitte Wörter aus der aktuellen Seite neu bestätigen.")


def import_data(db, row):
    status, error = row.status, row.error
    job = db.get(Job, row.job_id) if row.job_id else None
    if status in ("queued", "running") and (not job or job.status == "failed"):
        status, error = "failed", job.error if job else "Auftrag nicht mehr verfügbar. Bitte neu vorbereiten."
    return {"id": row.id, "target_locale": row.target_locale, "title": row.title, "status": status,
            "pairs": row.pairs if status in ("review", "confirmed") else [], "error": error,
            "source_revisions": row.source_revisions, "collection_id": row.collection_id, "job_id": row.job_id,
            "supports_deferred_pairs": True, "supports_import_discard": True}


@router.get("/language-capabilities")
def capabilities(p=Depends(authenticated)):
    return {"version": 1, "locales": s.TARGETS, "skills": sorted(s.SKILLS), "device_audio": True,
            "audio_assessment": False}


@router.post("/children/{child_id}/vocabulary/imports", status_code=201)
def create_import(child_id: str, data: s.ImportRequest, idempotency_key: str = KEY,
                  p=Depends(authenticated), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=p.user.role == "parent")
    lock_child(db, child)
    import_payload = data.model_dump()
    if import_payload.get("collection_id") is None:
        import_payload.pop("collection_id", None)  # Keep old request fingerprints stable.
    value = fingerprint(import_payload)
    existing = db.scalar(select(VocabularyImport).where(VocabularyImport.child_id == child.id,
                                                       VocabularyImport.request_key == idempotency_key))
    if existing:
        if existing.request_digest != value:
            raise HTTPException(409, "Dieser Importschlüssel wurde für andere Wörter verwendet.")
        return import_data(db, existing)
    if data.collection_id:
        target = own_collection(db, child, data.collection_id)
        if target.target_locale != data.target_locale:
            raise HTTPException(422, "Sammlung und Wörter müssen dieselbe bestätigte Lernsprache haben.")
    rate_limit(db, "vocabulary-import:" + p.user.id, 20, 3600, commit=False)
    if db.get(Family, child.family_id).synthetic:
        raise HTTPException(403, "Eigene Wörter bitte im normalen Familienzugang anlegen; der Testraum hat feste Inhalte.")
    row = VocabularyImport(id=uid(), child_id=child.id, user_id=p.user.id, session_id=p.session.id,
                           request_key=idempotency_key, request_digest=value, target_locale=data.target_locale,
                           title=data.title.strip(), collection_id=data.collection_id, text=data.text, source_revisions=[],
                           pairs=[pair.model_dump() for pair in data.pairs], status="review")
    if data.material_id:
        material = db.get(Material, data.material_id)
        if not material or material.child_id != child.id:
            raise HTTPException(404, "Heftseite nicht gefunden.")
        if material.purpose == "exam" or not material.confirmed or not material.content.strip() or material.synthetic:
            raise HTTPException(409, "Zuerst den erkannten Text der eigenen Seite bestätigen.")
        row.source_revisions = [{"id": material.id, "revision": material.revision}]
    if not data.pairs:
        context(db, row)  # Reject unusable selected sources before queue/reservation.
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
def imports(child_id: str, status: Literal["all", "open", "review", "failed", "confirmed"] = "all",
            search: str = Query("", max_length=100), page: int = Query(1, ge=1, le=100000),
            page_size: int = Query(30, ge=1, le=50), compact: bool = False, p=Depends(authenticated), db=Depends(get_db)):
    child_access(db, p, child_id)
    query = select(VocabularyImport).where(VocabularyImport.child_id == child_id)
    if status == "open":
        query = query.where(VocabularyImport.status != "confirmed")
    elif status == "failed":
        viable_job = select(Job.id).where(Job.id == VocabularyImport.job_id, Job.status != "failed").exists()
        query = query.where(or_(VocabularyImport.status == "failed", and_(VocabularyImport.status.in_(["queued", "running"]), ~viable_job)))
    elif status != "all":
        query = query.where(VocabularyImport.status == status)
    if search:
        escaped = search.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        query = query.where(VocabularyImport.title.ilike("%"+escaped+"%", escape="\\"))
    total = db.scalar(select(func.count()).select_from(query.subquery()))
    actual = min(page, max(1, (total + page_size - 1) // page_size))
    rows = db.scalars(query.order_by(VocabularyImport.created.desc(), VocabularyImport.id.desc()).offset((actual-1)*page_size).limit(page_size))
    open_total = db.scalar(select(func.count()).select_from(VocabularyImport).where(VocabularyImport.child_id == child_id, VocabularyImport.status != "confirmed"))
    def value(row):
        data = import_data(db, row)
        if compact:
            data["pair_count"] = len(data.pop("pairs"))
        return data
    return {"imports": [value(row) for row in rows], "open_total": open_total, "compact": compact,
            "pagination": {"page": actual, "page_size": page_size, "total": total},
            "filters": {"status": status, "search": search}, "supports_import_browser": True}


@router.get("/children/{child_id}/vocabulary/imports/{import_id}")
def get_import(child_id: str, import_id: str, p=Depends(authenticated), db=Depends(get_db)):
    child_access(db, p, child_id)
    row = db.get(VocabularyImport, import_id)
    if not row or row.child_id != child_id:
        raise HTTPException(404, "Wortimport nicht gefunden.")
    return import_data(db, row)


@router.delete("/children/{child_id}/vocabulary/imports/{import_id}")
def discard_import(child_id: str, import_id: str, p=Depends(authenticated), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=p.user.role == "parent")
    lock_child(db, child)
    child = child_access(db, p, child_id, write=p.user.role == "parent")
    row = db.get(VocabularyImport, import_id, populate_existing=True)
    if not row:
        return {"message": "Die Wortvorschläge sind nicht mehr offen."}
    if row.child_id != child.id:
        raise HTTPException(404, "Wortvorschläge nicht gefunden.")
    job = db.get(Job, row.job_id) if row.job_id else None
    if row.status != "review" or (job and job.status in ("queued", "running")):
        raise HTTPException(409, "Nur noch nicht übernommene Wortvorschläge können verworfen werden. Laufende Erkennungen und gespeicherte Wörter bleiben geschützt.")
    rate_limit(db, "vocabulary-discard:" + p.user.id, 30, 3600, commit=False)
    db.delete(row)
    db.commit()
    return {"message": "Nur offene Wortvorschläge verworfen. Heftseite, Wortschatz und Übungsbelege bleiben erhalten."}


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
    if row.collection_id:
        collection = own_collection(db, child, row.collection_id)
        if collection.target_locale != row.target_locale:
            raise HTTPException(409, "Die Lernsprache der Sammlung stimmt nicht mehr überein.")
    else:
        collection = VocabularyCollection(id=uid(), child_id=child.id, title=row.title, target_locale=row.target_locale)
        db.add(collection)
        db.flush()
    from .source_lineage import learning_source

    source_text = normalized("\n".join(learning_source(db, db.get(Material, source["id"]))["content"]
                                        for source in row.source_revisions) if row.source_revisions else row.text)
    for pair in data.pairs:
        value = identity(row.target_locale, pair)
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
            title=row.title[:140] + " · später prüfen", collection_id=collection.id, text=row.text, source_revisions=row.source_revisions,
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
            "source_revisions": item.source_revisions, "collection_ids": sorted(db.scalars(select(VocabularyMembership.collection_id).join(VocabularyCollection, VocabularyMembership.collection_id == VocabularyCollection.id).where(VocabularyMembership.item_id == item.id, VocabularyCollection.child_id == item.child_id))), "reviews": review.states(db, item)}


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
            sort: Literal["newest", "word", "meaning"] = "newest",
            origin: Literal["manual", "material", "text"] | None = None,
            clarification: bool = False, search_context: bool = False,
            page: int = Query(1, ge=1, le=100000), page_size: int = Query(20, ge=1, le=50),
            p=Depends(authenticated), db=Depends(get_db)):
    child = child_access(db, p, child_id)
    query = item_query(child.id, locale, collection, None if search_context else search)
    if search_context and search:
        escaped = search.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        query = query.where(VocabularyItem.context.ilike("%" + escaped + "%", escape="\\"))
    if origin is not None:
        query = query.where(VocabularyItem.origin == origin)
    if clarification:
        query = query.where(select(VocabularyReview.id).where(
            VocabularyReview.item_id == VocabularyItem.id, VocabularyReview.revision == VocabularyItem.revision,
            VocabularyReview.needs_clarification.is_(True)).exists())
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
    actual_page = min(page, max(1, (total + page_size - 1) // page_size))
    ordering = {"newest": VocabularyItem.created.desc(), "word": func.lower(VocabularyItem.word),
                "meaning": func.lower(VocabularyItem.meaning)}[sort]
    rows = list(db.scalars(query.order_by(ordering, VocabularyItem.id).offset((actual_page - 1) * page_size).limit(page_size)))
    open_rounds = list(db.scalars(select(LearningUnit).where(LearningUnit.child_id == child.id,
        LearningUnit.round_kind == "vocabulary", LearningUnit.status != "completed")
        .order_by(LearningUnit.created.desc(), LearningUnit.id).limit(8)))
    collections_query = select(VocabularyCollection).where(VocabularyCollection.child_id == child.id)
    if locale:
        collections_query = collections_query.where(VocabularyCollection.target_locale == locale)
    collection_total = db.scalar(select(func.count()).select_from(collections_query.subquery()))
    collection_rows = list(db.scalars(collections_query.order_by(VocabularyCollection.created.desc(), VocabularyCollection.id).limit(80)))
    if collection and not any(row.id == collection for row in collection_rows):
        chosen = db.get(VocabularyCollection, collection)
        if chosen and chosen.child_id == child.id and (not locale or chosen.target_locale == locale):
            collection_rows.append(chosen)
    return {"child": {"id": child.id, "display_name": db.get(User, child.user_id).display_name},
            "items": [item_data(db, row) for row in rows], "pagination": {"page": actual_page, "page_size": page_size, "total": total},
            "filters": {"sort": sort, "origin": origin, "clarification": clarification, "search_context": search_context},
            "open_rounds": [{"id": unit.id, "topic": unit.topic, "status": unit.status} for unit in open_rounds],
            "supports_import_browser": True, "supports_collections": True, "collections_total": collection_total, "collections": [collection_data(db, row) for row in collection_rows],
            "summary": summary(db, child), "locale_summary": summary(db, child, locale)}


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


def summary(db, child, locale=None):
    items = list(db.execute(select(VocabularyItem.id, VocabularyItem.target_locale).where(
        VocabularyItem.child_id == child.id, VocabularyItem.confirmed.is_(True))))
    if locale is not None:
        items = [item for item in items if item.target_locale == locale]
    today = review.local_day(child).isoformat()
    rows = list(db.scalars(select(VocabularyReview).join(VocabularyItem).where(
        VocabularyReview.child_id == child.id, VocabularyItem.child_id == child.id, VocabularyItem.confirmed.is_(True), VocabularyReview.revision == VocabularyItem.revision)))
    if locale is not None:
        item_ids = {item.id for item in items}
        rows = [row for row in rows if row.item_id in item_ids]
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
    from .learning_sources import current_values

    content = "\n\n".join(value["content"] for value in current_values(db, row.child_id, row.source_revisions)) if row.source_revisions else row.text
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
    from .learning_sources import failure_billing

    result = None
    provider_requested = False
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
            config = job_config(db, job, "vocabulary_import")
            usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
            if not usage or (usage.provider, usage.model, usage.config_revision) != (config.provider, config.model, config.revision):
                raise ProviderError("Die KI-Einstellung wurde geändert. Bitte neu vorbereiten.")
            external_allowed(config)
            values = {c.name: getattr(config, c.name) for c in ProviderConfig.__table__.columns}
            row.status = "running"
            db.commit()
        provider_requested = True
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
            config = job_config(db, job, "vocabulary_import")
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
                settle(db, usage, failure_billing(result, error, provider_requested=provider_requested), failed=True)


def purge_sources(db, material_ids, child_id):
    ids = set(material_ids)
    from .db import LanguageProject

    for model in (VocabularyImport, VocabularyItem, LanguageProject):
        for row in db.scalars(select(model).where(model.child_id == child_id)):
            historical = [source for version in getattr(row, "history", []) for source in version.get("source_revisions", [])]
            if any(source["id"] in ids for source in [*row.source_revisions, *historical]):
                db.delete(row)
    # Page-erasure callers remove linked rounds before purging these source
    # snapshots. Word-only deletion keeps its separate history policy.


@router.post("/children/{child_id}/vocabulary/{item_id}/reveal")
def reveal(child_id: str, item_id: str, revision: int | None = Query(None, ge=1),
           p=Depends(child_user), db=Depends(get_db)):
    child = child_access(db, p, child_id)
    lock_child(db, child)
    rate_limit(db, "vocabulary-reveal:" + p.user.id, 120, 3600, commit=False)
    item = db.get(VocabularyItem, item_id)
    if not item or item.child_id != child.id:
        raise HTTPException(404, "Wort nicht gefunden.")
    if revision is not None and item.revision != revision:
        raise HTTPException(409, "Das Wort wurde geändert. Bitte lade die aktuelle Karte neu, bevor du sie aufdeckst oder anhörst.")
    record(db, child.id, "vocabulary_exposure", {"item_id": item.id, "revision": item.revision, "via": "card"})
    db.commit()
    return {"word": item.word, "meaning": item.meaning, "context": item.context}


@router.delete("/children/{child_id}/vocabulary/{item_id}")
def delete_item(child_id: str, item_id: str, revision: int | None = Query(None, ge=1),
                p=Depends(authenticated), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=p.user.role == "parent")
    lock_child(db, child)
    rate_limit(db, "vocabulary-delete:" + p.user.id, 60, 3600, commit=False)
    item = db.get(VocabularyItem, item_id)
    if not item or item.child_id != child.id:
        raise HTTPException(404, "Wort nicht gefunden.")
    if revision is not None and item.revision != revision:
        raise HTTPException(409, "Das Wort wurde inzwischen geändert. Bitte die aktuelle Fassung erneut prüfen.")
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


class CollectionDraft(s.Strict):
    title: str = Field(min_length=1, max_length=160)
    target_locale: s.TargetLocale


class CollectionName(s.Strict):
    title: str = Field(min_length=1, max_length=160)
    expected_title: str = Field(min_length=1, max_length=160)


class CollectionErase(s.Strict):
    snapshot: str = Field(min_length=64, max_length=64, pattern=r"^[a-f0-9]+$")


class CollectionChoices(s.Strict):
    revision: int = Field(ge=1)
    collection_ids: list[str] = Field(max_length=80)
    expected_collection_ids: list[str] = Field(max_length=80)


def collection_data(db, row):
    ids = sorted(db.scalars(select(VocabularyMembership.item_id).join(VocabularyItem, VocabularyMembership.item_id == VocabularyItem.id).where(VocabularyMembership.collection_id == row.id, VocabularyItem.child_id == row.child_id)))
    return {"id": row.id, "title": row.title, "target_locale": row.target_locale, "word_count": len(ids),
            "snapshot": fingerprint([row.id, row.title, row.target_locale, ids])}


def own_collection(db, child, collection_id):
    row = db.get(VocabularyCollection, collection_id, populate_existing=True)
    if not row or row.child_id != child.id:
        raise HTTPException(404, "Sammlung nicht gefunden.")
    return row


@router.get("/children/{child_id}/vocabulary/collections")
def collection_list(child_id: str, locale: s.TargetLocale | None = None,
                    search: str = Query("", max_length=100), sort: Literal["newest", "name"] = "name",
                    page: int = Query(1, ge=1, le=100000), page_size: int = Query(20, ge=1, le=50),
                    p=Depends(authenticated), db=Depends(get_db)):
    child = child_access(db, p, child_id)
    query = select(VocabularyCollection).where(VocabularyCollection.child_id == child.id)
    if locale:
        query = query.where(VocabularyCollection.target_locale == locale)
    if search:
        escaped = search.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        query = query.where(VocabularyCollection.title.ilike("%" + escaped + "%", escape="\\"))
    total = db.scalar(select(func.count()).select_from(query.subquery()))
    actual = min(page, max(1, (total + page_size - 1) // page_size))
    order = func.lower(VocabularyCollection.title) if sort == "name" else VocabularyCollection.created.desc()
    rows = db.scalars(query.order_by(order, VocabularyCollection.id).offset((actual-1)*page_size).limit(page_size))
    return {"items": [collection_data(db, row) for row in rows], "pagination": {"page": actual, "page_size": page_size, "total": total},
            "filters": {"locale": locale, "search": search, "sort": sort}}


@router.get("/children/{child_id}/vocabulary/collections/{collection_id}")
def get_collection(child_id: str, collection_id: str, p=Depends(authenticated), db=Depends(get_db)):
    child = child_access(db, p, child_id)
    return collection_data(db, own_collection(db, child, collection_id))


@router.post("/children/{child_id}/vocabulary/collections", status_code=201)
def create_collection(child_id: str, data: CollectionDraft, idempotency_key: str = KEY,
                      p=Depends(authenticated), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=p.user.role == "parent")
    lock_child(db, child)
    child = child_access(db, p, child_id, write=p.user.role == "parent")
    title = data.title.strip()
    if not title:
        raise HTTPException(422, "Bitte einen Namen für die Sammlung eingeben.")
    identity_key = digest("word-collection-v1:" + p.user.id + ":" + child.id + ":" + idempotency_key)[:32]
    existing = db.get(VocabularyCollection, identity_key)
    if existing:
        if existing.child_id != child.id or existing.title != title or existing.target_locale != data.target_locale:
            raise HTTPException(409, "Dieser Speicherschlüssel gehört zu einer anderen Sammlung.")
        return collection_data(db, existing)
    rate_limit(db, "vocabulary-collection:" + p.user.id, 30, 3600, commit=False)
    row = VocabularyCollection(id=identity_key, child_id=child.id, title=title, target_locale=data.target_locale)
    db.add(row)
    db.flush()
    result = collection_data(db, row)
    db.commit()
    return result


@router.put("/children/{child_id}/vocabulary/collections/{collection_id}")
def rename_collection(child_id: str, collection_id: str, data: CollectionName,
                      p=Depends(authenticated), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=p.user.role == "parent")
    lock_child(db, child)
    child = child_access(db, p, child_id, write=p.user.role == "parent")
    row = own_collection(db, child, collection_id)
    if row.title != data.expected_title and row.title != data.title.strip():
        raise HTTPException(409, "Der Sammlungsname wurde geändert. Bitte die aktuelle Sammlung neu öffnen.")
    if not data.title.strip():
        raise HTTPException(422, "Bitte einen Namen für die Sammlung eingeben.")
    rate_limit(db, "vocabulary-collection:" + p.user.id, 30, 3600, commit=False)
    row.title = data.title.strip()
    result = collection_data(db, row)
    db.commit()
    return result


@router.delete("/children/{child_id}/vocabulary/collections/{collection_id}")
def erase_collection(child_id: str, collection_id: str, data: CollectionErase,
                     p=Depends(authenticated), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=p.user.role == "parent")
    lock_child(db, child)
    child = child_access(db, p, child_id, write=p.user.role == "parent")
    row = own_collection(db, child, collection_id)
    if db.scalar(select(VocabularyImport.id).where(VocabularyImport.collection_id == row.id, VocabularyImport.status != "confirmed")):
        raise HTTPException(409, "Für diese Sammlung sind noch Wörter zum Prüfen offen. Bitte diese zuerst abschließen.")
    if collection_data(db, row)["snapshot"] != data.snapshot:
        raise HTTPException(409, "Die Sammlung wurde inzwischen geändert. Bitte ihre aktuelle Vorschau prüfen.")
    rate_limit(db, "vocabulary-collection:" + p.user.id, 30, 3600, commit=False)
    db.delete(row)
    db.commit()
    return {"message": "Sammlung entfernt. Wörter, Wiederholungsstände und Antworten bleiben erhalten."}


@router.put("/children/{child_id}/vocabulary/{item_id}/collections")
def choose_collections(child_id: str, item_id: str, data: CollectionChoices,
                       p=Depends(authenticated), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=p.user.role == "parent")
    lock_child(db, child)
    child = child_access(db, p, child_id, write=p.user.role == "parent")
    item = db.get(VocabularyItem, item_id, populate_existing=True)
    if not item or item.child_id != child.id:
        raise HTTPException(404, "Wort nicht gefunden.")
    actual = set(db.scalars(select(VocabularyMembership.collection_id).join(VocabularyCollection, VocabularyMembership.collection_id == VocabularyCollection.id).where(VocabularyMembership.item_id == item.id, VocabularyCollection.child_id == child.id)))
    selected = set(data.collection_ids)
    if item.revision != data.revision or (actual != set(data.expected_collection_ids) and actual != selected):
        raise HTTPException(409, "Wort oder Sammlungszuordnung geändert. Bitte die aktuelle Wortkarte prüfen.")
    for collection_id in selected:
        row = own_collection(db, child, collection_id)
        if row.target_locale != item.target_locale:
            raise HTTPException(422, "Wähle Sammlungen derselben bestätigten Lernsprache.")
    rate_limit(db, "vocabulary-collection:" + p.user.id, 30, 3600, commit=False)
    for collection_id in actual - selected:
        db.delete(db.get(VocabularyMembership, (collection_id, item.id)))
    for collection_id in selected - actual:
        db.add(VocabularyMembership(collection_id=collection_id, item_id=item.id))
    db.commit()
    return {"collection_ids": sorted(selected), "message": "Zuordnung gespeichert. Wort und bisherige Übungen bleiben unverändert."}
