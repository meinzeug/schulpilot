import json
from concurrent.futures import ThreadPoolExecutor

import pytest
from conftest import HEADERS, create_child, register
from fastapi.testclient import TestClient
from schulpilot.config import runtime_settings
from schulpilot.db import DB, Family, Installation, OperatorJob, ProviderConfig, UsageBucket, User, now
from schulpilot.installation import code_path
from schulpilot.main import app
from schulpilot.operator_probe import work_one
from schulpilot.providers import Result
from schulpilot.security import decrypt
from sqlalchemy import select


def fresh():
    with DB.begin() as db:
        db.get(Installation, 1).completed = False
    return code_path().read_text().strip()


def unlock(api):
    assert api.post("/api/setup/unlock", json={"code": fresh()}).status_code == 200


def finish(api):
    return api.post("/api/setup/complete", json={"username": "admin", "password": "synthetic-admin-password-123"})


def test_first_installation_is_closed_to_accounts_until_operator_unlock(api):
    secret = fresh()
    assert api.get("/api/setup/status").json() == {"required": True}
    assert api.post("/api/demo").status_code == 503
    assert api.get("/api/setup/config").status_code == 401
    assert (
        api.post("/api/setup/complete", json={"username": "admin", "password": "synthetic-password-123"}).status_code
        == 401
    )
    assert api.post("/api/setup/unlock", json={"code": "wrong-code-" * 4}).status_code == 401
    response = api.post("/api/setup/unlock", json={"code": secret})
    assert response.status_code == 200 and secret not in response.text
    assert "HttpOnly" in response.headers["set-cookie"] and "SameSite=strict" in response.headers["set-cookie"]
    assert "bootstrap_digest" not in api.get("/api/setup/config").text


def test_codex_catalog_requires_the_live_single_use_setup_cookie(api, monkeypatch):
    calls = []
    catalog = {
        "source": "codex_cli",
        "cli_version": "0.162.1",
        "models": [{
            "id": "synthetic-model",
            "name": "Synthetic model",
            "reasoning_efforts": ["medium", "high"],
            "default_reasoning_effort": "medium",
            "input_modalities": ["text", "image"],
            "hidden": False,
        }],
    }

    def read(actor, db):
        calls.append(actor)
        return catalog

    monkeypatch.setattr("schulpilot.admin.provider_model_catalog", read)
    fresh()
    path = "/api/setup/provider/codex/models"
    assert api.get(path).status_code == 401
    assert calls == []
    unlock(api)
    response = api.get(path)
    assert response.status_code == 200 and response.json() == catalog
    assert calls == ["initial-setup"]
    with TestClient(app, headers=HEADERS) as untrusted:
        assert untrusted.get(path).status_code == 401
    assert calls == ["initial-setup"]
    assert finish(api).status_code == 201
    assert api.get(path).status_code == 409
    assert calls == ["initial-setup"]


def test_expired_setup_session_cannot_read_codex_catalog(api, monkeypatch):
    from schulpilot.db import Token

    def forbidden(*args):
        raise AssertionError("Expired setup must not reach the private worker")

    monkeypatch.setattr("schulpilot.admin.provider_model_catalog", forbidden)
    unlock(api)
    with DB.begin() as db:
        for token in db.scalars(select(Token).where(Token.purpose == "setup")):
            token.expires = int(now()) - 1
    assert api.get("/api/setup/provider/codex/models").status_code == 401


def test_settings_are_encrypted_persisted_and_secrets_never_echoed(api):
    unlock(api)
    body = {
        "smtp_host": "smtp.example.org",
        "smtp_from": "service@example.org",
        "smtp_user": "service@example.org",
        "smtp_password": "synthetic-smtp-private-123",
        "default_child_limit": 2,
        "operator_name": "Testbetrieb",
    }
    response = api.put("/api/setup/site", json=body)
    assert response.status_code == 200, response.text
    assert body["smtp_password"] not in response.text and response.json()["site"]["has_smtp_password"]
    with DB() as db:
        row = db.get(Installation, 1)
        assert body["smtp_password"] not in row.encrypted_settings
        assert json.loads(decrypt(row.encrypted_settings))["smtp_password"] == body["smtp_password"]
    assert runtime_settings().smtp_password == body["smtp_password"]
    assert api.put("/api/setup/site", json={"smtp_password": "", "operator_name": "Neuer Name"}).status_code == 200
    assert runtime_settings().smtp_password == body["smtp_password"]
    assert api.put("/api/setup/site", json={"clear_smtp_password": True}).status_code == 200
    assert runtime_settings().smtp_password == ""


