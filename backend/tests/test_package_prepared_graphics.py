"""Actual canonical validators over public artificial prepared graphics only."""
import copy
import json
import re
from collections import Counter

import pytest
from schulpilot import package_output_transport, package_part_output, package_transport, providers, visual_references
from schulpilot import package_prepared_graphics as prepared_graphics
from schulpilot.db import DB
from schulpilot.schemas import PackageOutput
from schulpilot.subject_content import Graphic, bind_graphic_schema
from test_package_part_output import part

SOURCE = "Ein Bruch 1/2 beschreibt 1 von 2 gleich großen Teilen.\nEin Bruch 2/3 beschreibt 2 von 3 gleich großen Teilen.\nWasser → Dampf."


def payload_for(content=SOURCE, subject="Mathematik"):
    with DB() as db:
        references = visual_references.candidates(db, subject, "Bruch " + content)
    return {"package_partition": 1, "package_plan_digest": "a" * 64,
        "selected_groups": [{"id": "g1", "subject": subject, "estimated_minutes": 8}],
        "materials": [{"subject": subject, "group_id": "g1", "topic": "Brüche", "content": content}],
        "visual_context": {"required": True, "references": references,
            "sources": [{"ref": "p1", "material_id": "b" * 32, "revision": 3, "source_refs": [{"block_id": "c" * 32}],
                         "subject": subject, "group_id": "g1", "topic": "Brüche", "content": content}]}}


def bind(payload):
    schema = providers.strict_schema(PackageOutput, preserve_limits=True)
    providers.prepare_package_schema(schema, payload, partition=True)
    bind_graphic_schema(schema, [row["subject"] for row in payload["selected_groups"]])
    visual_references.bind_schema(schema, payload)
    binding = package_part_output.bind_schema(schema, payload)
    return schema, binding


def wire_step(candidate):
    return {"id": "e1", "text": candidate["text"], "competence_id": None,
        "disclosure": candidate["disclosure"], "reference": copy.deepcopy(candidate["reference"]), "source_refs": list(candidate["source_refs"]),
        "presentation": {"version": 1, "evidence_kind": "knowledge", "blocks": [candidate["id"]]}}


def prepared(*, scene=False):
    """Return pre-codec ID-wire data, actual-source payload and bound hydrator."""
    payload = payload_for()
    _, binding = bind(payload)
    assert binding is not None
    intro = next(row for row in binding.candidates if row["kind"] == ("scene" if scene else "fraction") and row["disclosure"] == "given")
    selected = [row for row in binding.candidates if row["kind"] == "fraction" and row["disclosure"] == "solution"]
    questions = []
    for index in range(2):
        candidate = selected[index % len(selected)]
        n, d = map(int, candidate["block"]["numbers"])
        prompt = f"Was beschreibt der Bruch {n}/{d} mit {n} von {d} gleich großen Teilen?"
        answer = f"{n}/{d}"
        questions.append({"id": f"q{index + 1}", "type": "short", "prompt": prompt,
            "options": [], "answer": answer, "accepted": [], "hints": ["Lies den belegten Zusammenhang."],
            "explanation": SOURCE, "presentation": None, "field_group": None, "explanation_steps": [wire_step(candidate)]})
    data = {"units": [{"group_id": "g1", "subject": "Mathematik", "topic": "Brüche",
        "explanation": SOURCE, "explanation_steps": [wire_step(intro)], "questions": questions}]}
    return data, payload, binding


@pytest.mark.parametrize("literal,expected", [("1/2", (1, 2)), ("0/4", (0, 4)), ("24/24", (24, 24)),
    ("1 / 2.", (1, 2)), ("1/2, Text", (1, 2)), ("1/2;", (1, 2)), ("3/4", (3, 4))])
def test_only_literal_supported_proper_fraction_is_compiled_and_all_canonical_validators_pass(literal, expected):
    payload = payload_for("Bruch " + literal)
    candidates = prepared_graphics.compile_candidates(payload)
    assert Counter(row["kind"] for row in candidates) == {"fraction": 5}
    assert {row["disclosure"] for row in candidates} == set(prepared_graphics.STAGES)
    for row in candidates:
        block = Graphic.model_validate(row["block"])
        assert tuple(map(int, block.numbers)) == expected
        assert block.source_excerpt in payload["visual_context"]["sources"][0]["content"]
        assert block.labels == [] and row["source_refs"] == ["p1"]
        assert len(row["text"]) <= 350
    schema, binding = bind(payload)
    assert binding is not None and schema["properties"]["units"]["items"]


