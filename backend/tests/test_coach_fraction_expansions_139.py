"""Artificial goal-bound expansion follow-ups; actual mock HTTP, zero vendors."""
import copy
import json
import socket

import httpx
import pytest
from schulpilot import coach_fraction_expansions as expansion
from schulpilot import coaching, providers, schemas, subject_content, visual_references
from schulpilot.db import DB, Attempt, Child, Family, Job, LearningUnit, Material, ProviderConfig, UnitCoaching, Usage
from schulpilot.graphic_schema import bind_coherent_graphics
from schulpilot.math_tasks import _task, fraction_tasks
from schulpilot.visual_reference_models import UnitVisualSnapshot
from sqlalchemy import func, select
from test_coaching import finish, process_next
from test_coaching import normal_unit as normal_unit
from test_graphic_native_transport import subset_record
from test_presentation_capability_paths import _config

RULE = "Beim Erweitern multiplizierst du Zähler und Nenner mit derselben Zahl."
CONTENT = RULE + " Originalbrüche: 1/5 und 2/7."


@pytest.fixture(autouse=True)
def no_network(monkeypatch):
    def refuse(*args, **kwargs):
        raise AssertionError("No external network in artificial expansion tests")

    monkeypatch.setattr(socket.socket, "connect", refuse)
    monkeypatch.setattr(socket, "getaddrinfo", refuse)


def planned_tasks(payload):
    inputs = expansion.planning_inputs(payload)
    phase = "understand" if payload["practice_kind"] == "repair" else "recall"
    previous = payload.get("previous_prompts") or []
    tasks = providers.practice_tasks(payload)
    return fraction_tasks(payload["materials"], "Mathematik", payload["required_topic"], previous, phase, 2,
        json.dumps([phase, payload["required_topic"], previous], ensure_ascii=False),
        required_labels=[task["label"] for task in tasks],
        excluded_prompts=inputs["excluded_prompts"], expansion_denominator_limit=inputs["denominator_limit"])


def binding_wire(payload):
    planned = {**payload, "math_tasks": planned_tasks(payload)}
    schema = providers.strict_schema(schemas.PracticeUnitOutput, preserve_limits=True)
    subject_content.bind_graphic_schema(schema, ["Mathematik"])
    bind_coherent_graphics(schema)
    providers.indexed_choice_schema(schema, bounded_matches=True)
    providers.bind_practice_tasks(schema, providers.practice_tasks(planned))
    providers.bind_math_tasks(schema, planned["math_tasks"])
    visual_references.bind_schema(schema, planned)
    binding = expansion.bind_schema(schema, planned)
    assert binding is not None

    def step(candidate):
        return {"id": candidate["id"], "text": candidate["text"], "competence_id": None,
            "disclosure": candidate["disclosure"], "reference": copy.deepcopy(candidate["reference"]),
            "source_refs": copy.deepcopy(candidate["source_refs"]), "presentation": {
                "version": 1, "evidence_kind": "knowledge", "blocks": [candidate["id"]]}}

    questions = []
    for task in providers.practice_tasks(payload):
        candidate = next(row for row in binding.candidates if row.get("proof", {}).get("task", {}).get("id") == task["id"])
        questions.append({**copy.deepcopy(candidate["proof"]["task"]),
            "hints": ["Multipliziere oben und unten mit derselben Zahl."],
            "explanation": "Die Menge bleibt gleich; die Teile werden feiner.",
            "explanation_steps": [step(candidate)], "presentation": None, "field_group": None})
    intro = next(row for row in binding.candidates if row["disclosure"] == "given")
    wire = {"subject": "Mathematik", "topic": payload["required_topic"],
        "explanation": "Beim Erweitern wird die Einteilung feiner. Die Menge bleibt gleich.",
        "explanation_steps": [step(intro)], "questions": questions}
    return planned, schema, binding, wire


def prepared(household, action="repair", two_focus=False):
    with DB.begin() as db:
        child = db.get(Child, household[1]["id"])
        page = Material(child_id=child.id, title="Künstliche Erweiterungsregel", subject="Mathematik",
            topic="Brüche erweitern", content=CONTENT, confirmed=True, status="confirmed")
        db.add(page)
        db.flush()
        payload = {"grade": 6, "review": True, "practice_kind": action, "required_subject": "Mathematik",
            "required_topic": page.topic, "materials": [{"subject": "Mathematik", "topic": page.topic, "content": CONTENT}],
            "material": {"subject": "Mathematik", "topic": page.topic, "content": CONTENT}, "previous_prompts": [],
            "learning_goals": [{"id": key, "label": "Brüche erweitern", "source_excerpt": RULE}
                for key in (["g1", "g2"] if two_focus else ["g1"])],
            "focus_goal_ids": ["g1", "g2"] if two_focus else ["g1"]}
        payload = visual_references.with_visual_context(db, child, payload, [page])
        payload = expansion.with_history(payload, [])
        page_id = page.id
    return page_id, payload, *binding_wire(payload)


