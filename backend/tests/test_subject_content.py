"""Fachtest R02/R03/R09/R15. Fixtures are curated, never a live-AI claim."""

import copy
import json
from pathlib import Path

import pytest
from pydantic import ValidationError
from schulpilot.answer_evaluation import evaluate
from schulpilot.schemas import Question, UnitOutput
from schulpilot.subject_content import (
    PROFILES,
    Presentation,
    canonical_profile,
    legacy_presentation,
    public_presentation,
    validate_output,
    validate_question,
)

CASES = json.loads((Path(__file__).parents[2] / "testdata/subject_cases_v1.json").read_text())["cases"]


@pytest.mark.parametrize("case", CASES, ids=lambda c: c["id"])
def test_both_curated_sources_per_subject_validate_and_evaluate(case):
    question = Question.model_validate(case["question"]).model_dump()
    unit = UnitOutput(
        subject=case["subject"], topic=case["id"], explanation=case["source"], questions=[question]
    ).model_dump()
    validate_output(unit, {"required_subject": case["subject"], "materials": [{"content": case["source"]}]})
    actual = evaluate(question, question["answer"])
    opened = question["presentation"]["evidence_kind"] in ("reflection", "creative", "self_report", "movement")
    assert actual["outcome"] == ("uncertain" if opened else "correct")
    before = public_presentation(question["presentation"])
    after = public_presentation(question["presentation"], closed=True, hints=3)
    assert "source_excerpt" not in json.dumps(before)
    assert all(b["disclosure"] == "given" for b in before["blocks"])
    assert len(after["blocks"]) == 1
    assert evaluate(question, "")["outcome"] != "correct"


def test_subject_matrix_is_complete_and_has_two_sources_each():
    assert len(CASES) == 48
    subjects = {canonical_profile(subject) for subject in PROFILES}
    assert subjects == {c["subject"] for c in CASES}
    assert all(sum(c["subject"] == subject for c in CASES) == 2 for subject in subjects)


def test_given_hint_and_solution_are_independently_projected_with_no_hidden_quotes():
    p = copy.deepcopy(CASES[0]["question"]["presentation"])
    block = p["blocks"][0]
    p["blocks"] = [
        {**block, "disclosure": stage, "title": f"{stage}-private"} for stage in ("given", "hint1", "hint2", "solution")
    ]
    assert [b["title"] for b in public_presentation(p)["blocks"]] == ["given-private"]
    assert [b["title"] for b in public_presentation(p, hints=1)["blocks"]] == ["given-private", "hint1-private"]
    assert [b["title"] for b in public_presentation(p, closed=True)["blocks"]] == ["given-private", "solution-private"]


@pytest.mark.parametrize(
    "fault",
    [
        "version",
        "arbitrary_svg",
        "unknown_kind",
        "missing_node",
        "reversed_food",
        "zero_denominator",
        "unbound_angle",
        "unnamed_colour",
        "invented_keyboard",
        "year_zero",
        "year_out_of_range",
        "unknown_picture",
        "non_finite",
    ],
)
def test_reject_invalid_graphics_without_relaxing_task_rules(fault):
    by_id = {c["id"]: c for c in CASES}
    ids = {
        "reversed_food": "BIO02",
        "zero_denominator": "MAT01",
        "unbound_angle": "PHY01",
        "unnamed_colour": "KUN01",
        "invented_keyboard": "MUS02",
        "missing_node": "BIO02",
        "year_zero": "GES01",
        "year_out_of_range": "GES01",
    }
    value = copy.deepcopy(by_id[ids.get(fault, "MAT01")]["question"]["presentation"])
    block = value["blocks"][0]
    if fault == "version":
        value["version"] = 9
    if fault == "arbitrary_svg":
        block["svg"] = "<svg/>"
    if fault == "unknown_kind":
        block["kind"] = "anything"
    if fault == "missing_node":
        block["connections"][0]["end"] = 15
    if fault == "reversed_food":
        block["connections"][0].update(start=1, end=0)
    if fault == "zero_denominator":
        block["numbers"][1] = 0
    if fault == "unbound_angle":
        block["numbers"][0] = 90
    if fault == "unnamed_colour":
        block["variant"] = ""
    if fault == "invented_keyboard":
        block["labels"][6] = "B"
    if fault == "year_zero":
        block["numbers"][0] = 0
    if fault == "year_out_of_range":
        block["numbers"][1] = 3001
    if fault == "unknown_picture":
        value = copy.deepcopy(by_id["FRA01"]["question"]["presentation"])
        block = value["blocks"][0]
        block["labels"][0] = "a spacecraft"
    if fault == "non_finite":
        block["numbers"][0] = float("nan")
    with pytest.raises(ValidationError):
        Presentation.model_validate(value)


