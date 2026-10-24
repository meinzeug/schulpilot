"""Operator-owned daily/monthly EUR policy, independent of learning minutes.

An explicit enabled policy is authoritative. Legacy limits remain active until
the operator saves it. Global service/financial emergency stops remain separate.
"""

import hashlib
import json
import re
from datetime import datetime
from decimal import ROUND_CEILING, Decimal
from typing import Annotated
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from pydantic import Field, StrictBool, StrictInt, model_validator
from sqlalchemy import delete, or_, select, update

from .child_cost_models import ChildCostControl, ChildCostControlChange, UsageCostBalance
from .db import Child, ChildCostBucket, Family, ProviderConfig, Session, Usage, UsageBucket, User, get_db, now
from .schemas import Preferences, Strict
from .security import admin, audit, rate_limit

router = APIRouter(tags=["Kostenkontrolle je Kinderzugang"])
Money = Annotated[StrictInt, Field(ge=0, le=1_000_000_000_000)]
BASIS = "provider_usd_converted_plus_actual_or_reserved_fee"


class PolicyUpdate(Strict):
    revision: StrictInt = Field(ge=0)
    enabled: StrictBool
    timezone: str = Field(min_length=1, max_length=64)
    daily_limit_eur_micros: Money | None
    monthly_limit_eur_micros: Money | None

    @model_validator(mode="after")
    def valid_zone(self):
        try:
            ZoneInfo(self.timezone)
        except (ZoneInfoNotFoundError, ValueError):
            raise ValueError("Bitte eine gültige Zeitzone wählen.") from None
        return self


def policy_value(row):
    return {key: getattr(row, key) for key in ("revision", "enabled", "timezone",
        "daily_limit_eur_micros", "monthly_limit_eur_micros")}


def quote_for(config):
    from .model_routing import BudgetPolicy

    try:
        budget = BudgetPolicy.model_validate((config.routing_policy or {}).get("budget", {})).model_dump()
    except (ValueError, TypeError, AttributeError):
        raise HTTPException(503, "Für die EUR-Kostenkontrolle fehlt ein gültiger belegter Wechselkurs.") from None
    return {key: budget[key] for key in ("eur_per_usd", "fx_evidence", "fx_checked_at", "fee_reserve_bps")}


def convert(amount, quote):
    return int((Decimal(amount) * Decimal(quote["eur_per_usd"])).to_integral_value(rounding=ROUND_CEILING))


def fee_reserve(amount, quote):
    return int((Decimal(amount) * Decimal(quote["eur_per_usd"]) * Decimal(quote["fee_reserve_bps"]) / 10000
        ).to_integral_value(rounding=ROUND_CEILING))


def balance_value(usage, quote, balance=None):
    known = usage.cost_micros is not None
    provider = convert(usage.cost_micros, quote) if known else None
    fee = convert(usage.allocated_fee_micros, quote) if known and usage.allocated_fee_micros is not None else None
    reserve = fee_reserve(usage.cost_micros if known else usage.reserved_micros, quote) if fee is None else 0
    state = "actual" if fee is not None else "estimated"
    if (balance and balance.fee_basis_usd_micros is not None and known
            and balance.fee_basis_usd_micros != usage.cost_micros):
        # Generation receipts may correct a previously reported provider cost.
        # Historical credit allocations remain auditable until reconciled.
        reserve = max(fee or 0, fee_reserve(usage.cost_micros, quote))
        fee, state = None, "adjustment_pending"
    held = 0 if known else convert(usage.reserved_micros, quote)
    return {"provider_eur_micros": provider, "fee_known_eur_micros": fee,
        "fee_reserved_eur_micros": reserve, "held_eur_micros": held,
        "accounted_eur_micros": (provider or 0) + (fee or 0) + reserve + held,
        "fee_state": state}


def usage_quote(usage, fallback=None, balance=None):
    if balance:
        return balance.fx_snapshot
    value = (usage.route_snapshot or {}).get("budget") or (usage.route_snapshot or {}).get("child_cost_control", {}).get("quote")
    if isinstance(value, dict) and all(key in value for key in ("eur_per_usd", "fee_reserve_bps", "fx_checked_at", "fx_evidence")):
        return {key: value[key] for key in ("eur_per_usd", "fee_reserve_bps", "fx_checked_at", "fx_evidence")}
    if fallback:
        return fallback
    return None


