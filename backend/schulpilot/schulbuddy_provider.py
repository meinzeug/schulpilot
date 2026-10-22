"""Explicit Codex Luna/high binding. Never a global provider switch or fallback.

ProviderConfig row2 belongs only to this feature. Local setup selects an actual
CLI catalogue model; a successful fixed synthetic probe and audit accept it.
"""

import json

from fastapi import HTTPException
from sqlalchemy import select

from .config import settings
from .db import Audit, ProviderConfig, now
from .model_routing import BudgetPolicy
from .providers import ProviderError, external_allowed
from .security import digest

BINDING_ID = 2
EFFORT = "high"


def catalog_model(model_id):
    from .codex_setup import worker_models

    catalog = worker_models()
    model = next((m for m in catalog["models"] if m["id"] == model_id), None)
    if (not model or "luna" not in model["name"].casefold() or EFFORT not in model["reasoning_efforts"]
            or "text" not in model["input_modalities"] or model["hidden"]):
        raise HTTPException(503, "Die ausdrücklich gewählte Luna/high-Route wird vom aktuellen Codex-Katalog nicht angeboten.")
    return model


def binding_key(config):
    return digest(json.dumps([config.revision, config.provider, config.model, config.reasoning_effort], separators=(",", ":")))


def budget_snapshot(base, config):
    try:
        budget = BudgetPolicy.model_validate((base.routing_policy or {})["budget"]).model_dump()
    except (KeyError, ValueError):
        raise HTTPException(503, "Für Schulbuddy fehlt die bestehende geprüfte Kinderbudget-Grenze.") from None
    if not -300 <= int(now()) - budget["fx_checked_at"] <= 31 * 86400:
        raise HTTPException(503, "Die Kostenumrechnung muss vor Schulbuddy-Aufrufen geprüft werden.")
    return {"budget": budget, "tier": "luna", "reason": "explicit_schulbuddy_high",
            "binding": binding_key(config), "provider_revision": base.revision}


def configured(db, *, verify_catalog=False, probe=False):
    base = db.get(ProviderConfig, 1, populate_existing=True)
    binding = db.get(ProviderConfig, BINDING_ID, populate_existing=True)
    if not base or not binding or binding.provider != "codex" or binding.reasoning_effort != EFFORT:
        raise HTTPException(503, "Schulbuddy ist noch nicht mit der ausdrücklich gewählten Luna/high-Route eingerichtet.")
    if settings.codex_auth_mode != "account":
        raise HTTPException(503, "Schulbuddy benötigt die dokumentierte eigene Codex-Kontoanmeldung; keine automatische API-Abrechnung.")
    if not probe:
        accepted = db.scalar(select(Audit.id).where(Audit.action == "schulbuddy.binding_accepted",
            Audit.target == binding_key(binding)).limit(1))
        if binding.production_block_reason or not accepted:
            raise HTTPException(503, "Schulbuddy wartet auf den mitgezählten künstlichen Luna/high-Fähigkeitstest.")
    if verify_catalog:
        catalog_model(binding.model)
    values = {c.name: getattr(binding, c.name) for c in ProviderConfig.__table__.columns}
    values.update(emergency_stop=base.emergency_stop or binding.emergency_stop,
                  global_limit_micros=min(base.global_limit_micros, binding.global_limit_micros),
                  reserve_micros=min(base.reserve_micros, binding.reserve_micros),
                  max_output_tokens=min(base.max_output_tokens, binding.max_output_tokens),
                  routing_policy={}, encrypted_key=None)
    config = ProviderConfig(**values)
    # Existing privacy, capability, isolation and operator stop guards apply.
    try:
        external_allowed(config, synthetic_fixture=probe)
    except ProviderError as e:
        raise HTTPException(503, str(e)) from None
    budget_snapshot(base, config)
    return config


def snapshot(db, config):
    base = db.get(ProviderConfig, 1, populate_existing=True)
    return {"provider": config.provider, "model": config.model, "reasoning_effort": config.reasoning_effort,
            "binding_revision": config.revision, "provider_revision": base.revision,
            "binding_key": binding_key(config), "budget": budget_snapshot(base, config)["budget"]}


def select_local(db, model_id, privacy_evidence):
    """Explicit local operator action, not reachable from public/admin HTTP."""
    from .codex_setup import worker_health
    from .security import audit

    model = catalog_model(model_id)
    if not worker_health()["ready"] or settings.codex_auth_mode != "account":
        raise HTTPException(503, "Der eigene isolierte Codex-Kontozugang ist nicht bereit.")
    if len(privacy_evidence.strip()) < 20 or len(privacy_evidence) > 500:
        raise HTTPException(422, "Die ausdrückliche Schulbuddy-Datenschutzentscheidung dokumentieren.")
    base = db.get(ProviderConfig, 1)
    old = db.get(ProviderConfig, BINDING_ID)
    values = {c.name: getattr(base, c.name) for c in ProviderConfig.__table__.columns}
    values.update(id=BINDING_ID, revision=old.revision + 1 if old else 1, provider="codex", model=model["id"],
        reasoning_effort=EFFORT, extraction_model="", encrypted_key=None, routing_policy={},
        image_capable=False, structured_capable=True, capability_evidence="Actual isolated CLI catalogue; strict-schema synthetic probe pending.",
        privacy_approved=True, privacy_evidence=privacy_evidence, input_per_million_micros=None, output_per_million_micros=None,
        pricing_evidence="Codex account: USD cost unknown; keep the complete existing reservation and all family/system/child limits.",
        production_block_reason="Schulbuddy: fixed synthetic schema probe required.", status="Schulbuddy probe pending")
    if old:
        for key, value in values.items():
            setattr(old, key, value)
    else:
        old = ProviderConfig(**values)
        db.add(old)
    audit(db, "local-operator", "schulbuddy.binding_selected", binding_key(old))
    db.flush()
    return old


def accepted_probe(db, config, job):
    """Accept only the completed fixed synthetic report for this exact binding."""
    from .security import audit

    current = db.get(ProviderConfig, BINDING_ID, populate_existing=True)
    if (not current or binding_key(current) != binding_key(config) or job.config_revision != config.revision
            or job.status != "completed" or len(job.report or []) != 1
            or not job.report[0].get("available") or job.report[0].get("model") != config.model
            or job.report[0].get("reasoning_effort") != EFFORT or job.report[0].get("fixture") != "schulbuddy-v1"):
        raise HTTPException(409, "Der Schulbuddy-Prüfbeleg passt nicht zur gewählten Modellrevision.")
    current.production_block_reason = ""
    current.capability_evidence = "Fixed artificial Schulbuddy schema/citation probe=" + job.id
    current.status = "Schulbuddy Luna/high fixed synthetic probe accepted; account USD unknown"
    audit(db, "local-operator", "schulbuddy.binding_accepted", binding_key(current))
