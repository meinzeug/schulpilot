"""One conscious repair of a proven old free dispatch; no providers/network."""

import copy
from concurrent.futures import ThreadPoolExecutor
from types import SimpleNamespace

import pytest
from conftest import HEADERS
from fastapi.testclient import TestClient
from schulpilot.db import DB, Audit, Child, Family, Job, Material, ProviderConfig, SchoolDay, Session, Usage
from schulpilot.main import app
from schulpilot.model_routing import select_route
from schulpilot.package_transport import LEGACY_REVISION, REVISION, repair_revision
from schulpilot.provider_cost_preflight import projection
from schulpilot.providers import ProviderError, Result, reserve, settle
from schulpilot.school_preparation import _fingerprint
from schulpilot.security import digest
from sqlalchemy import func, select
from test_model_routing import setup_policy
from test_school_preparation import step


def proof():
    config = SimpleNamespace(revision=4, max_output_tokens=4000, reserve_micros=500000)
    route = {
        "model": "openai/gpt-6.1-sol",
        "input_per_million_micros": 2000000,
        "output_per_million_micros": 10000000,
        "max_output_tokens": 4000,
        "reserve_micros": 150000,
    }
    usage = SimpleNamespace(
        function="package",
        provider="openrouter",
        config_revision=4,
        status="failed_not_sent",
        cost_source="cancelled",
        cost_micros=0,
        input_tokens=0,
        output_tokens=0,
        reserved_micros=150000,
        model=route["model"],
        route_snapshot={"route": route},
        telemetry={
            "pre_dispatch": True,
            "cost_preflight": {
                "version": 1,
                "basis": "text_bytes",
                "text_bytes": 131697,
                "image_input_allowance": 0,
                "profile_sha256": None,
                "projected_micros": 311586,
                "reserved_micros": 150000,
                "guaranteed_invoice_ceiling": False,
            },
        },
    )
    return usage, config


def test_exact_old_route_proof_is_distinct_from_current_unknown_and_sent_requests():
    usage, config = proof()
    assert repair_revision(usage, config) == LEGACY_REVISION
    assert usage.telemetry["cost_preflight"]["projected_micros"] == 311586
    for stamp in (LEGACY_REVISION, REVISION, "unknown-future"):
        usage.telemetry["cost_preflight"]["transport_revision"] = stamp
        assert repair_revision(usage, config) == (LEGACY_REVISION if stamp == LEGACY_REVISION else None)


@pytest.mark.parametrize(
    "change",
    [
        "function",
        "provider",
        "config_revision",
        "status",
        "cost_source",
        "cost",
        "input",
        "output",
        "null_cost",
        "pre_dispatch",
        "no_snapshot",
        "no_preflight",
        "rate",
        "projection",
        "reserve",
        "image",
        "model",
        "bool_rate",
        "max_output",
        "unknown_revision",
    ],
)
def test_incomplete_or_changed_old_accounting_cannot_unlock_a_repair(change):
    usage, config = proof()
    if change == "function":
        usage.function = "unit"
    elif change == "provider":
        usage.provider = "codex"
    elif change == "config_revision":
        usage.config_revision = 3
    elif change == "status":
        usage.status = "failed_unknown"
    elif change == "cost_source":
        usage.cost_source = "unknown"
    elif change == "cost":
        usage.cost_micros = 1
    elif change == "input":
        usage.input_tokens = 1
    elif change == "output":
        usage.output_tokens = 1
    elif change == "null_cost":
        usage.cost_micros = None
    elif change == "pre_dispatch":
        usage.telemetry["pre_dispatch"] = False
    elif change == "no_snapshot":
        usage.route_snapshot = {}
    elif change == "no_preflight":
        usage.telemetry = {"pre_dispatch": True}
    elif change == "rate":
        usage.route_snapshot["route"]["input_per_million_micros"] += 1
    elif change == "projection":
        usage.telemetry["cost_preflight"]["projected_micros"] += 1
    elif change == "reserve":
        usage.reserved_micros = 149999
    elif change == "image":
        usage.telemetry["cost_preflight"]["image_input_allowance"] = 1000
    elif change == "model":
        usage.route_snapshot["route"]["model"] = "another/model"
    elif change == "bool_rate":
        usage.route_snapshot["route"]["max_output_tokens"] = True
    elif change == "max_output":
        config.max_output_tokens = 3999
    elif change == "unknown_revision":
        usage.telemetry["cost_preflight"]["transport_revision"] = "not-a-known-transport"
    assert repair_revision(usage, config) is None