def test_forged_source_numbers_subject_and_early_answers_are_rejected():
    original = copy.deepcopy(CASES[0]["question"])
    for fault in ("quote", "numbers", "subject", "answer"):
        q = copy.deepcopy(original)
        block = q["presentation"]["blocks"][0]
        if fault == "quote":
            block["source_excerpt"] = "Diese erfundene Quelle gibt es nicht."
        if fault == "numbers":
            block["numbers"] = [11, 13]
        if fault == "answer":
            block["labels"] = ["3/8"]
        with pytest.raises(ValueError):
            validate_question(
                q["presentation"], q, [CASES[0]["source"]], PROFILES["Deutsch" if fault == "subject" else "Mathematik"]
            )


def test_n007_triangle_error_localises_missing_halving_without_false_mastery():
    question = CASES[1]["question"]
    assert evaluate(question, "18 cm²")["outcome"] == "incorrect"
    assert "Rechteckfläche" in evaluate(question, "18 cm²")["reason"]
    assert evaluate(question, "9 cm²")["outcome"] == "correct"
    assert evaluate(question, "9 m²")["dimensions"] == {"content": "correct", "form": "incorrect"}
    assert evaluate({**question, "answer": "18 cm²"}, "18 cm²")["outcome"] == "uncertain"
    assert legacy_presentation(question)["blocks"][0]["numbers"] == [6, 3]


def test_fraction_value_and_requested_form_remain_distinct():
    q = CASES[0]["question"]
    assert evaluate(q, "6/16")["outcome"] == "correct"
    reduced = {**q, "prompt": q["prompt"] + " Kürze vollständig."}
    assert evaluate(reduced, "6/16")["dimensions"] == {"content": "correct", "form": "incorrect"}
    assert evaluate(reduced, "3/8")["outcome"] == "correct"


def _food_chain_question(labels, relation):
    question = copy.deepcopy(next(case for case in CASES if case["id"] == "BIO02")["question"])
    source = "; ".join([*labels, relation])
    block = question["presentation"]["blocks"][0]
    block.update(
        source_excerpt=source,
        labels=labels,
        connections=[{"start": 0, "end": 1, "relation": "food_to_eater"}],
    )
    return question, source


@pytest.mark.parametrize(
    "labels,relation",
    [
        (["Gras", "Kaninchen"], "Seegras→Kaninchen"),
        (["Gras", "Kaninchen"], "Gras→Kaninchenfloh"),
        (["Gras", "Kaninchen"], "Seegras->Kaninchenfloh"),
        (["A", "B"], "2A→B"),
        (["A", "B"], "A→B_2"),
        (["rotes Gras", "kleines Kaninchen"], "rotesGras→kleinesKaninchen"),
        (["rotes Gras", "kleines Kaninchen"], "dunkelrotes Gras→kleines Kaninchenfell"),
    ],
)
def test_food_chain_arrows_reject_partial_labels_or_collapsed_word_boundaries(labels, relation):
    question, source = _food_chain_question(labels, relation)
    with pytest.raises(ValueError, match="Nahrungskette"):
        validate_question(question["presentation"], question, [source], PROFILES["Biologie"])


@pytest.mark.parametrize(
    "labels,relation",
    [
        (["Gras", "Kaninchen"], "Gras→Kaninchen"),
        (["Gras", "Kaninchen"], "GRAS -> kaninchen"),
        (["Gras", "Kaninchen"], "Gras\t→\nKaninchen und weitere Beobachtungen"),
        (["rotes Gras", "kleines Kaninchen"], "rotes  Gras\t->\nkleines  Kaninchen"),
        (["rotes Gras", "kleines Kaninchen"], "(rotes Gras → kleines Kaninchen)."),
    ],
)
def test_food_chain_arrows_accept_complete_labels_whitespace_ascii_and_existing_case_folding(labels, relation):
    question, source = _food_chain_question(labels, relation)
    validate_question(question["presentation"], question, [source], PROFILES["Biologie"])
