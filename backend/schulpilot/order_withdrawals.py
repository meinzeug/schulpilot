"""Durable withdrawal receipts. Only verified declarations may hold payment.

Public input is never used to look up or change a private order. Linking is an
explicit audited adult-contract operation, not a refund or learning operation.
"""

import json
import secrets
import unicodedata
from datetime import datetime, time, timedelta, timezone
from typing import Literal
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response
from pydantic import EmailStr, Field, field_validator
from sqlalchemy import and_, delete, or_, select, update

from . import schemas as s
from .commerce import owned_order
from .db import BankOrder, Family, Session, User, get_db, now
from .order_withdrawal_models import OrderWithdrawal, PublicWithdrawal
from .security import admin, audit, decrypt, digest, encrypt, insert_ignore, parent, rate_limit

router = APIRouter(tags=["Widerruf"])
DAY = 86400
DECLARATION = "Hiermit widerrufe ich den von mir abgeschlossenen Vertrag über die Nutzung von SCHULPILOT."
BERLIN = ZoneInfo("Europe/Berlin")


class WithdrawalRequest(s.Strict):
    request_key: str = Field(min_length=16, max_length=60, pattern=r"^[A-Za-z0-9_-]+$")
    buyer_name: str = Field(min_length=2, max_length=160)
    contact_email: EmailStr
    confirm: Literal[True]

    @field_validator("buyer_name")
    @classmethod
    def name(cls, value):
        value = value.strip()
        if len(value) < 2 or any(unicodedata.category(c).startswith("C") for c in value):
            raise ValueError("Bitte einen lesbaren Namen ohne Steuerzeichen eingeben.")
        return value


class PublicRequest(WithdrawalRequest):
    order_reference: str = Field(min_length=1, max_length=80)

    @field_validator("order_reference")
    @classmethod
    def reference(cls, value):
        value = value.strip()
        if not value or any(unicodedata.category(c).startswith("C") for c in value):
            raise ValueError("Bitte eine Bestellreferenz ohne Steuerzeichen eingeben.")
        return value


class LinkRequest(s.Strict):
    order_reference: str = Field(min_length=1, max_length=80)
    identity_verified: Literal[True]


def snapshot(identifier, received, buyer_name, email, reference):
    return {"receipt_id": identifier, "declaration": DECLARATION, "buyer_name": buyer_name,
            "contact_email": email, "order_reference": reference, "received_at": received,
            "received_at_iso": datetime.fromtimestamp(received, timezone.utc).isoformat()}


def receipt_text(value):
    return ("SCHULPILOT – Eingangsbestätigung Ihrer Widerrufserklärung\n"
            f"Belegnummer: {value['receipt_id']}\n"
            f"Eingegangen am: {value['received_at_iso']} (UTC)\n"
            f"Name: {value['buyer_name']}\nBestellreferenz: {value['order_reference']}\n"
            f"Kontakt: {value['contact_email']}\n\n{value['declaration']}\n\n"
            "Diese Bestätigung belegt den Eingang der Erklärung. Eine Zuordnung, die rechtliche Prüfung "
            "und eine gegebenenfalls erforderliche Rückzahlung erfolgen getrennt. "
            "Die App hat keine Rückzahlung ausgelöst.\n")


def decoded(row):
    return json.loads(decrypt(row.encrypted_declaration))


def payload_digest(value):
    return digest(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False))


def within_standard_window(order, received):
    """Conservative automatic window, not a legal denial after its end.

    Fourteen calendar days after the local contract day, through end of day.
    Weekends extend to Monday. State-specific holiday/notice exceptions go to
    manual review; an outside submission is always retained and acknowledged.
    """
    end = datetime.fromtimestamp(order.created, BERLIN).date() + timedelta(days=14)
    while end.weekday() >= 5:
        end += timedelta(days=1)
    deadline = datetime.combine(end + timedelta(days=1), time.min, BERLIN).timestamp()
    return received < deadline


