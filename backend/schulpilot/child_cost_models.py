"""Explicit operator limits and auditable monetary balances; no learning data."""

from sqlalchemy import JSON, BigInteger, Boolean, Column, ForeignKey, Index, Integer, String, UniqueConstraint

from .db import Base, now, uid


class ChildCostControl(Base):
    __tablename__ = "child_cost_controls"
    child_id = Column(String(32), ForeignKey("children.id", ondelete="CASCADE"), primary_key=True)
    revision = Column(Integer, nullable=False, default=1)
    enabled = Column(Boolean, nullable=False, default=True)
    timezone = Column(String(64), nullable=False)
    daily_limit_eur_micros = Column(BigInteger)
    monthly_limit_eur_micros = Column(BigInteger)
    updated = Column(Integer, nullable=False, default=lambda: int(now()))


class ChildCostControlChange(Base):
    __tablename__ = "child_cost_control_changes"
    id = Column(String(32), primary_key=True, default=uid)
    child_id = Column(String(32), ForeignKey("children.id", ondelete="CASCADE"), nullable=False)
    actor_id = Column(String(32), ForeignKey("users.id", ondelete="SET NULL"))
    request_key = Column(String(80), nullable=False)
    digest = Column(String(64), nullable=False)
    revision = Column(Integer, nullable=False)
    policy = Column(JSON, nullable=False)
    created = Column(Integer, nullable=False, default=lambda: int(now()))
    __table_args__ = (UniqueConstraint("child_id", "request_key", name="uq_child_cost_control_request"),)


class UsageCostBalance(Base):
    __tablename__ = "usage_cost_balances"
    usage_id = Column(String(32), ForeignKey("usage.id", ondelete="CASCADE"), primary_key=True)
    child_id = Column(String(32), ForeignKey("children.id", ondelete="CASCADE"), nullable=False)
    created = Column(Integer, nullable=False)
    provider_eur_micros = Column(BigInteger)
    fee_known_eur_micros = Column(BigInteger)
    fee_reserved_eur_micros = Column(BigInteger, nullable=False)
    held_eur_micros = Column(BigInteger, nullable=False)
    accounted_eur_micros = Column(BigInteger, nullable=False)
    fee_state = Column(String(32), nullable=False)
    fx_snapshot = Column(JSON, nullable=False)
    fee_basis_usd_micros = Column(BigInteger)
    __table_args__ = (Index("ix_cost_balances_child_created", "child_id", "created"),)
