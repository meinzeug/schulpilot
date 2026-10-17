"""Native APK30, only the verified normal artificial browser-test household.

No installation, provider invocation, clock tampering or real-user data. This
finishes the already generated context round through Android's Flutter UI.
Credentials go to ADB stdin, never its process arguments or output.
"""

import argparse
import json
import re
import shlex
import subprocess
import time

import android_smoke as native
import httpx

PRIVATE = native.ARTIFACTS / ".school-day-qa-account.json"
HEADERS = {**native.HEADERS, "X-Schulpilot-Capabilities": "language-v1"}
PHASE = "offline"


class QaFailure(RuntimeError):
    pass


def check(value, reason):
    if not value:
        raise QaFailure(reason)


def labels():
    return "\n".join(node.get("content-desc", "") + "\n" + node.get("text", "") for node in native.nodes())


def step(value):
    global PHASE
    PHASE = value
    print(json.dumps({"native_language_phase": value}), flush=True)


def wait(fragment, seconds=35):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        current = labels()
        if "Zu viele Anfragen. Bitte später erneut versuchen." in current:
            raise QaFailure("normal_login_rate_limited_wait_for_next_window")
        if fragment in current:
            return
        time.sleep(0.4)
    raise QaFailure("expected_native_state_missing")


def press(fragment):
    for _ in range(26):
        found = native.matching(fragment)
        if found:
            clickable = [n for n in found if n.get("clickable") == "true"]
            native.tap_node((clickable or found)[-1])
            time.sleep(0.4)
            return
        native.adb("shell", "input", "swipe", "900", "1700", "900", "1300", "300")
    raise QaFailure("expected_native_action_missing")


def input_text(value):
    check(bool(re.fullmatch(r"[A-Za-z0-9_@.+ -]{1,500}", value)), "only_generated_ascii_test_input_allowed")
    command = "input text " + shlex.quote(value.replace(" ", "%s")) + "\n"
    result = subprocess.run(
        [*native.ADB, "shell"], input=command.encode(), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15
    )
    check(result.returncode == 0, "native_input_failed")


