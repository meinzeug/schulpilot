"""Explicit synthetic, free-only inference. Does not enable real-data processing.

Reads the authorized key file into memory; never prints it or provider errors.
The selected model/upstream are arguments, so there is no silent fallback.
"""

import argparse
import base64
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
import httpx  # noqa: E402
from schulpilot.fixtures import trusted_payload, worksheet  # noqa: E402
from schulpilot.providers import strict_schema, system_text  # noqa: E402
from schulpilot.schemas import ExtractionOutput, PackageOutput, UnitOutput  # noqa: E402


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--upstream", required=True)
    parser.add_argument("--key-file", type=Path, default=Path.home() / "or.txt")
    parser.add_argument("--function", choices=["extract", "unit", "package"], default="extract")
    parser.add_argument("--strict-privacy", action="store_true", help="Probe deny + ZDR using synthetic data only")
    args = parser.parse_args()
    if not args.model.endswith(":free"):
        raise SystemExit("Only an explicitly selected :free model is permitted")
    model_type = {"extract": ExtractionOutput, "package": PackageOutput}.get(args.function, UnitOutput)
    with httpx.Client(timeout=150, follow_redirects=False) as client:
        metadata = client.get("https://openrouter.ai/api/v1/models/" + args.model + "/endpoints")
        metadata.raise_for_status()
        endpoint = next((e for e in metadata.json()["data"]["endpoints"] if e["tag"] == args.upstream), None)
        if not endpoint or any(float(endpoint["pricing"].get(k, "-1")) != 0 for k in ("prompt", "completion")):
            raise SystemExit("Selected endpoint is not verified free")
        content = [{"type": "text", "text": json.dumps(trusted_payload(args.function), ensure_ascii=False)}]
        if args.function == "extract":
            content.append(
                {
                    "type": "image_url",
                    "image_url": {"url": "data:image/jpeg;base64," + base64.b64encode(worksheet()).decode()},
                }
            )
        body = {
            "model": args.model,
            "max_tokens": 7000,
            "messages": [
                {"role": "system", "content": system_text(args.function)},
                {"role": "user", "content": content},
            ],
            "provider": {
                "only": [args.upstream],
                "allow_fallbacks": False,
                "require_parameters": True,
                "data_collection": "deny" if args.strict_privacy else "allow",
                "zdr": args.strict_privacy,
                "max_price": {"prompt": 0, "completion": 0, "request": 0},
            },
            "response_format": {
                "type": "json_schema",
                "json_schema": {"name": "schulpilot", "strict": True, "schema": strict_schema(model_type)},
            },
            "reasoning": {"enabled": False},
        }
        response = client.post(
            "https://openrouter.ai/api/v1/chat/completions",
            headers={"Authorization": "Bearer " + args.key_file.read_text().strip()},
            json=body,
        )
        report = {
            "model": args.model,
            "upstream": args.upstream,
            "function": args.function,
            "http_status": response.status_code,
            "synthetic_only": True,
            "strict_privacy": args.strict_privacy,
        }
        if response.status_code != 200:
            try:
                err = response.json().get("error", {})
                report["error_code"] = err.get("code")
                # Report only a short routing reason, never arbitrary upstream text.
                if "No endpoints" in str(err.get("message", "")):
                    report["reason"] = "No endpoints found matching routing requirements"
            except ValueError:
                pass
            print(json.dumps(report))
            raise SystemExit(1)
        raw = response.json()
        try:
            choice = raw["choices"][0]
            report["finish_reason"] = choice.get("finish_reason")
            if choice.get("finish_reason") != "stop":
                raise ValueError("incomplete")
            output = model_type.model_validate_json(choice["message"]["content"])
        except (ValueError, KeyError, TypeError, IndexError) as error:
            report["validated"] = False
            if hasattr(error, "errors"):
                report["validation_errors"] = [{"location": e["loc"], "message": e["msg"]} for e in error.errors()]
            report["synthetic_output"] = raw.get("choices", [{}])[0].get("message", {}).get("content", "")[:6000]
            report["usage"] = raw.get("usage", {})
            print(json.dumps(report))
            raise SystemExit(1)
        report["validated"] = True
        report["usage"] = raw.get("usage", {})
        report["data"] = output.model_dump()
        print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
