"""Prepaid family access. Only a recorded manual bank check grants access."""

import json
import re
import secrets
from datetime import date, datetime, timezone
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import PlainTextResponse
from pydantic import Field, model_validator
from sqlalchemy import delete, func, select, update
from sqlalchemy.exc import IntegrityError

from . import schemas as s
from .config import runtime_settings
from .db import BankOrder, Child, Family, StoreConfiguration, get_db, now
from .security import admin, audit, decrypt, digest, encrypt, family_access, insert_ignore, parent, rate_limit

router = APIRouter(tags=["Verkauf"])
TERMS_VERSION = "2026-10-14.1"
DAY = 86400
DEFAULT_PLANS = [
    {"id": "start", "name": "Start", "price_cents": 990, "children": 1, "calls": 300},
    {"id": "familie", "name": "Familie", "price_cents": 1490, "children": 3, "calls": 900},
    {"id": "familie-plus", "name": "Familie Plus", "price_cents": 2490, "children": 5, "calls": 1800},
]


class Plan(s.Strict):
    id: str = Field(pattern=r"^[a-z][a-z0-9-]{1,29}$")
    name: str = Field(min_length=1, max_length=40)
    price_cents: int = Field(ge=100, le=25000)
    children: int = Field(ge=1, le=20)
    calls: int = Field(ge=10, le=10000)


class StoreSettings(s.Strict):
    enabled: bool = False
    recipient: str = Field(default="", max_length=160)
    iban: str = Field(default="", max_length=40)
    bank_name: str = Field(default="", max_length=160)
    tax_mode: Literal["unconfirmed", "small_business", "standard19"] = "unconfirmed"
    plans: list[Plan] = Field(default_factory=lambda: [Plan(**p) for p in DEFAULT_PLANS], min_length=1, max_length=6)

    @model_validator(mode="after")
    def validate_bank(self):
        self.iban = re.sub(r"\s+", "", self.iban).upper()
        if self.iban:
            if not re.fullmatch(r"[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}", self.iban):
                raise ValueError("Bitte eine gültige IBAN eintragen.")
            digits = "".join(str(ord(c) - 55) if c.isalpha() else c for c in self.iban[4:] + self.iban[:4])
            if int(digits) % 97 != 1:
                raise ValueError("Die IBAN-Prüfsumme stimmt nicht.")
        if len({p.id for p in self.plans}) != len(self.plans):
            raise ValueError("Tarifkennungen müssen eindeutig sein.")
        return self


class StoreUpdate(StoreSettings):
    revision: int = Field(ge=0)


def store(db):
    row = db.get(StoreConfiguration, 1, populate_existing=True)
    return (StoreSettings(**json.loads(decrypt(row.encrypted_config))), row.revision) if row else (StoreSettings(), 0)


def prerequisites(db, config):
    site = runtime_settings(db)
    missing = []
    if not all((site.operator_name, site.operator_address, site.operator_support_email)):
        missing.append("Vollständige Betreiberangaben")
    if not (config.recipient and config.iban):
        missing.append("Kontoinhaber und geprüfte IBAN")
    if config.tax_mode == "unconfirmed":
        missing.append("Bestätigte Umsatzsteuerbehandlung")
    if not site.mail_ready:
        missing.append("E-Mail-Versand für Bestellbestätigungen")
    return missing


def tax_notice(mode):
    return (
        "Endpreise inklusive 19 % Umsatzsteuer."
        if mode == "standard19"
        else "Endpreise. Gemäß § 19 UStG wird keine Umsatzsteuer berechnet."
        if mode == "small_business"
        else "Der Verkauf wird vorbereitet. Die Steuerangaben sind noch zu bestätigen."
    )


