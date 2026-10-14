import json
import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import FileResponse, JSONResponse
from sqlalchemy import text

from . import __version__, admin, auth, families, learning, materials, notifications, releases, school_day, synthetic
from .config import settings
from .db import DB, ProviderConfig, init_db
from .operations import router as operations_router
from .providers import ProviderError, config_for_function, external_allowed

log = logging.getLogger("schulpilot.api")


@asynccontextmanager
async def lifespan(app):
    init_db()
    yield


app = FastAPI(
    title="SCHULPILOT API",
    version=__version__,
    lifespan=lifespan,
    docs_url=None if settings.environment == "production" else "/api/docs",
    redoc_url=None,
    openapi_url=None if settings.environment == "production" else "/api/openapi.json",
)


class ActualBodyLimit:
    """Limit received bytes too: Content-Length alone does not cover chunking."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http" or scope["method"] not in ("POST", "PUT", "PATCH", "DELETE"):
            return await self.app(scope, receive, send)
        path = scope.get("path", "")
        maximum = 12 * 1024 * 1024 if path.startswith("/api/children/") and path.endswith("/materials") else 64 * 1024
        if path.startswith("/api/materials/") and path.endswith("/confirm"):
            maximum = 256 * 1024
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


@app.middleware("http")
async def security_headers(request: Request, call_next):
    if request.method in ("POST", "PUT", "PATCH", "DELETE"):
        origin = request.headers.get("origin")
        if origin and origin != settings.public_url:
            return JSONResponse({"detail": "Fremder Ursprung ist nicht erlaubt."}, status_code=403)
        if request.headers.get("x-schulpilot-request") != "1":
            return JSONResponse({"detail": "Sicherheitsheader fehlt."}, status_code=403)
        maximum = 12 * 1024 * 1024 if "/materials" in request.url.path else 64 * 1024
        length = request.headers.get("content-length", "0")
        if not length.isdigit() or int(length) > maximum:
            return JSONResponse({"detail": "Anfrage ist zu groß."}, status_code=413)
    try:
        response = await call_next(request)
    except Exception as exc:
        # Catch before ASGI's default error middleware can re-raise and log a
        # traceback containing SQL parameters, private answers or credentials.
        log.error("request_failed method=%s type=%s", request.method, type(exc).__name__)
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
    with DB() as db:
        config = db.get(ProviderConfig, 1)
        ai, reason = True, None
        try:
            for function in ("extract", "unit"):
                external_allowed(config_for_function(config, function), image=function == "extract")
        except ProviderError as error:
            ai, reason = False, str(error)
    return {
        "version": __version__,
        "registration_available": settings.mail_ready,
        "email_available": settings.mail_ready,
        "synthetic_demo_available": settings.synthetic_demo,
        "synthetic_ai_available": bool(
            settings.synthetic_ai_enabled
            and not config.emergency_stop
            and config.provider == "openrouter"
            and config.model.endswith(":free")
        ),
        "real_data_enabled": bool(settings.real_data_approved and settings.privacy_evidence),
        "ai_available": ai,
        "ai_provider": config.provider,
        "ai_free_only": bool(config.provider == "openrouter" and config.openrouter_free_only),
        "ai_data_collection": "deny" if config.provider == "openrouter" else None,
        "ai_requires_zdr": bool(config.provider == "openrouter" and config.openrouter_require_zdr),
        "ai_block_reason": (
            "Der eingerichtete KI-Endpunkt erfüllt die erforderlichen Datenschutzeinstellungen derzeit nicht. Deine Materialien werden nicht an diesen Endpunkt gesendet."
            if config.production_block_reason
            else reason
        ),
        "notice": (
            "Technischer Pilot. Betreiberfreigabe liegt vor; die Verfügbarkeit externer KI wird zusätzlich geprüft."
            if settings.real_data_approved and settings.privacy_evidence
            else "Entwicklungsstand mit synthetischem Testraum. Externe Verarbeitung echter Kinderdaten bleibt bis zur dokumentierten Freigabe gesperrt."
        ),
    }


@app.get("/api/legal")
def legal():
    return {
        "operator": settings.operator_name,
        "address": settings.operator_address,
        "support_email": settings.operator_support_email,
        "complete": bool(settings.operator_name and settings.operator_address and settings.operator_support_email),
        "operator_data_approval": bool(settings.real_data_approved and settings.privacy_evidence),
        "retention_days": {"learning": 365, "jobs": 30, "backups": 14, "local_pending_photos_hours": 24},
    }


for router in (
    operations_router,
    auth.router,
    families.router,
    learning.router,
    materials.router,
    synthetic.router,
    admin.router,
    notifications.router,
    releases.router,
    school_day.router,
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
