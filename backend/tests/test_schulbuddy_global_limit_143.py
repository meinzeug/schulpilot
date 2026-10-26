"""Artificial budgets only; never contacts Codex or changes real limits."""

from datetime import datetime, timezone

import pytest
from schulpilot.child_cost_models import ChildCostControl
from schulpilot.db import DB, Family, ProviderConfig, Usage, UsageBucket, uid
from schulpilot.providers import reserve
from schulpilot.schulbuddy_provider import configured
from sqlalchemy import func, select
from test_schulbuddy import book as book_fixture


@pytest.fixture
def book(api, household, monkeypatch):
    yield from book_fixture.__wrapped__(api, household, monkeypatch)


@pytest.mark.parametrize("current,old", [(100_000_000, 10_000_000), (5_000_000, 10_000_000)])
def test_current_operator_global_limit_is_authoritative_in_both_directions(book, current, old):
    with DB.begin() as db:
        base, binding = db.get(ProviderConfig, 1), db.get(ProviderConfig, 2)
        base.global_limit_micros, binding.global_limit_micros = current, old
        before = [{col.name: getattr(row, col.name) for col in ProviderConfig.__table__.columns}
                  for row in (base, binding)]
        result = configured(db)
        assert result.global_limit_micros == current
        assert result.reserve_micros == min(base.reserve_micros, binding.reserve_micros)
        assert result.max_output_tokens == min(base.max_output_tokens, binding.max_output_tokens)
        assert result.provider == "codex" and result.reasoning_effort == "high"
        assert [{col.name: getattr(row, col.name) for col in ProviderConfig.__table__.columns}
                for row in (base, binding)] == before


def test_unlimited_child_can_reserve_above_stale_copy_but_current_global_stop_still_applies(book):
    from fastapi import HTTPException

    child = book["child"]["id"]
    period = datetime.now(timezone.utc).strftime("%Y-%m")
    with DB.begin() as db:
        base, binding = db.get(ProviderConfig, 1), db.get(ProviderConfig, 2)
        base.global_limit_micros, binding.global_limit_micros = 100_000_000, 10_000_000
        db.add(ChildCostControl(child_id=child, revision=1, enabled=True, timezone="Europe/Berlin",
                               daily_limit_eur_micros=None, monthly_limit_eur_micros=None))
        db.add(UsageBucket(id=f"global:{period}", calls=533, encumbered_micros=10_221_446,
                           known_cost_micros=4_931_446, unknown_calls=162))
    with DB.begin() as db:
        family = db.get(Family, book["family_id"])
        usage = reserve(db, family, child, uid(), "schulbuddy")
        assert usage.cost_micros is None and usage.provider == "codex"
        assert usage.reserved_micros > 0
    with DB.begin() as db:
        db.get(ProviderConfig, 1).global_limit_micros = 10_221_446
    with DB.begin() as db, pytest.raises(HTTPException) as blocked:
        reserve(db, db.get(Family, book["family_id"]), child, uid(), "schulbuddy")
    assert blocked.value.status_code == 429
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
