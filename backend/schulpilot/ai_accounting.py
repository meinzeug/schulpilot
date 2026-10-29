"""Integer money, conservative holds and auditable cost reconciliation."""

import math
import re
from datetime import datetime, timezone
from decimal import ROUND_CEILING, Decimal, InvalidOperation

from fastapi import HTTPException
from sqlalchemy import func, select, update

from .db import ChildCostBucket, CreditPurchase, Usage, now
from .security import insert_ignore


def micros(value):
    try:
        number = Decimal(str(value))
        if not number.is_finite() or number < 0 or number > 1000:
            return None
        return int((number * 1_000_000).to_integral_value(rounding=ROUND_CEILING))
    except (InvalidOperation, ValueError, TypeError):
        return None


def integer(value):
    return value if type(value) is int and 0 <= value < 2**40 else None


def identifier(value):
    return value if isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9_.:/ -]{1,180}", value) else None


def response_metrics(raw, elapsed_ms, request_id=None):
    """No content, reasoning traces, arbitrary metadata or error bodies."""
    usage = raw.get("usage") or {}
    usage = usage if isinstance(usage, dict) else {}
    prompt = usage.get("prompt_tokens_details") or {}
    completion = usage.get("completion_tokens_details") or {}
    choices = raw.get("choices")
    finish = (choices[0].get("finish_reason") if isinstance(choices, list) and choices
              and isinstance(choices[0], dict) else None)
    details = {
        "generation_id": identifier(raw.get("id")),
        "request_id": identifier(request_id),
        "upstream": identifier(raw.get("provider")),
        "actual_model": identifier(raw.get("model")),
        "latency_ms": max(0, int(elapsed_ms)),
        "cached_tokens": integer(prompt.get("cached_tokens")) if isinstance(prompt, dict) else None,
        "cache_write_tokens": integer(prompt.get("cache_write_tokens")) if isinstance(prompt, dict) else None,
        "reasoning_tokens": integer(completion.get("reasoning_tokens")) if isinstance(completion, dict) else None,
        "billed_usd": str(usage["cost"]) if micros(usage.get("cost")) is not None else None,
        "attempt": 1,
        "finish_reason": finish if finish in ("stop", "length", "content_filter", "tool_calls", "error") else None,
    }
    # Reasoning tokens are a subset of completion_tokens, not an extra charge.
    return {
        "input_tokens": integer(usage.get("prompt_tokens")),
        "output_tokens": integer(usage.get("completion_tokens")),
        "cost_micros": micros(usage.get("cost")),
        "cost_source": "reported" if micros(usage.get("cost")) is not None else "unknown",
        "telemetry": details,
    }


def eur_amount(usd_micros, budget, *, reserve=False):
    fee = Decimal(1) + Decimal(budget["fee_reserve_bps"]) / 10000 if reserve else Decimal(1)
    return int((Decimal(usd_micros) * Decimal(budget["eur_per_usd"]) * fee).to_integral_value(rounding=ROUND_CEILING))


def reserve_child(db, usage, route):
    policy = (route or {}).get("child_cost_control")
    if policy:
        from .child_cost_controls import reserve_controlled

        reserve_controlled(db, usage, policy)
        return
    if not route:
        return
    budget = route["budget"]
    period = datetime.fromtimestamp(now(), timezone.utc).strftime("%Y-%m")
    key = usage.child_id + ":" + period
    amount = eur_amount(usage.reserved_micros, budget, reserve=True)
    insert_ignore(db, ChildCostBucket, {"id": key, "child_id": usage.child_id, "period": period,
        "calls": 0, "encumbered_eur_micros": 0, "known_eur_micros": 0, "unknown_calls": 0})
    changed = db.execute(update(ChildCostBucket).where(
        ChildCostBucket.id == key,
        ChildCostBucket.encumbered_eur_micros + amount <= budget["hard_eur_micros"],
    ).values(calls=ChildCostBucket.calls + 1,
        encumbered_eur_micros=ChildCostBucket.encumbered_eur_micros + amount,
        unknown_calls=ChildCostBucket.unknown_calls + 1))
    if not changed.rowcount:
        db.rollback()
        raise HTTPException(429, "Für neue KI-Übungen ist das Lernbudget erreicht. Deine Hefte, Übungen und Lerntipps bleiben da.")
    usage.child_budget_id, usage.reserved_eur_micros = key, amount


