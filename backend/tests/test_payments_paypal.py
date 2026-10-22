"""Only synthetic HTTP transport and isolated DB. Never PayPal sandbox/live calls."""

import copy
import json
from concurrent.futures import ThreadPoolExecutor

import httpx
import pytest
from conftest import HEADERS, register
from fastapi.testclient import TestClient
from schulpilot import commerce
from schulpilot import payments_paypal as payments
from schulpilot import paypal_client as provider
from schulpilot.db import DB, BankOrder, Family, Session
from schulpilot.main import app
from schulpilot.payment_models import (
    PaymentAttempt,
    PaymentConfiguration,
    PaymentConfigurationRevision,
    PaymentEvent,
    PaymentRefund,
)
from schulpilot.security import decrypt
from sqlalchemy import func, select, update
from test_commerce import check
from test_commerce import operator as operator_fixture
from test_commerce import shop as shop_fixture


@pytest.fixture
def operator(api):
    yield from operator_fixture.__wrapped__(api)


@pytest.fixture
def shop(operator, monkeypatch):
    return shop_fixture.__wrapped__(operator, monkeypatch)


class PayPalMock:
    def __init__(self):
        self.calls = []
        self.orders = {}
        self.refunds = {}
        self.capture_status = "COMPLETED"
        self.timeout_create = False
        self.timeout_capture = False
        self.capture_http_error = False
        self.minimal_capture = False
        self.signature = "SUCCESS"
        self.after_capture = None
        self.tamper = None

    def handle(self, request):
        path = request.url.path
        assert request.url.host == "api-m.sandbox.paypal.com"
        data = (
            json.loads(request.content)
            if request.content and "json" in request.headers.get("content-type", "")
            else None
        )
        self.calls.append((request.method, path, data, request.headers.get("paypal-request-id")))
        if path == "/v1/oauth2/token":
            return httpx.Response(200, json={"access_token": "SYNTHETIC-TRANSPORT-TOKEN"})
        if path == "/v1/notifications/verify-webhook-signature":
            return httpx.Response(200, json={"verification_status": self.signature})
        if path == "/v2/checkout/orders" and request.method == "POST":
            if self.timeout_create:
                raise httpx.ReadTimeout("synthetic", request=request)
            identifier = "SYNTHETIC-ORDER-" + str(len(self.orders) + 1)
            value = {"id": identifier, "status": "CREATED", "purchase_units": copy.deepcopy(data["purchase_units"])}
            self.orders[identifier] = value
            response = copy.deepcopy(value)
            if self.tamper:
                self.tamper(response)
            return httpx.Response(201, json=response)
        if path.startswith("/v2/checkout/orders/"):
            identifier = path.split("/")[4]
            value = self.orders[identifier]
            if path.endswith("/capture"):
                if self.capture_http_error:
                    return httpx.Response(
                        422, json={"name": "UNPROCESSABLE_ENTITY", "details": [{"issue": "ORDER_ALREADY_CAPTURED"}]}
                    )
                value["status"] = "COMPLETED"
                unit = value["purchase_units"][0]
                unit["payments"] = {
                    "captures": [
                        {
                            "id": "SYNTHETIC-CAPTURE-" + identifier,
                            "status": self.capture_status,
                            "final_capture": True,
                            "amount": unit["amount"],
                        }
                    ]
                }
                if self.after_capture:
                    self.after_capture()
                if self.timeout_capture:
                    raise httpx.ReadTimeout("synthetic", request=request)
                reply = (
                    {
                        "id": value["id"],
                        "status": value["status"],
                        "purchase_units": [{"reference_id": unit["reference_id"], "payments": unit["payments"]}],
                    }
                    if self.minimal_capture
                    else value
                )
                return httpx.Response(201, json=reply)
            return httpx.Response(200, json=value)
        if path.startswith("/v2/payments/refunds/"):
            return httpx.Response(200, json=self.refunds[path.rsplit("/", 1)[1]])
        if path.startswith("/v2/payments/captures/"):
            identifier = path.rsplit("/", 1)[1]
            for value in self.orders.values():
                for capture in value["purchase_units"][0].get("payments", {}).get("captures", []):
                    if capture["id"] == identifier:
                        return httpx.Response(
                            200, json={**capture, "supplementary_data": {"related_ids": {"order_id": value["id"]}}}
                        )
        raise AssertionError("Unexpected fixed provider request: " + path)

    def mutations(self, suffix):
        return [call for call in self.calls if call[0] == "POST" and call[1].endswith(suffix)]


