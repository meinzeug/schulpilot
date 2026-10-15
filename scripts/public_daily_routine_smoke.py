"""Public background acceptance, using one existing regular artificial family.

Run only after deployment approval:
    .venv/bin/python scripts/public_daily_routine_smoke.py --run-live

Default/--check-only performs LOCAL validation only. This never creates/deletes
accounts, changes preferences/limits, starts units, submits answers or retries a
failed provider call. Exactly two OCR jobs and one package job are permitted.
The child HTTP client is closed (without logout) during both background waits;
only the authorized parent reads server progress. Credentials/content are never
printed. An interrupted run is retained for explicit operator inspection, never
silently restarted. The same family remains available for browser/Android/tutor.
"""

import argparse
import hashlib
import json
import os
import re
import stat
import time
import unicodedata
import uuid
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

import httpx
from PIL import Image
from public_live_ai_smoke import BASE, HEADERS

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = ROOT / "artifacts/.school-day-qa-account.json"
REPORT = ROOT / "artifacts/daily-public-background-result.json"
TIMEOUT_SECONDS = 600
EXPECTED_LINES = (
    ("Brüche kürzen", "Zähler und Nenner durch dieselbe Zahl teilen."),
    ("Brüche erweitern", "Zähler und Nenner mit derselben Zahl multiplizieren.", "Der Wert des Bruchs bleibt gleich."),
)
EXPECTED_EQUATIONS = (("3/9=1/3", "6/12=1/2"), ("2/3=4/6",))
NEUTRAL_MESSAGES = {
    "Deine Heftseiten sind erkannt. Bitte schau sie dir an.",
    "Dein Lernpaket ist bereit. Starte, wenn es für dich passt.",
}


class SmokeFailure(Exception):
    """Only static error codes, never server bodies/private response values."""


def check(value, code):
    if not value:
        raise SmokeFailure(code)


def response_json(response, allowed=(200,)):
    check(response.status_code in allowed, "http_status_" + str(response.status_code))
    try:
        return response.json()
    except ValueError:
        raise SmokeFailure("response_was_not_json") from None


