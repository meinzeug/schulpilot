from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

import pytest
from conftest import HEADERS, register
from fastapi import HTTPException
from fastapi.testclient import TestClient
from schulpilot import commerce, mail
from schulpilot.config import settings
from schulpilot.db import DB, BankOrder, Family, User, now
from schulpilot.main import app
from schulpilot.security import password_hash
from sqlalchemy import select


@pytest.fixture
def operator(api):
    with DB.begin() as db:
        db.add(
            User(
                username="store-admin",
                display_name="Betrieb",
                role="admin",
                verified=True,
                password_hash=password_hash("synthetic-admin-pass-123"),
            )
        )
    with TestClient(app, headers=HEADERS) as client:
        login = client.post("/api/auth/login", json={"username": "store-admin", "password": "synthetic-admin-pass-123"})
        assert login.status_code == 200
        client.headers["Authorization"] = "Bearer " + login.json()["token"]
        yield client


@pytest.fixture
def shop(operator, monkeypatch):
    for key, value in {
        "operator_name": "Künstlicher Testanbieter",
        "operator_address": "Teststraße 1, 12345 Teststadt",
        "operator_support_email": "synthetic@example.org",
        "operator_phone": "+49 30 000000",
        "smtp_host": "smtp.invalid",
        "smtp_from": "synthetic@example.org",
    }.items():
        object.__setattr__(settings, key, value)
    monkeypatch.setattr(mail, "send_message", lambda *args: None)
    data = {
        "revision": 0,
        "enabled": True,
        "recipient": "Künstlicher Testanbieter",
        "iban": "DE89370400440532013000",
        "tax_mode": "standard19",
    }
    response = operator.put("/api/admin/store", json=data)
    assert response.status_code == 200, response.text
    return data


def order(api, fid, key="synthetic-request-00001", early=True):
    return api.post(
        f"/api/families/{fid}/orders",
        json={
            "plan_id": "start",
            "catalog_revision": 1,
            "request_key": key,
            "accept_terms": True,
            "early_start": early,
        },
    )


def check(operator, oid, ref="SYNTHETIC-BANK-0001", cents=990):
    return operator.post(
        f"/api/admin/orders/{oid}/approve",
        json={
            "received_cents": cents,
            "booking_date": datetime.now(timezone.utc).date().isoformat(),
            "booking_reference": ref,
            "bank_entry_checked": True,
        },
    )


def test_store_disabled_until_real_operator_bank_and_tax(api, operator):
    catalog = api.get("/api/store/catalog").json()
    assert not catalog["enabled"] and catalog["plans"][0]["price_cents"] == 990
    assert operator.put("/api/admin/store", json={"revision": 0, "enabled": True}).status_code == 422
    assert operator.put("/api/admin/store", json={"revision": 0, "iban": "DE00370400440532013000"}).status_code == 422
    assert operator.put("/api/admin/store", json={"revision": 0, "enabled": False}).status_code == 200
    assert operator.put("/api/admin/store", json={"revision": 0, "enabled": False}).status_code == 409


def test_only_checked_payment_grants_prepaid_access(api, mailbox, shop, operator):
    user = register(api, mailbox)
    fid = user["families"][0]["id"]
    with DB() as db:
        family = db.get(Family, fid)
        assert family.commerce_required
        with pytest.raises(HTTPException) as blocked:
            commerce.usage_terms(db, family, enforce=True)
        assert blocked.value.status_code == 403
    response = order(api, fid)
    assert response.status_code == 201, response.text
    row = response.json()
    assert row["status"] == "awaiting_payment" and row["mail_status"] == "accepted"
    assert order(api, fid).json()["id"] == row["id"]
    assert order(api, fid, key="synthetic-another-00001").status_code == 409
    assert check(operator, row["id"], cents=989).status_code == 422
    assert api.post(f"/api/admin/orders/{row['id']}/approve", json={}).status_code == 403
    assert (
        api.post(
            f"/api/admin/orders/{row['id']}/approve",
            json={
                "received_cents": 990,
                "booking_date": datetime.now(timezone.utc).date().isoformat(),
                "booking_reference": "SYNTHETIC",
                "bank_entry_checked": True,
            },
        ).status_code
        == 403
    )
    approved = check(operator, row["id"])
    assert approved.status_code == 200, approved.text
    assert approved.json()["ends"] - approved.json()["starts"] == 30 * 86400
    assert check(operator, row["id"]).status_code == 409
    with DB() as db:
        bucket, calls, _ = commerce.usage_terms(db, db.get(Family, fid), enforce=True)
        assert bucket == f"{fid}:paid:{row['id']}" and calls == 300


def test_order_price_and_terms_are_immutable_and_client_cannot_set_price(api, household, shop, operator):
    user, _ = household
    fid = user["families"][0]["id"]
    invalid = api.post(
        f"/api/families/{fid}/orders",
        json={
            "plan_id": "start",
            "catalog_revision": 1,
            "request_key": "synthetic-price-attack",
            "accept_terms": True,
            "amount_cents": 1,
        },
    )
    assert invalid.status_code == 422
    original = order(api, fid).json()
    config = operator.get("/api/admin/store").json()
    config.pop("missing")
    config.pop("trial_missing")
    config["plans"][0]["price_cents"] = 1190
    config["recipient"] = "Geänderter Empfänger"
    assert operator.put("/api/admin/store", json=config).status_code == 200
    saved = api.get(f"/api/families/{fid}/orders").json()["orders"][0]
    assert saved["amount_cents"] == 990 and saved["bank"]["recipient"] == original["bank"]["recipient"]
    confirmation = api.get(f"/api/orders/{saved['id']}/confirmation")
    assert "9.90 EUR" in confirmation.text and "Widerrufsbelehrung" in confirmation.text


