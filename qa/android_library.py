"""Installed release APK, same own artificial 601-page household as Web QA.

No adb install, no real child data and no provider requests. Run after the
browser journey has completed its four local Demo questions. Credentials stay
in the ignored0600 fixture; the final cleanup removes the entire household.
Clears only this dedicated test installation after checking its AVD and version.
"""

import json
import re
import time

import httpx
from android_smoke import ARTIFACTS, BASE, HEADERS, PACKAGE, adb, login, nodes, press, screenshot, tap_node


def contains(fragment, seconds=25):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        found = [n for n in nodes() if fragment in (n.get("content-desc", "") + n.get("text", ""))]
        if found:
            return found
        time.sleep(0.3)
    raise RuntimeError("Expected native library state did not appear")


def top():
    for _ in range(4):
        adb("shell", "input", "swipe", "900", "650", "900", "1950", "250")
    time.sleep(0.5)


def main():
    data = json.loads((ARTIFACTS / ".library-qa-account.json").read_text())
    assert data["marker"] == "library-qa-v1" and data["phase"] == "ready"
    checks = []
    assert adb("emu", "avd", "name").decode().splitlines()[0] == "schulpilot-qa-api36"
    expected_code = json.loads((ARTIFACTS / "android-release.json").read_text())["version_code"]
    installed = adb("shell", "dumpsys", "package", PACKAGE).decode()
    assert re.search(r"\bversionCode=" + str(expected_code) + r"\b", installed)
    # Repeated UI logins can legitimately revoke the fixture's oldest session.
    # Read the expected answer through a fresh normal owner login, then revoke
    # that setup session. Never reset session limits or resurrect old tokens.
    with httpx.Client(base_url=BASE, headers=HEADERS, timeout=25) as setup:
        response = (
            setup.post(
                "/auth/login",
                json={
                    "username": data["credentials"]["parent_username"],
                    "password": data["credentials"]["parent_password"],
                },
            )
            .raise_for_status()
            .json()
        )
        assert response["user"]["id"] == data["user"]["id"] and response["user"]["role"] == "parent"
        setup.headers["Authorization"] = "Bearer " + response["token"]
        unit = setup.get("/units/" + data["unit_id"]).raise_for_status().json()
        setup.post("/auth/logout").raise_for_status()
    assert unit["synthetic"] and unit["provider"] == "synthetic" and unit["status"] == "completed"
    assert unit["child_id"] == data["child_id"]
    saved_answer_label = unit["questions"][0]["attempts"][0]["answer"] + " · Richtig"
    # Clear only this dedicated test installation; never install another APK.
    adb("shell", "pm", "clear", PACKAGE)
    adb("shell", "am", "force-stop", PACKAGE)
    adb("shell", "am", "start", "-n", PACKAGE + "/.MainActivity")
    print(json.dumps({"phase": "native_child_login"}), flush=True)
    login(data["credentials"]["child_username"], data["credentials"]["child_password"])
    contains("Hallo, Mika")
    press("Hefte")
    contains("1–20 von 601 Seiten")
    screenshot("library-android-library.png")
    print(json.dumps({"phase": "native_library_pagination"}), flush=True)
    press("Nächste Seite", scroll=True)
    contains("21–40 von 601 Seiten")
    # Tap the first metadata tile, then Android Back must retain the page.
    tiles = [n for n in nodes() if "Beispiel " in n.get("content-desc", "") and n.get("clickable") == "true"]
    if not tiles:
        raise RuntimeError("No native metadata tile was tappable")
    tap_node(tiles[0])
    contains("Dein Lernstoff")
    adb("shell", "input", "keyevent", "4")
    contains("21–40 von 601 Seiten")
    checks.append("library_pagination_detail_android_back")
    print(json.dumps({"phase": "native_subject_and_search"}), flush=True)
    top()
    choices = [n for n in contains("Alle Fächer") if n.get("clickable") == "true"]
    if not choices:
        raise RuntimeError("Native subject selector was not tappable")
    tap_node(choices[0])
    press("Englisch")
    contains("1–20 von 150 Seiten")
    fields = [n for n in nodes() if n.get("class") == "android.widget.EditText"]
    assert len(fields) == 1
    tap_node(fields[0])
    adb("shell", "input", "text", "003")
    adb("shell", "input", "keyevent", "4")
    contains("1–1 von 1 Seiten")
    screenshot("library-android-search.png")
    checks.append("native_subject_and_keyboard_search")
    press("Filter zurücksetzen")
    contains("1–20 von 601 Seiten")
    press("Filter und Sortierung")
    contains("Ansicht anpassen")
    screenshot("library-android-filters.png")
    press("Abbrechen")
    keyboard = adb("shell", "dumpsys", "input_method").decode()
    assert re.search(r"\bmInputShown=false\b", keyboard), "Filter close reopened the search keyboard"
    print(json.dumps({"phase": "native_learning_and_answers"}), flush=True)
    press("Lernen")
    contains("Dein Lernen")
    press("Erledigt")
    contains("4 von 4 Aufgaben")
    tiles = [n for n in nodes() if "Brüche" in n.get("content-desc", "") and n.get("clickable") == "true"]
    assert tiles
    tap_node(tiles[0])
    contains("Runde geschafft!")
    press("Antworten")
    contains(saved_answer_label)
    screenshot("library-android-answers.png")
    top()
    press("Rückblick")
    assert not any(saved_answer_label in (n.get("content-desc", "") + n.get("text", "")) for n in nodes())
    checks.append("native_completed_round_and_separate_answers")
    text = adb("shell", "dumpsys", "package", PACKAGE).decode()
    version = re.search(r"\bversionCode=(\d+)", text)
    assert version and int(version[1]) == expected_code
    report = {
        "passed": True,
        "installed_code": expected_code,
        "artificial_pages": 601,
        "checks": checks,
        "external_ai_calls": 0,
    }
    (ARTIFACTS / "library-android-result.json").write_text(json.dumps(report) + "\n")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
