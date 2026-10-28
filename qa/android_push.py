"""Two neutral push checks on the already installed, signed direct Flutter APK.

Only dedicated emulator-5580 and the explicitly approved artificial child account
are used. No install/build/deployment, account creation, arbitrary-token sending,
or application-private-storage access. Tokens and UI snapshots stay in memory.
The current-device test buttons create at most two send intents; a private local
checkpoint is written before each tap so an interrupted run cannot resend them.
"""

import argparse
import json
import os
import re
import shlex
import stat
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

import httpx
from android_smoke import ADB, BASE, HEADERS, PACKAGE, adb, nodes, press, tap_node, wait

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = Path(os.environ.get(
    "SCHULPILOT_QA_PUSH_CREDENTIALS",
    str(Path.home() / ".local/share/schulpilot-firebase/test-login-private.json"),
)).expanduser()
REPORT = ROOT / "artifacts/android-push-result.json"
CHECKPOINT = ROOT / "artifacts/.android-push-send-checkpoint.json"
NEUTRAL = "Es gibt Neuigkeiten in SchuleSchlau."
BACKGROUND_BODY = "Es gibt Neuigkeiten in SchuleSchlau. Öffne deinen Lernraum."
ACCEPTED = "Testnachricht: Von FCM angenommen"


class PushQaError(Exception):
    pass


def load_credentials(path=PRIVATE):
    """Accept the old flat fixture or a new private synthetic-fixture wrapper."""
    if stat.S_IMODE(path.stat().st_mode) != 0o600:
        raise PushQaError("fixture_credentials_must_have_mode_600")
    fixture = json.loads(path.read_text())
    if "credentials" in fixture:
        if fixture.get("synthetic_only") is not True:
            raise PushQaError("wrapped_fixture_must_be_explicitly_synthetic")
        fixture = fixture["credentials"]
    if not isinstance(fixture, dict) or not all(
        isinstance(fixture.get(key), str) and fixture[key]
        for key in ("child_username", "child_password")
    ):
        raise PushQaError("fixture_credentials_schema_invalid")
    # Authentication, synthetic family, test grant and parental consent are
    # independently checked below. A local label alone never authorizes send.
    return fixture


def safe_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path, os.O_CREAT | os.O_TRUNC | os.O_WRONLY, 0o600)
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, "w") as target:
        json.dump(data, target)
        target.write("\n")


def labels(tree):
    return {
        value
        for node in tree
        for value in [node.get("text", ""), node.get("content-desc", ""), *node.get("content-desc", "").splitlines()]
        if value
    }


def bounds(node):
    values = list(map(int, re.findall(r"-?\d+", node.get("bounds", ""))))
    if len(values) != 4 or values[2] <= values[0] or values[3] <= values[1]:
        raise PushQaError("native_control_bounds_missing")
    return values


def seek_label(label, *, prefix=False):
    def matching(tree):
        return [
            node
            for node in tree
            if any(value.startswith(label) if prefix else value == label for value in labels([node]))
        ]

    tree = nodes()
    found = matching(tree)
    if found:
        return found[-1]
    for _ in range(3):
        adb("shell", "input", "swipe", "900", "650", "900", "1950", "250")
    for _ in range(28):
        found = matching(nodes())
        if found:
            return found[-1]
        adb("shell", "input", "swipe", "900", "1700", "900", "1300", "450")
    raise PushQaError("expected_native_push_control_missing")


def native_login(credentials):
    wait("Willkommen zurück")
    for index, name in enumerate(("child_username", "child_password")):
        value = credentials[name]
        if not re.fullmatch(r"[A-Za-z0-9_.-]+", value):
            raise PushQaError("fixture_input_requires_unsupported_native_keyboard_characters")
        fields = [node for node in nodes() if node.get("class") == "android.widget.EditText"]
        tap_node(fields[index])
        # Existing own emulator login forms can retain an unfinished value.
        # Hardware Ctrl+A is not handled by this Flutter field on API36; use
        # real End/Delete key events instead of reading private app storage.
        length = min(256, len(fields[index].get("text", "")))
        adb("shell", "input", "keyevent", "123")
        adb("shell", "input", "keyevent", *(["67"] * (length + 4)))
        result = subprocess.run(
            [*ADB, "shell"],
            input=("input text " + shlex.quote(value) + "\n").encode(),
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15,
        )
        if result.returncode:
            raise PushQaError("protected_native_input_failed")
        adb("shell", "input", "keyevent", "4")
    fields = [node for node in nodes() if node.get("class") == "android.widget.EditText"]
    if fields[0].get("text") != credentials["child_username"]:
        raise PushQaError("fixture_username_not_transferred_exactly")
    press("Anmelden")
    wait("Heute")


