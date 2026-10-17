"""Explicit local operator selection. Activation needs the bounded artificial probe."""

import json
import os
import re

import httpx
from fastapi import HTTPException
from pydantic import BaseModel, Field, ValidationError

from .config import settings
from .db import DB, ProviderConfig, uid
from .security import audit

MODEL = "gpt-6.1-sol"
CLI_VERSION = "0.162.1"


def search_policy_status():
    if not settings.codex_web_search:
        return "Websuche aus: Die Lern-KI verwendet nur die bereitgestellten Unterlagen."
    if settings.codex_auth_mode == "account":
        return (
            "Websuche an: Ein Anbieteraufruf je Auftrag, höchstens 145 Sekunden. "
            "Die Anzahl der Suchen wird nachträglich erfasst; keine feste Obergrenze je Antwort."
        )
    return "Websuche an: Höchstens eine Suche je Anbieterantwort."


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
        if not (
            data.get("isolated") is True
            and data.get("cli_search") is True
            and data.get("search") is settings.codex_web_search
            and data.get("cli_version") == CLI_VERSION
        ):
            return {"ready": False, "status": "Codex-Isolation, Websuche oder CLI-Version ist nicht bestätigt."}
        if data.get("auth_mode") != settings.codex_auth_mode:
            return {
                "ready": False,
                "status": "Codex bitte auf dem Server über schulpilot-codex login verbinden. Anmeldung oder passende Anmeldeart fehlt.",
            }
        return {
            "ready": True,
            "status": "Isolierter Codex-Worker erreichbar, eigene Anmeldung vorhanden. "
            + search_policy_status()
            + " Ein echter Bild-/Aufgabentest ist separat erforderlich.",
            "web_search": settings.codex_web_search,
            "cli_search": True,
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
        config.reasoning_effort = "medium"
        config.encrypted_key = None
        config.image_capable = config.structured_capable = True
        config.capability_evidence = (
            "Official Codex docs checked 2026-10-15; CLI 0.162.1; --search; image/schema; actual probe required"
            + "; web_search="
            + str(settings.codex_web_search).lower()
        )
        config.extraction_capability_evidence = "Official Codex docs checked 2026-10-15; CLI 0.162.1; OCR image/schema; actual probe required; web_search=false"
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
        audit(
            db,
            "local-operator",
            "provider.codex_search_policy",
            "account_web_search_no_preexecution_search_cap"
            if settings.codex_auth_mode == "account" and settings.codex_web_search
            else "api_single_search"
            if settings.codex_web_search
            else "source_only",
        )
    print(
        json.dumps(
            {
                "provider": "codex",
                "model": MODEL,
                "search": settings.codex_web_search,
                "cli_search": True,
                "web_search": settings.codex_web_search,
                "search_policy": search_policy_status(),
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


# This is a private protocol schema, not a list of guessed provider capabilities.
# Actual model IDs/effort options always come from the isolated pinned CLI.
class CatalogModel(BaseModel):
    model_config = {"extra": "forbid", "strict": True}
    id: str = Field(min_length=1, max_length=160, pattern=r"^[A-Za-z0-9][A-Za-z0-9._/-]{0,159}$")
    name: str = Field(min_length=1, max_length=160)
    reasoning_efforts: list[str] = Field(max_length=32)
    default_reasoning_effort: str
    input_modalities: list[str] = Field(max_length=3)
    hidden: bool


def worker_models():
    """Read bounded metadata over the fixed private socket; never infer or log in."""
    unavailable = "Der Codex-Modellkatalog ist gerade nicht erreichbar. Bitte später erneut laden."
    if not settings.codex_approved or not settings.codex_socket:
        raise HTTPException(503, "Der isolierte Codex-Lernworker ist noch nicht eingerichtet.")
    try:
        transport = httpx.HTTPTransport(uds=settings.codex_socket)
        with httpx.Client(transport=transport, timeout=httpx.Timeout(12, connect=2), follow_redirects=False) as client:
            with client.stream("GET", "http://localhost/models") as response:
                if response.status_code == 429:
                    raise HTTPException(
                        429, "Der Codex-Worker ist gerade belegt. Bitte den Modellkatalog später laden."
                    )
                if response.status_code != 200:
                    raise HTTPException(503, unavailable)
                raw = bytearray()
                for chunk in response.iter_bytes():
                    raw.extend(chunk)
                    if len(raw) > 256 * 1024:
                        raise HTTPException(503, "Der Codex-Modellkatalog ist zu groß oder ungültig.")
        data = json.loads(raw)
        if (
            not isinstance(data, dict)
            or set(data) != {"models", "source", "cli_version"}
            or (
                data["source"] != "codex_cli"
                or data["cli_version"] != CLI_VERSION
                or not isinstance(data["models"], list)
                or not 1 <= len(data["models"]) <= 200
            )
        ):
            raise ValueError("invalid catalog")
        models, seen = [], set()
        for item in data["models"]:
            model = CatalogModel.model_validate(item)
            if model.id in seen or any(ord(c) < 32 for c in model.name):
                raise ValueError("invalid catalog entry")
            seen.add(model.id)
            efforts = model.reasoning_efforts
            if (
                len(efforts) != len(set(efforts))
                or any(
                    not re.fullmatch(r"[a-z][a-z0-9_-]{0,31}", effort)
                    for effort in [*efforts, model.default_reasoning_effort]
                )
                or (efforts and model.default_reasoning_effort not in efforts)
            ):
                raise ValueError("invalid effort metadata")
            if len(model.input_modalities) != len(set(model.input_modalities)) or any(
                mode not in ("text", "image", "audio") for mode in model.input_modalities
            ):
                raise ValueError("invalid input modalities")
            models.append(model.model_dump())
        return {"models": models, "source": "codex_cli", "cli_version": CLI_VERSION}
    except HTTPException:
        raise
    except (httpx.HTTPError, ValueError, TypeError, AttributeError, ValidationError):
        # Do not echo the worker's response, auth data or exception text.
        raise HTTPException(503, unavailable) from None
