"""Single-use installation and encrypted settings, shared by API and worker."""

import hmac
import json
import os
import re
import secrets
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import EmailStr, Field, StringConstraints, ValidationError, model_validator
from sqlalchemy import select, update

from . import schemas as s
from .config import RUNTIME_FIELDS, runtime_settings, settings
from .db import DB, Family, Installation, OperatorJob, ProviderConfig, ServiceState, Token, User, get_db, now
from .security import admin, audit, digest, encrypt, insert_ignore, password_hash, rate_limit

router = APIRouter(tags=["Einrichtung"])
SECRET_FIELDS = {"smtp_password", "fcm_service_account_json"}


class SiteUpdate(s.Strict):
    smtp_host: str = Field(default="", max_length=253, pattern=r"^[A-Za-z0-9.-]*$")
    smtp_port: int = Field(default=587, ge=1, le=65535)
    smtp_user: str = Field(default="", max_length=254)
    smtp_password: Annotated[str, StringConstraints(strip_whitespace=False)] | None = Field(
        default=None, max_length=1024
    )
    smtp_from: str = Field(default="", max_length=254)
    smtp_mode: Literal["starttls", "tls"] = "starttls"
    clear_smtp_password: bool = False
    operator_name: str = Field(default="", max_length=160)
    operator_address: str = Field(default="", max_length=1000)
    operator_support_email: str = Field(default="", max_length=254)
    real_data_approved: bool = False
    privacy_evidence: str = Field(default="", max_length=500)
    synthetic_demo: bool = True
    synthetic_ai_enabled: bool = False
    synthetic_ai_daily_limit: int = Field(default=40, ge=1, le=100)
    default_plan: str = Field(default="Pilot", min_length=1, max_length=40)
    default_child_limit: int = Field(default=4, ge=1, le=20)
    default_call_limit: int = Field(default=100, ge=0, le=10000)
    default_budget_micros: int = Field(default=2_000_000, ge=0, le=100_000_000)
    fcm_public_config: str = Field(default="", max_length=10000)
    fcm_service_account_json: str | None = Field(default=None, max_length=16000)
    clear_fcm_service_account_json: bool = False
    push_approved: bool = False
    push_privacy_evidence: str = Field(default="", max_length=500)
    fcm_config_verification: str = Field(default="", max_length=1000)

    @model_validator(mode="after")
    def validate_config(self):
        for key in ("smtp_from", "operator_support_email"):
            value = getattr(self, key)
            if value:
                from pydantic import TypeAdapter

                TypeAdapter(EmailStr).validate_python(value)
        if self.real_data_approved and len(self.privacy_evidence) < 20:
            raise ValueError("Bitte die Datenschutzfreigabe nachvollziehbar dokumentieren.")
        if self.push_approved and len(self.push_privacy_evidence) < 20:
            raise ValueError("Bitte die Push-Freigabe nachvollziehbar dokumentieren.")
        if self.push_approved and len(self.fcm_config_verification) < 20:
            raise ValueError("Die Firebase-Apps, APIs und API-Key-Einschränkungen müssen zuvor geprüft sein.")
        if self.fcm_public_config:
            raw = json.loads(self.fcm_public_config)
            allowed = {"apiKey", "appId", "messagingSenderId", "projectId", "authDomain", "vapidKey", "androidAppId", "androidApiKey"}
            if not isinstance(raw, dict) or set(raw) - allowed or not all(isinstance(v, str) for v in raw.values()):
                raise ValueError("Firebase-App-Konfiguration enthält unbekannte Felder.")
            if raw.get("projectId") and not re.fullmatch(r"[a-z][a-z0-9-]{4,62}", raw["projectId"]):
                raise ValueError("Ungültige Firebase-Projektkennung.")
        if self.fcm_service_account_json:
            raw = json.loads(self.fcm_service_account_json)
            if (
                not isinstance(raw, dict)
                or raw.get("type") != "service_account"
                or raw.get("token_uri") != "https://oauth2.googleapis.com/token"
                or not all(raw.get(k) for k in ("project_id", "client_email", "private_key"))
            ):
                raise ValueError("Ungültiges Firebase-Dienstkonto.")
        return self


class Unlock(s.Strict):
    code: str = Field(min_length=32, max_length=128)


class AdminCreate(s.Strict):
    username: str = Field(min_length=3, max_length=50, pattern=r"^[A-Za-z0-9._-]+$")
    password: Annotated[str, StringConstraints(strip_whitespace=False)] = Field(min_length=12, max_length=128)
    display_name: str = Field(default="Administration", min_length=1, max_length=80)


class MailTest(s.Strict):
    email: EmailStr


def code_path():
    return settings.data_dir / "setup-code.txt"


