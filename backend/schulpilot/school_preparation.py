"""A durable coordinator over existing, separately budgeted OCR/package jobs.

Only an explicit submit starts/retries a run. Successful OCR advances to the next
page, never to source confirmation or learning. Reservations use a separate
transaction: a quota rollback cannot undo an already saved page or its usage.
"""

import copy
import hashlib
import json

from fastapi import HTTPException
from sqlalchemy import select, update
from sqlalchemy.orm import load_only

from .commerce import usage_terms
from .db import DB, Child, Family, Job, Material, ProviderConfig, SchoolDay, Session, Usage, User, now, uid
from .fixtures import DAY_FIXTURE_IDS, LIVE_FIXTURE_IDS
from .learning import record
from .providers import ProviderError, Result, config_for_function, external_allowed, reserve, settle
from .security import Principal, child_access, digest, rate_limit

MAX_ATTEMPTS = 2
ACTIVE = ("queued", "running")


def _state(day):
    return copy.deepcopy(day.preparation or {})


def _pages(db, day):
    from .school_day import pages

    return pages(db, day)


def _sources(db, day):
    return [
        {"id": row.id, "revision": row.revision}
        for row in db.execute(
            select(Material.id, Material.revision)
            .where(Material.school_day_id == day.id)
            .order_by(Material.page_number, Material.id)
        )
    ]


def _fingerprint(sources):
    return hashlib.sha256(json.dumps(sources, sort_keys=True).encode()).hexdigest()


def _write(day, state, **values):
    state.update(values, updated=int(now()))
    day.preparation = state


def authority(db, day, state):
    """The submitting session/family remains authoritative, also after inference."""
    session = db.get(Session, state.get("session_id")) if state.get("session_id") else None
    user = db.get(User, state.get("user_id")) if state.get("user_id") else None
    if (
        not session
        or not user
        or session.user_id != user.id
        or session.revoked
        or session.expires <= now()
        or now() - session.seen > 7 * 86400
        or not user.verified
        or user.disabled
        or user.role not in ("child", "parent")
    ):
        raise HTTPException(401, "Die Vorbereitung wurde unterbrochen. Bitte melde dich erneut an.")
    child = child_access(db, Principal(user, session), day.child_id, write=user.role == "parent")
    if child.family_id != state.get("family_id"):
        raise HTTPException(403, "Die Familienberechtigung hat sich geändert. Bitte neu anmelden.")
    family = db.get(Family, child.family_id)
    usage_terms(db, family, enforce=True)
    return child, family


def _check_sources(db, day, state):
    if _sources(db, day) != state.get("sources") or day.revision != state.get("day_revision"):
        raise ProviderError("Die Heftseiten wurden geändert. Bitte prüfe die Seiten und gib sie erneut ab.")


def notice_allowed(db, day):
    state = _state(day)
    try:
        authority(db, day, state)
        _check_sources(db, day, state)
    except (HTTPException, ProviderError):
        return False
    return True


def validate_job(db, job):
    """Preparation-specific access, revision, provider and tariff checks."""
    if not job.payload.get("preparation_id"):
        return
    day = db.get(SchoolDay, job.payload.get("school_day_id"))
    if not day or day.child_id != job.child_id:
        raise ProviderError("Dieser Schultag ist nicht mehr vorhanden.")
    state = _state(day)
    if state.get("run_id") != job.payload["preparation_id"] or state.get("job_id") != job.id:
        raise ProviderError("Dieser Vorbereitungsauftrag ist nicht mehr aktuell.")
    child, family = authority(db, day, state)
    _check_sources(db, day, state)
    config = config_for_function(db.get(ProviderConfig, 1), job.kind)
    material = db.get(Material, job.payload.get("material_id"))
    fixture = bool(material and material.fixture_id in LIVE_FIXTURE_IDS and material.synthetic and family.synthetic)
    external_allowed(config, image=job.kind == "extract", synthetic_fixture=fixture)
    usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
    if not usage or (
        usage.provider != config.provider or usage.model != config.model or usage.config_revision != config.revision
    ):
        raise ProviderError("Die KI-Einstellungen haben sich geändert. Bitte die Vorbereitung erneut anstoßen.")
    return day, child


def _saved(db, day, state, *, job=None):
    from .study_path import ensure_plan

    ensure_plan(db, day)
    if day.stage != "ready":
        day.stage = "ready"
        day.revision += 1
    _notify(db, day, state, "saved")
    _write(
        day,
        state,
        status="saved",
        phase="deferred",
        job_id=job.id if job else None,
        day_revision=day.revision,
        error=None,
    )
    record(db, day.child_id, "school_day_saved", {"school_day_id": day.id, "page_count": len(_pages(db, day))})
    if job:
        job.result = {"school_day_id": day.id, "unit_ids": [], "deferred": True}


