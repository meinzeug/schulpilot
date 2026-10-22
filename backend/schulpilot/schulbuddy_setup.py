"""Local operator selection and exactly one accounted fixed synthetic probe.

Never called by GET, modal opening or a normal chat. No credentials in args,
reports or stdout. No global provider mutation or automatic retry.
"""

import argparse
import json
from datetime import datetime, timezone
from types import SimpleNamespace

from fastapi import HTTPException
from sqlalchemy import update

from .config import runtime_settings
from .db import DB, OperatorJob, ProviderConfig, UsageBucket, now
from .providers import ProviderError, request_provider, settle
from .schulbuddy import checked_reply
from .schulbuddy_provider import accepted_probe, binding_key, configured, select_local
from .schulbuddy_schemas import synthetic_payload
from .security import audit, insert_ignore, rate_limit


def probe_once():
    with DB.begin() as db:
        config = configured(db, verify_catalog=True, probe=True)
        base_revision = db.get(ProviderConfig, 1).revision
        rate_limit(db, "schulbuddy-probe-hour", 2, 3600, commit=False)
        rate_limit(db, "synthetic-ai-global", runtime_settings().synthetic_ai_daily_limit, 86400, commit=False)
        buckets = ["global:" + datetime.now(timezone.utc).strftime("%Y-%m"), "schulbuddy-probe-20261022"]
        for name, limit in [(buckets[0], config.global_limit_micros), (buckets[1], 250000)]:
            insert_ignore(db, UsageBucket, {"id": name, "calls": 0, "encumbered_micros": 0,
                "known_cost_micros": 0, "unknown_calls": 0})
            if not db.execute(update(UsageBucket).where(UsageBucket.id == name,
                UsageBucket.encumbered_micros + config.reserve_micros <= limit).values(
                    calls=UsageBucket.calls + 1, encumbered_micros=UsageBucket.encumbered_micros + config.reserve_micros,
                    unknown_calls=UsageBucket.unknown_calls + 1)).rowcount:
                raise HTTPException(429, "Bestehendes globales oder künstliches Prüfbudget erreicht.")
        job = OperatorJob(actor="local-operator", config_revision=config.revision, status="running", started=int(now()),
            report=[{"function": "schulbuddy", "provider": "codex", "model": config.model, "reasoning_effort": "high",
                     "binding": binding_key(config), "provider_revision": base_revision, "fixture": "schulbuddy-v1", "available": False}])
        db.add(job)
        db.flush()
        identifier = job.id
        audit(db, "local-operator", "schulbuddy.probe_started", identifier)
        values = {c.name: getattr(config, c.name) for c in ProviderConfig.__table__.columns}
    result, failure = None, None
    try:
        result = request_provider(ProviderConfig(**values), "schulbuddy", {}, synthetic_fixture=True, private_probe=True)
        payload = synthetic_payload()
        reply = checked_reply(result.data, payload, [{"id": "synthetic-material", "ref": "p1", "label": "Künstliches Testblatt"}])
        if not reply["sources"]:
            raise ProviderError("Der feste Schulbuddy-Prüfauftrag enthält keinen geprüften Quellenbeleg.")
    except Exception as error:
        failure = str(error) if isinstance(error, ProviderError) else "Der feste künstliche Schulbuddy-Prüfauftrag ist fehlgeschlagen."
        result = result or getattr(error, "billing_result", None)
    with DB.begin() as db:
        job = db.get(OperatorJob, identifier)
        current = None
        try:
            current = configured(db, verify_catalog=True, probe=True)
        except (HTTPException, ProviderError):
            failure = "Die Schulbuddy-Freigabe ist nach der Prüfung nicht mehr gültig. Keine Aktivierung."
        same = current and (binding_key(current) == binding_key(config) and db.get(ProviderConfig, 1).revision == base_revision)
        if not same:
            failure = "Modellbindung oder globale Anbieterrevision während der Prüfung geändert. Keine Aktivierung."
        settle(db, SimpleNamespace(bucket_ids=buckets, reserved_micros=config.reserve_micros, provider="codex"),
               result, failed=bool(failure))
        job.status, job.finished, job.error = "failed" if failure else "completed", int(now()), failure
        job.report = [{**job.report[0], "available": failure is None,
            "cost_micros_usd": result.cost_micros if result else None,
            "cost_source": result.cost_source if result else "unknown",
            "input_tokens": result.input_tokens if result else None, "output_tokens": result.output_tokens if result else None,
            "search_calls": result.search_calls if result else None}]
        if not failure:
            accepted_probe(db, current, job)
        audit(db, "local-operator", "schulbuddy.probe_finished", identifier)
    return {"id": identifier, "status": "failed" if failure else "completed", "available": failure is None,
            "model": config.model, "reasoning_effort": "high", "cost_micros_usd": result.cost_micros if result else None,
            "notice": "Codex-Kontokosten bleiben unbekannt; bestehende Reservierung erhalten."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    choose = commands.add_parser("select")
    choose.add_argument("--model", required=True)
    choose.add_argument("--privacy-evidence", required=True)
    commands.add_parser("probe")
    args = parser.parse_args()
    try:
        if args.command == "select":
            with DB.begin() as db:
                value = select_local(db, args.model, args.privacy_evidence)
                result = {"model": value.model, "reasoning_effort": value.reasoning_effort, "available": False,
                          "next": "python -m schulpilot.schulbuddy_setup probe"}
        else:
            result = probe_once()
        print(json.dumps(result, ensure_ascii=False))
    except (HTTPException, ProviderError) as error:
        print(json.dumps({"available": False, "error": str(error.detail) if isinstance(error, HTTPException) else str(error)}))
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
