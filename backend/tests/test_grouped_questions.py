"""Synthetic contracts and ordinary routes; no real provider or child material."""

import copy
import json
from pathlib import Path

import httpx
import pytest
from conftest import HEADERS, create_child, register
from fastapi.testclient import TestClient
from pydantic import ValidationError
from schulpilot import providers
from schulpilot.answer_evaluation import evaluate
from schulpilot.db import DB, Activity, Attempt, LearningUnit, Material, ProviderConfig
from schulpilot.grouped_questions import canonical, parse_answer, public_group
from schulpilot.main import app
from schulpilot.schemas import Question
from schulpilot.subject_content import PROFILES, validate_output, validate_question
from sqlalchemy import func, select
from test_coaching import normal_unit as _normal_unit
from test_providers import configured

CASE = json.loads((Path(__file__).parents[2] / "testdata/learning_fields_v1.json").read_text())["cases"][0]


def question():
    return copy.deepcopy(CASE["question"])


def unit_value():
    return {"subject": CASE["subject"], "topic": "Begriffe", "explanation": CASE["source"], "questions": [question()]}


@pytest.fixture
def grouped_unit(api, household):
    for client, unit_id, material_id, parent, child in _normal_unit.__wrapped__(api, household):
        with DB.begin() as db:
            unit = db.get(LearningUnit, unit_id)
            unit.subject = CASE["subject"]
            unit.questions = [question(), unit.questions[1]]
            material = db.get(Material, material_id)
            material.subject, material.content = CASE["subject"], CASE["source"]
        client.headers["X-Schulpilot-Capabilities"] = "grouped-v1,visual-v1"
        yield client, unit_id, material_id, parent, child


def endpoint(unit_id):
    return f"/api/units/{unit_id}/questions/fields/answer"


def start(client, unit_id):
    response = client.post(f"/api/units/{unit_id}/start")
    assert response.status_code == 200, response.text
    return response.json()


def test_synthetic_fields_validate_and_keep_one_answer_string():
    q = Question.model_validate(question()).model_dump()
    validate_output(unit_value(), {"material": {"content": CASE["source"]}})
    assert q["answer"] == canonical({"planet": "Erde", "stern": "Sonne"})
    assert evaluate(q, q["answer"])["parts"] == [{"id": "planet", "outcome": "correct"}, {"id": "stern", "outcome": "correct"}]
    assert evaluate(q, canonical({"planet": "anders formuliert", "stern": "Sonne"}))["outcome"] == "uncertain"
    assert evaluate(q, canonical({"planet": "Erde", "stern": "Erde"}))["outcome"] == "incorrect"


@pytest.mark.parametrize("fault", ["one", "five", "duplicate_id", "version_bool", "foreign_kind", "text_options", "one_select", "duplicate_options", "missing_answer", "outer_options", "outer_accepted", "outer_mismatch", "non_grouped"])
def test_invalid_field_contract_is_rejected(fault):
    q = question()
    fields = q["field_group"]["fields"]
    if fault == "one":
        fields.pop()
    elif fault == "five":
        fields.extend([{**fields[0], "id": f"extra{i}"} for i in range(3)])
    elif fault == "duplicate_id":
        fields[1]["id"] = fields[0]["id"]
    elif fault == "version_bool":
        q["field_group"]["version"] = True
    elif fault == "foreign_kind":
        fields[0]["kind"] = "code"
    elif fault == "text_options":
        fields[0]["options"] = ["Erde", "Mond"]
    elif fault == "one_select":
        fields[1]["options"] = ["Sonne"]
    elif fault == "duplicate_options":
        fields[1]["options"] = ["Sonne", "Sonne"]
    elif fault == "missing_answer":
        fields[1]["answer"] = "Mond"
    elif fault == "outer_options":
        q["options"] = ["Erde"]
    elif fault == "outer_accepted":
        q["accepted"] = [q["answer"]]
    elif fault == "outer_mismatch":
        q["answer"] = canonical({"planet": "Mond", "stern": "Sonne"})
    else:
        q.update(type="short", answer="Erde")
    with pytest.raises((ValidationError, ValueError)):
        Question.model_validate(q)


@pytest.mark.parametrize("answer", ['{"version":1,"fields":{"planet":"Erde","planet":"Mond","stern":"Sonne"}}', '{"version":true,"fields":{}}', '{"version":1,"fields":{"alien":"x"}}', 'Erde;Sonne', '{"version":1,"fields":{"planet":2,"stern":"Sonne"}}', '{"version":1,"fields":{"planet":"Erde","stern":"Mond"}}'])
def test_malformed_or_foreign_answer_is_not_assessed(answer):
    with pytest.raises(ValueError):
        parse_answer(question()["field_group"], answer)


