"""Actual native Flutter release41; only the public smoke's own artificial family.

The parent API supplies fixture expectations for this automated QA run; no keys
are added to the child payload. Answers are entered through the real native UI.
No real learner performance or physical audio observation is inferred.
"""

import json
import re
import time

import android_smoke as native
import httpx
from android_material_words import input_text, login, read, require
from android_update import installed_code, launch

PRIVATE = native.ARTIFACTS / ".school-day-qa-account.json"
REPORT = native.ARTIFACTS / "report-review-native-result.json"


def all_text(tree=None):
    return "\n".join(n.get("text", "") + "\n" + n.get("content-desc", "") for n in (tree or native.nodes()))


def wait_fragment(value, seconds=35):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if value in all_text():
            return
        time.sleep(0.3)
    raise RuntimeError("owned_native_fragment_missing")


def open_round(topic):
    native.press("Lernen")
    wait_fragment("Dein Lernen")
    # A card with an actual question count is a saved unit, not a new homework
    # generator. Never use the Home action that could create another AI job.
    for _ in range(20):
        candidates = [
            n
            for n in native.nodes()
            if n.get("clickable") == "true" and topic in all_text([n]) and "Aufgaben" in all_text([n])
        ]
        if candidates:
            native.tap_node(candidates[-1])
            wait_fragment("Diese Einheit")
            return
        native.adb("shell", "input", "swipe", "900", "1700", "900", "1330", "350")
    raise RuntimeError("owned_saved_round_not_reachable")


