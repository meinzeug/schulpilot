"""Explicit prepaid web payments. Browser callbacks never prove a payment.

Fixed PayPal endpoints, immutable local amounts, no capture retries, local-only
GET status and shared settlement for capture responses and verified webhooks.
"""

import hashlib
import json
import threading
import uuid
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import Field, StringConstraints
from sqlalchemy import func, inspect, select, update
from sqlalchemy.exc import IntegrityError
from starlette.concurrency import run_in_threadpool

from . import paypal_client as provider
from . import schemas as s
from .config import settings
from .db import DB, BankOrder, Child, Family, Membership, Session, User, get_db, now
from .payment_models import (
    PaymentAttempt,
    PaymentConfiguration,
    PaymentConfigurationRevision,
    PaymentEvent,
    PaymentRefund,
)
from .security import admin, audit, decrypt, encrypt, family_access, insert_ignore, parent, rate_limit

router = APIRouter(tags=["Zahlungen"])
WEBHOOK_SLOTS = threading.BoundedSemaphore(4)
UNRESOLVED = ("awaiting_approval", "capture_pending", "uncertain")
FINAL = ("completed", "denied", "cancelled", "refunded", "reversed", "partially_refunded")
NOTICE = {
    "not_started": "Die Zahlung wurde noch nicht vorbereitet.",
    "awaiting_approval": "Die Zahlung ist vorbereitet. Bestätige sie ausdrücklich beim Zahlungsanbieter.",
    "capture_pending": "Der Zahlungsausgang wird geprüft. Nicht nochmals bezahlen.",
    "completed": "Die Zahlung ist bestätigt. Der gespeicherte Laufzeitbeginn gilt.",
    "denied": "Die Zahlung konnte nicht abgeschlossen werden. Es wurde kein Zugang freigeschaltet.",
    "cancelled": "Diese Bestellung wurde storniert.",
    "uncertain": "Der Zahlungsausgang ist noch unklar. Nicht nochmals bezahlen; den Status bewusst abgleichen.",
    "refunded": "Die vollständige Erstattung ist bestätigt. Diese Laufzeit ist gesperrt.",
    "partially_refunded": "Eine Teilerstattung ist bestätigt. Sie ist getrennt von der Laufzeit dokumentiert.",
    "reversed": "Die Zahlung wurde zurückgenommen. Diese Laufzeit ist gesperrt.",
}


class PayPalSettings(s.Strict):
    enabled: bool = False
    google_pay_enabled: bool = False
    environment: Literal["sandbox", "live"] = "sandbox"
    client_id: str = Field(default="", max_length=300)
    client_secret: Annotated[str, StringConstraints(strip_whitespace=False)] = Field(
        default="", max_length=4096, repr=False
    )
    merchant_id: str = Field(default="", max_length=64)
    webhook_id: str = Field(default="", max_length=80)
    approval_evidence: str = Field(default="", max_length=1000)
    google_pay_evidence: str = Field(default="", max_length=1000)


class PayPalUpdate(PayPalSettings):
    revision: int = Field(ge=0)
    clear_secret: bool = False


class PaymentRequest(s.Strict):
    request_key: str = Field(min_length=16, max_length=80, pattern=r"^[A-Za-z0-9_-]+$")


class CaptureRequest(PaymentRequest):
    payment_id: str = Field(pattern=r"^[a-f0-9]{32}$")


def configuration(db, *, lock=False):
    row = (
        db.scalar(
            select(PaymentConfiguration)
            .where(PaymentConfiguration.id == 1)
            .execution_options(populate_existing=True)
            .with_for_update()
        )
        if lock
        else db.get(PaymentConfiguration, 1, populate_existing=True)
    )
    return (PayPalSettings(**json.loads(decrypt(row.encrypted_config))), row.revision) if row else (PayPalSettings(), 0)


def connection(config, revision):
    return provider.Connection(config.environment, config.client_id, config.client_secret, config.merchant_id, revision)


def readiness(config):
    missing = []
    for name, label in (
        ("client_id", "PayPal Client-ID"),
        ("client_secret", "PayPal Client-Secret"),
        ("merchant_id", "PayPal Händler-ID"),
        ("webhook_id", "PayPal Webhook-ID"),
    ):
        value = getattr(config, name)
        if not value or not value.isascii() or any(ord(c) <= 32 or ord(c) == 127 for c in value):
            missing.append(label)
    if config.environment == "live" and not config.approval_evidence.strip():
        missing.append("Dokumentierte Live-Händlerfreigabe")
    if config.google_pay_enabled and not config.google_pay_evidence.strip():
        missing.append("Dokumentierte Google-Pay-Händlerfreigabe")
    if settings.environment == "production" and config.environment != "live":
        missing.append("Live-Zugang statt Sandbox")
    return missing


