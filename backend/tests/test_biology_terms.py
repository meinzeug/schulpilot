"""A new question must not assume an unintroduced biology term."""
import pytest
from schulpilot.subject_content import validate_introduced_terms, validate_output


@pytest.mark.parametrize("spelling", ["Fotosynthese", "Photosynthese"])
def test_term_in_question_requires_source_or_visible_introduction(spelling):
    question = {"prompt": f"Was nehmen Pflanzen bei der {spelling} auf?", "options": []}
    source = ["Pflanzen nehmen Wasser auf und bilden Zucker."]
    with pytest.raises(ValueError, match="Fachbegriff"):
        validate_introduced_terms("Biologie", question, source, ["Pflanzen brauchen Licht."])
    validate_introduced_terms("Biologie", question, source, [f"{spelling} nennt man diesen Vorgang."])
    validate_introduced_terms("Biologie", question, [f"{spelling}: Pflanzen nehmen Wasser auf."], [])
    validate_introduced_terms("Deutsch", question, source, [])


def test_ordinary_plant_question_does_not_require_an_extra_term():
    validate_introduced_terms("Biologie", {"prompt": "Was nimmt die Pflanze auf?", "options": ["Wasser"]},
                              ["Pflanzen nehmen Wasser auf."], [])


def test_generated_package_runs_the_term_guard_before_accepting_question():
    payload = {"materials": [{"group_id": "g1", "content": "Pflanzen nehmen Wasser auf."}]}
    unit = {"subject": "Biologie", "group_id": "g1", "explanation_steps": [], "questions": [
        {"type": "choice", "prompt": "Was nehmen Pflanzen bei der Fotosynthese auf?", "options": ["Wasser"]}]}
    with pytest.raises(ValueError, match="Fachbegriff"):
        validate_output({"units": [unit]}, payload)
    unit["explanation_steps"] = [{"text": "Fotosynthese ist der Vorgang, bei dem Pflanzen mit Licht Zucker bilden."}]
    validate_output({"units": [unit]}, payload)
