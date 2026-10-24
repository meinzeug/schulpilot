"""Declarative scenes use the real generator/parser and existing evidence gates.

All transport responses below are synthetic local fixtures, never live AI.
"""

import copy
import json
from pathlib import Path

import httpx
import pytest
from pydantic import ValidationError
from schulpilot import providers
from schulpilot.answer_evaluation import evaluate
from schulpilot.config import settings
from schulpilot.db import DB, ProviderConfig
from schulpilot.learning import hint_presentation
from schulpilot.learning_hints import match_parts
from schulpilot.learning_scenes import SceneV1
from schulpilot.schemas import Question, UnitOutput
from schulpilot.security import encrypt
from schulpilot.subject_content import (
    PROFILES,
    Graphic,
    bind_graphic_schema,
    generation_context,
    public_presentation,
    rules_for,
    validate_output,
    validate_question,
)

CASES = json.loads((Path(__file__).parents[2] / "testdata/learning_scenes_v1.json").read_text())["cases"]


@pytest.mark.parametrize("case", CASES, ids=lambda case: case["id"])
def test_individual_scene_is_grounded_and_disclosure_projects_every_frame(case):
    question = Question.model_validate(case["question"]).model_dump()
    validate_question(question["presentation"], question, [case["source"]], PROFILES[case["subject"]])
    visible = public_presentation(question["presentation"], hints=3, closed=True)
    assert visible == case["public_presentation"]
    assert "source_excerpt" not in json.dumps(visible)
    assert all(set(step) == {"caption", "placements", "highlight", "edges"}
               for step in visible["blocks"][0]["scene"]["steps"])
    stage = question["presentation"]["blocks"][0]["disclosure"]
    assert bool(public_presentation(question["presentation"])["blocks"]) == (stage == "given")
    assert evaluate(question, question["answer"])["outcome"] == "correct"


def test_every_subject_can_compose_a_scene_without_weakening_other_profiles():
    for subject, kinds in PROFILES.items():
        assert "scene" in kinds
        schema = bind_graphic_schema(providers.strict_schema(UnitOutput, preserve_limits=True), [subject])
        assert set(schema["$defs"]["Graphic"]["properties"]["kind"]["enum"]) == set(kinds)
    assert "molecule" not in PROFILES["Geschichte"]
    assert "scene" in generation_context(["Geschichte"])["graphic_kinds"]
    assert "scene:" in rules_for(["Geschichte"])
    assert "molecule:" not in rules_for(["Geschichte"])


def _scene_rejects_unsafe_or_unbounded_structure(fault):
    value = copy.deepcopy(CASES[0]["question"]["presentation"]["blocks"][0]["scene"])
    step = value["steps"][0]
    if fault == "duplicate_id":
        value["objects"][1]["id"] = value["objects"][0]["id"]
    elif fault == "invalid_id":
        value["objects"][0]["id"] = "object/script"
    elif fault == "unknown_shape":
        value["objects"][0]["shape"] = "svg"
    elif fault == "unknown_tone":
        value["objects"][0]["tone"] = "#ff0000"
    elif fault == "unknown_layout":
        value["layout"] = "javascript"
    elif fault == "unknown_key":
        step["on_end"] = "execute()"
    elif fault == "missing_placement":
        step["placements"].pop()
    elif fault == "duplicate_placement":
        step["placements"][1]["object_id"] = "o0"
    elif fault == "duplicate_slot":
        step["placements"][1]["slot"] = 0
    elif fault in ("negative_slot", "huge_slot", "bool_slot"):
        step["placements"][0]["slot"] = {"negative_slot": -1, "huge_slot": 12, "bool_slot": True}[fault]
    elif fault == "missing_highlight":
        step["highlight"] = ["missing"]
    elif fault == "duplicate_highlight":
        step["highlight"] = ["o0", "o0"]
    elif fault == "missing_edge":
        step["edges"][0]["end"] = "missing"
    elif fault == "self_edge":
        step["edges"][0]["end"] = "o0"
    elif fault == "duplicate_edge":
        step["edges"].append(copy.deepcopy(step["edges"][0]))
    elif fault in ("negative_duration", "huge_duration", "nan_duration", "bool_duration"):
        value["transition_ms"] = {"negative_duration": -1, "huge_duration": 801,
                                  "nan_duration": float("nan"), "bool_duration": True}[fault]
    elif fault == "empty_steps":
        value["steps"] = []
    elif fault == "too_many_steps":
        value["steps"] = [copy.deepcopy(step) for _ in range(9)]
    elif fault == "too_many_objects":
        value["objects"] *= 5
    elif fault in ("url", "html", "code", "empty_label"):
        value["objects"][0]["label"] = {"url": "https://example.invalid/", "html": "<svg/>",
                                            "code": "eval(answer)", "empty_label": "  "}[fault]
    elif fault == "long_caption":
        step["caption"] = "x" * 501
    with pytest.raises(ValidationError):
        SceneV1.model_validate(value)


