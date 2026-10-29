"""Public artificial invalid graphics and malicious exception text only."""
import copy
import json
from pathlib import Path

import pytest
from pydantic import BaseModel, ConfigDict, ValidationError, model_validator
from pydantic_core import PydanticCustomError
from schulpilot.provider_validation import annotate
from schulpilot.providers import Result
from schulpilot.subject_content import Graphic

BLOCK = json.loads((Path(__file__).parents[2] / "testdata/learning_scenes_v1.json").read_text())["cases"][0]["question"]["presentation"]["blocks"][0]


def result():
    return Result({"unchanged": "canonical-private-result"}, 123, 456, 789,
        telemetry={"cost_preflight": {"reserved_micros": 250000}}, cost_source="reported",
        request_receipt={"version": 1, "model": "synthetic/model"})


@pytest.mark.parametrize("kind,changes,reason", [
    ("scene", {"unit": "cm"}, "scene_parameters"),
    ("scene", {"scene": None}, "scene_parameters"),
    ("scene", {"labels": []}, "scene_parameters"),
    ("water_cycle", {}, "scene_kind"),
    ("fraction", {"scene": None, "labels": [], "numbers": [2, 1]}, "fraction_bounds"),
    ("text_probe", {"scene": None, "text_probe": None}, "text_probe_parameters"),
    ("lab", {"scene": None, "lab": None}, "lab_parameters"),
])
def test_actual_graphic_errors_become_closed_tags_without_changing_financial_facts(kind, changes, reason):
    block = {**copy.deepcopy(BLOCK), "kind": kind, **changes}
    with pytest.raises(ValidationError) as caught:
        Graphic.model_validate(block)
    value = result()
    before, previous_telemetry = copy.deepcopy(value.__dict__), value.telemetry
    assert annotate(value, caught.value) is value
    assert value.telemetry["validation"] == {"version": 1, "errors": [{"location": "field", "reason": reason}]}
    assert previous_telemetry == before["telemetry"]
    assert {key: item for key, item in value.__dict__.items() if key != "telemetry"} == {
        key: item for key, item in before.items() if key != "telemetry"}
    assert value.telemetry["cost_preflight"] == before["telemetry"]["cost_preflight"]
    diagnostic = json.dumps(value.telemetry["validation"], ensure_ascii=False)
    assert block["source_excerpt"] not in diagnostic
    assert not {"input", "msg", "ctx", "type"}.intersection(value.telemetry["validation"]["errors"][0])


def test_unknown_extra_keys_values_error_type_and_context_never_appear():
    error = ValidationError.from_exception_data("PRIVATE_MODEL_TITLE", [{
        "type": PydanticCustomError("PRIVATE_ERROR_TYPE", "PRIVATE_MESSAGE {secret}", {"secret": "PRIVATE_CONTEXT"}),
        "loc": ("units", 0, "PRIVATE_UNKNOWN_KEY", "questions", 1, "presentation", "blocks", 0),
        "input": "PRIVATE_INPUT"}])
    value = result()
    annotate(value, error)
    assert value.telemetry["validation"] == {"version": 1, "errors": [{
        "location": "units.0.field.questions.1.presentation.blocks.0", "reason": "schema_validation"}]}
    assert "PRIVATE" not in json.dumps(value.telemetry)


def test_known_message_plus_private_suffix_is_not_recognized_or_retained():
    error = ValidationError.from_exception_data("Private", [{"type": PydanticCustomError("arbitrary",
        "Value error, Bruchmodell braucht Zähler und positiven Nenner bis24. PRIVATE_SUFFIX"),
        "loc": ("answer",), "input": "PRIVATE_INPUT"}])
    value = result()
    annotate(value, error)
    assert value.telemetry["validation"]["errors"] == [{"location": "answer", "reason": "schema_validation"}]
    assert "PRIVATE" not in json.dumps(value.telemetry)