def main():
    account = json.loads(PRIVATE.read_text())
    state = account.get("report_qa", {})
    require(
        account.get("normal_account")
        and account.get("verified")
        and re.search(r"\+schulpilot-normal-qa-[a-f0-9]{12}@", account["credentials"]["parent_username"])
        and state.get("phase") == "web_passed_native_pending",
        "owned_public_smoke_required",
    )
    require(installed_code() == 41, "actual_signed_release41_required")
    require(native.adb("emu", "avd", "name").decode().splitlines()[0] == "schulpilot-qa-api36", "own_avd_required")
    phase = "login"
    checks = []
    report = {
        "installed_code": 41,
        "native_flutter": True,
        "android_api": 36,
        "checks": checks,
        "physical_device": False,
        "physical_audio_observed": False,
    }
    try:
        with httpx.Client(
            base_url=native.BASE, headers={**native.HEADERS, "X-Schulpilot-Capabilities": "language-v1"}, timeout=35
        ) as api:
            signed = (
                api.post(
                    "/auth/login",
                    json={
                        "username": account["credentials"]["parent_username"],
                        "password": account["credentials"]["parent_password"],
                    },
                )
                .raise_for_status()
                .json()
            )
            require(signed["user"]["id"] == account["user"]["id"], "owned_parent_required")
            api.headers["Authorization"] = "Bearer " + signed["token"]
            unit = read(api, "/units/" + state["unit_id"])
            require(
                unit["child_id"] == account["child_id"] and unit["subject"] == "Mathematik", "owned_math_round_required"
            )
            launch()
            if native.matching("Willkommen zurück"):
                login(account["credentials"], "child")
            native.wait("Heute")
            phase = "open_existing_round"
            open_round(unit["topic"])
            if native.matching("Einheit starten"):
                native.press("Einheit starten")
            if native.matching("Lernen fortsetzen"):
                native.press("Lernen fortsetzen")
            if native.matching("Weiter zu den Übungen"):
                native.press("Weiter zu den Übungen")
            checks.append("native_independent_child_login_existing_round_no_generation")
            phase = "saved_answer_and_native_resume"
            ids = []
            for index in range(6):
                unit = read(api, "/units/" + state["unit_id"])
                if unit.get("pending_feedback"):
                    native.press("Ergebnis ansehen" if unit["status"] == "completed" else "Weiter")
                    time.sleep(0.5)
                    unit = read(api, "/units/" + state["unit_id"])
                if unit["status"] == "completed":
                    break
                question = next((q for q in unit["questions"] if not q["attempts"]), None)
                require(question is not None, "bounded_artificial_question_required")
                expected = question["answer"]
                submitted = expected
                if question["type"] in ("short", "gap"):
                    # Different equivalent representation, only if no explicit
                    # reduction/expansion/denominator instruction is present.
                    if re.fullmatch(r"\d+/[1-9]\d*", expected) and not re.search(
                        r"kürz|erweit|nenner\s+\d", question["prompt"], re.I
                    ):
                        a, b = map(int, expected.split("/"))
                        submitted = f"{a * 2}/{b * 2}"
                        report["equivalent_fraction_entered"] = True
                    require(
                        re.fullmatch(r"[A-Za-z0-9_@.+ /;=-]{1,500}", submitted), "supported_native_test_input_required"
                    )
                    fields = [n for n in native.nodes() if n.get("class") == "android.widget.EditText"]
                    require(len(fields) == 1, "one_native_answer_field_required")
                    native.tap_node(fields[0])
                    input_text(submitted)
                    native.adb("shell", "input", "keyevent", "4")
                elif question["type"] == "choice":
                    native.press(expected, scroll=True)
                else:
                    raise RuntimeError("unhandled_native_fixture_type_no_answer_invented")
                native.press("Antwort prüfen")
                wait_fragment("Richtig!")
                after = read(api, "/units/" + state["unit_id"])
                saved = next(q for q in after["questions"] if q["id"] == question["id"])["attempts"]
                require(
                    len(saved) == 1 and saved[0]["outcome"] == "correct" and not saved[0]["assisted"],
                    "native_answer_ledger_inconsistent",
                )
                ids.append(saved[0]["id"])
                native.screenshot("report-review-native-feedback.png")
                if index == 0:
                    native.adb("shell", "am", "force-stop", native.PACKAGE)
                    launch()
                    native.wait("Heute")
                    # Completed rounds live under Erledigt; normal initial
                    # rounds contain at least two questions, so this is active.
                    open_round(unit["topic"])
                    wait_fragment("Deine Antwort")
                    repeated = read(api, "/units/" + state["unit_id"])
                    same = next(q for q in repeated["questions"] if q["id"] == question["id"])["attempts"]
                    require(len(same) == 1 and same[0]["id"] == ids[0], "native_resume_duplicated_answer")
                    checks.append("native_feedback_persists_restart_without_duplicate_answer")
            unit = read(api, "/units/" + state["unit_id"])
            require(unit["status"] == "completed", "bounded_native_round_not_completed")
            if unit.get("pending_feedback"):
                native.press("Ergebnis ansehen")
            checks.append("native_real_round_completed_through_saved_feedback")
            phase = "real_coach_and_minimum"
            end = time.monotonic() + 200
            while time.monotonic() < end:
                unit = read(api, "/units/" + state["unit_id"])
                coach = unit.get("coaching") or {}
                if coach.get("status") == "ready":
                    break
                require(coach.get("status") not in ("failed", "blocked"), "actual_coach_failed_no_retry")
                time.sleep(2)
            require(coach.get("status") == "ready", "actual_coach_wait_expired")
            require(
                all(q["attempts"][-1]["outcome"] == "correct" for q in unit["questions"]),
                "stored_round_verdicts_changed",
            )
            require(
                unit["learning_time"]["daily_active_seconds"] < 1200 and not unit["learning_time"]["daily_goal_met"],
                "fast_round_must_not_fulfil_twenty_minutes",
            )
            require(
                all("mit Hilfe" not in r["feedback"] for r in coach["report"]["question_reviews"]),
                "coach_must_not_invent_assistance",
            )
            native.screenshot("report-review-native-round.png")
            checks.append("actual_reserved_coach_uses_saved_verdicts_and_real_minimum_stays_open")
            phase = "native_new_photos"
            native.press("Lernrunde verlassen")
            native.press("Hefte")
            native.wait("Meine Hefte")
            native.press("Neue Heftfotos")
            native.wait("Fotos auswählen")
            require("Fotos abgeben" not in all_text(), "old_confirmed_pages_must_not_be_resubmitted")
            native.screenshot("report-review-native-new-photos.png")
            checks.append("native_new_photo_entry_excludes_confirmed_pages")
            native.press("Konto")
            native.press("Abmelden", scroll=True)
            native.wait("Willkommen zurück")
            state["phase"] = "native_passed"
            state["native_answer_ids"] = ids
            PRIVATE.write_text(json.dumps(account) + "\n")
            PRIVATE.chmod(0o600)
            report.update(
                success=True,
                real_saved_attempts=len(ids),
                actual_coach_jobs=1,
                daily_active_seconds=unit["learning_time"]["daily_active_seconds"],
            )
    except Exception:
        native.screenshot("report-review-native-failure.png")
        report.update(success=False, failed_phase=phase)
        raise
    finally:
        REPORT.write_text(json.dumps(report) + "\n")
        REPORT.chmod(0o600)
        print(json.dumps(report))


if __name__ == "__main__":
    main()