def test_scene_rejects_unsafe_or_unbounded_structure():
    for fault in ['duplicate_id', 'invalid_id', 'unknown_shape', 'unknown_tone', 'unknown_layout', 'unknown_key', 'missing_placement', 'duplicate_placement', 'duplicate_slot', 'negative_slot', 'huge_slot', 'bool_slot', 'missing_highlight', 'duplicate_highlight', 'missing_edge', 'self_edge', 'duplicate_edge', 'negative_duration', 'huge_duration', 'nan_duration', 'bool_duration', 'empty_steps', 'too_many_steps', 'too_many_objects', 'url', 'html', 'code', 'empty_label', 'long_caption']:
        _scene_rejects_unsafe_or_unbounded_structure(fault)


def _scene_facts_cannot_be_invented_or_reversed(fault):
    case = copy.deepcopy(CASES[0])
    q = case["question"]
    block = q["presentation"]["blocks"][0]
    scene = block["scene"]
    sources = [case["source"]]
    if fault == "quote":
        scene["steps"][-1]["source_excerpt"] = "Unbekannter Quellenstoff."
    elif fault == "caption":
        scene["steps"][-1]["caption"] = "Nicht belegte Erklärung."
    elif fault == "label":
        scene["objects"][0]["label"] = "Unbelegter Begriff"
    elif fault == "title":
        block["title"] = "Unbelegte Überschrift"
    elif fault == "edge_label":
        scene["steps"][0]["edges"][0]["label"] = "ohne Beleg"
    elif fault == "reversed_edge":
        scene["steps"][0]["edges"][0].update(start="o1", end="o0")
    elif fault == "invented_prompt_relation":
        q["prompt"] += " " + case["source"]
        sources = ["Ein anderer bestätigter Quellenstoff."]
        block["source_excerpt"] = q["prompt"]
    with pytest.raises(ValueError):
        validate_question(q["presentation"], q, sources, PROFILES[case["subject"]])


def test_scene_facts_cannot_be_invented_or_reversed():
    for fault in ['quote', 'caption', 'label', 'title', 'edge_label', 'reversed_edge', 'invented_prompt_relation']:
        _scene_facts_cannot_be_invented_or_reversed(fault)


def _given_scene_cannot_hide_answer_in_any_frame_or_alternative(location):
    case = copy.deepcopy(CASES[2])
    q = case["question"]
    block = q["presentation"]["blocks"][0]
    # Ground the answer in the confirmed text so that it is disclosure, not
    # absent evidence, which must reject the exposure.
    case["source"] += " 5 ist das Ergebnis. 2→3."
    block["source_excerpt"] = case["source"]
    for step in block["scene"]["steps"]:
        step["source_excerpt"] = case["source"]
    validate_question(q["presentation"], q, [case["source"]], PROFILES[case["subject"]])
    if location == "title":
        block["title"] = "5"
    elif location == "alt":
        block["labels"] = ["5"]
    elif location == "object":
        block["scene"]["objects"][1]["label"] = "5"
    elif location == "first_frame":
        block["scene"]["steps"][0]["caption"] = "5"
    elif location == "later_frame":
        block["scene"]["steps"][-1]["caption"] = "5"
    else:
        block["scene"]["steps"][0]["edges"] = [{"start": "o0", "end": "o1", "label": "5"}]
    with pytest.raises(ValueError, match="verrät"):
        validate_question(q["presentation"], q, [case["source"]], PROFILES[case["subject"]])


def test_given_scene_cannot_hide_answer_in_any_frame_or_alternative():
    for location in ['title', 'alt', 'object', 'first_frame', 'later_frame', 'edge']:
        _given_scene_cannot_hide_answer_in_any_frame_or_alternative(location)


def test_given_scene_cannot_reveal_a_single_private_match_pair():
    case = copy.deepcopy(CASES[0])
    q = case["question"]
    q.update(type="match", prompt="Ordne Verdunstung und Start zu.",
             options=["Verdunstung|Kondensation", "Start|Niederschlag"], answer="Kondensation;Niederschlag")
    q["presentation"]["blocks"][0]["disclosure"] = "given"
    with pytest.raises(ValueError, match="Zuordnungspaar"):
        validate_question(q["presentation"], q, [case["source"]], PROFILES[case["subject"]])
    # An arrangement can disclose order without any edge or paired caption.
    for step in q["presentation"]["blocks"][0]["scene"]["steps"]:
        step["edges"] = []
    with pytest.raises(ValueError, match="Zuordnungspaar"):
        validate_question(q["presentation"], q, [case["source"]], PROFILES[case["subject"]])


