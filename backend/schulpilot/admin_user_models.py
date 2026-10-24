"""Metadata-only admin operation receipts; no private learning payloads."""

from sqlalchemy import JSON, Column, ForeignKey, Integer, String, UniqueConstraint

from .db import Base, now, uid


class AdminUserVersion(Base):
    __tablename__ = "admin_user_versions"
    user_id = Column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    revision = Column(Integer, nullable=False, default=1)


class AdminUserOperation(Base):
    __tablename__ = "admin_user_operations"
    id = Column(String(32), primary_key=True, default=uid)
    actor_id = Column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    session_id = Column(ForeignKey("sessions.id", ondelete="CASCADE"), nullable=False)
    # Not an FK: the minimal receipt must survive successful target deletion.
    target_id = Column(String(32), nullable=False)
    request_key = Column(String(80), nullable=False)
    action = Column(String(24), nullable=False)
    request_digest = Column(String(64), nullable=False)
    result = Column(JSON, nullable=False)
    created = Column(Integer, nullable=False, default=lambda: int(now()))
    expires = Column(Integer, nullable=False, index=True)
    __table_args__ = (UniqueConstraint("actor_id", "request_key", name="uq_admin_user_operation_key"),)
