"""Operator-only, stdin key import for the explicitly authorized free fixture.

No default admin, no real-data approval, no development authentication reused.
"""

import sys

from sqlalchemy import update

from .db import DB, ProviderConfig, init_db
from .providers import verify_free_endpoint
from .security import audit, encrypt


def configure():
    key = sys.stdin.read(1025).strip()
    if len(key) < 32 or len(key) > 1024 or any(c.isspace() for c in key):
        raise SystemExit("A valid dedicated OpenRouter key must be supplied through stdin")
    text_model, text_upstream = "nvidia/nemotron-3-super-120b-a12b:free", "nvidia"
    image_model, image_upstream = "dots-studio/dots-3-note-preview:free", "atlas-cloud/fp8"
    verify_free_endpoint(text_model, text_upstream)
    verify_free_endpoint(image_model, image_upstream, image=True)
    init_db()
    with DB.begin() as db:
        config = db.get(ProviderConfig, 1)
        config.provider, config.model, config.extraction_model = "openrouter", text_model, image_model
        config.encrypted_key = encrypt(key)
        config.emergency_stop = False
        config.privacy_approved = False
        config.privacy_evidence = ""
        config.image_capable = config.structured_capable = True
        config.capability_evidence = (
            "upstream=" + text_upstream + " synthetic-schema-test 2026-10-14; OpenRouter models/endpoints API"
        )
        config.extraction_capability_evidence = (
            "upstream=" + image_upstream + " synthetic-image-test 2026-10-14; OpenRouter models/endpoints API"
        )
        config.input_per_million_micros = config.output_per_million_micros = 0
        config.pricing_evidence = "2026-10-14 https://openrouter.ai/api/v1/models ; exact free endpoints rechecked per request; max_price prompt/completion/request=0"
        config.reserve_micros = 1000
        config.max_output_tokens = 7000
        config.status = "Nur festes synthetisches Testblatt freigegeben. Bild- und Schemaaufrufe tatsächlich getestet. Echte Kinderdaten bleiben gesperrt."
        db.execute(update(ProviderConfig).where(ProviderConfig.id == 1).values(revision=ProviderConfig.revision + 1))
        audit(db, "local-cli", "provider.configure_free_fixture", "openrouter")
    print("Free fixture providers configured; key encrypted; real-data approval remains disabled.")


if __name__ == "__main__":
    configure()
