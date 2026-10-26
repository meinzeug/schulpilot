"""Source-literal notebook cores, actual synthetic HTTP, complete fresh history."""

import copy
import json
import socket

import httpx
import pytest
from schulpilot import learning_entry, providers, schemas, visual_references, worker
from schulpilot import notebook_fraction_compositions as planned
from schulpilot import unit_fraction_compositions as composition
from schulpilot.db import DB, Attempt, Child, Job, LearningUnit, Material, UnitSource, Usage
from schulpilot.subject_registry import identity
from sqlalchemy import func, select
from test_graphic_native_transport import subset_record
from test_notebook_practice import notebook as notebook
from test_notebook_practice import post
from test_presentation_capability_paths import _config
from test_unit_fraction_compositions import CONTENT


@pytest.fixture(autouse=True)
def no_network(monkeypatch):
    def refuse(*_args, **_kwargs):
        raise AssertionError("External network/provider forbidden")

    monkeypatch.setattr(socket.socket, "connect", refuse)
    monkeypatch.setattr(socket, "getaddrinfo", refuse)


def prepared(household, count=2, *, entry=True, prompts=(), content=CONTENT):
    with DB.begin() as db:
        child = db.get(Child, household[1]["id"])
        page = Material(
            child_id=child.id,
            subject="Mathematik",
            subject_id=identity("mathematik"),
            topic="Unechte Brüche in gemischte Zahlen",
            title="Künstliche Umwandlungsregel",
            content=content,
            confirmed=True,
            status="confirmed",
        )
        db.add(page)
        db.flush()
        payload = {
            "grade": 6,
            "required_subject": "Mathematik",
            "material": {"subject": page.subject, "topic": page.topic, "content": page.content},
            "notebook_practice": {"version": 1, "question_count": count},
            "previous_prompts": list(prompts),
        }
        payload = visual_references.with_visual_context(db, child, payload, [page])
        payload = learning_entry.with_learning_entry(db, child, payload, [page], enabled=entry)
        payload = visual_references.with_foundation_context(db, payload)
        payload = planned.with_history(payload, list(prompts))
        page_id = page.id
    return page_id, payload


def wire(payload):
    payload = planned.prepare(payload)
    schema = providers.strict_schema(schemas.UnitOutput, preserve_limits=True)
    providers.indexed_choice_schema(schema, bounded_matches=True)
    visual_references.bind_schema(schema, payload)
    learning_entry.bind_entry_schema(schema, payload)
    schema["properties"]["questions"].update(
        minItems=payload[planned.KEY]["question_count"], maxItems=payload[planned.KEY]["question_count"]
    )
    binding = composition.bind_schema(schema, payload)

    def step(candidate):
        return {
            "id": candidate["id"],
            "text": candidate["text"],
            "competence_id": None,
            "disclosure": candidate["disclosure"],
            "reference": copy.deepcopy(candidate["reference"]),
            "source_refs": copy.deepcopy(candidate["source_refs"]),
            "presentation": {"version": 1, "evidence_kind": "knowledge", "blocks": [candidate["id"]]},
        }

    questions = []
    for core in [*payload[planned.KEY]["probes"], *[t["question_core"] for t in payload[planned.KEY]["tasks"]]]:
        candidate = next(c for c in binding.candidates if c.get("question_core", {}).get("id") == core["id"])
        questions.append(
            {
                **copy.deepcopy(core),
                "hints": ["Bündele vollständige Ganze."],
                "explanation": "Bestimme ganze Mengen und den Rest.",
                "explanation_steps": [step(candidate)],
            }
        )
    intro = next(c for c in binding.candidates if c["disclosure"] == "given")
    return (
        payload,
        binding,
        {
            "subject": "Mathematik",
            "topic": "Unechte Brüche in gemischte Zahlen",
            "explanation": "Bündele gleich große Teile zu Ganzen und betrachte den Rest.",
            "explanation_steps": [step(intro)],
            "questions": questions,
        },
    )


def mock(monkeypatch, output, calls):
    real = httpx.Client

    def handler(request):
        calls.append(json.loads(request.content))
        return httpx.Response(
            200,
            json={
                "choices": [{"finish_reason": "stop", "message": {"content": json.dumps(output)}}],
                "usage": {"prompt_tokens": 17006, "completion_tokens": 1489, "cost": 0.048902},
            },
        )

    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real(transport=httpx.MockTransport(handler)))


