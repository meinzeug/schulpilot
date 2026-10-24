import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    JSON,
    Boolean,
    CheckConstraint,
    Column,
    Float,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    create_engine,
    event,
    false,
    true,
)
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from .config import settings


def uid():
    return uuid.uuid4().hex


def now():
    return datetime.now(timezone.utc).timestamp()


class Base(DeclarativeBase):
    pass


class Family(Base):
    __tablename__ = "families"
    id = Column(String(32), primary_key=True, default=uid)
    name = Column(String(120), nullable=False)
    synthetic = Column(Boolean, default=False, nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)
    expires = Column(Integer)
    child_limit = Column(Integer, default=4, nullable=False)
    call_limit = Column(Integer, default=100, nullable=False)
    budget_micros = Column(Integer, default=2_000_000, nullable=False)
    plan = Column(String(40), default="Pilot", nullable=False)
    commerce_required = Column(Boolean, default=False, server_default=false(), nullable=False)


class StoreConfiguration(Base):
    __tablename__ = "store_configuration"
    id = Column(Integer, primary_key=True)
    encrypted_config = Column(Text, nullable=False)
    revision = Column(Integer, nullable=False, default=1)
    ever_enabled = Column(Boolean, nullable=False, default=False, server_default=false())
    ever_trial_enabled = Column(Boolean, nullable=False, default=False, server_default=false())


class FamilyTrial(Base):
    __tablename__ = "family_trials"
    family_id = Column(ForeignKey("families.id", ondelete="CASCADE"), primary_key=True)
    owner_user_id = Column(ForeignKey("users.id", ondelete="SET NULL"), index=True)
    created = Column(Integer, default=lambda: int(now()), nullable=False)
    starts = Column(Integer)
    ends = Column(Integer)
    child_limit = Column(Integer, nullable=False)
    call_limit = Column(Integer, nullable=False)
    budget_micros = Column(Integer, nullable=False)
    version = Column(String(40), default="verified-family-trial-1", nullable=False)
    __table_args__ = (
        CheckConstraint("child_limit >= 1 AND call_limit >= 0 AND budget_micros >= 0", name="ck_trial_limits"),
        CheckConstraint("(starts IS NULL AND ends IS NULL) OR (starts IS NOT NULL AND ends IS NOT NULL AND ends = starts + 2592000)", name="ck_trial_period"),
    )


class BankOrder(Base):
    __tablename__ = "bank_orders"
    id = Column(String(32), primary_key=True, default=uid)
    family_id = Column(ForeignKey("families.id", ondelete="SET NULL"), index=True)
    buyer_id = Column(ForeignKey("users.id", ondelete="SET NULL"))
    idempotency = Column(String(100), unique=True, nullable=False)
    payment_reference = Column(String(24), unique=True, nullable=False)
    payment_method = Column(String(24), nullable=False, default="bank_transfer", server_default="bank_transfer")
    currency = Column(String(3), nullable=False, default="EUR", server_default="EUR")
    request_digest = Column(String(64))
    status = Column(String(24), default="awaiting_payment", nullable=False)
    # NULL permits history; the unique family slot permits one open order.
    pending_slot = Column(String(32), unique=True)
    amount_cents = Column(Integer, nullable=False)
    offer = Column(JSON, nullable=False)
    seller = Column(JSON, nullable=False)
    bank = Column(JSON, nullable=False)
    terms = Column(Text, nullable=False)
    terms_version = Column(String(32), default="2026-10-14.1", nullable=False)
    early_start = Column(Boolean, default=False, nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)
    starts = Column(Integer)
    ends = Column(Integer)
    checked_at = Column(Integer)
    checked_by = Column(String(32))
    booking_digest = Column(String(64), unique=True)
    booking_date = Column(String(10))
    revoked_at = Column(Integer)
    refund_digest = Column(String(64), unique=True)
    refund_date = Column(String(10))
    mail_status = Column(String(16), default="pending", nullable=False)


class PushTestGrant(Base):
    __tablename__ = "push_test_grants"
    user_id = Column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    expires = Column(Integer, nullable=False)


class User(Base):
    __tablename__ = "users"
    id = Column(String(32), primary_key=True, default=uid)
    username = Column(String(254), unique=True, nullable=False)
    email = Column(String(254), unique=True)
    display_name = Column(String(80), nullable=False)
    password_hash = Column(Text, nullable=False)
    role = Column(String(16), nullable=False)
    verified = Column(Boolean, default=False, nullable=False)
    disabled = Column(Boolean, default=False, nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)


class UserAvatar(Base):
    __tablename__ = "user_avatars"
    user_id = Column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    revision = Column(String(32), nullable=False)
    image_digest = Column(String(64))
    updated = Column(Integer, nullable=False)
    request_key = Column(String(100), nullable=False)
    request_digest = Column(String(64), nullable=False)


class Installation(Base):
    __tablename__ = "installation"
    id = Column(Integer, primary_key=True)
    completed = Column(Boolean, default=False, nullable=False)
    bootstrap_digest = Column(String(64))
    bootstrap_expires = Column(Integer)
    encrypted_settings = Column(Text)
    revision = Column(Integer, default=1, nullable=False)
    completed_at = Column(Integer)


