"""Private finite package parts over complete eligible pages; never dispatches AI.

The coordinator owns authority, reservations, retries and before/after guards.
Only fully validated provider output may enter the private receipt store below.
Neither this plan nor its outputs are an API projection or learning evidence.
"""
import copy
import hashlib
import json

TARGET_SOURCE_CHARS = 6000
MAX_SOURCE_CHARS = 24000
MAX_PAGES = 3
VERSION = 1


def _digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False,
        separators=(",", ":"), allow_nan=False).encode()).hexdigest()


def _require(value, message):
    if not value:
        raise ValueError(message)


def _partition(*, school_day_id, child_id, day_revision, groups, sources, planning_fingerprint, config_revision):
    """Compile server-projected sources, preserving page/group order and text."""
    _require(type(config_revision) is int and config_revision >= 1, "Ungültige KI-Konfigurationsrevision.")
    _require(type(day_revision) is int and day_revision >= 1, "Ungültige Schultagsrevision.")
    by_id = {source["id"]: source for source in sources}
    _require(len(by_id) == len(sources), "Eine Heftseite darf nur einmal im Schultag vorkommen.")
    seen_groups, seen_pages = set(), set()
    parts, blocked, excluded = [], [], []
    signatures = [{key: value for key, value in source.items() if key != "content"} | {
        "content_sha256": _digest(source["content"])} for source in sources]
    for group in groups:
        gid, subject = group["id"], group["subject"]
        _require(gid not in seen_groups and isinstance(subject, str) and bool(subject.strip()),
                 "Die Fachauswahl ist nicht eindeutig.")
        seen_groups.add(gid)
        ids = group["material_ids"]
        _require(isinstance(ids, list) and len(set(ids)) == len(ids), "Doppelte Quellen in einer Fachgruppe.")
        eligible = set(group.get("eligible_material_ids", ids))
        batches, batch, chars = [], [], 0
        for mid in ids:
            _require(mid not in seen_pages, "Eine Heftseite darf nicht mehreren Fachgruppen angehören.")
            seen_pages.add(mid)
            source = by_id.get(mid)
            if source is None:
                blocked.append({"id": mid, "reason": "source_missing"})
                continue
            _require(source["subject"].casefold() == subject.casefold(), "Eine Heftseite gehört zu einem anderen Fach.")
            if mid not in eligible or not source["content"].strip():
                excluded.append({"id": mid, "revision": source["revision"], "reason": "source_unusable"})
                continue
            size = len(source["content"])
            if size > MAX_SOURCE_CHARS:
                blocked.append({"id": mid, "revision": source["revision"], "reason": "source_exceeds_hard_limit",
                                "source_chars": size})
                continue
            if batch and (len(batch) >= MAX_PAGES or chars + size > TARGET_SOURCE_CHARS):
                batches.append(batch)
                batch, chars = [], 0
            batch.append(source)
            chars += size
            if size > TARGET_SOURCE_CHARS:
                batches.append(batch)
                batch, chars = [], 0
        if batch:
            batches.append(batch)
        if not batches:
            blocked.append({"group_id": gid, "reason": "no_usable_sources"})
        for number, batch in enumerate(batches):
            subset = [source["id"] for source in batch]
            local = copy.deepcopy(group)
            local.update(material_ids=subset, topics=list(dict.fromkeys(source["topic"] for source in batch)))
            for key in ("new_material_ids", "eligible_new_material_ids", "eligible_material_ids"):
                if key in local:
                    local[key] = [mid for mid in local[key] if mid in subset]
            if "excluded_sources" in local:
                local["excluded_sources"] = [item for item in local["excluded_sources"] if item.get("material_id") in subset]
            refs = [{"id": source["id"], "revision": source["revision"]} for source in batch]
            signature = _digest([value for value in signatures if value["id"] in subset])
            binding = {"school_day_id": school_day_id, "child_id": child_id, "group_id": gid,
                       "subject": subject, "source_signature": signature, "config_revision": config_revision,
                       "planning_fingerprint": planning_fingerprint, "learning_entry_enabled": number == 0}
            parts.append({"index": len(parts), "id": _digest(binding)[:32], "group": local, "sources": refs,
                          "source_signature": signature, "source_chars": sum(len(source["content"]) for source in batch),
                          "question_count": 2, "learning_entry_enabled": number == 0,
                          "oversize_single_page": len(batch) == 1 and len(batch[0]["content"]) > TARGET_SOURCE_CHARS})
    result = {"version": VERSION, "school_day_id": school_day_id, "child_id": child_id, "day_revision": day_revision,
              "config_revision": config_revision, "planning_fingerprint": planning_fingerprint,
              "source_signature": _digest(signatures), "selected_group_ids": [group["id"] for group in groups],
              "parts": parts, "excluded_sources": excluded, "blocked_sources": blocked,
              "status": "blocked" if blocked or not parts else "ready"}
    return {**result, "digest": _digest(result)}


