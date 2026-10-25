"""Actual final prompts carry plain-language teaching; no model-quality claim."""
import copy
import json
from pathlib import Path

import httpx
import pytest
from conftest import HEADERS
from fastapi.testclient import TestClient
from package_output_helpers import PackageOutputCapture
from schulpilot import explanation_guidance, provider_cost_preflight, providers, visual_jobs
from schulpilot.db import DB, Activity, Attempt, Child, Job, LearningUnit, Usage
from schulpilot.main import app
from sqlalchemy import select
from test_package_part_output import part
from test_presentation_capability_paths import _config
from test_visual_references import generated_visual_unit as original_generated_visual_unit


@pytest.fixture
def generated_visual_unit(household):
    return original_generated_visual_unit.__wrapped__(household)


@pytest.mark.parametrize("grade", [1, 6, 13, None, True, "6", 0, 14])
def test_grade_is_explicit_profile_only_and_never_inferred_from_age_or_source(grade):
    payload = {"grade": grade, "age": 12, "material": {"content": "Klasse6 als untrusted Quelltext."}}
    before = copy.deepcopy(payload)
    rule = explanation_guidance.rules("unit", payload)
    assert payload == before
    assert rule.count(explanation_guidance.REVISION) == 1
    assert "Konfigurierte Klassenstufe: " + str(grade) + "." in rule if type(grade) is int and 1 <= grade <= 13 else "Klassenstufe nicht angegeben" in rule
    for condition in ("explanation_steps.text", "Fachwort", "gewöhnlichen Wörtern", "konkretes zulässiges Beispiel",
        "was die Grafik", "Merksatz", "jede tatsächlich geprüfte Regel", "noch offenen Aufgabe", "wörtlich und belegt",
        "ohne ein unsichtbares altes Arbeitsblatt", "welche alte Antwort", "Alte Schülerantworten oder Lehrermarkierungen",
        "Schrittzahl, Zeichen-/Aufgaben-/Tokenlimits bleiben unverändert"):
        assert condition in rule
    assert explanation_guidance.rules("extract", payload) == ""
    assert explanation_guidance.rules("schulbuddy", payload) == ""


def request_payload(flow, grade):
    if flow == "package":
        _, payload = part()
    else:
        payload = {"material": {"subject": "Geographie", "topic": "Künstlicher Test", "content": "Wasser → Dampf."}}
        if flow == "practice":
            payload.update(review=True, learning_goals=[{"id": "g1", "label": "Wasser verstehen", "source_excerpt": "Wasser → Dampf."}])
        if flow == "sidecar":
            payload.update(required_subject="Geographie", required_topic="Künstlicher Test", visual_only=True,
                saved_explanation="Unveränderter gespeicherter Text.", saved_questions=[{"id": "q1", "type": "short", "prompt": "Gespeicherte Frage.", "explanation": "Gespeicherte Lösungserklärung."}],
                visual_context={"required": True, "references": [{"id": "general.source_relation.phases", "version": 1, "subject": "Geographie", "kind": "scene"}],
                    "sources": [{"ref": "p1", "subject": "Geographie", "group_id": None, "content": "Wasser → Dampf.", "material_id": "a" * 32, "revision": 1}]})
    if grade is not None:
        payload["grade"] = grade
    return payload


