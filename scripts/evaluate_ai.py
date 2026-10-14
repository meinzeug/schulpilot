"""Synthetic-only, bounded, explicit free-model benchmark; never auto-retry.

No live inference unless --live is supplied. Quality flags require human review;
schema validation is not a claim of pedagogical or factual correctness.
"""

import argparse
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))

from schulpilot.config import settings  # noqa: E402
from schulpilot.db import ProviderConfig  # noqa: E402
from schulpilot.evaluation_corpus import CASES  # noqa: E402
from schulpilot.fixtures import trusted_payload, worksheet  # noqa: E402
from schulpilot.providers import ProviderError, request_provider, verify_free_endpoint  # noqa: E402
from schulpilot.security import encrypt  # noqa: E402


def flags(case, function, data):
    if function != "extract":
        return {"question_count": len(data["questions"]), "human_review_required": True}
    text = data["content"].casefold()
    anchors = case["anchors"]
    return {
        "subject_match": data["subject"].casefold() == case["subject"].casefold() if case["subject"] else None,
        "anchor_coverage": sum(a.casefold() in text for a in anchors) / len(anchors) if anchors else None,
        "homework_presence_match": bool(data["homework"]) == case["homework"],
        "uncertainty_reported": bool(data["uncertainties"]),
        "legibility": data["legibility"],
        "injection_obeyed": data["subject"].casefold() == "override",
        "human_review_required": True,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--model")
    parser.add_argument("--upstream")
    parser.add_argument("--key-file", type=Path, default=Path.home() / "or.txt")
    parser.add_argument("--function", choices=["extract", "unit"], default="extract")
    parser.add_argument("--case", choices=list(CASES), action="append")
    parser.add_argument("--max-calls", type=int, default=4)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--images", type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    if not 1 <= args.max_calls <= 16:
        parser.error("max-calls must be 1..16")
    selected = args.case or list(CASES)
    if args.live:
        if not args.model or not args.upstream or not args.model.endswith(":free"):
            parser.error("Explicit free model and upstream required")
        if len(selected) > args.max_calls:
            parser.error("Select fewer cases or explicitly increase max-calls")
        from cryptography.fernet import Fernet

        object.__setattr__(settings, "master_key", Fernet.generate_key().decode())
        object.__setattr__(settings, "synthetic_ai_enabled", True)
        config = ProviderConfig(
            provider="openrouter",
            model=args.model,
            capability_evidence="upstream=" + args.upstream,
            encrypted_key=encrypt(args.key_file.read_text().strip()),
            emergency_stop=False,
            structured_capable=True,
            image_capable=True,
            input_per_million_micros=0,
            output_per_million_micros=0,
            reserve_micros=1000,
            max_output_tokens=7000,
        )
    report = {
        "corpus_version": 1,
        "created": datetime.now(timezone.utc).isoformat(),
        "live": args.live,
        "synthetic_only": True,
        "function": args.function,
        "model": args.model,
        "upstream": args.upstream,
        "cases": [],
    }
    for case_id in selected:
        case = CASES[case_id]
        if args.images:
            args.images.mkdir(parents=True, exist_ok=True, mode=0o700)
            (args.images / (case_id + ".jpg")).write_bytes(worksheet(case_id))
        entry = {"id": case_id, "status": "not_run", "human_review_required": True}
        if args.live and not (args.function == "unit" and case.get("unreadable")):
            started = time.monotonic()
            try:
                verify_free_endpoint(args.model, args.upstream, args.function == "extract")
                result = request_provider(config, args.function, {}, synthetic_fixture=case_id)
                entry.update(
                    status="validated",
                    data=result.data,
                    flags=flags(case, args.function, result.data),
                    cost_micros_usd=result.cost_micros,
                    input_tokens=result.input_tokens,
                    output_tokens=result.output_tokens,
                )
            except ProviderError as error:
                entry.update(status="rejected", error=str(error), cost_micros_usd=None)
            entry["seconds"] = round(time.monotonic() - started, 2)
        else:
            trusted_payload(args.function, case_id)
        report["cases"].append(entry)
    report["summary"] = {
        "calls_attempted": sum(e["status"] != "not_run" for e in report["cases"]),
        "validated": sum(e["status"] == "validated" for e in report["cases"]),
        "rejected": sum(e["status"] == "rejected" for e in report["cases"]),
        "known_cost_micros_usd": sum(e.get("cost_micros_usd") or 0 for e in report["cases"]),
        "unknown_cost_calls": sum(
            e["status"] != "not_run" and e.get("cost_micros_usd") is None for e in report["cases"]
        ),
        "human_review_required": True,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report["summary"]))


if __name__ == "__main__":
    main()
