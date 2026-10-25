"""Real notebook request/entry/proof contracts with artificial sources only."""
import copy
import json
from pathlib import Path

import httpx
import pytest
from schulpilot import learning_entry, providers, schemas, subject_content, visual_references, worker
from schulpilot import notebook_fraction_expansions as notebook_expansion
from schulpilot import study_fraction_expansions as expansion
from schulpilot.db import DB, Child, Job, LearningUnit, Material, UnitSource, Usage, now
from schulpilot.graphic_schema import bind_coherent_graphics
from schulpilot.math_tasks import _numbers, _task
from schulpilot.subject_registry import identity
from schulpilot.visual_reference_models import UnitVisualSnapshot
from sqlalchemy import select
from test_graphic_native_transport import subset_record
from test_learning_entry import dated_expansion_attempt
from test_notebook_practice import notebook as notebook
from test_notebook_practice import post
from test_presentation_capability_paths import _config

CONTENT = "Beim Erweitern multiplizierst du Zähler und Nenner mit derselben Zahl. Originalbeispiele: 1/5 und 2/7."


def binding_and_wire(payload, *, indexed=True):
    planned = notebook_expansion.prepare(payload)
    schema = providers.strict_schema(schemas.UnitOutput, preserve_limits=True)
    subject_content.bind_graphic_schema(schema, ["Mathematik"])
    bind_coherent_graphics(schema)
    if indexed:
        providers.indexed_choice_schema(schema, bounded_matches=True)
    visual_references.bind_schema(schema, planned)
    learning_entry.bind_entry_schema(schema, planned)
    binding = notebook_expansion.bind_schema(schema, planned)
    assert binding is not None

    def step(candidate):
        return {"id": candidate["id"], "text": candidate["text"], "competence_id": None,
            "disclosure": candidate["disclosure"], "reference": copy.deepcopy(candidate["reference"]),
            "source_refs": copy.deepcopy(candidate["source_refs"]),
            "presentation": {"version": 1, "evidence_kind": "knowledge", "blocks": [candidate["id"]]}}

    plan = planned[notebook_expansion.KEY]
    questions = []
    for core in [*plan["probes"], *plan["tasks"]]:
        candidate = next(c for c in binding.candidates if (c.get("question_core") or c.get("proof", {}).get("task", {})).get("id") == core["id"])
        question = {key: copy.deepcopy(core[key]) for key in notebook_expansion.CORE}
        question.update(hints=["Zähler und Nenner gemeinsam betrachten."], explanation="Die Menge bleibt gleich; die Einteilung wird feiner.",
            explanation_steps=[step(candidate)], presentation=None, field_group=None)
        questions.append(question)
    intro = next(c for c in binding.candidates if c["disclosure"] == "given")
    wire = {"subject": "Mathematik", "topic": "Brüche erweitern", "explanation": "Wir teilen gleich große Stücke feiner ein. Die Menge bleibt gleich.",
        "explanation_steps": [step(intro)], "questions": questions}
    return planned, binding, wire


def prepared(household, count=2, entry=True):
    with DB.begin() as db:
        child = db.get(Child, household[1]["id"])
        page = Material(child_id=child.id, subject="Mathematik", subject_id=identity("mathematik"), topic="Brüche erweitern",
            title="Künstliche Erweiterungsseite", content=CONTENT, confirmed=True, status="confirmed")
        db.add(page)
        db.flush()
        previous = []
        if entry == "known":
            for index, days in enumerate((8, 4, 1)):
                attempt = dated_expansion_attempt(db, child.id, page.id, index, int(now()) - days * 86400)
                previous.extend(question["prompt"] for question in db.get(LearningUnit, attempt.unit_id).questions)
        payload = {"grade": 6, "required_subject": "Mathematik", "notebook_practice": {"version": 1, "question_count": count},
            "material": {"subject": page.subject, "topic": page.topic, "content": page.content}, "previous_prompts": previous}
        payload = visual_references.with_visual_context(db, child, payload, [page])
        payload = learning_entry.with_learning_entry(db, child, payload, [page], enabled=entry)
        payload = visual_references.with_foundation_context(db, payload)
        payload = notebook_expansion.with_history(payload, payload["previous_prompts"])
        page_id = page.id
    return page_id, payload, *binding_and_wire(payload)


