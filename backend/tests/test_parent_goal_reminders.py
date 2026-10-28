"""Real API and worker checks use only saved synthetic learning facts."""

import io
import json
import uuid
import zipfile
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import pytest
from conftest import HEADERS, create_child, register
from fastapi.testclient import TestClient
from schulpilot import notification_inbox as inbox
from schulpilot import notifications as push
from schulpilot import parent_goal_reminders as reminders
from schulpilot import security
from schulpilot.db import (
    DB,
    Activity,
    Child,
    Family,
    Job,
    LearningUnit,
    Membership,
    NotificationRead,
    PushDelivery,
    PushDevice,
    Session,
    Usage,
    User,
)
from schulpilot.exam_models import Exam, ExamRound, ExamSession
from schulpilot.main import app
from schulpilot.parent_reminder_models import ParentGoalReminder, ParentGoalReminderChange, ParentGoalReminderEvent
from sqlalchemy import delete, func, select
from test_notifications import device, enable


@pytest.fixture
def clock(monkeypatch, household):
    stamp = int(datetime(2026, 10, 26, 18, 5, tzinfo=ZoneInfo("Europe/Berlin")).timestamp())
    for module in (reminders, push, inbox, security):
        monkeypatch.setattr(module, "now", lambda: stamp)
    with DB.begin() as db:
        for login in db.scalars(select(Session)):
            login.seen, login.expires = stamp, stamp + 7 * 86400
        child = db.get(Child, household[1]["id"])
        child.preferences = {"weekdays": list(range(7)), "daily_minutes": 20,
            "quiet_start": 0, "quiet_end": 0, "push_consent": False, "reminders": False}
    return stamp


def route(child):
    return f"/api/children/{child['id']}/parent-goal-reminders"


def headers(owner, key=None):
    return {"X-Schulpilot-Account": owner["id"], **({"Idempotency-Key": key or uuid.uuid4().hex} if key is not False else {})}


def body(**values):
    return {"revision": 0, "enabled": True, "weekdays": list(range(7)), "time": "18:00",
        "timezone": "Europe/Berlin", "daily_minimum": True, "exam_sessions": True, **values}


def save(api, household, **values):
    owner, child = household
    response = api.put(route(child), headers=headers(owner), json=body(**values))
    assert response.status_code == 200, response.text
    return response.json()


def sweep(clock):
    with DB.begin() as db:
        push.prepare(db, clock)


def event_count():
    with DB() as db:
        return db.scalar(select(func.count()).select_from(ParentGoalReminderEvent))


def activity(child, clock, seconds):
    with DB.begin() as db:
        db.add(Activity(child_id=child["id"], kind="active_time", detail={"seconds": seconds}, created=clock - 60))


def exam(child, clock, *, completed=0, rounds=2, offset=0, archived=False):
    with DB.begin() as db:
        value = Exam(child_id=child["id"], title="PRIVATE TITLE", purpose="preparation", kind="test",
            subject="Mathematik", timezone="Europe/Berlin", revision=4, plan_revision=2, minutes=15,
            topics=[], schedule={}, reminders=False, archived=archived, create_key=uuid.uuid4().hex,
            request_digest="synthetic")
        db.add(value)
        db.flush()
        day = datetime.fromtimestamp(clock, ZoneInfo(value.timezone)).date() + timedelta(days=offset)
        slot = ExamSession(exam_id=value.id, exam_revision=2, date=day.isoformat(), minutes=15, topics=[])
        db.add(slot)
        db.flush()
        for index in range(rounds):
            unit = None
            if index < completed:
                unit = LearningUnit(child_id=child["id"], subject="Mathematik", topic="PRIVATE TOPIC",
                    explanation="PRIVATE EXPLANATION", questions=[], status="completed", provider="synthetic")
                db.add(unit)
                db.flush()
            db.add(ExamRound(session_id=slot.id, ordinal=index, topic_id="t1", topic_label="PRIVATE TOPIC",
                question_count=3, source_revisions=[], unit_id=unit.id if unit else None))
        return value.id, slot.id