def method_available(db, method):
    from .commerce import prerequisites, store

    if method not in ("bank_transfer", "paypal", "google_pay"):
        return False
    shop, _ = store(db)
    if not shop.enabled or prerequisites(db, shop):
        return False
    if method == "bank_transfer":
        return True
    config, _ = configuration(db)
    return config.enabled and not readiness(config) and (method != "google_pay" or config.google_pay_enabled)


def payment_methods(db):
    result = {}
    for method in ("bank_transfer", "paypal", "google_pay"):
        available = method_available(db, method)
        result[method] = {
            "available": available,
            "notice": "" if available else "Dieses Zahlungsmittel ist noch nicht freigegeben.",
        }
    return result


def config_metadata(config, revision):
    return {
        "revision": revision,
        **config.model_dump(exclude={"client_secret"}),
        "has_client_secret": bool(config.client_secret),
        "readiness": readiness(config),
    }


@router.get("/admin/payments/paypal")
def read_configuration(p=Depends(admin), db=Depends(get_db)):
    config, revision = configuration(db)
    audit(db, p.user.id, "payment.configuration_read", "paypal")
    db.commit()
    return config_metadata(config, revision)


@router.put("/admin/payments/paypal")
def update_configuration(data: PayPalUpdate, p=Depends(admin), db=Depends(get_db)):
    rate_limit(db, "payment-config:" + p.user.id, 10, 3600)
    insert_ignore(db, PaymentConfiguration, {"id": 1, "revision": 0, "encrypted_config": encrypt("{}")})
    row = db.scalar(select(PaymentConfiguration).where(PaymentConfiguration.id == 1).with_for_update())
    db.expire_all()
    fresh_authority(db, p, role="admin")
    db.refresh(row)
    if row.revision != data.revision:
        raise HTTPException(409, "Die Zahlungseinstellungen wurden geändert. Bitte neu laden.")
    previous = PayPalSettings(**json.loads(decrypt(row.encrypted_config)))
    values = previous.model_dump()
    for field in data.model_fields_set - {"revision", "clear_secret"}:
        if field != "client_secret" or data.client_secret:
            values[field] = getattr(data, field)
    if data.clear_secret:
        values["client_secret"] = ""
    config = PayPalSettings(**values)
    missing = readiness(config)
    if config.enabled and missing:
        raise HTTPException(422, "Zahlungen können noch nicht starten: " + ", ".join(missing))
    if db.scalar(select(PaymentAttempt.id).where(PaymentAttempt.status.in_(UNRESOLVED)).limit(1)):
        raise HTTPException(409, "Offene Zahlungsversuche zuerst abgleichen. Ihre Händlerbindung bleibt erhalten.")
    row.encrypted_config = encrypt(config.model_dump_json())
    row.revision += 1
    db.add(PaymentConfigurationRevision(revision=row.revision, encrypted_config=row.encrypted_config))
    audit(db, p.user.id, "payment.configuration_update", "paypal")
    db.commit()
    return config_metadata(config, row.revision)


def fresh_authority(db, p, *, role="parent"):
    # ORM primary identities remain readable even if the row was deleted while
    # waiting; accessing an expired p.user.id could otherwise raise first.
    user_id, session_id = inspect(p.user).identity[0], inspect(p.session).identity[0]
    user = db.scalar(select(User).where(User.id == user_id).execution_options(populate_existing=True))
    session = db.scalar(select(Session).where(Session.id == session_id).execution_options(populate_existing=True))
    current = int(now())
    if (
        not user
        or user.disabled
        or not user.verified
        or user.role != role
        or not session
        or session.user_id != user.id
        or session.revoked
        or session.expires <= current
        or current - session.seen > 7 * 86400
    ):
        raise HTTPException(401, "Bitte erneut anmelden.")
    p.user, p.session = user, session


def lock_owned_family(db, p, family_id):
    changed = db.execute(update(Family).where(Family.id == family_id).values(child_limit=Family.child_limit))
    if not changed.rowcount:
        raise HTTPException(404, "Familie nicht gefunden.")
    # A SELECT alone can reuse the pre-lock Membership from the identity map.
    # Clear it before the authoritative, now serialized ownership recheck.
    db.expire_all()
    fresh_authority(db, p)
    family, _ = family_access(db, p, family_id, owner=True)
    if family.synthetic:
        raise HTTPException(403, "Im Testraum sind keine Zahlungen möglich.")
    return family