def http_mock(monkeypatch, wire, calls):
    real = httpx.Client

    def handler(request):
        calls.append(json.loads(request.content))
        return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {"content": json.dumps(wire)}}],
            "usage": {"prompt_tokens": 16694, "completion_tokens": 2290, "cost": .056288}})

    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real(transport=httpx.MockTransport(handler)))


@pytest.mark.parametrize("action,two_focus", [("repair", False), ("repair", True), ("check", False), ("check", True)])
def test_actual_native_request_closes_goal_math_graphics_sources_and_saved_disclosure(household, monkeypatch, action, two_focus):
    page_id, payload, planned, _, binding, wire = prepared(household, action, two_focus)
    calls = []
    http_mock(monkeypatch, wire, calls)
    config = _config("openrouter")
    config.max_output_tokens, config.reserve_micros = 8000, 250000
    config.input_per_million_micros, config.output_per_million_micros = 2000000, 10000000
    result = providers.request_provider(config, "unit", payload)
    assert len(calls) == 1 and result.cost_source == "reported" and result.cost_micros == 56288
    assert result.input_tokens == 16694 and result.output_tokens == 2290
    sent = calls[0]["response_format"]["json_schema"]["schema"]
    subset_record(sent)
    assert sent["properties"]["questions"]["minItems"] == sent["properties"]["questions"]["maxItems"] == 2
    assert expansion.REVISION in calls[0]["messages"][0]["content"]
    outgoing = json.loads(calls[0]["messages"][1]["content"][0]["text"])
    assert outgoing["prepared_graphics"]["revision"] == expansion.REVISION
    assert expansion.HISTORY not in outgoing
    prescribed = providers.practice_tasks(payload)
    for question, task, fixed in zip(result.data["questions"], planned["math_tasks"], prescribed, strict=True):
        assert {key: question[key] for key in ("id", "type", "prompt", "answer", "options", "accepted")} == {
            key: task[key] for key in ("id", "type", "prompt", "answer", "options", "accepted")}
        assert question["learning_goal_id"] == fixed["learning_goal_id"]
        candidate = next(row for row in binding.candidates if binding.question_bound(row, question))
        blocks = question["explanation_steps"][0]["presentation"]["blocks"]
        assert [block["numbers"] for block in blocks] == [candidate["proof"]["input"], candidate["proof"]["output"]]
        assert all(block["disclosure"] == "solution" for block in blocks)
        assert blocks[0]["numbers"][0] * blocks[1]["numbers"][1] == blocks[1]["numbers"][0] * blocks[0]["numbers"][1]
        assert max(blocks[1]["numbers"]) <= 24
        assert question["answer"] == "/".join(str(int(value)) for value in blocks[1]["numbers"])
    expansion.validate_practice_history(payload, result.data, [])
    with DB.begin() as db:
        visual_references.validate_output(db, result.data, payload)
        unit = LearningUnit(child_id=household[1]["id"], material_id=page_id, subject="Mathematik", topic="Brüche erweitern",
            explanation=result.data["explanation"], questions=result.data["questions"], provider="synthetic", model="own-fixture")
        db.add(unit)
        db.flush()
        visual_references.remember(db, unit, result.data, payload)
        db.flush()
        snapshot = db.get(UnitVisualSnapshot, unit.id)
        assert snapshot.status == "ready"
        assert all(not visual_references.public_steps(steps) for steps in snapshot.question_steps.values())
        assert all(len(visual_references.public_steps(steps, closed=True)) == 1 for steps in snapshot.question_steps.values())


