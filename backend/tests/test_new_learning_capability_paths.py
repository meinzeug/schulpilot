"""Mock the genuine adapters; capability metadata is not an AI success claim."""

import copy
import json
from pathlib import Path

import pytest
from schulpilot import providers
from schulpilot.grouped_questions import public_group
from schulpilot.subject_content import public_presentation
from test_presentation_capability_paths import _config, _submitted, _transport

DATA = Path(__file__).parents[2] / "testdata"
FIELDS = json.loads((DATA / "learning_fields_v1.json").read_text())["cases"][0]
TEXT = json.loads((DATA / "text_probes_v1.json").read_text())["cases"][0]


def unit(case):
    question = copy.deepcopy(case["question"])
    return {"subject": case["subject"], "topic": "Künstliche Vertragsprüfung", "explanation": case["source"],
            "questions": [question, {**copy.deepcopy(question), "id": "second"}]}


@pytest.mark.parametrize("provider", ["openai", "openrouter", "codex"])
@pytest.mark.parametrize("case", [FIELDS, TEXT], ids=["grouped", "text_probe"])
def test_actual_normal_unit_adapters_parse_validate_and_project_new_contracts(monkeypatch, provider, case):
    output = unit(case)
    calls = _transport(monkeypatch, provider, output)
    config = _config(provider)
    bounds = (config.max_output_tokens, config.reserve_micros)
    result = providers.request_provider(config, "unit", {"material": {"subject": case["subject"], "content": case["source"]}})
    assert len(calls) == 1
    submitted, schema, instructions = _submitted(provider, calls[0])
    context = submitted["content_context"]
    assert "grouped" in context["question_types"] and context["field_group"]["fields_max"] == 4
    assert "text_probe" in context["graphic_kinds"]
    assert instructions.count("MEHRFELDAUFGABE") == 1
    assert (config.max_output_tokens, config.reserve_micros) == bounds == (4000, 1000)
    q = result.data["questions"][0]
    if case is FIELDS:
        assert public_group(q["field_group"]) == FIELDS["public_question"]["field_group"]
    else:
        assert public_presentation(q["presentation"], hints=1) == TEXT["public_presentation_hint1"]
    assert "content_context" not in result.data


@pytest.mark.parametrize("case", [FIELDS, TEXT], ids=["grouped", "text_probe"])
def test_actual_adapter_rejects_unattested_output_without_retry(monkeypatch, case):
    output = unit(case)
    calls = _transport(monkeypatch, "openrouter", output)
    with pytest.raises(providers.ProviderError, match="abgelehnt"):
        providers.request_provider(_config("openrouter"), "unit", {"material": {"subject": case["subject"], "content": "Andere bestätigte Quelle."}})
    assert len(calls) == 1


@pytest.mark.parametrize("provider", ["openrouter", "codex"])
def test_factual_package_allows_new_grouped_only_in_explicit_compact_openrouter_path(monkeypatch, provider):
    response = {"units": [{**unit(FIELDS), "group_id": "g1"}]}
    payload = {"selected_groups": [{"id": "g1", "subject": FIELDS["subject"], "estimated_minutes": 5}],
               "materials": [{"group_id": "g1", "subject": FIELDS["subject"], "topic": "Begriffe", "content": FIELDS["source"]}]}
    calls = _transport(monkeypatch, provider, response)
    if provider == "codex":
        with pytest.raises(providers.ProviderError, match="angeforderten Ausgabeformat"):
            providers.request_provider(_config(provider), "package", payload)
    else:
        result = providers.request_provider(_config(provider), "package", payload)
        assert result.data["units"][0]["questions"][0]["type"] == "grouped"
    submitted, _, instructions = _submitted(provider, calls[0])
    context = submitted["content_context"]
    assert ("grouped" in context["question_types"]) == (provider == "openrouter")
    assert ("field_group" in context) == (provider == "openrouter")
    assert ("MEHRFELDAUFGABE" in instructions) == (provider == "openrouter")
    assert len(calls) == 1
