"""Artificial source/HTTP/worker kgV contracts, never actual learner material."""
import copy
import json

import pytest
from schulpilot import learning_entry, providers, schemas, subject_content, visual_references, worker
from schulpilot import unit_multiples_common as multiples
from schulpilot.db import DB, Attempt, Child, Job, LearningUnit, Material, UnitSource, Usage
from schulpilot.graphic_schema import bind_coherent_graphics
from schulpilot.subject_registry import identity
from schulpilot.visual_reference_models import UnitVisualSnapshot
from sqlalchemy import func, select
from test_graphic_native_transport import subset_record
from test_notebook_fraction_expansions import http_mock
from test_notebook_practice import notebook as shared_notebook
from test_notebook_practice import post
from test_presentation_capability_paths import _config

notebook = shared_notebook

RULE = "Das kleinste gemeinsame Vielfache zweier Zahlen ist die kleinste positive Zahl, die durch beide Zahlen ohne Rest teilbar ist."


def binding_and_wire(payload):
    planned = multiples.prepare(payload)
    schema = providers.strict_schema(schemas.UnitOutput, preserve_limits=True)
    subject_content.bind_graphic_schema(schema, ["Mathematik"])
    bind_coherent_graphics(schema)
    providers.indexed_choice_schema(schema, bounded_matches=True)
    count = planned[multiples.KEY]["question_count"]
    schema["properties"]["questions"].update(minItems=count, maxItems=count)
    visual_references.bind_schema(schema, planned)
    learning_entry.bind_entry_schema(schema, planned)
    binding = multiples.bind_schema(schema, planned)

    def step(row):
        return {"id": row["id"], "text": row["text"], "competence_id": None,
            "disclosure": row["disclosure"], "reference": copy.deepcopy(row["reference"]), "source_refs": copy.deepcopy(row["source_refs"]),
            "presentation": {"version": 1, "evidence_kind": "knowledge", "blocks": [row["id"]]}}

    intro = next(row for row in binding.candidates if row["disclosure"] == "given")
    questions = []
    for task in planned[multiples.KEY]["tasks"]:
        row = next(row for row in binding.candidates if row["proof"]["task"] == task)
        questions.append({**copy.deepcopy(task), "hints": ["Bilde die Vielfachen beider Zahlen.",
            "Suche die kleinste Zahl in beiden Reihen."], "explanation": row["text"],
            "presentation": None, "field_group": None, "explanation_steps": [step(row)]})
    wire = {"subject": "Mathematik", "topic": "Kleinstes gemeinsames Vielfaches", "explanation": intro["text"],
        "explanation_steps": [step(intro)], "questions": questions}
    return planned, schema, binding, wire


def prepared(household, count=2, *, entry=True, content=RULE):
    with DB.begin() as db:
        child = db.get(Child, household[1]["id"])
        page = Material(child_id=child.id, title="Künstliche kgV-Regel", subject="Mathematik",
            subject_id=identity("mathematik"), topic="kgV", content=content, confirmed=True, status="confirmed")
        db.add(page)
        db.flush()
        payload = {"required_subject": "Mathematik", "grade": 6,
            "notebook_practice": {"version": 1, "question_count": count},
            "material": {"subject": page.subject, "topic": page.topic, "content": page.content}, "previous_prompts": []}
        payload = visual_references.with_visual_context(db, child, payload, [page])
        payload = learning_entry.with_learning_entry(db, child, payload, [page], enabled=entry)
        payload = visual_references.with_foundation_context(db, payload)
        payload = multiples.with_history(payload, [])
        page_id = page.id
    return page_id, payload