@pytest.mark.parametrize("count,entry", [(2, True), (5, True), (2, False), (3, False)])
def test_actual_native_schema_closes_core_and_keeps_probe_source(household, monkeypatch, count, entry):
    _, original = prepared(household, count, entry=entry)
    payload, binding, output = wire(original)
    before = copy.deepcopy(output)
    calls = []
    mock(monkeypatch, output, calls)
    result = providers.request_provider(_config("openrouter"), "unit", payload)
    assert len(calls) == 1 and result.cost_micros == 48902 and output == before
    schema = calls[0]["response_format"]["json_schema"]["schema"]
    subset_record(schema)
    assert schema["properties"]["questions"]["minItems"] == schema["properties"]["questions"]["maxItems"] == count
    assert planned.REVISION in calls[0]["messages"][0]["content"]
    expected_cores = {
        core["id"]: core
        for core in [*payload[planned.KEY]["probes"], *[t["question_core"] for t in payload[planned.KEY]["tasks"]]]
    }
    found = set()

    def resolve(node):
        while "$ref" in node:
            node = schema["$defs"][node["$ref"].rsplit("/", 1)[-1]]
        return node

    def inspect(node):
        if isinstance(node, dict):
            fields = {key: resolve(value) for key, value in node.get("properties", {}).items()}
            if "prompt" in fields and "answer" in fields:
                assert len(fields["id"].get("enum", [])) == 1
                core = expected_cores[fields["id"]["enum"][0]]
                assert fields["prompt"].get("enum") == [core["prompt"]]
                assert fields["answer"].get("enum") == [core["answer"]]
                assert fields["type"].get("enum") == [core["type"]]
                assert fields["options"]["maxItems"] == fields["accepted"]["maxItems"] == 0
                found.add(core["id"])
            for value in node.values():
                inspect(value)
        elif isinstance(node, list):
            for item in node:
                inspect(item)

    inspect(schema)
    assert found == set(expected_cores)
    sent = json.loads(calls[0]["messages"][1]["content"][0]["text"])
    assert planned.HISTORY_KEY not in sent
    for task in payload[planned.KEY]["tasks"]:
        core = task["question_core"]
        assert [q for q in result.data["questions"] if q["id"] == core["id"]][0]["prompt"] == core["prompt"]
        candidate = next(c for c in binding.candidates if c["id"] == task["candidate_id"])
        assert composition._bound_question(candidate, core)
        assert all(
            core[key] == next(q for q in result.data["questions"] if q["id"] == core["id"])[key] for key in planned.CORE
        )
    for core in payload[planned.KEY]["probes"]:
        candidate = next(c for c in binding.candidates if c.get("question_core", {}).get("id") == core["id"])
        assert candidate["reference"]["id"] == "math.fraction.part_whole"
        assert any(
            s.get("source_type") == "curated_foundation" and s["ref"] in candidate["source_refs"]
            for s in payload["visual_context"]["sources"]
        )
        assert next(q for q in result.data["questions"] if q["id"] == core["id"])["answer"] == core["answer"]
    planned.validate_output(payload, result.data)
    planned.validate_history(payload, result.data, [])


@pytest.mark.parametrize("change", ["extra_fraction", "worded", "wrong_input", "answer", "id", "probe_answer"])
def test_ignored_schema_mutation_is_rejected_once_without_replacement(household, monkeypatch, change):
    _, payload = prepared(household)
    payload, _, output = wire(payload)
    target = output["questions"][-1]
    if change == "extra_fraction":
        target["prompt"] += " Vergleiche auch 5/4."
    elif change == "worded":
        target["prompt"] = "Schreibe neun Viertel als gemischte Zahl."
    elif change == "wrong_input":
        target["prompt"] = "Schreibe 7/3 als gemischte Zahl."
    elif change == "answer":
        target["answer"] = "3 1/4"
    elif change == "id":
        target["id"] = output["questions"][0]["id"]
    else:
        output["questions"][0]["answer"] = "falsch"
    changed = copy.deepcopy(output)
    calls = []
    mock(monkeypatch, output, calls)
    with pytest.raises(providers.ProviderError) as error:
        providers.request_provider(_config("openrouter"), "unit", payload)
    assert len(calls) == 1 and output == changed
    assert error.value.billing_result.cost_micros == 48902