def sync_balance(db, usage, fallback=None):
    """One balance per original Usage; recomputation cannot double-book money."""
    row = db.get(UsageCostBalance, usage.id)
    quote = usage_quote(usage, fallback, row)
    if not quote:
        return None
    values = balance_value(usage, quote, row)
    if not row:
        row = UsageCostBalance(usage_id=usage.id, child_id=usage.child_id, created=usage.created,
            fx_snapshot=quote, fee_basis_usd_micros=usage.cost_micros if usage.allocated_fee_micros is not None else None,
            **values)
        db.add(row)
    else:
        for key, value in values.items():
            setattr(row, key, value)
    return row


def reservation_policy(db, child_id, *, family_id=None):
    # The same Child lock protects create/update and reservation, including the
    # first configuration. No regime switch can occur halfway through a claim.
    if not db.execute(update(Child).where(Child.id == child_id).values(grade=Child.grade)).rowcount:
        raise HTTPException(404, "Kinderzugang nicht gefunden.")
    child = db.get(Child, child_id, populate_existing=True)
    if family_id is not None and child.family_id != family_id:
        raise HTTPException(403, "Kinderzugang und Kostenstelle stimmen nicht überein.")
    row = db.get(ChildCostControl, child_id, populate_existing=True)
    if not row or not row.enabled:
        return None
    return {**policy_value(row), "cost_basis": BASIS, "currency": "EUR",
        "quote": quote_for(db.get(ProviderConfig, 1))}


def windows(zone, current):
    local = datetime.fromtimestamp(current, ZoneInfo(zone))
    day = local.replace(hour=0, minute=0, second=0, microsecond=0)
    from datetime import timedelta

    next_day = day + timedelta(days=1)
    month = day.replace(day=1)
    next_month = month.replace(year=month.year + 1, month=1) if month.month == 12 else month.replace(month=month.month + 1)
    return {"day": (day.date().isoformat(), int(day.timestamp()), int(next_day.timestamp())),
        "month": (month.strftime("%Y-%m"), int(month.timestamp()), int(next_month.timestamp()))}


def rollups(db, child_id, policy, *, current=None, fallback=None):
    current = now() if current is None else current
    ranges = windows(policy["timezone"], current)
    start = min(value[1] for value in ranges.values())
    end = max(value[2] for value in ranges.values())
    usages = list(db.scalars(select(Usage).where(Usage.child_id == child_id, Usage.created >= start, Usage.created < end)))
    balances = {row.usage_id: row for row in db.scalars(select(UsageCostBalance).where(
        UsageCostBalance.usage_id.in_([usage.id for usage in usages])))} if usages else {}
    result = {}
    for kind, (label, begin, finish) in ranges.items():
        limit = policy.get(("daily" if kind == "day" else "monthly") + "_limit_eur_micros")
        value = {"period": label, "starts_at": begin, "ends_at": finish, "limit_eur_micros": limit,
            "calls": 0, "unknown_calls": 0, "provider_usd_micros": 0, "known_provider_eur_micros": 0,
            "fee_known_eur_micros": 0, "fee_reserved_eur_micros": 0, "held_eur_micros": 0,
            "accounted_eur_micros": 0, "cost_basis": BASIS, "unconverted_calls": 0,
            "fee_unsettled_calls": 0, "fee_adjustment_calls": 0, "receipt_pending_calls": 0,
            "receipt_unavailable_calls": 0}
        for usage in usages:
            if not begin <= usage.created < finish:
                continue
            value["calls"] += 1
            value["unknown_calls"] += usage.cost_micros is None
            value["provider_usd_micros"] += usage.cost_micros or 0
            if usage.provider == "openrouter" and usage.cost_source not in ("generation", "cancelled"):
                value["receipt_pending_calls"] += 1
                value["receipt_unavailable_calls"] += bool(not (usage.telemetry or {}).get("generation_id")
                    or (usage.telemetry or {}).get("reconcile_attempts", 0) >= 3)
            quote = usage_quote(usage, fallback, balances.get(usage.id))
            if not quote:
                value["unconverted_calls"] += 1
                continue
            amounts = balance_value(usage, quote, balances.get(usage.id))
            value["fee_unsettled_calls"] += amounts["fee_state"] != "actual"
            value["fee_adjustment_calls"] += amounts["fee_state"] == "adjustment_pending"
            value["known_provider_eur_micros"] += amounts["provider_eur_micros"] or 0
            for field in ("fee_known_eur_micros", "fee_reserved_eur_micros", "held_eur_micros", "accounted_eur_micros"):
                value[field] += amounts[field] or 0
        value["remaining_eur_micros"] = None if limit is None else max(0, limit - value["accounted_eur_micros"])
        value["state"] = "unavailable" if value["unconverted_calls"] else "unlimited" if limit is None else "limit_reached" if not value["remaining_eur_micros"] else "available"
        result[kind] = value
    return result


