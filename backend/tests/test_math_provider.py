"""Actual adapter transport with artificial, preplanned arithmetic only."""

import copy
import json
from fractions import Fraction

import httpx
import pytest
from schulpilot import providers
from schulpilot.coaching import fraction_task_goal, fraction_task_signature
from schulpilot.config import settings
from schulpilot.db import DB, ProviderConfig
from schulpilot.providers import ProviderError, request_provider
from schulpilot.security import encrypt

SOURCE = (
    "Brüche kürzen: Zähler und Nenner durch dieselbe ganze Zahl teilen.\n"
    "Brüche erweitern: Zähler und Nenner mit derselben ganzen Zahl multiplizieren."
)


@pytest.mark.parametrize(
    "prompt,signature,label",
    [
        (
            "Erweitere den Bruch 1/2 mit dem Faktor 2. Kürze das Ergebnis nicht.",
            ("expand", ("1", "2"), "2"),
            "Brüche erweitern",
        ),
        ("Berechne 1/6 + 2/6. Kürze das Ergebnis.", ("add", (("1", "6"), ("2", "6"))), "Brüche addieren"),
        ("Kürze 12/18 vollständig. Erweitere den Bruch nicht.", ("reduce", ("12", "18")), "Brüche kürzen"),
    ],
)
def test_novelty_and_goal_follow_the_requested_operation_before_later_instructions(prompt, signature, label):
    goals = [
        {"id": f"g{index}", "label": name}
        for index, name in enumerate(
            ["Zähler und Nenner benennen", "Brüche addieren", "Brüche kürzen", "Brüche erweitern"]
        )
    ]
    assert fraction_task_signature(prompt) == signature
    assert fraction_task_goal(prompt, goals) == next(goal["id"] for goal in goals if goal["label"] == label)


@pytest.fixture
def arithmetic_transport(monkeypatch):
    object.__setattr__(settings, "real_data_approved", True)
    object.__setattr__(settings, "privacy_evidence", "synthetic adapter test")
    with DB() as db:
        config = db.get(ProviderConfig, 1)
    config.provider = "openrouter"
    config.model = "synthetic-transport:free"
    config.emergency_stop = False
    config.structured_capable = True
    config.capability_evidence = "synthetic transport; upstream=test/fp8"
    config.privacy_approved = True
    config.privacy_evidence = "synthetic adapter test"
    config.production_block_reason = ""
    config.encrypted_key = encrypt("SYNTHETIC-NOT-A-REAL-KEY")
    config.input_per_million_micros = config.output_per_million_micros = 0
    payload = {
        "required_subject": "Mathematik",
        "required_topic": "Brüche",
        "material": {"subject": "Mathematik", "topic": "Brüche", "content": SOURCE},
        "previous_prompts": ["Kürze 12/18 vollständig.", "Erweitere 1/3 mit dem Faktor 2."],
        "study_block": {"mode": "detective", "question_count": 3, "tasks": []},
    }
    calls, outputs, mutations = [], [], []

    def respond(request):
        body = json.loads(request.content)
        router = config.provider == "openrouter"
        submitted = json.loads(
            body["messages"][1]["content"][0]["text"] if router else body["input"][0]["content"][0]["text"]
        )
        calls.append(body)
        goals = {task["id"]: task["learning_goal_id"] for task in submitted.get("practice_tasks", [])}
        output = {
            "subject": submitted["required_subject"],
            "topic": submitted["required_topic"],
            "explanation": "Künstliche Test-Erklärung, kein echter KI-Aufruf.",
            "questions": [
                {
                    **{key: value for key, value in task.items() if key != "source_excerpt"},
                    **({"learning_goal_id": goals[task["id"]]} if goals else {}),
                    "hints": ["Wende das bestätigte Verfahren auf beide Zahlen an."],
                    "explanation": "Künstlicher Testtext zum geprüften Beispiel.",
                }
                for task in submitted["math_tasks"]
            ],
        }
        if mutations:
            mutations[0](output)
        outputs.append(copy.deepcopy(output))
        text = json.dumps(output, ensure_ascii=False)
        reply = (
            {
                "choices": [{"finish_reason": "stop", "message": {"content": text}}],
                "usage": {"prompt_tokens": 120, "completion_tokens": 200, "cost": 0},
            }
            if router
            else {
                "status": "completed",
                "output": [{"type": "message", "content": [{"type": "output_text", "text": text}]}],
                "usage": {"input_tokens": 120, "output_tokens": 200},
            }
        )
        return httpx.Response(200, json=reply)

    client = httpx.Client
    monkeypatch.setattr(
        providers.httpx, "Client", lambda **kwargs: client(transport=httpx.MockTransport(respond), **kwargs)
    )
    monkeypatch.setattr(providers, "verify_free_endpoint", lambda *args: None)
    return config, payload, calls, outputs, mutations


