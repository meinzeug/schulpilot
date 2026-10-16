"""Native APK23 page review, at most two own fixed Demo families, zero AI.

Run only after Root's explicit GO and completed real OTA22→23 test:
  python qa/android_page_review.py --run-after-root-go

No installation, provider request, foreign fixture or real child data is used.
--cleanup-only retries only normal deletion of this driver's own saved families.
"""

import argparse
import json
import os
import re
import time

import httpx
from android_smoke import (
    ADB,
    ARTIFACTS,
    BASE,
    HEADERS,
    PACKAGE,
    adb,
    check,
    login,
    nodes,
    press,
    screenshot,
    tap_node,
)

PRIVATE = ARTIFACTS / ".android-page-review-accounts.json"
REPORT = ARTIFACTS / "android-page-review-result.json"
MARKER = "own-android-page-review-v1"
VERSION = 23
PHASE = "not_started"


def checkpoint(value):
    global PHASE
    PHASE = value
    print(json.dumps({"phase": value}), flush=True)


def save_private(data):
    temporary = PRIVATE.with_suffix(".new")
    with os.fdopen(os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600), "w") as stream:
        json.dump(data, stream)
        stream.write("\n")
    temporary.replace(PRIVATE)


def target():
    if ADB[-2:] != ["-s", "emulator-5580"]:
        raise RuntimeError("Only the dedicated test emulator is allowed")
    if adb("emu", "avd", "name").decode().splitlines()[0] != "schulpilot-qa-api36":
        raise RuntimeError("Unexpected Android virtual device")
    package = adb("shell", "dumpsys", "package", PACKAGE).decode(errors="replace")
    version = re.search(r"\bversionCode=(\d+)", package)
    if not version or int(version[1]) != VERSION:
        raise RuntimeError("APK23 must already be installed through Root's real updater test")


def text(node):
    return node.get("content-desc", "") + "\n" + node.get("text", "")


def no_checkbox(tree):
    if any("CheckBox" in node.get("class", "") or node.get("checkable") == "true" for node in tree):
        raise RuntimeError("Page review still exposes an unexpected checkbox")


def contains(fragment, seconds=25):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        matches = [node for node in nodes() if fragment in text(node)]
        if matches:
            return matches
        time.sleep(0.3)
    raise RuntimeError("Expected native page-review state did not appear")


def top():
    for _ in range(3):
        adb("shell", "input", "swipe", "900", "650", "900", "1950", "250")


def scan_page(label=None, *, absent=()):
    """Check the entire bounded review and reveal an enabled action if needed."""
    top()
    seen = set()
    for _ in range(24):
        tree = nodes()
        no_checkbox(tree)
        if any(value in text(node).splitlines() for value in absent for node in tree):
            raise RuntimeError("A protected material action is still exposed to the child")
        if label:
            matches = [node for node in tree if label in text(node).splitlines()]
            if matches:
                enabled = [node for node in matches if node.get("enabled") == "true"]
                if not enabled:
                    raise RuntimeError("The direct page action is disabled")
                return (next((node for node in enabled if node.get("clickable") == "true"), enabled[-1]))
        fingerprint = tuple((node.get("bounds"), text(node)) for node in tree)
        if fingerprint in seen:
            break
        seen.add(fingerprint)
        adb("shell", "input", "swipe", "900", "1700", "900", "1250", "450")
    if label:
        raise RuntimeError("The expected direct page action was not reachable")
    return None


def zero_usage(parent, family_id):
    usage = check(parent.get(f"/families/{family_id}/usage"))
    if usage["calls_used"] != 0 or usage["records"]:
        raise RuntimeError("A page-only action unexpectedly created AI usage")


def owner(demo):
    client = httpx.Client(base_url=BASE, headers=HEADERS, timeout=25, follow_redirects=False)
    client.headers["Authorization"] = "Bearer " + demo["token"]
    return client


def verify_own(demo):
    families = demo.get("user", {}).get("families", [])
    credentials = demo.get("credentials", {})
    if (
        len(families) != 1 or not families[0].get("synthetic")
        or not re.fullmatch(r"eltern-[a-f0-9]{10}", credentials.get("parent_username", ""))
        or not re.fullmatch(r"kind-[a-f0-9]{10}", credentials.get("child_username", ""))
        or not demo.get("child_id") or not demo.get("material_id")
    ):
        raise RuntimeError("Only this driver's newly created fixed Demo family may be used")
    return families[0]["id"]