@pytest.mark.parametrize("literal", ["3/2", "1/0", "25/25", "-1/2", "−1/2", "+1/2", "- 1/2", "− 1/2", "+ 1/2", "1/2.5", "1/20,5", "123/4", "1/234", "½", "1%", "Unbekannter Stoff"])
def test_unsupported_numbers_are_not_capped_reduced_repaired_or_used_as_a_fallback(literal):
    payload = payload_for("Bruch " + literal)
    assert prepared_graphics.compile_candidates(payload) == []
    assert bind(payload)[1] is None


@pytest.mark.parametrize("scene", [False, True])
def test_requested_id_projection_is_lossless_before_all_canonical_output_source_and_recipe_validators(scene):
    wire, payload, binding = prepared(scene=scene)
    before, before_payload = copy.deepcopy(wire), copy.deepcopy(payload)
    schema, _ = bind(payload)
    codec = package_output_transport.bind(package_transport.schema_projection(schema))
    decoded = codec.decode(codec.encode(wire))
    assert decoded == before
    hydrated = binding.hydrate(decoded)
    assert wire == before and payload == before_payload
    actual = PackageOutput.model_validate(hydrated).model_dump(mode="json")
    assert actual == hydrated
    package_part_output.validate(actual)
    with DB() as db:
        visual_references.validate_output(db, actual, payload)
    assert [q["answer"] for q in actual["units"][0]["questions"]] == [q["answer"] for q in before["units"][0]["questions"]]
    assert all(isinstance(step["presentation"]["blocks"][0], str) for unit in before["units"]
        for item in [unit, *unit["questions"]] for step in item["explanation_steps"])
    assert "source_excerpt" not in json.dumps(binding.context)
    assert prepared_graphics.REVISION in binding.rules


@pytest.mark.parametrize("fault", ["unknown_id", "wrong_source", "wrong_ref", "wrong_version", "wrong_stage", "wrong_text",
    "foreign_subject", "foreign_group", "two_ids", "full_graphic", "old_shape", "bool_version", "bool_reference_version"])
def test_hydration_refuses_field_mixes_without_fixing_answers_or_partial_graphics(fault):
    wire, _, binding = prepared()
    unit = wire["units"][0]
    step = unit["questions"][0]["explanation_steps"][0]
    if fault == "unknown_id":
        step["presentation"]["blocks"] = ["pg_unknown"]
    elif fault == "wrong_source":
        step["source_refs"] = ["p2"]
    elif fault == "wrong_ref":
        step["reference"] = {"id": "general.source_relation.phases", "version": 1}
    elif fault == "wrong_version":
        step["reference"] = {**step["reference"], "version": 2}
    elif fault == "wrong_stage":
        step["disclosure"] = "given"
    elif fault == "wrong_text":
        step["text"] = "Andere Zahlen: 3/4"
    elif fault == "foreign_subject":
        unit["subject"] = "Physik"
    elif fault == "foreign_group":
        unit["group_id"] = "g2"
    elif fault == "two_ids":
        step["presentation"]["blocks"] *= 2
    elif fault == "full_graphic":
        step["presentation"]["blocks"] = [copy.deepcopy(binding.candidates[0]["block"])]
    elif fault == "old_shape":
        step["presentation"] = {"blocks": step["presentation"]["blocks"]}
    elif fault == "bool_reference_version":
        step["reference"] = {**step["reference"], "version": True}
    else:
        step["presentation"]["version"] = True
    before = copy.deepcopy(wire)
    errors = {"unknown_id": "Unbekannte vorbereitete Grafik-ID.",
        "foreign_subject": "Vorbereitete Grafik gehört nicht zum Fach oder zur Paketgruppe.",
        "foreign_group": "Vorbereitete Grafik gehört nicht zum Fach oder zur Paketgruppe.",
        "wrong_stage": "Vorbereitete Grafik gehört nicht zur erlaubten Aufdeckstufe."}
    expected = errors.get(fault, "Ungültige Struktur der vorbereiteten Grafikzuordnung." if fault in
        ("two_ids", "full_graphic", "old_shape", "bool_version") else
        "Vorbereitete Grafikmetadaten stimmen nicht mit der Auswahl überein.")
    with pytest.raises(ValueError) as caught:
        binding.hydrate(wire)
    assert str(caught.value) == expected
    assert wire == before


