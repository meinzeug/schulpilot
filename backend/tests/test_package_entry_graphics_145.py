"""Artificial photo-like fractions plus exact curated diagnostic, no paid call."""
import copy
import json

import httpx
import pytest
from package_output_helpers import PackageOutputCapture
from schulpilot import competences, learning_entry, package_part_output, providers, visual_references
from schulpilot import package_prepared_graphics as prepared
from schulpilot.db import DB
from schulpilot.schemas import PackageOutput
from schulpilot.subject_content import bind_graphic_schema
from test_package_prepared_graphics import payload_for, wire_step
from test_package_transport import config


def fixture():
    # Enough ordinary photographed examples to exhaust the old eight-base menu.
    value = payload_for("Unechte Brüche und gemischte Zahlen: 9/4 = 2 1/4. "
        "Brüche kürzen und erweitern: 2/3 = 4/6. " + " ".join(f"{n}/24" for n in range(8)))
    rows = competences.catalogue()
    probes = [learning_entry._probe(rows[key], "artificial-package-145", set(), str(i))
        for i, key in enumerate(("math.fractions.meaning", "math.fractions.components"))]
    references = [competences.resolve_reference(p["reference_id"], competences.VERSION) for p in probes]
    value["learning_entry"] = {"version": 1, "catalog_version": competences.VERSION,
        "units": [{"group_id": "g1", "subject": "Mathematik", "entry_mode": "prerequisite_probe",
            "prefix": "artificial", "probes": probes}], "references": references}
    with DB() as db:
        value = visual_references.with_foundation_context(db, value)
    return value, probes


def bind(value):
    schema = providers.strict_schema(PackageOutput, preserve_limits=True)
    providers.prepare_package_schema(schema, value, partition=True)
    bind_graphic_schema(schema, ["Mathematik"])
    visual_references.bind_schema(schema, value)
    learning_entry.bind_entry_schema(schema, value)
    binding = package_part_output.bind_schema(schema, value)
    return schema, binding


def output(value, probes):
    _, binding = bind(value)
    intro = next(row for row in binding.candidates if row["disclosure"] == "given")
    questions = []
    for probe in probes:
        candidate = next(row for row in binding.candidates if row.get("question_core", {}).get("id") == probe["id"]
            and row["disclosure"] == "solution")
        questions.append({**{key: probe[key] for key in learning_entry.CORE},
            "hints": ["Der Nenner beschreibt alle gleich großen Teile."], "explanation": candidate["text"],
            "presentation": None, "explanation_steps": [wire_step(candidate)]})
    return {"units": [{"group_id": "g1", "subject": "Mathematik", "topic": "Brüche verstehen",
        "explanation": intro["text"], "explanation_steps": [wire_step(intro)], "questions": questions}]}


def test_fixed_meaning_and_components_keep_exact_cores_and_each_get_a_solution_graphic():
    value, probes = fixture()
    before = copy.deepcopy(value)
    schema, binding = bind(value)
    cores = {row["question_core"]["id"] for row in binding.candidates if row.get("question_core")}
    assert cores == {p["id"] for p in probes}
    assert all(row["disclosure"] in ("given", "solution") for row in binding.candidates if row.get("question_core"))
    hydrated = binding.hydrate(output(value, probes))
    learning_entry.validate_entry_output(value, hydrated)
    canonical = PackageOutput.model_validate(hydrated).model_dump(mode="json")
    with DB() as db:
        visual_references.validate_output(db, canonical, value)
    assert all({key: q[key] for key in learning_entry.CORE} == {key: p[key] for key in learning_entry.CORE}
        for q, p in zip(canonical["units"][0]["questions"], probes, strict=True))
    assert schema and value == before


@pytest.mark.parametrize("fault", ["id", "prompt", "answer", "type", "options", "accepted", "other_probe"])
def test_hydrator_does_not_admit_changed_probe_or_cross_pair_its_graphic(fault):
    value, probes = fixture()
    _, binding = bind(value)
    wire = output(value, probes)
    question = wire["units"][0]["questions"][0]
    if fault == "other_probe":
        question["explanation_steps"] = wire["units"][0]["questions"][1]["explanation_steps"]
    else:
        question[fault] = ["forged"] if fault in ("options", "accepted") else "forged"
    before = copy.deepcopy(wire)
    with pytest.raises(ValueError, match="Frageparametern"):
        binding.hydrate(wire)
    assert wire == before


@pytest.mark.parametrize("fault", ["example_digest", "digest", "content", "group_id", "reference_id"])
def test_curated_label_or_answer_alone_cannot_create_a_fixed_question_proof(fault):
    value, probes = fixture()
    source = next(s for s in value["visual_context"]["sources"] if s.get("example_question_id") == probes[0]["id"])
    source[fault] = "forged"
    rows = prepared.compile_candidates(value)
    assert not any(row.get("question_core", {}).get("id") == probes[0]["id"] for row in rows)


def test_actual_adapter_transports_fixed_probes_and_graphics_without_changing_limits(monkeypatch):
    value, probes = fixture()
    data = output(value, probes)
    capture, calls, client = PackageOutputCapture(monkeypatch), [], httpx.Client

    def handler(request):
        body = json.loads(request.content)
        calls.append(body)
        assert body["max_tokens"] == 8000 and body["reasoning"]["effort"] == "medium"
        return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {
            "content": json.dumps(capture.wire(data))}}], "usage": {"prompt_tokens": 100, "completion_tokens": 100,
            "cost": 0.002}})

    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: client(transport=httpx.MockTransport(handler)))
    monkeypatch.setattr(providers, "external_allowed", lambda *a, **kw: None)
    monkeypatch.setattr(providers, "decrypt", lambda _: "artificial-no-network-key")
    monkeypatch.setattr("schulpilot.model_routing.selection", lambda _: {"route": {"upstreams": ["azure"]}, "region": "standard"})
    route = config()
    route.max_output_tokens, route.reserve_micros = 8000, 250000
    result = providers.request_provider(route, "package", value)
    assert len(calls) == 1 and result.cost_micros == 2000
    assert len(result.data["units"][0]["questions"]) == 2
    assert all(q["explanation_steps"][0]["presentation"]["blocks"][0]["kind"] == "fraction"
        for q in result.data["units"][0]["questions"])
