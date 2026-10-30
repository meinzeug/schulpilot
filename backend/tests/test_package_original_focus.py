"""Public invented examples, never private pupil source excerpts."""
import copy
import json

import httpx
import pytest
from package_output_helpers import PackageOutputCapture
from schulpilot import package_output_transport, package_part_output, package_transport, providers, visual_references
from schulpilot import package_prepared_focus as focus
from schulpilot.db import DB
from schulpilot.schemas import PackageOutput
from schulpilot.subject_content import Graphic, bind_graphic_schema
from test_package_prepared_graphics import payload_for, wire_step
from test_package_transport import config

SOURCES = {
    "Deutsch": "Eigene Beispiele\n1. leise sprechen\n2. genau hinsehen\n3. freundlich fragen",
    "Geschichte": "Öffentliche künstliche Notizen\n• Im Dorf lebten mehrere Familien.\n• Die Menschen stellten Schalen aus Ton her.\n• Auf dem Markt wurden Waren getauscht.",
}


def fixture(subject="Deutsch", *, indexed=True, source=None):
    payload = payload_for(SOURCES[subject] if source is None else source, subject)
    schema = providers.strict_schema(PackageOutput, preserve_limits=True)
    providers.prepare_package_schema(schema, payload, allow_matching=True, partition=True)
    if indexed:
        providers.indexed_choice_schema(schema, bounded_matches=True)
    bind_graphic_schema(schema, [subject])
    visual_references.bind_schema(schema, payload)
    binding = package_part_output.bind_schema(schema, payload)
    assert isinstance(binding, focus.Binding)
    candidate = next(row for row in binding.candidates if row["disclosure"] == "solution")
    intro = next(row for row in binding.candidates if row["disclosure"] == "given")
    questions = [{"id": f"q{i}", "type": "choice", "prompt": prompt,
        "options": focus.options_slot(candidate), "answer": i if indexed else candidate["block"]["labels"][i],
        "accepted": [], "hints": ["Überlege, welche Originalaussage zur Frage passt."],
        "explanation": "Vergleiche die Bedeutung der Originalaussagen.", "presentation": None,
        "field_group": None, "explanation_steps": [wire_step(candidate)]}
        for i, prompt in enumerate(["Welcher Ausdruck beschreibt eine geringe Lautstärke?", "Welcher Ausdruck fordert auf, aufmerksam zu schauen?"]
            if subject == "Deutsch" else ["Welche Aussage beschreibt das Zusammenleben?", "Welche Aussage beschreibt die Herstellung eines Gegenstands?"])]
    for item in [*questions]:
        item["explanation_steps"][0]["text"] = "Lies die vollständigen Originalbeispiele. Wähle einen Lesefokus und vergleiche ihre Bedeutung."
    data = {"units": [{"group_id": "g1", "subject": subject, "topic": "Öffentliche Originalbeispiele",
        "explanation": "Vergleiche die Originalbeispiele und ihre Bedeutung.",
        "explanation_steps": [wire_step(intro)], "questions": questions}]}
    return payload, schema, binding, data


@pytest.mark.parametrize("subject", SOURCES)
@pytest.mark.parametrize("indexed", [False, True])
def test_original_options_slot_roundtrip_then_real_canonical_source_validation(subject, indexed):
    payload, schema, binding, model = fixture(subject, indexed=indexed)
    untouched = copy.deepcopy(model)
    codec = package_output_transport.bind(package_transport.schema_projection(schema))
    decoded = codec.decode(codec.encode(model))
    restored = binding.hydrate(decoded)
    providers.decode_choice_indices(restored)
    data = PackageOutput.model_validate(restored).model_dump(mode="json")
    with DB() as db:
        visual_references.validate_output(db, data, payload)
    assert model == untouched
    for unit in data["units"]:
        for question in unit["questions"]:
            assert question["options"] == question["explanation_steps"][0]["presentation"]["blocks"][0]["labels"]
        for item in [unit, *unit["questions"]]:
            scene = item["explanation_steps"][0]["presentation"]["blocks"][0]["scene"]
            assert len(scene["steps"]) == 2 and all(not phase["edges"] for phase in scene["steps"])
            assert scene["steps"][0]["highlight"] != scene["steps"][1]["highlight"]