def failed_package(api, parent, child):
    fid = parent["families"][0]["id"]
    setup_policy(fid)
    with DB.begin() as db:
        cfg = db.get(ProviderConfig, 1)
        cfg.reserve_micros = 500000
        cfg.max_output_tokens = 4000
        cfg.global_limit_micros = 10000000
        cfg.routing_policy = {
            **cfg.routing_policy,
            "routes": {
                name: {
                    **route,
                    "input_per_million_micros": 2000000,
                    "output_per_million_micros": 10000000,
                    "max_output_tokens": 4000,
                    "reserve_micros": 150000,
                }
                for name, route in cfg.routing_policy["routes"].items()
            },
        }
        db.get(Family, fid).budget_micros = 3000000
        db.get(Child, child["id"]).preferences = {
            "weekdays": list(range(7)),
            "daily_minutes": 40,
            "weekly_minutes": 280,
            "session_minutes": 15,
        }
    response = api.post(f"/api/children/{child['id']}/school-day/today")
    assert response.status_code == 201, response.text
    day_id = response.json()["id"]
    with DB.begin() as db:
        day = db.get(SchoolDay, day_id)
        day.stage = "review"
        material = Material(
            child_id=child["id"],
            school_day_id=day.id,
            title="Eigene künstliche Quelle",
            subject="Mathematik",
            topic="Brüche",
            content="Ein Bruch besteht aus Zähler und Nenner.",
            status="confirmed",
            confirmed=True,
            page_number=1,
        )
        db.add(material)
        db.flush()
        sources = [{"id": material.id, "revision": material.revision}]
        session = db.scalar(
            select(Session)
            .where(Session.user_id == parent["id"], Session.revoked.is_(False))
            .order_by(Session.created.desc())
        )
        run = "legacy-run"
        job = Job(
            child_id=child["id"],
            kind="package",
            status="failed",
            error="Material überschreitet die konfigurierte konservative Kostenreservierung.",
            error_code="cost_preflight",
            idempotency="old-package-proof",
            payload={
                "material_id": material.id,
                "material_revision": material.revision,
                "sources": sources,
                "school_day_id": day.id,
                "preparation_id": run,
            },
        )
        db.add(job)
        db.flush()
        usage = reserve(db, db.get(Family, fid), child["id"], job.id, "package")
        selected = select_route(db.get(ProviderConfig, 1), "package", snapshot=usage.route_snapshot)
        preflight = projection(selected, "package", 131697, None, 0)
        settle(
            db,
            usage,
            Result({}, 0, 0, 0, telemetry={"pre_dispatch": True, "cost_preflight": preflight}, cost_source="cancelled"),
            failed=True,
        )
        day.preparation = {
            "run_id": run,
            "status": "failed",
            "phase": "package",
            "job_id": job.id,
            "session_id": session.id,
            "user_id": parent["id"],
            "family_id": fid,
            "sources": sources,
            "day_revision": day.revision,
            "error": job.error,
            "requests": [{"key": digest(parent["id"] + ":old-submit"), "fingerprint": _fingerprint(sources)}],
            "package_attempts": {_fingerprint(sources): 1},
            "extract_attempts": {},
        }
        return day_id, job.id, usage.id


def counts():
    with DB() as db:
        return tuple(db.scalar(select(func.count()).select_from(model)) for model in (Job, Usage, Audit))