def test_scene_version_is_an_integer_and_numeric_labels_need_whole_source_tokens():
    scene = copy.deepcopy(CASES[2]["question"]["presentation"]["blocks"][0]["scene"])
    scene["version"] = True
    with pytest.raises(ValidationError):
        SceneV1.model_validate(scene)
    case = copy.deepcopy(CASES[2])
    case["source"] = "12 und 13 sind Summanden."
    q = case["question"]
    q["prompt"] = "Addiere die beiden Zahlen."
    block = q["presentation"]["blocks"][0]
    block.update(title="12", labels=["12", "13"], source_excerpt=case["source"])
    for step in block["scene"]["steps"]:
        step.update(source_excerpt=case["source"], caption="12")
    with pytest.raises(ValueError, match="beschriftung"):
        validate_question(q["presentation"], q, [case["source"]], PROFILES[case["subject"]])


def test_given_scene_cannot_publish_the_private_answer_as_an_object_identifier():
    case = copy.deepcopy(CASES[2])
    q = case["question"]
    scene = q["presentation"]["blocks"][0]["scene"]
    scene["objects"][0]["id"] = "5"
    for step in scene["steps"]:
        for placement in step["placements"]:
            if placement["object_id"] == "o0":
                placement["object_id"] = "5"
        step["highlight"] = ["5" if value == "o0" else value for value in step["highlight"]]
    with pytest.raises(ValueError, match="verrät"):
        validate_question(q["presentation"], q, [case["source"]], PROFILES[case["subject"]])


def test_scene_field_is_optional_only_for_existing_renderers_and_fallback_stays_readable():
    scene_block = copy.deepcopy(CASES[0]["question"]["presentation"]["blocks"][0])
    for value in ({**scene_block, "scene": None}, {**scene_block, "numbers": [1]}, {**scene_block, "labels": []}):
        with pytest.raises(ValidationError):
            Graphic.model_validate(value)
    old = {"kind": "triangle", "title": "Dreieck", "disclosure": "given", "source_excerpt": "g=6cm h=3cm",
           "labels": [], "numbers": [6, 3], "connections": [], "unit": "cm", "variant": ""}
    assert Graphic.model_validate(old).scene is None
    with pytest.raises(ValidationError):
        Graphic.model_validate({**old, "scene": scene_block["scene"]})
    projected = public_presentation({"version": 1, "evidence_kind": "application", "blocks": [old]})
    assert "scene" not in projected["blocks"][0]
    assert CASES[0]["public_presentation"]["blocks"][0]["labels"]


def test_saved_hint_path_reveals_only_the_opened_scene_and_strips_all_quotes():
    q = copy.deepcopy(CASES[0]["question"])
    original = q["presentation"]["blocks"][0]
    q["presentation"]["blocks"] = [{**copy.deepcopy(original), "disclosure": stage}
                                      for stage in ("given", "hint1", "hint2", "solution")]
    # This tests the projection of an already validated snapshot; it does not
    # ask a model for another scene or grant the future stages.
    shown = hint_presentation(q, 1)
    assert [block["disclosure"] for block in shown["blocks"]] == ["given", "hint1"]
    assert "source_excerpt" not in json.dumps(shown)
    assert "solution" not in json.dumps(shown)


def _config(provider):
    object.__setattr__(settings, "real_data_approved", True)
    object.__setattr__(settings, "privacy_evidence", "synthetic scene transport fixture")
    object.__setattr__(settings, "codex_approved", True)
    object.__setattr__(settings, "codex_socket", "/tmp/synthetic-scenes-no-connection.sock")
    object.__setattr__(settings, "codex_auth_mode", "api_key")
    with DB.begin() as db:
        config = db.get(ProviderConfig, 1)
        config.provider = provider
        config.model = "synthetic-scene-model"
        config.emergency_stop = False
        config.structured_capable = True
        config.capability_evidence = "synthetic upstream=fixture-upstream"
        config.privacy_approved = True
        config.privacy_evidence = "synthetic scene fixture"
        config.encrypted_key = encrypt("SYNTHETIC-NOT-A-REAL-KEY")
        config.openrouter_free_only = False
        config.input_per_million_micros = 1
        config.output_per_million_micros = 1
        config.pricing_evidence = "synthetic fixture"
        config.reserve_micros = 1000
    with DB() as db:
        return db.get(ProviderConfig, 1)