def owned(db, p, order_id, *, lock=False):
    fresh_authority(db, p)
    row = db.get(BankOrder, order_id, populate_existing=True)
    if not row or not row.family_id:
        raise HTTPException(404, "Bestellung nicht gefunden.")
    family, _ = family_access(db, p, row.family_id, owner=True)
    if family.synthetic:
        raise HTTPException(403, "Im Testraum sind keine Zahlungen möglich.")
    if lock:
        family_id = family.id
        lock_owned_family(db, p, family_id)
        row = db.get(BankOrder, order_id, populate_existing=True)
        if not row or row.family_id != family_id:
            raise HTTPException(404, "Bestellung nicht gefunden.")
    return row


def held(db, order_id):
    from .order_withdrawals import payment_hold

    return payment_hold(db, order_id)


def exact_config(db, payment):
    config, revision = configuration(db)
    if (config.environment, config.merchant_id, revision) != (
        payment.environment,
        payment.merchant_id,
        payment.config_revision,
    ):
        raise HTTPException(409, "Die Händlerbindung wurde geändert. Diese Zahlung muss geprüft werden.")
    return config, revision


def status_data(db, order):
    from .commerce import order_data

    payment = db.scalar(
        select(PaymentAttempt).where(PaymentAttempt.order_id == order.id).execution_options(populate_existing=True)
    )
    config, revision = configuration(db)
    matches = payment is None or (payment.environment, payment.merchant_id, payment.config_revision) == (
        config.environment,
        config.merchant_id,
        revision,
    )
    available = method_available(db, order.payment_method)
    hold = held(db, order.id)
    state = (
        payment.status
        if payment
        else "completed"
        if order.status == "paid"
        else "cancelled"
        if order.status == "cancelled"
        else "refunded"
        if order.status == "refunded"
        else "not_started"
    )
    can_open = bool(
        payment
        and state == "awaiting_approval"
        and payment.provider_order_id
        and payment.capture_started is None
        and matches
        and available
        and order.status == "awaiting_payment"
        and not hold
    )
    can_reconcile = bool(payment and payment.provider_order_id and matches and state in UNRESOLVED)
    notice = NOTICE[state]
    if hold:
        notice = "Ein Widerruf wird bearbeitet. Keine weitere Zahlung starten. Bereits gebuchte Zahlungen werden gesondert geprüft."
    elif payment and state == "uncertain" and not payment.provider_order_id:
        notice = "Die Vorbereitung ist unklar. Nicht nochmals bezahlen; der Anbieter muss den Vorgang prüfen."
    elif payment and not matches:
        notice = "Die Händlerbindung passt nicht mehr. Nicht nochmals bezahlen; der Anbieter muss den Vorgang prüfen."
    return {
        "payment_id": payment.id if payment else None,
        "provider_order_id": payment.provider_order_id if payment else None,
        "method": order.payment_method,
        "status": state,
        "amount_cents": order.amount_cents,
        "currency": order.currency,
        "environment": payment.environment
        if payment
        else config.environment
        if available and order.payment_method != "bank_transfer"
        else None,
        "client_id": config.client_id if matches and available and order.payment_method != "bank_transfer" else None,
        "config_revision": payment.config_revision
        if payment
        else revision
        if available and order.payment_method != "bank_transfer"
        else None,
        "config_matches": matches,
        "can_start": bool(
            not payment
            and available
            and order.payment_method != "bank_transfer"
            and order.status == "awaiting_payment"
            and not hold
        ),
        "can_open": can_open,
        "can_capture": can_open,
        "can_reconcile": can_reconcile,
        "notice": notice,
        "order": order_data(order),
    }


@router.get("/orders/{order_id}/payment")
def payment_status(order_id: str, p=Depends(parent), db=Depends(get_db)):
    return status_data(db, owned(db, p, order_id))


def mapping(value):
    if not isinstance(value, dict):
        raise provider.PayPalError("payment_mismatch")
    return value


def bound_configuration(db, payment):
    row = db.get(PaymentConfigurationRevision, payment.config_revision)
    if not row:
        raise HTTPException(503, "Die ursprüngliche Händlerbindung muss vom Anbieter geprüft werden.")
    config = PayPalSettings(**json.loads(decrypt(row.encrypted_config)))
    if (config.environment, config.merchant_id) != (payment.environment, payment.merchant_id):
        raise HTTPException(503, "Die ursprüngliche Händlerbindung muss vom Anbieter geprüft werden.")
    return config, payment.config_revision


