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
from .provider_attempts import counts as _attempt_counts
from .providers import ProviderError, Result, external_allowed, reserve, settle
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
    index = job.payload.get("package_partition")
    if index is not None:
        part = _checked_part(db, day, child, state, index)
        plan = state["package_plan"]
        if (job.kind != "package" or job.payload.get("package_plan_digest") != plan["digest"]
                or job.payload.get("package_partition_sources") != part["sources"]
                or job.payload.get("groups") != [part["group"]]
                or job.payload.get("sources") != state["sources"]):
            raise ProviderError("Dieser Teilauftrag passt nicht mehr zu den bestätigten Quellen.")
    from .model_routing import job_config

    config = job_config(db, job)
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
    db.add(Message(child_id=day.child_id, sender_id=None, kind="preparation", body=body, context={"day_id": day.id}))
    state["notice_status"], state["notice_created"] = status, int(now())
    record(db, day.child_id, "preparation_notice", {"school_day_id": day.id, "status": status})


def _transport_repair(db, day, state, job, sources, config):
    if (not job or job.kind != "package" or job.status != "failed" or job.child_id != day.child_id
            or state.get("sources") != sources or state.get("day_revision") != day.revision
            or job.payload.get("sources") != sources):
        return None
    from .package_transport import repair_revision

    usage = db.scalar(select(Usage).where(Usage.job_id == job.id).order_by(Usage.created.desc()).limit(1))
    if usage and usage.child_id == day.child_id:
        return repair_revision(usage, config)
    return None



# Private state only. Never pass these objects to preparation_data/job.result.
_PART_KEYS = ("package_plan", "package_config_revision", "package_outputs", "package_completed_parts",
              "package_publications", "package_publication_version")


def _clear_parts(state):
    for key in _PART_KEYS:
        state.pop(key, None)


def _parts_enabled(source_pages):
    # The paid fixed synthetic fixture intentionally replaces the whole input.
    # Keep its existing two-page probe contract; normal mocks use real flags.
    return bool(source_pages) and all(m.confirmed and not m.synthetic for m in source_pages)


def _part_key(plan, index):
    return plan["digest"] + ":" + str(index)


def _part_outputs(state, plan):
    from .package_partitions import validated_parts

    values = validated_parts(state, plan, require_complete=False)
    from .package_publication import publication_records

    return values, {int(key) for key in [*state.get("package_outputs", {}), *publication_records(state, plan)]}


def _current_plan(db, day, child, state):
    from .package_partitions import check_plan

    plan = state.get("package_plan")
    try:
        return bool(isinstance(plan, dict)
            and state.get("package_config_revision") == plan.get("config_revision")
            and check_plan(db, day, child, plan))
    except (ValueError, KeyError, TypeError, IndexError):
        return False


def _checked_part(db, day, child, state, index):
    plan = state.get("package_plan")
    if (not _current_plan(db, day, child, state) or type(index) is not int
            or not 0 <= index < len(plan["parts"])):
        raise ProviderError("Die Quellen, Planung oder KI-Einstellungen der Teilrunden wurden geändert. Bitte erneut abgeben.")
    return plan["parts"][index]


def _legacy_part_migration(db, day, state):
    """One conscious transition for an old billed length failure, never a retry reset."""
    if "package_parts_version" in state or state.get("package_plan"):
        return False
    job = db.get(Job, state.get("job_id")) if state.get("job_id") else None
    message = ("Die KI hat die begrenzte Ausgabelänge erreicht. Die unvollständige Antwort wurde verworfen; "
               "kein automatischer Wiederholungsversuch.")
    sources = _sources(db, day)
    if (not job or job.kind != "package" or job.status != "failed" or job.error != message
            or job.child_id != day.child_id or state.get("sources") != sources
            or state.get("day_revision") != day.revision
            or job.payload.get("school_day_id") != day.id or job.payload.get("day_revision") != day.revision
            or job.payload.get("sources") != sources or job.payload.get("package_partition") is not None):
        return False
    usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
    return bool(usage and usage.child_id == day.child_id and usage.status == "failed_billed"
        and usage.cost_micros is not None and usage.cost_micros > 0)


