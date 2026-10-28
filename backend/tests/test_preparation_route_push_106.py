"""Synthetic routing/budget and exact-run completion notices; no network calls."""

import uuid
from datetime import datetime, timezone

import pytest
from conftest import HEADERS
from fastapi import HTTPException
from fastapi.testclient import TestClient
from schulpilot import notifications as n
from schulpilot.db import (
    DB,
    Child,
    Family,
    Job,
    Material,
    ProviderConfig,
    PushDelivery,
    PushDevice,
    SchoolDay,
    Session,
    Usage,
    UsageBucket,
    now,
)
from schulpilot.job_failures import generation_availability
from schulpilot.main import app
from schulpilot.model_routing import features_for, select_route
from schulpilot.preparation_notifications import valid_preparation_path
from schulpilot.providers import reserve
from schulpilot.school_preparation import preparation_data
from sqlalchemy import func, select
from test_model_routing import setup_policy
from test_notifications import device, enable


def route_case(parent, child, *, remaining=402879, calls=190):
    fid = parent["families"][0]["id"]
    setup_policy(fid)
    with DB.begin() as db:
        cfg = db.get(ProviderConfig, 1)
        cfg.reserve_micros = 500000
        cfg.global_limit_micros = 10000000
        cfg.routing_policy = {**cfg.routing_policy, "routes": {
            key: {**value, "reserve_micros": 150000} for key, value in cfg.routing_policy["routes"].items()}}
        family = db.get(Family, fid)
        family.call_limit, family.budget_micros = 10000, 2000000
        bucket = UsageBucket(id=f"{fid}:{datetime.now(timezone.utc):%Y-%m}", calls=calls,
            encumbered_micros=2000000 - remaining, known_cost_micros=454121, unknown_calls=100)
        db.add(bucket)
        material = Material(child_id=child["id"], title="SYNTHETIC", status="uploaded")
        db.add(material)
        db.flush()
        job = Job(child_id=child["id"], kind="extract", payload={"material_id": material.id}, idempotency=uuid.uuid4().hex)
        db.add(job)
        db.flush()
        return fid, material.id, job.id


def test_route_preflight_matches_actual150k_reservation_despite_base500k(api, household):
    parent, child = household
    fid, _, job_id = route_case(parent, child)
    with DB() as db:
        family = db.get(Family, fid)
        assert generation_availability(db, family, "extract", child_id=child["id"], job_id=job_id) is None
        assert not db.new and not db.dirty and db.scalar(select(func.count()).select_from(Usage)) == 0
        selected = select_route(db.get(ProviderConfig, 1), "extract", features_for(db, child["id"], job_id))
        assert selected.reserve_micros == 150000
        actual = reserve(db, family, child["id"], job_id, "extract")
        assert actual.reserved_micros == 150000
        assert db.get(ProviderConfig, 1).reserve_micros == 500000
        assert family.budget_micros == 2000000 and family.call_limit == 10000
        db.rollback()


@pytest.mark.parametrize("remaining,calls", [(149999, 190), (402879, 10000)])
def test_real_route_budget_and_call_caps_still_block_without_any_mutation(api, household, remaining, calls):
    parent, child = household
    fid, _, job_id = route_case(parent, child, remaining=remaining, calls=calls)
    with DB() as db:
        value = generation_availability(db, db.get(Family, fid), "extract", child_id=child["id"], job_id=job_id)
        assert value["code"] == "quota_exhausted" and "Neue KI-Verarbeitung" in value["message"]
        assert "Lernumfang" not in value["message"]
        assert not db.new and not db.dirty
        with pytest.raises(HTTPException) as error:
            reserve(db, db.get(Family, fid), child["id"], job_id, "extract")
        assert error.value.status_code == 429


def test_selected_route_still_honors_emergency_stop(api, household):
    parent, child = household
    fid, _, job_id = route_case(parent, child)
    with DB.begin() as db:
        db.get(ProviderConfig, 1).emergency_stop = True
    with DB() as db:
        assert generation_availability(db, db.get(Family, fid), "extract", child_id=child["id"], job_id=job_id)["code"] == "not_configured"


