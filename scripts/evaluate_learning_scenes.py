#!/usr/bin/env python3
"""One fixed artificial scene evaluation, offline unless --live is explicit.

--directory is the private report directory, not a fresh spending allowance.
The fixed per-case SQLite ledger survives changes of report directory and keeps
unknown reservations. No failed, interrupted or completed generation is retried.
No production database, account data or active provider configuration is used.
"""

import argparse
import fcntl
import hashlib
import json
import os
import secrets
import sqlite3
import sys
from decimal import ROUND_CEILING, Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CASE = "learning-scenes-20261023:flow-v1:unit:luna:azure:medium"
MODEL = "openai/gpt-6-luna"
UPSTREAM = "azure"
CAP_MICROS = 250_000
RESERVATION_MICROS = 150_000
MAX_OUTPUT_TOKENS = 4000
LEDGER = Path.home() / ".local/share/schulpilot-scene-evaluation-20261023"
MARKER = "schulpilot-fixed-synthetic-scene-evaluation-20261023-v1"
SOURCE_FILES = (
    "backend/schulpilot/learning_scenes.py",
    "backend/schulpilot/subject_content.py",
    "backend/schulpilot/providers.py",
    "backend/schulpilot/fixtures.py",
)


def source_hashes():
    return {relative: hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() for relative in SOURCE_FILES}


def private_json(path, value):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as target:
        os.fchmod(target.fileno(), 0o600)
        json.dump(value, target, ensure_ascii=False, indent=2)
        target.write("\n")


def directory(value):
    path = value.expanduser().resolve()
    if path in (Path("/"), Path.home().resolve(), ROOT) or path.is_relative_to(ROOT):
        raise ValueError("A dedicated private report directory outside the checkout is required")
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.chmod(0o700)
    return path


def no_quotes(value):
    if isinstance(value, dict):
        return "source_excerpt" not in value and all(no_quotes(v) for v in value.values())
    return not isinstance(value, list) or all(no_quotes(v) for v in value)


def preflight():
    from schulpilot.fixtures import SCENE_FIXTURE_ID, trusted_payload
    from schulpilot.subject_content import generation_context

    payload = trusted_payload("unit", SCENE_FIXTURE_ID)
    content = payload["material"]["content"]
    context = generation_context([payload["required_subject"]])
    checks = {
        "server_owned_fixture": SCENE_FIXTURE_ID == "learning-scene-flow-v1",
        "synthetic_source_only": payload.get("synthetic_fixture") == SCENE_FIXTURE_ID,
        "scene_request": payload.get("scene_request") == {
            "kind": "scene", "disclosure": "hint1", "steps": 3, "matching_pairs": 2,
        },
        "literal_matching_pairs": all(line in content for line in ("Wasser = flüssig.", "Wasserdampf = gasförmig.")),
        "literal_three_relations": all(
            relation in "".join(content.split()) for relation in ("Wasser→Wasserdampf", "Wasserdampf→Wolke", "Wolke→Wasser")
        ),
        "scene_in_existing_context": "scene" in json.dumps(context, ensure_ascii=False),
        "no_fixture_injected_from_cli": True,
    }
    if not all(checks.values()):
        raise ValueError("Fixed synthetic fixture/context preflight failed")
    return SCENE_FIXTURE_ID, payload, checks


def prepare_ledger():
    LEDGER.mkdir(parents=True, exist_ok=True, mode=0o700)
    LEDGER.chmod(0o700)
    marker = LEDGER / "evaluation-marker.json"
    database = LEDGER / "evaluation.sqlite"
    if marker.is_symlink() or database.is_symlink():
        raise ValueError("Evaluation ledger must use ordinary private files")
    if marker.exists():
        if json.loads(marker.read_text()) != {"purpose": MARKER}:
            raise ValueError("Unrecognized evaluation ledger")
    elif database.exists():
        raise ValueError("An existing unmarked database is never adopted")
    else:
        private_json(marker, {"purpose": MARKER})
    if database.exists():
        with sqlite3.connect(database.as_uri() + "?mode=ro", uri=True) as connection:
            if connection.execute("select count(*) from families where synthetic != 1").fetchone()[0]:
                raise ValueError("Evaluation ledger contains a non-synthetic family")
        database.chmod(0o600)
    lock_path = LEDGER / "evaluation.lock"
    descriptor = os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    lock = os.fdopen(descriptor, "w")
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    return database, lock


