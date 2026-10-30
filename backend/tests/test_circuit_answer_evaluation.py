"""Recheck only a literal, source-verified circuit question."""
import copy

import pytest
from schulpilot.answer_evaluation import CIRCUIT_VERSION, evaluate
from schulpilot.package_prepared_circuit import REFERENCE, bases
from test_package_circuit import SOURCE


def question():
    block = next(row for row in bases(SOURCE) if row["variant"] == "open")
    return {"type": "short", "prompt": "Bei geöffnetem Schalter: Was bewirkt dieser im Stromkreis?",
            "answer": "unterbricht", "accepted": [],
            "explanation_steps": [{"reference": {"id": REFERENCE, "version": 1},
                "presentation": {"blocks": [{**block, "disclosure": "solution"}]}}]}


@pytest.mark.parametrize("answer", ["Er unterbricht den Stromkreis.",
    "Der Schalter unterbricht den Stromkreis", "Der Stromkreis wird unterbrochen."])
def test_exact_source_backed_student_sentences_are_correct(answer):
    result = evaluate(question(), answer)
    assert result["outcome"] == "correct" and result["method"] == CIRCUIT_VERSION


@pytest.mark.parametrize("answer", ["Er unterbricht den Stromkreis nicht.",
    "Er unterbricht den Stromkreis und die Lampe leuchtet.", "Der Stromkreis ist geschlossen."])
def test_negation_extra_claims_and_different_answers_remain_open(answer):
    assert evaluate(question(), answer)["outcome"] == "uncertain"


@pytest.mark.parametrize("fault", ["wrong_key", "wrong_prompt", "foreign_reference", "changed_graphic", "missing_source"])
def test_rule_requires_the_same_question_key_and_verified_snapshot(fault):
    q = question()
    block = q["explanation_steps"][0]["presentation"]["blocks"][0]
    if fault == "wrong_key":
        q["answer"] = "leuchtet"
    elif fault == "wrong_prompt":
        q["prompt"] = "Was bewirkt der geschlossene Schalter?"
    elif fault == "foreign_reference":
        q["explanation_steps"][0]["reference"]["id"] = "unknown"
    elif fault == "changed_graphic":
        block["variant"] = "closed"
    else:
        block["source_excerpt"] = "Ein geöffneter Schalter schließt den Stromkreis."
    original = copy.deepcopy(q)
    assert evaluate(q, "Er unterbricht den Stromkreis.")["outcome"] == "uncertain"
    assert q == original