@pytest.mark.parametrize(
    "prompt",
    [
        "Schreibe 9/4 als gemischte Zahl.",
        "Schreibe 9 durch 4 als gemischte Zahl.",
        r"Schreibe \frac{18}{8} als gemischte Zahl.",
    ],
)
def test_complete_history_excludes_value_even_beyond_context_window(household, prompt):
    _, payload = prepared(household, 2, entry=False)
    all_prompts = [prompt, *[f"Andere künstliche Frage {i}." for i in range(121)]]
    payload["previous_prompts"] = all_prompts[-80:]
    payload = planned.prepare(planned.with_history(payload, all_prompts))
    assert all("9/4" not in t["question_core"]["prompt"] for t in payload[planned.KEY]["tasks"])
    assert payload[planned.HISTORY_KEY]["used_values"] == ["9/4"]
    assert "prompt" not in json.dumps(payload[planned.HISTORY_KEY])


@pytest.mark.parametrize("fault", ["missing", "digest", "revision", "exhausted", "worded_unknown", "too_many"])
def test_incomplete_stale_or_exhausted_plan_refuses_before_any_http(household, monkeypatch, fault):
    _, payload = prepared(household, 3 if fault == "too_many" else 2, entry=False)
    if fault == "missing":
        payload.pop(planned.HISTORY_KEY)
    elif fault == "digest":
        payload[planned.HISTORY_KEY]["pool_digest"] = "0" * 64
    elif fault == "revision":
        payload["visual_context"]["sources"][0]["revision"] += 1
    elif fault == "worded_unknown":
        payload = planned.with_history(payload, ["Schreibe neun Viertel als gemischte Zahl."])
    elif fault == "too_many":
        payload = planned.with_history(payload, ["Schreibe 9/4 als gemischte Zahl."])
    else:
        payload = planned.with_history(payload, ["Schreibe 9/4 und 5/4 und 7/3 als gemischte Zahlen."])
    calls = []
    mock(monkeypatch, {}, calls)
    with pytest.raises(providers.ProviderError) as error:
        providers.request_provider(_config("openrouter"), "unit", payload)
    assert (
        calls == []
        and error.value.billing_result.cost_source == "cancelled"
        and error.value.billing_result.cost_micros == 0
    )


def test_fresh_history_rejects_selected_concurrent_value_and_keeps_output(household):
    _, payload = prepared(household, entry=False)
    payload, binding, output = wire(payload)
    restored = binding.hydrate(output)
    before = copy.deepcopy(restored)
    with pytest.raises(ValueError, match="inzwischen bereits"):
        planned.validate_history(payload, restored, [payload[planned.KEY]["tasks"][0]["question_core"]["prompt"]])
    assert restored == before


@pytest.mark.parametrize(
    "flag",
    ["review", "study_block", "homework_practice", "exam_preparation", "exam_review_practice", "selected_groups"],
)
def test_other_existing_contracts_are_not_replanned(household, flag):
    _, payload = prepared(household)
    payload.pop(planned.HISTORY_KEY)
    payload[flag] = {"version": 1}
    before = copy.deepcopy(payload)
    assert planned.with_history(payload, []) == before
    assert planned.prepare(payload) == before


def configure_notebook(notebook):
    identifier = notebook.refs[0]["id"]
    with DB.begin() as db:
        page = db.get(Material, identifier)
        page.topic, page.content = "Unechte Brüche in gemischte Zahlen", CONTENT
        previous = [(a.id, a.answer, a.outcome) for a in db.scalars(select(Attempt).order_by(Attempt.id))]
    return identifier, previous


def start(notebook, identifier, key):
    response = post(
        notebook, {"material_id": identifier, "notebook_sources": notebook.refs[:1], "question_count": 2}, key=key
    )
    assert response.status_code == 202, response.text
    with DB() as db:
        assert worker.claim(db) == response.json()["id"]
    return response.json()["id"]


