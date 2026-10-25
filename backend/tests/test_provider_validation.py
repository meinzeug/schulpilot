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
