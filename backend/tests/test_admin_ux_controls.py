"""Metadata-only operational UX; artificial profiles, no provider transport."""

from concurrent.futures import ThreadPoolExecutor

import pytest
from conftest import HEADERS
from fastapi.testclient import TestClient
from schulpilot import admin as admin_routes
from schulpilot.db import DB, Audit, Family, ProviderConfig, Usage, engine
from schulpilot.main import app
from schulpilot.security import decrypt
from sqlalchemy import func, select
from sqlalchemy.orm import Session as OrmSession
from sqlalchemy.sql.dml import Update
from test_codex_models import operator as synthetic_operator_fixture


@pytest.fixture
def operator():
    yield from synthetic_operator_fixture.__wrapped__()


def provider_payload():
    with DB() as db:
        config = db.get(ProviderConfig, 1)
        return {
            "provider": "disabled",
            "model": "",
            "emergency_stop": config.emergency_stop,
            "image_capable": False,
            "structured_capable": False,
            "reserve_micros": config.reserve_micros,
            "expected_revision": config.revision,
        }


def test_revision_conflict_keeps_newer_provider_config_and_never_exposes_keys(operator):
    original = provider_payload()
    first = operator.put("/api/admin/provider", json={**original, "reserve_micros": 1234})
    assert first.status_code == 200
    revision = first.json()["revision"]
    rejected = operator.put(
        "/api/admin/provider", json={**original, "reserve_micros": 2345, "api_key": "SYNTHETIC-NEVER-STORE-ON-CONFLICT"}
    )
    assert rejected.status_code == 409 and "Entwurf" in rejected.json()["detail"]
    assert "SYNTHETIC-NEVER-STORE-ON-CONFLICT" not in rejected.text
    with DB() as db:
        config = db.get(ProviderConfig, 1)
        assert config.revision == revision and config.reserve_micros == 1234
        assert config.encrypted_key is None
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_emergency_stop_invalidates_open_draft_and_repeated_stop_is_idempotent(operator):
    with DB.begin() as db:
        db.get(ProviderConfig, 1).emergency_stop = False
    original = provider_payload()
    stopped = operator.post("/api/admin/emergency-stop")
    assert stopped.status_code == 200 and stopped.json()["revision"] == original["expected_revision"] + 1
    assert operator.post("/api/admin/emergency-stop").json()["revision"] == stopped.json()["revision"]
    assert operator.put("/api/admin/provider", json=original).status_code == 409
    with DB() as db:
        assert db.get(ProviderConfig, 1).emergency_stop is True


def test_two_operator_drafts_can_commit_the_same_revision_only_once(operator):
    original = provider_payload()
    headers = {**HEADERS, "Authorization": operator.headers["Authorization"]}

    def save(value):
        with TestClient(app, headers=headers) as client:
            return client.put("/api/admin/provider", json={**original, "reserve_micros": value}).status_code

    with ThreadPoolExecutor(max_workers=2) as pool:
        outcomes = list(pool.map(save, [1234, 2345]))
    assert sorted(outcomes) == [200, 409]
    with DB() as db:
        assert db.get(ProviderConfig, 1).revision == original["expected_revision"] + 1


