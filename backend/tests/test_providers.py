from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

from conftest import HEADERS
from fastapi import HTTPException
from fastapi.testclient import TestClient
from schulpilot.config import settings
from schulpilot.db import DB, Family, ProviderConfig, Usage, UsageBucket, User, uid
from schulpilot.main import app
from schulpilot.providers import ProviderError, Result, request_provider, reserve, settle
from schulpilot.security import encrypt, password_hash
from schulpilot.synthetic import sample_unit
from sqlalchemy import select


def configured(family_id):
    object.__setattr__(settings, "real_data_approved", True)
    object.__setattr__(settings, "privacy_evidence", "synthetic-test-approval")
    with DB.begin() as db:
        config = db.get(ProviderConfig, 1)
        config.provider = "openai"
        config.model = "model-from-test-fixture"
        config.emergency_stop = False
        config.image_capable = True
        config.structured_capable = True
        config.capability_evidence = "synthetic fixture"
        config.privacy_approved = True
        config.privacy_evidence = "synthetic fixture"
        config.encrypted_key = encrypt("SYNTHETIC-NOT-A-REAL-KEY")
        config.reserve_micros = 1000
        config.global_limit_micros = 1000000
        config.input_per_million_micros = 1
        config.output_per_million_micros = 1
        config.pricing_evidence = "synthetic fixture"
        family = db.get(Family, family_id)
        family.call_limit = 3
        family.budget_micros = 3000


def test_parallel_family_budget_atomic(api, household):
    user, child = household
    fid = user["families"][0]["id"]
    configured(fid)

    def attempt(_):
        try:
            with DB.begin() as db:
                reserve(db, db.get(Family, fid), child["id"], uid(), "unit")
            return "ok"
        except HTTPException as e:
            return e.status_code

    with ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(attempt, range(12)))
    assert results.count("ok") == 3 and results.count(429) == 9
    with DB() as db:
        usage = list(db.scalars(select(Usage)))
        assert len(usage) == 3
        bucket = db.get(UsageBucket, f"{fid}:{datetime.now(timezone.utc):%Y-%m}")
        assert bucket.calls == 3 and bucket.encumbered_micros == 3000


def test_unknown_cost_retains_reservation_and_stop_blocks(api, household):
    user, child = household
    fid = user["families"][0]["id"]
    configured(fid)
    with DB.begin() as db:
        usage = reserve(db, db.get(Family, fid), child["id"], uid(), "unit")
        settle(db, usage, failed=True)
    with DB() as db:
        record = db.scalar(select(Usage))
        assert record.cost_micros is None and record.status == "failed_unknown"
        bucket = db.get(UsageBucket, record.bucket_ids[1])
        assert bucket.encumbered_micros == 1000 and bucket.unknown_calls == 1
    with DB.begin() as db:
        db.get(ProviderConfig, 1).emergency_stop = True
    with DB() as db:
        try:
            reserve(db, db.get(Family, fid), child["id"], uid(), "unit")
        except HTTPException as e:
            assert e.status_code == 503
        else:
            raise AssertionError("emergency stop bypassed")


def test_settlement_and_global_limit(api, household):
    user, child = household
    fid = user["families"][0]["id"]
    configured(fid)
    with DB.begin() as db:
        config = db.get(ProviderConfig, 1)
        config.global_limit_micros = 1000
        usage = reserve(db, db.get(Family, fid), child["id"], uid(), "unit")
        settle(db, usage, Result({}, 100, 10, 400))
    with DB() as db:
        bucket = db.scalar(select(UsageBucket).where(UsageBucket.id.like("global:%")))
        assert bucket.encumbered_micros == 400 and bucket.known_cost_micros == 400 and bucket.unknown_calls == 0
        try:
            reserve(db, db.get(Family, fid), child["id"], uid(), "unit")
        except HTTPException as e:
            assert e.status_code == 429
        else:
            raise AssertionError("global budget bypassed")


def test_real_data_gate_and_unknown_pricing(api, household):
    user, child = household
    fid = user["families"][0]["id"]
    configured(fid)
    object.__setattr__(settings, "real_data_approved", False)
    with DB() as db:
        try:
            reserve(db, db.get(Family, fid), child["id"], uid(), "unit")
        except HTTPException as e:
            assert e.status_code == 503 and "Datenschutz" in e.detail
        else:
            raise AssertionError("privacy gate bypassed")
    object.__setattr__(settings, "real_data_approved", True)
    with DB.begin() as db:
        db.get(ProviderConfig, 1).input_per_million_micros = None
    with DB() as db:
        try:
            reserve(db, db.get(Family, fid), child["id"], uid(), "unit")
        except HTTPException as e:
            assert "unbekannt" in e.detail
        else:
            raise AssertionError("unknown prices treated as zero")


