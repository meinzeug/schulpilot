"""Native APK26 acceptance; --check is offline, --run requires Root's OTA GO.

Only emulator-5580 / schulpilot-qa-api36, one newly owned fixed Demo and one
synthetic four-component unit. No provider, audio, installer or clock changes.
An interrupted case retains its private journal: use --run --resume, never a
replacement family/job. --run --cleanup-only deletes only this owned fixture.
"""

import argparse
import ast
import json
import os
import re
import time
from pathlib import Path

import android_minimum_time as shared
import android_smoke as native

VERSION = 26
MARKER = "own-android-learning-room-v1"
PRIVATE = native.ARTIFACTS / ".learning-room-android-qa.json"
REPORT = native.ARTIFACTS / "learning-room-native-result.json"
PREFERENCES = {"weekdays": list(range(7)), "daily_minutes": 20, "weekly_minutes": 20,
               "session_minutes": 5, "break_minutes": 5, "timezone": "Europe/Berlin"}
PHASE = "offline_check"


class QaFailure(RuntimeError):
    """Only fixed in-code reason identifiers may enter the public QA report."""


def require(value, reason):
    if not value:
        raise QaFailure(reason)


def step(value):
    global PHASE
    PHASE = value
    print(json.dumps({"phase": value}), flush=True)


def configure():
    # These helpers are imported without side effects. Rebind only this QA
    # process; do not edit or execute the previous minimum-time driver.
    shared.VERSION, shared.MARKER = VERSION, MARKER
    shared.PRIVATE, shared.REPORT = PRIVATE, REPORT
    shared.PREFERENCES = PREFERENCES
    shared.screenshot = shot
    native.adb = shared.bounded_adb


def target():
    require(native.ADB[-2:] == ["-s", "emulator-5580"], "dedicated_serial_required")
    name = native.adb("emu", "avd", "name").decode().splitlines()[0]
    require(name == "schulpilot-qa-api36", "dedicated_avd_required")
    package = native.adb("shell", "dumpsys", "package", native.PACKAGE).decode(errors="replace")
    version = re.search(r"\bversionCode=(\d+)", package)
    require(version and int(version[1]) == VERSION, "root_ota_to_apk26_required")


def shot(label):
    require(re.fullmatch(r"[a-z0-9-]+", label), "fixed_screenshot_name_required")
    native.screenshot("learning-room-native-" + label + ".png")


def text(tree=None):
    return shared.labels(tree)


def visible(fragment):
    return fragment in text()


def wait_fragment(fragment, seconds=30):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if visible(fragment):
            return
        time.sleep(.25)
    raise QaFailure("expected_native_state_not_visible")


def press(label, *, first=False, scroll=True):
    """Match actual labels, with bounded scrolling and no private tree output."""
    for attempt in range(28 if scroll else 1):
        found = native.matching(label)
        if found:
            candidates = [n for n in found if n.get("clickable") == "true"] or found
            native.tap_node(candidates[0 if first else -1])
            return
        if scroll:
            native.adb("shell", "input", "swipe", "900", "1700", "900", "1320", "350")
        if attempt == 0:
            time.sleep(.4)
    raise QaFailure("expected_native_action_not_reachable")


def snapshot(parent, data):
    result = shared.unit_view(parent, data["demo"])
    require(result.get("material_id") == data["demo"]["material_id"]
            and result.get("model") == "fixed-fractions-v1"
            and [q["type"] for q in result["questions"]] == ["choice", "gap", "match", "short"]
            and "pending_feedback" in result, "owned_fixed_guided_unit_required")
    return result


def save_check(data, name, value=True):
    data.setdefault("checks", {})[name] = value
    shared.save(data)


def wait_unit(parent, data, predicate, reason, seconds=25):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        unit = snapshot(parent, data)
        if predicate(unit):
            return unit
        time.sleep(.3)
    raise QaFailure(reason)


def actual(unit):
    measured = unit.get("learning_time", {})
    require(measured.get("daily_goal_minutes") == 20 and measured.get("goal_required") is True,
            "own_twenty_minute_goal_required")
    return measured["daily_active_seconds"]


def keep_minimum_open(unit):
    require(0 <= actual(unit) < 1200 and unit["learning_time"].get("daily_goal_met") is False,
            "minimum_must_still_be_open")


def app_start():
    native.adb("shell", "am", "start", "-n", native.PACKAGE + "/.MainActivity")


