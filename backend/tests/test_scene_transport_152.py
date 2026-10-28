"""Synthetic scenes exercise the actual wire, reconstruction and strict gates."""
import copy
import json
from pathlib import Path

import pytest
from pydantic import ValidationError
from schulpilot import graphic_table_transport, graphic_transport, providers, subject_content
from schulpilot.graphic_schema import bind_coherent_graphics
from schulpilot.schemas import UnitOutput
from test_presentation_capability_paths import _config, _scene_unit, _transport

CASES = json.loads((Path(__file__).parents[2] / "testdata/learning_scenes_v1.json").read_text())["cases"]


def schema(subject="Mathematik", labs=False):
    value = providers.strict_schema(UnitOutput, preserve_limits=True)
    subject_content.bind_graphic_schema(value, [subject], labs_enabled=labs)
    bind_coherent_graphics(value)
    return graphic_transport.bind(value).wire_schema


@pytest.mark.parametrize("subject", subject_content.PROFILES)
@pytest.mark.parametrize("labs", [False, True])
def test_actual_array_and_object_depth_is_bounded_for_every_subject(subject, labs):
    canonical = schema(subject, labs)
    before = copy.deepcopy(canonical)
    assert graphic_table_transport.nesting_depth(canonical) > 10
    binding = graphic_table_transport.bind(canonical)
    assert canonical == before
    assert graphic_table_transport.nesting_depth(binding.wire_schema) <= 10
    from test_graphic_native_transport import subset_record
    subset_record(binding.wire_schema)


@pytest.mark.parametrize("case", CASES, ids=lambda case: case["id"])
def test_scene_roundtrip_keeps_sources_disclosure_and_all_frames(case):
    binding = graphic_table_transport.bind(schema(case["subject"]))
    value = {"questions": [copy.deepcopy(case["question"])]}
    before = copy.deepcopy(value)
    wire = binding.encode(value)
    assert value == before
    assert wire["questions"][0]["presentation"]["blocks"][0] == "g0"
    assert wire["graphic_catalog"][0]["graphic"] == value["questions"][0]["presentation"]["blocks"][0]
    assert binding.decode(wire) == value
    assert wire == binding.encode(value)  # Decoder must not mutate input.


@pytest.mark.parametrize("fault", ["unknown", "duplicate", "unused", "missing", "inline", "extra", "malformed"])
def test_corrupt_table_is_rejected_without_guessing_or_partial_reconstruction(fault):
    binding = graphic_table_transport.bind(schema())
    canonical = {"questions": [copy.deepcopy(CASES[0]["question"])]}
    wire = binding.encode(canonical)
    if fault == "unknown":
        wire["questions"][0]["presentation"]["blocks"][0] = "g8"
    elif fault == "duplicate":
        wire["graphic_catalog"].append(copy.deepcopy(wire["graphic_catalog"][0]))
    elif fault == "unused":
        wire["graphic_catalog"].append({**copy.deepcopy(wire["graphic_catalog"][0]), "id": "g1"})
    elif fault == "missing":
        del wire["graphic_catalog"]
    elif fault == "inline":
        wire["questions"][0]["presentation"]["blocks"][0] = copy.deepcopy(CASES[0]["question"]["presentation"]["blocks"][0])
    elif fault == "extra":
        wire["graphic_catalog"][0]["source"] = "extra"
    else:
        wire["graphic_catalog"] = None
    before = copy.deepcopy(wire)
    with pytest.raises(ValueError, match="Grafiktransport"):
        binding.decode(wire)
    assert before == wire


def test_empty_table_supports_old_no_scene_envelopes_but_not_unchecked_scenes():
    binding = graphic_table_transport.bind(schema())
    value = {"questions": [{"presentation": None}]}
    assert binding.decode(value) == value
    assert binding.encode(value) == {**value, "graphic_catalog": []}
    assert binding.decode(binding.encode(value)) == value


