"""Native signed catalog/album release, only the own artificial web dataset.

Requires the real OTA upgrade and successful public photo/provider chain first.
Credentials use ADB stdin. No new model call, real-family access or video claim.
"""

import hashlib
import json
import re
import time

import android_smoke as native
import httpx
from android_material_words import login, read, require
from android_notebooks import toolbar
from android_update import installed_code, launch

PRIVATE = native.ARTIFACTS / ".school-day-qa-account.json"


def reveal(name):
    width, height = map(int, re.findall(r"(\d+)x(\d+)", native.adb("shell", "wm", "size").decode())[-1])
    for _ in range(18):
        if native.matching(name):
            return
        native.adb("shell", "input", "swipe", str(width * 9 // 10), str(height * 7 // 10),
                   str(width * 9 // 10), str(height // 2), "450")
    raise RuntimeError("Expected native catalog control stayed off-screen")


def main():
    account = json.loads(PRIVATE.read_text())
    state = account.get("catalog_qa", {})
    require(account.get("normal_account") and account.get("verified") and
            state.get("phase") in ("web_passed_native_pending", "native_passed") and
            re.search(r"\+schulpilot-normal-qa-[a-f0-9]{12}@", account["credentials"]["parent_username"]),
            "own_successful_public_catalog_dataset_required")
    require(installed_code() == 38, "real_upgrade_to_current_signed_apk_required")
    require(native.adb("emu", "avd", "name").decode().splitlines()[0] == "schulpilot-qa-api36", "own_avd_required")
    checks, phase, identity_verified = [], "native_child_login", False
    report = {"success": False, "installed_code": 38, "native_flutter": True, "android_api": 36,
              "additional_model_calls": 0, "checks": checks,
              "dataset_key": hashlib.sha256(account["child_id"].encode()).hexdigest()}
    try:
        native.adb("shell", "am", "force-stop", native.PACKAGE)
        launch()
        native.wait_any(["Anmelden", "Willkommen zurück", "Heute"])
        if native.matching("Anmelden") and not native.matching("Willkommen zurück"):
            native.press("Anmelden")
        if native.matching("Willkommen zurück"):
            login(account["credentials"], "child")
        native.press("Konto")
        native.wait(account["credentials"]["child_username"])
        identity_verified = True
        native.press("Hefte")
        native.wait("Meine Hefte")
        native.screenshot("catalog-native-fixed-subjects.png")
        native.press("Mathematik, 2 Seiten, Hefter öffnen", scroll=True)
        native.wait("1 von 2")
        native.press("Nächste Seite", scroll=True)
        native.wait("2 von 2")
        native.press("Vergrößern", scroll=True)
        native.wait("Heftfoto")
        native.screenshot("catalog-native-real-photo-zoom.png")
        native.press("Schließen")
        checks.append("native_actual_private_photo_album_turn_and_zoom")
        phase = "native_catalog_browser"
        toolbar()
        native.press("Themen entdecken", scroll=True)
        # Flutter exposes the empty search label as Android hint text, not text.
        native.wait("Meine Stufe")
        require(any(n.get("class") == "android.widget.EditText" for n in native.nodes()), "native_topic_search_missing")
        require(not native.matching("Stufe einstellen"), "child_must_not_change_parent_level")
        native.press("Meine Stufe")
        native.screenshot("catalog-native-known-level-topic-browser.png")
        native.press("Schließen")
        checks.append("native_topic_browser_known_class_and_parent_only_level")
        phase = "native_source_tips"
        native.press("Lerntipps", scroll=True)
        reveal("Bei Sofatutor ansehen")
        native.screenshot("catalog-native-source-tips.png")
        # The operating-system chooser/browser is an external-link check only.
        native.press("Bei Sofatutor ansehen", scroll=True)
        time.sleep(2)
        top = native.adb("shell", "dumpsys", "activity", "activities").decode()
        require("sofatutor.com" in top or any(name in top for name in ("com.android.chrome", "org.chromium", "ResolverActivity")),
                "native_https_link_intent_missing")
        native.screenshot("catalog-native-external-https.png")
        # Explicit launch restores our app and exercises its foreground update check.
        launch()
        native.wait("Hefte")
        checks.append("native_real_external_https_intent_no_playback_claim")
        phase = "native_grid_list_and_restart"
        toolbar()
        native.press("Kacheln", scroll=True)
        native.wait("1–2 von 2")
        native.screenshot("catalog-native-pages-grid.png")
        native.press("Liste", scroll=True)
        native.screenshot("catalog-native-pages-list.png")
        native.adb("shell", "am", "force-stop", native.PACKAGE)
        launch()
        native.wait("Heute")
        native.press("Hefte")
        native.wait("Meine Hefte")
        native.press("Konto")
        native.press("Abmelden", scroll=True)
        native.wait("Willkommen zurück")
        checks.append("native_grid_list_secure_restart_and_logout")
        with httpx.Client(base_url=native.BASE, headers=native.HEADERS, timeout=30) as api:
            signed = api.post("/auth/login", json={"username": account["credentials"]["parent_username"],
                                                   "password": account["credentials"]["parent_password"]}).raise_for_status().json()
            require(signed["user"]["id"] == account["user"]["id"], "own_parent_required")
            api.headers["Authorization"] = "Bearer " + signed["token"]
            progress = read(api, "/children/" + account["child_id"] + "/learning-progress")
            require(progress["totals"]["practiced_tasks"] == 0, "external_links_are_not_solved_tasks")
            family_id = account["user"]["families"][0]["id"]
            usage = read(api, "/families/" + family_id + "/usage")
            require(usage["calls_used"] == 4, "only_four_explicit_normal_ai_jobs_expected")
            api.post("/auth/logout").raise_for_status()
        state["phase"] = "native_passed"
        PRIVATE.write_text(json.dumps(account) + "\n")
        PRIVATE.chmod(0o600)
        report.update(success=True, own_photos=2, actual_reserved_ai_jobs=4, invented_attempts=0)
    except Exception:
        report["failed_phase"] = phase
        if identity_verified:
            native.screenshot("catalog-native-failure.png")
        raise
    finally:
        file = native.ARTIFACTS / "catalog-native-result.json"
        file.write_text(json.dumps(report) + "\n")
        file.chmod(0o600)
        print(json.dumps(report), flush=True)


if __name__ == "__main__":
    main()
