"""Observe notebook actions in the signed APK; cancel every destructive/AI action.

Run only after the operator has completed the dedicated emulator's OTA update.
The normal artificial household must already contain a confirmed Mathematics
photo. This driver creates no account, photo, exercise, answer or provider job.
Credentials, source snapshots and UI screenshots never leave ignored artifacts.
"""

import argparse
import hashlib
import json
import re
import time

import android_smoke as native
import httpx
from android_design import login, read, require
from android_update import installed_code, launch

PRIVATE = native.ARTIFACTS / ".school-day-qa-account.json"
REPORT = native.ARTIFACTS / "notebook-actions-android-result.json"


def dimensions():
    values = re.findall(r"(\d+)x(\d+)", native.adb("shell", "wm", "size").decode())
    require(bool(values), "dedicated_screen_dimensions_missing")
    return tuple(map(int, values[-1]))


def density():
    values = re.findall(r"density:\s*(\d+)", native.adb("shell", "wm", "density").decode())
    require(bool(values), "dedicated_screen_density_missing")
    return int(values[-1]) / 160


def bounds(node):
    result = list(map(int, re.findall(r"\d+", node.get("bounds", ""))))
    require(len(result) == 4, "native_control_bounds_missing")
    return result


def visible(name):
    width, height = dimensions()
    return [node for node in native.matching(name)
            if (box := bounds(node))[2] > box[0] and box[3] > box[1]
            and box[0] >= 0 and box[2] <= width and box[1] >= 0 and box[3] <= height]


