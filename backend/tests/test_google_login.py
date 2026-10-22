"""Synthetic OIDC identities; no Google account or network is used by this suite."""

import json
from urllib.parse import parse_qs, urlparse

import httpx
import pytest
from conftest import HEADERS, create_child, register
from fastapi.testclient import TestClient
from schulpilot import google_login as g
from schulpilot.config import settings
from schulpilot.db import DB, Family, GoogleFlow, GoogleIdentity, User, now
from schulpilot.main import app
from sqlalchemy import func, select

CLIENT = {
    "web": {
        "client_id": "123456-synthetic.apps.googleusercontent.com",
        "client_secret": "synthetic-client-secret-only",
        "auth_uri": "https://accounts.google.com/o/oauth2/auth",
        "token_uri": "https://oauth2.googleapis.com/token",
        "redirect_uris": ["http://testserver/api/auth/google/callback"],
    }
}
VERIFIER = "a" * 64
TICKETS = {}


@pytest.fixture
def google(monkeypatch):
    object.__setattr__(settings, "google_login_enabled", True)
    object.__setattr__(settings, "google_oauth_client_json", json.dumps(CLIENT))
    values = {"email": "google-parent@example.org", "sub": "synthetic-google-subject", "hd": "example.org"}
    calls = []

    def exchange(config, code, verifier):
        calls.append(code)
        return {
            "iss": "https://accounts.google.com",
            "aud": CLIENT["web"]["client_id"],
            "email_verified": True,
            **values,
        }

    monkeypatch.setattr(g, "exchange_code", exchange)
    return values, calls


def begin(api, google, intent="login", password="", native=True):
    if not native:
        api.headers.pop("x-client-platform", None)
    prepared = api.post(
        "/api/auth/google/prepare",
        json={
            "intent": intent,
            "password": password,
            **({"client_challenge": g.challenge(VERIFIER)} if native else {}),
        },
    )
    assert prepared.status_code == 200, prepared.text
    prepared = prepared.json()
    started = api.post("/api/auth/google/start", json={"request": prepared["request"]})
    assert started.status_code == 200
    query = parse_qs(urlparse(started.json()["authorization_url"]).query)
    assert query["scope"] == ["openid email"]
    assert query["code_challenge_method"] == ["S256"]
    google[0]["nonce"] = query["nonce"][0]
    return prepared, query["state"][0]


def callback(api, state, **extra):
    r = api.get(
        "/api/auth/google/callback",
        params={"state": state, **({"code": "synthetic-code"} if not extra else extra)},
        follow_redirects=False,
    )
    fragment = parse_qs(urlparse(r.headers["location"]).fragment)
    if fragment.get("flow") and fragment.get("ticket"):
        TICKETS[fragment["flow"][0]] = fragment["ticket"][0]
    return r


def result(api, flow, **extra):
    return api.post(
        "/api/auth/google/result",
        json={
            "flow_id": flow["flow_id"],
            "client_verifier": VERIFIER,
            **({"ticket": TICKETS[flow["flow_id"]]} if flow["flow_id"] in TICKETS else {}),
            **extra,
        },
    )


def registration():
    return {
        "email": "google-parent@example.org",
        "display_name": "Test-Eltern",
        "family_name": "Künstliche Familie",
        "password": "secure-parent-pass-123",
        "adult_consent": True,
    }


def test_unconfigured_google_does_not_replace_own_accounts(api):
    assert api.get("/api/auth/google/status").json() == {"available": False, "parents_only": True}
    assert api.post("/api/auth/google/prepare", json={}).status_code == 503


def test_native_registration_login_and_single_consumption(api, google):
    flow, state = begin(api, google)
    assert callback(api, state).status_code == 303
    assert result(api, flow).json()["status"] == "registration_required"
    created = result(api, flow, registration=registration())
    assert created.status_code == 200, created.text
    user = created.json()["user"]
    assert user["role"] == "parent" and len(user["families"]) == 1
    assert "token" in created.json()
    assert result(api, flow).status_code == 400
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Family)) == 1
        saved = db.get(GoogleFlow, flow["flow_id"])
        assert saved.subject is None and saved.email is None and saved.encrypted_verifier is None
        assert db.scalar(select(GoogleIdentity.user_id)) == user["id"]
    # No second account; Google's stable subject continues to identify the parent.
    api.headers["Authorization"] = "Bearer " + created.json()["token"]
    second, state = begin(api, google)
    callback(api, state)
    logged = result(api, second)
    assert logged.json()["user"]["id"] == user["id"]
    assert api.get("/api/auth/me").status_code == 401  # Previous device session revoked.
    api.headers["Authorization"] = "Bearer " + logged.json()["token"]
    assert api.get("/api/auth/me").status_code == 200


def test_web_session_is_http_only_and_never_returned_as_json(api, google):
    flow, state = begin(api, google, native=False)
    assert callback(api, state).status_code == 303
    r = result(api, flow, registration=registration())
    assert r.status_code == 200, r.text
    assert "token" not in r.json()
    assert "HttpOnly" in r.headers["set-cookie"] and "SameSite=strict" in r.headers["set-cookie"]
    assert api.get("/api/auth/me").status_code == 200


