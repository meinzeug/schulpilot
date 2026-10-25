"""Source-probe formats in canonical and actual adapter schemas; synthetic only."""

import copy
import json

import httpx
import pytest
from schulpilot import learning_entry, providers
from schulpilot.schemas import UnitOutput
from test_presentation_capability_paths import _config, _submitted

SUBJECTS = ("Deutsch", "Englisch", "Mathematik")


def source_probe(subject, count):
    plan = {"group_id": None, "subject": subject, "prefix": "public_probe",
        "source_refs": [], "targets": [], "competence_ids": [], "evidence": [],
        "probes": [], "entry_mode": "source_probe"}
    return {"required_subject": subject, "grade": 6,
        "material": {"subject": subject, "topic": "Künstlicher Begriffsvergleich",
            "content": "Eigener künstlicher Quellentext: Ein Begriff und ein Beispiel werden verglichen."},
        "notebook_practice": {"version": 1, "question_count": count},
        "learning_entry": {"version": 1, "catalog_version": "competencies-1",
            "source_refs": [], "source_signature": "a" * 64, "units": [plan], "references": []}}


def question_branches(schema):
    pending = [schema["properties"]["questions"]["items"]]
    while pending:
        node = pending.pop()
        if "$ref" in node:
            pending.append(schema["$defs"][node["$ref"].rsplit("/", 1)[-1]])
        elif "anyOf" in node:
            pending.extend(node["anyOf"])
        else:
            yield node


def formats_by_id(schema):
    result = {}
    for branch in question_branches(schema):
        props = branch["properties"]
        for identifier in props["id"]["enum"]:
            result.setdefault(identifier, set()).update(props["type"]["enum"])
    return result


def assert_source_probe_contract(schema, payload, count):
    questions = schema["properties"]["questions"]
    assert questions["minItems"] == questions["maxItems"] == count
    actual = formats_by_id(schema)
    specs = learning_entry._specs(payload["learning_entry"]["units"][0], count)
    assert set(actual) == {spec["id"] for spec in specs}
    for spec in specs:
        if spec["role"] == "prior_check":
            assert actual[spec["id"]] and actual[spec["id"]] <= {"choice", "short"}
            assert "match" not in actual[spec["id"]]
        else:
            assert "match" in actual[spec["id"]], "The practice format must remain available."
    assert len([spec for spec in specs if spec["role"] == "prior_check"]) == 2


@pytest.mark.parametrize("subject", SUBJECTS)
@pytest.mark.parametrize("count", [2, 5])
def test_canonical_source_probe_restricts_copied_branch_without_changing_formats(subject, count):
    payload = source_probe(subject, count)
    before_payload = copy.deepcopy(payload)
    schema = providers.strict_schema(UnitOutput, preserve_limits=True)
    before_defs = copy.deepcopy(schema["$defs"])
    learning_entry.bind_entry_schema(schema, payload)
    assert_source_probe_contract(schema, payload, count)
    assert schema["$defs"] == before_defs  # Only per-ID copies are restricted.
    assert payload == before_payload


@pytest.mark.parametrize("provider", ["openai", "openrouter", "codex"])
@pytest.mark.parametrize("subject", SUBJECTS)
@pytest.mark.parametrize("count", [2, 5])
def test_actual_outbound_adapter_schema_excludes_match_only_for_prior_checks(monkeypatch, provider, subject, count):
    class Captured(BaseException):
        pass

    payload = source_probe(subject, count)
    before_payload = copy.deepcopy(payload)
    sent = []
    real_client = httpx.Client

    def handler(request):
        sent.append(json.loads(request.content))
        raise Captured

    monkeypatch.setattr(providers.httpx, "Client",
        lambda **kwargs: real_client(transport=httpx.MockTransport(handler)))
    config = _config(provider)
    original_budget = (config.max_output_tokens, config.reserve_micros)
    with pytest.raises(Captured):
        providers.request_provider(config, "unit", payload)
    assert len(sent) == 1  # Artificial in-process adapter boundary; no real HTTP.
    _, schema, _ = _submitted(provider, sent[0])
    assert_source_probe_contract(schema, payload, count)
    assert payload == before_payload
    assert (config.max_output_tokens, config.reserve_micros) == original_budget
    assert sent[0].get("max_tokens", sent[0].get("max_output_tokens")) == original_budget[0]


@pytest.mark.parametrize("indexed", [False, True])
def test_known_fixed_probe_core_stays_exact_and_main_match_remains(indexed):
    payload = source_probe("Mathematik", 5)
    plan = payload["learning_entry"]["units"][0]
    fixed = {"id": "prior_verified", "role": "prior_check", "type": "short",
        "prompt": "Künstliche feste Nennerfrage: Beim Bruch 1/4, welcher Nenner?",
        "answer": "4", "options": [], "accepted": []}
    plan.update(entry_mode="prerequisite_probe", probes=[copy.deepcopy(fixed)])
    before = copy.deepcopy(payload)
    schema = providers.strict_schema(UnitOutput, preserve_limits=True)
    if indexed:
        providers.indexed_choice_schema(schema)
    learning_entry.bind_entry_schema(schema, payload)
    fixed_branches = [branch for branch in question_branches(schema)
        if branch["properties"]["id"]["enum"] == [fixed["id"]]]
    assert fixed_branches
    for branch in fixed_branches:
        props = branch["properties"]
        for key in ("id", "type", "prompt", "answer"):
            assert props[key]["enum"] == [fixed[key]]
        assert props["options"]["maxItems"] == props["accepted"]["maxItems"] == 0
    assert any("match" in kinds for identifier, kinds in formats_by_id(schema).items() if identifier != fixed["id"])
    assert payload == before


def test_model_match_prior_is_still_rejected_without_rewriting_output():
    payload = source_probe("Deutsch", 5)
    plan = payload["learning_entry"]["units"][0]
    questions = [{"id": spec["id"], "type": "short", "prompt": "Künstliche Frage?",
        "answer": "Begriff", "options": [], "accepted": []}
        for spec in learning_entry._specs(plan, 5)]
    questions[0].update(type="match", prompt="Ordne zu.", options=["a", "b"], answer="a;b")
    data = {"subject": "Deutsch", "questions": questions}
    before = copy.deepcopy(data)
    with pytest.raises(ValueError, match="ein einzelnes Antwortformat"):
        learning_entry.validate_entry_output(payload, data)
    assert data == before