def test_partial_settings_validate_merged_values_without_echoing_retained_secrets(api):
    unlock(api)
    saved = api.put(
        "/api/setup/site",
        json={
            "real_data_approved": True,
            "privacy_evidence": "Recorded artificial-data approval for isolated installation test",
            "smtp_password": "synthetic-retained-secret-123",
        },
    )
    assert saved.status_code == 200
    invalid = api.put("/api/setup/site", json={"privacy_evidence": ""})
    assert invalid.status_code == 422
    assert "synthetic-retained-secret-123" not in invalid.text
    assert runtime_settings().privacy_evidence and runtime_settings().real_data_approved


def test_wizard_completion_creates_password_only_admin_and_cannot_reopen(api):
    unlock(api)
    assert finish(api).status_code == 201
    assert not code_path().exists()
    assert api.get("/api/setup/status").json() == {"required": False}
    assert finish(api).status_code == 409
    assert api.get("/api/setup/config").status_code == 409
    response = api.post("/api/auth/login", json={"username": "admin", "password": "synthetic-admin-password-123"})
    assert response.status_code == 200 and response.json()["user"]["role"] == "admin"
    assert "Max-Age=86400" in response.headers["set-cookie"]
    api.headers["Authorization"] = "Bearer " + response.json()["token"]
    assert api.get("/api/admin/installation").status_code == 200


def test_parallel_completion_creates_exactly_one_admin(api):
    unlock(api)
    cookie = api.cookies.get("sp_setup")

    def submit(_):
        with TestClient(app, headers=HEADERS) as own:
            own.cookies.set("sp_setup", cookie, path="/api/setup")
            return finish(own).status_code

    with ThreadPoolExecutor(max_workers=2) as pool:
        assert sorted(pool.map(submit, range(2))) == [201, 409]
    with DB() as db:
        assert len(list(db.scalars(select(User)))) == 1


def test_existing_family_cannot_be_claimed_through_setup(api, mailbox):
    register(api, mailbox)
    assert api.get("/api/setup/status").json() == {"required": False}
    assert api.post("/api/setup/unlock", json={"code": "synthetic-" * 5}).status_code == 409
    assert api.get("/api/admin/installation").status_code == 403
    assert api.put("/api/admin/installation/site", json={"default_child_limit": 20}).status_code == 403


def test_expired_setup_code_and_cookie_cannot_change_or_complete_installation(api):
    secret = fresh()
    with DB.begin() as db:
        db.get(Installation, 1).bootstrap_expires = int(now()) - 1
    assert api.post("/api/setup/unlock", json={"code": secret}).status_code == 401
    with DB.begin() as db:
        db.get(Installation, 1).bootstrap_expires = int(now()) + 3600
    assert api.post("/api/setup/unlock", json={"code": secret}).status_code == 200
    from schulpilot.db import Token

    with DB.begin() as db:
        token = db.scalar(select(Token).where(Token.purpose == "setup"))
        token.expires = int(now()) - 1
    assert api.put("/api/setup/site", json={"operator_name": "Unberechtigt"}).status_code == 401
    assert finish(api).status_code == 401