def test_parallel_approval_has_one_winner(api, household, shop, operator):
    user, _ = household
    row = order(api, user["families"][0]["id"]).json()
    bearer = operator.headers["Authorization"]

    def attempt(_):
        with TestClient(app, headers={**HEADERS, "Authorization": bearer}) as client:
            return check(client, row["id"]).status_code

    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(attempt, range(4)))
    assert sorted(results) == [200, 409, 409, 409]


def test_bank_booking_cannot_activate_two_orders(api, mailbox, shop, operator):
    user = register(api, mailbox)
    row = order(api, user["families"][0]["id"]).json()
    assert check(operator, row["id"]).status_code == 200
    renewal = order(api, user["families"][0]["id"], key="synthetic-renewal-0001").json()
    assert check(operator, renewal["id"]).status_code == 409
    assert check(operator, renewal["id"], ref="SYNTHETIC-BANK-0002").status_code == 200
    with DB() as db:
        first, second = db.get(BankOrder, row["id"]), db.get(BankOrder, renewal["id"])
        assert second.starts == first.ends


def test_no_early_start_and_expiration_do_not_delete_family(api, mailbox, shop, operator):
    user = register(api, mailbox)
    fid = user["families"][0]["id"]
    row = order(api, fid, early=False).json()
    checked = check(operator, row["id"])
    assert checked.status_code == 200
    assert checked.json()["starts"] >= row["created"] + 14 * 86400
    assert api.get(f"/api/families/{fid}/orders").json()["access"]["state"] == "scheduled"
    with DB.begin() as db:
        item = db.get(BankOrder, row["id"])
        item.starts, item.ends = int(now()) - 86400, int(now()) - 1
    with DB() as db:
        family = db.get(Family, fid)
        assert commerce.access(db, family)["state"] == "inactive" and family.expires is None
        with pytest.raises(HTTPException):
            commerce.usage_terms(db, family, enforce=True)


def test_family_separation_cancel_and_erasure(api, household, mailbox, shop, operator):
    user, child = household
    fid = user["families"][0]["id"]
    row = order(api, fid).json()
    assert check(operator, row["id"]).status_code == 200
    second = order(api, fid, key="synthetic-second-0002").json()
    assert api.post(f"/api/orders/{second['id']}/cancel").status_code == 200
    assert check(operator, second["id"], ref="SYNTHETIC-BANK-0002").status_code == 409
    with TestClient(app, headers=HEADERS) as unrelated:
        register(unrelated, mailbox, "other@example.org")
        assert unrelated.get(f"/api/orders/{row['id']}/confirmation").status_code == 404
    with TestClient(app, headers=HEADERS) as kid:
        login = kid.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}).json()
        kid.headers["Authorization"] = "Bearer " + login["token"]
        assert kid.get(f"/api/families/{fid}/orders").status_code == 403
    assert api.request("DELETE", "/api/account", json={"password": "secure-parent-pass-123"}).status_code == 200
    with DB() as db:
        kept = db.get(BankOrder, row["id"])
        assert kept.family_id is None and kept.buyer_id is None
        assert db.get(BankOrder, second["id"]) is None
        assert not db.scalar(select(Family).where(Family.id == fid))


def test_checked_external_refund_revokes_access_and_keeps_accounting_record(api, household, shop, operator):
    user, _ = household
    fid = user["families"][0]["id"]
    row = order(api, fid).json()
    assert check(operator, row["id"]).status_code == 200
    response = operator.post(
        f"/api/admin/orders/{row['id']}/refund",
        json={
            "received_cents": 990,
            "booking_date": datetime.now(timezone.utc).date().isoformat(),
            "booking_reference": "SYNTHETIC-REFUND-0001",
            "bank_entry_checked": True,
        },
    )
    assert response.status_code == 200, response.text
    with DB() as db:
        assert commerce.access(db, db.get(Family, fid))["state"] == "inactive"
        with pytest.raises(HTTPException):
            commerce.usage_terms(db, db.get(Family, fid), enforce=True)
    assert api.request("DELETE", "/api/account", json={"password": "secure-parent-pass-123"}).status_code == 200
    with DB() as db:
        kept = db.get(BankOrder, row["id"])
        assert kept.status == "refunded" and kept.family_id is None and kept.buyer_id is None


def test_pausing_checkout_does_not_create_free_commercial_accounts(api, mailbox, shop, operator):
    config = operator.get("/api/admin/store").json()
    config.pop("missing")
    config.pop("trial_missing")
    config["enabled"] = False
    assert operator.put("/api/admin/store", json=config).status_code == 200
    user = register(api, mailbox)
    with DB() as db:
        assert db.get(Family, user["families"][0]["id"]).commerce_required
    assert not api.get("/api/store/catalog").json()["enabled"]