@pytest.mark.parametrize("field", ["revision", "content", "material_id", "block_id", "plan", "part", "recipe_digest"])
def test_candidate_ids_bind_exact_source_revision_full_content_block_and_plan_identity(field):
    payload = payload_for()
    changed = copy.deepcopy(payload)
    source = changed["visual_context"]["sources"][0]
    if field == "revision":
        source["revision"] += 1
    elif field == "content":
        source["content"] += "\nAnderer bestätigter Stoff."
    elif field == "material_id":
        source["material_id"] = "d" * 32
    elif field == "block_id":
        source["source_refs"][0]["block_id"] = "e" * 32
    elif field == "plan":
        changed["package_plan_digest"] = "f" * 64
    elif field == "part":
        changed["package_partition"] += 1
    else:
        for ref in changed["visual_context"]["references"]:
            ref["digest"] = "9" * 64
    original = {row["id"] for row in prepared_graphics.compile_candidates(payload)}
    current = {row["id"] for row in prepared_graphics.compile_candidates(changed)}
    assert original and current and original.isdisjoint(current)


def test_candidates_are_bounded_deterministic_private_and_do_not_leak_to_another_group_or_subject():
    payload = payload_for("Bruch " + " ".join(f"{n}/24" for n in range(24)))
    values = prepared_graphics.compile_candidates(payload)
    assert len(values) == prepared_graphics.MAX_BASE_CANDIDATES * 5
    assert values == prepared_graphics.compile_candidates(payload)
    payload["visual_context"]["sources"][0]["group_id"] = "g2"
    assert prepared_graphics.compile_candidates(payload) == []
    payload["visual_context"]["sources"][0]["group_id"] = "g1"
    payload["visual_context"]["sources"][0]["subject"] = "Englisch"
    assert prepared_graphics.compile_candidates(payload) == []


@pytest.mark.parametrize("text", ["Keine belegten Pfeile.", "A ← B", "A → A", "A → B → C → D → E", "https://host → B"])
def test_scene_compiler_never_guesses_reverses_or_extends_a_relation(text):
    assert not any(row["kind"] == "scene" for row in prepared_graphics.compile_candidates(payload_for(text)))


def test_explicit_nonmath_source_binding_keeps_legacy_paths_and_existing_saved_parts_unchanged():
    payload = payload_for("Wasser → Dampf.", subject="Geographie")
    assert prepared_graphics.compile_candidates(payload)
    assert bind(payload)[1].context["revision"] == "package-source-graphics-2"
    # The new source-bound nonmath contract is explicit; legacy requests and
    # already saved canonical outputs do not acquire it retroactively.
    payload["package_partition"] = None
    assert prepared_graphics.compile_candidates(payload) == []
    assert bind(payload)[1] is None
    data, _ = part()
    frozen = copy.deepcopy(data)
    package_part_output.validate(data)
    assert data == frozen


@pytest.mark.parametrize("literal,pair", [(r"\frac{1}{2}", (1, 2)), (r"\dfrac{2}{3}", (2, 3)), (r"\frac{3}{2}", None)])
def test_exact_latex_fraction_pairs_keep_the_complete_original_quote_and_canonical_bounds(literal, pair):
    payload = payload_for("Bruch " + literal)
    rows = prepared_graphics.compile_candidates(payload)
    if pair is None:
        assert rows == [] and bind(payload)[1] is None
        return
    assert len(rows) == 5
    for row in rows:
        assert tuple(map(int, row["block"]["numbers"])) == pair
        assert row["block"]["source_excerpt"] == literal
    assert bind(payload)[1] is not None


def anchored_wire():
    return prepared()


def test_question_anchor_rejects_unrelated_fraction_without_rewriting_the_question():
    wire, _, binding = anchored_wire()
    wire["units"][0]["questions"][0]["prompt"] = "Welchen Nenner hat der Bruch 5/4?"
    original = copy.deepcopy(wire)
    with pytest.raises(ValueError, match="Frageparametern"):
        binding.hydrate(wire)
    assert wire == original