def request_fee_evidence(pricing, catalog_pricing, request_optional):
    """Distinguish the documented absence of a billed SKU from an unknown rate.

    PublicPricing only requires prompt/completion. Provider integration docs
    explicitly tell providers to omit SKUs they do not bill. Accept that omission
    only when fresh endpoint and catalog prices agree and the fresh API schema
    still declares request optional. Null, invalid and nonzero rates fail closed.
    """
    if any(Decimal(str(pricing[kind])) != Decimal(str(catalog_pricing[kind])) for kind in ("prompt", "completion")):
        raise ValueError("Endpoint and catalog token prices do not agree")
    evidence = {"schema_request_optional": request_optional,
                "omission_documentation": "https://openrouter.ai/docs/guides/providers/integration#3-pricing"}
    for name, value in (("endpoint", pricing), ("catalog", catalog_pricing)):
        if "request" not in value:
            if not request_optional:
                raise ValueError("Unknown request price: API schema does not document its omission")
            evidence[name + "_request_field"] = "omitted_not_billed_sku"
        else:
            price = Decimal(str(value["request"]))
            if not price.is_finite() or price != 0:
                raise ValueError("A nonzero or unknown request fee is not admitted")
            evidence[name + "_request_field"] = "explicit_zero"
        for override in value.get("overrides", []):
            if "request" in override:
                price = Decimal(str(override["request"]))
                if not price.is_finite() or price != 0:
                    raise ValueError("A nonzero or unknown conditional request fee is not admitted")
    return evidence


def fresh_policy(key, now):
    import httpx
    from schulpilot.model_routing import RoutingPolicy

    routes, metadata = {}, []
    # RoutingPolicy requires both tiers. Sol metadata only satisfies that existing
    # schema; this evaluator reserves and dispatches exclusively the Luna tier.
    with httpx.Client(timeout=25, follow_redirects=False) as client:
        response = client.get("https://openrouter.ai/api/v1/endpoints/zdr", headers={"Authorization": "Bearer " + key})
        response.raise_for_status()
        eligible = {(row["model_id"], row["tag"]) for row in response.json()["data"]}
        response = client.get("https://openrouter.ai/api/v1/models")
        response.raise_for_status()
        catalog = {row["id"]: row for row in response.json()["data"]}
        response = client.get("https://openrouter.ai/openapi.json")
        response.raise_for_status()
        pricing_schema = response.json()["components"]["schemas"]["PublicPricing"]
        request_optional = (
            "request" not in pricing_schema.get("required", [])
            and pricing_schema["properties"]["request"].get("type") == "string"
            and {"prompt", "completion"} <= set(pricing_schema.get("required", []))
        )
        for tier, model in (("luna", MODEL), ("sol", "openai/gpt-6.1-sol")):
            url = "https://openrouter.ai/api/v1/models/" + model + "/endpoints"
            response = client.get(url)
            response.raise_for_status()
            data = response.json()["data"]
            endpoint = next(row for row in data["endpoints"] if row["tag"] == UPSTREAM and (model, UPSTREAM) in eligible)
            if not {"reasoning", "response_format", "structured_outputs"} <= set(endpoint["supported_parameters"]):
                raise ValueError("Required structured reasoning parameters are unavailable")
            pricing = endpoint["pricing"]
            rates = []
            for kind in ("prompt", "completion"):
                price = Decimal(str(pricing[kind]))
                if not price.is_finite() or price < 0:
                    raise ValueError("Invalid endpoint price")
                rates.append(int((price * 10**12).to_integral_value(rounding=ROUND_CEILING)))
            fee_evidence = request_fee_evidence(pricing, catalog[model]["pricing"], request_optional)
            routes[tier] = {
                "model": model, "upstreams": [UPSTREAM], "input_per_million_micros": rates[0],
                "output_per_million_micros": rates[1], "max_output_tokens": MAX_OUTPUT_TOKENS,
                "reserve_micros": RESERVATION_MICROS,
                "image_capable": "image" in data["architecture"]["input_modalities"],
                "reasoning": "medium", "capability_evidence": "Fresh Azure structured-output endpoint metadata; synthetic scene acceptance pending",
                "pricing_evidence": url, "verified_at": int(now()), "evaluated": False, "under13_approved": False,
            }
            metadata.append({"model": model, "upstream": UPSTREAM, "pricing": pricing, "zdr_listed": True,
                             "request_fee_evidence": fee_evidence,
                             "catalog_evidence": "https://openrouter.ai/api/v1/models",
                             "schema_evidence": "https://openrouter.ai/openapi.json"})
    return RoutingPolicy(
        version=1, enabled=True, revision="fixed-scene-evaluation-20261023-v1", routes=routes,
        budget={"eur_per_usd": "1.00", "fx_evidence": "Synthetic conservative bound, 1 EUR per USD; not an exchange-rate quotation",
                "fx_checked_at": int(now()), "fee_reserve_bps": 800},
    ).model_dump(), metadata