def test_default_get_is_personal_disabled_and_read_only(api, household, clock):
    owner, child = household
    for _ in range(2):
        response = api.get(route(child), headers=headers(owner, False))
        assert response.status_code == 200
        assert response.json() == {"child_id": child["id"], "revision": 0, "enabled": False,
            "weekdays": [0, 1, 2, 3, 4], "time": "18:00", "timezone": "Europe/Berlin",
            "daily_minimum": True, "exam_sessions": True, "updated": None, "can_configure": True}
    sweep(clock)
    with DB() as db:
        for model in (ParentGoalReminder, ParentGoalReminderEvent, ParentGoalReminderChange, Usage, Job, Activity):
            assert db.scalar(select(func.count()).select_from(model)) == 0


def test_save_cas_replay_and_current_truth(api, household, clock):
    owner, child = household
    key = "synthetic-parent-rule-key"
    result = api.put(route(child), headers=headers(owner, key), json=body())
    assert result.status_code == 200 and result.json()["revision"] == 1
    assert api.put(route(child), headers=headers(owner, key), json=body()).json() == result.json()
    assert api.put(route(child), headers=headers(owner, key), json=body(time="19:00")).status_code == 409
    assert api.put(route(child), headers=headers(owner), json=body()).status_code == 409
    latest = save(api, household, revision=1, time="19:00")
    assert api.put(route(child), headers=headers(owner, key), json=body()).json() == latest
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(ParentGoalReminderChange)) == 2
        assert db.get(Child, child["id"]).preferences["daily_minutes"] == 20
        assert db.scalar(select(func.count()).select_from(Activity)) == 0


@pytest.mark.parametrize("override", [
    {"weekdays": [1, 1]}, {"weekdays": [7]}, {"weekdays": [True]}, {"weekdays": []},
    {"time": "24:00"}, {"time": "8:00"}, {"timezone": "unknown/zone"},
    {"daily_minimum": False, "exam_sessions": False}, {"revision": -1}, {"user_id": "forged"},
])
def test_invalid_configuration_is_rejected_without_changes(api, household, clock, override):
    owner, child = household
    response = api.put(route(child), headers=headers(owner), json=body(**override))
    assert response.status_code == 422, response.text
    assert event_count() == 0
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(ParentGoalReminder)) == 0


@pytest.mark.parametrize("method", ["get", "put"])
def test_actor_cookie_binding_is_mandatory_before_personal_read_or_write(api, household, clock, method):
    owner, child = household
    kwargs = {"json": body(), "headers": {"Idempotency-Key": uuid.uuid4().hex}} if method == "put" else {}
    assert getattr(api, method)(route(child), **kwargs).status_code == 422
    kwargs["headers"] = {**kwargs.get("headers", {}), "X-Schulpilot-Account": "f" * 32}
    assert getattr(api, method)(route(child), **kwargs).status_code == 409
    assert api.get(route(child), headers=headers(owner, False)).json()["revision"] == 0


@pytest.mark.parametrize("role", ["child", "admin", "stranger"])
def test_only_own_parent_membership_can_read_or_write(api, household, clock, mailbox, role):
    owner, child = household
    if role == "stranger":
        actor = register(api, mailbox, "stranger@example.org")
    else:
        with DB.begin() as db:
            db.get(User, owner["id"]).role = role
        actor = owner
    assert api.get(route(child), headers=headers(actor, False)).status_code in (403, 404)
    assert api.put(route(child), headers=headers(actor), json=body()).status_code in (403, 404)
    assert event_count() == 0


