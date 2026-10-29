import pytest

from schulpilot.coaching import conflicting_fraction_goal


@pytest.mark.parametrize("prompt", [
    "Ein Ganzes ist in 11 gleich große Teile geteilt. 5 Teile sind ausgewählt. Welchen Bruch beschreibt das? Schreibe Zähler/Nenner.",
    "Beim Bruch 4/6: Welche Zahl ist der Nenner?",
])
def test_prerequisite_is_not_an_addition_goal(prompt):
    assert conflicting_fraction_goal(prompt, "Zähler und Nenner beim Addieren gleichnamiger Brüche unterscheiden: Zähler addieren und Nenner beibehalten.")
    assert not conflicting_fraction_goal(prompt, "Zähler und Nenner benennen")


def test_actual_addition_and_ambiguous_question_are_not_blocked():
    assert not conflicting_fraction_goal("Addiere 1/4 + 2/4 und nenne den Nenner.", "Brüche addieren")
    assert not conflicting_fraction_goal("Erkläre den Nenner.", "Brüche addieren")