def open_owned_unit(parent, data):
    credentials = data["demo"]["credentials"]
    native.adb("shell", "am", "force-stop", native.PACKAGE)
    app_start()
    deadline = time.monotonic() + 40
    while time.monotonic() < deadline:
        current = text()
        if "Willkommen zurück" in current:
            native.login(credentials["child_username"], credentials["child_password"])
            break
        if "Hallo," in current or "Deine Lernrunde" in current or "Dein Lernen" in current:
            break
        time.sleep(.4)
    # A native process restart starts at Home. Use only the collection card for
    # the one existing unit; never the Home action that could create a new job.
    if not visible("Dein Lernen"):
        press("Lernen")
    wait_fragment("Dein Lernen")
    if snapshot(parent, data)["status"] == "completed":
        press("Erledigt")
    for _ in range(24):
        candidates = [n for n in native.nodes()
                      if "Brüche" in text([n]) and n.get("clickable") == "true"]
        if candidates:
            native.tap_node(candidates[-1])
            break
        native.adb("shell", "input", "swipe", "900", "1700", "900", "1320", "350")
    else:
        raise QaFailure("existing_fixed_round_not_reachable")
    wait_fragment("Diese Einheit")
    unit = snapshot(parent, data)
    if visible("Einheit starten"):
        press("Einheit starten", scroll=False)
    # Do not start/resume a paused feedback view just to read its feedback.
    if not unit.get("pending_feedback") and not unit["introduction_seen"]:
        wait_fragment("Weiter zu den Übungen")
        press("Weiter zu den Übungen", scroll=False)
    wait_fragment("Hilfe")
    return snapshot(parent, data)


def enter_answer(question, answer):
    if question["type"] == "choice":
        press(answer)
    elif question["type"] == "match":
        rights = answer.split(";")
        for index, pair in enumerate(question["options"]):
            left, right = pair.split("|", 1)
            require(left and right == rights[index], "fixed_matching_source_required")
            press("Was passt dazu?", first=True)
            wait_fragment("Was passt zu")
            press(right)
    else:
        require(re.fullmatch(r"[A-Za-z0-9/ ]+", answer), "safe_fixed_native_input_required")
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            fields = [n for n in native.nodes() if n.get("class") == "android.widget.EditText"]
            if fields:
                native.tap_node(fields[0])
                break
            native.adb("shell", "input", "swipe", "900", "1700", "900", "1320", "350")
        else:
            raise QaFailure("native_answer_field_not_reachable")
        native.adb("shell", "input", "text", answer.replace(" ", "%s"))
        # Keep the genuine Android keyboard open. The fixed footer must remain
        # tappable; submitting must dismiss it without covering the answer.
        wait_fragment("Antwort prüfen")


def submit(parent, data, question, answer, prior_count):
    before = snapshot(parent, data)
    current = next(q for q in before["questions"] if q["id"] == question["id"])
    attempts = current["attempts"]
    if len(attempts) == prior_count + 1:
        require(attempts[-1]["answer"] == answer, "ambiguous_answer_requires_operator_review")
        return before
    require(len(attempts) == prior_count and before.get("pending_feedback") is None,
            "unexpected_saved_attempts_no_resubmit")
    data["answer_intent"] = {"question_id": question["id"], "prior_count": prior_count, "answer": answer}
    shared.save(data)
    enter_answer(question, answer)
    press("Antwort prüfen", scroll=False)
    updated = wait_unit(parent, data,
                        lambda u: len(next(q for q in u["questions"] if q["id"] == question["id"])["attempts"])
                        == prior_count + 1, "native_answer_not_saved")
    pending = updated.get("pending_feedback")
    require(pending and pending["question_id"] == question["id"] and pending["answer"] == answer,
            "guided_feedback_not_persisted")
    return updated


def acknowledge(parent, data, label):
    before = snapshot(parent, data)
    pending = before.get("pending_feedback")
    if pending is None:
        return before
    counts = [len(q["attempts"]) for q in before["questions"]]
    data["ack_intent"] = pending["attempt_id"]
    shared.save(data)
    press(label, scroll=False)
    updated = wait_unit(parent, data, lambda u: u.get("pending_feedback") is None,
                        "feedback_acknowledgement_not_saved")
    require([len(q["attempts"]) for q in updated["questions"]] == counts,
            "acknowledgement_created_an_extra_attempt")
    return updated