def reserve_controlled(db, usage, policy):
    quote = policy["quote"]
    amount = convert(usage.reserved_micros, quote) + fee_reserve(usage.reserved_micros, quote)
    current = now()
    values = rollups(db, usage.child_id, policy, current=current, fallback=quote)
    for kind, value in values.items():
        if value["unconverted_calls"]:
            raise HTTPException(503, "Vor neuen KI-Aufträgen müssen bisherige Kosten in EUR geprüft werden.")
        limit = policy[("daily" if kind == "day" else "monthly") + "_limit_eur_micros"]
        if limit is not None and value["accounted_eur_micros"] + amount > limit:
            db.rollback()
            label = "Tageskostenlimit" if kind == "day" else "Monatskostenlimit"
            raise HTTPException(429, label + " für neue KI-Verarbeitung erreicht. Gespeicherte Inhalte bleiben nutzbar.")
    db.add(usage)
    db.flush()
    sync_balance(db, usage, quote)


def projection(db, child, row=None):
    row = db.get(ChildCostControl, child.id) if row is None else row
    policy = policy_value(row) if row else {"revision": 0, "enabled": False,
        "timezone": Preferences(**child.preferences).timezone,
        "daily_limit_eur_micros": None, "monthly_limit_eur_micros": None}
    config = db.get(ProviderConfig, 1)
    try:
        quote = quote_for(config)
    except HTTPException:
        quote = None
    user = db.get(User, child.user_id)
    return {"child_id": child.id, "family_id": child.family_id, "username": user.username,
        "account_label": user.username, "mode": "configured" if policy["enabled"] else "legacy",
        **policy, "currency": "EUR", "cost_basis": BASIS, "conversion": quote,
        **rollups(db, child.id, policy, fallback=quote),
        "system_stop": {"emergency_stop": bool(config.emergency_stop),
            "global_limit_micros_usd": config.global_limit_micros,
            "global_call_limit": 1_000_000,
            "notice": "Notfallstopp, Anbieterfreigabe und globales Betriebskostenlimit gelten getrennt weiter."},
        "effective_limits": {"child_policy_authoritative": policy["enabled"],
            "legacy_family_and_routing_caps_apply": not policy["enabled"]},
        "legacy_effective": legacy_effective(db, child, config) if not policy["enabled"] else None,
        "notice": "Unbekannte Anbieterpreise bleiben reserviert. Gebühren ohne Beleg sind ausdrücklich geschätzt. Keine Lernzeitbegrenzung."}


def legacy_effective(db, child, config):
    from datetime import timezone

    from .commerce import usage_terms
    from .model_routing import enabled

    family = db.get(Family, child.family_id)
    key, calls, budget = usage_terms(db, family)
    bucket = db.get(UsageBucket, key)
    value = config.routing_policy or {}
    period = datetime.fromtimestamp(now(), timezone.utc).strftime("%Y-%m")
    child_bucket = db.get(ChildCostBucket, child.id + ":" + period)
    routed = enabled(config)
    return {"family": {"calls_limit": calls, "calls_used": bucket.calls if bucket else 0,
        "calls_remaining": max(0, calls - (bucket.calls if bucket else 0)),
        "limit_usd_micros": budget, "encumbered_usd_micros": bucket.encumbered_micros if bucket else 0,
        "remaining_usd_micros": max(0, budget - (bucket.encumbered_micros if bucket else 0))},
        "route_child": {"applies": routed, "period": period,
            "limit_eur_micros": value.get("budget", {}).get("hard_eur_micros", 12_000_000) if routed else None,
            "encumbered_eur_micros": child_bucket.encumbered_eur_micros if child_bucket else 0,
            "known_eur_micros": child_bucket.known_eur_micros if child_bucket else 0,
            "unknown_calls": child_bucket.unknown_calls if child_bucket else 0,
            "reserve_usd_micros": {tier: min(config.reserve_micros, route["reserve_micros"])
                for tier, route in value.get("routes", {}).items()} if routed else {"base": config.reserve_micros}}}