def _prepare_parts(db, day, child, state, source_pages, *, automatic=False):
    """Bind finite plans without reopening a previously attempted legacy package."""
    from .package_partitions import build_plan
    from .school_day import package_plan

    allowed = _parts_enabled(source_pages)
    if automatic:
        from .material_review import authority as review_authority
        from .material_review import pipeline_ready

        review_authority(db, child.id, state.get("review_origin"))
        _check_sources(db, day, state)
        allowed = bool(source_pages) and all(not m.synthetic for m in source_pages) and pipeline_ready(db, day, source_pages)
    if not allowed:
        return {}
    if _current_plan(db, day, child, state):
        _part_outputs(state, state["package_plan"])
        return {key: copy.deepcopy(state[key]) for key in _PART_KEYS if key in state}
    if not any(group["selected"] for group in package_plan(db, day, child)["groups"]):
        return {}  # Already covered sources use the existing cost-free save path.
    plan = build_plan(db, day, child)
    if plan["status"] != "ready":
        raise HTTPException(409, "Die Heftseiten sind für die Teilplanung noch nicht verwendbar. Bitte zuerst die markierten Quellen prüfen.")
    if len(plan["parts"]) <= 1 and not state.get("package_plan") and not _legacy_part_migration(db, day, state):
        # This opt-in is set only when a new conscious submission starts. It is
        # carried through automatic OCR; old failed requests never acquire it.
        # Check the persisted job history as well as the state counter so a
        # restart, missing state or resubmission cannot reset legacy attempts.
        sources = _sources(db, day)
        stored = state.get("package_attempts", {}).get(_fingerprint(sources), 0)
        starts, _ = _attempt_counts(db, day.child_id, "package", sources, stored)
        if state.get("single_part_contract") is not True or starts:
            return {}
    return {"package_plan": plan, "package_config_revision": plan["config_revision"], "package_outputs": {}}