@pytest.mark.parametrize("fault", ["task", "goal", "answer", "ref", "version", "source", "stage", "step_id", "text", "foreign"])
def test_provider_cannot_substitute_arithmetic_goals_or_graphic_contract(household, monkeypatch, fault):
    _, payload, _, _, _, wire = prepared(household, two_focus=True)
    question = wire["questions"][0]
    step = question["explanation_steps"][0]
    if fault == "task":
        question["prompt"] += " Noch eine Rechnung."
    elif fault == "goal":
        question["learning_goal_id"] = "g2"
    elif fault == "answer":
        question["answer"] = "1/2"
    elif fault == "ref":
        step["reference"]["id"] = "math.fraction.part_whole"
    elif fault == "version":
        step["reference"]["version"] = 2
    elif fault == "source":
        step["source_refs"] = ["p2"]
    elif fault == "stage":
        step["disclosure"] = "given"
    elif fault == "step_id":
        step["id"] = "foreign"
    elif fault == "text":
        step["text"] += " Ein erfundener Faktor."
    else:
        step["presentation"]["blocks"] = ["cf_foreign"]
    calls = []
    http_mock(monkeypatch, wire, calls)
    with pytest.raises(providers.ProviderError) as error:
        providers.request_provider(_config("openrouter"), "unit", payload)
    assert len(calls) == 1 and error.value.billing_result.cost_source == "reported"
    assert error.value.billing_result.cost_micros == 56288


@pytest.mark.parametrize("fault", ["pair", "factor", "order", "extra_block", "revision", "source_text", "digest", "goal", "prompt"])
def test_saved_proof_rejects_changed_parameters_sources_or_scope(household, fault):
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
    elif fault == "revision":
        context["sources"][0]["revision"] += 1
    elif fault == "source_text":
        context["sources"][0]["content"] += " Andere Quelle."
    elif fault == "digest":
        next(ref for ref in context["references"] if ref["id"] == "math.fraction.expansion")["digest"] = "0" * 64
    elif fault == "goal":
        question["learning_goal_id"] = "g2"
    else:
        question["prompt"] = "Kürze den Bruch 2/4."
    with DB() as db, pytest.raises(ValueError):
        visual_references.validate_steps(db, [step], "Mathematik", context, question=question)


@pytest.mark.parametrize("fault", ["missing", "revision", "digest", "bool", "duplicate", "unknown"])
def test_malformed_or_stale_history_refuses_before_http_with_cancelled_billing(household, monkeypatch, fault):
    _, payload, _, _, _, _ = prepared(household)
    if fault == "missing":
        payload.pop(expansion.HISTORY)
    elif fault == "revision":
        payload["visual_context"]["sources"][0]["revision"] += 1
    elif fault == "digest":
        payload[expansion.HISTORY]["source_digest"] = "0" * 64
    elif fault == "bool":
        payload[expansion.HISTORY]["signatures"] = [[True, 3, 2]]
    elif fault == "duplicate":
        payload[expansion.HISTORY]["signatures"] = [[1, 3, 2], [1, 3, 2]]
    else:
        payload = expansion.with_history(payload, ["Erweitere einen Bruch mit einer geeigneten Zahl."])
    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: pytest.fail("No HTTP for invalid preflight"))
    with pytest.raises(providers.ProviderError) as error:
        providers.request_provider(_config("openrouter"), "unit", payload)
    assert error.value.billing_result.cost_micros == 0 and error.value.billing_result.cost_source == "cancelled"


@pytest.mark.parametrize("fault", ["study", "notebook", "homework", "exam", "not_review", "other_goal", "other_subject", "source_quote"])
def test_unrelated_contracts_keep_schema_and_do_not_gain_proof(household, fault):
    _, _, planned, schema, _, _ = prepared(household)
    if fault == "study":
        planned["study_block"] = {"mode": "apply"}
    elif fault == "notebook":
        planned["notebook_practice"] = {"version": 1, "question_count": 2}
    elif fault == "homework":
        planned["homework_practice"] = True
    elif fault == "exam":
        planned["exam_preparation"] = True
    elif fault == "not_review":
        planned["review"] = False
    elif fault == "other_goal":
        planned["learning_goals"][0]["label"] = "Brüche kürzen"
    elif fault == "other_subject":
        planned["required_subject"] = "Deutsch"
    else:
        planned["learning_goals"][0]["source_excerpt"] = "Erfundene Regel."
    before = copy.deepcopy(schema)
    assert expansion.bind_schema(schema, planned) is None and schema == before


def test_complete_history_excludes_older_signatures_and_postcall_collision(household):
    _, payload, _, _, _, _ = prepared(household)
    old_prompt, _ = _task("expand", (1, 3, 2), "apply")
    payload = expansion.with_history(payload, [old_prompt, *("Andere Frage." for _ in range(150))])
    assert payload[expansion.HISTORY]["signatures"] == [[1, 3, 2]]
    planned, _, binding, wire = binding_wire(payload)
    assert all("1/3 mit dem Faktor 2." not in question["prompt"] for question in planned["math_tasks"])
    data = binding.hydrate(wire)
    expansion.validate_practice_history(payload, data, [old_prompt])
    with pytest.raises(ValueError) as error:
        expansion.validate_practice_history(payload, data, [old_prompt, data["questions"][0]["prompt"]])
    assert error.value.args == (expansion.CURRENT_ERROR,)