def defer_package(db, job, *, before_call=False):
    """Only already covered sources need no new package.

    Before dispatch the known zero-cost result is settled explicitly. After a
    real call its real usage is settled by the normal worker. Crossing midnight
    or a recommended time goal never discards an explicitly requested package.
    """
    if job.kind != "package" or not job.payload.get("preparation_id"):
        return False
    from .school_day import package_plan

    day = db.get(SchoolDay, job.payload["school_day_id"])
    child = db.get(Child, job.child_id)
    if any(group["selected"] for group in package_plan(db, day, child)["groups"]):
        return False
    _saved(db, day, _state(day), job=job)
    if before_call:
        usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
        if usage:
            settle(db, usage, Result({}, 0, 0, 0))
        job.status, job.finished = "completed", int(now())
    return True


def _notify(db, day, state, status):
    """Persistent neutral in-app notice; FCM separately checks opt-in/quiet time."""
    if state.get("notice_status") == status:
        return
    from .db import Message

    body = {
        "needs_review": "Deine Heftseiten sind erkannt. Bitte schau sie dir an.",
        "needs_photo": "Bitte fotografiere eine Heftseite noch einmal.",
        "ready": "Dein Lernpaket ist bereit. Starte, wenn es für dich passt.",
        "saved": "Deine Seiten sind für spätere Lerntage gespeichert.",
    }[status]
    db.add(Message(child_id=day.child_id, sender_id=None, kind="preparation", body=body))
    state["notice_status"], state["notice_created"] = status, int(now())
    record(db, day.child_id, "preparation_notice", {"school_day_id": day.id, "status": status})


def preparation_data(db, day, child=None):
    """Small read-only metadata; never expose actor/session IDs or private state."""
    state = _state(day)
    source_pages = list(
        db.scalars(
            select(Material)
            .options(load_only(Material.id, Material.revision, Material.status, Material.confirmed))
            .where(Material.school_day_id == day.id)
            .order_by(Material.page_number, Material.id)
        )
    )
    job = db.get(Job, state.get("job_id")) if state.get("job_id") else None
    status, error = state.get("status", "idle"), state.get("error")
    if status == "processing" and job and job.status == "failed":
        status, error = "failed", job.error
    current = [{"id": m.id, "revision": m.revision} for m in source_pages]
    can_retry = status in ("failed", "blocked") and bool(source_pages)
    if can_retry and current == state.get("sources"):
        if state.get("phase") == "extract":
            waiting = next((m for m in source_pages if m.status == "uploaded" and not m.confirmed), None)
            counts = state.get("extract_attempts", {})
            previous = counts.get(waiting.id, {}) if waiting else {}
            can_retry = not waiting or (
                previous.get("revision") != waiting.revision or previous.get("count", 0) < MAX_ATTEMPTS
            )
        elif state.get("phase") == "package":
            can_retry = state.get("package_attempts", {}).get(_fingerprint(current), 0) < MAX_ATTEMPTS
    return {
        "status": status,
        "phase": state.get("phase"),
        "completed_pages": sum(m.status in ("review", "confirmed", "unreadable") for m in source_pages),
        "total_pages": len(source_pages),
        "job": {"id": job.id, "kind": job.kind, "status": job.status} if job else None,
        "error": error,
        "can_retry": can_retry,
    }