def _part_progress(state, job):
    plan = state.get("package_plan")
    if not isinstance(plan, dict) or not isinstance(plan.get("parts"), list):
        return {}
    total = len(plan["parts"])
    completed = min(total, len(set(state.get("package_outputs", {})) | set(state.get("package_publications", {}))))
    if state.get("status") == "ready":
        completed = min(total, state.get("package_completed_parts", 0))
    index = (job.payload or {}).get("package_partition") if job else None
    active = index if type(index) is int and 0 <= index < total else None
    return {"total_parts": total, "completed_parts": completed, "active_part": active}


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
    if status == "processing" and job and job.status == "failed" and not job.payload.get("material_check"):
        status, error = "failed", job.error
    current = [{"id": m.id, "revision": m.revision} for m in source_pages]
    can_retry = status in ("failed", "blocked") and bool(source_pages)
    new_part_contract = False
    if can_retry and current == state.get("sources"):
        if state.get("phase") == "extract":
            waiting = next((m for m in source_pages if m.status == "uploaded" and not m.confirmed), None)
            counts = state.get("extract_attempts", {})
            previous = counts.get(waiting.id, {}) if waiting else {}
            can_retry = not waiting or (
                _attempt_counts(db, day.child_id, "extract", [{"id": waiting.id, "revision": waiting.revision}],
                    previous.get("count", 0) if previous.get("revision") == waiting.revision else 0)[1] < MAX_ATTEMPTS
            )
        elif state.get("phase") == "package":
            child = child or db.get(Child, day.child_id)
            try:
                proposed = _prepare_parts(db, day, child, state, source_pages)
                new_part_contract = bool(proposed.get("package_plan")) and (
                    proposed["package_plan"] != state.get("package_plan")
                    or proposed["package_config_revision"] != state.get("package_config_revision"))
                if proposed.get("package_plan"):
                    plan = proposed["package_plan"]
                    _, completed = _part_outputs(proposed, plan)
                    index = next((i for i in range(len(plan["parts"])) if i not in completed), None)
                    can_retry = index is None or _attempt_counts(db, day.child_id, "package", current,
                        state.get("package_part_attempts", {}).get(_part_key(plan, index), 0),
                        partition=(plan["digest"], index))[1] < MAX_ATTEMPTS
                else:
                    can_retry = _attempt_counts(db, day.child_id, "package", current,
                        state.get("package_attempts", {}).get(_fingerprint(current), 0))[1] < MAX_ATTEMPTS
            except (HTTPException, ValueError, KeyError, TypeError, IndexError):
                can_retry = False
    from .job_failures import generation_availability, message_code

    waiting = next((m for m in source_pages if m.status == "uploaded" and not m.confirmed), None)
    # Match _advance: OCR first, package only after all sources are confirmed.
    # Reviewing saved OCR is cost-free and must remain possible at any budget.
    retry_kind = "extract" if waiting else "package" if source_pages and all(m.confirmed for m in source_pages) else None
    routing_features = None
    if can_retry and retry_kind:
        child = child or db.get(Child, day.child_id)
        from .model_routing import extraction_failed

        next_sources = [waiting] if waiting else source_pages
        routing_features = {
            "errors": 0, "uncertain": 0,
            "extraction_failed": extraction_failed(db, child.id, waiting.id) if waiting else False,
            "poor_image": any(m.uncertainties or m.quality_warnings or m.legibility in ("partial", "unreadable") for m in next_sources),
            "sources_known": bool(next_sources), "source_count": len(next_sources),
            "source_chars": sum(len(m.content or "") for m in next_sources),
            "subject_count": len({m.subject for m in next_sources}), "question_chars": 0,
        }
    blocker = generation_availability(db, db.get(Family, child.family_id), retry_kind,
        child_id=child.id, routing_features=routing_features) if can_retry and retry_kind else None
    error_code = (job.error_code if job and job.status == "failed" else None) or state.get("error_code") or (message_code(error) if error else None)
    if error_code == "unknown" and error:
        error_code = message_code(error)
    if can_retry and not blocker and error_code == "cost_preflight" and job and not new_part_contract:
        failed_usage = db.scalar(select(Usage).where(Usage.job_id == job.id).order_by(Usage.created.desc()).limit(1))
        config = db.get(ProviderConfig, 1)
        if (failed_usage and config and failed_usage.config_revision == config.revision
                and not _transport_repair(db, day, state, job, current, config)):
            blocker = {
                "code": "cost_preflight",
                "message": "Die KI-Verarbeitung muss zuerst geprüft werden. Bitte deine Eltern um Hilfe. Deine Fotos sind gespeichert.",
            }
    if blocker:
        can_retry = False
    from .package_publication import publication_data

    return {
        **publication_data(db, day, child=child),
        "status": status,
        "sources_changed": bool(state.get("package_plan") and state.get("sources") and current != state["sources"]),
        "error_code": error_code if error else None,
        "retry_blocker": blocker,
        "retry_kind": retry_kind,
        "phase": state.get("phase"),
        "completed_pages": sum(m.status in ("review", "confirmed", "unreadable") for m in source_pages),
        "total_pages": len(source_pages),
        "job": {"id": job.id, "kind": job.kind, "status": job.status} if job else None,
        "error": error,
        "can_retry": can_retry,
        **_part_progress(state, job),
    }


