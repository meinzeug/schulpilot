"""Small public synthetic concurrency/authorization smoke, no AI or mail.

Reuse the private school-day QA account to avoid additional demo registrations.
This is not a claim about production capacity or exhaustive penetration testing.
"""

import argparse
import json
import math
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import httpx

BASE = "https://schulpilot.dorfspy.de/api"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--account-file", type=Path, required=True)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--requests", type=int, default=12, help="Requests per worker")
    parser.add_argument("--output", type=Path, default=Path("artifacts/load-smoke.json"))
    args = parser.parse_args()
    if not 1 <= args.workers <= 4 or not 1 <= args.requests <= 20:
        parser.error("Bounded smoke only: workers 1..4, requests 1..20")
    demo = json.loads(args.account_file.read_text())
    headers = {"X-Schulpilot-Request": "1", "X-Client-Platform": "native"}
    with httpx.Client(base_url=BASE, headers=headers, timeout=20) as client:
        response = client.post(
            "/auth/login",
            json={"username": demo["credentials"]["child_username"], "password": demo["credentials"]["child_password"]},
        )
        response.raise_for_status()
        token = response.json()["token"]
    authorized = {**headers, "Authorization": "Bearer " + token}

    def worker(_):
        samples = []
        with httpx.Client(base_url=BASE, headers=authorized, timeout=15) as client:
            for _ in range(args.requests):
                start = time.monotonic()
                response = client.get(f"/children/{demo['child_id']}/overview")
                samples.append({"ms": round((time.monotonic() - start) * 1000, 2), "status": response.status_code})
                if response.status_code == 200:
                    assert response.json()["child"]["id"] == demo["child_id"]
                time.sleep(0.1)
        return samples

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        samples = [s for result in pool.map(worker, range(args.workers)) for s in result]
    times = sorted(s["ms"] for s in samples)
    with httpx.Client(base_url=BASE, headers=authorized, timeout=15) as child:
        assert child.get("/admin/provider").status_code == 403
        assert child.get("/children/" + uuid.uuid4().hex + "/overview").status_code == 404
    with httpx.Client(base_url=BASE, headers=headers, timeout=15) as anonymous:
        assert anonymous.get(f"/children/{demo['child_id']}/overview").status_code == 401
        body = b'{"email":"' + b"x" * 70_000 + b'"}'
        response = anonymous.post(
            "/auth/register",
            content=(body[i : i + 4096] for i in range(0, len(body), 4096)),
            headers={"Content-Type": "application/json"},
        )
        assert response.status_code == 413
    report = {
        "synthetic_only": True,
        "workers": args.workers,
        "requests": len(samples),
        "http_200": sum(s["status"] == 200 for s in samples),
        "p50_ms": times[len(times) // 2],
        "p95_ms": times[math.ceil(0.95 * len(times)) - 1],
        "max_ms": times[-1],
        "authorization_guards": ["admin_403", "unknown_child_404", "anonymous_401", "chunked_body_413"],
        "ai_calls": 0,
    }
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report))
    if report["http_200"] != len(samples):
        raise SystemExit("Concurrency smoke encountered HTTP errors")


if __name__ == "__main__":
    main()
