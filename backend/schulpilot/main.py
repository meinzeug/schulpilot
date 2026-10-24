import json
import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import FileResponse, JSONResponse
from sqlalchemy import text
from starlette.concurrency import run_in_threadpool

from . import (
    __version__,
    admin,
    admin_users,
    auth,
    coaching,
    commerce,
    controller_jobs,
    curriculum,
    exam_review,
    exams,
    families,
    family_calls,
    google_login,
    grade_imports,
    grades,
    homework,
    installation,
    instructional_decisions,
    language_projects,
    learning,
    learning_assets,
    learning_controller,
    learning_progress,
    learning_tips,
    library,
    materials,
    notification_inbox,
    notifications,
    operator_incidents,
    order_withdrawals,
    parent_goal_reminders,
    parent_insights,
    parent_plans,
    payment_documents,
    payments_paypal,
    profile_images,
    public_privacy,
    releases,
    routing_admin,
    school_day,
    schulbuddy,
    study_path,
    subjects,
    synthetic,
    tutor,
    unit_actions,
    visual_jobs,
    visual_positions,
    vocabulary,
)
from .config import runtime_settings, settings
from .db import DB, ProviderConfig, init_db
from .operations import router as operations_router
from .providers import ProviderError, config_for_function, external_allowed

log = logging.getLogger("schulpilot.api")


@asynccontextmanager
async def lifespan(app):
    init_db()
    async with family_calls.signal_memory_lifespan():
        yield


app = FastAPI(
    title="SCHULPILOT API",
    version=__version__,
    lifespan=lifespan,
    docs_url=None if settings.environment == "production" else "/api/docs",
    redoc_url=None,
    openapi_url=None if settings.environment == "production" else "/api/openapi.json",
)


def request_body_limit(path: str) -> int:
    """One policy for declared and received sizes, including multipart overhead."""
    if path == "/api/auth/me/avatar":
        return 6 * 1024 * 1024
    if path.startswith("/api/children/"):
        if path.endswith("/materials"):
            return 12 * 1024 * 1024
        if path.endswith("/grade-imports"):
            return 7 * 1024 * 1024
        if "/grade-imports/" in path and path.endswith("/confirm"):
            return 512 * 1024
    if path.startswith("/api/exams/") and path.endswith("/pages"):
        return 12 * 1024 * 1024
    if path.startswith("/api/materials/") and path.endswith("/confirm"):
        return 256 * 1024
    return 64 * 1024