def run_case(parent, data, report):
    shared.verify_own(data["demo"])
    checks = data.setdefault("checks", {})
    if checks.get("round_result"):
        finish_checks(parent, data, report)
        return
    if not checks.get("native_opened"):
        step("independent_native_child_and_quiet_learning_room")
        require(b"Success" in native.adb("shell", "pm", "clear", native.PACKAGE), "own_app_clear_failed")
    open_owned_unit(parent, data)
    if not checks.get("native_opened"):
        current = text()
        require("Konto" not in current and "Verstehen" in current and "Üben" in current
                and "Rückblick" in current and "Aufgabe 1 von 4" in current,
                "focused_round_navigation_not_visible")
        shot("quiet-room")
        save_check(data, "native_opened")
    first = snapshot(parent, data)["questions"][0]
    wrong = next(option for option in first["options"] if option != first["answer"])
    if not checks.get("wrong_answer"):
        step("incorrect_answer_keeps_question_and_own_input")
        unit = submit(parent, data, first, wrong, 0)
        require(unit["pending_feedback"]["outcome"] == "incorrect", "fixed_wrong_answer_not_incorrect")
        wait_fragment("Noch nicht ganz")
        current = text()
        require(first["prompt"] in current and "Deine Antwort" in current and wrong in current,
                "feedback_lost_question_or_own_answer")
        shot("wrong-feedback-context")
        save_check(data, "wrong_answer")
    if not checks.get("restart_restored"):
        step("process_restart_restores_same_pending_feedback")
        before = snapshot(parent, data)["pending_feedback"]["attempt_id"]
        native.adb("shell", "am", "force-stop", native.PACKAGE)
        open_owned_unit(parent, data)
        wait_fragment("Noch nicht ganz")
        restored = snapshot(parent, data)
        require(restored["pending_feedback"]["attempt_id"] == before
                and len(restored["questions"][0]["attempts"]) == 1,
                "process_restart_changed_pending_attempt")
        shot("restored-feedback")
        save_check(data, "restart_restored")
    if not checks.get("retry_acknowledged"):
        step("explicit_retry_acknowledges_without_extra_answer")
        unit = acknowledge(parent, data, "Noch einmal versuchen")
        require(len(unit["questions"][0]["attempts"]) == 1, "retry_added_attempt")
        save_check(data, "retry_acknowledged")
    if not checks.get("direct_hint"):
        step("one_consistent_help_entry_reveals_real_hint")
        if snapshot(parent, data)["questions"][0]["hints_used"] == 0:
            press("Hilfe", scroll=False)
        wait_fragment("Dein Tipp")
        require(snapshot(parent, data)["questions"][0]["hints_used"] == 1, "single_hint_not_recorded")
        shot("inline-hint")
        save_check(data, "direct_hint")
    if not checks.get("first_correct"):
        step("hinted_retry_keeps_explicit_feedback")
        unit = submit(parent, data, first, first["answer"], 1)
        require(unit["pending_feedback"]["outcome"] == "correct"
                and unit["pending_feedback"]["assisted"] is True, "hinted_answer_not_assisted")
        wait_fragment("Richtig!")
        wait_fragment("Weiter")
        shot("correct-assisted-feedback")
        save_check(data, "first_correct")
    if not checks.get("paused_feedback"):
        step("manual_pause_preserves_feedback_without_time_credit")
        if snapshot(parent, data)["status"] == "active":
            press("Pause", scroll=False)
        paused = wait_unit(parent, data, lambda u: u["status"] == "paused", "manual_pause_not_saved")
        require(paused.get("pending_feedback"), "pause_lost_pending_feedback")
        before = actual(paused)
        time.sleep(20)
        require(actual(snapshot(parent, data)) == before, "paused_time_was_credited")
        data["paused_seconds_observed"] = 20
        data["paused_credit_seconds"] = 0
        shot("paused-feedback")
        save_check(data, "paused_feedback")
    if not checks.get("paused_acknowledged"):
        step("paused_feedback_ack_does_not_restart_learning")
        before = actual(snapshot(parent, data))
        unit = acknowledge(parent, data, "Weiter")
        require(unit["status"] == "paused" and actual(unit) == before
                and [len(q["attempts"]) for q in unit["questions"]] == [2, 0, 0, 0],
                "paused_ack_started_time_or_added_answer")
        wait_fragment("Lernen fortsetzen")
        shot("explicit-pause-resume")
        save_check(data, "paused_acknowledged")
    if not checks.get("resumed"):
        step("deliberate_resume_then_complete_three_other_components")
        press("Lernen fortsetzen", scroll=False)
        wait_unit(parent, data, lambda u: u["status"] == "active", "deliberate_resume_not_saved")
        save_check(data, "resumed")
    for index in range(1, 4):
        if checks.get("question_ack_" + str(index)):
            continue
        question = snapshot(parent, data)["questions"][index]
        step("native_component_" + question["type"])
        unit = submit(parent, data, question, question["answer"], 0)
        require(unit["pending_feedback"]["outcome"] == "correct", "fixed_component_not_correct")
        wait_fragment("Richtig!")
        last = index == 3
        wait_fragment("Ergebnis ansehen" if last else "Weiter")
        if last:
            keep_minimum_open(unit)
            shot("last-feedback-before-result")
        acknowledge(parent, data, "Ergebnis ansehen" if last else "Weiter")
        save_check(data, "question_ack_" + str(index))
    step("one_round_result_before_minimum_with_saved_parent_facts")
    completed = wait_unit(parent, data, lambda u: u["status"] == "completed"
                          and (u.get("coaching") or {}).get("status") == "ready",
                          "automatic_synthetic_round_review_not_ready", seconds=60)
    keep_minimum_open(completed)
    coach = completed["coaching"]
    require(coach.get("provider") == "synthetic" and not coach.get("next_unit_id")
            and not coach.get("practice_job_id"), "only_automatic_synthetic_review_allowed")
    require([len(q["attempts"]) for q in completed["questions"]] == [2, 1, 1, 1]
            and all(q["attempts"][-1]["outcome"] == "correct" for q in completed["questions"])
            and [q["attempts"][-1]["assisted"] for q in completed["questions"]] == [True, False, False, False],
            "parent_saved_facts_or_support_classification_disagree")
    wait_fragment("4 von 4 Aufgaben bearbeitet")
    wait_fragment("1 mit Hilfe")
    wait_fragment("3 selbstständig")
    shot("one-honest-round-result")
    save_check(data, "round_result")
    finish_checks(parent, data, report)


