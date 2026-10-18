"""Real native Flutter APK33, only our verified artificial photo/word household.

Run after qa/material_words.mjs and actual OTA. Credentials go to ADB stdin;
no provider invocation, push send, clock changes or real-family access.
"""

import json
import re
import shlex
import subprocess
import time

import android_smoke as native
import httpx
from android_update import installed_code, launch

PRIVATE = native.ARTIFACTS / ".school-day-qa-account.json"
REPORT = native.ARTIFACTS / "material-words-android-result.json"


def require(condition, code):
    if not condition:
        raise RuntimeError(code)


def input_text(value):
    require(bool(re.fullmatch(r"[A-Za-z0-9_@.+ /;=-]{1,500}", value)), "generated_safe_input_required")
    result = subprocess.run(
        [*native.ADB, "shell"], input=("input text " + shlex.quote(value.replace(" ", "%s")) + "\n").encode(),
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15,
    )
    require(result.returncode == 0, "protected_native_input_failed")


def login(credentials, role):
    native.wait("Willkommen zurück")
    for index, key in enumerate((role + "_username", role + "_password")):
        fields = [n for n in native.nodes() if n.get("class") == "android.widget.EditText"]
        require(len(fields) == 2, "native_login_fields_missing")
        native.tap_node(fields[index])
        length = min(256, len(fields[index].get("text", "")))
        native.adb("shell", "input", "keyevent", "123")
        native.adb("shell", "input", "keyevent", *(["67"] * (length + 4)))
        input_text(credentials[key])
        native.adb("shell", "input", "keyevent", "4")
    native.press("Anmelden")
    native.wait("Heute" if role == "child" else "Deine Familie")


def read(api, route):
    response = api.get(route)
    require(response.status_code == 200, "owned_api_read_failed")
    return response.json()


