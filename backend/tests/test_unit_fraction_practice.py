"""Actual focused-practice adapter with artificial sources and zero vendor calls."""
import copy
import json

import httpx
import pytest
from schulpilot import coaching, providers, schemas, visual_references
from schulpilot import unit_fraction_compositions as compositions
from schulpilot.db import DB, Attempt, Child, LearningUnit, Material, UnitCoaching, UnitSource, now
from test_graphic_native_transport import subset_record
from test_presentation_capability_paths import _config

METHOD = "Unechte Brüche als gemischte Zahlen darstellen."
CONTENT = METHOD + " Zähler und Nenner notieren. Beispiele: 9/4 = 2 + 1/4; 7/3 = 2 + 1/3."


def setup_practice(household, *, two_focus=False, action="repair"):
    with DB.begin() as db:
        child = db.get(Child, household[1]["id"])
        material = Material(child_id=child.id, title="Künstliche Anschlussquelle", subject="Mathematik",
            topic="Unechte Brüche als gemischte Zahlen", content=CONTENT, confirmed=True, status="confirmed")
        db.add(material)
        db.flush()
        goals = [{"id": "g1", "label": "Unechte Brüche in gemischte Zahlen umwandeln" if two_focus
                  else "Einen Bruch mit Zähler und Nenner notieren", "source_excerpt": METHOD if two_focus
                  else "Zähler und Nenner notieren."},
            {"id": "g2", "label": METHOD, "source_excerpt": METHOD}]
        questions = [{"id": "old1", "type": "short", "prompt": "Notiere den Bruch zwei Drittel.",
            "answer": "2/3", "accepted": [], "options": [], "hints": ["Notiere beide Zahlen."],
            "explanation": "Zwei Drittel.", "learning_goal_id": "g1"},
            {"id": "old2", "type": "short", "prompt": "Schreibe 11/4 als gemischte Zahl.",
             "answer": "2¾", "accepted": [], "options": [], "hints": ["Bündele volle Ganze."],
             "explanation": "Zwei Ganze und drei Viertel.", "learning_goal_id": "g2"}]
        unit = LearningUnit(child_id=child.id, material_id=material.id, subject=material.subject,
            topic=material.topic, explanation="Künstliche vorherige Einführung.", questions=questions,
            status="completed", completed=int(now()), provider="synthetic", model="own-fixture")
        db.add(unit)
        db.flush()
        db.add(UnitSource(unit_id=unit.id, material_id=material.id, revision=material.revision))
        db.add(UnitCoaching(unit_id=unit.id, status="ready", decision=action,
            report={"learning_goals": goals, "question_reviews": []}))
        db.add_all([Attempt(unit_id=unit.id, question_id=q["id"], answer=q["answer"], outcome="correct",
            assisted=two_focus or q["id"] == "old2") for q in questions])
        db.flush()
        _, payload, sources = coaching.context(db, unit)
        focus = coaching.focus_ids(db, unit, action)
        payload.update(review=True, practice_kind=action, focus_goal_ids=focus,
            material={"subject": unit.subject, "topic": unit.topic, "content": CONTENT})
        payload.pop("completed_questions", None)
        payload = visual_references.with_visual_context(db, child, payload,
            [db.get(Material, source["id"]) for source in sources])
        unit_id = unit.id
    schema = providers.strict_schema(schemas.PracticeUnitOutput, preserve_limits=True)
    providers.indexed_choice_schema(schema, bounded_matches=True)
    providers.bind_practice_tasks(schema, providers.practice_tasks(payload))
    visual_references.bind_schema(schema, payload)
    binding = compositions.bind_schema(schema, payload)
    assert binding is not None

    def step(candidate):
        return {"id": candidate["id"], "text": candidate["text"], "competence_id": None,
            "disclosure": candidate["disclosure"], "reference": copy.deepcopy(candidate["reference"]),
            "source_refs": copy.deepcopy(candidate["source_refs"]),
            "presentation": {"version": 1, "evidence_kind": "knowledge", "blocks": [candidate["id"]]}}

    new_questions = []
    for task, (literal, answer) in zip(providers.practice_tasks(payload), [("9/4", "2¼"), ("7/3", "2⅓")], strict=True):
        question = schemas.PracticeQuestion.model_validate({"id": task["id"], "learning_goal_id": task["learning_goal_id"],
            "type": "short", "prompt": "Schreibe " + literal + " als gemischte Zahl.", "answer": answer,
            "options": [], "accepted": [], "hints": ["Bündele vollständige Ganze."],
            "explanation": "Bestimme die vollständigen Ganzen und den Rest."}).model_dump(mode="json")
        candidate = next(c for c in binding.candidates if c["disclosure"] == "solution" and binding.question_bound(c, question))
        question["explanation_steps"] = [step(candidate)]
        new_questions.append(question)
    intro = next(c for c in binding.candidates if c["disclosure"] == "given")
    wire = {"subject": payload["required_subject"], "topic": payload["required_topic"],
        "explanation": "Bündele vollständige Ganze, dann betrachte den Rest.",
        "explanation_steps": [step(intro)], "questions": new_questions}
    return unit_id, payload, binding, wire