def open_device_panel():
    # Push configuration has its own stable route; do not depend on which
    # account tab was selected previously.
    press("Benachrichtigungen")
    if "Alle anzeigen" in labels(nodes()):
        press("Alle anzeigen")
    wait("Deine Neuigkeiten")
    press("Gerät einstellen")


def quiet(moment, start, end):
    return (
        False
        if start == end
        else moment.hour >= start or moment.hour < end
        if start > end
        else start <= moment.hour < end
    )


def choose_hour(label):
    field = seek_label(label)
    x0, _, x1, _ = bounds(field)
    x = (x0 + x1) // 2
    tap_node(field)
    for _ in range(12):
        tree = nodes()
        options = [node for node in tree if "00:00" in labels([node])]
        if options:
            tap_node(options[-1])
            return
        # Scroll inside this popup, rather than on its outside modal barrier.
        adb("shell", "input", "swipe", str(x), "650", str(x), "1800", "400")
    raise PushQaError("fixture_device_quiet_time_control_missing")


def api_json(client, method, route, expected=200, **kwargs):
    response = client.request(method, route, **kwargs)
    if response.status_code != expected:
        raise PushQaError("observer_api_status_" + str(response.status_code))
    return response.json()


def own_notifications():
    # Never write or print dumpsys output. A channel configuration alone is not
    # a posted notification; inspect only NotificationRecord package headers.
    data = adb("shell", "dumpsys", "notification").decode(errors="replace")
    return tuple(
        line.strip() for line in data.splitlines() if "NotificationRecord(" in line and ("pkg=" + PACKAGE) in line
    )


def known_firebase_errors():
    data = adb(
        "logcat", "-d", "-s", "FirebaseMessaging:W", "Firebase-Installations:W", "FirebaseInstallations:W", "*:S"
    )
    return [
        code
        for code in (
            "FIS_AUTH_ERROR",
            "AUTHENTICATION_FAILED",
            "SERVICE_NOT_AVAILABLE",
            "API_KEY_INVALID",
            "TOO_MANY_REGISTRATIONS",
        )
        if code.encode() in data
    ]


