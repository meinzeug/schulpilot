"""Own fraction homework attempts need sum feedback, not operand equality."""

import pytest
from schulpilot import homework


def check(prompt, answer):
    return homework.deterministic_reply(
        {"homework": {"action": "check", "draft": answer, "task": {"source_quote": prompt}}},
        [{"id": "artificial-page", "label": "Künstliche Bruchaufgabe"}],
    )


@pytest.mark.parametrize("answer", ["2/9", "2/6", "1/3"])
def test_wrong_fraction_sum_explains_what_to_check_without_disclosing_result(answer):
    reply = check(r"1) Berechne \(\frac{1}{3} + \frac{1}{6}\).", answer)
    assert reply["outcome"] == "incorrect"
    assert reply["answer"] == "Dein Ergebnis passt noch nicht zur Summe."
    assert "Nenner" in reply["next_step"]
    assert "gleich große Teile" in reply["next_question"]
    visible = " ".join(reply[field] for field in ("answer", "next_step", "next_question"))
    assert "1/2" not in visible and r"\frac{1}{2}" not in visible
    assert "denselben Wert" not in visible


def test_denominator_sum_gets_a_specific_impulse_without_claiming_a_diagnosis():
    reply = check("Berechne 1/3 + 1/6.", "2/9")
    assert reply["next_step"].startswith("Addiere die Nenner nicht.")
    other_error = check("Berechne 1/3 + 1/6.", "2/6")
    assert "Addiere die Nenner nicht" not in other_error["next_step"]


@pytest.mark.parametrize("answer", ["1/2", "3/6"])
def test_correct_fraction_value_has_clear_feedback_without_pretending_to_check_a_written_method(answer):
    reply = check("Berechne 1/3 + 1/6.", answer)
    assert reply["outcome"] == "correct"
    assert reply["answer"] == "Dein Ergebnis passt zur Summe."
    assert "Beschreibe deinen Rechenweg" in reply["next_step"]


def test_correct_value_in_wrong_requested_form_does_not_become_a_calculation_error():
    reply = check("Berechne 1/3 + 1/6 als Bruch mit dem Nenner 6.", "1/2")
    assert reply["outcome"] == "incorrect"
    assert "Der Wert stimmt" in reply["answer"]
    assert "Bruchdarstellung" in reply["next_step"]
    assert "noch nicht zur Summe" not in reply["answer"]


def test_open_written_solution_is_not_upgraded_to_a_deterministic_verdict():
    assert check("Berechne 1/3 + 1/6.", "Ich erweitere den ersten Bruch und zähle dann die Teile zusammen.") is None


def test_rectangle_feedback_remains_about_the_area():
    reply = check("Ein Rechteck ist 7 cm lang und 4 cm breit. Wie groß ist seine Fläche in cm²?", "11")
    assert reply["outcome"] == "incorrect"
    assert "Länge" in reply["answer"] and "Breite" in reply["answer"]
    assert "Summe" not in reply["answer"]