def open_native_page(demo):
    # No install/upgrade path: Root owns the already completed OTA test.
    if b"Success" not in adb("shell", "pm", "clear", PACKAGE):
        raise RuntimeError("Dedicated test app data could not be cleared")
    adb("shell", "am", "start", "-n", PACKAGE + "/.MainActivity")
    login(demo["credentials"]["child_username"], demo["credentials"]["child_password"])
    contains("Hallo,")
    press("Hefte")
    contains("Meine Hefte")
    contains("1–1 von 1 Seiten")
    for _ in range(18):
        candidates = [node for node in nodes() if "Brüche" in text(node) and node.get("clickable") == "true"]
        if candidates:
            tap_node(candidates[0])
            contains("Dein Lernstoff")
            return
        adb("shell", "input", "swipe", "900", "1700", "900", "1250", "450")
    raise RuntimeError("The only synthetic fraction page was not reachable")


def wait_material(parent, material_id, *, confirmed=False, deleted=False):
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        response = parent.get("/materials/" + material_id)
        if deleted and response.status_code == 404:
            return
        material = check(response)
        if not deleted and material["confirmed"] is confirmed:
            return material
        time.sleep(0.4)
    raise RuntimeError("The actual page mutation was not persisted")


def run_case(demo, mode):
    family_id = verify_own(demo)
    with owner(demo) as parent, httpx.Client(base_url=BASE, headers=HEADERS, timeout=25) as observer:
        original = check(parent.get("/materials/" + demo["material_id"]))
        if original["confirmed"] or not original["synthetic"] or original.get("school_day_id") or original.get("fixture_id"):
            raise RuntimeError("Expected the fresh standalone unconfirmed Demo page")
        listing = check(parent.get(f"/children/{demo['child_id']}/materials"))
        if listing["total"] != 1:
            raise RuntimeError("Expected exactly one own artificial page")
        zero_usage(parent, family_id)
        observer_login = check(observer.post("/auth/login", json={
            "username": demo["credentials"]["child_username"], "password": demo["credentials"]["child_password"],
            "device": "Own Android page-review session observer",
        }))
        if observer_login["user"].get("role") != "child" or observer_login["user"].get("child_id") != demo["child_id"]:
            raise RuntimeError("Independent child session does not belong to the own artificial fixture")
        observer.headers["Authorization"] = "Bearer " + observer_login["token"]
        demo["observer_token"] = observer_login["token"]
        checkpoint(mode + "_native_child_login")
        open_native_page(demo)
        checkpoint(mode + "_direct_page_review")
        confirm = scan_page("Stimmt, weiter")
        screenshot("android-page-review-" + mode + "-before.png")
        if mode == "confirm":
            # This is the only confirmation action: no checkbox or API PUT.
            tap_node(confirm)
            checkpoint("confirm_check_persisted_source_and_protected_actions")
            saved = wait_material(parent, demo["material_id"], confirmed=True)
            if any(saved[key] != original[key] for key in ("subject", "topic", "content", "homework")):
                raise RuntimeError("Direct confirmation unexpectedly changed the prepared source")
            scan_page(absent=("Stimmt, weiter", "Seite löschen"))
            screenshot("android-page-review-confirmed.png")
            if observer.delete("/materials/" + demo["material_id"]).status_code != 403:
                raise RuntimeError("Child backend access did not protect the confirmed source")
            adb("shell", "input", "keyevent", "4")
            contains("Meine Hefte")
            contains("1–1 von 1 Seiten")
        else:
            checkpoint("delete_cancel_dialog")
            tap_node(scan_page("Seite löschen"))
            contains("Seite löschen?")
            checkpoint("delete_confirm_dialog")
            screenshot("android-page-review-delete-dialog.png")
            press("Abbrechen")
            wait_material(parent, demo["material_id"], confirmed=False)
            scan_page("Stimmt, weiter")
            tap_node(scan_page("Seite löschen"))
            contains("Seite löschen?")
            press("Bestätigen")
            wait_material(parent, demo["material_id"], deleted=True)
            contains("Hallo,")
            if any("Dein Lernstoff" in text(node) for node in nodes()):
                raise RuntimeError("Page deletion stayed on a broken material detail route")
            press("Hefte")
            contains("Meine Hefte")
            contains("Keine Ergebnisse")
            if check(parent.get(f"/children/{demo['child_id']}/materials"))["total"] != 0:
                raise RuntimeError("The deleted page remains in the actual private library")
            screenshot("android-page-review-deleted-library.png")
        zero_usage(parent, family_id)