def payment_hold(db, order_id):
    """Caller holds the existing Family lock before capture/settlement.

    Pure read. Public unverified submissions never participate in this query.
    Historical holds remain effective after the standard window has elapsed.
    """
    return db.scalar(select(OrderWithdrawal.id).where(OrderWithdrawal.order_id == order_id,
        OrderWithdrawal.verified.is_(True), OrderWithdrawal.hold_payment.is_(True)).limit(1)) is not None


def cancel_if_certainly_unpaid(db, order, timely):
    from .payment_models import PaymentAttempt

    if timely and order.status == "awaiting_payment":
        payment = db.scalar(select(PaymentAttempt).where(PaymentAttempt.order_id == order.id))
        # A withdrawal is still received, but an already dispatched/uncertain
        # capture is not reclassified as definitely unpaid or refunded.
        if not payment or (payment.capture_started is None
                           and payment.status not in ("capture_pending", "uncertain", "completed")):
            order.status, order.pending_slot = "cancelled", None


def checked_principal(db, p, role):
    user = db.get(User, p.user.id, populate_existing=True)
    session = db.get(Session, p.session.id, populate_existing=True)
    if (not user or user.disabled or not user.verified or not session or session.revoked
            or session.user_id != user.id or session.expires <= now() or session.seen < now() - 7 * DAY):
        raise HTTPException(401, "Bitte erneut anmelden.")
    if user.role != role:
        raise HTTPException(403, "Dieser Zugang erlaubt die Aktion nicht.")
    return user


def lock_order(db, p, order_id):
    row = owned_order(db, p, order_id)
    db.execute(update(Family).where(Family.id == row.family_id).values(child_limit=Family.child_limit))
    db.expire_all()
    checked_principal(db, p, "parent")
    row = owned_order(db, p, order_id)
    family = db.get(Family, row.family_id)
    if family.synthetic:
        raise HTTPException(403, "Im Testraum werden keine Vertragswiderrufe abgegeben.")
    return row


def projection(row, *, public=False, private=False):
    value = decoded(row)
    result = {"id": row.id, "status": "received_unverified" if public else row.status,
              "received_at": row.received, "received_at_iso": value["received_at_iso"],
              "mail_status": row.mail_status, "receipt_text": receipt_text(value),
              "payment_hold": False if public else bool(getattr(row, "hold_payment", False)),
              "refund_executed": False,
              "notice": "Ihre Erklärung ist eingegangen. Eine Rückzahlung wurde nicht ausgelöst."
                if not public else "Ihre Erklärung ist eingegangen. Die Zuordnung wird geprüft; Zahlungs- und Familienstatus wurden nicht geändert."}
    if not public and row.status == "review_required":
        result["notice"] = ("Ihre Erklärung ist eingegangen und wird gesondert geprüft. "
                            "Der Prüfstatus ist keine Ablehnung Ihres Widerrufs. Eine Rückzahlung wurde nicht ausgelöst.")
    elif not public and result["payment_hold"]:
        result["notice"] = ("Ihre Erklärung ist eingegangen. Weitere Zahlungen und Freischaltungen dieser Bestellung "
                            "sind angehalten. Eine gegebenenfalls erforderliche Rückzahlung wird gesondert geprüft.")
    if row.mail_status == "accepted":
        result["mail_notice"] = "Der Mailserver hat die Bestätigung angenommen. Die Zustellung ist nicht bestätigt."
    elif row.mail_status == "failed":
        result["mail_notice"] = "Die E-Mail-Übergabe ist nicht bestätigt. Bitte den Eingangsbeleg herunterladen und aufbewahren."
    else:
        result["mail_notice"] = "Die E-Mail-Übergabe ist noch nicht bestätigt. Der Eingangsbeleg bleibt verfügbar."
    if private:
        result["declaration"] = value
    return result