@pytest.mark.parametrize("count,entry", [(2, True), (5, True), (2, False), (5, False)])
def test_actual_http_planned_core_graphics_and_snapshot_keep_disclosure(household, monkeypatch, count, entry):
    page_id, payload = prepared(household, count, entry=entry)
    planned, schema, binding, wire = binding_and_wire(payload)
    before = copy.deepcopy(wire)
    calls = []
    http_mock(monkeypatch, wire, calls)
    config = _config("openrouter")
    config.max_output_tokens, config.reserve_micros = 8000, 250000
    config.input_per_million_micros, config.output_per_million_micros = 2000000, 10000000
    try:
        result = providers.request_provider(config, "unit", payload)
    except providers.ProviderError as error:
        pytest.fail(str(error.billing_result.telemetry if error.billing_result else str(error)))
    assert len(calls) == 1 and result.cost_micros == 1000 and wire == before
    assert calls[0]["max_tokens"] == 8000 and calls[0]["reasoning"]["effort"] == "medium"
    subset_record(calls[0]["response_format"]["json_schema"]["schema"])
    assert [q["answer"] for q in result.data["questions"]] == [q["answer"] for q in wire["questions"]]
    assert len(result.data["questions"]) == count
    assert schema["properties"]["questions"]["minItems"] == schema["properties"]["questions"]["maxItems"] == count
    intro = next(row for row in binding.candidates if row["disclosure"] == "given")
    assert intro["proof"]["pair"] == [2, 4]
    assert all(int(q["answer"]) not in {2, 4} for q in result.data["questions"])
    with DB.begin() as db:
        unit = LearningUnit(child_id=household[1]["id"], material_id=page_id, subject="Mathematik", topic="kgV",
            explanation=result.data["explanation"], questions=result.data["questions"], provider="fixture")
        db.add(unit)
        db.flush()
        db.add(UnitSource(unit_id=unit.id, material_id=page_id, revision=1))
        visual_references.remember(db, unit, result.data, planned)
        db.flush()
        snapshot = db.get(UnitVisualSnapshot, unit.id)
        assert snapshot.status == "ready", snapshot.reason
        assert snapshot.source_bindings[0]["material_id"] == page_id
        public = visual_references.projection(db, unit)
        assert len(public["explanation_steps"]) == 1
        assert all(step["disclosure"] == "given" for step in public["explanation_steps"])
        question = unit.questions[0]
        assert visual_references.question_projection(db, unit, question, closed=False, hints=3) == []
        solution = visual_references.question_projection(db, unit, question, closed=True, hints=0)
        assert len(solution) == 1
        assert "source_excerpt" not in json.dumps(solution)


@pytest.mark.parametrize("content", ["kgV von 3 und 4. Vielfache: 3, 6, 9, 12 und 4, 8, 12.",
    "Das kgV ist die größte positive Zahl, die durch beide Zahlen teilbar ist.",
    "Das kgV ist nicht die kleinste positive Zahl, die durch beide Zahlen teilbar ist."])
def test_missing_or_false_rule_refuses_before_any_http_with_zero_cancelled(household, monkeypatch, content):
    _, payload = prepared(household, content=content)
    def forbidden(*args, **kwargs):
        pytest.fail("An unsupported rule must not construct an HTTP client")
    monkeypatch.setattr(providers.httpx, "Client", forbidden)
    with pytest.raises(providers.ProviderError) as caught:
        providers.request_provider(_config("openrouter"), "unit", payload)
    assert str(caught.value) == multiples.RULE_ERROR
    assert caught.value.billing_result.cost_source == "cancelled" and caught.value.billing_result.cost_micros == 0


