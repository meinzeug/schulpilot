"""One resumable, artificial family and fixed four-widget unit; no external AI."""

import argparse
import json
import os
import time
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = ROOT / "artifacts/.design-qa-account.json"
HEADERS = {"X-Schulpilot-Request": "1", "X-Client-Platform": "native"}


def check(response, status=200):
    if response.status_code != status:
        raise RuntimeError("Own synthetic fixture API status " + str(response.status_code))
    return response.json()


def save(data):
    fd = os.open(PRIVATE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, "w") as target:
        json.dump(data, target)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cleanup", action="store_true")
    args = parser.parse_args()
    with httpx.Client(base_url="https://schulpilot.dorfspy.de/api", headers=HEADERS, timeout=30) as api:
        data = json.loads(PRIVATE.read_text()) if PRIVATE.exists() else None
        if args.cleanup and not data:
            return
        if data:
            login = check(api.post("/auth/login", json={
                "username": data["credentials"]["parent_username"],
                "password": data["credentials"]["parent_password"],
            }))
        else:
            login = check(api.post("/demo"), 201)
            data = {"credentials": login["credentials"], "child_id": login["child_id"], "material_id": login["material_id"]}
            save(data)
        api.headers["Authorization"] = "Bearer " + login["token"]
        if not login["user"]["families"] or not all(f["synthetic"] for f in login["user"]["families"]):
            raise RuntimeError("Only our artificial demo family is permitted")
        if args.cleanup:
            check(api.request("DELETE", "/account", json={"password": data["credentials"]["parent_password"]}))
            PRIVATE.unlink()
            print(json.dumps({"own_synthetic_family_deleted": True}))
            return
        if not data.get("job_id") and not data.get("unit_id"):
            material = check(api.get("/materials/" + data["material_id"]))
            if not material["synthetic"]:
                raise RuntimeError("Synthetic material required")
            if not material["confirmed"]:
                check(api.put("/materials/" + data["material_id"] + "/confirm", json={
                    **{key: material[key] for key in ("subject", "topic", "content", "homework")},
                    "uncertainties_resolved": True,
                }))
            # The existing demo worker takes the fixed synthetic path, not a provider.
            job = check(api.post("/children/" + data["child_id"] + "/units",
                                 headers={"Idempotency-Key": "design-fixed-unit-v1"},
                                 json={"material_id": data["material_id"]}), 202)
            data["job_id"] = job["id"]
            save(data)
        if not data.get("unit_id"):
            for _ in range(60):
                job = check(api.get("/jobs/" + data["job_id"]))
                if job["status"] == "failed":
                    raise RuntimeError("Fixed fixture failed; no automatic retry")
                if job["status"] == "completed":
                    data["unit_id"] = job["result"]["unit_id"]
                    save(data)
                    break
                time.sleep(.5)
        if not data.get("unit_id"):
            raise RuntimeError("Fixed unit is not ready; resume the stored job")
        unit = check(api.get("/units/" + data["unit_id"]))
        if unit["provider"] != "synthetic" or not unit["synthetic"] or {q["type"] for q in unit["questions"]} != {"choice", "gap", "short", "match"}:
            raise RuntimeError("Only fixed synthetic tasks are permitted")
        check(api.post("/auth/logout"))
        print(json.dumps({"synthetic_fixture_ready": True, "task_types": 4, "external_ai_calls": 0}))


if __name__ == "__main__":
    main()
