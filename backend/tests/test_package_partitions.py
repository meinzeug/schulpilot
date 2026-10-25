"""Synthetic finite package plans and private receipts; no provider dispatch."""
import copy
import json

import pytest
from schulpilot import package_partitions as parts
from schulpilot.db import DB, Activity, Child, Job, Material, ProviderConfig, SchoolDay, Usage
from sqlalchemy import func, select


def source(index, chars=1000, subject="Englisch"):
    return {"id": f"{index + 1:032x}", "revision": 1, "subject": subject, "topic": f"Künstliches Thema {index}",
            "content": (f"Private künstliche Quelle {index}: CO ≠ Co; 😀 é e\u0301. " + "x" * chars)[:chars],
            "source_refs": [{"material_id": f"{index + 1:032x}", "revision": 1, "block_id": "b1"}],
            "exclusions": [], "policy_version": 1, "reading_status": "not_reported"}


def group(sources, gid="g1"):
    ids = [item["id"] for item in sources]
    return {"id": gid, "subject": sources[0]["subject"], "material_ids": ids, "eligible_material_ids": ids,
            "new_material_ids": ids, "eligible_new_material_ids": ids, "estimated_minutes": 8,
            "topics": [item["topic"] for item in sources], "excluded_sources": [], "selected": True}


def plan(sources, groups=None, **values):
    return parts._partition(school_day_id=values.get("school_day_id", "d" * 32),
        child_id=values.get("child_id", "c" * 32), day_revision=values.get("day_revision", 1),
        groups=groups if groups is not None else [group(sources)], sources=sources,
        planning_fingerprint=values.get("planning_fingerprint", "p" * 64),
        config_revision=values.get("config_revision", 32))


def output(part):
    question = {"id": "q1", "type": "short", "prompt": "Was heißt cat?", "options": [], "answer": "Katze",
                "accepted": [], "hints": ["Das Tier miaut."], "explanation": "Cat heißt Katze."}
    return {"units": [{"group_id": part["group"]["id"], "subject": part["group"]["subject"],
        "topic": "Künstliche Tierwörter", "explanation": "Eigene synthetische Einführung.",
        "questions": [question, {**question, "id": "q2", "prompt": "Was heißt dog?", "answer": "Hund"}]}]}


def save(state, planned, index, **kwargs):
    return parts.store_validated_part(state, planned, index, output(planned["parts"][index]),
        job_id=f"{index + 200:032x}", provider="synthetic", model="synthetic-model", config_revision=32, **kwargs)


def test_23_whole_pages_preserve_all_sources_no_text_in_private_plan():
    sources = [source(i, 1000) for i in range(23)]
    old = copy.deepcopy(sources)
    value = plan(sources)
    assert value == plan(sources) and sources == old
    assert [len(part["sources"]) for part in value["parts"]] == [3] * 7 + [2]
    assert [ref for part in value["parts"] for ref in part["sources"]] == [
        {"id": row["id"], "revision": row["revision"]} for row in sources]
    assert all(part["question_count"] == 2 for part in value["parts"])
    assert [part["learning_entry_enabled"] for part in value["parts"]] == [True] + [False] * 7
    assert "Private künstliche Quelle" not in json.dumps(value, ensure_ascii=False)


def test_whole_oversize_page_is_alone_up_to_existing_hard_limit():
    sources = [source(i, size) for i, size in enumerate([3000, 3000, 1, 6001, 24000, 2])]
    value = plan(sources)
    assert value["status"] == "ready" and not value["blocked_sources"]
    assert [part["source_chars"] for part in value["parts"]] == [6000, 1, 6001, 24000, 2]
    assert [part["oversize_single_page"] for part in value["parts"]] == [False, False, True, True, False]
    assert all(len(part["sources"]) == 1 for part in value["parts"] if part["oversize_single_page"])


def test_multisubject_parts_never_mix_subjects_or_repeat_entry_per_subject():
    english = [source(i) for i in range(4)]
    german = [source(i + 10, subject="Deutsch") for i in range(5)]
    value = plan(english + german, [group(english), group(german, "g2")])
    assert [part["group"]["id"] for part in value["parts"]] == ["g1", "g1", "g2", "g2"]
    assert [part["learning_entry_enabled"] for part in value["parts"]] == [True, False, True, False]
    for part in value["parts"]:
        assert part["group"]["material_ids"] == [ref["id"] for ref in part["sources"]]
        assert set(part["group"]["topics"]) <= set(group(english + german)["topics"])


@pytest.mark.parametrize("field,value", [("content", "Anderer unveränderter Wortlaut"), ("revision", 2),
    ("topic", "Anderes Thema"), ("exclusions", [{"block_id": "b1", "reason": "student_work"}])])
def test_same_revision_safety_or_literal_change_invalidates_part(field, value):
    sources = [source(0)]
    old = plan(sources)
    sources[0][field] = value
    new = plan(sources)
    assert old["digest"] != new["digest"] and old["source_signature"] != new["source_signature"]
    assert old["parts"][0]["source_signature"] != new["parts"][0]["source_signature"]


