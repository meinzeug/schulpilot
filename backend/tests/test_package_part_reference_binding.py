"""Immutable recipe identity and its graphic are one request-bound choice.

All source prose is public synthetic text. No real provider or private response
is used; canonical postvalidation and saved-part acceptance remain unchanged.
"""
import copy
import json

import pytest
from schulpilot import package_output_transport, package_part_output, package_transport, providers, visual_references
from schulpilot.db import DB
from schulpilot.schemas import PackageOutput
from schulpilot.subject_content import bind_graphic_schema, generation_context
from schulpilot.visual_reference_models import VisualReference
from test_package_output_transport import fixture
from test_package_part_graphics import CASES, normalized
from test_package_part_output import part


def request(groups=1):
    data, context, _ = fixture(groups=max(2, groups))
    data["units"] = data["units"][:groups]
    for key in ("sources", "references"):
        context["visual_context"][key] = context["visual_context"][key][:groups]
    for unit in data["units"]:
        unit["questions"] = unit["questions"][:2]
        for item in [unit, *unit["questions"]]:
            for step in item["explanation_steps"]:
                step["presentation"]["blocks"] = [normalized(step["presentation"]["blocks"][0])]
    for ref in context["visual_context"]["references"]:
        ref["kind"] = "scene"
    payload = {**context, "package_partition": 0, "selected_groups": [
        {"id": unit["group_id"], "subject": unit["subject"], "estimated_minutes": 8}
        for unit in data["units"]]}
    return data, payload


def schema_for(payload, *, coupled=True):
    schema = providers.strict_schema(PackageOutput, preserve_limits=True)
    subjects = [item["subject"] for item in payload["selected_groups"]]
    providers.prepare_package_schema(schema, payload, partition=True)
    bind_graphic_schema(schema, subjects, labs_enabled=bool(payload.get("labs_enabled")))
    visual_references.bind_schema(schema, payload)
    package_part_output.bind_schema(schema, payload if coupled else None)
    return schema


def binding(payload, *, coupled=True):
    return package_output_transport.bind(package_transport.schema_projection(schema_for(payload, coupled=coupled)))


def test_previous_schema_allowed_the_exact_reference_kind_mismatch_new_request_rejects_it():
    data, payload = request()
    context = payload["visual_context"]
    context["references"].append({"id": "geography.compass.direction", "version": 1,
        "kind": "compass", "subject": "Geographie"})
    data["units"][0]["questions"][0]["explanation_steps"][0]["reference"]["id"] = "geography.compass.direction"
    old = binding(payload, coupled=False)
    assert old.decode(old.encode(data)) == data
    with DB() as db, pytest.raises(ValueError, match="Referenz"):
        visual_references.validate_output(db, data, payload)
    with pytest.raises(ValueError):
        binding(payload).encode(data)


@pytest.mark.parametrize("fault", ["cross_version", "foreign_subject", "foreign_group", "unknown_ref",
    "intro_solution", "question_given", "mixed_disclosure", "missing_metadata"])
def test_new_request_excludes_wrong_reference_scope_identity_and_disclosure(fault):
    data, payload = request(groups=2)
    context, unit = payload["visual_context"], data["units"][0]
    step = unit["explanation_steps"][0]
    if fault == "cross_version":
        context["references"].append({"id": "geography.compass.direction", "version": 2,
            "kind": "compass", "subject": "Geographie"})
        step["reference"]["version"] = 2  # Only the OTHER recipe has version2.
    elif fault == "foreign_subject":
        context["references"][0]["subject"] = "Englisch"
    elif fault == "foreign_group":
        context["sources"].append({**context["sources"][0], "ref": "p3", "group_id": "g3"})
        step["source_refs"] = ["p3"]
    elif fault == "unknown_ref":
        step["reference"]["id"] = "unknown.recipe"
    elif fault == "intro_solution":
        step["disclosure"] = step["presentation"]["blocks"][0]["disclosure"] = "solution"
    elif fault == "question_given":
        step = unit["questions"][0]["explanation_steps"][0]
        step["disclosure"] = step["presentation"]["blocks"][0]["disclosure"] = "given"
    elif fault == "mixed_disclosure":
        step["presentation"]["blocks"][0]["disclosure"] = "hint1"
    else:
        context["references"][0].pop("kind")
    with pytest.raises(ValueError):
        binding(payload).encode(data)


@pytest.mark.parametrize("stage", ["hint1", "hint2", "hint3", "solution"])
@pytest.mark.parametrize("groups", [1, 2])
def test_valid_multiple_subjects_and_question_stages_roundtrip_without_source_or_answer_changes(stage, groups):
    data, payload = request(groups)
    for unit in data["units"]:
        for question in unit["questions"]:
            step = question["explanation_steps"][0]
            step["disclosure"] = step["presentation"]["blocks"][0]["disclosure"] = stage
    original, original_payload = copy.deepcopy(data), copy.deepcopy(payload)
    value = binding(payload)
    decoded = value.decode(value.encode(data))
    assert decoded == original and payload == original_payload
    assert PackageOutput.model_validate(decoded).model_dump(mode="json") == original
    with DB() as db:
        visual_references.validate_output(db, decoded, payload)


