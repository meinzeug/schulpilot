import pytest
from pydantic import ValidationError
from schulpilot.learning import evaluate
from schulpilot.schemas import Question


def expansion_question(**values):
    # Observed in the real free-model child flow: the main answer was right,
    # but an equivalent unexpanded fraction was offered as an accepted alias.
    return {
        "id": "expand",
        "type": "short",
        "prompt": "Erweitere den Bruch 1/2 mit dem Faktor 2.",
        "options": [],
        "answer": "2/4",
        "accepted": ["2 / 4", "1/2"],
        "hints": ["Multipliziere Zähler und Nenner mit 2."],
        "explanation": "1 mal 2 ist 2, 2 mal 2 ist 4. Das Ergebnis ist 2/4.",
        **values,
    }


def test_expansion_keeps_correct_answer_and_only_suitable_aliases():
    parsed = Question.model_validate(expansion_question())
    assert parsed.answer == "2/4" and parsed.accepted == ["2 / 4"]


@pytest.mark.parametrize(
    "prompt", ["Erweitere den Bruch 1/2 mit dem Faktor 2.", "Erweitere den Bruch 1/2 durch Multiplikation mit 2."]
)
def test_wrong_main_expansion_answer_is_rejected_instead_of_replaced(prompt):
    with pytest.raises(ValidationError, match="Erweiterungsfaktor"):
        Question.model_validate(expansion_question(prompt=prompt, answer="1/2"))


def test_expansion_grading_also_protects_previously_saved_model_output():
    stored = expansion_question()
    assert evaluate(stored, "1/2") == "incorrect"
    assert evaluate(stored, "4/8") == "incorrect"
    assert evaluate(stored, "2 / 4") == "correct"
    assert evaluate(stored, "zwei Viertel") == "uncertain"


def test_equivalent_answers_remain_valid_when_no_form_is_requested():
    question = expansion_question(prompt="Welcher Bruch ist gleich 2/4?")
    assert evaluate(question, "1/2") == "correct"
    assert Question.model_validate(question).accepted == ["2 / 4", "1/2"]