def test_preplanned_oversized_task_is_not_replaced_and_never_sent(household, monkeypatch):
    _, payload, _, _, _, _ = prepared(household)
    prompt, answer = _task("expand", (8, 9, 4), "understand")
    task = {"id": "q1", "type": "short", "prompt": prompt, "answer": answer, "options": [], "accepted": [], "source_excerpt": RULE}
    from schulpilot import math_tasks

    monkeypatch.setattr(math_tasks, "fraction_tasks", lambda *a, **kw: [copy.deepcopy(task), {**copy.deepcopy(task), "id": "q2"}])
    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: pytest.fail("No HTTP for unrepresentable task"))
    with pytest.raises(providers.ProviderError) as error:
        providers.request_provider(_config("openrouter"), "unit", payload)
    assert error.value.billing_result.cost_source == "cancelled" and error.value.billing_result.cost_micros == 0


def test_arithmetic_proof_independently_rejects_a_regressed_planner_answer(household, monkeypatch):
    _, _, planned, _, binding, _ = prepared(household)
    candidate = next(row for row in binding.candidates if row.get("proof"))
    task = {**candidate["proof"]["task"], "answer": "1/2"}
    original = expansion._task
    monkeypatch.setattr(expansion, "_task", lambda *args: (original(*args)[0], "1/2"))
    assert expansion._candidate(planned["visual_context"], task, "understand") is None


def test_existing_exact_reference_is_reused_without_duplicate_or_source_mutation(household):
    _, payload, _, _, _, _ = prepared(household)
    before = copy.deepcopy(payload)
    with DB() as db:
        assert expansion.add_reference(db, payload) is payload
        assert expansion.add_reference(db, payload) is payload
    assert payload == before
    assert len([ref for ref in payload["visual_context"]["references"] if ref["id"] == "math.fraction.expansion"]) == 1


@pytest.mark.parametrize("field,value", [("digest", "0" * 64), ("kind", "scene"), ("subject", "Deutsch")])
def test_existing_conflicting_reference_is_rejected_instead_of_appending(household, field, value):
    _, payload, _, _, _, _ = prepared(household)
    next(ref for ref in payload["visual_context"]["references"] if ref["id"] == "math.fraction.expansion")[field] = value
    before = copy.deepcopy(payload)
    with DB() as db, pytest.raises(ValueError) as error:
        expansion.add_reference(db, payload)
    assert error.value.args == (expansion.ERROR,) and payload == before


@pytest.mark.parametrize("fault", ["missing_reference", "missing_literal_introduction", "finite_pool_used"])
def test_unavailable_complete_proof_or_pool_is_rejected_before_http(household, monkeypatch, fault):
    _, payload, _, _, _, _ = prepared(household)
    if fault == "missing_reference":
        payload["visual_context"]["references"] = [ref for ref in payload["visual_context"]["references"]
            if ref["id"] != "math.fraction.expansion"]
    elif fault == "missing_literal_introduction":
        payload["visual_context"]["sources"][0]["content"] = RULE
        payload["materials"][0]["content"] = RULE
        payload["material"]["content"] = RULE
        payload = expansion.with_history(payload, [])
    else:
        payload = expansion.with_history(payload, [_task("expand", values, "apply")[0] for values in expansion._pool()])
    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: pytest.fail("No HTTP without a full fresh proof"))
    with pytest.raises(providers.ProviderError) as error:
        providers.request_provider(_config("openrouter"), "unit", payload)
    assert error.value.billing_result.cost_source == "cancelled" and error.value.billing_result.cost_micros == 0