def test_read_only_parent_has_separate_personal_setting_and_private_export(api, household, clock, mailbox):
    owner, child = household
    save(api, household)
    fid = owner["families"][0]["id"]
    assert api.post(f"/api/families/{fid}/invitations", json={"email": "reader@example.org", "permission": "view"}).status_code == 201
    token = mailbox[-1]["token"]
    assert api.post("/api/invitations/accept", json={"token": token, "password": "synthetic-reader-password", "display_name": "Reader"}).status_code == 200
    with TestClient(app, headers=HEADERS) as reader:
        login = reader.post("/api/auth/login", json={"username": "reader@example.org", "password": "synthetic-reader-password"}).json()
        reader.headers["Authorization"] = "Bearer " + login["token"]
        other = login["user"]
        assert reader.get(route(child), headers=headers(other, False)).json()["revision"] == 0
        assert reader.put(route(child), headers=headers(other), json=body(time="19:00")).status_code == 200
        response = reader.get(f"/api/children/{child['id']}/export?include_photos=false")
        assert response.status_code == 200
        with zipfile.ZipFile(io.BytesIO(response.content)) as archive:
            exported = json.loads(archive.read("child.json"))["parent_goal_reminders"]
        assert [row["time"] for row in exported["settings"]] == ["19:00"]
    assert api.get(route(child), headers=headers(owner, False)).json()["time"] == "18:00"


@pytest.mark.parametrize("seconds,finished,expected", [(0, False, 1200), (300, False, 900), (0, True, 1200), (1200, False, 0), (1800, False, 0)])
def test_minimum_is_exact_saved_seconds_not_a_finished_round(api, household, clock, seconds, finished, expected):
    _, child = household
    save(api, household)
    if seconds:
        activity(child, clock, seconds)
    if finished:
        with DB.begin() as db:
            db.add(Activity(child_id=child["id"], kind="unit_completed", detail={"estimated_minutes": 20}, created=clock - 1))
    sweep(clock)
    with DB() as db:
        rows = list(db.scalars(select(ParentGoalReminderEvent)))
        assert len(rows) == bool(expected)
        if expected:
            assert rows[0].daily_remaining_seconds == expected
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
        assert db.scalar(select(func.count()).select_from(Job)) == 0


@pytest.mark.parametrize("change", [{"weekdays": []}, {"pause_until": "2026-10-26"}])
def test_free_or_paused_child_day_has_no_minimum_warning(api, household, clock, change):
    save(api, household)
    with DB.begin() as db:
        child = db.get(Child, household[1]["id"])
        child.preferences = {**child.preferences, **change}
    sweep(clock)
    assert event_count() == 0


def test_previous_and_future_seconds_do_not_satisfy_todays_minimum(api, household, clock):
    save(api, household)
    with DB.begin() as db:
        for stamp in (clock - 86400, clock + 60):
            db.add(Activity(child_id=household[1]["id"], kind="active_time", detail={"seconds": 1200}, created=stamp))
    sweep(clock)
    with DB() as db:
        assert db.scalar(select(ParentGoalReminderEvent)).daily_remaining_seconds == 1200


@pytest.mark.parametrize("completed,offset,archived,expected", [(0, 0, False, 1), (1, 0, False, 1), (2, 0, False, 0), (0, -1, False, 0), (0, 1, False, 0), (0, 0, True, 0)])
def test_exam_checks_only_current_today_plan_and_all_rounds(api, household, clock, completed, offset, archived, expected):
    save(api, household, daily_minimum=False)
    exam(household[1], clock, completed=completed, offset=offset, archived=archived)
    sweep(clock)
    assert event_count() == expected
    with DB() as db:
        if expected:
            row = db.scalar(select(ParentGoalReminderEvent))
            assert row.daily_remaining_seconds == 0 and len(row.exam_sessions) == 1


def test_plan_revision_replacement_excludes_old_session(api, household, clock):
    save(api, household, daily_minimum=False)
    exam_id, _ = exam(household[1], clock)
    with DB.begin() as db:
        db.get(Exam, exam_id).plan_revision += 1
    sweep(clock)
    assert event_count() == 0