def cleanup(demo, *, native_check=False):
    family_id = verify_own(demo)
    with owner(demo) as parent:
        if not demo.get("delete_accepted"):
            # An expired/revoked setup token is not proof of account deletion.
            # Reauthenticate normally, then verify exact own owner membership.
            authenticated = check(parent.post("/auth/login", json={
                "username": demo["credentials"]["parent_username"],
                "password": demo["credentials"]["parent_password"],
                "device": "Own Android page-review cleanup",
            }))
            user = authenticated["user"]
            families = user.get("families", [])
            if (
                user["id"] != demo["user"]["id"] or user["role"] != "parent"
                or len(families) != 1 or families[0]["id"] != family_id
                or families[0].get("permission") != "owner" or not families[0].get("synthetic")
            ):
                raise RuntimeError("Own cleanup identity or family ownership could not be verified")
            parent.headers["Authorization"] = "Bearer " + authenticated["token"]
            zero_usage(parent, family_id)
            check(parent.request("DELETE", "/account", json={"password": demo["credentials"]["parent_password"]}))
            demo["delete_accepted"] = True
        if parent.get("/auth/me").status_code != 401:
            raise RuntimeError("Deleted own owner session is still valid")
        if parent.get("/auth/me", headers={"Authorization": "Bearer " + demo["token"]}).status_code != 401:
            raise RuntimeError("Deleted original owner session is still valid")
        if demo.get("observer_token"):
            observer = parent.get("/auth/me", headers={"Authorization": "Bearer " + demo["observer_token"]})
            if observer.status_code != 401:
                raise RuntimeError("Deleted own child session is still valid")
    if native_check:
        adb("shell", "am", "force-stop", PACKAGE)
        adb("shell", "am", "start", "-n", PACKAGE + "/.MainActivity")
        contains("Willkommen zurück")
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-after-root-go", action="store_true")
    parser.add_argument("--cleanup-only", action="store_true")
    args = parser.parse_args()
    if not args.run_after_root_go:
        parser.error("Wait for Root's explicit emulator/OTA GO, then pass --run-after-root-go")
    os.umask(0o077)
    target()
    if args.cleanup_only:
        if PRIVATE.is_symlink() or PRIVATE.stat().st_mode & 0o777 != 0o600:
            raise RuntimeError("The own QA journal must remain protected")
        data = json.loads(PRIVATE.read_text())
        if data.get("marker") != MARKER or len(data.get("families", [])) > 2:
            raise RuntimeError("Unexpected private QA fixture")
    else:
        if PRIVATE.exists() or REPORT.exists():
            raise RuntimeError("Existing own run must be reviewed/cleaned; never create extra Demo families")
        data = {"marker": MARKER, "creation_attempts": 0, "families": []}
        save_private(data)
    report = {"installed_code": VERSION, "avd_verified": True, "external_ai_calls": 0, "checks": [],
              "cleanup_only": args.cleanup_only, "passed": args.cleanup_only}
    failure = None
    cleanup_failed = False
    try:
        if not args.cleanup_only:
            for mode in ("confirm", "delete"):
                checkpoint(mode + "_create_own_demo")
                data["creation_attempts"] += 1
                if data["creation_attempts"] > 2:
                    raise RuntimeError("The two-family QA limit is exhausted")
                save_private(data)
                with httpx.Client(base_url=BASE, headers=HEADERS, timeout=25, follow_redirects=False) as setup:
                    data["creation_unresolved"] = True
                    save_private(data)
                    response = setup.post("/demo")
                    if response.status_code != 201:
                        data["creation_unresolved"] = False
                    demo = check(response, 201)
                data["families"].append(demo)
                data["creation_unresolved"] = False
                save_private(data)
                verify_own(demo)
                run_case(demo, mode)
                save_private(data)
                checkpoint(mode + "_normal_account_deletion_and_session_revocation")
                cleanup(demo, native_check=True)
                demo["deleted"] = True
                save_private(data)
                report["checks"].append(mode + "_without_checkbox_native_and_persisted_zero_ai")
            report["passed"] = True
    except Exception as error:
        failure = type(error).__name__
    finally:
        for demo in data["families"]:
            if not demo.get("deleted"):
                try:
                    cleanup(demo)
                    demo["deleted"] = True
                except Exception:
                    cleanup_failed = True
        try:
            target()
            adb("shell", "am", "force-stop", PACKAGE)
            if b"Success" not in adb("shell", "pm", "clear", PACKAGE):
                raise RuntimeError("Dedicated test app data could not be cleared")
            adb("shell", "rm", "-f", "/sdcard/schulpilot-window.xml")
            report["own_emulator_app_data_cleared"] = True
        except Exception:
            cleanup_failed = True
        cleanup_failed = cleanup_failed or bool(data.get("creation_unresolved"))
        report.update({"own_demo_families_created": len(data["families"]), "creation_attempts": data["creation_attempts"],
                       "last_phase": PHASE,
                       "own_families_deleted": not data.get("creation_unresolved") and all(demo.get("deleted") for demo in data["families"]),
                       "cleanup_succeeded": not cleanup_failed})
        if failure:
            report["failure_type"] = failure
        report["passed"] = bool(report["passed"] and not cleanup_failed and not failure)
        if report["own_families_deleted"]:
            PRIVATE.unlink(missing_ok=True)
        else:
            save_private(data)
        REPORT.write_text(json.dumps(report, indent=2) + "\n")
        REPORT.chmod(0o600)
        print(json.dumps(report))
    if failure or cleanup_failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