def test_historical_pilot_fixture_and_upload_gate_follow_persisted_settings(api, mailbox):
    # Historical fixture only; current public signup is fail-closed and tested
    # separately without the legacy-cohort helper in test_family_trial.py.
    from schulpilot.config import settings
    from test_school_day import image_bytes

    unlock(api)
    body = {
        "default_plan": "Familienpaket",
        "default_child_limit": 2,
        "default_call_limit": 75,
        "default_budget_micros": 1_000_000,
        "real_data_approved": True,
        "privacy_evidence": "Isolated test, only artificial images; no external provider calls",
    }
    assert api.put("/api/setup/site", json=body).status_code == 200
    assert finish(api).status_code == 201
    user = register(api, mailbox)
    child = create_child(api, user)
    with DB() as db:
        family = db.get(Family, user["families"][0]["id"])
        assert (family.plan, family.child_limit, family.call_limit, family.budget_micros) == (
            "Familienpaket",
            2,
            75,
            1_000_000,
        )
    assert not settings.real_data_approved
    upload = api.post(
        f"/api/children/{child['id']}/materials", files={"file": ("artificial.jpg", image_bytes(), "image/jpeg")}
    )
    assert upload.status_code == 201, upload.text
    assert api.get("/api/status").json()["real_data_enabled"]
    # The persisted operator decision also overrides a permissive old environment.
    with DB.begin() as db:
        row = db.get(Installation, 1)
        values = json.loads(decrypt(row.encrypted_settings))
        values["real_data_approved"] = False
        from schulpilot.security import encrypt

        row.encrypted_settings = encrypt(json.dumps(values))
    object.__setattr__(settings, "real_data_approved", True)
    blocked = api.post(
        f"/api/children/{child['id']}/materials", files={"file": ("artificial.jpg", image_bytes(), "image/jpeg")}
    )
    assert blocked.status_code == 503
    assert not api.get("/api/status").json()["real_data_enabled"]


@pytest.mark.parametrize(
    "body",
    [
        {"smtp_mode": "plain"},
        {"smtp_from": "invalid"},
        {"real_data_approved": True},
        {"fcm_public_config": '{"private_key":"private"}'},
        {"fcm_service_account_json": '{"type":"service_account","token_uri":"http://internal/"}'},
    ],
)
def test_insecure_or_invalid_settings_are_rejected(api, body):
    unlock(api)
    assert api.put("/api/setup/site", json=body).status_code == 422


def configure_operator_probe(api):
    from schulpilot.config import settings
    from schulpilot.security import encrypt

    unlock(api)
    object.__setattr__(settings, "synthetic_ai_enabled", True)
    with DB.begin() as db:
        config = db.get(ProviderConfig, 1)
        config.provider, config.model = "openrouter", "synthetic-model:free"
        config.encrypted_key = encrypt("synthetic-provider-key")
        config.emergency_stop = False
        config.image_capable = config.structured_capable = True
        config.capability_evidence = "upstream=synthetic-route fixed artificial-only test"
        config.input_per_million_micros = config.output_per_million_micros = 0


def test_operator_probe_is_durable_bounded_and_accounts_for_global_usage(api, monkeypatch):
    from schulpilot import operator_probe

    configure_operator_probe(api)
    calls = []

    def provider(config, function, payload, **kwargs):
        assert payload == {} and kwargs == {"synthetic_fixture": True, "private_probe": True}
        calls.append(function)
        return Result({}, 30, 20, 0, cost_source="reported")

    monkeypatch.setattr(operator_probe, "request_provider", provider)
    queued = api.post("/api/setup/provider/probe")
    assert queued.status_code == 202
    assert api.post("/api/setup/provider/probe").json()["id"] == queued.json()["id"]
    assert work_one()
    report = api.get("/api/setup/provider/probes/" + queued.json()["id"]).json()
    assert report["status"] == "completed" and len(report["report"]) == 3
    assert calls == ["extract", "unit", "package"]
    with DB() as db:
        assert len(list(db.scalars(select(OperatorJob)))) == 1
        bucket = db.scalar(select(UsageBucket))
        assert bucket.calls == 3 and bucket.unknown_calls == 0 and bucket.encumbered_micros == 0


def test_operator_probe_unknown_cost_retains_budget_and_never_automatically_retries(api, monkeypatch):
    from schulpilot import operator_probe
    from schulpilot.providers import ProviderError

    configure_operator_probe(api)
    with DB.begin() as db:
        config = db.get(ProviderConfig, 1)
        config.global_limit_micros = config.reserve_micros
    calls = []

    def unavailable(config, function, payload, **kwargs):
        calls.append(function)
        raise ProviderError("Synthetic provider outage")

    monkeypatch.setattr(operator_probe, "request_provider", unavailable)
    job_id = api.post("/api/setup/provider/probe").json()["id"]
    assert work_one() and not work_one()
    report = api.get("/api/setup/provider/probes/" + job_id).json()
    assert report["status"] == "failed" and calls == ["extract"]
    assert report["report"][0]["cost_micros_usd"] is None
    with DB() as db:
        bucket = db.scalar(select(UsageBucket))
        assert bucket.calls == 1 and bucket.unknown_calls == 1
        assert bucket.encumbered_micros == db.get(ProviderConfig, 1).reserve_micros