def preflight(db, child_id, reserved_micros):
    """Read-only, same amount/basis as reserve_controlled; not a claim."""
    row = db.get(ChildCostControl, child_id) if child_id else None
    if not row or not row.enabled:
        return False, None
    try:
        quote = quote_for(db.get(ProviderConfig, 1))
        amount = convert(reserved_micros, quote) + fee_reserve(reserved_micros, quote)
        for kind, value in rollups(db, child_id, policy_value(row), fallback=quote).items():
            if value["unconverted_calls"]:
                return True, {"code": "not_configured", "message": "Bisherige KI-Kosten müssen zuerst geprüft werden. Gespeicherte Inhalte bleiben nutzbar."}
            if value["limit_eur_micros"] is not None and value["accounted_eur_micros"] + amount > value["limit_eur_micros"]:
                label = "Tageskostenlimit" if kind == "day" else "Monatskostenlimit"
                return True, {"code": "quota_exhausted", "message": label + " für neue KI-Verarbeitung erreicht. Gespeicherte Inhalte bleiben nutzbar."}
    except HTTPException as error:
        return True, {"code": "not_configured", "message": str(error.detail)}
    return True, None


def fresh_admin(db, principal):
    user = db.get(User, principal.user.id, populate_existing=True)
    session = db.get(Session, principal.session.id, populate_existing=True)
    if (not user or user.role != "admin" or user.disabled or not user.verified or not session
            or session.user_id != user.id or session.revoked or session.expires <= now()
            or now() - session.seen > 7 * 86400):
        raise HTTPException(403, "Die Betriebsberechtigung oder Sitzung hat sich geändert.")


def export_child(db, child_id):
    row = db.get(ChildCostControl, child_id)
    return {"policy": policy_value(row) if row else None,
        "changes": [{"revision": item.revision, "policy": item.policy, "created": item.created}
            for item in db.scalars(select(ChildCostControlChange).where(ChildCostControlChange.child_id == child_id)
                .order_by(ChildCostControlChange.created, ChildCostControlChange.id))],
        "balances": [{column.name: getattr(item, column.name) for column in UsageCostBalance.__table__.columns}
            for item in db.scalars(select(UsageCostBalance).where(UsageCostBalance.child_id == child_id))]}


def purge_expired(db):
    """Keep the live policy; private historical changes expire after 365 days."""
    return db.execute(delete(ChildCostControlChange).where(
        ChildCostControlChange.created < int(now()) - 365 * 86400)).rowcount


@router.get("/admin/child-cost-controls")
def list_controls(limit: int = Query(30, ge=1, le=50), cursor: str | None = Query(None, max_length=32),
                  query: str = Query("", max_length=100), p=Depends(admin), db=Depends(get_db)):
    statement = select(Child).join(User, User.id == Child.user_id)
    if cursor:
        statement = statement.where(Child.id > cursor)
    if query.strip():
        escaped = query.strip().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        statement = statement.where(or_(User.username.ilike("%" + escaped + "%", escape="\\"), Child.id == query.strip()))
    rows = list(db.scalars(statement.order_by(Child.id).limit(limit + 1)))
    return {"items": [projection(db, child) for child in rows[:limit]],
        "next_cursor": rows[limit - 1].id if len(rows) > limit else None}


@router.get("/admin/children/{child_id}/cost-controls")
def read_control(child_id: str, p=Depends(admin), db=Depends(get_db)):
    child = db.get(Child, child_id)
    if not child:
        raise HTTPException(404, "Kinderzugang nicht gefunden.")
    return projection(db, child)


@router.put("/admin/children/{child_id}/cost-controls")
def save_control(child_id: str, data: PolicyUpdate, idempotency_key: str = Header("", alias="Idempotency-Key"),
                 p=Depends(admin), db=Depends(get_db)):
    if not re.fullmatch(r"[A-Za-z0-9_-]{16,80}", idempotency_key, re.ASCII):
        raise HTTPException(422, "Bitte einen eindeutigen Speicherschlüssel verwenden.")
    if not db.execute(update(Child).where(Child.id == child_id).values(grade=Child.grade)).rowcount:
        raise HTTPException(404, "Kinderzugang nicht gefunden.")
    child = db.get(Child, child_id, populate_existing=True)
    fresh_admin(db, p)
    digest = hashlib.sha256(json.dumps(data.model_dump(), sort_keys=True).encode()).hexdigest()
    previous = db.scalar(select(ChildCostControlChange).where(
        ChildCostControlChange.child_id == child_id, ChildCostControlChange.request_key == idempotency_key))
    row = db.get(ChildCostControl, child_id, populate_existing=True)
    if previous:
        if previous.digest != digest or previous.actor_id != p.user.id or not row or row.revision != previous.revision:
            raise HTTPException(409, "Dieser Speichervorgang gehört zu einem anderen Kostenstand.")
        return projection(db, child, row)
    if data.revision != (row.revision if row else 0):
        raise HTTPException(409, "Die Kostenkontrolle wurde geändert. Bitte neu laden.")
    rate_limit(db, "cost-control:" + p.user.id, 30, 3600, commit=False)
    quote = quote_for(db.get(ProviderConfig, 1)) if data.enabled else None
    values = data.model_dump(exclude={"revision"})
    if row:
        for key, value in values.items():
            setattr(row, key, value)
        row.revision += 1
        row.updated = int(now())
    else:
        row = ChildCostControl(child_id=child_id, revision=1, **values)
        db.add(row)
    if quote:
        # Freeze a known conversion for older calls too; a timezone or FX edit
        # can never reset already incurred daily/monthly spending.
        for usage in db.scalars(select(Usage).where(Usage.child_id == child_id).order_by(Usage.id).with_for_update()):
            sync_balance(db, usage, quote)
    db.add(ChildCostControlChange(child_id=child_id, actor_id=p.user.id, request_key=idempotency_key,
        digest=digest, revision=row.revision, policy={**values, "revision": row.revision}))
    audit(db, p.user.id, "child_cost_control_changed", child_id)
    db.commit()
    return projection(db, child, row)


