import pytest
from pydantic import ValidationError
from schulpilot.schemas import Question


def question(**values):
    return Question.model_validate(
        {
            "id": "q1",
            "type": "choice",
            "prompt": "Berechne: 1/4 + 2/4 = ?",
            "options": ["A: 1/2", "B: 3/4"],
            "answer": "B",
            "accepted": ["B"],
            "hints": ["Addiere die Zähler."],
            "explanation": "1 + 2 = 3; der Nenner bleibt 4.",
            **values,
        }
    )


@pytest.mark.parametrize("answer", ["B", "b)", "(B)", "B: 3/4", "3/4"])
def test_explicit_labels_decode_to_the_same_existing_answer(answer):
    parsed = question(answer=answer)
    assert parsed.options == ["A: 1/2", "B: 3/4"]
    assert parsed.answer == "B: 3/4" and parsed.accepted == ["B: 3/4"]


def test_unlabelled_options_do_not_guess_letter_positions():
    with pytest.raises(ValidationError, match="gültige Antwort"):
        question(options=["1/2", "3/4"])
    with pytest.raises(ValidationError):
        question(options=["A: 1/2", "A: 3/4"], answer="A")


def test_label_conversion_never_approves_wrong_arithmetic():
    with pytest.raises(ValidationError, match="rechnerisch"):
        question(options=["A: 1/2", "B: 2/4"])
    with pytest.raises(ValidationError, match="rechnerisch"):
        question(options=["A: 1/2", "B: 3/4 oder 2/4"])
    parsed = question(options=["A: 1/2", "B: 3/4 oder 6/8"], accepted=[])
    assert parsed.answer == "B: 3/4 oder 6/8"


def test_a_letter_that_is_also_another_answer_is_not_guessed():
    with pytest.raises(ValidationError, match="Mehrdeutiger"):
        question(prompt="Welche Zeichenfolge passt?", options=["A: B", "B: A"], answer="B", accepted=[])
