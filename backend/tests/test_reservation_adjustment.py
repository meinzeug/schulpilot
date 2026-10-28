"""Explicit operator action changes holds, not prices, models or old usage."""
import pytest
from sqlalchemy import select

from schulpilot.db import Audit, DB, OperatorJob, ProviderConfig
from schulpilot.reservation_adjustment import raise_reservations
from test_model_routing import policy


def seed():
    with DB.begin() as db:
        base = db.get(ProviderConfig, 1)
        base.provider, base.model, base.routing_policy = "openrouter", "openai/gpt-6.1-sol", policy()
        base.reserve_micros = 1_500_000
        base.routing_policy = {**base.routing_policy, "budget": {**base.routing_policy["budget"], "eur_per_usd": "0.890869"}}
        db.add(ProviderConfig(id=2, provider="codex", model="gpt-6-luna", reserve_micros=150_000))
        return base.revision


def test_increase_is_idempotent_and_preserves_bindings():
    revision = seed()
    with DB.begin() as db:
        result = raise_reservations(db, revision, "test-3eur")
        assert result["increase_usd_micros"] == 3_367_499
        assert result["after"]["buddy"] == 3_517_499
        assert result["after"]["base"] == 4_867_499
        assert db.get(ProviderConfig, 2).model == "gpt-6-luna"
        assert db.get(ProviderConfig, 1).routing_policy["routes"]["sol"]["evaluated"]
        assert raise_reservations(db, revision, "test-3eur")["already_applied"]
    with DB() as db:
        assert db.get(ProviderConfig, 1).revision == revision + 1
        assert len(list(db.scalars(select(Audit).where(Audit.action == "provider.reservation_increase")))) == 1


def test_old_revision_and_active_job_refuse_change():
    revision = seed()
    with DB.begin() as db:
        with pytest.raises(ValueError):
            raise_reservations(db, revision + 1, "wrong-revision")
        db.add(OperatorJob(id="fixture-job", actor="test", config_revision=revision, status="queued"))
        db.flush()
        with pytest.raises(ValueError):
            raise_reservations(db, revision, "active-job")
        assert db.get(ProviderConfig, 1).reserve_micros == 1_500_000
