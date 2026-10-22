"""Content-free operator controls. All mutations are explicit and audited."""

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select

from . import schemas as s
from .ai_accounting import report
from .db import CreditPurchase, ProviderConfig, get_db, now
from .model_routing import ROUTING_REASONING_EFFORT, RoutingPolicy
from .security import admin, audit

router = APIRouter(tags=["KI-Routing und Kosten"])


class PolicyUpdate(s.Strict):
    revision: int
    policy: RoutingPolicy


@router.get("/admin/ai-routing")
def routing(p=Depends(admin), db=Depends(get_db)):
    config = db.get(ProviderConfig, 1)
    return {"revision": config.revision, "policy": config.routing_policy, "provider": config.provider,
        "emergency_stop": config.emergency_stop,
        "effective_reasoning_effort": ROUTING_REASONING_EFFORT,
        "existing_global_limit_micros_usd": config.global_limit_micros,
        "existing_reservation_micros_usd": config.reserve_micros}


@router.put("/admin/ai-routing")
def save(data: PolicyUpdate, p=Depends(admin), db=Depends(get_db)):
    config = db.scalar(select(ProviderConfig).where(ProviderConfig.id == 1).with_for_update())
    if config.revision != data.revision:
        raise HTTPException(409, "Die Einstellungen wurden geändert. Bitte neu laden.")
    value = data.policy.model_dump()
    if value == config.routing_policy:
        return {"revision": config.revision, "policy": value}
    config.routing_policy, config.revision = value, config.revision + 1
    # Metadata/configuration is not an operational acceptance test.
    config.production_block_reason = "Neue Routingregeln müssen mit künstlichen Bild-, Aufgaben- und Pakettests geprüft werden."
    audit(db, p.user.id, "admin.ai_routing_update", value["revision"])
    db.commit()
    return {"revision": config.revision, "policy": value}


@router.get("/admin/ai-costs")
def costs(days: int = Query(31, ge=1, le=90), p=Depends(admin), db=Depends(get_db)):
    data = report(db, int(now()) - days * 86400)
    data["credit_purchases"] = [{"id": r.id, "credits_micros_usd": r.credits_micros,
        "fee_micros_usd": r.fee_micros, "consumed_micros_usd": r.consumed_micros,
        "allocated_fee_micros_usd": r.allocated_fee_micros} for r in db.scalars(select(CreditPurchase)
            .order_by(CreditPurchase.created.desc(), CreditPurchase.id).limit(50))]
    return data


class Receipt(s.Strict):
    receipt_id: str = s.Field(min_length=8, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")
    credits_micros_usd: int = s.Field(ge=1, le=1_000_000_000)
    fee_micros_usd: int = s.Field(ge=0, le=100_000_000)


@router.post("/admin/ai-credit-receipts")
def receipt(data: Receipt, p=Depends(admin), db=Depends(get_db)):
    # No credit purchase is made here; this records a real existing receipt.
    from .security import insert_ignore

    insert_ignore(db, CreditPurchase, {"id": data.receipt_id, "credits_micros": data.credits_micros_usd,
        "fee_micros": data.fee_micros_usd, "consumed_micros": 0, "allocated_fee_micros": 0, "created": int(now())})
    row = db.get(CreditPurchase, data.receipt_id)
    if (row.credits_micros, row.fee_micros) != (data.credits_micros_usd, data.fee_micros_usd):
        raise HTTPException(409, "Diese Belegkennung wurde bereits mit anderen Werten gespeichert.")
    audit(db, p.user.id, "admin.ai_credit_receipt", data.receipt_id)
    db.commit()
    return {"recorded": True}