@pytest.fixture
def transport(monkeypatch):
    fake = PayPalMock()
    monkeypatch.setattr(
        provider, "client", lambda: httpx.Client(transport=httpx.MockTransport(fake.handle), follow_redirects=False)
    )
    return fake


@pytest.fixture
def wallet(shop, operator, transport):
    response = operator.put(
        "/api/admin/payments/paypal",
        json={
            "revision": 0,
            "enabled": True,
            "client_id": "SYNTHETIC-CLIENT",
            "client_secret": "SYNTHETIC-SECRET",
            "merchant_id": "SYNTHETIC-MERCHANT",
            "webhook_id": "SYNTHETIC-WEBHOOK",
            "google_pay_enabled": True,
            "google_pay_evidence": "Synthetic sandbox permission",
        },
    )
    assert response.status_code == 200, response.text
    return transport


def order(api, mailbox, method="paypal", key="synthetic-wallet-order-0001"):
    user = register(api, mailbox, historical_pilot=False)
    fid = user["families"][0]["id"]
    response = api.post(
        f"/api/families/{fid}/orders",
        json={
            "plan_id": "start",
            "catalog_revision": 1,
            "request_key": key,
            "accept_terms": True,
            "early_start": True,
            "payment_method": method,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def prepare(api, row):
    response = api.post(f"/api/orders/{row['id']}/paypal/create", json={"request_key": "synthetic-prepare-0001"})
    assert response.status_code in (200, 202), response.text
    return response.json()


def capture(api, row, payment):
    return api.post(
        f"/api/orders/{row['id']}/paypal/capture",
        json={"payment_id": payment["payment_id"], "request_key": "synthetic-capture-0001"},
    )


def webhook(api, event):
    return api.post(
        "/api/payments/paypal/webhook",
        content=json.dumps(event),
        headers={
            "Content-Type": "application/json",
            "paypal-auth-algo": "SHA256withRSA",
            "paypal-transmission-id": "SYNTHETIC-TRANSMISSION",
            "paypal-transmission-sig": "SYNTHETIC-SIGNATURE",
            "paypal-transmission-time": "2026-10-22T00:00:00Z",
            "paypal-cert-url": "https://api.sandbox.paypal.com/v1/notifications/certs/SYNTHETIC",
        },
    )


def event(payment, kind="COMPLETED", eid="SYNTHETIC-EVENT-1"):
    return {
        "id": eid,
        "event_type": "PAYMENT.CAPTURE." + kind,
        "resource": {
            "id": "SYNTHETIC-CAPTURE-" + payment["provider_order_id"],
            "supplementary_data": {"related_ids": {"order_id": payment["provider_order_id"]}},
        },
    }


def test_default_closed_catalog_and_public_legal_preview(api, transport):
    value = api.get("/api/store/catalog").json()
    assert not value["enabled"] and not value["legal_ready"]
    assert all(not v["available"] for v in value["payment_methods"].values())
    assert value["terms_version"] is None and "vorbereitet" in value["terms"].lower()
    assert transport.calls == []


def test_configuration_secret_is_encrypted_and_never_returned(wallet, operator):
    value = operator.get("/api/admin/payments/paypal").json()
    assert value["has_client_secret"] and "client_secret" not in value and value["revision"] == 1
    assert operator.put("/api/admin/payments/paypal", json={"revision": 0}).status_code == 409
    with DB() as db:
        row = db.get(PaymentConfiguration, 1)
        assert "SYNTHETIC-SECRET" not in row.encrypted_config
        assert json.loads(decrypt(row.encrypted_config))["client_secret"] == "SYNTHETIC-SECRET"
        assert db.get(PaymentConfigurationRevision, 1).encrypted_config == row.encrypted_config
    assert wallet.calls == []


@pytest.mark.parametrize("method", [None, "card", "unknown"])
def test_unknown_or_null_method_rejected(api, mailbox, wallet, method):
    user = register(api, mailbox, historical_pilot=False)
    response = api.post(
        f"/api/families/{user['families'][0]['id']}/orders",
        json={
            "plan_id": "start",
            "catalog_revision": 1,
            "request_key": "synthetic-invalid-method",
            "accept_terms": True,
            "payment_method": method,
        },
    )
    assert response.status_code == 422 and wallet.calls == []


@pytest.mark.parametrize("method", ["paypal", "google_pay"])
def test_explicit_payment_binds_server_price_and_one_activation(api, mailbox, wallet, operator, method):
    row = order(api, mailbox, method)
    assert row["amount_cents"] == 990 and row["currency"] == "EUR" and row["payment_method"] == method
    receipt = api.get(f"/api/orders/{row['id']}/confirmation").text
    assert "Keine Banküberweisung" in receipt and "Bitte innerhalb von 14 Tagen überweisen" not in receipt
    assert wallet.calls == []
    status = api.get(f"/api/orders/{row['id']}/payment").json()
    assert status["can_start"] and status["status"] == "not_started" and wallet.calls == []
    payment = prepare(api, row)
    assert payment["status"] == "awaiting_approval" and payment["can_open"]
    created = wallet.mutations("/v2/checkout/orders")
    assert len(created) == 1 and created[0][2]["purchase_units"][0]["amount"] == {
        "currency_code": "EUR",
        "value": "9.90",
    }
    assert method in created[0][2]["payment_source"]
    assert (
        prepare(api, row)["payment_id"] == payment["payment_id"] and len(wallet.mutations("/v2/checkout/orders")) == 1
    )
    assert operator.put("/api/admin/payments/paypal", json={"revision": 1, "enabled": False}).status_code == 409
    result = capture(api, row, payment)
    assert result.status_code == 200 and result.json()["status"] == "completed", result.text
    saved = result.json()["order"]
    assert saved["status"] == "paid" and saved["ends"] - saved["starts"] == 30 * 86400
    assert capture(api, row, payment).json()["order"]["ends"] == saved["ends"]
    assert len(wallet.mutations("/capture")) == 1
    assert check(operator, row["id"]).status_code == 409


@pytest.mark.parametrize("tamper", ["amount", "currency", "merchant", "reference", "shape"])
def test_provider_mismatch_never_enables_capture(api, mailbox, wallet, tamper):
    row = order(api, mailbox)

    def change(value):
        unit = value["purchase_units"][0]
        if tamper == "amount":
            unit["amount"]["value"] = "0.01"
        if tamper == "currency":
            unit["amount"]["currency_code"] = "USD"
        if tamper == "merchant":
            unit["payee"]["merchant_id"] = "OTHER-MERCHANT"
        if tamper == "reference":
            unit["custom_id"] = "OTHER-ORDER"
        if tamper == "shape":
            unit["amount"] = []

    wallet.tamper = change
    payment = prepare(api, row)
    assert payment["status"] == "uncertain" and not payment["can_capture"]
    assert capture(api, row, payment).status_code == 202
    with DB() as db:
        assert db.get(BankOrder, row["id"]).status == "awaiting_payment"
    assert not wallet.mutations("/capture")


def test_create_timeout_survives_reload_without_another_post(api, mailbox, wallet):
    row = order(api, mailbox)
    wallet.timeout_create = True
    payment = prepare(api, row)
    assert payment["status"] == "uncertain" and payment["provider_order_id"] is None and not payment["can_reconcile"]
    assert prepare(api, row)["payment_id"] == payment["payment_id"]
    assert api.get(f"/api/orders/{row['id']}/payment").json()["status"] == "uncertain"
    assert api.post(f"/api/orders/{row['id']}/cancel").status_code == 409
    assert len(wallet.mutations("/v2/checkout/orders")) == 1


def test_capture_timeout_reconciles_only_get_and_preserves_period(api, mailbox, wallet):
    row = order(api, mailbox)
    payment = prepare(api, row)
    wallet.timeout_capture = True
    response = capture(api, row, payment)
    assert response.status_code == 202 and response.json()["can_reconcile"]
    assert not response.json()["can_open"]
    capture(api, row, payment)
    response = api.post(
        f"/api/orders/{row['id']}/paypal/reconcile",
        json={"payment_id": payment["payment_id"], "request_key": "synthetic-reconcile-001"},
    )
    assert response.status_code == 200 and response.json()["status"] == "completed", response.text
    assert len(wallet.mutations("/capture")) == 1
    assert any(c[0] == "GET" and c[1].endswith(payment["provider_order_id"]) for c in wallet.calls)


def test_pending_capture_does_not_grant_access_or_repeat_capture(api, mailbox, wallet):
    row = order(api, mailbox)
    payment = prepare(api, row)
    wallet.capture_status = "PENDING"
    result = capture(api, row, payment)
    assert result.status_code == 202 and result.json()["status"] == "capture_pending"
    assert result.json()["order"]["status"] == "awaiting_payment"
    assert capture(api, row, payment).status_code == 202 and len(wallet.mutations("/capture")) == 1


def test_revoked_session_after_capture_does_not_grant_access(api, mailbox, wallet):
    row = order(api, mailbox)
    payment = prepare(api, row)

    def revoke():
        with DB.begin() as db:
            db.execute(update(Session).values(revoked=True))

    wallet.after_capture = revoke
    assert capture(api, row, payment).status_code == 401
    with DB() as db:
        assert db.get(BankOrder, row["id"]).status == "awaiting_payment"
        assert db.get(PaymentAttempt, payment["payment_id"]).status == "uncertain"


def test_parallel_create_and_capture_each_make_one_provider_post(api, mailbox, wallet):
    row = order(api, mailbox)
    auth = api.headers["Authorization"]

    def preparing(_):
        with TestClient(app, headers={**HEADERS, "Authorization": auth}) as client:
            return prepare(client, row)

    with ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(preparing, range(3)))
    assert len({r["payment_id"] for r in results}) == 1 and len(wallet.mutations("/v2/checkout/orders")) == 1
    payment = api.get(f"/api/orders/{row['id']}/payment").json()

    def capturing(_):
        with TestClient(app, headers={**HEADERS, "Authorization": auth}) as client:
            return capture(client, row, payment)

    with ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(capturing, range(3)))
    assert all(r.status_code in (200, 202) for r in results) and len(wallet.mutations("/capture")) == 1
    with DB() as db:
        assert db.get(BankOrder, row["id"]).status == "paid"


