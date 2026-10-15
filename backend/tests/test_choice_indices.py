"""Synthetic provider choices keep their explicit option binding end to end."""

import copy
import json

import httpx
import pytest
from schulpilot import providers
from schulpilot.db import DB, ProviderConfig
from schulpilot.providers import ProviderError, request_provider
from schulpilot.schemas import PackageOutput, PracticeUnitOutput, UnitOutput
from schulpilot.synthetic import sample_unit
from test_providers import configured


@pytest.fixture
def transport(api, household, monkeypatch):
    parent, _ = household
    configured(parent["families"][0]["id"])
    with DB() as db:
        config = db.get(ProviderConfig, 1)
    config.provider = "openrouter"
    config.model = "synthetic-fixture:free"
    config.capability_evidence = "synthetic transport upstream=test/fp8"
    config.input_per_million_micros = config.output_per_million_micros = 0
    output = {"units": [{**sample_unit(), "group_id": "g1"}]}
    output["units"][0]["questions"] = output["units"][0]["questions"][:2]
    choice = output["units"][0]["questions"][0]
    # Put the correct answer last: this catches a first-option fallback and
    # off-by-one conversion, rather than merely mirroring the decoder.
    choice["options"] = ["1/8", "2/8", "2/4"]
    choice["answer"] = 2
    calls = []

    class Client:
        def __init__(self, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def post(self, url, headers, **kwargs):
            calls.append(kwargs["json"])
            return httpx.Response(
                200,
                json={
                    "choices": [{"finish_reason": "stop", "message": {"content": json.dumps(output)}}],
                    "usage": {"prompt_tokens": 100, "completion_tokens": 200, "cost": 0},
                },
            )

    monkeypatch.setattr(providers.httpx, "Client", Client)
    monkeypatch.setattr(providers, "verify_free_endpoint", lambda *args: None)
    return config, output, choice, calls


def test_package_choice_index_becomes_existing_full_answer_without_extra_call(transport):
    config, output, _, calls = transport
    result = request_provider(config, "package", {"materials": [{"content": "Synthetic fractions."}]})
    question = result.data["units"][0]["questions"][0]
    assert question["answer"] == "2/4"
    assert question["options"] == ["1/8", "2/8", "2/4"]
    assert result.data["units"][0]["questions"][1] == output["units"][0]["questions"][1]
    PackageOutput.model_validate(result.data)
    assert result.cost_micros == 0 and len(calls) == 1
    schema = calls[0]["response_format"]["json_schema"]["schema"]
    choice, written = schema["$defs"]["Question"]["anyOf"]
    assert choice["properties"]["answer"]["type"] == "integer"
    assert choice["properties"]["options"]["minItems"] == 2
    assert choice["properties"]["accepted"]["maxItems"] == 0
    assert written["properties"]["type"]["enum"] == ["gap", "short"]
    assert written["properties"]["answer"]["type"] == "string"
    assert calls[0]["provider"]["allow_fallbacks"] is False
    assert calls[0]["provider"]["data_collection"] == "deny"


@pytest.mark.parametrize("answer", [-1, 3, 999, True, 1.5, "B", "2"])
def test_invalid_choice_reference_is_rejected_without_guessing_or_retry(transport, answer):
    config, _, choice, calls = transport
    choice["answer"] = answer
    with pytest.raises(ProviderError):
        request_provider(config, "package", {})
    assert len(calls) == 1


def test_index_does_not_bypass_arithmetic_or_duplicate_checks(transport):
    config, _, choice, calls = transport
    choice["answer"] = 0  # Explicit but mathematically wrong.
    with pytest.raises(ProviderError, match="Aufgabenprüfung"):
        request_provider(config, "package", {})
    choice["answer"] = 2
    choice["options"][0] = "2/4"
    with pytest.raises(ProviderError, match="Aufgabenprüfung"):
        request_provider(config, "package", {})
    assert len(calls) == 2


def test_index_cannot_hide_extra_accepted_answers(transport):
    config, _, choice, calls = transport
    choice["accepted"] = ["1/8"]
    with pytest.raises(ProviderError):
        request_provider(config, "package", {})
    assert len(calls) == 1


def test_written_answer_and_known_coach_goal_ids_survive_transport():
    unit = sample_unit()
    unit["questions"] = unit["questions"][:2]
    unit["questions"][0]["answer"] = 0
    for question in unit["questions"]:
        question["learning_goal_id"] = "g2"
    original = copy.deepcopy(unit)
    report = {"next_unit": unit, "question_reviews": [{"question_id": "old", "outcome": "correct"}]}
    decoded = providers.decode_choice_indices(report)
    assert decoded["question_reviews"] == [{"question_id": "old", "outcome": "correct"}]
    assert decoded["next_unit"]["questions"][1] == original["questions"][1]
    assert decoded["next_unit"]["questions"][0]["learning_goal_id"] == "g2"
    PracticeUnitOutput.model_validate(decoded["next_unit"])
    schema = providers.strict_schema(PracticeUnitOutput, preserve_limits=True)
    providers.indexed_choice_schema(schema)
    assert all(
        branch["properties"]["learning_goal_id"]["enum"] == ["g1", "g2", "g3", "g4"]
        for branch in schema["$defs"]["PracticeQuestion"]["anyOf"]
    )
    # The public/persisted contract still rejects numeric choice answers.
    with pytest.raises(ValueError):
        UnitOutput.model_validate(original)


def multipage_payload(groups=1, topics=5, minutes=8):
    return {
        "selected_groups": [
            {"id": f"g{i + 1}", "subject": "Mathematik", "estimated_minutes": minutes} for i in range(groups)
        ],
        "materials": [
            {"group_id": f"g{i + 1}", "page_number": j + 1, "topic": f"Synthetic topic {j + 1}", "content": "Example"}
            for i in range(groups)
            for j in range(topics)
        ],
    }


@pytest.mark.parametrize(
    ("groups", "topics", "minutes", "expected"),
    [(1, 5, 8, [5]), (2, 5, 8, [3, 3]), (3, 5, 8, [2, 2, 2]), (1, 5, 5, [2]), (1, 1, 8, [2])],
)
def test_package_topics_expand_only_within_time_and_total_question_budget(groups, topics, minutes, expected):
    payload = multipage_payload(groups, topics, minutes)
    before = copy.deepcopy(payload)
    schema = providers.strict_schema(PackageOutput, preserve_limits=True)
    prepared, targets = providers.prepare_package_schema(schema, payload)
    assert list(targets.values()) == expected
    assert payload == before  # No changes to the worker's confirmed source snapshot.
    assert sum(targets.values()) <= 6
    assert [group["question_count"] for group in prepared["selected_groups"]] == expected
    assert all(len(group["topics"]) == topics for group in prepared["selected_groups"])
    for branch, count in zip(schema["properties"]["units"]["items"]["anyOf"], expected, strict=True):
        assert branch["properties"]["questions"]["minItems"] == count
        assert branch["properties"]["questions"]["maxItems"] == count


def test_five_topic_package_uses_all_confirmed_topics_in_one_bounded_request(transport):
    config, output, _, calls = transport
    questions = output["units"][0]["questions"]
    for index in range(3):
        questions.append({**copy.deepcopy(questions[1]), "id": f"topic_{index}"})
    result = request_provider(config, "package", multipage_payload())
    assert len(result.data["units"][0]["questions"]) == 5 and len(calls) == 1
    submitted = json.loads(calls[0]["messages"][1]["content"][0]["text"])
    assert len(submitted["materials"]) == 5
    assert submitted["selected_groups"][0]["question_count"] == 5
    assert len(submitted["selected_groups"][0]["topics"]) == 5


def test_provider_cannot_silently_shrink_a_five_topic_package(transport):
    config, _, _, calls = transport
    with pytest.raises(ProviderError, match="Lernumfang"):
        request_provider(config, "package", multipage_payload())
    assert len(calls) == 1


def factual_output(answer="Stern", accepted=None, options=None):
    return {
        "units": [
            {
                "group_id": "g1",
                "questions": [
                    {"type": "short", "answer": answer, "accepted": accepted or [], "options": options or []}
                ],
            }
        ]
    }


def factual_payload():
    return {
        "selected_groups": [{"id": "g1", "subject": "Sachkunde", "estimated_minutes": 8}],
        "materials": [{"group_id": "g1", "content": "Die Sonne ist ein Stern. Der Mond umkreist die Erde."}],
    }


@pytest.mark.parametrize("answer", ["Stern", "stern", "STERN"])
def test_initial_factual_recall_accepts_a_term_in_the_confirmed_material(answer):
    providers.validate_factual_package(factual_output(answer), factual_payload())


@pytest.mark.parametrize(
    ("answer", "accepted", "options"),
    [("1/4", [], []), ("Ste", [], []), ("Stern", ["Mond"], []), ("Stern", [], ["Stern", "Mond"])],
)
def test_unrelated_numeric_answers_partial_words_and_wrong_aliases_are_not_approved(answer, accepted, options):
    with pytest.raises(ProviderError):
        providers.validate_factual_package(factual_output(answer, accepted, options), factual_payload())


def test_initial_factual_schema_requests_no_unchecked_aliases_or_math_examples(transport):
    config, output, _, calls = transport
    payload = factual_payload()
    output["units"][0].update(subject="Sachkunde", topic="Himmelskörper")
    q1, q2 = output["units"][0]["questions"]
    q1.update(prompt="Was ist die Sonne?", options=["Ein Stern", "Ein Planet"], answer=0)
    q2.update(type="short", prompt="Was umkreist die Erde?", options=[], answer="Mond", accepted=[])
    result = request_provider(config, "package", payload)
    assert result.data["units"][0]["questions"][1]["answer"] == "Mond"
    schema = calls[0]["response_format"]["json_schema"]["schema"]
    choice, written = schema["$defs"]["GroundedQuestion"]["anyOf"]
    assert choice["properties"]["accepted"]["maxItems"] == 0
    assert written["properties"]["accepted"]["maxItems"] == 0
    assert written["properties"]["options"]["maxItems"] == 0
    assert providers.ARITHMETIC_RULES not in calls[0]["messages"][0]["content"]
    assert len(calls) == 1


@pytest.mark.parametrize("answer", ["ALPHA + BETA", "ALPHA, BETA", "ALPHA BETA GAMMA DELTA EPSILON ZETA"])
def test_factual_short_inputs_never_require_a_formula_or_multiple_part_answer(answer):
    payload = factual_payload()
    payload["materials"][0]["content"] += " Synthetischer Ausdruck: " + answer
    with pytest.raises(ProviderError, match="kurze eindeutige Antwort"):
        providers.validate_factual_package(factual_output(answer), payload)


def test_fact_recall_does_not_mislabel_an_open_question_as_a_gap():
    output = factual_output()
    output["units"][0]["questions"][0]["type"] = "gap"
    with pytest.raises(ProviderError):
        providers.validate_factual_package(output, factual_payload())
