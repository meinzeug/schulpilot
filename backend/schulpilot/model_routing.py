"""Explicit evaluated routes, selected once before reservation. No LLM router."""

import hashlib
import json
from decimal import Decimal, InvalidOperation
from typing import Literal

from fastapi import HTTPException
from pydantic import Field, model_validator
from sqlalchemy import select

from .db import Attempt, Job, LearningUnit, Material, ProviderConfig, Usage, now
from .schemas import Strict

ROUTING_VERSION = "school-1"
PROMPT_VERSION = "school-20261019-1"


class ModelRoute(Strict):
    model: str = Field(min_length=3, max_length=160, pattern=r"^[a-z0-9_.-]+/[a-z0-9_.:-]+$")
    upstreams: list[str] = Field(min_length=1, max_length=4)
    input_per_million_micros: int = Field(ge=0, le=100_000_000)
    output_per_million_micros: int = Field(ge=0, le=500_000_000)
    max_output_tokens: int = Field(ge=1000, le=8000)
    reserve_micros: int = Field(ge=1000, le=250_000)
    image_capable: bool = False
    reasoning: Literal["medium"] = "medium"
    capability_evidence: str = Field(min_length=12, max_length=500)
    pricing_evidence: str = Field(min_length=12, max_length=500)
    privacy_evidence: str = Field(default="", max_length=500)
    evaluated: bool = False
    under13_approved: bool = False
    verified_at: int = Field(ge=1)

    @model_validator(mode="after")
    def exact_endpoints(self):
        import re

        if len(set(self.upstreams)) != len(self.upstreams) or any(
            not re.fullmatch(r"[a-z0-9_-]+(?:/[a-z0-9_.-]+)*", value) for value in self.upstreams
        ):
            raise ValueError("Nur ausdrücklich geprüfte Endpunktkennungen verwenden.")
        if self.under13_approved and (not self.evaluated or not self.privacy_evidence):
            raise ValueError("Kinderroute benötigt Evaluation und dokumentierte Datenschutzprüfung.")
        return self


class BudgetPolicy(Strict):
    target_eur_micros: int = Field(default=7_000_000, ge=0, le=7_000_000)
    warning_eur_micros: int = Field(default=9_000_000, ge=0, le=9_000_000)
    hard_eur_micros: int = Field(default=12_000_000, ge=0, le=12_000_000)
    # Explicit conservative conversion, not a fabricated exchange rate.
    eur_per_usd: str = Field(max_length=24)
    fx_evidence: str = Field(min_length=12, max_length=500)
    fx_checked_at: int = Field(ge=1)
    fee_reserve_bps: int = Field(default=800, ge=0, le=5000)

    @model_validator(mode="after")
    def valid_money(self):
        try:
            rate = Decimal(self.eur_per_usd)
            if not rate.is_finite() or not Decimal("0.1") <= rate <= Decimal("10"):
                raise ValueError("Wechselkurs außerhalb der gültigen Grenzen.")
        except InvalidOperation:
            raise ValueError("Ungültiger Wechselkurs.") from None
        if not self.target_eur_micros <= self.warning_eur_micros <= self.hard_eur_micros:
            raise ValueError("Ziel, Warnung und Obergrenze müssen aufsteigend sein.")
        return self


class RoutingPolicy(Strict):
    version: Literal[1] = 1
    enabled: bool = False
    routes: dict[Literal["luna", "sol", "astra"], ModelRoute]
    budget: BudgetPolicy
    region: Literal["standard", "eu", "us"] = "standard"
    regional_access_evidence: str = Field(default="", max_length=500)
    revision: str = Field(min_length=1, max_length=60)

    @model_validator(mode="after")
    def required_routes(self):
        if "sol" not in self.routes or "luna" not in self.routes:
            raise ValueError("Geprüfte einfache und anspruchsvolle Route sind erforderlich.")
        if len({route.model for route in self.routes.values()}) != len(self.routes):
            raise ValueError("Jede Modellstufe benötigt eine eindeutige Modellkennung.")
        if self.region != "standard" and not self.regional_access_evidence:
            raise ValueError("Regionaler Kontozugang muss dokumentiert sein.")
        return self