def contract_text(seller):
    return f"""SCHULPILOT – Vertragsbedingungen {TERMS_VERSION}
Anbieter: {seller["name"]}
Anschrift: {seller["address"]}
Kontakt: {seller["email"]}

Leistung: Nutzung der SCHULPILOT-Lernplattform für die im bestellten Tarif angegebene Kinderanzahl und die enthaltenen KI-Schritte. Ein KI-Schritt ist ein einzelner Erkennungs-, Aufgaben- oder Lernhilfe-Aufruf, einschließlich ausdrücklich erneut angeforderter Versuche. Bei fehlgeschlagenen Aufrufen mit unbekanntem Verbrauch bleibt die Reservierung angerechnet. Gespeicherte Lerninhalte bleiben nach Ende der Laufzeit im Konto erreichbar. Uploads, Antworten und vorhandene Erklärungen sind keine zusätzlichen KI-Schritte. KI-Ausgaben können Fehler enthalten und werden nicht als Noten- oder Lernerfolgsgarantie verkauft. Die Verfügbarkeit externer KI-Anbieter kann schwanken; es gibt keinen heimlichen Modellwechsel.

Der Gesamtpreis und der Leistungsumfang werden vor der Bestellung angezeigt. Zahlung ausschließlich per Überweisung mit dem angegebenen Verwendungszweck. Die Bestellung wird mit der gespeicherten Bestellbestätigung angenommen. Nach Prüfung des tatsächlichen Zahlungseingangs aktiviert der Anbieter den Zugang manuell. Die Laufzeit beträgt 30 Tage ab Beginn; keine automatische Verlängerung, keine wiederkehrende Abbuchung. Bei Verlängerung desselben Tarifs beginnt der neue Zeitraum nach dem bisherigen. Ein Tarifwechsel während einer laufenden oder vorgemerkten Laufzeit erfolgt erst nach deren Ende. Die enthaltenen KI-Schritte gelten pro bezahltem Zeitraum und werden nicht angesammelt.

Ohne ausdrücklichen Wunsch nach vorzeitigem Beginn startet die Leistung frühestens 14 Tage nach Vertragsabschluss und erst nach Zahlungsprüfung. Bei gewünschtem vorzeitigem Beginn kann der Zugang nach Zahlungsprüfung früher beginnen. Gesetzliche Mängel- und Verbraucherrechte bleiben bestehen.

Widerrufsbelehrung: Sie haben das Recht, binnen vierzehn Tagen ohne Angabe von Gründen diesen Vertrag zu widerrufen. Die Widerrufsfrist beträgt vierzehn Tage ab dem Tag des Vertragsabschlusses. Um Ihr Widerrufsrecht auszuüben, müssen Sie uns unter den oben genannten Kontaktdaten mittels einer eindeutigen Erklärung, etwa per E-Mail oder Brief, über Ihren Entschluss informieren. Zur Wahrung der Frist genügt die rechtzeitige Absendung. Bei Widerruf erstatten wir erhaltene Zahlungen unverzüglich, spätestens binnen vierzehn Tagen nach Eingang der Erklärung, mit demselben Zahlungsmittel, sofern nichts anderes ausdrücklich vereinbart wurde; es entstehen keine Erstattungsgebühren. Haben Sie einen Beginn während der Widerrufsfrist verlangt, ist für bis zum Widerruf auf Ihren Wunsch erbrachte Leistungen ein angemessener anteiliger Betrag zu zahlen. Eine Erstattung wird vom Anbieter geprüft und ausgeführt; die App löst keine Banküberweisung aus.

Muster-Widerrufsformular: An {seller["name"]}, {seller["address"]}, {seller["email"]}: Hiermit widerrufe ich den von mir abgeschlossenen Vertrag über die Nutzung von SCHULPILOT. Bestellt am: __. Bestellnummer: __. Name: __. Anschrift: __. Datum: __. Unterschrift (nur bei Papier): __.
"""


def seller_data(db, config):
    site = runtime_settings(db)
    return {
        "name": site.operator_name,
        "address": site.operator_address,
        "email": site.operator_support_email,
        "tax_mode": config.tax_mode,
        "tax_notice": tax_notice(config.tax_mode),
    }


@router.get("/store/catalog")
def catalog(db=Depends(get_db)):
    config, revision = store(db)
    return {
        "enabled": config.enabled and not prerequisites(db, config),
        "revision": revision,
        "currency": "EUR",
        "duration_days": 30,
        "auto_renew": False,
        "plans": [p.model_dump() for p in config.plans],
        "tax_notice": tax_notice(config.tax_mode),
        "terms_version": TERMS_VERSION,
        "terms": contract_text(seller_data(db, config)),
    }


