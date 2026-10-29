"""Artificial source evidence only; no provider call or learner data."""
import copy

import pytest
from schulpilot import package_output_transport, package_part_output, package_transport, visual_references
from schulpilot.db import DB
from schulpilot.package_prepared_photosynthesis import REFERENCE, bases
from schulpilot.schemas import PackageOutput, PracticeUnitOutput, UnitOutput
from test_package_prepared_graphics import bind, payload_for, wire_step

SOURCE = ("Pflanzen und Photosynthese\n\nPflanzen nehmen Wasser und Kohlenstoffdioxid auf.\n"
          "Mit Licht bilden sie Zucker und geben Sauerstoff ab.")


def test_fotosynthese_uses_verified_exchange_not_unrelated_plant_anatomy():
    payload = payload_for(SOURCE, "Biologie")
    with DB() as db:
        payload["visual_context"]["references"] = visual_references.candidates(db, "Biologie", SOURCE, package_prepared=True)
    ids = {row["id"] for row in payload["visual_context"]["references"]}
    assert REFERENCE in ids
    assert "biology.plant.structure" not in ids
    schema, binding = bind(payload)
    assert binding is not None
    # Azure strict output rejects line breaks inside string enum literals.
    def enum_strings(node):
        if isinstance(node, dict):
            yield from (value for value in node.get("enum", []) if isinstance(value, str))
            for value in node.values():
                yield from enum_strings(value)
        elif isinstance(node, list):
            for value in node:
                yield from enum_strings(value)
    assert all("\n" not in value for value in enum_strings(schema))
    intro = next(row for row in binding.candidates if row["disclosure"] == "given")
    answer = next(row for row in binding.candidates if row["disclosure"] == "solution")
    assert {row["disclosure"] for row in binding.candidates} == {"given", "solution"}
    assert intro["text"] == answer["text"] == " ".join(intro["block"]["source_excerpt"].split())
    questions = []
    for n, (prompt, solution) in enumerate((("Welches Gas nehmen Pflanzen bei der Fotosynthese auf?", "Kohlenstoffdioxid"),
                                             ("Welches Gas geben Pflanzen bei der Fotosynthese ab?", "Sauerstoff"))):
        questions.append({"id": f"q{n}", "type": "short", "prompt": prompt, "answer": solution,
                          "options": [], "accepted": [], "hints": ["Lies den Satz genau."],
                          "explanation": SOURCE, "presentation": None, "field_group": None,
                          "explanation_steps": [wire_step(answer)]})
    output = {"units": [{"group_id": "g1", "subject": "Biologie", "topic": "Fotosynthese",
                        "explanation": SOURCE, "explanation_steps": [wire_step(intro)], "questions": questions}]}
    codec = package_output_transport.bind(package_transport.schema_projection(schema))
    result = binding.hydrate(codec.decode(codec.encode(output)))
    result = PackageOutput.model_validate(result).model_dump(mode="json")
    package_part_output.validate(result)
    with DB() as db:
        visual_references.validate_output(db, result, payload)
    block = result["units"][0]["explanation_steps"][0]["presentation"]["blocks"][0]
    assert block["labels"] == ["Wasser", "Kohlenstoffdioxid", "Zucker", "Sauerstoff"]
    assert [phase["highlight"] for phase in block["scene"]["steps"]] == [["o0", "o1"], ["o2", "o3"]]
    assert all(not phase["edges"] for phase in block["scene"]["steps"])


@pytest.mark.parametrize("source", [
    "Pflanzen nehmen Wasser und Kohlenstoffdioxid auf.",
    "Pflanzen nehmen Wasser und Sauerstoff auf. Mit Licht bilden sie Zucker und geben Kohlenstoffdioxid ab.",
    "Pflanzen nehmen Wasser und Kohlenstoffdioxid nicht auf. Mit Licht bilden sie Zucker und geben Sauerstoff ab.",
])
def test_no_scene_is_invented_for_unmatched_or_negated_text(source):
    assert not list(bases(source))


def test_anatomy_remains_available_when_all_positions_are_proven():
    with DB() as db:
        refs = visual_references.candidates(db, "Biologie", "Die Pflanze: Blüte, Blatt, Stängel, Wurzel.")
    assert "biology.plant.structure" in {row["id"] for row in refs}


def test_prepared_scene_rejects_changed_labels_and_unrelated_questions():
    payload = payload_for(SOURCE, "Biologie")
    with DB() as db:
        payload["visual_context"]["references"] = visual_references.candidates(db, "Biologie", SOURCE, package_prepared=True)
    _, binding = bind(payload)
    candidate = next(row for row in binding.candidates if row["disclosure"] == "solution")
    block = copy.deepcopy(candidate["block"])
    block["labels"][0] = "Luft"
    from schulpilot.subject_content import Graphic

    with pytest.raises(ValueError):
        visual_references._meaningful(Graphic.model_validate(block), {"id": REFERENCE, "kind": "scene"},
                                      sources=[SOURCE])
    assert not binding.question_bound(candidate, {"prompt": "Welche Farbe hat das Meer?"})