@pytest.mark.parametrize("fault", ["answer", "prompt", "step_id", "source", "reference", "version", "stage", "block", "two_panels", "intro_prose"])
def test_closed_binding_rejects_mixes_instead_of_repairing(household, fault):
    _, payload = prepared(household)
    planned, _, binding, wire = binding_and_wire(payload)
    original = copy.deepcopy(wire)
    question = wire["questions"][0]
    step = question["explanation_steps"][0]
    if fault == "answer":
        question["answer"] = "999"
    elif fault == "prompt":
        question["prompt"] += " Anderes Beispiel."
    elif fault == "step_id":
        step["id"] = "unbound"
    elif fault == "source":
        step["source_refs"] = ["p9"]
    elif fault == "reference":
        step["reference"] = {"id": "general.source_relation.phases", "version": 1}
    elif fault == "version":
        step["reference"]["version"] = True
    elif fault == "stage":
        step["disclosure"] = "given"
    elif fault == "block":
        step["presentation"]["blocks"] = ["unknown"]
    elif fault == "intro_prose":
        wire["explanation"] += " Die nächste Lösung ist " + question["answer"] + "."
    else:
        question["presentation"] = {"version": 1, "blocks": []}
    changed = copy.deepcopy(wire)
    with pytest.raises(ValueError):
        binding.hydrate(wire)
    assert wire == changed and json.dumps(original, sort_keys=True) != json.dumps(wire, sort_keys=True)
    assert multiples.prepare(planned) == planned


@pytest.mark.parametrize("fault", ["edge", "label", "number", "phase", "source_revision", "safe_content", "intro_as_solution"])
def test_independent_canonical_proof_recheck_rejects_changes(household, fault):
    _, payload = prepared(household)
    planned, _, binding, wire = binding_and_wire(payload)
    actual = schemas.UnitOutput.model_validate(binding.hydrate(wire)).model_dump(mode="json")
    question = actual["questions"][0]
    step = question["explanation_steps"][0]
    block = step["presentation"]["blocks"][0]
    if fault == "edge":
        block["scene"]["steps"][1]["edges"] = [{"start": "left", "end": "right", "label": "erfundene Beziehung"}]
    elif fault == "label":
        block["scene"]["objects"][0]["label"] = "Unbelegte Beschriftung"
    elif fault == "number":
        block["labels"][2] = "Kleinstes gemeinsames Vielfaches: 99"
    elif fault == "phase":
        block["scene"]["steps"][0]["highlight"] = ["common"]
    elif fault == "source_revision":
        planned["visual_context"]["sources"][0]["revision"] += 1
    elif fault == "safe_content":
        planned["visual_context"]["sources"][0]["content"] += " Geänderte Quelle."
    else:
        step = actual["explanation_steps"][0]
    with pytest.raises(ValueError):
        multiples.validate_step(step, planned["visual_context"], question)


def test_arithmetic_proves_minimality_and_keeps_all_original_scene_guards(household):
    _, payload = prepared(household)
    planned, _, binding, wire = binding_and_wire(payload)
    for row in binding.candidates:
        proof = row["proof"]
        a, b = proof["pair"]
        assert all(not phase["edges"] for phase in row["block"]["scene"]["steps"])
        assert row["block"]["scene"]["steps"][0]["highlight"] != row["block"]["scene"]["steps"][1]["highlight"]
        assert min(set(proof["left"]) & set(proof["right"])) == proof["result"]
        assert not any(number % a == number % b == 0 for number in range(1, proof["result"]))
    actual = binding.hydrate(wire)
    block = subject_content.Graphic.model_validate(actual["questions"][0]["explanation_steps"][0]["presentation"]["blocks"][0])
    from schulpilot.learning_scenes import validate
    with pytest.raises(ValueError):
        validate(block, actual["questions"][0], [RULE])
    with DB() as db:
        visual_references.validate_output(db, actual, planned)


def test_complete_history_not_bounded_prompt_context_controls_pool_and_publish(household):
    _, payload = prepared(household)
    planned, _, binding, wire = binding_and_wire(payload)
    chosen = planned[multiples.KEY]["tasks"][0]
    old = f"Bestimme das kgV von {multiples._pair_for_question(chosen)[1]} und {multiples._pair_for_question(chosen)[0]}."
    history = [old, *[f"Anderes früheres Beispiel {index}" for index in range(100)]]
    revised = multiples.prepare(multiples.with_history(payload, history))
    assert multiples._pair_for_question(chosen) not in {multiples._pair_for_question(task) for task in revised[multiples.KEY]["tasks"]}
    with pytest.raises(ValueError, match="keine neuen"):
        multiples.validate_history(planned, binding.hydrate(wire), history)
    exhausted = multiples.with_history(payload, [multiples._core("old", pair)["prompt"] for pair in multiples._pool()])
    with pytest.raises(ValueError, match="keine neuen"):
        multiples.prepare(exhausted)


