"""Exactly one real notebook question on our own regular artificial QA family.

Run only after the background tester has explicitly handed over the account.
No generated pages, responses or credentials are printed. Never retries a POST.
"""

import json
import os
import re
import secrets
import time
import unicodedata
from pathlib import Path

import httpx
from public_live_ai_smoke import BASE, HEADERS, expect

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = ROOT / "artifacts/.school-day-qa-account.json"
REPORT = ROOT / "artifacts/codex-tutor-live.json"
QUESTION = "Warum bleibt der Wert eines Bruchs beim Erweitern gleich?"


def save(data):
    temporary = PRIVATE.with_suffix(".tutor-new")
    with os.fdopen(os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as stream:
        json.dump(data, stream)
        stream.write("\n")
    temporary.replace(PRIVATE)


def normalize(value):
    return " ".join(unicodedata.normalize("NFC", value).split())


def session(client, credentials, role):
    result = expect(client.post("/auth/login", json={
        "username": credentials[role + "_username"], "password": credentials[role + "_password"],
    }))
    if result["user"]["role"] != role:
        raise RuntimeError("Unexpected QA account role")
    client.headers["Authorization"] = "Bearer " + result["token"]


def history(client, child_id, day_id):
    return expect(client.get(f"/children/{child_id}/tutor/questions", params={"day_id": day_id}))["questions"]


def main():
    if PRIVATE.is_symlink() or PRIVATE.stat().st_mode & 0o777 != 0o600:
        raise RuntimeError("The private QA fixture must be a regular protected file")
    data = json.loads(PRIVATE.read_text())
    credentials = data["credentials"]
    address = credentials["parent_username"]
    if not data.get("normal_account") or not data.get("verified") or not re.search(
        r"\+schulpilot-normal-qa-[a-f0-9]{12}@", address
    ):
        raise RuntimeError("Only this script family's original regular artificial QA account is allowed")
    background = data.get("daily_background_smoke", {})
    if not background.get("passed") or background.get("phase") != "complete":
        raise RuntimeError("The background tester has not completed and handed over the fixture")
    day_id, child_id = background["day_id"], data["child_id"]
    journal = data.setdefault("codex_tutor_qa", {"idempotency_key": secrets.token_hex(20)})
    if journal.get("passed"):
        raise RuntimeError("The one approved real question has already passed; no further inference allowed")
    save(data)
    report = {"real_provider": "codex", "actual_inference_posts": 0}
    with httpx.Client(base_url=BASE, headers=HEADERS, timeout=30, follow_redirects=False) as child:
        session(child, credentials, "child")
        try:
            day = expect(child.get("/school-days/" + day_id))
            if day["synthetic"] or day["child_id"] != child_id or any(not page["confirmed"] for page in day["pages"]):
                raise RuntimeError("Only this own fully confirmed artificial day's regular sources may be used")
            pages = {page["id"]: page for page in day["pages"]}
            if set(pages) != set(background["material_ids"]):
                raise RuntimeError("Unexpected source set; no question was sent")
            if not journal.get("turn_id"):
                if journal.get("post_started"):
                    raise RuntimeError("Previous submit outcome unknown; no automatic retry permitted")
                journal["post_started"] = True
                save(data)
                turn = expect(child.post(
                    f"/children/{child_id}/tutor/questions", json={"day_id": day_id, "question": QUESTION},
                    headers={"Idempotency-Key": journal["idempotency_key"]},
                ), 202)
                report["actual_inference_posts"] = 1
                journal.update(turn_id=turn["id"], job_id=turn["job_id"])
                save(data)
            for _ in range(65):
                matches = [turn for turn in history(child, child_id, day_id) if turn["id"] == journal["turn_id"]]
                if len(matches) != 1:
                    raise RuntimeError("Saved own question is not readable")
                turn = matches[0]
                if turn["status"] in ("ready", "failed"):
                    break
                time.sleep(3)
            else:
                raise RuntimeError("Own question timeout; no provider retry was attempted")
            if turn["status"] != "ready" or turn["source_changed"]:
                raise RuntimeError("Own real tutor answer failed or sources changed; no retry")
            reply = turn["reply"]
            if reply["kind"] != "answer" or not reply["sources"] or not reply["answer"].strip():
                raise RuntimeError("The real question did not receive a source-backed answer")
            for source in reply["sources"]:
                page = pages.get(source["material_id"])
                if not page or normalize(source["quote"]) not in normalize(page["content"]):
                    raise RuntimeError("The real reply's quotation did not match its own confirmed source")
            report.update({"child_question_saved": True, "ready": True, "literal_source_quotes_verified": True,
                           "source_quote_count": len(reply["sources"]), "answer_characters": len(reply["answer"])})
        finally:
            report["own_child_session_logged_out"] = child.post("/auth/logout").status_code == 200
    with httpx.Client(base_url=BASE, headers=HEADERS, timeout=30, follow_redirects=False) as parent:
        session(parent, credentials, "parent")
        try:
            turns = history(parent, child_id, day_id)
            parent_turn = next((turn for turn in turns if turn["id"] == journal["turn_id"]), None)
            if not parent_turn or parent_turn["status"] != "ready":
                raise RuntimeError("The authorized parent cannot read the saved own reply")
            family_id = data["user"]["families"][0]["id"]
            usage = expect(parent.get(f"/families/{family_id}/usage"))
            records = [record for record in usage["records"] if record["child_id"] == child_id and record["function"] == "tutor"]
            if len(records) != 1 or records[0]["provider"] != "codex" or records[0]["model"] != "gpt-6.1-sol":
                raise RuntimeError("Expected exactly one genuine Codex tutor usage record")
            record = records[0]
            if record["cost_micros_usd"] is not None or type(record.get("search_calls")) is not int:
                raise RuntimeError("Subscription cost must stay unknown and actual search count must be stored")
            report.update({"authorized_parent_reads_saved_reply": True, "exactly_one_usage_record": True,
                           "measured_search_calls": record["search_calls"], "cost_micros_usd": None})
        finally:
            report["own_parent_session_logged_out"] = parent.post("/auth/logout").status_code == 200
    if not report["own_child_session_logged_out"] or not report["own_parent_session_logged_out"]:
        raise RuntimeError("Own QA session logout did not succeed")
    journal.update(passed=True, source_quote_count=report["source_quote_count"])
    save(data)
    report["passed"] = True
    REPORT.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
