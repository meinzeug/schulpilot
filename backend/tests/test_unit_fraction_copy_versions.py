"""Versioned grammar only; old immutable source-bound candidates stay valid."""
import copy
import json

import pytest
from fastapi import HTTPException
from schulpilot import unit_fraction_compositions as compositions
from schulpilot import visual_references
from schulpilot.db import DB
from schulpilot.learning_assets import public_spec
from schulpilot.visual_reference_models import VisualReference
from test_unit_fraction_compositions import prepared

LEGACY_DIGEST = "e4d6911883c84b6400b26f4ebee736c1e74cc8bfb532812f0a7a4b9009af3a41"
LEGACY_IDS = ("uc_a00dd661cca78b6cf269bb5f", "uc_b086b66413f18ff5482e3064")


def context(version, literal="5/4"):
    recipes = json.loads(visual_references.BUNDLE.read_text())["references"]
    recipe = next(r for r in recipes if r["id"] == compositions.RECIPE and r["version"] == version)
    return {"required": True, "references": [{"id": recipe["id"], "version": version,
        "digest": visual_references.digest(recipe), "subject": "Mathematik"}], "sources": [
        {"ref": "p1", "material_id": "a" * 32, "revision": 2, "subject": "Mathematik",
         "topic": "Unechte Brüche in gemischte Zahlen", "group_id": None,
         "content": "Unechte Brüche in gemischte Zahlen. Beispiel: " + literal + "."}]}


def step(candidate):
    return {"id": candidate["id"], "text": candidate["text"], "competence_id": None,
        "disclosure": candidate["disclosure"], "reference": copy.deepcopy(candidate["reference"]),
        "source_refs": copy.deepcopy(candidate["source_refs"]),
        "presentation": {"version": 1, "evidence_kind": "knowledge", "blocks": compositions._blocks(candidate)}}


def test_v1_reference_digest_and_both_candidate_ids_and_text_are_frozen():
    bound = context(1)
    assert bound["references"][0]["digest"] == LEGACY_DIGEST
    rows = compositions.compile_candidates(bound)
    assert tuple(row["id"] for row in rows) == LEGACY_IDS
    assert [row["text"] for row in rows] == ["Ein Ganzes besteht aus 4 gleich großen Teilen.",
        "Bei 5/4 bündeln wir jeweils 4 Teile zu einem Ganzen. So entstehen 1 Ganze. Es bleiben 1 Teile: 1/4."]


@pytest.mark.parametrize("literal,wholes,remainder", [
    ("5/4", "So entsteht ein Ganzes.", "Es bleibt ein Teil: 1/4."),
    ("6/4", "So entsteht ein Ganzes.", "Es bleiben 2 Teile: 2/4."),
    ("9/4", "So entstehen 2 Ganze.", "Es bleibt ein Teil: 1/4."),
    ("10/4", "So entstehen 2 Ganze.", "Es bleiben 2 Teile: 2/4."),
    ("12/4", "So entstehen 3 Ganze.", "Es bleibt kein Bruchteil übrig."),
    ("1/1", "So entsteht ein Ganzes.", "Es bleibt kein Bruchteil übrig."),
    ("2/1", "So entstehen 2 Ganze.", "Es bleibt kein Bruchteil übrig."),
])
def test_v2_singular_plural_and_zero_remainder_keep_identical_arithmetic(literal, wholes, remainder):
    old, new = [compositions.compile_candidates(context(version, literal)) for version in (1, 2)]
    assert [row["reference"]["version"] for row in new] == [2, 2]
    assert all(before["id"] != after["id"] for before, after in zip(old, new, strict=True))
    assert compositions._blocks(old[1]) == compositions._blocks(new[1])
    assert new[1]["text"].endswith(wholes + " " + remainder)
    assert "1 Ganze" not in new[1]["text"] and "1 Teile" not in new[1]["text"]
    if literal.endswith("/1"):
        assert "jeweils einen Teil zu einem Ganzen" in new[1]["text"]
        assert new[0]["text"] == "Ein Ganzes besteht aus einem Teil."
    question = {"prompt": "Schreibe " + literal + " als gemischte Zahl."}
    compositions.validate_step(step(new[0]), new, introduction=True)
    compositions.validate_step(step(new[1]), new, question=question)


def test_current_database_keeps_old_v1_steps_valid_and_seeds_both_versions_immutably():
    bound = context(1)
    rows = compositions.compile_candidates(bound)
    with DB.begin() as db:
        before = db.get(VisualReference, (compositions.RECIPE, 1))
        assert before.digest == LEGACY_DIGEST
        recipe = copy.deepcopy(before.recipe)
        visual_references.seed(db)
        visual_references.seed(db)
        assert db.get(VisualReference, (compositions.RECIPE, 1)).recipe == recipe
        assert db.get(VisualReference, (compositions.RECIPE, 1)).digest == LEGACY_DIGEST
        assert db.get(VisualReference, (compositions.RECIPE, 2)).digest != LEGACY_DIGEST
        visual_references.validate_steps(db, [step(rows[0])], "Mathematik", bound, introduction=True)
        visual_references.validate_steps(db, [step(rows[1])], "Mathematik", bound,
            question={"prompt": "Schreibe 5/4 als gemischte Zahl."})
    assert tuple(row["id"] for row in compositions.compile_candidates(bound)) == LEGACY_IDS