def test_actual_extra_key_and_model_validator_messages_are_not_retained():
    class Closed(BaseModel):
        model_config = ConfigDict(extra="forbid")
        version: int

    with pytest.raises(ValidationError) as caught:
        Closed.model_validate({"version": "PRIVATE_INPUT", "PRIVATE_EXTRA_KEY": "PRIVATE_VALUE"})
    value = result()
    annotate(value, caught.value)
    assert {item["location"] for item in value.telemetry["validation"]["errors"]} == {"version", "field"}
    assert "PRIVATE" not in json.dumps(value.telemetry)

    class DynamicMessage(BaseModel):
        answer: str

        @model_validator(mode="after")
        def private_error(self):
            raise ValueError("PRIVATE_CONTEXT " + self.answer)

    with pytest.raises(ValidationError) as caught:
        DynamicMessage.model_validate({"answer": "PRIVATE_ANSWER"})
    annotate(value, caught.value)
    assert value.telemetry["validation"]["errors"] == [{"location": "field", "reason": "schema_validation"}]
    assert "PRIVATE" not in json.dumps(value.telemetry)


def test_diagnostic_count_path_depth_and_numeric_indices_are_bounded():
    error = ValidationError.from_exception_data("Private", [{"type": "missing",
        "loc": ("units", 10 ** 30, "PRIVATE_KEY", *(["explanation_steps"] * 30)), "input": {}}
        for _ in range(8)])
    value = result()
    annotate(value, error)
    entries = value.telemetry["validation"]["errors"]
    assert len(entries) == 3
    assert all(len(item["location"]) <= 200 and len(item["location"].split(".")) <= 16 for item in entries)
    assert all(item["location"].startswith("units.field.field.") for item in entries)
    assert "PRIVATE" not in json.dumps(value.telemetry)


def test_absent_result_and_non_pydantic_errors_are_harmless_and_none_telemetry_supported():
    assert annotate(None, ValueError("PRIVATE")) is None
    value = result()
    before = copy.deepcopy(value.__dict__)
    assert annotate(value, ValueError("PRIVATE")) is value and value.__dict__ == before
    error = ValidationError.from_exception_data("Private", [{"type": "missing", "loc": ("answer",), "input": {}}])
    value.telemetry = None
    annotate(value, error)
    assert value.telemetry == {"validation": {"version": 1, "errors": [{"location": "answer", "reason": "schema_validation"}]}}


def test_unexpected_existing_telemetry_is_not_replaced():
    error = ValidationError.from_exception_data("Private", [{"type": "missing", "loc": (), "input": {}}])
    value = result()
    value.telemetry = "existing-invalid-receipt"
    assert annotate(value, error) is value and value.telemetry == "existing-invalid-receipt"


@pytest.mark.parametrize("phase,error,reason", [
    ("part_bounds", ValueError("Ein Lernpaketteil benötigt genau ein Fach."), "part_structure"),
    ("part_bounds", ValueError("Eine Aufgabe enthält eine stark wiederholte Formulierung."), "part_repeated_words"),
    ("part_bounds", ValueError("Eine Aufgabenstellung verweist auf eine Lösungsgrafik."), "part_solution_in_prompt"),
    ("catalog", ValueError("Unknown catalog subject identity"), "catalog_assignment"),
    ("entry", ValueError("Eine geprüfte Voraussetzung wurde verändert."), "entry_probe_changed"),
    ("subject", ValueError("Grafik ohne wörtlichen Quellenbeleg."), "source_excerpt"),
    ("visual", ValueError("Unveränderte Wortkästen sind keine fachliche Phasenvisualisierung."), "visual_scene_phases"),
    ("visual", ValueError("Erklärtext und Bruchgrafik verwenden verschiedene Brüche."), "visual_fraction_parameters"),
    ("visual", ValueError("Erklärtext und Dreieckgrafik verwenden verschiedene Grundseiten oder Höhen."), "visual_triangle_parameters"),
    ("visual", ValueError("Erklärtext und Spiegelgrafik verwenden verschiedene Winkel."), "visual_reflection_parameters"),
    ("json", ValueError("PRIVATE_RESPONSE"), "schema_validation"),
    ("visual", KeyError("PRIVATE_KEY"), "missing_field"),
    ("visual", IndexError("PRIVATE_INDEX"), "invalid_index"),
    ("visual", TypeError("PRIVATE_TYPE"), "invalid_type"),
])
def test_closed_stage_diagnostics_never_render_exceptions_or_change_billing(phase, error, reason):
    value = result()
    before = copy.deepcopy(value.__dict__)
    annotate(value, error, phase=phase)
    assert value.telemetry["validation"] == {"version": 1, "phase": phase,
        "errors": [{"location": "field", "reason": reason}]}
    assert {key: item for key, item in value.__dict__.items() if key != "telemetry"} == {
        key: item for key, item in before.items() if key != "telemetry"}
    assert value.telemetry["cost_preflight"] == before["telemetry"]["cost_preflight"]
    assert "PRIVATE" not in json.dumps(value.telemetry)


