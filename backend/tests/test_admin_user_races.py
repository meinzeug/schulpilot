"""Controlled account races. Event handshakes, no sleeps or real accounts."""

from concurrent.futures import ThreadPoolExecutor
from threading import Event

import pytest
from conftest import HEADERS
from fastapi.testclient import TestClient
from schulpilot import admin_users, auth, learning
from schulpilot.db import (
    DB,
    Child,
    Family,
    GoogleFlow,
    GoogleIdentity,
    LearningUnit,
    Membership,
    Session,
    Token,
    User,
    engine,
    now,
)
from schulpilot.main import app
from schulpilot.security import digest, password_hash
from sqlalchemy import event, select, text
from sqlalchemy.exc import OperationalError
from test_admin_users import child_user, confirm, get_detail, mutation, preview, private_rows
from test_admin_users import operator as operator_fixture
from test_google_login import begin, callback, result
from test_google_login import google as google_fixture


@pytest.fixture
def operator():
    yield from operator_fixture.__wrapped__()


@pytest.fixture
def google(monkeypatch):
    return google_fixture.__wrapped__(monkeypatch)


def wait(signal):
    assert signal.wait(12), "The controlled concurrent request did not reach its expected boundary."


def test_pg_delete_obeys_real_heartbeat_unit_before_child_lock_order(household, operator, monkeypatch):
    if engine.dialect.name != "postgresql":
        pytest.skip("PostgreSQL row-lock integration case.")
    _, child = household
    identifier = child_user(child)
    _, unit_id = private_rows(child)
    with DB.begin() as db:
        unit = db.get(LearningUnit, unit_id)
        unit.status, unit.synthetic, unit.heartbeat = "active", True, int(now())
        db.add(
            Session(
                user_id=identifier,
                token_hash=digest("heartbeat-race-token"),
                device="Artificial learner",
                expires=int(now()) + 3600,
            )
        )
    value = preview(operator, identifier)
    unit_locked, admin_boundary = Event(), Event()
    original_get, original_target = learning.get_unit, admin_users.lock_target

    def held_unit(db, principal, selected, *args, **kwargs):
        row = original_get(db, principal, selected, *args, **kwargs)
        if selected == unit_id and principal.user.role == "child":
            unit_locked.set()
            wait(admin_boundary)
        return row

    def marked_target(db, *args, **kwargs):
        connection = db.connection()
        connection.info["admin_heartbeat_race"] = True
        try:
            return original_target(db, *args, **kwargs)
        finally:
            connection.info.pop("admin_heartbeat_race", None)

    def before(connection, cursor, statement, parameters, context, many):
        sql = statement.lower()
        if connection.info.get("admin_heartbeat_race") and "learning_units" in sql and "for update" in sql:
            admin_boundary.set()

    def after(connection, cursor, statement, parameters, context, many):
        # The old Child-first implementation would release the learner only
        # once it actually held Child, deterministically exposing its cycle.
        if connection.info.get("admin_heartbeat_race") and statement.lower().startswith("update children"):
            admin_boundary.set()

    monkeypatch.setattr(learning, "get_unit", held_unit)
    monkeypatch.setattr(admin_users, "lock_target", marked_target)
    event.listen(engine, "before_cursor_execute", before)
    event.listen(engine, "after_cursor_execute", after)

    def heartbeat():
        with TestClient(app, headers={**HEADERS, "Authorization": "Bearer heartbeat-race-token"}) as client:
            return client.post(f"/api/units/{unit_id}/heartbeat")

    def delete():
        with TestClient(app, headers=dict(operator.headers)) as client:
            return confirm(client, identifier, value)

    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            learner = pool.submit(heartbeat)
            wait(unit_locked)
            deletion = pool.submit(delete)
            learned, deleted = learner.result(timeout=20), deletion.result(timeout=20)
        assert learned.status_code == 200, learned.text
        assert deleted.status_code == 200, deleted.text
        with DB() as db:
            assert not db.get(User, identifier) and not db.get(LearningUnit, unit_id)
    finally:
        admin_boundary.set()
        event.remove(engine, "before_cursor_execute", before)
        event.remove(engine, "after_cursor_execute", after)