def initialize():
    with DB.begin() as db:
        legacy = bool(db.scalar(select(User.id).limit(1)) or db.scalar(select(Family.id).limit(1)))
        insert_ignore(db, Installation, {"id": 1, "completed": legacy, "revision": 1})
        # Serializes API/worker initialization before touching the operator file.
        db.execute(update(Installation).where(Installation.id == 1).values(revision=Installation.revision))
        item = db.get(Installation, 1)
        if item.completed or item.bootstrap_digest:
            return
        path = code_path()
        try:
            fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        except FileExistsError:
            if path.is_symlink():
                raise RuntimeError("Installation code must be an operator-owned regular file")
            value = path.read_text().strip()
        else:
            value = secrets.token_urlsafe(36)
            with os.fdopen(fd, "w") as output:
                output.write(value + "\n")
        if not re.fullmatch(r"[A-Za-z0-9_-]{32,128}", value):
            raise RuntimeError("Invalid installation code file; rotate it through the local CLI")
        path.chmod(0o600)
        item.bootstrap_digest, item.bootstrap_expires = digest(value), int(now()) + 86400


def required(db):
    item = db.get(Installation, 1, populate_existing=True)
    return bool(item and not item.completed)


def setup_operator(request: Request, db=Depends(get_db)):
    # Keep setup actions and completion serial: a previously authenticated
    # request must not change settings after another request closes setup.
    db.execute(update(Installation).where(Installation.id == 1).values(revision=Installation.revision))
    if not required(db):
        raise HTTPException(409, "Die Ersteinrichtung ist bereits abgeschlossen.")
    value = request.cookies.get("sp_setup", "")
    token = db.scalar(
        select(Token).where(
            Token.digest == digest(value), Token.purpose == "setup", Token.used.is_(False), Token.expires > int(now())
        )
    )
    if not token:
        raise HTTPException(401, "Bitte die Ersteinrichtung mit dem Installationscode öffnen.")
    return "initial-setup"


@router.get("/setup/status")
def status(db=Depends(get_db)):
    return {"required": required(db)}


@router.post("/setup/unlock")
def unlock(data: Unlock, request: Request, response: Response, db=Depends(get_db)):
    if not required(db):
        raise HTTPException(409, "Die Ersteinrichtung ist bereits abgeschlossen.")
    rate_limit(db, "setup-unlock:" + digest(request.client.host), 6, 900)
    db.execute(update(Installation).where(Installation.id == 1).values(revision=Installation.revision))
    if not required(db):
        raise HTTPException(409, "Die Ersteinrichtung ist bereits abgeschlossen.")
    item = db.get(Installation, 1)
    if (
        not item.bootstrap_digest
        or not item.bootstrap_expires
        or item.bootstrap_expires < now()
        or not hmac.compare_digest(digest(data.code), item.bootstrap_digest)
    ):
        raise HTTPException(401, "Installationscode ist ungültig oder abgelaufen.")
    value = secrets.token_urlsafe(48)
    db.add(Token(digest=digest(value), purpose="setup", expires=int(now()) + 1800))
    audit(db, "initial-setup", "setup.unlocked", "installation")
    db.commit()
    response.set_cookie(
        "sp_setup",
        value,
        max_age=1800,
        path="/api/setup",
        httponly=True,
        secure=settings.environment == "production",
        samesite="strict",
    )
    return {"message": "Einrichtung geöffnet."}


def configuration(db):
    from .admin import config_data
    from .notifications import public_config

    site = runtime_settings(db)
    values = {k: getattr(site, k) for k in RUNTIME_FIELDS - SECRET_FIELDS}
    values.update(
        has_smtp_password=bool(site.smtp_password),
        has_fcm_service_account=bool(site.fcm_service_account_json or site.fcm_service_account_file),
        public_url=site.public_url,
    )
    worker = db.get(ServiceState, "worker")
    checks = {
        "database": True,
        "https": settings.environment != "production" or settings.public_url.startswith("https://"),
        "mail_configured": site.mail_ready,
        "operator_complete": bool(site.operator_name and site.operator_address and site.operator_support_email),
        "data_approved": bool(site.real_data_approved and site.privacy_evidence),
        "push_available": public_config()["available"],
        "worker_available": bool(worker and now() - worker.updated < 600),
        "codex_available": bool(settings.codex_approved and settings.codex_socket),
    }
    return {"site": values, "provider": config_data(db.get(ProviderConfig, 1)), "checks": checks}


def save_site(data, actor, db):
    db.execute(update(Installation).where(Installation.id == 1).values(revision=Installation.revision + 1))
    item = db.get(Installation, 1)
    from .security import decrypt

    values = json.loads(decrypt(item.encrypted_settings)) if item.encrypted_settings else {}
    changes = data.model_dump(exclude_unset=True)
    for name in RUNTIME_FIELDS:
        if name in changes and (name not in SECRET_FIELDS or changes[name]):
            values[name] = changes[name]
    for name in SECRET_FIELDS:
        if changes.get("clear_" + name):
            values[name] = ""
    # Validate the complete merged settings, including retained secrets.
    complete = {k: values.get(k, getattr(settings, k)) for k in RUNTIME_FIELDS}
    try:
        SiteUpdate(**complete)
    except ValidationError:
        # The merged settings can fail although a partial request was valid.
        # Never include Pydantic's input dump: it contains retained secrets.
        raise HTTPException(
            422, "Die gespeicherten Einstellungen passen nicht zusammen. Freigaben und Pflichtfelder bitte prüfen."
        ) from None
    if complete.get("fcm_service_account_json") and complete.get("fcm_public_config"):
        if json.loads(complete["fcm_service_account_json"])["project_id"] != json.loads(
            complete["fcm_public_config"]
        ).get("projectId"):
            raise HTTPException(422, "Firebase-App und Dienstkonto gehören zu verschiedenen Projekten.")
    item.encrypted_settings = encrypt(json.dumps(values))
    audit(db, actor, "installation.settings_update", "site")
    db.commit()
    return configuration(db)


