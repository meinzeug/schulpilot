"""Synthetic exact fraction-component questions; never real child answers."""

import copy

import pytest
from schulpilot.answer_evaluation import evaluate


def question(prompt="Beim Bruch 6/7: Welche Zahl ist der Nenner?", key="7", **changes):
    return {"id": "synthetic-component", "type": "short", "prompt": prompt, "answer": key,
        "accepted": [], "options": [], "hints": ["Prüfe die Position der Zahl."],
        "explanation": "Ein eigenes künstliches Beispiel.", **changes}


def test_explicit_wrong_denominator_is_incorrect_not_an_open_prose_verdict():
    q = question()
    before = copy.deepcopy(q)
    verdict = evaluate(q, "6")
    assert verdict["outcome"] == verdict["dimensions"]["content"] == "incorrect"
    assert q == before


def test_conflicting_stored_component_key_stays_uncertain_even_for_an_exact_match():
    q = question(key="6", accepted=["7"])
    assert evaluate(q, "6")["outcome"] == "uncertain"
    assert evaluate(q, "7")["outcome"] == "uncertain"


@pytest.mark.parametrize("component,key,answer,outcome", [
    ("Zähler", "6", "6", "correct"),
    ("Zähler", "6", "7", "incorrect"),
    ("Nenner", "7", "7", "correct"),
    ("Nenner", "7", "6", "incorrect"),
    ("Nenner", "7", "6.5", "incorrect"),
    ("Nenner", "7", "-7", "incorrect"),
    ("Nenner", "7", "+7", "correct"),
    ("Nenner", "7", "7,0", "correct"),
])
def test_exact_component_oracle_uses_position_not_the_fraction_value(component, key, answer, outcome):
    from schulpilot.answer_evaluation import FRACTION_COMPONENT_VERSION

    q = question(prompt=f"Beim Bruch 6/7: Welche Zahl ist der {component}?", key=key)
    original = copy.deepcopy(q)
    verdict = evaluate(q, answer)
    assert verdict["outcome"] == outcome
    assert verdict["method"] == FRACTION_COMPONENT_VERSION
    assert q == original


@pytest.mark.parametrize("kind", ["short", "gap", "choice"])
def test_improper_fraction_is_not_reduced_or_reinterpreted_when_naming_a_component(kind):
    q = question("Wie lautet der Zähler des Bruchs 7/4?", "7", type=kind, options=["7", "4", "7/4"])
    assert evaluate(q, "7")["outcome"] == "correct"
    assert evaluate(q, "4")["outcome"] == "incorrect"
    q["prompt"], q["answer"] = "Wie lautet der Nenner des Bruchs 7/4?", "4"
    assert evaluate(q, "4")["outcome"] == "correct"
    assert evaluate(q, "7")["outcome"] == "incorrect"


@pytest.mark.parametrize("prompt", [
    "Wie lautet der Nenner des Bruches 6/7?",
    "Was ist der Nenner von 6/7?",
    "Welche Zahl ist der Nenner im Bruch 6/7?",
    "Welcher Nenner steht im Bruch 6/7?",
    "Nenne den Nenner des Bruchs 6/7.",
    "Gib den Nenner von 6/7 an.",
    r"Übung: Beim Bruch \(6/7\): Welche Zahl ist der Nenner?",
    r"Wie lautet der Nenner des Bruchs $\frac{6}{7}$?",
])
def test_complete_finite_question_forms_and_literal_math_wrappers(prompt):
    from schulpilot.answer_evaluation import FRACTION_COMPONENT_VERSION

    q = question(prompt)
    assert evaluate(q, "6")["outcome"] == "incorrect"
    assert evaluate(q, "7")["method"] == FRACTION_COMPONENT_VERSION


@pytest.mark.parametrize("prompt", [
    "Beim Bruch 6/7 und 7/4: Welche Zahl ist der Nenner?",
    "Beim Bruch 6/7: Welche Zahl ist der Nenner von 3/4?",
    "Beim Bruch 6/7 + 3/4: Welche Zahl ist der Nenner?",
    "Beim Bruch 6/7: Welche Zahl ist der Nenner? Denke auch an 6/7.",
    "Beim Bruch 6/7: Welche Zahl ist nicht der Nenner?",
    "Beim Bruch 6/7: Welche Zahl ist der Zähler oder Nenner?",
    "Kürze 6/7. Wie lautet der neue Nenner?",
    "Beim Bruch 1 6/7: Welche Zahl ist der Nenner?",
    "Beim Bruch 6⁰/7⁰: Welche Zahl ist der Nenner?",
    "Beim Bruch 6/0: Welche Zahl ist der Nenner?",
    "Beim Bruch -6/7: Welche Zahl ist der Nenner?",
])
def test_unrecognised_clauses_multiple_fractions_and_changed_notation_stay_outside_the_rule(prompt):
    from schulpilot.answer_evaluation import fraction_component

    q = question(prompt)
    assert fraction_component(q, "6") is None
    assert evaluate(q, "6")["outcome"] == "uncertain"


