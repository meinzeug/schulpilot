"""Installed APK checks of the same synthetic day as the public/browser smoke.

Requires the dedicated emulator-5580 and a --keep-for-browser test account.
Changes only this test installation. Leaves the family for qa/school_day.mjs,
which deletes it after the browser check. No credentials are printed.
"""

import json
from pathlib import Path

from android_smoke import PACKAGE, adb, login, nodes, press, screenshot, tap_node, wait


def expand_section(prefix):
    # Android appends the expanded/collapsed accessibility state to the label.
    for _ in range(10):
        found = [n for n in nodes() if n.get("content-desc", "").startswith(prefix)]
        if found:
            tap_node(found[0])
            return
        adb("shell", "input", "swipe", "900", "1850", "900", "750", "250")
    raise RuntimeError("Native source-page expander was not visible")


def main():
    private = Path(__file__).resolve().parents[1] / "artifacts/.school-day-qa-account.json"
    demo = json.loads(private.read_text())
    adb("install", "-r", str(private.parent / "schulpilot-0.1.0-test.apk"))
    adb("shell", "pm", "clear", PACKAGE)
    adb("shell", "am", "start", "-n", PACKAGE + "/.MainActivity")
    press("Anmelden")
    login(demo["credentials"]["child_username"], demo["credentials"]["child_password"])
    if demo.get("last_completed_unit_id"):
        press("Lernbegleitung ansehen", scroll=True)
        wait("Deine Lernbegleitung")
        expand_section("Rückmeldung zu jeder Aufgabe")
        screenshot("android-coaching-review.png")
        adb("shell", "am", "force-stop", PACKAGE)
        adb("shell", "am", "start", "-n", PACKAGE + "/.MainActivity")
        press("Mein Lernraum")
        press("Lernbegleitung ansehen", scroll=True)
        wait("Deine Lernbegleitung")
        screenshot("android-coaching-resumed.png")
        adb("shell", "input", "keyevent", "4")
    press("Nach der Schule starten", scroll=True)
    wait("Dein Lernpaket ist bereit")
    expand_section("Heftseiten dieses Tages (2)")
    wait("Seite 1 · Mathematik")
    adb("shell", "input", "swipe", "900", "1700", "900", "950", "250")
    wait("Seite 2 · Mathematik")
    screenshot("android-school-day-pages.png")
    adb("shell", "am", "force-stop", PACKAGE)
    adb("shell", "am", "start", "-n", PACKAGE + "/.MainActivity")
    press("Mein Lernraum")
    press("Nach der Schule starten", scroll=True)
    wait("Dein Lernpaket ist bereit")
    screenshot("android-school-day-resumed.png")
    checks = [
        "installed_signed_apk",
        "separate_native_child_login",
        "after_school_entry",
        "two_persisted_notebook_sources",
        "secure_session_and_day_resume_after_process_restart",
    ]
    if demo.get("last_completed_unit_id"):
        checks += [
            "persisted_ai_review_and_question_feedback",
            "secure_session_and_coaching_resume_after_process_restart",
        ]
    print(json.dumps({"checks": checks, "synthetic_only": True, "ai_calls": 0}))


if __name__ == "__main__":
    main()
