"""Native Flutter/Android document picker; original synthetic PDFs and own family."""

import io
import json
import re
import zipfile

import android_smoke as native
import httpx
from android_material_words import login, read, require
from android_update import installed_code, launch

PRIVATE = native.ARTIFACTS / ".school-day-qa-account.json"


def open_grades():
    native.wait("Deine Familie")
    native.press("Lernüberblick öffnen", scroll=True)
    native.press("Noten")
    native.wait("PDF importieren")


def choose_pdf(variant):
    local = native.ARTIFACTS / f"grades-synthetic-{variant}.pdf"
    name = f"SCHULPILOT-Notenprobe-{variant}.pdf"
    native.adb("push", str(local), "/sdcard/Download/" + name)
    native.press("PDF importieren")
    native.press("PDF auswählen")
    native.wait_any([name, "Show roots", "Downloads"], seconds=35)
    if not native.matching(name):
        if native.matching("Show roots"):
            native.press("Show roots")
        native.press("Downloads")
    native.press(name)
    native.wait("Auswahl übernehmen")


def main():
    account = json.loads(PRIVATE.read_text())
    state = account.get("grade_pdf_qa", {})
    require(account.get("normal_account") and account.get("verified") and state.get("phase") == "web_passed_native_pending"
            and re.search(r"\+schulpilot-normal-qa-[a-f0-9]{12}@", account["credentials"]["parent_username"]), "own_web_fixture_required")
    require(installed_code() == 35, "actual_ota35_required")
    require(native.adb("emu", "avd", "name").decode().splitlines()[0] == "schulpilot-qa-api36", "own_dedicated_avd_required")
    phase, checks = "login", []
    report = {"success": False, "native_flutter": True, "installed_code": 35, "android_api": 36, "checks": checks}
    try:
        with httpx.Client(base_url=native.BASE, headers={**native.HEADERS, "X-Schulpilot-Capabilities": "grade-pdf-v1"}, timeout=60) as api:
            signed = api.post("/auth/login", json={"username": account["credentials"]["parent_username"],
                                                   "password": account["credentials"]["parent_password"]}).raise_for_status().json()
            require(signed["user"]["id"] == account["user"]["id"], "own_parent_required")
            api.headers["Authorization"] = "Bearer " + signed["token"]
            route = "/children/" + account["child_id"] + "/grades"
            require(read(api, route)["pagination"]["total"] in (4, 5), "owned_web_grades_required")
            launch()
            native.wait_any(["Anmelden", "Willkommen zurück", "Deine Familie"])
            if native.matching("Anmelden") and not native.matching("Willkommen zurück"):
                native.press("Anmelden")
            if native.matching("Willkommen zurück"):
                login(account["credentials"], "parent")
            open_grades()
            phase = "native_document_picker_and_append"
            choose_pdf("added")
            native.screenshot("grade-pdf-native-preview.png")
            native.press("Auswahl übernehmen")
            native.wait("Fertig")
            native.press("Fertig")
            require(read(api, route)["pagination"]["total"] == 5, "one_added_not_duplicate_required")
            checks.append("android_system_pdf_picker_and_one_new_grade")
            phase = "native_source_change_confirmation"
            choose_pdf("changed")
            if not native.matching("Übernahme"):
                native.press("Übernahme", scroll=True)
            else:
                native.press("Übernahme")
            native.press("Gespeicherte Note aktualisieren")
            native.press("Auswahl übernehmen")
            native.wait("Fertig")
            native.press("Fertig")
            grades = read(api, route)
            require(grades["pagination"]["total"] == 5 and next(g for g in grades["items"] if g["subject"] == "Englisch")["value"] == 3,
                    "confirmed_changed_grade_required")
            require(next(g for g in grades["items"] if g["id"] == state["manual_id"])["assessed_on"] is not None,
                    "manual_date_preserved_required")
            native.screenshot("grade-pdf-native-saved.png")
            checks.append("changed_source_value_requires_explicit_update")
            phase = "native_session_restore"
            native.adb("shell", "am", "force-stop", native.PACKAGE)
            launch()
            native.wait_any(["Deine Familie", "PDF importieren"])
            if not native.matching("PDF importieren"):
                open_grades()
            require(read(api, route)["pagination"]["total"] == 5, "restart_must_not_duplicate")
            native.screenshot("grade-pdf-native-reloaded.png")
            checks.append("native_restart_and_saved_grade_consistency")
            phase = "own_export_and_logout"
            family_id = account["user"]["families"][0]["id"]
            exported = api.get(f"/families/{family_id}/export").raise_for_status()
            with zipfile.ZipFile(io.BytesIO(exported.content)) as archive:
                data = json.loads(archive.read("family.json"))
            own = data["children"][0]
            require(own["child"]["id"] == account["child_id"] and len(own["school_grades"]) == len(own["grade_source_slots"]) == 5,
                    "owned_export_five_unique_grades_required")
            require(not data["usage"] and not own["attempts"], "pdf_import_must_not_invoke_ai_or_invent_learning")
            native.press("Konto")
            native.press("Abmelden", scroll=True)
            native.wait("Willkommen zurück")
            api.post("/auth/logout").raise_for_status()
            state["phase"] = "native_passed"
            PRIVATE.write_text(json.dumps(account) + "\n")
            PRIVATE.chmod(0o600)
            report.update(success=True, total_grades=5, source_slots=5, provider_calls=0, invented_attempts=0)
    except Exception:
        report["failed_phase"] = phase
        native.screenshot("grade-pdf-native-failure.png")
        raise
    finally:
        for variant in ("added", "changed"):
            native.adb("shell", "rm", "-f", f"/sdcard/Download/SCHULPILOT-Notenprobe-{variant}.pdf")
        result = native.ARTIFACTS / "grade-pdf-native-result.json"
        result.write_text(json.dumps(report) + "\n")
        result.chmod(0o600)
        print(json.dumps(report), flush=True)


if __name__ == "__main__":
    main()