@router.get("/admin/store")
def admin_store(p=Depends(admin), db=Depends(get_db)):
    config, revision = store(db)
    audit(db, p.user.id, "store.settings_read", "store")
    db.commit()
    return {**config.model_dump(), "revision": revision, "missing": prerequisites(db, config)}


@router.put("/admin/store")
def update_store(data: StoreUpdate, p=Depends(admin), db=Depends(get_db)):
    config = StoreSettings(**data.model_dump(exclude={"revision"}))
    if config.enabled and prerequisites(db, config):
        raise HTTPException(422, "Verkauf kann noch nicht starten: " + ", ".join(prerequisites(db, config)))
    insert_ignore(db, StoreConfiguration, {"id": 1, "encrypted_config": encrypt("{}"), "revision": 0})
    result = db.execute(
        update(StoreConfiguration)
        .where(StoreConfiguration.id == 1, StoreConfiguration.revision == data.revision)
        .values(
            encrypted_config=encrypt(config.model_dump_json()),
            revision=data.revision + 1,
            ever_enabled=True if config.enabled else StoreConfiguration.ever_enabled,
        )
    )
    if not result.rowcount:
        raise HTTPException(409, "Verkaufseinstellungen wurden geändert. Bitte neu laden.")
    audit(db, p.user.id, "store.settings_update", "store")
    db.commit()
    return {"revision": data.revision + 1, "message": "Verkaufseinstellungen gespeichert."}


def current_order(db, family, current=None):
    current = int(now()) if current is None else current
    return db.scalar(
        select(BankOrder)
        .where(
            BankOrder.family_id == family.id,
            BankOrder.status == "paid",
            BankOrder.starts <= current,
            BankOrder.ends > current,
        )
        .order_by(BankOrder.starts.desc())
        .limit(1)
    )


def access(db, family):
    if not family.commerce_required:
        return {"state": "existing", "plan": family.plan, "starts": None, "ends": None}
    order = current_order(db, family)
    if order:
        return {"state": "active", "plan": order.offer["name"], "starts": order.starts, "ends": order.ends}
    future = db.scalar(
        select(BankOrder)
        .where(BankOrder.family_id == family.id, BankOrder.status == "paid", BankOrder.starts > now())
        .order_by(BankOrder.starts)
        .limit(1)
    )
    return {
        "state": "scheduled" if future else "inactive",
        "plan": future.offer["name"] if future else family.plan,
        "starts": future.starts if future else None,
        "ends": future.ends if future else None,
    }


def usage_terms(db, family, *, enforce=False):
    period = datetime.now(timezone.utc).strftime("%Y-%m")
    if not family.commerce_required:
        return f"{family.id}:{period}", family.call_limit, family.budget_micros
    order = current_order(db, family)
    if not order:
        if enforce:
            raise HTTPException(
                403,
                "Neue KI-Lerneinheiten sind gerade nicht freigeschaltet. Deine gespeicherten Inhalte bleiben da. Bitte sprich mit deinen Eltern.",
            )
        return f"{family.id}:inactive", 0, 0
    return f"{family.id}:paid:{order.id}", order.offer["calls"], order.offer["budget_micros"]


def order_data(row, *, private=True):
    fields = (
        "id",
        "payment_reference",
        "status",
        "amount_cents",
        "offer",
        "early_start",
        "created",
        "starts",
        "ends",
        "checked_at",
        "mail_status",
    )
    result = {k: getattr(row, k) for k in fields}
    if private:
        result.update(bank=row.bank, seller=row.seller, terms=row.terms, terms_version=row.terms_version)
    return result


def orders_export(db, family_id):
    return [order_data(row) for row in db.scalars(select(BankOrder).where(BankOrder.family_id == family_id))]


class OrderCreate(s.Strict):
    plan_id: str = Field(max_length=30)
    catalog_revision: int = Field(ge=0)
    request_key: str = Field(min_length=16, max_length=60, pattern=r"^[A-Za-z0-9_-]+$")
    accept_terms: Literal[True]
    early_start: bool = False


