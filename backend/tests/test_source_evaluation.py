"""Bounded operator diagnosis with artificial local photos and mocked transport."""

import io

import pytest
from fastapi import HTTPException
from PIL import Image
from schulpilot import providers
from schulpilot.config import settings
from schulpilot.db import DB, Activity, Family, Job, LearningUnit, Material, ProviderConfig, Usage, User, uid
from schulpilot.providers import Result, reserve, settle
from schulpilot.source_evaluation import (
    CAP_MICROS,
    WORK_ID,
    create_grant,
    dispatched,
    prepare_case,
    reserve_guard,
    run_case,
    settled,
    used_micros,
)
from schulpilot.source_lineage import purge_diagnostic_outputs
from schulpilot.source_lineage_models import SourceEvaluationCase, SourceEvaluationGrant
from sqlalchemy import func, select
from test_model_routing import setup_policy


def authorized(household):
    user, child = household
    fid = user["families"][0]["id"]
    setup_policy(fid)
    with DB.begin() as db:
        operator = User(
            username="synthetic-local-operator",
            display_name="Künstlicher Betrieb",
            role="admin",
            verified=True,
            password_hash="not-used-by-local-test",
        )
        db.add(operator)
        photo = Image.new("RGB", (600, 900), "white")
        out = io.BytesIO()
        photo.save(out, "JPEG")
        folder = settings.data_dir / "uploads"
        folder.mkdir(exist_ok=True)
        path = uid() + ".jpg"
        (folder / path).write_bytes(out.getvalue())
        material = Material(
            child_id=child["id"],
            title="Ausschließlich künstliches Diagnosebild",
            path=path,
            subject="Mathematik",
            topic="Künstlicher Stoff",
            content="Vorhandene ungeänderte Abschrift",
            confirmed=True,
        )
        db.add(material)
        db.flush()
        operator_id, mid = operator.id, material.id
        grant = create_grant(db, operator_id, fid, [mid])
        gid = grant.id
    return fid, child["id"], mid, gid, operator_id


def reserve_case(fid, mid, gid, key="fixed-case-001", tier="luna"):
    with DB.begin() as db:
        row = prepare_case(db, gid, mid, tier, key)
        job = db.get(Job, row.job_id)
        usage = reserve(
            db, db.get(Family, fid), job.child_id, job.id, "extract", probe_tier=tier, operator_evaluation=row.id
        )
        return row.id, usage.id


def test_real_operator_grant_uses_normal_budget_and_never_synthetic_bypass(api, household):
    fid, child, mid, gid, operator = authorized(household)
    cid, usage_id = reserve_case(fid, mid, gid, tier="sol")
    with DB() as db:
        usage = db.get(Usage, usage_id)
        row = db.get(SourceEvaluationCase, cid)
        assert usage.route_snapshot["tier"] == "sol"
        assert usage.route_snapshot["reason"] == "explicit_operator_ocr_diagnosis"
        assert usage.family_id == fid and usage.child_id == child
        assert usage.reserved_micros == row.reserved_micros == used_micros(db)
        assert db.get(Job, row.job_id).status == "operator_held"
        assert not db.get(Family, fid).synthetic
    with DB.begin() as db:
        with pytest.raises(HTTPException) as error:
            prepare_case(db, gid, mid, "sol", "fixed-case-001")
        assert error.value.status_code == 409
    with DB.begin() as db:
        db.get(User, operator).disabled = True
    with DB.begin() as db:
        with pytest.raises(HTTPException):
            row = db.get(SourceEvaluationCase, cid)
            reserve_guard(db, db.get(Family, fid), child, row.job_id, "extract", "sol", cid)