def submit(db, p, day, child, key, *, learning_entry_enabled=False):
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
    from .material_review import origin

    review_origin = origin(db, p, child)
    policy_changed = bool(review_origin and state.get("review_origin") != review_origin)
    same = state.get("sources") == snapshot and state.get("day_revision") == day.revision
    old_job = db.get(Job, state.get("job_id")) if state.get("job_id") else None
    status = "failed" if state.get("status") == "processing" and old_job and old_job.status == "failed" else state.get("status")
    completed_review = status == "needs_review" and all(m.confirmed for m in source_pages)
    if previous or (
        same
        and not completed_review
        and not policy_changed
        and status in ("processing", "needs_review", "needs_photo", "ready", "saved")
    ):
        return
    if db.scalar(select(Job.id).where(Job.child_id == child.id, Job.status.in_(ACTIVE))):
        raise HTTPException(409, "Für dich wird gerade noch etwas vorbereitet. Bitte kurz warten.")
    repair = None
    planning_state = dict(state)
    if status in (None, "idle", "needs_review") or (not same and status in ("failed", "blocked")):
        planning_state["single_part_contract"] = True
    part_state = _prepare_parts(db, day, child, planning_state, source_pages) if _parts_enabled(source_pages) else {}
    new_part_contract = bool(part_state) and not _current_plan(db, day, child, state)
    if same and status in ("failed", "blocked", "processing"):
        blocker = preparation_data(db, day, child).get("retry_blocker")
        if blocker and blocker.get("code") == "cost_preflight" and not new_part_contract:
            raise HTTPException(409, blocker["message"])
        from .job_failures import message_code

        failed_job = db.get(Job, state.get("job_id")) if state.get("job_id") else None
        if failed_job and (failed_job.error_code == "cost_preflight" or message_code(failed_job.error or "") == "cost_preflight"):
            old_revision = _transport_repair(db, day, state, failed_job, snapshot, db.get(ProviderConfig, 1))
            if old_revision:
                from .package_transport import REVISION
                from .security import audit

                repair = {"failed_job_id": failed_job.id, "from_revision": old_revision, "to_revision": REVISION}
                audit(db, p.user.id, "school_day.package_transport_repair", failed_job.id + ":" + REVISION)
    rate_limit(db, "school-prepare:" + p.user.id, 10, 60, commit=False)
    if day.stage == "collecting":
        day.stage = "review"
        day.revision += 1
        if part_state:
            part_state = _prepare_parts(db, day, child, {"package_plan": part_state["package_plan"]}, source_pages)
    state = {
        "run_id": uid(),
        "status": "processing",
        "phase": "extract",
        "job_id": None,
        "user_id": p.user.id,
        "session_id": p.session.id,
        "learning_entry_enabled": bool(learning_entry_enabled),
        "labs_enabled": "labs-v1" in getattr(p.session, "request_capabilities", ()),
        "family_id": child.family_id,
        "review_origin": review_origin,
        "sources": snapshot,
        "day_revision": day.revision,
        "error": None,
        "requests": [*requests, {"key": key_hash, "fingerprint": fingerprint}][-128:],
        "extract_attempts": state.get("extract_attempts", {}),
        "package_attempts": state.get("package_attempts", {}),
        "package_part_attempts": state.get("package_part_attempts", {}),
        "package_parts_version": 1,
        "single_part_contract": planning_state.get("single_part_contract") is True,
        "package_publish_requests": state.get("package_publish_requests", []),
        **part_state,
    }
    if all(m.confirmed for m in source_pages):
        state["phase"] = "package"
    if repair:
        state["transport_repair"] = repair
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
    if state.get("sources") != _sources(db, day) or state.get("day_revision") != day.revision:
        _clear_parts(state)
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
    """Called after deleting own pages, while holding Child.

    No pending inference may exist. Cancel the old coordinator intent so a tick
    selected before deletion cannot reserve another job. Keep remaining pages,
    prior attempt counts and completed learning untouched; continuing is explicit.
    """
    state = _state(day)
    _clear_parts(state)
    source_pages = _pages(db, day)
    from .study_path import source_backed_blocks

    plan = day.learning_plan or {}
    blocks = source_backed_blocks(db, day)
    if blocks != plan.get("blocks", []):
        ids = {m.id for m in source_pages}
        day.learning_plan = {**plan, "blocks": blocks,
            "extents": [extent for extent in plan.get("extents", []) if extent.get("material_id") in ids]}
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
        starts, attempts = _attempt_counts(db, child.id, "extract", [{"id": material.id, "revision": material.revision}],
            old.get("count", 0) if old.get("revision") == material.revision else 0)
        if attempts >= MAX_ATTEMPTS:
            raise ProviderError("Die Erkennung hat zweimal nicht geklappt. Bitte fotografiere die Seite neu.")
        counts[material.id] = {"revision": material.revision, "count": starts + 1}
    else:
        index = payload.get("package_partition")
        if index is None:
            counts, name = state.setdefault("package_attempts", {}), _fingerprint(state["sources"])
            starts, attempts = _attempt_counts(db, child.id, "package", state["sources"], counts.get(name, 0))
        else:
            _checked_part(db, day, child, state, index)
            plan = state["package_plan"]
            counts, name = state.setdefault("package_part_attempts", {}), _part_key(plan, index)
            starts, attempts = _attempt_counts(db, child.id, "package", state["sources"], counts.get(name, 0),
                partition=(plan["digest"], index))
        if attempts >= MAX_ATTEMPTS:
            raise ProviderError("Diese Teilrunde konnte zweimal nicht erstellt werden. Deine Seiten und fertigen Teilrunden bleiben gespeichert."
                if index is not None else "Das Paket konnte zweimal nicht erstellt werden. Deine Seiten bleiben gespeichert.")
        counts[name] = starts + 1
    payload = {
        **payload,
        "school_day_id": day.id,
        "preparation_id": state["run_id"],
        "learning_entry_enabled": kind == "package" and bool(state.get("learning_entry_enabled"))
            and (payload.get("package_partition") is None
                 or state["package_plan"]["parts"][payload["package_partition"]]["learning_entry_enabled"]),
        **({"labs_enabled": True} if kind == "package" and state.get("labs_enabled") else {}),
        "material_revision": material.revision,
    }
    job = Job(
        id=uid(),
        child_id=child.id,
        kind=kind,
        payload=payload,
        idempotency="prepare:" + state["run_id"] + ":" + kind + ":" + material.id
            + (":part:" + str(payload["package_partition"]) + ":" + str(starts)
               if payload.get("package_partition") is not None else ""),
    )
    if kind == "extract" and state.get("review_origin"):
        job.payload = {**job.payload, "auto_review_origin": state["review_origin"]}
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