def submitted_request(config, body):
    if config.provider == "openrouter":
        return (
            json.loads(body["messages"][1]["content"][0]["text"]),
            body["response_format"]["json_schema"]["schema"],
            body["messages"][0]["content"],
        )
    return json.loads(body["input"][0]["content"][0]["text"]), body["text"]["format"]["schema"], body["instructions"]


@pytest.mark.parametrize("provider", ["openrouter", "openai"])
def test_arithmetic_is_planned_before_one_call_and_never_rewrites_model_answers(arithmetic_transport, provider):
    config, payload, calls, outputs, _ = arithmetic_transport
    config.provider = provider
    before = copy.deepcopy(payload)
    result = request_provider(config, "unit", payload)
    assert payload == before and len(calls) == 1 and result.data == outputs[0]
    submitted, schema, instructions = submitted_request(config, calls[0])
    planned = submitted["math_tasks"]
    assert len(planned) == 3
    branches = schema["$defs"]["Question"]["anyOf"]
    assert len(branches) == 3
    assert "Erzeuge choice und short." not in instructions
    assert "math_tasks legt die konkreten Beispiele fest" in instructions
    for task, branch in zip(planned, branches, strict=True):
        properties = branch["properties"]
        for key in ("id", "type", "prompt", "answer"):
            assert properties[key]["enum"] == [task[key]]
        assert properties["options"]["maxItems"] == properties["accepted"]["maxItems"] == 0
        assert task["source_excerpt"] in SOURCE
        assert task["prompt"] not in before["previous_prompts"]
        assert Fraction(task["answer"]) > 0
    if provider == "openrouter":
        assert calls[0]["provider"]["data_collection"] == "deny"
        assert calls[0]["provider"]["allow_fallbacks"] is False
        assert calls[0]["provider"]["only"] == ["test/fp8"]
        assert calls[0]["provider"]["max_price"] == {"prompt": 0, "completion": 0, "request": 0}
    else:
        assert calls[0]["store"] is False


@pytest.mark.parametrize("fault", ["prompt", "answer", "options", "id", "duplicate"])
def test_ignored_arithmetic_schema_is_rejected_without_retry_or_replacement(arithmetic_transport, fault):
    config, payload, calls, _, mutations = arithmetic_transport

    def mutate(output):
        question = output["questions"][0]
        if fault == "prompt":
            question["prompt"] += " Noch einmal."
        elif fault == "answer":
            question["answer"] = "999"
        elif fault == "options":
            question["options"] = [question["answer"]]
        elif fault == "id":
            question["id"] = "changed"
        else:
            output["questions"][1] = copy.deepcopy(question)

    mutations.append(mutate)
    with pytest.raises(ProviderError):
        request_provider(config, "unit", payload)
    assert len(calls) == 1


@pytest.mark.parametrize("kind", ["repair", "check"])
def test_practice_keeps_two_existing_goal_assignments_and_checked_examples(arithmetic_transport, kind):
    config, payload, calls, _, _ = arithmetic_transport
    payload.pop("study_block")
    payload.update(
        review=True,
        practice_kind=kind,
        learning_goals=[
            {"id": "g1", "label": "Brüche kürzen", "source_excerpt": SOURCE.splitlines()[0]},
            {"id": "g2", "label": "Brüche erweitern", "source_excerpt": SOURCE.splitlines()[1]},
        ],
        focus_goal_ids=["g1", "g2"],
    )
    result = request_provider(config, "unit", payload)
    submitted, schema, instructions = submitted_request(config, calls[0])
    assert len(calls) == 1 and len(result.data["questions"]) == 2
    assert [(q["id"], q["learning_goal_id"]) for q in result.data["questions"]] == [("q1", "g1"), ("q2", "g2")]
    assert len(schema["$defs"]["PracticeQuestion"]["anyOf"]) == 2
    assert "sowohl Auswahlaufgaben" not in instructions
    for task, branch in zip(submitted["math_tasks"], schema["$defs"]["PracticeQuestion"]["anyOf"], strict=True):
        assert branch["properties"]["learning_goal_id"]["enum"] == ["g1" if task["id"] == "q1" else "g2"]
        assert ("Verstehen" if kind == "repair" else "Erinnern") in task["prompt"]


def test_wrong_practice_goal_does_not_get_relabelled(arithmetic_transport):
    config, payload, calls, outputs, mutations = arithmetic_transport
    payload.pop("study_block")
    payload.update(
        review=True,
        practice_kind="repair",
        learning_goals=[
            {"id": "g1", "label": "Brüche kürzen", "source_excerpt": SOURCE.splitlines()[0]},
            {"id": "g2", "label": "Brüche erweitern", "source_excerpt": SOURCE.splitlines()[1]},
        ],
        focus_goal_ids=["g1", "g2"],
    )
    mutations.append(lambda output: output["questions"][1].update(learning_goal_id="g1"))
    with pytest.raises(ProviderError, match="vorgegebenen Lernzielen"):
        request_provider(config, "unit", payload)
    assert len(calls) == 1 and outputs[0]["questions"][1]["learning_goal_id"] == "g1"