def test_openai_request_schema_and_invalid_response(api, household, monkeypatch):
    import httpx
    from schulpilot import providers

    user, _ = household
    configured(user["families"][0]["id"])
    calls = []

    class Client:
        def __init__(self, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def post(self, url, headers, json):
            calls.append(json)
            return httpx.Response(
                200,
                json={
                    "status": "completed",
                    "output": [
                        {
                            "type": "message",
                            "content": [{"type": "output_text", "text": __import__("json").dumps(sample_unit())}],
                        }
                    ],
                    "usage": {"input_tokens": 100, "output_tokens": 500},
                },
            )

    monkeypatch.setattr(providers.httpx, "Client", Client)
    with DB() as db:
        config = db.get(ProviderConfig, 1)
    result = request_provider(config, "unit", {"material": "synthetic"})
    assert len(result.data["questions"]) == 4 and result.input_tokens == 100
    assert calls[0]["store"] is False and calls[0]["text"]["format"]["strict"] is True
    assert "tools" not in calls[0] and calls[0]["model"] == "model-from-test-fixture"

    class Broken(Client):
        def post(self, *args, **kwargs):
            return httpx.Response(200, json={"choices": []})

    monkeypatch.setattr(providers.httpx, "Client", Broken)
    try:
        request_provider(config, "unit", {})
    except ProviderError as e:
        assert "nicht als sichere Aufgabenstruktur" in str(e)
    else:
        raise AssertionError("invalid response accepted")


def test_admin_no_private_access_and_keys_never_returned(api, household):
    user, child = household
    with DB.begin() as db:
        admin = User(
            username="test-admin",
            display_name="Admin",
            role="admin",
            verified=True,
            password_hash=password_hash("admin-password-123"),
        )
        db.add(admin)
        db.flush()
        from schulpilot.db import Session, now
        from schulpilot.security import digest

        db.add(
            Session(
                user_id=admin.id, token_hash=digest("synthetic-admin-token"), device="test", expires=int(now()) + 1000
            )
        )
    with TestClient(app, headers={**HEADERS, "Authorization": "Bearer synthetic-admin-token"}) as operator:
        assert operator.get(f"/api/children/{child['id']}/overview").status_code == 403
        data = operator.get("/api/admin/provider").json()
        assert "encrypted_key" not in data and "api_key" not in data
        secret = "SYNTHETIC_NOT_A_REAL_PROVIDER_KEY"
        saved = operator.put(
            "/api/admin/provider",
            json={
                "provider": "openai",
                "model": "model-from-test-fixture",
                "api_key": secret,
                "emergency_stop": True,
                "image_capable": True,
                "structured_capable": True,
                "reserve_micros": 1000,
            },
        )
        assert saved.status_code == 200 and secret not in saved.text and saved.json()["has_key"]
        with DB() as db:
            assert db.get(ProviderConfig, 1).encrypted_key != secret
        assert operator.post("/api/admin/emergency-stop").status_code == 200
        audit = operator.get("/api/admin/audit").json()
        assert any(x["action"] == "admin.emergency_stop" for x in audit)


def test_admin_login_uses_password_without_totp_and_remains_revocable(api):
    with DB.begin() as db:
        db.add(
            User(
                username="password-admin",
                display_name="Admin",
                role="admin",
                verified=True,
                password_hash=password_hash("synthetic-admin-pass-123"),
            )
        )
    payload = {"username": "password-admin", "password": "synthetic-admin-pass-123"}
    response = api.post("/api/auth/login", json=payload)
    assert response.status_code == 200 and response.json()["user"]["role"] == "admin"
    api.headers["Authorization"] = "Bearer " + response.json()["token"]
    assert api.post("/api/auth/logout").status_code == 200
    assert api.get("/api/admin/provider").status_code == 401
    assert api.post("/api/auth/login", json={**payload, "password": "wrong-password"}).status_code == 401


def test_openrouter_is_bound_to_model_upstream_and_has_safe_errors(api, household, monkeypatch):

    import httpx
    from schulpilot import providers

    user, _ = household
    configured(user["families"][0]["id"])
    with DB.begin() as db:
        config = db.get(ProviderConfig, 1)
        config.provider = "openrouter"
        config.openrouter_free_only = False
        config.capability_evidence = "synthetic upstream=fixture-upstream"
    calls = []

    class Client:
        def __init__(self, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def post(self, url, headers, json):
            calls.append(json)
            return httpx.Response(
                200,
                json={
                    "choices": [
                        {"finish_reason": "stop", "message": {"content": __import__("json").dumps(sample_unit())}}
                    ],
                    "usage": {"prompt_tokens": 100, "completion_tokens": 100},
                },
            )

    monkeypatch.setattr(providers.httpx, "Client", Client)
    with DB() as db:
        config = db.get(ProviderConfig, 1)
    assert len(request_provider(config, "unit", {}).data["questions"]) == 4
    assert calls[0]["provider"]["only"] == ["fixture-upstream"] and calls[0]["provider"]["allow_fallbacks"] is False

    class Failed(Client):
        def post(self, *args, **kwargs):
            return httpx.Response(500, json={"error": "PRIVATE_SYNTHETIC_PROVIDER_ECHO"})

    monkeypatch.setattr(providers.httpx, "Client", Failed)
    try:
        request_provider(config, "unit", {})
    except ProviderError as error:
        assert "HTTP 500" in str(error) and "PRIVATE_SYNTHETIC_PROVIDER_ECHO" not in str(error)
    else:
        raise AssertionError("Provider error was hidden")