def test_schedule_day_time_dedupe_and_no_catchup(api, household, clock):
    owner, child = household
    save(api, household, time="18:10")
    sweep(clock)
    assert event_count() == 0
    sweep(clock + 5 * 60)
    sweep(clock + 6 * 60)
    assert event_count() == 1
    save(api, household, revision=1, time="18:00")
    sweep(clock + 7 * 60)
    assert event_count() == 1  # Time edit is not a second daily alert.
    sweep(clock + 3 * 86400)
    assert event_count() == 2  # One current check, no skipped-day backlog.
    with DB() as db:
        assert {row.date for row in db.scalars(select(ParentGoalReminderEvent))} == {"2026-10-26", "2026-10-29"}
        assert db.get(ParentGoalReminder, (owner["id"], child["id"])).next_check > clock + 3 * 86400


def test_unselected_weekday_does_not_emit(api, household, clock):
    save(api, household, weekdays=[1])  # Monday check skipped, Tuesday scheduled.
    sweep(clock)
    assert event_count() == 0
    sweep(clock + 86400)
    assert event_count() == 1


def test_dst_gap_and_repeated_hour_have_one_daily_event(api, household, clock):
    save(api, household, time="02:30", weekdays=list(range(7)))
    spring = int(datetime(2027, 3, 28, 3, 0, tzinfo=ZoneInfo("Europe/Berlin")).timestamp())
    fall = int(datetime(2027, 10, 31, 2, 35, tzinfo=ZoneInfo("Europe/Berlin"), fold=0).timestamp())
    for stamp in (spring - 60, spring, spring + 60):
        sweep(stamp)
    with DB() as db:
        rows = list(db.scalars(select(ParentGoalReminderEvent)))
        assert len(rows) == 1 and rows[0].scheduled == spring
    for stamp in (fall, fall + 3600):
        sweep(stamp)
    with DB() as db:
        rows = list(db.scalars(select(ParentGoalReminderEvent)))
        # The spring snapshot correctly expired after 30 days.
        assert len(rows) == 1 and rows[0].date == "2027-10-31"


def test_inbox_persists_worker_snapshot_without_fcm_or_get_writes(api, household, clock):
    owner, child = household
    save(api, household)
    sweep(clock)
    assert api.get("/api/notifications/config").json()["available"] is False
    for _ in range(2):
        data = api.get("/api/notifications/inbox").json()
        assert len(data["items"]) == 1
        item = data["items"][0]
        assert item["kind"] == "parent_goal" and item["route"] == f"/child/{child['id']}"
        assert "waren noch offen" in item["title"]
    activity(child, clock, 1200)
    # The dated check remains honest history, not a new current-failure claim.
    assert api.post("/api/notifications/inbox/read", json={"ids": [item["id"]]}).status_code == 200
    assert api.get("/api/notifications/inbox").json()["unread"] == 0
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(NotificationRead)) == 1
        assert db.scalar(select(func.count()).select_from(Activity)) == 1
        assert db.scalar(select(func.count()).select_from(Job)) == 0
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
        assert db.get(ParentGoalReminder, (owner["id"], child["id"])).revision == 1


def queued(api, household, clock, tmp_path):
    enable(tmp_path)
    save(api, household)
    result = device(api)
    sweep(clock)
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(PushDelivery)) == 1
    return result


def test_one_neutral_delivery_per_device_child_day_and_hour_ttl(api, household, clock, tmp_path, monkeypatch):
    queued(api, household, clock, tmp_path)
    sweep(clock)
    sent = []
    monkeypatch.setattr(push, "send_fcm", lambda *args, **kwargs: sent.append((args, kwargs)))
    assert push.deliver_one(DB)
    assert not push.deliver_one(DB)
    assert len(sent) == 1 and sent[0][0][1:] == ("parent_goal", 3600)
    assert sent[0][1] == {}  # No child identifier, name or private payload.
    with DB() as db:
        assert db.scalar(select(PushDelivery)).status == "accepted"