def test_unknown_phase_and_malicious_exception_arguments_are_closed_without_rendering():
    class Secret:
        def __str__(self):
            raise AssertionError("Exception argument must not be rendered")

        def __repr__(self):
            raise AssertionError("Exception argument must not be represented")

    class SecretError(ValueError):
        def __str__(self):
            raise AssertionError("Exception must not be rendered")

    for error in (ValueError(Secret()), SecretError("PRIVATE_MESSAGE"),
            ValueError("Grafik passt nicht zur gewählten Referenz. PRIVATE_SUFFIX")):
        value = result()
        annotate(value, error, phase="PRIVATE_PHASE")
        assert value.telemetry["validation"] == {"version": 1, "phase": "schema",
            "errors": [{"location": "field", "reason": "schema_validation"}]}
        assert "PRIVATE" not in json.dumps(value.telemetry)


@pytest.mark.parametrize("target,error,phase,reason", [
    ("json", None, "json", "schema_validation"),
    ("transport", None, "transport", "schema_validation"),
    ("schulpilot.package_part_output.validate", ValueError("Der Grafikschritt überschreitet den begrenzten Umfang."),
        "part_bounds", "part_bounds"),
    ("schulpilot.subject_content.validate_output", KeyError("PRIVATE_CHILD_KEY"), "subject", "missing_field"),
    ("schulpilot.visual_references.validate_output", ValueError("Unveränderte Wortkästen sind keine fachliche Phasenvisualisierung."),
        "visual", "visual_scene_phases"),
    ("schulpilot.visual_references.validate_output", IndexError("PRIVATE_INDEX"), "visual", "invalid_index"),
    ("schulpilot.visual_references.validate_output", TypeError("PRIVATE_ARGUMENT"), "visual", "invalid_type"),
])
def test_actual_adapter_keeps_single_reported_bill_when_postvalidation_fails(monkeypatch, target, error, phase, reason):
    import httpx
    from package_output_helpers import PackageOutputCapture
    from schulpilot import providers
    from test_package_part_output import part
    from test_package_transport import config

    data, payload = part()
    # Actual immutable reference metadata, matching the normal server context.
    for reference in payload["visual_context"]["references"]:
        reference["kind"] = "scene"
    output, real_client, calls = PackageOutputCapture(monkeypatch), httpx.Client, []

    def handler(request):
        calls.append(request)
        content = "{PRIVATE_JSON_PAYLOAD" if target == "json" else json.dumps(
            {"PRIVATE_KEY": "PRIVATE_VALUE"} if target == "transport" else output.wire(data), ensure_ascii=False)
        return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {
            "content": content}}],
            "usage": {"prompt_tokens": 100, "completion_tokens": 2000, "cost": 0.0202}})

    def fail(*args, **kwargs):
        raise error

    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real_client(transport=httpx.MockTransport(handler)))
    monkeypatch.setattr(providers, "external_allowed", lambda *a, **kw: None)
    monkeypatch.setattr(providers, "decrypt", lambda _: "synthetic-no-network-key")
    monkeypatch.setattr("schulpilot.model_routing.selection", lambda _: {
        "route": {"upstreams": ["azure"]}, "region": "standard"})
    if target not in ("json", "transport"):
        monkeypatch.setattr(target, fail)
    value = config()
    value.max_output_tokens, value.reserve_micros = 8000, 250000
    with pytest.raises(providers.ProviderError) as caught:
        providers.request_provider(value, "package", payload)
    billed = caught.value.billing_result
    assert len(calls) == 1
    assert billed.cost_micros == 20200 and billed.cost_source == "reported"
    assert billed.input_tokens == 100 and billed.output_tokens == 2000
    assert billed.telemetry["validation"] == {"version": 1, "phase": phase,
        "errors": [{"location": "field", "reason": reason}]}
    assert "PRIVATE" not in json.dumps(billed.telemetry)
    assert "PRIVATE" not in str(caught.value)