def test_late_sqlite_revision_conflict_preserves_the_winner_and_has_no_loser_writes(operator, monkeypatch):
    if engine.dialect.name != "sqlite":
        pytest.skip("SQLite omits FOR UPDATE; PostgreSQL serializes before this boundary")
    original = provider_payload()
    winner_key = "SYNTHETIC-CAS-WINNER-KEY"
    loser_key = "SYNTHETIC-CAS-LOSER-KEY"
    winner_responses, rollbacks, encrypted_values = [], [], []
    execute = OrmSession.execute
    rollback = OrmSession.rollback
    encrypt = admin_routes.encrypt
    dispatched = False

    def record_encrypt(value):
        encrypted_values.append(value)
        assert value != loser_key, "The rejected draft must not reach key encryption"
        return encrypt(value)

    def record_rollback(db):
        rollbacks.append(db)
        return rollback(db)

    def competing_save_before_claim(db, statement, *args, **kwargs):
        nonlocal dispatched
        if not dispatched and isinstance(statement, Update) and statement.table.name == "provider_config":
            dispatched = True
            # The losing request has read revision N but has not executed its
            # claim. A separate real API transaction now wins that revision.
            winner = operator.put(
                "/api/admin/provider",
                json={**original, "reserve_micros": 2345, "api_key": winner_key},
            )
            assert winner.status_code == 200
            winner_responses.append(winner.json())
            assert not any(isinstance(value, ProviderConfig) for value in db.dirty)
        return execute(db, statement, *args, **kwargs)

    monkeypatch.setattr(OrmSession, "execute", competing_save_before_claim)
    monkeypatch.setattr(OrmSession, "rollback", record_rollback)
    monkeypatch.setattr(admin_routes, "encrypt", record_encrypt)
    rejected = operator.put(
        "/api/admin/provider",
        json={**original, "reserve_micros": 1234, "api_key": loser_key, "image_capable": True},
    )
    assert dispatched and len(winner_responses) == 1
    assert rejected.status_code == 409 and "Entwurf" in rejected.json()["detail"]
    assert loser_key not in rejected.text and winner_key not in rejected.text
    assert encrypted_values == [winner_key]
    assert len(rollbacks) == 1
    assert winner_responses[0]["revision"] == original["expected_revision"] + 1
    with DB() as db:
        config = db.get(ProviderConfig, 1)
        assert config.revision == original["expected_revision"] + 1
        assert config.reserve_micros == 2345 and config.image_capable is False
        assert decrypt(config.encrypted_key) == winner_key
        assert db.scalar(select(func.count()).select_from(Audit).where(Audit.action == "admin.provider_update")) == 1
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_provider_validation_failure_rolls_back_the_revision_claim(operator):
    original = provider_payload()
    with DB() as db:
        config = db.get(ProviderConfig, 1)
        before = {column.name: getattr(config, column.name) for column in ProviderConfig.__table__.columns}
    rejected = operator.put(
        "/api/admin/provider",
        json={
            **original,
            "provider": "openrouter",
            "model": "synthetic-model-without-free-suffix",
            "openrouter_free_only": True,
            "api_key": "SYNTHETIC-REJECTED-CONFIG-KEY",
        },
    )
    assert rejected.status_code == 422 and ":free" in rejected.json()["detail"]
    with DB() as db:
        config = db.get(ProviderConfig, 1)
        assert config.revision == original["expected_revision"]
        assert {column.name: getattr(config, column.name) for column in ProviderConfig.__table__.columns} == before
        assert db.scalar(select(func.count()).select_from(Audit).where(Audit.action == "admin.provider_update")) == 0
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_legacy_provider_saves_return_the_actual_single_increment(operator):
    payload = provider_payload()
    original_revision = payload.pop("expected_revision")
    for offset, value in enumerate((1234, 2345), start=1):
        response = operator.put("/api/admin/provider", json={**payload, "reserve_micros": value})
        assert response.status_code == 200
        assert response.json()["revision"] == original_revision + offset
        assert response.json()["reserve_micros"] == value
    with DB() as db:
        config = db.get(ProviderConfig, 1)
        assert config.revision == original_revision + 2 and config.reserve_micros == 2345
        assert db.scalar(select(func.count()).select_from(Audit).where(Audit.action == "admin.provider_update")) == 2
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_legacy_provider_payload_stays_compatible(operator):
    payload = provider_payload()
    payload.pop("expected_revision")
    assert operator.put("/api/admin/provider", json=payload).status_code == 200
    assert operator.put("/api/admin/provider", json={**payload, "expected_revision": 0}).status_code == 422


def seed_families():
    with DB.begin() as db:
        for index in reversed(range(201)):
            db.add(
                Family(
                    id=f"{index:032x}",
                    name="PRIVATE-SYNTHETIC-FAMILY-TITLE",
                    plan="trial" if index % 2 == 0 else "paid",
                    synthetic=index % 3 == 0,
                )
            )