def http_mock(monkeypatch, wire, calls):
    real = httpx.Client

    def handler(request):
        calls.append(json.loads(request.content))
        return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {"content": json.dumps(wire)}}],
            "usage": {"prompt_tokens": 100, "completion_tokens": 500, "cost": .001}})

    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real(transport=httpx.MockTransport(handler)))


@pytest.mark.parametrize("count,entry", [(2, True), (5, True), (2, False), (5, False), (2, "known"), (5, "known")])
def test_actual_http_count_entry_probe_and_saved_snapshot_keep_both_exact_contracts(household, monkeypatch, count, entry):
    page_id, payload, planned, binding, wire = prepared(household, count, entry)
    calls, costs = [], []
    from schulpilot import provider_cost_preflight

    real_projection = provider_cost_preflight.projection

    def measure(config, function, text_bytes, image_bytes, encoded_image_bytes):
        value = real_projection(config, function, text_bytes, image_bytes, encoded_image_bytes)
        costs.append(value)
        return value

    monkeypatch.setattr(provider_cost_preflight, "projection", measure)
    http_mock(monkeypatch, wire, calls)
    config = _config("openrouter")
    config.max_output_tokens, config.reserve_micros = 8000, 250000
    config.input_per_million_micros, config.output_per_million_micros = 2000000, 10000000
    result = providers.request_provider(config, "unit", payload)
    assert len(calls) == len(costs) == 1 and result.cost_micros == 1000
    assert costs[0]["projected_micros"] <= 250000
    plan = planned[notebook_expansion.KEY]
    assert len(plan["probes"]) == (min(3, count - 1) if entry is True else 0)
    if entry == "known":
        assert planned["learning_entry"]["units"][0]["entry_mode"] == "reuse_evidence"
    assert len(plan["tasks"]) + len(plan["probes"]) == len(result.data["questions"]) == count
    by_id = {question["id"]: question for question in result.data["questions"]}
    for core in [*plan["probes"], *plan["tasks"]]:
        assert all(by_id[core["id"]][key] == core[key] for key in notebook_expansion.CORE)
    probe_examples = [probe["visual_example"] for unit in (planned.get("learning_entry") or {}).get("units", [])
        for probe in unit.get("probes", [])]
    for intro in [candidate for candidate in binding.candidates if candidate["disclosure"] == "given"]:
        assert intro["block"]["numbers"] not in [[example["numerator"], example["denominator"]] for example in probe_examples]
    for task in plan["tasks"]:
        candidate = next(c for c in binding.candidates if c.get("proof", {}).get("task", {}).get("id") == task["id"])
        assert [b["numbers"] for b in by_id[task["id"]]["explanation_steps"][0]["presentation"]["blocks"]] == [candidate["proof"]["input"], candidate["proof"]["output"]]
        assert by_id[task["id"]]["explanation_steps"][0]["source_refs"] == candidate["source_refs"]
    sent = calls[0]["response_format"]["json_schema"]["schema"]
    limits = subset_record(sent)
    assert sent["properties"]["questions"]["minItems"] == sent["properties"]["questions"]["maxItems"] == count
    assert notebook_expansion.REVISION in calls[0]["messages"][0]["content"]
    with DB.begin() as db:
        visual_references.validate_output(db, result.data, payload)
        unit = LearningUnit(child_id=household[1]["id"], material_id=page_id, subject="Mathematik", topic=result.data["topic"],
            explanation=result.data["explanation"], questions=result.data["questions"], provider="synthetic", model="own-fixture")
        db.add(unit)
        db.flush()
        visual_references.remember(db, unit, result.data, payload)
        db.flush()
        snapshot = db.get(UnitVisualSnapshot, unit.id)
        before = copy.deepcopy(snapshot.question_steps)
        assert snapshot.status == "ready" and visual_references.projection(db, unit)["explanation_visual_status"] == "ready"
        assert snapshot.question_steps == before
        assert all(not visual_references.public_steps(steps) for steps in before.values())
        assert all(len(visual_references.public_steps(steps, closed=True)) == 1 for steps in before.values())
    Path(f"/tmp/schulpilot129-notebook-expansion-wire-{count}-{entry}.json").write_text(json.dumps({
        "text_bytes": costs[0]["text_bytes"], "schema_bytes": len(json.dumps(sent).encode()),
        "projected_micros": costs[0]["projected_micros"], "reserve": 250000, "output_cap": 8000,
        "schema_limits": limits, "http_mocks": 1, "vendor_calls": 0}, indent=2))