def test_partial_draft_and_literal_unicode_punctuation_have_no_semicolon_encoding():
    group = question()["field_group"]
    assert parse_answer(group, canonical({"planet": "Erde"}), partial=True) == {"planet": "Erde", "stern": ""}
    assert parse_answer(group, "", partial=True) == {"planet": "", "stern": ""}
    value = "ä;ß = Wort"
    assert parse_answer(group, canonical({"planet": value, "stern": "Sonne"}))["planet"] == value
    with pytest.raises(ValueError):
        parse_answer(group, canonical({"planet": "Erde"}))


@pytest.mark.parametrize("source", ["Zwergplanet: Erde. Stern: Sonne.", "Planet: Erden. Stern: Sonne.", "Planet: Erde. Stern: Sonnen.", "split"])
def test_pair_prefix_suffix_and_cross_material_evidence_cannot_be_forged(source):
    q = question()
    if source == "split":
        sources = [{"content": "Planet:"}, {"content": "Erde. Stern: Sonne."}]
    else:
        sources = [{"content": source}]
    with pytest.raises(ValueError):
        validate_output({**unit_value(), "questions": [q]}, {"materials": sources})


def test_fields_are_bound_to_original_package_group_and_no_given_graphic_leaks_single_value():
    unit = {**unit_value(), "group_id": "first"}
    with pytest.raises(ValueError):
        validate_output({"units": [unit]}, {"materials": [{"group_id": "second", "content": CASE["source"]}]})
    block = {"kind": "forms", "title": "Stern", "disclosure": "given", "source_excerpt": CASE["source"],
             "labels": ["Sonne"], "numbers": [], "connections": [], "unit": "", "variant": ""}
    with pytest.raises(ValueError):
        validate_question({"version": 1, "evidence_kind": "knowledge", "blocks": [block]}, question(), [CASE["source"]], PROFILES[CASE["subject"]])


def test_public_group_never_contains_private_field_solutions_or_quotes():
    value = public_group(question()["field_group"])
    assert set(value["fields"][0]) == {"id", "label", "kind", "options"}
    assert "source_excerpt" not in json.dumps(value) and '"answer"' not in json.dumps(value)


def test_open_and_parent_unit_transport_redact_nested_private_fields(grouped_unit, api):
    client, unit_id, *_ = grouped_unit
    for reader in (client, api):
        payload = reader.get(f"/api/units/{unit_id}").json()
        group = payload["questions"][0]["field_group"]
        assert all(set(field) == {"id", "label", "kind", "options"} for field in group["fields"])
    assert "answer" not in client.get(f"/api/units/{unit_id}").json()["questions"][0]


def test_old_client_cannot_start_or_submit_grouped_round(grouped_unit):
    client, unit_id, *_ = grouped_unit
    client.headers.pop("X-Schulpilot-Capabilities")
    assert client.post(f"/api/units/{unit_id}/start").status_code == 426
    assert client.post(endpoint(unit_id), json={"answer": question()["answer"]}).status_code == 426
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0


def test_grouped_draft_is_private_revisioned_and_not_an_attempt(grouped_unit, api):
    client, unit_id, *_ = grouped_unit
    value = start(client, unit_id)
    path = f"/api/units/{unit_id}/learning-session"
    body = {"request_key": "grouped-draft-0001", "revision": value["learning_session"]["draft_revision"],
            "question_id": "fields", "answer": canonical({"planet": "Erde"})}
    with DB() as db:
        before = db.scalar(select(func.count()).select_from(Activity))
    first = client.put(path + "/draft", json=body)
    assert first.status_code == 200, first.text
    assert client.put(path + "/draft", json=body).json()["revision"] == first.json()["revision"]
    assert client.get(path).json()["working_memory"]["draft"]["answer"] == body["answer"]
    assert "draft" not in api.get(path).json()["working_memory"]
    assert client.post(endpoint(unit_id), json={"answer": body["answer"]}).status_code == 422
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0
        assert db.scalar(select(func.count()).select_from(Activity)) == before
        assert db.get(LearningUnit, unit_id).active_seconds == 0


def test_grouped_submit_creates_one_idempotent_attempt_with_nonsecret_parts(grouped_unit):
    client, unit_id, *_ = grouped_unit
    start(client, unit_id)
    body = {"answer": question()["answer"], "request_id": "grouped-answer-0001"}
    first = client.post(endpoint(unit_id), json=body)
    assert first.status_code == 200, first.text
    assert first.json()["outcome"] == "correct"
    again = client.post(endpoint(unit_id), json=body)
    assert again.status_code == 200 and again.json()["attempt_id"] == first.json()["attempt_id"]
    reordered = {**body, "answer": '{"version":1,"fields":{"stern":"Sonne","planet":"Erde"}}'}
    equivalent = client.post(endpoint(unit_id), json=reordered)
    assert equivalent.status_code == 200 and equivalent.json()["attempt_id"] == first.json()["attempt_id"]
    with DB() as db:
        attempts = list(db.scalars(select(Attempt)))
        assert len(attempts) == 1
        assert attempts[0].evaluation["parts"] == [{"id": "planet", "outcome": "correct"}, {"id": "stern", "outcome": "correct"}]
        assert "answer" not in json.dumps(attempts[0].evaluation)


