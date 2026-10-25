"""Complete source/day novelty becomes bounded private arithmetic exclusions."""
import copy
import json

import pytest
from schulpilot import notebook_fraction_expansions as expansions
from schulpilot import providers, schemas, visual_references, worker
from schulpilot.db import DB, Attempt, Child, Job, LearningUnit, Material, UnitSource, Usage, now
from schulpilot.math_tasks import _task
from schulpilot.subject_registry import identity
from sqlalchemy import func, select
from test_notebook_fraction_expansions import CONTENT, binding_and_wire, http_mock, prepared
from test_notebook_practice import notebook as notebook
from test_notebook_practice import post
from test_presentation_capability_paths import _config


def save_history(db, child_id, material, prompts, *, start):
    answers = {_task("expand", numbers, "apply")[0]: _task("expand", numbers, "apply")[1] for numbers in expansions._pool()}
    for offset in range(0, len(prompts), 5):
        unit = LearningUnit(child_id=child_id, material_id=material.id, school_day_id=material.school_day_id,
            subject="Mathematik", topic="Frühere künstliche Heft-Runde", explanation="Künstliche frühere Einführung.",
            questions=[{"id": f"q{index + 1}", "type": "short", "prompt": prompt, "answer": answers.get(prompt, "2"),
                "options": [], "accepted": [], "hints": [], "explanation": "Künstliche historische Metadaten."}
                for index, prompt in enumerate(prompts[offset:offset + 5])],
            provider="synthetic", model="own-history-fixture", status="completed", created=start + offset)
        db.add(unit)
        db.flush()
        db.add(UnitSource(unit_id=unit.id, material_id=material.id, revision=material.revision))
    db.flush()


@pytest.mark.parametrize("exhausted", [False, True])
def test_real_worker_uses_all_day_signatures_before_80_prompt_and_character_cutoff(notebook, monkeypatch, exhausted):
    pool = sorted(expansions._pool())
    remaining = [] if exhausted else pool[-2:]
    used = pool if exhausted else pool[:-2]
    old_prompts = [_task("expand", numbers, "apply")[0] for numbers in used]
    filler = [f"Frühere künstliche Verständnisfrage {index}: "
        + "Beim Lesen achten wir auf die im Beispiel genannten Zahlen und ihre Bedeutung. " * 4
        + "Welche Zahl steht beim Bruch 1/2 unter dem Bruchstrich?" for index in range(100)]
    with DB.begin() as db:
        page = db.get(Material, notebook.refs[0]["id"])
        page.content, page.topic = CONTENT, "Brüche erweitern"
        other = db.get(Material, notebook.refs[2]["id"])
        other.confirmed = False  # Unselected older source does not become a teaching source.
        assert page.school_day_id == other.school_day_id
        save_history(db, notebook.child["id"], page, old_prompts, start=int(now()) - 4000)
        save_history(db, notebook.child["id"], other, filler, start=int(now()) - 2000)
        before_units = db.scalar(select(func.count()).select_from(LearningUnit))
        before_attempts = [(row.id, copy.deepcopy(row.answer), row.outcome) for row in db.scalars(select(Attempt))]
    _config("openrouter")
    value = {"material_id": notebook.refs[0]["id"], "notebook_sources": notebook.refs[:1], "question_count": 2}
    response = post(notebook, value)
    assert response.status_code == 202, response.text
    job_id = response.json()["id"]
    provider_entries, calls = [], []
    real_provider = providers.request_provider

    def request(config, function, payload, *args, **kwargs):
        provider_entries.append(copy.deepcopy(payload))
        assert function == "unit"
        bounded = payload["previous_prompts"]
        assert len(bounded) <= 80 and sum(map(len, bounded)) <= 12000
        assert len(bounded) < 80  # This history exercises the character boundary too.
        assert not set(old_prompts).intersection(bounded)
        meta = payload[expansions.HISTORY_KEY]
        assert set(meta) == {"version", "source_digest", "signatures"}
        assert meta["signatures"] == [list(numbers) for numbers in used]
        assert all(type(number) is int for row in meta["signatures"] for number in row)
        assert not any(prompt in json.dumps(meta) for prompt in old_prompts + filler)
        if not exhausted:
            planned, _, wire = binding_and_wire(payload)
            assert [candidate["id"] for candidate in planned[expansions.KEY]["tasks"]] == ["q1", "q2"]
            planned_signatures = [expansions.expansion._planned(task, "apply") for task in planned[expansions.KEY]["tasks"]]
            assert set(planned_signatures) == set(remaining)
            http_mock(monkeypatch, wire, calls)
        else:
            http_mock(monkeypatch, {}, calls)
        return real_provider(config, function, payload, *args, **kwargs)

    monkeypatch.setattr(worker, "request_provider", request)
    with DB() as db:
        assert worker.claim(db) == job_id
    worker.process(job_id)
    with DB() as db:
        job = db.get(Job, job_id)
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        assert len(provider_entries) == 1
        if exhausted:
            assert job.status == "failed" and job.error == expansions.EXHAUSTED
            assert calls == [] and usage.cost_source == "cancelled" and usage.cost_micros == 0
            assert db.scalar(select(func.count()).select_from(LearningUnit)) == before_units
        else:
            assert job.status == "completed", job.error
            assert len(calls) == 1 and usage.cost_micros == 1000
            wire_payload = json.loads(calls[0]["messages"][1]["content"][0]["text"])
            assert expansions.HISTORY_KEY not in wire_payload
            assert not any(prompt in json.dumps(wire_payload) for prompt in old_prompts)
            unit = db.get(LearningUnit, job.result["unit_id"])
            assert len(unit.questions) == 2
            assert db.scalar(select(func.count()).select_from(LearningUnit)) == before_units + 1
        assert [(row.id, row.answer, row.outcome) for row in db.scalars(select(Attempt))] == before_attempts
    worker.process(job_id)
    assert len(provider_entries) == 1  # No automatic second request or retry.