def main():
    data = json.loads(PRIVATE.read_text())
    state = data.get("material_words_qa", {})
    credentials = data["credentials"]
    require(data.get("normal_account") and data.get("verified")
            and re.search(r"\+schulpilot-normal-qa-[a-f0-9]{12}@", credentials["parent_username"]), "own_fixture_required")
    require(state.get("phase") in ("web_passed_keep_for_native", "native_round_created", "native_passed"), "actual_public_web_chain_required")
    require(installed_code() == 33, "actual_ota_to_apk33_required")
    require(native.adb("emu", "avd", "name").decode().splitlines()[0] == "schulpilot-qa-api36", "dedicated_avd_required")
    checks = []
    report = {"installed_code": 33, "android_api": 36, "native_flutter": True, "checks": checks, "additional_ai_calls": 0}
    phase = "own_native_child_login"
    try:
        with httpx.Client(base_url=native.BASE, headers=native.HEADERS, timeout=30) as api:
            response = api.post("/auth/login", json={"username": credentials["parent_username"], "password": credentials["parent_password"]})
            require(response.status_code == 200, "own_parent_login_failed")
            parent = response.json()
            require(parent["user"]["id"] == data["user"]["id"], "own_parent_identity_mismatch")
            api.headers["Authorization"] = "Bearer " + parent["token"]
            words = read(api, "/children/" + data["child_id"] + "/vocabulary")
            require(words["pagination"]["total"] == 5, "five_source_words_required")
            meanings = {word["id"]: word["meaning"] for word in words["items"]}
            launch()
            if native.matching("Willkommen zurück"):
                login(credentials, "child")
            else:
                native.press("Konto")
                native.wait(credentials["child_username"])
                native.press("Heute")
            native.press("Wörter")
            native.wait("Meine Wörter")
            native.screenshot("material-words-native-regular-menu.png")
            checks.append("native_words_regular_menu_and_five_photo_words")
            phase = "native_recognition_round"
            if not state.get("native_unit_id"):
                native.press("Wörter üben", scroll=True)
                native.wait("Deine nächste Wörterrunde")
                native.press("Wörter schreiben")
                native.press("Bedeutung erkennen")
                native.press("Runde beginnen")
                deadline = time.monotonic() + 30
                unit = None
                while time.monotonic() < deadline:
                    current = read(api, "/children/" + data["child_id"] + "/vocabulary")
                    pending = [r for r in current["open_rounds"] if r["id"] != state["unit_id"]]
                    if pending:
                        unit = read(api, "/units/" + pending[0]["id"])
                        break
                    time.sleep(.5)
                require(unit is not None, "native_round_was_not_persisted")
                state["native_unit_id"], state["phase"] = unit["id"], "native_round_created"
                PRIVATE.write_text(json.dumps(data) + "\n")
                PRIVATE.chmod(0o600)
            else:
                native.press("Mein Wortschatz", scroll=True)
                unit = read(api, "/units/" + state["native_unit_id"])
            unit = read(api, "/units/" + state["native_unit_id"])
            if unit["status"] not in ("active", "completed"):
                # Explicit saved rounds may auto-start on open; allow the UI
                # request to finish before deciding whether a start is needed.
                time.sleep(1)
                unit = read(api, "/units/" + unit["id"])
                if unit["status"] not in ("active", "completed"):
                    native.press("Lernen fortsetzen" if unit["status"] == "paused" else "Einheit starten", scroll=True)
            restarted = state.get("native_reload_checked", False)
            for _ in range(10):
                unit = read(api, "/units/" + state["native_unit_id"])
                if unit.get("pending_feedback"):
                    native.press("Ergebnis ansehen" if unit["status"] == "completed" else "Weiter")
                    continue
                question = next((q for q in unit["questions"] if not q["attempts"]), None)
                if not question:
                    break
                require(question.get("language", {}).get("task_kind") == "meaning_choice", "only_own_recognition_round_allowed")
                answer = meanings.get(question["language"]["vocabulary_item_id"])
                require(answer in question["options"], "only_original_artificial_answer_allowed")
                native.press(answer, scroll=True)
                native.press("Antwort prüfen", scroll=True)
                native.wait("Richtig!")
                current = read(api, "/units/" + unit["id"])
                saved = next(q for q in current["questions"] if q["id"] == question["id"])
                require(len(saved["attempts"]) == 1 and saved["attempts"][0]["outcome"] == "correct", "one_persisted_answer_required")
                if not restarted:
                    attempt_id = current["pending_feedback"]["attempt_id"]
                    native.adb("shell", "am", "force-stop", native.PACKAGE)
                    launch()
                    native.wait("Rückmeldung ansehen")
                    native.press("Rückmeldung ansehen", scroll=True)
                    native.wait("Richtig!")
                    require(read(api, "/units/" + unit["id"])["pending_feedback"]["attempt_id"] == attempt_id, "native_restart_duplicated_or_lost_feedback")
                    state["native_reload_checked"] = restarted = True
                    PRIVATE.write_text(json.dumps(data) + "\n")
                    PRIVATE.chmod(0o600)
                    checks.append("native_feedback_survives_restart_without_double_answer")
                native.screenshot("material-words-native-answer.png")
                native.press("Ergebnis ansehen" if current["status"] == "completed" else "Weiter")
            unit = read(api, "/units/" + state["native_unit_id"])
            require(unit["status"] == "completed" and len(unit["questions"]) == 3, "three_native_recognition_answers_required")
            require(all(len(q["attempts"]) == 1 for q in unit["questions"]), "native_answers_duplicated")
            progress = read(api, "/children/" + data["child_id"] + "/learning-progress")
            require(progress["totals"]["practiced_tasks"] == 6, "parent_history_must_match_web_and_native_answers")
            checks.append("three_native_recognition_answers_and_six_total_parent_tasks")
            native.press("Lernrunde verlassen")
            native.press("Konto")
            native.press("Abmelden", scroll=True)
            native.wait("Willkommen zurück")
            phase = "native_parent_words_menu"
            login(credentials, "parent")
            native.press("Wörter")
            native.wait("Wörter deiner Kinder")
            native.press("Künstliches Testkind")
            native.wait("Künstliches Testkind · Wortschatz")
            native.screenshot("material-words-native-parent.png")
            checks.append("native_parent_words_menu_child_selector_and_summary")
            native.press("Konto")
            native.press("Abmelden", scroll=True)
            native.wait("Willkommen zurück")
            require(api.post("/auth/logout").status_code == 200, "observer_logout_failed")
            state["phase"] = "native_passed"
            PRIVATE.write_text(json.dumps(data) + "\n")
            PRIVATE.chmod(0o600)
            report["success"] = True
    except Exception:
        report["success"], report["failed_phase"] = False, phase
        raise
    finally:
        REPORT.write_text(json.dumps(report) + "\n")
        REPORT.chmod(0o600)
        print(json.dumps(report), flush=True)


if __name__ == "__main__":
    main()