@pytest.mark.parametrize("action,two_focus", [("repair", False), ("repair", True), ("check", True)])
def test_actual_focused_practice_http_keeps_two_task_ids_goal_pairs_answers_and_novelty(household, monkeypatch, action, two_focus):
    unit_id, payload, binding, wire = setup_practice(household, two_focus=two_focus, action=action)
    assert payload["focus_goal_ids"] == (["g1", "g2"] if two_focus else ["g2"])
    requests = []
    real = httpx.Client

    def handler(request):
        requests.append(json.loads(request.content))
        return httpx.Response(200, json={"choices": [{"message": {"content": json.dumps(wire)}, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": 100, "completion_tokens": 500, "cost": .001}})

    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real(transport=httpx.MockTransport(handler)))
    result = providers.request_provider(_config("openrouter"), "unit", payload)
    assert len(requests) == 1 and len(result.data["questions"]) == 2
    pairs = {(q["id"], q["learning_goal_id"]) for q in result.data["questions"]}
    assert pairs == {(t["id"], t["learning_goal_id"]) for t in providers.practice_tasks(payload)}
    assert [(q["prompt"], q["answer"]) for q in result.data["questions"]] == [(q["prompt"], q["answer"]) for q in wire["questions"]]
    assert result.cost_source == "reported" and result.cost_micros == 1000
    assert [b["numbers"] for b in result.data["questions"][0]["explanation_steps"][0]["presentation"]["blocks"]] == [[4, 4], [4, 4], [1, 4]]
    outbound = requests[0]["response_format"]["json_schema"]["schema"]
    subset_record(outbound)
    assert outbound["properties"]["questions"]["minItems"] == outbound["properties"]["questions"]["maxItems"] == 2
    assert compositions.REVISION in requests[0]["messages"][0]["content"]
    with DB() as db:
        previous = db.get(LearningUnit, unit_id)
        coaching.validate_new_round(db, previous, result.data, desired_ids=payload["focus_goal_ids"])
        visual_references.validate_output(db, result.data, payload)
        changed = copy.deepcopy(result.data)
        changed["questions"][0]["prompt"] = previous.questions[1]["prompt"]
        with pytest.raises(providers.ProviderError, match="wiederholt"):
            coaching.validate_new_round(db, previous, changed, desired_ids=payload["focus_goal_ids"])
    config = _config("openrouter")
    config.max_output_tokens, config.reserve_micros = 8000, 250000
    config.input_per_million_micros, config.output_per_million_micros = 2000000, 10000000
    from schulpilot.provider_cost_preflight import projection

    text_bytes = sum(len(x.encode()) for x in [requests[0]["messages"][0]["content"],
        requests[0]["messages"][1]["content"][0]["text"], json.dumps(outbound)])
    estimated = projection(config, "unit", text_bytes, None, 0)
    assert estimated["projected_micros"] <= 250000
    from pathlib import Path

    Path("/tmp/schulpilot127-practice-wire-" + action + "-" + str(two_focus) + ".json").write_text(json.dumps(
        {"text_bytes": text_bytes, "projected_micros": estimated["projected_micros"], "reserve": 250000,
         "output_cap": 8000, "mock_requests": len(requests), "actual_vendor_calls": 0}, indent=2))


@pytest.mark.parametrize("fault", ["given", "foreign_id", "source_refs", "goal_pair", "count"])
def test_wrong_practice_scope_is_rejected_once_with_known_mock_billing(household, monkeypatch, fault):
    _, payload, _, wire = setup_practice(household)
    target = wire["questions"][0]["explanation_steps"][0]
    if fault == "given":
        target["disclosure"] = "given"
    elif fault == "foreign_id":
        target["presentation"]["blocks"] = ["uc_unrelated"]
    elif fault == "source_refs":
        target["source_refs"] = ["p999"]
    elif fault == "goal_pair":
        wire["questions"][0]["learning_goal_id"] = "g1"
    else:
        wire["questions"].pop()
    calls = []
    real = httpx.Client

    def handler(request):
        calls.append(request)
        return httpx.Response(200, json={"choices": [{"message": {"content": json.dumps(wire)}, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": 100, "completion_tokens": 500, "cost": .001}})

    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real(transport=httpx.MockTransport(handler)))
    with pytest.raises(providers.ProviderError) as error:
        providers.request_provider(_config("openrouter"), "unit", payload)
    assert len(calls) == 1
    assert error.value.billing_result.cost_source == "reported" and error.value.billing_result.cost_micros == 1000


@pytest.mark.parametrize("fault", ["other_review", "not_true", "no_focus", "unknown_goal", "duplicate_goal", "different_skill",
    "addition", "addition_and_conversion", "conversion_and_addition", "reverse_conversion",
    "unquoted_goal", "foreign_subject", "study_block", "homework_practice", "exam_preparation", "exam_review_practice"])
def test_other_review_or_contract_never_gets_the_composition_binder(household, fault):
    _, payload, _, _ = setup_practice(household)
    payload = copy.deepcopy(payload)
    if fault == "other_review":
        payload["practice_kind"] = "spaced_review"
    elif fault == "not_true":
        payload["review"] = "true"
    elif fault == "no_focus":
        payload["focus_goal_ids"] = []
    elif fault == "unknown_goal":
        payload["focus_goal_ids"] = ["g4"]
    elif fault == "duplicate_goal":
        payload["focus_goal_ids"] = ["g2", "g2"]
    elif fault == "different_skill":
        payload["focus_goal_ids"] = ["g1"]
    elif fault in ("addition", "addition_and_conversion", "conversion_and_addition", "reverse_conversion"):
        payload["learning_goals"][1]["label"] = {
            "addition": "Unechte Brüche addieren",
            "addition_and_conversion": "Unechte Brüche addieren und als gemischte Zahlen darstellen",
            "conversion_and_addition": "Unechte Brüche als gemischte Zahlen darstellen und addieren",
            "reverse_conversion": "Gemischte Zahlen als unechte Brüche darstellen",
        }[fault]
    elif fault == "unquoted_goal":
        payload["learning_goals"][1]["source_excerpt"] = "Nicht im bestätigten Material."
    elif fault == "foreign_subject":
        payload["required_subject"] = "Deutsch"
    else:
        payload[fault] = {"question_count": 2} if fault == "study_block" else True
    schema = providers.strict_schema(schemas.PracticeUnitOutput, preserve_limits=True)
    assert compositions.bind_schema(schema, payload) is None
    payload["visual_context"]["references"] = [r for r in payload["visual_context"]["references"] if r["id"] != compositions.RECIPE]
    with DB() as db:
        result = compositions.add_reference(db, payload)
    assert not any(r["id"] == compositions.RECIPE for r in result["visual_context"]["references"])


@pytest.mark.parametrize("already_planned", ["addition", "conversion"])
def test_existing_math_task_plan_and_all_fixed_schema_fields_are_untouched(household, already_planned):
    _, payload, _, _ = setup_practice(household)
    examples = [{"id": "q1", "type": "short", "prompt": "Addiere 1/2 und 1/3.", "answer": "5/6"},
        {"id": "q2", "type": "short", "prompt": "Addiere 1/4 und 1/3.", "answer": "7/12"}]
    if already_planned == "conversion":
        examples = [{"id": "q1", "type": "short", "prompt": "Schreibe 9/4 als gemischte Zahl.", "answer": "2¼"},
            {"id": "q2", "type": "short", "prompt": "Schreibe 7/3 als gemischte Zahl.", "answer": "2⅓"}]
    payload["math_tasks"] = examples
    schema = providers.strict_schema(schemas.PracticeUnitOutput, preserve_limits=True)
    providers.indexed_choice_schema(schema, bounded_matches=True)
    providers.bind_practice_tasks(schema, providers.practice_tasks(payload))
    providers.bind_math_tasks(schema, examples)
    before_schema, before_payload = copy.deepcopy(schema), copy.deepcopy(payload)
    assert compositions.bind_schema(schema, payload) is None
    assert schema == before_schema and payload == before_payload
    payload["visual_context"]["references"] = [r for r in payload["visual_context"]["references"] if r["id"] != compositions.RECIPE]
    with DB() as db:
        result = compositions.add_reference(db, payload)
    assert not any(r["id"] == compositions.RECIPE for r in result["visual_context"]["references"])
