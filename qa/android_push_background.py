"""One explicitly authorized background push on the dedicated existing APK.

The real child UI registers a new Android device. After an observed Activity
STOPPED, a root SSH wrapper drops to schulpilot and invokes the unchanged own_test
handler with that exact authenticated fixture/device session. Password travels
only over SSH stdin; no raw FCM/session token is read or printed. No install,
product/server configuration change, arbitrary recipient, retry, or fallback.
"""

import argparse
import json
import os
import re
import shlex
import subprocess
import time
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

import httpx
from android_push import (
    BACKGROUND_BODY,
    ROOT,
    PushQaError,
    api_json,
    choose_hour,
    labels,
    load_credentials,
    native_login,
    open_device_panel,
    own_notifications,
    quiet,
    safe_write,
    seek_label,
)
from android_smoke import ADB, BASE, HEADERS, PACKAGE, adb, nodes, press, tap_node, wait

# This fixed program is the only remote command; no user input enters its shell.
# It leaves neither a credential file nor a remotely callable API endpoint.
REMOTE = r"""
import json, os, pwd, re, shlex, sys
from pathlib import Path
try:
    raw = sys.stdin.buffer.read(16385)
    if len(raw) > 16384 or os.geteuid() != 0:
        raise ValueError("input")
    payload = json.loads(raw)
    if set(payload) != {"username", "password", "device_id", "registered_after", "action"}:
        raise ValueError("schema")
    if payload["action"] not in ("queue", "status") or not re.fullmatch(r"[a-f0-9]{32}", payload["device_id"]):
        raise ValueError("mode")
    environment = {"PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"}
    for line in Path("/etc/schulpilot/environment").read_text().splitlines():
        if line.strip() and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1)
            environment[key] = " ".join(shlex.split(value)) if value else ""
    user_entry = pwd.getpwnam("schulpilot")
    os.initgroups("schulpilot", user_entry.pw_gid)
    os.setgid(user_entry.pw_gid)
    os.setuid(user_entry.pw_uid)
    os.environ.clear()
    os.environ.update(environment)
    os.chdir("/opt/schulpilot/current/backend")
    sys.path.insert(0, os.getcwd())
    from fastapi import HTTPException
    from sqlalchemy import select
    from schulpilot.db import DB, Child, Family, PushDelivery, PushDevice, PushTestGrant, Session, User, now
    from schulpilot.notifications import OwnTest, own_test
    from schulpilot.security import Principal, verify_password
    with DB() as db:
        user = db.scalar(select(User).where(User.username == payload["username"].lower()))
        if not user or user.role != "child" or not user.verified or user.disabled or not verify_password(payload["password"], user.password_hash):
            raise ValueError("fixture_authentication")
        child = db.scalar(select(Child).where(Child.user_id == user.id))
        family = db.get(Family, child.family_id) if child else None
        grant = db.get(PushTestGrant, user.id)
        if not family or not family.synthetic or (family.expires and family.expires <= now()) or not grant or grant.expires <= now():
            raise ValueError("fixture_grant")
        device = db.scalar(select(PushDevice).where(PushDevice.id == payload["device_id"], PushDevice.user_id == user.id).with_for_update())
        if not device or device.platform != "android" or device.updated < int(payload["registered_after"]):
            raise ValueError("exact_new_android_device")
        session = db.get(Session, device.session_id)
        if not session or session.user_id != user.id or session.revoked or session.expires <= now() or now() - session.seen > 7 * 86400:
            raise ValueError("exact_device_session")
        previous = db.scalar(select(PushDelivery).where(PushDelivery.device_id == device.id, PushDelivery.kind == "test_send").order_by(PushDelivery.created.desc()))
        if payload["action"] == "queue":
            if previous:
                raise ValueError("one_delivery_already_exists_no_resend")
            # Existing grant/quiet/consent/session and six-per-day limiter stay
            # inside the normal product handler. No reservation is bypassed.
            result = own_test(OwnTest(mode="send"), Principal(user, session), db)
            print(json.dumps({"ok": True, "status": result["status"]}))
        else:
            print(json.dumps({"ok": True, "status": previous.status if previous else "missing", "error": previous.error_code if previous else None}))
except Exception as error:
    code = "guard_" + str(error) if isinstance(error, ValueError) else "http_" + str(error.status_code) if error.__class__.__name__ == "HTTPException" else "remote_" + type(error).__name__
    print(json.dumps({"ok": False, "code": code}))
    raise SystemExit(1)
"""