def verified_purchase(payment, order, value):
    value = mapping(value)
    if value.get("id") != payment.provider_order_id:
        raise provider.PayPalError("payment_mismatch")
    units = value.get("purchase_units")
    if not isinstance(units, list) or len(units) != 1 or not isinstance(units[0], dict):
        raise provider.PayPalError("payment_mismatch")
    unit = units[0]
    amount = mapping(unit.get("amount"))
    payee = mapping(unit.get("payee"))
    if (
        unit.get("reference_id") != order.id
        or unit.get("custom_id") != order.id
        or unit.get("invoice_id") != order.payment_reference
        or amount.get("currency_code") != payment.currency
        or provider.cents(amount.get("value")) != payment.amount_cents
        or payee.get("merchant_id") != payment.merchant_id
    ):
        raise provider.PayPalError("payment_mismatch")
    if (payment.amount_cents, payment.currency, payment.method) != (
        order.amount_cents,
        order.currency,
        order.payment_method,
    ):
        raise provider.PayPalError("payment_mismatch")
    return unit


def buyer_still_authorized(db, order):
    user = db.get(User, order.buyer_id, populate_existing=True) if order.buyer_id else None
    return bool(
        user
        and user.role == "parent"
        and user.verified
        and not user.disabled
        and order.family_id
        and db.scalar(
            select(Membership.id).where(
                Membership.family_id == order.family_id, Membership.user_id == user.id, Membership.permission == "owner"
            )
        )
    )


def settle(db, payment, order, value):
    """Caller holds Family before this payment; one transition grants one period."""
    from .commerce import DAY, last_paid_order

    unit = verified_purchase(payment, order, value)
    if payment.status in ("completed", "refunded", "reversed", "partially_refunded"):
        return
    captures = mapping(unit.get("payments", {})).get("captures", [])
    if value.get("status") != "COMPLETED":
        payment.status = (
            "awaiting_approval"
            if payment.capture_started is None
            and value.get("status") in ("CREATED", "SAVED", "APPROVED", "PAYER_ACTION_REQUIRED")
            else "uncertain"
        )
        return
    if not isinstance(captures, list) or len(captures) != 1:
        raise provider.PayPalError("payment_mismatch")
    capture = mapping(captures[0])
    amount = mapping(capture.get("amount"))
    if (
        amount.get("currency_code") != payment.currency
        or provider.cents(amount.get("value")) != payment.amount_cents
        or capture.get("final_capture") is not True
    ):
        raise provider.PayPalError("payment_mismatch")
    capture_id = provider.identifier(capture.get("id"))
    if payment.capture_id and payment.capture_id != capture_id:
        raise provider.PayPalError("payment_mismatch")
    if capture.get("status") == "PENDING":
        payment.status = "capture_pending"
        return
    if capture.get("status") != "COMPLETED":
        payment.status = "denied" if capture.get("status") in ("DECLINED", "DENIED", "FAILED") else "uncertain"
        return
    payment.capture_id = capture_id
    if order.status in ("refunded", "cancelled"):
        payment.status, payment.error_code = "uncertain", "operator_review_required"
        return
    if order.status == "paid":
        payment.status = "completed"
        return
    family = db.get(Family, order.family_id, populate_existing=True) if order.family_id else None
    if (
        not family
        or family.synthetic
        or not buyer_still_authorized(db, order)
        or held(db, order.id)
        or not method_available(db, payment.method)
    ):
        payment.status, payment.error_code = "uncertain", "operator_review_required"
        return
    if db.scalar(select(func.count()).select_from(Child).where(Child.family_id == family.id)) > order.offer["children"]:
        payment.status, payment.error_code = "uncertain", "operator_review_required"
        return
    current = int(now())
    previous = last_paid_order(db, family.id, current)
    if previous and previous.offer["id"] != order.offer["id"]:
        payment.status, payment.error_code = "uncertain", "operator_review_required"
        return
    starts = max(current, previous.ends if previous else 0, 0 if order.early_start else order.created + 14 * DAY)
    if order.status != "awaiting_payment":
        payment.status, payment.error_code = "uncertain", "operator_review_required"
        return
    order.status, order.pending_slot = "paid", None
    order.starts, order.ends, order.checked_at = starts, starts + 30 * DAY, current
    family.commerce_required, family.plan = True, order.offer["name"]
    family.child_limit, family.call_limit, family.budget_micros = (
        order.offer["children"],
        order.offer["calls"],
        order.offer["budget_micros"],
    )
    payment.status, payment.error_code = "completed", None
    audit(db, order.buyer_id, "payment.verified_and_activated", order.id)


