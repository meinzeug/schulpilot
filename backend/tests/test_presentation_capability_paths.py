"""Synthetic adapter envelopes exercise final prompts without any network calls."""

import copy
import json
from pathlib import Path

import httpx
import pytest
from schulpilot import providers
from schulpilot.config import settings
from schulpilot.db import DB, ProviderConfig
from schulpilot.security import encrypt
from schulpilot.subject_content import PROFILES, public_presentation

FIXTURES = Path(__file__).parents[2] / "testdata"
SCENE = json.loads((FIXTURES / "learning_scenes_v1.json").read_text())["cases"][0]
LOGIC = next(
    case for case in json.loads((FIXTURES / "science_graphics_v1.json").read_text())["cases"]
    if case["id"] == "LOGIC01"
)


def _config(provider):
    object.__setattr__(settings, "real_data_approved", True)
    object.__setattr__(settings, "privacy_evidence", "artificial capability-path test")
    object.__setattr__(settings, "codex_approved", True)
    object.__setattr__(settings, "codex_socket", "/tmp/artificial-capability-path-no-connection.sock")
    object.__setattr__(settings, "codex_auth_mode", "api_key")
    with DB.begin() as db:
        config = db.get(ProviderConfig, 1)
        config.provider = provider
        config.model = "artificial-capability-path-model"
        config.emergency_stop = False
        config.structured_capable = True
        config.capability_evidence = "artificial transport upstream=fixture-upstream"
        config.privacy_approved = True
        config.privacy_evidence = "artificial capability-path test"
        config.encrypted_key = encrypt("SYNTHETIC-NOT-A-REAL-KEY")
        config.openrouter_free_only = False
        config.input_per_million_micros = config.output_per_million_micros = 1
        config.pricing_evidence = "artificial fixture"
        config.max_output_tokens = 4000
        config.reserve_micros = 1000
    with DB() as db:
        return db.get(ProviderConfig, 1)


