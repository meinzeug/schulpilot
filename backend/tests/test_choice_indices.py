"""Synthetic provider choices keep their explicit option binding end to end."""

import copy
import json

import httpx
import pytest
from package_output_helpers import PackageOutputCapture
from schema_helpers import package_questions
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
    encoded = PackageOutputCapture(monkeypatch)

    class Client:
        def __init__(self, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def post(self, url, headers, **kwargs):
            calls.append(kwargs["json"])
            wire = encoded.wire(output)
            if encoded.binding is not None:
                calls[-1]["_package_schema"] = encoded.binding.canonical_schema
            return httpx.Response(
                200,
                json={
                    "choices": [{"finish_reason": "stop", "message": {"content": json.dumps(wire)}}],
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
    schema = calls[0].get("_package_schema", calls[0]["response_format"]["json_schema"]["schema"])
    choice, written, matching, grouped = package_questions(schema)
    assert choice["properties"]["answer"]["type"] == "integer"
    assert choice["properties"]["options"]["minItems"] == 2
    assert choice["properties"]["accepted"]["maxItems"] == 0
    assert written["properties"]["type"]["enum"] == ["gap", "short"]
    assert written["properties"]["answer"]["type"] == "string"
    assert matching["properties"]["type"]["enum"] == ["match"]
    assert matching["properties"]["options"]["minItems"] == 2
    assert matching["properties"]["options"]["maxItems"] == 4
    assert matching["properties"]["accepted"]["maxItems"] == 0
    assert grouped["properties"]["type"]["enum"] == ["grouped"]
    fields = grouped["properties"]["field_group"]
    assert fields["additionalProperties"] is False
    assert fields["properties"]["version"]["const"] == 1
    assert fields["properties"]["fields"]["minItems"] == 2
    assert fields["properties"]["fields"]["maxItems"] == 4
    assert grouped["properties"]["options"]["maxItems"] == grouped["properties"]["accepted"]["maxItems"] == 0
    assert grouped["properties"]["answer"]["maxLength"] == 600
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


@pytest.mark.parametrize("paid", [False, True])
def test_five_topic_package_uses_all_confirmed_topics_in_one_bounded_request(transport, paid):
    config, output, _, calls = transport
    if paid:
        config.model, config.openrouter_free_only = "synthetic-paid-fixture", False
    questions = output["units"][0]["questions"]
    for index in range(3):
        questions.append({**copy.deepcopy(questions[1]), "id": f"topic_{index}"})
    result = request_provider(config, "package", multipage_payload())
    assert len(result.data["units"][0]["questions"]) == 5 and len(calls) == 1
    submitted = json.loads(calls[0]["messages"][1]["content"][0]["text"])
    assert len(submitted["materials"]) == 5
    assert submitted["selected_groups"][0]["question_count"] == 5
    assert len(submitted["selected_groups"][0]["topics"]) == 5


@pytest.mark.parametrize("paid", [False, True])
def test_provider_cannot_silently_shrink_a_five_topic_package(transport, paid):
    config, _, _, calls = transport
    if paid:
        config.model, config.openrouter_free_only = "synthetic-paid-fixture", False
    with pytest.raises(ProviderError, match="Lernumfang"):
        request_provider(config, "package", multipage_payload())
    assert len(calls) == 1


def test_followup_stage_transports_concrete_new_thinking_and_literal_source_anchors(transport):
    config, output, _, calls = transport
    unit = copy.deepcopy(output["units"][0])
    unit.pop("group_id")
    output.clear()
    output.update(unit)
    tasks = [
        {"number": 1, "action": "Ein neues Bruchbeispiel begründen.", "source_excerpt": "1/2 = 2/4"},
        {
            "number": 2,
            "action": "Einen ausdrücklich markierten Denkfehler korrigieren.",
            "source_excerpt": "Beide Zahlen mit 2 multiplizieren.",
        },
    ]
    payload = {
        "required_subject": unit["subject"],
        "required_topic": unit["topic"],
        "material": {"subject": unit["subject"], "content": "1/2 = 2/4. Beide Zahlen mit 2 multiplizieren."},
        "study_block": {"mode": "detective", "question_count": 2, "tasks": tasks},
        "previous_prompts": ["Welche Zahl ist der Nenner von 1/2?"],
    }
    before = copy.deepcopy(payload)
    result = request_provider(config, "unit", payload)
    assert result.data["questions"][0]["answer"] == "2/4"
    assert len(calls) == 1 and payload == before
    request = calls[0]
    submitted = json.loads(request["messages"][1]["content"][0]["text"])
    assert submitted["study_block"]["tasks"] == tasks
    assert submitted["previous_prompts"] == payload["previous_prompts"]
    instructions = request["messages"][0]["content"]
    assert "pro Eintrag in study_block.tasks genau eine Aufgabe" in instructions
    assert "bloß leicht umformuliert" in instructions
    assert "Ein Zusatz wie 'Erneut:' macht eine alte Frage nicht neu" in instructions
    assert request["response_format"]["json_schema"]["schema"]["properties"]["questions"]["minItems"] == 2
    assert request["provider"]["allow_fallbacks"] is False
    assert request["provider"]["max_price"] == {"prompt": 0, "completion": 0, "request": 0}


def factual_stage(transport, mode="understand", *, written=False):
    config, output, _, calls = transport
    unit = copy.deepcopy(output["units"][0])
    unit.pop("group_id")
    unit.update(
        subject="Sachunterricht", topic="Sonne und Licht", explanation="Die Sonne ist ein Stern. Sie sendet Licht aus."
    )
    for index, question in enumerate(unit["questions"]):
        question.update(
            type="choice",
            prompt=f"Welche Begründung passt zu Beobachtung {index + 1}?",
            options=["Die Sonne sendet Licht aus.", "Die Sonne ist eine Lampe."],
            answer=0,
            accepted=[],
            hints=["Denke an das Licht der Sonne."],
            explanation="Die Sonne ist ein Stern und sendet Licht aus.",
        )
    if written:
        unit["questions"][-1].update(
            type="short", prompt="Welcher Begriff bezeichnet die Sonne?", options=[], answer="Stern"
        )
    output.clear()
    output.update(unit)
    payload = {
        "required_subject": unit["subject"],
        "required_topic": unit["topic"],
        "material": {"subject": unit["subject"], "content": "Die Sonne ist ein Stern. Sie sendet Licht aus."},
        "study_block": {"mode": mode, "question_count": 2, "tasks": []},
        "previous_prompts": [],
    }
    return config, payload, calls


@pytest.mark.parametrize("mode", ["understand", "detective", "apply"])
def test_factual_reasoning_stage_requests_real_explanations_without_an_impossible_empty_branch(transport, mode):
    config, payload, calls = factual_stage(transport, mode)
    result = request_provider(config, "unit", payload)
    assert len(result.data["questions"]) == 2 and all(q["type"] == "choice" for q in result.data["questions"])
    schema = calls[0].get("_package_schema", calls[0]["response_format"]["json_schema"]["schema"])
    question = schema["$defs"]["Question"]
    assert "anyOf" not in question
    assert question["properties"]["type"]["enum"] == ["choice"]
    assert question["properties"]["answer"]["type"] == "integer"
    assert "nur type=choice" in calls[0]["messages"][0]["content"]
    assert "sowohl Auswahlaufgaben als auch kurze Eingaben" not in calls[0]["messages"][0]["content"]


def test_reasoning_stage_rejects_unrequested_definition_instead_of_rewriting_it(transport):
    config, payload, calls = factual_stage(transport, written=True)
    with pytest.raises(ProviderError, match="Verständnisaufgaben"):
        request_provider(config, "unit", payload)
    assert len(calls) == 1


def test_recall_still_accepts_a_source_backed_short_response(transport):
    config, payload, calls = factual_stage(transport, "recall", written=True)
    result = request_provider(config, "unit", payload)
    assert result.data["questions"][-1]["type"] == "short"
    assert result.data["questions"][-1]["answer"] == "Stern"
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
    schema = calls[0].get("_package_schema", calls[0]["response_format"]["json_schema"]["schema"])
    choice, written, matching, grouped = package_questions(schema)
    assert choice["properties"]["accepted"]["maxItems"] == 0
    assert written["properties"]["accepted"]["maxItems"] == 0
    assert written["properties"]["options"]["maxItems"] == 0
    assert matching["properties"]["type"]["enum"] == ["match"]
    assert matching["properties"]["accepted"]["maxItems"] == 0
    assert grouped["properties"]["type"]["enum"] == ["grouped"]
    fields = grouped["properties"]["field_group"]
    assert fields["additionalProperties"] is False
    assert fields["properties"]["version"]["const"] == 1
    assert fields["properties"]["fields"]["minItems"] == 2
    assert fields["properties"]["fields"]["maxItems"] == 4
    assert grouped["properties"]["options"]["maxItems"] == grouped["properties"]["accepted"]["maxItems"] == 0
    assert grouped["properties"]["answer"]["maxLength"] == 600
    assert "pattern" not in matching["properties"]["answer"]
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


@pytest.fixture
def practice_transport(transport):
    config, output, _, calls = transport
    unit = copy.deepcopy(output["units"][0])
    unit.pop("group_id")
    for index, question in enumerate(unit["questions"]):
        question.update(id=f"q{index + 1}", learning_goal_id=f"g{index + 1}")
    output.clear()
    output.update(unit)
    payload = {
        "review": True,
        "required_subject": unit["subject"],
        "required_topic": unit["topic"],
        "learning_goals": [
            {"id": "g1", "label": "Brüche addieren", "source_excerpt": "Bei gleichem Nenner die Zähler addieren."},
            {"id": "g2", "label": "Brüche kürzen", "source_excerpt": "Zähler und Nenner durch dieselbe Zahl teilen."},
        ],
        "focus_goal_ids": ["g1", "g2"],
        "previous_prompts": [],
    }
    return config, payload, output, calls


def test_practice_schema_binds_each_unique_question_to_its_required_goal_without_reassignment(practice_transport):
    config, payload, output, calls = practice_transport
    before = copy.deepcopy(payload)
    result = request_provider(config, "unit", payload)
    assert len(calls) == 1 and payload == before
    assert [(q["id"], q["learning_goal_id"]) for q in result.data["questions"]] == [("q1", "g1"), ("q2", "g2")]
    submitted = json.loads(calls[0]["messages"][1]["content"][0]["text"])
    assert [(q["id"], q["learning_goal_id"]) for q in submitted["practice_tasks"]] == [("q1", "g1"), ("q2", "g2")]
    assert [q["source_excerpt"] for q in submitted["practice_tasks"]] == [
        g["source_excerpt"] for g in payload["learning_goals"]
    ]
    schema = calls[0].get("_package_schema", calls[0]["response_format"]["json_schema"]["schema"])
    branches = schema["$defs"]["PracticeQuestion"]["anyOf"]
    assert len(branches) == 8
    assert sum(branch["properties"]["type"]["enum"] == ["grouped"] for branch in branches) == 2
    assert {(b["properties"]["id"]["enum"][0], b["properties"]["learning_goal_id"]["enum"][0]) for b in branches} == {
        ("q1", "g1"),
        ("q2", "g2"),
    }
    assert {b["properties"]["answer"]["type"] for b in branches} == {"integer", "string"}
    assert result.data["questions"][0]["answer"] == "2/4"
    assert output["questions"][0]["answer"] == 2


def test_practice_does_not_silently_relabel_two_questions_on_the_same_goal(practice_transport):
    config, payload, output, calls = practice_transport
    output["questions"][1]["learning_goal_id"] = "g1"
    original = copy.deepcopy(output)
    with pytest.raises(ProviderError, match="vorgegebenen Lernzielen"):
        request_provider(config, "unit", payload)
    assert output == original and len(calls) == 1


def test_one_repair_goal_gets_two_distinct_tasks_without_inventing_another_goal(practice_transport):
    config, payload, output, calls = practice_transport
    payload["focus_goal_ids"] = ["g1"]
    output["questions"][1]["learning_goal_id"] = "g1"
    result = request_provider(config, "unit", payload)
    assert {q["learning_goal_id"] for q in result.data["questions"]} == {"g1"}
    submitted = json.loads(calls[0]["messages"][1]["content"][0]["text"])
    assert [q["id"] for q in submitted["practice_tasks"]] == ["q1", "q2"]
    assert {q["learning_goal_id"] for q in submitted["practice_tasks"]} == {"g1"}