def test_verified_webhook_settles_duplicate_once_and_ignores_stale_pending(api, mailbox, wallet):
    row = order(api, mailbox)
    payment = prepare(api, row)
    wallet.timeout_capture = True
    capture(api, row, payment)
    notice = event(payment)
    assert webhook(api, notice).status_code == 200
    with DB() as db:
        ends = db.get(BankOrder, row["id"]).ends
    assert webhook(api, notice).status_code == 200
    assert webhook(api, event(payment, "PENDING", "SYNTHETIC-EVENT-2")).status_code == 200
    with DB() as db:
        assert db.get(BankOrder, row["id"]).ends == ends
        assert db.get(PaymentAttempt, payment["payment_id"]).status == "completed"
        assert db.scalar(select(func.count()).select_from(PaymentEvent)) == 2


def test_bad_webhook_signature_never_changes_order(api, mailbox, wallet):
    row = order(api, mailbox)
    payment = prepare(api, row)
    wallet.signature = "FAILURE"
    assert webhook(api, event(payment)).status_code == 400
    assert not [c for c in wallet.calls if c[0] == "GET"]
    with DB() as db:
        assert db.get(BankOrder, row["id"]).status == "awaiting_payment"
        assert db.scalar(select(func.count()).select_from(PaymentEvent)) == 0


