"""Export and erase only the successfully exercised, owned artificial family.

Private export bytes and credentials stay in memory. Revocation is checked
with the same child session after deletion; no admin or real family is used.
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
        raise RuntimeError("Owned language export/erasure assertion failed; private checkpoint retained")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", action="store_true")
    if not parser.parse_args().run:
        print(json.dumps({"ready": True, "requires": "own successful web and native language case"}))
        return
    account = json.loads(PRIVATE.read_text())
    native = json.loads((ROOT / "artifacts/language-native-result.json").read_text())
    check(account.get("normal_account") and account.get("verified")
          and re.search(r"\+schulpilot-normal-qa-[a-f0-9]{12}@", account["credentials"]["parent_username"])
          and account["language_qa"]["phase"] == "passed_keep_for_native"
          and native.get("cross_device_context_resume") and native.get("cold_resume"))
    child_id = account["child_id"]
    with httpx.Client(base_url=BASE, headers=HEADERS, timeout=60) as parent, httpx.Client(base_url=BASE, headers=HEADERS, timeout=30) as child:
        for client, role in ((parent, "parent"), (child, "child")):
            response = client.post("/auth/login", json={
                "username": account["credentials"][role + "_username"],
                "password": account["credentials"][role + "_password"], "device": "Owned language export QA"})
            check(response.status_code == 200)
            login = response.json()
            check(login["user"]["role"] == role)
            if role == "parent":
                check(login["user"]["id"] == account["user"]["id"] and len(login["user"]["families"]) == 1)
                check(login["user"]["families"][0]["id"] == account["user"]["families"][0]["id"])
            else:
                check(login["user"]["child_id"] == child_id)
            client.headers["Authorization"] = "Bearer " + login["token"]
        path = f"/children/{child_id}/learning-progress"
        parent_progress = parent.get(path).raise_for_status().json()
        check(parent_progress == child.get(path).raise_for_status().json())
        check(parent_progress["totals"]["practiced_tasks"] == 3 + native["completed_context_tasks"])
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
        check(counts["vocabulary_items"] == 5 and counts["vocabulary_review_events"] == 5)
        check({row["attempt_id"] for row in data["vocabulary_review_events"]} == {row["id"] for row in data["attempts"]})
        check(all(row["evaluation"] and row["request_key"] for row in data["attempts"]))
        failures = len(account["language_qa"].get("failed_context_ids", []))
        check(len(exported["usage"]) == 5 + failures and counts["language_projects"] == 3 + failures)
        response = parent.request("DELETE", "/account", json={"password": account["credentials"]["parent_password"]})
        check(response.status_code == 200)
        check(child.get(f"/children/{child_id}/vocabulary").status_code == 401)
        check(parent.get(f"/families/{family_id}/export").status_code == 401)
        PRIVATE.unlink()
        report = {"own_family_export": True, "exported_private_rows": counts, "saved_attempts": 5,
                  "parent_child_progress_equal": True, "own_household_deleted": True,
                  "old_child_and_parent_sessions_rejected": True, "private_credentials_file_removed": True}
        (ROOT / "artifacts/language-erasure-result.json").write_text(json.dumps(report) + "\n")
        print(json.dumps(report))


if __name__ == "__main__":
    main()
