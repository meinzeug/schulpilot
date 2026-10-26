"""Artificial source-bound decomposition, no external provider or learner data."""
import copy
import json
from pathlib import Path

import httpx
import pytest
from schulpilot import learning_entry, notebook_fraction_compositions, providers, visual_references
from schulpilot import unit_fraction_compositions as compositions
from schulpilot.db import DB, Child, Material
from schulpilot.schemas import UnitOutput
from schulpilot.subject_registry import identity
from test_graphic_native_transport import subset_record
from test_presentation_capability_paths import _config

CONTENT = "Unechte Brüche in gemischte Zahlen umwandeln. Volle Ganze bündeln, den Rest als Bruch schreiben. Beispiel: 9/4 = 2 + 1/4. Weiteres Beispiel: 5/4 = 1 + 1/4. Drittes Beispiel: 7/3 = 2 + 1/3."


def prepared(household, count=2):
    with DB.begin() as db:
        child = db.get(Child, household[1]["id"])
        page = Material(child_id=child.id, title="Künstliche Regel", subject="Mathematik", subject_id=identity("mathematik"),
            topic="Unechte Brüche in gemischte Zahlen", content=CONTENT, confirmed=True, status="confirmed")
        db.add(page)
        db.flush()
        payload = {"grade": 6, "required_subject": "Mathematik", "material": {"subject": page.subject, "topic": page.topic, "content": page.content},
            "notebook_practice": {"version": 1, "question_count": count}}
        payload = visual_references.with_visual_context(db, child, payload, [page])
        payload = learning_entry.with_learning_entry(db, child, payload, [page], enabled=True)
        payload = visual_references.with_foundation_context(db, payload)
        payload = notebook_fraction_compositions.prepare(notebook_fraction_compositions.with_history(payload, []))
    schema = providers.strict_schema(UnitOutput, preserve_limits=True)
    visual_references.bind_schema(schema, payload)
    learning_entry.bind_entry_schema(schema, payload)
    binding = compositions.bind_schema(schema, payload)
    assert binding is not None
    intro = next(c for c in binding.candidates if c["disclosure"] == "given")

    def step(candidate, text=None):
        return {"id": candidate["id"], "text": text or candidate["text"], "competence_id": None,
            "disclosure": candidate["disclosure"], "reference": candidate["reference"], "source_refs": candidate["source_refs"],
            "presentation": {"version": 1, "evidence_kind": "knowledge", "blocks": [candidate["id"]]}}

    questions = []
    for core in [*payload[notebook_fraction_compositions.KEY]["probes"],
            *[task["question_core"] for task in payload[notebook_fraction_compositions.KEY]["tasks"]]]:
        candidate = next(c for c in binding.candidates if c.get("question_core", {}).get("id") == core["id"])
        question = copy.deepcopy(core)
        question.update(hints=["Bündele vollständige Ganze."], explanation="Vollständige Ganze und Rest.",
            explanation_steps=[step(candidate)])
        questions.append(question)
    wire = {"subject": "Mathematik", "topic": "Unechte Brüche in gemischte Zahlen", "explanation": "Volle Ganze bündeln, den Rest darstellen.",
        "explanation_steps": [step(intro)], "questions": questions}
    return payload, binding, wire