@pytest.mark.parametrize("status,confirmed,old_phase,next_kind", [
    ("uploaded", False, "package", "extract"), ("confirmed", True, "extract", "package"),
    ("review", False, "extract", None), ("unreadable", False, "extract", None),
])
def test_retry_uses_next_actual_phase_and_preserves_original_failure(api, household, monkeypatch, status, confirmed, old_phase, next_kind):
    parent, child = household
    fid, material_id, _ = route_case(parent, child)
    with DB.begin() as db:
        day = SchoolDay(child_id=child["id"], school_date="2026-10-24")
        db.add(day)
        db.flush()
        material = db.get(Material, material_id)
        material.school_day_id, material.status, material.confirmed = day.id, status, confirmed
        material.content, material.subject = "SYNTHETIC current source", "Mathematik"
        day.preparation = {"status": "failed", "phase": old_phase,
            "error": "Die KI hat die begrenzte Ausgabelänge erreicht.",
            "sources": [{"id": material.id, "revision": material.revision}]}
        day_id = day.id
    seen = []
    def availability(db, family, function, **kwargs):
        seen.append((function, kwargs))
        assert family.id == fid and kwargs["child_id"] == child["id"]
        return None
    monkeypatch.setattr("schulpilot.job_failures.generation_availability", availability)
    with DB() as db:
        value = preparation_data(db, db.get(SchoolDay, day_id), db.get(Child, child["id"]))
        assert value["can_retry"] is True and value["retry_kind"] == next_kind
        assert "Ausgabelänge" in value["error"] and value["error_code"] == "invalid_output"
        assert value["retry_blocker"] is None and not db.new and not db.dirty
    assert [call[0] for call in seen] == ([next_kind] if next_kind else [])


@pytest.fixture
def completion(api, household, tmp_path):
    parent, child = household
    enable(tmp_path)
    with DB.begin() as db:
        db.get(Child, child["id"]).preferences = {"push_consent": True, "reminders": False, "quiet_start": 0, "quiet_end": 0}
    with TestClient(app, headers=HEADERS) as kid:
        login = kid.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}).json()
        kid.headers["Authorization"] = "Bearer " + login["token"]
        device_id = device(kid)["id"]
        fixed = int(now())
        with DB.begin() as db:
            session_id = db.get(PushDevice, device_id).session_id
            day = SchoolDay(child_id=child["id"], school_date="2026-10-24")
            db.add(day)
            db.flush()
            material = Material(child_id=child["id"], school_day_id=day.id, title="PRIVATE SYNTHETIC TITLE",
                status="review", content="PRIVATE SYNTHETIC TEXT")
            db.add(material)
            db.flush()
            day.preparation = {"run_id": uuid.uuid4().hex, "status": "needs_review", "notice_status": "needs_review",
                "notice_created": fixed, "session_id": session_id, "user_id": db.get(Child, child["id"]).user_id,
                "family_id": parent["families"][0]["id"], "day_revision": day.revision,
                "sources": [{"id": material.id, "revision": material.revision}]}
            value = {"child_id": child["id"], "day_id": day.id, "material_id": material.id,
                "device_id": device_id, "session_id": session_id, "fixed": fixed}
        yield value


def test_completion_retries_get_exact_run_status_dedupe_and_same_day_route(completion, monkeypatch):
    value = completion
    sent = []
    monkeypatch.setattr(n, "now", lambda: value["fixed"])
    monkeypatch.setattr(n, "send_fcm", lambda *args, **kwargs: sent.append((args, kwargs)))
    for status, new_run in [("needs_review", False), ("ready", False), ("ready", True)]:
        with DB.begin() as db:
            day = db.get(SchoolDay, value["day_id"])
            state = {**day.preparation, "status": status, "notice_status": status}
            if new_run:
                state["run_id"] = uuid.uuid4().hex
            day.preparation = state
            n.prepare(db, value["fixed"])
            n.prepare(db, value["fixed"])
        assert n.deliver_one(DB)
        assert not n.deliver_one(DB)
    assert len(sent) == 3
    assert all(kwargs == {"preparation_path": f"/after-school/{value['child_id']}?day={value['day_id']}"} for _, kwargs in sent)
    assert all("PRIVATE" not in str(call) for call in sent)
    with DB() as db:
        deliveries = list(db.scalars(select(PushDelivery)))
        assert len(deliveries) == 3 and all(row.status == "accepted" for row in deliveries)
        assert len({row.dedup_key for row in deliveries}) == 3
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