def test_pg_last_preview_check_holds_family_against_new_membership_fk(household, operator, monkeypatch):
    if engine.dialect.name != "postgresql":
        pytest.skip("PostgreSQL FK lock integration case.")
    parent, child = household
    family_id = parent["families"][0]["id"]
    with DB.begin() as db:
        other = User(
            username="late-fk-parent",
            display_name="Synthetic parent",
            role="parent",
            verified=True,
            password_hash="unused",
        )
        db.add(other)
        db.flush()
        other_id = other.id
    value = preview(operator, parent["id"], "account_and_sole_families")
    final_check, fk_finished = Event(), Event()
    original = admin_users.deletion_shape
    rejected = []

    def checked_shape(db, user, scope):
        output = original(db, user, scope)
        final_check.set()
        wait(fk_finished)
        return output

    monkeypatch.setattr(admin_users, "deletion_shape", checked_shape)

    def late_join():
        wait(final_check)
        try:
            with DB.begin() as db:
                # A bounded DB lock timeout proves a real conflicting FK lock;
                # it is not a scheduling delay or an implementation mock.
                db.execute(text("SET LOCAL lock_timeout = '250ms'"))
                db.add(Membership(family_id=family_id, user_id=other_id, permission="manage"))
                db.flush()
        except OperationalError as error:
            rejected.append(getattr(error.orig, "sqlstate", None))
        finally:
            fk_finished.set()

    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            joining = pool.submit(late_join)
            deletion = pool.submit(lambda: confirm(operator, parent["id"], value))
            response = deletion.result(timeout=20)
            joining.result(timeout=20)
        assert rejected == ["55P03"], "A late member must be blocked before the confirmed sole-family deletion."
        assert response.status_code == 200, response.text
        with DB() as db:
            assert not db.get(Family, family_id) and not db.get(Child, child["id"])
            assert db.get(User, other_id) is not None
    finally:
        fk_finished.set()


def test_pg_real_invitation_acceptance_cannot_join_after_final_delete_check(household, operator, monkeypatch):
    if engine.dialect.name != "postgresql":
        pytest.skip("PostgreSQL invitation race integration case.")
    parent, child = household
    family_id = parent["families"][0]["id"]
    with DB.begin() as db:
        other = User(
            username="late-accept@example.invalid",
            email="late-accept@example.invalid",
            display_name="Synthetic invited parent",
            role="parent",
            verified=True,
            password_hash=password_hash("secure-invited-pass-123"),
        )
        db.add(other)
        db.flush()
        other_id = other.id
        raw_token = auth.new_token(db, "invite", family_id=family_id, email=other.email, permission="manage")
    value = preview(operator, parent["id"], "account_and_sole_families")
    final_check, accept_attempt = Event(), Event()
    original = admin_users.deletion_shape

    def checked_shape(db, user, scope):
        output = original(db, user, scope)
        final_check.set()
        wait(accept_attempt)
        return output

    def before(connection, cursor, statement, parameters, context, many):
        if statement.lower().startswith("update tokens"):
            accept_attempt.set()

    monkeypatch.setattr(admin_users, "deletion_shape", checked_shape)
    event.listen(engine, "before_cursor_execute", before)

    def accepting():
        wait(final_check)
        with TestClient(app, headers=HEADERS) as client:
            return client.post(
                "/api/invitations/accept", json={"token": raw_token, "password": "secure-invited-pass-123"}
            )

    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            accepted = pool.submit(accepting)
            deleted = pool.submit(lambda: confirm(operator, parent["id"], value))
            deletion, invitation = deleted.result(timeout=20), accepted.result(timeout=20)
        assert deletion.status_code == 200, deletion.text
        assert invitation.status_code == 400, invitation.text
        with DB() as db:
            assert db.get(User, other_id) is not None
            assert not db.get(Family, family_id) and not db.get(Child, child["id"])
            assert not db.scalar(select(Token.id).where(Token.digest == digest(raw_token)))
    finally:
        accept_attempt.set()
        event.remove(engine, "before_cursor_execute", before)


