"""Controlled categories; never surface upstream bodies or claim zero cost."""

import re

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
    "decision_shape",
    "decision_refs",
    "decision_closed",
    "decision_not_new",
    "decision_flow",
}


def message_code(message):
    value = message.casefold()
    if "konservative kostenreservierung" in value:
        return "cost_preflight"
    if "lernumfang" in value and ("erreicht" in value or "kostenlimit" in value):
        return "quota_exhausted"
    if "beschäftigt" in value or re.search(r"\b(?:worker|ki|anbieter|modell|dienst)\b.{0,40}\bbelegt\b", value):
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
            "sachantwort ist nicht im bestätigten material belegt",
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


def generation_availability(db, family, function, *, child_id=None, job_id=None, routing_features=None):
    """A read-only explanation, never a reservation or promise under concurrency."""
    from datetime import datetime, timezone

    from .db import ProviderConfig, UsageBucket
    from .providers import ProviderError, config_for_function, external_allowed, usage_summary

    config = db.get(ProviderConfig, 1)
    if not config:
        return {"code": "not_configured", "message": "Die Lern-KI ist noch nicht eingerichtet."}
    # Preflight the same selected route as the upcoming explicit reservation,
    # never the potentially larger base reserve. This is not a reservation.
    from .model_routing import enabled, features_for, select_route

    try:
        config = (select_route(config, function,
            routing_features if routing_features is not None else features_for(db, child_id, job_id))
            if enabled(config) else config_for_function(config, function))
    except HTTPException as error:
        return {"code": "not_configured", "message": str(error.detail)}
    from .child_cost_controls import preflight

    configured_child, child_blocker = preflight(db, child_id, config.reserve_micros)
    if child_blocker:
        return child_blocker
    summary = usage_summary(db, family)
    if (
        summary["access"]["state"] not in ("existing", "active", "trial")
        or (not configured_child and (not summary["calls_remaining"]
            or summary["budget_remaining_micros_usd"] < config.reserve_micros))
    ):
        return {
            "code": "quota_exhausted",
            "message": "Neue KI-Verarbeitung ist durch das Aufruf- oder Kostenlimit begrenzt. Gespeicherte Aufgaben und Erklärungen kannst du weiter nutzen.",
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
        external_allowed(config, image=function == "extract")
    except ProviderError as error:
        return {"code": "not_configured", "message": str(error)}
    return None
