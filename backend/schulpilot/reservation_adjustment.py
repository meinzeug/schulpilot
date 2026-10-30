"""Explicit local-operator reservation adjustment; never starts an AI call."""
import argparse
import json
from decimal import ROUND_CEILING, Decimal

from sqlalchemy import select

from .db import DB, Audit, Job, OperatorJob, ProviderConfig
from .model_routing import RoutingPolicy
from .security import audit


def raise_reservations(db, expected_revision, operation):
    if db.scalar(select(Audit.id).where(Audit.action == "provider.reservation_increase", Audit.target == operation)):
        return {"already_applied": True}
    base = db.scalar(select(ProviderConfig).where(ProviderConfig.id == 1).with_for_update())
    buddy = db.scalar(select(ProviderConfig).where(ProviderConfig.id == 2).with_for_update())
    # Another operator may have completed the same request while we waited.
    if db.scalar(select(Audit.id).where(Audit.action == "provider.reservation_increase", Audit.target == operation)):
        return {"already_applied": True}
    if not base or base.revision != expected_revision or not buddy:
        raise ValueError("Anbietereinstellungen haben sich geändert oder Schulbuddy fehlt.")
    if (db.scalar(select(Job.id).where(Job.status.in_(["queued", "running"])).limit(1))
            or db.scalar(select(OperatorJob.id).where(OperatorJob.status.in_(["queued", "running"])).limit(1))):
        raise ValueError("Laufende KI-Aufträge zuerst abschließen.")
    policy = RoutingPolicy.model_validate(base.routing_policy).model_dump()
    rate = Decimal(policy["budget"]["eur_per_usd"])
    increase = int((Decimal(3_000_000) / rate).to_integral_value(rounding=ROUND_CEILING))
    before = {"base": base.reserve_micros, "buddy": buddy.reserve_micros,
              "routes": {name: route["reserve_micros"] for name, route in policy["routes"].items()}}
    after = {"base": before["base"] + increase, "buddy": before["buddy"] + increase,
             "routes": {name: value + increase for name, value in before["routes"].items()}}
    if max(after["base"], after["buddy"], *after["routes"].values()) > 10_000_000:
        raise ValueError("Die gewünschte Reservierung überschreitet die zulässige Auftragsgrenze.")
    for name, amount in after["routes"].items():
        policy["routes"][name]["reserve_micros"] = amount
    policy["revision"] = (policy["revision"][:45] + "-reserve3eur")
    policy = RoutingPolicy.model_validate(policy).model_dump()
    base.reserve_micros, base.routing_policy = after["base"], policy
    base.revision += 1
    # The separately audited Schulbuddy binding identifies model/provider/effort.
    # Those do not change; the global revision invalidates in-flight snapshots.
    buddy.reserve_micros = after["buddy"]
    audit(db, "local-operator", "provider.reservation_increase", operation)
    audit(db, "local-operator", "provider.reservation_eur_rate", str(rate))
    for name, value in before["routes"].items():
        audit(db, "local-operator", "provider.reservation_route", f"{name}:{value}->{after['routes'][name]}")
    audit(db, "local-operator", "provider.reservation_base", f"{before['base']}->{after['base']}")
    audit(db, "local-operator", "provider.reservation_buddy", f"{before['buddy']}->{after['buddy']}")
    return {"already_applied": False, "revision": base.revision, "usd_eur_rate": str(rate),
            "increase_usd_micros": increase, "before": before, "after": after}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected-revision", type=int, required=True)
    parser.add_argument("--operation", required=True, choices=["reserve-plus-3eur-20261028"])
    args = parser.parse_args()
    with DB.begin() as db:
        result = raise_reservations(db, args.expected_revision, args.operation)
    print(json.dumps(result))


if __name__ == "__main__":
    main()