@pytest.mark.parametrize("change", ["consent", "device_quiet", "child_quiet", "source", "session", "run"])
def test_completion_rechecks_consent_quiet_source_actor_and_exact_run_before_send(completion, monkeypatch, change):
    value = completion
    with DB.begin() as db:
        n.prepare(db, value["fixed"])
        assert db.scalar(select(func.count()).select_from(PushDelivery)) == 1
    with DB.begin() as db:
        child = db.get(Child, value["child_id"])
        if change == "consent":
            child.preferences = {**child.preferences, "push_consent": False}
        elif change in ("device_quiet", "child_quiet"):
            hour = datetime.fromtimestamp(value["fixed"], timezone.utc).hour
            if change == "device_quiet":
                row = db.get(PushDevice, value["device_id"])
                row.timezone, row.quiet_start, row.quiet_end = "UTC", hour, (hour + 1) % 24
            else:
                child.preferences = {**child.preferences, "timezone": "UTC", "quiet_start": hour, "quiet_end": (hour + 1) % 24}
        elif change == "source":
            db.get(Material, value["material_id"]).revision += 1
        elif change == "session":
            db.get(Session, value["session_id"]).revoked = True
        else:
            day = db.get(SchoolDay, value["day_id"])
            day.preparation = {**day.preparation, "run_id": uuid.uuid4().hex}
    sent = []
    monkeypatch.setattr(n, "now", lambda: value["fixed"])
    monkeypatch.setattr(n, "send_fcm", lambda *args, **kwargs: sent.append((args, kwargs)))
    assert n.deliver_one(DB) and sent == []
    with DB() as db:
        assert db.scalar(select(PushDelivery)).status == "suppressed"


@pytest.mark.parametrize("suffix", ["\n", "\u2028", "#fragment", "&extra=1", "/../../", "?redirect=https://example.invalid"])
def test_only_exact_local_after_school_paths_are_accepted(suffix):
    route = "/after-school/" + "a" * 32 + "?day=" + "b" * 32
    assert valid_preparation_path(route) and not valid_preparation_path(route + suffix)
    with pytest.raises(n.FcmError):
        n.send_fcm("SYNTHETIC", "preparation_ready", preparation_path=route + suffix)


def test_service_worker_handles_wrapped_and_flat_exact_preparation_routes(api, tmp_path):
    enable(tmp_path)
    script = api.get("/api/notifications/service-worker.js").text
    assert "data.FCM_MSG.data" in script and "payload.route" in script
    assert r"after-school\/[a-f0-9]{32}\?day=" in script
    assert "(?![\\s\\S])" in script and " : '/app'" in script
    assert "PRIVATE" not in script and "fetch(" not in script