@pytest.mark.parametrize("key", ["6", "6/7", "sieben", "7⁰"])
def test_unverified_or_conflicting_keys_are_not_promoted_by_exact_match_or_alias(key):
    from schulpilot.answer_evaluation import FRACTION_COMPONENT_VERSION

    q = question(key=key, accepted=["7"])
    for answer in [key, "7"]:
        verdict = evaluate(q, answer)
        assert verdict["outcome"] == "uncertain"
        assert verdict["method"] == FRACTION_COMPONENT_VERSION


def test_numeric_alias_cannot_override_the_independently_verified_component():
    q = question(accepted=["6"])
    assert evaluate(q, "6")["outcome"] == "incorrect"


@pytest.mark.parametrize("answer", ["6/7", "7/1", "7⁰", "7, weil das der Wert des ganzen Bruchs ist"])
def test_whole_fraction_notation_or_unrecognised_prose_does_not_gain_numeric_acceptance(answer):
    assert evaluate(question(), answer)["outcome"] == "uncertain"


def test_explicit_choice_labels_are_literal_option_content_never_guessed_indices():
    q = question(type="choice", key="A) 7", options=["A) 7", "B) 6"])
    assert evaluate(q, "A) 7")["outcome"] == "correct"
    assert evaluate(q, "B) 6")["outcome"] == "incorrect"
    assert evaluate(q, "A")["outcome"] != "correct"
    assert evaluate(q, "0")["outcome"] == "incorrect"


def test_zero_numerator_is_an_exact_component_and_does_not_make_the_denominator_zero():
    q = question("Beim Bruch 0/7: Welche Zahl ist der Zähler?", "0")
    assert evaluate(q, "0")["outcome"] == "correct"
    assert evaluate(q, "7")["outcome"] == "incorrect"


def test_language_contract_is_not_reclassified_as_a_math_component():
    from schulpilot.answer_evaluation import fraction_component

    q = question(language={"skill": "translation"})
    assert fraction_component(q, "6") is None


def test_new_answer_is_incorrect_in_the_normal_api_and_existing_attempts_are_unchanged(api, household):
    from schulpilot.db import DB, Attempt, Job, LearningUnit, Usage
    from sqlalchemy import func, select
    from test_coaching import normal_unit

    fixture = normal_unit.__wrapped__(api, household)
    child, uid, *_ = next(fixture)
    try:
        q = question()
        with DB.begin() as db:
            unit = db.get(LearningUnit, uid)
            other = unit.questions[1]
            unit.questions = [q, other]
            old = Attempt(unit_id=uid, question_id=other["id"], answer="saved artificial legacy answer",
                outcome="uncertain", assisted=False,
                evaluation={"method": "subject_rules_v5", "outcome": "uncertain", "legacy_marker": True})
            db.add(old)
            db.flush()
            old_id = old.id
            snapshot = {key: copy.deepcopy(getattr(old, key)) for key in
                ("answer", "outcome", "assisted", "evaluation", "created")}
        assert child.post(f"/api/units/{uid}/start").status_code == 200
        response = child.post(f"/api/units/{uid}/questions/{q['id']}/answer", json={
            "answer": "6", "request_id": "synthetic-component-answer", "guided_feedback": True})
        assert response.status_code == 200, response.text
        assert response.json()["outcome"] == "incorrect"
        assert response.json()["unit"]["pending_feedback"]["outcome"] == "incorrect"
        assert child.get(f"/api/units/{uid}").status_code == 200
        with DB() as db:
            old = db.get(Attempt, old_id)
            assert {key: getattr(old, key) for key in snapshot} == snapshot
            new = db.scalar(select(Attempt).where(Attempt.unit_id == uid, Attempt.question_id == q["id"]))
            assert new.answer == "6" and new.outcome == "incorrect"
            assert new.evaluation["method"] == "fraction_components_v1"
            assert db.scalar(select(func.count()).select_from(Attempt).where(Attempt.unit_id == uid)) == 2
            for model in (Job, Usage):
                assert db.scalar(select(func.count()).select_from(model)) == 0
    finally:
        fixture.close()
