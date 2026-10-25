"""Public synthetic source chains on the real package/schema/hydration path."""
import copy

import pytest
from schulpilot import package_output_transport, package_transport, visual_references
from schulpilot.db import DB
from schulpilot.schemas import PackageOutput
from test_package_prepared_graphics import bind, payload_for, wire_step

CASES = [
    ("Deutsch", "Vorsilbe (Präfix) | + | Wortstamm | + | Nachsilbe (Suffix)", "sentence"),
    ("Biologie", "Raupe → Puppe → Schmetterling.", "scene"),
    ("Geographie", "Quelle -> Fluss -> Mündung.", "scene"),
]


def fixture(subject, source):
    payload = payload_for(source, subject)
    payload["materials"][0]["topic"] = "Künstliche belegte Bausteine"
    payload["visual_context"]["sources"][0]["topic"] = "Künstliche belegte Bausteine"
    schema, binding = bind(payload)
    return payload, schema, binding


def response(payload, binding):
    intro = next(row for row in binding.candidates if row["disclosure"] == "given")
    graphic = next(row for row in binding.candidates if row["disclosure"] == "solution")
    labels = graphic["block"]["labels"]
    questions = []
    for index in range(2):
        prompt = f"Was folgt in der Originalfolge {labels[0]} und {labels[1]} auf {labels[0]}?" if index == 0 else f"Welcher Originalausdruck steht in der Folge {labels[0]} und {labels[1]} am Anfang?"
        questions.append({"id": f"q{index}", "type": "short", "prompt": prompt,
            "options": [], "answer": labels[1] if index == 0 else labels[0],
            "accepted": [], "hints": ["Lies die vollständige Originalfolge."],
            "explanation": "Die Originalfolge ist vollständig im belegten Beispiel sichtbar.",
            "presentation": None, "field_group": None, "explanation_steps": [wire_step(graphic)]})
    return {"units": [{"group_id": "g1", "subject": payload["selected_groups"][0]["subject"],
        "topic": "Künstliche belegte Bausteine", "explanation": "Die Originalfolge zeigt die belegten Bausteine.",
        "explanation_steps": [wire_step(intro)], "questions": questions}]}


@pytest.mark.parametrize("subject,source,kind", CASES)
def test_new_part_selects_only_prevalidated_source_graphics_with_same_complete_quote(subject, source, kind):
    payload, schema, binding = fixture(subject, source)
    assert binding is not None
    assert {row["kind"] for row in binding.candidates} == {kind}
    model = response(payload, binding)
    unchanged = copy.deepcopy(model)
    wire = package_output_transport.bind(package_transport.schema_projection(schema))
    assert wire.decode(wire.encode(model)) == model
    data = binding.hydrate(model)
    assert model == unchanged
    value = PackageOutput.model_validate(data).model_dump(mode="json")
    with DB() as db:
        visual_references.validate_output(db, value, payload)
    assert [q["answer"] for q in data["units"][0]["questions"]] == [q["answer"] for q in model["units"][0]["questions"]]
    for item in [data["units"][0], *data["units"][0]["questions"]]:
        block = item["explanation_steps"][0]["presentation"]["blocks"][0]
        assert block["source_excerpt"] == source
        assert block["title"] in source and all(label in source for label in block["labels"])
        if kind == "scene":
            assert len(block["scene"]["steps"]) == 2
            assert block["scene"]["steps"][0]["highlight"] != block["scene"]["steps"][1]["highlight"]
            assert all(phase["source_excerpt"] == source for phase in block["scene"]["steps"])
        else:
            assert block["scene"] is None and block["connections"] == []


@pytest.mark.parametrize("stage", ["hint1", "hint2", "hint3", "solution"])
def test_source_scene_keeps_each_existing_disclosure_stage(stage):
    payload, schema, binding = fixture("Biologie", CASES[1][1])
    model = response(payload, binding)
    choice = next(row for row in binding.candidates if row["disclosure"] == stage)
    for question in model["units"][0]["questions"]:
        question["explanation_steps"] = [wire_step(choice)]
    codec = package_output_transport.bind(package_transport.schema_projection(schema))
    hydrated = binding.hydrate(codec.decode(codec.encode(model)))
    with DB() as db:
        visual_references.validate_output(db, hydrated, payload)
    assert all(q["explanation_steps"][0]["disclosure"] == stage for q in hydrated["units"][0]["questions"])


