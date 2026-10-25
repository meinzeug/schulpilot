"""Fixed server subjects stay fixed; topic matching remains optional."""
import copy

import pytest
from schulpilot import package_output_transport, package_transport, providers
from schulpilot.catalog_ai import CatalogAssignment, checked_assignment, constrain_schema
from schulpilot.package_part_catalog import bind_schema


def example():
    schema = providers.strict_schema(CatalogAssignment, preserve_limits=True)
    schema = {"type": "object", "properties": {"catalog_assignment": schema},
              "required": ["catalog_assignment"], "additionalProperties": False,
              "$defs": schema.pop("$defs", {})}
    # Use the actual named definition used by the package's augmented model.
    schema["$defs"]["CatalogAssignment"] = schema["properties"]["catalog_assignment"]
    schema["properties"]["catalog_assignment"] = {"$ref": "#/$defs/CatalogAssignment"}
    context = {"snapshot_id": "public-synthetic", "subjects": [{"id": "math", "title": "Mathematik"},
        {"id": "physics", "title": "Physik"}], "subject_aliases": {"mathe": "math", "mathematik": "math"},
        "candidates": [], "context_refs": ["g"]}
    payload = {"package_partition": 0, "selected_groups": [{"id": "g", "subject": "Mathe"}],
               "catalog_context": context}
    constrain_schema(schema, context)
    return schema, payload


def test_fixed_subject_is_required_in_final_wire_and_valid_annotation_roundtrips():
    schema, payload = example()
    bind_schema(schema, payload)
    field = schema["$defs"]["CatalogAssignment"]["properties"]["subject_ids"]
    assert field["minItems"] == field["maxItems"] == 1
    assert field["items"]["enum"] == ["math"]
    value = {"subject_ids": ["math"], "matches": [], "unmatched_context_refs": ["g"]}
    binding = package_output_transport.bind(package_transport.schema_projection(schema))
    decoded = binding.decode(binding.encode({"catalog_assignment": value}))
    assert decoded["catalog_assignment"] == value
    assert checked_assignment(value, payload["catalog_context"], {"units": [{"subject": "Mathe"}]}) == {
        "snapshot_id": "public-synthetic", "subject_ids": ["math"], "matches": []}
    # No replacement or acceptance of an invalid response after generation.
    for ids in ([], ["physics"]):
        with pytest.raises(ValueError, match="Output subject"):
            checked_assignment({**value, "subject_ids": ids}, payload["catalog_context"],
                               {"units": [{"subject": "Mathe"}]})


@pytest.mark.parametrize("change", ["legacy", "unknown", "multiple", "no_catalog"])
def test_only_new_known_single_subject_parts_are_bound(change):
    schema, payload = example()
    if change == "legacy":
        payload.pop("package_partition")
    elif change == "unknown":
        payload["selected_groups"][0]["subject"] = "Unzugeordnet"
    elif change == "multiple":
        payload["selected_groups"].append({"id": "h", "subject": "Physik"})
    else:
        payload.pop("catalog_context")
    before = copy.deepcopy(schema)
    bind_schema(schema, payload)
    assert schema == before
