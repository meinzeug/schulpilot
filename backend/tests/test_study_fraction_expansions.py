"""Artificial StudyPath expansion proofs; no external model or learner data."""
import copy
import json
from pathlib import Path

import httpx
import pytest
from schulpilot import providers, schemas, subject_content, visual_references
from schulpilot import study_fraction_expansions as expansion
from schulpilot.db import DB, Child, LearningUnit, Material
from schulpilot.graphic_schema import bind_coherent_graphics
from schulpilot.math_tasks import _task, fraction_tasks
from schulpilot.visual_reference_models import UnitVisualSnapshot
from test_graphic_native_transport import subset_record
from test_presentation_capability_paths import _config

CONTENT = "Beim Erweitern multiplizierst du Zähler und Nenner mit derselben Zahl. Originalbrüche: 1/5 und 2/7."


def prepared(household, phase="apply", count=2):
    with DB.begin() as db:
        child = db.get(Child, household[1]["id"])
        page = Material(child_id=child.id, title="Künstliche Erweiterungsregel", subject="Mathematik",
            topic="Brüche erweitern", content=CONTENT, confirmed=True, status="confirmed")
        db.add(page)
        db.flush()
        payload = {"grade": 6, "required_subject": "Mathematik", "required_topic": page.topic,
            "material": {"subject": page.subject, "topic": page.topic, "content": CONTENT},
            "study_block": {"mode": phase, "question_count": count, "tasks": []}, "previous_prompts": []}
        payload = visual_references.with_visual_context(db, child, payload, [page])
    tasks = fraction_tasks([payload["material"]], "Mathematik", page.topic, [], phase, count,
        json.dumps([phase, page.topic, []], ensure_ascii=False), expansion_denominator_limit=24)
    planned = {**payload, "math_tasks": tasks}
    schema = providers.strict_schema(schemas.UnitOutput, preserve_limits=True)
    subject_content.bind_graphic_schema(schema, ["Mathematik"])
    bind_coherent_graphics(schema)
    providers.indexed_choice_schema(schema, bounded_matches=True)
    providers.bind_math_tasks(schema, tasks)
    visual_references.bind_schema(schema, planned)
    binding = expansion.bind_schema(schema, planned)
    assert binding is not None

    def step(candidate):
        return {"id": candidate["id"], "text": candidate["text"], "competence_id": None,
            "disclosure": candidate["disclosure"], "reference": copy.deepcopy(candidate["reference"]),
            "source_refs": copy.deepcopy(candidate["source_refs"]), "presentation": {
                "version": 1, "evidence_kind": "knowledge", "blocks": [candidate["id"]]}}

    intro = next(c for c in binding.candidates if c["disclosure"] == "given")
    questions = []
    for task in tasks:
        candidate = next(c for c in binding.candidates if c.get("proof", {}).get("task", {}).get("id") == task["id"])
        question = {key: copy.deepcopy(task[key]) for key in expansion.CORE}
        question.update(hints=["Zähler und Nenner werden mit demselben Faktor multipliziert."],
            explanation="Die Menge bleibt gleich; die Einteilung wird feiner.", explanation_steps=[step(candidate)],
            presentation=None, field_group=None)
        questions.append(question)
    wire = {"subject": "Mathematik", "topic": page.topic,
        "explanation": "Beim Erweitern teilen wir die Stücke feiner ein. Die Menge bleibt gleich.",
        "explanation_steps": [step(intro)], "questions": questions}
    return page.id, payload, planned, schema, binding, wire