def test_immutable_candidate_metadata_contains_only_the_actual_variant_and_lab_recipe():
    with DB.begin() as db:
        recipe = {"id": "test.plant.roots", "version": 1, "kind": "plant", "subjects": ["Biologie"],
            "purpose": "Eigenes künstliches Wurzelbeispiel", "terms": ["Wurzel"], "interaction": "inspect", "variant": "roots"}
        db.add(VisualReference(id=recipe["id"], version=1, digest=visual_references.digest(recipe), recipe=recipe))
        db.flush()
        row = next(item for item in visual_references.candidates(db, "Biologie", "Wurzel") if item["id"] == recipe["id"])
        assert row["variant"] == "roots" and "lab_recipe_id" not in row
        lab = next(item for item in visual_references.candidates(db, "Physik", "Kraft") if item["kind"] == "lab")
        assert lab["lab_recipe_id"] == "physics.force_motion" and "variant" not in lab


@pytest.mark.parametrize("variant,kind,subject", [("roots", "plant", "Biologie"), ("pollination", "forms", "Biologie")])
def test_curated_variant_is_bound_even_when_base_variant_has_no_explicit_enum(variant, kind, subject):
    data, payload = request()
    unit = data["units"][0]
    unit["subject"] = payload["selected_groups"][0]["subject"] = subject
    for row in payload["visual_context"]["sources"] + payload["visual_context"]["references"]:
        row["subject"] = subject
    payload["visual_context"]["references"].append({"id": "test." + variant, "version": 1,
        "kind": kind, "variant": variant, "subject": subject})
    step = unit["questions"][0]["explanation_steps"][0]
    step["reference"]["id"] = "test." + variant
    block = step["presentation"]["blocks"][0]
    block.update(kind=kind, variant=variant, scene=None)
    if kind == "plant":
        # The current plant schema has four fixed positions; this is still a
        # transport-only fixture and does not claim these labels are sourced.
        block["labels"] = ["Blüte", "Blatt", "Stängel", "Wurzel"]
    value = binding(payload)
    assert value.decode(value.encode(data)) == data  # Structural pairing; not a source-approval claim.
    block["variant"] = ""
    with pytest.raises(ValueError):
        value.encode(data)


@pytest.mark.parametrize("recipe,subject", [("physics.force_motion", "Physik"), ("german.sentence_shift", "Deutsch")])
def test_lab_reference_is_bound_to_its_actual_finite_recipe_and_parameter_family(recipe, subject):
    data, payload = request()
    unit = data["units"][0]
    unit["subject"] = payload["selected_groups"][0]["subject"] = subject
    for row in payload["visual_context"]["sources"] + payload["visual_context"]["references"]:
        row["subject"] = subject
    payload["labs_enabled"] = True
    payload["visual_context"]["references"].append({"id": "lab." + recipe, "version": 1,
        "kind": "lab", "lab_recipe_id": recipe, "subject": subject})
    step = unit["questions"][0]["explanation_steps"][0]
    step["reference"]["id"] = "lab." + recipe
    block = next(normalized(block) for case_id, _, block in CASES if case_id == recipe)
    block["disclosure"] = "solution"
    step["presentation"]["blocks"] = [block]
    value = binding(payload)
    assert value.decode(value.encode(data)) == data
    block["lab"]["recipe_id"] = "german.sentence_shift" if recipe == "physics.force_motion" else "physics.force_motion"
    with pytest.raises(ValueError):
        value.encode(data)


def test_capabilities_use_reachable_reference_bound_graphics_and_ignore_inactive_global_defs():
    _, payload = request()
    schema = schema_for(payload)
    context = generation_context(["Geographie"], schema=schema)
    assert context["graphic_kinds"] == ["scene"] and context["max_blocks"] == 1
    schema["$defs"]["Graphic"]["properties"]["kind"]["enum"] = ["compass"]
    schema["$defs"]["Presentation"]["properties"]["blocks"]["maxItems"] = 99
    assert generation_context(["Geographie"], schema=schema) == context


def test_saved_part_validation_and_nonpart_contract_remain_unchanged():
    data, payload = part()
    saved = copy.deepcopy(data)
    package_part_output.validate(data)
    assert data == saved
    payload["package_partition"] = None
    before = schema_for(payload, coupled=False)
    after = schema_for(payload, coupled=True)
    assert before == after
    assert json.dumps(data, ensure_ascii=False) == json.dumps(saved, ensure_ascii=False)