def test_native_handoff_needs_proof_and_cannot_become_browser_session(api, google):
    flow, state = begin(api, google)
    callback(api, state)
    # The returning browser only gets the app-return instruction, no email or credentials.
    r = api.post("/api/auth/google/result", json={"flow_id": flow["flow_id"]})
    assert r.json()["status"] == "return_to_app" and "email" not in r.json() and "token" not in r.json()
    with TestClient(app, headers=HEADERS) as foreign:
        assert (
            foreign.post(
                "/api/auth/google/result", json={"flow_id": flow["flow_id"], "client_verifier": "b" * 64}
            ).status_code
            == 403
        )
        assert foreign.post("/api/auth/google/result", json={"flow_id": flow["flow_id"]}).status_code == 403
    assert result(api, flow).json()["status"] == "registration_required"


def test_callback_binding_state_and_replay(api, google):
    flow, state = begin(api, google)
    with TestClient(app, headers=HEADERS) as foreign:
        assert "error=invalid" in callback(foreign, state).headers["location"]
    assert "error=invalid" in callback(api, "b" * 64).headers["location"]
    callback(api, state)
    assert "error=invalid" in callback(api, state).headers["location"]
    assert len(google[1]) == 1
    assert result(api, flow).json()["status"] == "registration_required"


@pytest.mark.parametrize(
    "key,value",
    [
        ("email_verified", False),
        ("aud", "other-client"),
        ("azp", "other-client"),
        ("iss", "https://attacker.example.org"),
        ("nonce", "wrong-nonce"),
        ("sub", ""),
    ],
)
def test_untrusted_identity_claims_are_rejected(api, google, key, value):
    flow, state = begin(api, google)
    google[0][key] = value
    callback(api, state)
    assert result(api, flow).status_code == 400
    with DB() as db:
        assert not db.scalar(select(User.id))


def test_existing_email_never_links_without_password(api, mailbox, google):
    register(api, mailbox, "google-parent@example.org")
    flow, state = begin(api, google)
    callback(api, state)
    assert result(api, flow, registration=registration()).status_code == 409
    with DB() as db:
        assert not db.scalar(select(GoogleIdentity.subject))
    assert (
        api.post(
            "/api/auth/google/prepare",
            json={"intent": "link", "password": "wrong", "client_challenge": g.challenge(VERIFIER)},
        ).status_code
        == 403
    )
    linked, state = begin(api, google, intent="link", password="secure-parent-pass-123")
    callback(api, state)
    assert result(api, linked).json()["status"] == "linked"
    assert api.get("/api/auth/google/identity").json()["linked"]
    assert api.request("DELETE", "/api/auth/google/identity", json={"password": "wrong"}).status_code == 403
    assert (
        api.request("DELETE", "/api/auth/google/identity", json={"password": "secure-parent-pass-123"}).status_code
        == 200
    )
    assert not api.get("/api/auth/google/identity").json()["linked"]


def test_link_fails_after_session_revocation_and_for_different_email(api, mailbox, google):
    register(api, mailbox)
    flow, state = begin(api, google, intent="link", password="secure-parent-pass-123")
    callback(api, state)
    assert result(api, flow).status_code == 409
    google[0]["email"] = "parent@example.org"
    flow, state = begin(api, google, intent="link", password="secure-parent-pass-123")
    callback(api, state)
    api.post("/api/auth/logout")
    assert result(api, flow).status_code == 400  # Logout deletes the pending link flow.


def test_child_and_admin_cannot_use_google(api, mailbox, google):
    parent = register(api, mailbox)
    create_child(api, parent)
    r = api.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"})
    api.headers["Authorization"] = "Bearer " + r.json()["token"]
    assert api.post("/api/auth/google/prepare", json={"client_challenge": g.challenge(VERIFIER)}).status_code == 403
    assert api.get("/api/auth/google/identity").status_code == 403
    with DB.begin() as db:
        db.get(User, parent["id"]).role = "admin"
    r = api.post("/api/auth/login", json={"username": "parent@example.org", "password": "secure-parent-pass-123"})
    api.headers["Authorization"] = "Bearer " + r.json()["token"]
    assert api.post("/api/auth/google/prepare", json={"client_challenge": g.challenge(VERIFIER)}).status_code == 403


def test_cancel_network_error_expiry_and_start_replay(api, google, monkeypatch):
    flow, state = begin(api, google)
    assert api.post("/api/auth/google/start", json={"request": flow["request"]}).status_code == 400
    callback(api, state, error="access_denied")
    assert "abgebrochen" in result(api, flow).json()["detail"]
    flow, state = begin(api, google)
    monkeypatch.setattr(g, "exchange_code", lambda *a: (_ for _ in ()).throw(httpx.ConnectError("synthetic")))
    callback(api, state)
    assert "erreichbar" in result(api, flow).json()["detail"]
    with DB.begin() as db:
        db.get(GoogleFlow, flow["flow_id"]).expires = int(now()) - 1
    assert result(api, flow).status_code == 400


