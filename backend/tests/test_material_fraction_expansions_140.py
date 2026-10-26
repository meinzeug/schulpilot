"""Ordinary material -> fixed arithmetic -> real native HTTP -> source guards."""
import copy
import json
import socket

import httpx
import pytest
from schulpilot import learning_entry, providers, schemas, subject_content, visual_references, worker
from schulpilot import material_fraction_expansions as material_expansion
from schulpilot import notebook_fraction_expansions as notebook_expansion
from schulpilot.db import DB, Attempt, Child, Job, LearningUnit, Material, UnitSource, Usage, now
from schulpilot.graphic_schema import bind_coherent_graphics
from schulpilot.math_tasks import _task
from schulpilot.subject_registry import identity
from schulpilot.visual_reference_models import UnitVisualSnapshot
from sqlalchemy import func, select
from test_graphic_native_transport import subset_record
from test_learning_entry import dated_expansion_attempt
from test_material_output_routing import post, selection
from test_notebook_output_routing import routed as routed
from test_notebook_practice import notebook as notebook
from test_presentation_capability_paths import _config

CONTENT = "Beim Erweitern multiplizierst du Zähler und Nenner mit derselben Zahl. Originalbeispiele: 1/5 und 2/7."


@pytest.fixture(autouse=True)
def no_network(monkeypatch):
    def deny(*args, **kwargs):
        raise AssertionError("No vendor traffic in synthetic material proof tests")
    monkeypatch.setattr(socket.socket, "connect", deny)
    monkeypatch.setattr(socket, "getaddrinfo", deny)


def binding_and_wire(payload):
    planned = material_expansion.prepare(payload)
    schema = providers.strict_schema(schemas.UnitOutput, preserve_limits=True)
    subject_content.bind_graphic_schema(schema, ["Mathematik"])
    bind_coherent_graphics(schema)
    providers.indexed_choice_schema(schema, bounded_matches=True)
    visual_references.bind_schema(schema, planned)
    schema["properties"]["questions"].update(minItems=2, maxItems=2)
    learning_entry.bind_entry_schema(schema, planned)
    old_bounds = copy.deepcopy({key: schema["properties"]["questions"][key] for key in ("minItems", "maxItems")})
    binding = material_expansion.bind_schema(schema, planned)
    assert binding is not None
    assert {key: schema["properties"]["questions"][key] for key in old_bounds} == old_bounds

    def step(candidate):
        return {"id": candidate["id"], "text": candidate["text"], "competence_id": None,
            "disclosure": candidate["disclosure"], "reference": copy.deepcopy(candidate["reference"]),
            "source_refs": copy.deepcopy(candidate["source_refs"]),
            "presentation": {"version": 1, "evidence_kind": "knowledge", "blocks": [candidate["id"]]}}

    plan = planned[material_expansion.KEY]
    questions = []
    for core in [*plan["probes"], *plan["tasks"]]:
        candidate = next(row for row in binding.candidates
            if (row.get("question_core") or row.get("proof", {}).get("task", {})).get("id") == core["id"])
        question = {key: copy.deepcopy(core[key]) for key in notebook_expansion.CORE}
        question.update(hints=["Betrachte beide Zahlen des Bruchs."], explanation="Die Menge bleibt gleich; die Einteilung wird feiner.",
            explanation_steps=[step(candidate)], presentation=None, field_group=None)
        questions.append(question)
    intro = next(row for row in binding.candidates if row["disclosure"] == "given")
    wire = {"subject": "Mathematik", "topic": "Brüche erweitern", "explanation": "Die Menge bleibt gleich; die Teile werden feiner.",
        "explanation_steps": [step(intro)], "questions": questions}
    return planned, binding, wire


def prepared(household, entry=True):
    with DB.begin() as db:
        child = db.get(Child, household[1]["id"])
        page = Material(child_id=child.id, subject="Mathematik", subject_id=identity("mathematik"), topic="Brüche erweitern",
            title="PUBLIC SYNTHETIC", content=CONTENT, confirmed=True, status="confirmed")
        db.add(page)
        db.flush()
        previous = []
        if entry == "known":
            for index, days in enumerate((8, 4, 1)):
                attempt = dated_expansion_attempt(db, child.id, page.id, index, int(now()) - days * 86400)
                previous.extend(question["prompt"] for question in db.get(LearningUnit, attempt.unit_id).questions)
        payload = {"function": "unit", "grade": 6, "review": False, "goal": None,
            "material": {"subject": page.subject, "topic": page.topic, "content": page.content}, "previous_prompts": previous}
        payload = visual_references.with_visual_context(db, child, payload, [page])
        payload = material_expansion.add_reference(db, payload)
        payload = learning_entry.with_learning_entry(db, child, payload, [page], enabled=entry)
        payload = visual_references.with_foundation_context(db, payload)
        payload = material_expansion.with_history(payload, previous)
        page_id = page.id
    return page_id, payload, *binding_and_wire(payload)


