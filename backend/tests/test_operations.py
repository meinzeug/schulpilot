"""Synthetic-only recovery, monitoring and provider availability checks."""

import json

import pytest
from schulpilot.config import settings
from schulpilot.db import (
    DB,
    Audit,
    Base,
    Child,
    ErasureRequest,
    Family,
    Material,
    ProviderConfig,
    ServiceState,
    Usage,
    now,
)
from schulpilot.erasure import prune_journal, reconcile, signed, verify
from schulpilot.operations import snapshot
from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import Session
from test_school_day import allow_synthetic_test_transport, image_bytes


def test_authenticated_erasure_journal_reconciles_a_separate_snapshot(api, household):
    user, child = household
    allow_synthetic_test_transport()
    material = api.post(
        f"/api/children/{child['id']}/materials", files={"file": ("synthetic.jpg", image_bytes())}
    ).json()
    with DB() as db:
        backup = {table: list(db.execute(table.select()).mappings()) for table in Base.metadata.sorted_tables}
    response = api.request("DELETE", "/api/account", json={"password": "secure-parent-pass-123"})
    assert response.status_code == 200, response.text
    ledger = settings.data_dir / "erasure-ledger.jsonl"
    records = [verify(line, settings.master_key) for line in ledger.read_text().splitlines()]
    assert any(r["scope"] == "family" and r["target"] == user["families"][0]["id"] for r in records)
    assert all("Testkind" not in json.dumps(r) and "password" not in json.dumps(r) for r in records)
    forged = json.loads(ledger.read_text().splitlines()[-1])
    forged["record"]["target"] = "f" * 32
    with pytest.raises(ValueError, match="authentication"):
        verify(json.dumps(forged), settings.master_key)
    restored = create_engine("sqlite:///:memory:")
    with restored.connect() as connection:
        connection.exec_driver_sql("PRAGMA foreign_keys=ON")
    Base.metadata.create_all(restored)
    with restored.begin() as connection:
        for table, rows in backup.items():
            if rows:
                connection.execute(table.insert(), [dict(row) for row in rows])
    with Session(restored) as db:
        restored_material = db.get(Material, material["id"])
        assert restored_material is not None
        expected_path = restored_material.path
        paths = reconcile(db, list(reversed(records)))
        db.commit()
        assert expected_path in paths and db.scalar(select(func.count()).select_from(Family)) == 0
        assert db.scalar(select(func.count()).select_from(Child)) == 0
        assert db.scalar(select(func.count()).select_from(Material)) == 0
    restored.dispose()


def test_deletion_ledger_retention_exceeds_backup_retention_but_is_bounded(api):
    record = {"id": "a" * 32, "scope": "material", "target": "b" * 32, "created": int(now()) - 36 * 86400}
    with (settings.data_dir / "erasure-ledger.jsonl").open("a") as output:
        output.write(signed(record, settings.master_key) + "\n")
    with DB.begin() as db:
        db.add(ErasureRequest(**record, published=True))
    prune_journal()
    assert all(
        verify(line, settings.master_key)["id"] != record["id"]
        for line in (settings.data_dir / "erasure-ledger.jsonl").read_text().splitlines()
    )
    with DB() as db:
        assert db.get(ErasureRequest, record["id"]) is None


def test_operational_metrics_are_private_and_contain_no_child_content(api, household):
    assert api.get("/api/admin/operations").status_code == 403
    with DB.begin() as db:
        db.add(ServiceState(name="worker", updated=int(now()) - 12))
    with DB() as db:
        data = snapshot(db)
    assert 12 <= data["worker_age_seconds"] < 15
    assert "Testkind" not in json.dumps(data) and "subject" not in json.dumps(data)


def test_operator_approval_is_distinct_from_an_unavailable_private_route(api):
    object.__setattr__(settings, "real_data_approved", True)
    object.__setattr__(settings, "privacy_evidence", "Operator approval; synthetic test")
    with DB.begin() as db:
        config = db.get(ProviderConfig, 1)
        config.privacy_approved = True
        config.provider = "openrouter"
        config.emergency_stop = False
        config.production_block_reason = "Synthetic technical routing failure"
    result = api.get("/api/status").json()
    assert result["real_data_enabled"] is True and result["ai_available"] is False
    assert result["ai_block_reason"] and "liegt vor" in result["notice"]
    assert api.get("/api/legal").json()["operator_data_approval"] is True


def test_operational_metadata_retention_preserves_recent_records(api, household):
    from datetime import datetime, timezone

    from schulpilot.db import UsageBucket
    from schulpilot.worker import maintenance

    user, child = household
    with DB.begin() as db:
        current = datetime.now(timezone.utc).strftime("%Y-%m")
        db.add(UsageBucket(id="global:2000-01", calls=2, encumbered_micros=1000))
        db.add(UsageBucket(id="global:" + current, calls=3, encumbered_micros=2000))
        db.add(Audit(actor="synthetic", action="retention.test", target="expired", created=int(now()) - 181 * 86400))
        db.add(Audit(actor="synthetic", action="retention.test", target="recent", created=int(now())))
        for age in (0, 91):
            db.add(
                Usage(
                    family_id=user["families"][0]["id"],
                    child_id=child["id"],
                    job_id="synthetic-no-job",
                    provider="synthetic",
                    model="fixed",
                    config_revision=1,
                    function="unit",
                    status="completed",
                    reserved_micros=0,
                    bucket_ids=[],
                    created=int(now()) - age * 86400,
                )
            )
    maintenance()
    with DB() as db:
        assert db.get(UsageBucket, "global:2000-01") is None
        assert db.get(UsageBucket, "global:" + current).encumbered_micros == 2000
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
        assert list(db.scalars(select(Audit.target).where(Audit.action == "retention.test"))) == ["recent"]
