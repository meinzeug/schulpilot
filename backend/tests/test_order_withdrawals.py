"""Synthetic receipts, mocked SMTP and isolated DB only; no payment/provider call."""

import json
import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

import pytest
from conftest import HEADERS, create_child, register
from fastapi import HTTPException
from fastapi.testclient import TestClient
from schulpilot import commerce, mail
from schulpilot import order_withdrawals as withdrawals
from schulpilot.db import DB, Audit, BankOrder, Family, Membership, Session, User, engine, now, uid
from schulpilot.main import app
from schulpilot.order_withdrawal_models import OrderWithdrawal, PublicWithdrawal
from schulpilot.payment_models import PaymentAttempt
from schulpilot.security import decrypt, digest, encrypt, password_hash
from sqlalchemy import func, select, update


@pytest.fixture
def operator(api):
    with DB.begin() as db:
        db.add(User(username="synthetic-withdraw-admin", display_name="Betrieb", role="admin", verified=True,
                    password_hash=password_hash("synthetic-admin-pass-123")))
    with TestClient(app, headers=HEADERS) as client:
        reply = client.post("/api/auth/login", json={"username": "synthetic-withdraw-admin",
                                                     "password": "synthetic-admin-pass-123"})
        assert reply.status_code == 200
        client.headers["Authorization"] = "Bearer " + reply.json()["token"]
        yield client


@pytest.fixture
def sent(monkeypatch):
    messages = []
    monkeypatch.setattr(mail, "send_message", lambda *args: messages.append(args))
    return messages


def seed(user, *, status="awaiting_payment", created=None):
    identifier = uid()
    with DB.begin() as db:
        row = BankOrder(id=identifier, family_id=user["families"][0]["id"], buyer_id=user["id"],
            idempotency="synthetic:" + identifier, payment_reference="SP-" + identifier[:16].upper(),
            status=status, pending_slot=user["families"][0]["id"] if status == "awaiting_payment" else None,
            amount_cents=990, offer={"id": "start", "name": "Synthetic Start", "children": 1, "calls": 300,
                "budget_micros": 450000}, seller={"tax_notice": "Synthetic"}, bank={}, terms="Synthetic saved terms",
            created=int(now()) if created is None else created, starts=int(now()) - 100,
            ends=int(now()) + 30 * 86400, checked_at=int(now()) if status == "paid" else None)
        db.add(row)
        db.flush()
        reference = row.payment_reference
    return identifier, reference


def body(key="synthetic-withdraw-key-001", **values):
    return {"request_key": key, "buyer_name": "Künstliche Testperson", "contact_email": "parent@example.org",
            "confirm": True, **values}


def public_body(reference="UNKNOWN-SYNTHETIC-REF", **values):
    return body(order_reference=reference, **values)


def submit(api, identifier, **values):
    return api.post(f"/api/orders/{identifier}/withdrawals", json=body(**values))


def test_owner_receipt_is_durable_encrypted_idempotent_and_cancels_only_open_order(api, mailbox, sent):
    user = register(api, mailbox)
    identifier, reference = seed(user)
    response = submit(api, identifier)
    assert response.status_code == 201, response.text
    data = response.json()
    assert data["status"] == "received_verified" and data["payment_hold"] is True
    assert data["refund_executed"] is False and data["mail_status"] == "accepted"
    assert all(value in data["receipt_text"] for value in [reference, "Künstliche Testperson", "parent@example.org",
        data["received_at_iso"], withdrawals.DECLARATION])
    assert "Zustellung ist nicht bestätigt" in data["mail_notice"]
    repeated = submit(api, identifier)
    assert repeated.status_code == 200 and repeated.json()["id"] == data["id"]
    assert len(sent) == 1
    assert api.get(f"/api/orders/{identifier}/withdrawal").json()["withdrawal"] == repeated.json()
    with DB() as db:
        row = db.scalar(select(OrderWithdrawal))
        assert "parent@example.org" not in row.encrypted_declaration
        assert "Künstliche" not in row.encrypted_declaration
        assert json.loads(decrypt(row.encrypted_declaration))["declaration"] == withdrawals.DECLARATION
        assert db.get(BankOrder, identifier).status == "cancelled"
        assert db.get(BankOrder, identifier).pending_slot is None
        assert withdrawals.payment_hold(db, identifier)
        assert db.scalar(select(func.count()).select_from(OrderWithdrawal)) == 1


