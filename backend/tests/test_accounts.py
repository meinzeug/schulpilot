from conftest import HEADERS, create_child, register
from fastapi.testclient import TestClient
from schulpilot.db import DB, User
from schulpilot.main import app
from sqlalchemy import select


def test_registration_verification_and_child_login(api, mailbox):
    user = register(api, mailbox, historical_pilot=False)
    child = create_child(api, user)
    with TestClient(app, headers=HEADERS) as own:
        login = own.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"})
        assert login.status_code == 200
        own.headers["Authorization"] = "Bearer " + login.json()["token"]
        assert own.get("/api/child/home").json()["child"]["id"] == child["id"]
        assert own.get(f"/api/families/{user['families'][0]['id']}").status_code == 403
        assert own.put(f"/api/children/{child['id']}/preferences", json={}).status_code == 403
        assert own.get("/api/admin/provider").status_code == 403
        assert own.post("/api/auth/logout").status_code == 200
        assert own.get("/api/auth/me").status_code == 401


def test_cannot_choose_role(api, mailbox):
    response = api.post(
        "/api/auth/register",
        json={
            "email": "admin@example.org",
            "password": "parent-secret-123",
            "display_name": "A",
            "family_name": "A",
            "adult_consent": True,
            "role": "admin",
        },
    )
    assert response.status_code == 422
    with DB() as db:
        assert not db.scalar(select(User))


def test_unverified_parent_cannot_login(api, mailbox):
    api.post(
        "/api/auth/register",
        json={
            "email": "p@example.org",
            "password": "parent-secret-123",
            "display_name": "A",
            "family_name": "A",
            "adult_consent": True,
        },
    )
    assert (
        api.post("/api/auth/login", json={"username": "p@example.org", "password": "parent-secret-123"}).status_code
        == 403
    )
    token = mailbox[-1]["token"]
    assert api.post("/api/auth/verify", json={"token": token}).status_code == 200
    assert api.post("/api/auth/verify", json={"token": token}).status_code == 400


def test_email_not_configured_is_explicit(api):
    assert api.post("/api/auth/recovery", json={"email": "p@example.org"}).status_code == 503
    assert (
        api.post(
            "/api/auth/register",
            json={
                "email": "p@example.org",
                "password": "parent-secret-123",
                "display_name": "A",
                "family_name": "A",
                "adult_consent": True,
            },
        ).status_code
        == 503
    )


def test_siblings_and_other_families_are_private(api, mailbox, household):
    user, child = household
    sibling = create_child(api, user, "test-sibling")
    with TestClient(app, headers=HEADERS) as own:
        token = own.post(
            "/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}
        ).json()["token"]
        own.headers["Authorization"] = "Bearer " + token
        assert own.get(f"/api/children/{sibling['id']}/overview").status_code == 404
        assert (
            own.post(f"/api/children/{sibling['id']}/messages", json={"kind": "help", "body": "Hi"}).status_code == 404
        )
    register(api, mailbox, "other@example.org")
    assert api.get(f"/api/children/{child['id']}/overview").status_code == 404
    assert api.get(f"/api/families/{user['families'][0]['id']}/export").status_code == 404


def test_invite_view_rights_and_revocation(api, mailbox, household):
    user, child = household
    family_id = user["families"][0]["id"]
    response = api.post(
        f"/api/families/{family_id}/invitations", json={"email": "guest@example.org", "permission": "view"}
    )
    assert response.status_code == 201
    token = mailbox[-1]["token"]
    with TestClient(app, headers=HEADERS) as guest:
        response = guest.post(
            "/api/invitations/accept",
            json={"token": token, "display_name": "Gast", "password": "secure-guest-pass-123"},
        )
        assert response.status_code == 200, response.text
        assert (
            guest.post(
                "/api/invitations/accept", json={"token": token, "password": "secure-guest-pass-123"}
            ).status_code
            == 400
        )
        response = guest.post(
            "/api/auth/login", json={"username": "guest@example.org", "password": "secure-guest-pass-123"}
        )
        guest.headers["Authorization"] = "Bearer " + response.json()["token"]
        assert guest.get(f"/api/children/{child['id']}/overview").status_code == 200
        assert guest.put(f"/api/children/{child['id']}/preferences", json={}).status_code == 403
        member = next(m for m in api.get(f"/api/families/{family_id}/members").json() if m["permission"] == "view")
        assert api.delete(f"/api/families/{family_id}/members/{member['id']}").status_code == 200
        assert guest.get(f"/api/children/{child['id']}/overview").status_code == 401


def test_invitation_can_be_cancelled(api, mailbox, household):
    user, _ = household
    fid = user["families"][0]["id"]
    api.post(f"/api/families/{fid}/invitations", json={"email": "g@example.org", "permission": "manage"})
    token = mailbox[-1]["token"]
    invitation = api.get(f"/api/families/{fid}/invitations").json()[0]
    api.delete(f"/api/families/{fid}/invitations/{invitation['id']}")
    assert (
        api.post(
            "/api/invitations/accept", json={"token": token, "display_name": "G", "password": "guest-password-123"}
        ).status_code
        == 400
    )


def test_recovery_revokes_existing_sessions(api, mailbox, household):
    api.post("/api/auth/recovery", json={"email": "parent@example.org"})
    token = mailbox[-1]["token"]
    response = api.post("/api/auth/reset", json={"token": token, "password": "new-parent-password-123"})
    assert response.status_code == 200
    assert api.get("/api/auth/me").status_code == 401
    assert api.post("/api/auth/reset", json={"token": token, "password": "new-parent-password-123"}).status_code == 400


def test_child_reset_revokes_devices(api, household):
    _, child = household
    with TestClient(app, headers=HEADERS) as own:
        login = own.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"})
        own.headers["Authorization"] = "Bearer " + login.json()["token"]
        response = api.put(
            f"/api/children/{child['id']}/password",
            json={"password": "new-child-password-123", "parent_password": "secure-parent-pass-123"},
        )
        assert response.status_code == 200
        assert own.get("/api/auth/me").status_code == 401


def test_csrf_and_secret_validation(api):
    assert api.post("/api/demo", headers={"Origin": "https://attacker.example"}).status_code == 403
    value = "secret-that-must-not-be-echoed"
    result = api.post("/api/auth/login", json={"username": value, "password": "x" * 200})
    assert result.status_code == 422
    assert value not in result.text and "x" * 200 not in result.text


def test_account_deletion_cascades_and_revokes(api, household):
    user, child = household
    assert api.request("DELETE", "/api/account", json={"password": "wrong"}).status_code == 403
    response = api.request("DELETE", "/api/account", json={"password": "secure-parent-pass-123"})
    assert response.status_code == 200
    assert api.get("/api/auth/me").status_code == 401
    with DB() as db:
        assert not db.get(User, user["id"])
        assert not db.scalar(select(User).where(User.username == child["username"]))
