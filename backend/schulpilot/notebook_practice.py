"""Explicit notebook selections use the existing unit queue and billing contract.

Only metadata/digests are persisted in the job; the selected safe text is loaded
fresh before dispatch and publication. No day expansion, retry or answer writes.
"""

from fastapi import HTTPException

from .db import Family, Material, Subject
from .source_lineage import digest, learning_source


def requested_count(payload):
    value = payload.get("notebook_practice")
    if value is None:
        return None
    from .providers import ProviderError

    if (not isinstance(value, dict) or set(value) != {"version", "question_count"}
            or type(value["version"]) is not int or value["version"] != 1
            or type(value["question_count"]) is not int or not 2 <= value["question_count"] <= 5):
        raise ProviderError("Der vereinbarte Umfang der Heft-Runde ist ungültig.")
    return value["question_count"]


def _sources(db, child, material_id, refs):
    if (not isinstance(refs, list) or not 1 <= len(refs) <= 12
            or any(not isinstance(ref, dict) or set(ref) != {"id", "revision"}
                or not isinstance(ref["id"], str) or type(ref["revision"]) is not int or ref["revision"] < 1
                for ref in refs)
            or len({ref["id"] for ref in refs}) != len(refs)
            or material_id not in {ref["id"] for ref in refs}):
        raise HTTPException(422, "Bitte die geöffnete Seite und höchstens zwölf unterschiedliche Heftseiten auswählen.")
    family = db.get(Family, child.family_id, populate_existing=True)
    if not family or family.synthetic:
        raise HTTPException(403, "Der Testraum verwendet ausschließlich seine bestehenden festen Beispiele.")
    pages, snapshots, subject_id, total = [], [], None, 0
    for ref in refs:
        page = db.get(Material, ref["id"], populate_existing=True)
        if not page or page.child_id != child.id:
            raise HTTPException(404, "Eine ausgewählte Heftseite ist nicht verfügbar.")
        if page.synthetic or page.fixture_id:
            raise HTTPException(403, "Feste Testbeispiele gehören nicht in eine freie Heftauswahl.")
        if page.purpose != "notebook":
            raise HTTPException(422, "Bitte ausschließlich Heftseiten auswählen, keine Hausaufgaben oder Arbeitsfotos.")
        if not page.confirmed or page.revision != ref["revision"]:
            raise HTTPException(409, "Eine ausgewählte Heftseite wurde geändert. Bitte die Auswahl neu prüfen.")
        subject = db.get(Subject, page.subject_id) if page.subject_id else None
        if not subject or subject.owner_family_id not in (None, child.family_id):
            raise HTTPException(409, "Bitte die Heftseiten zuerst einem eigenen gemeinsamen Fach zuordnen.")
        subject_id = subject_id or subject.id
        if subject.id != subject_id:
            raise HTTPException(422, "Bitte für eine Runde Heftseiten aus demselben Fach auswählen.")
        safe = learning_source(db, page, revision=ref["revision"])
        if not safe["content"].strip():
            raise HTTPException(409, "Eine gewählte Seite enthält noch keine verwendbare Lehrgrundlage. Bitte zuerst prüfen.")
        total += len(page.content)
        if total > 60_000:
            raise HTTPException(422, "Bitte für eine Runde höchstens 60000 Zeichen bestätigten Heftstoff auswählen.")
        snapshots.append({"id": page.id, "revision": page.revision, "subject_id": page.subject_id,
            "safe_source": safe})
        pages.append(page)
    return pages, subject_id, digest(snapshots)


def selection(db, child, material_id, refs, question_count):
    requested_count({"notebook_practice": {"version": 1, "question_count": question_count}})
    _, subject_id, signature = _sources(db, child, material_id, refs)
    return {"sources": refs, "notebook_practice": {"version": 1, "question_count": question_count,
        "subject_id": subject_id, "source_signature": signature}}


def guard(db, child, payload):
    meta = payload.get("notebook_practice")
    if (not isinstance(meta, dict) or set(meta) != {"version", "question_count", "subject_id", "source_signature"}
            or payload.get("assignment_id") or payload.get("review_of")):
        raise HTTPException(409, "Die vereinbarte Heftauswahl ist nicht mehr gültig.")
    requested_count({"notebook_practice": {key: meta[key] for key in ("version", "question_count")}})
    pages, subject_id, signature = _sources(db, child, payload.get("material_id"), payload.get("sources"))
    if subject_id != meta["subject_id"] or signature != meta["source_signature"]:
        raise HTTPException(409, "Die ausgewählte Lehrgrundlage wurde geändert. Bitte ausdrücklich neu vorbereiten.")
    return pages


def provider_context(db, child, payload):
    pages = guard(db, child, payload)
    subject = db.get(Subject, pages[0].subject_id)
    meta = payload["notebook_practice"]
    return {"notebook_practice": {key: meta[key] for key in ("version", "question_count")},
        "required_subject": subject.title}


def validate_output(db, child, payload, data):
    from .providers import ProviderError
    from .subject_registry import resolve

    guard(db, child, payload)
    subject = resolve(db, data.get("subject", ""), child.family_id)
    if (not subject or subject.id != payload["notebook_practice"]["subject_id"]
            or len(data.get("questions", [])) != payload["notebook_practice"]["question_count"]):
        raise ProviderError("Die erzeugte Heft-Runde weicht vom gewählten Fach oder Aufgabenumfang ab.")
