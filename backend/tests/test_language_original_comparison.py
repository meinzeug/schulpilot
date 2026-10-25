"""Literal public language examples, never grammar judgments or model calls."""
import copy

import pytest
from schulpilot import package_output_transport, package_part_output, package_transport, providers, visual_references
from schulpilot.db import DB
from schulpilot.schemas import PackageOutput
from schulpilot.subject_content import bind_graphic_schema
from schulpilot.visual_reference_models import VisualReference

REFERENCE = "language.forms.original_comparison"
EXAMPLES = ["I play football.", "She plays football.", "They play football.", "We play football."]
SOURCE = "\n".join(EXAMPLES)
LANGUAGES = ["Englisch", "Französisch", "Spanisch", "Latein", "Deutsch als Zweitsprache"]


def context(db, subject="Englisch"):
    return {"required": True, "references": visual_references.candidates(db, subject, SOURCE),
        "sources": [{"ref": "p1", "subject": subject, "group_id": "g1", "content": SOURCE}]}


def step(stage="solution", count=2):
    return {"id": "e1", "text": "Vergleiche die beiden Originalbeispiele.", "competence_id": None,
        "disclosure": stage, "reference": {"id": REFERENCE, "version": 1}, "source_refs": ["p1"],
        "presentation": {"version": 1, "evidence_kind": "knowledge", "blocks": [{"kind": "forms",
            "title": "Originalbeispiele vergleichen", "disclosure": stage, "source_excerpt": SOURCE,
            "labels": EXAMPLES[:count], "numbers": [], "connections": [], "marks": [], "unit": "",
            "variant": "classification", "scene": None, "text_probe": None, "lab": None}]}}


@pytest.mark.parametrize("subject", LANGUAGES)
def test_language_sources_without_arrows_or_keyword_hints_have_the_actual_versioned_comparison_recipe(subject):
    with DB() as db:
        rows = visual_references.candidates(db, subject, "Originalausdrücke ohne Pfeil und ohne besonderes Stichwort.")
        selected = next(row for row in rows if row["id"] == REFERENCE)
        actual = db.get(VisualReference, (REFERENCE, 1))
        assert selected["kind"] == "forms" and selected["variant"] == "classification"
        assert selected["version"] == 1 and selected["digest"] == actual.digest == visual_references.digest(actual.recipe)
        assert actual.recipe["terms"] == []


@pytest.mark.parametrize("subject", ["Mathematik", "Biologie", "Deutsch"])
def test_comparison_is_not_a_silent_all_subject_graphic_fallback(subject):
    with DB() as db:
        assert not any(row["id"] == REFERENCE for row in visual_references.candidates(db, subject, SOURCE))


@pytest.mark.parametrize("count", [2, 3, 4])
@pytest.mark.parametrize("stage", ["given", "solution"])
def test_valid_original_examples_keep_their_spelling_and_existing_disclosure_contract(count, stage):
    value = step(stage, count)
    original = copy.deepcopy(value)
    with DB() as db:
        checked = visual_references.validate_steps(db, [value], "Englisch", context(db), group_id="g1", introduction=stage == "given")
    assert checked == [original] and value == original


@pytest.mark.parametrize("fault", ["single", "five", "duplicate", "whitespace_duplicate", "invented", "reordered", "wrong_case",
    "substring", "numbers", "connection", "unit", "variant", "only_model_prompt", "foreign_source", "foreign_group"])