@pytest.mark.parametrize("fault", ["title", "object_label", "quote", "phase_quote", "raw_block", "foreign_id", "source_ref", "stage", "unrelated_question", "similar_token"])
def test_source_binding_rejects_unverified_labels_quotes_scope_or_question_before_canonical_acceptance(fault):
    payload, schema, binding = fixture("Biologie", CASES[1][1])
    model = response(payload, binding)
    step = model["units"][0]["questions"][0]["explanation_steps"][0]
    if fault in ("title", "object_label", "quote", "phase_quote", "raw_block"):
        block = copy.deepcopy(next(row for row in binding.candidates if row["disclosure"] == "solution")["block"])
        if fault == "title":
            block["title"] = "Unbelegte Beschriftung"
        elif fault == "object_label":
            block["scene"]["objects"][0]["label"] = "Unbelegtes Objekt"
        elif fault == "quote":
            block["source_excerpt"] = "Andere Quelle."
        elif fault == "phase_quote":
            block["scene"]["steps"][0]["source_excerpt"] = "Andere Phase."
        step["presentation"]["blocks"] = [block]
    elif fault == "foreign_id":
        step["presentation"]["blocks"] = ["foreign-untrusted-id"]
    elif fault == "source_ref":
        step["source_refs"] = ["p2"]
    elif fault == "stage":
        step["disclosure"] = "given"
    elif fault == "unrelated_question":
        model["units"][0]["questions"][0]["prompt"] = "Welche Zahl steht unten in 2/3?"
    else:
        model["units"][0]["questions"][0]["prompt"] = "Was unterscheiden Raupen und Puppen?"
    with pytest.raises(ValueError):
        binding.hydrate(model)


@pytest.mark.parametrize("change", ["revision", "material", "source_text", "block", "reference_version", "reference_digest", "partition", "plan"])
def test_source_and_recipe_snapshot_changes_replace_ids_without_touching_previous_choices(change):
    from schulpilot.package_prepared_scenes import compile_candidates
    payload, _, binding = fixture("Geographie", CASES[2][1])
    before = copy.deepcopy(binding.candidates)
    changed = copy.deepcopy(payload)
    source = changed["visual_context"]["sources"][0]
    if change == "revision":
        source["revision"] += 1
    elif change == "material":
        source["material_id"] = "d" * 32
    elif change == "source_text":
        source["content"] += "\nWeiterer Originalsatz."
    elif change == "block":
        source["source_refs"][0]["block_id"] = "d" * 32
    elif change in ("reference_version", "reference_digest"):
        recipe = next(row for row in changed["visual_context"]["references"] if row["kind"] == "scene")
        recipe["version" if change == "reference_version" else "digest"] = 2 if change == "reference_version" else "d" * 64
    elif change == "partition":
        changed["package_partition"] += 1
    else:
        changed["package_plan_digest"] = "d" * 64
    current = compile_candidates(changed)
    assert current and {r["id"] for r in current}.isdisjoint(r["id"] for r in binding.candidates)
    assert binding.candidates == before


@pytest.mark.parametrize("subject,text", [
    ("Deutsch", "Haus + Baum"),
    ("Deutsch", "Vorsilbe und Wortstamm werden gemeinsam betrachtet."),
    ("Deutsch", "Vorsilbe + Wortstamm = Wort"),
    ("Physik", "Kraft + Beschleunigung"),
])
def test_plus_or_prose_never_turns_into_an_invented_direction_or_universal_word_box(subject, text):
    from schulpilot.package_prepared_scenes import compile_candidates
    payload = payload_for(text, subject)
    assert compile_candidates(payload) == []


def test_unavailable_scene_is_removed_while_existing_language_comparison_remains_reachable():
    payload = payload_for("He reads. She reads.", "Englisch")
    schema, binding = bind(payload)
    assert binding is None
    codec = package_output_transport.bind(package_transport.schema_projection(schema))
    import json
    encoded = json.dumps(codec.wire_schema)
    assert "general.source_relation.phases" not in encoded
    assert "language.forms.original_comparison" in encoded