@pytest.mark.parametrize("field,value", [("child_id", "e" * 32), ("school_day_id", "f" * 32),
    ("config_revision", 33), ("planning_fingerprint", "q" * 64), ("day_revision", 2)])
def test_plan_digest_owner_day_configuration_and_parent_plan_bound(field, value):
    assert plan([source(0)])["digest"] != plan([source(0)], **{field: value})["digest"]


def test_unusable_missing_and_hard_oversize_are_explicit_without_silent_clipping():
    for sources in ([source(0, 24001)], [{**source(0), "content": ""}]):
        value = plan(sources)
        assert value["status"] == "blocked" and value["blocked_sources"]
        assert value["parts"] == []
    value = plan([source(0)], [{**group([source(0)]), "material_ids": ["missing"]}])
    assert value["status"] == "blocked" and value["blocked_sources"][0]["reason"] == "source_missing"


def test_store_partial_and_complete_receipts_are_immutable_idempotent_and_bound():
    planned = plan([source(i) for i in range(4)])
    original = {"user_id": "parent", "requests": [{"key": "existing"}]}
    state = save(original, planned, 0, context={"visual_context": {"private": "ONLY SYNTHETIC SOURCE"},
        "learning_entry": {"units": []}, "catalog_assignment": None})
    assert original == {"user_id": "parent", "requests": [{"key": "existing"}]}
    assert save(state, planned, 0, context=state["package_outputs"]["0"]["context"]) == state
    with pytest.raises(ValueError):
        parts.validated_parts(state, planned)
    partial = parts.validated_parts(state, planned, require_complete=False)
    assert len(partial) == 1 and partial[0]["index"] == 0
    assert partial[0]["context"] == state["package_outputs"]["0"]["context"]
    complete = save(state, planned, 1)
    assert [row["index"] for row in parts.validated_parts(complete, planned)] == [0, 1]
    partial[0]["context"].clear()
    assert state["package_outputs"]["0"]["context"]


@pytest.mark.parametrize("field,value", [("job_id", "different"), ("source_signature", "x"),
    ("config_revision", 33), ("context", {"visual_context": {"private": "changed"}}),
    ("output", {"units": []}), ("plan_digest", "x")])
def test_tampered_receipt_is_rejected(field, value):
    planned = plan([source(0)])
    state = save({}, planned, 0)
    state["package_outputs"]["0"][field] = value
    with pytest.raises(ValueError):
        parts.validated_parts(state, planned)


@pytest.mark.parametrize("fault", ["group", "subject", "count", "duplicate", "context", "config", "overwrite"])
def test_wrong_partial_data_cannot_be_stored_or_replace_success(fault):
    planned = plan([source(0)])
    data = output(planned["parts"][0])
    if fault == "group":
        data["units"][0]["group_id"] = "g2"
    elif fault == "subject":
        data["units"][0]["subject"] = "Deutsch"
    elif fault == "count":
        data["units"][0]["questions"].pop()
    elif fault == "duplicate":
        data["units"][0]["questions"][1]["id"] = "q1"
    old = save({}, planned, 0) if fault == "overwrite" else {}
    with pytest.raises(ValueError):
        parts.store_validated_part(old, planned, 0, data, job_id="different-job", provider="synthetic",
            model="synthetic-model", config_revision=33 if fault == "config" else 32,
            context={"other_private_field": "forbidden"} if fault == "context" else None)


def test_real_server_plan_is_readonly_and_detects_same_revision_source_change(household):
    _, child_data = household
    with DB.begin() as db:
        child = db.get(Child, child_data["id"])
        day = SchoolDay(child_id=child.id, school_date="2026-10-25", stage="review", revision=1)
        db.add(day)
        db.flush()
        materials = [Material(child_id=child.id, school_day_id=day.id, page_number=i + 1, subject="Englisch",
            title="Künstliches Klassenheft", topic=f"Tiere {i}", content="Cat heißt Katze. Dog heißt Hund.",
            confirmed=True, status="confirmed", purpose="notebook") for i in range(4)]
        db.add_all(materials)
        db.flush()
        day_id, child_id, mid = day.id, child.id, materials[0].id
    with DB() as db:
        day, child = db.get(SchoolDay, day_id), db.get(Child, child_id)
        counts = [db.scalar(select(func.count()).select_from(model)) for model in (Job, Usage, Activity)]
        value = parts.build_plan(db, day, child)
        assert parts.check_plan(db, day, child, value)
        assert [len(part["sources"]) for part in value["parts"]] == [3, 1]
        assert not db.new and not db.dirty
        assert counts == [db.scalar(select(func.count()).select_from(model)) for model in (Job, Usage, Activity)]
        db.get(Material, mid).content = "Andere wörtliche Quelle, gleiche Revision."
        db.flush()
        assert not parts.check_plan(db, day, child, value)
        db.rollback()
    with DB.begin() as db:
        db.get(ProviderConfig, 1).revision += 1
    with DB() as db:
        assert not parts.check_plan(db, db.get(SchoolDay, day_id), db.get(Child, child_id), value)