def save_provider_error(db, payment_id, code, uncertain=True):
    payment = db.get(PaymentAttempt, payment_id, populate_existing=True)
    if payment:
        order = db.get(BankOrder, payment.order_id)
        if order and order.family_id:
            db.execute(update(Family).where(Family.id == order.family_id).values(child_limit=Family.child_limit))
        db.refresh(payment)
    if payment and payment.status not in FINAL:
        payment.status = "uncertain" if uncertain else "denied"
        payment.error_code, payment.updated = code, int(now())
        db.commit()


def pending(response, result):
    if result["status"] in ("capture_pending", "uncertain"):
        response.status_code = 202
    return result


@router.post("/orders/{order_id}/paypal/create")
def create_payment(order_id: str, data: PaymentRequest, response: Response, p=Depends(parent), db=Depends(get_db)):
    rate_limit(db, "payment-create:" + p.user.id, 10, 3600)
    order = owned(db, p, order_id, lock=True)
    existing = db.scalar(select(PaymentAttempt).where(PaymentAttempt.order_id == order.id))
    if existing:
        return pending(response, status_data(db, order))
    if (
        order.status != "awaiting_payment"
        or order.payment_method not in ("paypal", "google_pay")
        or held(db, order.id)
        or not method_available(db, order.payment_method)
    ):
        raise HTTPException(409, "Diese Bestellung ist nicht für eine neue Anbieterzahlung freigegeben.")
    config, revision = configuration(db, lock=True)
    if (
        not config.enabled
        or readiness(config)
        or (order.payment_method == "google_pay" and not config.google_pay_enabled)
    ):
        raise HTTPException(409, "Die Zahlungseinstellungen wurden geändert. Bitte neu laden.")
    payment = PaymentAttempt(
        order_id=order.id,
        environment=config.environment,
        merchant_id=config.merchant_id,
        config_revision=revision,
        method=order.payment_method,
        amount_cents=order.amount_cents,
        currency=order.currency,
        status="capture_pending",
        create_request_id=str(uuid.uuid4()),
        capture_request_id=str(uuid.uuid4()),
    )
    db.add(payment)
    db.flush()
    payment_id, create_id = payment.id, payment.create_request_id
    audit(db, p.user.id, "payment.create_requested", order.id)
    db.commit()  # Persist intent before the only provider mutation.
    try:
        value = provider.create_order(connection(config, revision), order, create_id)
        provider_id = provider.identifier(value.get("id"))
        db.expire_all()
        order = owned(db, p, order_id, lock=True)
        payment = db.get(PaymentAttempt, payment_id, populate_existing=True)
        exact_config(db, payment)
        payment.provider_order_id = provider_id
        verified_purchase(payment, order, value)
        payment.status = "awaiting_approval"
        payment.updated = int(now())
        db.commit()
    except provider.PayPalError as error:
        db.rollback()
        save_provider_error(db, payment_id, error.code, error.uncertain)
    except IntegrityError:
        db.rollback()
        save_provider_error(db, payment_id, "payment_mismatch")
    except HTTPException:
        db.rollback()
        save_provider_error(db, payment_id, "authority_changed")
        raise
    return pending(response, status_data(db, owned(db, p, order_id)))


def after_provider(db, p, order_id, payment_id, value):
    db.expire_all()
    order = owned(db, p, order_id, lock=True)
    payment = db.get(PaymentAttempt, payment_id, populate_existing=True)
    exact_config(db, payment)
    settle(db, payment, order, value)
    payment.updated = int(now())
    db.commit()
    return order


@router.post("/orders/{order_id}/paypal/capture")
def capture_payment(order_id: str, data: CaptureRequest, response: Response, p=Depends(parent), db=Depends(get_db)):
    rate_limit(db, "payment-capture:" + p.user.id, 20, 3600)
    order = owned(db, p, order_id, lock=True)
    payment = db.get(PaymentAttempt, data.payment_id, populate_existing=True)
    if not payment or payment.order_id != order.id:
        raise HTTPException(404, "Zahlungsversuch nicht gefunden.")
    if payment.status != "awaiting_approval":
        return pending(response, status_data(db, order))
    if (
        order.status != "awaiting_payment"
        or held(db, order.id)
        or not method_available(db, payment.method)
        or not payment.provider_order_id
    ):
        raise HTTPException(409, "Diese Zahlung darf nicht erneut eingezogen werden.")
    config, revision = exact_config(db, payment)
    payment.status, payment.updated = "capture_pending", int(now())
    payment.capture_started = int(now())
    payment_id, provider_id, capture_id = payment.id, payment.provider_order_id, payment.capture_request_id
    audit(db, p.user.id, "payment.capture_requested", order.id)
    db.commit()
    try:
        captured = provider.capture_order(connection(config, revision), provider_id, capture_id)
        if captured.get("id") != provider_id:
            raise provider.PayPalError("payment_mismatch")
        # Capture representations can omit original purchase amount/payee. Read
        # the fixed canonical order only after a successful POST, not on timeout.
        db.expire_all()
        owned(db, p, order_id)
        exact_config(db, db.get(PaymentAttempt, payment_id, populate_existing=True))
        db.commit()
        value = provider.read_order(connection(config, revision), provider_id)
        order = after_provider(db, p, order_id, payment_id, value)
    except provider.PayPalError as error:
        db.rollback()
        save_provider_error(db, payment_id, error.code, error.uncertain)
    except IntegrityError:
        db.rollback()
        save_provider_error(db, payment_id, "payment_mismatch")
    except HTTPException:
        db.rollback()
        save_provider_error(db, payment_id, "authority_changed")
        raise
    return pending(response, status_data(db, owned(db, p, order_id)))


