"""Export and erase only our successfully exercised artificial photo household.

Private export/credentials stay in memory. Check existing parent/child
sessions are rejected after erasure; never use an administrative content read.
"""

import argparse
import io
import json
import re
import zipfile
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = ROOT / "artifacts/.school-day-qa-account.json"
BASE = "https://schulpilot.dorfspy.de/api"
HEADERS = {"X-Schulpilot-Request": "1", "X-Client-Platform": "native", "X-Schulpilot-Capabilities": "language-v1"}


def check(value):
    if not value:
        raise RuntimeError("Owned photo-word export/erasure assertion failed; private checkpoint retained")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", action="store_true")
    if not parser.parse_args().run:
        print(json.dumps({"ready": True, "requires": "own successful public photo-word and native cases"}))
        return
    account = json.loads(PRIVATE.read_text())
    web = json.loads((ROOT / "artifacts/material-words-web-result.json").read_text())
    native = json.loads((ROOT / "artifacts/material-words-android-result.json").read_text())
    check(account.get("normal_account") and account.get("verified")
          and re.search(r"\+schulpilot-normal-qa-[a-f0-9]{12}@", account["credentials"]["parent_username"])
          and account["material_words_qa"]["phase"] == "native_passed" and web.get("success") and native.get("success"))
    child_id = account["child_id"]
    with httpx.Client(base_url=BASE, headers=HEADERS, timeout=60) as parent, httpx.Client(base_url=BASE, headers=HEADERS, timeout=30) as child:
        for client, role in ((parent, "parent"), (child, "child")):
            response = client.post("/auth/login", json={
                "username": account["credentials"][role + "_username"],
                "password": account["credentials"][role + "_password"], "device": "Owned photo-word erasure QA"})
            check(response.status_code == 200)
            login = response.json()
            check(login["user"]["id"] == account["user"]["id"] if role == "parent" else login["user"]["child_id"] == child_id)
            client.headers["Authorization"] = "Bearer " + login["token"]
        path = f"/children/{child_id}/learning-progress"
        progress = parent.get(path).raise_for_status().json()
        check(progress == child.get(path).raise_for_status().json())
        check(progress["totals"]["practiced_tasks"] == 6)
        family_id = account["user"]["families"][0]["id"]
        response = parent.get(f"/families/{family_id}/export")
        check(response.status_code == 200)
        with zipfile.ZipFile(io.BytesIO(response.content)) as archive:
            exported = json.loads(archive.read("family.json"))
        check(len(exported["children"]) == 1 and exported["children"][0]["child"]["id"] == child_id)
        data = exported["children"][0]
        tables = ["vocabulary_collections", "vocabulary_items", "vocabulary_memberships", "vocabulary_reviews",
                  "vocabulary_review_events", "vocabulary_imports", "vocabulary_actions", "language_projects"]
        counts = {table: len(data[table]) for table in tables}
        check(counts["vocabulary_items"] == 5 and counts["vocabulary_imports"] == 1 and counts["vocabulary_review_events"] == 6)
        check({r["attempt_id"] for r in data["vocabulary_review_events"]} == {r["id"] for r in data["attempts"]})
        check(len(exported["usage"]) == 1 and len(data["materials"]) == 1)
        check(parent.request("DELETE", "/account", json={"password": account["credentials"]["parent_password"]}).status_code == 200)
        check(child.get(f"/children/{child_id}/vocabulary").status_code == 401)
        check(parent.get(f"/families/{family_id}/export").status_code == 401)
        PRIVATE.unlink()
        report = {"own_family_export": True, "exported_private_rows": counts, "saved_attempts": 6,
                  "parent_child_progress_equal": True, "own_household_deleted": True,
                  "old_child_and_parent_sessions_rejected": True, "private_credentials_file_removed": True}
        (ROOT / "artifacts/material-words-erasure-result.json").write_text(json.dumps(report) + "\n")
        print(json.dumps(report))


if __name__ == "__main__":
    main()
