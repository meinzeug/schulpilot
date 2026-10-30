"""Literal, computed source evidence is required for decimal visualizations."""

import copy

import pytest
from schulpilot import package_output_transport, package_part_output, package_transport, visual_references
from schulpilot import package_prepared_decimals as decimal
from schulpilot.db import DB
from schulpilot.schemas import PackageOutput
from schulpilot.subject_content import Graphic, public_presentation
from test_package_prepared_graphics import bind, payload_for, wire_step

SOURCE = "Dezimalzahlen addieren\nKomma unter Komma schreiben.\n2,4 + 1,3 = 3,7\n5,6 + 2,2 = 7,8"


def prepared():
    payload = payload_for(SOURCE)
    with DB() as db:
        payload["visual_context"]["references"] = visual_references.candidates(
            db, "Mathematik", SOURCE, package_prepared=True
        )
    _, binding = bind(payload)
    assert isinstance(binding, decimal.Binding)
    return payload, binding


@pytest.mark.parametrize(
    "text",
    [
        "2,4 + 1,3 = 3,8",
        "2,4 + 1,3 = ?",
        "-2,4 + 1,3 = -1,1",
        "2,4 + 1,3 = 3,7 oder 4",
        "2,4 + 1,3 = 3,7 → richtig",
        "2 + 1 = 3",
    ],
)
def test_never_invents_repairs_or_rounds_an_unusable_source(text):
    assert list(decimal.bases(text)) == []


def test_exact_correct_originals_are_available_and_scope_checked():
    payload, binding = prepared()
    assert len(binding.candidates) == 10
    for candidate in binding.candidates:
        graphic = Graphic.model_validate(candidate["block"])
        assert graphic.source_excerpt in SOURCE
        decimal.validate_decimal(graphic, sources=[SOURCE])
        assert not any(phase.edges for phase in graphic.scene.steps)
    assert payload["visual_context"]["references"]


def test_latex_ocr_retains_source_and_projects_readable_decimal_labels():
    source = r"\(1{,}2 + 0{,}6 = 1{,}8\)"
    base = next(decimal.bases(source))
    assert base["source_excerpt"] == "1{,}2 + 0{,}6 = 1{,}8"
    graphic = Graphic.model_validate({**base, "disclosure": "given"})
    decimal.validate_decimal(graphic, sources=[source])
    public = public_presentation({"version": 1, "evidence_kind": "knowledge", "blocks": [graphic.model_dump()]})
    assert public["blocks"][0]["labels"] == ["1,2 + 0,6", "1,8"]
    assert [row["label"] for row in public["blocks"][0]["scene"]["objects"]] == ["1,2 + 0,6", "1,8"]
    assert graphic.source_excerpt == "1{,}2 + 0{,}6 = 1{,}8"
    assert list(decimal.bases(r"\(1{,}2 + 0{,}6 = 1{,}8")) == []
    full_source = "Dezimalzahlen addieren\n" + source + "\n" + r"\(4{,}5 + 2{,}3 = 6{,}8\)"
    payload = payload_for(full_source)
    with DB() as db:
        payload["visual_context"]["references"] = visual_references.candidates(
            db, "Mathematik", full_source, package_prepared=True
        )
    _, binding = bind(payload)
    assert isinstance(binding, decimal.Binding)
    q = {"type": "short", "prompt": "Wie viel ist 1,2 + 0,6?",
         "answer": "1,8", "accepted": [], "options": []}
    assert decimal.question_bound(base["source_excerpt"], q)


def test_wire_round_trip_and_canonical_graphic_validation():
    payload, binding = prepared()
    schema, _ = bind(payload)
    intro = next(row for row in binding.candidates if row["disclosure"] == "given")
    solutions = [row for row in binding.candidates if row["disclosure"] == "solution"]
    questions = []
    for index, (candidate, prompt, answer) in enumerate(
        zip(
            solutions,
            ["Wie viel ist 2,4 + 1,3?", "Wie viel ist 5,6 + 2,2?"],
            ["3,7", "7,8"],
            strict=True,
        )
    ):
        questions.append(
            {
                "id": f"q{index}",
                "type": "short",
                "prompt": prompt,
                "options": [],
                "answer": answer,
                "accepted": [],
                "hints": ["Schreibe die Kommas untereinander."],
                "explanation": "Addiere die beiden Zahlen.",
                "presentation": None,
                "field_group": None,
                "explanation_steps": [wire_step(candidate)],
            }
        )
    data = {
        "units": [
            {
                "group_id": "g1",
                "subject": "Mathematik",
                "topic": "Dezimalzahlen",
                "explanation": "Addiere die beiden Zahlen.",
                "explanation_steps": [wire_step(intro)],
                "questions": questions,
            }
        ]
    }
    codec = package_output_transport.bind(package_transport.schema_projection(schema))
    decoded = codec.decode(codec.encode(data))
    result = PackageOutput.model_validate(binding.hydrate(decoded)).model_dump(mode="json")
    package_part_output.validate(result)
    with DB() as db:
        visual_references.validate_output(db, result, payload)
    assert [item["answer"] for item in result["units"][0]["questions"]] == ["3,7", "7,8"]
    data["units"][0]["questions"][1] = copy.deepcopy(data["units"][0]["questions"][0])
    with pytest.raises(ValueError, match="nicht mehrfach"):
        binding.hydrate(data)


@pytest.mark.parametrize(
    "mutation", ["bad_answer", "foreign_number", "answer_in_prompt", "duplicate_correct", "other_source", "trailing_numbers", "extra_operand", "model_note"]
)
def test_wrong_answer_unrelated_task_and_duplicate_correct_choices_are_rejected(mutation):
    payload, binding = prepared()
    intro = next(row for row in binding.candidates if row["disclosure"] == "given")
    task = next(row for row in binding.candidates if row["disclosure"] == "solution")
    question = {
        "id": "q1",
        "type": "short",
        "prompt": "Wie viel ist 2,4 + 1,3?",
        "options": [],
        "answer": "3,7",
        "accepted": [],
        "hints": ["Schreibe die Kommas untereinander."],
        "explanation": "Addiere die beiden Zahlen.",
        "presentation": None,
        "explanation_steps": [wire_step(task)],
    }
    data = {
        "units": [
            {
                "group_id": "g1",
                "subject": "Mathematik",
                "topic": "Dezimalzahlen",
                "explanation": "Addiere die beiden Zahlen.",
                "explanation_steps": [wire_step(intro)],
                "questions": [question, copy.deepcopy(question)],
            }
        ]
    }
    if mutation == "bad_answer":
        question["answer"] = "3,6"
    elif mutation == "foreign_number":
        question["prompt"] = "Wie groß ist die Summe von 2,4 und 9,3?"
    elif mutation == "answer_in_prompt":
        question["prompt"] += " Ist es 3,7?"
    elif mutation == "duplicate_correct":
        question["type"] = "choice"
        question["options"] = ["3,7", "3,70", "4,7"]
    elif mutation == "other_source":
        question["explanation_steps"][0]["source_refs"] = ["p2"]
    elif mutation == "trailing_numbers":
        question["prompt"] = "Wie groß ist die Summe? 2,4 1,3"
    elif mutation == "extra_operand":
        question["prompt"] = "Wie groß ist die Summe von 2,4 und 1,3 und 5?"
    elif mutation == "model_note":
        question["prompt"] = "Wie viel ist 2,4 + 1,3 insgesamt, oops bad character Need fix.2,4 + 1,3?"
    with pytest.raises(ValueError):
        binding.hydrate(data)
