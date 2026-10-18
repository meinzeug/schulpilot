"""Check export/progress and erase only our exercised artificial exam family."""

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
        raise RuntimeError("Owned exam export/erasure check failed; protected checkpoint retained")


def main():
    account = json.loads(PRIVATE.read_text())
    native = json.loads((ROOT / "artifacts/workshop-exam-native-result.json").read_text())
    check(account.get("normal_account") and account.get("verified")
          and re.search(r"\+schulpilot-normal-qa-[a-f0-9]{12}@", account["credentials"]["parent_username"])
          and account.get("workshop_exam_qa", {}).get("phase") == "native_passed" and native.get("success"))
    with httpx.Client(base_url=BASE, headers=HEADERS, timeout=60) as parent, httpx.Client(base_url=BASE, headers=HEADERS, timeout=30) as child:
        for client, role in ((parent, "parent"), (child, "child")):
            response = client.post("/auth/login", json={"username": account["credentials"][role + "_username"],
                                                       "password": account["credentials"][role + "_password"]})
            check(response.status_code == 200)
            identity = response.json()
            check(identity["user"]["id"] == account["user"]["id"] if role == "parent" else identity["user"]["child_id"] == account["child_id"])
            client.headers["Authorization"] = "Bearer " + identity["token"]
        path = "/children/" + account["child_id"] + "/learning-progress"
        progress = parent.get(path).raise_for_status().json()
        check(progress == child.get(path).raise_for_status().json())
        check(progress["totals"]["practiced_tasks"] == native["total_questions"])
        family_id = account["user"]["families"][0]["id"]
        response = parent.get(f"/families/{family_id}/export")
        check(response.status_code == 200)
        with zipfile.ZipFile(io.BytesIO(response.content)) as archive:
            exported = json.loads(archive.read("family.json"))
        check(len(exported["children"]) == 1 and exported["children"][0]["child"]["id"] == account["child_id"])
        data = exported["children"][0]
        check(len(data["vocabulary_items"]) == 10 and len(data["vocabulary_imports"]) == 1)
        check(len(data["language_projects"]) == 1 and len(exported["usage"]) == 1)
        check(len(data["attempts"]) == native["total_questions"])
        check({r["attempt_id"] for r in data["vocabulary_review_events"]} == {r["id"] for r in data["attempts"]})
        check(parent.request("DELETE", "/account", json={"password": account["credentials"]["parent_password"]}).status_code == 200)
        check(child.get(path).status_code == 401 and parent.get(f"/families/{family_id}/export").status_code == 401)
        PRIVATE.unlink()
        report = {"success": True, "own_family_deleted": True, "old_sessions_rejected": True,
                  "private_credentials_removed": True, "exported_words": 10, "project_and_usage": 1,
                  "attempts_and_review_events": native["total_questions"], "parent_child_progress_equal": True}
        (ROOT / "artifacts/workshop-exam-erasure-result.json").write_text(json.dumps(report) + "\n")
        print(json.dumps(report))


if __name__ == "__main__":
    main()