def test_get_and_replay_never_start_repair_but_one_conscious_post_is_audited(api, household, monkeypatch):
    parent, child = household
    day, old_job, usage_id = failed_package(api, parent, child)
    before = counts()
    with DB() as db:
        history = copy.deepcopy(db.get(Usage, usage_id).telemetry)
    for _ in range(2):
        value = api.get(f"/api/school-days/{day}").json()["preparation"]
        assert value["can_retry"] is True
        assert value["job"]["id"] == old_job
    assert counts() == before
    replay = api.post(f"/api/school-days/{day}/prepare", headers={"Idempotency-Key": "old-submit"})
    assert replay.status_code == 202
    assert counts() == before
    first = api.post(f"/api/school-days/{day}/prepare", headers={"Idempotency-Key": "repair-submit"})
    assert first.status_code == 202, first.text
    new_job = first.json()["preparation"]["job"]["id"]
    assert new_job != old_job
    for key in ("repair-submit", "another-conscious-key"):
        repeated = api.post(f"/api/school-days/{day}/prepare", headers={"Idempotency-Key": key})
        assert repeated.status_code == 202, repeated.text
        assert repeated.json()["preparation"]["job"]["id"] == new_job
    with DB() as db:
        assert db.get(Usage, usage_id).telemetry == history
        assert db.get(Job, old_job).status == "failed"
        audit = db.scalar(select(Audit).where(Audit.action == "school_day.package_transport_repair"))
        assert audit.actor == parent["id"]
        assert audit.target == old_job + ":" + REVISION
        assert db.get(SchoolDay, day).preparation["transport_repair"]["to_revision"] == REVISION
    after = counts()
    assert after[0] == before[0] + 1 and after[1] == before[1] + 1 and after[2] == before[2] + 1

    def current_failure(*args, **kwargs):
        raise ProviderError(
            "Material überschreitet die konfigurierte konservative Kostenreservierung.",
            code="cost_preflight",
            billing_result=Result(
                {},
                0,
                0,
                0,
                telemetry={
                    "pre_dispatch": True,
                    "cost_preflight": {**history["cost_preflight"], "transport_revision": REVISION},
                },
                cost_source="cancelled",
            ),
        )

    monkeypatch.setattr("schulpilot.worker.request_provider", current_failure)
    assert step() == new_job
    blocked = api.get(f"/api/school-days/{day}").json()["preparation"]
    assert not blocked["can_retry"] and blocked["retry_blocker"]["code"] == "cost_preflight"
    assert api.post(f"/api/school-days/{day}/prepare", headers={"Idempotency-Key": "no-loop"}).status_code == 409
    assert counts() == after


@pytest.mark.parametrize("missing", ["telemetry", "billing", "route"])
def test_unknown_old_proof_stays_blocked_and_preserves_sources(api, household, missing):
    parent, child = household
    day, _, usage_id = failed_package(api, parent, child)
    with DB.begin() as db:
        usage = db.get(Usage, usage_id)
        if missing == "telemetry":
            usage.telemetry = {"pre_dispatch": True}
        elif missing == "billing":
            usage.cost_micros = None
        else:
            usage.route_snapshot = {}
    before = counts()
    value = api.get(f"/api/school-days/{day}").json()["preparation"]
    assert not value["can_retry"]
    assert api.post(f"/api/school-days/{day}/prepare", headers={"Idempotency-Key": "not-proven"}).status_code == 409
    assert counts() == before
    with DB() as db:
        assert db.scalar(select(Material).where(Material.school_day_id == day)).confirmed


def test_parallel_conscious_repair_reserves_and_audits_only_once(api, household):
    parent, child = household
    day, old_job, _ = failed_package(api, parent, child)
    before = counts()
    headers = {**HEADERS, "Authorization": api.headers["Authorization"]}

    def submit(index):
        with TestClient(app, headers=headers) as client:
            response = client.post(
                f"/api/school-days/{day}/prepare", headers={"Idempotency-Key": f"conscious-repair-{index}"}
            )
            assert response.status_code == 202, response.text
            return response.json()["preparation"]["job"]["id"]

    with ThreadPoolExecutor(max_workers=2) as pool:
        jobs = list(pool.map(submit, range(2)))
    assert jobs[0] == jobs[1] and jobs[0] != old_job
    after = counts()
    assert after[0] == before[0] + 1 and after[1] == before[1] + 1 and after[2] == before[2] + 1