@pytest.mark.parametrize("change", ["minimum_met", "disable_rule", "remove_membership", "expire_family", "revoke_session", "disabled_parent", "role_changed", "device_optout"])
def test_queued_delivery_revalidates_live_goal_rule_role_membership_session_and_optin(api, household, clock, tmp_path, monkeypatch, change):
    registration = queued(api, household, clock, tmp_path)
    owner, child = household
    with DB.begin() as db:
        if change == "minimum_met":
            db.add(Activity(child_id=child["id"], kind="active_time", detail={"seconds": 1200}, created=clock))
        elif change == "disable_rule":
            db.get(ParentGoalReminder, (owner["id"], child["id"])).enabled = False
        elif change == "remove_membership":
            db.execute(delete(Membership).where(Membership.user_id == owner["id"]))
        elif change == "expire_family":
            db.get(Family, owner["families"][0]["id"]).expires = clock - 1
        elif change == "revoke_session":
            db.get(Session, db.get(PushDevice, registration["id"]).session_id).revoked = True
        elif change == "disabled_parent":
            db.get(User, owner["id"]).disabled = True
        elif change == "role_changed":
            db.get(User, owner["id"]).role = "child"
        elif change == "device_optout":
            db.get(PushDevice, registration["id"]).reminders = False
    sent = []
    monkeypatch.setattr(push, "send_fcm", lambda *a, **kw: sent.append(a))
    assert push.deliver_one(DB)
    assert sent == []
    with DB() as db:
        assert db.scalar(select(PushDelivery)).status == "suppressed"


@pytest.mark.parametrize("which", ["device", "child"])
def test_both_quiet_windows_cap_ttl_and_block_send(api, household, clock, tmp_path, monkeypatch, which):
    registration = queued(api, household, clock, tmp_path)
    # 18:05 -> next quiet hour19:00: 55 minutes, under the separate one-hour cap.
    with DB.begin() as db:
        if which == "device":
            value = db.get(PushDevice, registration["id"])
            value.quiet_start, value.quiet_end = 19, 8
        else:
            value = db.get(Child, household[1]["id"])
            value.preferences = {**value.preferences, "quiet_start": 19, "quiet_end": 8}
    sent = []
    monkeypatch.setattr(push, "send_fcm", lambda *a, **kw: sent.append(a))
    assert push.deliver_one(DB)
    assert sent[0][2] == 55 * 60


def test_exam_finished_or_plan_replaced_before_send_suppresses_warning(api, household, clock, tmp_path, monkeypatch):
    enable(tmp_path)
    save(api, household, daily_minimum=False)
    exam_id, slot_id = exam(household[1], clock)
    device(api)
    sweep(clock)
    with DB.begin() as db:
        db.get(Exam, exam_id).plan_revision += 1
    sent = []
    monkeypatch.setattr(push, "send_fcm", lambda *a, **kw: sent.append(a))
    assert push.deliver_one(DB) and not sent
    with DB() as db:
        assert db.scalar(select(PushDelivery)).status == "suppressed"
        assert db.get(ExamSession, slot_id).exam_revision == 2


def test_multiple_children_are_deduped_and_unrelated_child_quiet_is_not_target_ttl(api, household, clock, tmp_path, monkeypatch):
    owner, child = household
    other = create_child(api, owner, username="second-child")
    with DB.begin() as db:
        db.get(Child, other["id"]).preferences = {"quiet_start": 0, "quiet_end": 23}
    queued(api, household, clock, tmp_path)
    sent = []
    monkeypatch.setattr(push, "send_fcm", lambda *a, **kw: sent.append(a))
    assert push.deliver_one(DB)
    assert sent[0][2] == 3600
    assert event_count() == 1
    with DB() as db:
        assert db.scalar(select(ParentGoalReminderEvent)).child_id == child["id"]


def test_concurrent_scheduler_ticks_do_not_duplicate_checks(api, household, clock):
    save(api, household)
    with ThreadPoolExecutor(max_workers=2) as workers:
        list(workers.map(sweep, [clock, clock]))
    assert event_count() == 1


def test_account_and_child_cascades_remove_own_rules_changes_events(api, household, clock):
    owner, child = household
    save(api, household)
    sweep(clock)
    with DB.begin() as db:
        db.execute(delete(Child).where(Child.id == child["id"]))
    with DB() as db:
        for model in (ParentGoalReminder, ParentGoalReminderChange, ParentGoalReminderEvent):
            assert db.scalar(select(func.count()).select_from(model)) == 0
        assert db.get(User, owner["id"]) is not None