def test_scene_question_is_not_offered_even_when_its_source_labels_match_the_question():
    wire, _, binding = prepared(scene=True)
    selected = next(row for row in binding.candidates if row["kind"] == "scene" and row["disclosure"] == "solution")
    wire["units"][0]["questions"][0].update(prompt="Beschreibe Wasser und Dampf.", explanation_steps=[wire_step(selected)])
    original = copy.deepcopy(wire)
    assert selected["id"] not in {row["id"] for row in binding.context["candidates"]}
    with pytest.raises(ValueError, match="Grafik-ID"):
        binding.hydrate(wire)
    assert wire == original


@pytest.mark.parametrize("prompt,accepted", [
    ("Was beschreibt 2/3?", True),
    (r"Was beschreibt \frac{2}{3}?", False),
    (r"Was beschreibt \dfrac { 2 } { 3 }?", False),
    ("Was beschreibt 2 / 3?", False),
    (r"Was beschreibt \(2/3\)?", True),
    ("Was beschreibt 4/6?", False),
    ("Was beschreibt 5/4?", False),
    ("Was beschreibt 12/3?", False),
    ("Was beschreibt 2/30?", False),
    ("Was beschreibt -2/3?", False),
    ("Was beschreibt 2/3.5?", False),
])
def test_question_anchor_uses_exact_numerator_denominator_not_numeric_equivalence(prompt, accepted):
    wire, _, binding = anchored_wire()
    selected = next(row for row in binding.candidates
        if row["disclosure"] == "solution" and row["kind"] == "fraction" and row["block"]["numbers"] == [2, 3])
    question = wire["units"][0]["questions"][0]
    question.update(prompt=prompt, answer="2/3", explanation_steps=[wire_step(selected)])
    original = copy.deepcopy(wire)
    if accepted:
        assert binding.hydrate(wire)["units"][0]["questions"][0]["answer"] == "2/3"
    else:
        with pytest.raises(ValueError, match="Frageparametern"):
            binding.hydrate(wire)
    assert wire == original


@pytest.mark.parametrize("prompt,accepted", [
    ("Beschreibe Wasser und Dampf.", True),
    ("Beschreibe Wasser\nund\tDampf.", True),
    ("Beschreibe Wasserstoff und Dampf.", False),
    ("Beschreibe Wasser und Wasserdampf.", False),
    ("Beschreibe Wasser und Dampfer.", False),
    ("Beschreibe Wasser und Wasser.", False),
    ("Beschreibe den Bruch 1/2.", False),
])
def test_question_anchor_needs_two_distinct_complete_scene_object_expressions(prompt, accepted):
    payload = payload_for()
    candidate = next(row for row in prepared_graphics.compile_candidates(payload)
        if row["kind"] == "scene" and row["disclosure"] == "solution")
    # A semantic helper regression only: new maths requests do not offer scene questions.
    assert prepared_graphics._question_anchor(candidate, {"prompt": prompt}) is accepted


def test_intro_does_not_require_a_question_anchor():
    wire, _, binding = anchored_wire()
    wire["units"][0]["explanation"] = "Eine offene Einführung ohne einzelne Beispielzahlen."
    assert binding.hydrate(wire)["units"][0]["explanation"] == wire["units"][0]["explanation"]



@pytest.mark.parametrize("labels,prompt,accepted", [
    ("flüssiges Wasser → heißer Dampf.", "Beschreibe flüssiges\nWasser und heißer\tDampf.", True),
    ("flüssiges Wasser → heißer Dampf.", "Beschreibe Wasser und Dampf.", False),
    ("CO → CO2.", "Beschreibe CO und CO2.", True),
    ("CO → CO2.", "Beschreibe Co und CO2.", False),
])
def test_question_anchor_preserves_whole_multiword_labels_and_scientific_case(labels, prompt, accepted):
    payload = payload_for("Ein Bruch 1/2 beschreibt 1 von 2 Teilen.\n" + labels)
    candidate = next(row for row in prepared_graphics.compile_candidates(payload)
        if row["kind"] == "scene" and row["disclosure"] == "solution")
    assert prepared_graphics._question_anchor(candidate, {"prompt": prompt}) is accepted


