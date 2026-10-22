"""Encrypted adult contract declarations; never learning or refund evidence."""

from sqlalchemy import Boolean, Column, ForeignKey, Integer, String, Text

from .db import Base, now, uid


class OrderWithdrawal(Base):
    __tablename__ = "order_withdrawals"
    id = Column(String(32), primary_key=True, default=uid)
    order_id = Column(ForeignKey("bank_orders.id", ondelete="CASCADE"), nullable=False, unique=True)
    owner_user_id = Column(ForeignKey("users.id", ondelete="SET NULL"))
    received = Column(Integer, nullable=False, default=lambda: int(now()))
    effective_received = Column(Integer, nullable=False)
    verified = Column(Boolean, nullable=False, default=False)
    hold_payment = Column(Boolean, nullable=False, default=False)
    status = Column(String(24), nullable=False, default="review_required")
    encrypted_declaration = Column(Text, nullable=False)
    request_digest = Column(String(64), nullable=False)
    idempotency = Column(String(100), nullable=False, unique=True)
    mail_status = Column(String(16), nullable=False, default="pending")
    public_declaration_id = Column(String(32), unique=True)


class PublicWithdrawal(Base):
    __tablename__ = "public_withdrawals"
    id = Column(String(32), primary_key=True, default=uid)
    received = Column(Integer, nullable=False, default=lambda: int(now()), index=True)
    reference_digest = Column(String(64), nullable=False, index=True)
    email_digest = Column(String(64), nullable=False, index=True)
    encrypted_declaration = Column(Text, nullable=False)
    request_digest = Column(String(64), nullable=False)
    idempotency = Column(String(80), nullable=False, unique=True)
    mail_status = Column(String(16), nullable=False, default="pending")
    status = Column(String(24), nullable=False, default="received_unverified")
    identity_verified = Column(Boolean, nullable=False, default=False)
    reviewed = Column(Integer)
    reviewed_by = Column(ForeignKey("users.id", ondelete="SET NULL"))
    linked_order_id = Column(ForeignKey("bank_orders.id", ondelete="SET NULL"), index=True)