def test_registration_requires_adult_consent_and_cannot_select_role(api, google):
    flow, state = begin(api, google)
    callback(api, state)
    assert result(api, flow, registration={**registration(), "adult_consent": False}).status_code == 422
    assert result(api, flow, registration={**registration(), "role": "admin"}).status_code == 422
    assert result(api, flow, registration={**registration(), "email": "other@example.org"}).status_code == 422
    assert result(api, flow, registration=registration()).status_code == 200


def test_client_configuration_rejects_other_endpoints_and_callback(api):
    for key, value in [
        ("token_uri", "https://attacker.example.org/token"),
        ("redirect_uris", ["https://other.example.org/api/auth/google/callback"]),
    ]:
        raw = {"web": {**CLIENT["web"], key: value}}
        with pytest.raises(ValueError):
            g.validate_client(json.dumps(raw), settings.public_url)


def test_real_google_auth_library_checks_signature_expiry_and_audience(monkeypatch):
    """Exercise the installed verifier with a locally signed synthetic JWT."""
    import time
    from types import SimpleNamespace

    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from google.auth import crypt, jwt

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    private = key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
    )
    public = (
        key.public_key()
        .public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)
        .decode()
    )
    claims = {
        "iss": "https://accounts.google.com",
        "aud": CLIENT["web"]["client_id"],
        "sub": "synthetic",
        "iat": int(time.time()),
        "exp": int(time.time()) + 120,
    }
    current = {}
    observed = []

    def token_endpoint(request):
        assert str(request.url) == "https://oauth2.googleapis.com/token"
        observed.append(True)
        return httpx.Response(200, json={"id_token": current["jwt"]})

    original = httpx.Client
    monkeypatch.setattr(g.httpx, "Client", lambda **kw: original(transport=httpx.MockTransport(token_endpoint), **kw))

    class Certs:
        def __call__(self, *args, **kwargs):
            assert kwargs["timeout"] == 10
            return SimpleNamespace(status=200, data=json.dumps({"synthetic-key": public}).encode())

    monkeypatch.setattr(g, "GoogleRequest", Certs)
    signer = crypt.RSASigner.from_string(private, key_id="synthetic-key")
    current["jwt"] = jwt.encode(signer, claims).decode()
    assert g.exchange_code(CLIENT["web"], "synthetic", "a" * 64)["sub"] == "synthetic"
    for changed in [{"aud": "different-client"}, {"iat": int(time.time()) - 100, "exp": int(time.time()) - 60}]:
        current["jwt"] = jwt.encode(signer, {**claims, **changed}).decode()
        with pytest.raises(ValueError):
            g.exchange_code(CLIENT["web"], "synthetic", "a" * 64)
    other = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pem = other.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
    )
    current["jwt"] = jwt.encode(crypt.RSASigner.from_string(pem, key_id="synthetic-key"), claims).decode()
    with pytest.raises(ValueError):
        g.exchange_code(CLIENT["web"], "synthetic", "a" * 64)
    assert len(observed) == 4


def test_native_initiator_cannot_claim_somebody_elses_callback(api, google):
    flow, state = begin(api, google)
    callback(api, state)
    # Knowing the initiating app's proof is still insufficient without receipt
    # of the callback. This also blocks browser-link/QR login phishing.
    r = api.post("/api/auth/google/result", json={"flow_id": flow["flow_id"], "client_verifier": VERIFIER})
    assert r.json() == {"status": "awaiting_return"}
    assert result(api, flow, ticket="x" * 64).status_code == 403
    assert result(api, flow).json()["status"] == "registration_required"


def test_web_flow_cannot_be_upgraded_to_json_bearer_session(api, google):
    flow, state = begin(api, google, native=False)
    callback(api, state)
    api.headers["X-Client-Platform"] = "native"
    r = result(api, flow, registration=registration())
    assert r.status_code == 403 and "token" not in r.json()
    api.headers.pop("x-client-platform")
    assert result(api, flow, registration=registration()).status_code == 200


def test_third_party_google_email_needs_actual_mailbox_confirmation(api, mailbox, google):
    google[0].pop("hd")
    flow, state = begin(api, google)
    callback(api, state)
    r = result(api, flow, registration=registration())
    assert r.json() == {"status": "verification_required", "access_notice":
        "Der Lernzugang für neue Familien wird noch vorbereitet. Neue KI-Aufträge sind bis zur Freigabe einer Testphase oder eines bezahlten Tarifs gesperrt."}
    assert "token" not in r.json()
    assert api.get("/api/auth/me").status_code == 401
    with DB() as db:
        assert not db.scalar(select(User.verified))
    assert mailbox[-1]["route"] == "verify"
    assert api.post("/api/auth/verify", json={"token": mailbox[-1]["token"]}).status_code == 200
    flow, state = begin(api, google)
    callback(api, state)
    assert result(api, flow).json()["status"] == "authenticated"