def allocate_fee(db, amount):
    if amount == 0:
        return 0
    lots = list(db.scalars(select(CreditPurchase).where(CreditPurchase.consumed_micros < CreditPurchase.credits_micros)
        .order_by(CreditPurchase.created, CreditPurchase.id).with_for_update()))
    if sum(lot.credits_micros - lot.consumed_micros for lot in lots) < amount:
        return None  # Missing receipts are not zero fees.
    fee, remaining = 0, amount
    for lot in lots:
        take = min(remaining, lot.credits_micros - lot.consumed_micros)
        lot.consumed_micros += take
        allocated = lot.fee_micros * lot.consumed_micros // lot.credits_micros
        fee += allocated - lot.allocated_fee_micros
        lot.allocated_fee_micros = allocated
        remaining -= take
        if not remaining:
            break
    return fee


def settle_child(db, usage):
    from .child_cost_controls import balance_value, sync_balance, usage_quote
    from .child_cost_models import UsageCostBalance

    previous = db.get(UsageCostBalance, usage.id)
    quote = usage_quote(usage, balance=previous)
    if not quote:
        return
    # A later verified provider correction must not allocate the same credits
    # again. Preserve its historical fee basis and explicitly flag a mismatch.
    if usage.cost_micros is not None and usage.allocated_fee_micros is None:
        usage.allocated_fee_micros = allocate_fee(db, usage.cost_micros)
        if usage.allocated_fee_micros is not None:
            if not previous:
                previous = sync_balance(db, usage)
            previous.fee_basis_usd_micros = usage.cost_micros
    row = sync_balance(db, usage)
    if usage.child_budget_id and usage.cost_micros is not None:
        booking = (usage.telemetry or {}).get("child_bucket_booking")
        if not (isinstance(booking, dict) and booking.get("version") == 1
                and booking.get("bucket_id") == usage.child_budget_id
                and type(booking.get("accounted_eur_micros")) is int
                and type(booking.get("known_eur_micros")) is int
                and type(booking.get("provider_known")) is bool):
            # 0038 balances did not exist for historical usage. A projection or
            # policy edit may have created one without changing the legacy
            # bucket. Its real booked amount is the old final charge, or the
            # original reservation while a fee/price receipt was missing.
            final = usage.charged_eur_micros
            booking = {"accounted_eur_micros": final if final is not None else usage.reserved_eur_micros,
                "known_eur_micros": final if final is not None else 0,
                "provider_known": final is not None}
        known = (row.provider_eur_micros or 0) + (row.fee_known_eur_micros or 0)
        db.execute(update(ChildCostBucket).where(ChildCostBucket.id == usage.child_budget_id).values(
            encumbered_eur_micros=ChildCostBucket.encumbered_eur_micros + row.accounted_eur_micros - booking["accounted_eur_micros"],
            known_eur_micros=ChildCostBucket.known_eur_micros + known - booking["known_eur_micros"],
            unknown_calls=ChildCostBucket.unknown_calls - int(not booking["provider_known"])))
        usage.telemetry = {**(usage.telemetry or {}), "child_bucket_booking": {"version": 1,
            "bucket_id": usage.child_budget_id, "accounted_eur_micros": row.accounted_eur_micros,
            "known_eur_micros": known, "provider_known": True}}
    if row and usage.cost_micros is not None and row.fee_state == "actual":
        usage.charged_eur_micros = row.accounted_eur_micros
    else:
        usage.charged_eur_micros = None
    reserved = balance_value(type("Reservation", (), {"cost_micros": None, "reserved_micros": usage.reserved_micros,
        "allocated_fee_micros": None})(), quote)["accounted_eur_micros"]
    if row and row.accounted_eur_micros > reserved:
        from .db import ProviderConfig

        config = db.get(ProviderConfig, 1)
        config.emergency_stop = True
        config.status = "Kosten einschließlich Gebühren übersteigen die Reservierung. Belege und Wechselkurs prüfen."