def inspect_result(data, payload):
    from schulpilot.subject_content import public_presentation, validate_output

    validate_output(data, payload, bounded_matching=True)
    scenes, public = [], []
    matching = [question for question in data["questions"] if question.get("type") == "match"]
    exact_match = (
        len(matching) == 1
        and matching[0].get("options") == ["Wasser|flüssig", "Wasserdampf|gasförmig"]
        and matching[0].get("answer") == "flüssig;gasförmig"
    )
    for question in data["questions"]:
        presentation = question.get("presentation")
        if not presentation:
            continue
        scenes.extend(block for block in presentation["blocks"] if block["kind"] == "scene")
        for hints, closed in ((0, False), (1, False), (3, False), (3, True)):
            projected = public_presentation(presentation, hints=hints, closed=closed)
            allowed = {"given"} | {f"hint{i}" for i in range(1, hints + 1)} | ({"solution"} if closed else set())
            if not no_quotes(projected) or any(block["disclosure"] not in allowed for block in projected["blocks"]):
                raise ValueError("Public projection leaked private quotes or a hidden stage")
            public.append({"question_id": question.get("id"), "hints": hints, "closed": closed, "presentation": projected})
    return {
        "unit_parse_and_validation": True,
        "public_quotes_removed": all(no_quotes(row) for row in public),
        "disclosure_projection_checked": True,
        "requested_two_pair_match": exact_match,
        "matching_question_count": len(matching),
        "scene_emitted": bool(scenes),
        "scene_count": len(scenes),
        "hint1_three_step_scene": any(block["disclosure"] == "hint1" and len(block["scene"]["steps"]) == 3 for block in scenes),
        "finite_or_no_scene_only": not scenes,
    }, public


