"""Versioned official topic metadata, never evidence of a pupil's attainment.

No downloader, model, private source photo or inferred grade translation.
Public imports are explicit reviewed operator actions; child reads stay private.
"""

import hashlib
import json
import re
import unicodedata
from pathlib import Path
from urllib.parse import urlsplit

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from sqlalchemy import func, select, update

from .curriculum_models import ChildCurriculumChange, ChildCurriculumProfile, CurriculumDocument, CurriculumTopic
from .curriculum_schemas import CatalogueInput, ProfileInput
from .db import Membership, Session, Subject, User, get_db, now
from .families import child_data
from .security import Principal, admin, audit, authenticated, child_access, rate_limit

router = APIRouter(tags=["Lehrplan"])
REFERENCE = Path(__file__).with_name("reference")
NOTICE = "Amtliche Quellen und kuratierte Themen sind teilweise erfasst. Fehlende Zuordnungen bleiben offen; keine vollständige Abdeckung aller Länder, Schularten, Fächer oder Klassen."


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def inventory():
    data = json.loads((REFERENCE / "curriculum-sources-v1.json").read_text())
    rows = {row["iso3166_2"]: row for row in data["states"]}
    if len(rows) != 16:
        raise ValueError("Das Länderquelleninventar benötigt die 16 eindeutigen Länder.")
    return rows


def form_id(state, label):
    plain = unicodedata.normalize("NFKD", label).encode("ascii", errors="ignore").decode().lower()
    return state.lower() + "." + re.sub(r"[^a-z0-9]+", "-", plain).strip("-")


def school_forms(db, state):
    known = inventory().get(state)
    if known is None:
        raise HTTPException(422, "Bitte ein gültiges Bundesland wählen.")
    result = {form_id(state, label): {"id": form_id(state, label), "label": label}
        for label in known["schooltypes_observed"]}
    for document in db.scalars(select(CurriculumDocument).where(CurriculumDocument.state_code == state)):
        row = document.data
        if row.get("school_form_scope", "specific") == "cross_form":
            continue
        key = row["school_form_id"]
        if key in result and result[key]["label"] != row["school_form_label"]:
            raise ValueError("Eine Schulformkennung enthält widersprüchliche amtliche Bezeichnungen.")
        result[key] = {"id": key, "label": row["school_form_label"]}
    return sorted(result.values(), key=lambda row: (row["label"], row["id"]))


def official_hosts():
    data = json.loads((REFERENCE / "curriculum-sources-v1.json").read_text())
    def walk(value):
        if isinstance(value, str) and value.startswith("https://"):
            yield urlsplit(value).hostname
        elif isinstance(value, dict):
            for child in value.values():
                yield from walk(child)
        elif isinstance(value, list):
            for child in value:
                yield from walk(child)
    return {host.lower() for host in walk(data) if host}