def test_operator_probe_does_not_approve_a_changed_provider_configuration(api, monkeypatch):
    from schulpilot import operator_probe

    configure_operator_probe(api)
    with DB.begin() as db:
        db.get(ProviderConfig, 1).production_block_reason = "Not yet tested"
    calls = []

    def changed(config, function, payload, **kwargs):
        calls.append(function)
        with DB.begin() as db:
            current = db.get(ProviderConfig, 1)
            current.revision += 1
        return Result({}, 30, 20, 0, cost_source="reported")

    monkeypatch.setattr(operator_probe, "request_provider", changed)
    job_id = api.post("/api/setup/provider/probe").json()["id"]
    assert work_one()
    assert api.get("/api/setup/provider/probes/" + job_id).json()["status"] == "failed"
    assert calls == ["extract"]
    with DB() as db:
        assert db.get(ProviderConfig, 1).production_block_reason == "Not yet tested"
        bucket = db.scalar(select(UsageBucket))
        assert bucket.calls == 1 and bucket.unknown_calls == 0


def test_mail_test_uses_saved_tls_settings_and_does_not_expose_password(api, monkeypatch):
    from schulpilot import mail

    unlock(api)
    assert (
        api.put(
            "/api/setup/site",
            json={
                "smtp_host": "saved-smtp.example.org",
                "smtp_from": "service@example.org",
                "smtp_user": "saved-mail-user",
                "smtp_password": "synthetic-saved-mail-password",
            },
        ).status_code
        == 200
    )
    calls = []

    class SMTP:
        def __init__(self, host, port, **kwargs):
            assert host == "saved-smtp.example.org" and port == 587

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def starttls(self, context):
            assert context.check_hostname
            calls.append("tls")

        def login(self, user, password):
            assert (user, password) == ("saved-mail-user", "synthetic-saved-mail-password")
            calls.append("login")

        def send_message(self, message):
            assert message["To"] == "recipient@example.org"
            calls.append("sent")

    monkeypatch.setattr(mail.smtplib, "SMTP", SMTP)
    response = api.post("/api/setup/mail-test", json={"email": "recipient@example.org"})
    assert response.status_code == 200 and calls == ["tls", "login", "sent"]
    assert "synthetic-saved-mail-password" not in response.text


def test_parallel_first_start_initializes_provider_once():
    from concurrent.futures import ThreadPoolExecutor

    from schulpilot.db import DB, ProviderConfig, init_db
    from sqlalchemy import delete, func, select

    with DB.begin() as db:
        db.execute(delete(ProviderConfig))
    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(lambda _: init_db(), range(4)))
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(ProviderConfig)) == 1
        assert db.get(ProviderConfig, 1).emergency_stop


def test_existing_family_clients_can_login_while_the_apk_updates(api, household):
    parent, _ = household
    for username, password, role in [
        (parent["username"], "secure-parent-pass-123", "parent"),
        ("test-child", "secure-child-pass-123", "child"),
    ]:
        response = api.post("/api/auth/login", json={"username": username, "password": password, "totp": ""})
        assert response.status_code == 200
        assert response.json()["user"]["role"] == role
    assert (
        api.post(
            "/api/auth/login",
            json={"username": "test-child", "password": "secure-child-pass-123", "totp": "", "role": "admin"},
        ).status_code
        == 422
    )


def test_setup_probe_recovery_is_cookie_bound_read_only_and_closes_after_setup(api):
    fresh()
    path = "/api/setup/provider/probes"
    assert api.get(path).status_code == 401
    unlock(api)
    assert api.get(path).json() == {"latest": None, "active": None}
    with DB.begin() as db:
        db.add(OperatorJob(id="e" * 32, actor="initial-setup", config_revision=7,
                           status="completed", created=123))
    data = api.get(path).json()
    assert data == {"latest": {"id": "e" * 32, "status": "completed", "config_revision": 7, "created": 123},
                    "active": None}
    with DB() as db:
        assert len(list(db.scalars(select(OperatorJob)))) == 1
        assert len(list(db.scalars(select(UsageBucket)))) == 0
    assert finish(api).status_code == 201
    assert api.get(path).status_code == 409