def protected_request(credentials, device_id, registered_after, action):
    payload = {
        "username": credentials["child_username"],
        "password": credentials["child_password"],
        "device_id": device_id,
        "registered_after": registered_after,
        "action": action,
    }
    command = "/opt/schulpilot/current/venv/bin/python -c " + shlex.quote(REMOTE)
    result = subprocess.run(
        ["ssh", "dorfspy", command],
        input=json.dumps(payload).encode(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=35,
        check=False,
    )
    try:
        data = json.loads(result.stdout)
    except (ValueError, UnicodeDecodeError):
        raise PushQaError("protected_ssh_result_unreadable_no_replay") from None
    if not data.get("ok"):
        # All remote error codes originate from fixed guard literals or class
        # names; never return password, SQL arguments, or raw stderr.
        code = data.get("code", "unknown")
        if not re.fullmatch(r"[a-zA-Z_0-9]+", code):
            code = "unclassified"
        raise PushQaError("protected_ssh_" + code)
    return data


def activity_state():
    data = adb("shell", "dumpsys", "activity", "activities").decode(errors="replace")
    lines = data.splitlines()
    foreground = any(PACKAGE in line for line in lines if "mResumedActivity" in line or "topResumedActivity" in line)
    stopped = False
    for index, line in enumerate(lines):
        if PACKAGE in line and "ActivityRecord{" in line:
            block = "\n".join(lines[index : index + 45])
            if re.search(r"\b(?:state|mState)=STOPPED\b", block):
                stopped = True
    events = adb("logcat", "-b", "events", "-d", "-v", "epoch").decode(errors="replace")
    stops = [float(line.split()[0]) for line in events.splitlines() if PACKAGE in line and "wm_on_stop_called" in line]
    return foreground, stopped, max(stops, default=0)


def reserve_one(version):
    path = ROOT / f"artifacts/.android-push-background-{version}-checkpoint.json"
    today = datetime.now(timezone.utc).date().isoformat()
    old = json.loads(path.read_text()) if path.exists() else {}
    if old.get("date") == today and old.get("reserved"):
        raise PushQaError("one_background_send_already_reserved_no_replay")
    claim = path.with_name(f".android-push-background-{version}-{today}-reserved.json")
    try:
        descriptor = os.open(claim, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        raise PushQaError("background_send_already_reserved_no_replay") from None
    with os.fdopen(descriptor, "w") as target:
        json.dump({"date": today, "installed_code": version, "reserved": True}, target)
    safe_write(path, {"date": today, "installed_code": version, "reserved": True})


def stop_cached_process():
    """am kill preserves FCM eligibility; force-stop would invalidate this test."""
    adb("shell", "am", "kill", PACKAGE)
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        result = subprocess.run(
            [*ADB, "shell", "pidof", PACKAGE], capture_output=True, timeout=8,
        )
        if result.returncode not in (0, 1):
            raise PushQaError("emulator_process_state_unreadable_no_message_sent")
        if not result.stdout.strip():
            return
        time.sleep(.25)
    raise PushQaError("cached_process_not_stopped_no_message_sent")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--expected-code", type=int, required=True)
    parser.add_argument("--cold-process", action="store_true", help="After observed STOPPED, kill only the cached process and require no PID before send.")
    parser.add_argument("--foreground", action="store_true", help="One additional explicit foreground test on this own device.")
    args = parser.parse_args()
    report_file = ROOT / "artifacts/android-push-background-result.json"
    report = {
        "installed_code": None,
        "synthetic_child_verified": False,
        "native_registration": False,
        "activity_stopped_before_queue": False,
        "cold_process_requested": args.cold_process,
        "process_absent_before_queue": False,
        "requested_messages": 0,
        "fcm_accepted": False,
        "android_notification_visible": False,
        "notification_opens_correct_child": False,
        "fixture_device_removed": False,
        "app_logged_out": False,
        "bell_visible": False,
    }
    observer = None
    logged_in = False
    device_id = None
    baseline_devices = set()
    try:
        credentials = load_credentials()
        package = adb("shell", "dumpsys", "package", PACKAGE).decode(errors="replace")
        match = re.search(r"\bversionCode=(\d+)", package)
        if not match or int(match[1]) != args.expected_code:
            raise PushQaError("actual_installed_version_mismatch")
        report["installed_code"] = int(match[1])
        observer = httpx.Client(base_url=BASE, headers=HEADERS, timeout=25)
        session = api_json(
            observer,
            "POST",
            "/auth/login",
            json={
                "username": credentials["child_username"],
                "password": credentials["child_password"],
                "device": "Isolated background push QA observer",
            },
        )
        observer.headers["Authorization"] = "Bearer " + session["token"]
        user = session["user"]
        if user.get("role") != "child" or not user.get("synthetic"):
            raise PushQaError("artificial_child_required")
        report["synthetic_child_verified"] = True
        overview = api_json(observer, "GET", "/children/" + user["child_id"] + "/overview")
        prefs = overview["child"]["preferences"]
        if not prefs.get("push_consent") or quiet(
            datetime.now(ZoneInfo(prefs["timezone"])), prefs["quiet_start"], prefs["quiet_end"]
        ):
            raise PushQaError("existing_fixture_consent_or_quiet_policy_blocks_test")
        baseline_devices = {row["id"] for row in api_json(observer, "GET", "/notifications/devices")}
        # The workstation and server clocks can differ. Anchor freshness to
        # the server-created observer session, never to a client timestamp.
        sessions = api_json(observer, "GET", "/auth/sessions")
        current_sessions = [row for row in sessions if row.get("current") is True]
        if len(current_sessions) != 1:
            raise PushQaError("server_observer_session_anchor_missing")
        registered_after = current_sessions[0]["created"]
        report["phase"] = "native_login"
        safe_write(report_file, report)
        # Discard only the prior QA callback Activity; no app data is cleared.
        adb("shell", "am", "force-stop", PACKAGE)
        adb(
            "shell",
            "am",
            "start",
            "-a",
            "android.intent.action.MAIN",
            "-c",
            "android.intent.category.LAUNCHER",
            "-n",
            PACKAGE + "/.MainActivity",
        )
        native_login(credentials)
        logged_in = True
        press("Benachrichtigungen")
        if "Alle anzeigen" in labels(nodes()):
            press("Alle anzeigen")
        wait("Deine Neuigkeiten")
        report["bell_visible"] = True
        press("Konto")
        if credentials["child_username"] not in labels(nodes()):
            raise PushQaError("native_identity_mismatch")
        open_device_panel()
        report["phase"] = "native_opt_in"
        safe_write(report_file, report)
        tap_node(seek_label("Zeiten & Auswahl", prefix=True))
        choose_hour("Ruhe ab")
        choose_hour("Ruhe bis")
        tap_node(seek_label("Auf diesem Gerät einschalten"))
        until = time.monotonic() + 65
        while time.monotonic() < until:
            tree = nodes()
            permission = [node for node in tree if node.get("resource-id", "").endswith(":id/permission_allow_button")]
            if permission:
                tap_node(permission[0])
            new = [
                row
                for row in api_json(observer, "GET", "/notifications/devices")
                if row["id"] not in baseline_devices and row.get("platform") == "android"
            ]
            if len(new) == 1:
                device_id = new[0]["id"]
                if new[0]["quiet_start"] != 0 or new[0]["quiet_end"] != 0:
                    raise PushQaError("only_fixture_device_quiet_hours_not_saved")
                report["native_registration"] = True
                break
        if not device_id:
            raise PushQaError("native_registration_timeout")
        before_notifications = own_notifications()
        before_home = float(adb("shell", "date", "+%s.%N").decode().strip())
        adb("shell", "input", "keyevent", "3")
        until = time.monotonic() + 25
        while time.monotonic() < until:
            foreground, stopped, stop_time = activity_state()
            if not foreground and stopped and stop_time > before_home:
                report["activity_stopped_before_queue"] = True
                break
            time.sleep(0.5)
        if not report["activity_stopped_before_queue"]:
            raise PushQaError("activity_stopped_not_proven_no_message_sent")
        if args.cold_process:
            stop_cached_process()
            report["process_absent_before_queue"] = True
        report["phase"] = "single_stopped_background_message"
        safe_write(report_file, report)
        reserve_one(report["installed_code"])
        report["queue_attempts"] = 1
        queued = protected_request(credentials, device_id, registered_after, "queue")
        if queued.get("status") != "queued":
            raise PushQaError("normal_handler_did_not_queue_test")
        report["requested_messages"] = 1
        until = time.monotonic() + 45
        while time.monotonic() < until:
            result = protected_request(credentials, device_id, registered_after, "status")
            if result.get("status") == "accepted":
                report["fcm_accepted"] = True
                break
            if result.get("status") in ("failed", "suppressed"):
                report["delivery_error"] = result.get("error")
                raise PushQaError("normal_outbox_" + result["status"])
            time.sleep(1)
        if not report["fcm_accepted"]:
            raise PushQaError("accepted_outbox_status_not_observed")
        until = time.monotonic() + 60
        while time.monotonic() < until:
            current = own_notifications()
            if current and current != before_notifications:
                break
            time.sleep(1)
        adb("shell", "cmd", "statusbar", "expand-notifications")
        until = time.monotonic() + 15
        while time.monotonic() < until:
            values = labels(nodes())
            if "SCHULPILOT" in values and BACKGROUND_BODY in values:
                report["android_notification_visible"] = True
                break
        if not report["android_notification_visible"]:
            raise PushQaError("android_background_notification_not_visible")
        tap_node(seek_label(BACKGROUND_BODY))
        wait("Deine Neuigkeiten")
        press("Konto")
        if credentials["child_username"] not in labels(nodes()):
            raise PushQaError("notification_opened_wrong_or_unauthenticated_account")
        report["notification_opens_correct_child"] = True
        if args.foreground:
            # The background message above was queued only AFTER STOPPED was
            # observed. This second, separately checkpointed action tests the
            # Flutter callback and its neutral native foreground presentation.
            from android_push import mark_send

            open_device_panel()
            seek_label("Test an dieses Gerät senden")
            mark_send(report["installed_code"])
            before = own_notifications()
            tap_node(seek_label("Test an dieses Gerät senden"))
            report["requested_messages"] += 1
            report["foreground_in_app_visible"] = False
            until = time.monotonic() + 35
            while time.monotonic() < until:
                values = labels(nodes())
                report["foreground_in_app_visible"] |= "Es gibt Neuigkeiten in SCHULPILOT." in values
                if own_notifications() != before:
                    break
                time.sleep(.3)
            # NotificationRecord alone is insufficient: inspect the actual
            # neutral text in Android's visible notification shade as well.
            foreground, _, _ = activity_state()
            report["foreground_resumed_at_delivery"] = foreground
            adb("shell", "cmd", "statusbar", "expand-notifications")
            report["foreground_android_visible"] = BACKGROUND_BODY in labels(nodes())
            adb("shell", "cmd", "statusbar", "collapse")
            result = protected_request(credentials, device_id, registered_after, "status")
            report["foreground_fcm_accepted"] = result.get("status") == "accepted"
            if not (report["foreground_fcm_accepted"] and report["foreground_android_visible"] and foreground):
                raise PushQaError("foreground_native_delivery_not_fully_observed")
    except Exception as error:
        report["blocker"] = str(error) if isinstance(error, PushQaError) else "unexpected_" + type(error).__name__
    finally:
        if logged_in:
            try:
                adb("shell", "cmd", "statusbar", "collapse")
                adb("shell", "am", "start", "-n", PACKAGE + "/.MainActivity")
                open_device_panel()
                if device_id:
                    tap_node(seek_label("Auf diesem Gerät ausschalten"))
                press("Konto öffnen")
                press("Abmelden")
                wait("Willkommen zurück")
                report["app_logged_out"] = True
            except Exception:
                report["cleanup_ui_incomplete"] = True
        if observer:
            try:
                if device_id:
                    remaining = api_json(observer, "GET", "/notifications/devices")
                    if any(row["id"] == device_id for row in remaining):
                        api_json(observer, "DELETE", "/notifications/devices/" + device_id)
                    report["fixture_device_removed"] = not any(
                        row["id"] == device_id for row in api_json(observer, "GET", "/notifications/devices")
                    )
                api_json(observer, "POST", "/auth/logout")
            except Exception:
                report["cleanup_observer_incomplete"] = True
            observer.close()
        try:
            adb("shell", "rm", "-f", "/sdcard/schulpilot-window.xml")
        except Exception:
            pass
        safe_write(report_file, report)
        print(json.dumps(report))
    return int(
        bool(report.get("blocker") or report.get("cleanup_ui_incomplete") or report.get("cleanup_observer_incomplete"))
    )


if __name__ == "__main__":
    raise SystemExit(main())