@pytest.mark.parametrize("source", ["Freie Prosa ohne sichtbare Liste.", "1. Einzelner Ausdruck", "1. gleich\n2. gleich", "A + B = AB", "1. " + "x" * 161 + "\n2. kurz", "1. oben\nZwischentext\n2. unten"])
def test_no_prose_segmentation_equation_duplicate_or_overlong_item_fallback(source):
    assert list(focus.focus_bases(source)) == []


@pytest.mark.parametrize("fault", ["index_bool", "index_text", "index_range", "slot", "raw_options", "foreign_id", "source", "stage", "prompt_leak"])
def test_scoped_hydration_rejects_wrong_answer_slot_scope_or_disclosure(fault):
    _, _, binding, model = fixture()
    question = model["units"][0]["questions"][0]
    step = question["explanation_steps"][0]
    if fault == "index_bool":
        question["answer"] = True
    elif fault == "index_text":
        question["answer"] = "0"
    elif fault == "index_range":
        question["answer"] = 4
    elif fault == "slot":
        question["options"] = "foreign-list"
    elif fault == "raw_options":
        question["options"] = ["leise sprechen", "genau hinsehen", "freundlich fragen"]
    elif fault == "foreign_id":
        step["presentation"]["blocks"] = ["foreign-id"]
    elif fault == "source":
        step["source_refs"] = ["p2"]
    elif fault == "stage":
        step["disclosure"] = "given"
    else:
        question["prompt"] = "Was bedeutet leise sprechen?"
    with pytest.raises(ValueError):
        binding.hydrate(model)


def test_old_arrow_reference_stays_strict_and_sport_has_no_focus_candidate():
    payload, _, binding, _ = fixture()
    candidate = next(row for row in binding.candidates if row["disclosure"] == "solution")
    block = Graphic.model_validate(candidate["block"])
    with pytest.raises(ValueError, match="Beziehungen"):
        visual_references._meaningful(block, {"id": "general.source_relation.phases", "kind": "scene"})
    sport = payload_for(SOURCES["Deutsch"], "Sport")
    assert focus.compile_candidates(sport) == []
    assert all(row["id"] != focus.REFERENCE for row in sport["visual_context"]["references"])
    assert payload["visual_context"]["sources"][0]["content"] == SOURCES["Deutsch"]


def test_history_prose_uses_separate_exact_sentence_reference(api):
    source = ("Geschichte und Quellen\n\n"
              "Quellen sind Überreste oder Berichte aus der Vergangenheit.\n\n"
              "Ein altes Werkzeug ist eine Sachquelle.\n\n"
              "Ein Brief ist eine schriftliche Quelle.")
    payload = payload_for(source, "Geschichte")
    candidates = focus.compile_candidates(payload)
    rows = [row for row in candidates if row["reference"]["id"] == focus.SENTENCE_REFERENCE]
    assert rows
    block = Graphic.model_validate(rows[0]["block"])
    assert len(block.labels) >= 2 and all(label in source for label in block.labels)
    assert all(not phase.edges for phase in block.scene.steps)
    visual_references._meaningful(block, {"id": focus.SENTENCE_REFERENCE, "kind": "scene"}, sources=[source])
    altered = block.model_dump(mode="json")
    altered["labels"][0] = "Erfundener Satz."
    with pytest.raises(ValueError):
        visual_references._meaningful(Graphic.model_validate(altered),
            {"id": focus.SENTENCE_REFERENCE, "kind": "scene"}, sources=[source])


def test_wrapped_ocr_sentences_keep_exact_source_and_no_invented_relations(api):
    source = ("Geschichte: Quellen\n\n"
              "Sachquellen sind Gegenstände aus früherer\nZeit, zum Beispiel ein Werkzeug.\n\n"
              "Schriftquellen sind geschriebene Texte, zum\nBeispiel ein Brief.\n\n"
              "Bildquellen zeigen Bilder aus früherer Zeit,\nzum Beispiel eine Zeichnung.")
    payload = payload_for(source, "Geschichte")
    candidates = focus.compile_candidates(payload)
    row = next(row for row in candidates if row["reference"]["id"] == focus.SENTENCE_REFERENCE)
    block = Graphic.model_validate(row["block"])
    assert block.source_excerpt in source
    assert len(block.labels) == 3
    assert all(label in " ".join(source.split()) for label in block.labels)
    assert all(not step.edges for step in block.scene.steps)
    visual_references._meaningful(block, {"id": focus.SENTENCE_REFERENCE, "kind": "scene"}, sources=[source])
    assert "Geschichte: Quellen" not in " ".join(block.labels)