@router.get("/setup/config")
def get_setup(actor=Depends(setup_operator), db=Depends(get_db)):
    return configuration(db)


@router.put("/setup/site")
def update_setup(data: SiteUpdate, actor=Depends(setup_operator), db=Depends(get_db)):
    return save_site(data, actor, db)


@router.get("/admin/installation")
def get_admin(p=Depends(admin), db=Depends(get_db)):
    audit(db, p.user.id, "installation.settings_read", "site")
    db.commit()
    return configuration(db)


@router.put("/admin/installation/site")
def update_admin(data: SiteUpdate, p=Depends(admin), db=Depends(get_db)):
    return save_site(data, p.user.id, db)


@router.put("/setup/provider")
def setup_provider(data: s.ProviderUpdate, actor=Depends(setup_operator), db=Depends(get_db)):
    from .admin import save_provider

    return save_provider(data, actor, db)


@router.post("/setup/provider/check")
def check_provider(actor=Depends(setup_operator), db=Depends(get_db)):
    from .admin import provider_check

    return provider_check(actor, db)


def test_mail(data, actor, db):
    from .mail import send_message

    rate_limit(db, "operator-mail-test", 5, 3600)
    if actor == "initial-setup":
        db.execute(update(Installation).where(Installation.id == 1).values(revision=Installation.revision))
        if not required(db):
            raise HTTPException(409, "Die Ersteinrichtung ist bereits abgeschlossen.")
    send_message(
        str(data.email), "SCHULPILOT: E-Mail-Test", "Der E-Mail-Test deiner SCHULPILOT-Installation war erfolgreich."
    )
    audit(db, actor, "installation.mail_test", "smtp")
    db.commit()
    return {"message": "Testnachricht wurde vom Mailserver angenommen. Bitte den tatsächlichen Eingang prüfen."}


@router.post("/setup/mail-test")
def setup_mail(data: MailTest, actor=Depends(setup_operator), db=Depends(get_db)):
    return test_mail(data, actor, db)


@router.post("/admin/installation/mail-test")
def admin_mail(data: MailTest, p=Depends(admin), db=Depends(get_db)):
    return test_mail(data, p.user.id, db)


@router.post("/setup/complete", status_code=201)
def complete(data: AdminCreate, response: Response, actor=Depends(setup_operator), db=Depends(get_db)):
    # Conditional write gives exactly one winner under parallel completion.
    changed = db.execute(
        update(Installation)
        .where(Installation.id == 1, Installation.completed.is_(False))
        .values(completed=True, completed_at=int(now()), bootstrap_digest=None, bootstrap_expires=None)
    )
    if not changed.rowcount:
        raise HTTPException(409, "Die Ersteinrichtung ist bereits abgeschlossen.")
    if db.scalar(select(User.id).limit(1)) or db.scalar(select(Family.id).limit(1)):
        raise HTTPException(409, "Es bestehen bereits Konten. Bitte die lokale Admin-Verwaltung verwenden.")
    username = data.username.lower()
    user = User(
        username=username,
        display_name=data.display_name,
        role="admin",
        verified=True,
        password_hash=password_hash(data.password),
    )
    db.add(user)
    db.flush()
    db.execute(update(Token).where(Token.purpose == "setup").values(used=True))
    audit(db, actor, "setup.completed", user.id)
    db.commit()
    code_path().unlink(missing_ok=True)
    response.delete_cookie(
        "sp_setup", path="/api/setup", secure=settings.environment == "production", samesite="strict"
    )
    return {"message": "Einrichtung abgeschlossen. Bitte mit deinem Administratorkonto anmelden."}


@router.post("/setup/provider/probe", status_code=202)
def setup_probe(actor=Depends(setup_operator), db=Depends(get_db)):
    from .operator_probe import enqueue

    return enqueue(actor, db)


@router.post("/admin/provider/probe", status_code=202)
def admin_probe(p=Depends(admin), db=Depends(get_db)):
    from .operator_probe import enqueue

    return enqueue(p.user.id, db)


def probe_data(job):
    if not job:
        raise HTTPException(404, "Prüfauftrag nicht gefunden.")
    return {k: getattr(job, k) for k in ("id", "status", "report", "error")}


@router.get("/setup/provider/probes/{job_id}")
def setup_probe_result(job_id: str, actor=Depends(setup_operator), db=Depends(get_db)):
    return probe_data(db.get(OperatorJob, job_id))


@router.get("/admin/provider/probes/{job_id}")
def admin_probe_result(job_id: str, p=Depends(admin), db=Depends(get_db)):
    return probe_data(db.get(OperatorJob, job_id))