def scroll_up():
    width, height = dimensions()
    native.adb("shell", "input", "swipe", str(width // 2), str(height // 4),
               str(width // 2), str(height * 3 // 4), "400")


def press(name, *, scroll=False):
    # All coordinates follow the current screen override, including 320dp.
    found = visible(name)
    if not found and scroll:
        for _ in range(4):
            scroll_up()
        for _ in range(35):
            found = visible(name)
            if found:
                break
            width, height = dimensions()
            native.adb("shell", "input", "swipe", str(width // 2), str(height * 3 // 4),
                       str(width // 2), str(height // 2), "450")
    if not found:
        native.wait(name)
        found = visible(name)
    require(bool(found), "native_notebook_control_not_visible")
    clickable = [node for node in found if node.get("clickable") == "true"]
    native.tap_node((clickable or found)[-1])


def touch_target(name):
    # UiAutomator bounds are physical pixels. Compare against actual density,
    # not against a guessed emulator scale or the icon's 24dp artwork.
    found = visible(name)
    require(bool(found), "native_notebook_action_not_visible")
    clickable = [node for node in found if node.get("clickable") == "true"]
    box = bounds((clickable or found)[-1])
    smallest_dp = min(box[2] - box[0], box[3] - box[1]) / density()
    require(smallest_dp >= 47.5, "native_notebook_action_below_48dp")
    return round(smallest_dp, 2)


def toolbar():
    for _ in range(10):
        if visible("Blättern") and visible("Liste"):
            return
        scroll_up()
    raise RuntimeError("native_notebook_toolbar_not_visible")


def snapshot(api, account):
    child = account["child_id"]
    materials = read(api, f"/children/{child}/materials?page_size=50")
    require(materials["total"] <= 50, "bounded_artificial_household_required")
    sources = []
    for item in sorted(materials["items"], key=lambda row: row["id"]):
        source = read(api, "/materials/" + item["id"])
        sources.append({key: source.get(key) for key in (
            "id", "revision", "confirmed", "subject_id", "subject", "topic", "content", "homework",
        )})
    progress = read(api, f"/children/{child}/learning-progress")
    overview = read(api, f"/children/{child}/overview?compact=true")
    usage = read(api, f"/families/{account['user']['families'][0]['id']}/usage")
    return {
        "materials": sources,
        "progress_totals": progress["totals"],
        "daily_active_seconds": overview["plan"].get("daily_active_seconds"),
        "weekly_active_seconds": overview["plan"].get("weekly_active_seconds"),
        "usage_calls": usage["calls_used"],
        "usage_records": usage["records"],
    }


def open_folder(title, count):
    press("Hefte")
    native.wait("Meine Hefte")
    press(f"{title}, {count} {'Seite' if count == 1 else 'Seiten'}, Hefter öffnen", scroll=True)
    toolbar()
    press("Blättern")
    native.wait(f"1 von {count}")


def cancel_dialog(title):
    native.wait(title)
    press("Abbrechen", scroll=True)


def logout_if_own(account):
    # Closing a dialog is safe; never choose its affirmative action.
    if visible("Abbrechen"):
        press("Abbrechen")
    if visible("Willkommen zurück"):
        return True
    if not visible("Konto"):
        return False
    press("Konto")
    native.wait(account["credentials"]["child_username"])
    press("Abmelden", scroll=True)
    native.wait("Willkommen zurück")
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=int, default=50)
    parser.add_argument("--large-text", action="store_true", help="Also observe actual 200%% text at 320dp")
    args = parser.parse_args()
    require(PRIVATE.stat().st_mode & 0o077 == 0, "private_checkpoint_permissions_required")
    account = json.loads(PRIVATE.read_text())
    require(account.get("normal_account") and account.get("verified") and
            re.search(r"\+schulpilot-normal-qa-[a-f0-9]{12}@", account["credentials"]["parent_username"]),
            "owned_regular_artificial_household_required")
    require(native.adb("emu", "avd", "name").decode().splitlines()[0] == "schulpilot-qa-api36",
            "dedicated_emulator_required")
    require(installed_code() == args.build, "complete_actual_ota_before_native_actions_test")
    release = httpx.get(native.BASE + "/app-release", timeout=20).raise_for_status().json()
    require(release["version_code"] == args.build, "matching_public_build_required")
    previous_font = native.adb("shell", "settings", "get", "system", "font_scale").decode().strip()
    previous_size = native.adb("shell", "wm", "size").decode()
    override = re.search(r"Override size:\s*(\d+x\d+)", previous_size)
    checks, phase = [], "own_parent_observer_login"
    report = {"success": False, "installed_code": args.build, "native_flutter": True, "android_api": 36,
              "checks": checks, "dataset_key": hashlib.sha256(account["child_id"].encode()).hexdigest()}
    observer = httpx.Client(base_url=native.BASE, headers=native.HEADERS, timeout=30)
    try:
        signed = observer.post("/auth/login", json={
            "username": account["credentials"]["parent_username"],
            "password": account["credentials"]["parent_password"],
        })
        require(signed.status_code == 200, "owned_parent_observer_login_failed")
        parent = signed.json()
        require(parent["user"]["id"] == account["user"]["id"] and len(parent["user"]["families"]) == 1
                and parent["user"]["families"][0]["synthetic"] is False, "owned_regular_parent_required")
        observer.headers["Authorization"] = "Bearer " + parent["token"]
        subjects = read(observer, f"/children/{account['child_id']}/subjects")
        math = next((row for row in subjects["items"] if row["key"] == "mathematik"), None)
        require(math and math["page_count"] > 0, "owned_math_photo_required")
        sources = read(observer, f"/children/{account['child_id']}/materials?subject_id={math['id']}")
        require(any(row["confirmed"] and row["has_image"] and not row["fixed_example"]
                    for row in sources["items"]), "confirmed_regular_math_photo_required")
        before = snapshot(observer, account)
        phase = "native_child_login"
        native.adb("shell", "settings", "put", "system", "font_scale", "1.0")
        time.sleep(2)
        launch()
        entry, _ = native.wait_any(("Willkommen zurück", "Heute"))
        if entry == "Heute":
            require(logout_if_own(account), "normal_owned_logout_required")
        login(account["credentials"], "child")
        checks.append("normal_native_child_login_over_public_https")
        phase = "album_visible_actions"
        open_folder(math["title"], math["page_count"])
        targets = [touch_target(name) for name in ("Heftseite löschen", "Mit KI neu lesen")]
        native.screenshot("notebook-actions-native-album.png")
        checks.append("confirmed_photo_album_has_visible_48dp_delete_and_ki_actions")
        phase = "cancel_ai_and_single_delete"
        press("Mit KI neu lesen")
        cancel_dialog("Seite neu einlesen?")
        press("Heftseite löschen")
        cancel_dialog("Heftseite löschen?")
        checks.append("cancel_ai_and_single_delete_without_source_change")
        phase = "grid_and_list_actions"
        toolbar()
        press("Kacheln")
        press("Heftseite löschen", scroll=True)
        cancel_dialog("Heftseite löschen?")
        toolbar()
        press("Liste")
        native.wait("Seiten auswählen")
        native.screenshot("notebook-actions-native-list.png")
        press("Seiten auswählen", scroll=True)
        press("Seite 1 auswählen", scroll=True)
        native.wait("Auswahl löschen (1)")
        press("Alle auswählen", scroll=True)
        native.wait(f"Auswahl löschen ({math['page_count']})")
        press(f"Auswahl löschen ({math['page_count']})", scroll=True)
        cancel_dialog("Heftseite löschen?" if math["page_count"] == 1 else f"{math['page_count']} Heftseiten löschen?")
        press("Auswahl aufheben", scroll=True)
        press("Alles löschen", scroll=True)
        cancel_dialog("Heftseite löschen?" if math["page_count"] == 1 else f"{math['page_count']} Heftseiten löschen?")
        checks.append("native_grid_list_multiple_and_all_selection_with_cancelled_delete_previews")
        if args.large_text:
            phase = "small_screen_200_percent_system_text"
            scale = density()
            native.adb("shell", "wm", "size", f"{round(320 * scale)}x{round(840 * scale)}")
            native.adb("shell", "settings", "put", "system", "font_scale", "2.0")
            time.sleep(3)
            open_folder(math["title"], math["page_count"])
            # At large system text the reader actions may require a small
            # explicit scroll, but remain separate, labeled 48dp controls.
            press("Heftseite löschen", scroll=True)
            cancel_dialog("Heftseite löschen?")
            targets.append(touch_target("Mit KI neu lesen"))
            native.screenshot("notebook-actions-native-320dp-200text.png")
            toolbar()
            press("Liste")
            press("Seiten auswählen", scroll=True)
            press("Alle auswählen", scroll=True)
            native.wait(f"Auswahl löschen ({math['page_count']})")
            press("Auswahl aufheben", scroll=True)
            checks.append("actual_native_320dp_200_percent_text_keeps_reader_actions_and_multiple_selection_usable")
        phase = "server_side_no_mutation_check"
        after = snapshot(observer, account)
        require(after == before, "native_photo_views_or_cancelled_actions_changed_saved_learning_or_sources")
        checks.append("parent_api_snapshots_match_sources_attempts_time_progress_and_usage")
        report.update(success=True, minimum_action_target_dp=min(targets), additional_model_calls=0,
                      deleted_pages=0, submitted_answers=0, added_learning_seconds=0,
                      actual_200_percent_system_text=args.large_text)
    except Exception:
        report["failed_phase"] = phase
        try:
            native.screenshot("notebook-actions-native-failure.png")
        except Exception:
            pass
        raise RuntimeError("Native notebook action QA failed in " + phase) from None
    finally:
        native.adb("shell", "wm", "size", override[1] if override else "reset")
        if previous_font in {"", "null"}:
            native.adb("shell", "settings", "delete", "system", "font_scale")
        else:
            require(bool(re.fullmatch(r"[0-9.]+", previous_font)), "saved_font_scale_invalid")
            native.adb("shell", "settings", "put", "system", "font_scale", previous_font)
        time.sleep(2)
        try:
            report["normal_child_logout"] = logout_if_own(account)
        except Exception:
            report["normal_child_logout"] = False
        if observer.headers.get("Authorization"):
            observer.post("/auth/logout")
        observer.close()
        report["success"] = report["success"] and report.get("normal_child_logout") is True
        REPORT.write_text(json.dumps(report) + "\n")
        REPORT.chmod(0o600)
        print(json.dumps(report), flush=True)
    require(report["success"], "native_notebook_actions_or_normal_logout_incomplete")


if __name__ == "__main__":
    main()