@router.get("/families/{family_id}/orders")
def orders(family_id: str, p=Depends(parent), db=Depends(get_db)):
    family, membership = family_access(db, p, family_id)
    if membership.permission != "owner":
        raise HTTPException(403, "Bestellungen verwaltet der Inhaber des Familienkontos.")
    return {
        "access": access(db, family),
        "orders": [
            order_data(o)
            for o in db.scalars(
                select(BankOrder).where(BankOrder.family_id == family.id).order_by(BankOrder.created.desc()).limit(100)
            )
        ],
    }


@router.post("/families/{family_id}/orders", status_code=201)
def create_order(family_id: str, data: OrderCreate, p=Depends(parent), db=Depends(get_db)):
    family, _ = family_access(db, p, family_id, owner=True)
    if family.synthetic:
        raise HTTPException(
            403, "Im Testraum sind keine Käufe möglich. Bitte zuerst ein eigenes Elternkonto erstellen."
        )
    rate_limit(db, "orders:" + p.user.id, 10, 3600)
    db.execute(update(Family).where(Family.id == family.id).values(child_limit=Family.child_limit))
    key = family.id + ":" + data.request_key
    existing = db.scalar(select(BankOrder).where(BankOrder.idempotency == key))
    if existing:
        return order_data(existing)
    config, revision = store(db)
    if not config.enabled or prerequisites(db, config):
        raise HTTPException(503, "Bestellungen sind noch nicht freigegeben.")
    if revision != data.catalog_revision:
        raise HTTPException(409, "Die Tarife wurden geändert. Bitte prüfe den aktuellen Gesamtpreis.")
    plan = next((item for item in config.plans if item.id == data.plan_id), None)
    if not plan:
        raise HTTPException(404, "Tarif nicht gefunden.")
    count = db.scalar(select(func.count()).select_from(Child).where(Child.family_id == family.id))
    if count > plan.children:
        raise HTTPException(409, "Dieser Tarif bietet zu wenige Kinderzugänge für deine Familie.")
    if db.scalar(select(BankOrder.id).where(BankOrder.pending_slot == family.id)):
        raise HTTPException(409, "Es gibt bereits eine offene Bestellung. Du findest sie unter Tarif & Bestellungen.")
    remaining = db.scalar(
        select(BankOrder)
        .where(BankOrder.family_id == family.id, BankOrder.status == "paid", BankOrder.ends > now())
        .order_by(BankOrder.ends.desc())
        .limit(1)
    )
    if remaining and remaining.offer["id"] != plan.id:
        raise HTTPException(409, "Während einer laufenden Laufzeit ist nur die Verlängerung desselben Tarifs möglich.")
    offer = {**plan.model_dump(), "duration_days": 30, "budget_micros": 5_000_000}
    seller = seller_data(db, config)
    row = BankOrder(
        family_id=family.id,
        buyer_id=p.user.id,
        idempotency=key,
        payment_reference="SCH-" + secrets.token_hex(6).upper(),
        amount_cents=plan.price_cents,
        offer=offer,
        seller=seller,
        bank={"recipient": config.recipient, "iban": config.iban, "name": config.bank_name},
        terms=contract_text(seller),
        early_start=data.early_start,
        pending_slot=family.id,
    )
    db.add(row)
    db.flush()
    audit(db, p.user.id, "order.created", row.id)
    db.commit()
    send_confirmation(db, row, p.user.email)
    return order_data(row)


def receipt(row):
    bank = row.bank
    return f"""SCHULPILOT – Bestellbestätigung
Bestellnummer / Verwendungszweck: {row.payment_reference}
Bestellt am: {datetime.fromtimestamp(row.created, timezone.utc).isoformat()}
Tarif: {row.offer["name"]} · {row.offer["children"]} Kinderzugänge · {row.offer["calls"]} KI-Schritte
Laufzeit: 30 Tage, keine automatische Verlängerung
Gesamtpreis: {row.amount_cents / 100:.2f} EUR
{row.seller["tax_notice"]}
Empfänger: {bank["recipient"]}
IBAN: {bank["iban"]}
Bank: {bank["name"]}
Bitte innerhalb von 14 Tagen überweisen. Erst nach manueller Prüfung des Zahlungseingangs wird freigeschaltet.
Vorzeitiger Beginn ausdrücklich gewünscht: {"Ja" if row.early_start else "Nein"}
Status: {row.status}

{row.terms}
"""