@router.post("/orders/{order_id}/paypal/reconcile")
def reconcile_payment(order_id: str, data: CaptureRequest, response: Response, p=Depends(parent), db=Depends(get_db)):
    rate_limit(db, "payment-reconcile:" + p.user.id, 12, 3600)
    order = owned(db, p, order_id, lock=True)
    payment = db.get(PaymentAttempt, data.payment_id, populate_existing=True)
    if not payment or payment.order_id != order.id:
        raise HTTPException(404, "Zahlungsversuch nicht gefunden.")
    if payment.status not in UNRESOLVED or not payment.provider_order_id:
        return pending(response, status_data(db, order))
    config, revision = exact_config(db, payment)
    payment_id, provider_id = payment.id, payment.provider_order_id
    db.commit()
    try:
        value = provider.read_order(connection(config, revision), provider_id)
        order = after_provider(db, p, order_id, payment_id, value)
    except provider.PayPalError as error:
        db.rollback()
        save_provider_error(db, payment_id, error.code)
    except IntegrityError:
        db.rollback()
        save_provider_error(db, payment_id, "payment_mismatch")
    except HTTPException:
        db.rollback()
        save_provider_error(db, payment_id, "authority_changed")
        raise
    return pending(response, status_data(db, owned(db, p, order_id)))


def capture_reference(resource):
    related = mapping(mapping(resource.get("supplementary_data", {})).get("related_ids", {}))
    capture_id = related.get("capture_id")
    if capture_id:
        return provider.identifier(capture_id)
    # Refund API responses identify their original capture through the up link.
    links = resource.get("links", [])
    if not isinstance(links, list) or len(links) > 20:
        raise provider.PayPalError("payment_mismatch")
    for link in links:
        if not isinstance(link, dict) or link.get("rel") != "up":
            continue
        href = link.get("href")
        if not isinstance(href, str):
            continue
        for base in provider.BASES.values():
            prefix = base + "/v2/payments/captures/"
            if href.startswith(prefix) and "/" not in href[len(prefix) :] and "?" not in href:
                return provider.identifier(href[len(prefix) :])
    raise provider.PayPalError("payment_mismatch")


def apply_refund(db, payment, order, refund):
    refund_id = provider.identifier(refund.get("id"))
    if capture_reference(refund) != payment.capture_id or refund.get("status") != "COMPLETED":
        raise provider.PayPalError("payment_mismatch")
    amount = mapping(refund.get("amount"))
    amount_cents = provider.cents(amount.get("value"))
    if amount.get("currency_code") != payment.currency or amount_cents <= 0 or amount_cents > payment.amount_cents:
        raise provider.PayPalError("payment_mismatch")
    existing = db.scalar(
        select(PaymentRefund).where(
            PaymentRefund.payment_id == payment.id, PaymentRefund.provider_refund_id == refund_id
        )
    )
    if existing:
        if existing.amount_cents != amount_cents:
            raise provider.PayPalError("payment_mismatch")
        return
    if payment.refunded_cents + amount_cents > payment.amount_cents:
        raise provider.PayPalError("payment_mismatch")
    db.add(PaymentRefund(payment_id=payment.id, provider_refund_id=refund_id, amount_cents=amount_cents))
    payment.refunded_cents += amount_cents
    if payment.refunded_cents == payment.amount_cents:
        payment.status, order.status, order.revoked_at = "refunded", "refunded", int(now())
        order.pending_slot = None
        order.checked_at = order.checked_at or int(now())
    elif payment.status != "reversed":
        payment.status = "partially_refunded"
    audit(db, order.buyer_id or "payment", "payment.refund_verified", order.id)