def test_multiple_full_ocr_sentences_on_one_line_preserve_literal_evidence():
    source = ("Leben am Nil\nDie Menschen wohnten in Dörfern am Nil. "
              "Sie bauten Getreide auf den Feldern an. Der Fluss versorgte die Felder mit Wasser.")
    bases = list(focus.sentence_bases(source))
    assert len(bases) == 2
    assert bases[0]['labels'] == ["Die Menschen wohnten in Dörfern am Nil.",
                                 "Sie bauten Getreide auf den Feldern an.",
                                 "Der Fluss versorgte die Felder mit Wasser."]
    assert bases[0]['source_excerpt'] in source
    block = Graphic.model_validate({**bases[0], 'disclosure': 'solution'})
    focus.validate_focus(block, sources=[source], sentences=True)


@pytest.mark.parametrize('line', [
    "Die Messung beträgt 1.5 Meter. Danach wurde weitergemessen.",
    "Die Kinder besuchten z.B. alte Bauwerke. Danach gingen sie weiter.",
    "Der Aufsatz ist für die 6. Klasse gedacht. Danach folgt eine Übung.",
    "Die Klasse traf Prof. Müller im Museum. Danach ging sie weiter.",
])
def test_inline_sentence_focus_does_not_guess_at_ambiguous_periods(line):
    assert list(focus.sentence_bases(line)) == []


@pytest.mark.parametrize("change", ["edges", "label", "phase", "quote"])
def test_new_reference_proves_exact_compile_shape_instead_of_relaxing_scene_rules(change):
    payload, _, binding, _ = fixture()
    block = copy.deepcopy(binding.candidates[0]["block"])
    if change == "edges":
        block["scene"]["steps"][0]["edges"] = [{"start": "o0", "end": "o1", "label": ""}]
    elif change == "label":
        block["scene"]["objects"][0]["label"] = "Andere Aussage"
    elif change == "phase":
        block["scene"]["steps"][1]["highlight"] = ["o0"]
    else:
        block["source_excerpt"] += "\n3. erfunden"
    with pytest.raises(ValueError):
        visual_references._meaningful(Graphic.model_validate(block), {"id": focus.REFERENCE, "kind": "scene"}, sources=[SOURCES["Deutsch"]])
    assert payload["visual_context"]["sources"][0]["content"] == SOURCES["Deutsch"]


@pytest.mark.parametrize("subject", SOURCES)
def test_actual_http_schema_has_finite_slot_and_unchanged_cost_source_bounds(monkeypatch, subject, record_property):
    payload, _, binding, model = fixture(subject)
    capture, real, calls = PackageOutputCapture(monkeypatch), httpx.Client, []
    def handler(request):
        body = json.loads(request.content)
        calls.append(body)
        encoded = json.dumps(body["response_format"]["json_schema"]["schema"], ensure_ascii=False)
        assert focus.options_slot(binding.candidates[0]) in encoded
        assert body["max_tokens"] == 8000 and body["reasoning"]["effort"] == "medium"
        assert "package-original-focus-1" in body["messages"][0]["content"]
        assert "Erkläre den konkreten Inhalt" in body["messages"][0]["content"]
        assert "eine vollständige Originalaussage" in body["messages"][0]["content"]
        assert "eine allgemeine Aussage über Texte" in body["messages"][0]["content"]
        wire = capture.wire(model)
        return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {"content": json.dumps(wire, ensure_ascii=False)}}],
            "usage": {"prompt_tokens": 100, "completion_tokens": 100, "cost": 0.01}})
    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real(transport=httpx.MockTransport(handler)))
    monkeypatch.setattr(providers, "external_allowed", lambda *a, **kw: None)
    monkeypatch.setattr(providers, "decrypt", lambda _: "synthetic-offline-key")
    monkeypatch.setattr("schulpilot.model_routing.selection", lambda _: {"route": {"upstreams": ["azure"]}, "region": "standard"})
    cfg = config()
    cfg.max_output_tokens, cfg.reserve_micros = 8000, 250000
    result = providers.request_provider(cfg, "package", payload)
    assert len(calls) == 1 and result.cost_micros == 10000 and result.cost_source == "reported"
    assert [q["answer"] for q in result.data["units"][0]["questions"]] == [row["block"]["labels"][i] for i, row in enumerate([binding.candidates[0]] * 2)]
    record_property("request_body_bytes", len(json.dumps(calls[0], ensure_ascii=False).encode()))