def test_pydantic_phase_keeps_existing_bounded_three_error_contract():
    error = ValidationError.from_exception_data("PRIVATE_MODEL", [{"type": "missing",
        "loc": ("units", 0, "questions", index, "PRIVATE_FIELD"), "input": {"secret": "PRIVATE_INPUT"}}
        for index in range(5)])
    value = result()
    annotate(value, error, phase="schema")
    assert value.telemetry["validation"] == {"version": 1, "phase": "schema", "errors": [
        {"location": f"units.0.questions.{index}.field", "reason": "schema_validation"} for index in range(3)]}
    assert "PRIVATE" not in json.dumps(value.telemetry)



@pytest.mark.parametrize("message,reason", [
    ("Grafik ohne wörtlichen Quellenbeleg.", "source_excerpt"),
    ("Grafikzahl fehlt im Beleg oder in der Aufgabe.", "number_evidence"),
    ("Grafikbeschriftung fehlt im wörtlichen Beleg.", "label_evidence"),
    ("Szenenbeschriftung fehlt im wörtlichen Beleg.", "scene_label_evidence"),
    ("Szenenschritt ohne wörtlichen Quellenbeleg.", "scene_source_excerpt"),
    ("Die Szenenbeschreibung muss im Schrittbeleg stehen.", "scene_caption_evidence"),
    ("Szenenpfeil hat keine belegte Richtung zwischen seinen Beschriftungen.", "scene_arrow_evidence"),
    ("Pfeilbeschriftung fehlt im Schrittbeleg.", "scene_edge_label_evidence"),
])
def test_literal_evidence_failures_remain_distinct_closed_codes(message, reason):
    value = result()
    annotate(value, ValueError(message), phase="visual")
    assert value.telemetry["validation"]["errors"] == [{"location": "field", "reason": reason}]
    annotate(value, ValueError(message + " PRIVATE_SOURCE"), phase="visual")
    assert value.telemetry["validation"]["errors"] == [{"location": "field", "reason": "schema_validation"}]
    assert "PRIVATE" not in json.dumps(value.telemetry)


def test_actual_scene_shape_error_has_its_own_tag_without_retaining_scene_text():
    block = copy.deepcopy(BLOCK)
    block["scene"]["objects"][1]["id"] = block["scene"]["objects"][0]["id"]
    with pytest.raises(ValidationError) as caught:
        Graphic.model_validate(block)
    value = result()
    annotate(value, caught.value, phase="schema")
    assert value.telemetry["validation"]["errors"][0]["reason"] == "scene_object_ids"
    assert block["source_excerpt"] not in json.dumps(value.telemetry)
    assert value.cost_micros == 789 and value.cost_source == "reported"