@pytest.mark.parametrize("phase,count", [("apply", 2), ("detective", 2), ("apply", 5)])
def test_actual_native_request_and_saved_snapshot_keep_exact_tasks_sources_and_disclosure(household, monkeypatch, phase, count):
    page_id, payload, planned, _, binding, wire = prepared(household, phase, count)
    calls, projections = [], []
    real = httpx.Client
    from schulpilot import provider_cost_preflight

    original = provider_cost_preflight.projection

    def measure(config, function, text_bytes, image_bytes, encoded_image_bytes):
        result = original(config, function, text_bytes, image_bytes, encoded_image_bytes)
        projections.append(copy.deepcopy(result))
        return result

    def handler(request):
        calls.append(json.loads(request.content))
        return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {"content": json.dumps(wire)}}],
            "usage": {"prompt_tokens": 100, "completion_tokens": 500, "cost": .001}})

    monkeypatch.setattr(provider_cost_preflight, "projection", measure)
    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real(transport=httpx.MockTransport(handler)))
    config = _config("openrouter")
    config.max_output_tokens, config.reserve_micros = 8000, 250000
    config.input_per_million_micros, config.output_per_million_micros = 2000000, 10000000
    result = providers.request_provider(config, "unit", payload)
    assert len(calls) == len(projections) == 1
    assert result.cost_source == "reported" and result.cost_micros == 1000
    assert projections[0]["projected_micros"] <= 250000
    sent = calls[0]["response_format"]["json_schema"]["schema"]
    limits = subset_record(sent)
    assert expansion.REVISION in calls[0]["messages"][0]["content"]
    assert sent["properties"]["questions"]["minItems"] == sent["properties"]["questions"]["maxItems"] == count
    assert [{key: q[key] for key in expansion.CORE} for q in result.data["questions"]] == [
        {key: q[key] for key in expansion.CORE} for q in planned["math_tasks"]]
    for question in result.data["questions"]:
        candidate = next(c for c in binding.candidates if binding.question_bound(c, question))
        assert [block["numbers"] for block in question["explanation_steps"][0]["presentation"]["blocks"]] == [
            candidate["proof"]["input"], candidate["proof"]["output"]]
        assert question["explanation_steps"][0]["disclosure"] == "solution"
    with DB.begin() as db:
        visual_references.validate_output(db, result.data, payload)
        unit = LearningUnit(child_id=household[1]["id"], material_id=page_id, subject="Mathematik", topic=payload["required_topic"],
            explanation=result.data["explanation"], questions=result.data["questions"], provider="synthetic", model="own-fixture")
        db.add(unit)
        db.flush()
        visual_references.remember(db, unit, result.data, payload)
        db.flush()
        snapshot = db.get(UnitVisualSnapshot, unit.id)
        assert snapshot.status == "ready"
        assert all(not visual_references.public_steps(steps) for steps in snapshot.question_steps.values())
        assert all(len(visual_references.public_steps(steps, closed=True)) == 1 for steps in snapshot.question_steps.values())
        before = copy.deepcopy(snapshot.question_steps)
        assert visual_references.projection(db, unit)["explanation_visual_status"] == "ready"
        assert snapshot.question_steps == before
    Path("/tmp/schulpilot128-expansion-wire-" + phase + "-" + str(count) + ".json").write_text(json.dumps({
        "text_bytes": projections[0]["text_bytes"], "schema_bytes": len(json.dumps(sent).encode()),
        "projected_micros": projections[0]["projected_micros"], "reserve": 250000,
        "output_cap": 8000, "schema_limits": limits, "mock_http_requests": 1, "vendor_calls": 0}, indent=2))


@pytest.mark.parametrize("fault", ["task_id", "prompt", "answer", "goal", "ref", "version", "source", "disclosure", "step_id", "intro_step_id", "text", "foreign_id"])
def test_mismatched_wire_cannot_change_the_proof_or_task(household, fault):
    _, _, _, _, binding, wire = prepared(household)
    data = copy.deepcopy(wire)
    question = data["questions"][0]
    step = question["explanation_steps"][0]
    if fault == "task_id":
        question["id"] = "foreign"
    elif fault == "prompt":
        question["prompt"] += " Zusätzliche Aufgabe."
    elif fault == "answer":
        question["answer"] = "1/2"
    elif fault == "goal":
        question["learning_goal_id"] = "g1"
    elif fault == "ref":
        step["reference"]["id"] = "math.fraction.part_whole"
    elif fault == "version":
        step["reference"]["version"] = 2
    elif fault == "source":
        step["source_refs"] = ["p2"]
    elif fault == "disclosure":
        step["disclosure"] = "given"
    elif fault == "step_id":
        step["id"] = "unbound"
    elif fault == "intro_step_id":
        data["explanation_steps"][0]["id"] = "unbound"
    elif fault == "text":
        step["text"] += " Andere Zahlen."
    else:
        step["presentation"]["blocks"] = ["fx_foreign"]
    with pytest.raises(ValueError):
        binding.hydrate(data)


