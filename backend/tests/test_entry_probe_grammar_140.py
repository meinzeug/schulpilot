"""Synthetic singular wording and historical novelty; no external processing."""
import copy

import pytest
from schulpilot import competences, learning_entry
from schulpilot.competence_models import QuestionCompetence
from schulpilot.db import DB, Attempt, LearningUnit
from sqlalchemy import func, select
from test_learning_entry import output, payload, saved
from test_learning_entry import source as source

MEANING = {"id": "math.fractions.meaning", "probe": "fraction_meaning"}
SINGULAR_SEED = "public-synthetic-grammar-45"


def prompt(n, d, *, legacy=False):
    selected = f"{n} Teile sind ausgewählt" if legacy or n != 1 else "1 Teil ist ausgewählt"
    return f"Ein Ganzes ist in {d} gleich große Teile geteilt. {selected}. Welchen Bruch beschreibt das? Schreibe Zähler/Nenner."


def test_actual_probe_uses_singular_verb_noun_and_same_canonical_answer():
    result = learning_entry._probe(MEANING, SINGULAR_SEED, set(), "sample")
    assert result["prompt"] == prompt(1, 6)
    assert result["answer"] == "1/6"
    assert result["visual_example"]["text"] == "Servergeprüftes Beispiel: " + prompt(1, 6) + " Ergebnis: 1/6."
    assert {key: result["visual_example"][key] for key in ("numerator", "denominator", "factor")} == {
        "numerator": 1, "denominator": 6, "factor": 2}


def test_plural_wording_and_question_identity_are_unchanged():
    result = learning_entry._probe(MEANING, "public-synthetic-grammar-0", set(), "sample")
    assert result["prompt"] == prompt(6, 7, legacy=True)
    assert result["answer"] == "6/7"
    assert result["id"] == "prior_sample" and result["competence_id"] == MEANING["id"]


@pytest.mark.parametrize("legacy", [False, True])
def test_prior_singular_wording_excludes_the_same_fraction_without_rewriting_history(legacy):
    previous = {competences.normalized(prompt(1, 6, legacy=legacy))}
    before = copy.deepcopy(previous)
    result = learning_entry._probe(MEANING, SINGULAR_SEED, previous, "sample")
    assert result is not None and result["answer"] != "1/6"
    assert previous == before
    paired = learning_entry._probe(MEANING, SINGULAR_SEED, {competences.normalized(prompt(1, 6, legacy=not legacy))}, "sample")
    assert result == paired


@pytest.mark.parametrize("legacy", [False, True])
def test_exhausted_old_or_new_prompt_pool_never_repeats_a_question(legacy):
    previous = {competences.normalized(prompt(n, d, legacy=legacy)) for d in range(3, 13) for n in range(1, d)}
    before = copy.deepcopy(previous)
    assert learning_entry._probe(MEANING, SINGULAR_SEED, previous, "sample") is None
    assert previous == before


@pytest.mark.parametrize("template,expected,answer", [
    ("fraction_components", "Beim Bruch 1/6: Welche Zahl ist der Nenner?", "6"),
    ("fraction_equivalence", "Erweitere 1/6 mit 2. Welcher Bruch entsteht? Schreibe Zähler/Nenner.", "2/12"),
])
def test_other_templates_do_not_gain_grammar_aliases(template, expected, answer):
    result = learning_entry._probe({"id": "other", "probe": template}, SINGULAR_SEED,
        {competences.normalized(prompt(1, 6, legacy=True))}, "sample")
    assert result["prompt"] == expected and result["answer"] == answer


def test_reserved_introduction_example_is_still_excluded():
    result = learning_entry._probe(MEANING, SINGULAR_SEED, set(), "sample", excluded_examples=((1, 6),))
    assert result is not None and result["answer"] != "1/6"


def test_saved_legacy_probe_attempt_and_competence_binding_survive_new_generation(source, monkeypatch):
    _, child, material_id = source
    original = learning_entry._probe

    def stable(competence, seed, previous, ordinal, **kwargs):
        return original(competence, SINGULAR_SEED if competence["probe"] == "fraction_meaning" else seed,
            previous, ordinal, **kwargs)

    monkeypatch.setattr(learning_entry, "_probe", stable)
    with DB.begin() as db:
        value = payload(db, child["id"], material_id)
        meaning = next(probe for probe in value["learning_entry"]["units"][0]["probes"]
            if probe["competence_id"] == MEANING["id"])
        assert meaning["answer"] == "1/6"
        meaning["prompt"] = prompt(1, 6, legacy=True)
        meaning["visual_example"]["text"] = "Servergeprüftes Beispiel: " + meaning["prompt"] + " Ergebnis: 1/6."
        unit = saved(db, child["id"], material_id, value)
        before = copy.deepcopy(unit.questions)
        old_id = unit.id
        event = Attempt(unit_id=unit.id, question_id=meaning["id"], answer="1/6", outcome="correct", assisted=False)
        db.add(event)
        db.flush()
        event_id = event.id
        bindings = [(row.question_id, row.question_digest, row.competence_id) for row in db.scalars(
            select(QuestionCompetence).where(QuestionCompetence.unit_id == old_id).order_by(QuestionCompetence.question_id))]
    with DB.begin() as db:
        fresh = payload(db, child["id"], material_id)
        probes = fresh["learning_entry"]["units"][0]["probes"]
        meaning = next(probe for probe in probes if probe["competence_id"] == MEANING["id"])
        assert meaning["answer"] != "1/6"
        learning_entry.validate_entry_output(fresh, output(fresh))
        new_unit = saved(db, child["id"], material_id, fresh)
        assert new_unit.id != old_id
        assert db.get(LearningUnit, old_id).questions == before
        old = db.get(Attempt, event_id)
        assert (old.answer, old.outcome, old.assisted) == ("1/6", "correct", False)
        assert db.scalar(select(func.count()).select_from(Attempt)) == 1
        assert [(row.question_id, row.question_digest, row.competence_id) for row in db.scalars(
            select(QuestionCompetence).where(QuestionCompetence.unit_id == old_id).order_by(QuestionCompetence.question_id))] == bindings
