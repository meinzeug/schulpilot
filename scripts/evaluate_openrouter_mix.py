#!/usr/bin/env python3
"""Fixed artificial sources and a private durable, bounded ledger across restarts.

Never imports production users, never buys credits, never activates a route.
Run with the pinned venv; the key is read only from the local file.
"""

import argparse
import json
import os
import sys
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--key-file", type=Path, default=Path.home() / "or.txt")
    parser.add_argument("--directory", type=Path, default=Path.home() / ".local/share/schulpilot-evaluation")
    parser.add_argument("--full", action="store_true", help="Two OCR variants and two model tiers in five subjects")
    parser.add_argument("--terra-candidate", action="store_true", help="Evaluate Terra on Azure/EU using only fixed synthetic fixtures")
    parser.add_argument("--terra-full-photo", action="store_true", help="Test the larger synthetic fractions photo with a 0.50 USD total test ceiling")
    args = parser.parse_args()
    if args.terra_full_photo and not args.terra_candidate:
        parser.error("--terra-full-photo requires --terra-candidate")
    args.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    args.directory.chmod(0o700)
    from cryptography.fernet import Fernet

    master = args.directory / "master.key"
    if not master.exists():
        master.write_bytes(Fernet.generate_key())
        master.chmod(0o600)
    os.environ.update(DATABASE_URL="sqlite:///" + str(args.directory / "evaluation.sqlite"),
        DATA_DIR=str(args.directory / "data"), MASTER_KEY=master.read_text().strip(),
        OPENROUTER_API_KEY=args.key_file.expanduser().read_text().strip(), ENVIRONMENT="test",
        SYNTHETIC_AI_ENABLED="true", SYNTHETIC_PAID_PROBE="true",
        SYNTHETIC_TEST_BUDGET_MICROS="500000" if args.terra_full_photo else "250000")
    sys.path.insert(0, str(ROOT / "backend"))
    import httpx
    from fastapi import HTTPException
    from schulpilot.ai_accounting import reconcile_one
    from schulpilot.audit_fixtures import prepare as prepare_audit
    from schulpilot.db import DB, Child, Family, Installation, Job, ProviderConfig, Usage, User, init_db, now, uid
    from schulpilot.fixtures import CASES
    from schulpilot.model_routing import RoutingPolicy, select_route
    from schulpilot.providers import ProviderError, request_provider, reserve, settle
    from schulpilot.security import password_hash
    from sqlalchemy import select

    init_db()
    routes, metadata = {}, []
    key = os.environ["OPENROUTER_API_KEY"]
    headers = {"Authorization": "Bearer " + key}
    with httpx.Client(timeout=25, follow_redirects=False) as client:
        zdr = client.get("https://openrouter.ai/api/v1/endpoints/zdr", headers=headers)
        zdr.raise_for_status()
        eligible = {(e["model_id"], e["tag"]) for e in zdr.json()["data"]}
        candidate_models = {"luna": "openai/gpt-6-luna", "sol": "openai/gpt-6.1-terra" if args.terra_candidate else "openai/gpt-6.1-sol", "astra": "openai/gpt-6-astra"}
        for tier, model in candidate_models.items():
            upstream = "azure/eu" if args.terra_candidate and tier == "sol" else "azure"
            response = client.get("https://openrouter.ai/api/v1/models/" + model + "/endpoints")
            response.raise_for_status()
            data = response.json()["data"]
            endpoint = next(e for e in data["endpoints"] if e["tag"] == upstream and (model, e["tag"]) in eligible and e["status"] == 0)
            supported = endpoint["supported_parameters"]
            if not {"reasoning", "response_format", "structured_outputs"} <= set(supported):
                raise SystemExit("Required parameters not available; no fallback used")
            metadata.append({"model": model, "upstream": upstream, "pricing": endpoint["pricing"], "zdr_listed": True})
            rates = [int((Decimal(endpoint["pricing"][kind]) * 10**12).to_integral_value()) for kind in ("prompt", "completion")]
            routes[tier] = {"model": model, "upstreams": [upstream], "input_per_million_micros": rates[0],
                "output_per_million_micros": rates[1], "max_output_tokens": 8000 if args.terra_candidate and tier == "sol" else 4000 if tier != "astra" else 2000,
                "reserve_micros": 250000 if args.terra_full_photo and tier == "sol" else 150000 if args.terra_candidate and tier == "sol" else 50000 if tier == "luna" else 80000 if tier == "sol" else 250000, "image_capable": "image" in data["architecture"]["input_modalities"],
                "capability_evidence": "OpenRouter endpoint metadata; synthetic acceptance pending",
                "pricing_evidence": "https://openrouter.ai/api/v1/models/" + model + "/endpoints",
                "verified_at": int(now()), "evaluated": False, "under13_approved": False}
    # Explicit conservative planning assumption for synthetic costs, not an FX
    # transaction rate. No claim about a real EUR invoice is made from this.
    policy = RoutingPolicy(version=1, enabled=True, revision="synthetic-evaluation-1", routes=routes,
        budget={"eur_per_usd": "1.00", "fx_evidence": "Synthetic budget bound: 1 EUR per USD; not a market quotation",
            "fx_checked_at": int(now()), "fee_reserve_bps": 800}).model_dump()
    with DB.begin() as db:
        db.get(Installation, 1).completed = True
        family = db.scalar(select(Family).where(Family.name == "OpenRouter artificial evaluation"))
        if not family:
            family = Family(name="OpenRouter artificial evaluation", synthetic=True, call_limit=1000)
            db.add(family)
            db.flush()
            import secrets

            user = User(username="openrouter-artificial-reference", display_name="Artificial reference", role="child",
                verified=True, password_hash=password_hash(secrets.token_urlsafe(32)))
            db.add(user)
            db.flush()
            child = Child(family_id=family.id, user_id=user.id, grade=6, subjects=["Mathematik"], preferences={})
            db.add(child)
            db.flush()
        else:
            child = db.scalar(select(Child).where(Child.family_id == family.id))
        fid, cid = family.id, child.id
        config = db.get(ProviderConfig, 1)
        config.provider, config.model, config.routing_policy = "openrouter", routes["sol"]["model"], policy
        config.emergency_stop, config.production_block_reason = False, "Synthetic evaluation only"
        config.reserve_micros, config.max_output_tokens = 250000, 8000 if args.terra_candidate else 4000
        config.revision += 1
    if args.full:
        prepare_audit(Path.home() / "Downloads/Schulpilot_Testbilder_48_2026-10-19.zip")
    cases = ["audit-" + key.lower() + "-v1" for key in ("MAT01", "MAT02", "DEU01", "DEU02", "ENG01", "ENG02", "BIO01", "BIO02", "GEO01", "GEO02")] if args.full else ["fractions-v1"]
    reconcile_one()  # Metadata only; never re-run a failed generation.
    reports, blocked = [], False
    for fixture in cases:
        operations = [("extract", "sol")] if args.terra_full_photo else [("extract", "sol"), ("unit", "sol"), ("package", "sol")] if args.terra_candidate else [("extract", "luna"), ("unit", "luna"), ("unit", "sol")]
        for function, tier in operations:
            probe_fixture = "eval-english-v1" if args.terra_candidate and function == "extract" and not args.terra_full_photo else fixture
            identity = ("terra-eu-full-photo-1:" if args.terra_full_photo else "terra-eu-1:" if args.terra_candidate else "mix-1:") + probe_fixture + ":" + function + ":" + tier
            with DB.begin() as db:
                previous = db.scalar(select(Job).where(Job.idempotency == identity))
                if previous:
                    item = previous.result or {"case": identity, "status": previous.status}
                    usage = db.scalar(select(Usage).where(Usage.job_id == previous.id))
                    if usage:
                        item = {**item, "billed_micros_usd": usage.cost_micros, "telemetry": usage.telemetry}
                    reports.append(item)
                    continue
                job = Job(id=uid(), child_id=cid, kind=function, payload={}, idempotency=identity, status="running")
                db.add(job)
                db.flush()
                try:
                    usage = reserve(db, db.get(Family, fid), cid, job.id, function, synthetic_fixture=True, probe_tier=tier)
                except HTTPException:
                    blocked = True
                    reports.append({"case": identity, "function": function, "tier": tier,
                        "status": "not_started_budget", "billed_micros_usd": None, "cost_source": "not_sent"})
                    continue
                config = select_route(db.get(ProviderConfig, 1), function, snapshot=usage.route_snapshot)
                job_id = job.id
            result, error = None, None
            try:
                result = request_provider(config, function, {}, synthetic_fixture=probe_fixture, private_probe=True)
            except ProviderError as exc:
                result, error = exc.billing_result, str(exc)
            with DB.begin() as db:
                usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
                settle(db, usage, result, failed=bool(error))
                item = {"case": identity, "function": function, "tier": tier, "status": "failed" if error else "completed",
                    "billed_micros_usd": usage.cost_micros, "input_tokens": usage.input_tokens, "output_tokens": usage.output_tokens,
                    "telemetry": usage.telemetry, "error": error}
                if result and not error:
                    if function == "extract":
                        expected = CASES.get(probe_fixture, {}).get("anchors", ["Nenner", "Zähler", "1/4"])
                        item["ocr_anchor_checks"] = {anchor: anchor.casefold() in result.data["content"].casefold() for anchor in expected}
                    item["synthetic_output"] = result.data
                job = db.get(Job, job_id)
                job.status, job.finished, job.result = item["status"], int(now()), item
                reports.append(item)
            print(json.dumps({k: v for k, v in item.items() if k not in ("synthetic_output", "telemetry")}), flush=True)
    output = {"synthetic_only": True, "budget_cap_usd": "0.50" if args.terra_full_photo else "0.25", "budget_blocked": blocked, "metadata": metadata, "calls": reports,
        "cost_micros_usd": sum(r["billed_micros_usd"] or 0 for r in reports),
        "unknown_cost_calls": sum(r["billed_micros_usd"] is None and r["status"] != "not_started_budget" for r in reports),
        "limits": "Schema/OCR anchors are technical checks, not a learning-effectiveness trial or complete delivery test."}
    target = args.directory / "report.json"
    target.write_text(json.dumps(output, indent=2, ensure_ascii=False))
    target.chmod(0o600)
    print("Saved synthetic evaluation to " + str(target))


if __name__ == "__main__":
    main()
