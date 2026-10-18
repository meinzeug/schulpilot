"""Resume the real workshop exam in native APK33, only our artificial family.

No generation, clock change or private solution retrieval. Credentials use
ADB stdin through the established helper, never process arguments or logs.
"""

import json
import re
import time

import android_smoke as native
import httpx
from android_material_words import input_text, login, read, require
from android_update import installed_code, launch

PRIVATE = native.ARTIFACTS / ".school-day-qa-account.json"


def main():
    account = json.loads(PRIVATE.read_text())
    state = account.get("workshop_exam_qa", {})
    require(account.get("normal_account") and account.get("verified")
            and re.search(r"\+schulpilot-normal-qa-[a-f0-9]{12}@", account["credentials"]["parent_username"])
            and state.get("phase") == "web_passed_keep_for_native", "successful_own_web_exam_required")
    require(installed_code() == 33, "existing_stable_apk33_required")
    require(native.adb("emu", "avd", "name").decode().splitlines()[0] == "schulpilot-qa-api36", "dedicated_avd_required")
    checks = []
    with httpx.Client(base_url=native.BASE, headers={**native.HEADERS, "X-Schulpilot-Capabilities": "language-v1"}, timeout=30) as api:
        response = api.post("/auth/login", json={"username": account["credentials"]["child_username"],
                                               "password": account["credentials"]["child_password"]})
        require(response.status_code == 200 and response.json()["user"]["child_id"] == account["child_id"], "own_observer_login_required")
        api.headers["Authorization"] = "Bearer " + response.json()["token"]
        words = read(api, "/children/" + account["child_id"] + "/vocabulary?page_size=50")
        dictionary = {word["id"]: word["word"] for word in words["items"]}
        unit = read(api, "/units/" + state["unit_id"])
        require(any(a["id"] == state["web_attempt_id"] for q in unit["questions"] for a in q["attempts"]), "same_saved_web_answer_required")
        launch()
        native.wait_any(["Willkommen zurück", "Anmelden", "Lernrunde verlassen", "Konto"], seconds=60)
        if native.matching("Lernrunde verlassen"):
            native.press("Lernrunde verlassen")
        if native.matching("Anmelden") and not native.matching("Willkommen zurück"):
            native.press("Anmelden")
        if native.matching("Willkommen zurück"):
            login(account["credentials"], "child")
        else:
            native.press("Konto")
            native.wait(account["credentials"]["child_username"])
        native.press("Wörter")
        native.wait("Meine Wörter")
        native.press("Wörter anwenden")
        native.wait("Sprachwerkstatt")
        native.press("Probe mit verdeckten Lösungen", scroll=True)
        native.wait("Mit den Aufgaben üben")
        native.screenshot("workshop-exam-native-project.png")
        native.press("Mit den Aufgaben üben")
        if read(api, "/units/" + state["unit_id"]).get("pending_feedback"):
            native.wait("Weiter")
        checks.append("native_project_directly_usable_and_web_feedback_resumed")
        answered_here = 0
        for _ in range(12):
            unit = read(api, "/units/" + state["unit_id"])
            if unit.get("pending_feedback"):
                native.press("Ergebnis ansehen" if unit["status"] == "completed" else "Weiter")
                time.sleep(.4)
                continue
            if unit["status"] == "completed":
                break
            if unit["status"] != "active":
                native.press("Lernen fortsetzen" if unit["status"] == "paused" else "Einheit starten")
            question = next(q for q in unit["questions"] if not q["attempts"])
            require(question["language"]["task_kind"] == "context_gap", "known_closed_word_task_required")
            answer = dictionary[question["language"]["vocabulary_item_id"]]
            if question["type"] == "choice":
                native.press(answer, scroll=True)
            else:
                fields = []
                for _ in range(12):
                    fields = [n for n in native.nodes() if n.get("class") == "android.widget.EditText"]
                    if fields:
                        break
                    native.adb("shell", "input", "swipe", "900", "1700", "900", "1300", "300")
                require(len(fields) == 1, "one_native_answer_editor_required")
                native.tap_node(fields[0])
                input_text(answer)
                native.adb("shell", "input", "keyevent", "4")
            native.press("Antwort prüfen", scroll=True)
            for _ in range(40):
                changed = read(api, "/units/" + state["unit_id"])
                saved = next(q for q in changed["questions"] if q["id"] == question["id"])
                if saved["attempts"]:
                    break
                time.sleep(.5)
            require(len(saved["attempts"]) == 1 and saved["attempts"][0]["outcome"] == "correct", "native_answer_must_be_saved_once_and_correct")
            answered_here += 1
        unit = read(api, "/units/" + state["unit_id"])
        require(unit["status"] == "completed" and all(len(q["attempts"]) == 1 for q in unit["questions"]), "complete_exam_without_duplicate_answers_required")
        checks.append("native_remaining_exam_answers_and_result_saved")
        native.screenshot("workshop-exam-native-result.png")
        native.press("Lernrunde verlassen")
        native.press("Konto")
        native.press("Abmelden", scroll=True)
        native.wait("Willkommen zurück")
        require(api.post("/auth/logout").status_code == 200, "own_observer_logout_failed")
        state["phase"] = "native_passed"
        PRIVATE.write_text(json.dumps(account) + "\n")
        PRIVATE.chmod(0o600)
        report = {"success": True, "native_flutter": True, "installed_code": 33, "android_api": 36,
                  "checks": checks, "native_answers": len(unit["questions"]) - 1, "answers_this_resume": answered_here,
                  "total_questions": len(unit["questions"]), "extra_ai_calls": 0}
        (native.ARTIFACTS / "workshop-exam-native-result.json").write_text(json.dumps(report) + "\n")
        print(json.dumps(report))


if __name__ == "__main__":
    main()