@pytest.fixture
def expansion_review(normal_unit, monkeypatch):
    client, unit_id, page_id, parent, kid = normal_unit
    with DB.begin() as db:
        page, unit = db.get(Material, page_id), db.get(LearningUnit, unit_id)
        page.content, page.topic = CONTENT, "Brüche erweitern"
        unit.topic = page.topic
        questions = []
        for index, values in enumerate(((1, 3, 2), (2, 5, 3))):
            prompt, answer = _task("expand", values, "apply")
            questions.append({"id": f"q{index + 1}", "type": "short", "prompt": prompt, "answer": answer,
                "options": [], "accepted": [], "hints": ["Oben und unten gleich multiplizieren."],
                "explanation": "Die Menge bleibt gleich.", "learning_goal_id": "g1"})
        unit.questions = questions

    def review(config, function, payload):
        assert function == "coach" and payload["defer_practice"] is True
        with DB() as db:
            result = coaching.synthetic_report(db, db.get(LearningUnit, unit_id), payload["next_action"])
            result["next_unit"] = None
        return providers.Result(result, 100, 100, 0)

    monkeypatch.setattr(coaching, "request_provider", review)
    finish(client, unit_id, help_first=True)
    process_next()
    _config("openrouter")
    with DB.begin() as db:
        config = db.get(ProviderConfig, 1)
        config.max_output_tokens, config.reserve_micros = 8000, 250000
        db.get(Family, parent["families"][0]["id"]).budget_micros = 1000000
        item = db.get(UnitCoaching, unit_id)
        assert item.status == "ready" and item.report["practice_deferred"] and item.decision == "repair"
    monkeypatch.setattr(coaching, "request_provider", providers.request_provider)
    return client, unit_id, page_id, kid


def preserved(db, unit_id):
    return {"questions": copy.deepcopy(db.get(LearningUnit, unit_id).questions),
        "report": copy.deepcopy(db.get(UnitCoaching, unit_id).report),
        "attempts": [(row.id, row.question_id, row.answer, row.outcome, row.assisted)
            for row in db.scalars(select(Attempt).where(Attempt.unit_id == unit_id).order_by(Attempt.id))]}


@pytest.mark.parametrize("race", ["none", "source", "history"])
def test_actual_worker_publishes_once_and_rejects_source_or_history_race_with_report_preserved(expansion_review, monkeypatch, race):
    client, unit_id, page_id, kid = expansion_review
    from test_coaching_stages import ask_practice

    job_id = ask_practice(client, unit_id, "explicit-artificial-expansion-139")
    assert ask_practice(client, unit_id, "explicit-artificial-expansion-139") == job_id
    with DB() as db:
        before = preserved(db, unit_id)
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 1
        assert db.get(Job, job_id).payload["practice_number"] == 1
    calls, collision, local_payloads = [], [], []
    original_history = coaching._practice_history_prompts

    def model(config, function, payload):
        local_payloads.append(copy.deepcopy(payload))
        return providers.request_provider(config, function, payload)

    monkeypatch.setattr(coaching, "request_provider", model)

    def history(db, unit):
        return [*original_history(db, unit), *collision]

    monkeypatch.setattr(coaching, "_practice_history_prompts", history)
    real = httpx.Client

    def handler(request):
        body = json.loads(request.content)
        calls.append(body)
        payload = json.loads(body["messages"][1]["content"][0]["text"])
        assert expansion.HISTORY not in payload
        assert local_payloads[0][expansion.HISTORY]["signatures"] == [[1, 3, 2], [2, 5, 3]]
        _, _, _, wire = binding_wire(local_payloads[0])
        if catalog := payload.get("catalog_context"):
            wire["catalog_assignment"] = {"subject_ids": [catalog["subject_aliases"]["mathematik"]],
                "matches": [], "unmatched_context_refs": catalog["context_refs"]}
        if race == "source":
            with DB.begin() as db:
                page = db.get(Material, page_id)
                page.content += " Neue geprüfte Notiz."
                page.revision += 1
        elif race == "history":
            collision.append(wire["questions"][0]["prompt"])
        return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {"content": json.dumps(wire)}}],
            "usage": {"prompt_tokens": 16694, "completion_tokens": 2290, "cost": .056288}})

    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real(transport=httpx.MockTransport(handler)))
    process_next()
    with DB() as db:
        job = db.get(Job, job_id)
        item = db.get(UnitCoaching, unit_id)
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        assert len(calls) == 1 and usage.cost_micros == 56288 and usage.cost_source == "reported"
        assert db.get(LearningUnit, unit_id).questions == before["questions"]
        assert preserved(db, unit_id)["attempts"] == before["attempts"]
        if race == "none":
            assert job.status == "completed" and item.next_unit_id and usage.status == "completed"
            new = db.get(LearningUnit, item.next_unit_id)
            assert new.child_id == kid["id"] and new.status == "not_started" and new.round_kind == "repair"
            assert len(new.questions) == 2 and db.get(UnitVisualSnapshot, new.id).status == "ready"
            assert db.scalar(select(func.count()).select_from(LearningUnit)) == 2
        else:
            assert job.status == "failed" and item.next_unit_id is None and usage.status == "failed_billed"
            assert preserved(db, unit_id) == before
            assert db.scalar(select(func.count()).select_from(LearningUnit)) == 1
            if race == "history":
                assert job.error == expansion.CURRENT_ERROR
