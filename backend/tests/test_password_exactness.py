"""Credential characters are exact across synthetic account and confirmation paths."""

import pytest
from conftest import HEADERS
from fastapi import HTTPException
from fastapi.testclient import TestClient
from schulpilot import schemas as s
from schulpilot.db import DB, User
from schulpilot.families import ChildPassword
from schulpilot.main import app
from schulpilot.security import password_hash, verify_password

RAW = "  synthetic exact password 123  "


@pytest.mark.parametrize(
    "make",
    [
        lambda: s.Register(
            email="synthetic@example.org",
            password=RAW,
            display_name="Synthetic",
            family_name="Synthetic",
            adult_consent=True,
        ),
        lambda: s.ResetRequest(token="synthetic_token_1234567890123456789012345", password=RAW),
        lambda: s.ConfirmPassword(password=RAW),
        lambda: s.ChildCreate(display_name="Synthetic", username="synthetic-child", password=RAW, grade=6),
        lambda: s.InviteAccept(token="synthetic_token_1234567890123456789012345", password=RAW),
        lambda: ChildPassword(password=RAW, parent_password=RAW),
    ],
)
def test_request_models_preserve_the_actual_password(make):
    request = make()
    assert request.password == RAW
    if isinstance(request, ChildPassword):
        assert request.parent_password == RAW


def test_registration_and_sensitive_parent_confirmation_use_the_same_exact_password(api, mailbox):
    result = api.post(
        "/api/auth/register",
        json={
            "email": "exact@example.org",
            "password": RAW,
            "display_name": "Synthetic",
            "family_name": "Synthetic",
            "adult_consent": True,
        },
    )
    assert result.status_code == 201
    assert api.post("/api/auth/verify", json={"token": mailbox[-1]["token"]}).status_code == 200
    result = api.post("/api/auth/login", json={"username": "exact@example.org", "password": RAW})
    assert result.status_code == 200
    api.headers["Authorization"] = "Bearer " + result.json()["token"]
    with DB() as db:
        user = db.get(User, result.json()["user"]["id"])
        assert verify_password(RAW, user.password_hash) and not verify_password(RAW.strip(), user.password_hash)
    assert api.request("DELETE", "/api/account", json={"password": RAW.strip()}).status_code == 403
    assert api.request("DELETE", "/api/account", json={"password": RAW}).status_code == 200


def test_child_creation_and_parent_reset_keep_exact_credentials(api, household):
    parent, child = household
    with DB.begin() as db:
        db.get(User, parent["id"]).password_hash = password_hash(RAW)
    replacement = "  synthetic child replacement 123  "
    result = api.put(
        "/api/children/" + child["id"] + "/password", json={"parent_password": RAW, "password": replacement}
    )
    assert result.status_code == 200
    with TestClient(app, headers=HEADERS) as client:
        assert (
            client.post("/api/auth/login", json={"username": "test-child", "password": replacement.strip()}).status_code
            == 401
        )
        assert (
            client.post("/api/auth/login", json={"username": "test-child", "password": replacement}).status_code == 200
        )
    result = api.post(
        "/api/families/" + parent["families"][0]["id"] + "/children",
        json={
            "display_name": "Synthetic exact child",
            "username": "exact-child-two",
            "password": RAW,
            "grade": 6,
            "subjects": [],
        },
    )
    assert result.status_code == 201
    with TestClient(app, headers=HEADERS) as client:
        assert client.post("/api/auth/login", json={"username": "exact-child-two", "password": RAW}).status_code == 200
        assert (
            client.post("/api/auth/login", json={"username": "exact-child-two", "password": RAW.strip()}).status_code
            == 401
        )


def test_recovery_changes_no_password_characters_and_revokes_old_sessions(api, household, mailbox):
    user, _ = household
    assert api.post("/api/auth/recovery", json={"email": user["username"]}).status_code == 200
    result = api.post("/api/auth/reset", json={"token": mailbox[-1]["token"], "password": RAW})
    assert result.status_code == 200
    assert api.get("/api/auth/me").status_code == 401
    with TestClient(app, headers=HEADERS) as client:
        assert (
            client.post("/api/auth/login", json={"username": user["username"], "password": RAW.strip()}).status_code
            == 401
        )
        assert client.post("/api/auth/login", json={"username": user["username"], "password": RAW}).status_code == 200


def test_new_invitation_account_preserves_the_password(api, household, mailbox):
    parent, _ = household
    result = api.post(
        "/api/families/" + parent["families"][0]["id"] + "/invitations",
        json={"email": "invited-exact@example.org", "permission": "view"},
    )
    assert result.status_code == 201
    with TestClient(app, headers=HEADERS) as client:
        assert (
            client.post(
                "/api/invitations/accept",
                json={"token": mailbox[-1]["token"], "display_name": "Synthetic invited parent", "password": RAW},
            ).status_code
            == 200
        )
        assert (
            client.post(
                "/api/auth/login", json={"username": "invited-exact@example.org", "password": RAW.strip()}
            ).status_code
            == 401
        )
        result = client.post("/api/auth/login", json={"username": "invited-exact@example.org", "password": RAW})
        assert result.status_code == 200 and result.json()["user"]["families"][0]["permission"] == "view"


@pytest.mark.parametrize("value", [" " * 12, " " * 11 + "a", " " + ("a" * 11) + " ", "a" * 129])
def test_password_hashing_does_not_lower_existing_nonpadding_minimum(value):
    with pytest.raises(HTTPException) as rejected:
        password_hash(value)
    assert rejected.value.status_code == 422