def http_mock(monkeypatch, wire, calls, effect=None):
    real = httpx.Client
    def handler(request):
        body = json.loads(request.content)
        calls.append(body)
        if effect:
            effect(json.loads(body["messages"][1]["content"][0]["text"]))
        return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {"content": json.dumps(wire)}}],
            "usage": {"prompt_tokens": 1000, "completion_tokens": 1000, "cost": .001}})
    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real(transport=httpx.MockTransport(handler)))


@pytest.mark.parametrize("entry,count", [(False, 2), (True, 5), ("known", 4)])
def test_native_ordinary_contract_preserves_entry_cores_count_proofs_and_ready_snapshots(household, monkeypatch, entry, count):
    page_id, payload, planned, binding, wire = prepared(household, entry)
    calls = []
    http_mock(monkeypatch, wire, calls)
    config = _config("openrouter")
    config.max_output_tokens, config.reserve_micros = 8000, 250000
    config.input_per_million_micros, config.output_per_million_micros = 2000000, 10000000
    result = providers.request_provider(config, "unit", planned)
    assert len(calls) == 1 and calls[0]["max_tokens"] == 8000 and result.cost_micros == 1000
    assert calls[0]["reasoning"]["effort"] == "medium"
    assert len(result.data["questions"]) == planned[material_expansion.KEY]["question_count"] == count
    schema = calls[0]["response_format"]["json_schema"]["schema"]
    subset_record(schema)
    assert schema["properties"]["questions"]["minItems"] == schema["properties"]["questions"]["maxItems"] == count
    sent = json.loads(calls[0]["messages"][1]["content"][0]["text"])
    assert material_expansion.HISTORY not in sent
    assert not any(sent.get(key) for key in ("notebook_practice", "study_block"))
    assert sent["math_tasks"] == planned[material_expansion.KEY]["tasks"]
    cores = {core["id"]: core for core in [*planned[material_expansion.KEY]["probes"], *planned[material_expansion.KEY]["tasks"]]}
    for question in result.data["questions"]:
        assert all(question[key] == cores[question["id"]][key] for key in notebook_expansion.CORE)
    for candidate in binding.candidates:
        if candidate.get("proof"):
            n, d = candidate["proof"]["input"]
            factor = candidate["proof"]["factor"]
            assert candidate["proof"]["output"] == [n * factor, d * factor] and d * factor <= 24
    with DB.begin() as db:
        visual_references.validate_output(db, result.data, payload)
        unit = LearningUnit(child_id=household[1]["id"], material_id=page_id, subject="Mathematik", topic=result.data["topic"],
            explanation=result.data["explanation"], questions=result.data["questions"], provider="synthetic", model="own-fixture")
        db.add(unit)
        db.flush()
        visual_references.remember(db, unit, result.data, payload)
        db.flush()
        snapshot = db.get(UnitVisualSnapshot, unit.id)
        assert snapshot.status == "ready"
        assert all(not visual_references.public_steps(steps) for steps in snapshot.question_steps.values())


@pytest.mark.parametrize("fault", ["task_answer", "probe_answer", "question_id", "source_ref", "reference", "version", "disclosure", "candidate_id"])
def test_native_wrong_core_or_proof_is_billed_once_and_rejected(household, monkeypatch, fault):
    _, _, planned, _, wire = prepared(household)
    question = wire["questions"][0 if fault == "probe_answer" else -1]
    step = question["explanation_steps"][0]
    if fault.endswith("answer"):
        question["answer"] = "99/99"
    elif fault == "question_id":
        question["id"] = "unbound"
    elif fault == "source_ref":
        step["source_refs"] = ["p999"]
    elif fault == "reference":
        step["reference"]["id"] = "math.fraction.part_whole"
    elif fault == "version":
        step["reference"]["version"] += 1
    elif fault == "disclosure":
        step["disclosure"] = "given"
    else:
        step["presentation"]["blocks"] = ["not-from-this-request"]
    calls = []
    http_mock(monkeypatch, wire, calls)
    with pytest.raises(providers.ProviderError) as error:
        providers.request_provider(_config("openrouter"), "unit", planned)
    assert len(calls) == 1 and error.value.billing_result.cost_source == "reported"
    assert error.value.billing_result.cost_micros == 1000


