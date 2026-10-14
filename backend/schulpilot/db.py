import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    JSON,
    Boolean,
    Column,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    create_engine,
    event,
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
    totp_secret = Column(Text)
    totp_last_step = Column(Integer, default=0, nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)


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


class SchoolDay(Base):
    __tablename__ = "school_days"
    id = Column(String(32), primary_key=True, default=uid)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    school_date = Column(String(10), nullable=False)
    stage = Column(String(16), default="collecting", nullable=False)
    revision = Column(Integer, default=1, nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)
    __table_args__ = (UniqueConstraint("child_id", "school_date"),)


class Material(Base):
    __tablename__ = "materials"
    id = Column(String(32), primary_key=True, default=uid)
    revision = Column(Integer, default=1, server_default="1", nullable=False)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    school_day_id = Column(ForeignKey("school_days.id", ondelete="SET NULL"), index=True)
    page_number = Column(Integer)
    title = Column(String(160), nullable=False)
    path = Column(String(80))
    status = Column(String(24), default="uploaded", nullable=False)
    subject = Column(String(80), default="", nullable=False)
    topic = Column(String(160), default="", nullable=False)
    content = Column(Text, default="", nullable=False)
    uncertainties = Column(JSON, default=list, nullable=False)
    homework = Column(JSON, default=list, nullable=False)
    confirmed = Column(Boolean, default=False, nullable=False)
    synthetic = Column(Boolean, default=False, nullable=False)
    fixture_id = Column(String(40))
    extraction_provider = Column(String(20), default="", server_default="", nullable=False)
    extraction_model = Column(String(160), default="", server_default="", nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)


class Assignment(Base):
    __tablename__ = "assignments"
    id = Column(String(32), primary_key=True, default=uid)
    revision = Column(Integer, default=1, server_default="1", nullable=False)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    material_id = Column(ForeignKey("materials.id", ondelete="SET NULL"))
    kind = Column(String(24), nullable=False)  # parent, exam, homework, interest
    subject = Column(String(80), nullable=False)
    topic = Column(String(160), nullable=False)
    note = Column(Text, default="", nullable=False)
    due = Column(String(10))
    mandatory = Column(Boolean, default=True, nullable=False)
    done = Column(Boolean, default=False, nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)


class LearningUnit(Base):
    __tablename__ = "learning_units"
    id = Column(String(32), primary_key=True, default=uid)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    school_day_id = Column(ForeignKey("school_days.id", ondelete="SET NULL"), index=True)
    estimated_minutes = Column(Integer)
    material_id = Column(ForeignKey("materials.id", ondelete="SET NULL"))
    assignment_id = Column(ForeignKey("assignments.id", ondelete="SET NULL"))
    subject = Column(String(80), nullable=False)
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


class UnitSource(Base):
    __tablename__ = "unit_sources"
    unit_id = Column(ForeignKey("learning_units.id", ondelete="CASCADE"), primary_key=True)
    material_id = Column(ForeignKey("materials.id", ondelete="CASCADE"), primary_key=True)
    revision = Column(Integer, nullable=False)


class Attempt(Base):
    __tablename__ = "attempts"
    id = Column(String(32), primary_key=True, default=uid)
    unit_id = Column(ForeignKey("learning_units.id", ondelete="CASCADE"), nullable=False, index=True)
    question_id = Column(String(60), nullable=False)
    answer = Column(JSON, nullable=False)
    outcome = Column(String(20), nullable=False)
    assisted = Column(Boolean, default=False, nullable=False)
    created = Column(Float, default=now, nullable=False)
    __table_args__ = (UniqueConstraint("unit_id", "question_id", "id"),)


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
    resolved = Column(Boolean, default=False, nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)


class ProviderConfig(Base):
    __tablename__ = "provider_config"
    id = Column(Integer, primary_key=True, default=1)
    revision = Column(Integer, default=1, server_default="1", nullable=False)
    provider = Column(String(20), default="disabled", nullable=False)
    model = Column(String(160), default="", nullable=False)
    extraction_model = Column(String(160), default="", server_default="", nullable=False)
    extraction_capability_evidence = Column(String(500), default="", server_default="", nullable=False)
    encrypted_key = Column(Text)
    emergency_stop = Column(Boolean, default=True, nullable=False)
    image_capable = Column(Boolean, default=False, nullable=False)
    structured_capable = Column(Boolean, default=False, nullable=False)
    capability_evidence = Column(String(500), default="", nullable=False)
    privacy_approved = Column(Boolean, default=False, nullable=False)
    privacy_evidence = Column(String(500), default="", nullable=False)
    reserve_micros = Column(Integer, default=250_000, nullable=False)
    input_per_million_micros = Column(Integer)
    output_per_million_micros = Column(Integer)
    pricing_evidence = Column(String(500), default="", nullable=False)
    max_output_tokens = Column(Integer, default=4000, nullable=False)
    global_limit_micros = Column(Integer, default=10_000_000, nullable=False)
    status = Column(String(500), default="Nicht konfiguriert", nullable=False)


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
    cost_micros = Column(Integer)
    reserved_micros = Column(Integer, nullable=False)
    bucket_ids = Column(JSON, nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)


class Job(Base):
    __tablename__ = "jobs"
    id = Column(String(32), primary_key=True, default=uid)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    kind = Column(String(20), nullable=False)
    payload = Column(JSON, nullable=False)
    status = Column(String(20), default="queued", nullable=False)
    result = Column(JSON)
    error = Column(String(500))
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
    with DB.begin() as db:
        if not db.get(ProviderConfig, 1):
            db.add(ProviderConfig(id=1))


def get_db():
    with DB() as db:
        yield db
