"""Minimal provider payment ledgers; no card, child or raw webhook contents."""

from sqlalchemy import CheckConstraint, Column, ForeignKey, Integer, String, Text, UniqueConstraint

from .db import Base, now, uid


class PaymentConfiguration(Base):
    __tablename__ = "payment_configuration"
    id = Column(Integer, primary_key=True)
    revision = Column(Integer, nullable=False, default=0)
    encrypted_config = Column(Text, nullable=False)


class PaymentConfigurationRevision(Base):
    __tablename__ = "payment_configuration_revisions"
    revision = Column(Integer, primary_key=True)
    encrypted_config = Column(Text, nullable=False)


class PaymentAttempt(Base):
    __tablename__ = "payment_attempts"
    id = Column(String(32), primary_key=True, default=uid)
    order_id = Column(ForeignKey("bank_orders.id", ondelete="CASCADE"), nullable=False, unique=True)
    environment = Column(String(8), nullable=False)
    merchant_id = Column(String(64), nullable=False)
    config_revision = Column(Integer, nullable=False)
    method = Column(String(24), nullable=False)
    amount_cents = Column(Integer, nullable=False)
    currency = Column(String(3), nullable=False, default="EUR")
    status = Column(String(24), nullable=False, default="capture_pending")
    provider_order_id = Column(String(64))
    capture_id = Column(String(64))
    capture_started = Column(Integer)
    create_request_id = Column(String(36), nullable=False, unique=True)
    capture_request_id = Column(String(36), nullable=False, unique=True)
    refunded_cents = Column(Integer, nullable=False, default=0)
    created = Column(Integer, nullable=False, default=lambda: int(now()))
    updated = Column(Integer, nullable=False, default=lambda: int(now()))
    error_code = Column(String(40))
    __table_args__ = (
        UniqueConstraint("environment", "merchant_id", "provider_order_id", name="uq_payment_provider_order"),
        UniqueConstraint("environment", "merchant_id", "capture_id", name="uq_payment_capture"),
        CheckConstraint(
            "amount_cents > 0 AND refunded_cents >= 0 AND refunded_cents <= amount_cents", name="ck_payment_amounts"
        ),
        CheckConstraint("currency = 'EUR'", name="ck_payment_currency"),
        CheckConstraint("environment IN ('sandbox', 'live')", name="ck_payment_environment"),
    )


class PaymentEvent(Base):
    __tablename__ = "payment_events"
    id = Column(String(32), primary_key=True, default=uid)
    environment = Column(String(8), nullable=False)
    merchant_id = Column(String(64), nullable=False)
    event_id = Column(String(160), nullable=False)
    event_type = Column(String(80), nullable=False)
    body_sha256 = Column(String(64), nullable=False)
    payment_id = Column(ForeignKey("payment_attempts.id", ondelete="SET NULL"))
    result = Column(String(32), nullable=False, default="verified")
    created = Column(Integer, nullable=False, default=lambda: int(now()))
    __table_args__ = (UniqueConstraint("environment", "merchant_id", "event_id", name="uq_payment_webhook_event"),)


class PaymentRefund(Base):
    __tablename__ = "payment_refunds"
    id = Column(String(32), primary_key=True, default=uid)
    payment_id = Column(ForeignKey("payment_attempts.id", ondelete="CASCADE"), nullable=False)
    provider_refund_id = Column(String(64), nullable=False)
    amount_cents = Column(Integer, nullable=False)
    created = Column(Integer, nullable=False, default=lambda: int(now()))
    __table_args__ = (
        UniqueConstraint("payment_id", "provider_refund_id", name="uq_payment_refund"),
        CheckConstraint("amount_cents > 0", name="ck_payment_refund_amount"),
    )