def submit(db, p, day, child, key):
    """Persist intent before reserving; a disconnected browser cannot lose it."""
    if not key or len(key) > 80:
        raise HTTPException(422, "Ein eindeutiger Idempotency-Key (max. 80 Zeichen) ist erforderlich.")
    source_pages = _pages(db, day)
    if not source_pages:
        raise HTTPException(409, "Bitte zuerst mindestens ein Foto hinzufügen.")
    if any(m.synthetic and not m.fixture_id for m in source_pages):
        raise HTTPException(409, "Bitte für diesen Test die festen Testheftseiten verwenden.")
    if any(m.synthetic for m in source_pages) and [m.fixture_id for m in source_pages] != list(DAY_FIXTURE_IDS):
        raise HTTPException(409, "Der KI-Tagespakettest benötigt genau die zwei festen Testheftseiten.")
    snapshot = _sources(db, day)
    fingerprint, key_hash = _fingerprint(snapshot), digest(p.user.id + ":" + key)
    state = _state(day)
    requests = state.get("requests", [])
    previous = next((r for r in requests if r["key"] == key_hash), None)
    if previous and previous["fingerprint"] != fingerprint:
        raise HTTPException(409, "Dieser Anfrageschlüssel gehört zu einem anderen Stand der Heftseiten.")
    same = state.get("sources") == snapshot and state.get("day_revision") == day.revision
    completed_review = state.get("status") == "needs_review" and all(m.confirmed for m in source_pages)
    if previous or (
        same
        and not completed_review
        and state.get("status") in ("processing", "needs_review", "needs_photo", "ready", "saved")
    ):
        return
    if db.scalar(select(Job.id).where(Job.child_id == child.id, Job.status.in_(ACTIVE))):
        raise HTTPException(409, "Für dich wird gerade noch etwas vorbereitet. Bitte kurz warten.")
    rate_limit(db, "school-prepare:" + p.user.id, 10, 60, commit=False)
    if day.stage == "collecting":
        day.stage = "review"
        day.revision += 1
    state = {
        "run_id": uid(),
        "status": "processing",
        "phase": "extract",
        "job_id": None,
        "user_id": p.user.id,
        "session_id": p.session.id,
        "family_id": child.family_id,
        "sources": snapshot,
        "day_revision": day.revision,
        "error": None,
        "requests": [*requests, {"key": key_hash, "fingerprint": fingerprint}][-128:],
        "extract_attempts": state.get("extract_attempts", {}),
        "package_attempts": state.get("package_attempts", {}),
    }
    if all(m.confirmed for m in source_pages):
        state["phase"] = "package"
    _write(day, state)
    record(db, child.id, "school_day_submitted", {"school_day_id": day.id, "page_count": len(source_pages)})


def postpone_preparation(db, day):
    """Explicitly remove pending review from the inbox, keeping every source.

    In particular, an unreadable archived photo must not trap a child forever:
    new photos belong to today, the old set remains available in the archive.
    No confirmation, generated package, learning-plan or achievement is claimed.
    """
    state = _state(day)
    if state.get("status") == "postponed":
        return
    if state.get("status") not in ("needs_photo", "needs_review", "failed", "blocked"):
        raise HTTPException(409, "Bitte eine laufende Vorbereitung erst abschließen lassen.")
    _write(day, state, status="postponed", phase="review", error=None, notice_created=0)
    record(db, day.child_id, "school_day_postponed", {"school_day_id": day.id})


def saved_by_user(db, day, p):
    """Keep legacy explicit save buttons consistent with the preparation inbox."""
    state = _state(day)
    state.update(
        run_id=state.get("run_id") or uid(),
        user_id=p.user.id,
        session_id=p.session.id,
        family_id=db.get(Child, day.child_id).family_id,
        sources=_sources(db, day),
        day_revision=day.revision,
    )
    _notify(db, day, state, "saved")
    _write(day, state, status="saved", phase="deferred", job_id=None, error=None)


def sources_removed(db, day):
    """Called after deleting an unconfirmed page, while holding Child.

    No pending inference may exist. Cancel the old coordinator intent so a tick
    selected before deletion cannot reserve another job. Keep remaining pages,
    prior attempt counts and completed learning untouched; continuing is explicit.
    """
    state = _state(day)
    source_pages = _pages(db, day)
    status, phase, error = "idle", None, None
    if not source_pages:
        day.stage = "collecting"
    elif day.stage != "collecting":
        if any(m.status == "unreadable" for m in source_pages):
            status, phase = "needs_photo", "review"
        elif any(m.status == "uploaded" and not m.confirmed for m in source_pages):
            status, phase = "blocked", "extract"
            error = "Deine übrigen Fotos sind gespeichert. Bitte gib sie erneut ab."
        else:
            status, phase = "needs_review", "review"
    _write(
        day,
        state,
        run_id=uid(),
        sources=_sources(db, day),
        day_revision=day.revision,
        status=status,
        phase=phase,
        job_id=None,
        error=error,
        notice_created=0,
        notice_status=None,
    )


def _queue(db, day, child, family, state, kind, payload):
    """Called only while holding Child; rollback here never undoes prior jobs."""
    material = db.get(Material, payload["material_id"])
    if kind == "extract":
        counts = state.setdefault("extract_attempts", {})
        old = counts.get(material.id, {})
        attempts = old.get("count", 0) if old.get("revision") == material.revision else 0
        historical = sum(
            j.payload.get("material_id") == material.id and j.payload.get("material_revision") == material.revision
            for j in db.scalars(select(Job).where(Job.child_id == child.id, Job.kind == "extract"))
        )
        attempts = max(attempts, historical)
        if attempts >= MAX_ATTEMPTS:
            raise ProviderError("Die Erkennung hat zweimal nicht geklappt. Bitte fotografiere die Seite neu.")
        counts[material.id] = {"revision": material.revision, "count": attempts + 1}
    else:
        counts, name = state.setdefault("package_attempts", {}), _fingerprint(state["sources"])
        historical = sum(
            j.payload.get("sources") == state["sources"]
            for j in db.scalars(select(Job).where(Job.child_id == child.id, Job.kind == "package"))
        )
        attempts = max(counts.get(name, 0), historical)
        if attempts >= MAX_ATTEMPTS:
            raise ProviderError("Das Paket konnte zweimal nicht erstellt werden. Deine Seiten bleiben gespeichert.")
        counts[name] = attempts + 1
    payload = {
        **payload,
        "school_day_id": day.id,
        "preparation_id": state["run_id"],
        "material_revision": material.revision,
    }
    job = Job(
        id=uid(),
        child_id=child.id,
        kind=kind,
        payload=payload,
        idempotency="prepare:" + state["run_id"] + ":" + kind + ":" + material.id,
    )
    db.add(job)
    db.flush()
    reserve(
        db,
        family,
        child.id,
        job.id,
        kind,
        synthetic_fixture=bool(material.fixture_id in LIVE_FIXTURE_IDS and material.synthetic and family.synthetic),
    )
    _write(day, state, job_id=job.id, phase=kind, error=None)