def import_catalogue(db, package):
    """Validated immutable records; repeated import adds no rows or inference."""
    package = CatalogueInput.model_validate(package)
    states, hosts = inventory(), official_hosts()
    subjects = {row.key: row for row in db.scalars(select(Subject).where(Subject.owner_family_id.is_(None)))}
    documents = {row.id: row for row in db.scalars(select(CurriculumDocument))}
    saved_topics = {row.id: row for row in db.scalars(select(CurriculumTopic).where(
        CurriculumTopic.id.in_([entry.id for entry in package.topics])))}
    known_forms = {(state, form_id(state, label)): label for state, row in states.items()
        for label in row["schooltypes_observed"]}
    for document in documents.values():
        if document.data.get("school_form_scope", "specific") == "specific":
            key = document.state_code, document.data["school_form_id"]
            label = document.data["school_form_label"]
            if key in known_forms and known_forms[key] != label:
                raise ValueError("Eine gespeicherte Schulformkennung enthält widersprüchliche Bezeichnungen.")
            known_forms[key] = label
    pending_docs, pending_topics = [], []
    for entry in package.documents:
        value = entry.model_dump(mode="json")
        if entry.state_code not in states or urlsplit(entry.official_url).hostname.lower() not in hosts:
            raise ValueError("Dokumentland oder amtlicher Quellenhost ist nicht im geprüften Inventar.")
        prefix = entry.state_code.lower() + "."
        if not entry.school_form_id.startswith(prefix) or any(not key.startswith(prefix) for key in entry.applies_to_school_forms):
            raise ValueError("Schulformkennung gehört zu einem anderen Bundesland.")
        if entry.school_form_scope == "specific":
            form_key = entry.state_code, entry.school_form_id
            if form_key in known_forms and known_forms[form_key] != entry.school_form_label:
                raise ValueError("Schulformkennung hat bereits eine andere amtliche Bezeichnung.")
            known_forms[form_key] = entry.school_form_label
        saved = documents.get(entry.id)
        encoded = fingerprint(value)
        if saved and saved.digest != encoded:
            raise ValueError("Eine vorhandene Dokumentfassung ist unveränderlich; neue Fassung mit neuer Kennung importieren.")
        if not saved:
            saved = CurriculumDocument(id=entry.id, state_code=entry.state_code, digest=encoded, data=value)
            pending_docs.append(saved)
        documents[entry.id] = saved
    for entry in package.topics:
        value = entry.model_dump(mode="json")
        document = documents.get(entry.document_id)
        subject = subjects.get(entry.subject_key)
        if document is None or subject is None:
            raise ValueError("Thema benötigt eine vorhandene amtliche Dokumentfassung und ein bestehendes Stammfach.")
        encoded = fingerprint(value)
        saved = saved_topics.get(entry.id)
        if saved and saved.digest != encoded:
            raise ValueError("Ein vorhandener Themenbeleg ist unveränderlich; neue Fassung mit neuer Kennung importieren.")
        if not saved:
            pending_topics.append(CurriculumTopic(id=entry.id, document_id=document.id, subject_id=subject.id,
                state_code=document.state_code, school_form_id=document.data["school_form_id"], title=entry.title,
                digest=encoded, data=value))
    db.add_all(pending_docs)
    db.flush()
    db.add_all(pending_topics)
    db.flush()
    return {"documents_added": len(pending_docs), "topics_added": len(pending_topics),
        "package_digest": fingerprint(package.model_dump(mode="json")), "notice": NOTICE}


def seed(db):
    path = REFERENCE / "curriculum-topics-v1.json"
    if path.is_file():
        import_catalogue(db, json.loads(path.read_text()))


@router.post("/admin/curriculum/import")
def import_reviewed(data: CatalogueInput, p=Depends(admin), db=Depends(get_db)):
    rate_limit(db, "curriculum-import:" + p.user.id, 10, 3600, commit=False)
    try:
        result = import_catalogue(db, data)
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from None
    audit(db, p.user.id, "curriculum.import_reviewed", result["package_digest"])
    db.commit()
    return result


@router.get("/curriculum/catalog")
def catalogue(p=Depends(authenticated), db=Depends(get_db)):
    counts = dict(db.execute(select(CurriculumTopic.state_code, func.count()).group_by(CurriculumTopic.state_code)).all())
    documents = dict(db.execute(select(CurriculumDocument.state_code, func.count()).group_by(CurriculumDocument.state_code)).all())
    return {"version": 1, "states": [{"code": key, "name": value["label"], "school_forms": school_forms(db, key),
        "school_forms_complete": False, "topic_count": counts.get(key, 0), "document_count": documents.get(key, 0),
        "coverage": "partial" if counts.get(key, 0) else "sources_only", "official_portal_url": value["officialportalURL"]}
        for key, value in inventory().items()], "subjects": [{"id": row.id, "key": row.key, "title": row.title}
            for row in db.scalars(select(Subject).where(Subject.owner_family_id.is_(None), Subject.active.is_(True)).order_by(Subject.sort_order, Subject.id))],
        "coverage": {"states_in_inventory": 16, "states_with_topics": len(counts), "topics": sum(counts.values()),
            "complete": False}, "notice": NOTICE}