def reconcile_one():
    """One bounded metadata GET per tick; at most three, never repeat inference."""
    import httpx

    from .config import settings
    from .db import DB, ProviderConfig, UsageBucket
    from .security import decrypt

    with DB.begin() as db:
        fee_pending = db.scalar(select(Usage).where(Usage.cost_micros.is_not(None),
            Usage.allocated_fee_micros.is_(None), Usage.charged_eur_micros.is_(None)).order_by(Usage.created, Usage.id).limit(1).with_for_update(skip_locked=True))
        if fee_pending:
            settle_child(db, fee_pending)
            if fee_pending.charged_eur_micros is not None:
                return True
    # Release the fee row/credit locks before claiming an unrelated metadata
    # reconciliation. Two workers must never acquire Usage locks in reverse.
    with DB.begin() as db:
        generation = Usage.telemetry["generation_id"].as_string()
        # Filter before LIMIT: old unknown costs without a usable generation or
        # with exhausted attempts must never starve newer billable requests.
        row = db.scalar(select(Usage).where(
            Usage.provider == "openrouter", Usage.cost_source.not_in(("generation", "cancelled")), Usage.status != "reserved",
            generation.is_not(None), func.length(generation).between(1, 180),
            func.coalesce(Usage.telemetry["reconcile_attempts"].as_integer(), 0) < 3,
            func.coalesce(Usage.telemetry["reconcile_after"].as_float(), 0) <= now(),
        ).order_by(Usage.created, Usage.id).limit(1).with_for_update(skip_locked=True))
        if not row:
            return False
        if not identifier(row.telemetry.get("generation_id")):
            # Malformed historical metadata is not a cost of zero. Keep its
            # hold, stop retrying it and continue with later rows next tick.
            row.telemetry = {**row.telemetry, "reconcile_attempts": 3,
                "reconcile_error": "invalid_generation_id"}
            return True
        config = db.get(ProviderConfig, 1)
        if config.provider != "openrouter" or not (settings.openrouter_api_key or config.encrypted_key):
            return False
        key = settings.openrouter_api_key or decrypt(config.encrypted_key)
        row.telemetry = {**row.telemetry, "reconcile_attempts": row.telemetry.get("reconcile_attempts", 0) + 1,
            "reconcile_after": int(now()) + 300}
        usage_id, generation_id = row.id, row.telemetry["generation_id"]
    try:
        response = httpx.get("https://openrouter.ai/api/v1/generation", params={"id": generation_id},
            headers={"Authorization": "Bearer " + key}, timeout=10, follow_redirects=False)
        if response.status_code != 200 or len(response.content) > 50_000:
            return True
        data = response.json()["data"]
        if data.get("id") != generation_id or micros(data.get("total_cost")) is None:
            return True
        cost = micros(data["total_cost"])
        with DB.begin() as db:
            row = db.scalar(select(Usage).where(Usage.id == usage_id).with_for_update())
            if not row or row.cost_source == "generation" or row.status == "reserved":
                return True
            if row.cost_micros is not None:
                from .child_cost_controls import sync_balance

                sync_balance(db, row)
            previous_cost = row.cost_micros
            previous_amount = row.reserved_micros if previous_cost is None else previous_cost
            for name in row.bucket_ids:
                db.execute(update(UsageBucket).where(UsageBucket.id == name).values(
                    encumbered_micros=UsageBucket.encumbered_micros + cost - previous_amount,
                    known_cost_micros=UsageBucket.known_cost_micros + cost - (previous_cost or 0),
                    unknown_calls=UsageBucket.unknown_calls - int(previous_cost is None)))
            row.cost_micros, row.cost_source = cost, "generation"
            row.telemetry = {**row.telemetry, "billed_usd": str(data["total_cost"]),
                "request_id": identifier(data.get("request_id")), "upstream": identifier(data.get("provider_name")),
                "reasoning_tokens": integer(data.get("native_tokens_reasoning")),
                "native_completion_tokens": integer(data.get("native_tokens_completion")),
                "native_finish_reason": data.get("native_finish_reason") if data.get("native_finish_reason") in
                    ("stop", "length", "max_output_tokens", "content_filter", "tool_calls", "error") else None,
                "cached_tokens": integer(data.get("native_tokens_cached")), "reconciled_at": int(now()),
                "cost_receipt_state": "verified_generation", "reported_cost_micros": previous_cost}
            row.input_tokens = integer(data.get("tokens_prompt"))
            row.output_tokens = integer(data.get("tokens_completion"))
            if row.status.startswith("failed"):
                row.status = "failed_billed"
            if cost > row.reserved_micros:
                config = db.get(ProviderConfig, 1)
                config.emergency_stop = True
                config.status = "Nachträgliche Abrechnung überschreitet die Reservierung. Notfallstopp aktiv."
            settle_child(db, row)
    except (httpx.HTTPError, ValueError, KeyError, TypeError):
        pass
    return True


