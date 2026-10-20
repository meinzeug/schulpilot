"""Controlled categories; never surface upstream bodies or claim zero cost."""

from fastapi import HTTPException

CODES = {
    "quota_exhausted",
    "provider_busy",
    "provider_timeout",
    "provider_unavailable",
    "invalid_output",
    "unreadable_photo",
    "source_changed",
    "access_changed",
    "not_configured",
    "cost_preflight",
    "interrupted",
    "unknown",
}


def message_code(message):
    value = message.casefold()
    if "konservative kostenreservierung" in value:
        return "cost_preflight"
    if "lernumfang" in value and ("erreicht" in value or "kostenlimit" in value):
        return "quota_exhausted"
    if "beschäftigt" in value or "belegt" in value:
        return "provider_busy"
    if "unlesbar" in value or "nicht lesbar" in value:
        return "unreadable_photo"
    if any(
        s in value
        for s in (
            "aufgabenprüfung",
            "aufgabenstruktur",
            "lernziel",
            "lernantwort",
            "ungeprüfte",
            "ausgabe",
            "unvollständig",
        )
    ):
        return "invalid_output"
    if "geändert" in value or "quelle" in value:
        return "source_changed"
    if "anmelden" in value or "sitzung" in value or "familienberechtigung" in value:
        return "access_changed"
    if "freigabe" in value or "konfiguration" in value or "eingerichtet" in value:
        return "not_configured"
    return "unknown"


def failure_code(error):
    if getattr(error, "code", None) in CODES:
        return error.code
    if isinstance(error, HTTPException):
        if error.status_code == 429:
            return "quota_exhausted" if message_code(str(error.detail)) == "quota_exhausted" else "provider_busy"
        if error.status_code in (401, 403):
            return "access_changed"
        return message_code(str(error.detail))
    return "unknown"


def generation_availability(db, family, function):
    """A read-only explanation, never a reservation or promise under concurrency."""
    from datetime import datetime, timezone

    from .db import ProviderConfig, UsageBucket
    from .providers import ProviderError, config_for_function, external_allowed, usage_summary

    config = db.get(ProviderConfig, 1)
    if not config:
        return {"code": "not_configured", "message": "Die Lern-KI ist noch nicht eingerichtet."}
    summary = usage_summary(db, family)
    if (
        summary["access"]["state"] not in ("existing", "active")
        or not summary["calls_remaining"]
        or summary["budget_remaining_micros_usd"] < config.reserve_micros
    ):
        return {
            "code": "quota_exhausted",
            "message": "Dein Lernumfang ist gerade aufgebraucht. Gespeicherte Aufgaben und Erklärungen kannst du weiter nutzen.",
        }
    period = datetime.now(timezone.utc).strftime("%Y-%m")
    global_bucket = db.get(UsageBucket, f"global:{period}")
    if config.emergency_stop or (
        global_bucket and global_bucket.encumbered_micros + config.reserve_micros > config.global_limit_micros
    ):
        return {
            "code": "not_configured",
            "message": "Neue KI-Schritte sind vorübergehend angehalten. Deine gespeicherten Inhalte bleiben da.",
        }
    try:
        external_allowed(config_for_function(config, function))
    except ProviderError as error:
        return {"code": "not_configured", "message": str(error)}
    return None
