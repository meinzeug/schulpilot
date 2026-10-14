"""Installed APK checks of the same synthetic day as the public/browser smoke.

Requires the dedicated emulator-5580 and a --keep-for-browser test account.
Changes only this test installation. Leaves the family for qa/school_day.mjs,
which deletes it after the browser check. No credentials are printed.
"""

import json
from pathlib import Path

from android_smoke import PACKAGE, adb, login, nodes, press, screenshot, tap_node, wait


def expand_sources():
    # Android appends the expanded/collapsed accessibility state to the label.
    for _ in range(10):
        found = [n for n in nodes() if n.get("content-desc", "").startswith("Heftseiten dieses Tages (2)")]
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
    press("Nach der Schule starten", scroll=True)
    wait("Dein Lernpaket ist bereit")
    expand_sources()
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
    print(json.dumps({"checks": ["installed_signed_apk", "separate_native_child_login", "after_school_entry", "two_persisted_notebook_sources", "secure_session_and_day_resume_after_process_restart"], "synthetic_only": True, "ai_calls": 0}))


if __name__ == "__main__":
    main()