def mark_send(version):
    today = datetime.now(timezone.utc).date().isoformat()
    previous = json.loads(CHECKPOINT.read_text()) if CHECKPOINT.exists() else {}
    if previous.get("date") != today or previous.get("installed_code") != version:
        previous = {"date": today, "installed_code": version, "intents": 0}
    if previous["intents"] >= 2:
        raise PushQaError("two_send_intents_already_reserved_no_resend")
    previous["intents"] += 1
    # Claim before any tap. A competing/interrupted invocation cannot reuse
    # this send even if the older summary checkpoint has not yet been written.
    claim = CHECKPOINT.with_name(f".android-push-{version}-{today}-send-{previous['intents']}.json")
    try:
        descriptor = os.open(claim, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        raise PushQaError("send_already_reserved_no_resend") from None
    with os.fdopen(descriptor, "w") as target:
        json.dump({"reserved": True, **previous}, target)
    safe_write(CHECKPOINT, previous)
    return previous["intents"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--expected-code", type=int, required=True)
    args = parser.parse_args()
    report = {
        "installed_code": None,
        "artificial_child_only": False,
        "registration": False,
        "foreground_fcm_accepted": False,
        "foreground_in_app_visible": False,
        "background_fcm_accepted": False,
        "background_android_notification_visible": False,
        "notification_opens_authenticated_app": False,
        "requested_messages": 0,
        "fixture_device_removed": False,
        "app_logged_out": False,
    }
    observer = None
    native_logged_in = False
    fixture_device_id = None
    before_devices = set()
    try:
        credentials = load_credentials()
        package = adb("shell", "dumpsys", "package", PACKAGE).decode(errors="replace")
        version = re.search(r"\bversionCode=(\d+)", package)
        if not version or int(version[1]) != args.expected_code:
            raise PushQaError("installed_version_does_not_match_requested_existing_apk")
        report["installed_code"] = int(version[1])
        observer = httpx.Client(base_url=BASE, headers=HEADERS, timeout=30)
        session = api_json(
            observer,
            "POST",
            "/auth/login",
            json={
                "username": credentials["child_username"],
                "password": credentials["child_password"],
                "device": "Isolated native push QA observer",
            },
        )
        observer.headers["Authorization"] = "Bearer " + session["token"]
        user = session["user"]
        if user.get("role") != "child" or not user.get("synthetic"):
            raise PushQaError("explicit_artificial_child_fixture_required")
        report["artificial_child_only"] = True
        overview = api_json(observer, "GET", "/children/" + user["child_id"] + "/overview")
        preferences = overview["child"]["preferences"]
        if not preferences.get("push_consent"):
            raise PushQaError("fixture_parent_push_consent_missing")
        if quiet(datetime.now(ZoneInfo(preferences["timezone"])), preferences["quiet_start"], preferences["quiet_end"]):
            raise PushQaError("fixture_parent_quiet_hours_active_not_changed")
        config = api_json(observer, "GET", "/notifications/config")
        grant = api_json(observer, "GET", "/notifications/tests")
        if not config.get("available") or not grant.get("allowed"):
            raise PushQaError("fixture_push_configuration_or_test_grant_not_available")
        before_devices = {device["id"] for device in api_json(observer, "GET", "/notifications/devices")}
        report["phase"] = "native_fixture_login"
        safe_write(REPORT, report)
        adb("shell", "am", "start", "-n", PACKAGE + "/.MainActivity")
        wait("Willkommen zurück")
        native_login(credentials)
        native_logged_in = True
        press("Konto")
        wait("Zugänge & Einstellungen")
        if credentials["child_username"] not in labels(nodes()):
            raise PushQaError("native_session_is_not_the_explicit_fixture")
        open_device_panel()
        report["phase"] = "configure_fixture_device"
        safe_write(REPORT, report)
        tap_node(seek_label("Zeiten & Auswahl", prefix=True))
        choose_hour("Ruhe ab")
        choose_hour("Ruhe bis")
        tap_node(seek_label("Auf diesem Gerät einschalten"))
        deadline = time.monotonic() + 70
        while time.monotonic() < deadline:
            tree = nodes()
            permission = [node for node in tree if node.get("resource-id", "").endswith(":id/permission_allow_button")]
            if permission:
                tap_node(permission[0])
                continue
            devices = api_json(observer, "GET", "/notifications/devices")
            new = [
                device
                for device in devices
                if device["id"] not in before_devices and device.get("platform") == "android"
            ]
            if len(new) == 1:
                fixture_device_id = new[0]["id"]
                if new[0]["quiet_start"] != 0 or new[0]["quiet_end"] != 0:
                    raise PushQaError("fixture_device_quiet_hours_not_saved")
                report["registration"] = True
                break
            if any("Benachrichtigungen konnten nicht eingeschaltet werden" in value for value in labels(tree)):
                report["firebase_error_flags"] = known_firebase_errors()
                raise PushQaError("native_firebase_registration_failed")
            time.sleep(0.5)
        if not report["registration"]:
            report["firebase_error_flags"] = known_firebase_errors()
            raise PushQaError("native_registration_bounded_wait_expired")
        report["phase"] = "foreground_message"
        safe_write(REPORT, report)
        report["requested_messages"] = mark_send(report["installed_code"])
        tap_node(seek_label("Test an dieses Gerät senden"))
        deadline = time.monotonic() + 40
        while time.monotonic() < deadline:
            values = labels(nodes())
            report["foreground_in_app_visible"] |= NEUTRAL in values
            report["foreground_fcm_accepted"] |= any(value.startswith(ACCEPTED) for value in values)
            if report["foreground_in_app_visible"] and report["foreground_fcm_accepted"]:
                break
        if not report["foreground_fcm_accepted"]:
            seek_label(ACCEPTED, prefix=True)
            report["foreground_fcm_accepted"] = True
        report["phase"] = "background_message"
        safe_write(REPORT, report)
        baseline = own_notifications()
        send = seek_label("Test an dieses Gerät senden")
        report["requested_messages"] = mark_send(report["installed_code"])
        x0, y0, x1, y1 = bounds(send)
        adb("shell", "input", "tap", str((x0 + x1) // 2), str((y0 + y1) // 2))
        adb("shell", "input", "keyevent", "3")
        deadline = time.monotonic() + 75
        while time.monotonic() < deadline:
            current = own_notifications()
            if current and current != baseline:
                break
            time.sleep(1)
        adb("shell", "cmd", "statusbar", "expand-notifications")
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            values = labels(nodes())
            if "SchuleSchlau" in values and BACKGROUND_BODY in values:
                report["background_android_notification_visible"] = True
                break
        if report["background_android_notification_visible"]:
            tap_node(seek_label(BACKGROUND_BODY))
            wait("Heute")
            report["notification_opens_authenticated_app"] = True
        else:
            adb("shell", "cmd", "statusbar", "collapse")
            adb("shell", "am", "start", "-n", PACKAGE + "/.MainActivity")
        open_device_panel()
        seek_label(ACCEPTED, prefix=True)
        values = labels(nodes())
        report["background_fcm_accepted"] = sum(value.startswith(ACCEPTED) for value in values) >= 2
        # Distinct identical status Text widgets collapse in a set. Count actual
        # native nodes if both successful deliveries share the same text.
        if not report["background_fcm_accepted"]:
            report["background_fcm_accepted"] = (
                sum(any(value.startswith(ACCEPTED) for value in labels([node])) for node in nodes()) >= 2
            )
        if not all(
            report[key]
            for key in (
                "foreground_fcm_accepted",
                "foreground_in_app_visible",
                "background_fcm_accepted",
                "background_android_notification_visible",
                "notification_opens_authenticated_app",
            )
        ):
            raise PushQaError("native_push_delivery_or_visibility_not_fully_observed")
    except Exception as error:
        report["blocker"] = str(error) if isinstance(error, PushQaError) else "unexpected_" + type(error).__name__
    finally:
        if native_logged_in:
            try:
                adb("shell", "cmd", "statusbar", "collapse")
                adb("shell", "am", "start", "-n", PACKAGE + "/.MainActivity")
                open_device_panel()
                if fixture_device_id:
                    tap_node(seek_label("Auf diesem Gerät ausschalten"))
                press("Konto öffnen")
                press("Abmelden")
                wait("Willkommen zurück")
                report["app_logged_out"] = True
            except Exception:
                report["cleanup_ui_incomplete"] = True
        if observer:
            try:
                if fixture_device_id:
                    remaining = api_json(observer, "GET", "/notifications/devices")
                    if any(device["id"] == fixture_device_id for device in remaining):
                        api_json(observer, "DELETE", "/notifications/devices/" + fixture_device_id)
                    report["fixture_device_removed"] = not any(
                        device["id"] == fixture_device_id
                        for device in api_json(observer, "GET", "/notifications/devices")
                    )
                api_json(observer, "POST", "/auth/logout")
            except Exception:
                report["cleanup_observer_incomplete"] = True
            observer.close()
        try:
            adb("shell", "rm", "-f", "/sdcard/schulpilot-window.xml")
        except Exception:
            pass
        safe_write(REPORT, report)
        print(json.dumps(report))
    return (
        1
        if report.get("blocker") or report.get("cleanup_ui_incomplete") or report.get("cleanup_observer_incomplete")
        else 0
    )


if __name__ == "__main__":
    raise SystemExit(main())