@pytest.mark.parametrize("count", [2, 5])
def test_count_entry_and_graphics_use_one_actual_http_mock(household, monkeypatch, count):
    payload, binding, wire = prepared(household, count)
    calls = []
    real = httpx.Client

    def handler(request):
        body = json.loads(request.content)
        calls.append(body)
        # The real request asks for IDs, never free graphic parameters.
        assert "unit-fraction-composition-1" in body["messages"][0]["content"]
        return httpx.Response(200, json={"choices": [{"message": {"content": json.dumps(wire)}, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": 100, "completion_tokens": 500, "cost": .001}})

    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real(transport=httpx.MockTransport(handler)))
    try:
        result = providers.request_provider(_config("openrouter"), "unit", payload)
    except providers.ProviderError as error:
        pytest.fail(str(error.billing_result.telemetry))
    assert len(calls) == 1 and len(result.data["questions"]) == count
    schema = calls[0]["response_format"]["json_schema"]["schema"]
    subset_record(schema)
    assert schema["properties"]["questions"]["minItems"] == schema["properties"]["questions"]["maxItems"] == count
    assert result.cost_source == "reported"
    main = next(q for q in result.data["questions"] if q["prompt"] == "Schreibe 9/4 als gemischte Zahl.")
    assert main["prompt"] == next(q["prompt"] for q in wire["questions"] if q["prompt"] == main["prompt"]) and main["answer"] == "2 1/4"
    assert [b["numbers"] for b in main["explanation_steps"][0]["presentation"]["blocks"]] == [[4, 4], [4, 4], [1, 4]]
    from schulpilot.provider_cost_preflight import projection
    config = _config("openrouter")
    config.max_output_tokens, config.reserve_micros = 8000, 250000
    config.input_per_million_micros, config.output_per_million_micros = 2000000, 10000000
    size = sum(len(value.encode()) for value in (calls[0]["messages"][0]["content"], calls[0]["messages"][1]["content"][0]["text"], json.dumps(schema)))
    estimated = projection(config, "unit", size, None, 0)
    metrics_path = Path("/tmp/schulpilot126-composition-wire-metrics.json")
    metrics = json.loads(metrics_path.read_text()) if metrics_path.exists() else {}
    metrics[str(count)] = {"text_bytes": size, "schema_bytes": len(json.dumps(schema).encode()),
        "projected_micros": estimated["projected_micros"], "output_cap": 8000, "reserve": 250000,
        "provider_calls": 0, "mock_http_requests": len(calls), "schema_limits": subset_record(schema)}
    metrics_path.write_text(json.dumps(metrics, sort_keys=True, indent=2))
    assert estimated["projected_micros"] <= 250000
    learning_entry.validate_entry_output(payload, result.data)
    with DB() as db:
        visual_references.validate_output(db, result.data, payload)


@pytest.mark.parametrize("mutation", ["remainder", "whole", "input", "source_revision", "source_digest", "version", "disclosure", "missing", "foreign_id", "question", "unrelated_fraction", "bool_version"])
def test_changed_or_unproven_compositions_fail_closed(household, mutation):
    payload, binding, wire = prepared(household)
    data = binding.hydrate(wire)
    step = data["questions"][-1]["explanation_steps"][0]
    context = copy.deepcopy(payload["visual_context"])
    if mutation == "remainder":
        step["presentation"]["blocks"][-1]["numbers"] = [2, 4]
    elif mutation == "whole":
        step["presentation"]["blocks"].pop(0)
    elif mutation == "input":
        step["text"] = "7/4 = 1 + 3/4."
    elif mutation == "source_revision":
        context["sources"][0]["revision"] += 1
    elif mutation == "source_digest":
        context["sources"][0]["content"] += " geänderte Quelle"
    elif mutation == "version":
        step["reference"]["version"] = 3
    elif mutation == "bool_version":
        step["reference"]["version"] = True
    elif mutation == "unrelated_fraction":
        data["questions"][-1]["prompt"] = "Stelle 9/4 und 5/4 als gemischte Zahlen dar."
    elif mutation == "disclosure":
        step["disclosure"] = "given"
    elif mutation == "missing":
        step["presentation"]["blocks"] = []
    elif mutation == "foreign_id":
        step["id"] = "uc_foreign"
    else:
        data["questions"][-1]["prompt"] = "Schreibe 5/4 als gemischte Zahl."
    with pytest.raises(ValueError):
        compositions.validate_step(step, compositions.compile_candidates(context), question=data["questions"][-1])


@pytest.mark.parametrize("literal,pairs", [("9/4", [[4, 4], [4, 4], [1, 4]]), ("5/4", [[4, 4], [1, 4]]), ("7/3", [[3, 3], [3, 3], [1, 3]])])
def test_generic_arithmetic_composition_without_hardcoded_example(household, literal, pairs):
    payload, _, _ = prepared(household)
    context = copy.deepcopy(payload["visual_context"])
    context["sources"][0]["content"] = "Unechte Brüche in gemischte Zahlen umwandeln. Beispiel: " + literal
    candidate = next(c for c in compositions.compile_candidates(context) if c["disclosure"] == "solution")
    assert [b["numbers"] for b in compositions._blocks(candidate)] == pairs


@pytest.mark.parametrize("content", ["Nur ein Bruch: 9/4", "Unechte Brüche in gemischte Zahlen. 17/4", "Unechte Brüche in gemischte Zahlen. -9/4"])
def test_no_method_or_unsupported_composition_stays_legacy_strict(household, content):
    payload, _, _ = prepared(household)
    context = copy.deepcopy(payload["visual_context"])
    context["sources"][0].update(content=content, topic="Brüche")
    assert compositions.compile_candidates(context) == []


def test_old_fraction_recipe_still_rejects_input_rest_mismatch(household):
    payload, binding, wire = prepared(household)
    data = binding.hydrate(wire)
    step = data["questions"][-1]["explanation_steps"][0]
    step.update(id="legacy", reference={"id": "math.fraction.part_whole", "version": 1}, text="9/4 = 2 + 1/4")
    for block in step["presentation"]["blocks"]:
        block["source_excerpt"] = "9/4 = 2 + 1/4"
    with DB() as db, pytest.raises(ValueError, match="verschiedene Brüche"):
        visual_references.validate_steps(db, [step], "Mathematik", payload["visual_context"], question=data["questions"][-1])


def test_composition_recipe_cannot_be_selected_as_global_unbound_asset(household):
    from fastapi import HTTPException
    from schulpilot.learning_assets import public_spec

    with DB() as db, pytest.raises(HTTPException) as caught:
        public_spec(db, {"subject": "Mathematik", "recipe_id": compositions.RECIPE, "recipe_version": 1,
            "level_band": "lower_secondary", "foundation_ids": ["math.fractions.meaning"]})
    assert caught.value.status_code == 422


def test_given_does_not_show_computed_answer_and_wrong_prose_is_rejected(household):
    payload, binding, wire = prepared(household)
    data = binding.hydrate(wire)
    intro = data["explanation_steps"][0]
    assert [b["numbers"] for b in intro["presentation"]["blocks"]] == [[4, 4]]
    assert "9/4" not in intro["text"] and "1/4" not in intro["text"] and "2 Ganze" not in intro["text"]
    step = data["questions"][-1]["explanation_steps"][0]
    step["text"] = "Bei 9/4 entstehen 3 Ganze und 1/4."
    with pytest.raises(ValueError):
        compositions.validate_step(step, compositions.compile_candidates(payload["visual_context"]), question=data["questions"][-1])


@pytest.mark.parametrize("changed", ["version", "foreign_id", "disclosure"])
def test_bad_mock_response_is_rejected_once_and_keeps_reported_billing(household, monkeypatch, changed):
    payload, _, wire = prepared(household)
    step = wire["questions"][-1]["explanation_steps"][0]
    if changed == "version":
        step["reference"]["version"] = 3
    elif changed == "foreign_id":
        step["presentation"]["blocks"] = ["uc_unrelated"]
    else:
        step["disclosure"] = "given"
    calls = []
    real = httpx.Client

    def handler(request):
        calls.append(request)
        return httpx.Response(200, json={"choices": [{"message": {"content": json.dumps(wire)}, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": 100, "completion_tokens": 500, "cost": .001}})

    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real(transport=httpx.MockTransport(handler)))
    with pytest.raises(providers.ProviderError) as caught:
        providers.request_provider(_config("openrouter"), "unit", payload)
    assert len(calls) == 1
    receipt = caught.value.billing_result
    assert receipt.cost_source == "reported" and receipt.cost_micros == 1000