@pytest.mark.parametrize("fault,reason", [
    ("shape", "original_comparison_shape"),
    ("label", "original_comparison_label"),
    ("source", "original_comparison_source"),
    ("question", "original_comparison_question"),
])
def test_actual_original_comparison_failures_are_closed_and_preserve_billing(fault, reason):
    from schulpilot.visual_references import _meaningful

    quote = "I play football. She plays football."
    block = {"kind": "forms", "title": "Öffentliche künstliche Beispiele", "disclosure": "solution",
        "source_excerpt": quote, "labels": ["I play football.", "She plays football."],
        "numbers": [], "connections": [], "marks": [], "unit": "", "variant": "classification",
        "scene": None, "text_probe": None, "lab": None}
    sources = [quote]
    question = {"prompt": "Which verb appears in She plays football.?"}
    if fault == "shape":
        block["labels"] = block["labels"][:1]
    elif fault == "label":
        block["labels"][1] = "We swim."
    elif fault == "source":
        sources = ["Unrelated public artificial source."]
    else:
        question["prompt"] = "An unrelated artificial question."
    graphic = Graphic.model_validate(block)
    with pytest.raises(ValueError) as caught:
        _meaningful(graphic, {"id": "language.forms.original_comparison", "kind": "forms",
            "variant": "classification"}, sources=sources, question=question)
    value = result()
    before = copy.deepcopy(value.__dict__)
    annotate(value, caught.value, phase="visual")
    assert value.telemetry["validation"] == {"version": 1, "phase": "visual",
        "errors": [{"location": "field", "reason": reason}]}
    assert {key: item for key, item in value.__dict__.items() if key != "telemetry"} == {
        key: item for key, item in before.items() if key != "telemetry"}
    assert value.telemetry["cost_preflight"] == before["telemetry"]["cost_preflight"]
    assert quote not in json.dumps(value.telemetry)
    annotate(value, ValueError(caught.value.args[0] + " PRIVATE_SOURCE_SUFFIX"), phase="visual")
    assert value.telemetry["validation"]["errors"] == [{"location": "field", "reason": "schema_validation"}]
    assert "PRIVATE" not in json.dumps(value.telemetry)


@pytest.mark.parametrize("message,reason", [
    ("Ungültige Struktur der vorbereiteten Grafikzuordnung.", "prepared_graphic_structure"),
    ("Unbekannte vorbereitete Grafik-ID.", "prepared_graphic_id"),
    ("Vorbereitete Grafik gehört nicht zum Fach oder zur Paketgruppe.", "prepared_graphic_scope"),
    ("Vorbereitete Grafikmetadaten stimmen nicht mit der Auswahl überein.", "prepared_graphic_metadata"),
    ("Vorbereitete Grafik gehört nicht zur erlaubten Aufdeckstufe.", "prepared_graphic_disclosure"),
    ("Vorbereitete Grafik passt nicht zu den ausdrücklichen Frageparametern.", "prepared_graphic_question_anchor"),
    ("Ungültige vorbereitete Grafikzuordnung.", "prepared_graphic_binding"),
])
def test_prepared_graphic_guard_metadata_is_closed_and_does_not_change_billing(message, reason):
    value = result()
    before = copy.deepcopy(value.__dict__)
    annotate(value, ValueError(message), phase="prepared_graphics")
    assert value.telemetry["validation"] == {"version": 1, "phase": "prepared_graphics",
        "errors": [{"location": "field", "reason": reason}]}
    assert {key: item for key, item in value.__dict__.items() if key != "telemetry"} == {
        key: item for key, item in before.items() if key != "telemetry"}
    assert value.telemetry["cost_preflight"] == before["telemetry"]["cost_preflight"]
    annotate(value, ValueError(message + " PRIVATE_SOURCE_SUFFIX"), phase="prepared_graphics")
    assert value.telemetry["validation"]["errors"] == [{"location": "field", "reason": "schema_validation"}]
    assert "PRIVATE" not in json.dumps(value.telemetry)