@pytest.mark.parametrize("change", ["expiry", "revision", "config", "image", "foreign", "synthetic"])
def test_grant_scope_changes_reject_before_usage_or_provider(api, household, change):
    from schulpilot.db import Child

    fid, child, mid, gid, _ = authorized(household)
    with DB.begin() as db:
        if change == "expiry":
            db.get(SourceEvaluationGrant, gid).expires = 0
        elif change == "revision":
            db.get(Material, mid).revision += 1
        elif change == "config":
            db.get(ProviderConfig, 1).revision += 1
        elif change == "image":
            material = db.get(Material, mid)
            (settings.data_dir / "uploads" / material.path).write_bytes(b"changed-artificial-image")
        elif change == "foreign":
            foreign = Family(id=uid(), name="Andere künstliche Familie", synthetic=False)
            db.add(foreign)
            db.flush()
            db.get(Child, child).family_id = foreign.id
        else:
            db.get(Material, mid).synthetic = True
    with pytest.raises(HTTPException):
        reserve_case(fid, mid, gid)
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_budget_is_durable_across_grants_counts_unknown_holds_and_actual_cost(api, household):
    fid, _, mid, gid, operator = authorized(household)
    with DB.begin() as db:
        config = db.get(ProviderConfig, 1)
        policy = config.routing_policy
        config.reserve_micros = 150_000
        config.routing_policy = {
            **policy,
            "routes": {tier: {**route, "reserve_micros": 150_000} for tier, route in policy["routes"].items()},
        }
        # A changed config deliberately needs a new explicit grant.
        grant = create_grant(db, operator, fid, [mid])
        gid = grant.id
    cid, usage_id = reserve_case(fid, mid, gid, "fixed-budget-001")
    with pytest.raises(HTTPException) as error:
        reserve_case(fid, mid, gid, "fixed-budget-002")
    assert error.value.status_code == 429
    with DB() as db:
        assert used_micros(db) == 150_000
    with DB.begin() as db:
        usage = db.get(Usage, usage_id)
        settle(db, usage, Result({}, cost_micros=10_000, input_tokens=10, output_tokens=10, cost_source="reported"))
        settled(db, cid, usage)
        newer = create_grant(db, operator, fid, [mid])
        another_gid = newer.id
    reserve_case(fid, mid, another_gid, "fixed-budget-003")
    with DB() as db:
        assert used_micros(db) == 160_000 < CAP_MICROS
    with pytest.raises(HTTPException):
        reserve_case(fid, mid, another_gid, "fixed-budget-004")
    with DB() as db:
        assert used_micros(db) == 160_000


def test_dispatch_cas_has_no_second_call_even_after_process_restart(api, household):
    fid, _, mid, gid, _ = authorized(household)
    cid, _ = reserve_case(fid, mid, gid)
    with DB.begin() as db:
        dispatched(db, cid)
    with DB.begin() as db:
        with pytest.raises(HTTPException) as error:
            dispatched(db, cid)
        assert error.value.status_code == 409


def test_bounded_transport_is_diagnostic_only_and_outputs_stay_server_private(api, household, monkeypatch):
    fid, _, mid, gid, _ = authorized(household)
    called = []

    def fake(config, function, payload, image, *, synthetic_fixture):
        called.append((function, synthetic_fixture, config.model))
        return Result(
            dict(
                subject="Mathematik",
                topic="Künstliche Diagnose",
                content="2+2=4",
                source_blocks=[dict(kind="formula", text="2+2=4")],
                uncertainties=[],
                homework=[],
                legibility="readable",
            ),
            input_tokens=10,
            output_tokens=10,
            cost_micros=100,
            cost_source="reported",
            request_receipt={"version": 1, "image_detail": "high", "schema_sha256": "a" * 64},
        )

    monkeypatch.setattr(providers, "request_provider", fake)
    with DB() as db:
        before = {column.name: getattr(db.get(Material, mid), column.name) for column in Material.__table__.columns}
    summary = run_case(gid, mid, "sol", "fixed-mocked-call")
    assert summary["accepted"] and summary["diagnostic_only"] and summary["cost_micros"] == 100
    assert called == [("extract", False, "openai/gpt-6.1-sol")]
    assert "2+2" not in str(summary)
    output = settings.data_dir / "operator-diagnostics" / WORK_ID / (summary["case_id"] + ".json")
    assert output.is_file() and output.stat().st_mode & 0o777 == 0o600
    with DB() as db:
        after = {column.name: getattr(db.get(Material, mid), column.name) for column in Material.__table__.columns}
        assert before == after
        assert db.scalar(select(func.count()).select_from(Activity)) == 0
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 0
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
    with DB.begin() as db:
        purge_diagnostic_outputs(db, [mid])
    assert not output.exists()
    with DB() as db:
        assert used_micros(db) == 100