def send_confirmation(db, row, email):
    from .mail import send_message

    try:
        send_message(email, "SCHULPILOT: Bestellbestätigung " + row.payment_reference, receipt(row))
        row.mail_status = "accepted"
    except HTTPException:
        row.mail_status = "failed"
    db.commit()


def owned_order(db, p, order_id):
    row = db.get(BankOrder, order_id)
    if not row or not row.family_id:
        raise HTTPException(404, "Bestellung nicht gefunden.")
    family_access(db, p, row.family_id, owner=True)
    return row


@router.get("/orders/{order_id}/confirmation", response_class=PlainTextResponse)
def confirmation(order_id: str, p=Depends(parent), db=Depends(get_db)):
    return PlainTextResponse(receipt(owned_order(db, p, order_id)))


@router.post("/orders/{order_id}/resend")
def resend(order_id: str, p=Depends(parent), db=Depends(get_db)):
    row = owned_order(db, p, order_id)
    rate_limit(db, "order-mail:" + p.user.id, 3, 3600)
    send_confirmation(db, row, p.user.email)
    return {"mail_status": row.mail_status}


@router.post("/orders/{order_id}/cancel")
def cancel(order_id: str, p=Depends(parent), db=Depends(get_db)):
    row = owned_order(db, p, order_id)
    result = db.execute(
        update(BankOrder)
        .where(BankOrder.id == row.id, BankOrder.status == "awaiting_payment")
        .values(status="cancelled", pending_slot=None)
    )
    if not result.rowcount:
        raise HTTPException(
            409, "Die Bestellung wurde bereits bearbeitet. Bei Widerruf bitte den Anbieter kontaktieren."
        )
    audit(db, p.user.id, "order.cancelled", row.id)
    db.commit()
    return {"message": "Offene Bestellung storniert. Falls du schon überwiesen hast, kontaktiere bitte den Anbieter."}


@router.get("/admin/orders")
def admin_orders(p=Depends(admin), db=Depends(get_db)):
    audit(db, p.user.id, "order.list", "billing")
    db.commit()
    return [
        order_data(o, private=False)
        for o in db.scalars(select(BankOrder).order_by(BankOrder.created.desc()).limit(200))
    ]


class PaymentCheck(s.Strict):
    received_cents: int = Field(ge=1, le=100000)
    booking_date: date
    booking_reference: str = Field(min_length=6, max_length=160)
    bank_entry_checked: Literal[True]