def test_paid_withdrawal_holds_access_without_claiming_refund_or_rewriting_paid_record(api, mailbox, sent):
    user = register(api, mailbox)
    identifier, _ = seed(user, status="paid")
    with DB.begin() as db:
        family = db.get(Family, user["families"][0]["id"])
        family.commerce_required = True
    response = submit(api, identifier)
    assert response.status_code == 201 and response.json()["refund_executed"] is False
    with DB() as db:
        order = db.get(BankOrder, identifier)
        assert order.status == "paid" and order.refund_digest is None and order.revoked_at is None
        assert commerce.current_order(db, db.get(Family, order.family_id)) is None


def test_outside_standard_window_is_retained_for_review_not_rejected(api, mailbox, sent):
    user = register(api, mailbox)
    identifier, _ = seed(user, created=int(now()) - 25 * 86400)
    response = submit(api, identifier)
    assert response.status_code == 201
    assert response.json()["status"] == "review_required" and response.json()["payment_hold"] is False
    with DB() as db:
        assert db.get(BankOrder, identifier).status == "awaiting_payment"
        assert not withdrawals.payment_hold(db, identifier)


def test_calendar_day_and_weekend_window_does_not_cut_off_at_order_hour():
    class Order:
        # Thursday14-day deadline falls on Thursday; late on that day is valid.
        created = int(datetime(2026, 10, 1, 8, tzinfo=withdrawals.BERLIN).timestamp())
    late_day = int(datetime(2026, 10, 15, 23, 50, tzinfo=withdrawals.BERLIN).timestamp())
    assert withdrawals.within_standard_window(Order, late_day)
    assert not withdrawals.within_standard_window(Order, late_day + 86400)
    Order.created = int(datetime(2026, 10, 3, 8, tzinfo=withdrawals.BERLIN).timestamp())
    monday = int(datetime(2026, 10, 19, 23, 50, tzinfo=withdrawals.BERLIN).timestamp())
    assert withdrawals.within_standard_window(Order, monday)


def test_wrong_email_foreign_family_demo_child_admin_and_view_member_cannot_submit(api, mailbox, sent, operator):
    user = register(api, mailbox)
    identifier, _ = seed(user)
    assert submit(api, identifier, contact_email="wrong@example.org").status_code == 422
    assert operator.post(f"/api/orders/{identifier}/withdrawals", json=body()).status_code == 403
    create_child(api, user)
    with TestClient(app, headers=HEADERS) as other:
        login = other.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"})
        other.headers["Authorization"] = "Bearer " + login.json()["token"]
        assert other.post(f"/api/orders/{identifier}/withdrawals", json=body()).status_code == 403
        stranger = register(other, mailbox, "stranger@example.org")
        assert other.post(f"/api/orders/{identifier}/withdrawals", json=body(contact_email="stranger@example.org")).status_code == 404
        assert other.get(f"/api/orders/{identifier}/withdrawal").status_code == 404
        with DB.begin() as db:
            db.add(Membership(user_id=stranger["id"], family_id=user["families"][0]["id"], permission="view"))
        assert other.post(f"/api/orders/{identifier}/withdrawals", json=body(contact_email="stranger@example.org")).status_code == 403
    with DB.begin() as db:
        db.get(Family, user["families"][0]["id"]).synthetic = True
    assert submit(api, identifier).status_code == 403
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(OrderWithdrawal)) == 0
        assert db.get(BankOrder, identifier).status == "awaiting_payment"
    assert not sent


def test_conflicting_request_key_or_changed_declaration_never_overwrites_receipt(api, mailbox, sent):
    user = register(api, mailbox)
    identifier, _ = seed(user)
    first = submit(api, identifier).json()
    assert submit(api, identifier, buyer_name="Andere Testperson").status_code == 409
    second, _ = seed(user)
    assert submit(api, second).status_code == 409
    assert api.get(f"/api/orders/{identifier}/withdrawal").json()["withdrawal"]["receipt_text"] == first["receipt_text"]
    assert len(sent) == 1


def test_mail_failure_keeps_saved_receipt_and_never_retries_on_get_or_same_post(api, mailbox, monkeypatch):
    user = register(api, mailbox)
    identifier, _ = seed(user)
    calls = []
    def failed(*args):
        calls.append(True)
        raise HTTPException(503, "synthetic mail failure")
    monkeypatch.setattr(mail, "send_message", failed)
    response = submit(api, identifier)
    assert response.status_code == 201 and response.json()["mail_status"] == "failed"
    assert "nicht bestätigt" in response.json()["mail_notice"]
    assert submit(api, identifier).status_code == 200
    assert api.get(f"/api/orders/{identifier}/withdrawal").status_code == 200
    assert calls == [True]