@pytest.mark.parametrize("marker", ["goal", "review", "study_block", "selected_groups", "homework_practice", "exam_preparation", "exam_review_practice"])
def test_other_contracts_keep_their_original_path(household, marker):
    _, payload = prepared(household)
    payload.pop(multiples.HISTORY_KEY)
    payload[marker] = True
    assert multiples.prepare(payload) == payload
    assert multiples.bind_schema({"untouched": True}, payload) is None


def test_worker_publishes_ready_once_and_rechecks_history_under_child_lock(notebook, monkeypatch):
    identifier = notebook.refs[0]["id"]
    with DB.begin() as db:
        page = db.get(Material, identifier)
        page.topic = "kgV"
        page.content = RULE
    outputs, seen = [], []
    def model(config, function, payload, *args, **kwargs):
        assert function == "unit"
        planned, _, binding, wire = binding_and_wire(payload)
        seen.append(copy.deepcopy(planned))
        data = schemas.UnitOutput.model_validate(binding.hydrate(wire)).model_dump(mode="json")
        outputs.append(copy.deepcopy(data))
        return providers.Result(data, 100, 200, 1000, cost_source="reported")
    monkeypatch.setattr(worker, "request_provider", model)
    response = post(notebook, {"material_id": identifier, "notebook_sources": notebook.refs[:1], "question_count": 2},
        key="kgv-explicit-notebook-request-0001")
    assert response.status_code == 202, response.text
    job_id = response.json()["id"]
    with DB() as db:
        assert worker.claim(db) == job_id
    worker.process(job_id)
    with DB() as db:
        job = db.get(Job, job_id)
        assert job.status == "completed", job.error
        unit = db.get(LearningUnit, job.result["unit_id"])
        assert db.get(UnitVisualSnapshot, unit.id).status == "ready"
        assert len(unit.questions) == 2
        assert db.scalar(select(func.count()).select_from(UnitSource).where(UnitSource.unit_id == unit.id)) == 1
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        assert usage.cost_micros == 1000
    worker.process(job_id)
    assert len(seen) == len(outputs) == 1


PROCEDURE = ("Künstliche kgV-Lernseite\nkgV(3;4)=\n1. Schritt: Notiere die Vielfachenmengen!\n"
    "V3={3;6;9;12;15;}\nV4={4;8;12;16;}\n2. Schritt: Finde die kleinste gemeinsame Zahl!\n"
    "Teiler: Eigenständiger anderer Abschnitt, keine zusätzliche kgV-Regel.")


@pytest.mark.parametrize("notation", ["ascii", "subscript", "braced", "unicode", "latex"])
def test_two_step_source_procedure_has_exact_bounded_evidence_and_unmodified_indices(household, notation):
    content = PROCEDURE
    if notation == "subscript":
        content = content.replace("V3", "V_3").replace("V4", "V_4")
    elif notation == "braced":
        content = content.replace("V3", "V_{3}").replace("V4", "V_{4}")
    elif notation == "unicode":
        content = content.replace("V3", "V₃").replace("V4", "V₄")
    elif notation == "latex":
        content = content.replace("kgV(3;4)", r"\operatorname{kgV}\left(3;4\right)")
        content = content.replace("V3={", r"V_{3}=\left\{").replace("V4={", r"V_{4}=\left\{")
        content = content.replace(";}", r";\right\}")
    _, payload = prepared(household, content=content)
    before = copy.deepcopy(payload)
    planned, _, binding, wire = binding_and_wire(payload)
    rule = planned[multiples.KEY]["rule"]
    assert rule["method"] == "verified_two_step_multiples"
    assert rule["quote"] in content and "Teiler:" not in rule["quote"]
    assert rule["quote"] == multiples._algorithm_rule(content)
    assert payload == before
    assert (3, 4) not in {multiples._pair_for_question(task) for task in planned[multiples.KEY]["tasks"]}
    actual = schemas.UnitOutput.model_validate(binding.hydrate(wire)).model_dump(mode="json")
    multiples.validate_output(planned, actual)
    with DB() as db:
        visual_references.validate_output(db, actual, planned)