def bootstrap_live():
    from cryptography.fernet import Fernet

    database, lock = prepare_ledger()
    try:
        master = LEDGER / "master.key"
        if master.is_symlink():
            raise ValueError("Master key must be an ordinary private file")
        if not master.exists():
            descriptor = os.open(master, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            with os.fdopen(descriptor, "wb") as target:
                target.write(Fernet.generate_key())
        master.chmod(0o600)
        key = (Path.home() / "or.txt").read_text().strip()
        if not key or len(key) > 4096 or any(character.isspace() for character in key):
            raise ValueError("The local key file does not contain one bounded credential")
        os.environ.update(
            DATABASE_URL="sqlite:///" + str(database), DATA_DIR=str(LEDGER / "data"), MASTER_KEY=master.read_text().strip(),
            OPENROUTER_API_KEY=key, ENVIRONMENT="test", SYNTHETIC_AI_ENABLED="true", SYNTHETIC_PAID_PROBE="true",
            REAL_DATA_APPROVED="false", PRIVACY_EVIDENCE="", CODEX_APPROVED="false",
        )
        return {"database": database, "lock": lock, "key": key}
    except BaseException:
        lock.close()
        raise


def run_live(report_directory, fixture, payload, checks, bootstrap):
    database, key = bootstrap["database"], bootstrap["key"]
    from fastapi import HTTPException
    from schulpilot.db import (
        DB,
        Child,
        Family,
        Installation,
        Job,
        ProviderConfig,
        Usage,
        UsageBucket,
        User,
        init_db,
        now,
        uid,
    )
    from schulpilot.model_routing import select_route
    from schulpilot.providers import ProviderError, request_provider, reserve, settle
    from schulpilot.security import password_hash
    from sqlalchemy import select

    init_db()
    database.chmod(0o600)

    def summary(db, job, usage):
        dispatched_sources = (job.payload or {}).get("source_sha256")
        bucket = db.get(UsageBucket, "openrouter-evaluation-20261019")
        accounting = {
            "budget_cap_micros_usd": CAP_MICROS,
            "encumbered_micros_usd": bucket.encumbered_micros if bucket else 0,
            "known_cost_micros_usd": bucket.known_cost_micros if bucket else 0,
            "unknown_cost_calls": bucket.unknown_calls if bucket else 0,
        }
        return {
            "case": CASE, "synthetic_only": True, "status": (job.result or {}).get("status", job.status),
            "model": MODEL, "upstream": UPSTREAM, "reasoning": "medium", "max_output_tokens": MAX_OUTPUT_TOKENS,
            "reserved_micros_usd": usage.reserved_micros if usage else None,
            "billed_micros_usd": usage.cost_micros if usage else None,
            "input_tokens": usage.input_tokens if usage else None, "output_tokens": usage.output_tokens if usage else None,
            "checks": (job.result or {}).get("checks", checks),
            "source_sha256": dispatched_sources,
            "source_hash_stage": "dispatch_reserved",
            "current_sources_match_dispatch": dispatched_sources == source_hashes() if dispatched_sources else None,
            **accounting,
        }

    with DB() as db:
        previous = db.scalar(select(Job).where(Job.idempotency == CASE))
        if previous:
            usage = db.scalar(select(Usage).where(Usage.job_id == previous.id))
            result = {"summary": summary(db, previous, usage), "durable_job": previous.result}
            private_json(report_directory / "scene-evaluation-private.json", result)
            return result["summary"]

    policy, metadata = fresh_policy(key, now)
    dispatched_sources = source_hashes()
    with DB.begin() as db:
        db.get(Installation, 1).completed = True
        family = Family(name="Fixed artificial scene evaluation", synthetic=True, call_limit=1, budget_micros=CAP_MICROS)
        db.add(family)
        db.flush()
        user = User(username="scene-evaluation-" + uid(), display_name="Artificial scene reference", role="child",
                    verified=True, password_hash=password_hash(secrets.token_urlsafe(32)))
        db.add(user)
        db.flush()
        child = Child(family_id=family.id, user_id=user.id, grade=payload["grade"], subjects=["Geographie"], preferences={})
        db.add(child)
        db.flush()
        fid, cid = family.id, child.id
        config = db.get(ProviderConfig, 1)
        config.provider, config.model, config.routing_policy = "openrouter", MODEL, policy
        config.emergency_stop, config.production_block_reason = False, "Synthetic scene evaluation only"
        config.reserve_micros, config.max_output_tokens = RESERVATION_MICROS, MAX_OUTPUT_TOKENS
        config.global_limit_micros, config.reasoning_effort = CAP_MICROS, "medium"
        config.revision += 1
    try:
        with DB.begin() as db:
            job = Job(id=uid(), child_id=cid, kind="unit",
                      payload={"synthetic_fixture": fixture, "source_sha256": dispatched_sources},
                      idempotency=CASE, status="running", started=int(now()),
                      result={"status": "dispatch_reserved", "source_sha256": dispatched_sources, "checks": checks})
            db.add(job)
            db.flush()
            usage = reserve(db, db.get(Family, fid), cid, job.id, "unit", synthetic_fixture=True, probe_tier="luna")
            if usage.reserved_micros > RESERVATION_MICROS:
                raise ValueError("Unexpected reservation exceeds this evaluation's fixed bound")
            config = select_route(db.get(ProviderConfig, 1), "unit", snapshot=usage.route_snapshot)
            if config.model != MODEL or config.reasoning_effort != "medium":
                raise ValueError("Unexpected model route; no dispatch")
            job_id = job.id
    except HTTPException:
        with DB.begin() as db:
            job = Job(id=uid(), child_id=cid, kind="unit", payload={"source_sha256": dispatched_sources},
                      idempotency=CASE, status="failed", finished=int(now()),
                      result={"status": "not_started_budget_or_policy", "checks": checks, "source_sha256": dispatched_sources})
            db.add(job)
            db.flush()
            result = {"summary": summary(db, job, None), "metadata": metadata}
        private_json(report_directory / "scene-evaluation-private.json", result)
        return result["summary"]

    output, failure, failure_detail, public = None, None, None, None
    verified = checks
    try:
        if source_hashes() != dispatched_sources:
            raise ValueError("Critical sources changed after reservation; no dispatch")
        output = request_provider(config, "unit", {}, synthetic_fixture=fixture, private_probe=True)
        checked, public = inspect_result(output.data, payload)
        verified = {**checks, **checked}
    except ProviderError as error:
        output, failure = error.billing_result, type(error).__name__
        failure_detail = str(error).replace(key, "[redacted]")
    except Exception as error:
        failure = type(error).__name__
        failure_detail = str(error).replace(key, "[redacted]")
    with DB.begin() as db:
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        settle(db, usage, output, failed=failure is not None)
        job = db.get(Job, job_id)
        job.status, job.finished = ("failed" if failure else "completed"), int(now())
        if failure:
            status = "failed"
        elif verified.get("hint1_three_step_scene") and verified.get("requested_two_pair_match"):
            status = "scene_and_matching_checked"
        else:
            status = "valid_unit_requested_scene_or_matching_missing"
        job.result = {"status": status, "checks": verified, "failure_type": failure, "private_failure_detail": failure_detail, "metadata": metadata,
                      "source_sha256": dispatched_sources,
                      "synthetic_output": output.data if output else None, "public_projections": public}
        db.flush()
        result = {"summary": summary(db, job, usage), "durable_job": job.result}
    private_json(report_directory / "scene-evaluation-private.json", result)
    return result["summary"]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True, help="Dedicated private report directory outside the checkout")
    parser.add_argument("--live", action="store_true", help="Explicitly allow fresh metadata and the single fixed, reserved model call")
    args = parser.parse_args()
    os.umask(0o077)
    target = directory(args.directory)
    sys.path.insert(0, str(ROOT / "backend"))
    bootstrap = None
    try:
        if args.live:
            # Must precede importing fixtures: audit_fixtures also imports Settings.
            bootstrap = bootstrap_live()
        else:
            os.environ.update(
                DATABASE_URL="sqlite:///:memory:", DATA_DIR=str(target / "offline-unused"),
                MASTER_KEY="", OPENROUTER_API_KEY="", ENVIRONMENT="test",
                SYNTHETIC_AI_ENABLED="false", SYNTHETIC_PAID_PROBE="false",
                REAL_DATA_APPROVED="false", PRIVACY_EVIDENCE="", CODEX_APPROVED="false",
            )
        fixture, payload, checks = preflight()
        result = run_live(target, fixture, payload, checks, bootstrap) if args.live else {
            "case": CASE, "synthetic_only": True, "status": "offline_preflight", "model": MODEL, "upstream": UPSTREAM,
            "reasoning": "medium", "max_output_tokens": MAX_OUTPUT_TOKENS, "checks": checks,
            "network_calls": 0, "budget_cap_micros_usd": CAP_MICROS, "reservation_micros_usd": RESERVATION_MICROS,
            "source_sha256": source_hashes(), "source_hash_stage": "offline_preflight_only",
        }
        private_json(target / "scene-evaluation-summary.json", result)
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    finally:
        if bootstrap is not None:
            bootstrap["lock"].close()


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Never print provider bodies, local credentials, source text or traceback.
        print(json.dumps({"case": CASE, "status": "blocked", "error_type": type(error).__name__}))
        raise SystemExit(1) from None