@pytest.mark.parametrize("subject,source,kind", CASES)
def test_actual_http_mock_uses_checked_ids_preserves_answers_and_one_reported_bill(monkeypatch, subject, source, kind):
    import json

    import httpx
    from package_output_helpers import PackageOutputCapture
    from schulpilot import providers
    from test_package_transport import config

    payload, _, binding = fixture(subject, source)
    model = response(payload, binding)
    for item in [model["units"][0], *model["units"][0]["questions"]]:
        item["explanation_steps"][0]["text"] = "Schau dir die belegten Bausteine von links nach rechts an. Vergleiche zuerst die ersten beiden Beschriftungen. Die Grafik zeigt dir dieselben Ausdrücke aus deiner Quelle nebeneinander."
    expected = binding.hydrate(model)
    capture, real, calls = PackageOutputCapture(monkeypatch), httpx.Client, []

    def handler(request):
        body = json.loads(request.content)
        calls.append(body)
        schema = body["response_format"]["json_schema"]["schema"]
        assert schema == capture.binding.wire_schema
        wire = capture.wire(model)
        assert binding.hydrate(capture.binding.decode(wire)) == expected
        bad = copy.deepcopy(model)
        bad["units"][0]["questions"][0]["prompt"] = "Andere Frage ohne Originalausdrücke?"
        with pytest.raises(ValueError, match="Frageparametern"):
            binding.hydrate(capture.binding.decode(capture.wire(bad)))
        # The same strict question/ID branch retains its anchor through the
        # actual HTTP schema; full canonical validators run after decoding.
        def patterns(node):
            if isinstance(node, dict):
                if "pattern" in node:
                    yield node["pattern"]
                for value in node.values():
                    yield from patterns(value)
            elif isinstance(node, list):
                for value in node:
                    yield from patterns(value)
        from schulpilot.package_prepared_scenes import prompt_pattern
        assert prompt_pattern(next(row for row in binding.candidates if row["disclosure"] == "solution")) in set(patterns(schema))
        sent = json.loads(body["messages"][1]["content"][0]["text"])
        assert sent["prepared_graphics"]["revision"] == "package-source-graphics-1"
        assert all("block" not in row and "text" not in row and "source_caption" in row for row in sent["prepared_graphics"]["candidates"])
        assert "explanation-guidance-1" in body["messages"][0]["content"]
        assert "tatsächlich sichtbare explanation_steps.text" in body["messages"][0]["content"]
        assert body["max_tokens"] == 8000 and body["reasoning"]["effort"] == "medium"
        return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {
            "content": json.dumps(wire, ensure_ascii=False)}}],
            "usage": {"prompt_tokens": 100, "completion_tokens": 1700, "cost": 0.021}})

    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real(transport=httpx.MockTransport(handler)))
    monkeypatch.setattr(providers, "external_allowed", lambda *a, **kw: None)
    monkeypatch.setattr(providers, "decrypt", lambda _: "synthetic-offline-key")
    monkeypatch.setattr("schulpilot.model_routing.selection", lambda _: {"route": {"upstreams": ["azure"]}, "region": "standard"})
    cfg = config()
    cfg.max_output_tokens, cfg.reserve_micros = 8000, 250000
    result = providers.request_provider(cfg, "package", payload)
    assert len(calls) == 1 and result.cost_micros == 21000 and result.cost_source == "reported"
    assert PackageOutput.model_validate(result.data).model_dump()["units"][0]["questions"] == PackageOutput.model_validate(expected).model_dump()["units"][0]["questions"]
    assert {step["presentation"]["blocks"][0]["kind"] for unit in result.data["units"]
        for item in [unit, *unit["questions"]] for step in item["explanation_steps"]} == {kind}


def test_only_unavailable_scene_recipe_is_rejected_before_dispatch_instead_of_empty_schema():
    payload = payload_for("Eigene synthetische Prosa ohne eine sichtbare Pfeilfolge.", "Biologie")
    payload["visual_context"]["references"] = [row for row in payload["visual_context"]["references"]
        if row["id"] == "general.source_relation.phases"]
    assert payload["visual_context"]["references"]
    with pytest.raises(ValueError, match="keine passende Referenz/Grafik"):
        bind(payload)