def test_grouped_source_change_and_other_child_cannot_submit(grouped_unit, api, mailbox):
    client, unit_id, material_id, *_ = grouped_unit
    start(client, unit_id)
    with TestClient(app, headers=HEADERS) as other:
        user = register(other, mailbox, email="other-fields@example.org")
        create_child(other, user, username="other-fields-child")
        login = other.post("/api/auth/login", json={"username": "other-fields-child", "password": "secure-child-pass-123"})
        assert login.status_code == 200
        other.headers["Authorization"] = "Bearer " + login.json()["token"]
        assert other.post(endpoint(unit_id), json={"answer": question()["answer"]}).status_code in (403, 404)
    with DB.begin() as db:
        db.get(Material, material_id).revision += 1
    assert client.post(endpoint(unit_id), json={"answer": question()["answer"]}).status_code == 409
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0


def test_actual_compact_provider_parse_schema_sourcecheck_and_projection(api, household, monkeypatch):
    parent, _ = household
    configured(parent["families"][0]["id"])
    output = unit_value()
    output["questions"].append({**question(), "id": "second"})
    requests = []

    class Client:
        def __init__(self, **_):
            pass
        def __enter__(self):
            return self
        def __exit__(self, *_):
            pass
        def post(self, url, headers, json):
            requests.append(json)
            return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {"content": __import__("json").dumps(output)}}],
                                              "usage": {"prompt_tokens": 10, "completion_tokens": 10, "cost": 0}})

    monkeypatch.setattr(providers.httpx, "Client", Client)
    with DB() as db:
        config = db.get(ProviderConfig, 1)
        config.provider = "openrouter"
        config.openrouter_free_only = False
        config.capability_evidence = "synthetic upstream=test-upstream"
        result = providers.request_provider(config, "unit", {"material": {"subject": CASE["subject"], "content": CASE["source"]}})
    assert len(requests) == 1 and len(result.data["questions"]) == 2
    schema = requests[0]["response_format"]["json_schema"]["schema"]
    branch = next(branch for branch in schema["$defs"]["Question"]["anyOf"] if branch["properties"]["type"]["enum"] == ["grouped"])
    assert branch["properties"]["field_group"] == {"$ref": "#/$defs/FieldGroup"}
    assert branch["properties"]["answer"]["maxLength"] == 600
    assert requests[0]["max_tokens"] == 4000
    assert "MEHRFELDAUFGABE" in requests[0]["messages"][0]["content"]
    assert public_group(result.data["questions"][0]["field_group"])["fields"][0]["kind"] == "text"


@pytest.mark.parametrize(("expected", "supplied"), [("x²", "x2"), ("10⁻²", "10−2"), ("CO", "Co"), ("X", "x")])
def test_grouped_math_symbols_never_collapse_into_a_different_known_answer(expected, supplied):
    q = question()
    q["field_group"]["fields"][0].update(answer=expected, source_excerpt="Planet: " + expected)
    q["answer"] = canonical({"planet": expected, "stern": "Sonne"})
    assert evaluate(q, canonical({"planet": supplied, "stern": "Sonne"}))["outcome"] == "uncertain"
    assert evaluate(q, q["answer"])["outcome"] == "correct"
    with pytest.raises(ValueError):
        validate_output({**unit_value(), "questions": [q]}, {"material": {"content": "Planet: " + supplied + ". Stern: Sonne."}})


def test_grouped_invalid_unicode_and_existing_answer_limits_remain_rejected():
    q = question()
    with pytest.raises(ValueError):
        parse_answer(q["field_group"], '{"version":1,"fields":{"planet":"\\ud800","stern":"Sonne"}}')
    q["field_group"]["fields"][0]["answer"] = "\ud800"
    with pytest.raises((ValidationError, ValueError)):
        Question.model_validate(q)
    q = question()
    q["field_group"]["fields"] *= 2
    for index, field in enumerate(q["field_group"]["fields"]):
        field["id"] = "field" + str(index)
        field["kind"], field["options"], field["answer"] = "text", [], "x" * 160
    with pytest.raises((ValidationError, ValueError)):
        Question.model_validate(q)