def _advance_parts(db, day, child, family, state, job):
    from .package_partitions import validated_parts

    plan = state["package_plan"]
    if not _current_plan(db, day, child, state):
        raise ProviderError("Die Quellen, Planung oder KI-Einstellungen der Teilrunden wurden geändert. Bitte erneut abgeben.")
    ordered, completed = _part_outputs(state, plan)
    if job and job.payload.get("package_partition") is not None:
        index = job.payload["package_partition"]
        if (job.payload.get("package_plan_digest") != plan["digest"]
                or type(index) is not int or index not in completed):
            raise ProviderError("Ein fertiger Teilauftrag hat keinen gültigen gespeicherten Ergebnisbeleg. Bitte erneut prüfen.")
    if len(completed) == len(plan["parts"]):
        from .school_day import save_package_parts

        ordered = validated_parts(state, plan)
        published = state.get("package_publications", {})
        final_job = job or db.get(Job, ordered[-1]["job_id"] if ordered else published[str(len(plan["parts"]) - 1)]["job_id"])
        if final_job is None or final_job.status != "completed":
            raise ProviderError("Der letzte Teilauftrag ist noch nicht abgeschlossen.")
        save_package_parts(db, final_job, ordered, plan)
        # The aggregate saver may change private state; never restore stale JSON.
        state = _state(day)
        state.pop("package_outputs", None)
        _notify(db, day, state, "ready")
        _write(day, state, status="ready", phase="complete", job_id=final_job.id,
            day_revision=day.revision, package_completed_parts=len(plan["parts"]), error=None, error_code=None)
        return
    if db.scalar(select(Job.id).where(Job.child_id == child.id, Job.status.in_(ACTIVE))):
        raise ProviderError("Für dieses Kind läuft bereits ein anderer Auftrag. Bitte später erneut versuchen.")
    index = next(i for i in range(len(plan["parts"])) if i not in completed)
    part = plan["parts"][index]
    _queue(db, day, child, family, state, "package", {
        "material_id": part["sources"][0]["id"], "day_revision": day.revision,
        "sources": state["sources"], "groups": [part["group"]],
        "planning_fingerprint": plan["planning_fingerprint"],
        "package_partition": index, "package_plan_digest": plan["digest"],
        "package_partition_sources": part["sources"],
    })


