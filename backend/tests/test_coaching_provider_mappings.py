"""Exercise the real provider adapter with synthetic, source-bound coach data."""

import copy
import json as jsonlib

import httpx
import pytest
from schulpilot import providers
from schulpilot.db import DB, ProviderConfig
from schulpilot.providers import ProviderError, request_provider
from test_providers import configured


@pytest.fixture
def coach_transport(api, household, monkeypatch):
    parent, _ = household
    configured(parent["families"][0]["id"])
    with DB() as db:
        config = db.get(ProviderConfig, 1)
    config.capability_evidence = "synthetic transport; upstream=test/fp8"
    payload = {
        "required_subject": "Mathematik",
        "required_topic": "Brüche",
        "next_action": "pause",
        "learning_goals": [
            {"id": "g1", "label": "Brüche kürzen", "source_excerpt": "Kürze beide Zahlen."},
            {"id": "g2", "label": "Brüche erweitern", "source_excerpt": "Erweitere beide Zahlen."},
        ],
        "completed_questions": [
            {"question_id": "expand", "learning_goal_id": "g2", "deterministic_outcome": "correct"},
            {"question_id": "reduce", "learning_goal_id": "g1", "deterministic_outcome": "correct"},
        ],
    }
    # A different response order rules out accidental positional reconstruction.
    output = {
        "explanation": "Du kannst nach der Pause weiterüben.",
        "question_reviews": [
            {"question_id": "reduce", "outcome": "correct", "feedback": "Richtig gekürzt."},
            {"question_id": "expand", "outcome": "correct", "feedback": "Richtig erweitert."},
        ],
        "next_unit": None,
    }
    calls = []

    class Client:
        def __init__(self, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def post(self, url, headers, json):
            calls.append(json)
            text = jsonlib.dumps(output)
            if config.provider == "openai":
                body = {
                    "status": "completed",
                    "output": [{"type": "message", "content": [{"type": "output_text", "text": text}]}],
                    "usage": {"input_tokens": 100, "output_tokens": 150},
                }
            else:
                body = {
                    "choices": [{"finish_reason": "stop", "message": {"content": text}}],
                    "usage": {"prompt_tokens": 100, "completion_tokens": 150, "cost": 0},
                }
            return httpx.Response(200, json=body)

    monkeypatch.setattr(providers.httpx, "Client", Client)
    monkeypatch.setattr(providers, "verify_free_endpoint", lambda *args: None)
    return config, payload, output, calls


@pytest.mark.parametrize("provider", ["openai", "openrouter"])
def test_known_question_goals_are_omitted_from_output_schema_and_restored_by_id(coach_transport, provider):
    config, payload, _, calls = coach_transport
    config.provider = provider
    if provider == "openrouter":
        config.model = "synthetic-fixture:free"
        config.input_per_million_micros = config.output_per_million_micros = 0
    result = request_provider(config, "coach", payload)
    assert len(calls) == 1
    call = calls[0]
    if provider == "openai":
        schema = call["text"]["format"]["schema"]
        submitted = jsonlib.loads(call["input"][0]["content"][0]["text"])
    else:
        schema = call["response_format"]["json_schema"]["schema"]
        submitted = jsonlib.loads(call["messages"][1]["content"][0]["text"])
        assert call["provider"]["only"] == ["test/fp8"]
        assert call["provider"]["data_collection"] == "deny"
        assert call["provider"]["allow_fallbacks"] is False
        assert call["provider"]["max_price"] == {"prompt": 0, "completion": 0, "request": 0}
    review = schema["$defs"]["QuestionFeedback"]
    assert set(review["properties"]) == {"question_id", "outcome", "feedback"}
    assert review["additionalProperties"] is False
    assert review["properties"]["question_id"]["enum"] == ["expand", "reduce"]
    assert schema["properties"]["question_reviews"]["minItems"] == 2
    assert schema["properties"]["question_reviews"]["maxItems"] == 2
    assert "learning_goals" not in schema["properties"]
    assert schema["properties"]["next_unit"] == {"type": "null"}
    assert submitted["completed_questions"] == payload["completed_questions"]
    assert result.data["learning_goals"] == payload["learning_goals"]
    assert [(r["question_id"], r["learning_goal_id"]) for r in result.data["question_reviews"]] == [
        ("reduce", "g1"),
        ("expand", "g2"),
    ]
    assert all(r["outcome"] == "correct" for r in result.data["question_reviews"])


@pytest.mark.parametrize("fault", ["new_assignment", "foreign_question", "duplicate_question"])
def test_slim_coach_output_rejects_assignments_and_nonmatching_question_sets(coach_transport, fault):
    config, payload, output, calls = coach_transport
    if fault == "new_assignment":
        output["question_reviews"][0]["learning_goal_id"] = "g2"
    elif fault == "foreign_question":
        output["question_reviews"][0]["question_id"] = "foreign"
    else:
        output["question_reviews"][0]["question_id"] = "expand"
    with pytest.raises(ProviderError):
        request_provider(config, "coach", payload)
    assert len(calls) == 1


@pytest.mark.parametrize("mixed", [False, True])
def test_legacy_questions_keep_strict_goal_schema_and_existing_assignments(coach_transport, mixed):
    config, payload, output, calls = coach_transport
    for question in payload["completed_questions"]:
        if not mixed or question["question_id"] == "reduce":
            question.pop("learning_goal_id")
    # The legacy assignment is still the model's responsibility; the already
    # stored expansion assignment must be restored even in this mixed schema.
    output["question_reviews"][0]["learning_goal_id"] = "g1"
    output["question_reviews"][1]["learning_goal_id"] = "g1" if mixed else "g2"
    result = request_provider(config, "coach", payload)
    schema = calls[0]["text"]["format"]["schema"]
    assert "learning_goal_id" in schema["$defs"]["QuestionReview"]["required"]
    assert schema["$defs"]["QuestionReview"]["properties"]["learning_goal_id"]["enum"] == ["g1", "g2"]
    assert result.data["question_reviews"][1]["learning_goal_id"] == "g2"
    bad = copy.deepcopy(output)
    bad["question_reviews"][0].pop("learning_goal_id")
    output.update(bad)
    with pytest.raises(ProviderError):
        request_provider(config, "coach", payload)
    assert len(calls) == 2


def test_unknown_stored_goal_is_rejected_before_any_provider_request(coach_transport):
    config, payload, _, calls = coach_transport
    payload["completed_questions"][0]["learning_goal_id"] = "g4"
    with pytest.raises(ProviderError, match="gespeicherte Aufgabe"):
        request_provider(config, "coach", payload)
    assert calls == []