def _event_payment(db, event, environment):
    resource = mapping(event.get("resource", {}))
    kind = event.get("event_type")
    related = mapping(mapping(resource.get("supplementary_data", {})).get("related_ids", {}))
    condition = None
    if kind == "PAYMENT.CAPTURE.REFUNDED":
        capture_id = capture_reference(resource)
        condition = PaymentAttempt.capture_id == capture_id
    elif kind in (
        "PAYMENT.CAPTURE.COMPLETED",
        "PAYMENT.CAPTURE.PENDING",
        "PAYMENT.CAPTURE.DENIED",
        "PAYMENT.CAPTURE.DECLINED",
        "PAYMENT.CAPTURE.REVERSED",
    ):
        condition = PaymentAttempt.provider_order_id == provider.identifier(related.get("order_id"))
    if condition is None:
        return None
    matches = list(
        db.scalars(select(PaymentAttempt).where(condition, PaymentAttempt.environment == environment).limit(2))
    )
    if len(matches) > 1:
        raise provider.PayPalError("payment_mismatch")
    return matches[0] if matches else None


def process_webhook(raw, headers):
    # Do not occupy the entire API threadpool with externally triggered HTTP.
    if not WEBHOOK_SLOTS.acquire(blocking=False):
        raise HTTPException(503, "Zahlungsprüfung ist ausgelastet. Bitte später erneut zustellen.")
    try:
        return _process_webhook(raw, headers)
    finally:
        WEBHOOK_SLOTS.release()


