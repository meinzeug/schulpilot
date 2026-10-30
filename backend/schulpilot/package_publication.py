"""Cost-free publication of a validated package prefix, never inference.

Callers hold Child. Existing rounds are read only; no Unit lock is acquired
following Child. Original source/config/actor guards remain authoritative.
"""
import copy
import re

from fastapi import HTTPException
from sqlalchemy import select

from .db import Child, Job, LearningUnit, Session, UnitSource, Usage, User, now
from .package_partitions import _digest, _require
from .providers import ProviderError


def publication_records(state, plan):
    records = state.get("package_publications", {})
    _require(isinstance(records, dict), "Ungültige Veröffentlichung der Teilrunden.")
    for key, row in records.items():
        _require(isinstance(row, dict) and key in {str(part["index"]) for part in plan["parts"]},
                 "Unbekannte veröffentlichte Teilrunde.")
        part = plan["parts"][int(key)]
        _require(row.get("sha256") == _digest({k: v for k, v in row.items() if k != "sha256"})
            and row.get("plan_digest") == plan["digest"] and row.get("part_id") == part["id"]
            and row.get("source_signature") == part["source_signature"]
            and row.get("config_revision") == plan["config_revision"]
            and type(row.get("package_version")) is int
            and re.fullmatch(r"[a-f0-9]{32}", row.get("unit_id", ""))
            and re.fullmatch(r"[a-f0-9]{32}", row.get("job_id", "")),
            "Die Veröffentlichung gehört nicht zum gespeicherten Teilplan.")
    return records


def _unit_digest(unit):
    return _digest({key: getattr(unit, key) for key in
        ("child_id", "school_day_id", "material_id", "subject", "topic", "explanation", "questions",
         "estimated_minutes", "synthetic", "provider", "model", "package_version")})


def verified_publications(db, day, plan):
    from .visual_reference_models import UnitVisualSnapshot

    records = publication_records(day.preparation or {}, plan)
    for key, row in records.items():
        part, unit = plan["parts"][int(key)], db.get(LearningUnit, row["unit_id"])
        if row.get("deleted"):
            _require(unit is None, "Eine gelöschte Teilrunde darf nicht wiederverwendet werden.")
            continue
        job = db.get(Job, row["job_id"])
        usage = db.scalar(select(Usage).where(Usage.job_id == row["job_id"]))
        _require(unit is not None and unit.child_id == day.child_id and unit.school_day_id == day.id
            and unit.package_version == row["package_version"] and _unit_digest(unit) == row["unit_sha256"]
            and job is not None and job.child_id == day.child_id and job.status == "completed"
            and job.kind == "package" and job.payload.get("package_plan_digest") == plan["digest"]
            and job.payload.get("package_partition") == int(key)
            and usage is not None and usage.child_id == day.child_id
            and usage.config_revision == plan["config_revision"], "Eine veröffentlichte Teilrunde ist nicht mehr gültig.")
        links = [{"id": link.material_id, "revision": link.revision}
                 for link in db.scalars(select(UnitSource).where(UnitSource.unit_id == unit.id))]
        _require(sorted(links, key=lambda ref: ref["id"]) == sorted(part["sources"], key=lambda ref: ref["id"]),
                 "Die Quellen einer veröffentlichten Teilrunde wurden geändert.")
        visual = db.get(UnitVisualSnapshot, unit.id)
        _require(not row["visual_required"] or visual is not None and visual.status == "ready",
                 "Die geprüfte Grafik einer veröffentlichten Teilrunde fehlt.")
    return records


def _prefix(state, plan):
    from .package_partitions import validated_parts

    values = {value["index"]: value for value in validated_parts(state, plan, require_complete=False)}
    publications = publication_records(state, plan)
    result = []
    for part in plan["parts"]:
        if str(part["index"]) in publications:
            continue
        if part["index"] not in values:
            break
        result.append(values[part["index"]])
    return result