def save_json(path, data, *, private=False):
    temporary = path.with_name(path.name + ".tmp-" + uuid.uuid4().hex)
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600 if private else 0o644)
    try:
        with os.fdopen(descriptor, "w") as stream:
            json.dump(data, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def canonical(text):
    value = unicodedata.normalize("NFKD", text).casefold()
    return "".join(c for c in value if c.isalnum())


def formula_text(text):
    value = unicodedata.normalize("NFKC", text).replace("⁄", "/")
    value = re.sub(r"\\(?:dfrac|tfrac|frac)\s*\{(\d+)\}\s*\{(\d+)\}", r"\1/\2", value)
    return value


def local_account():
    check(PRIVATE.is_file() and not PRIVATE.is_symlink(), "private_regular_account_missing")
    check(stat.S_IMODE(PRIVATE.stat().st_mode) == 0o600, "private_account_permissions_must_be_0600")
    data = json.loads(PRIVATE.read_text())
    check(data.get("normal_account") is True and data.get("verified") is True, "verified_regular_account_required")
    check(not data.get("daily_background_smoke"), "previous_run_exists_inspect_without_replaying")
    credentials = data.get("credentials", {})
    check(
        all(
            isinstance(credentials.get(key), str) and credentials[key]
            for key in (
                "parent_username",
                "parent_password",
                "child_username",
                "child_password",
            )
        ),
        "private_credentials_incomplete",
    )
    check(
        re.search(r"\+schulpilot-normal-qa-[a-f0-9]{12}@(gmail\.com|googlemail\.com)$", credentials["parent_username"]),
        "own_artificial_gmail_alias_required",
    )
    families = data.get("user", {}).get("families", [])
    check(len(families) == 1 and families[0].get("synthetic") is False, "one_regular_family_required")
    check(bool(data.get("child_id")), "own_child_missing")
    paths = data.get("upload_paths") or data.get("image_paths", [])
    check(len(paths) == 2, "exactly_two_artificial_images_required")
    paths = [Path(path).resolve() for path in paths]
    expected = [ROOT / f"artifacts/normal-school-page-{number}.jpg" for number in (1, 2)]
    check(paths == [path.resolve() for path in expected], "only_known_original_artificial_pages_allowed")
    hashes = []
    for path in paths:
        check(path.is_file() and path.stat().st_size <= 10 * 1024 * 1024, "artificial_image_missing_or_too_large")
        with Image.open(path) as image:
            check(image.format == "JPEG" and image.size == (1400, 900), "unexpected_artificial_image")
            image.verify()
        hashes.append(hashlib.sha256(path.read_bytes()).hexdigest())
    check(hashes[0] != hashes[1], "two_distinct_artificial_pages_required")
    return data, paths


def login(client, credentials, role):
    result = response_json(
        client.post(
            "/auth/login",
            json={
                "username": credentials[role + "_username"],
                "password": credentials[role + "_password"],
            },
        )
    )
    check(result.get("user", {}).get("role") == ("child" if role == "child" else "parent"), "wrong_login_role")
    client.headers["Authorization"] = "Bearer " + result["token"]
    return result


def client(token=None):
    headers = dict(HEADERS)
    if token:
        headers["Authorization"] = "Bearer " + token
    return httpx.Client(base_url=BASE, headers=headers, timeout=30, follow_redirects=False)


def checkpoint(account, report, phase, **values):
    account["daily_background_smoke"].update(phase=phase, **values)
    report["phase"] = phase
    save_json(PRIVATE, account, private=True)
    save_json(REPORT, report)
    print(json.dumps({"daily_background_phase": phase}), flush=True)


def queue_once(child, day_id, key):
    route = f"/school-days/{day_id}/prepare"
    first = response_json(child.post(route, headers={"Idempotency-Key": key}), (200, 202))["preparation"]
    check(first.get("status") == "processing" and first.get("job"), "preparation_not_queued_no_retry")
    # One intentional same-key transport replay, never a new inference attempt.
    replay = response_json(child.post(route, headers={"Idempotency-Key": key}), (200, 202))["preparation"]
    replay_job = replay.get("job") or {}
    check(
        replay_job.get("id") == first["job"]["id"]
        or (first.get("phase") == "extract" and replay.get("completed_pages", 0) > first.get("completed_pages", 0)),
        "transport_replay_did_not_deduplicate",
    )
    return first


def wait_with_parent(parent, day_id, target):
    start = time.monotonic()
    deadline, polls, observed = start + TIMEOUT_SECONDS, 0, set()
    while time.monotonic() < deadline:
        day = response_json(parent.get(f"/school-days/{day_id}"))
        polls += 1
        preparation = day.get("preparation", {})
        state = preparation.get("status")
        observed.add(str(state))
        if state == target:
            return day, {
                "parent_polls": polls,
                "seconds": round(time.monotonic() - start, 2),
                "states": sorted(observed),
                "child_requests_during_wait": 0,
            }
        check(
            state not in ("failed", "blocked", "needs_photo", "saved", "postponed"),
            "background_phase_stopped_no_provider_retry",
        )
        time.sleep(2)
    raise SmokeFailure("background_deadline_no_provider_retry")


def verify_transcript(page, index, provider):
    check(page.get("synthetic") is False and page.get("confirmed") is False, "normal_unconfirmed_source_required")
    check(page.get("status") == "review" and page.get("legibility") == "readable", "source_requires_manual_review")
    check(page.get("extraction_provider") == provider, "unexpected_ocr_provider")
    check(
        bool(page.get("extraction_model")) and page.get("subject", "").casefold() == "mathematik",
        "ocr_metadata_incomplete",
    )
    check(not page.get("uncertainties") and not page.get("homework"), "unresolved_source_or_invented_homework")
    content = page.get("content", "")
    check(
        all(canonical(line) in canonical(content) for line in EXPECTED_LINES[index]), "literal_artificial_rule_missing"
    )
    mathematics = formula_text(content)
    check(
        all(
            re.search(
                r"(?<!\d)" + r"\s*".join(re.escape(token) for token in re.findall(r"\d+|[=/]", equation)) + r"(?!\d)",
                mathematics,
            )
            for equation in EXPECTED_EQUATIONS[index]
        ),
        "artificial_equation_missing_or_changed",
    )


def verify_ledger(usage, child_id, provider):
    records = usage.get("records", [])
    check(
        usage.get("synthetic") is False and usage.get("calls_used") == 3 and len(records) == 3,
        "expected_exactly_three_recorded_calls",
    )
    check(
        Counter(record.get("function") for record in records) == {"extract": 2, "package": 1},
        "unexpected_ai_function_or_extra_call",
    )
    check(
        all(
            record.get("child_id") == child_id
            and record.get("provider") == provider
            and record.get("status") == "completed"
            for record in records
        ),
        "usage_scope_or_completion_mismatch",
    )
    unknown = [record for record in records if record.get("cost_micros_usd") is None]
    known = [record for record in records if record.get("cost_micros_usd") is not None]
    check(
        all(isinstance(record["cost_micros_usd"], int) and record["cost_micros_usd"] >= 0 for record in known),
        "invalid_recorded_cost",
    )
    known_sum = sum(record["cost_micros_usd"] for record in known)
    retained = sum(record["reserved_micros_usd"] for record in unknown)
    check(usage.get("unknown_cost_calls") == len(unknown), "unknown_costs_must_not_be_zeroed")
    check(usage.get("known_cost_micros_usd") == known_sum, "known_cost_ledger_mismatch")
    check(usage.get("encumbered_micros_usd") == retained + known_sum, "unknown_cost_reservation_not_retained")
    if provider == "openrouter":
        check(not unknown and known_sum == 0, "approved_openrouter_free_route_was_not_zero_cost")
    return {
        "calls": 3,
        "functions": {"extract": 2, "package": 1},
        "known_cost_micros_usd": known_sum,
        "unknown_cost_calls": len(unknown),
        "retained_unknown_reservation_micros_usd": retained,
        "total_cost_micros_usd": None if unknown else known_sum,
    }


def run_live(account, paths, report):
    credentials, child_id = account["credentials"], account["child_id"]
    family_id = account["user"]["families"][0]["id"]
    account["daily_background_smoke"] = {
        "started": datetime.now(timezone.utc).isoformat(),
        "phase": "validating_account",
        "passed": False,
    }
    checkpoint(account, report, "validating_account")
    with client() as parent:
        status = response_json(parent.get("/status"))
        check(status.get("real_data_enabled") and status.get("ai_available"), "approved_ai_route_unavailable")
        provider = status.get("ai_provider")
        check(provider in ("codex", "openrouter"), "unapproved_test_provider")
        if provider == "openrouter":
            check(
                status.get("ai_free_only") is True and status.get("ai_data_collection") == "deny",
                "openrouter_free_privacy_route_required",
            )
        report["provider"] = provider
        parent_login = login(parent, credentials, "parent")
        families = parent_login["user"].get("families", [])
        check(
            len(families) == 1 and families[0]["id"] == family_id and families[0].get("synthetic") is False,
            "authenticated_parent_family_mismatch",
        )
        family = response_json(parent.get(f"/families/{family_id}"))
        children = family.get("children", [])
        check(
            family.get("synthetic") is False
            and len(children) == 1
            and children[0]["id"] == child_id
            and children[0].get("username") == credentials["child_username"],
            "authenticated_own_child_mismatch",
        )
        baseline = response_json(parent.get(f"/families/{family_id}/usage"))
        check(baseline.get("calls_used") == 0 and not baseline.get("records"), "family_already_used_no_parallel_jobs")
        initial = response_json(parent.get(f"/children/{child_id}/overview?compact=true"))
        check(not initial.get("units") and not initial.get("school_days"), "fresh_artificial_child_required")
        checkpoint(account, report, "uploading_two_artificial_pages")
        with client() as child:
            child_login = login(child, credentials, "child")
            check(
                child_login["user"].get("child_id") == child_id and child_login["user"].get("synthetic") is False,
                "authenticated_child_user_mismatch",
            )
            child_token = child_login["token"]
            day = response_json(child.post(f"/children/{child_id}/school-day/today"), (200, 201))
            check(not day.get("pages") and not day.get("units"), "existing_day_must_not_be_modified")
            day_id = day["id"]
            account["school_day_id"] = day_id
            material_ids = []
            for path in paths:
                with path.open("rb") as image:
                    material = response_json(
                        child.post(
                            f"/children/{child_id}/materials?school_day_id={day_id}",
                            headers={"Idempotency-Key": uuid.uuid4().hex},
                            files={"file": (path.name, image, "image/jpeg")},
                        ),
                        (201,),
                    )
                check(
                    material.get("school_day_id") == day_id and material.get("synthetic") is False,
                    "uploaded_source_scope_mismatch",
                )
                material_ids.append(material["id"])
                checkpoint(account, report, "uploading_two_artificial_pages", day_id=day_id, material_ids=material_ids)
            key = uuid.uuid4().hex
            checkpoint(account, report, "submitting_ocr_once", ocr_key=key)
            queued = queue_once(child, day_id, key)
            check(queued["phase"] == "extract" and queued["total_pages"] == 2, "two_page_ocr_not_queued")
        # Closing the HTTP client is NOT logout: the authorized session remains.
        checkpoint(account, report, "child_closed_ocr_running")
        reviewed, absence = wait_with_parent(parent, day_id, "needs_review")
        report["ocr_background_absence"] = absence
        check(
            reviewed.get("confirmed_count") == 0 and not reviewed.get("units"), "ocr_must_not_confirm_or_generate_units"
        )
        pages = reviewed.get("pages", [])
        check(len(pages) == 2 and [page["id"] for page in pages] == material_ids, "source_order_or_count_changed")
        for index, page in enumerate(pages):
            verify_transcript(page, index, provider)
        ocr_usage = response_json(parent.get(f"/families/{family_id}/usage"))
        check(
            ocr_usage.get("calls_used") == 2
            and len(ocr_usage.get("records", [])) == 2
            and all(
                record.get("function") == "extract" and record.get("status") == "completed"
                for record in ocr_usage["records"]
            ),
            "expected_two_ocr_calls_before_package",
        )
        report["artificial_pages_literally_reviewed"] = 2
        checkpoint(account, report, "confirming_reviewed_sources")
        with client(child_token) as child:
            for page in pages:
                confirmed = response_json(
                    child.put(
                        f"/materials/{page['id']}/confirm",
                        json={
                            **{key: page[key] for key in ("subject", "topic", "content", "homework")},
                            "uncertainties_resolved": True,
                        },
                    )
                )
                check(
                    confirmed.get("confirmed") is True and confirmed.get("content") == page["content"],
                    "source_confirmation_changed_content",
                )
            key = uuid.uuid4().hex
            checkpoint(account, report, "submitting_package_once", package_key=key)
            queued = queue_once(child, day_id, key)
            check(queued["phase"] == "package", "confirmed_package_not_queued")
        checkpoint(account, report, "child_closed_package_running")
        finished, absence = wait_with_parent(parent, day_id, "ready")
        report["package_background_absence"] = absence
        units = finished.get("units", [])
        check(
            finished.get("stage") == "ready" and finished.get("confirmed_count") == 2 and units,
            "package_or_confirmed_sources_missing",
        )
        check(
            all(
                unit.get("status") == "not_started"
                and unit.get("completed") is None
                and unit.get("active_seconds_approx") == 0
                for unit in units
            ),
            "generated_units_must_remain_unstarted",
        )
        check(
            all(not question.get("attempts") for unit in units for question in unit.get("questions", [])),
            "background_flow_must_not_submit_answers",
        )
        check(
            all(set(unit.get("source_material_ids", [])) == set(material_ids) for unit in units),
            "unit_source_links_incomplete",
        )
        check(
            all(unit.get("provider") == provider and unit.get("model") for unit in units),
            "unit_provider_provenance_missing",
        )
        overview = response_json(parent.get(f"/children/{child_id}/overview?compact=true"))
        notices = [message for message in overview.get("messages", []) if message.get("kind") == "preparation"]
        check({message.get("body") for message in notices} == NEUTRAL_MESSAGES, "neutral_persisted_notices_missing")
        check(overview.get("day_summary", {}).get("answer_count") == 0, "parent_summary_contains_unsubmitted_answers")
        usage = response_json(parent.get(f"/families/{family_id}/usage"))
        report["usage"] = verify_ledger(usage, child_id, provider)
        report.update(
            passed=True,
            original_artificial_images=2,
            demo_api_used=False,
            child_client_closed_during_both_waits=True,
            provider_retries=0,
            prepare_transport_replays=2,
            units_not_started=len(units),
            submitted_answers=0,
            source_links_verified=True,
            neutral_in_app_notices=2,
            account_retained_for_browser_android_tutor=True,
            push_delivery_tested=False,
        )
        account["package_unit_id"] = units[0]["id"]
        checkpoint(account, report, "complete", passed=True, unit_ids=[unit["id"] for unit in units])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-live", action="store_true", help="Explicitly run the approved real HTTPS workflow")
    parser.add_argument("--check-only", action="store_true", help="Validate local private inputs; no network")
    args = parser.parse_args()
    report = {"passed": False, "phase": "local_validation", "artificial_data_only": True}
    account = None
    try:
        account, paths = local_account()
        if not args.run_live:
            print(json.dumps({"local_inputs_valid": True, "images": 2, "network_calls": 0}))
            return 0
        check(not args.check_only, "choose_run_live_or_check_only")
        run_live(account, paths, report)
        print(
            json.dumps(
                {
                    "passed": True,
                    "ai_calls": 3,
                    "submitted_answers": 0,
                    "total_cost_known": report["usage"]["total_cost_micros_usd"] is not None,
                }
            )
        )
        return 0
    except Exception as error:
        report.update(
            passed=False,
            error_code=str(error) if isinstance(error, SmokeFailure) else "unexpected_" + type(error).__name__,
            provider_retry_performed=False,
            retained_for_inspection=True,
        )
        save_json(REPORT, report)
        if account and account.get("daily_background_smoke"):
            account["daily_background_smoke"].update(passed=False, error_code=report["error_code"])
            save_json(PRIVATE, account, private=True)
        print(
            json.dumps(
                {
                    "passed": False,
                    "phase": report["phase"],
                    "error_code": report["error_code"],
                    "provider_retry_performed": False,
                }
            )
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
