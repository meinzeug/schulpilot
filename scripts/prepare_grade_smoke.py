"""Prepare only our verified artificial household and original PDF fixtures."""

import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = ROOT / "artifacts/.school-day-qa-account.json"
BASE = "https://schulpilot.dorfspy.de/api"


def main():
    if not PRIVATE.exists():
        subprocess.run([sys.executable, str(ROOT / "scripts/prepare_normal_ai_smoke.py")], check=True, cwd=ROOT)
    account = json.loads(PRIVATE.read_text())
    if not (account.get("normal_account") and account.get("verified") and
            re.search(r"\+schulpilot-normal-qa-[a-f0-9]{12}@", account["credentials"]["parent_username"])):
        raise RuntimeError("Only the own regular artificial QA family is allowed")
    spec = importlib.util.spec_from_file_location("original_grade_fixture", ROOT / "backend/tests/pdf_fixture.py")
    fixture = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fixture)
    with httpx.Client(base_url=BASE, headers={"X-Schulpilot-Request": "1", "X-Client-Platform": "native"}, timeout=30) as api:
        login = api.post("/auth/login", json={"username": account["credentials"]["parent_username"],
                                            "password": account["credentials"]["parent_password"]}).raise_for_status().json()
        assert login["user"]["id"] == account["user"]["id"]
        api.headers["Authorization"] = "Bearer " + login["token"]
        path = "/children/" + account["child_id"] + "/grades"
        listing = api.get(path).raise_for_status().json()
        from datetime import date

        today = date.fromisoformat(listing["today"])
        year = today.year if today.month >= 8 else today.year - 1
        state = account.setdefault("grade_pdf_qa", {})
        if not state.get("manual_id"):
            assert not listing["items"]
            grade = api.post(path, json={"subject": "Mathe", "topic": "Künstliche Kontrollnote", "kind": "test",
                                         "value": 4, "scale": "grade_1_6", "weight": 1, "assessed_on": today.isoformat(), "note": ""},
                             headers={"Idempotency-Key": "owned-pdf-manual-grade-001"}).raise_for_status().json()
            state.update(manual_id=grade["id"], phase="prepared")
        first = [("Mathematik", 1, "other", 1, "4"), ("Mathematik", 1, "other", 2, "3"),
                 ("Englisch", 1, "classwork", 1, "2"), ("Biologie", 1, "other", 1, "3")]
        variants = {"first": first, "added": first + [("Mathematik", 1, "other", 3, "2")],
                    "changed": [(s, h, k, n, "3" if s == "Englisch" else v) for s, h, k, n, v in first] + [("Mathematik", 1, "other", 3, "2")]}
        for name, entries in variants.items():
            file = ROOT / f"artifacts/grades-synthetic-{name}.pdf"
            file.write_bytes(fixture.pdf(year, entries))
            file.chmod(0o600)
        state["school_year_start"] = year
        PRIVATE.write_text(json.dumps(account) + "\n")
        PRIVATE.chmod(0o600)
        api.post("/auth/logout").raise_for_status()
    print(json.dumps({"own_verified_artificial_family": True, "three_original_pdf_fixtures": True,
                      "preexisting_manual_grade": True, "provider_calls": 0}))


if __name__ == "__main__":
    main()