def _advance(db, day):
    state = _state(day)
    if state.get("status") != "processing":
        return
    child, family = authority(db, day, state)
    _check_sources(db, day, state)
    if state.get("package_plan") and not _current_plan(db, day, child, state):
        raise ProviderError("Die Quellen, Planung oder KI-Einstellungen der Teilrunden wurden geändert. Bitte erneut abgeben.")
    job = db.get(Job, state.get("job_id")) if state.get("job_id") else None
    if job:
        if job.status in ACTIVE:
            return
        if job.status == "failed" and not job.payload.get("material_check"):
            if state.get("review_origin") and job.kind == "extract":
                from .material_review import hold_first_failure

                hold_first_failure(db, day, state, job)
            else:
                _write(day, state, status="failed", error=job.error)
                return
        if job.kind == "package" and job.status == "completed" and state.get("package_plan"):
            _advance_parts(db, day, child, family, state, job)
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
    from .material_review import advance_day, held, pipeline_ready

    if state.get("review_origin") and advance_day(db, day, child, family, state, source_pages):
        return
    waiting = next((m for m in source_pages if m.status == "uploaded" and not m.confirmed
                    and not (state.get("review_origin") and held(db, m))), None)
    if waiting:
        _queue(db, day, child, family, state, "extract", {"material_id": waiting.id})
        return
    if not pipeline_ready(db, day, source_pages):
        status = "needs_photo" if any(m.status == "unreadable" for m in source_pages) else "needs_review"
        _notify(db, day, state, status)
        _write(day, state, status=status, phase="review", job_id=None, error=None)
        return
    from .school_day import MAX_CONTENT, package_plan, planning_fingerprint
    from .source_lineage import usable_source

    if not any(usable_source(db, material) for material in source_pages):
        if state.get("review_origin"):
            # Photos remain in the collection even when none is a safe learning
            # source. This completes storage, never an invented learning path.
            if day.stage != "ready":
                day.stage = "ready"
                day.revision += 1
            _write(day, state, status="saved", phase="complete", job_id=None,
                   day_revision=day.revision, error=None)
            _notify(db, day, state, "saved")
            return
        raise ProviderError("Die Heftseiten enthalten noch keine verwendbare Lehrgrundlage. Bitte unsichere oder fehlerhafte Stellen zuerst prüfen.")

    if sum(len(m.content) for m in source_pages) > MAX_CONTENT:
        raise ProviderError("Der Text ist für ein Paket zu umfangreich. Bitte mit deinen Eltern den Stoff eingrenzen.")
    preview = package_plan(db, day, child)
    selected = [g for g in preview["groups"] if g["selected"]]
    if not selected:
        if any(group.get("blocked_reason") for group in preview["groups"]):
            raise ProviderError("Die neuen Heftquellen sind noch ungeklärt. Bitte zuerst die markierten Stellen prüfen.")
        _saved(db, day, state)
        return
    if state.get("review_origin") and not state.get("package_plan"):
        # The explicit automatic submission already authorized finite package
        # preparation. Bind the same existing part plan only after all image
        # checks have settled; never fall back to one giant legacy request.
        part_state = _prepare_parts(db, day, child, state, source_pages, automatic=True)
        if part_state:
            state.update(part_state)
    if state.get("package_plan"):
        _advance_parts(db, day, child, family, state, job)
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
            before = _state(day)
            _advance(db, day)
            return before != _state(day)
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
                from .job_failures import failure_code

                if state.get("package_plan") and not _current_plan(db, day, db.get(Child, day.child_id), state):
                    _clear_parts(state)
                _write(day, state, status="blocked", error=message[:500], error_code=failure_code(error))


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
    changed = False
    for day_id in ids:
        changed = advance(day_id) or changed
    return changed