def _transport(monkeypatch, provider, response):
    calls = []

    def indexed(value):
        if isinstance(value, dict):
            if value.get("type") == "choice" and "answer" in value:
                value["answer"] = value["options"].index(value["answer"])
            for child in value.values():
                indexed(child)
        elif isinstance(value, list):
            for child in value:
                indexed(child)

    class Client:
        def __init__(self, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def post(self, url, **kwargs):
            calls.append(kwargs["json"])
            data = copy.deepcopy(response)
            if provider in ("openrouter", "codex"):
                indexed(data)
            usage = {"input_tokens": 123, "output_tokens": 234, "prompt_tokens": 123, "completion_tokens": 234}
            if provider == "codex":
                envelope = {"data": data, "usage": usage}
            elif provider == "openrouter":
                envelope = {"usage": usage, "choices": [
                    {"finish_reason": "stop", "message": {"content": json.dumps(data)}}
                ]}
            else:
                envelope = {"status": "completed", "usage": usage, "output": [
                    {"type": "message", "content": [{"type": "output_text", "text": json.dumps(data)}]}
                ]}
            return httpx.Response(200, json=envelope)

    monkeypatch.setattr(providers.httpx, "Client", Client)
    return calls


def _submitted(provider, body):
    if provider == "codex":
        return body["payload"], body["schema"], body["system"]
    if provider == "openrouter":
        return (
            json.loads(body["messages"][1]["content"][0]["text"]),
            body["response_format"]["json_schema"]["schema"],
            body["messages"][0]["content"],
        )
    return json.loads(body["input"][0]["content"][0]["text"]), body["text"]["format"]["schema"], body["instructions"]


def _scene_unit():
    question = copy.deepcopy(SCENE["question"])
    return {"subject": SCENE["subject"], "topic": "Wasserkreislauf", "explanation": SCENE["source"],
            "questions": [question, {**copy.deepcopy(question), "id": "second_scene"}]}


def _plain_unit():
    return {"subject": "Informatik", "topic": "Logische Operationen", "explanation": "UND. ODER.",
            "questions": [
                {"id": "logic_" + str(index), "type": "short", "prompt": "Nenne den belegten Begriff.",
                 "options": [], "answer": answer, "accepted": [], "hints": ["Lies den bestätigten Stoff."],
                 "explanation": "Der Begriff steht im bestätigten Stoff."}
                for index, answer in enumerate(("UND", "ODER"))
            ]}


@pytest.mark.parametrize("provider", ["openai", "openrouter", "codex"])
def test_normal_material_unit_receives_its_profile_without_required_subject(monkeypatch, provider):
    unit = _scene_unit()
    payload = {"material": {"subject": unit["subject"], "topic": unit["topic"], "content": SCENE["source"]}}
    original = copy.deepcopy(payload)
    calls = _transport(monkeypatch, provider, unit)
    config = _config(provider)
    result = providers.request_provider(config, "unit", payload)
    assert payload == original and len(calls) == 1
    submitted, schema, instructions = _submitted(provider, calls[0])
    context = submitted["content_context"]
    assert context["graphic_kinds"] == sorted(PROFILES["Geographie"])
    assert [item["subject"] for item in context["subject_profiles"]] == ["Geographie"]
    assert context["subject_profiles"][0]["graphic_kinds"] == context["graphic_kinds"]
    assert "short" in context["question_types"]
    assert set(context["answer_ui"]) == set(context["question_types"])
    assert context["max_blocks"] == schema["$defs"]["Presentation"]["properties"]["blocks"]["maxItems"] == 2
    assert "scene" in context["local_interactions"] and "logic_table" not in context["use_for"]
    assert instructions.count("DARSTELLUNGSWAHL:") == 1 and "scene:" in instructions
    assert config.max_output_tokens == 4000 and config.reserve_micros == 1000
    assert calls[0].get("max_tokens", calls[0].get("max_output_tokens")) == 4000
    presentation = result.data["questions"][0]["presentation"]
    assert public_presentation(presentation)["blocks"] == []
    assert public_presentation(presentation, hints=1) == SCENE["public_presentation"]


@pytest.mark.parametrize("provider", ["openrouter", "codex"])
@pytest.mark.parametrize("misfiled_graphic", [False, True])
def test_package_profiles_keep_group_boundaries_and_codex_question_limits(monkeypatch, provider, misfiled_graphic):
    geography, computing = _scene_unit(), _plain_unit()
    response = {"units": [{**geography, "group_id": "g1"}, {**computing, "group_id": "g2"}]}
    if misfiled_graphic:
        response["units"][0]["questions"][0]["presentation"] = copy.deepcopy(LOGIC["question"]["presentation"])
    payload = {
        "selected_groups": [{"id": "g1", "subject": "Geographie", "estimated_minutes": 5},
                            {"id": "g2", "subject": "Informatik", "estimated_minutes": 5}],
        "materials": [{"group_id": "g1", "subject": "Geographie", "topic": geography["topic"],
                       "content": SCENE["source"] + "\n" + LOGIC["source"]},
                      {"group_id": "g2", "subject": "Informatik", "topic": computing["topic"],
                       "content": computing["explanation"]}],
    }
    calls = _transport(monkeypatch, provider, response)
    if misfiled_graphic:
        with pytest.raises(providers.ProviderError, match="abgelehnt"):
            providers.request_provider(_config(provider), "package", payload)
    else:
        result = providers.request_provider(_config(provider), "package", payload)
        assert len(result.data["units"]) == 2
    assert len(calls) == 1
    submitted, schema, instructions = _submitted(provider, calls[0])
    context = submitted["content_context"]
    profiles = {item["subject"]: item for item in context["subject_profiles"]}
    assert set(profiles) == {"Geographie", "Informatik"}
    assert "logic_table" in profiles["Informatik"]["graphic_kinds"]
    assert "logic_table" not in profiles["Geographie"]["graphic_kinds"]
    assert set(schema["$defs"]["Graphic"]["properties"]["kind"]["enum"]) == set(context["graphic_kinds"])
    expected = {"choice", "short", "match", "grouped"} if provider == "openrouter" else {"choice", "short"}
    assert set(context["question_types"]) == expected
    assert set(context["answer_ui"]) == expected
    assert all(set(profile["question_types"]) == expected for profile in profiles.values())
    if provider == "openrouter":
        assert context["matching"]["pairs_min"] == 2 and context["matching"]["pairs_max"] == 4
    else:
        assert "matching" not in context
        assert "ausschließlich choice/short, keine gap- oder match-Aufgabe" in instructions


@pytest.mark.parametrize("provider", ["openai", "openrouter", "codex"])
def test_review_only_does_not_receive_graphic_generation_capabilities(monkeypatch, provider):
    payload = {
        "required_subject": "Geographie", "required_topic": "Wasserkreislauf", "next_action": "repair",
        "defer_practice": True, "materials": [{"subject": "Geographie", "content": SCENE["source"]}],
        "learning_goals": [{"id": "g1", "label": "Wasserkreislauf", "source_excerpt": SCENE["source"]}],
        "completed_questions": [{"question_id": "done", "learning_goal_id": "g1"}],
    }
    response = {"explanation": "Vergleiche die gespeicherten Schritte.", "next_unit": None,
                "question_reviews": [{"question_id": "done", "outcome": "incorrect", "feedback": "Lies die Erklärung."}]}
    calls = _transport(monkeypatch, provider, response)
    result = providers.request_provider(_config(provider), "coach", payload)
    assert len(calls) == 1 and result.data["next_unit"] is None
    submitted, schema, instructions = _submitted(provider, calls[0])
    assert "content_context" not in submitted and "DARSTELLUNGSWAHL:" not in instructions
    assert not {"Graphic", "Presentation", "SceneV1"} & schema.get("$defs", {}).keys()


@pytest.mark.parametrize("provider", ["openai", "openrouter", "codex"])
def test_language_project_retains_its_own_word_contract_without_graphic_capabilities(monkeypatch, provider):
    payload = {"mode": "exam", "target_locale": "en-GB", "grade": 6, "goal": "Belegte Wörter anwenden",
               "words": [{"id": "a" * 32, "word": "apple", "meaning": "Apfel", "context": "", "variants": []}],
               "materials": [{"subject": "Englisch", "content": "apple = Apfel"}]}
    response = {"title": "Künstliche Wortübung", "explanation": "Wähle das bestätigte Wort.",
                "response": "Vergleiche die Bedeutung.", "response_locale": "de-DE", "source_excerpt": "apple = Apfel",
                "criteria": [], "questions": [
                    {"id": f"word_{i}", "type": "choice", "task_kind": "context_gap", "vocabulary_item_id": "a" * 32,
                     "prompt": f"Welches Wort passt in Beispiel {i + 1}?", "cue": "I see an ___.", "cue_locale": "en-GB",
                     "source_excerpt": "apple = Apfel", "options": ["Apfel", "apple"], "answer": "apple",
                     "accepted": [], "hints": ["Vergleiche die Bedeutung."], "explanation": "apple = Apfel"}
                    for i in range(2)
                ]}
    calls = _transport(monkeypatch, provider, response)
    result = providers.request_provider(_config(provider), "language_project", payload)
    assert len(calls) == 1 and result.data["questions"][0]["answer"] == "apple"
    submitted, schema, instructions = _submitted(provider, calls[0])
    assert "content_context" not in submitted and "DARSTELLUNGSWAHL:" not in instructions
    assert not {"Graphic", "Presentation", "SceneV1"} & schema.get("$defs", {}).keys()
    assert submitted["source_evidence"] == [{"vocabulary_item_id": "a" * 32, "source_excerpt": "apple = Apfel"}]
    assert "presentation" not in json.dumps(schema)
