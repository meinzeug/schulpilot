"""Synthetic source and versioned reference, no learner data or provider call."""
import copy

import pytest
from schulpilot import package_output_transport, package_part_output, package_transport, visual_references
from schulpilot.db import DB
from schulpilot.package_prepared_heart import REFERENCE, bases
from schulpilot.schemas import PackageOutput
from schulpilot.subject_content import Graphic
from test_package_prepared_graphics import bind, payload_for, wire_step

SOURCE = ("Das Herz\nDas Herz pumpt Blut durch den Körper. "
          "Blutgefäße transportieren das Blut. Der Puls zeigt, wie oft das Herz schlägt.")


@pytest.mark.parametrize("source", [
    "Das Herz pumpt kein Blut durch den Körper.",
    "Das Herz pumpt Blut nicht durch den Körper.",
    "Das Gehirn pumpt Blut durch den Körper.",
    "Das Herz pumpt Blut durch den Lungenkreislauf.",
])
def test_never_infer_unconfirmed_or_negated_relations(source):
    assert not list(bases(source))


def test_new_source_binds_exact_reference_graphic_and_question():
    payload = payload_for(SOURCE, "Biologie")
    with DB() as db:
        payload["visual_context"]["references"] = visual_references.candidates(db, "Biologie", SOURCE, package_prepared=True)
    schema, binding = bind(payload)
    assert binding is not None
    assert {row["reference"]["id"] for row in binding.candidates} == {REFERENCE}
    intro = next(row for row in binding.candidates if row["disclosure"] == "given")
    solution = next(row for row in binding.candidates if row["disclosure"] == "solution")
    assert solution["block"]["labels"] == ["Herz", "Blut", "Körper"]
    assert not binding.question_bound(solution, {"prompt": "Wo liegt der Mond?"})
    questions = [
        {"id": "q1", "type": "short", "prompt": "Was pumpt das Herz durch den Körper?", "answer": "Blut",
         "options": [], "accepted": [], "hints": ["Lies den Satz."], "explanation": "Das Herz pumpt Blut.",
         "presentation": None, "field_group": None, "explanation_steps": [wire_step(solution)]},
        {"id": "q2", "type": "short", "prompt": "Was pumpt das Herz?", "answer": "Blut",
         "options": [], "accepted": [], "hints": ["Lies den Satz."], "explanation": "Das Herz pumpt Blut.",
         "presentation": None, "field_group": None, "explanation_steps": [wire_step(solution)]},
    ]
    wire = {"units": [{"group_id": "g1", "subject": "Biologie", "topic": "Das Herz",
                        "explanation": "Das Herz pumpt Blut durch den Körper.",
                        "explanation_steps": [wire_step(intro)], "questions": questions}]}
    original = copy.deepcopy(wire)
    codec = package_output_transport.bind(package_transport.schema_projection(schema))
    decoded = binding.hydrate(codec.decode(codec.encode(wire)))
    assert wire == original
    decoded = PackageOutput.model_validate(decoded).model_dump(mode="json")
    package_part_output.validate(decoded)
    with DB() as db:
        visual_references.validate_output(db, decoded, payload)
    changed = copy.deepcopy(solution["block"])
    changed["labels"][1] = "Sauerstoff"
    with pytest.raises(ValueError):
        visual_references._meaningful(Graphic.model_validate(changed), {"id": REFERENCE, "kind": "heart_pump"}, sources=[SOURCE])


def test_heart_direction_accepts_only_exact_equivalent_with_verified_reference():
    from schulpilot.answer_evaluation import heart_pump_direction

    block = {**next(bases(SOURCE)), "disclosure": "solution"}
    question = {"type": "short", "prompt": "Wohin pumpt das Herz das Blut?", "answer": "Körper",
        "explanation_steps": [{"reference": {"id": REFERENCE, "version": 1}, "presentation": {"blocks": [block]}}]}
    assert heart_pump_direction(question, "durch den Körper.")["outcome"] == "correct"
    for answer in ("nicht durch den Körper", "durch den Körper und die Lunge", "Kopf", ""):
        assert heart_pump_direction(question, answer) is None
    foreign = copy.deepcopy(question)
    foreign["explanation_steps"][0]["reference"]["id"] = "foreign"
    assert heart_pump_direction(foreign, "durch den Körper") is None
    foreign = copy.deepcopy(question)
    foreign["answer"] = "Lunge"
    assert heart_pump_direction(foreign, "durch den Körper") is None


def test_goal_bound_followup_keeps_task_goal_ids_and_checked_source():
    from schulpilot import providers
    from schulpilot.package_prepared_heart import bind_followup
    from schulpilot.schemas import PracticeUnitOutput
    from schulpilot.subject_content import bind_graphic_schema

    base = payload_for(SOURCE, "Biologie")
    with DB() as db:
        refs = visual_references.candidates(db, "Biologie", SOURCE, package_prepared=True)
    source = {**base["visual_context"]["sources"][0], "group_id": None}
    payload = {"review": True, "practice_kind": "repair", "required_subject": "Biologie", "required_topic": "Das Herz",
        "focus_goal_ids": ["g1"], "learning_goals": [{"id": "g1", "label": "Funktion des Herzens", "source_excerpt": SOURCE}],
        "visual_context": {"required": True, "references": refs, "sources": [source]}}
    schema = providers.strict_schema(PracticeUnitOutput, preserve_limits=True)
    providers.indexed_choice_schema(schema, bounded_matches=True)
    providers.bind_practice_tasks(schema, providers.practice_tasks(payload))
    bind_graphic_schema(schema, ["Biologie"])
    visual_references.bind_schema(schema, payload)
    binding = bind_followup(schema, payload)
    assert binding is not None
    intro = next(row for row in binding.candidates if row["disclosure"] == "given")
    solution = next(row for row in binding.candidates if row["disclosure"] == "solution")
    questions = [{"id": f"q{n}", "learning_goal_id": "g1", "type": "short", "prompt": prompt,
        "answer": answer, "options": [], "accepted": [], "hints": ["Lies den Satz."],
        "explanation": SOURCE, "presentation": None, "field_group": None, "explanation_steps": [wire_step(solution)]}
        for n, (prompt, answer) in enumerate((("Was pumpt das Herz?", "Blut"),
                                               ("Wohin pumpt das Herz Blut?", "Körper")), 1)]
    wire = {"subject": "Biologie", "topic": "Das Herz", "explanation": SOURCE,
            "explanation_steps": [wire_step(intro)], "questions": questions}
    result = PracticeUnitOutput.model_validate(binding.hydrate(wire)).model_dump(mode="json")
    with DB() as db:
        visual_references.validate_output(db, result, payload)
    assert [(q["id"], q["learning_goal_id"]) for q in result["questions"]] == [("q1", "g1"), ("q2", "g1")]
    assert bind_followup(schema, {**payload, "required_subject": "Physik"}) is None