def test_public_receipt_never_looks_up_private_order_or_changes_family_or_payment(api, mailbox, sent, monkeypatch):
    user = register(api, mailbox)
    identifier, reference = seed(user)
    def forbidden(*args, **kwargs):
        raise AssertionError("Public receipt must never call owned_order")
    monkeypatch.setattr(withdrawals, "owned_order", forbidden)
    response = api.post("/api/withdrawals/public", json=public_body(reference))
    assert response.status_code == 201
    data = response.json()
    assert data["status"] == "received_unverified" and data["payment_hold"] is False
    assert not {"order_id", "family_id", "amount_cents", "starts", "ends", "order"}.intersection(data)
    assert identifier not in response.text and user["families"][0]["id"] not in response.text
    assert data["refund_executed"] is False
    assert api.post("/api/withdrawals/public", json=public_body(reference)).status_code == 200
    assert api.post("/api/withdrawals/public", json=public_body(reference, buyer_name="Other Name")).status_code == 409
    assert len(sent) == 1
    with DB() as db:
        assert db.get(BankOrder, identifier).status == "awaiting_payment"
        assert db.scalar(select(func.count()).select_from(OrderWithdrawal)) == 0
        public = db.scalar(select(PublicWithdrawal))
        assert public.reference_digest == digest(reference) and not public.identity_verified
        assert public.linked_order_id is None and "parent@example.org" not in public.encrypted_declaration
        assert not withdrawals.payment_hold(db, identifier)


def test_public_input_confirmation_and_rate_limits_are_bounded_and_do_not_echo_pii(api, sent):
    for invalid in [public_body(confirm=False), public_body(buyer_name="Test\nInjected"), public_body(reference="\n")]:
        response = api.post("/api/withdrawals/public", json=invalid)
        assert response.status_code == 422
        assert invalid["buyer_name"] not in response.text
    for index in range(3):
        response = api.post("/api/withdrawals/public", json=public_body(key=f"synthetic-public-rate-{index}"))
        assert response.status_code == 201
    assert api.post("/api/withdrawals/public", json=public_body(key="synthetic-public-rate-4")).status_code == 429
    assert len(sent) == 3


def test_admin_must_explicitly_verify_exact_reference_then_link_once_without_refund(api, mailbox, sent, operator):
    user = register(api, mailbox)
    identifier, reference = seed(user, status="paid")
    received = api.post("/api/withdrawals/public", json=public_body(reference)).json()
    path = f"/api/admin/withdrawals/{received['id']}/link"
    assert api.post(path, json={"order_reference": reference, "identity_verified": True}).status_code == 403
    assert operator.post(path, json={"order_reference": reference, "identity_verified": False}).status_code == 422
    assert operator.post(path, json={"order_reference": "WRONG", "identity_verified": True}).status_code == 409
    response = operator.post(path, json={"order_reference": reference, "identity_verified": True})
    assert response.status_code == 200 and response.json()["payment_hold"] is True
    assert operator.post(path, json={"order_reference": reference, "identity_verified": True}).json() == response.json()
    assert len(sent) == 1
    with DB() as db:
        assert db.get(BankOrder, identifier).status == "paid"
        assert db.scalar(select(func.count()).select_from(OrderWithdrawal)) == 1
        assert db.scalar(select(func.count()).select_from(Audit).where(Audit.action == "withdrawal.public_identity_verified")) == 1
        assert commerce.current_order(db, db.get(Family, user["families"][0]["id"])) is None


def test_admin_late_public_match_keeps_original_receipt_and_requires_review(api, mailbox, sent, operator):
    user = register(api, mailbox)
    identifier, reference = seed(user, created=int(now()) - 30 * 86400)
    received = api.post("/api/withdrawals/public", json=public_body(reference)).json()
    response = operator.post(f"/api/admin/withdrawals/{received['id']}/link",
                            json={"order_reference": reference, "identity_verified": True})
    assert response.status_code == 200 and response.json()["status"] == "review_required"
    assert not response.json()["payment_hold"] and not response.json()["refund_executed"]
    with DB() as db:
        row = db.scalar(select(OrderWithdrawal))
        assert withdrawals.receipt_text(withdrawals.decoded(row)) == received["receipt_text"]
        assert db.get(BankOrder, identifier).status == "awaiting_payment"


