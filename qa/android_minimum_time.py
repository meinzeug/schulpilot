"""APK25 native minimum-time QA. --check is offline; --run needs Root's GO.

Only emulator-5580 / schulpilot-qa-api36, one new own fixed Demo family,
one deterministic synthetic unit job, no provider calls or clock/DB changes.
An interrupted run is never replaced with another Demo: use --run
--cleanup-only after reviewing the protected recovery journal.
"""

import argparse
import ast
import json
import math
import os
import re
import subprocess
import tempfile
import time
from pathlib import Path

import android_smoke as native
import httpx

VERSION = 25
MARKER = "own-android-minimum-time-v1"
PRIVATE = native.ARTIFACTS / ".android-minimum-time-qa.json"
REPORT = native.ARTIFACTS / "android-minimum-time-result.json"
PHASE = "not_started"
PREFERENCES = {"weekdays": list(range(7)), "daily_minutes": 5, "weekly_minutes": 5,
               "session_minutes": 5, "break_minutes": 5, "timezone": "Europe/Berlin"}


def checkpoint(value):
    global PHASE
    PHASE = value
    print(json.dumps({"phase": value}), flush=True)


def save(data):
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=PRIVATE.parent, prefix=PRIVATE.name + ".", delete=False) as stream:
            temporary = Path(stream.name)
            os.fchmod(stream.fileno(), 0o600)
            json.dump(data, stream)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        temporary.replace(PRIVATE)
    finally:
        if temporary:
            temporary.unlink(missing_ok=True)


def load():
    if PRIVATE.is_symlink() or PRIVATE.stat().st_mode & 0o777 != 0o600:
        raise RuntimeError("Protected own recovery journal required")
    data = json.loads(PRIVATE.read_text())
    if data.get("marker") != MARKER or data.get("creation_attempts") != 1:
        raise RuntimeError("Unexpected own fixture journal")
    return data


