"""Literal source text comparisons, never invented grammar verdicts or model calls."""

import copy
import json
from pathlib import Path

import pytest
from pydantic import ValidationError
from schulpilot import providers
from schulpilot.db import DB, Activity, Attempt, Job, LearningUnit, Material
from schulpilot.schemas import UnitOutput
from schulpilot.subject_content import PROFILES, generation_context, public_presentation, validate_output
from sqlalchemy import func, select
from test_coaching import normal_unit as _normal_unit

CASE = json.loads((Path(__file__).parents[2] / "testdata/text_probes_v1.json").read_text())["cases"][0]


def value():
    return {"subject": CASE["subject"], "topic": "Textgruppen", "explanation": CASE["source"], "questions": [copy.deepcopy(CASE["question"])]}


def validate(data, sources=None):
    checked = UnitOutput.model_validate(data).model_dump()
    validate_output(checked, {"materials": sources if sources is not None else [{"content": CASE["source"]}]})
    return checked


def test_literal_text_probe_validates_and_public_projection_matches_shared_fixture():
    data = validate(value())
    presentation = data["questions"][0]["presentation"]
    assert public_presentation(presentation)["blocks"] == []
    public = public_presentation(presentation, hints=1)
    assert public == CASE["public_presentation_hint1"]
    assert "source_excerpt" not in json.dumps(public)
    probe = public["blocks"][0]["text_probe"]
    assert all(set(variant) == {"id", "order"} for variant in probe["variants"])
    assert len(probe["segments"]) == 3


@pytest.mark.parametrize("fault", ["given", "version_bool", "version_unknown", "one_segment", "too_many_segments", "one_variant", "too_many_variants", "duplicate_segment", "duplicate_variant", "duplicate_order", "missing_segment", "foreign_segment", "repeat_segment", "invented_quote", "invented_order", "prefix_clip", "suffix_clip", "url", "markup", "code", "grammar_verdict", "foreign_graphic_payload"])
def test_text_probe_rejects_invalid_or_unattested_orders_without_new_semantics(fault):
    data = value()
    block = data["questions"][0]["presentation"]["blocks"][0]
    probe = block["text_probe"]
    sources = None
    if fault == "given":
        block["disclosure"] = "given"
    elif fault == "version_bool":
        probe["version"] = True
    elif fault == "version_unknown":
        probe["version"] = 2
    elif fault == "one_segment":
        probe["segments"] = probe["segments"][:1]
    elif fault == "too_many_segments":
        probe["segments"] += [{"id": f"other{i}", "text": "Wort"} for i in range(6)]
    elif fault == "one_variant":
        probe["variants"].pop()
    elif fault == "too_many_variants":
        probe["variants"] *= 3
    elif fault == "duplicate_segment":
        probe["segments"][1]["id"] = probe["segments"][0]["id"]
    elif fault == "duplicate_variant":
        probe["variants"][1]["id"] = probe["variants"][0]["id"]
    elif fault == "duplicate_order":
        probe["variants"][1]["order"] = probe["variants"][0]["order"]
    elif fault == "missing_segment":
        probe["variants"][0]["order"].pop()
    elif fault == "foreign_segment":
        probe["variants"][0]["order"][0] = "foreign"
    elif fault == "repeat_segment":
        probe["variants"][0]["order"][0] = "person"
    elif fault == "invented_quote":
        probe["variants"][0]["source_excerpt"] = "Unbelegtes Beispiel"
    elif fault == "invented_order":
        probe["variants"][0]["order"] = ["verb", "time", "person"]
    elif fault == "prefix_clip":
        sources = [{"content": CASE["source"].replace("heute lernt Mika;", "vorheute lernt Mika;")}]
        block["source_excerpt"] = sources[0]["content"]
    elif fault == "suffix_clip":
        sources = [{"content": CASE["source"].replace("heute lernt Mika;", "heute lernt Mikael;")}]
        block["source_excerpt"] = sources[0]["content"]
    elif fault in ("url", "markup", "code"):
        probe["segments"][0]["text"] = {"url": "https://example.invalid", "markup": "<script>x</script>", "code": "eval(x)"}[fault]
    elif fault == "grammar_verdict":
        probe["variants"][0]["correct"] = True
    else:
        block["kind"] = "forms"
    with pytest.raises((ValueError, ValidationError)):
        validate(data, sources)


def test_text_probe_cannot_join_material_boundaries_or_other_package_group():
    data = value()
    with pytest.raises(ValueError):
        validate(data, [{"content": "Textgruppen: heute, lernt, Mika. heute lernt"}, {"content": "Mika; Mika lernt heute."}])
    unit = {**data, "group_id": "own"}
    with pytest.raises(ValueError):
        validate_output({"units": [unit]}, {"materials": [{"group_id": "other", "content": CASE["source"]}]})


def test_text_probe_source_accepts_literal_whitespace_without_case_or_grammar_inference():
    data = value()
    source = CASE["source"].replace("heute lernt Mika", "heute\nlernt   Mika")
    validate(data, [{"content": source}])


def test_final_schema_and_real_profiles_advertise_only_local_source_bound_controls():
    schema = providers.strict_schema(UnitOutput, preserve_limits=True)
    from schulpilot.subject_content import bind_graphic_schema

    bind_graphic_schema(schema, ["Deutsch"])
    context = generation_context(["Deutsch"], schema=schema)
    assert "text_probe" in context["graphic_kinds"]
    assert context["text_probe"]["variants_max"] == 4
    assert all("text_probe" in profile for profile in PROFILES.values())
    assert "Bewertung" in context["local_interactions"]["text_probe"]


def test_text_probe_opens_only_saved_help_without_attempt_or_new_job(api, household):
    for client, unit_id, material_id, *_ in _normal_unit.__wrapped__(api, household):
        with DB.begin() as db:
            unit = db.get(LearningUnit, unit_id)
            unit.subject = CASE["subject"]
            unit.questions = [copy.deepcopy(CASE["question"]), unit.questions[1]]
            material = db.get(Material, material_id)
            material.subject, material.content = CASE["subject"], CASE["source"]
        client.headers["X-Schulpilot-Capabilities"] = "visual-v1"
        assert client.post(f"/api/units/{unit_id}/start").status_code == 200
        before = client.get(f"/api/units/{unit_id}").json()
        assert before["questions"][0]["presentation"]["blocks"] == []
        response = client.post(f"/api/units/{unit_id}/questions/text/hint")
        assert response.status_code == 200, response.text
        assert "source_excerpt" not in json.dumps(response.json())
        opened = client.get(f"/api/units/{unit_id}").json()
        assert opened["questions"][0]["presentation"]["blocks"][0]["kind"] == "text_probe"
        assert "source_excerpt" not in json.dumps(opened)
        with DB() as db:
            assert db.scalar(select(func.count()).select_from(Attempt)) == 0
            assert db.scalar(select(func.count()).select_from(Job)) == 0
            assert db.scalar(select(func.count()).select_from(Activity).where(Activity.kind == "hint")) == 1
            assert db.get(LearningUnit, unit_id).active_seconds == 0


@pytest.mark.parametrize("field", ["title", "labels"])
def test_model_prompt_cannot_authorize_its_own_grammar_verdict(field):
    data = value()
    data["questions"][0]["prompt"] += " Grammatisch falsch."
    block = data["questions"][0]["presentation"]["blocks"][0]
    block[field] = "Grammatisch falsch" if field == "title" else ["Grammatisch falsch"]
    with pytest.raises(ValueError, match="Originalbeleg"):
        validate(data)
