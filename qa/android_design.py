"""Actual signed Flutter APK32 on our emulator, fixed artificial tasks only.

Run prepare_design_review.py and the real OTA update first. No Firebase sends,
new provider calls, account creation or arbitrary app-private-storage access.
"""

import json
import re
import shlex
import subprocess
import time

import android_smoke as native
import httpx
from android_update import installed_code, launch

PRIVATE = native.ARTIFACTS / ".design-qa-account.json"
REPORT = native.ARTIFACTS / "design-android-result.json"


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
    credentials = data["credentials"]
    require(installed_code() == 32, "upgrade_to_signed_apk32_first")
    checks = []
    report = {"installed_code": 32, "android_api": 36, "native_flutter": True, "checks": checks, "external_ai_calls": 0}
    phase = "own_fixture_login"
    try:
        with httpx.Client(base_url=native.BASE, headers=native.HEADERS, timeout=30) as api:
            response = api.post("/auth/login", json={"username": credentials["parent_username"], "password": credentials["parent_password"]})
            require(response.status_code == 200, "own_parent_login_failed")
            parent = response.json()
            require(all(f["synthetic"] for f in parent["user"]["families"]), "own_artificial_family_required")
            api.headers["Authorization"] = "Bearer " + parent["token"]
            unit = read(api, "/units/" + data["unit_id"])
            require(unit["synthetic"] and unit["provider"] == "synthetic", "fixed_synthetic_unit_required")
            launch()
            login(credentials, "child")
            native.screenshot("design-native-child-home.png")
            checks.append("native_child_login_and_today")
            native.press("Benachrichtigungen")
            native.wait("Deine Neuigkeiten")
            native.screenshot("design-native-notifications.png")
            checks.append("visible_bell_and_inbox_without_push_optin")
            native.press("Hefte")
            native.screenshot("design-native-notebooks.png")
            native.press("Heute")
            native.press("Jetzt lernen", scroll=True)
            native.wait("Weiter zu den Übungen")
            native.screenshot("design-native-understand.png")
            native.press("Weiter zu den Übungen", scroll=True)
            phase = "fixed_structured_tasks"
            for q in unit["questions"]:
                # All answers are our fixed fixture, obtained only with its parent.
                if q["type"] == "choice":
                    native.press(q["answer"], scroll=True)
                elif q["type"] in {"gap", "short"}:
                    fields = [n for n in native.nodes() if n.get("class") == "android.widget.EditText"]
                    require(bool(fields), "native_answer_field_missing")
                    native.tap_node(fields[0])
                    input_text(q["answer"])
                    native.screenshot("design-native-" + q["type"] + "-keyboard.png")
                    require(bool(native.matching("Antwort prüfen")), "keyboard_must_not_hide_primary_action")
                    # Explicit button remains usable with the keyboard open.
                elif q["type"] == "match":
                    for pair in q["options"]:
                        _, right = pair.split("|", 1)
                        candidates = native.matching("Was passt dazu?")
                        require(bool(candidates), "native_match_button_missing")
                        native.tap_node(candidates[0])
                        native.press(right)
                else:
                    raise RuntimeError("unsupported_fixture_task")
                native.screenshot("design-native-task-" + q["type"] + ".png")
                native.press("Antwort prüfen", scroll=True)
                native.wait("Richtig!")
                native.screenshot("design-native-feedback-" + q["type"] + ".png")
                if q["type"] == "choice":
                    native.adb("shell", "am", "force-stop", native.PACKAGE)
                    launch()
                    state, _ = native.wait_any(("Richtig!", "Weiterlernen"))
                    if state == "Weiterlernen":
                        native.press("Weiterlernen", scroll=True)
                    native.wait("Richtig!")
                    checks.append("saved_feedback_visible_after_native_restart")
                current = read(api, "/units/" + data["unit_id"])
                saved = next(item for item in current["questions"] if item["id"] == q["id"])
                require(len(saved["attempts"]) == 1 and saved["attempts"][0]["outcome"] == "correct", "one_saved_answer_required")
                native.press("Zum Rückblick" if current["status"] == "completed" else "Weiter")
                checks.append("native_" + q["type"] + "_answer_and_explicit_feedback")
            phase = "review_and_parent"
            time.sleep(2)
            native.screenshot("design-native-review.png")
            overview = read(api, "/children/" + data["child_id"] + "/overview?compact=true")
            require(overview["day_summary"]["answer_count"] == 4, "parent_must_see_all_four_answers")
            checks.append("parent_history_matches_four_actual_answers")
            native.press("Lernrunde verlassen")
            native.press("Konto")
            native.press("Abmelden", scroll=True)
            native.wait("Willkommen zurück")
            login(credentials, "parent")
            native.screenshot("design-native-parent-family.png")
            native.press("Konto")
            native.press("Abmelden", scroll=True)
            native.wait("Willkommen zurück")
            checks.append("native_parent_layout_and_logout")
            require(api.post("/auth/logout").status_code == 200, "observer_logout_failed")
            report["success"] = True
    except Exception:
        # No exception contents, UI dumps, passwords or answers in the report.
        report["success"] = False
        report["failed_phase"] = phase
        raise
    finally:
        REPORT.write_text(json.dumps(report) + "\n")
        REPORT.chmod(0o600)
        print(json.dumps(report), flush=True)


if __name__ == "__main__":
    main()