@pytest.mark.parametrize("mode", ["text", "select", "mixed"])
def test_two_to_four_fields_accept_text_select_and_mixed_with_one_aggregate_result(mode):
    q = question()
    q["field_group"]["fields"] += copy.deepcopy(q["field_group"]["fields"])
    for index, field in enumerate(q["field_group"]["fields"]):
        field["id"] = "f" + str(index)
        field["kind"] = mode if mode != "mixed" else ("text" if index % 2 else "select")
        field["options"] = ["Erde", "Sonne"] if field["kind"] == "select" else []
    q["answer"] = canonical({field["id"]: field["answer"] for field in q["field_group"]["fields"]})
    q = Question.model_validate(q).model_dump()
    validate_output({**unit_value(), "questions": [q]}, {"material": {"content": CASE["source"]}})
    result = evaluate(q, q["answer"])
    assert result["outcome"] == "correct" and len(result["parts"]) == 4


def test_unknown_free_field_is_saved_as_uncertain_without_independent_success(grouped_unit):
    client, unit_id, *_ = grouped_unit
    start(client, unit_id)
    response = client.post(endpoint(unit_id), json={"answer": canonical({"planet": "anders formuliert", "stern": "Sonne"}),
                                                  "request_id": "unknown-grouped-001"})
    assert response.status_code == 200, response.text
    result = response.json()
    assert result["outcome"] == "uncertain" and not result["evaluation"]["independent_evidence"]
    assert result["evaluation"]["parts"] == [{"id": "planet", "outcome": "uncertain"}, {"id": "stern", "outcome": "correct"}]
    observations = result["unit"]["learning_session"]["observations"]
    assert observations["uncertain_answers"] == 1 and observations["independent_first_answers"] == 0
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Attempt)) == 1


@pytest.mark.parametrize("prompt", [
    "Kürze 2/4 vollständig.", "Übung: Kürze 2/4 durch 2.", "Erweitere 1/2 mit 3.",
    "Berechne 1/2 + 1/4.", "Wie viel ist 2 + 3?", "Was ist 2 + 3?", "Berechne 3 × 4.",
    "Ein Rechteck ist 3 cm lang und 4 cm breit. Berechne seine Fläche.", "2/4 = __/4",
])
def test_grouped_cannot_bypass_known_arithmetic_or_required_fraction_representation(prompt):
    q = question()
    q["prompt"] = prompt
    q["field_group"]["fields"][0].update(label="Ergebnis", answer="2/4", source_excerpt="Ergebnis: 2/4.")
    q["answer"] = canonical({"planet": "2/4", "stern": "Sonne"})
    source = "Ergebnis: 2/4. Stern: Sonne. Planet: Erde."
    with pytest.raises((ValidationError, ValueError), match="Rechen-"):
        Question.model_validate(q)
    with pytest.raises(ValueError, match="Rechen-"):
        validate_output({**unit_value(), "questions": [q]}, {"material": {"content": source}})
    checked = evaluate(q, q["answer"])
    assert checked["outcome"] == "uncertain"
    assert all(part["outcome"] == "uncertain" for part in checked["parts"])


def test_arithmetic_hidden_in_visible_field_label_also_requires_existing_math_contract():
    q = question()
    q["field_group"]["fields"][0].update(label="Kürze 2/4 vollständig", answer="2/4", source_excerpt="Kürze 2/4 vollständig: 2/4.")
    q["answer"] = canonical({"planet": "2/4", "stern": "Sonne"})
    with pytest.raises((ValidationError, ValueError), match="Rechen-"):
        Question.model_validate(q)
    assert evaluate(q, q["answer"])["outcome"] == "uncertain"


def test_literal_numerator_denominator_concepts_are_not_calculation_questions():
    q = question()
    q["prompt"] = "Benenne Zähler und Nenner des Bruchs 2/4."
    q["field_group"]["fields"] = [
        {"id": "n", "label": "Zähler", "kind": "text", "options": [], "answer": "2", "source_excerpt": "Zähler: 2."},
        {"id": "d", "label": "Nenner", "kind": "text", "options": [], "answer": "4", "source_excerpt": "Nenner: 4."},
    ]
    q["answer"] = canonical({"n": "2", "d": "4"})
    checked = Question.model_validate(q).model_dump()
    validate_output({**unit_value(), "questions": [checked]}, {"material": {"content": "Zähler: 2. Nenner: 4."}})
    assert evaluate(checked, q["answer"])["outcome"] == "correct"


def test_existing_scalar_fraction_representation_checks_remain_strict():
    q = {key: value for key, value in question().items() if key != "field_group"}
    q.update(type="short", prompt="Kürze 2/4 vollständig.", answer="2/4")
    with pytest.raises((ValidationError, ValueError), match="vollständig"):
        Question.model_validate(q)
    q["answer"] = "1/2"
    assert Question.model_validate(q).answer == "1/2"
