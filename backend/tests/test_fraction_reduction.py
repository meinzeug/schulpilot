"""Arithmetic regressions from an explicitly artificial learning journey."""

import copy

import pytest
from pydantic import ValidationError
from schulpilot.checks import fraction_parts, fraction_result
from schulpilot.learning import evaluate
from schulpilot.schemas import Question


def result_question(prompt, answer, **values):
    return {
        "id": "result",
        "type": "short",
        "prompt": prompt,
        "options": [],
        "answer": answer,
        "accepted": [],
        "hints": ["Beachte, welcher Wert gefragt ist."],
        "explanation": "Künstliche mathematische Testaufgabe.",
        **values,
    }


def test_observed_divisor_as_result_fraction_is_rejected_without_rewriting():
    # Exact artificial question from the failed browser stage; no account IDs
    # or private artifact dependency. Its explanation must not repair the key.
    question = {
        "id": "q3",
        "type": "short",
        "prompt": "Wie lautet der Bruch nach dem ersten Kürzen von 12/18?",
        "options": [],
        "answer": "2",
        "accepted": [],
        "hints": ["Teile Zähler und Nenner durch dieselbe Zahl."],
        "explanation": "12/18 kann durch 2 gekürzt werden. 12 : 2 = 6 und 18 : 2 = 9. Das Ergebnis ist 6/9.",
    }
    original = copy.deepcopy(question)
    with pytest.raises(ValidationError, match="mehrdeutig"):
        Question.model_validate(question)
    assert question == original


@pytest.mark.parametrize("kind", ["short", "gap"])
@pytest.mark.parametrize("answer", ["6/9", "4/6"])
def test_unspecified_first_reduction_step_has_no_unique_free_text_answer(kind, answer):
    with pytest.raises(ValidationError, match="mehrdeutig"):
        Question.model_validate(
            result_question("Wie lautet der Bruch nach dem ersten Kürzen von 12/18?", answer, type=kind)
        )


@pytest.mark.parametrize(
    "prompt,answer",
    [
        ("Kürze 12/18 durch 2.", "6/9"),
        ("Kürze den Bruch 12/18 mit dem Faktor 3.", "4/6"),
        ("Wie lautet der Bruch nach dem ersten Kürzen von 12/18 durch den Teiler 2?", "6/9"),
        ("Welcher Bruch entsteht, wenn du 12/18 durch die Zahl 3 kürzt?", "4/6"),
        ("Kürze 12/18 vollständig.", "2/3"),
        ("Welcher Bruch ist der vollständig gekürzte Bruch von 6/12?", "1/2"),
        ("Kürze 12/18 so weit wie möglich.", "2/3"),
        ("Wie lautet der erweiterte Bruch von 1/2 mit dem Faktor 3?", "3/6"),
    ],
)
def test_explicit_result_questions_keep_the_mathematically_correct_main_answer(prompt, answer):
    value = result_question(prompt, answer)
    parsed = Question.model_validate(value)
    assert parsed.answer == answer
    assert evaluate(parsed.model_dump(), answer) == "correct"


@pytest.mark.parametrize(
    "prompt,answer",
    [
        ("Kürze 12/18 durch 2.", "2"),
        ("Kürze 12/18 durch 2.", "2/3"),
        ("Kürze 12/18 durch 2.", "12/18"),
        ("Kürze 12/18 vollständig.", "6/9"),
        ("Welcher Bruch ist der vollständig gekürzte Bruch von 6/12?", "6"),
        ("Kürze 12/18.", "5/15"),
        ("Kürze 3/2.", "6/4"),
        ("Wie lautet der erweiterte Bruch von 1/2 mit dem Faktor 3?", "1/2"),
    ],
)
def test_wrong_result_or_requested_representation_is_rejected(prompt, answer):
    original = result_question(prompt, answer)
    with pytest.raises(ValidationError):
        Question.model_validate(original)
    assert original["answer"] == answer


@pytest.mark.parametrize(
    "prompt,answer",
    [
        ("Durch welche Zahl kannst du 12/18 kürzen?", "2"),
        ("Wie lautet der Kürzungsfaktor für 12/18 zu 6/9?", "2"),
        ("Mit welchem Faktor erweiterst du 1/2 zu 3/6?", "3"),
        ("Wie lautet der Zähler nach dem Kürzen von 12/18 durch 2?", "6"),
        ("Welcher Nenner entsteht beim Kürzen von 12/18 durch 2?", "9"),
        ("Kürze 12/18 durch 2. Welcher Zähler entsteht?", "6"),
        ("Wie viele gleich große Teile sind bei 1/3 gegeben?", "3"),
        ("Kürze 12/18 durch 2: __/9", "6"),
    ],
)
def test_explicit_divisor_numerator_denominator_and_gap_questions_remain_valid(prompt, answer):
    assert Question.model_validate(result_question(prompt, answer)).answer == answer