def test_new_request_prefers_v2_without_mutating_an_existing_v1_context(household):
    old = context(1)
    original = copy.deepcopy(old)
    payload, binding, wire = prepared(household)
    refs = [row for row in payload["visual_context"]["references"] if row["id"] == compositions.RECIPE]
    assert len(refs) == 1 and refs[0]["version"] == 2
    data = binding.hydrate(wire)
    with DB() as db:
        visual_references.validate_output(db, data, payload)
    assert old == original and tuple(row["id"] for row in compositions.compile_candidates(old)) == LEGACY_IDS


def test_persisted_v1_snapshot_stays_ready_and_byte_identical_when_new_context_prefers_v2(household):
    from schulpilot.db import Activity, Attempt, Child, LearningUnit, Material, UnitSource
    from schulpilot.visual_reference_models import UnitVisualSnapshot

    with DB.begin() as db:
        child = db.get(Child, household[1]["id"])
        material = Material(child_id=child.id, title="Öffentliches künstliches Beispiel", subject="Mathematik",
            topic="Unechte Brüche in gemischte Zahlen", content=context(1)["sources"][0]["content"],
            confirmed=True, status="confirmed")
        db.add(material)
        db.flush()
        new_payload = visual_references.with_visual_context(db, child, {}, [material])
        old_payload = copy.deepcopy(new_payload)
        old_payload["visual_context"]["references"] = [r for r in old_payload["visual_context"]["references"]
            if r["id"] != compositions.RECIPE] + context(1)["references"]
        rows = compositions.compile_candidates(old_payload["visual_context"])
        questions = [{"id": "old-question", "type": "short", "prompt": "Schreibe 5/4 als gemischte Zahl.",
            "answer": "1¼", "options": [], "accepted": [], "hints": [], "explanation": rows[1]["text"],
            "explanation_steps": [step(rows[1])]}]
        unit = LearningUnit(child_id=child.id, material_id=material.id, subject="Mathematik", topic=material.topic,
            explanation=rows[0]["text"], questions=questions, provider="synthetic", model="old-v1-fixture")
        db.add(unit)
        db.flush()
        db.add(UnitSource(unit_id=unit.id, material_id=material.id, revision=material.revision))
        visual_references.remember(db, unit, {"subject": unit.subject, "explanation_steps": [step(rows[0])],
            "questions": questions}, old_payload)
        db.flush()
        saved = db.get(UnitVisualSnapshot, unit.id)
        assert saved.status == "ready"
        original = visual_references.digest({column.name: getattr(saved, column.name)
            for column in UnitVisualSnapshot.__table__.columns})
        unit_id, material_id = unit.id, material.id
    with DB() as db:
        unit, saved = db.get(LearningUnit, unit_id), db.get(UnitVisualSnapshot, unit_id)
        before = db.query(Activity).count(), db.query(Attempt).count()
        fresh = visual_references.with_visual_context(db, db.get(Child, unit.child_id), {},
            [db.get(Material, material_id)])
        assert next(r for r in fresh["visual_context"]["references"] if r["id"] == compositions.RECIPE)["version"] == 2
        public = visual_references.projection(db, unit)
        assert public["explanation_visual_status"] == "ready"
        assert public["explanation_steps"][0]["reference"]["version"] == 1
        solution = visual_references.public_steps(saved.question_steps["old-question"], closed=True)[0]
        assert solution["reference"]["version"] == 1 and "So entstehen 1 Ganze." in solution["text"]
        assert original == visual_references.digest({column.name: getattr(saved, column.name)
            for column in UnitVisualSnapshot.__table__.columns})
        assert before == (db.query(Activity).count(), db.query(Attempt).count())
        assert not db.new and not db.dirty and not db.deleted


@pytest.mark.parametrize("version", [1, 2])
def test_each_version_rejects_the_other_versions_bound_text_and_source_revision(version):
    rows = compositions.compile_candidates(context(version))
    other = compositions.compile_candidates(context(3 - version))
    raw = step(rows[1])
    raw["text"] = other[1]["text"]
    with pytest.raises(ValueError):
        compositions.validate_step(raw, rows, question={"prompt": "Schreibe 5/4 als gemischte Zahl."})
    changed = context(version)
    changed["sources"][0]["revision"] += 1
    with pytest.raises(ValueError):
        compositions.validate_step(step(rows[1]), compositions.compile_candidates(changed),
            question={"prompt": "Schreibe 5/4 als gemischte Zahl."})


@pytest.mark.parametrize("version", [1, 2])
def test_both_recipe_versions_stay_out_of_unbound_shared_asset_selection(household, version):
    with DB() as db, pytest.raises(HTTPException) as error:
        public_spec(db, {"subject": "Mathematik", "recipe_id": compositions.RECIPE, "recipe_version": version,
            "level_band": "lower_secondary", "foundation_ids": ["math.fractions.meaning"]})
    assert error.value.status_code == 422
