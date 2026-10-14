"""Local, explicit, free-only private-routing check with fixed synthetic data."""

import json

from sqlalchemy import update

from .db import DB, ProviderConfig
from .providers import ProviderError, config_for_function, request_provider
from .security import audit


def run():
    with DB() as db:
        config = db.get(ProviderConfig, 1)
        revision = config.revision
        configs = [config_for_function(config, function) for function in ("extract", "unit", "package")]
    if any(c.provider != "openrouter" or not c.model.endswith(":free") for c in configs):
        raise SystemExit("This command only probes explicitly selected free OpenRouter models.")
    results = []
    for function, config in zip(("extract", "unit", "package"), configs, strict=True):
        try:
            result = request_provider(config, function, {}, synthetic_fixture=True, private_probe=True)
            results.append({"function": function, "available": True, "cost_micros_usd": result.cost_micros})
        except ProviderError as error:
            results.append({"function": function, "available": False, "cost_micros_usd": None, "error": str(error)})
    ready = all(r["available"] for r in results)
    reason = (
        ""
        if ready
        else (
            "Die konfigurierten kostenlosen Endpunkte erfüllen die eingestellte Route nicht oder liefern keine gültige Ausgabe. Kein Ersatzanbieter wird verwendet."
        )
    )
    with DB.begin() as db:
        config = db.get(ProviderConfig, 1)
        if config.revision != revision:
            raise SystemExit("Configuration changed during probe; result was not activated.")
        config.production_block_reason = reason
        config.status = "Geschützte Route mit festen künstlichen Bild-/Textdaten geprüft." if ready else reason
        db.execute(update(ProviderConfig).where(ProviderConfig.id == 1).values(revision=ProviderConfig.revision + 1))
        audit(db, "local-cli", "provider.private_route_probe", "ready" if ready else "unavailable")
    print(
        json.dumps(
            {
                "synthetic_only": True,
                "private_route_ready": ready,
                "data_collection": "deny",
                "require_zdr": configs[0].openrouter_require_zdr,
                "calls": results,
            }
        )
    )


if __name__ == "__main__":
    run()
