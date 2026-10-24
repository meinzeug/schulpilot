"""Capabilities describe real renderers and the final request, never new output fields."""

import copy
import json

import pytest
from schulpilot import providers
from schulpilot.presentation_capabilities import INTERACTIONS, PURPOSES
from schulpilot.schemas import UnitOutput
from schulpilot.subject_content import (
    KINDS,
    PROFILES,
    bind_graphic_schema,
    generation_context,
    generation_subjects,
)
from test_learning_scenes import _config, _transport
from test_math_provider import arithmetic_transport as arithmetic_transport
from test_math_provider import submitted_request


def final_schema(subjects, *, labs_enabled=False):
    schema = bind_graphic_schema(providers.strict_schema(UnitOutput, preserve_limits=True), subjects, labs_enabled=labs_enabled)
    schema["$defs"]["Presentation"]["properties"]["blocks"]["maxItems"] = 2
    return schema


@pytest.mark.parametrize("subject", PROFILES)
@pytest.mark.parametrize("labs_enabled", [False, True])
def test_every_actual_subject_profile_has_complete_purpose_and_accurate_interaction_scope(subject, labs_enabled):
    schema = final_schema([subject], labs_enabled=labs_enabled)
    supported = set(PROFILES[subject]) - ({"lab"} if not labs_enabled else set())
    context = generation_context([subject], schema=schema)
    assert context["graphic_kinds"] == sorted(supported)
    assert set(context["use_for"]) == supported
    assert context["subject_profiles"] == [{"subject": subject, "graphic_kinds": sorted(supported),
                                            "question_types": ["choice", "gap", "grouped", "match", "short"]}]
    assert set(context["local_interactions"]) == supported & INTERACTIONS.keys()
    assert "function_curve" not in context["local_interactions"]
    assert "matching" not in context
    assert set(context["answer_ui"]) == {"choice", "gap", "grouped", "match", "short"}
    assert "Drag" in context["answer_ui"]["match"] and "Prüfen" in context["answer_ui"]["match"]
    assert context["max_blocks"] == 2
    assert "controls" not in schema["$defs"]["Graphic"]["properties"]
    assert "content_context" not in schema["properties"]
    def valid_enums(value):
        if isinstance(value, dict):
            if "enum" in value:
                assert value["enum"], "Strict provider schemas reject empty enums."
            for child in value.values():
                valid_enums(child)
        elif isinstance(value, list):
            for child in value:
                valid_enums(child)
    valid_enums(schema)


def test_catalog_covers_every_existing_kind_and_does_not_export_one_subject_union_as_another():
    assert set(PURPOSES) == set(KINDS)
    subjects = ["Technik", "Geographie", "Englisch"]
    context = generation_context(subjects, schema=final_schema(subjects), compact_matching=True)
    profiles = {profile["subject"]: profile for profile in context["subject_profiles"]}
    assert "logic_table" in profiles["Technik"]["graphic_kinds"]
    assert "logic_table" not in profiles["Geographie"]["graphic_kinds"]
    assert "data_plot" not in profiles["Geographie"]["graphic_kinds"]
    assert "picture_words" not in profiles["Technik"]["graphic_kinds"]
    assert context["matching"]["pairs_min"] == 2 and context["matching"]["pairs_max"] == 4
    assert "polynomial2" in context["local_interactions"]["function_graph"]
    assert "0,1" in context["local_interactions"]["function_graph"]
    assert "Originalpaaren" in context["local_interactions"]["data_plot"]
    assert "UND/ODER/NICHT" in context["local_interactions"]["logic_table"]
    assert "Autoplay" in context["local_interactions"]["scene"]
    assert "rouge" in context["picture_word_labels"]
    assert len(json.dumps(context, ensure_ascii=False).encode()) < 13000


@pytest.mark.parametrize(
    "payload,expected",
    [
        ({"material": {"subject": "Biologie"}}, ["Biologie"]),
        ({"goal": {"subject": "Physik"}}, ["Physik"]),
        ({"materials": [{"subject": "Chemie"}, {"subject": "Chemie"}]}, ["Chemie"]),
        ({"required_subject": "Technik", "material": {"subject": "Chemie"}}, ["Technik"]),
        ({"required_subject": "Technik", "selected_groups": [{"subject": "Chemie"}, {"subject": "Deutsch"}]},
         ["Chemie", "Deutsch"]),
        ({"material": "synthetic"}, []),
        ({"goal": "legacy goal"}, []),
        ({"material": "synthetic", "materials": [None, "legacy text", {"subject": "Physik"}]}, ["Physik"]),
        ({"material": None, "goal": {"subject": "Geschichte"}}, ["Geschichte"]),
        ({}, []),
    ],
)
def test_subject_scope_uses_confirmed_source_fallback_without_widening_explicit_requests(payload, expected):
    assert generation_subjects(payload) == expected


