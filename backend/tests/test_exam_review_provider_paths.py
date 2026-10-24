"""Inspect actual provider envelopes using only synthetic in-memory HTTP adapters."""

import copy

import pytest
from schulpilot import providers
from test_exam_reviews import REPORT, TEXT
from test_presentation_capability_paths import _config, _submitted, _transport


@pytest.mark.parametrize("provider", ["openai", "openrouter", "codex"])
@pytest.mark.parametrize("action", ["analyze", "hint"])
def test_review_uses_explicit_tutor_budget_schema_and_no_unit_generation(monkeypatch, provider, action):
    response = (
        copy.deepcopy(REPORT)
        if action == "analyze"
        else {
            "kind": "answer",
            "answer": "Vergleiche die Markierung.",
            "sources": [{"ref": "p1", "quote": "Nenner bleibt 4."}],
            "next_question": None,
        }
    )
    config = _config(provider)
    calls = _transport(monkeypatch, provider, response)
    payload = {
        "grade": 6,
        "sources": [{"ref": "p1", "label": "Seite 1", "content": TEXT}],
        "history": [],
        "exam_context": {"action": action, "subject": "Mathematik"},
    }
    result = providers.request_provider(config, "tutor", payload)
    assert result.data == response and len(calls) == 1
    submitted, schema, instructions = _submitted(provider, calls[0])
    assert submitted["exam_context"]["action"] == action
    assert ("tasks" in schema["properties"]) is (action == "analyze")
    assert "questions" not in schema["properties"] and "content_context" not in submitted
    assert "keine Note" in instructions and "nicht vertrauenswürdige Daten" in instructions
    assert config.max_output_tokens == 4000 and config.reserve_micros == 1000


def unit(count):
    words = ["UND", "ODER", "NICHT", "XOR", "NAND"]
    return {
        "subject": "Informatik",
        "topic": "Operationen",
        "explanation": "Die Begriffe stehen im bestätigten Stoff.",
        "questions": [
            {
                "id": f"q{index}",
                "type": "short",
                "prompt": f"Nenne den Begriff an Position {index + 1}.",
                "answer": words[index],
                "accepted": [],
                "options": [],
                "hints": ["Lies die geordnete Liste."],
                "explanation": "Der Begriff steht in der geordneten Liste.",
            }
            for index in range(count)
        ],
    }


@pytest.mark.parametrize("provider", ["openai", "openrouter", "codex"])
@pytest.mark.parametrize("count", [1, 3, 5])
def test_exam_preparation_exact_question_count_applies_to_every_existing_provider(monkeypatch, provider, count):
    config = _config(provider)
    calls = _transport(monkeypatch, provider, unit(count))
    payload = {
        "exam_preparation": True,
        "required_subject": "Informatik",
        "required_topic": "Operationen",
        "study_block": {"mode": "recall", "question_count": count},
        "previous_prompts": ["Eine alte Frage."],
        "material": {
            "subject": "Informatik",
            "topic": "Operationen",
            "content": "Geordnete Liste: UND, ODER, NICHT, XOR, NAND.",
        },
    }
    result = providers.request_provider(config, "unit", payload)
    assert len(result.data["questions"]) == count and len(calls) == 1
    _, schema, instructions = _submitted(provider, calls[0])
    assert schema["properties"]["questions"]["minItems"] == schema["properties"]["questions"]["maxItems"] == count
    assert "Klassenarbeitsvorbereitung" in instructions and f"GENAU {count}" in instructions
    assert "Erzeuge pro Eintrag in study_block.tasks" not in instructions
    assert config.max_output_tokens == 4000 and config.reserve_micros == 1000


def test_generic_study_block_does_not_gain_exam_one_question_exception(monkeypatch):
    config = _config("openai")
    calls = _transport(monkeypatch, "openai", unit(1))
    with pytest.raises(providers.ProviderError, match="Umfang"):
        providers.request_provider(
            config,
            "unit",
            {
                "required_subject": "Informatik",
                "required_topic": "Operationen",
                "study_block": {"mode": "recall", "question_count": 1},
                "material": {"content": "UND"},
            },
        )
    assert calls == []