@pytest.mark.parametrize("login_kind", ["password", "google"])
def test_verified_login_cannot_issue_a_new_session_after_admin_disable(
    household, operator, api, google, monkeypatch, login_kind
):
    parent, _ = household
    parent_id = parent["id"]
    value = get_detail(operator, parent_id)
    read_login, allow_lock = Event(), Event()
    original = auth.lock_session_user
    held = []
    flow = None
    if login_kind == "google":
        google[0]["email"] = parent["email"]
        with DB.begin() as db:
            db.add(GoogleIdentity(subject=google[0]["sub"], user_id=parent_id))
        flow, state = begin(api, google)
        assert callback(api, state).status_code == 303

    def stop_before_lock(db, user):
        if user.id == parent_id and not held:
            held.append(True)
            read_login.set()
            wait(allow_lock)
        return original(db, user)

    monkeypatch.setattr(auth, "lock_session_user", stop_before_lock)

    def logging_in():
        if login_kind == "google":
            return result(api, flow)
        return api.post("/api/auth/login", json={"username": parent["username"], "password": "secure-parent-pass-123"})

    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            login = pool.submit(logging_in)
            wait(read_login)
            response = mutation(operator, parent_id, "status", {"revision": value["revision"], "disabled": True})
            assert response.status_code == 200, response.text
            allow_lock.set()
            logged = login.result(timeout=20)
        assert logged.status_code == 401, logged.text
        enabled = mutation(operator, parent_id, "status", {"revision": response.json()["revision"], "disabled": False})
        assert enabled.status_code == 200
        with DB() as db:
            assert all(row.revoked for row in db.scalars(select(Session).where(Session.user_id == parent_id)))
            assert not db.get(User, parent_id).disabled
            if flow:
                assert db.get(GoogleFlow, flow["flow_id"]).phase == "verified"
        assert api.get("/api/auth/me").status_code == 401
    finally:
        allow_lock.set()


@pytest.mark.parametrize("login_kind", ["password"])
def test_pg_admin_previous_account_switch_conflicts_instead_of_deadlocking(
    household, operator, google, monkeypatch, login_kind
):
    if engine.dialect.name != "postgresql":
        pytest.skip("PostgreSQL cross-account lock-order integration case.")
    parent, _ = household
    identifier = parent["id"]
    value = get_detail(operator, identifier)
    target_locked, admin_at_target = Event(), Event()
    lock_user, lock_target = auth.lock_session_user, admin_users.lock_target
    held = []
    with TestClient(app, headers=dict(operator.headers)) as switcher:
        flow = None
        if login_kind == "google":
            google[0]["email"] = parent["email"]
            with DB.begin() as db:
                db.add(GoogleIdentity(subject=google[0]["sub"], user_id=identifier))
            flow, state = begin(switcher, google)
            assert callback(switcher, state).status_code == 303

        def paused_user(db, user):
            result = lock_user(db, user)
            if user.id == identifier and not held:
                held.append(True)
                target_locked.set()
                wait(admin_at_target)
            return result

        def signalled_target(db, *args, **kwargs):
            admin_at_target.set()  # start() already holds the actor session.
            return lock_target(db, *args, **kwargs)

        monkeypatch.setattr(auth, "lock_session_user", paused_user)
        monkeypatch.setattr(admin_users, "lock_target", signalled_target)

        def logging_in():
            if login_kind == "google":
                return result(switcher, flow)
            return switcher.post(
                "/api/auth/login", json={"username": parent["username"], "password": "secure-parent-pass-123"}
            )

        try:
            with ThreadPoolExecutor(max_workers=2) as pool:
                login = pool.submit(logging_in)
                wait(target_locked)
                disable = pool.submit(
                    lambda: mutation(operator, identifier, "status", {"revision": value["revision"], "disabled": True})
                )
                logged, disabled = login.result(timeout=20), disable.result(timeout=20)
            assert logged.status_code == 409, logged.text
            assert disabled.status_code == 200, disabled.text
            with DB() as db:
                assert db.get(User, identifier).disabled
                assert not db.get(Session, operator.session_id).revoked
                assert all(row.revoked for row in db.scalars(select(Session).where(Session.user_id == identifier)))
                if flow:
                    assert db.get(GoogleFlow, flow["flow_id"]).phase == "verified"
        finally:
            admin_at_target.set()


def test_google_admin_previous_session_is_rejected_before_any_flow_or_session_change(operator, google):
    with DB() as db:
        before = db.scalar(select(Session.id).where(Session.id == operator.session_id))
        assert before is not None
    response = operator.post("/api/auth/google/prepare", json={"intent": "login", "client_challenge": "a" * 43})
    assert response.status_code == 403
    with DB() as db:
        assert not db.get(Session, operator.session_id).revoked
        assert list(db.scalars(select(GoogleFlow.id))) == []
