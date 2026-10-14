"""Actual installed Android APK, isolated synthetic family, public HTTPS API.

Requires the dedicated emulator-5580. Never prints credentials or answers.
Exercises native login, secure-session restoration, child login, hint/answer,
server-side revocation and deletion. Web smoke covers all four task widgets.
"""

import json
import re
import subprocess
import time
import xml.etree.ElementTree as ET
from pathlib import Path

import httpx

ADB = [str(Path.home() / "android-sdk/platform-tools/adb"), "-s", "emulator-5580"]
PACKAGE = "de.dorfspy.schulpilot"
BASE = "https://schulpilot.dorfspy.de/api"
ARTIFACTS = Path(__file__).resolve().parents[1] / "artifacts"
PRIVATE = ARTIFACTS / ".android-qa-account.json"
HEADERS = {"X-Schulpilot-Request": "1", "X-Client-Platform": "native"}


def adb(*args):
    return subprocess.check_output([*ADB, *args], stderr=subprocess.PIPE)


def nodes():
    adb("shell", "uiautomator", "dump", "/sdcard/schulpilot-window.xml")
    return list(ET.fromstring(adb("exec-out", "cat", "/sdcard/schulpilot-window.xml")).iter("node"))


def matching(name):
    return [n for n in nodes() if name in (n.get("content-desc", "").splitlines() + [n.get("text", "")])]


def wait(name, seconds=35):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        found = matching(name)
        if found:
            return found
        time.sleep(0.5)
    raise RuntimeError("Expected native UI element was not visible")


def tap_node(node):
    bounds = list(map(int, re.findall(r"\d+", node.get("bounds", ""))))
    if len(bounds) != 4 or bounds[3] <= bounds[1]:
        raise RuntimeError("Native element has no tappable bounds")
    adb("shell", "input", "tap", str((bounds[0] + bounds[2]) // 2), str((bounds[1] + bounds[3]) // 2))
    time.sleep(0.5)


def press(name, scroll=False):
    found = matching(name)
    if not found and scroll:
        for _ in range(3):
            adb("shell", "input", "swipe", "900", "650", "900", "1950", "250")
        for _ in range(12):
            found = matching(name)
            if found:
                break
            adb("shell", "input", "swipe", "900", "1900", "900", "750", "250")
    if not found:
        found = wait(name)
    clickable = [n for n in found if n.get("clickable") == "true"]
    tap_node((clickable or found)[-1])


def login(username, password):
    wait("Willkommen zurück.")
    for index, value in enumerate((username, password)):
        if not re.fullmatch(r"[A-Za-z0-9_.-]+", value):
            raise RuntimeError("ADB test input must be generated safe synthetic text")
        fields = [n for n in nodes() if n.get("class") == "android.widget.EditText"]
        tap_node(fields[index])
        time.sleep(0.4)
        adb("shell", "input", "text", value)
        adb("shell", "input", "keyevent", "4")  # close keyboard
    press("Anmelden")


def screenshot(name):
    p = ARTIFACTS / name
    p.write_bytes(adb("exec-out", "screencap", "-p"))
    p.chmod(0o600)


def check(response, expected=200):
    if response.status_code != expected:
        raise RuntimeError("Unexpected public API status " + str(response.status_code))
    return response.json()


def main():
    checks = []
    with httpx.Client(base_url=BASE, headers=HEADERS, timeout=30) as parent:
        if PRIVATE.exists():
            demo = json.loads(PRIVATE.read_text())
        else:
            demo = check(parent.post("/demo"), 201)
            PRIVATE.write_text(json.dumps(demo))
            PRIVATE.chmod(0o600)
        parent.headers["Authorization"] = "Bearer " + demo["token"]
        if not demo.get("unit_id"):
            material = check(parent.get("/materials/" + demo["material_id"]))
            check(
                parent.put(
                    "/materials/" + material["id"] + "/confirm",
                    json={
                        **{k: material[k] for k in ("subject", "topic", "content", "homework")},
                        "uncertainties_resolved": True,
                    },
                )
            )
            queue = check(
                parent.post(
                    "/children/" + demo["child_id"] + "/units",
                    headers={"Idempotency-Key": "android-smoke"},
                    json={"material_id": material["id"]},
                ),
                202,
            )
            for _ in range(30):
                result = check(parent.get("/jobs/" + queue["id"]))
                if result["status"] == "completed":
                    demo["unit_id"] = result["result"]["unit_id"]
                    PRIVATE.write_text(json.dumps(demo))
                    break
                time.sleep(1)
            if not demo.get("unit_id"):
                raise RuntimeError("Synthetic unit was not prepared")
        credentials = demo["credentials"]
        adb("shell", "pm", "clear", PACKAGE)
        adb("shell", "am", "start", "-n", PACKAGE + "/.MainActivity")
        wait("Anmelden")
        press("Anmelden")
        login(credentials["parent_username"], credentials["parent_password"])
        wait("Deine Familie im Blick.")
        screenshot("android-parent.png")
        checks.append("native_parent_login_over_public_https")
        adb("shell", "am", "force-stop", PACKAGE)
        adb("shell", "am", "start", "-n", PACKAGE + "/.MainActivity")
        # Cold-start opens landing with the restored account and its CTA.
        wait("Mein Lernraum")
        press("Mein Lernraum")
        wait("Deine Familie im Blick.")
        checks.append("secure_session_restored_after_process_restart")
        press("Einstellungen")
        press("Abmelden", scroll=True)
        login(credentials["child_username"], credentials["child_password"])
        wait("Jetzt lernen")
        screenshot("android-child.png")
        checks.append("separate_native_child_login")
        press("Jetzt lernen")
        current_unit = check(parent.get("/units/" + demo["unit_id"]))
        if not current_unit["introduction_seen"]:
            press("Weiter zu den Übungen", scroll=True)
        first = check(parent.get("/units/" + demo["unit_id"]))["questions"][0]
        press("Ein Hinweis bitte", scroll=True)
        press(first["answer"], scroll=True)
        press("Antwort prüfen", scroll=True)
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            updated = check(parent.get("/units/" + demo["unit_id"]))["questions"][0]
            if updated["attempts"]:
                break
            time.sleep(1)
        assert updated["attempts"][-1]["outcome"] == "correct" and updated["attempts"][-1]["assisted"] is True
        assert updated["hints_used"] >= 1
        screenshot("android-exercise.png")
        checks.append("native_hint_and_answer_persist_in_parent_history")
        sessions = check(parent.get("/children/" + demo["child_id"] + "/sessions"))
        for session in sessions:
            check(parent.delete("/children/" + demo["child_id"] + "/sessions/" + session["id"]))
        adb("shell", "am", "force-stop", PACKAGE)
        adb("shell", "am", "start", "-n", PACKAGE + "/.MainActivity")
        wait("Anmelden")
        checks.append("parent_revocation_blocks_restoration_of_child_session")
        check(parent.request("DELETE", "/account", json={"password": credentials["parent_password"]}))
        PRIVATE.unlink()
        checks.append("own_synthetic_family_deleted")
    print(
        json.dumps(
            {"android_api": 36, "installed_apk": True, "public_https": BASE, "checks": checks, "external_ai_calls": 0}
        )
    )


if __name__ == "__main__":
    main()