def test_worker_prepares_same_closed_plan_and_publishes_graphics_without_editing_old_answers(notebook, monkeypatch):
    identifier, previous = configure_notebook(notebook)
    calls = []

    def model(config, function, payload, *args, **kwargs):
        assert planned.KEY in payload and planned.HISTORY_KEY in payload
        current, binding, output = wire(payload)
        assert current == payload
        calls.append(copy.deepcopy(payload))
        return providers.Result(
            schemas.UnitOutput.model_validate(binding.hydrate(output)).model_dump(mode="json"),
            100,
            200,
            1000,
            cost_source="reported",
        )

    monkeypatch.setattr(worker, "request_provider", model)
    job_id = start(notebook, identifier, "notebook-composition-worker-normal-140")
    worker.process(job_id)
    from schulpilot.visual_reference_models import UnitVisualSnapshot

    with DB() as db:
        job = db.get(Job, job_id)
        assert job.status == "completed" and job.result["unit_id"]
        unit = db.get(LearningUnit, job.result["unit_id"])
        assert db.get(UnitVisualSnapshot, unit.id).status == "ready"
        assert all(
            step["reference"]["id"] == composition.RECIPE for q in unit.questions[1:] for step in q["explanation_steps"]
        )
        assert [(a.id, a.answer, a.outcome) for a in db.scalars(select(Attempt).order_by(Attempt.id))] == previous
    assert len(calls) == 1


def test_worker_rechecks_concurrent_equivalent_value_beyond_exact_prompt_matching(notebook, monkeypatch):
    identifier, previous = configure_notebook(notebook)
    calls = []

    def model(config, function, payload, *args, **kwargs):
        _, binding, output = wire(payload)
        core = payload[planned.KEY]["tasks"][0]["question_core"]
        candidate = next(c for c in binding.candidates if c.get("question_core") == core)
        n, d = candidate["proof"]["input"]
        with DB.begin() as db:
            other = LearningUnit(
                child_id=notebook.child["id"],
                material_id=identifier,
                subject="Mathematik",
                topic="Parallel gespeicherte künstliche Frage",
                explanation="Gespeicherte künstliche Erklärung.",
                questions=[{"id": "parallel", "prompt": f"Schreibe {2 * n}/{2 * d} als gemischte Zahl."}],
                status="completed",
                provider="fixture",
            )
            db.add(other)
            db.flush()
            db.add(UnitSource(unit_id=other.id, material_id=identifier, revision=1))
        calls.append(True)
        return providers.Result(
            schemas.UnitOutput.model_validate(binding.hydrate(output)).model_dump(mode="json"),
            100,
            200,
            1000,
            cost_source="reported",
        )

    monkeypatch.setattr(worker, "request_provider", model)
    job_id = start(notebook, identifier, "notebook-composition-worker-fresh-140")
    worker.process(job_id)
    with DB() as db:
        job = db.get(Job, job_id)
        assert job.status == "failed" and job.error == planned.CURRENT_ERROR and job.result is None
        usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
        assert usage.status == "failed_billed" and usage.cost_micros == 1000
        assert [(a.id, a.answer, a.outcome) for a in db.scalars(select(Attempt).order_by(Attempt.id))] == previous
    assert calls == [True]


def test_worker_whole_history_exhaustion_stops_before_provider_and_keeps_saved_records(notebook, monkeypatch):
    identifier, previous = configure_notebook(notebook)
    with DB.begin() as db:
        for i in range(121):
            old = LearningUnit(
                child_id=notebook.child["id"],
                material_id=identifier,
                subject="Mathematik",
                topic="Künstlicher Verlauf",
                explanation="Gespeichert.",
                questions=[
                    {
                        "id": "old",
                        "prompt": "Schreibe 9/4 und 5/4 und 7/3 als gemischte Zahlen."
                        if i == 0
                        else f"Andere künstliche Frage {i}.",
                    }
                ],
                status="completed",
                provider="fixture",
                created=i,
            )
            db.add(old)
            db.flush()
            db.add(UnitSource(unit_id=old.id, material_id=identifier, revision=1))
        before = db.scalar(select(func.count()).select_from(LearningUnit))
    calls = []

    def forbidden(*args, **kwargs):
        calls.append(True)
        raise AssertionError("No provider for exhausted originals")

    monkeypatch.setattr(worker, "request_provider", forbidden)
    job_id = start(notebook, identifier, "notebook-composition-worker-exhausted-140")
    worker.process(job_id)
    with DB() as db:
        job = db.get(Job, job_id)
        assert job.status == "failed" and job.error == planned.EXHAUSTED
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        assert usage.cost_micros == 0 and usage.cost_source == "cancelled"
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == before
        assert [(a.id, a.answer, a.outcome) for a in db.scalars(select(Attempt).order_by(Attempt.id))] == previous
    assert calls == []