class ActualBodyLimit:
    """Limit received bytes too: Content-Length alone does not cover chunking."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http" or scope["method"] not in ("POST", "PUT", "PATCH", "DELETE"):
            return await self.app(scope, receive, send)
        maximum = request_body_limit(scope.get("path", ""))
        size = 0

        async def limited_receive():
            nonlocal size
            message = await receive()
            if message["type"] == "http.request":
                size += len(message.get("body", b""))
                if size > maximum:
                    raise HTTPException(413, "Anfrage ist zu groß.")
            return message

        await self.app(scope, limited_receive, send)


app.add_middleware(ActualBodyLimit)


def installation_gate_required():
    # Session creation, checkout, query and close belong to the same worker.
    # Waiting for a saturated synchronous pool must never block the API loop,
    # which also schedules pending responses and dependency-session cleanup.
    with DB() as db:
        return installation.required(db)


@app.middleware("http")
async def security_headers(request: Request, call_next):
    if request.method in ("POST", "PUT", "PATCH", "DELETE"):
        origin = request.headers.get("origin")
        provider_webhook = request.url.path == "/api/payments/paypal/webhook"
        if not provider_webhook and origin and origin != settings.public_url:
            return JSONResponse({"detail": "Fremder Ursprung ist nicht erlaubt."}, status_code=403)
        if not provider_webhook and request.headers.get("x-schulpilot-request") != "1":
            return JSONResponse({"detail": "Sicherheitsheader fehlt."}, status_code=403)
        maximum = request_body_limit(request.url.path)
        length = request.headers.get("content-length", "0")
        if not length.isdigit() or int(length) > maximum:
            return JSONResponse({"detail": "Anfrage ist zu groß."}, status_code=413)
    try:
        if (
            request.url.path.startswith("/api/")
            and request.url.path not in ("/api/health", "/api/status", "/api/app-release", "/api/legal")
            and not request.url.path.startswith("/api/setup/")
        ):
            if await run_in_threadpool(installation_gate_required):
                return JSONResponse(
                    {"detail": "Bitte zuerst die Installation abschließen.", "setup_required": True},
                    status_code=503,
                    headers={"Cache-Control": "no-store"},
                )
        response = await call_next(request)
    except Exception as exc:
        # Catch before ASGI's default error middleware can re-raise and log a
        # traceback containing SQL parameters, private answers or credentials.
        log.error("request_failed method=%s type=%s", request.method, type(exc).__name__)
        await run_in_threadpool(operator_incidents.record_api_failure, exc)
        response = JSONResponse({"detail": "Interner Fehler. Bitte später erneut versuchen."}, status_code=500)
    response.headers["Cache-Control"] = "no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "no-referrer"
    return response


@app.exception_handler(RequestValidationError)
async def validation_error(request, exc):
    # FastAPI's default echoes input, which could include passwords or API keys.
    errors = [{"field": ".".join(str(x) for x in e["loc"]), "message": e["msg"][:240]} for e in exc.errors()]
    return JSONResponse({"detail": "Bitte die Eingaben prüfen.", "fields": errors}, status_code=422)


@app.exception_handler(Exception)
async def unexpected_error(request, exc):
    log.error("request_failed method=%s type=%s", request.method, type(exc).__name__)
    await run_in_threadpool(operator_incidents.record_api_failure, exc)
    return JSONResponse({"detail": "Interner Fehler. Bitte später erneut versuchen."}, status_code=500)


@app.get("/api/health")
def health():
    with DB() as db:
        db.execute(text("SELECT 1"))
    manifest = Path(__file__).resolve().parents[2] / "release.json"
    release = json.loads(manifest.read_text()) if manifest.is_file() else {"source_commit": "development"}
    return {"status": "ok", "version": __version__, **release}


@app.get("/api/status")
def status():
    site = runtime_settings()
    with DB() as db:
        config = db.get(ProviderConfig, 1)
        ai, reason = True, None
        try:
            for function in ("extract", "unit"):
                external_allowed(config_for_function(config, function), image=function == "extract")
        except ProviderError as error:
            ai, reason = False, str(error)
        synthetic_ai = bool(site.synthetic_ai_enabled)
        if synthetic_ai:
            try:
                for function in ("extract", "unit"):
                    external_allowed(config_for_function(config, function), image=function == "extract", synthetic_fixture=True)
            except ProviderError:
                synthetic_ai = False
    return {
        "version": __version__,
        "registration_available": site.mail_ready,
        "email_available": site.mail_ready,
        "synthetic_demo_available": site.synthetic_demo,
        "synthetic_ai_available": synthetic_ai,
        "real_data_enabled": bool(site.real_data_approved and site.privacy_evidence),
        "ai_available": ai,
        "ai_provider": config.provider,
        "ai_free_only": bool(config.provider == "openrouter" and config.openrouter_free_only),
        "ai_data_collection": "deny" if config.provider == "openrouter" else None,
        "ai_requires_zdr": bool(config.provider == "openrouter" and config.openrouter_require_zdr),
        "ai_block_reason": (
            "Der eingerichtete KI-Dienst hat die technische Bild- und Aufgabenprüfung noch nicht bestanden. Gespeicherte Lerninhalte bleiben nutzbar."
            if config.production_block_reason
            else reason
        ),
        "notice": (
            "SCHULPILOT ist bereit."
            if site.real_data_approved and site.privacy_evidence and ai
            else "Der KI-Dienst ist vorübergehend nicht verfügbar. Gespeicherte Lerninhalte bleiben nutzbar."
            if site.real_data_approved and site.privacy_evidence
            else "Eigene Unterrichtsmaterialien können noch nicht verarbeitet werden."
        ),
    }


@app.get("/api/legal")
def legal():
    site = runtime_settings()
    return {
        "operator": site.operator_name,
        "address": site.operator_address,
        "support_email": site.operator_support_email,
        "phone": site.operator_phone,
        "complaints_address": site.operator_complaints_address,
        "legal_info": site.operator_legal_info,
        "imprint_complete": bool(site.operator_name and site.operator_address and site.operator_support_email and site.operator_phone),
        "complete": bool(site.operator_name and site.operator_address and site.operator_support_email and site.operator_phone),
        "operator_data_approval": bool(site.real_data_approved and site.privacy_evidence),
        "retention_days": {"learning": 365, "jobs": 30, "backups": 14, "local_pending_photos_hours": 24, "push_devices_inactive": 60, "push_delivery_status": 14, "notification_reads": 30, "family_calls": 30},
        "accounting_retention": "Zahlungsbelege acht Jahre nach Ende des Buchungsjahres; bei Kontolöschung ohne Kontozuordnung.",
    }


for router in (
    operations_router,
    auth.router,
    profile_images.router,
    google_login.router,
    installation.router,
    families.router,
    family_calls.router,
    learning.router,
    learning_assets.router,
    learning_progress.router,
    grades.router,
    grade_imports.router,
    library.router,
    coaching.router,
    materials.router,
    exams.router,
    exam_review.router,
    synthetic.router,
    admin.router,
    admin_users.router,
    operator_incidents.router,
    notifications.router,
    notification_inbox.router,
    public_privacy.router,
    commerce.router,
    releases.router,
    school_day.router,
    schulbuddy.router,
    study_path.router,
    tutor.router,
    homework.router,
    vocabulary.router,
    language_projects.router,
    subjects.router,
    learning_tips.router,
    learning_controller.router,
    controller_jobs.router,
    curriculum.router,
    instructional_decisions.router,
    visual_jobs.router,
    visual_positions.router,
    parent_goal_reminders.router,
    parent_insights.router,
    parent_plans.router,
    payment_documents.router,
    order_withdrawals.router,
    payments_paypal.router,
    routing_admin.router,
    unit_actions.router,
):
    app.include_router(router, prefix="/api")

if settings.web_dir and settings.environment != "production":
    directory = Path(settings.web_dir).resolve()

    @app.get("/{path:path}")
    def local_flutter(path: str):
        if path == "api" or path.startswith("api/"):
            raise HTTPException(404, "API-Endpunkt nicht gefunden.")
        candidate = (directory / path).resolve()
        if not candidate.is_relative_to(directory):
            raise HTTPException(404)
        return FileResponse(candidate if candidate.is_file() else directory / "index.html")