def publication_data(db, day, *, child=None):
    """Read-only, closed public progress; never expose raw staged answers."""
    state, empty = day.preparation or {}, {"ready_prefix_parts": 0, "published_parts": 0,
        "can_publish_parts": False, "publication_plan_digest": None, "published_unit_ids": []}
    plan = state.get("package_plan")
    if not isinstance(plan, dict):
        return empty
    try:
        records = verified_publications(db, day, plan)
        visible = [row["unit_id"] for row in records.values() if not row.get("deleted")]
        result = {**empty, "published_parts": len(records), "published_unit_ids": visible}
        if (state.get("phase") != "package" and state.get("status") != "postponed") or day.stage != "review":
            return result
        from .school_preparation import _check_sources, _current_plan, authority

        child = child or db.get(Child, day.child_id)
        authority(db, day, state)
        _check_sources(db, day, state)
        if not _current_plan(db, day, child, state):
            return result
        ready = _prefix(state, plan)
        return {**result, "ready_prefix_parts": len(ready), "can_publish_parts": bool(ready),
                "publication_plan_digest": plan["digest"] if ready else None}
    except (ValueError, KeyError, TypeError, HTTPException, ProviderError):
        return empty


def _attach_path(db, day, new_units):
    from .study_path import ensure_plan

    ensure_plan(db, day)
    path = copy.deepcopy(day.learning_plan)
    known = {block.get("unit_id") for block in path["blocks"]}
    additions = [{"id": "unit-" + unit.id, "title": unit.topic, "phase": "learning", "label": "Erste Runde",
        "subject": unit.subject, "question_count": len(unit.questions), "unit_id": unit.id, "job_id": None}
        for unit in new_units if unit.id not in known]
    # Saved rounds are inserted before unprepared optional stages. Existing
    # block IDs, jobs, units and all learner state remain unchanged.
    if additions:
        first_pending = next((i for i, block in enumerate(path["blocks"]) if not block.get("unit_id")), len(path["blocks"]))
        path["blocks"][first_pending:first_pending] = additions
        day.learning_plan = path


def publish_prefix(db, day, child, plan, *, complete=False):
    from .catalog_ai import remember as remember_catalog
    from .learning import record
    from .learning_entry import guard_entry_context, remember_generated
    from .model_routing import job_config
    from .package_part_output import validate as validate_part_output
    from .package_partitions import check_plan
    from .schemas import PackageOutput
    from .school_day import validate_package_sources
    from .school_preparation import _state, _write
    from .visual_reference_models import UnitVisualSnapshot
    from .visual_references import remember as remember_visuals
    from .visual_references import validate_output as validate_visuals

    state = _state(day)
    _require(check_plan(db, day, child, plan), "Die Quellen oder Vorgaben des Lernpakets wurden geändert.")
    published = copy.deepcopy(verified_publications(db, day, plan))
    ready = _prefix(state, plan)
    _require(bool(ready) or complete and len(published) == len(plan["parts"]), "Noch keine fertige Teilrunde verfügbar.")
    if complete:
        _require(len(ready) + len(published) == len(plan["parts"]), "Noch nicht alle Teilrunden sind fertig.")
    version = state.get("package_publication_version")
    if version is None:
        day.package_version += 1
        version = day.package_version
    _require(type(version) is int and version == day.package_version, "Die Paketversion wurde geändert.")
    units = []
    for receipt in ready:
        index = receipt["index"]
        job = db.get(Job, receipt["job_id"])
        usage = db.scalar(select(Usage).where(Usage.job_id == receipt["job_id"]))
        _require(job is not None and job.status == "completed" and job.kind == "package"
            and job.child_id == child.id and job.payload.get("package_partition") == index
            and job.payload.get("package_plan_digest") == plan["digest"]
            and usage is not None and usage.child_id == child.id and usage.config_revision == plan["config_revision"],
            "Ein Lernpaketteil gehört nicht zum aktuellen geprüften Auftrag.")
        job_config(db, job)
        _, source_pages = validate_package_sources(db, job)
        data, context, group = receipt["output"], receipt["context"], receipt["group"]
        # All retained private snapshots are independently revalidated before
        # publication, including source/entry guards after any inference.
        validate_part_output(data)
        validate_visuals(db, data, context)
        guard_entry_context(db, child, context, [material for material in source_pages if material.id in group["material_ids"]])
        value = PackageOutput.model_validate(data).units[0]
        unit = LearningUnit(child_id=child.id, school_day_id=day.id, material_id=group["material_ids"][0],
            estimated_minutes=group["estimated_minutes"], synthetic=False, provider=receipt["provider"], model=receipt["model"],
            package_version=version, **value.model_dump(exclude={"group_id", "explanation_steps"}))
        db.add(unit)
        db.flush()
        for material in source_pages:
            if material.id in group["material_ids"]:
                db.add(UnitSource(unit_id=unit.id, material_id=material.id, revision=material.revision))
        db.flush()
        remember_visuals(db, unit, data["units"][0], context)
        db.flush()
        visual = db.get(UnitVisualSnapshot, unit.id)
        required = bool(context.get("visual_context", {}).get("required"))
        _require(not required or visual is not None and visual.status == "ready", "Die geprüfte Grafik eines Lernpaketteils fehlt noch.")
        remember_generated(db, unit, context, group_id=value.group_id)
        remember_catalog(db, "unit", unit, context.get("catalog_assignment"))
        stored = state["package_outputs"].pop(str(index))
        entry = {"unit_id": unit.id, "job_id": job.id, "part_id": plan["parts"][index]["id"],
            "plan_digest": plan["digest"], "source_signature": plan["parts"][index]["source_signature"],
            "config_revision": plan["config_revision"], "package_version": version, "unit_sha256": _unit_digest(unit),
            "receipt_sha256": stored["receipt_sha256"], "output_sha256": stored["output_sha256"],
            "context_sha256": stored["context_sha256"], "visual_required": required, "deleted": False}
        published[str(index)] = {**entry, "sha256": _digest(entry)}
        units.append(unit)
        record(db, child.id, "unit_created", {"subject": unit.subject, "topic": unit.topic, "synthetic": False,
            "school_day_id": day.id, "package_partition": index}, unit.id)
    state.update(package_publications=published, package_publication_version=version)
    done = len(published) == len(plan["parts"])
    if done:
        day.stage = "ready"
        state.pop("package_outputs", None)
        record(db, child.id, "school_day_ready", {"page_count": len(plan["parts"]), "unit_count": len(published),
            "package_parts": len(published)})
    _write(day, state)
    # The path must see the persisted, server-generated prerequisite roles.
    db.flush()
    _attach_path(db, day, units)
    return {"unit_ids": [unit.id for unit in units], "all_unit_ids": [published[str(i)]["unit_id"]
            for i in range(len(plan["parts"])) if str(i) in published and not published[str(i)].get("deleted")],
            "published_parts": len(published), "total_parts": len(plan["parts"]), "complete": done}