def test_unreachable_question_and_graphic_definitions_do_not_advertise_capabilities():
    schema = final_schema(["Technik"])
    # Keep dead definitions deliberately: the guide must follow reachable refs,
    # even if a future caller forgets to prune them first.
    schema["properties"]["questions"] = {"type": "null"}
    schema["properties"]["explanation_steps"] = {"type": "null"}
    context = generation_context(["Technik"], schema=schema, compact_matching=True)
    assert context["question_types"] == []
    assert context["graphic_kinds"] == []
    assert context["max_blocks"] == 0
    assert context["local_interactions"] == {}
    assert "matching" not in context


def test_intro_graphics_remain_reachable_without_question_graphics():
    schema = final_schema(["Technik"])
    schema["properties"]["questions"] = {"type": "null"}
    context = generation_context(["Technik"], schema=schema, compact_matching=True)
    assert context["question_types"] == []
    assert context["graphic_kinds"]  # A real intro step still has a graphic.


def test_fixed_math_request_exposes_only_its_final_short_tasks_without_changing_limits(arithmetic_transport):
    config, payload, calls, _, _ = arithmetic_transport
    bounds = (config.max_output_tokens, config.reserve_micros)
    result = providers.request_provider(config, "unit", payload)
    submitted, schema, instructions = submitted_request(config, calls[0])
    context = submitted["content_context"]
    assert context["question_types"] == ["short"]
    assert set(context["answer_ui"]) == {"short"}
    assert context["subject_profiles"][0]["question_types"] == ["short"]
    assert context["max_blocks"] == schema["$defs"]["Presentation"]["properties"]["blocks"]["maxItems"] == 2
    assert "matching" not in context
    assert "Kleine Zuordnung (type match) ist erlaubt" not in instructions
    assert "content_context" not in result.data
    assert [question["prompt"] for question in result.data["questions"]] == [task["prompt"] for task in submitted["math_tasks"]]
    assert (config.max_output_tokens, config.reserve_micros) == bounds
    assert calls[0]["max_tokens"] == bounds[0]
    assert len(calls) == 1


@pytest.mark.parametrize("provider", ["openrouter", "codex"])
def test_factual_reasoning_stage_advertises_only_choice_after_all_schema_narrowing(monkeypatch, provider):
    source = "Pflanzen brauchen Licht. Pflanzen brauchen Wasser."
    questions = [
        {"id": f"q{index}", "type": "choice", "prompt": prompt, "answer": 0, "options": options,
         "accepted": [], "hints": ["Lies den bestätigten Satz."], "explanation": source}
        for index, (prompt, options) in enumerate([
            ("Welche Voraussetzung nennt die erste Aussage?", ["Licht", "Metall"]),
            ("Was braucht die Pflanze laut zweiter Aussage?", ["Wasser", "Stein"]),
        ])
    ]
    response = {"subject": "Biologie", "topic": "Pflanzen", "explanation": source, "questions": questions}
    calls = []
    _transport(monkeypatch, provider, copy.deepcopy(response), calls)
    config = _config(provider)
    bounds = (config.max_output_tokens, config.reserve_micros)
    providers.request_provider(config, "unit", {
        "required_subject": "Biologie", "required_topic": "Pflanzen", "material": {"subject": "Biologie", "content": source},
        "study_block": {"mode": "understand", "question_count": 2, "tasks": []},
    })
    submitted = calls[0]["payload"] if provider == "codex" else json.loads(calls[0]["messages"][1]["content"][0]["text"])
    context = submitted["content_context"]
    assert context["question_types"] == ["choice"]
    assert set(context["answer_ui"]) == {"choice"}
    assert context["subject_profiles"][0]["question_types"] == ["choice"]
    assert "matching" not in context
    assert len(calls) == 1
    assert (config.max_output_tokens, config.reserve_micros) == bounds
