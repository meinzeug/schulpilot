"""Real direct-APK update on the dedicated emulator, through Android's UI.

--prepare installs a signed lower seed while the server is still older.
After deploying the higher release, --upgrade verifies the automatic download,
unknown-source consent, Android install prompt and actual installed version.
No adb install is used in the upgrade phase. No account data is printed.
"""

import argparse
import json
import re
import time
from pathlib import Path

import httpx
from android_smoke import PACKAGE, adb, nodes, press, screenshot, tap_node


def installed_code():
    text = adb("shell", "dumpsys", "package", PACKAGE).decode()
    match = re.search(r"\bversionCode=(\d+)", text)
    if not match:
        raise RuntimeError("Own test package is not installed")
    return int(match[1])


def log():
    return adb("logcat", "-d", "-s", "SchulpilotUpdate:I", "*:S").decode()


def launch():
    adb(
        "shell",
        "am",
        "start",
        "-a",
        "android.intent.action.MAIN",
        "-c",
        "android.intent.category.LAUNCHER",
        "-f",
        "0x10200000",
        "-n",
        PACKAGE + "/.MainActivity",
    )


def wait_until(condition, seconds=45):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if condition():
            return
        time.sleep(0.8)
    raise RuntimeError("Native update did not reach the expected state")


def ui_texts():
    return {n.get("text", "") for n in nodes()}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--prepare", type=Path)
    parser.add_argument("--check-starts", action="store_true")
    parser.add_argument("--upgrade", action="store_true")
    args = parser.parse_args()
    release = httpx.get("https://schulpilot.dorfspy.de/api/app-release", timeout=20).raise_for_status().json()
    if args.prepare or args.check_starts:
        if args.prepare:
            adb("install", "-r", str(args.prepare.resolve()))
        before = log().count("Checking release manifest on app start")
        current_before = log().count("Installed version is current")
        adb("shell", "am", "force-stop", PACKAGE)
        launch()
        wait_until(lambda: log().count("Installed version is current") >= current_before + 1)
        adb("shell", "input", "keyevent", "3")
        time.sleep(1.5)  # Let the launcher transition really stop the Activity.
        launch()
        wait_until(lambda: log().count("Checking release manifest on app start") >= before + 2)
        wait_until(lambda: log().count("Installed version is current") >= current_before + 2)
        if args.check_starts:
            launch()  # An additional launcher intent while already visible.
            wait_until(lambda: log().count("Installed version is current") >= current_before + 3)
        assert installed_code() >= release["version_code"]
        print(
            json.dumps(
                {
                    "start_checks": 3 if args.check_starts else 2,
                    "cold_and_foreground_checked": True,
                    "installed_code": installed_code(),
                    "no_downgrade": True,
                }
            )
        )
        return
    if not args.upgrade:
        parser.error("Use --prepare SEED.apk, --check-starts or --upgrade")
    old = installed_code()
    target = release["version_code"]
    assert target > old, "Deploy the higher signed release before testing the update"
    adb("shell", "am", "force-stop", PACKAGE)
    launch()
    wait_until(
        lambda: "Update-Installation erlauben" in ui_texts() or "Update" in ui_texts() or "Aktualisieren" in ui_texts(),
        seconds=180,
    )
    if "Update-Installation erlauben" in ui_texts():
        screenshot("android-update-permission-explanation.png")
        press("Android-Einstellungen öffnen")
        wait_until(lambda: any(n.get("checkable") == "true" for n in nodes()))
        controls = [n for n in nodes() if n.get("checkable") == "true"]
        switch = controls[-1]
        if switch.get("checked") != "true":
            tap_node(switch)
        screenshot("android-update-source-consent.png")
        adb("shell", "input", "keyevent", "4")
    wait_until(lambda: "Update" in ui_texts() or "Aktualisieren" in ui_texts(), seconds=90)
    screenshot("android-update-system-confirmation.png")
    press("Update" if "Update" in ui_texts() else "Aktualisieren")
    wait_until(lambda: installed_code() == target, seconds=90)
    # Android's success sheet belongs to the installer, not to our app task.
    names = ui_texts()
    if "Open" in names or "Öffnen" in names:
        press("Open" if "Open" in names else "Öffnen")
    elif "Done" in names or "Fertig" in names:
        press("Done" if "Done" in names else "Fertig")
    current_before = log().count("Installed version is current")
    launch()
    wait_until(lambda: log().count("Installed version is current") > current_before)
    screenshot("android-updated-current-version.png")
    print(
        json.dumps(
            {
                "automatic_server_check": True,
                "automatic_verified_download": True,
                "system_install_confirmed": True,
                "adb_install_used_for_upgrade": False,
                "previous_code": old,
                "installed_code": installed_code(),
                "server_code": target,
            }
        )
    )


if __name__ == "__main__":
    main()