def refund_event(wallet, payment, amount="3.00", rid="SYNTHETIC-REFUND-1", eid="SYNTHETIC-REFUND-EVENT-1"):
    cap = "SYNTHETIC-CAPTURE-" + payment["provider_order_id"]
    value = {
        "id": rid,
        "status": "COMPLETED",
        "amount": {"currency_code": "EUR", "value": amount},
        "links": [{"rel": "up", "href": provider.BASES["sandbox"] + "/v2/payments/captures/" + cap}],
    }
    wallet.refunds[rid] = value
    return {"id": eid, "event_type": "PAYMENT.CAPTURE.REFUNDED", "resource": value}


def test_partial_and_full_refunds_do_not_add_period_or_double_count(api, mailbox, wallet):
    row = order(api, mailbox)
    payment = prepare(api, row)
    paid = capture(api, row, payment).json()["order"]
    first = refund_event(wallet, payment)
    assert webhook(api, first).status_code == 200
    assert webhook(api, {**first, "id": "SYNTHETIC-REFUND-EVENT-DUP"}).status_code == 200
    with DB() as db:
        item = db.get(PaymentAttempt, payment["payment_id"])
        assert item.status == "partially_refunded" and item.refunded_cents == 300
        assert db.get(BankOrder, row["id"]).status == "paid"
    second = refund_event(wallet, payment, "6.90", "SYNTHETIC-REFUND-2", "SYNTHETIC-REFUND-EVENT-2")
    assert webhook(api, second).status_code == 200
    with DB() as db:
        item = db.get(PaymentAttempt, payment["payment_id"])
        saved = db.get(BankOrder, row["id"])
        assert item.refunded_cents == 990 and item.status == "refunded" and saved.status == "refunded"
        assert saved.ends == paid["ends"] and saved.revoked_at is not None
        assert commerce.current_order(db, db.get(Family, saved.family_id)) is None
        assert db.scalar(select(func.count()).select_from(PaymentRefund)) == 2