def test_two_concurrent_saves_claim_exactly_one_revision(api, household, clock):
    owner, child = household
    auth = api.headers["Authorization"]
    def request(index):
        with TestClient(app, headers={**HEADERS, "Authorization": auth}) as client:
            return client.put(route(child), headers=headers(owner), json=body(time=f"18:0{index}"))
    with ThreadPoolExecutor(max_workers=2) as workers:
        responses = list(workers.map(request, [0, 1]))
    assert sorted(row.status_code for row in responses) == [200, 409]
    with DB() as db:
        assert db.get(ParentGoalReminder, (owner["id"], child["id"])).revision == 1
        assert db.scalar(select(func.count()).select_from(ParentGoalReminderChange)) == 1


def test_role_changed_while_waiting_for_child_lock_is_denied(api, household, clock, monkeypatch):
    from sqlalchemy.orm import Session as OrmSession

    owner, child = household
    execute, changed = OrmSession.execute, []
    def interpose(self, statement, *args, **kwargs):
        if getattr(statement, "is_update", False) and getattr(statement.table, "name", "") == "children" and not changed:
            changed.append(True)
            with DB.begin() as other:
                other.get(User, owner["id"]).role = "child"
        return execute(self, statement, *args, **kwargs)
    monkeypatch.setattr(OrmSession, "execute", interpose)
    result = api.put(route(child), headers=headers(owner), json=body())
    assert result.status_code == 401 and changed
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(ParentGoalReminder)) == 0
        assert db.scalar(select(func.count()).select_from(ParentGoalReminderChange)) == 0


def test_lost_membership_purges_personal_optin_but_not_child_learning(api, household, clock):
    owner, child = household
    save(api, household)
    activity(child, clock, 300)
    sweep(clock)
    with DB.begin() as db:
        db.execute(delete(Membership).where(Membership.user_id == owner["id"]))
    sweep(clock + 1)
    with DB() as db:
        for model in (ParentGoalReminder, ParentGoalReminderChange, ParentGoalReminderEvent):
            assert db.scalar(select(func.count()).select_from(model)) == 0
        assert db.scalar(select(func.count()).select_from(Activity)) == 1