def _process_webhook(raw, headers):
    """Verify only the exact saved binding; retain no payload or payer contents."""
    if len(raw) > 65536:
        raise HTTPException(413, "Anfrage ist zu groß.")
    try:
        event = json.loads(raw)
    except (ValueError, UnicodeError):
        raise HTTPException(400, "Ungültige Zahlungsnachricht.") from None
    if not isinstance(event, dict) or not isinstance(event.get("event_type"), str) or len(event["event_type"]) > 80:
        raise HTTPException(400, "Ungültige Zahlungsnachricht.")
    try:
        event_id = provider.identifier(event.get("id"), limit=160)
        # Certificate environment is only a candidate selector, never authority.
        certificate = headers.get("paypal-cert-url", "")
        environment = "sandbox" if ".sandbox.paypal.com/" in certificate else "live"
        with DB() as db:
            rate_limit(db, "paypal-webhook-verification", 120, 60)
            payment = _event_payment(db, event, environment)
            config, revision = bound_configuration(db, payment) if payment else configuration(db)
            if not config.webhook_id or not config.client_secret:
                raise HTTPException(503, "Zahlungsprüfung ist nicht eingerichtet.")
            binding = connection(config, revision)
            if not provider.verify_webhook(binding, headers, event, config.webhook_id):
                raise HTTPException(400, "Zahlungsnachricht konnte nicht bestätigt werden.")
            body_hash = hashlib.sha256(raw).hexdigest()
            previous = db.scalar(
                select(PaymentEvent).where(
                    PaymentEvent.environment == config.environment,
                    PaymentEvent.merchant_id == config.merchant_id,
                    PaymentEvent.event_id == event_id,
                )
            )
            if previous:
                if previous.body_sha256 != body_hash:
                    raise HTTPException(409, "Zahlungsnachricht passt nicht zum gespeicherten Vorgang.")
                return {"received": True}
            kind = event["event_type"]
            # A refund can race the original capture response. Resolve its fixed
            # capture endpoint only after signature validation, then bind locally.
            if not payment and kind == "PAYMENT.CAPTURE.REFUNDED":
                capture = provider.read_capture(binding, capture_reference(event["resource"]))
                related = mapping(mapping(capture.get("supplementary_data", {})).get("related_ids", {}))
                payment = db.scalar(
                    select(PaymentAttempt).where(
                        PaymentAttempt.provider_order_id == provider.identifier(related.get("order_id")),
                        PaymentAttempt.environment == config.environment,
                        PaymentAttempt.merchant_id == config.merchant_id,
                        PaymentAttempt.config_revision == revision,
                    )
                )
            if not payment:
                return {"received": True}
            order = db.get(BankOrder, payment.order_id)
            if not order:
                return {"received": True}
            payment_id, order_id, provider_id = payment.id, order.id, payment.provider_order_id
            db.commit()  # No application lock is held during any provider HTTP.
            canonical = provider.read_order(binding, provider_id)
            refund = (
                provider.read_refund(binding, provider.identifier(event["resource"].get("id")))
                if kind == "PAYMENT.CAPTURE.REFUNDED"
                else None
            )
            capture = (
                provider.read_capture(binding, provider.identifier(event["resource"].get("id")))
                if kind == "PAYMENT.CAPTURE.REVERSED"
                else None
            )
            db.expire_all()
            order = db.get(BankOrder, order_id, populate_existing=True)
            if not order:
                return {"received": True}
            if order.family_id:
                db.execute(update(Family).where(Family.id == order.family_id).values(child_limit=Family.child_limit))
                db.refresh(order)
            payment = db.scalar(
                select(PaymentAttempt)
                .where(PaymentAttempt.id == payment_id)
                .execution_options(populate_existing=True)
                .with_for_update()
            )
            saved, saved_revision = bound_configuration(db, payment)
            if saved_revision != revision or saved != config:
                raise provider.PayPalError("payment_mismatch")
            previous = db.scalar(
                select(PaymentEvent).where(
                    PaymentEvent.environment == config.environment,
                    PaymentEvent.merchant_id == config.merchant_id,
                    PaymentEvent.event_id == event_id,
                )
            )
            if previous:
                if previous.body_sha256 != body_hash:
                    raise HTTPException(409, "Zahlungsnachricht passt nicht zum gespeicherten Vorgang.")
                return {"received": True}
            unit = verified_purchase(payment, order, canonical)
            if kind == "PAYMENT.CAPTURE.COMPLETED" and payment.status not in (
                "completed",
                "refunded",
                "reversed",
                "partially_refunded",
            ):
                capture_rows = mapping(unit.get("payments", {})).get("captures", [])
                if (
                    canonical.get("status") != "COMPLETED"
                    or not isinstance(capture_rows, list)
                    or len(capture_rows) != 1
                    or mapping(capture_rows[0]).get("status") != "COMPLETED"
                ):
                    # Eventual consistency must not consume a final event before
                    # its canonical capture can be verified. Provider redelivery
                    # repeats GET verification, never a capture POST.
                    raise provider.PayPalError("payment_mismatch")
            if refund is not None or capture is not None:
                captures = mapping(unit.get("payments", {})).get("captures", [])
                if not isinstance(captures, list) or len(captures) != 1:
                    raise provider.PayPalError("payment_mismatch")
                original = mapping(captures[0])
                amount = mapping(original.get("amount"))
                original_id = provider.identifier(original.get("id"))
                if (
                    amount.get("currency_code") != payment.currency
                    or provider.cents(amount.get("value")) != payment.amount_cents
                    or original.get("final_capture") is not True
                    or (payment.capture_id and payment.capture_id != original_id)
                ):
                    raise provider.PayPalError("payment_mismatch")
                payment.capture_id = original_id
                if refund is not None:
                    apply_refund(db, payment, order, refund)
                else:
                    amount = mapping(capture.get("amount"))
                    if (
                        capture.get("id") != payment.capture_id
                        or capture.get("status")
                        not in ("COMPLETED", "REFUNDED", "PARTIALLY_REFUNDED", "DECLINED", "FAILED")
                        or amount.get("currency_code") != payment.currency
                        or provider.cents(amount.get("value")) != payment.amount_cents
                    ):
                        raise provider.PayPalError("payment_mismatch")
                    # The signed REVERSED event proves the reversal. Payments
                    # v2 does not define a REVERSED capture status; the canonical
                    # capture proves identity/gross amount, not a fabricated enum.
                    payment.status, order.status, order.revoked_at = "reversed", "refunded", int(now())
                    order.pending_slot = None
                    order.checked_at = order.checked_at or int(now())
                    audit(db, order.buyer_id or "payment", "payment.reversal_verified", order.id)
            else:
                # An obsolete configuration can revoke access on confirmed
                # refund, but cannot grant a fresh entitlement.
                exact_config(db, payment)
                settle(db, payment, order, canonical)
            db.add(
                PaymentEvent(
                    environment=config.environment,
                    merchant_id=config.merchant_id,
                    event_id=event_id,
                    event_type=kind,
                    body_sha256=body_hash,
                    payment_id=payment.id,
                    result=payment.status,
                )
            )
            payment.updated = int(now())
            db.commit()
            return {"received": True}
    except provider.PayPalError:
        raise HTTPException(503, "Die Zahlungsnachricht muss erneut geprüft werden.") from None
    except IntegrityError:
        raise HTTPException(503, "Die Zahlungsnachricht muss erneut abgeglichen werden.") from None


@router.post("/payments/paypal/webhook")
async def paypal_webhook(request: Request):
    raw = await request.body()
    return await run_in_threadpool(process_webhook, raw, {key.lower(): value for key, value in request.headers.items()})