def publish_requested(db, p, day, child, plan_digest, key):
    from .school_preparation import _check_sources, _state, _write, authority
    from .security import Principal, child_access, digest, rate_limit

    actor = db.get(User, p.user.id, populate_existing=True)
    session = db.get(Session, p.session.id, populate_existing=True)
    if (not actor or not actor.verified or actor.disabled or not session or session.revoked
            or session.user_id != actor.id or session.expires <= now() or now() - session.seen > 7 * 86400):
        raise HTTPException(401, "Bitte erneut anmelden.")
    child = child_access(db, Principal(actor, session), child.id, write=actor.role == "parent")
    state = _state(day)
    authority(db, day, state)
    _check_sources(db, day, state)
    plan = state.get("package_plan")
    if not plan or plan["digest"] != plan_digest:
        raise HTTPException(409, "Der vorbereitete Lernweg wurde geändert. Bitte neu laden.")
    requested = digest(actor.id + ":" + key)
    previous = next((row for row in state.get("package_publish_requests", []) if row["key"] == requested), None)
    if previous:
        if previous["plan_digest"] != plan_digest:
            raise HTTPException(409, "Dieser Anfrageschlüssel gehört zu einem anderen Lernweg.")
        return previous["result"]
    if (state.get("phase") != "package" and state.get("status") != "postponed") or day.stage != "review":
        raise HTTPException(409, "Es gibt keine neuen fertigen Teilrunden zum Freigeben.")
    rate_limit(db, "package-publish:" + actor.id, 30, 60, commit=False)
    result = publish_prefix(db, day, child, plan)
    state = _state(day)
    if result["complete"]:
        from .school_preparation import _notify

        _notify(db, day, state, "ready")
        state.update(status="ready", phase="complete", package_completed_parts=len(plan["parts"]), error=None, error_code=None)
    state["package_publish_requests"] = [*state.get("package_publish_requests", []),
        {"key": requested, "plan_digest": plan_digest, "result": result}][-128:]
    _write(day, state)
    return result


def mark_deleted(db, day, ids):
    """Called by existing Unit→Child erasure; never resurrect a deleted round."""
    state = copy.deepcopy(day.preparation or {})
    changed = False
    for row in state.get("package_publications", {}).values():
        if row["unit_id"] in ids:
            row["deleted"] = True
            row["sha256"] = _digest({k: v for k, v in row.items() if k != "sha256"})
            changed = True
    if changed:
        day.preparation = state
