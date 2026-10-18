"""Export and erase exactly our successfully tested artificial catalog family."""

import hashlib
import io
import json
import re
import zipfile
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = ROOT / "artifacts/.school-day-qa-account.json"
BASE = "https://schulpilot.dorfspy.de/api"


def require(value):
    if not value:
        raise RuntimeError("Owned catalog export/erasure failed; checkpoint retained")


def main():
    account = json.loads(PRIVATE.read_text())
    require(account.get("normal_account") and account.get("verified") and
            account.get("catalog_qa", {}).get("phase") == "native_passed" and
            re.search(r"\+schulpilot-normal-qa-[a-f0-9]{12}@", account["credentials"]["parent_username"]))
    expected = hashlib.sha256(account["child_id"].encode()).hexdigest()
    for name in ("web", "native"):
        report = json.loads((ROOT / f"artifacts/catalog-{name}-result.json").read_text())
        require(report.get("success") and report.get("dataset_key") == expected)
    headers = {"X-Schulpilot-Request": "1", "X-Client-Platform": "native"}
    with httpx.Client(base_url=BASE, headers=headers, timeout=60) as parent, httpx.Client(base_url=BASE, headers=headers, timeout=30) as child:
        for role, client in (("parent", parent), ("child", child)):
            signed = client.post("/auth/login", json={"username": account["credentials"][role + "_username"],
                                                      "password": account["credentials"][role + "_password"]}).raise_for_status().json()
            require(signed["user"]["id"] == account["user"]["id"] if role == "parent" else signed["user"]["child_id"] == account["child_id"])
            client.headers["Authorization"] = "Bearer " + signed["token"]
        family_id = account["user"]["families"][0]["id"]
        exported = parent.get(f"/families/{family_id}/export").raise_for_status()
        with zipfile.ZipFile(io.BytesIO(exported.content)) as archive:
            data = json.loads(archive.read("family.json"))
        own = data["children"][0]
        require(own["child"]["id"] == account["child_id"] and len(own["materials"]) == 2)
        require(not own["attempts"] and not own["school_grades"] and len(data["usage"]) == 4)
        require(len(own["learning_tip_contexts"]) >= 4 and len(own["learning_tip_interactions"]) >= 2)
        require(len(own["learning_units"]) == 1 and len(own["tutor_turns"]) == 1)
        for row in own["materials"]:
            require(parent.get("/materials/" + row["id"] + "/image").status_code == 200)
        old_photo = own["materials"][0]["id"]
        old_tip = "/children/" + account["child_id"] + "/learning-tips/material/" + old_photo
        require(parent.request("DELETE", "/account", json={"password": account["credentials"]["parent_password"]}).status_code == 200)
        require(parent.get(old_tip).status_code == 401)
        require(child.get("/materials/" + old_photo + "/image").status_code == 401)
        PRIVATE.unlink()
        report = {"success": True, "exported_materials": 2, "actual_reserved_ai_usage_rows": 4,
                  "exported_tip_contexts": len(own["learning_tip_contexts"]),
                  "exported_tip_interactions": len(own["learning_tip_interactions"]),
                  "invented_attempts": 0, "private_sources_readable_before_delete": True,
                  "own_family_deleted": True, "old_sessions_rejected": True, "private_credentials_removed": True}
        (ROOT / "artifacts/catalog-erasure-result.json").write_text(json.dumps(report) + "\n")
        print(json.dumps(report))


if __name__ == "__main__":
    main()