@router.get("/admin/children/{child_id}/cost-calls")
def cost_calls(child_id: str, limit: int = Query(30, ge=1, le=50), cursor: str | None = Query(None, max_length=32),
               p=Depends(admin), db=Depends(get_db)):
    if not db.get(Child, child_id):
        raise HTTPException(404, "Kinderzugang nicht gefunden.")
    statement = select(Usage).where(Usage.child_id == child_id)
    if cursor:
        statement = statement.where(Usage.id > cursor)
    rows = list(db.scalars(statement.order_by(Usage.id).limit(limit + 1)))
    values = []
    for usage in rows[:limit]:
        balance = db.get(UsageCostBalance, usage.id)
        quote = usage_quote(usage, balance=balance)
        values.append({"id": usage.id, "created": usage.created, "provider": usage.provider, "model": usage.model,
            "status": usage.status, "provider_usd_micros": usage.cost_micros, "reserved_usd_micros": usage.reserved_micros,
            "cost_source": usage.cost_source, "conversion": quote,
            "receipt_state": "verified_generation" if usage.cost_source == "generation" else
                "reported" if usage.cost_micros is not None else "unknown",
            "metadata_attempts": (usage.telemetry or {}).get("reconcile_attempts", 0),
            **(balance_value(usage, quote, balance) if quote else {"accounted_eur_micros": None})})
    return {"items": values, "next_cursor": rows[limit - 1].id if len(rows) > limit else None}


@router.post("/admin/usage/{usage_id}/refresh-cost")
def refresh_cost(usage_id: str, idempotency_key: str = Header("", alias="Idempotency-Key"),
                 p=Depends(admin), db=Depends(get_db)):
    from .ai_accounting import identifier

    if not re.fullmatch(r"[A-Za-z0-9_-]{16,80}", idempotency_key, re.ASCII):
        raise HTTPException(422, "Bitte einen eindeutigen Speicherschlüssel verwenden.")
    # The row is only a metadata refresh queue; inference is never retried.
    db.execute(update(Usage).where(Usage.id == usage_id).values(created=Usage.created))
    usage = db.get(Usage, usage_id, populate_existing=True)
    fresh_admin(db, p)
    if not usage:
        raise HTTPException(404, "Kostenbeleg nicht gefunden.")
    if usage.cost_source == "generation":
        return {"status": "verified", "usage_id": usage.id}
    if usage.provider != "openrouter" or usage.status == "reserved" or not identifier((usage.telemetry or {}).get("generation_id")):
        raise HTTPException(422, "Für diesen Aufruf liegt keine abgleichbare Generierungskennung vor.")
    history = (usage.telemetry or {}).get("cost_refresh_requests", [])
    key = hashlib.sha256((p.user.id + ":" + idempotency_key).encode()).hexdigest()
    if any(item["key"] == key for item in history):
        return {"status": "queued", "usage_id": usage.id}
    if len(history) >= 3:
        raise HTTPException(429, "Die begrenzten manuellen Belegabgleiche sind ausgeschöpft.")
    rate_limit(db, "cost-refresh:" + p.user.id, 30, 3600, commit=False)
    usage.telemetry = {**usage.telemetry, "reconcile_attempts": 0, "reconcile_after": 0,
        "cost_refresh_requests": [*history, {"key": key, "created": int(now())}]}
    audit(db, p.user.id, "admin.cost_receipt_refresh", usage.id)
    db.commit()
    return {"status": "queued", "usage_id": usage.id}