def test_original_comparison_rejects_unattested_or_meaningless_values_without_loosening_old_validators(fault):
    value = step()
    block = value["presentation"]["blocks"][0]
    question = {"type": "short", "prompt": "Which word is in I play football.?", "answer": "plays", "accepted": []}
    with DB() as db:
        source = context(db)
        if fault == "single":
            block["labels"] = EXAMPLES[:1]
        elif fault == "five":
            block["labels"] = [*EXAMPLES, "You play football."]
            block["source_excerpt"] += "\nYou play football."
            source["sources"][0]["content"] = block["source_excerpt"]
        elif fault == "duplicate":
            block["labels"] = [EXAMPLES[0], EXAMPLES[0]]
        elif fault == "whitespace_duplicate":
            block["labels"] = [EXAMPLES[0], "I  play football."]
        elif fault == "invented":
            block["labels"][1] = "We swim."
        elif fault == "reordered":
            block["labels"][1] = "Football plays she."
        elif fault == "wrong_case":
            block["labels"][1] = "she plays football."
        elif fault == "substring":
            block["labels"] = ["play", "lay"]
        elif fault == "numbers":
            block["numbers"] = [1]
        elif fault == "connection":
            block["connections"] = [{"start": 0, "end": 1, "relation": "next"}]
        elif fault == "unit":
            block["unit"] = "cm"
        elif fault == "variant":
            block["variant"] = ""
        elif fault == "only_model_prompt":
            block["source_excerpt"] = "We swim. They swim."
            block["labels"] = ["We swim.", "They swim."]
            question["prompt"] = block["source_excerpt"]
        elif fault == "foreign_source":
            value["source_refs"] = ["p2"]
        else:
            source["sources"][0]["group_id"] = "g2"
        with pytest.raises(ValueError):
            visual_references.validate_steps(db, [value], "Englisch", source, question=question, group_id="g1")


def test_real_new_part_schema_accepts_original_comparison_without_arrows_and_keeps_question_source_and_answer():
    with DB() as db:
        visual = context(db)
    question = {"id": "q1", "type": "short", "prompt": "Which verb form is in She plays football.?", "answer": "plays",
        "options": [], "accepted": [], "hints": ["Read the second example."], "explanation": "Read the original examples.",
        "presentation": None, "explanation_steps": [step()]}
    data = PackageOutput.model_validate({"units": [{"group_id": "g1", "subject": "Englisch", "topic": "Originalvergleich",
        "explanation": "Vergleiche die Originalbeispiele.", "explanation_steps": [step("given")],
        "questions": [question, {**copy.deepcopy(question), "id": "q2"}]}]}).model_dump(mode="json")
    payload = {"package_partition": 3, "package_plan_digest": "a" * 64, "visual_context": visual,
        "selected_groups": [{"id": "g1", "subject": "Englisch", "estimated_minutes": 8}],
        "materials": [{"subject": "Englisch", "group_id": "g1", "topic": "Originalvergleich", "content": SOURCE}]}
    schema = providers.strict_schema(PackageOutput, preserve_limits=True)
    providers.prepare_package_schema(schema, payload, partition=True)
    bind_graphic_schema(schema, ["Englisch"])
    visual_references.bind_schema(schema, payload)
    assert package_part_output.bind_schema(schema, payload) is None  # Frozen non-maths compiler path.
    binding = package_output_transport.bind(package_transport.schema_projection(schema))
    decoded = binding.decode(binding.encode(data))
    assert decoded == data
    with DB() as db:
        visual_references.validate_output(db, decoded, payload)
    package_part_output.validate(decoded)
    assert decoded["units"][0]["questions"][0]["answer"] == "plays"
    assert payload["materials"][0]["content"] == SOURCE


def test_comparison_original_excerpt_can_preserve_ocr_line_breaks_without_inventing_words():
    value = step()
    value["presentation"]["blocks"][0]["source_excerpt"] = SOURCE.replace("I play", "I\nplay")
    with DB() as db:
        visual_references.validate_steps(db, [value], "Englisch", context(db), group_id="g1")


@pytest.mark.parametrize("prompt,valid", [("Which verb form is in She plays football.?", True),
    ("Which verb form is in She\nplays football.?", True), ("Which verb form is used?", False),
    ("Which word is in she plays football.?", False), ("Compare football.", False)])
def test_question_comparison_needs_a_complete_case_preserving_original_expression_anchor(prompt, valid):
    value = step()
    question = {"type": "short", "prompt": prompt, "answer": "plays", "accepted": []}
    with DB() as db:
        if valid:
            visual_references.validate_steps(db, [value], "Englisch", context(db), question=question, group_id="g1")
        else:
            with pytest.raises(ValueError, match="vollständigen Originalausdruck"):
                visual_references.validate_steps(db, [value], "Englisch", context(db), question=question, group_id="g1")