def test_refund_before_capture_response_prevents_later_access(api, mailbox, wallet):
    row = order(api, mailbox)
    payment = prepare(api, row)
    wallet.timeout_capture = True
    capture(api, row, payment)
    assert webhook(api, refund_event(wallet, payment, "9.90")).status_code == 200
    assert webhook(api, event(payment)).status_code == 200
    with DB() as db:
        assert db.get(BankOrder, row["id"]).status == "refunded"
        assert db.get(PaymentAttempt, payment["payment_id"]).status == "refunded"


def test_refund_uses_original_encrypted_binding_after_configuration_update(api, mailbox, wallet, operator):
    row = order(api, mailbox)
    payment = prepare(api, row)
    capture(api, row, payment)
    update_reply = operator.put(
        "/api/admin/payments/paypal", json={"revision": 1, "client_secret": "ROTATED-SYNTHETIC-SECRET"}
    )
    assert update_reply.status_code == 200, update_reply.text
    assert webhook(api, refund_event(wallet, payment, "9.90")).status_code == 200
    with DB() as db:
        assert db.get(PaymentAttempt, payment["payment_id"]).status == "refunded"


def test_owner_separation_and_local_get_are_read_only(api, mailbox, wallet):
    row = order(api, mailbox)
    payment = prepare(api, row)
    before = len(wallet.calls)
    for _ in range(3):
        assert api.get(f"/api/orders/{row['id']}/payment").json()["payment_id"] == payment["payment_id"]
    assert len(wallet.calls) == before
    with TestClient(app, headers=HEADERS) as stranger:
        register(stranger, mailbox, "stranger@example.org", historical_pilot=False)
        assert stranger.get(f"/api/orders/{row['id']}/payment").status_code == 404
        assert (
            stranger.post(
                f"/api/orders/{row['id']}/paypal/create", json={"request_key": "synthetic-stranger-001"}
            ).status_code
            == 404
        )
    assert len(wallet.calls) == before


def test_trial_and_paid_readiness_require_phone_without_restricting_old_access(api, mailbox, wallet):
    from schulpilot.config import settings

    object.__setattr__(settings, "operator_phone", "")
    catalog = api.get("/api/store/catalog").json()
    assert not catalog["enabled"] and not catalog["trial"]["enabled"] and not catalog["legal_ready"]
    with DB() as db:
        assert commerce.trial_prerequisites(db) == ["Vollständige Betreiberangaben"]


def test_wallet_order_request_cannot_change_method_price_or_merchant(api, mailbox, wallet):
    row = order(api, mailbox)
    with DB() as db:
        fid = db.get(BankOrder, row["id"]).family_id
    body = {
        "plan_id": "start",
        "catalog_revision": 1,
        "request_key": "synthetic-wallet-order-0001",
        "accept_terms": True,
        "early_start": True,
        "payment_method": "google_pay",
    }
    assert api.post(f"/api/families/{fid}/orders", json=body).status_code == 409
    for key, value in (("amount_cents", 1), ("currency", "USD"), ("merchant_id", "EVIL")):
        assert api.post(f"/api/families/{fid}/orders", json={**body, key: value}).status_code == 422
    assert wallet.calls == []


def test_google_pay_flag_has_separate_evidence_and_stays_off_without_it(api, operator, shop, transport):
    missing = operator.put(
        "/api/admin/payments/paypal",
        json={
            "revision": 0,
            "enabled": True,
            "client_id": "SYNTHETIC",
            "client_secret": "SYNTHETIC",
            "merchant_id": "SYNTHETIC",
            "webhook_id": "SYNTHETIC",
            "google_pay_enabled": True,
        },
    )
    assert missing.status_code == 422
    assert (
        operator.put(
            "/api/admin/payments/paypal",
            json={
                "revision": 0,
                "enabled": True,
                "client_id": "SYNTHETIC",
                "client_secret": "SYNTHETIC",
                "merchant_id": "SYNTHETIC",
                "webhook_id": "SYNTHETIC",
                "google_pay_enabled": False,
            },
        ).status_code
        == 200
    )
    methods = api.get("/api/store/catalog").json()["payment_methods"]
    assert methods["paypal"]["available"] and not methods["google_pay"]["available"]
    assert transport.calls == []


def test_live_configuration_and_production_do_not_fall_back_to_sandbox(wallet, operator):
    from schulpilot.config import settings

    assert (
        operator.put(
            "/api/admin/payments/paypal", json={"revision": 1, "environment": "live", "enabled": True}
        ).status_code
        == 422
    )
    object.__setattr__(settings, "environment", "production")
    with DB() as db:
        assert not payments.method_available(db, "paypal")
    assert wallet.calls == []