def percentile(values, fraction):
    return sorted(values)[max(0, math.ceil(len(values) * fraction) - 1)] if values else None


def report(db, since):
    rows = list(db.scalars(select(Usage).where(Usage.created >= since)))
    grouped, children, minutes = {}, {}, {}
    for row in rows:
        key = row.provider + ":" + row.model
        item = grouped.setdefault(key, {"calls": 0, "billed_micros_usd": 0, "unknown_calls": 0,
            "unusable_calls": 0, "cached_tokens": 0, "reasoning_tokens": 0, "latencies": []})
        item["calls"] += 1
        item["billed_micros_usd"] += row.cost_micros or 0
        item["unknown_calls"] += row.cost_micros is None
        item["unusable_calls"] += row.status.startswith("failed")
        item["cached_tokens"] += (row.telemetry or {}).get("cached_tokens") or 0
        item["reasoning_tokens"] += (row.telemetry or {}).get("reasoning_tokens") or 0
        if type((row.telemetry or {}).get("latency_ms")) is int:
            item["latencies"].append(row.telemetry["latency_ms"])
        # Pseudonymous account identifier, no names/materials/answers.
        import hashlib

        child = hashlib.sha256(("ai-cost:" + row.child_id).encode()).hexdigest()[:16]
        cost = children.setdefault(child, {"calls": 0, "held_micros_usd": 0, "billed_micros_usd": 0})
        cost["calls"] += 1
        cost["held_micros_usd"] += row.cost_micros if row.cost_micros is not None else row.reserved_micros
        cost["billed_micros_usd"] += row.cost_micros or 0
        minute = row.created // 60
        minutes[minute] = minutes.get(minute, 0) + 1
    for item in grouped.values():
        values = item.pop("latencies")
        item.update(p50_ms=percentile(values, .5), p95_ms=percentile(values, .95))
    policy = None
    from .db import Attempt, Job, LearningUnit, OperatorJob, ProviderConfig
    from .model_routing import enabled

    config = db.get(ProviderConfig, 1)
    if enabled(config):
        policy = config.routing_policy["budget"]
    budgets = []
    if policy:
        for bucket in db.scalars(select(ChildCostBucket).where(ChildCostBucket.period == datetime.fromtimestamp(now(), timezone.utc).strftime("%Y-%m"))):
            import hashlib

            budgets.append({"cost_centre": hashlib.sha256(("ai-cost:" + bucket.child_id).encode()).hexdigest()[:16],
                "known_eur_micros": bucket.known_eur_micros, "held_eur_micros": bucket.encumbered_eur_micros,
                "unsettled_calls": bucket.unknown_calls,
                "state": "blocked" if bucket.encumbered_eur_micros >= policy["hard_eur_micros"] else
                    "warning" if bucket.encumbered_eur_micros >= policy["warning_eur_micros"] else
                    "over_target" if bucket.encumbered_eur_micros >= policy["target_eur_micros"] else "within_target"})
    # Attribution is limited to jobs explicitly attached to a saved round.
    # Material/OCR costs are not silently assigned to a completed learning goal.
    jobs = {j.id: j.payload for j in db.scalars(select(Job).where(Job.id.in_([r.job_id for r in rows])))}
    attributed = {}
    for row in rows:
        unit_id = jobs.get(row.job_id, {}).get("unit_id")
        if unit_id:
            attributed.setdefault(unit_id, []).append(row)
    completed = list(db.scalars(select(LearningUnit).where(LearningUnit.id.in_(attributed), LearningUnit.status == "completed")))
    costed = [unit for unit in completed if all(r.cost_micros is not None for r in attributed[unit.id])]
    completed_cost = sum(r.cost_micros for unit in costed for r in attributed[unit.id])
    # A successful practice goal is narrower than durable mastery. Keep the
    # accounting population explicit; unknown costs are never averaged as zero.
    independent = {(a.unit_id, a.question_id) for a in db.scalars(select(Attempt).where(
        Attempt.unit_id.in_([u.id for u in costed]), Attempt.outcome == "correct", Attempt.assisted.is_(False)))}
    practiced_goals = {(u.id, q["learning_goal_id"]) for u in costed for q in u.questions
        if q.get("learning_goal_id") and (u.id, q["id"]) in independent}
    goal_units = {unit_id for unit_id, _ in practiced_goals}
    goal_cost = sum(r.cost_micros for unit_id in goal_units for r in attributed[unit_id])
    probes = [item for job in db.scalars(select(OperatorJob).where(OperatorJob.created >= since)) for item in job.report]
    return {"models": grouped, "cost_centres": sorted(children.items(), key=lambda r: -r[1]["held_micros_usd"])[:20],
        "operator_probes": {"calls": len(probes), "billed_micros_usd": sum(item.get("cost_micros_usd") or 0 for item in probes),
            "unknown_calls": sum(item.get("cost_micros_usd") is None for item in probes)},
        "child_budgets": budgets, "budget_policy": policy,
        "completed_costed_sessions": len(costed),
        "attributed_completed_cost_micros_usd": completed_cost,
        "cost_per_completed_session_micros_usd": (completed_cost + len(costed) - 1) // len(costed) if costed else None,
        "independently_practiced_goals": len(practiced_goals),
        "cost_per_independently_practiced_goal_micros_usd": (goal_cost + len(practiced_goals) - 1) // len(practiced_goals) if practiced_goals else None,
        "goal_cost_notice": "Verteilung der bekannten Rundenzuordnung auf gespeicherte Lernziele mit selbstständiger Anwendung; keine Beherrschung und keine vollständigen Materialkosten.",
        "attribution_notice": "Nur eindeutig zugeordnete KI-Aufträge; Materialkosten und unbekannte Kosten sind darin nicht vollständig enthalten. Keine Kosten pro beherrschtem Lernziel behauptet.",
        "peak_calls_per_minute": max(minutes.values(), default=0),
        "escalations": sum((r.route_snapshot or {}).get("tier") == "astra" for r in rows),
        "note": "Unbekannte Kosten und fehlende Gebührenbelege sind keine Nullkosten. Schätzungen sind keine Rechnung."}