@pytest.mark.parametrize("original", ["Quelle → Fluss → Mündung.", "Vorsilbe (Präfix) + Wortstamm + Nachsilbe (Suffix)"])
def test_existing_literal_relation_or_word_parts_win_over_additional_numbered_list(original):
    from schulpilot import package_prepared_scenes
    from test_package_prepared_graphics import bind

    payload = payload_for(original + "\n" + SOURCES["Deutsch"], "Deutsch")
    _, binding = bind(payload)
    assert type(binding) is package_prepared_scenes.Binding
    assert all(row["reference"]["id"] != focus.REFERENCE for row in binding.candidates)


def test_maximum_source_list_focus_records_actual_wire_preflight(monkeypatch, record_property):
    import test_package_transport
    from schulpilot import provider_cost_preflight

    labels = [f"Öffentliches Beispiel {i} " + "langes Originalwort " * 6 for i in range(8)]
    source = ("\n".join(f"{i + 1}. {label}" for i, label in enumerate(labels)) + "\nÖffentlicher zusätzlicher Kontext. " * 300)[:6000]
    payload = payload_for(source, "Geschichte")
    original, measures = provider_cost_preflight.projection, []
    def project(*args):
        result = original(*args)
        measures.append(result)
        return result
    old_config = test_package_transport.config
    def configured(provider="openrouter"):
        cfg = old_config(provider)
        cfg.max_output_tokens, cfg.reserve_micros = 8000, 250000
        return cfg
    monkeypatch.setattr(provider_cost_preflight, "projection", project)
    monkeypatch.setattr(test_package_transport, "config", configured)
    capture = PackageOutputCapture(monkeypatch)
    request = test_package_transport.wire(monkeypatch, payload)
    candidates = request["payload"]["prepared_graphics"]["candidates"]
    assert len(source) == 6000 and len(candidates) == 20
    assert all(row["reference"]["id"] == focus.REFERENCE for row in candidates)
    assert len(measures) == 1 and measures[0]["projected_micros"] <= 250000
    record_property("preflight_text_bytes", measures[0]["text_bytes"])
    record_property("preflight_projected_micros", measures[0]["projected_micros"])
    record_property("wire_schema_bytes", len(json.dumps(capture.binding.wire_schema, ensure_ascii=False, separators=(",", ":")).encode()))


@pytest.mark.parametrize("prompt,source", [
    ("Was bedeutet Leise sprechen?", None),
    ("Was bedeutet LEISE   sprechen?", None),
    ("Was bedeutet Scho\u0308n sprechen?", "1. schön sprechen\n2. genau hören"),
])
def test_answer_leak_detection_is_case_insensitive_nfc_and_whitespace_only(prompt, source):
    payload, _, binding, model = fixture(source=source)
    question = model["units"][0]["questions"][0]
    question["prompt"] = prompt
    with pytest.raises(ValueError, match="Frageparametern"):
        binding.hydrate(model)
    candidate = next(row for row in binding.candidates if row["disclosure"] == "solution")
    canonical = {**question, "options": candidate["block"]["labels"], "answer": candidate["block"]["labels"][0]}
    with pytest.raises(ValueError, match="Antwort im Prompt"):
        visual_references._meaningful(Graphic.model_validate(candidate["block"]), {"id": focus.REFERENCE, "kind": "scene"},
            sources=[payload["visual_context"]["sources"][0]["content"]], question=canonical)
    assert candidate["block"]["source_excerpt"] in payload["visual_context"]["sources"][0]["content"]