def send_receipt(db, model, identifier):
    """At most one send attempt, after durable receipt commit; no retry on GET."""
    from .mail import send_message

    if not db.execute(update(model).where(model.id == identifier, model.mail_status == "pending")
                      .values(mail_status="sending")).rowcount:
        db.rollback()
        return
    db.commit()
    row = db.get(model, identifier, populate_existing=True)
    if row is None:
        return
    value = decoded(row)
    try:
        send_message(value["contact_email"], "SCHULPILOT: Eingang Ihrer Widerrufserklärung", receipt_text(value))
        status = "accepted"
    except (HTTPException, OSError):
        status = "failed"
    db.execute(update(model).where(model.id == identifier, model.mail_status == "sending").values(mail_status=status))
    db.commit()


@router.post("/orders/{order_id}/withdrawals", status_code=201)
def submit_owner(order_id: str, data: WithdrawalRequest, response: Response,
                 p=Depends(parent), db=Depends(get_db)):
    owned_order(db, p, order_id)
    rate_limit(db, "withdraw-owner:" + p.user.id, 10, 3600)
    order = lock_order(db, p, order_id)
    email = str(data.contact_email).casefold()
    if not p.user.email or email != p.user.email.casefold():
        raise HTTPException(422, "Bitte die bestätigte E-Mail-Adresse dieses Elternkontos verwenden.")
    key = order.family_id + ":" + data.request_key
    body_hash = payload_digest({"order_id": order.id, "buyer_name": data.buyer_name, "contact_email": email})
    existing_key = db.scalar(select(OrderWithdrawal).where(OrderWithdrawal.idempotency == key))
    if existing_key and existing_key.order_id != order.id:
        raise HTTPException(409, "Dieser Vorgangsschlüssel wurde bereits für eine andere Erklärung verwendet.")
    existing = db.scalar(select(OrderWithdrawal).where(OrderWithdrawal.order_id == order.id))
    if existing:
        if existing.request_digest != body_hash:
            raise HTTPException(409, "Für diese Bestellung liegt bereits eine Erklärung vor. Bitte den gespeicherten Beleg ansehen.")
        response.status_code = 200
        return projection(existing)
    current, identifier = int(now()), secrets.token_hex(16)
    value = snapshot(identifier, current, data.buyer_name, email, order.payment_reference)
    timely = within_standard_window(order, current)
    row = OrderWithdrawal(id=identifier, order_id=order.id, owner_user_id=p.user.id,
        received=current, effective_received=current, verified=True, hold_payment=timely,
        status="received_verified" if timely else "review_required", encrypted_declaration=encrypt(json.dumps(value)),
        request_digest=body_hash, idempotency=key)
    db.add(row)
    cancel_if_certainly_unpaid(db, order, timely)
    audit(db, p.user.id, "withdrawal.owner_received", identifier)
    db.commit()
    send_receipt(db, OrderWithdrawal, identifier)
    db.refresh(row)
    return projection(row)


@router.get("/orders/{order_id}/withdrawal")
def get_owner(order_id: str, p=Depends(parent), db=Depends(get_db)):
    order = owned_order(db, p, order_id)
    row = db.scalar(select(OrderWithdrawal).where(OrderWithdrawal.order_id == order.id))
    return {"withdrawal": projection(row) if row else None}


