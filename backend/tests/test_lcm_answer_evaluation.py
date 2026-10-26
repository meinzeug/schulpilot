"""Synthetic pure kgV checks; no app, database or saved attempts are used."""

import copy

import pytest
from schulpilot.answer_evaluation import LCM_VERSION, evaluate, lcm_short_answer


def question(first=3, second=4, key="12", **changes):
    return {
        "type": "short",
        "prompt": f"Was ist das kleinste gemeinsame Vielfache von {first} und {second}?",
        "answer": key,
        "accepted": [],
        **changes,
    }


@pytest.mark.parametrize("answer", ["12", " 12 ", "0012"])
def test_single_numeric_result_is_correct(answer):
    verdict = evaluate(question(), answer)
    assert verdict["outcome"] == verdict["dimensions"]["content"] == "correct"
    assert verdict["method"] == LCM_VERSION


@pytest.mark.parametrize("answer", ["0", "1", "3", "4", "11", "13", "24", "36", "999999999"])
def test_other_values_including_larger_common_multiples_are_incorrect(answer):
    verdict = evaluate(question(), answer)
    assert verdict["outcome"] == "incorrect"
    assert verdict["method"] == LCM_VERSION


@pytest.mark.parametrize("first,second,key", [
    (1, 7, "7"), (6, 6, "6"), (4, 6, "12"), (8, 12, "24"), (9, 15, "45"),
    (9998, 9999, "99970002"),
])
def test_common_factors_equal_operands_and_boundary_values_are_recomputed(first, second, key):
    q = question(first, second, key)
    assert evaluate(q, key)["outcome"] == "correct"
    assert evaluate(q, str(int(key) * 2))["outcome"] == "incorrect"


@pytest.mark.parametrize("prompt", [
    "Was ist das kleinste gemeinsame Vielfache von 3 und 4?",
    "Was ist das kleinste gemeinsame Vielfache (kgV) von 3 und 4?",
    "  WAS IST DAS KLEINSTE GEMEINSAME VIELFACHE (kgV) von 3   und 4?  ",
])
def test_complete_supported_question_forms(prompt):
    assert evaluate(question(prompt=prompt), "12")["method"] == LCM_VERSION


@pytest.mark.parametrize("key", [
    "24", "0", "zwölf", "12,0", "12.0", "12/1", "+12", "-12", "−12", "1²", "１２",
    True, False, None, 12, 12.0,
])
def test_contradictory_or_non_integer_key_blocks_even_exact_match_and_correct_alias(key):
    q = question(key=key, accepted=["12"])
    for answer in (key, "12"):
        verdict = evaluate(q, answer)
        assert verdict["outcome"] == "uncertain"
        assert verdict["method"] == LCM_VERSION


@pytest.mark.parametrize("answer", [
    "12 oder 24", "12 24", "3 und 4", "zwölf", "Die Antwort ist 12", "kgV = 12", "ungefähr 12",
    "12,0", "12.0", "12/1", "+12", "-12", "−12", "1²", "１２", "١٢", "12 cm", "1_2", "1e1", "",
    True, False, None, 12, 12.0,
])
def test_unsupported_answer_notation_cannot_gain_exact_or_accepted_alias_credit(answer):
    q = question(accepted=[answer])
    verdict = evaluate(q, answer)
    assert verdict["outcome"] == "uncertain"
    assert verdict["method"] == LCM_VERSION


def test_wrong_numeric_alias_cannot_override_the_smallest_common_multiple():
    assert evaluate(question(accepted=["24"]), "24")["outcome"] == "incorrect"


@pytest.mark.parametrize("prompt", [
    "Was ist das kleinste gemeinsame Vielfache von 3 und 4 und 5?",
    "Was ist das kleinste gemeinsame Vielfache von 3, 4?",
    "Was ist das kleinste gemeinsame Vielfache von 3 oder 4?",
    "Was ist das kleinste gemeinsame Vielfache von 3 und 4? Begründe.",
    "Was ist das kleinste gemeinsame Vielfache von 3 und 4? Denke auch an 5.",
    "Was ist das kleinste gemeinsame Vielfache von -3 und 4?",
    "Was ist das kleinste gemeinsame Vielfache von +3 und 4?",
    "Was ist das kleinste gemeinsame Vielfache von 0 und 4?",
    "Was ist das kleinste gemeinsame Vielfache von 3,0 und 4?",
    "Was ist das kleinste gemeinsame Vielfache von 3/1 und 4?",
    "Was ist das kleinste gemeinsame Vielfache von 3² und 4?",
    "Was ist das kleinste gemeinsame Vielfache von ３ und ４?",
    "Was ist das kleinste gemeinsame Vielfache von ٣ und ٤?",
    "Was ist das kleinste gemeinsame Vielfache von 10000 und 4?",
    "Was ist das kleinste gemeinsame Vielfache von 03 und 4?",
    "Was ist das kleinste gemeinsame Vielfache von drei und vier?",
    "Was ist das kleinste gemeinsame Vielfache von True und 4?",
    "Was ist das kleinste gemeinsame Vielfache von 3 cm und 4 cm?",
    "Was ist der größte gemeinsame Teiler von 3 und 4?",
    "Was ist ein gemeinsames Vielfaches von 3 und 4?",
    "Berechne das kgV von 3 und 4.",
    "Was ist das kleinste gemeinsame Vielfache von 3 und 4",
])
def test_unsupported_or_ambiguous_question_is_not_reinterpreted(prompt):
    q = question(prompt=prompt)
    assert lcm_short_answer(q, "24") is None
    assert evaluate(q, "24")["outcome"] == "uncertain"


@pytest.mark.parametrize("changes", [
    {"type": "gap"}, {"type": "choice", "options": ["12", "24"]},
    {"language": {"skill": "translation"}},
])
def test_other_question_contracts_stay_outside_the_new_rule(changes):
    assert lcm_short_answer(question(**changes), "24") is None


def test_evaluation_does_not_mutate_question_or_existing_metadata():
    q = question(accepted=["24"], prior_attempt={"answer": "24", "outcome": "uncertain", "method": "old"})
    original = copy.deepcopy(q)
    assert evaluate(q, "24")["outcome"] == "incorrect"
    assert q == original


@pytest.mark.parametrize("q,answer,outcome,method", [
    ({"type": "short", "prompt": "Wie viel ist 81 - 35?", "answer": "46"}, "0", "incorrect", "subject_rules_v5"),
    ({"type": "short", "prompt": "Wie viel ist 81 - 35?", "answer": "0"}, "0", "uncertain", "subject_rules_v5"),
    ({"type": "short", "prompt": "Beim Bruch 6/7: Welche Zahl ist der Nenner?", "answer": "7"},
     "6", "incorrect", "fraction_components_v1"),
    ({"type": "short", "prompt": "Beim Bruch 6/7: Welche Zahl ist der Zähler?", "answer": "6"},
     "6", "correct", "fraction_components_v1"),
    ({"type": "short", "prompt": "Erweitere 2/3 mit 4.", "answer": "8/12"},
     "2/3", "incorrect", "subject_rules_v5"),
])
def test_existing_arithmetic_and_fraction_guards_keep_their_verdicts(q, answer, outcome, method):
    verdict = evaluate(q, answer)
    assert verdict["outcome"] == outcome
    assert verdict["method"] == method