@pytest.mark.parametrize("permission", ["view", "manage"])
def test_revoke_then_reinvite_without_sweep_never_restores_personal_optin(api, household, clock, mailbox, permission):
    owner, child = household
    family_id = owner["families"][0]["id"]
    sibling = create_child(api, owner, username="reminder-sibling")
    save(api, household)
    activity(child, clock, 300)
    with TestClient(app, headers=HEADERS) as reader:
        other = register(reader, mailbox, "returning-reader@example.org")
        unrelated = create_child(reader, other, username="unrelated-reminder-child")
        assert reader.put(route(unrelated), headers=headers(other), json=body()).status_code == 200

        def invite_and_accept():
            response = api.post(f"/api/families/{family_id}/invitations", json={
                "email": "returning-reader@example.org", "permission": permission})
            assert response.status_code == 201, response.text
            response = reader.post("/api/invitations/accept", json={
                "token": mailbox[-1]["token"], "password": "secure-parent-pass-123"})
            assert response.status_code == 200, response.text

        invite_and_accept()
        replay_key = uuid.uuid4().hex
        assert reader.put(route(child), headers=headers(other, replay_key), json=body()).status_code == 200
        assert reader.put(route(sibling), headers=headers(other), json=body()).status_code == 200
        sweep(clock)
        with DB() as db:
            membership_id = db.scalar(select(Membership.id).where(
                Membership.user_id == other["id"], Membership.family_id == family_id))
            event_ids = set(db.scalars(select(ParentGoalReminderEvent.id)))
            changes = db.scalar(select(func.count()).select_from(ParentGoalReminderChange))
            assert event_ids
        response = api.delete(f"/api/families/{family_id}/members/{membership_id}")
        assert response.status_code == 200, response.text
        # No scheduler tick between revoke and re-invitation: revocation itself
        # must invalidate the old opt-in and stale configuration revisions.
        with DB() as db:
            for selected in (child, sibling):
                rule = db.get(ParentGoalReminder, (other["id"], selected["id"]))
                assert not rule.enabled and rule.revision == 2
            assert db.get(ParentGoalReminder, (owner["id"], child["id"])).enabled
            assert db.get(ParentGoalReminder, (other["id"], unrelated["id"])).enabled
            assert set(db.scalars(select(ParentGoalReminderEvent.id))) == event_ids
            assert db.scalar(select(func.count()).select_from(ParentGoalReminderChange)) == changes
            assert db.scalar(select(func.count()).select_from(Activity)) == 1
            assert db.scalar(select(func.count()).select_from(Job)) == 0
            assert db.scalar(select(func.count()).select_from(Usage)) == 0
        invite_and_accept()
        login = reader.post("/api/auth/login", json={
            "username": "returning-reader@example.org", "password": "secure-parent-pass-123"})
        assert login.status_code == 200, login.text
        reader.headers["Authorization"] = "Bearer " + login.json()["token"]
        current = reader.get(route(child), headers=headers(other, False)).json()
        assert current["enabled"] is False and current["revision"] == 2
        replay = reader.put(route(child), headers=headers(other, replay_key), json=body())
        assert replay.status_code == 200 and replay.json()["enabled"] is False
        assert reader.put(route(child), headers=headers(other), json=body(revision=1)).status_code == 409
        with DB() as db:
            assert all(event.child_id not in (child["id"], sibling["id"])
                for event, _, _ in reminders.due_events(db, other["id"], clock))
            assert set(db.scalars(select(ParentGoalReminderEvent.id))) == event_ids
        # Only a new conscious save against the current revision re-enables it.
        response = reader.put(route(child), headers=headers(other), json=body(revision=2))
        assert response.status_code == 200 and response.json()["enabled"] is True
        assert response.json()["revision"] == 3


def test_quiet_period_keeps_inapp_but_does_not_queue_until_outside(api, household, clock, tmp_path):
    enable(tmp_path)
    save(api, household)
    registered = device(api)
    with DB.begin() as db:
        value = db.get(PushDevice, registered["id"])
        value.quiet_start, value.quiet_end = 18, 19
    sweep(clock)
    assert event_count() == 1
    assert api.get("/api/notifications/inbox").json()["unread"] == 1
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(PushDelivery)) == 0
    sweep(clock + 3600)
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(PushDelivery)) == 1


def test_exam_completed_after_queue_does_not_send(api, household, clock, tmp_path, monkeypatch):
    enable(tmp_path)
    save(api, household, daily_minimum=False)
    _, slot_id = exam(household[1], clock)
    device(api)
    sweep(clock)
    with DB.begin() as db:
        for row in db.scalars(select(ExamRound).where(ExamRound.session_id == slot_id)):
            unit = LearningUnit(child_id=household[1]["id"], subject="Mathematik", topic="synthetic",
                explanation="synthetic", questions=[], status="completed", provider="synthetic")
            db.add(unit)
            db.flush()
            row.unit_id = unit.id
    sent = []
    monkeypatch.setattr(push, "send_fcm", lambda *a, **kw: sent.append(a))
    assert push.deliver_one(DB) and not sent
    with DB() as db:
        assert db.scalar(select(PushDelivery)).status == "suppressed"