def _transport(monkeypatch, provider, response, calls):
    class Client:
        def __init__(self, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def post(self, url, **kwargs):
            calls.append(kwargs["json"])
            usage = {"input_tokens": 200, "output_tokens": 500, "prompt_tokens": 200, "completion_tokens": 500}
            if provider == "openai":
                envelope = {"status": "completed", "usage": usage, "output": [{"type": "message",
                            "content": [{"type": "output_text", "text": json.dumps(response)}]}]}
            elif provider == "openrouter":
                envelope = {"usage": usage, "choices": [{"finish_reason": "stop",
                            "message": {"content": json.dumps(response)}}]}
            else:
                envelope = {"usage": usage, "data": response}
            return httpx.Response(200, json=envelope)

    monkeypatch.setattr(providers.httpx, "Client", Client)


@pytest.mark.parametrize("provider", ["openai", "openrouter", "codex"])
def test_real_provider_pipeline_binds_schema_validates_and_projects_without_extra_call(monkeypatch, provider):
    case = CASES[0]
    response = {"subject": case["subject"], "topic": "Wasser", "explanation": case["source"],
                "questions": [copy.deepcopy(case["question"]), {**copy.deepcopy(case["question"]), "id": "scene_extra"}]}
    calls = []
    _transport(monkeypatch, provider, response, calls)
    result = providers.request_provider(_config(provider), "unit", {
        "required_subject": case["subject"], "material": {"subject": case["subject"], "content": case["source"]},
    })
    assert len(calls) == 1
    assert result.data["questions"][0]["presentation"]["blocks"][0]["scene"]["steps"]
    assert public_presentation(result.data["questions"][0]["presentation"], hints=1) == case["public_presentation"]
    body = calls[0]
    if provider == "openai":
        schema = body["text"]["format"]["schema"]
        instructions = body["instructions"]
    elif provider == "openrouter":
        schema = body["response_format"]["json_schema"]["schema"]
        instructions = body["messages"][0]["content"]
        assert body["provider"]["allow_fallbacks"] is False
    else:
        schema = body["schema"]
        instructions = body["system"]
    assert "scene" in schema["$defs"]["Graphic"]["properties"]["kind"]["enum"]
    assert schema["$defs"]["SceneV1"]["properties"]["version"]["const"] == 1
    assert "scene" in schema["$defs"]["Graphic"]["required"]  # nullable for legacy graphics
    assert {"type": "null"} in schema["$defs"]["Graphic"]["properties"]["scene"]["anyOf"]
    assert "scene:" in instructions
    assert body.get("max_tokens", body.get("max_output_tokens")) <= 4000


def test_provider_rejects_invalid_scene_without_retry_or_partial_unit(monkeypatch):
    case = copy.deepcopy(CASES[0])
    case["question"]["presentation"]["blocks"][0]["scene"]["steps"][-1]["source_excerpt"] = "Erfundener Stoff"
    response = {"subject": case["subject"], "topic": "Wasser", "explanation": case["source"],
                "questions": [case["question"]]}
    calls = []
    _transport(monkeypatch, "openai", response, calls)
    with pytest.raises(providers.ProviderError):
        providers.request_provider(_config("openai"), "unit", {
            "required_subject": case["subject"], "materials": [{"content": case["source"]}],
        })
    assert len(calls) == 1


def test_optional_scene_does_not_rewrite_legacy_provider_graphics(monkeypatch):
    source = "g=6cm und h=3cm"
    q = {"id": "legacy", "type": "short", "prompt": "Wie groß ist die Dreiecksfläche bei g=6cm und h=3cm?",
         "options": [], "answer": "9 cm²", "accepted": [], "hints": ["Halbiere die Rechteckfläche."],
         "explanation": "9 cm²", "presentation": {"version": 1, "evidence_kind": "application", "blocks": [{
             "kind": "triangle", "title": "Dreieck", "disclosure": "given", "source_excerpt": source,
             "labels": [], "numbers": [6, 3], "connections": [], "unit": "cm", "variant": "", "scene": None}]}}
    calls = []
    _transport(monkeypatch, "openai", {"subject": "Mathematik", "topic": "Dreieck", "explanation": source,
                                     "questions": [q]}, calls)
    result = providers.request_provider(_config("openai"), "unit", {
        "required_subject": "Mathematik", "materials": [{"content": source}],
    })
    assert "scene" not in result.data["questions"][0]["presentation"]["blocks"][0]


def test_match_and_order_as_position_match_keep_exact_saved_answer_evidence():
    for pairs in (["Tier|Klasse", "Pflanze|Gruppe"], ["1|Eis", "2|Wasser", "3|Wasserdampf"]):
        answer = ";".join(pair.split("|")[1] for pair in pairs)
        q = Question.model_validate({"id": "matching", "type": "match", "prompt": "Ordne die belegten Begriffe zu.",
                                     "options": pairs, "answer": answer, "accepted": [],
                                     "hints": ["Prüfe die Begriffe."], "explanation": "Belegte Zuordnung."}).model_dump()
        wrong = ";".join(reversed(answer.split(";")))
        assert evaluate(q, answer)["outcome"] == "correct"
        assert evaluate(q, wrong)["outcome"] == "incorrect"
        assert all(part["outcome"] == "correct" for part in match_parts(q, answer))
        assert any(part["outcome"] == "incorrect" for part in match_parts(q, wrong))
    assert "order" not in Question.model_json_schema()["properties"]["type"]["enum"]


def test_generated_unit_validation_still_rejects_forged_source_and_wrong_subject():
    case = CASES[0]
    unit = {"subject": "Unbekanntes Fach", "questions": [case["question"]]}
    with pytest.raises(ValueError, match="Fachprofil"):
        validate_output(unit, {"materials": [{"content": case["source"]}]})


@pytest.mark.parametrize("provider", ["codex", "openrouter"])
def test_server_owned_scene_fixture_replaces_caller_text_before_dispatch(monkeypatch, provider):
    from schulpilot.fixtures import SCENE_FIXTURE_ID, trusted_payload, worksheet

    trusted = trusted_payload("unit", SCENE_FIXTURE_ID)
    assert trusted["required_subject"] == "Geographie"
    assert trusted["scene_request"] == {"kind": "scene", "disclosure": "hint1", "steps": 3, "matching_pairs": 2}
    assert worksheet(SCENE_FIXTURE_ID).startswith(b"\xff\xd8")
    source = trusted["material"]["content"]
    labels = ["Wasser", "Wasserdampf", "Wolke"]
    scene = copy.deepcopy(CASES[0]["question"]["presentation"]["blocks"][0])
    scene.update(title="Wasserkreislauf", source_excerpt=source, labels=labels)
    for obj, label in zip(scene["scene"]["objects"], labels, strict=True):
        obj["label"] = label
    for index, step in enumerate(scene["scene"]["steps"]):
        step.update(source_excerpt=source, caption=f"{labels[index]} → {labels[(index + 1) % 3]}",
                    edges=[{"start": f"o{index}", "end": f"o{(index + 1) % 3}", "label": ""}])
    q = {**copy.deepcopy(CASES[0]["question"]), "prompt": "Welcher Stoff steigt nach der Verdunstung auf?",
         "answer": "Wasserdampf", "presentation": {"version": 1, "evidence_kind": "knowledge", "blocks": [scene]}}
    written = {**copy.deepcopy(q), "id": "second_scene_question"}
    q.update(type="match", prompt="Ordne die beiden Wasserformen ihrem Zustand zu.",
             options=["Wasser|flüssig", "Wasserdampf|gasförmig"], answer="flüssig;gasförmig")
    response = {"subject": "Geographie", "topic": "Wasserkreislauf", "explanation": source,
                "questions": [q, written]}
    calls = []
    _transport(monkeypatch, provider, response, calls)
    object.__setattr__(settings, "synthetic_ai_enabled", True)
    config = _config(provider)
    if provider == "openrouter":
        # Same compact parse/source path, entirely local HTTP envelope. This
        # is not a live free-endpoint capability or cost claim.
        config.model = "synthetic-scene-fixture:free"
        config.input_per_million_micros = config.output_per_million_micros = 0
        monkeypatch.setattr(providers, "verify_free_endpoint", lambda *args: None)
    result = providers.request_provider(config, "unit", {
        "material": {"content": "PRIVATE_CALLER_TEXT_MUST_NOT_LEAVE"},
        "scene_request": {"kind": "execute", "script": "PRIVATE_CALLER_TEXT_MUST_NOT_LEAVE"},
    }, synthetic_fixture=SCENE_FIXTURE_ID)
    assert len(calls) == 1
    assert "PRIVATE_CALLER_TEXT_MUST_NOT_LEAVE" not in json.dumps(calls)
    submitted = (calls[0]["payload"] if provider == "codex"
                 else json.loads(calls[0]["messages"][1]["content"][0]["text"]))
    system = calls[0]["system"] if provider == "codex" else calls[0]["messages"][0]["content"]
    assert submitted["material"]["content"] == source
    assert submitted["scene_request"] == trusted["scene_request"]
    assert "serverseitig festgelegte synthetische Szenentest" in system
    assert result.data["questions"][0]["presentation"]["blocks"][0]["scene"]
    assert not public_presentation(result.data["questions"][0]["presentation"])["blocks"]


@pytest.mark.parametrize("review_only", [False, True])
def test_coach_scene_generation_and_review_only_schema_keep_existing_call_scope(monkeypatch, review_only):
    case = CASES[0]
    goal = {"id": "g1", "label": "Wasserkreislauf", "source_excerpt": case["source"]}
    payload = {"required_subject": case["subject"], "required_topic": "Wasserkreislauf", "next_action": "repair",
               "learning_goals": [goal], "completed_questions": [{"question_id": "done", "learning_goal_id": "g1"}],
               "materials": [{"subject": case["subject"], "content": case["source"]}], "defer_practice": review_only}
    next_unit = {"subject": case["subject"], "topic": "Wasserkreislauf", "explanation": case["source"],
                 "questions": [{**copy.deepcopy(case["question"]), "learning_goal_id": "g1"},
                               {**copy.deepcopy(case["question"]), "id": "next_scene", "learning_goal_id": "g1"}]}
    response = {"explanation": "Vergleiche die belegten Schritte.",
                "question_reviews": [{"question_id": "done", "outcome": "incorrect", "feedback": "Prüfe die Reihenfolge."}]}
    if not review_only:
        response["next_unit"] = next_unit
    calls = []
    _transport(monkeypatch, "openrouter", response, calls)
    result = providers.request_provider(_config("openrouter"), "coach", payload)
    assert len(calls) == 1
    schema = calls[0]["response_format"]["json_schema"]["schema"]
    instructions = calls[0]["messages"][0]["content"]
    if review_only:
        assert result.data["next_unit"] is None
        assert "SceneV1" not in schema["$defs"]
        assert "Graphic" not in schema["$defs"]
        assert "scene:" not in instructions
        assert "graphic_kinds" not in calls[0]["messages"][1]["content"][0]["text"]
    else:
        assert "SceneV1" in schema["$defs"]
        assert "scene:" in instructions
        assert public_presentation(result.data["next_unit"]["questions"][0]["presentation"], hints=1) == case["public_presentation"]


def _matching_unit():
    source = "Hund = Säugetier. Schmetterling = Insekt."
    match = {"id": "pairs", "type": "match", "prompt": "Ordne die beiden Tiere ihrer Klasse zu.",
             "options": ["Hund|Säugetier", "Schmetterling|Insekt"], "answer": "Säugetier;Insekt", "accepted": [],
             "hints": ["Vergleiche die Begriffe im bestätigten Stoff."], "explanation": source}
    written = {"id": "recall", "type": "short", "prompt": "Welche Klasse ist für den Hund belegt?",
               "options": [], "answer": "Säugetier", "accepted": [],
               "hints": ["Lies den belegten Begriff."], "explanation": source}
    return {"subject": "Biologie", "topic": "Tierklassen", "explanation": source, "questions": [match, written]}, source


@pytest.mark.parametrize("context", ["unit", "block", "package", "coach"])
def test_normal_compact_ai_rounds_can_emit_small_source_bound_matching(monkeypatch, context):
    unit, source = _matching_unit()
    payload = {"required_subject": unit["subject"], "required_topic": unit["topic"],
               "material": {"subject": unit["subject"], "topic": unit["topic"], "content": source}}
    function, response = "unit", unit
    if context == "block":
        payload["study_block"] = {"question_count": 2, "mode": "recall", "tasks": []}
    elif context == "package":
        function, response = "package", {"units": [{**unit, "group_id": "g1"}]}
        payload = {"selected_groups": [{"id": "g1", "subject": "Biologie", "estimated_minutes": 5}],
                   "materials": [{"group_id": "g1", "subject": "Biologie", "topic": "Tierklassen", "content": source}]}
    elif context == "coach":
        function = "coach"
        for question in unit["questions"]:
            question["learning_goal_id"] = "g1"
        payload.update(next_action="repair", learning_goals=[{"id": "g1", "label": "Tierklassen", "source_excerpt": source}],
                       completed_questions=[{"question_id": "done", "learning_goal_id": "g1"}])
        response = {"explanation": "Vergleiche die belegten Tierklassen.", "next_unit": unit,
                    "question_reviews": [{"question_id": "done", "outcome": "incorrect", "feedback": "Prüfe die Zuordnung."}]}
    calls = []
    _transport(monkeypatch, "openrouter", response, calls)
    result = providers.request_provider(_config("openrouter"), function, payload)
    assert len(calls) == 1
    actual_unit = result.data["units"][0] if context == "package" else result.data["next_unit"] if context == "coach" else result.data
    actual = actual_unit["questions"][0]
    assert actual["type"] == "match"
    assert actual["options"] == unit["questions"][0]["options"]
    assert actual["answer"] == "Säugetier;Insekt" and actual["accepted"] == []
    assert evaluate(actual, "Insekt;Säugetier")["outcome"] == "incorrect"
    schema = calls[0]["response_format"]["json_schema"]["schema"]
    definitions = schema["$defs"]
    name = "GroundedQuestion" if context == "package" else "PracticeQuestion" if context == "coach" else "Question"
    from schema_helpers import package_questions, resolved

    branches = package_questions(schema) if context == "package" else resolved(schema, definitions[name])["anyOf"]
    branch = next(branch for branch in branches
                  if branch["properties"]["type"]["enum"] == ["match"])
    assert branch["properties"]["options"]["minItems"] == 2
    assert branch["properties"]["options"]["maxItems"] == 4
    assert branch["properties"]["accepted"]["maxItems"] == 0
    assert branch["properties"]["answer"]["type"] == "string"
    assert "pattern" not in branch["properties"]["answer"]
    assert calls[0]["max_tokens"] == 4000
    assert "Verwende keine Zuordnungen" not in calls[0]["messages"][0]["content"]


def test_new_matching_requires_literal_pair_evidence_and_unambiguous_answers():
    from schulpilot.learning_scenes import validate_matching

    unit, source = _matching_unit()
    q = unit["questions"][0]
    validate_matching(q, [source])
    for count in (2, 3, 4):
        bounded = {**q, "options": [f"L{i}|R{i}" for i in range(count)],
                   "answer": ";".join(f"R{i}" for i in range(count))}
        validate_matching(bounded, [". ".join(pair.replace("|", "=") for pair in bounded["options"])])
    for separator in (":", "→", "->", "|"):
        validate_matching(q, [source.replace("=", separator)])
    for fault in ("missing_pair", "reversed_pair", "only_words", "invented_prompt", "variants", "too_many", "separator", "ambiguous"):
        changed, evidence = copy.deepcopy(q), source
        if fault == "missing_pair":
            evidence = "Hund = Säugetier. Schmetterling. Insekt."
        elif fault == "reversed_pair":
            changed.update(options=["Hund|Insekt", "Schmetterling|Säugetier"], answer="Insekt;Säugetier")
        elif fault == "only_words":
            evidence = "Hund Säugetier Schmetterling Insekt"
        elif fault == "invented_prompt":
            changed["prompt"] += " Hund = Säugetier."
        elif fault == "variants":
            changed["accepted"] = ["etwas anderes"]
        elif fault == "too_many":
            changed.update(options=[f"L{i}|R{i}" for i in range(5)], answer=";".join(f"R{i}" for i in range(5)))
            evidence = ". ".join(pair.replace("|", "=") for pair in changed["options"])
            assert Question.model_validate(changed)  # archived snapshots keep the old contract
        elif fault == "separator":
            changed.update(options=["Hund|Säuge;tier", "Schmetterling|Insekt"], answer="Säuge;tier;Insekt")
            evidence = "Hund = Säuge;tier. Schmetterling = Insekt."
        else:
            changed.update(options=["Hund|Tier", "Schmetterling|tier"], answer="Tier;tier")
            evidence = "Hund = Tier. Schmetterling = tier."
        with pytest.raises(ValueError):
            validate_matching(changed, [evidence])


def test_normal_compact_provider_rejects_a_forged_pair_without_retry(monkeypatch):
    unit, source = _matching_unit()
    unit["questions"][0].update(options=["Hund|Insekt", "Schmetterling|Säugetier"], answer="Insekt;Säugetier")
    calls = []
    _transport(monkeypatch, "openrouter", unit, calls)
    with pytest.raises(providers.ProviderError, match="sichere Aufgabenstruktur") as failure:
        providers.request_provider(_config("openrouter"), "unit", {
            "required_subject": "Biologie", "materials": [{"content": source}],
        })
    assert "Hund" not in str(failure.value) and "Säugetier" not in str(failure.value)
    assert len(calls) == 1


def test_generated_matching_cannot_borrow_pair_evidence_from_a_different_group():
    unit, source = _matching_unit()
    unit["group_id"] = "own"
    with pytest.raises(ValueError, match="Quellenstoff"):
        validate_output({"units": [unit]}, {"materials": [
            {"group_id": "own", "content": "Hund und Schmetterling stehen im Heft."},
            {"group_id": "other", "content": source},
        ]}, bounded_matching=True)


def test_codex_factual_packages_keep_the_previous_choice_short_permission(monkeypatch):
    unit, source = _matching_unit()
    calls = []
    _transport(monkeypatch, "codex", {"units": [{**unit, "group_id": "g1"}]}, calls)
    with pytest.raises(providers.ProviderError, match="Antwortvarianten"):
        providers.request_provider(_config("codex"), "package", {
            "selected_groups": [{"id": "g1", "subject": "Biologie", "estimated_minutes": 5}],
            "materials": [{"group_id": "g1", "subject": "Biologie", "topic": "Tierklassen", "content": source}],
        })
    assert len(calls) == 1
    from schema_helpers import package_questions

    branches = package_questions(calls[0]["schema"])
    assert {kind for branch in branches for kind in branch["properties"]["type"]["enum"]} == {"choice", "short"}


def _scene_for_edge_evidence(left, right, source):
    q = copy.deepcopy(CASES[0]["question"])
    q.update(prompt="Beschreibe die ausdrücklich belegte Verbindung.", answer="Beispielantwort")
    block = q["presentation"]["blocks"][0]
    block.update(title=left, source_excerpt=source, labels=[left, right], scene={
        "version": 1, "layout": "row", "transition_ms": 200,
        "objects": [
            {"id": "start", "label": left, "shape": "circle", "tone": "neutral"},
            {"id": "end", "label": right, "shape": "box", "tone": "accent"},
        ],
        "steps": [{"caption": left, "source_excerpt": source,
                   "placements": [{"object_id": "start", "slot": 0}, {"object_id": "end", "slot": 1}],
                   "highlight": ["start"], "edges": [{"start": "start", "end": "end", "label": ""}]}],
    })
    return q


def test_scene_edge_evidence_requires_complete_terms_on_both_sides():
    for left, right, relation in [
        ("A", "B", "A→BC"),
        ("A", "B", "CA→B"),
        ("A", "B", "CA→BC"),
        ("roter Apfel", "grünes Blatt", "dunkelroter Apfel→grünes Blatt"),
        ("roter Apfel", "grünes Blatt", "roter Apfel→grünes Blattwerk"),
    ]:
        # Both labels really occur independently. Only the claimed edge is
        # false, so an unbound-label error cannot conceal the regression.
        source = f"{left}. {right}. {relation}."
        q = _scene_for_edge_evidence(left, right, source)
        with pytest.raises(ValueError, match="belegte Richtung"):
            validate_question(q["presentation"], q, [source], PROFILES["Geographie"])


def test_scene_edge_evidence_preserves_multiword_terms_arrows_and_whitespace():
    for left, right, source in [
        ("A", "B", "A→B und danach C."),
        ("A", "B", "A -> B."),
        ("roter Apfel", "grünes Blatt", "roter Apfel → grünes Blatt."),
        ("roter Apfel", "grünes Blatt", "ROTER  APFEL\t->\nGRÜNES  BLATT und ein weiterer Begriff."),
    ]:
        q = _scene_for_edge_evidence(left, right, source)
        validate_question(q["presentation"], q, [source], PROFILES["Geographie"])


@pytest.mark.parametrize("kind", ["process_graph", "process_cycle", "bar_chart"])
def test_new_match_graphics_cannot_reveal_individual_pairs_before_help(kind):
    if kind == "process_graph":
        subject, source = "Geographie", "Wasser→flüssig. Wasserdampf→gasförmig."
        pairs, labels, numbers = ["Wasser|flüssig", "Wasserdampf|gasförmig"], ["Wasser", "flüssig"], []
        connections = [{"start": 0, "end": 1, "relation": "next"}]
    elif kind == "process_cycle":
        subject, source = "Geographie", "A→B. B→A. C→D."
        pairs, labels, numbers = ["A|B", "C|D"], ["A", "B"], []
        connections = [{"start": 0, "end": 1, "relation": "next"}, {"start": 1, "end": 0, "relation": "next"}]
    else:
        subject, source = "Gemeinschaftskunde", "A = 2. B = 3."
        pairs, labels, numbers = ["A|2", "B|3"], ["A", "B"], [2, 3]
        connections = []
    block = {"kind": kind, "title": labels[0], "disclosure": "given", "source_excerpt": source,
             "labels": labels, "numbers": numbers, "connections": connections, "marks": [], "unit": "", "variant": ""}
    q = Question.model_validate({"id": "pair_graph", "type": "match", "prompt": "Ordne die belegten Begriffe zu.",
                                 "options": pairs, "answer": ";".join(pair.split("|")[1] for pair in pairs),
                                 "accepted": [], "hints": ["Vergleiche die belegten Begriffe."], "explanation": source,
                                 "presentation": {"version": 1, "evidence_kind": "application", "blocks": [block]}}).model_dump()
    original = copy.deepcopy(q)
    with pytest.raises(ValueError, match="Zuordnungspaar"):
        validate_question(q["presentation"], q, [source], PROFILES[subject])
    assert q == original  # Validation cannot rewrite an archived question.
    q["presentation"]["blocks"][0]["disclosure"] = "hint1"
    validate_question(q["presentation"], q, [source], PROFILES[subject])
    assert public_presentation(q["presentation"])["blocks"] == []
    assert public_presentation(q["presentation"], hints=1)["blocks"][0]["kind"] == kind


def test_matching_pair_evidence_cannot_be_created_across_material_boundaries():
    from schulpilot.learning_scenes import validate_matching

    unit, source = _matching_unit()
    unit["group_id"] = "own"
    separated = ["Hund =", "Säugetier. Schmetterling = Insekt."]
    q = unit["questions"][0]
    with pytest.raises(ValueError, match="Quellenstoff"):
        validate_matching(q, separated)
    payload = {
        "selected_groups": [{"id": "own", "subject": "Biologie"}],
        "materials": [{"group_id": "own", "content": text} for text in separated]
                     + [{"group_id": "another", "content": source}],
    }
    with pytest.raises(ValueError, match="Quellenstoff"):
        validate_output({"units": [unit]}, payload, bounded_matching=True)
    with pytest.raises(providers.ProviderError, match="Quellenstoff"):
        providers.validate_factual_package({"units": [unit]}, payload, allow_matching=True)
    # Different complete pairs can live on different confirmed pages; line
    # wrapping within one original text also remains valid.
    whole_pairs = ["Hund =\n Säugetier.", "Schmetterling = Insekt."]
    validate_matching(q, whole_pairs)
    payload["materials"] = [{"group_id": "own", "content": text} for text in whole_pairs]
    validate_output({"units": [unit]}, payload, bounded_matching=True)
    providers.validate_factual_package({"units": [unit]}, payload, allow_matching=True)
