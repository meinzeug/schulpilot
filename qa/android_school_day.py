"""Installed Flutter APK checks for the browser smoke's own artificial family.

Requires dedicated emulator-5580 and a --keep-for-native test account. Only this
emulator's SCHULPILOT installation is touched. The browser/cleanup script owns
family deletion. No credentials, answers, or report content are printed.

Pass --already-installed after the real updater test: this path never replaces
that update with adb install. All learning navigation below uses the actual UI;
API GETs independently verify persisted sources/reviews and unchanged AI usage.
"""

import argparse
import json
import re
from pathlib import Path

import httpx
from android_smoke import (
    BASE,
    HEADERS,
    PACKAGE,
    adb,
    check,
    login,
    matching,
    nodes,
    press,
    screenshot,
    tap_node,
    wait,
)


def expand_section(prefix, *, optional=False):
    # Android appends expanded/collapsed accessibility state to the label.
    # Each caller opens a fresh route; its disclosure starts collapsed.
    for _ in range(3):
        adb("shell", "input", "swipe", "900", "650", "900", "1950", "250")
    for _ in range(24):
        found = [node for node in nodes() if node.get("content-desc", "").startswith(prefix)]
        if found:
            clickable = [node for node in found if node.get("clickable") == "true"]
            tap_node((clickable or found)[0])
            return True
        adb("shell", "input", "swipe", "900", "1700", "900", "1300", "500")
    if optional:
        return False
    raise RuntimeError("Native disclosure was not visible")


def reveal_text(text):
    for _ in range(3):
        adb("shell", "input", "swipe", "900", "650", "900", "1950", "250")
    for _ in range(28):
        if matching(text):
            return
        adb("shell", "input", "swipe", "900", "1700", "900", "1300", "500")
    raise RuntimeError("Expected stored content was not visible")


def open_day_details():
    # A persistent navigation destination works whichever home action is due.
    press("Heftfotos")
    wait("Nach der Schule")
    expand_section("Was ist im Paket?")
    reveal_text("Heftseite 1")
    reveal_text("Heftseite 2")


def open_saved_review(unit):
    # The package's original unit has the persisted report too. Coach follow-up
    # rounds need not have school_day_id and are not assumed to be in this list.
    press(unit["subject"] + " · " + unit["topic"], scroll=True)
    wait("Runde geschafft!")
    expand_section("Mein Rückblick")
    reveal_text(unit["coaching"]["report"]["summary"])
    reviews = unit["coaching"]["report"].get("question_reviews", [])
    if reviews:
        expand_section("Rückmeldung zu jeder Aufgabe")
        reveal_text(reviews[0]["feedback"])
    screenshot("android-coaching-review.png")
    return bool(reviews)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--already-installed", action="store_true")
    args = parser.parse_args()
    private = Path(__file__).resolve().parents[1] / "artifacts/.school-day-qa-account.json"
    demo = json.loads(private.read_text())
    # This is the already-authorized QA family; never create accounts or AI jobs
    # merely to make an installed-APK check pass.
    if not all(demo.get(field) for field in ("child_id", "school_day_id", "package_unit_id", "credentials")):
        raise RuntimeError("Prepare and retain the dedicated artificial browser test family first")
    if demo.get("normal_account"):
        if not re.search(
            r"\+schulpilot-normal-qa-[a-f0-9]{12}@",
            demo["credentials"]["parent_username"],
        ):
            raise RuntimeError("Only the prepared artificial regular-account family may be tested")
    elif not any(family.get("synthetic") for family in demo.get("user", {}).get("families", [])):
        raise RuntimeError("Only a clearly marked artificial demo family may be tested")
    with httpx.Client(
        base_url=BASE,
        headers=HEADERS,
        timeout=30,
    ) as parent:
        session = check(
            parent.post(
                "/auth/login",
                json={
                    "username": demo["credentials"]["parent_username"],
                    "password": demo["credentials"]["parent_password"],
                    "device": "Dedicated Android QA observer",
                },
            )
        )
        parent.headers["Authorization"] = "Bearer " + session["token"]
        try:
            day = check(parent.get("/school-days/" + demo["school_day_id"]))
            assert day["child_id"] == demo["child_id"]
            assert day["stage"] == "ready" and len(day["pages"]) == 2
            assert {page["page_number"] for page in day["pages"]} == {1, 2}
            assert all(page["confirmed"] for page in day["pages"])
            unit = check(parent.get("/units/" + demo["package_unit_id"]))
            assert unit["id"] in {item["id"] for item in day["units"]}
            assert set(unit["source_material_ids"]) == {page["id"] for page in day["pages"]}
            assert unit["status"] == "completed"
            coach = unit.get("coaching") or {}
            assert coach.get("status") == "ready" and coach.get("report", {}).get("summary")
            if demo.get("normal_account"):
                assert coach.get("provider") == "openrouter" and not unit["synthetic"]
            family_id = demo["user"]["families"][0]["id"]
            before_calls = check(parent.get("/families/" + family_id + "/usage"))["calls_used"]
            if not args.already_installed:
                adb("install", "-r", str(private.parent / "schulpilot-android.apk"))
            adb("shell", "pm", "clear", PACKAGE)
            adb("shell", "am", "start", "-n", PACKAGE + "/.MainActivity")
            login(demo["credentials"]["child_username"], demo["credentials"]["child_password"])
            wait("Heute")  # persistent native navigation; the main CTA can vary.
            screenshot("android-child-home.png")
            open_day_details()
            screenshot("android-school-day-pages.png")
            has_question_feedback = open_saved_review(unit)
            adb("shell", "am", "force-stop", PACKAGE)
            adb("shell", "am", "start", "-n", PACKAGE + "/.MainActivity")
            wait("Heute")
            # Session restoration must go straight to the child home, without a
            # marketing page, re-login, or an obsolete 'Mein Lernraum' button.
            open_day_details()
            screenshot("android-school-day-resumed.png")
            open_saved_review(unit)
            screenshot("android-coaching-resumed.png")
            after_calls = check(parent.get("/families/" + family_id + "/usage"))["calls_used"]
            assert after_calls == before_calls
            checks = [
                "installed_flutter_apk",
                "separate_native_child_login",
                "after_school_entry_from_persistent_navigation",
                "two_persisted_notebook_sources",
                "package_unit_opens_its_saved_ai_review",
                "secure_session_and_day_resume_after_process_restart",
                "secure_session_and_coaching_resume_after_process_restart",
                "reopening_saved_learning_makes_no_ai_calls",
            ]
            if has_question_feedback:
                checks.append("persisted_question_feedback_visible")
            print(
                json.dumps(
                    {
                        "checks": checks,
                        "artificial_test_data_only": True,
                        "adb_install_skipped": args.already_installed,
                        "ai_calls": after_calls - before_calls,
                    }
                )
            )
        finally:
            check(parent.post("/auth/logout"))


if __name__ == "__main__":
    main()
