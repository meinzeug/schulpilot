"""Explicit local switch; no secrets in JSON and no automatic privacy approval."""

import json
import sys

from pydantic import Field
from sqlalchemy import select

from .config import settings
from .db import DB, ProviderConfig
from .model_routing import RoutingPolicy
from .schemas import Strict
from .security import audit


class Configuration(Strict):
    policy: RoutingPolicy
    evidence: str = Field(min_length=20, max_length=500)
    reservation_micros: int | None = Field(default=None, ge=1000, le=250000)


def configure():
    raw = sys.stdin.read(65537)
    if len(raw.encode()) > 65536:
        raise SystemExit('Configuration exceeds 64 KiB')
    try:
        data = Configuration.model_validate_json(raw)
    except ValueError:
        raise SystemExit('Invalid routing configuration; use the documented schema. Input is not printed.') from None
    if not settings.openrouter_api_key:
        raise SystemExit('OPENROUTER_API_KEY must already exist in the protected server environment')
    policy = data.policy.model_dump()
    if not policy['enabled']:
        raise SystemExit('Explicit switch requires an enabled, versioned routing policy')
    with DB.begin() as db:
        config = db.scalar(select(ProviderConfig).where(ProviderConfig.id == 1).with_for_update())
        route = policy['routes']['sol']
        config.provider, config.model, config.routing_policy = 'openrouter', route['model'], policy
        config.extraction_model, config.reasoning_effort = '', 'medium'
        config.openrouter_free_only, config.openrouter_require_zdr = False, True
        config.image_capable, config.structured_capable = route['image_capable'], route['evaluated']
        config.capability_evidence, config.pricing_evidence = route['capability_evidence'], route['pricing_evidence']
        config.input_per_million_micros = route['input_per_million_micros']
        config.output_per_million_micros = route['output_per_million_micros']
        if data.reservation_micros is not None:
            previous = config.reserve_micros
            config.reserve_micros = data.reservation_micros
            audit(db, 'local-cli', 'provider.explicit_paid_reservation',
                  f'{previous}->{data.reservation_micros}; family/system quotas unchanged')
        # Global/family/call/output limits and emergency stop remain intact.
        # The accounting hold changes only through the explicit operator field.
        # Route flags are not operator consent.
        config.production_block_reason = 'Modellmix gespeichert; künstliche Bild-, Aufgaben- und Paketprüfung steht aus.'
        config.status = config.production_block_reason
        config.revision += 1
        audit(db, 'local-cli', 'provider.configure_openrouter_mix', policy['revision'])
        audit(db, 'local-cli', 'provider.switch_evidence', data.evidence[:80])
    print(json.dumps({'configured': True, 'provider': 'openrouter', 'synthetic_probe_required': True,
        'privacy_route_flags_preserved': True, 'quotas_preserved': True,
        'existing_reservation_preserved': data.reservation_micros is None,
        'explicit_reservation_micros': data.reservation_micros}))