def test_cancel_prepared_order_blocks_popup_and_capture(api, mailbox, wallet):
    row = order(api, mailbox)
    payment = prepare(api, row)
    assert api.post(f"/api/orders/{row['id']}/cancel").status_code == 200
    value = api.get(f"/api/orders/{row['id']}/payment").json()
    assert value["status"] == "cancelled" and not value["can_open"] and not value["can_capture"]
    assert capture(api, row, payment).json()["status"] == "cancelled"
    assert not wallet.mutations("/capture")


def test_owner_withdrawal_blocks_capture_without_a_provider_call(api, mailbox, wallet):
    row = order(api, mailbox)
    payment = prepare(api, row)
    response = api.post(
        f"/api/orders/{row['id']}/withdrawals",
        json={
            "request_key": "synthetic-withdrawal-0001",
            "buyer_name": "Künstlicher Elternteil",
            "contact_email": "parent@example.org",
            "confirm": True,
        },
    )
    assert response.status_code == 201, response.text
    assert response.json()["payment_hold"]
    assert capture(api, row, payment).status_code == 409
    assert not wallet.mutations("/capture")


def test_withdrawal_arriving_during_capture_keeps_financial_result_without_access(api, mailbox, wallet):
    from schulpilot.order_withdrawal_models import OrderWithdrawal
    from schulpilot.security import encrypt

    row = order(api, mailbox)
    payment = prepare(api, row)

    def hold():
        with DB.begin() as db:
            db.add(
                OrderWithdrawal(
                    order_id=row["id"],
                    effective_received=1,
                    verified=True,
                    hold_payment=True,
                    encrypted_declaration=encrypt("{}"),
                    request_digest="0" * 64,
                    idempotency="synthetic-racing-hold",
                )
            )

    wallet.after_capture = hold
    response = capture(api, row, payment)
    assert response.status_code == 202 and response.json()["status"] == "uncertain"
    assert response.json()["order"]["status"] == "awaiting_payment"
    with DB() as db:
        assert db.get(PaymentAttempt, payment["payment_id"]).capture_id


def test_forged_certificate_url_is_rejected_before_http(api, mailbox, wallet):
    row = order(api, mailbox)
    payment = prepare(api, row)
    before = len(wallet.calls)
    response = api.post(
        "/api/payments/paypal/webhook",
        content=json.dumps(event(payment)),
        headers={"paypal-cert-url": "https://attacker.invalid/v1/notifications/certs/fake"},
    )
    assert response.status_code == 400 and len(wallet.calls) == before


def test_verified_reversal_revokes_access_without_claiming_a_refund(api, mailbox, wallet):
    row = order(api, mailbox)
    payment = prepare(api, row)
    paid = capture(api, row, payment).json()["order"]
    wallet.orders[payment["provider_order_id"]]["purchase_units"][0]["payments"]["captures"][0]["status"] = "REFUNDED"
    notice = event(payment, "REVERSED")
    assert webhook(api, notice).status_code == 200
    assert webhook(api, notice).status_code == 200
    with DB() as db:
        item = db.get(PaymentAttempt, payment["payment_id"])
        saved = db.get(BankOrder, row["id"])
        assert item.status == "reversed" and item.refunded_cents == 0
        assert saved.status == "refunded" and saved.ends == paid["ends"]


def test_completed_duplicate_with_different_payload_is_rejected(api, mailbox, wallet):
    row = order(api, mailbox)
    payment = prepare(api, row)
    capture(api, row, payment)
    notice = event(payment)
    assert webhook(api, notice).status_code == 200
    assert webhook(api, {**notice, "extra": "different"}).status_code == 409


def test_account_erasure_keeps_financial_binding_but_removes_family_link(api, mailbox, wallet):
    row = order(api, mailbox)
    payment = prepare(api, row)
    capture(api, row, payment)
    response = api.request("DELETE", "/api/account", json={"password": "secure-parent-pass-123"})
    assert response.status_code == 200, response.text
    with DB() as db:
        saved = db.get(BankOrder, row["id"])
        assert saved.family_id is None and saved.buyer_id is None
        assert db.get(PaymentAttempt, payment["payment_id"]).order_id == saved.id
    assert webhook(api, refund_event(wallet, payment, "9.90")).status_code == 200


def test_adapter_response_bound_rejects_oversized_stream(monkeypatch):
    class LargeStream(httpx.SyncByteStream):
        def __iter__(self):
            yield b" " * 65536
            yield b"x"

    def handle(request):
        return httpx.Response(200, stream=LargeStream())

    monkeypatch.setattr(provider, "client", lambda: httpx.Client(transport=httpx.MockTransport(handle)))
    with pytest.raises(provider.PayPalError) as exc:
        provider.read_order(provider.Connection("sandbox", "SYNTHETIC", "SYNTHETIC"), "SYNTHETIC-ORDER")
    assert exc.value.code == "invalid_response"