def build_plan(db, day, child, selected_groups=None, *, config_revision=None):
    """Read-only server plan; capability still gates each part's entry flag."""
    from .db import ProviderConfig
    from .school_day import package_plan, pages, planning_fingerprint
    from .source_lineage import learning_source

    _require(day.child_id == child.id, "Dieser Schultag gehört zu einem anderen Kind.")
    if selected_groups is None:
        selected_groups = [group for group in package_plan(db, day, child)["groups"] if group["selected"]]
    if config_revision is None:
        config_revision = db.get(ProviderConfig, 1).revision
    sources = []
    for material in pages(db, day):
        _require(material.child_id == child.id and type(material.revision) is int and material.revision >= 1,
                 "Die Heftquellen sind nicht mehr gültig.")
        safe = learning_source(db, material, revision=material.revision)
        _require(safe["material_id"] == material.id and safe["revision"] == material.revision,
                 "Die geprüfte Quellenfassung wurde geändert.")
        sources.append({"id": material.id, "revision": material.revision, "subject": material.subject,
                        "topic": material.topic, "content": safe["content"],
                        "source_refs": safe.get("source_refs", []), "exclusions": safe.get("exclusions", []),
                        "policy_version": safe.get("policy_version"), "reading_status": safe.get("reading_status")})
    return _partition(school_day_id=day.id, child_id=child.id, day_revision=day.revision,
                      groups=selected_groups, sources=sources, planning_fingerprint=planning_fingerprint(db, child),
                      config_revision=config_revision)


def check_plan(db, day, child, plan):
    """Reject changed sources, safe-text decisions, planning or provider settings."""
    return build_plan(db, day, child) == plan


def _checked_plan(plan):
    _require(isinstance(plan, dict) and plan.get("version") == VERSION and plan.get("status") == "ready",
             "Die Teilplanung ist noch nicht vollständig nutzbar.")
    _require(plan.get("digest") == _digest({key: value for key, value in plan.items() if key != "digest"}),
             "Die Teilplanung wurde verändert.")
    _require([part["index"] for part in plan["parts"]] == list(range(len(plan["parts"])))
             and len({part["id"] for part in plan["parts"]}) == len(plan["parts"]), "Die Teilplanung ist nicht eindeutig.")


def _checked_output(part, output):
    from .schemas import PackageOutput

    data = PackageOutput.model_validate(output).model_dump(mode="json")
    _require(len(data["units"]) == 1 and data["units"][0]["group_id"] == part["group"]["id"]
             and data["units"][0]["subject"] == part["group"]["subject"]
             and len(data["units"][0]["questions"]) == part["question_count"] == 2,
             "Die erzeugte Teilrunde entspricht nicht ihrer Fach- und Aufgabenplanung.")
    _require(len({question["id"] for question in data["units"][0]["questions"]}) == 2,
             "Die Teilrunde enthält doppelte Aufgabenkennungen.")
    return data