def profile_data(db, child, *, can_manage):
    row = db.get(ChildCurriculumProfile, child.id)
    binding = {"region": child.region, "school_type": child.school_type}
    current = row is not None and row.legacy_binding == binding
    return {"child_id": child.id, "revision": row.revision if row else 0,
        "profile_revision": child_data(db, child)["profile_revision"], "grade": child.grade,
        "state_code": row.state_code if current else None,
        "school_form_id": row.school_form_id if current else None, "configured": current,
        "needs_review": row is not None and not current, "state_binding_stale": row is not None and not current,
        "notice": "Land oder Schulform wurde außerhalb des Lehrplanprofils geändert. Bitte die amtliche Zuordnung erneut auswählen." if row is not None and not current else "",
        "legacy_region": child.region,
        "legacy_school_type": child.school_type, "can_manage": can_manage, "updated": row.updated if row else None}


def manages(db, p, child):
    return p.user.role == "parent" and bool(db.scalar(select(Membership.id).where(
        Membership.user_id == p.user.id, Membership.family_id == child.family_id, Membership.permission != "view")))


def account_bound(p, account):
    if p.user.id != account:
        raise HTTPException(409, "Der angemeldete Zugang wurde geändert. Bitte neu laden.")


@router.get("/children/{child_id}/curriculum-profile")
def get_profile(child_id: str, p=Depends(authenticated), db=Depends(get_db),
                account: str = Header(..., alias="X-Schulpilot-Account", pattern=r"^[a-f0-9]{32}$")):
    account_bound(p, account)
    child = child_access(db, p, child_id)
    return profile_data(db, child, can_manage=manages(db, p, child))


@router.put("/children/{child_id}/curriculum-profile")
def save_profile(child_id: str, data: ProfileInput, p=Depends(authenticated), db=Depends(get_db),
                 account: str = Header(..., alias="X-Schulpilot-Account", pattern=r"^[a-f0-9]{32}$"),
                 key: str = Header(..., alias="Idempotency-Key", min_length=16, max_length=80, pattern=r"^[A-Za-z0-9_-]+$")):
    from .parent_insights import lock_parent

    account_bound(p, account)
    if p.user.role != "parent":
        raise HTTPException(403, "Schulangaben können nur berechtigte Eltern ändern.")
    actor_id, session_id = p.user.id, p.session.id
    child = lock_parent(db, p, child_id)
    # Same lock order as the existing child editor: Child, then child User,
    # followed by another fresh authorization check after a possible wait.
    db.execute(update(User).where(User.id == child.user_id).values(display_name=User.display_name))
    db.get(User, child.user_id, populate_existing=True)
    child = lock_parent(db, p, child_id)
    actor = db.get(User, actor_id, populate_existing=True)
    login = db.get(Session, session_id, populate_existing=True)
    if (not actor or actor.role != "parent" or not actor.verified or actor.disabled or not login or
            login.user_id != actor_id or login.revoked or login.expires <= now() or now() - login.seen > 7 * 86400):
        raise HTTPException(401, "Bitte erneut anmelden.")
    child = child_access(db, Principal(actor, login), child_id, write=True)
    request_digest = fingerprint(data.model_dump())
    previous = db.scalar(select(ChildCurriculumChange).where(ChildCurriculumChange.child_id == child.id,
        ChildCurriculumChange.request_key == key))
    if previous:
        if previous.actor_id != p.user.id or previous.digest != request_digest:
            raise HTTPException(409, "Dieser Speicherversuch gehört zu anderen Angaben.")
        return profile_data(db, child, can_manage=True)
    row = db.get(ChildCurriculumProfile, child.id)
    if data.revision != (row.revision if row else 0) or data.profile_revision != child_data(db, child)["profile_revision"]:
        raise HTTPException(409, "Die Kinder- oder Lehrplanangaben wurden inzwischen geändert. Bitte neu laden; dein Entwurf bleibt erhalten.")
    states = inventory()
    if data.state_code not in states:
        raise HTTPException(422, "Bitte ein gültiges Bundesland wählen.")
    forms = {item["id"]: item for item in school_forms(db, data.state_code)}
    if data.school_form_id is not None and data.school_form_id not in forms:
        raise HTTPException(422, "Die gewählte Schulform gehört nicht zu diesem Bundesland.")
    rate_limit(db, "curriculum-profile:" + p.user.id, 30, 3600, commit=False)
    child.grade = data.grade
    child.region = states[data.state_code]["label"]
    # Unknown stays explicitly unknown; never infer a path from a legacy label.
    child.school_type = forms[data.school_form_id]["label"] if data.school_form_id else ""
    if row is None:
        row = ChildCurriculumProfile(child_id=child.id)
        db.add(row)
    row.revision, row.state_code, row.school_form_id = data.revision + 1, data.state_code, data.school_form_id
    row.legacy_binding = {"region": child.region, "school_type": child.school_type}
    row.updated = int(now())
    db.add(ChildCurriculumChange(child_id=child.id, actor_id=p.user.id, request_key=key, digest=request_digest,
        revision=row.revision, data=data.model_dump()))
    audit(db, p.user.id, "child.curriculum_profile_update", child.id)
    db.flush()
    result = profile_data(db, child, can_manage=True)
    db.commit()
    return result