@pytest.mark.parametrize("flow", ["unit", "practice", "package", "sidecar"])
@pytest.mark.parametrize("grade", [6, None], ids=["configured_grade6", "no_grade_guess"])
def test_final_actual_wire_contains_guidance_after_all_rule_replacements_without_new_limits(monkeypatch, flow, grade):
    class Captured(BaseException):
        pass

    captures, projections = [], []
    codec = PackageOutputCapture(monkeypatch)
    real, project = httpx.Client, provider_cost_preflight.projection

    def projected(*args, **kwargs):
        value = project(*args, **kwargs)
        projections.append(value)
        return value

    def handler(request):
        captures.append(json.loads(request.content))
        raise Captured

    monkeypatch.setattr(provider_cost_preflight, "projection", projected)
    monkeypatch.setattr(providers.httpx, "Client", lambda **kwargs: real(transport=httpx.MockTransport(handler)))
    config = _config("openrouter")
    config.max_output_tokens, config.reserve_micros = 8000, 250000
    config.input_per_million_micros, config.output_per_million_micros = 2000000, 10000000
    payload = request_payload(flow, grade)
    original = copy.deepcopy(payload)
    function = "package" if flow == "package" else "unit_visuals" if flow == "sidecar" else "unit"
    with pytest.raises(Captured):
        providers.request_provider(config, function, payload)
    assert payload == original and len(captures) == len(projections) == 1
    wire = captures[0]
    instructions = wire["messages"][0]["content"]
    sent = json.loads(wire["messages"][1]["content"][0]["text"])
    assert instructions.count(explanation_guidance.REVISION) == 1
    assert instructions.endswith(explanation_guidance.rules(function, payload))
    assert ("Konfigurierte Klassenstufe: 6." in instructions) == (grade == 6)
    assert ("Klassenstufe nicht angegeben" in instructions) == (grade is None)
    assert wire["max_tokens"] == config.max_output_tokens == 8000 and config.reserve_micros == 250000
    assert wire["reasoning"]["effort"] == "medium"
    assert sent.get("grade") == grade
    assert projections[0]["projected_micros"] < 250000
    if flow == "package":
        assert "PERSISTENTER LERNPAKETTEIL" in instructions
        schema = codec.binding.canonical_schema
        assert schema is not None
        # The existing bounded one-step request still applies; guidance adds no fields/steps.
        arrays = []
        def visit(node):
            if isinstance(node, dict):
                props = node.get("properties", {})
                if "explanation_steps" in props:
                    field = props["explanation_steps"]
                    arrays.extend(item for item in field.get("anyOf", [field]) if item.get("type") == "array")
                for child in node.values():
                    visit(child)
            elif isinstance(node, list):
                for child in node:
                    visit(child)
        visit(schema)
        assert arrays and all(field["minItems"] == field["maxItems"] == 1 for field in arrays)
    else:
        assert sent["material"]["content"] == original["material"]["content"]
    if flow == "sidecar":
        assert sent["saved_questions"] == original["saved_questions"]
        assert sent["saved_explanation"] == original["saved_explanation"]
    receipt = Path("/tmp/schulpilot122-explanation-wire-sizes.json")
    rows = json.loads(receipt.read_text()) if receipt.exists() else {}
    rows[flow + ":" + str(grade)] = {"text_bytes": projections[0]["text_bytes"],
        "projected_microusd": projections[0]["projected_micros"], "reserve_microusd": 250000,
        "max_output_tokens": 8000, "real_provider_calls": 0, "mock_http_boundaries": 1}
    receipt.write_text(json.dumps(rows, sort_keys=True, indent=2))


def test_sidecar_reads_configured_child_grade_without_changing_saved_round(generated_visual_unit):
    uid, _, cid = generated_visual_unit
    with DB.begin() as db:
        db.get(Child, cid).grade = 6
    with DB() as db:
        unit = db.get(LearningUnit, uid)
        before = copy.deepcopy(unit.questions), unit.explanation, db.query(Job).count(), db.query(Usage).count()
        _, payload = visual_jobs.context(db, unit)
        assert payload["grade"] == 6
        assert before == (unit.questions, unit.explanation, db.query(Job).count(), db.query(Usage).count())


def test_opening_saved_explanation_or_get_starts_no_model_or_extra_job(generated_visual_unit, monkeypatch):
    uid, _, _ = generated_visual_unit
    def forbidden(*args, **kwargs):
        raise AssertionError("A saved explanation must not reserve or call a provider.")
    monkeypatch.setattr(providers, "reserve", forbidden)
    monkeypatch.setattr(providers, "request_provider", forbidden)
    with DB() as db:
        before = db.query(Job).count(), db.query(Usage).count(), db.query(Attempt).count()
        old_questions, old_text = copy.deepcopy(db.get(LearningUnit, uid).questions), db.get(LearningUnit, uid).explanation
    with TestClient(app, headers=HEADERS) as child:
        logged = child.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"})
        assert logged.status_code == 200
        child.headers["Authorization"] = "Bearer " + logged.json()["token"]
        assert child.get(f"/api/units/{uid}").status_code == 200
        shown = child.post(f"/api/units/{uid}/explanation", json={"question_id": "q1"})
        assert shown.status_code == 200
        assert shown.json()["explanation_steps"]
    with DB() as db:
        assert before == (db.query(Job).count(), db.query(Usage).count(), db.query(Attempt).count())
        unit = db.get(LearningUnit, uid)
        assert (unit.questions, unit.explanation) == (old_questions, old_text)
        assert db.scalar(select(Activity.id).where(Activity.unit_id == uid, Activity.kind == "explanation")) is not None