@pytest.mark.parametrize("change", ["wrong_list", "no_common", "wrong_step", "only_keywords", "superscript", "contradictory_result", "unknown_result"])
def test_two_step_rule_does_not_guess_or_promote_erroneous_work(household, change):
    content = PROCEDURE
    if change == "wrong_list":
        content = content.replace("3;6;9;12;15", "3;6;10;12;15")
    elif change == "no_common":
        content = content.replace("3;6;9;12;15", "3;6;9").replace("4;8;12;16", "4;8")
    elif change == "wrong_step":
        content = content.replace("kleinste gemeinsame Zahl", "irgendeine gemeinsame Zahl")
    elif change == "only_keywords":
        content = "kgV. Vielfache. Kleinste gemeinsame Zahl. V3={3;6;9;12;} V4={4;8;12;}"
    elif change == "contradictory_result":
        content = content.replace("kgV(3;4)=", "kgV(3;4)=24")
    elif change == "unknown_result":
        content = content.replace("kgV(3;4)=", "kgV(3;4)=unbekannt")
    else:
        content = content.replace("V3", "V³").replace("V4", "V⁴")
    _, payload = prepared(household, content=content)
    with pytest.raises(ValueError, match="Lehrgrundlage"):
        multiples.prepare(payload)


def test_own_source_revision_and_content_changes_hide_saved_graphic_not_questions(household):
    page_id, payload = prepared(household)
    planned, _, binding, wire = binding_and_wire(payload)
    actual = schemas.UnitOutput.model_validate(binding.hydrate(wire)).model_dump(mode="json")
    with DB.begin() as db:
        unit = LearningUnit(child_id=household[1]["id"], material_id=page_id, subject="Mathematik", topic="kgV",
            explanation=actual["explanation"], questions=actual["questions"], provider="fixture")
        db.add(unit)
        db.flush()
        visual_references.remember(db, unit, actual, planned)
        db.flush()
        assert db.get(UnitVisualSnapshot, unit.id).status == "ready"
        before = copy.deepcopy(unit.questions)
        source = db.get(Material, page_id)
        source.content += " Künstliche Änderung."
        source.revision += 1
        db.flush()
        view = visual_references.projection(db, unit)
        assert view["explanation_visual_status"] == "incomplete"
        assert view["explanation_visual_reason"] == "source_changed"
        assert visual_references.question_projection(db, unit, unit.questions[0], closed=True) == []
        assert unit.questions == before


def test_worker_missing_rule_is_cancelled_without_provider_or_new_unit(notebook, monkeypatch):
    identifier = notebook.refs[0]["id"]
    with DB.begin() as db:
        page = db.get(Material, identifier)
        page.topic = "kgV"
        page.content = "kgV. Vielfache von 3: 3, 6, 9. Vielfache von 4: 4, 8, 12."
    calls = []
    def forbidden(*args, **kwargs):
        calls.append(True)
        raise AssertionError("No provider request for missing teaching rule")
    monkeypatch.setattr(worker, "request_provider", forbidden)
    with DB() as db:
        before = db.scalar(select(func.count()).select_from(LearningUnit))
    response = post(notebook, {"material_id": identifier, "notebook_sources": notebook.refs[:1], "question_count": 2},
        key="kgv-missing-rule-request-0001")
    assert response.status_code == 202, response.text
    job_id = response.json()["id"]
    with DB() as db:
        assert worker.claim(db) == job_id
    worker.process(job_id)
    with DB() as db:
        job = db.get(Job, job_id)
        assert job.status == "failed" and job.error_code == "invalid_output" and job.error == multiples.RULE_ERROR
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        assert usage.cost_micros == 0 and usage.cost_source == "cancelled"
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == before
    assert calls == []