def _resolved(schema, node):
    return schema["$defs"][node["$ref"].rsplit("/", 1)[-1]] if "$ref" in node else node


def _question_branches(schema):
    units = schema["properties"]["units"]["items"]["anyOf"]
    for unit in units:
        unit = _resolved(schema, unit)
        question = _resolved(schema, unit["properties"]["questions"]["items"])
        for branch in question["anyOf"]:
            yield _resolved(schema, branch)


def test_each_request_question_branch_couples_its_prompt_pattern_to_one_base_with_four_exact_stage_ids():
    _, payload, binding = prepared()
    schema, _ = bind(payload)
    choices = {row["id"]: row for row in binding.candidates}
    branches = list(_question_branches(schema))
    assert branches
    for branch in branches:
        steps = branch["properties"]["explanation_steps"]["items"]["anyOf"]
        assert len(steps) == 4
        all_choices = []
        for selected_step in steps:
            selected_step = _resolved(schema, selected_step)
            ids = selected_step["properties"]["presentation"]["properties"]["blocks"]["items"]["enum"]
            assert len(ids) == 1
            all_choices.append(choices[ids[0]])
        assert {row["disclosure"] for row in all_choices} == {"hint1", "hint2", "hint3", "solution"}
        bases = []
        for row in all_choices:
            base = copy.deepcopy(row)
            base.pop("id")
            base.pop("disclosure")
            base["block"].pop("disclosure")
            bases.append(base)
        assert all(base == bases[0] for base in bases)
        step = _resolved(schema, steps[0])
        graphic_id = step["properties"]["presentation"]["properties"]["blocks"]["items"]["enum"]
        assert len(graphic_id) == 1
        candidate = choices[graphic_id[0]]
        assert candidate["kind"] == "fraction" and candidate["disclosure"] != "given"
        pattern = branch["properties"]["prompt"]["pattern"]
        assert pattern == prepared_graphics._fraction_prompt_pattern(candidate)
        n, d = map(int, candidate["block"]["numbers"])
        assert re.search(pattern, f"Was beschreibt {n}/{d}?")
        assert not re.search(pattern, f"Was beschreibt {n + d}/{d}?")
        assert not re.search(pattern, f"Was beschreibt {n}/{d}0?")
        assert not re.search(pattern, rf"Was beschreibt \frac{{{n}}}{{{d}}}?")
    projected = package_transport.schema_projection(schema)
    codec = package_output_transport.bind(projected)
    text = json.dumps(codec.wire_schema)
    assert all(json.dumps(branch["properties"]["prompt"]["pattern"])[1:-1] in text for branch in branches)


@pytest.mark.parametrize("text,valid", [("Was beschreibt 2/3?", True), ("Was beschreibt 2/3.", True),
    ("Vergleiche (2/3).", True), (r"Vergleiche \(2/3\).", True), ("Was beschreibt 2/30?", False), ("Was beschreibt 12/3?", False),
    ("Was beschreibt 2/3.5?", False), ("Was beschreibt 2/3,5?", False), ("x2/3", False),
    ("2/3x", False), ("2/3/4", False)])
def test_fraction_prompt_pattern_has_literal_character_boundaries_without_lookarounds(text, valid):
    candidate = next(row for row in prepared_graphics.compile_candidates(payload_for())
        if row["kind"] == "fraction" and row["block"]["numbers"] == [2, 3])
    pattern = prepared_graphics._fraction_prompt_pattern(candidate)
    assert "(?=" not in pattern and "(?<" not in pattern and "(?!" not in pattern
    assert bool(re.search(pattern, text)) is valid


@pytest.mark.parametrize("compatible", [True, False])
def test_fixed_entry_prompt_and_answer_are_never_rewritten_to_fit_a_graphic(compatible):
    payload = payload_for()
    schema = providers.strict_schema(PackageOutput, preserve_limits=True)
    providers.prepare_package_schema(schema, payload, partition=True)
    bind_graphic_schema(schema, ["Mathematik"])
    visual_references.bind_schema(schema, payload)
    prompt = "Was beschreibt 1/2?" if compatible else "Benenne den unteren Teil eines Bruchs."
    original = schema["$defs"]["Question"]["properties"]
    original["prompt"]["enum"] = [prompt]
    original["answer"]["enum"] = ["1/2"]
    answer = copy.deepcopy(original["answer"])
    if not compatible:
        with pytest.raises(ValueError, match="festgelegte Frage"):
            package_part_output.bind_schema(schema, payload)
        return
    package_part_output.bind_schema(schema, payload)
    for branch in _question_branches(schema):
        assert branch["properties"]["prompt"]["enum"] == [prompt]
        assert branch["properties"]["answer"] == answer


