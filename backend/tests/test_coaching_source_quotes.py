"""Real HTTP adapter checks using only synthetic source text and transport."""

import copy
import json

import httpx
import pytest
from schulpilot import providers
from schulpilot.config import settings
from schulpilot.db import DB, ProviderConfig
from schulpilot.providers import ProviderError, request_provider
from schulpilot.security import encrypt


def test_topic_only_parent_goals_keep_their_literal_evidence_without_a_notebook():
    assert providers.source_excerpt_candidates(
        {"materials": [], "goal": {"subject": "Englisch", "topic": "Unregelmäßige Verben", "note": ""}}
    ) == ["Unregelmäßige Verben"]


@pytest.fixture
def quote_transport(monkeypatch):
    object.__setattr__(settings, "real_data_approved", True)
    object.__setattr__(settings, "privacy_evidence", "synthetic transport approval")
    with DB() as db:
        config = db.get(ProviderConfig, 1)
    config.provider = "openrouter"
    config.model = "synthetic-fixture:free"
    config.emergency_stop = False
    config.structured_capable = True
    config.capability_evidence = "synthetic transport; upstream=test/fp8"
    config.privacy_approved = True
    config.privacy_evidence = "synthetic transport"
    config.production_block_reason = ""
    config.encrypted_key = encrypt("SYNTHETIC-NOT-A-REAL-KEY")
    config.input_per_million_micros = config.output_per_million_micros = 0
    payload = {
        "required_subject": "Sachunterricht",
        "required_topic": "Künstliche Testseiten",
        "next_action": "pause",
        "defer_practice": True,
        "learning_goals": [],
        "materials": [
            {
                "subject": "Sachunterricht",
                "content": "\n".join(
                    f"Seite {page}, Abschnitt {section}: Äpfel gehören zu den Früchten." for section in range(20)
                ),
            }
            for page in range(1, 6)
        ],
        "goal": {"note": "Vergleiche anschließend Äpfel und Birnen."},
        "completed_questions": [{"question_id": "q1", "deterministic_outcome": "correct"}],
    }
    literal = payload["materials"][-1]["content"].splitlines()[-1]
    output = {
        "explanation": "Du hast die gespeicherte Frage richtig beantwortet.",
        "learning_goals": [{"id": "g1", "label": "Früchte benennen", "source_excerpt": literal}],
        "question_reviews": [
            {
                "question_id": "q1",
                "learning_goal_id": "g1",
                "outcome": "correct",
                "feedback": "Die Antwort ist richtig.",
            }
        ],
        "next_unit": None,
    }
    calls = []

    def respond(request):
        body = json.loads(request.content)
        calls.append((request.url, body))
        text = json.dumps(output, ensure_ascii=False)
        if config.provider == "openai":
            reply = {
                "status": "completed",
                "output": [{"type": "message", "content": [{"type": "output_text", "text": text}]}],
                "usage": {"input_tokens": 80, "output_tokens": 100},
            }
        else:
            reply = {
                "choices": [{"finish_reason": "stop", "message": {"content": text}}],
                "usage": {"prompt_tokens": 80, "completion_tokens": 100, "cost": 0},
            }
        return httpx.Response(200, json=reply)

    real_client = httpx.Client
    monkeypatch.setattr(
        providers.httpx,
        "Client",
        lambda **kwargs: real_client(transport=httpx.MockTransport(respond), **kwargs),
    )
    monkeypatch.setattr(providers, "verify_free_endpoint", lambda *args: None)
    return config, payload, output, calls


@pytest.mark.parametrize("provider", ["openrouter", "openai"])
def test_literal_goal_quote_is_schema_bound_across_all_pages_and_accepted(quote_transport, provider):
    config, payload, output, calls = quote_transport
    config.provider = provider
    original = copy.deepcopy(payload)
    result = request_provider(config, "coach", payload)
    assert len(calls) == 1
    url, body = calls[0]
    if provider == "openrouter":
        assert str(url) == "https://openrouter.ai/api/v1/chat/completions"
        schema = body["response_format"]["json_schema"]["schema"]
        submitted = json.loads(body["messages"][1]["content"][0]["text"])
        instructions = body["messages"][0]["content"]
        assert body["provider"]["data_collection"] == "deny"
        assert body["provider"]["only"] == ["test/fp8"]
        assert body["provider"]["allow_fallbacks"] is False
        assert body["provider"]["max_price"] == {"prompt": 0, "completion": 0, "request": 0}
    else:
        assert str(url) == "https://api.openai.com/v1/responses"
        schema = body["text"]["format"]["schema"]
        submitted = json.loads(body["input"][0]["content"][0]["text"])
        instructions = body["instructions"]
        assert body["store"] is False
    candidates = submitted["source_excerpt_candidates"]
    assert len(candidates) == len(set(candidates)) == 32
    assert schema["$defs"]["LearningGoal"]["properties"]["source_excerpt"]["enum"] == candidates
    assert "EXAKT und UNVERÄNDERT" in instructions
    texts = [material["content"] for material in payload["materials"]] + [payload["goal"]["note"]]
    assert all(3 <= len(candidate) <= 350 and any(candidate in text for text in texts) for candidate in candidates)
    # Each page gets evidence from its beginning, middle and end, despite a
    # large earlier page. The parent note remains an independent valid source.
    for material in payload["materials"]:
        lines = material["content"].splitlines()
        assert lines[0] in candidates and lines[-1] in candidates
        assert any(line in candidates for line in lines[7:13])
    assert payload["goal"]["note"] in candidates
    assert result.data == output
    assert payload == original


def test_paraphrased_quote_from_http_200_is_rejected_after_transport(quote_transport):
    config, payload, output, calls = quote_transport
    output["learning_goals"][0]["source_excerpt"] = "Äpfel sind Früchte."
    with pytest.raises(ProviderError, match="keinen der wörtlichen Belege"):
        request_provider(config, "coach", payload)
    assert len(calls) == 1


def test_long_source_passages_remain_literal_and_bounded(quote_transport):
    config, payload, output, calls = quote_transport
    text = "Künstliches Wort " * 200 + "Wörtliches Ende."
    payload["materials"] = [{"content": text}]
    payload.pop("goal")
    output["learning_goals"][0]["source_excerpt"] = providers.source_excerpt_candidates(payload)[-1]
    request_provider(config, "coach", payload)
    submitted = json.loads(calls[0][1]["messages"][1]["content"][0]["text"])
    candidates = submitted["source_excerpt_candidates"]
    assert all(3 <= len(candidate) <= 350 and candidate in text for candidate in candidates)
    assert text.endswith(candidates[-1])
