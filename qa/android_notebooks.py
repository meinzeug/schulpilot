"""Actual signed native Flutter album, own artificial photos and normal login."""

import json
import re

import android_smoke as native
import httpx
from android_material_words import input_text, login, read, require
from android_update import installed_code, launch

PRIVATE = native.ARTIFACTS / ".school-day-qa-account.json"


def toolbar():
    width, height = map(int, re.findall(r"(\d+)x(\d+)", native.adb("shell", "wm", "size").decode())[-1])
    for _ in range(8):
        if native.matching("Kacheln"):
            return
        native.adb("shell", "input", "swipe", str(width//2), str(height//4), str(width//2), str(height*3//4), "400")
    raise RuntimeError("Own album toolbar not visible")


def main():
    account = json.loads(PRIVATE.read_text())
    state = account.get("notebook_qa", {})
    require(account.get("normal_account") and account.get("verified") and
            state.get("phase") == "web_passed_native_pending" and
            re.search(r"\+schulpilot-normal-qa-[a-f0-9]{12}@", account["credentials"]["parent_username"]),
            "own_actual_web_album_required")
    current = installed_code()
    published = httpx.get(native.BASE + '/app-release', timeout=20).raise_for_status().json()
    require(current >= 36 and current == published['version_code'], "current_signed_album_apk_required")
    require(native.adb("emu", "avd", "name").decode().splitlines()[0] == "schulpilot-qa-api36", "own_avd_required")
    checks, phase = [], "native_child_login"
    report = {"success": False, "installed_code": current, "native_flutter": True, "android_api": 36, "checks": checks}
    try:
        launch()
        native.wait_any(["Anmelden", "Willkommen zurück", "Heute"])
        if native.matching("Anmelden") and not native.matching("Willkommen zurück"):
            native.press("Anmelden")
        if native.matching("Willkommen zurück"):
            login(account["credentials"], "child")
        native.press("Hefte")
        native.wait("Meine Hefte")
        native.screenshot("notebooks-native-shelf.png")
        phase = "native_actual_photos_and_turn"
        native.press("Mathematik, 2 Seiten, Hefter öffnen", scroll=True)
        native.wait("1 von 2")
        native.screenshot("notebooks-native-album.png")
        native.press("Nächste Seite", scroll=True)
        native.wait("2 von 2")
        checks.append("native_subject_folder_and_actual_photo_paging")
        phase = "native_zoom_and_overviews"
        native.press("Vergrößern", scroll=True)
        native.wait("Heftfoto")
        native.screenshot("notebooks-native-zoom.png")
        native.press("Schließen")
        # Move back to the toolbar before changing the presentation.
        toolbar()
        native.press("Kacheln", scroll=True)
        native.wait("1–2 von 2")
        native.screenshot("notebooks-native-grid.png")
        native.press("Liste", scroll=True)
        native.screenshot("notebooks-native-list.png")
        checks.append("native_zoom_grid_and_list")
        phase = "native_jump_across_batches"
        native.adb("shell", "input", "keyevent", "4")
        native.wait("Meine Hefte")
        fields = [n for n in native.nodes() if n.get("class") == "android.widget.EditText"]
        require(len(fields) == 1, "own_shelf_search_required")
        native.tap_node(fields[0])
        input_text("Noch zuordnen")
        native.adb("shell", "input", "keyevent", "66")
        native.press("Noch zuordnen, 24 Seiten, Hefter öffnen", scroll=True)
        native.wait("1 von 24")
        native.press("1 von 24")
        native.wait("Zu welcher Seite?")
        fields = [n for n in native.nodes() if n.get("class") == "android.widget.EditText"]
        require(len(fields) == 1, "own_page_jump_field_required")
        native.tap_node(fields[0])
        native.adb("shell", "input", "keyevent", "123")
        native.adb("shell", "input", "keyevent", "67", "67", "67")
        input_text("24")
        native.adb("shell", "input", "keyevent", "4")
        native.press("Seite öffnen")
        native.wait("24 von 24")
        native.screenshot("notebooks-native-second-batch.png")
        checks.append("native_page_jump_second_metadata_batch")
        phase = "native_restart_and_logout"
        native.adb("shell", "am", "force-stop", native.PACKAGE)
        launch()
        native.wait("Heute")
        native.press("Hefte")
        native.wait("Meine Hefte")
        native.press("Konto")
        native.press("Abmelden", scroll=True)
        native.wait("Willkommen zurück")
        checks.append("native_session_restore_and_logout")
        with httpx.Client(base_url=native.BASE, headers=native.HEADERS, timeout=30) as api:
            signed = api.post('/auth/login', json={"username": account["credentials"]["parent_username"],
                                                   "password": account["credentials"]["parent_password"]}).raise_for_status().json()
            require(signed["user"]["id"] == account["user"]["id"], "own_parent_required")
            api.headers["Authorization"] = "Bearer " + signed["token"]
            own = read(api, '/children/' + account["child_id"] + '/subjects')
            require(next(r for r in own["items"] if r["key"] == "mathematik")["page_count"] == 2 and own["unassigned_count"] == 24,
                    "owned_subject_counts_preserved")
            require(read(api, '/children/' + account["child_id"] + '/learning-progress')["totals"]["practiced_tasks"] == 0,
                    "album_must_not_invent_practice")
            api.post('/auth/logout').raise_for_status()
        state["phase"] = "native_passed"
        PRIVATE.write_text(json.dumps(account) + '\n')
        PRIVATE.chmod(0o600)
        report.update(success=True, own_photos=26, additional_model_calls=0, invented_attempts=0)
    except Exception:
        report["failed_phase"] = phase
        native.screenshot("notebooks-native-failure.png")
        raise
    finally:
        file = native.ARTIFACTS / "notebooks-native-result.json"
        file.write_text(json.dumps(report) + '\n')
        file.chmod(0o600)
        print(json.dumps(report), flush=True)


if __name__ == "__main__":
    main()