class OperatorJob(Base):
    __tablename__ = "operator_jobs"
    id = Column(String(32), primary_key=True, default=uid)
    actor = Column(String(32), nullable=False)
    config_revision = Column(Integer, nullable=False)
    status = Column(String(20), default="queued", nullable=False)
    report = Column(JSON, default=list, nullable=False)
    error = Column(String(500))
    created = Column(Integer, default=lambda: int(now()), nullable=False)
    started = Column(Integer)
    finished = Column(Integer)


class Membership(Base):
    __tablename__ = "memberships"
    id = Column(String(32), primary_key=True, default=uid)
    family_id = Column(ForeignKey("families.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    permission = Column(String(16), nullable=False)  # owner, manage, view
    __table_args__ = (UniqueConstraint("family_id", "user_id"),)


class Child(Base):
    __tablename__ = "children"
    id = Column(String(32), primary_key=True, default=uid)
    family_id = Column(ForeignKey("families.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, unique=True)
    grade = Column(Integer, nullable=False)
    subjects = Column(JSON, default=list, nullable=False)
    school_type = Column(String(80), default="", nullable=False)
    region = Column(String(80), default="", nullable=False)
    preferences = Column(JSON, default=dict, nullable=False)
    grade_planning_enabled = Column(Boolean, default=True, server_default=true(), nullable=False)
    parent_review_settings = Column(JSON, default=dict, server_default="{}", nullable=False)


class Subject(Base):
    __tablename__ = "subjects"
    id = Column(String(32), primary_key=True)
    key = Column(String(100), nullable=False, unique=True)
    title = Column(String(80), nullable=False)
    owner_family_id = Column(ForeignKey("families.id", ondelete="CASCADE"), index=True)
    cover_key = Column(String(100), nullable=False)
    active = Column(Boolean, default=True, nullable=False)
    sort_order = Column(Integer, default=100, nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)


class SubjectAlias(Base):
    __tablename__ = "subject_aliases"
    key = Column(String(64), primary_key=True)
    subject_id = Column(ForeignKey("subjects.id", ondelete="CASCADE"), nullable=False, index=True)
    family_id = Column(ForeignKey("families.id", ondelete="CASCADE"), index=True)
    normalized = Column(String(160), nullable=False)


class SubjectProvider(Base):
    __tablename__ = "subject_providers"
    provider = Column(String(24), primary_key=True)
    external_id = Column(String(100), primary_key=True)
    subject_id = Column(ForeignKey("subjects.id", ondelete="CASCADE"), nullable=False, index=True)
    data = Column(JSON, nullable=False)


class ChildSubject(Base):
    __tablename__ = "child_subjects"
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), primary_key=True)
    subject_id = Column(ForeignKey("subjects.id", ondelete="CASCADE"), primary_key=True)
    active = Column(Boolean, default=True, nullable=False)
    level_type = Column(String(16))
    level_number = Column(Integer)
    revision = Column(Integer, default=1, nullable=False)
    __table_args__ = (CheckConstraint("(level_type IS NULL AND level_number IS NULL) OR (level_type IS NOT NULL AND level_type IN ('klasse','lernjahr','vorschule') AND level_number IS NOT NULL AND level_number >= 0 AND level_number <= 20)", name="ck_child_subject_level"),)


class Session(Base):
    __tablename__ = "sessions"
    id = Column(String(32), primary_key=True, default=uid)
    user_id = Column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    token_hash = Column(String(64), unique=True, nullable=False)
    device = Column(String(100), nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)
    seen = Column(Integer, default=lambda: int(now()), nullable=False)
    expires = Column(Integer, nullable=False)
    revoked = Column(Boolean, default=False, nullable=False)


class Token(Base):
    __tablename__ = "tokens"
    id = Column(String(32), primary_key=True, default=uid)
    digest = Column(String(64), unique=True, nullable=False)
    purpose = Column(String(16), nullable=False)
    user_id = Column(ForeignKey("users.id", ondelete="CASCADE"))
    family_id = Column(ForeignKey("families.id", ondelete="CASCADE"))
    email = Column(String(254))
    permission = Column(String(16))
    expires = Column(Integer, nullable=False)
    used = Column(Boolean, default=False, nullable=False)


class GoogleIdentity(Base):
    __tablename__ = "google_identities"
    subject = Column(String(255), primary_key=True)
    user_id = Column(ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)


class GoogleFlow(Base):
    __tablename__ = "google_flows"
    id = Column(String(32), primary_key=True, default=uid)
    request_digest = Column(String(64), unique=True, nullable=False)
    state_digest = Column(String(64), unique=True)
    browser_digest = Column(String(64))
    nonce_digest = Column(String(64))
    encrypted_verifier = Column(Text)
    client_challenge = Column(String(43))
    ticket_digest = Column(String(64))
    platform = Column(String(8), nullable=False)
    intent = Column(String(8), nullable=False)
    previous_session_id = Column(ForeignKey("sessions.id", ondelete="CASCADE"))
    phase = Column(String(16), nullable=False)
    subject = Column(String(255))
    email = Column(String(254))
    failure = Column(String(32))
    email_authoritative = Column(Boolean, default=False, server_default=false(), nullable=False)
    expires = Column(Integer, nullable=False, index=True)


class PushDevice(Base):
    __tablename__ = "push_devices"
    id = Column(String(32), primary_key=True, default=uid)
    user_id = Column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    session_id = Column(ForeignKey("sessions.id", ondelete="CASCADE"), nullable=False, index=True)
    token_hash = Column(String(64), unique=True, nullable=False)
    encrypted_token = Column(Text, nullable=False)
    platform = Column(String(16), nullable=False)
    timezone = Column(String(64), nullable=False)
    quiet_start = Column(Integer, nullable=False)
    quiet_end = Column(Integer, nullable=False)
    reminders = Column(Boolean, default=True, nullable=False)
    help_requests = Column(Boolean, default=True, nullable=False)
    summaries = Column(Boolean, default=False, nullable=False)
    family_calls = Column(Boolean, default=False, server_default=false(), nullable=False)
    call_binding = Column(String(64))
    updated = Column(Integer, default=lambda: int(now()), nullable=False)


class PushDelivery(Base):
    __tablename__ = "push_deliveries"
    id = Column(String(32), primary_key=True, default=uid)
    device_id = Column(ForeignKey("push_devices.id", ondelete="CASCADE"), nullable=False, index=True)
    dedup_key = Column(String(160), unique=True, nullable=False)
    kind = Column(String(24), nullable=False)
    status = Column(String(24), default="queued", nullable=False)
    error_code = Column(String(80))
    created = Column(Integer, default=lambda: int(now()), nullable=False)
    sent = Column(Integer)


class NotificationRead(Base):
    """Only an acknowledgement; notification content stays in its source."""
    __tablename__ = "notification_reads"
    user_id = Column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    event_key = Column(String(80), primary_key=True)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    created = Column(Integer, default=lambda: int(now()), nullable=False)


class FamilyCall(Base):
    """Minimal family-call history. SDP, ICE candidates and media never persist."""
    __tablename__ = "family_calls"
    id = Column(String(32), primary_key=True, default=uid)
    family_id = Column(ForeignKey("families.id", ondelete="CASCADE"), nullable=False, index=True)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    caller_session_id = Column(ForeignKey("sessions.id", ondelete="CASCADE"), nullable=False)
    parent_session_id = Column(ForeignKey("sessions.id", ondelete="SET NULL"))
    parent_user_id = Column(ForeignKey("users.id", ondelete="SET NULL"))
    active_slot = Column(String(32), unique=True)
    parent_active_slot = Column(String(32), unique=True)
    idempotency = Column(String(64), unique=True, nullable=False)
    instance = Column(String(32), nullable=False)
    context_kind = Column(String(16), nullable=False)
    context_id = Column(String(32))
    status = Column(String(16), nullable=False, default="ringing")
    reason = Column(String(32))
    declined_users = Column(JSON, nullable=False, default=list)
    created = Column(Integer, nullable=False, default=lambda: int(now()))
    ring_expires = Column(Integer, nullable=False)
    expires = Column(Integer, nullable=False)
    caller_seen = Column(Integer, nullable=False)
    parent_seen = Column(Integer)
    accepted_at = Column(Integer)
    ended_at = Column(Integer)


class SchoolDay(Base):
    __tablename__ = "school_days"
    id = Column(String(32), primary_key=True, default=uid)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    school_date = Column(String(10), nullable=False)
    stage = Column(String(16), default="collecting", nullable=False)
    revision = Column(Integer, default=1, nullable=False)
    package_version = Column(Integer, default=0, server_default="0", nullable=False)
    learning_plan = Column(JSON, default=dict, server_default="{}", nullable=False)
    preparation = Column(JSON, default=dict, server_default="{}", nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)
    __table_args__ = (UniqueConstraint("child_id", "school_date"),)


class ErasureRequest(Base):
    __tablename__ = "erasure_requests"
    id = Column(String(32), primary_key=True, default=uid)
    scope = Column(String(16), nullable=False)
    target = Column(String(32), nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)
    published = Column(Boolean, default=False, server_default=false(), nullable=False)


class ServiceState(Base):
    __tablename__ = "service_state"
    name = Column(String(40), primary_key=True)
    updated = Column(Integer, nullable=False)


class Material(Base):
    __tablename__ = "materials"
    id = Column(String(32), primary_key=True, default=uid)
    purpose = Column(String(16), default="notebook", server_default="notebook", nullable=False)
    homework_state = Column(JSON, default=dict, server_default="{}", nullable=False)
    revision = Column(Integer, default=1, server_default="1", nullable=False)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    school_day_id = Column(ForeignKey("school_days.id", ondelete="SET NULL"), index=True)
    page_number = Column(Integer)
    upload_key = Column(String(80))
    image_digest = Column(String(64))
    quality_warnings = Column(JSON, default=list, server_default="[]", nullable=False)
    legibility = Column(String(16), default="unknown", server_default="unknown", nullable=False)
    title = Column(String(160), nullable=False)
    path = Column(String(80))
    status = Column(String(24), default="uploaded", nullable=False)
    subject = Column(String(80), default="", nullable=False)
    subject_id = Column(ForeignKey("subjects.id", ondelete="SET NULL"), index=True)
    topic = Column(String(160), default="", nullable=False)
    content = Column(Text, default="", nullable=False)
    uncertainties = Column(JSON, default=list, nullable=False)
    homework = Column(JSON, default=list, nullable=False)
    confirmed = Column(Boolean, default=False, nullable=False)
    source_blocks = Column(JSON, default=list, server_default="[]", nullable=False)
    confirmation_digest = Column(String(64))
    task_decisions = Column(JSON, server_default="[]", nullable=False)
    synthetic = Column(Boolean, default=False, nullable=False)
    fixture_id = Column(String(40))
    extraction_provider = Column(String(20), default="", server_default="", nullable=False)
    extraction_model = Column(String(160), default="", server_default="", nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)
    __table_args__ = (UniqueConstraint("child_id", "upload_key", name="uq_material_upload_key"),
                      Index("ix_materials_child_purpose", "child_id", "purpose", "created", "id"))


class Assignment(Base):
    __tablename__ = "assignments"
    id = Column(String(32), primary_key=True, default=uid)
    revision = Column(Integer, default=1, server_default="1", nullable=False)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    material_id = Column(ForeignKey("materials.id", ondelete="SET NULL"))
    kind = Column(String(24), nullable=False)  # parent, exam, homework, interest
    origin_kind = Column(String(24))
    source_key = Column(String(64))
    request_digest = Column(String(64))
    source_unit_id = Column(ForeignKey("learning_units.id", ondelete="SET NULL", use_alter=True, name="fk_assignment_source_unit"))
    source_revisions = Column(JSON, default=list, server_default="[]", nullable=False)
    source_status = Column(String(20), default="confirmed", server_default="confirmed", nullable=False)
    subject = Column(String(80), nullable=False)
    subject_id = Column(ForeignKey("subjects.id", ondelete="SET NULL"), index=True)
    topic = Column(String(160), nullable=False)
    note = Column(Text, default="", nullable=False)
    due = Column(String(10))
    scheduled_for = Column(String(10))
    mandatory = Column(Boolean, default=True, nullable=False)
    done = Column(Boolean, default=False, nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)
    __table_args__ = (Index("uq_assignment_source_key", "source_key", unique=True),)


class LearningUnit(Base):
    __tablename__ = "learning_units"
    id = Column(String(32), primary_key=True, default=uid)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    school_day_id = Column(ForeignKey("school_days.id", ondelete="SET NULL"), index=True)
    estimated_minutes = Column(Integer)
    package_version = Column(Integer)
    introduction_seen = Column(Boolean, default=False, server_default=false(), nullable=False)
    material_id = Column(ForeignKey("materials.id", ondelete="SET NULL"))
    assignment_id = Column(ForeignKey("assignments.id", ondelete="SET NULL"))
    subject = Column(String(80), nullable=False)
    subject_id = Column(ForeignKey("subjects.id", ondelete="SET NULL"), index=True)
    topic = Column(String(160), nullable=False)
    explanation = Column(Text, nullable=False)
    questions = Column(JSON, nullable=False)
    status = Column(String(20), default="not_started", nullable=False)
    synthetic = Column(Boolean, default=False, nullable=False)
    provider = Column(String(20), nullable=False)
    model = Column(String(160), default="", server_default="", nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)
    completed = Column(Integer)
    active_seconds = Column(Integer, default=0, nullable=False)
    segment_seconds = Column(Integer, default=0, server_default="0", nullable=False)
    break_until = Column(Integer)
    heartbeat = Column(Integer)
    review_of = Column(ForeignKey("learning_units.id", ondelete="SET NULL"))
    learning_root_id = Column(ForeignKey("learning_units.id", ondelete="SET NULL"), index=True)
    followup_of = Column(ForeignKey("learning_units.id", ondelete="SET NULL"))
    round_kind = Column(String(20), default="learning", server_default="learning", nullable=False)
    not_before = Column(String(10))
    goal_revision = Column(Integer)


class UnitCoaching(Base):
    __tablename__ = "unit_coaching"
    unit_id = Column(ForeignKey("learning_units.id", ondelete="CASCADE"), primary_key=True)
    job_id = Column(ForeignKey("jobs.id", ondelete="SET NULL"))
    status = Column(String(20), default="pending", nullable=False)
    decision = Column(String(24), default="", nullable=False)
    reason = Column(String(500), default="", nullable=False)
    report = Column(JSON, default=dict, nullable=False)
    next_unit_id = Column(ForeignKey("learning_units.id", ondelete="SET NULL"))
    next_review = Column(String(10))
    request_count = Column(Integer, default=0, nullable=False)
    provider = Column(String(20), default="", nullable=False)
    model = Column(String(160), default="", nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)


class UnitSource(Base):
    __tablename__ = "unit_sources"
    unit_id = Column(ForeignKey("learning_units.id", ondelete="CASCADE"), primary_key=True)
    material_id = Column(ForeignKey("materials.id", ondelete="CASCADE"), primary_key=True)
    revision = Column(Integer, nullable=False)


class SchoolGrade(Base):
    __tablename__ = "school_grades"
    id = Column(String(32), primary_key=True, default=uid)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    subject = Column(String(80), nullable=False)
    subject_id = Column(ForeignKey("subjects.id", ondelete="SET NULL"), index=True)
    topic = Column(String(160), default="", nullable=False)
    kind = Column(String(20), nullable=False)
    scale = Column(String(12), nullable=False)
    value = Column(Numeric(4, 2), nullable=False)
    weight = Column(Integer, default=1, nullable=False)
    assessed_on = Column(String(10))
    school_year_start = Column(Integer)
    semester = Column(Integer)
    note = Column(String(500), default="", nullable=False)
    assignment_id = Column(ForeignKey("assignments.id", ondelete="SET NULL"))
    request_key = Column(String(80))
    request_digest = Column(String(64))
    revision = Column(Integer, default=1, server_default="1", nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)
    updated = Column(Integer, default=lambda: int(now()), nullable=False)
    __table_args__ = (UniqueConstraint("child_id", "request_key", name="uq_grade_request"),
                     CheckConstraint("assessed_on IS NOT NULL OR (school_year_start IS NOT NULL AND semester IS NOT NULL AND semester IN (1,2))", name="ck_grade_known_period"))


class GradeImport(Base):
    __tablename__ = "grade_imports"
    id = Column(String(32), primary_key=True, default=uid)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    request_key = Column(String(80), nullable=False)
    file_digest = Column(String(64), nullable=False)
    school_year_start = Column(Integer, nullable=False)
    entries = Column(JSON, nullable=False)
    status = Column(String(16), nullable=False, default="preview")
    confirmation_digest = Column(String(64))
    result = Column(JSON)
    created = Column(Integer, default=lambda: int(now()), nullable=False, index=True)
    __table_args__ = (UniqueConstraint("child_id", "request_key", name="uq_grade_import_request"),)


class GradeSourceSlot(Base):
    __tablename__ = "grade_source_slots"
    id = Column(String(32), primary_key=True, default=uid)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    grade_id = Column(ForeignKey("school_grades.id", ondelete="SET NULL"), unique=True)
    slot_key = Column(String(64), nullable=False)
    school_year_start = Column(Integer, nullable=False)
    last_value = Column(String(20), nullable=False)
    ignored = Column(Boolean, default=False, nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)
    __table_args__ = (UniqueConstraint("child_id", "slot_key", name="uq_grade_source_slot"),)


class TutorTurn(Base):
    __tablename__ = "tutor_turns"
    id = Column(String(32), primary_key=True, default=uid)
    homework_context = Column(JSON)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    session_id = Column(ForeignKey("sessions.id", ondelete="SET NULL"))
    school_day_id = Column(ForeignKey("school_days.id", ondelete="CASCADE"))
    material_id = Column(ForeignKey("materials.id", ondelete="CASCADE"))
    unit_id = Column(ForeignKey("learning_units.id", ondelete="CASCADE"))
    reply_to = Column(ForeignKey("tutor_turns.id", ondelete="CASCADE"))
    question = Column(Text, nullable=False)
    status = Column(String(20), default="queued", nullable=False)
    reply = Column(JSON)
    error = Column(String(500))
    source_revisions = Column(JSON, default=list, nullable=False)
    job_id = Column(ForeignKey("jobs.id", ondelete="SET NULL"))
    created = Column(Integer, default=lambda: int(now()), nullable=False, index=True)


class ParentLearningReview(Base):
    __tablename__ = "parent_learning_reviews"
    id = Column(String(32), primary_key=True, default=uid)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    family_id = Column(ForeignKey("families.id", ondelete="CASCADE"), nullable=False)
    requested_by = Column(ForeignKey("users.id", ondelete="SET NULL"))
    job_id = Column(ForeignKey("jobs.id", ondelete="SET NULL"))
    signature = Column(String(64), nullable=False)
    observations = Column(JSON, default=dict, nullable=False)
    report = Column(JSON)
    status = Column(String(20), default="queued", nullable=False)
    error = Column(String(500))
    created = Column(Integer, default=lambda: int(now()), nullable=False)
    finished = Column(Integer)


class Attempt(Base):
    __tablename__ = "attempts"
    id = Column(String(32), primary_key=True, default=uid)
    unit_id = Column(ForeignKey("learning_units.id", ondelete="CASCADE"), nullable=False, index=True)
    question_id = Column(String(60), nullable=False)
    answer = Column(JSON, nullable=False)
    outcome = Column(String(20), nullable=False)
    assisted = Column(Boolean, default=False, nullable=False)
    request_key = Column(String(80))
    request_digest = Column(String(64))
    evaluation = Column(JSON)
    input_method = Column(String(12), default="typed", server_default="typed", nullable=False)
    created = Column(Float, default=now, nullable=False)
    __table_args__ = (UniqueConstraint("unit_id", "question_id", "id"),
                      Index("uq_attempt_request", "unit_id", "request_key", unique=True))


class AttemptAssessment(Base):
    """Append-only corrections; original answers, time and support never change."""

    __tablename__ = "attempt_assessments"
    id = Column(String(32), primary_key=True, default=uid)
    attempt_id = Column(ForeignKey("attempts.id", ondelete="CASCADE"), nullable=False, index=True)
    rules_version = Column(String(40), nullable=False)
    previous_outcome = Column(String(20), nullable=False)
    outcome = Column(String(20), nullable=False)
    previous_evaluation = Column(JSON)
    evaluation = Column(JSON, nullable=False)
    actor_id = Column(ForeignKey("users.id", ondelete="SET NULL"))
    created = Column(Float, default=now, nullable=False)
    __table_args__ = (UniqueConstraint("attempt_id", "rules_version"),)


class VocabularyCollection(Base):
    __tablename__ = "vocabulary_collections"
    id = Column(String(32), primary_key=True, default=uid)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    title = Column(String(160), nullable=False)
    target_locale = Column(String(12), nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)


class VocabularyItem(Base):
    __tablename__ = "vocabulary_items"
    id = Column(String(32), primary_key=True, default=uid)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    identity = Column(String(64), nullable=False)
    target_locale = Column(String(12), nullable=False)
    word = Column(String(200), nullable=False)
    meaning = Column(String(200), nullable=False)
    context = Column(String(500), default="", nullable=False)
    part_of_speech = Column(String(40), default="", nullable=False)
    variants = Column(JSON, default=list, nullable=False)
    meaning_variants = Column(JSON, default=list, nullable=False)
    source_revisions = Column(JSON, default=list, nullable=False)
    origin = Column(String(16), nullable=False)
    revision = Column(Integer, default=1, nullable=False)
    confirmed = Column(Boolean, default=False, nullable=False)
    history = Column(JSON, default=list, nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)
    __table_args__ = (UniqueConstraint("child_id", "identity", name="uq_vocabulary_identity"),)


class VocabularyMembership(Base):
    __tablename__ = "vocabulary_memberships"
    collection_id = Column(ForeignKey("vocabulary_collections.id", ondelete="CASCADE"), primary_key=True)
    item_id = Column(ForeignKey("vocabulary_items.id", ondelete="CASCADE"), primary_key=True)


class VocabularyReview(Base):
    __tablename__ = "vocabulary_reviews"
    id = Column(String(32), primary_key=True, default=uid)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    item_id = Column(ForeignKey("vocabulary_items.id", ondelete="CASCADE"), nullable=False)
    revision = Column(Integer, nullable=False)
    direction = Column(String(16), nullable=False)
    skill = Column(String(24), nullable=False)
    stage = Column(Integer, default=0, nullable=False)
    due = Column(String(10), nullable=False)
    last_promoted = Column(String(10))
    needs_clarification = Column(Boolean, default=False, nullable=False)
    __table_args__ = (UniqueConstraint("item_id", "revision", "direction", "skill", name="uq_vocabulary_review"),)


class VocabularyReviewEvent(Base):
    __tablename__ = "vocabulary_review_events"
    attempt_id = Column(ForeignKey("attempts.id", ondelete="CASCADE"), primary_key=True)
    review_id = Column(ForeignKey("vocabulary_reviews.id", ondelete="CASCADE"), nullable=False, index=True)
    day = Column(String(10), nullable=False)
    advanced = Column(Boolean, nullable=False)
    stage = Column(Integer, nullable=False)
    due = Column(String(10), nullable=False)


class VocabularyImport(Base):
    __tablename__ = "vocabulary_imports"
    id = Column(String(32), primary_key=True, default=uid)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    session_id = Column(ForeignKey("sessions.id", ondelete="SET NULL"))
    request_key = Column(String(80), nullable=False)
    request_digest = Column(String(64), nullable=False)
    target_locale = Column(String(12), nullable=False)
    title = Column(String(160), nullable=False)
    text = Column(Text, default="", nullable=False)
    source_revisions = Column(JSON, default=list, nullable=False)
    pairs = Column(JSON, default=list, nullable=False)
    status = Column(String(16), default="review", nullable=False)
    job_id = Column(ForeignKey("jobs.id", ondelete="SET NULL"))
    collection_id = Column(ForeignKey("vocabulary_collections.id", ondelete="SET NULL"))
    error = Column(String(500))
    created = Column(Integer, default=lambda: int(now()), nullable=False)
    __table_args__ = (UniqueConstraint("child_id", "request_key", name="uq_vocabulary_import_request"),)


class VocabularyAction(Base):
    __tablename__ = "vocabulary_actions"
    id = Column(String(32), primary_key=True, default=uid)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    request_key = Column(String(80), nullable=False)
    request_digest = Column(String(64), nullable=False)
    unit_id = Column(ForeignKey("learning_units.id", ondelete="CASCADE"), nullable=False)
    __table_args__ = (UniqueConstraint("child_id", "request_key", name="uq_vocabulary_action_request"),)


class LanguageProject(Base):
    __tablename__ = "language_projects"
    id = Column(String(32), primary_key=True, default=uid)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    session_id = Column(ForeignKey("sessions.id", ondelete="SET NULL"))
    request_key = Column(String(80), nullable=False)
    request_digest = Column(String(64), nullable=False)
    target_locale = Column(String(12), nullable=False)
    mode = Column(String(32), nullable=False)
    inputs = Column(JSON, nullable=False)
    source_revisions = Column(JSON, default=list, nullable=False)
    item_revisions = Column(JSON, default=list, nullable=False)
    previous_id = Column(ForeignKey("language_projects.id", ondelete="CASCADE"))
    step = Column(Integer, default=1, nullable=False)
    status = Column(String(16), default="queued", nullable=False)
    result = Column(JSON)
    error = Column(String(500))
    job_id = Column(ForeignKey("jobs.id", ondelete="SET NULL"))
    unit_id = Column(ForeignKey("learning_units.id", ondelete="SET NULL"))
    created = Column(Integer, default=lambda: int(now()), nullable=False)
    __table_args__ = (UniqueConstraint("child_id", "request_key", name="uq_language_project_request"),)


class Activity(Base):
    __tablename__ = "activities"
    id = Column(String(32), primary_key=True, default=uid)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    unit_id = Column(ForeignKey("learning_units.id", ondelete="CASCADE"))
    kind = Column(String(24), nullable=False)
    detail = Column(JSON, default=dict, nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False, index=True)


class Mastery(Base):
    __tablename__ = "mastery"
    id = Column(String(32), primary_key=True, default=uid)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    subject = Column(String(80), nullable=False)
    subject_id = Column(ForeignKey("subjects.id", ondelete="SET NULL"), index=True)
    topic = Column(String(160), nullable=False)
    independent = Column(Integer, default=0, nullable=False)
    assisted = Column(Integer, default=0, nullable=False)
    difficulties = Column(Integer, default=0, nullable=False)
    uncertain_units = Column(Integer, default=0, nullable=False)
    review_successes = Column(Integer, default=0, nullable=False)
    next_review = Column(String(10), nullable=False)
    last_practiced = Column(String(10), nullable=False)
    __table_args__ = (UniqueConstraint("child_id", "subject", "topic"),)


class Message(Base):
    __tablename__ = "messages"
    id = Column(String(32), primary_key=True, default=uid)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    sender_id = Column(ForeignKey("users.id", ondelete="SET NULL"))
    kind = Column(String(24), nullable=False)
    body = Column(String(1000), nullable=False)
    context = Column(JSON)
    resolved = Column(Boolean, default=False, nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)


class ProviderConfig(Base):
    __tablename__ = "provider_config"
    id = Column(Integer, primary_key=True, default=1)
    revision = Column(Integer, default=1, server_default="1", nullable=False)
    provider = Column(String(20), default="openrouter", nullable=False)
    model = Column(String(160), default="", nullable=False)
    reasoning_effort = Column(String(32), default="medium", server_default="medium", nullable=False)
    extraction_model = Column(String(160), default="", server_default="", nullable=False)
    extraction_capability_evidence = Column(String(500), default="", server_default="", nullable=False)
    encrypted_key = Column(Text)
    emergency_stop = Column(Boolean, default=True, nullable=False)
    image_capable = Column(Boolean, default=False, nullable=False)
    structured_capable = Column(Boolean, default=False, nullable=False)
    capability_evidence = Column(String(500), default="", nullable=False)
    privacy_approved = Column(Boolean, default=False, nullable=False)
    privacy_evidence = Column(String(500), default="", nullable=False)
    production_block_reason = Column(String(500), default="", server_default="", nullable=False)
    openrouter_free_only = Column(Boolean, default=True, server_default=true(), nullable=False)
    openrouter_require_zdr = Column(Boolean, default=False, server_default=true(), nullable=False)
    reserve_micros = Column(Integer, default=250_000, nullable=False)
    input_per_million_micros = Column(Integer)
    output_per_million_micros = Column(Integer)
    pricing_evidence = Column(String(500), default="", nullable=False)
    max_output_tokens = Column(Integer, default=4000, nullable=False)
    global_limit_micros = Column(Integer, default=10_000_000, nullable=False)
    status = Column(String(500), default="Nicht konfiguriert", nullable=False)
    routing_policy = Column(JSON, default=dict, server_default="{}", nullable=False)


class UsageBucket(Base):
    __tablename__ = "usage_buckets"
    id = Column(String(80), primary_key=True)
    calls = Column(Integer, default=0, nullable=False)
    encumbered_micros = Column(Integer, default=0, nullable=False)
    known_cost_micros = Column(Integer, default=0, nullable=False)
    unknown_calls = Column(Integer, default=0, nullable=False)


class Usage(Base):
    __tablename__ = "usage"
    id = Column(String(32), primary_key=True, default=uid)
    family_id = Column(ForeignKey("families.id", ondelete="CASCADE"), nullable=False, index=True)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False)
    job_id = Column(String(32), nullable=False)
    provider = Column(String(20), nullable=False)
    model = Column(String(160), nullable=False)
    config_revision = Column(Integer, nullable=False)
    function = Column(String(20), nullable=False)
    status = Column(String(20), default="reserved", nullable=False)
    input_tokens = Column(Integer)
    output_tokens = Column(Integer)
    search_calls = Column(Integer)
    cost_micros = Column(Integer)
    reserved_micros = Column(Integer, nullable=False)
    bucket_ids = Column(JSON, nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)
    route_snapshot = Column(JSON, default=dict, server_default="{}", nullable=False)
    telemetry = Column(JSON, default=dict, server_default="{}", nullable=False)
    cost_source = Column(String(24), default="unknown", server_default="unknown", nullable=False)
    settlement_version = Column(Integer, default=0, server_default="0", nullable=False)
    estimated_micros = Column(Integer)
    child_budget_id = Column(String(80))
    reserved_eur_micros = Column(Integer)
    charged_eur_micros = Column(Integer)
    allocated_fee_micros = Column(Integer)
    reservation_key = Column(String(64), unique=True)


class ChildCostBucket(Base):
    __tablename__ = "child_cost_buckets"
    id = Column(String(80), primary_key=True)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    period = Column(String(7), nullable=False)
    calls = Column(Integer, default=0, nullable=False)
    encumbered_eur_micros = Column(Integer, default=0, nullable=False)
    known_eur_micros = Column(Integer, default=0, nullable=False)
    unknown_calls = Column(Integer, default=0, nullable=False)


class CreditPurchase(Base):
    """Operator-recorded credit receipts; fees allocated only as credit is used."""

    __tablename__ = "credit_purchases"
    id = Column(String(64), primary_key=True)
    credits_micros = Column(Integer, nullable=False)
    fee_micros = Column(Integer, nullable=False)
    consumed_micros = Column(Integer, default=0, nullable=False)
    allocated_fee_micros = Column(Integer, default=0, nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)


class LearningMemory(Base):
    """Working memory only; attempts remain the authoritative learning evidence."""

    __tablename__ = "learning_memory"
    unit_id = Column(ForeignKey("learning_units.id", ondelete="CASCADE"), primary_key=True)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    revision = Column(Integer, default=1, nullable=False)
    plan_revision = Column(Integer, default=1, nullable=False)
    source_signature = Column(String(64), nullable=False)
    working = Column(JSON, default=dict, nullable=False)
    decision = Column(JSON, default=dict, nullable=False)
    updated = Column(Integer, default=lambda: int(now()), nullable=False)


class LearningEvent(Base):
    __tablename__ = "learning_controller_events"
    id = Column(String(32), primary_key=True, default=uid)
    unit_id = Column(ForeignKey("learning_units.id", ondelete="CASCADE"), nullable=False, index=True)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    event_key = Column(String(100), nullable=False)
    digest = Column(String(64), nullable=False)
    kind = Column(String(32), nullable=False)
    evidence = Column(JSON, nullable=False)
    decision = Column(JSON, nullable=False)
    strategy_version = Column(String(32), nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)
    __table_args__ = (UniqueConstraint("unit_id", "event_key", name="uq_controller_event"),)


class SchulbuddyTurn(Base):
    """Private, user-owned advisory chat. Never authoritative learning evidence."""

    __tablename__ = "schulbuddy_turns"
    id = Column(String(32), primary_key=True, default=uid)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    session_id = Column(ForeignKey("sessions.id", ondelete="CASCADE"), nullable=False)
    job_id = Column(String(32), nullable=False, unique=True)
    request_key = Column(String(80), nullable=False)
    request_hash = Column(String(64), nullable=False)
    context_key = Column(String(64), nullable=False, index=True)
    scope = Column(JSON, nullable=False)
    source_revisions = Column(JSON, nullable=False)
    reply_to = Column(String(32))
    question = Column(String(1200), nullable=False)
    reply = Column(JSON)
    error = Column(String(500))
    status = Column(String(20), default="queued", nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)
    __table_args__ = (UniqueConstraint("user_id", "request_key", name="uq_schulbuddy_request"),)


class Job(Base):
    __tablename__ = "jobs"
    id = Column(String(32), primary_key=True, default=uid)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    kind = Column(String(20), nullable=False)
    payload = Column(JSON, nullable=False)
    status = Column(String(20), default="queued", nullable=False)
    result = Column(JSON)
    error = Column(String(500))
    error_code = Column(String(24))
    attempts = Column(Integer, default=0, nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)
    started = Column(Integer)
    finished = Column(Integer)
    idempotency = Column(String(120), unique=True, nullable=False)


class RateBucket(Base):
    __tablename__ = "rate_buckets"
    id = Column(String(160), primary_key=True)
    count = Column(Integer, default=0, nullable=False)
    expires = Column(Integer, nullable=False)


class Audit(Base):
    __tablename__ = "audit"
    id = Column(String(32), primary_key=True, default=uid)
    actor = Column(String(32), nullable=False)
    action = Column(String(80), nullable=False)
    target = Column(String(80), nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)


Index("jobs_queue", Job.status, Job.created)

# Register additive catalog tables after all referenced private models exist.
from . import (  # noqa: E402,F401  # noqa: E402,F401
    admin_user_models,
    catalog_models,
    child_cost_models,
    competence_models,
    curriculum_models,
    exam_models,
    exam_review_models,
    learning_asset_models,
    order_withdrawal_models,
    parent_reminder_models,
    payment_models,
    source_lineage_models,  # noqa: E402,F401
    visual_reference_models,  # noqa: E402,F401
)

settings.data_dir.mkdir(parents=True, exist_ok=True)
engine = create_engine(
    settings.database_url,
    pool_pre_ping=True,
    connect_args={"check_same_thread": False, "timeout": 30} if settings.database_url.startswith("sqlite") else {},
)
if settings.database_url.startswith("sqlite"):

    @event.listens_for(engine, "connect")
    def sqlite_setup(connection, _):
        connection.execute("PRAGMA foreign_keys=ON")
        connection.execute("PRAGMA journal_mode=WAL")


DB = sessionmaker(engine, expire_on_commit=False)


def init_db():
    if settings.environment == "production":
        from sqlalchemy import inspect

        if not inspect(engine).has_table("alembic_version"):
            raise RuntimeError("Database migrations must be applied before production startup")
    else:
        Base.metadata.create_all(engine)
    from .security import insert_ignore

    with DB.begin() as db:
        insert_ignore(db, ProviderConfig, {"id": 1})
        from .subject_registry import seed_connection

        seed_connection(db.connection())
        from .competences import seed_connection as seed_competences

        seed_competences(db.connection())
        from .visual_references import seed as seed_visual_references

        seed_visual_references(db)
        from .curriculum import seed as seed_curriculum

        seed_curriculum(db)
    from .installation import initialize

    initialize()
    if settings.environment != "test":
        from .catalog_import import ensure_bundled

        ensure_bundled()


def get_db():
    with DB() as db:
        yield db