@pytest.mark.parametrize("fault", ["pair", "factor", "order", "extra_block", "source_revision", "source_text", "ref_digest", "wrong_question", "given"])
def test_canonical_proof_validation_is_not_a_generic_evidence_bypass(household, fault):
    _, _, planned, _, binding, wire = prepared(household)
    data = binding.hydrate(wire)
    context = copy.deepcopy(planned["visual_context"])
    question = data["questions"][0]
    step = question["explanation_steps"][0]
    if fault == "pair":
        step["presentation"]["blocks"][1]["numbers"] = [1, 2]
    elif fault == "factor":
        step["text"] = step["text"].replace("Faktor", "Teiler")
    elif fault == "order":
        step["presentation"]["blocks"].reverse()
    elif fault == "extra_block":
        step["presentation"]["blocks"].append(copy.deepcopy(step["presentation"]["blocks"][0]))
    elif fault == "source_revision":
        context["sources"][0]["revision"] += 1
    elif fault == "source_text":
        context["sources"][0]["content"] += " Änderung."
    elif fault == "ref_digest":
        next(r for r in context["references"] if r["id"] == expansion.RECIPE)["digest"] = "0" * 64
    elif fault == "wrong_question":
        question["prompt"] = "Addiere 1/3 und 1/4."
    else:
        step["disclosure"] = "given"
        for block in step["presentation"]["blocks"]:
            block["disclosure"] = "given"
    with DB() as db, pytest.raises(ValueError):
        visual_references.validate_steps(db, [step], "Mathematik", context, question=question)


@pytest.mark.parametrize("fault", ["understand", "recall", "review", "homework", "exam", "other_subject"])
def test_other_contracts_keep_their_unchanged_schema(household, fault):
    _, _, planned, schema, _, _ = prepared(household)
    if fault in ("understand", "recall"):
        planned["study_block"]["mode"] = fault
    elif fault == "review":
        planned["review"] = True
    elif fault == "homework":
        planned["homework_practice"] = True
    elif fault == "exam":
        planned["exam_preparation"] = True
    else:
        planned["required_subject"] = "Deutsch"
    before = copy.deepcopy(schema)
    assert expansion.bind_schema(schema, planned) is None
    assert schema == before and expansion.planning_limit(planned) is None


def test_oversized_existing_plan_is_refused_before_any_request_with_cancelled_billing(household, monkeypatch):
    _, payload, _, _, _, _ = prepared(household)
    prompt, answer = _task("expand", (8, 9, 4), "apply")
    task = {"id": "q1", "type": "short", "prompt": prompt, "answer": answer, "options": [], "accepted": [],
        "source_excerpt": "Beim Erweitern multiplizierst du Zähler und Nenner mit derselben Zahl."}
    from schulpilot import math_tasks

    monkeypatch.setattr(math_tasks, "fraction_tasks", lambda *a, **kw: [copy.deepcopy(task), {**copy.deepcopy(task), "id": "q2"}])
    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: pytest.fail("No HTTP is allowed for an unrepresentable preflight"))
    with pytest.raises(providers.ProviderError) as error:
        providers.request_provider(_config("openrouter"), "unit", payload)
    assert str(error.value) == expansion.UNREPRESENTABLE
    assert error.value.billing_result.cost_source == "cancelled" and error.value.billing_result.cost_micros == 0
    assert error.value.billing_result.telemetry["pre_dispatch"] is True