def test_choice_first_step_can_offer_a_single_valid_reduction():
    question = result_question(
        "Wie lautet der Bruch nach dem ersten Kürzen von 12/18?",
        "6/9",
        type="choice",
        options=["6/9", "2", "12/18"],
    )
    assert Question.model_validate(question).answer == "6/9"
    with pytest.raises(ValidationError, match="Bruchlösung"):
        Question.model_validate({**question, "answer": "2"})


def test_broader_expansion_wording_keeps_form_filtering_and_saved_answer_grading():
    question = result_question(
        "Wie lautet der erweiterte Bruch von 1/2 mit dem Faktor 3?",
        "3/6",
        accepted=["3 / 6", "1/2", "6/12", "3"],
    )
    parsed = Question.model_validate(question)
    assert parsed.answer == "3/6" and parsed.accepted == ["3 / 6"]
    assert evaluate(question, "1/2") == "incorrect"
    assert evaluate(question, "6/12") == "incorrect"


def test_fraction_result_rejects_bad_explicit_reduction_and_preserves_fraction_parts():
    with pytest.raises(ValueError, match="Bruchlösung"):
        fraction_result("Kürze 12/18 durch 2.", "2", [])
    fraction_result("Kürze 12/18 durch 2.", "6/9", [])
    assert fraction_parts("B) 6 / 9") == (6, 9)


def test_labeled_divisor_option_cannot_pass_as_the_result_fraction():
    with pytest.raises(ValidationError, match="Bruchlösung"):
        Question.model_validate(
            result_question("Kürze 12/18 vollständig.", "B", type="choice", options=["A) 2/3", "B) 6"])
        )


def test_repeated_source_fraction_in_a_result_gap_does_not_bypass_the_check():
    prompt = "Kürze 12/18 vollständig: 12/18 = __ (als Bruch)."
    assert Question.model_validate(result_question(prompt, "2/3", type="gap")).answer == "2/3"
    with pytest.raises(ValidationError, match="Bruchlösung"):
        Question.model_validate(result_question(prompt, "2", type="gap"))
    with pytest.raises(ValidationError, match="vollständig gekürzt"):
        Question.model_validate(result_question(prompt, "6/9", type="gap"))


@pytest.mark.parametrize("answer", ["6/9", "4/6"])
def test_first_step_choice_with_two_correct_fractions_is_ambiguous(answer):
    question = result_question(
        "Wie lautet der Bruch nach dem ersten Kürzen von 12/18?",
        answer,
        type="choice",
        options=["6/9", "4/6", "12/18"],
    )
    with pytest.raises(ValidationError, match="nicht genau eine"):
        Question.model_validate(question)
    assert question["answer"] == answer


@pytest.mark.parametrize(
    "prompt,options,answer",
    [
        ("Kürze 12/18 vollständig.", ["2/3", "6/9", "4/6"], "2/3"),
        ("Kürze 12/18 durch 2.", ["6/9", "4/6", "2/3"], "6/9"),
        ("Erweitere den Bruch 1/2 mit dem Faktor 2.", ["2/4", "1/2", "4/8"], "2/4"),
    ],
)
def test_choice_correctness_respects_full_reduction_and_explicit_factors(prompt, options, answer):
    assert Question.model_validate(result_question(prompt, answer, type="choice", options=options)).answer == answer


@pytest.mark.parametrize("operation", ["Kürze 12/18 durch", "Erweitere 1/2 mit dem Faktor"])
@pytest.mark.parametrize("factor", ["0", "-2", "−3"])
def test_explicit_nonpositive_factor_is_invalid_instead_of_unspecified(operation, factor):
    with pytest.raises(ValidationError, match="positiv"):
        Question.model_validate(result_question(f"{operation} {factor}.", "2/3"))


@pytest.mark.parametrize("answer", ["zwei Drittel", "durch 2", "6/9 oder 4/6", "6/9 = 2/3", "6/0"])
def test_recognized_result_questions_reject_uncheckable_main_answers(answer):
    with pytest.raises(ValidationError, match="nicht als eindeutige"):
        Question.model_validate(result_question("Kürze 12/18 vollständig.", answer))


def test_part_question_with_numeric_choices_remains_outside_whole_fraction_validation():
    question = result_question(
        "Welcher Nenner entsteht beim Kürzen von 12/18 durch 2?", "9", type="choice", options=["9", "6", "2"]
    )
    assert Question.model_validate(question).answer == "9"