def api_get(client, path):
    response = client.get(path)
    check(response.status_code == 200, "owned_native_api_read_failed")
    return response.json()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", action="store_true")
    args = parser.parse_args()
    if not args.run:
        print(json.dumps({"ready": True, "requires": "own successful language web case and OTA to APK30"}))
        return 0
    account = json.loads(PRIVATE.read_text())
    check(
        account.get("normal_account")
        and account.get("verified")
        and re.search(r"\+schulpilot-normal-qa-[a-f0-9]{12}@", account["credentials"]["parent_username"]),
        "own_artificial_household_required",
    )
    case = account.get("language_qa", {})
    check(
        case.get("phase") in ("grammar_probe_queued", "explicit_writing_provider_probe", "writing_probe_queued", "passed_keep_for_native")
        and case.get("project_unit_id"),
        "successful_owned_web_word_and_context_case_required",
    )
    check(native.adb("emu", "avd", "name").decode().splitlines()[0] == "schulpilot-qa-api36", "dedicated_avd_required")
    package = native.adb("shell", "dumpsys", "package", native.PACKAGE).decode()
    check(bool(re.search(r"\bversionCode=30\b", package)), "ota_to_regular_apk30_required")
    child_id, unit_id = account["child_id"], case["project_unit_id"]
    with httpx.Client(base_url=native.BASE, headers=HEADERS, timeout=30) as api:
        credentials = account["credentials"]
        response = api.post(
            "/auth/login",
            json={
                "username": credentials["child_username"],
                "password": credentials["child_password"],
                "device": "Owned native language QA observer",
            },
        )
        check(
            response.status_code == 200 and response.json()["user"]["child_id"] == child_id,
            "own_observer_identity_failed",
        )
        api.headers["Authorization"] = "Bearer " + response.json()["token"]
        words = api_get(api, f"/children/{child_id}/vocabulary?page_size=50")
        dictionary = {word["id"]: word["word"] for word in words["items"]}
        unit = api_get(api, "/units/" + unit_id)
        check(unit["status"] in ("not_started", "active", "paused", "completed"), "stored_context_unit_required")
        step("native_child_login")
        native.adb("shell", "am", "force-stop", native.PACKAGE)
        native.adb("shell", "am", "start", "-n", native.PACKAGE + "/.MainActivity")
        end = time.monotonic() + 35
        while time.monotonic() < end and "Willkommen zurück" not in labels():
            if "Anmelden" in labels():
                press("Anmelden")
            time.sleep(0.4)
        wait("Willkommen zurück")
        step("native_login_form")
        for index, value in enumerate((credentials["child_username"], credentials["child_password"])):
            fields = [n for n in native.nodes() if n.get("class") == "android.widget.EditText"]
            check(len(fields) == 2, "native_login_fields_missing")
            native.tap_node(fields[index])
            native.adb("shell", "input", "keyevent", "123")
            native.adb("shell", "input", "keyevent", *(["67"] * 128))
            input_text(value)
            native.adb("shell", "input", "keyevent", "4")
        press("Anmelden")
        step("native_login_submitted")
        wait("Hallo,")
        step("native_vocabulary_and_saved_round")
        press("Wörter")
        wait("Meine Wörter")
        native.screenshot("language-native-vocabulary.png")
        press(unit["topic"])
        if unit["status"] != "completed":
            if unit["status"] != "active":
                press("Lernen fortsetzen" if unit["status"] == "paused" else "Einheit starten")
            if not unit["introduction_seen"]:
                press("Weiter zu den Übungen")
            for _ in range(16):
                unit = api_get(api, "/units/" + unit_id)
                if unit.get("pending_feedback"):
                    press("Ergebnis ansehen" if unit["status"] == "completed" else "Weiter")
                    continue
                question = next(
                    (
                        q
                        for q in unit["questions"]
                        if not any(a["outcome"] in ("correct", "uncertain") for a in q["attempts"])
                        and len(q["attempts"]) < 3
                    ),
                    None,
                )
                if not question:
                    break
                check(
                    "answer" not in question
                    and "accepted" not in question
                    and "evaluation_policy" not in question["language"],
                    "child_solution_leak",
                )
                answer = dictionary.get(question["language"]["vocabulary_item_id"])
                check(
                    answer and question["language"]["task_kind"] == "context_gap",
                    "only_approved_artificial_word_answers_allowed",
                )
                step("native_context_answer")
                if question["type"] == "choice":
                    press(answer)
                else:
                    end = time.monotonic() + 15
                    fields = []
                    while time.monotonic() < end and not fields:
                        fields = [n for n in native.nodes() if n.get("class") == "android.widget.EditText"]
                        if not fields:
                            native.adb("shell", "input", "swipe", "900", "1700", "900", "1300", "300")
                    check(len(fields) == 1, "native_answer_field_missing")
                    native.tap_node(fields[0])
                    input_text(answer)
                    native.screenshot("language-native-keyboard.png")
                    native.adb("shell", "input", "keyevent", "4")
                press("Antwort prüfen")
                end = time.monotonic() + 20
                while time.monotonic() < end:
                    updated = api_get(api, "/units/" + unit_id)
                    if updated.get("pending_feedback"):
                        break
                    time.sleep(0.3)
                check(
                    updated.get("pending_feedback", {}).get("outcome") == "correct", "native_answer_not_saved_correctly"
                )
                native.screenshot("language-native-feedback.png")
                press("Ergebnis ansehen" if updated["status"] == "completed" else "Weiter")
        unit = api_get(api, "/units/" + unit_id)
        check(unit["status"] == "completed" and unit["pending_feedback"] is None, "native_round_not_completed")
        check(
            all(len(q["attempts"]) == 1 and q["attempts"][0]["outcome"] == "correct" for q in unit["questions"]),
            "native_attempt_duplicate_or_outcome_error",
        )
        native.screenshot("language-native-result.png")
        step("native_cold_resume")
        native.adb("shell", "am", "force-stop", native.PACKAGE)
        native.adb("shell", "am", "start", "-n", native.PACKAGE + "/.MainActivity")
        wait("Hallo,")
        press("Wörter")
        wait("Meine Wörter")
        native.screenshot("language-native-resume.png")
        check(
            api_get(api, f"/children/{child_id}/learning-progress")["totals"]["practiced_tasks"]
            == 3 + len(unit["questions"]),
            "web_native_progress_inconsistent",
        )
        report = {
            "native_android_api": 36,
            "version_code": 30,
            "native_flutter": True,
            "own_child_login": True,
            "cross_device_context_resume": True,
            "keyboard_answers": True,
            "completed_context_tasks": len(unit["questions"]),
            "feedback_acknowledged": True,
            "cold_resume": True,
            "duplicate_answers": 0,
            "new_provider_calls": 0,
            "actual_microphone_audio_acceptance": False,
            "physical_phone_acceptance": False,
        }
        (native.ARTIFACTS / "language-native-result.json").write_text(json.dumps(report) + "\n")
        print(json.dumps(report))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        reason = (
            str(error)
            if isinstance(error, QaFailure) and re.fullmatch(r"[a-z0-9_]+", str(error))
            else "native_or_local_io_failed"
        )
        print(json.dumps({"failed_phase": PHASE, "reason": reason, "private_fixture_preserved": True}))
        raise SystemExit(1) from None