@pytest.mark.parametrize("fault", ["plan_answer", "math_answer", "reference_digest", "source_revision", "probe_core", "exhausted", "unknown_history"])
def test_invalid_or_exhausted_request_stops_before_http(household, monkeypatch, fault):
    _, payload, planned, _, wire = prepared(household)
    if fault == "plan_answer":
        planned[material_expansion.KEY]["tasks"][0]["answer"] = "1/2"
    elif fault == "math_answer":
        planned["math_tasks"] = copy.deepcopy(planned["math_tasks"])
        planned["math_tasks"][0]["answer"] = "1/2"
    elif fault == "reference_digest":
        next(ref for ref in planned["visual_context"]["references"] if ref["id"] == "math.fraction.expansion")["digest"] = "0" * 64
    elif fault == "source_revision":
        next(row for row in planned["visual_context"]["sources"] if row.get("material_id"))["revision"] += 1
    elif fault == "probe_core":
        planned["learning_entry"]["units"][0]["probes"][0]["answer"] = "99"
    else:
        prompts = [_task("expand", values, "apply")[0] for values in notebook_expansion._pool()] if fault == "exhausted" else ["Erweitere diesen unklaren Altbruch."]
        planned = material_expansion.with_history(payload, prompts)
        # A fresh actual worker would prepare immediately, without dispatch.
    calls = []
    http_mock(monkeypatch, wire, calls)
    with pytest.raises((providers.ProviderError, ValueError)):
        if fault in ("exhausted", "unknown_history"):
            material_expansion.prepare(planned)
        else:
            providers.request_provider(_config("openrouter"), "unit", planned)
    assert calls == []


@pytest.mark.parametrize("flag", ["review", "goal", "study_block", "notebook_practice", "selected_groups", "homework_practice", "exam_preparation", "exam_review_practice"])
def test_no_relabeling_or_cross_contract_adaptation(household, flag):
    _, payload, _, _, _ = prepared(household, False)
    payload.pop(material_expansion.HISTORY)
    payload[flag] = {"version": 1} if flag not in ("review", "homework_practice") else True
    assert not material_expansion.eligible(payload)
    assert material_expansion.prepare(payload) == payload


def test_reference_is_idempotent_and_conflicting_digest_is_rejected(household):
    _, payload, _, _, _ = prepared(household, False)
    with DB() as db:
        assert material_expansion.add_reference(db, payload) == payload
        damaged = copy.deepcopy(payload)
        next(ref for ref in damaged["visual_context"]["references"] if ref["id"] == "math.fraction.expansion")["digest"] = "0" * 64
        with pytest.raises(ValueError):
            material_expansion.add_reference(db, damaged)


@pytest.mark.parametrize("race", ["none", "source", "history", "configuration"])
def test_real_normal_api_worker_reserves_sol_once_and_rechecks_sources_and_full_history(routed, monkeypatch, race):
    value = selection(routed)
    with DB.begin() as db:
        page = db.get(Material, value["material_id"])
        page.content, page.topic = CONTENT, "Brüche erweitern"
    routed.client.headers["X-Schulpilot-Capabilities"] = "learning-entry-v1"
    response = post(routed, value, "ordinary-expansion-140")
    assert response.status_code == 202, response.text
    job_id = response.json()["id"]
    assert post(routed, value, "ordinary-expansion-140").json()["id"] == job_id
    calls, payloads = [], []
    original = providers.request_provider
    with DB() as db:
        old_attempts = list(db.execute(select(Attempt.id, Attempt.answer, Attempt.outcome, Attempt.assisted)))
        old_units = db.scalar(select(func.count()).select_from(LearningUnit))
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        snapshot = copy.deepcopy(usage.route_snapshot)
        assert snapshot["reason"] == "material_graphic_teaching" and usage.reserved_micros == 250000
        job = db.get(Job, job_id)
        assert not job.payload.get("notebook_practice") and "question_count" not in job.payload

    def effect(sent):
        assert not sent.get("notebook_practice") and not sent.get("study_block")
        assert material_expansion.HISTORY not in sent
        with DB.begin() as db:
            if race == "source":
                db.get(Material, value["material_id"]).revision += 1
            elif race == "history":
                task = sent[material_expansion.KEY]["tasks"][0]
                unit = LearningUnit(child_id=routed.child["id"], material_id=value["material_id"], subject="Mathematik", topic="PUBLIC SYNTHETIC",
                    explanation="Künstlicher Parallelauftrag.", questions=[task], provider="fixture")
                db.add(unit)
                db.flush()
                db.add(UnitSource(unit_id=unit.id, material_id=value["material_id"], revision=db.get(Material, value["material_id"]).revision))
            elif race == "configuration":
                from schulpilot.db import ProviderConfig
                db.get(ProviderConfig, 1).revision += 1

    def request(config, function, payload, *args, **kwargs):
        payloads.append(copy.deepcopy(payload))
        assert function == "unit" and payload[material_expansion.KEY] and payload["math_tasks"]
        _, _, wire = binding_and_wire(payload)
        if context := payload.get("catalog_context"):
            wire["catalog_assignment"] = {"subject_ids": [context["subject_aliases"]["mathematik"]], "matches": [], "unmatched_context_refs": context["context_refs"]}
        http_mock(monkeypatch, wire, calls, effect)
        return original(config, function, payload, *args, **kwargs)

    monkeypatch.setattr(worker, "request_provider", request)
    with DB() as db:
        assert worker.claim(db) == job_id
    worker.process(job_id)
    with DB() as db:
        job = db.get(Job, job_id)
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        assert len(calls) == len(payloads) == 1 and calls[0]["max_tokens"] == 8000
        assert usage.route_snapshot == snapshot and usage.cost_micros == 1000 and usage.cost_source == "reported"
        assert list(db.execute(select(Attempt.id, Attempt.answer, Attempt.outcome, Attempt.assisted))) == old_attempts
        if race == "none":
            assert job.status == "completed", job.error
            unit = db.get(LearningUnit, job.result["unit_id"])
            assert db.get(UnitVisualSnapshot, unit.id).status == "ready" and len(unit.questions) == 5
            assert db.scalar(select(func.count()).select_from(LearningUnit)) == old_units + 1
        else:
            assert job.status == "failed" and usage.status == "failed_billed"
            assert db.scalar(select(func.count()).select_from(LearningUnit)) == old_units + (1 if race == "history" else 0)
    worker.process(job_id)
    assert len(calls) == 1


