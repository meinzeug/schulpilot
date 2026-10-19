"""Export and erase only this report review's successfully exercised QA family.

Credentials and exported learning contents stay in memory. No real family can
pass the own-account, identity, checkpoint, and exact fixture-count guards.
"""

import io
import json
import re
import zipfile
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = ROOT / "artifacts/.school-day-qa-account.json"
BASE = "https://schulpilot.dorfspy.de/api"


def require(value, label):
    if not value:
        raise RuntimeError(label + "; owned checkpoint retained")


def main():
    account = json.loads(PRIVATE.read_text())
    state = account.get("report_qa", {})
    require(
        account.get("normal_account")
        and account.get("verified")
        and re.search(r"\+schulpilot-normal-qa-[a-f0-9]{12}@", account["credentials"]["parent_username"])
        and state.get("phase") == "native_passed",
        "owned_successful_report_smoke_required",
    )
    evidence = {}
    for platform in ("web", "native"):
        evidence[platform] = json.loads((ROOT / f"artifacts/report-review-{platform}-result.json").read_text())
        require(evidence[platform].get("success"), "both_platforms_must_have_passed")
    web = evidence["web"]
    native = evidence["native"]
    expected_usage = sum(web[k] for k in ("actual_ocr_jobs", "actual_package_jobs", "actual_tutor_jobs"))
    expected_usage += native["actual_coach_jobs"]
    expected_attempts = set(state["native_answer_ids"])
    require(len(expected_attempts) == state["question_count"] == native["real_saved_attempts"], "fixture_answers_required")
    require(len(state["materials"]) == 3 and state["assignments"] == 1, "exact_artificial_fixture_required")
    headers = {"X-Schulpilot-Request": "1", "X-Client-Platform": "native", "X-Schulpilot-Capabilities": "language-v1"}
    with (
        httpx.Client(base_url=BASE, headers=headers, timeout=60) as parent,
        httpx.Client(base_url=BASE, headers=headers, timeout=35) as child,
    ):
        for role, client in (("parent", parent), ("child", child)):
            signed = client.post(
                "/auth/login",
                json={
                    "username": account["credentials"][role + "_username"],
                    "password": account["credentials"][role + "_password"],
                },
            ).raise_for_status().json()
            require(
                signed["user"]["id"] == account["user"]["id"]
                if role == "parent" else signed["user"]["child_id"] == account["child_id"],
                "matching_own_identity_required",
            )
            client.headers["Authorization"] = "Bearer " + signed["token"]
        family_id = account["user"]["families"][0]["id"]
        before = parent.get(f"/children/{account['child_id']}/overview?compact=true").raise_for_status().json()
        exported = parent.get(f"/families/{family_id}/export").raise_for_status()
        with zipfile.ZipFile(io.BytesIO(exported.content)) as archive:
            data = json.loads(archive.read("family.json"))
            require(len(data["children"]) == 1, "only_own_child_required")
            own = data["children"][0]
            require(own["child"]["id"] == account["child_id"], "owned_export_required")
            require(len(own["materials"]) == 3 and len(own["learning_units"]) == 2, "exact_sources_and_rounds_required")
            require(len(own["assignments"]) == 1 and own["assignments"][0]["mandatory"], "deduplicated_homework_required")
            require(sum(bool(m["task_decisions"]) for m in own["materials"]) >= 2, "saved_source_decisions_required")
            require({a["id"] for a in own["attempts"]} == expected_attempts, "exact_saved_answer_history_required")
            require(all(a["outcome"] == "correct" and not a["assisted"] for a in own["attempts"]), "consistent_verdicts_required")
            require("attempt_assessments" in own and not own["attempt_assessments"], "audit_export_required")
            require(not own["school_grades"] and len(own["tutor_turns"]) == web["actual_tutor_jobs"], "exact_tutor_fixture_required")
            require(len(data["usage"]) == expected_usage, "all_actual_model_calls_must_be_accounted")
            require(all(u["child_id"] == account["child_id"] for u in data["usage"]), "owned_usage_required")
            require(len([name for name in archive.namelist() if name.startswith("materials/")]) == 3, "all_photo_files_exported")
        after = parent.get(f"/children/{account['child_id']}/overview?compact=true").raise_for_status().json()
        require(before["plan"]["daily_active_seconds"] == after["plan"]["daily_active_seconds"], "parent_export_must_not_create_child_time")
        old_photo = own["materials"][0]["id"]
        require(parent.get(f"/materials/{old_photo}/image").status_code == 200, "private_photo_readable_before_deletion")
        require(
            parent.request("DELETE", "/account", json={"password": account["credentials"]["parent_password"]}).status_code == 200,
            "normal_own_account_deletion_required",
        )
        require(parent.get(f"/children/{account['child_id']}/overview?compact=true").status_code == 401, "parent_session_must_be_revoked")
        require(child.get(f"/materials/{old_photo}/image").status_code == 401, "child_session_must_be_revoked")
        PRIVATE.unlink()
        result = {
            "success": True,
            "exported_materials": len(own["materials"]),
            "exported_rounds": len(own["learning_units"]),
            "exported_attempts": len(own["attempts"]),
            "exported_homework": len(own["assignments"]),
            "actual_model_usage_rows": len(data["usage"]),
            "unknown_cost_rows": sum(u["cost_micros"] is None for u in data["usage"]),
            "assessment_audit_and_source_decisions_exported": True,
            "parent_read_and_export_added_no_child_time": True,
            "own_family_deleted": True,
            "both_old_sessions_rejected": True,
            "private_credentials_removed": True,
        }
        report = ROOT / "artifacts/report-review-erasure-result.json"
        report.write_text(json.dumps(result) + "\n")
        report.chmod(0o600)
        print(json.dumps(result))


if __name__ == "__main__":
    main()