def topic_data(row, document):
    value, source = row.data, document.data
    return {"id": row.id, "title": row.title, "subject_id": row.subject_id, "subject_key": value["subject_key"],
        "state_code": row.state_code, "school_form_id": row.school_form_id,
        "grade_kind": value["grade_kind"], "grades": value["grades"], "phase_label": value["phase_label"],
        "canonical_topic_key": value.get("canonical_topic_key"),
        "canonical_topic_key_status": "unverified_proposal" if value.get("canonical_topic_key") else None,
        "mapping_status": value.get("mapping_status", "curated_source_heading"),
        "source": {"document_id": document.id, "url": source["official_url"], "title": source["title"],
            "edition": source["edition"], "effective_from": source["effective_from"], "retrieved": source["retrieved"],
            "status": source["source_status"], "digest": document.digest, "section": value["section"],
            "page": value["page"], "quote": value["quote"], "school_form_scope": source["school_form_scope"],
            "document_kind": source["document_kind"], "applicability_note": source["applicability_note"], "source_notes": source["source_notes"]}}


@router.get("/curriculum/topics")
def topics(state_code: str | None = Query(None, pattern=r"^DE-[A-Z]{2}$"), school_form_id: str | None = Query(None, max_length=120),
           subject_id: str | None = Query(None, max_length=32), grade: int | None = Query(None, ge=1, le=13),
           phase: str | None = Query(None, max_length=120), query: str = Query("", max_length=120),
           limit: int = Query(30, ge=1, le=50), cursor: str | None = Query(None, max_length=140),
           p=Depends(authenticated), db=Depends(get_db)):
    if state_code is not None and state_code not in inventory():
        raise HTTPException(422, "Unbekanntes Bundesland.")
    statement = select(CurriculumTopic, CurriculumDocument).join(CurriculumDocument)
    if state_code:
        statement = statement.where(CurriculumTopic.state_code == state_code)
    if subject_id:
        statement = statement.where(CurriculumTopic.subject_id == subject_id)
    if cursor:
        statement = statement.where(CurriculumTopic.id > cursor)
    if query:
        escaped = query.lower().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        statement = statement.where(func.lower(CurriculumTopic.title).like("%" + escaped + "%", escape="\\"))
    # Keyset scan advances through at most 1000 records per request; Python
    # checks preserve JSON grade bands identically on SQLite and PostgreSQL.
    scanned, items, last, exhausted = 0, [], cursor, False
    while len(items) <= limit and scanned < 1000:
        page = statement.where(CurriculumTopic.id > last) if last else statement
        rows = list(db.execute(page.order_by(CurriculumTopic.id).limit(min(100, 1000 - scanned))))
        if not rows:
            exhausted = True
            break
        for row, document in rows:
            scanned += 1
            last = row.id
            value, source = row.data, document.data
            if school_form_id and row.school_form_id != school_form_id and school_form_id not in source.get("applies_to_school_forms", []):
                continue
            if grade is not None and (not value["grades"] or grade not in value["grades"]):
                continue
            if phase is not None and value["phase_label"] != phase:
                continue
            if len(items) == limit:
                # Next request must start just before this qualifying record.
                return {"items": items, "next_cursor": items[-1]["id"], "coverage": "partial", "notice": NOTICE}
            items.append(topic_data(row, document))
    return {"items": items, "next_cursor": None if exhausted else last, "coverage": "partial", "notice": NOTICE}