def test_family_pages_have_stable_boundaries_and_only_operational_metadata(operator):
    seed_families()
    legacy = operator.get("/api/admin/families").json()
    assert isinstance(legacy, list) and len(legacy) == 200
    assert [row["id"] for row in legacy] == sorted(row["id"] for row in legacy)
    response = operator.get("/api/admin/families", params={"paginated": "true", "page_size": 50})
    first = response.json()
    assert first["pagination"] == {"page": 1, "pages": 5, "page_size": 50, "total": 201}
    second = operator.get("/api/admin/families", params={"paginated": "true", "page_size": 50, "page": 2}).json()
    assert first["items"] == legacy[:50] and second["items"] == legacy[50:100]
    assert not ({row["id"] for row in first["items"]} & {row["id"] for row in second["items"]})
    assert "PRIVATE-SYNTHETIC" not in response.text
    assert all(
        set(row) == {"id", "plan", "child_limit", "call_limit", "budget_micros", "synthetic", "entitlement_revision"} for row in first["items"]
    )
    assert all(len(row["entitlement_revision"]) == 64 and set(row["entitlement_revision"]) <= set("0123456789abcdef") for row in first["items"])
    last = operator.get("/api/admin/families", params={"paginated": "true", "page_size": 50, "page": 999}).json()
    assert last["pagination"]["page"] == 5 and len(last["items"]) == 1
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_family_search_and_filters_are_literal_and_apply_before_pagination(operator):
    seed_families()
    result = operator.get(
        "/api/admin/families", params={"paginated": "true", "search": "PAID", "synthetic": "true", "page_size": 2}
    ).json()
    expected = [f"{index:032x}" for index in range(201) if index % 2 and index % 3 == 0]
    assert [row["id"] for row in result["items"]] == expected[:2]
    assert result["pagination"]["total"] == len(expected)
    assert operator.get("/api/admin/families", params={"paginated": "true", "search": "%"}).json()["items"] == []
    assert operator.get("/api/admin/families", params={"paginated": "true", "search": "_"}).json()["items"] == []
    one = operator.get("/api/admin/families", params={"paginated": "true", "search": f"{170:032x}".upper()}).json()
    assert [row["id"] for row in one["items"]] == [f"{170:032x}"]
    empty = operator.get("/api/admin/families", params={"paginated": "true", "plan": "unlisted-plan"}).json()
    assert empty["items"] == [] and empty["pagination"]["page"] == empty["pagination"]["pages"] == 1


@pytest.mark.parametrize(
    "params", [{"page": 0}, {"page_size": 0}, {"page_size": 201}, {"search": "x" * 81}, {"plan": "x" * 41}]
)
def test_family_pagination_is_bounded(operator, params):
    assert operator.get("/api/admin/families", params={"paginated": "true", **params}).status_code == 422


def test_parent_child_and_anonymous_cannot_use_operational_search(api, household):
    params = {"paginated": "true", "search": household[0]["families"][0]["id"]}
    assert api.get("/api/admin/families", params=params).status_code == 403
    with TestClient(app, headers=HEADERS) as client:
        assert client.get("/api/admin/families", params=params).status_code == 401
        result = client.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"})
        client.headers["Authorization"] = "Bearer " + result.json()["token"]
        assert client.get("/api/admin/families", params=params).status_code == 403


def test_probe_recovery_only_reads_bounded_operational_metadata(operator):
    from schulpilot.db import OperatorJob, User
    with DB.begin() as db:
        actor = db.scalar(select(User).where(User.role == "admin")).id
        db.add_all([
            OperatorJob(id="a" * 32, actor=actor, config_revision=2, status="completed", created=10,
                        report=[{"SYNTHETIC-PRIVATE-REPORT": "never-in-summary"}]),
            OperatorJob(id="b" * 32, actor=actor, config_revision=3, status="failed", created=20),
            OperatorJob(id="c" * 32, actor="other-operator", config_revision=4, status="running", created=30),
        ])
    for _ in range(2):
        response = operator.get("/api/admin/provider/probes")
        assert response.status_code == 200
        data = response.json()
        assert data["latest"] == {"id": "b" * 32, "status": "failed", "config_revision": 3, "created": 20}
        assert data["active"] == {"id": "c" * 32, "status": "running", "config_revision": 4, "created": 30}
        assert "SYNTHETIC-PRIVATE-REPORT" not in response.text
    detail = operator.get("/api/admin/provider/probes/" + "a" * 32).json()
    assert detail["config_revision"] == 2 and detail["created"] == 10
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(OperatorJob)) == 3
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_probe_recovery_empty_and_routing_effort_are_truthful(operator):
    from schulpilot.model_routing import ROUTING_REASONING_EFFORT
    assert operator.get("/api/admin/provider/probes").json() == {"latest": None, "active": None}
    data = operator.get("/api/admin/ai-routing").json()
    assert data["effective_reasoning_effort"] == ROUTING_REASONING_EFFORT


def test_parents_children_and_anonymous_cannot_read_probe_recovery(api, household):
    assert api.get("/api/admin/provider/probes").status_code == 403
    with TestClient(app, headers=HEADERS) as client:
        assert client.get("/api/admin/provider/probes").status_code == 401
        result = client.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"})
        client.headers["Authorization"] = "Bearer " + result.json()["token"]
        assert client.get("/api/admin/provider/probes").status_code == 403
