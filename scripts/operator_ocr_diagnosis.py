#!/usr/bin/env python3
"""Explicit local-only named-source OCR diagnosis. No auto retries or exports.

Requires deployed0035 tables; never creates/migrates a live database. Only Root
may run the reviewed grant/run commands for the explicitly approved family.
Without --live, all commands show bounded preflight only, without image reads.
"""

import argparse
import json


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("preflight", "grant", "run", "purge"))
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--operator-id")
    parser.add_argument("--family-id")
    parser.add_argument("--material-id", action="append", default=[])
    parser.add_argument("--grant-id")
    parser.add_argument("--tier", choices=("luna", "sol"))
    parser.add_argument("--case-key")
    args = parser.parse_args()
    from schulpilot.config import settings
    from schulpilot.db import DB, ProviderConfig, engine
    from schulpilot.model_routing import policy_hash, select_route
    from schulpilot.source_evaluation import CAP_MICROS, WORK_ID, create_grant, run_case, used_micros
    from sqlalchemy import inspect

    if not inspect(engine).has_table("source_evaluation_budgets"):
        raise RuntimeError("required_migration_0035_missing")
    with DB() as db:
        config = db.get(ProviderConfig, 1)
        holds = used_micros(db)
        bounds = {
            tier: select_route(
                config,
                "extract",
                snapshot={
                    "policy_hash": policy_hash(config.routing_policy),
                    "tier": tier,
                    "reason": "operator_preflight",
                },
            ).reserve_micros
            for tier in ("luna", "sol")
        }
    if not args.live or args.command == "preflight":
        print(
            json.dumps(
                {
                    "preflight_only": True,
                    "cap_micros": CAP_MICROS,
                    "used_or_held_micros": holds,
                    "reserve_bounds_micros": bounds,
                    "all_12_luna_2_sol_worst_case_micros": 12 * bounds["luna"] + 2 * bounds["sol"],
                    "all_cases_worst_case_fits": holds + 12 * bounds["luna"] + 2 * bounds["sol"] <= CAP_MICROS,
                }
            )
        )
        return
    if args.command == "grant":
        if not args.operator_id or not args.family_id or not args.material_id:
            raise ValueError("explicit_operator_family_sources_required")
        with DB.begin() as db:
            grant = create_grant(db, args.operator_id, args.family_id, args.material_id)
            print(
                json.dumps(
                    {
                        "grant_id": grant.id,
                        "expires": grant.expires,
                        "source_count": len(grant.sources),
                        "cap_micros": CAP_MICROS,
                    }
                )
            )
    elif args.command == "run":
        if not args.grant_id or len(args.material_id) != 1 or not args.tier or not args.case_key:
            raise ValueError("one_explicit_fixed_case_required")
        print(json.dumps(run_case(args.grant_id, args.material_id[0], args.tier, args.case_key)))
    elif args.command == "purge":
        # Only transient diagnostic outputs; ledger/accounting stay persistent.
        directory = settings.data_dir / "operator-diagnostics" / WORK_ID
        count = 0
        if directory.is_dir():
            for path in directory.glob("*.json"):
                if len(path.stem) == 32 and all(char in "0123456789abcdef" for char in path.stem):
                    path.unlink()
                    count += 1
        print(json.dumps({"private_outputs_purged": count, "ledger_preserved": True}))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(json.dumps({"stopped": True, "error_kind": type(error).__name__}))
        raise SystemExit(1) from None