@router.post("/withdrawals/public", status_code=201)
def submit_public(data: PublicRequest, request: Request, response: Response, db=Depends(get_db)):
    # No order/family/user lookup in this route. Hashes are used only for limits.
    email = str(data.contact_email).casefold()
    ip = request.client.host if request.client else "unknown"
    rate_limit(db, "withdraw-public-global", 100, 3600)
    rate_limit(db, "withdraw-public-ip:" + digest(ip), 10, 3600)
    rate_limit(db, "withdraw-public-email:" + digest(email), 3, 3600)
    key = "public:" + digest(data.request_key)
    body_hash = payload_digest({"buyer_name": data.buyer_name, "contact_email": email,
                                "order_reference": data.order_reference})
    identifier, current = secrets.token_hex(16), int(now())
    value = snapshot(identifier, current, data.buyer_name, email, data.order_reference)
    insert_ignore(db, PublicWithdrawal, {
        "id": identifier, "received": current, "reference_digest": digest(data.order_reference),
        "email_digest": digest(email), "encrypted_declaration": encrypt(json.dumps(value)),
        "request_digest": body_hash, "idempotency": key,
        "mail_status": "pending", "status": "received_unverified", "identity_verified": False,
    }, key="idempotency")
    row = db.scalar(select(PublicWithdrawal).where(PublicWithdrawal.idempotency == key))
    if row.request_digest != body_hash:
        raise HTTPException(409, "Dieser Vorgangsschlüssel wurde bereits für eine andere Erklärung verwendet.")
    created = row.id == identifier
    if created:
        audit(db, "public-withdrawal", "withdrawal.public_received_unverified", row.id)
    db.commit()
    if created:
        send_receipt(db, PublicWithdrawal, row.id)
    else:
        response.status_code = 200
    db.refresh(row)
    return projection(row, public=True)


@router.get("/admin/withdrawals")
def admin_list(status: Literal["received_unverified", "received_verified", "review_required", "linked_verified"] | None = None,
               limit: int = Query(25, ge=1, le=50),
               before: str | None = Query(None, max_length=60, pattern=r"^[0-9]{1,12}:[a-f0-9]{32}$"),
               p=Depends(admin), db=Depends(get_db)):
    # Adult declaration fields only. No learning data or family/child names.
    items = []
    for model, source in ((PublicWithdrawal, "public"), (OrderWithdrawal, "owner")):
        query = select(model)
        if status:
            query = query.where(model.status == status)
        if before is not None:
            stamp, identifier = before.split(":")
            query = query.where(or_(model.received < int(stamp),
                and_(model.received == int(stamp), model.id < identifier)))
        for row in db.scalars(query.order_by(model.received.desc(), model.id.desc()).limit(limit + 1)):
            item = projection(row, private=True)
            item["source"] = source
            items.append(item)
    items.sort(key=lambda item: (item["received_at"], item["id"]), reverse=True)
    has_more = len(items) > limit
    items = items[:limit]
    audit(db, p.user.id, "withdrawal.admin_list", "contract-declarations")
    db.commit()
    return {"items": items, "next_before": f"{items[-1]['received_at']}:{items[-1]['id']}" if has_more else None}