def test_parent_kind_uses_neutral_http_payload_and_bounded_transport_ttl(api, tmp_path, monkeypatch):
    import httpx
    from google.oauth2 import service_account
    from schulpilot.config import settings

    enable(tmp_path)
    # Entirely synthetic IN-MEMORY configuration: never write a configured
    # credential path. Both Google credential creation and HTTP are mocked.
    object.__setattr__(settings, "fcm_service_account_json", json.dumps({"type": "service_account",
        "project_id": "synthetic-project", "token_uri": "https://oauth2.googleapis.com/token"}))
    class Credential:
        token = "SYNTHETIC-OAUTH-TOKEN"
        def refresh(self, request):
            pass
    monkeypatch.setattr(service_account.Credentials, "from_service_account_info", lambda *a, **kw: Credential())
    sent = []
    def send(request):
        assert str(request.url) == "https://fcm.googleapis.com/v1/projects/synthetic-project/messages:send"
        sent.append(json.loads(request.content))
        return httpx.Response(200, json={"name": "synthetic/receipt"})
    real_client = httpx.Client
    monkeypatch.setattr(httpx, "Client", lambda **kwargs: real_client(
        **kwargs, transport=httpx.MockTransport(send)))
    push.send_fcm("SYNTHETIC_TOKEN", "parent_goal", 3600)
    message = sent[0]["message"]
    assert message["data"] == {"route": "/app"}
    assert message["notification"] == {"title": "SchuleSchlau", "body": "Ein geplanter Tagescheck ist da. Öffne SchuleSchlau."}
    assert message["android"]["ttl"] == "3600s"
    assert message["webpush"]["headers"]["TTL"] == "3600"
    assert message["webpush"]["fcm_options"]["link"] == "http://testserver/app"



@pytest.mark.parametrize("timezone,time", [("Pacific/Honolulu", "12:55"), ("America/New_York", "18:55")])
def test_parent_day_check_never_becomes_the_next_child_days_minimum(api, household, clock, timezone, time):
    save(api, household, timezone=timezone, time=time, exam_sessions=False)
    before_midnight = int(datetime(2026, 10, 26, 23, 55, tzinfo=ZoneInfo("Europe/Berlin")).timestamp())
    sweep(before_midnight)
    with DB() as db:
        assert len(reminders.due_events(db, household[0]["id"], before_midnight)) == 1
        assert reminders.due_events(db, household[0]["id"], before_midnight + 10 * 60) == []
        assert db.scalar(select(func.count()).select_from(ParentGoalReminderEvent)) == 1
        assert db.scalar(select(func.count()).select_from(Activity)) == 0


@pytest.mark.parametrize("timezone,time", [("Pacific/Honolulu", "12:55"), ("America/New_York", "18:55")])
def test_parent_push_ttl_expires_before_its_target_child_day_ends(api, household, clock, tmp_path, monkeypatch, timezone, time):
    enable(tmp_path)
    save(api, household, timezone=timezone, time=time, exam_sessions=False)
    registration = device(api)
    with DB.begin() as db:
        target = db.get(PushDevice, registration["id"])
        target.quiet_start = target.quiet_end = 0
    before_midnight = int(datetime(2026, 10, 26, 23, 55, tzinfo=ZoneInfo("Europe/Berlin")).timestamp())
    sweep(before_midnight)
    sent = []
    monkeypatch.setattr(push, "now", lambda: before_midnight)
    monkeypatch.setattr(push, "send_fcm", lambda *args, **kwargs: sent.append((args, kwargs)))
    assert push.deliver_one(DB)
    assert len(sent) == 1 and sent[0][0][1:] == ("parent_goal", 5 * 60)
    assert sent[0][1] == {}


def test_still_current_exam_session_survives_child_midnight_without_reusing_daily_goal(api, household, clock):
    save(api, household, timezone="Pacific/Honolulu", time="12:55", daily_minimum=False)
    exam_id, _ = exam(household[1], clock)
    with DB.begin() as db:
        db.get(Exam, exam_id).timezone = "Pacific/Honolulu"
    before_midnight = int(datetime(2026, 10, 26, 23, 55, tzinfo=ZoneInfo("Europe/Berlin")).timestamp())
    sweep(before_midnight)
    with DB() as db:
        event = db.scalar(select(ParentGoalReminderEvent))
        assert event.daily_remaining_seconds == 0
        assert len(reminders.due_events(db, household[0]["id"], before_midnight + 10 * 60)) == 1
        assert db.scalar(select(func.count()).select_from(Activity)) == 0
