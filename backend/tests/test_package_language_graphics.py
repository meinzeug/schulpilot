"""An original language comparison remains feasible without source arrows."""
import copy

from schulpilot.package_transport import rules
from schulpilot.subject_content import generation_context
from test_package_part_reference_binding import binding, request, schema_for


def language_part(*, arrow=False, comparison=True):
    data, payload = request()
    unit = data["units"][0]
    unit["subject"] = payload["selected_groups"][0]["subject"] = "Englisch"
    content = "I walk to school. He walks to school."
    if arrow:
        content += "\nwater → steam"
    for row in payload["visual_context"]["sources"]:
        row.update(subject="Englisch", content=content)
    payload["visual_context"]["references"] = [{"id": "general.source_relation.phases", "version": 1,
        "kind": "scene", "subject": "Englisch"}]
    if comparison:
        payload["visual_context"]["references"].append({"id": "language.forms.original_comparison", "version": 1,
            "kind": "forms", "variant": "classification", "subject": "Englisch"})
    for item in [unit, *unit["questions"]]:
        step = item["explanation_steps"][0]
        step["reference"] = {"id": "language.forms.original_comparison", "version": 1}
        step["presentation"]["blocks"][0].update(kind="forms", labels=["I walk to school.", "He walks to school."],
            source_excerpt=content, numbers=[], connections=[], marks=[], unit="", variant="classification", scene=None)
    return data, payload


def test_no_arrow_language_part_offers_applicable_comparison_instead_of_impossible_scene():
    data, payload = language_part()
    before = copy.deepcopy(payload)
    schema = schema_for(payload)
    assert generation_context(["Englisch"], schema=schema)["graphic_kinds"] == ["forms"]
    codec = binding(payload)
    assert codec.decode(codec.encode(data)) == data
    assert payload == before  # No source, catalogue or private context rewriting.
    instructions = rules({**payload, "content_context": generation_context(["Englisch"], schema=schema)}, indexed_choices=True)
    assert "Bestäubung" not in instructions and "MATH:" not in instructions


def test_literal_source_arrows_keep_the_original_directed_scene_available():
    _, payload = language_part(arrow=True)
    assert generation_context(["Englisch"], schema=schema_for(payload))["graphic_kinds"] == ["forms", "scene"]


def test_other_legacy_requests_keep_their_reference_contract():
    _, payload = language_part(comparison=False)
    assert generation_context(["Englisch"], schema=schema_for(payload))["graphic_kinds"] == ["scene"]


def test_comparison_request_advertises_complete_parameter_family_and_bounds():
    _, payload = language_part()
    schema = schema_for(payload)
    comparisons = [node["properties"] for node in schema["$defs"].values()
        if node.get("properties", {}).get("kind", {}).get("enum") == ["forms"]
        and node["properties"].get("variant", {}).get("enum") == ["classification"]]
    assert comparisons
    for fields in comparisons:
        assert fields["labels"]["minItems"] == 2 and fields["labels"]["maxItems"] == 4
        assert fields["variant"]["enum"] == ["classification"] and fields["unit"]["enum"] == [""]
        for name in ("numbers", "connections", "marks"):
            assert fields[name]["minItems"] == fields[name]["maxItems"] == 0
        for name in ("scene", "text_probe", "lab"):
            assert fields[name] == {"type": "null"}