def store_validated_part(state, plan, index, output, *, job_id, provider, model, config_revision, context=None):
    """Return a new private state; callers MUST run all source/visual/entry guards first.

    Never replace a successful receipt or expose this state via day/job APIs.
    No unit/attempt/activity/reservation is created here.
    """
    _checked_plan(plan)
    _require(type(index) is int and 0 <= index < len(plan["parts"]), "Unbekannte Teilrunde.")
    _require(config_revision == plan["config_revision"] and type(config_revision) is int,
             "Die KI-Konfiguration der Teilrunde wurde geändert.")
    _require(state.get("package_plan", plan) == plan
             and state.get("package_config_revision", config_revision) == config_revision,
             "Diese Teilrunde gehört zu einer anderen Vorbereitung.")
    _require(isinstance(job_id, str) and bool(job_id) and len(job_id) <= 32
             and isinstance(provider, str) and 1 <= len(provider) <= 20
             and isinstance(model, str) and 1 <= len(model) <= 160, "Der KI-Auftragsbeleg ist nicht gültig.")
    part = plan["parts"][index]
    data = _checked_output(part, output)
    context = {} if context is None else context
    _require(isinstance(context, dict) and set(context) <= {"visual_context", "learning_entry", "catalog_assignment"},
             "Unzulässiger privater Teilrundenkontext.")
    receipt = {"plan_digest": plan["digest"], "part_id": part["id"], "source_signature": part["source_signature"],
               "job_id": job_id, "provider": provider, "model": model, "config_revision": config_revision,
               "output": data, "output_sha256": _digest(data), "context": copy.deepcopy(context),
               "context_sha256": _digest(context)}
    receipt["receipt_sha256"] = _digest(receipt)
    result = copy.deepcopy(state)
    previous = result.setdefault("package_outputs", {}).get(str(index))
    _require(previous is None or previous == receipt, "Eine fertige Teilrunde darf nicht überschrieben werden.")
    result.update(package_plan=copy.deepcopy(plan), package_config_revision=config_revision)
    result["package_outputs"][str(index)] = receipt
    return result


def validated_parts(state, plan, config_revision=None, *, require_complete=True):
    """Read bound receipts; partial mode is for the coordinator, never final save."""
    _checked_plan(plan)
    revision = state.get("package_config_revision") if config_revision is None else config_revision
    _require(state.get("package_plan") == plan and revision == plan["config_revision"]
             and state.get("package_config_revision") == revision, "Der Vorbereitungsstand wurde geändert.")
    outputs = state.get("package_outputs", {})
    indices = {str(part["index"]) for part in plan["parts"]}
    _require(set(outputs) <= indices and (not require_complete or set(outputs) == indices),
             "Noch nicht alle Teilrunden sind fertig.")
    result = []
    for part in plan["parts"]:
        if str(part["index"]) not in outputs:
            continue
        receipt = outputs[str(part["index"])]
        _require(receipt["receipt_sha256"] == _digest({key: value for key, value in receipt.items() if key != "receipt_sha256"})
                 and receipt["plan_digest"] == plan["digest"] and receipt["part_id"] == part["id"]
                 and receipt["source_signature"] == part["source_signature"] and receipt["config_revision"] == revision
                 and receipt["output_sha256"] == _digest(receipt["output"])
                 and isinstance(receipt["context"], dict)
                 and set(receipt["context"]) <= {"visual_context", "learning_entry", "catalog_assignment"}
                 and receipt["context_sha256"] == _digest(receipt["context"]), "Ein Teilrundenbeleg ist nicht mehr gültig.")
        result.append({"index": part["index"], "part_id": part["id"],
                       "group": copy.deepcopy(part["group"]), "output": _checked_output(part, receipt["output"]),
                       "context": copy.deepcopy(receipt["context"]),
                       **{key: receipt[key] for key in ("job_id", "provider", "model", "config_revision")}})
    return result
