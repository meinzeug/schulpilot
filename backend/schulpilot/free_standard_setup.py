"""Explicit operator switch to the tested free OpenRouter standard.

Keeps provider data collection denied. No existing approval/key is fabricated.
The route stays blocked until the separate fixed-image/text/package probe passes.
"""

import json
import sys
from datetime import datetime, timezone

from sqlalchemy import update

from .config import runtime_settings
from .db import DB, ProviderConfig
from .providers import verify_free_endpoint
from .security import audit

FREE_MODEL = "dots-studio/dots-3-note-preview:free"
FREE_UPSTREAM = "atlas-cloud/fp8"


def configure():
    data = json.loads(sys.stdin.read(4096))
    evidence = data.get("evidence")
    if not isinstance(evidence, str) or not 20 <= len(evidence) <= 500:
        raise SystemExit("A documented operator approval must be supplied through stdin")
    if not runtime_settings().real_data_approved or not runtime_settings().privacy_evidence:
        raise SystemExit("The existing global operator approval must be recorded first")
    verify_free_endpoint(FREE_MODEL, FREE_UPSTREAM, image=True)
    today = datetime.now(timezone.utc).date().isoformat()
    with DB.begin() as db:
        config = db.get(ProviderConfig, 1)
        if config.provider != "openrouter" or not config.encrypted_key:
            raise SystemExit("An encrypted OpenRouter key must already be configured")
        config.model = config.extraction_model = FREE_MODEL
        config.openrouter_free_only = True
        config.openrouter_require_zdr = False
        config.privacy_approved = True
        config.privacy_evidence = evidence
        config.emergency_stop = False
        config.image_capable = config.structured_capable = True
        config.capability_evidence = config.extraction_capability_evidence = (
            f"upstream={FREE_UPSTREAM} {today} OpenRouter endpoints API; actual schema/image probes required"
        )
        config.input_per_million_micros = config.output_per_million_micros = 0
        config.pricing_evidence = (
            f"{today} https://openrouter.ai/api/v1/models/{FREE_MODEL}/endpoints; "
            "exact zero-price endpoint checked before every request; max_price=0; no fallback"
        )
        config.reserve_micros = 1000
        config.max_output_tokens = 7000
        config.production_block_reason = (
            "Kostenlose Standardroute gespeichert; Bild-, Aufgaben- und Tagespaketprüfung stehen noch aus."
        )
        config.status = config.production_block_reason
        db.execute(update(ProviderConfig).where(ProviderConfig.id == 1).values(revision=ProviderConfig.revision + 1))
        audit(db, "local-cli", "provider.configure_free_standard", "openrouter;deny;zdr=false;price=0")
    print("OpenRouter free standard configured; data collection denied; ZDR not required; probe before activation.")


if __name__ == "__main__":
    configure()