def test_graphic_transport_reports_only_closed_diagnostic_codes():
    from schulpilot.provider_validation import annotate
    from schulpilot.providers import Result

    binding = graphic_table_transport.bind(schema())
    value = {"presentation": {"blocks": ["g0"]}, "graphic_catalog": []}
    with pytest.raises(ValueError) as raised:
        binding.decode(value)
    result = Result({}, 0, 0, 0, telemetry={})
    annotate(result, raised.value, phase="transport")
    assert result.telemetry["validation"]["errors"] == [
        {"location": "field", "reason": "graphic_table_reference"}
    ]


def test_decoding_does_not_bypass_canonical_scene_validation():
    binding = graphic_table_transport.bind(schema())
    value = _scene_unit()
    wire = binding.encode(value)
    wire["graphic_catalog"][0]["graphic"]["scene"]["steps"][0]["placements"][0]["slot"] = 1000
    with pytest.raises(ValidationError):
        UnitOutput.model_validate(binding.decode(wire))


def test_completed_provider_response_reconstructs_scene_before_normal_validation(monkeypatch):
    config = _config("openrouter")
    value = _scene_unit()
    case = CASES[0]
    calls = _transport(monkeypatch, "openrouter", value)
    result = providers.request_provider(config, "unit", {"material": {
        "subject": value["subject"], "topic": value["topic"], "content": case["source"]}})
    assert len(calls) == 1
    actual = calls[0]["response_format"]["json_schema"]["schema"]
    assert graphic_table_transport.nesting_depth(actual) <= 10
    assert "graphic_catalog" in actual["required"]
    assert "graphic-table-1" in calls[0]["messages"][0]["content"]
    assert "graphic_catalog" not in result.data
    assert result.data["questions"][0]["presentation"]["blocks"][0]["scene"]["steps"]
    assert result.request_receipt["schema_sha256"]


@pytest.mark.parametrize("location", ["top", "choice"])
def test_http200_diagnostics_remain_private_but_keep_schema_cause(monkeypatch, location):
    import httpx
    config = _config("openrouter")
    private = "PRIVATE-FIXTURE-CONTENT"
    envelope = {"message": "Invalid schema " + private,
        "metadata": {"raw": private, "untrusted": private}, "code": 400}
    raw = {"error": envelope} if location == "top" else {"choices": [{"error": envelope}]}
    calls = []
    real_client = httpx.Client
    def handler(request):
        calls.append(request)
        return httpx.Response(200, json=raw)
    monkeypatch.setattr(providers.httpx, "Client",
        lambda **kw: real_client(transport=httpx.MockTransport(handler), **kw))
    with pytest.raises(providers.ProviderError) as raised:
        providers.request_provider(config, "unit", {"material": {
            "subject": "Informatik", "topic": "UND", "content": "UND und ODER."}})
    assert len(calls) == 1
    telemetry = raised.value.billing_result.telemetry
    assert telemetry["error_type"] == "invalid_schema"
    assert telemetry["provider_error_code"] == 400
    assert private not in str(raised.value) + json.dumps(telemetry)


def test_failed_job_keeps_its_status_and_discovers_only_same_child_repair(household):
    # The regular fixture's child session is used; no administrator content path.
    from types import SimpleNamespace

    from schulpilot import materials
    from schulpilot.db import DB, Child, Job, User, uid
    from schulpilot.security import Principal
    with DB.begin() as db:
        child = db.get(Child, household[1]["id"])
        user = db.get(User, child.user_id)
        principal = Principal(user, SimpleNamespace(family_id=child.family_id))
        failed = Job(child_id=child.id, kind="unit", status="failed", error="Original error",
            error_code="provider_unavailable", payload={}, idempotency=uid())
        db.add(failed)
        db.flush()
        repair = Job(child_id=child.id, kind="unit", status="queued",
            payload={"repairs_failed_job_id": failed.id}, idempotency=uid())
        db.add(repair)
        db.flush()
        data = materials.job_view(failed.id, principal, db)
        assert data["status"] == "failed" and data["error"] == "Original error"
        assert data["recovery_job_id"] == repair.id
        assert db.get(Job, failed.id).result is None
        assert materials.job_view(repair.id, principal, db)["recovery_job_id"] is None