def test_max_eight_bases_use_eight_question_templates_without_dropping_any_stage():
    payload = payload_for("Bruch " + " ".join(f"{n}/24" for n in range(8)))
    schema, binding = bind(payload)
    branches = list(_question_branches(schema))
    assert len(branches) == 8
    ids = []
    for branch in branches:
        steps = branch["properties"]["explanation_steps"]["items"]["anyOf"]
        assert len(steps) == 4
        for step in steps:
            selected = _resolved(schema, step)
            ids.extend(selected["properties"]["presentation"]["properties"]["blocks"]["items"]["enum"])
    assert len(ids) == len(set(ids)) == 32
    assert len(binding.context["candidates"]) == 40


@pytest.mark.parametrize("stage", ["hint1", "hint2", "hint3", "solution"])
def test_every_stage_roundtrips_for_the_same_exact_fraction_base(stage):
    wire, payload, binding = prepared()
    row = next(row for row in binding.candidates if row["kind"] == "fraction"
        and row["block"]["numbers"] == [1, 2] and row["disclosure"] == stage)
    wire["units"][0]["questions"][0]["explanation_steps"] = [wire_step(row)]
    schema, _ = bind(payload)
    codec = package_output_transport.bind(package_transport.schema_projection(schema))
    restored = binding.hydrate(codec.decode(codec.encode(wire)))
    assert restored["units"][0]["questions"][0]["explanation_steps"][0]["disclosure"] == stage
    assert restored["units"][0]["questions"][0]["answer"] == "1/2"
    with DB() as db:
        visual_references.validate_output(db, restored, payload)


def test_equivalent_fractions_and_different_original_pages_are_not_merged_into_one_base():
    payload = payload_for("Brüche 1/2 und 2/4.")
    original = payload["visual_context"]["sources"][0]
    payload["visual_context"]["sources"].append({**copy.deepcopy(original), "ref": "p2", "material_id": "d" * 32})
    schema, binding = bind(payload)
    assert len(list(_question_branches(schema))) == 4
    assert len(binding.context["candidates"]) == 20
    candidate = next(row for row in binding.candidates if row["kind"] == "fraction"
        and row["block"]["numbers"] == [2, 4] and row["disclosure"] == "solution")
    wire, _, _ = prepared()
    intro = next(row for row in binding.candidates if row["disclosure"] == "given")
    wire["units"][0]["explanation_steps"] = [wire_step(intro)]
    wire["units"][0]["questions"][0].update(prompt="Was beschreibt 1/2?", explanation_steps=[wire_step(candidate)])
    with pytest.raises(ValueError, match="Frageparametern"):
        binding.hydrate(wire)


@pytest.mark.parametrize('line,labels', [
    ('1) go → went', ['go', 'went']),
    ('12. play → played', ['play', 'played']),
    ('3 → 7', ['3', '7']),
    ('A1 → B2', ['A1', 'B2']),
])
def test_scene_excludes_only_separate_exercise_number_and_preserves_verbatim_quote(line, labels):
    bases = list(prepared_graphics._scene_bases(line))
    assert len(bases) == 1
    block, _ = bases[0]
    assert block['source_excerpt'] == line and block['labels'] == labels
    assert [obj['label'] for obj in block['scene']['objects']] == labels
    for stage in prepared_graphics.STAGES:
        graphic = Graphic.model_validate({**block, 'disclosure': stage})
        from schulpilot.subject_content import PROFILES, validate_question
        validate_question({'version': 1, 'evidence_kind': 'knowledge', 'blocks': [graphic.model_dump()]},
            {'prompt': '', 'type': 'short', 'answer': '', 'accepted': []}, [line], PROFILES['Englisch'],
            structured=True, subject='Englisch')