def test_admin_paging_keeps_same_second_receipts_and_does_not_include_learning_data(api, sent, operator):
    for index in range(6):
        identifier = f"{index + 1:032x}"
        value = withdrawals.snapshot(identifier, int(now()), "Synthetic Adult", "test@example.org", "REF" + str(index))
        with DB.begin() as db:
            db.add(PublicWithdrawal(id=identifier, received=value["received_at"], reference_digest=digest("REF" + str(index)),
                email_digest=digest("test@example.org"), encrypted_declaration=encrypt(json.dumps(value)),
                request_digest="f" * 64, idempotency="synthetic-list-" + str(index)))
    first = operator.get("/api/admin/withdrawals?limit=3").json()
    assert len(first["items"]) == 3 and first["next_before"]
    second = operator.get("/api/admin/withdrawals", params={"limit": 3, "before": first["next_before"]}).json()
    assert len(second["items"]) == 3 and second["next_before"] is None
    assert len({row["id"] for row in first["items"] + second["items"]}) == 6
    assert all("declaration" in item and "child_id" not in item for item in first["items"])
    assert api.get("/api/admin/withdrawals").status_code in (401, 403)


@pytest.mark.skipif(engine.dialect.name != "postgresql", reason="Actual PostgreSQL lock contention")
def test_family_lock_serializes_payment_after_verified_withdrawal(api, mailbox, sent, operator, monkeypatch):
    user = register(api, mailbox)
    identifier, _ = seed(user)
    entered, release, payment_started = threading.Event(), threading.Event(), threading.Event()
    original = withdrawals.within_standard_window
    def blocked(order, stamp):
        entered.set()
        assert release.wait(8)
        return original(order, stamp)
    monkeypatch.setattr(withdrawals, "within_standard_window", blocked)
    def pay():
        payment_started.set()
        return operator.post(f"/api/admin/orders/{identifier}/approve", json={"received_cents": 990,
            "booking_date": datetime.now(timezone.utc).date().isoformat(), "booking_reference": "SYNTHETIC-WITHDRAW-PAY",
            "bank_entry_checked": True})
    with ThreadPoolExecutor(max_workers=2) as pool:
        pending = pool.submit(submit, api, identifier)
        assert entered.wait(8)
        paying = pool.submit(pay)
        assert payment_started.wait(8)
        try:
            assert not paying.done()
        finally:
            release.set()
        assert pending.result(12).status_code == 201
        assert paying.result(12).status_code == 409
    with DB() as db:
        assert db.get(BankOrder, identifier).status == "cancelled"
        assert withdrawals.payment_hold(db, identifier)


@pytest.mark.skipif(engine.dialect.name != "postgresql", reason="Actual PostgreSQL concurrent idempotency")
def test_parallel_public_request_is_one_receipt_and_one_mail(api, sent):
    def send():
        with TestClient(app, headers=HEADERS) as client:
            return client.post("/api/withdrawals/public", json=public_body())
    with ThreadPoolExecutor(max_workers=2) as pool:
        replies = list(pool.map(lambda _: send(), range(2)))
    assert sorted(reply.status_code for reply in replies) == [200, 201]
    assert len({reply.json()["id"] for reply in replies}) == 1 and len(sent) == 1


def test_export_erasure_and_retention_separate_unpaid_from_paid_contract_records(api, mailbox, sent):
    user = register(api, mailbox)
    unpaid, _ = seed(user)
    assert submit(api, unpaid).status_code == 201
    paid, _ = seed(user, status="paid")
    assert submit(api, paid, key="synthetic-withdraw-paid-001").status_code == 201
    family_id = user["families"][0]["id"]
    with DB.begin() as db:
        exported = withdrawals.withdrawals_export(db, family_id)
        assert {row["order_id"] for row in exported} == {unpaid, paid}
        assert all(row["declaration"]["buyer_name"] == "Künstliche Testperson" for row in exported)
        withdrawals.erase_family_withdrawals(db, family_id)
        assert db.scalar(select(OrderWithdrawal).where(OrderWithdrawal.order_id == unpaid)) is None
        retained = db.scalar(select(OrderWithdrawal).where(OrderWithdrawal.order_id == paid))
        assert retained is not None and retained.owner_user_id is None
        old = int(now()) - 366 * 86400
        for identifier, linked in [(uid(), None), (uid(), paid)]:
            value = withdrawals.snapshot(identifier, old, "Synthetic Adult", "test@example.org", "OLD-REF")
            db.add(PublicWithdrawal(id=identifier, received=old, reference_digest="a" * 64, email_digest="b" * 64,
                encrypted_declaration=encrypt(json.dumps(value)), request_digest="c" * 64,
                idempotency=identifier, linked_order_id=linked))
        db.flush()
        withdrawals.maintenance(db)
        remaining = list(db.scalars(select(PublicWithdrawal)))
        assert len(remaining) == 1 and remaining[0].linked_order_id == paid
        assert retained.encrypted_declaration