@pytest.mark.parametrize("value", [None, 9.90, "9.9", "1e3", "-1.00", "1.001", "NaN", "1,00"])
def test_adapter_money_is_strict_decimal_not_client_float(value):
    with pytest.raises(provider.PayPalError):
        provider.cents(value)


def test_operator_shop_stop_during_capture_preserves_result_for_review(api, mailbox, wallet):
    from schulpilot.db import StoreConfiguration
    from schulpilot.security import encrypt

    row = order(api, mailbox)
    payment = prepare(api, row)

    def stop():
        with DB.begin() as db:
            config, _ = commerce.store(db)
            config.enabled = False
            db.get(StoreConfiguration, 1).encrypted_config = encrypt(config.model_dump_json())

    wallet.after_capture = stop
    response = capture(api, row, payment)
    assert response.status_code == 202 and response.json()["status"] == "uncertain"
    assert response.json()["order"]["status"] == "awaiting_payment"
    with DB() as db:
        assert db.get(PaymentAttempt, payment["payment_id"]).capture_id


def test_maintenance_preserves_uncertain_payment_after_cancelled_order_retention(api, mailbox, wallet):
    from schulpilot.db import now

    row = order(api, mailbox)
    payment = prepare(api, row)
    with DB.begin() as db:
        saved = db.get(BankOrder, row["id"])
        saved.status, saved.created = "cancelled", int(now()) - 10 * 365 * 86400
        item = db.get(PaymentAttempt, payment["payment_id"])
        item.status, item.created = "uncertain", saved.created
    with DB.begin() as db:
        commerce.maintenance(db)
    with DB() as db:
        assert db.get(BankOrder, row["id"]) is not None
        assert db.get(PaymentConfigurationRevision, 1) is not None
    with DB.begin() as db:
        db.get(PaymentAttempt, payment["payment_id"]).status = "denied"
    with DB.begin() as db:
        commerce.maintenance(db)
    with DB() as db:
        assert db.get(BankOrder, row["id"]) is None
        assert db.get(PaymentAttempt, payment["payment_id"]) is None
        assert db.get(PaymentConfigurationRevision, 1) is not None  # current binding


def test_delayed_canonical_capture_does_not_consume_final_webhook(api, mailbox, wallet):
    row = order(api, mailbox)
    payment = prepare(api, row)
    notice = event(payment)
    assert webhook(api, notice).status_code == 503
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(PaymentEvent)) == 0
    capture(api, row, payment)
    assert webhook(api, notice).status_code == 200
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(PaymentEvent)) == 1


def test_capture_422_is_not_misrepresented_as_proven_no_payment(api, mailbox, wallet):
    row = order(api, mailbox)
    payment = prepare(api, row)
    wallet.capture_http_error = True
    response = capture(api, row, payment)
    assert response.status_code == 202 and response.json()["status"] == "uncertain"
    assert response.json()["can_reconcile"] and not response.json()["can_capture"]
    assert api.post(f"/api/orders/{row['id']}/cancel").status_code == 409
    assert len(wallet.mutations("/capture")) == 1


def test_secret_is_not_trimmed_and_cannot_be_silently_enabled(operator, shop, transport):
    response = operator.put(
        "/api/admin/payments/paypal", json={"revision": 0, "client_secret": " synthetic-secret ", "enabled": False}
    )
    assert response.status_code == 200
    with DB() as db:
        value = json.loads(decrypt(db.get(PaymentConfiguration, 1).encrypted_config))
        assert value["client_secret"] == " synthetic-secret "
    assert transport.calls == []


def test_wallet_payment_cannot_be_faked_by_manual_bank_refund(api, mailbox, wallet, operator):
    from datetime import datetime, timezone

    row = order(api, mailbox)
    response = operator.post(
        f"/api/admin/orders/{row['id']}/refund",
        json={
            "received_cents": 990,
            "booking_date": datetime.now(timezone.utc).date().isoformat(),
            "booking_reference": "SYNTHETIC-BANK-REFUND",
            "bank_entry_checked": True,
        },
    )
    assert response.status_code == 409 and wallet.calls == []