@pytest.mark.parametrize("prompt", ["Bestimme das kgV von 6 und 4.", "Berechne kgV(6;4).", r"Bestimme \operatorname{kgV}\left(6;4\right)."])
def test_semantic_history_accepts_sentence_punctuation_and_function_notation(prompt):
    assert multiples._pairs([prompt]) == {(4, 6)}
    assert multiples._pairs([prompt.replace("6", "6²")]) == set()


def test_worker_rechecks_new_semantic_history_before_publication_without_losing_attempts(notebook, monkeypatch):
    identifier = notebook.refs[0]["id"]
    with DB.begin() as db:
        page = db.get(Material, identifier)
        page.topic, page.content = "kgV", RULE
        old_attempts = [(row.id, row.answer, row.outcome) for row in db.scalars(select(Attempt).order_by(Attempt.id))]
        old_units = db.scalar(select(func.count()).select_from(LearningUnit))
    saved, calls = [], []
    def model(config, function, payload, *args, **kwargs):
        planned, _, binding, wire = binding_and_wire(payload)
        data = schemas.UnitOutput.model_validate(binding.hydrate(wire)).model_dump(mode="json")
        a, b = multiples._pair_for_question(data["questions"][0])
        old_question = {**data["questions"][0], "prompt": f"Bestimme kgV({b};{a})."}
        with DB.begin() as db:
            other = LearningUnit(child_id=notebook.child["id"], material_id=identifier, subject="Mathematik",
                topic="Künstliche parallel gespeicherte Runde", explanation="Altbestand bleibt erhalten.",
                questions=[old_question], status="completed", provider="fixture")
            db.add(other)
            db.flush()
            db.add(UnitSource(unit_id=other.id, material_id=identifier, revision=1))
            saved.append(other.id)
        calls.append(True)
        assert planned[multiples.KEY]["tasks"][0]["prompt"] != old_question["prompt"]
        return providers.Result(data, 100, 200, 1000, cost_source="reported")
    monkeypatch.setattr(worker, "request_provider", model)
    response = post(notebook, {"material_id": identifier, "notebook_sources": notebook.refs[:1], "question_count": 2},
        key="kgv-fresh-semantic-history-0001")
    assert response.status_code == 202, response.text
    job_id = response.json()["id"]
    with DB() as db:
        assert worker.claim(db) == job_id
    worker.process(job_id)
    with DB() as db:
        job = db.get(Job, job_id)
        assert job.status == "failed" and job.result is None
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == old_units + 1
        assert db.get(LearningUnit, saved[0]).status == "completed"
        assert [(row.id, row.answer, row.outcome) for row in db.scalars(select(Attempt).order_by(Attempt.id))] == old_attempts
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        assert usage.cost_micros == 1000 and usage.status == "failed_billed"
    assert len(calls) == 1


def test_two_step_explicit_correct_result_is_independently_verified(household):
    content = PROCEDURE.replace("kgV(3;4)=", "kgV(3;4)=12")
    _, payload = prepared(household, content=content)
    planned = multiples.prepare(payload)
    assert "kgV(3;4)=12" in planned[multiples.KEY]["rule"]["quote"]
    assert planned[multiples.KEY]["rule"]["method"] == "verified_two_step_multiples"


def test_canonical_legacy_intro_prose_cannot_disclose_a_pending_answer(household):
    _, payload = prepared(household)
    planned, _, binding, wire = binding_and_wire(payload)
    data = schemas.UnitOutput.model_validate(binding.hydrate(wire)).model_dump(mode="json")
    data["explanation"] += " Die nächste Lösung ist " + data["questions"][0]["answer"] + "."
    with pytest.raises(ValueError):
        multiples.validate_output(planned, data)
