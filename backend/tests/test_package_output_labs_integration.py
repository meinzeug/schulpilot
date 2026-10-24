"""Additive real-adapter intersection: compact packages plus both finite labs."""
import pytest
from schema_helpers import object_with
from schulpilot import learning_labs, providers, visual_references
from schulpilot.db import DB, Activity, Attempt, Child, LearningUnit, Material
from schulpilot.schemas import PackageOutput
from test_learning_labs import make_unit
from test_presentation_capability_paths import _config, _submitted, _transport


@pytest.mark.parametrize("provider", ["openai", "openrouter", "codex"])
@pytest.mark.parametrize("recipe", list(learning_labs.RECIPES))
def test_package_codec_preserves_both_finite_labs_through_real_adapter_and_canonical_guards(monkeypatch, household, provider, recipe):
    _, mid, _, output = make_unit(household, recipe)
    with DB() as db:
        child, material = db.get(Child, household[1]["id"]), db.get(Material, mid)
        group = {"id": "g1", "subject": material.subject, "estimated_minutes": 5, "material_ids": [mid]}
        payload = visual_references.with_visual_context(db, child, {"labs_enabled": True, "selected_groups": [group]},
            [material], groups=[group])
        before = (db.query(LearningUnit).count(), db.query(Attempt).count(), db.query(Activity).count())
    calls = _transport(monkeypatch, provider, {"units": [{**output, "group_id": "g1"}]})
    result = providers.request_provider(_config(provider), "package", payload)
    PackageOutput.model_validate(result.data)
    assert len(calls) == 1 and result.data["units"][0]["questions"][0]["answer"] == output["questions"][0]["answer"]
    submitted, schema, instructions = _submitted(provider, calls[0])
    assert submitted["labs_enabled"] is True
    lab = object_with(schema, {"recipe_id", "recipe_version", "parameters"})
    assert lab["properties"]["recipe_id"]["enum"] == [recipe]
    assert "package-output-1" in instructions
    block = result.data["units"][0]["questions"][0]["presentation"]["blocks"][0]
    assert block["lab"]["recipe_id"] == recipe and block["lab"]["recipe_version"] == 1
    assert block["lab"]["parameters"] == output["questions"][0]["presentation"]["blocks"][0]["lab"]["parameters"]
    with DB() as db:
        visual_references.validate_output(db, result.data, payload)
        assert (db.query(LearningUnit).count(), db.query(Attempt).count(), db.query(Activity).count()) == before


@pytest.mark.parametrize("recipe", list(learning_labs.RECIPES))
def test_package_output_cannot_add_labs_to_request_without_saved_capability(monkeypatch, household, recipe):
    _, mid, _, output = make_unit(household, recipe)
    with DB() as db:
        child, material = db.get(Child, household[1]["id"]), db.get(Material, mid)
        group = {"id": "g1", "subject": material.subject, "estimated_minutes": 5, "material_ids": [mid]}
        payload = visual_references.with_visual_context(db, child, {"labs_enabled": False, "selected_groups": [group]},
            [material], groups=[group])
    calls = _transport(monkeypatch, "openrouter", {"units": [{**output, "group_id": "g1"}]})
    with pytest.raises(providers.ProviderError, match="angeforderten Ausgabeformat"):
        providers.request_provider(_config("openrouter"), "package", payload)
    assert len(calls) == 1
    _, schema, _ = _submitted("openrouter", calls[0])
    graphic = object_with(schema, {"kind", "disclosure", "labels", "numbers"})
    assert "lab" not in graphic["properties"]["kind"]["enum"]