def bounded_adb(*args):
    if native.ADB[-2:] != ["-s", "emulator-5580"] or any(arg.startswith("install") for arg in args):
        raise RuntimeError("Only the existing dedicated APK may be used")
    try:
        return subprocess.run([*native.ADB, *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              timeout=30, check=True).stdout
    except (subprocess.SubprocessError, OSError):
        raise RuntimeError("Dedicated emulator operation failed") from None


def target():
    if native.adb("emu", "avd", "name").decode().splitlines()[0] != "schulpilot-qa-api36":
        raise RuntimeError("Unexpected Android virtual device")
    package = native.adb("shell", "dumpsys", "package", native.PACKAGE).decode(errors="replace")
    version = re.search(r"\bversionCode=(\d+)", package)
    if not version or int(version[1]) != VERSION:
        raise RuntimeError("APK25 must already be installed through Root's updater test")


def labels(tree=None):
    return "\n".join(node.get("content-desc", "") + "\n" + node.get("text", "")
                     for node in (native.nodes() if tree is None else tree))


def contains(fragment, seconds=25):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if fragment in labels():
            return
        time.sleep(.3)
    raise RuntimeError("Expected native minimum-time state was not visible")


def top():
    for _ in range(3):
        native.adb("shell", "input", "swipe", "900", "650", "900", "1950", "250")


def native_clock():
    top()
    current = labels()
    day = re.search(r"Heute\s+(\d+):(\d{2})\s*/\s*5:00", current)
    unit = re.search(r"Diese Einheit\s+(\d+):(\d{2})", current)
    if not day or not unit:
        raise RuntimeError("Actual native daily and unit second clocks were not visible")
    return int(day[1]) * 60 + int(day[2]), int(unit[1]) * 60 + int(unit[2])


def verify_own(demo):
    families, credentials = demo.get("user", {}).get("families", []), demo.get("credentials", {})
    if (len(families) != 1 or families[0].get("synthetic") is not True
        or families[0].get("permission") != "owner"
        or not re.fullmatch(r"eltern-[a-f0-9]{10}", credentials.get("parent_username", ""))
        or not re.fullmatch(r"kind-[a-f0-9]{10}", credentials.get("child_username", ""))
        or not demo.get("child_id") or not demo.get("material_id")):
        raise RuntimeError("Only this driver's newly created fixed Demo family is allowed")
    return families[0]["id"]


def client(token=None):
    value = httpx.Client(base_url=native.BASE, headers=native.HEADERS, timeout=25, follow_redirects=False)
    if token:
        value.headers["Authorization"] = "Bearer " + token
    return value


def no_ai(parent, family_id):
    usage = native.check(parent.get(f"/families/{family_id}/usage"))
    if usage["calls_used"] != 0 or usage["records"]:
        raise RuntimeError("The fixed synthetic flow unexpectedly created provider usage")


def unit_view(parent, demo):
    value = native.check(parent.get("/units/" + demo["unit_id"]))
    if value["child_id"] != demo["child_id"] or value["synthetic"] is not True or value["provider"] != "synthetic":
        raise RuntimeError("The own deterministic unit could not be verified")
    return value


def actual(parent, demo):
    measured = unit_view(parent, demo)["learning_time"]
    if measured["daily_goal_minutes"] != 5 or measured["goal_required"] is not True:
        raise RuntimeError("Unexpected own daily minimum")
    return measured["daily_active_seconds"]


def screenshot(name):
    native.screenshot("android-minimum-time-" + name + ".png")


def start_app():
    native.adb("shell", "am", "start", "-n", native.PACKAGE + "/.MainActivity")


def logout():
    native.press("Konto")
    native.press("Abmelden", scroll=True)
    contains("Willkommen zurück")


def prepare(parent, data):
    demo = data["demo"]
    family_id = verify_own(demo)
    native.check(parent.put(f"/children/{demo['child_id']}/preferences", json=PREFERENCES))
    material = native.check(parent.get("/materials/" + demo["material_id"]))
    if material["confirmed"] or not material["synthetic"] or material.get("fixture_id") or material.get("school_day_id"):
        raise RuntimeError("Expected the fixed standalone unconfirmed Demo page")
    native.check(parent.put("/materials/" + material["id"] + "/confirm", json={
        **{key: material[key] for key in ("subject", "topic", "content", "homework")},
        "uncertainties_resolved": True,
    }))
    data["unit_request_attempted"] = True
    save(data)  # Do not repeat an ambiguous job reservation automatically.
    queued = native.check(parent.post(f"/children/{demo['child_id']}/units",
        headers={"Idempotency-Key": MARKER}, json={"material_id": material["id"]}), 202)
    data["job_id"] = queued["id"]
    save(data)
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        job = native.check(parent.get("/jobs/" + queued["id"]))
        if job["status"] == "completed":
            demo["unit_id"] = job["result"]["unit_id"]
            save(data)
            break
        if job["status"] == "failed":
            raise RuntimeError("The fixed synthetic unit preparation failed")
        time.sleep(.5)
    if not demo.get("unit_id") or len(unit_view(parent, demo)["questions"]) != 4:
        raise RuntimeError("Exactly one fixed four-question synthetic unit is required")
    no_ai(parent, family_id)


def run_case(parent, data, report):
    demo, credentials = data["demo"], data["demo"]["credentials"]
    family_id = verify_own(demo)
    checkpoint("native_parent_minimum_and_child_detail")
    if b"Success" not in native.adb("shell", "pm", "clear", native.PACKAGE):
        raise RuntimeError("Own dedicated app data could not be cleared")
    start_app()
    native.login(credentials["parent_username"], credentials["parent_password"])
    contains("Deine Familie")
    contains("Tagesziel offen")
    contains("0:00 / 5 Min.")
    screenshot("parent-family-before")
    native.press("Lernüberblick öffnen", scroll=True)
    contains("Tagesziel offen")
    screenshot("parent-child-before")
    logout()
    checkpoint("independent_native_child_login_and_unit")
    native.login(credentials["child_username"], credentials["child_password"])
    contains("Hallo,")
    native.press("Lernen")
    contains("Dein Lernen")
    for _ in range(20):
        candidates = [node for node in native.nodes()
                      if "Brüche" in labels([node]) and node.get("clickable") == "true"]
        if candidates:
            native.tap_node(candidates[-1])
            break
        native.adb("shell", "input", "swipe", "900", "1700", "900", "1250", "400")
    else:
        raise RuntimeError("The one own synthetic unit was not reachable normally")
    native.press("Einheit starten", scroll=True)
    if not unit_view(parent, demo)["introduction_seen"]:
        native.press("Weiter zu den Übungen", scroll=True)
    first = unit_view(parent, demo)["questions"][0]
    if first["type"] != "choice" or len(first["options"]) < 2:
        raise RuntimeError("The fixed first choice task changed")
    checkpoint("real_foreground_interactions_35_seconds")
    started = time.monotonic()
    index = 0
    while time.monotonic() - started < 35:
        native.press(first["options"][index % 2], scroll=True)
        index += 1
        time.sleep(min(3, max(0, 35 - (time.monotonic() - started))))
    foreground_seconds = round(time.monotonic() - started, 2)
    displayed, _ = native_clock()
    if not 20 <= actual(parent, demo) < 300 or not 20 <= displayed < 300:
        raise RuntimeError("Native/server active time did not remain genuinely below the five-minute minimum")
    screenshot("child-running-clock")
    # Finish just one question: this flushes its real partial interval and
    # proves persisted work, while preventing a coach/follow-up job.
    native.press("Ein Hinweis bitte", scroll=True)
    native.press(first["answer"], scroll=True)
    native.press("Antwort prüfen", scroll=True)
    contains("Richtig!")
    saved = unit_view(parent, demo)
    if (len(saved["questions"][0]["attempts"]) != 1
        or saved["questions"][0]["attempts"][0]["assisted"] is not True
        or saved["status"] != "active"):
        raise RuntimeError("The single own hinted answer was not persisted normally")
    native.press("Weiter", scroll=True)
    checkpoint("background_20_seconds_without_credit")
    native.adb("shell", "input", "keyevent", "3")
    activity = native.adb("shell", "dumpsys", "activity", "activities").decode(errors="replace")
    resumed = [line for line in activity.splitlines() if "mResumedActivity" in line or "topResumedActivity" in line]
    if any(native.PACKAGE in line for line in resumed):
        raise RuntimeError("The own app did not leave foreground")
    time.sleep(2)  # Settle only an already dispatched pre-background pulse.
    before = actual(parent, demo)
    time.sleep(20)
    if actual(parent, demo) != before:
        raise RuntimeError("Background time was incorrectly credited")
    resumed_at = time.monotonic()
    start_app()
    after = actual(parent, demo)
    if not 0 <= after - before <= math.ceil(time.monotonic() - resumed_at) + 1:
        raise RuntimeError("Resume credited more than genuine foreground wall time")
    native_clock()
    native.press("Pause", scroll=True)
    if unit_view(parent, demo)["status"] != "paused":
        raise RuntimeError("Deliberate pause was not persisted")
    final = actual(parent, demo)
    if not 20 <= final < 300:
        raise RuntimeError("The test minimum must remain unmet")
    no_ai(parent, family_id)
    checkpoint("parent_matches_actual_child_time_and_role_guards")
    logout()
    native.login(credentials["parent_username"], credentials["parent_password"])
    contains("Deine Familie")
    native_counter = f"{final // 60}:{final % 60:02d} / 5 Min."
    contains(native_counter)
    contains("Tagesziel offen")
    screenshot("parent-family-after")
    native.press("Lernüberblick öffnen", scroll=True)
    contains(native_counter)
    screenshot("parent-child-after")
    family = native.check(parent.get("/families/" + family_id))
    child = next(child for child in family["children"] if child["id"] == demo["child_id"])
    overview = native.check(parent.get(f"/children/{demo['child_id']}/overview?compact=true"))
    if child["learning_time"]["daily_active_seconds"] != final or overview["plan"]["daily_active_seconds"] != final:
        raise RuntimeError("Parent and child saved active time disagree")
    with client() as observer:
        login = native.check(observer.post("/auth/login", json={
            "username": credentials["child_username"], "password": credentials["child_password"],
            "device": "Own minimum-time QA session observer",
        }))
        if login["user"].get("role") != "child" or login["user"].get("child_id") != demo["child_id"]:
            raise RuntimeError("Independent own child identity mismatch")
        data["observer_token"] = login["token"]
        save(data)
        observer.headers["Authorization"] = "Bearer " + login["token"]
        if observer.put(f"/children/{demo['child_id']}/preferences", json=PREFERENCES).status_code != 403:
            raise RuntimeError("Child changed binding parent minimum")
    if parent.post(f"/units/{demo['unit_id']}/start").status_code != 403:
        raise RuntimeError("Parent could impersonate child learning")
    report.update({"foreground_interaction_seconds": foreground_seconds, "saved_active_seconds": final,
                   "background_seconds": 20, "background_credit_seconds": 0,
                   "resume_credit_seconds": after - before, "synthetic_unit_jobs": 1,
                   "persisted_answers": 1, "parent_matches_child": True, "external_ai_calls": 0})


def cleanup(data):
    demo = data.get("demo")
    if not demo:
        if data.get("creation_unresolved"):
            raise RuntimeError("Ambiguous Demo creation needs operator recovery; never retry creation")
        return
    family_id = verify_own(demo)
    with client(demo["token"]) as parent:
        if not data.get("delete_accepted"):
            login = native.check(parent.post("/auth/login", json={
                "username": demo["credentials"]["parent_username"],
                "password": demo["credentials"]["parent_password"], "device": "Own minimum-time QA cleanup",
            }))
            families = login["user"].get("families", [])
            if (login["user"].get("id") != demo["user"]["id"] or login["user"].get("role") != "parent"
                or len(families) != 1 or families[0]["id"] != family_id
                or families[0].get("permission") != "owner" or not families[0].get("synthetic")):
                raise RuntimeError("Own cleanup ownership could not be verified")
            parent.headers["Authorization"] = "Bearer " + login["token"]
            no_ai(parent, family_id)
            data["provider_usage_verified_zero"] = True
            native.check(parent.request("DELETE", "/account", json={"password": demo["credentials"]["parent_password"]}))
            data["delete_accepted"] = True
            save(data)
        for token in (demo["token"], data.get("observer_token"), parent.headers.get("Authorization", "")[7:]):
            if token and parent.get("/auth/me", headers={"Authorization": "Bearer " + token}).status_code != 401:
                raise RuntimeError("Deleted own session remains valid")
    target()
    native.adb("shell", "am", "force-stop", native.PACKAGE)
    start_app()
    contains("Willkommen zurück")
    screenshot("deleted-login")
    if b"Success" not in native.adb("shell", "pm", "clear", native.PACKAGE):
        raise RuntimeError("Own emulator app data could not be cleared")
    native.adb("shell", "rm", "-f", "/sdcard/schulpilot-window.xml")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="Offline syntax and fixed-target check; no API/ADB")
    mode.add_argument("--run", action="store_true", help="Only after explicit Root GO and real OTA to APK25")
    parser.add_argument("--cleanup-only", action="store_true")
    args = parser.parse_args()
    if args.check:
        ast.parse(Path(__file__).read_text())
        if native.ADB[-2:] != ["-s", "emulator-5580"] or VERSION != 25:
            raise RuntimeError("Unexpected offline QA target")
        print(json.dumps({"offline_check": True, "network_calls": 0, "adb_calls": 0, "required_apk_code": VERSION}))
        return
    os.umask(0o077)
    native.adb = bounded_adb
    target()
    if args.cleanup_only:
        data = load()
    else:
        if PRIVATE.exists() or REPORT.exists():
            raise RuntimeError("Review/recover the previous own run before creating any family")
        data = {"marker": MARKER, "creation_attempts": 1, "creation_unresolved": True}
        save(data)
    report = {"passed": False, "installed_code": VERSION, "avd_verified": True, "external_ai_calls": None,
              "mode": "cleanup_only" if args.cleanup_only else "full_native_qa", "qa_completed": False}
    failure = None
    cleaned = False
    try:
        if not args.cleanup_only:
            checkpoint("create_exactly_one_own_fixed_demo")
            with client() as setup:
                response = setup.post("/demo")
                if response.status_code != 201:
                    data["creation_unresolved"] = False
                    save(data)
                data["demo"] = native.check(response, 201)
            data["creation_unresolved"] = False
            save(data)
            with client(data["demo"]["token"]) as parent:
                prepare(parent, data)
                run_case(parent, data, report)
                report["qa_completed"] = True
        report["passed"] = True
    except Exception as error:
        failure = type(error).__name__
        report["failed_phase"] = PHASE
    finally:
        try:
            checkpoint("normal_own_account_deletion_and_session_revocation")
            cleanup(data)
            cleaned = True
        except Exception as error:
            cleaned = False
            report["cleanup_failure_type"] = type(error).__name__
        if data.get("provider_usage_verified_zero"):
            report["external_ai_calls"] = 0
        report.update({"passed": report["passed"] and cleaned and failure is None,
                       "cleanup_succeeded": cleaned, "last_phase": PHASE,
                       "creation_attempts": data["creation_attempts"], "failure_type": failure})
        REPORT.write_text(json.dumps(report, indent=2) + "\n")
        REPORT.chmod(0o600)
        if report["passed"]:
            PRIVATE.unlink(missing_ok=True)
        else:
            save(data)
        print(json.dumps(report))
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