@router.post("/admin/orders/{order_id}/approve")
def approve(order_id: str, data: PaymentCheck, p=Depends(admin), db=Depends(get_db)):
    rate_limit(db, "payment-check:" + p.user.id, 60, 3600)
    row = db.get(BankOrder, order_id)
    if not row or not row.family_id:
        raise HTTPException(404, "Bestellung nicht gefunden.")
    db.execute(update(Family).where(Family.id == row.family_id).values(child_limit=Family.child_limit))
    db.refresh(row)
    if row.status != "awaiting_payment":
        raise HTTPException(409, "Diese Bestellung wurde bereits bearbeitet.")
    if data.received_cents != row.amount_cents:
        raise HTTPException(
            422,
            "Der geprüfte Zahlungseingang muss dem Gesamtpreis entsprechen. Abweichungen zuerst außerhalb der App klären.",
        )
    if data.booking_date > datetime.now(timezone.utc).date():
        raise HTTPException(422, "Der Buchungstag darf nicht in der Zukunft liegen.")
    current = int(now())
    previous = db.scalar(
        select(BankOrder)
        .where(BankOrder.family_id == row.family_id, BankOrder.status == "paid", BankOrder.ends > current)
        .order_by(BankOrder.ends.desc())
        .limit(1)
    )
    if previous and previous.offer["id"] != row.offer["id"]:
        raise HTTPException(409, "Ein anderer Tarif ist noch aktiv. Erst nach Ende freischalten.")
    family = db.get(Family, row.family_id)
    if db.scalar(select(func.count()).select_from(Child).where(Child.family_id == family.id)) > row.offer["children"]:
        raise HTTPException(409, "Die Familie hat mehr Kinderzugänge als bestellt.")
    starts = max(current, previous.ends if previous else 0, 0 if row.early_start else row.created + 14 * DAY)
    # Unique bank digest prevents the same ledger transaction being used twice.
    booking = digest(data.booking_reference.strip().casefold())
    try:
        changed = db.execute(
            update(BankOrder)
            .where(BankOrder.id == row.id, BankOrder.status == "awaiting_payment")
            .values(
                status="paid",
                pending_slot=None,
                starts=starts,
                ends=starts + 30 * DAY,
                checked_at=current,
                checked_by=p.user.id,
                booking_digest=booking,
                booking_date=data.booking_date.isoformat(),
            )
        )
        if not changed.rowcount:
            raise HTTPException(409, "Diese Bestellung wurde bereits bearbeitet.")
        family.commerce_required = True
        family.plan = row.offer["name"]
        family.child_limit = row.offer["children"]
        family.call_limit = row.offer["calls"]
        family.budget_micros = row.offer["budget_micros"]
        audit(db, p.user.id, "order.payment_checked_and_activated", row.id)
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "Diese Bankbuchung wurde bereits einer Bestellung zugeordnet.") from None
    db.refresh(row)
    return order_data(row, private=False)


def erase_family_orders(db, family_id):
    """Keep only required paid accounting records, unlink all family identity."""
    db.execute(delete(BankOrder).where(BankOrder.family_id == family_id, BankOrder.status.not_in(["paid", "refunded"])))
    for row in db.scalars(select(BankOrder).where(BankOrder.family_id == family_id)):
        row.family_id, row.buyer_id, row.pending_slot = None, None, None
        row.idempotency = "erased:" + row.id


@router.post("/admin/orders/{order_id}/refund")
def record_refund(order_id: str, data: PaymentCheck, p=Depends(admin), db=Depends(get_db)):
    row = db.get(BankOrder, order_id)
    if not row:
        raise HTTPException(404, "Bestellung nicht gefunden.")
    if data.received_cents != row.amount_cents or data.booking_date > datetime.now(timezone.utc).date():
        raise HTTPException(
            422,
            "Eine vollständige, tatsächlich gebuchte Erstattung bestätigen. Teilbeträge bitte außerhalb der App klären.",
        )
    if row.family_id:
        db.execute(update(Family).where(Family.id == row.family_id).values(child_limit=Family.child_limit))
    try:
        changed = db.execute(
            update(BankOrder)
            .where(BankOrder.id == order_id, BankOrder.status == "paid")
            .values(
                status="refunded",
                revoked_at=int(now()),
                refund_digest=digest(data.booking_reference.strip().casefold()),
                refund_date=data.booking_date.isoformat(),
            )
        )
        if not changed.rowcount:
            raise HTTPException(409, "Diese Bestellung ist nicht als bezahlt erfasst.")
        audit(db, p.user.id, "order.external_refund_checked", order_id)
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "Diese Erstattungsbuchung wurde bereits zugeordnet.") from None
    return {
        "message": "Extern gebuchte Erstattung dokumentiert. Diese Laufzeit ist gesperrt. Die App hat keine Überweisung ausgelöst."
    }


def maintenance(db):
    # Eight years after the end of the booking year; never child content.
    cutoff = int(datetime(datetime.now(timezone.utc).year - 8, 1, 1, tzinfo=timezone.utc).timestamp())
    db.execute(
        delete(BankOrder).where(
            BankOrder.status.in_(["paid", "refunded"]),
            BankOrder.checked_at < cutoff,
            (BankOrder.revoked_at.is_(None)) | (BankOrder.revoked_at < cutoff),
        )
    )
    db.execute(delete(BankOrder).where(BankOrder.status == "cancelled", BankOrder.created < now() - 90 * DAY))
