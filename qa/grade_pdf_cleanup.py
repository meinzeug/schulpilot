"""Verify new private tables/export, then erase only the exercised own QA family."""

import io
import json
import re
import zipfile
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = ROOT / "artifacts/.school-day-qa-account.json"
BASE = "https://schulpilot.dorfspy.de/api"


def require(condition):
    if not condition:
        raise RuntimeError("Own PDF export/erasure verification failed; private checkpoint retained")


def main():
    account = json.loads(PRIVATE.read_text())
    require(account.get("normal_account") and account.get("verified") and account.get("grade_pdf_qa", {}).get("phase") == "native_passed"
            and re.search(r"\+schulpilot-normal-qa-[a-f0-9]{12}@", account["credentials"]["parent_username"]))
    require(json.loads((ROOT / "artifacts/grade-pdf-native-result.json").read_text())["success"])
    headers = {"X-Schulpilot-Request": "1", "X-Client-Platform": "native"}
    with httpx.Client(base_url=BASE, headers=headers, timeout=60) as parent, httpx.Client(base_url=BASE, headers=headers, timeout=30) as child:
        for client, role in ((parent, "parent"), (child, "child")):
            result = client.post("/auth/login", json={"username": account["credentials"][role + "_username"],
                                                      "password": account["credentials"][role + "_password"]}).raise_for_status().json()
            require(result["user"]["id"] == account["user"]["id"] if role == "parent" else result["user"]["child_id"] == account["child_id"])
            client.headers["Authorization"] = "Bearer " + result["token"]
        path = "/children/" + account["child_id"]
        require(child.get(path + "/grades").status_code == 403)
        progress = parent.get(path + "/learning-progress").raise_for_status().json()
        require(progress == child.get(path + "/learning-progress").raise_for_status().json())
        require(progress["totals"]["practiced_tasks"] == 0)
        family_id = account["user"]["families"][0]["id"]
        exported = parent.get(f"/families/{family_id}/export").raise_for_status()
        with zipfile.ZipFile(io.BytesIO(exported.content)) as archive:
            data = json.loads(archive.read("family.json"))
        require(len(data["children"]) == 1 and data["children"][0]["child"]["id"] == account["child_id"])
        own = data["children"][0]
        require(len(own["school_grades"]) == len(own["grade_source_slots"]) == 5)
        require(len({s["grade_id"] for s in own["grade_source_slots"]}) == 5)
        require(len(own["grade_imports"]) >= 4 and all(r["status"] == "applied" for r in own["grade_imports"]))
        require(not data["usage"] and not own["attempts"])
        require(parent.request("DELETE", "/account", json={"password": account["credentials"]["parent_password"]}).status_code == 200)
        require(parent.get(path + "/grades").status_code == child.get(path + "/learning-progress").status_code == 401)
        PRIVATE.unlink()
        result = {"success": True, "exported_grades": 5, "unique_source_slots": 5,
                  "no_ai_usage_or_invented_practice": True, "child_cannot_read_grades": True,
                  "own_family_deleted": True, "old_sessions_rejected": True, "private_credentials_removed": True}
        (ROOT / "artifacts/grade-pdf-erasure-result.json").write_text(json.dumps(result) + "\n")
        print(json.dumps(result))


if __name__ == "__main__":
    main()