def finish_checks(parent, data, report):
    checks = data["checks"]
    family = shared.verify_own(data["demo"])
    completed = snapshot(parent, data)
    require(completed["status"] == "completed" and completed.get("pending_feedback") is None,
            "completed_acknowledged_owned_round_required")
    keep_minimum_open(completed)
    if not checks.get("native_parent_readback"):
        step("native_parent_sees_same_saved_time")
        # A retained case may already be on the parent's Home after a selector
        # failure. Detect that state, instead of switching accounts blindly.
        if not visible("Deine Familie"):
            if visible("Lernrunde verlassen"):
                press("Lernrunde verlassen", scroll=False)
            if not visible("Willkommen zurück"):
                shared.logout()
            c = data["demo"]["credentials"]
            native.login(c["parent_username"], c["parent_password"])
            wait_fragment("Deine Familie")
        shared.reveal("Tagesziel offen")
        seconds = actual(completed)
        wait_fragment(f"{seconds // 60}:{seconds % 60:02d} / 20 Min.")
        shot("parent-saved-time")
        press("Lernüberblick öffnen")
        shared.reveal("Tagesziel offen")
        wait_fragment(f"{seconds // 60}:{seconds % 60:02d} / 20 Min.")
        shot("parent-child-saved-time")
        save_check(data, "native_parent_readback")
    # Observe the child's independent ordinary session and role guard; never
    # answer, start, hint or send a heartbeat through this API session.
    if not data.get("observer_token"):
        with shared.client() as observer:
            c = data["demo"]["credentials"]
            auth = native.check(observer.post("/auth/login", json={
                "username": c["child_username"], "password": c["child_password"],
                "device": "Own learning room QA session observer",
            }))
            require(auth["user"].get("role") == "child"
                    and auth["user"].get("child_id") == data["demo"]["child_id"],
                    "own_independent_child_identity_required")
            data["observer_token"] = auth["token"]
            shared.save(data)
    with shared.client(data["observer_token"]) as observer:
        require(observer.put(f"/children/{data['demo']['child_id']}/preferences",
                             json=PREFERENCES).status_code == 403, "child_changed_parent_goals")
    require(parent.post(f"/units/{data['demo']['unit_id']}/start").status_code == 403,
            "parent_impersonated_child_learning")
    usage = native.check(parent.get(f"/families/{family}/usage"))
    require(usage.get("calls_used") == 0 and usage.get("records") == []
            and usage.get("known_cost_micros_usd") == 0 and usage.get("unknown_cost_calls") == 0
            and usage.get("encumbered_micros_usd") == 0, "zero_provider_usage_and_reservations_required")
    report.update({"qa_completed": True, "checks": checks, "saved_attempt_counts": [2, 1, 1, 1],
                   "correct_independent": 3, "correct_assisted": 1, "unresolved": 0,
                   "saved_active_seconds": actual(completed), "daily_minimum_minutes": 20,
                   "minimum_still_open": True, "paused_seconds_observed": data["paused_seconds_observed"],
                   "paused_credit_seconds": data["paused_credit_seconds"], "synthetic_unit_jobs": 1,
                   "automatic_review_provider": "synthetic", "external_ai_calls": 0,
                   "parent_readback_verified": True, "roles_verified": True,
                   "audio_played_or_recorded": False})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--check", action="store_true")
    modes.add_argument("--run", action="store_true")
    recovery = parser.add_mutually_exclusive_group()
    recovery.add_argument("--resume", action="store_true")
    recovery.add_argument("--cleanup-only", action="store_true")
    args = parser.parse_args()
    if args.check:
        ast.parse(Path(__file__).read_text())
        require(VERSION == 26 and native.ADB[-2:] == ["-s", "emulator-5580"], "offline_target_changed")
        require(PRIVATE.name == ".learning-room-android-qa.json", "private_journal_changed")
        print(json.dumps({"offline_check": True, "network_calls": 0, "adb_calls": 0,
                          "required_apk_code": VERSION, "maximum_own_demos": 1,
                          "maximum_synthetic_unit_jobs": 1, "external_ai_calls": 0}))
        return
    os.umask(0o077)
    configure()
    target()
    if args.resume or args.cleanup_only:
        require(PRIVATE.exists(), "owned_recovery_journal_required")
        data = shared.load()
    else:
        require(not PRIVATE.exists() and not REPORT.exists(), "recover_existing_owned_case_first")
        data = {"marker": MARKER, "creation_attempts": 1, "creation_unresolved": True}
        shared.save(data)
    report = {"passed": False, "installed_code": VERSION, "avd_verified": True,
              "qa_completed": False, "cleanup_succeeded": False, "external_ai_calls": None,
              "mode": "cleanup_only" if args.cleanup_only else "resume" if args.resume else "full_native_qa"}
    try:
        if not args.cleanup_only:
            if not args.resume:
                step("create_exactly_one_new_own_fixed_demo")
                with shared.client() as setup:
                    response = setup.post("/demo")
                    if response.status_code != 201:
                        data["creation_unresolved"] = False
                        shared.save(data)
                    data["demo"] = native.check(response, 201)
                data["creation_unresolved"] = False
                shared.save(data)
            require(data.get("demo") and not data.get("delete_accepted"), "own_live_fixture_required")
            shared.verify_own(data["demo"])
            with shared.client(data["demo"]["token"]) as parent:
                identity = native.check(parent.get("/auth/me"))
                require(identity.get("id") == data["demo"]["user"]["id"], "own_parent_session_required")
                if not data["demo"].get("unit_id"):
                    require(not data.get("unit_request_attempted"), "uncertain_job_no_automatic_retry")
                    step("one_normal_fixed_synthetic_unit_job")
                    shared.prepare(parent, data)
                run_case(parent, data, report)
        step("normal_own_account_deletion_session401_and_native_guest")
        shared.cleanup(data)
        report.update({"passed": True, "cleanup_succeeded": True,
                       "delete_accepted": data.get("delete_accepted") is True,
                       "parent_and_child_sessions_401": bool(data.get("observer_token")),
                       "native_guest_verified": True, "own_app_data_cleared": True,
                       "external_ai_calls": 0 if data.get("provider_usage_verified_zero") else None})
        PRIVATE.unlink(missing_ok=True)
        report["private_journal_removed"] = True
    except Exception as error:
        report["failed_phase"] = PHASE
        report["failure_type"] = type(error).__name__
        report["failure_reason"] = (str(error) if isinstance(error, QaFailure)
                                    and re.fullmatch(r"[a-z0-9_]{1,100}", str(error)) else "safe_operation_failed")
        report["cleanup_pending"] = True
        shared.save(data)
        try:
            shot("failure-retained-own-case")
        except Exception:
            pass
    report["last_phase"] = PHASE
    REPORT.write_text(json.dumps(report, indent=2) + "\n")
    REPORT.chmod(0o600)
    print(json.dumps(report), flush=True)
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
