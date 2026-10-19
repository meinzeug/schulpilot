"""Public PDF regression in our isolated artificial family. Never reads real PDFs."""

import argparse
import json
import sys
from datetime import date
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend/tests"))
from pdf_fixture import pdf  # noqa: E402


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--expect-status", type=int, default=201)
    args = parser.parse_args()
    fixture = json.loads((ROOT / "artifacts/.design-qa-account.json").read_text())
    credentials = fixture["credentials"]
    report = {"synthetic_family_only": True, "external_ai_calls": 0}
    headers = {"X-Schulpilot-Request": "1", "X-Client-Platform": "native"}
    with httpx.Client(base_url="https://schulpilot.dorfspy.de/api", headers=headers, timeout=35) as api:
        login = api.post("/auth/login", json={"username": credentials["parent_username"], "password": credentials["parent_password"]})
        assert login.status_code == 200, "own_parent_login_failed"
        data = login.json()
        assert data["user"]["families"] and all(f["synthetic"] for f in data["user"]["families"])
        api.headers["Authorization"] = "Bearer " + data["token"]
        try:
            year = date.today().year - (date.today().month < 8)
            raw = pdf(year, padding_bytes=240 * 1024)
            route = "/children/" + fixture["child_id"] + "/grade-imports"

            def upload(key):
                return api.post(route, files={"file": ("synthetic.pdf", raw, "application/pdf")}, headers={"Idempotency-Key": key})

            response = upload("practice-grade-smoke-v1")
            report.update(upload_status=response.status_code, pdf_bytes=len(raw))
            assert response.status_code == args.expect_status, "unexpected_pdf_upload_status"
            if response.status_code == 201:
                preview = response.json()
                assert len(preview["items"]) == 3 and preview["counts"]["new"] == 3
                assert upload("practice-grade-smoke-v1").json()["id"] == preview["id"]

                def confirm(batch):
                    return api.post(route + "/" + batch["id"] + "/confirm", json={
                        "school_year_start": year, "context_revision": batch["context_revision"],
                        "choices": [{"slot_key": row["slot_key"], "action": "add" if row["status"] == "new" else "keep"} for row in batch["items"]],
                    })

                applied = confirm(preview)
                assert applied.status_code == 200 and applied.json()["added"] == 3
                repeated = upload("practice-grade-smoke-v2")
                assert repeated.status_code == 201 and repeated.json()["counts"]["existing"] == 3
                applied_again = confirm(repeated.json())
                assert applied_again.status_code == 200 and applied_again.json()["unchanged"] == 3
                report.update(added=3, duplicate_grades=0, existing_on_reimport=3)
            report["success"] = True
        finally:
            api.post("/auth/logout")
    print(json.dumps(report))
    destination = ROOT / f"artifacts/practice-grade-public-{args.expect_status}.json"
    destination.write_text(json.dumps(report) + "\n")
    destination.chmod(0o600)


if __name__ == "__main__":
    main()