def export_child(db, child):
    return {"profile": profile_data(db, child, can_manage=False),
        "changes": [{"revision": row.revision, "data": row.data, "created": row.created}
            for row in db.scalars(select(ChildCurriculumChange).where(ChildCurriculumChange.child_id == child.id)
                .order_by(ChildCurriculumChange.created, ChildCurriculumChange.id))]}



def _planning_binding(db, child):
    row = db.get(ChildCurriculumProfile, child.id)
    if row is None or row.legacy_binding != {"region": child.region, "school_type": child.school_type}:
        return None
    return {"revision": row.revision, "state_code": row.state_code, "school_form_id": row.school_form_id,
        "grade": child.grade, "profile_signature": fingerprint([child.grade, row.revision, row.state_code,
            row.school_form_id, row.legacy_binding])}


def planning_context(db, child, subjects):
    """A bounded official planning hint, never answer truth or pupil evidence."""
    binding = _planning_binding(db, child)
    if binding is None:
        return None
    # A deliberately unresolved school form does not inherit every school path
    # in this state. Phase-only or unclassified topics never gain invented years.
    rows = []
    if binding["school_form_id"]:
        subject_ids = list(db.scalars(select(Subject.id).where(Subject.owner_family_id.is_(None),
            Subject.active.is_(True), Subject.title.in_(list(dict.fromkeys(subjects))[:24]))))
        candidates = db.execute(select(CurriculumTopic, CurriculumDocument).join(CurriculumDocument).where(
            CurriculumTopic.state_code == binding["state_code"], CurriculumTopic.subject_id.in_(subject_ids))
            .order_by(CurriculumTopic.id).limit(1000)) if subject_ids else []
        by_subject = {}
        for topic, document in candidates:
            scope, value = document.data, topic.data
            if (topic.school_form_id != binding["school_form_id"] and binding["school_form_id"] not in scope.get("applies_to_school_forms", [])):
                continue
            if binding["grade"] not in (value["grades"] or []):
                continue
            actual = topic_data(topic, document)
            metadata = {key: actual[key] for key in ("id", "title", "subject_key", "grade_kind", "grades", "phase_label")}
            metadata["source"] = {key: actual["source"][key] for key in ("document_id", "url", "edition", "status", "digest", "section", "page", "document_kind")}
            by_subject.setdefault(topic.subject_id, []).append(metadata)
        # Fair, finite metadata allocation across selected subjects; no union of
        # a biology curriculum silently presented as physics learning content.
        for index in range(8):
            for entries in by_subject.values():
                if index < len(entries) and len(rows) < 8:
                    rows.append(entries[index])
    return {"version": 1, **binding, "topics": rows, "coverage": "partial",
        "notice": NOTICE, "use": "Nur amtliche Planungsorientierung. Klassenband, Originalphase, Schulform und Fassungsstatus erhalten. Kein Antwortschlüssel, keine neue Lernquelle, kein Beleg vorhandener Kinderkompetenz. Bestätigten ausgewählten Heftstoff und Elternziele nicht durch andere Lehrplanthemen ersetzen."}


def guard_planning_context(db, child, context):
    if context is not None and any(context.get(key) != value for key, value in (_planning_binding(db, child) or {"profile_signature": None}).items()):
        raise ValueError("Die Schul- oder Lehrplanangaben wurden während der Vorbereitung geändert. Bitte mit dem aktuellen Profil erneut vorbereiten.")