def test_maximum_source_scenes_measure_real_outbound_preflight_without_a_provider_call(monkeypatch, record_property):
    import json

    import test_package_transport
    from package_output_helpers import PackageOutputCapture
    from schulpilot import provider_cost_preflight

    lines = [" → ".join(f"Beleg{i}{j}" + "x" * 52 for j in range(4)) + "." for i in range(8)]
    source = ("\n".join(lines) + "\nEigener künstlicher Quellenkontext. " * 300)[:6000]
    payload = payload_for(source, "Biologie")
    assert len(source) == 6000
    original_projection, measured = provider_cost_preflight.projection, []
    original_config = test_package_transport.config

    def configured(provider="openrouter"):
        value = original_config(provider)
        value.max_output_tokens, value.reserve_micros = 8000, 250000
        return value

    def project(*args):
        value = original_projection(*args)
        measured.append(value)
        record_property("preflight_text_bytes", value["text_bytes"])
        record_property("preflight_projected_micros", value["projected_micros"])
        return value

    monkeypatch.setattr(provider_cost_preflight, "projection", project)
    monkeypatch.setattr(test_package_transport, "config", configured)
    capture = PackageOutputCapture(monkeypatch)
    request = test_package_transport.wire(monkeypatch, payload)
    rows = request["payload"]["prepared_graphics"]["candidates"]
    from schulpilot.package_prepared_scenes import MAX_SOURCE_BASE_CANDIDATES
    assert len(rows) == MAX_SOURCE_BASE_CANDIDATES * 5
    record_property("base_candidates", len(rows) // 5)
    record_property("label_chars", 59)
    record_property("wire_schema_bytes", len(json.dumps(capture.binding.wire_schema, ensure_ascii=False, separators=(",", ":")).encode()))
    assert len(measured) == 1 and measured[0]["projected_micros"] <= 250000
    assert request["body"]["max_tokens"] == 8000


def test_exact_decomposed_unicode_labels_keep_their_original_quote_through_hydration():
    source = "A\u0308hre → Blu\u0308te."
    payload, _, binding = fixture("Biologie", source)
    model = response(payload, binding)
    data = binding.hydrate(model)
    assert data["units"][0]["explanation_steps"][0]["presentation"]["blocks"][0]["source_excerpt"] == source
    with DB() as db:
        visual_references.validate_output(db, data, payload)


def test_source_bound_graphic_allows_a_real_visible_explanation_without_changing_its_quote_or_answer():
    payload, schema, binding = fixture("Deutsch", CASES[0][1])
    model = response(payload, binding)
    text = "Die Grafik trennt die drei aufgeschriebenen Wortbausteine. Links steht die Vorsilbe, in der Mitte der Wortstamm und rechts die Nachsilbe. Vergleiche diese Reihenfolge mit der belegten Plusfolge. So kannst du jeden Originalbaustein an seiner Stelle wiederfinden."
    for item in [model["units"][0], *model["units"][0]["questions"]]:
        item["explanation_steps"][0]["text"] = text
    before = copy.deepcopy(model)
    codec = package_output_transport.bind(package_transport.schema_projection(schema))
    data = binding.hydrate(codec.decode(codec.encode(model)))
    with DB() as db:
        visual_references.validate_output(db, data, payload)
    assert model == before
    assert data["units"][0]["explanation_steps"][0]["text"] == text
    assert data["units"][0]["explanation_steps"][0]["presentation"]["blocks"][0]["source_excerpt"] == CASES[0][1]
    assert data["units"][0]["questions"][0]["answer"] == before["units"][0]["questions"][0]["answer"]
    assert all("text" not in row and "source_caption" in row for row in binding.context["candidates"])


@pytest.mark.parametrize("invalid", ["", " ", "x" * 351, None, 123])
def test_visible_explanation_still_requires_existing_finite_text_bounds(invalid):
    payload, _, binding = fixture("Biologie", CASES[1][1])
    model = response(payload, binding)
    model["units"][0]["explanation_steps"][0]["text"] = invalid
    with pytest.raises(ValueError, match="Struktur"):
        binding.hydrate(model)


def test_actual_openai_schema_retains_explicit_visible_text_bounds_without_preserved_pydantic_limits(monkeypatch):
    import test_package_transport

    payload = payload_for(CASES[1][1], "Biologie")
    original_config = test_package_transport.config

    def configured(provider="openrouter"):
        value = original_config(provider)
        value.max_output_tokens, value.reserve_micros = 8000, 250000
        return value

    monkeypatch.setattr(test_package_transport, "config", configured)
    request = test_package_transport.wire(monkeypatch, payload, provider="openai")
    schema = request["body"]["text"]["format"]["schema"]
    output = request["output_binding"]
    field = output.aliases.get("text", "text") if output else "text"

    def text_fields(node):
        if isinstance(node, dict):
            candidate = node.get("properties", {}).get(field)
            while isinstance(candidate, dict) and "$ref" in candidate:
                candidate = schema["$defs"][candidate["$ref"].rsplit("/", 1)[-1]]
            if isinstance(candidate, dict) and candidate.get("maxLength") == 350 and "enum" not in candidate:
                yield candidate
            for value in node.values():
                yield from text_fields(value)
        elif isinstance(node, list):
            for value in node:
                yield from text_fields(value)

    fields = list(text_fields(schema))
    assert fields and all(row["minLength"] == 1 for row in fields)
    assert request["body"]["max_output_tokens"] == 8000
