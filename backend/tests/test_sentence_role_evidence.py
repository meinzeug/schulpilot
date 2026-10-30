"""Whole artificial word groups, not inferred grammar or loose prefix matches."""
import copy

import pytest
from schulpilot.db import DB
from schulpilot.subject_content import PROFILES, Graphic, public_presentation, validate_question
from schulpilot.visual_references import candidates, validate_steps

SOURCE = "Der Hund rennt im Park.\n\nSubjekt: Der Hund\nPrädikat: rennt"


def graphic(labels=None, marks=None, source=SOURCE):
    return {"kind": "sentence", "title": "Satz zum Anschauen", "disclosure": "solution",
            "source_excerpt": source, "labels": labels or ["Der", "Hund", "rennt", "im", "Park."],
            "marks": marks if marks is not None else [{"index": 0, "role": "subject"}, {"index": 1, "role": "subject"}],
            "numbers": [], "connections": [], "unit": "", "variant": ""}


def check(value):
    validate_question({"version": 1, "evidence_kind": "knowledge", "blocks": [value]},
                      {"prompt": "Untersuche den Satz.", "type": "short", "answer": "Der Hund", "accepted": []},
                      [value["source_excerpt"]], PROFILES["Deutsch"], structured=True, subject="Deutsch")


@pytest.mark.parametrize("labels,marks", [
    (["Der", "Hund", "rennt", "im", "Park."], [{"index": 0, "role": "subject"}, {"index": 1, "role": "subject"}]),
    (["Der Hund", "rennt", "im Park."], [{"index": 0, "role": "subject"}]),
    (["Der", "Hund", "rennt", "im", "Park."], [{"index": 2, "role": "predicate"}]),
])
def test_complete_source_bound_constituent_can_span_several_word_boxes(labels, marks):
    value = graphic(labels, marks)
    before = copy.deepcopy(value)
    check(value)
    assert value == before
    assert public_presentation({"version": 1, "evidence_kind": "knowledge", "blocks": [value]})["blocks"] == []


@pytest.mark.parametrize("source", [
    "Der Hund rennt.\nSubjekt: Der Hund.",
    "Der Hund rennt.\nDas Subjekt = Der Hund",
    "Der Hund rennt.\nDer Hund ist das Subjekt.",
    "Der Hund rennt.\nSubjekt:\nDer Hund",
    "Der Hund rennt.\nSubjekt: Der Hund; Prädikat: rennt",
    "Der Hund rennt. Der Hund ist das Subjekt.",
    "Der Hund rennt. Subjekt: Der Hund. Prädikat: rennt.",
])
def test_literal_complete_role_statements_keep_notation(source):
    check(graphic(["Der", "Hund", "rennt"], source=source))


@pytest.mark.parametrize("value", [
    graphic(marks=[{"index": 0, "role": "subject"}]),  # prefix of Der Hund
    graphic(marks=[{"index": 1, "role": "subject"}]),  # suffix of Der Hund
    graphic(marks=[{"index": 2, "role": "subject"}]),
    graphic(marks=[{"index": 0, "role": "predicate"}, {"index": 1, "role": "predicate"}]),
    graphic(source="Der Hund rennt im Park.\nKein Subjekt: Der Hund"),
    graphic(source="Der Hund rennt im Park.\nDer Hund ist nicht das Subjekt."),
    graphic(source="Der Hund rennt im Park.\nSubjekt: Der Hund im Park"),
    graphic(marks=[{"index": 0, "role": "subject"}, {"index": 1, "role": "predicate"}]),
    graphic(marks=[{"index": 0, "role": "subject"}, {"index": 0, "role": "predicate"}]),
])
def test_partial_negated_unproven_and_conflicting_roles_remain_rejected(value):
    with pytest.raises(ValueError, match="Rollen"):
        check(value)


def test_whole_group_passes_the_same_versioned_reference_path_as_real_followup():
    value = graphic()
    with DB() as db:
        context = {"required": True, "references": candidates(db, "Deutsch", SOURCE),
                   "sources": [{"ref": "p1", "subject": "Deutsch", "group_id": None, "content": SOURCE}]}
        step = {"id": "s1", "text": "Der Hund ist das Subjekt. Frage: Wer oder was rennt?",
                "competence_id": None, "disclosure": "solution",
                "reference": {"id": "language.sentence.roles", "version": 1}, "source_refs": ["p1"],
                "presentation": {"version": 1, "evidence_kind": "knowledge", "blocks": [value]}}
        before = copy.deepcopy(step)
        validate_steps(db, [step], "Deutsch", context,
                       question={"prompt": "Wer rennt im Park?", "type": "short", "answer": "Der Hund", "accepted": []})
        assert step == before


def test_given_marks_stay_forbidden():
    with pytest.raises(ValueError, match="Satzmarkierungen"):
        Graphic.model_validate({**graphic(), "disclosure": "given"})
