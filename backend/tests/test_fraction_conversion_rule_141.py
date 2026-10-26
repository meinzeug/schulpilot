"""Artificial procedure examples, no actual child materials or provider access."""

import copy
import json
from fractions import Fraction

import pytest
from schulpilot import fraction_conversion_rule as rule
from schulpilot import notebook_fraction_compositions as planned
from schulpilot import providers, visual_references
from schulpilot import unit_fraction_compositions as composition
from schulpilot.db import DB
from schulpilot.schemas import ExplanationStep, UnitOutput
from test_notebook_fraction_composition_140 import mock, prepared, wire
from test_notebook_fraction_composition_140 import no_network as no_network
from test_presentation_capability_paths import _config

CONTENT = (
    "Unechte Brüche in gemischte Zahlen umwandeln.\n"
    "Zähler : Nenner → 14 : 5 = 2 Rest 4.\n"
    "Beispiel: 14/5 = 2 + 4/5."
)


def test_pool_is_finite_small_exact_and_equivalence_unique():
    values = list(rule.inputs())
    assert 100 < len(values) < 200 and values == list(rule.inputs())
    assert len({Fraction(n, d) for n, d in values}) == len(values)
    assert all(2 <= d <= 12 and 1 <= n // d <= 3 and 0 < n % d < d for n, d in values)


@pytest.mark.parametrize("text,pairs", [
    ("Zähler : Nenner → 14 : 5 = 3 Rest 4", {(14, 5)}),
    ("Zähler : Nenner → 14 : 5 = 2 Rest 5", {(14, 5)}),
    ("Zähler : Nenner → 14 : 5 = 2 Rest 4", {(15, 5)}),
    ("Nenner : Zähler → 14 : 5 = 2 Rest 4", {(14, 5)}),
    ("Zähler : Nenner ist hier falsch. 14 : 5 = 2 Rest 4", {(14, 5)}),
    ("Zähler : Nenner → -14 : 5 = 2 Rest 4", {(14, 5)}),
    ("Zähler : Nenner → 14 : 0 = 2 Rest 4", {(14, 0)}),
    ("Zähler : Nenner → 10 : 5 = 2 Rest 0", {(10, 5)}),
    ("Beispiel: 14/5 = 2 + 4/5", {(14, 5)}),
])
def test_incomplete_false_reversed_or_unrelated_procedure_never_licenses_new_numbers(text, pairs):
    assert rule.evidence(text, pairs) is None


@pytest.mark.parametrize("separator", [":", "÷", "durch"])
def test_explicit_correct_procedure_retains_exact_quote(separator):
    text = f"Vorher. Zähler {separator} Nenner => 14 {separator} 5 = 2 Rest 4. Nachher."
    proof = rule.evidence(text, {(14, 5)})
    assert proof["quote"] in text and proof["worked_input"] == [14, 5]
    assert proof["worked_whole"] == 2 and proof["worked_remainder"] == 4


def test_new_notebook_tasks_after_original_is_used_remain_source_rule_and_graphic_bound(household, monkeypatch):
    _, original = prepared(household, entry=False, content=CONTENT,
        prompts=["Schreibe 14/5 als gemischte Zahl."])
    payload, binding, output = wire(original)
    before = copy.deepcopy(output)
    calls = []
    mock(monkeypatch, output, calls)
    result = providers.request_provider(_config("openrouter"), "unit", payload)
    assert len(calls) == 1 and output == before and result.cost_micros == 48902
    selected = [candidate for candidate in binding.candidates if candidate.get("question_core")]
    assert len(selected) == 2
    assert all(candidate["proof"]["input"] != [14, 5] for candidate in selected)
    for candidate in selected:
        proof = candidate["proof"]
        assert proof["rule"]["quote"] in CONTENT
        n, d = proof["input"]
        core = candidate["question_core"]
        assert core["answer"] == f"{n // d} {n % d}/{d}"
        q = next(q for q in result.data["questions"] if q["id"] == core["id"])
        assert all(q[key] == core[key] for key in planned.CORE)
        step = ExplanationStep.model_validate(q["explanation_steps"][0])
        step = step.model_dump(mode="json")
        assert len(step["presentation"]["blocks"]) == n // d + 1
        assert step["id"] == candidate["id"]
        assert step["presentation"]["blocks"] == composition._blocks(candidate)
        composition.validate_step(step, composition.compile_candidates(payload["visual_context"]), question=q)
    # The large local finite pool never becomes an enormous provider schema.
    assert len(json.dumps(calls[0]["response_format"])) < 100_000
    with DB() as db:
        visual_references.validate_output(db, result.data, payload)


def test_every_historical_equivalent_is_excluded_and_concurrent_new_value_refused(household):
    prompts = [f"Schreibe {2*n}/{2*d} als gemischte Zahl." for n, d in list(rule.inputs())[:30]]
    _, payload = prepared(household, entry=False, content=CONTENT, prompts=prompts)
    payload, binding, output = wire(payload)
    selected = [candidate for candidate in binding.candidates if candidate.get("question_core")]
    used = {Fraction(n, d) for n, d in list(rule.inputs())[:30]}
    assert all(Fraction(*candidate["proof"]["input"]) not in used for candidate in selected)
    unchanged = binding.hydrate(output)
    before = copy.deepcopy(unchanged)
    with pytest.raises(ValueError, match="inzwischen bereits"):
        planned.validate_history(payload, unchanged, [*prompts, selected[0]["question_core"]["prompt"]])
    assert unchanged == before


def test_finite_pool_exhaustion_still_refuses_without_provider_or_repeated_values(household, monkeypatch):
    _, payload = prepared(household, entry=False, content=CONTENT)
    candidates = composition.compile_candidates(payload["visual_context"])
    prompts = [f"Schreibe {c['proof']['input'][0]}/{c['proof']['input'][1]} als gemischte Zahl."
        for c in candidates if c["disclosure"] == "solution"]
    payload = planned.with_history(payload, prompts)
    calls = []
    mock(monkeypatch, {}, calls)
    with pytest.raises(providers.ProviderError) as error:
        providers.request_provider(_config("openrouter"), "unit", payload)
    assert calls == [] and error.value.billing_result.cost_micros == 0


def test_changed_source_rule_never_reuses_prepared_plan(household):
    _, payload = prepared(household, entry=False, content=CONTENT)
    payload = planned.prepare(payload)
    payload["visual_context"]["sources"][0]["content"] = CONTENT.replace("2 Rest 4", "3 Rest 4")
    with pytest.raises(ValueError):
        planned.prepare(payload)


def test_normal_unplanned_unit_never_receives_the_whole_new_private_pool(household):
    _, payload = prepared(household, entry=False, content=CONTENT)
    payload.pop("notebook_practice")
    payload.pop(planned.HISTORY_KEY)
    schema = providers.strict_schema(UnitOutput, preserve_limits=True)
    binding = composition.bind_schema(schema, payload)
    assert binding is not None and len(binding.candidates) <= 6
    assert not any(candidate.get("proof", {}).get("rule") for candidate in binding.candidates)