@pytest.mark.parametrize("fault", ["probe_core", "task_core", "task_id", "source", "reference", "version", "stage", "foreign_id", "intro_id"])
def test_actual_http_rejects_wrong_probe_task_source_reference_or_disclosure_once(household, monkeypatch, fault):
    _, payload, planned, _, wire = prepared(household)
    question = wire["questions"][0 if fault == "probe_core" else -1]
    step = question["explanation_steps"][0]
    if fault in ("probe_core", "task_core"):
        question["answer"] = "99/99"
    elif fault == "task_id":
        question["id"] = planned[notebook_expansion.KEY]["probes"][0]["id"]
    elif fault == "source":
        step["source_refs"] = ["p999"]
    elif fault == "reference":
        step["reference"]["id"] = "math.fraction.part_whole"
    elif fault == "version":
        step["reference"]["version"] += 1
    elif fault == "stage":
        step["disclosure"] = "given"
    elif fault == "intro_id":
        wire["explanation_steps"][0]["id"] = "unbound"
    else:
        step["presentation"]["blocks"] = ["not-a-request-candidate"]
    calls = []
    http_mock(monkeypatch, wire, calls)
    with pytest.raises(providers.ProviderError) as error:
        providers.request_provider(_config("openrouter"), "unit", payload)
    assert len(calls) == 1 and error.value.billing_result.cost_source == "reported"
    assert error.value.billing_result.cost_micros == 1000


def test_exhausted_finite_expansion_pool_stops_before_http_without_partial_round(household, monkeypatch):
    _, payload, _, _, wire = prepared(household, 2, False)
    payload["previous_prompts"] = [_task("expand", numbers, "apply")[0] for numbers in _numbers("expand") if numbers[1] * numbers[2] <= 24]
    before = copy.deepcopy(payload)
    calls = []
    http_mock(monkeypatch, wire, calls)
    with pytest.raises(providers.ProviderError) as error:
        providers.request_provider(_config("openrouter"), "unit", payload)
    assert calls == [] and payload == before
    assert error.value.args == (notebook_expansion.EXHAUSTED,)
    assert error.value.billing_result.cost_source == "cancelled" and error.value.billing_result.cost_micros == 0


@pytest.mark.parametrize("fault", ["plan_core", "source_revision", "reference_digest", "probe_core"])
def test_stale_request_plan_is_refused_before_http(household, monkeypatch, fault):
    _, _, planned, _, wire = prepared(household)
    if fault == "plan_core":
        planned[notebook_expansion.KEY]["tasks"][0]["answer"] = "1/2"
    elif fault == "source_revision":
        next(source for source in planned["visual_context"]["sources"] if source.get("material_id"))["revision"] += 1
    elif fault == "reference_digest":
        next(ref for ref in planned["visual_context"]["references"] if ref["id"] == expansion.RECIPE)["digest"] = "0" * 64
    else:
        planned["learning_entry"]["units"][0]["probes"][0]["answer"] = "99"
    calls = []
    http_mock(monkeypatch, wire, calls)
    with pytest.raises(providers.ProviderError) as error:
        providers.request_provider(_config("openrouter"), "unit", planned)
    assert calls == [] and error.value.billing_result.cost_source == "cancelled"


