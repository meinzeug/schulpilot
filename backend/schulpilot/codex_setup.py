"""Explicit local operator selection. Activation needs the bounded artificial probe."""

import json
import os

import httpx
from fastapi import HTTPException

from .config import settings
from .db import DB, ProviderConfig, uid
from .security import audit

MODEL = "gpt-6.1-sol"
CLI_VERSION = "0.162.1"


def worker_health():
    unavailable = {"ready": False, "status": "Der isolierte Codex-Lernworker ist nicht erreichbar."}
    if not settings.codex_approved or not settings.codex_socket:
        return {"ready": False, "status": "Der isolierte Codex-Lernworker ist noch nicht eingerichtet."}
    try:
        transport = httpx.HTTPTransport(uds=settings.codex_socket)
        with httpx.Client(transport=transport, timeout=5, follow_redirects=False) as client:
            response = client.get("http://localhost/health")
        if response.status_code != 200:
            return unavailable
        data = response.json()
        if not (data.get("isolated") is True and data.get("search") is True and data.get("cli_version") == CLI_VERSION):
            return {"ready": False, "status": "Codex-Isolation, Websuche oder CLI-Version ist nicht bestätigt."}
        if data.get("auth_mode") != settings.codex_auth_mode:
            return {
                "ready": False,
                "status": "Codex bitte auf dem Server über schulpilot-codex login verbinden. Anmeldung oder passende Anmeldeart fehlt.",
            }
        return {
            "ready": True,
            "status": "Isolierter Codex-Worker erreichbar, Websuche aktiviert, eigene Anmeldung vorhanden. Ein echter Bild-/Aufgabentest ist separat erforderlich.",
        }
    except (httpx.HTTPError, ValueError, TypeError, AttributeError):
        return unavailable


def configure():
    if (
        not settings.codex_approved
        or not settings.codex_socket
        or settings.codex_auth_mode not in ("api_key", "account")
    ):
        raise SystemExit("Zuerst den isolierten Worker und seine Anmeldeart lokal konfigurieren.")
    with DB.begin() as db:
        config = db.get(ProviderConfig, 1)
        backups = settings.data_dir / "operator-backups"
        backups.mkdir(mode=0o700, parents=True, exist_ok=True)
        snapshot = backups / f"provider-before-codex-{uid()}.json"
        with os.fdopen(os.open(snapshot, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as stream:
            json.dump(
                {column.name: getattr(config, column.name) for column in ProviderConfig.__table__.columns}, stream
            )
        # This is an explicit replacement, never an OpenRouter fallback.
        config.provider = "codex"
        config.model = config.extraction_model = MODEL
        config.encrypted_key = None
        config.image_capable = config.structured_capable = True
        config.capability_evidence = config.extraction_capability_evidence = (
            "Official Codex docs checked 2026-10-15; CLI 0.162.1; --search; image/schema; actual probe required"
        )
        config.production_block_reason = (
            "Codex ist ausgewählt. Eigene Server-Anmeldung und erfolgreicher künstlicher Bild-/Aufgabentest fehlen."
        )
        config.status = config.production_block_reason
        config.privacy_approved = True
        config.privacy_evidence = "Betreiberauftrag 15.10.2026: dauerhafter Codex-CLI-Provider mit --search; vorherige Anbieter-/Datenschutzfreigabe bleibt gültig."
        if settings.codex_auth_mode == "account":
            config.input_per_million_micros = config.output_per_million_micros = None
            config.pricing_evidence = "Codex-Konto: keine verlässlichen USD-Kosten; unbekannt, volle Reservierung erhalten; bestehende Aufruf-/Familien-/Unternehmenslimits und Kontolimits gelten."
        else:
            # Conservative upper bounds including long context/cache writes.
            config.input_per_million_micros = 5_000_000
            config.output_per_million_micros = 15_000_000
            config.reserve_micros = max(config.reserve_micros, 1_000_000)
            config.pricing_evidence = "https://developers.openai.com/api/docs/pricing ; 2026-10-15; gpt-6.1-sol long-context/cache-write ceiling; web search $10/1000 plus model tokens"
        config.revision += 1
        audit(db, "local-operator", "provider.codex_selected", settings.codex_auth_mode)
    print(
        json.dumps(
            {
                "provider": "codex",
                "model": MODEL,
                "search": True,
                "production_ready": False,
                "next": "schulpilot-codex login",
            }
        )
    )


def enqueue_probe():
    from .operator_probe import enqueue

    with DB() as db:
        if db.get(ProviderConfig, 1).provider != "codex":
            raise SystemExit("Codex ist nicht als Anbieter ausgewählt.")
        try:
            result = enqueue("local-operator", db)
        except HTTPException as error:
            raise SystemExit(error.detail) from None
    print(
        json.dumps(
            {
                "probe": result,
                "synthetic_only": True,
                "next": "Prüfauftrag im Adminbereich beobachten. Erst drei erfolgreiche Funktionen aktivieren die neue Route.",
            }
        )
    )