def test_finite_early_selection_is_fresh_renderable_and_exhaustion_never_repeats():
    materials = [{"content": CONTENT}]
    previous = []
    for index in range(5):
        tasks = fraction_tasks(materials, "Mathematik", "Brüche erweitern", previous, "detective", 2,
            str(index), expansion_denominator_limit=24)
        assert all(int(task["answer"].split("/")[1]) <= 24 for task in tasks)
        assert not set(task["prompt"] for task in tasks) & set(previous)
        previous.extend(task["prompt"] for task in tasks)
    with pytest.raises(providers.ProviderError, match="keine neuen kleinen"):
        fraction_tasks(materials, "Mathematik", "Brüche erweitern", previous, "detective", 2,
            "exhausted", expansion_denominator_limit=1)


def test_new_proof_reference_is_never_a_general_or_shared_asset_candidate(household):
    _, payload, _, _, _, _ = prepared(household)
    from schulpilot import learning_assets

    with DB() as db:
        assert not any(r["id"] == expansion.RECIPE for r in visual_references.candidates(db, "Mathematik", CONTENT))
        catalogue = learning_assets.catalogue(db=db, page=1)
        assert not any(r["id"] == expansion.RECIPE for r in catalogue["recipes"])
    assert any(r["id"] == expansion.RECIPE for r in payload["visual_context"]["references"])


@pytest.mark.parametrize("fault", ["task", "answer", "source", "ref", "disclosure", "goal"])
def test_actual_adapter_rejection_keeps_one_request_and_known_mock_cost(household, monkeypatch, fault):
    _, payload, _, _, _, wire = prepared(household)
    question = wire["questions"][0]
    step = question["explanation_steps"][0]
    if fault == "task":
        question["id"] = "foreign"
    elif fault == "answer":
        question["answer"] = "1/2"
    elif fault == "source":
        step["source_refs"] = ["p2"]
    elif fault == "ref":
        step["reference"]["version"] = 2
    elif fault == "disclosure":
        step["disclosure"] = "given"
    else:
        question["learning_goal_id"] = "g1"
    calls = []
    real = httpx.Client

    def handler(request):
        calls.append(request)
        return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {"content": json.dumps(wire)}}],
            "usage": {"prompt_tokens": 100, "completion_tokens": 500, "cost": .001}})

    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real(transport=httpx.MockTransport(handler)))
    with pytest.raises(providers.ProviderError) as error:
        providers.request_provider(_config("openrouter"), "unit", payload)
    assert len(calls) == 1
    assert error.value.billing_result.cost_source == "reported" and error.value.billing_result.cost_micros == 1000


def test_legacy_planner_defaults_and_nonexpansion_task_are_not_rebound(household):
    args = ([{"content": CONTENT}], "Mathematik", "Brüche erweitern", [], "apply", 2, "legacy")
    assert fraction_tasks(*args) == fraction_tasks(*args, expansion_denominator_limit=None)
    _, _, planned, schema, _, _ = prepared(household)
    planned["math_tasks"] = [{"id": "q1", "type": "short", "prompt": "Addiere 1/4 und 1/4.",
        "answer": "2/4", "options": [], "accepted": []}]
    before = copy.deepcopy(schema)
    assert expansion.bind_schema(schema, planned) is None
    assert schema == before


def test_exhausted_local_planning_is_cancelled_before_transport(household, monkeypatch):
    _, payload, _, _, _, _ = prepared(household)
    from schulpilot import math_tasks

    monkeypatch.setattr(math_tasks, "_numbers", lambda operation: iter(()))
    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: pytest.fail("No exhausted-plan request is allowed"))
    with pytest.raises(providers.ProviderError, match="keine neuen kleinen") as error:
        providers.request_provider(_config("openrouter"), "unit", payload)
    assert error.value.billing_result.cost_source == "cancelled" and error.value.billing_result.cost_micros == 0
