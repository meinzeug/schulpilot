"""Create exactly one isolated synthetic family for coordinated parent/child QA."""

import argparse
import json
import os
import sys
from datetime import date
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = ROOT / "artifacts/.role-simulation-account.json"
HEADERS = {"X-Schulpilot-Request": "1", "X-Client-Platform": "native"}


def prepare_pdf():
    sys.path.insert(0, str(ROOT / "backend/tests"))
    from pdf_fixture import pdf

    today = date.today()
    path = PRIVATE.parent / "role-parent-synthetic-grades.pdf"
    path.write_bytes(pdf(today.year - (today.month < 8), padding_bytes=240 * 1024))
    path.chmod(0o600)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cleanup", action="store_true")
    args = parser.parse_args()
    if args.cleanup and not PRIVATE.exists():
        print(json.dumps({"own_synthetic_family_already_absent": True}))
        return
    PRIVATE.parent.mkdir(exist_ok=True, mode=0o700)
    PRIVATE.parent.chmod(0o700)
    with httpx.Client(base_url="https://schulpilot.dorfspy.de/api", headers=HEADERS, timeout=40) as api:
        if PRIVATE.exists():
            data = json.loads(PRIVATE.read_text())
            response = api.post(
                "/auth/login",
                json={
                    "username": data["credentials"]["parent_username"],
                    "password": data["credentials"]["parent_password"],
                },
            )
            assert response.status_code == 200, "own_fixture_login_failed"
        else:
            response = api.post("/demo")
            assert response.status_code == 201, "own_fixture_create_failed"
            body = response.json()
            data = {
                "credentials": body["credentials"],
                "child_id": body["child_id"],
                "material_id": body["material_id"],
            }
            fd = os.open(PRIVATE, os.O_CREAT | os.O_WRONLY | os.O_EXCL, 0o600)
            with os.fdopen(fd, "w") as target:
                json.dump(data, target)
        login = response.json()
        assert login["user"]["role"] == "parent"
        # Parent synthetic status is carried by its memberships, not user fields.
        assert login["user"].get("synthetic", True) is True
        assert login["user"]["families"] and all(row["synthetic"] is True for row in login["user"]["families"])
        api.headers["Authorization"] = "Bearer " + login["token"]
        family = api.get("/families/" + login["user"]["families"][0]["id"])
        assert family.status_code == 200
        assert family.json()["synthetic"] is True
        assert any(child["id"] == data["child_id"] for child in family.json()["children"])
        if args.cleanup:
            removed = api.request("DELETE", "/account", json={"password": data["credentials"]["parent_password"]})
            assert removed.status_code == 200, "own_synthetic_family_cleanup_failed"
            PRIVATE.unlink()
            print(json.dumps({"own_synthetic_family_deleted": True}))
            return
        result = api.post("/auth/logout")
        assert result.status_code == 200
        PRIVATE.chmod(0o600)
        prepare_pdf()
        print(
            json.dumps(
                {
                    "fixture_ready": True,
                    "credentials_file": str(PRIVATE),
                    "only_own_synthetic_family": True,
                    "external_ai_calls": 0,
                }
            )
        )


if __name__ == "__main__":
    main()
