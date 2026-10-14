import json
import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import FileResponse, JSONResponse
from sqlalchemy import text

from . import __version__, admin, auth, families, learning, materials, synthetic
from .config import settings
from .db import DB, ProviderConfig, init_db

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
        ai = (
            not config.emergency_stop
            and config.provider != "disabled"
            and config.privacy_approved
            and settings.real_data_approved
        )
    return {
        "version": __version__,
        "registration_available": settings.mail_ready,
        "email_available": settings.mail_ready,
        "synthetic_demo_available": settings.synthetic_demo,
        "real_data_enabled": bool(settings.real_data_approved and settings.privacy_evidence),
        "ai_available": ai,
        "notice": "Entwicklungsstand mit synthetischem Testraum. Externe Verarbeitung echter Kinderdaten bleibt bis zur dokumentierten Freigabe gesperrt.",
    }


for router in (auth.router, families.router, learning.router, materials.router, synthetic.router, admin.router):
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