def test_complete_history_excludes_old_arithmetic_outside_bounded_model_context(household):
    from schulpilot.coaching import fraction_task_signature
    from schulpilot.unit_novelty import provider_context

    _, payload, _, _, _ = prepared(household, False)
    old = _task("expand", (1, 4, 3), "understand")[0]
    history = [old, *[f"PUBLIC SYNTHETIC other question {index}?" for index in range(100)]]
    payload["previous_prompts"] = provider_context(history)
    assert old not in payload["previous_prompts"]
    planned = material_expansion.prepare(material_expansion.with_history(payload, history))
    assert all(fraction_task_signature(task["prompt"]) != fraction_task_signature(old)
        for task in planned[material_expansion.KEY]["tasks"])
    _, _, wire = binding_and_wire(planned)
    task = planned[material_expansion.KEY]["tasks"][0]
    with pytest.raises(ValueError, match="inzwischen"):
        material_expansion.validate_history(planned, wire, [*history, task["prompt"]])


@pytest.mark.parametrize("extra", [" Beim Kürzen werden Zähler und Nenner durch dieselbe Zahl geteilt.",
    " Bei gleichem Nenner addiert man die Zähler beim Addieren."])
def test_unrelated_confirmed_procedures_are_not_silently_reallocated(household, extra):
    _, payload, _, _, _ = prepared(household, False)
    payload.pop(material_expansion.HISTORY)
    source = next(row for row in payload["visual_context"]["sources"] if row.get("material_id"))
    source["content"] += extra
    assert not material_expansion.eligible(payload)
    assert material_expansion.prepare(payload) == payload


@pytest.mark.parametrize("prompt", ["Warum bleibt der Wert beim Erweitern gleich?",
    "Was passiert beim Erweitern mit Zähler und Nenner?"])
def test_number_free_concept_question_does_not_consume_numeric_expansion_pool(household, prompt):
    from schulpilot.unit_novelty import normalized_prompt

    _, payload, _, _, _ = prepared(household, False)
    payload["previous_prompts"] = [prompt]
    planned = material_expansion.prepare(material_expansion.with_history(payload, [prompt]))
    assert planned[material_expansion.HISTORY]["unknown"] is False
    assert planned[material_expansion.HISTORY]["signatures"] == []
    assert len(planned[material_expansion.KEY]["tasks"]) == 2
    assert prompt in planned["previous_prompts"]
    assert all(normalized_prompt(task["prompt"]) != normalized_prompt(prompt)
        for task in planned[material_expansion.KEY]["tasks"])


@pytest.mark.parametrize("detail", ["2/3", "٢/٣", "⅔", "²", "Ⅳ", "一", "II", "zwei", "dreißig",
    "einundzwanzig", "drittel", "einhalb", "two", r"\frac{2}{3}", r"\frac{x}{y}",
    r"\tfrac{eins}{zwei}", "x/y", "x∕y", "x⁄y", "x−y", "x-y", "x∶y", "x⋅y", "x = y", "x + y", "Zweien",
    "dieser Bruch", "der oben gezeigte Bruch", "Faktor ein", "Faktorzwei"])
def test_unclear_numeric_symbolic_or_referenced_expansion_remains_closed(household, detail):
    _, payload, _, _, _ = prepared(household, False)
    prompt = "Wie funktioniert das Erweitern mit " + detail + "?"
    candidate = material_expansion.with_history(payload, [prompt])
    assert candidate[material_expansion.HISTORY]["unknown"] is True
    with pytest.raises(ValueError, match="keine neuen darstellbaren"):
        material_expansion.prepare(candidate)