def test_goal_bound_followup_keeps_questions_and_uses_same_proven_scene():
    from schulpilot import providers
    from schulpilot.package_prepared_photosynthesis import bind_followup
    from schulpilot.subject_content import bind_graphic_schema

    base = payload_for(SOURCE, "Biologie")
    with DB() as db:
        refs = visual_references.candidates(db, "Biologie", SOURCE, package_prepared=True)
    source = {**base["visual_context"]["sources"][0], "group_id": None}
    payload = {"review": True, "practice_kind": "repair", "required_subject": "Biologie",
               "required_topic": "Fotosynthese", "focus_goal_ids": ["g1"],
               "learning_goals": [{"id": "g1", "label": "Stoffaufnahme unterscheiden", "source_excerpt": SOURCE}],
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
    questions = []
    for n, answer in enumerate(("Kohlenstoffdioxid", "Wasser"), start=1):
        questions.append({"id": f"q{n}", "learning_goal_id": "g1", "type": "short",
                          "prompt": "Welches Gas nehmen Pflanzen bei der Fotosynthese auf?" if n == 1
                                    else "Was nehmen Pflanzen bei der Fotosynthese außer Kohlenstoffdioxid auf?",
                          "answer": answer, "options": [], "accepted": [], "hints": ["Lies genau."],
                          "explanation": SOURCE, "presentation": None, "field_group": None,
                          "explanation_steps": [wire_step(solution)]})
    wire = {"subject": "Biologie", "topic": "Fotosynthese", "explanation": SOURCE,
            "explanation_steps": [wire_step(intro)], "questions": questions}
    hydrated = binding.hydrate(wire)
    result = PracticeUnitOutput.model_validate(hydrated).model_dump(mode="json")
    with DB() as db:
        visual_references.validate_output(db, result, payload)
    assert [(q["id"], q["learning_goal_id"], q["answer"]) for q in result["questions"]] == [
        ("q1", "g1", "Kohlenstoffdioxid"), ("q2", "g1", "Wasser")]


def test_explicit_notebook_round_can_use_same_source_bound_scene(monkeypatch):
    from schulpilot import providers
    from schulpilot.package_prepared_photosynthesis import bind_followup
    from schulpilot.subject_content import bind_graphic_schema

    base = payload_for(SOURCE, "Biologie")
    with DB() as db:
        refs = visual_references.candidates(db, "Biologie", SOURCE, package_prepared=True)
    source = {**base["visual_context"]["sources"][0], "group_id": None}
    payload = {"function": "unit", "notebook_practice": {"version": 1, "question_count": 2},
               "review": False, "required_subject": "Biologie", "required_topic": "Fotosynthese",
               "visual_context": {"required": True, "references": refs, "sources": [source]}}
    schema = providers.strict_schema(UnitOutput, preserve_limits=True)
    providers.indexed_choice_schema(schema, bounded_matches=True)
    bind_graphic_schema(schema, ["Biologie"])
    visual_references.bind_schema(schema, payload)
    binding = bind_followup(schema, payload)
    assert binding is not None
    intro = next(row for row in binding.candidates if row["disclosure"] == "given")
    solution = next(row for row in binding.candidates if row["disclosure"] == "solution")
    questions = [{"id": f"q{n}", "type": "short", "prompt": prompt, "answer": answer,
                  "options": [], "accepted": [], "hints": ["Lies genau."], "explanation": SOURCE,
                  "presentation": None, "field_group": None, "explanation_steps": [wire_step(solution)]}
                 for n, (prompt, answer) in enumerate([
                    ("Welches Gas nehmen Pflanzen bei der Fotosynthese auf?", "Kohlenstoffdioxid"),
                    ("Welches Gas geben Pflanzen bei der Fotosynthese ab?", "Sauerstoff")], 1)]
    wire = {"subject": "Biologie", "topic": "Fotosynthese", "explanation": SOURCE,
            "explanation_steps": [wire_step(intro)], "questions": questions}
    result = binding.hydrate(copy.deepcopy(wire))
    result = UnitOutput.model_validate(result).model_dump(mode="json")
    with DB() as db:
        visual_references.validate_output(db, result, payload)
    assert len(result["questions"]) == 2
    assert result["explanation_steps"][0]["reference"]["id"] == REFERENCE
    assert bind_followup(schema, {**payload, "notebook_practice": None}) is None
    assert bind_followup(schema, {**payload, "required_subject": "Physik"}) is None
    from test_presentation_capability_paths import _config, _transport

    calls = _transport(monkeypatch, "openrouter", wire)
    payload["material"] = {"subject": "Biologie", "topic": "Fotosynthese", "content": SOURCE, "uncertainties": []}
    result = providers.request_provider(_config("openrouter"), "unit", payload)
    assert len(calls) == 1
    assert result.data["explanation_steps"][0]["reference"]["id"] == REFERENCE


@pytest.mark.parametrize("mutation", ["not_review", "other_subject", "no_practice", "homework"])
def test_followup_does_not_replace_other_unit_contracts(mutation):
    from schulpilot.package_prepared_photosynthesis import bind_followup

    payload = {"review": True, "practice_kind": "repair", "required_subject": "Biologie"}
    payload.update({"not_review": {"review": False}, "other_subject": {"required_subject": "Physik"},
                    "no_practice": {"practice_kind": "other"}, "homework": {"homework_practice": True}}[mutation])
    assert bind_followup({}, payload) is None