def test_preparation_fcm_transports_neutral_exact_route_and_same_origin_link(api, tmp_path, monkeypatch):
    import json
    from pathlib import Path

    import httpx
    from google.oauth2 import service_account
    from schulpilot.config import settings

    enable(tmp_path)
    Path(settings.fcm_service_account_file).write_text(json.dumps({"type": "service_account",
        "project_id": "synthetic-project", "token_uri": "https://oauth2.googleapis.com/token"}))
    class Credential:
        token = "SYNTHETIC-OAUTH-TOKEN"

        def refresh(self, request):
            pass

    monkeypatch.setattr(service_account.Credentials, "from_service_account_info", lambda *args, **kwargs: Credential())
    sent = []
    class Client:
        def __init__(self, **kwargs):
            assert kwargs["follow_redirects"] is False

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def post(self, url, headers, json):
            sent.append(json["message"])
            return httpx.Response(200, json={"name": "synthetic-message"})

    route = "/after-school/" + "a" * 32 + "?day=" + "b" * 32
    monkeypatch.setattr(n.httpx, "Client", Client)
    n.send_fcm("SYNTHETIC-TOKEN", "preparation_ready", preparation_path=route)
    assert sent[0]["data"] == {"route": route}
    assert sent[0]["webpush"]["fcm_options"]["link"] == settings.public_url + route
    assert sent[0]["notification"] == {"title": "SchuleSchlau",
        "body": "Es gibt Neuigkeiten in SchuleSchlau. Öffne deinen Lernraum."}
    assert all(secret not in str(sent) for secret in ("PRIVATE SYNTHETIC TITLE", "PRIVATE SYNTHETIC TEXT"))
    assert sent[0]["android"]["ttl"] == "60s" and sent[0]["android"]["notification"]["visibility"] == "PRIVATE"


@pytest.mark.parametrize("fault", ["same", "old_revision", "other_material", "not_failed", "other_error"])
def test_explicit_retry_selects_sol_only_after_same_revision_output_truncation(api, household, fault):
    from schulpilot.model_routing import choose_tier, extraction_failed

    parent, child = household
    fid, material_id, next_job_id = route_case(parent, child)
    with DB.begin() as db:
        material = db.get(Material, material_id)
        failure = Job(child_id=child["id"], kind="extract", status="failed",
            payload={"material_id": material_id, "material_revision": material.revision},
            error="Die KI hat die begrenzte Ausgabelänge erreicht.", idempotency=uuid.uuid4().hex)
        if fault == "old_revision":
            failure.payload = {**failure.payload, "material_revision": material.revision + 1}
        elif fault == "other_material":
            failure.payload = {**failure.payload, "material_id": uuid.uuid4().hex}
        elif fault == "not_failed":
            failure.status = "completed"
        elif fault == "other_error":
            failure.error = "Die Quelle wurde geändert."
        db.add(failure)
    with DB() as db:
        recorded = extraction_failed(db, child["id"], material_id)
        assert recorded is (fault == "same")
        facts = features_for(db, child["id"], next_job_id)
        assert facts["extraction_failed"] is recorded
        tier, reason = choose_tier("extract", facts, economy=True)
        assert tier == ("sol" if recorded else "luna")
        if recorded:
            assert reason == "recorded_transcription_failure"
        assert generation_availability(db, db.get(Family, fid), "extract", child_id=child["id"], job_id=next_job_id) is None
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_retry_preflight_uses_the_same_higher_selected_sol_reservation(api, household):
    parent, child = household
    fid, material_id, _ = route_case(parent, child, remaining=175000)
    with DB.begin() as db:
        cfg = db.get(ProviderConfig, 1)
        cfg.routing_policy = {**cfg.routing_policy, "routes": {**cfg.routing_policy["routes"],
            "sol": {**cfg.routing_policy["routes"]["sol"], "reserve_micros": 200000}}}
        day = SchoolDay(child_id=child["id"], school_date="2026-10-24")
        db.add(day)
        db.flush()
        material = db.get(Material, material_id)
        material.school_day_id = day.id
        db.add(Job(child_id=child["id"], kind="extract", status="failed", error="Die KI hat die begrenzte Ausgabelänge erreicht.",
            payload={"material_id": material_id, "material_revision": material.revision}, idempotency=uuid.uuid4().hex))
        day.preparation = {"status": "failed", "phase": "extract", "error": "Die KI hat die begrenzte Ausgabelänge erreicht.",
            "sources": [{"id": material_id, "revision": material.revision}]}
        day_id = day.id
    with DB() as db:
        value = preparation_data(db, db.get(SchoolDay, day_id), db.get(Child, child["id"]))
        assert value["retry_kind"] == "extract" and value["retry_blocker"]["code"] == "quota_exhausted"
        assert value["can_retry"] is False
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