def test_normal_notebook_api_worker_selects_only_current_page_and_keeps_unconfirmed_elsewhere_ignored(notebook, monkeypatch):
    with DB.begin() as db:
        first = db.get(Material, notebook.refs[0]["id"])
        first.content, first.topic = CONTENT, "Brüche erweitern"
        db.get(Material, notebook.refs[1]["id"]).confirmed = False
        db.get(Material, notebook.refs[2]["id"]).confirmed = False
    _config("openrouter")  # The following local HTTP envelope is the native chat adapter.
    value = {"material_id": notebook.refs[0]["id"], "notebook_sources": notebook.refs[:1], "question_count": 2}
    notebook.client.headers["X-Schulpilot-Capabilities"] = "learning-entry-v1"
    response = post(notebook, value)
    assert response.status_code == 202, response.text
    job_id = response.json()["id"]
    assert post(notebook, value).json()["id"] == job_id
    calls = []
    real_provider = providers.request_provider

    def request(config, function, payload, *args, **kwargs):
        assert function == "unit" and payload["notebook_practice"] == {"version": 1, "question_count": 2}
        assert {source["material_id"] for source in payload["visual_context"]["sources"] if source.get("material_id")} == {notebook.refs[0]["id"]}
        _, _, wire = binding_and_wire(payload, indexed=False)
        http_mock(monkeypatch, wire, calls)
        return real_provider(config, function, payload, *args, **kwargs)

    monkeypatch.setattr(worker, "request_provider", request)
    with DB() as db:
        assert worker.claim(db) == job_id
    worker.process(job_id)
    with DB() as db:
        job = db.get(Job, job_id)
        assert job.status == "completed", job.error
        unit = db.get(LearningUnit, job.result["unit_id"])
        assert len(unit.questions) == 2 and len(calls) == 1
        assert set(db.scalars(select(UnitSource.material_id).where(UnitSource.unit_id == unit.id))) == {notebook.refs[0]["id"]}
        assert db.scalar(select(Usage).where(Usage.job_id == job_id)).cost_micros == 1000
        assert db.get(UnitVisualSnapshot, unit.id).status == "ready"
        assert db.get(Material, notebook.refs[1]["id"]).confirmed is False
    worker.process(job_id)
    assert len(calls) == 1


def test_optional_intro_pair_exclusion_retains_legacy_default_and_selects_other_original(household):
    _, _, planned, _, _ = prepared(household, 2, False)
    context = planned["visual_context"]
    tasks = [expansion._candidate(context, task, "apply") for task in planned[notebook_expansion.KEY]["tasks"]]
    original = expansion._introductions(context, tasks)
    assert original == expansion._introductions(context, tasks, excluded_pairs=[])
    assert [intro["block"]["numbers"] for intro in original] == [[1, 5], [2, 7]]
    kept = expansion._introductions(context, tasks, excluded_pairs=[[1, 5]])
    assert [intro["block"]["numbers"] for intro in kept] == [[2, 7]]
    assert kept[0] == original[1]  # Text/ID/source digest of retained originals unchanged.
    assert expansion._introductions(context, tasks, excluded_pairs=[[1, 5], [2, 7]]) == []


@pytest.mark.parametrize("required", [False, None])
def test_legacy_nonrequired_graphics_do_not_get_new_notebook_plan_or_schema(household, required):
    _, payload, _, _, _ = prepared(household, 2, False)
    payload["visual_context"]["required"] = required
    payload.pop(notebook_expansion.HISTORY_KEY)  # Legacy non-graphic workers never create private proof exclusions.
    before = copy.deepcopy(payload)
    assert notebook_expansion.prepare(payload) == before
    schema = providers.strict_schema(schemas.UnitOutput, preserve_limits=True)
    original = copy.deepcopy(schema)
    assert notebook_expansion.bind_schema(schema, payload) is None
    assert schema == original and payload == before


def test_an_existing_graphic_plan_cannot_downgrade_itself_to_nonrequired(household, monkeypatch):
    _, _, planned, _, wire = prepared(household, 2, False)
    planned["visual_context"]["required"] = False
    calls = []
    http_mock(monkeypatch, wire, calls)
    with pytest.raises(providers.ProviderError) as error:
        providers.request_provider(_config("openrouter"), "unit", planned)
    assert calls == [] and error.value.billing_result.cost_source == "cancelled"