def policy_hash(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def enabled(config):
    return config.provider == "openrouter" and bool((config.routing_policy or {}).get("enabled"))


def features_for(db, child_id, job_id):
    """Use bounded recorded facts, never client-selected difficulty or model IDs."""
    job = db.get(Job, job_id)
    data = job.payload if job else {}
    unit = db.get(LearningUnit, data.get("unit_id")) if data.get("unit_id") else None
    if unit and unit.child_id != child_id:
        raise HTTPException(403, "Diese Lernrunde gehört zu einem anderen Zugang.")
    attempts = list(db.scalars(select(Attempt).where(Attempt.unit_id == unit.id).limit(40))) if unit else []
    material = db.get(Material, data.get("material_id")) if data.get("material_id") else None
    if material and material.child_id != child_id:
        raise HTTPException(403, "Diese Heftseite gehört zu einem anderen Zugang.")
    return {
        "errors": sum(a.outcome == "incorrect" for a in attempts),
        "uncertain": sum(a.outcome == "uncertain" for a in attempts),
        "poor_image": bool(material and (material.uncertainties or material.quality_warnings
            or material.legibility in ("partial", "unreadable"))),
        "source_count": len(data.get("sources", data.get("material_revisions", []))),
    }


def choose_tier(function, features):
    # Start difficult material on the suitable route, without a trial cascade.
    if features.get("uncertain", 0) >= 2 and features.get("errors", 0) >= 3:
        return "astra", "recorded_ambiguity_after_support"
    if function == "extract" and not features.get("poor_image"):
        return "luna", "bounded_literal_transcription"
    if function in ("extract", "package", "unit", "tutor", "language_project", "controller_check", "coach_practice", "study_block"):
        return "sol", "material_or_new_teaching"
    if features.get("poor_image") or features.get("errors", 0) >= 2 or features.get("uncertain", 0):
        return "sol", "recorded_difficulty"
    return "luna", "bounded_structured_review"


def select_route(config, function, features=None, snapshot=None):
    policy_data = config.routing_policy or {}
    if not enabled(config):
        return config
    policy = RoutingPolicy.model_validate(policy_data)
    tier, reason = choose_tier(function, features or {})
    if snapshot:
        if snapshot.get("policy_hash") != policy_hash(policy_data):
            raise HTTPException(409, "Die KI-Einstellung wurde geändert. Bitte den aktuellen Lernschritt öffnen.")
        tier, reason = snapshot["tier"], snapshot["reason"]
    route = policy.routes.get(tier)
    if not route:
        raise HTTPException(503, "Für diesen Lernschritt fehlt eine geprüfte KI-Route. Gespeicherte Übungen bleiben nutzbar.")
    values = {c.name: getattr(config, c.name) for c in ProviderConfig.__table__.columns}
    selection = {
        "tier": tier, "reason": reason, "policy_hash": policy_hash(policy_data),
        "routing_version": ROUTING_VERSION, "prompt_version": PROMPT_VERSION,
        "policy_revision": policy.revision, "route": route.model_dump(),
        "budget": policy.budget.model_dump(), "region": policy.region,
    }
    values.update(
        model=route.model, extraction_model="", openrouter_free_only=False, openrouter_require_zdr=True,
        reasoning_effort="medium", image_capable=route.image_capable, structured_capable=route.evaluated,
        capability_evidence=route.capability_evidence, pricing_evidence=route.pricing_evidence,
        input_per_million_micros=route.input_per_million_micros,
        output_per_million_micros=route.output_per_million_micros,
        max_output_tokens=min(config.max_output_tokens, route.max_output_tokens),
        reserve_micros=min(config.reserve_micros, route.reserve_micros),
    )
    result = ProviderConfig(**values)
    result._selected_route = selection
    return result


def selection(config):
    # Worker copies persistent columns across its database boundary. Resolve the
    # already selected model from its policy, never re-route the job afterwards.
    if hasattr(config, "_selected_route"):
        return config._selected_route
    if enabled(config):
        policy = RoutingPolicy.model_validate(config.routing_policy)
        tiers = [(tier, route) for tier, route in policy.routes.items() if route.model == config.model]
        if len(tiers) != 1:
            raise HTTPException(503, "Keine eindeutige gebundene Modellroute vorhanden.")
        result = select_route(config, "unit", snapshot={
            "policy_hash": policy_hash(config.routing_policy), "tier": tiers[0][0], "reason": "reserved_route",
        })
        return result._selected_route
    return {}


def job_config(db, job, function=None):
    from .providers import config_for_function

    config = db.get(ProviderConfig, 1)
    guard = (job.payload or {}).get("controller_guard")
    if guard:
        from .learning_controller import generation_guard

        if generation_guard(db, guard["unit_id"]) != guard:
            raise HTTPException(409, "Der Lernschritt wurde inzwischen geändert. Die verspätete Antwort wird nicht übernommen.")
    usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
    if enabled(config) and usage and usage.route_snapshot:
        if usage.config_revision != config.revision:
            raise HTTPException(409, "Die KI-Einstellung wurde seit Auftragserstellung geändert.")
        return select_route(config, function or job.kind, snapshot=usage.route_snapshot)
    return config_for_function(config, function or job.kind)


def validate_ready(config, *, image=False, synthetic=False):
    value = selection(config)
    if not value:
        return
    route = value["route"]
    if (not route["evaluated"] and not synthetic) or (image and not route["image_capable"]):
        raise HTTPException(503, "Die KI-Route wurde für diesen Lernschritt noch nicht geprüft.")
    if not synthetic and not (route["under13_approved"] and route["privacy_evidence"]):
        raise HTTPException(503, "Die Datenschutzprüfung für diese Kinderroute ist noch offen.")
    budget = value["budget"]
    if not -300 <= int(now()) - budget["fx_checked_at"] <= 31 * 86400:
        raise HTTPException(503, "Die Kostenumrechnung muss vor weiteren KI-Aufrufen aktualisiert werden.")
    if not -300 <= int(now()) - route["verified_at"] <= 31 * 86400:
        raise HTTPException(503, "Modellfähigkeiten, Endpunkt und Preise müssen erneut geprüft werden.")