def _advance(db, day):
    state = _state(day)
    if state.get("status") != "processing":
        return
    child, family = authority(db, day, state)
    _check_sources(db, day, state)
    job = db.get(Job, state.get("job_id")) if state.get("job_id") else None
    if job:
        if job.status in ACTIVE:
            return
        if job.status == "failed":
            _write(day, state, status="failed", error=job.error)
            return
        if job.kind == "package" and job.status == "completed":
            status = "saved" if job.result and job.result.get("deferred") else "ready"
            if status == "ready":
                _notify(db, day, state, status)
            _write(day, state, status=status, phase="deferred" if status == "saved" else "complete", error=None)
            return
    if db.scalar(select(Job.id).where(Job.child_id == child.id, Job.status.in_(ACTIVE))):
        raise ProviderError("Für dieses Kind läuft bereits ein anderer Auftrag. Bitte später erneut versuchen.")
    source_pages = _pages(db, day)
    waiting = next((m for m in source_pages if m.status == "uploaded" and not m.confirmed), None)
    if waiting:
        _queue(db, day, child, family, state, "extract", {"material_id": waiting.id})
        return
    if any(not m.confirmed for m in source_pages):
        status = "needs_photo" if any(m.status == "unreadable" for m in source_pages) else "needs_review"
        _notify(db, day, state, status)
        _write(day, state, status=status, phase="review", job_id=None, error=None)
        return
    from .school_day import MAX_CONTENT, package_plan, planning_fingerprint

    if sum(len(m.content) for m in source_pages) > MAX_CONTENT:
        raise ProviderError("Der Text ist für ein Paket zu umfangreich. Bitte mit deinen Eltern den Stoff eingrenzen.")
    preview = package_plan(db, day, child)
    selected = [g for g in preview["groups"] if g["selected"]]
    if not selected:
        _saved(db, day, state)
        return
    _queue(
        db,
        day,
        child,
        family,
        state,
        "package",
        {
            "material_id": source_pages[0].id,
            "day_revision": day.revision,
            "sources": state["sources"],
            "groups": selected,
            "planning_fingerprint": planning_fingerprint(db, child),
        },
    )


def advance(day_id):
    """Recoverable after restart; never retries a failed provider job."""
    run_id = None
    try:
        with DB.begin() as db:
            day = db.get(SchoolDay, day_id)
            if not day or (day.preparation or {}).get("status") != "processing":
                return
            run_id = day.preparation.get("run_id")
            if not db.execute(update(Child).where(Child.id == day.child_id).values(grade=Child.grade)).rowcount:
                return
            db.refresh(day)
            _advance(db, day)
    except Exception as error:
        # Provider/API exceptions contain controlled messages only; no raw data.
        message = (
            str(error.detail)
            if isinstance(error, HTTPException)
            else (
                str(error)
                if isinstance(error, ProviderError)
                else "Die Vorbereitung wurde unterbrochen. Bitte erneut versuchen."
            )
        )
        with DB.begin() as db:
            day = db.get(SchoolDay, day_id)
            if not day:
                return
            db.execute(update(Child).where(Child.id == day.child_id).values(grade=Child.grade))
            db.refresh(day)
            state = _state(day)
            if state.get("run_id") == run_id and state.get("status") == "processing":
                _write(day, state, status="blocked", error=message[:500])


def advance_one():
    """Worker tick, independent of browser polling and safe after server restart."""
    with DB() as db:
        ids = list(
            db.scalars(
                select(SchoolDay.id)
                .where(SchoolDay.preparation["status"].as_string() == "processing")
                .order_by(SchoolDay.created, SchoolDay.id)
                .limit(100)
            )
        )
    for day_id in ids:
        advance(day_id)