def test_family_export_keeps_contract_declarations_owner_only(api, mailbox, wallet):
    import io
    import zipfile

    from schulpilot.db import Membership

    row = order(api, mailbox)
    response = api.post(
        f"/api/orders/{row['id']}/withdrawals",
        json={
            "request_key": "synthetic-private-declaration",
            "buyer_name": "Private QA-Unterzeichner",
            "contact_email": "parent@example.org",
            "confirm": True,
        },
    )
    assert response.status_code == 201, response.text
    with DB() as db:
        fid = db.get(BankOrder, row["id"]).family_id
        assert "withdrawals" not in commerce.orders_export(db, fid)[0]
    exported = api.get(f"/api/families/{fid}/export")
    assert exported.status_code == 200
    with zipfile.ZipFile(io.BytesIO(exported.content)) as archive:
        value = json.loads(archive.read("family.json"))
    assert value["orders"][0]["withdrawals"][0]["declaration"]["buyer_name"] == "Private QA-Unterzeichner"
    with TestClient(app, headers=HEADERS) as viewer:
        user = register(viewer, mailbox, "viewer@example.org", historical_pilot=False)
        with DB.begin() as db:
            db.add(Membership(family_id=fid, user_id=user["id"], permission="view"))
        exported = viewer.get(f"/api/families/{fid}/export")
        assert exported.status_code == 200
        with zipfile.ZipFile(io.BytesIO(exported.content)) as archive:
            raw = archive.read("family.json")
            assert json.loads(raw)["orders"] == [] and b"Private QA-Unterzeichner" not in raw
    assert wallet.calls == []


def test_sparse_realistic_capture_response_is_verified_by_canonical_order_get(api, mailbox, wallet):
    row = order(api, mailbox)
    payment = prepare(api, row)
    wallet.minimal_capture = True
    response = capture(api, row, payment)
    assert response.status_code == 200 and response.json()["status"] == "completed", response.text
    assert len(wallet.mutations("/capture")) == 1
    assert len([c for c in wallet.calls if c[0] == "GET"]) == 1


def test_webhook_slots_are_bounded_and_released_without_provider_call(api, mailbox, wallet):
    row = order(api, mailbox)
    payment = prepare(api, row)
    for _ in range(4):
        assert payments.WEBHOOK_SLOTS.acquire(blocking=False)
    before = len(wallet.calls)
    try:
        assert webhook(api, event(payment)).status_code == 503
        assert len(wallet.calls) == before
    finally:
        for _ in range(4):
            payments.WEBHOOK_SLOTS.release()
    assert payments.WEBHOOK_SLOTS.acquire(blocking=False)
    payments.WEBHOOK_SLOTS.release()


def test_webhook_verification_rate_limit_precedes_provider_http(api, mailbox, wallet):
    import time

    from schulpilot.db import RateBucket

    row = order(api, mailbox)
    payment = prepare(api, row)
    tick = int(time.time()) // 60
    with DB.begin() as db:
        db.add(RateBucket(id=f"paypal-webhook-verification:{tick}", count=120, expires=(tick + 1) * 60))
    before = len(wallet.calls)
    assert webhook(api, event(payment)).status_code == 429 and len(wallet.calls) == before


@pytest.mark.parametrize("operation", ["create", "capture"])
def test_owner_revocation_while_waiting_for_family_lock_blocks_provider(api, mailbox, wallet, monkeypatch, operation):
    import threading

    from schulpilot.db import Membership, engine

    if engine.dialect.name != "postgresql":
        pytest.skip("Deterministic row-lock race requires isolated PostgreSQL")
    row = order(api, mailbox)
    payment = prepare(api, row) if operation == "capture" else None
    with DB() as db:
        fid = db.get(BankOrder, row["id"]).family_id
    reached = threading.Event()
    original = payments.family_access

    def checked(*args, **kwargs):
        result = original(*args, **kwargs)
        reached.set()
        return result

    monkeypatch.setattr(payments, "family_access", checked)
    auth = api.headers["Authorization"]

    def waiting():
        with TestClient(app, headers={**HEADERS, "Authorization": auth}) as client:
            return client.post(
                f"/api/orders/{row['id']}/paypal/{operation}",
                json={
                    "request_key": "synthetic-revocation-race",
                    **({"payment_id": payment["payment_id"]} if payment else {}),
                },
            )

    before = len(wallet.calls)
    with DB() as holder, ThreadPoolExecutor(max_workers=1) as pool:
        holder.execute(update(Family).where(Family.id == fid).values(child_limit=Family.child_limit))
        result = pool.submit(waiting)
        assert reached.wait(5), "request did not reach its pre-lock authority check"
        holder.execute(update(Membership).where(Membership.family_id == fid).values(permission="view"))
        holder.commit()
        response = result.result(timeout=15)
    assert response.status_code == 403, response.text
    assert len(wallet.calls) == before
    with DB() as db:
        assert db.get(BankOrder, row["id"]).status == "awaiting_payment"