@router.post("/admin/withdrawals/{public_id}/link")
def link_public(public_id: str, data: LinkRequest, p=Depends(admin), db=Depends(get_db)):
    rate_limit(db, "withdraw-link:" + p.user.id, 30, 3600)
    public = db.get(PublicWithdrawal, public_id)
    reference = data.order_reference.strip()
    if not public or public.reference_digest != digest(reference):
        raise HTTPException(409, "Erklärung und ausdrücklich geprüfte Bestellreferenz stimmen nicht überein.")
    order = db.scalar(select(BankOrder).where(BankOrder.payment_reference == reference))
    if not order:
        raise HTTPException(404, "Keine passende Bestellung zur geprüften Referenz gefunden.")
    order_id = order.id
    if order.family_id:
        db.execute(update(Family).where(Family.id == order.family_id).values(child_limit=Family.child_limit))
    db.expire_all()
    checked_principal(db, p, "admin")
    order = db.scalar(select(BankOrder).where(BankOrder.id == order_id).with_for_update())
    public = db.scalar(select(PublicWithdrawal).where(PublicWithdrawal.id == public_id).with_for_update())
    if not order or not public or public.reference_digest != digest(reference) or order.payment_reference != reference:
        raise HTTPException(409, "Der zu prüfende Vorgang wurde geändert. Bitte neu laden.")
    if public.linked_order_id and public.linked_order_id != order.id:
        raise HTTPException(409, "Die Erklärung ist bereits einer anderen Bestellung zugeordnet.")
    if order.family_id and db.get(Family, order.family_id).synthetic:
        raise HTTPException(403, "Im Testraum werden keine Vertragswiderrufe zugeordnet.")
    existing = db.scalar(select(OrderWithdrawal).where(OrderWithdrawal.order_id == order.id))
    timely = within_standard_window(order, public.received)
    if not public.identity_verified:
        public.identity_verified = True
        public.reviewed, public.reviewed_by = int(now()), p.user.id
        public.linked_order_id = order.id
        public.status = "linked_verified" if timely else "review_required"
        if existing:
            existing.verified = True
            existing.effective_received = min(existing.effective_received, public.received)
            existing.hold_payment = existing.hold_payment or timely
            if existing.hold_payment:
                existing.status = "received_verified"
            if not existing.public_declaration_id:
                existing.public_declaration_id = public.id
        else:
            existing = OrderWithdrawal(order_id=order.id, received=public.received,
                effective_received=public.received, verified=True, hold_payment=timely,
                status="received_verified" if timely else "review_required",
                encrypted_declaration=public.encrypted_declaration, request_digest=public.request_digest,
                idempotency="public-linked:" + public.id, public_declaration_id=public.id,
                mail_status=public.mail_status)
            db.add(existing)
        cancel_if_certainly_unpaid(db, order, timely)
        audit(db, p.user.id, "withdrawal.public_identity_verified", public.id)
        audit(db, p.user.id, "withdrawal.verified_link", order.id)
        db.commit()
    return {"public_id": public.id, "status": public.status, "identity_verified": True,
            "payment_hold": payment_hold(db, order.id), "refund_executed": False,
            "notice": "Geprüfte Zuordnung gespeichert. Eine Rückzahlung wurde nicht ausgelöst."}


def withdrawals_export(db, family_id):
    """Caller checks family-owner authorization; never part of a child export."""
    ids = select(BankOrder.id).where(BankOrder.family_id == family_id)
    return [{"order_id": row.order_id, "source": "owner", **projection(row, private=True)}
            for row in db.scalars(select(OrderWithdrawal).where(OrderWithdrawal.order_id.in_(ids)))] + [
                {"order_id": row.linked_order_id, "source": "public", **projection(row, private=True)}
                for row in db.scalars(select(PublicWithdrawal).where(PublicWithdrawal.linked_order_id.in_(ids)))]


def erase_family_withdrawals(db, family_id):
    """Match the order ledger: paid AND potentially charged attempts survive."""
    from .payment_models import PaymentAttempt

    attempted = select(PaymentAttempt.order_id)
    unpaid = select(BankOrder.id).where(BankOrder.family_id == family_id,
                                      BankOrder.status.not_in(["paid", "refunded"]), BankOrder.id.not_in(attempted))
    db.execute(delete(PublicWithdrawal).where(PublicWithdrawal.linked_order_id.in_(unpaid)))
    db.execute(delete(OrderWithdrawal).where(OrderWithdrawal.order_id.in_(unpaid)))
    paid = select(BankOrder.id).where(BankOrder.family_id == family_id,
                                    or_(BankOrder.status.in_(["paid", "refunded"]), BankOrder.id.in_(attempted)))
    db.execute(update(OrderWithdrawal).where(OrderWithdrawal.order_id.in_(paid)).values(owner_user_id=None))


def maintenance(db):
    from .payment_models import PaymentAttempt

    paid = select(BankOrder.id).where(or_(BankOrder.status.in_(["paid", "refunded"]),
                                        BankOrder.id.in_(select(PaymentAttempt.order_id))))
    db.execute(delete(PublicWithdrawal).where(PublicWithdrawal.received < now() - 365 * DAY,
        (PublicWithdrawal.linked_order_id.is_(None)) | (PublicWithdrawal.linked_order_id.not_in(paid))))