@pytest.mark.parametrize("fault", ["missing", "version", "scope", "duplicate", "outside_pool", "bool", "nan"])
def test_unknown_or_stale_closed_exclusions_refuse_before_http(household, monkeypatch, fault):
    _, payload, _, _, wire = prepared(household, 2, False)
    key = expansions.HISTORY_KEY
    if fault == "missing":
        payload.pop(key)
    elif fault == "version":
        payload[key]["version"] = 2
    elif fault == "scope":
        payload[key]["source_digest"] = "0" * 64
    elif fault == "duplicate":
        payload[key]["signatures"] = [[1, 2, 2], [1, 2, 2]]
    elif fault == "outside_pool":
        payload[key]["signatures"] = [[1, 25, 2]]
    elif fault == "bool":
        payload[key]["signatures"] = [[True, 2, 2]]
    else:
        payload[key]["signatures"] = [[float("nan"), 2, 2]]
    calls = []
    http_mock(monkeypatch, wire, calls)
    with pytest.raises(providers.ProviderError) as error:
        providers.request_provider(_config("openrouter"), "unit", payload)
    assert calls == [] and error.value.billing_result.cost_source == "cancelled"
    assert error.value.billing_result.cost_micros == 0


def test_exclusion_only_changes_cannot_rebind_an_existing_private_plan(household, monkeypatch):
    _, _, planned, _, wire = prepared(household, 2, False)
    # Even an unused exclusion changes the bound history receipt, never a returned answer.
    selected = {expansions.expansion._planned(task, "apply") for task in planned[expansions.KEY]["tasks"]}
    unused = next(numbers for numbers in sorted(expansions._pool()) if numbers not in selected)
    planned[expansions.HISTORY_KEY]["signatures"] = [list(unused)]
    calls = []
    http_mock(monkeypatch, wire, calls)
    with pytest.raises(providers.ProviderError) as error:
        providers.request_provider(_config("openrouter"), "unit", planned)
    assert calls == [] and error.value.billing_result.cost_source == "cancelled"


@pytest.mark.parametrize("other_rule", [
    "Beim Kürzen teilst du Zähler und Nenner durch dieselbe ganze Zahl.",
    "Beim Addieren von Brüchen mit gleichem Nenner addierst du die Zähler.",
])
def test_multimethod_page_keeps_all_three_new_hooks_inactive(household, other_rule):
    with DB.begin() as db:
        child = db.get(Child, household[1]["id"])
        page = Material(child_id=child.id, subject="Mathematik", subject_id=identity("mathematik"),
            topic="Brüche erweitern und weitere Verfahren", title="Künstliche Mehrverfahrensseite",
            content=CONTENT + " " + other_rule, confirmed=True, status="confirmed")
        db.add(page)
        db.flush()
        payload = visual_references.with_visual_context(db, child, {
            "required_subject": "Mathematik", "notebook_practice": {"version": 1, "question_count": 2},
            "material": {"subject": page.subject, "topic": page.topic, "content": page.content}}, [page])
        assert payload["visual_context"]["required"] is True
        assert expansions.eligible(payload) is True  # Literal expansion exists; catalog scope is narrower.
        assert not any(ref["id"] == expansions.expansion.RECIPE for ref in payload["visual_context"]["references"])
        before = copy.deepcopy(payload)
        assert expansions.add_reference(db, payload) == before
        assert expansions.with_history(payload, ["Erweitere 1/2 mit 2."]) == before
        assert expansions.prepare(payload) == before
        assert expansions.HISTORY_KEY not in payload and expansions.KEY not in payload
        schema = providers.strict_schema(schemas.UnitOutput, preserve_limits=True)
        original = copy.deepcopy(schema)
        assert expansions.bind_schema(schema, payload) is None
        assert schema == original and payload == before