def test_uncertain_capture_keeps_financial_declaration_and_does_not_claim_cancellation(api, mailbox, sent):
    user = register(api, mailbox)
    identifier, reference = seed(user)
    with DB.begin() as db:
        db.add(PaymentAttempt(order_id=identifier, environment="sandbox", merchant_id="SYNTHETIC-MERCHANT",
            config_revision=1, method="paypal", amount_cents=990, status="uncertain", capture_started=int(now()),
            create_request_id=uid(), capture_request_id=uid()))
    reply = submit(api, identifier)
    assert reply.status_code == 201 and reply.json()["payment_hold"] is True
    family_id = user["families"][0]["id"]
    public = api.post("/api/withdrawals/public", json=public_body(reference)).json()
    with DB.begin() as db:
        db.get(PublicWithdrawal, public["id"]).linked_order_id = identifier
        db.get(PublicWithdrawal, public["id"]).received = int(now()) - 366 * 86400
        assert db.get(BankOrder, identifier).status == "awaiting_payment"
        assert db.scalar(select(PaymentAttempt)).status == "uncertain"
        commerce.erase_family_orders(db, family_id)
        assert db.get(BankOrder, identifier).family_id is None
        retained = db.scalar(select(OrderWithdrawal).where(OrderWithdrawal.order_id == identifier))
        assert retained is not None and retained.owner_user_id is None
        withdrawals.maintenance(db)
        assert db.get(PublicWithdrawal, public["id"]) is not None
        assert withdrawals.payment_hold(db, identifier)


def test_earlier_public_receipt_after_verified_link_can_hold_without_rewriting_owner_receipt(api, mailbox, sent, operator):
    user = register(api, mailbox)
    created = int(now()) - 25 * 86400
    identifier, reference = seed(user, created=created)
    own = submit(api, identifier).json()
    assert own["status"] == "review_required" and not own["payment_hold"]
    public_id, received = uid(), created + 86400
    value = withdrawals.snapshot(public_id, received, "Synthetic Earlier Adult", "another@example.org", reference)
    with DB.begin() as db:
        db.add(PublicWithdrawal(id=public_id, received=received, reference_digest=digest(reference),
            email_digest=digest("another@example.org"), encrypted_declaration=encrypt(json.dumps(value)),
            request_digest="e" * 64, idempotency="synthetic-earlier-public", mail_status="accepted"))
    response = operator.post(f"/api/admin/withdrawals/{public_id}/link",
                            json={"order_reference": reference, "identity_verified": True})
    assert response.status_code == 200 and response.json()["payment_hold"] is True
    with DB() as db:
        row = db.scalar(select(OrderWithdrawal).where(OrderWithdrawal.order_id == identifier))
        assert row.received == own["received_at"] and row.effective_received == received
        assert withdrawals.receipt_text(withdrawals.decoded(row)) == own["receipt_text"]
        assert db.get(BankOrder, identifier).status == "cancelled"


@pytest.mark.skipif(engine.dialect.name != "postgresql", reason="Actual PostgreSQL family-lock wait")
@pytest.mark.parametrize("change", ["revoke_session", "remove_owner"])
def test_authority_is_rechecked_after_family_lock_wait(api, mailbox, sent, monkeypatch, change):
    user = register(api, mailbox)
    identifier, _ = seed(user)
    waiting = threading.Event()
    original = withdrawals.lock_order
    def awaiting_lock(db, principal, order_id):
        waiting.set()
        return original(db, principal, order_id)
    monkeypatch.setattr(withdrawals, "lock_order", awaiting_lock)
    with ThreadPoolExecutor(max_workers=1) as pool:
        with DB.begin() as locked:
            locked.execute(update(Family).where(Family.id == user["families"][0]["id"]).values(child_limit=Family.child_limit))
            pending = pool.submit(submit, api, identifier)
            assert waiting.wait(8)
            if change == "revoke_session":
                token = api.headers["Authorization"].removeprefix("Bearer ")
                locked.execute(update(Session).where(Session.token_hash == digest(token)).values(revoked=True))
            else:
                locked.execute(update(Membership).where(Membership.user_id == user["id"]).values(permission="view"))
        assert pending.result(12).status_code in (401, 403)
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(OrderWithdrawal)) == 0
        assert db.get(BankOrder, identifier).status == "awaiting_payment"
    assert sent == []
