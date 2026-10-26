"""Explicit evaluated routes, selected once before reservation. No LLM router."""

import hashlib
import json
from decimal import Decimal, InvalidOperation
from typing import Literal

from fastapi import HTTPException
from pydantic import Field, model_validator
from sqlalchemy import select

from .db import (
    Attempt,
    Child,
    Job,
    LearningUnit,
    Material,
    ProviderConfig,
    SchoolDay,
    TutorTurn,
    UnitSource,
    Usage,
    now,
)
from .schemas import Strict

ROUTING_VERSION = "school-2"
ROUTING_REASONING_EFFORT = "medium"
PROMPT_VERSION = "school-20261020-4"


class VisionBudget(Strict):
    """Explicit operator risk allowance, never a claimed provider token rule."""

    version: Literal[1] = 1
    basis: Literal["operator_estimate"]
    model: str = Field(min_length=3, max_length=160)
    upstreams: list[str] = Field(min_length=1, max_length=4)
    image_tokens: int = Field(ge=1000, le=100_000, strict=True)
    max_side: int = Field(ge=512, le=3200, strict=True)
    max_pixels: int = Field(ge=262144, le=16_000_000, strict=True)
    evidence: str = Field(min_length=20, max_length=500)
    approved_at: int = Field(ge=1, strict=True)


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
    vision_budget: VisionBudget | None = None

    @model_validator(mode="after")
    def exact_endpoints(self):
        import re

        if len(set(self.upstreams)) != len(self.upstreams) or any(
            not re.fullmatch(r"[a-z0-9_-]+(?:/[a-z0-9_.-]+)*", value) for value in self.upstreams
        ):
            raise ValueError("Nur ausdrücklich geprüfte Endpunktkennungen verwenden.")
        if self.under13_approved and (not self.evaluated or not self.privacy_evidence):
            raise ValueError("Kinderroute benötigt Evaluation und dokumentierte Datenschutzprüfung.")
        if self.vision_budget and (
            self.vision_budget.model != self.model or self.vision_budget.upstreams != self.upstreams
            or not self.evaluated or not self.image_capable
        ):
            raise ValueError("Die Bildkostenschätzung muss exakt zum geprüften Bildmodell und Endpunkt passen.")
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
    economy_mode: bool = False
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


_EXTRACTION_LENGTH_MESSAGE = (
    "Die KI hat die begrenzte Ausgabelänge erreicht. Die unvollständige Antwort wurde verworfen; "
    "kein automatischer Wiederholungsversuch."
)


def extraction_failed(db, child_id, material_id, *, material_revision=None):
    """Recorded need for the next request, never a retry or provider call.

    Keep exact-page retries. Other notebook pages may share a length observation
    only within the same child's actual photo day and while its failed source
    still exists there at the recorded revision. A corrected/deleted/moved source
    cannot supply that observation; unrelated pages need not remain unchanged.
    """
    material = db.get(Material, material_id) if material_id else None
    if (not material or material.child_id != child_id or (material_revision is not None
            and (type(material_revision) is not int or material_revision != material.revision))):
        return False
    if db.scalar(select(Job.id).where(
        Job.child_id == child_id, Job.kind == "extract", Job.status == "failed",
        Job.payload["material_id"].as_string() == material.id,
        Job.payload["material_revision"].as_integer() == material.revision,
        Job.error.contains("begrenzte Ausgabelänge"),
    ).limit(1)) is not None:
        return True
    if material.purpose != "notebook" or not material.school_day_id:
        return False
    return db.scalar(select(Job.id).join(Material,
        Material.id == Job.payload["material_id"].as_string()).join(SchoolDay,
        SchoolDay.id == Material.school_day_id).where(
        Job.child_id == child_id, Job.kind == "extract", Job.status == "failed",
        Job.error == _EXTRACTION_LENGTH_MESSAGE,
        Job.payload["school_day_id"].as_string() == material.school_day_id,
        Job.payload["material_revision"].as_integer() == Material.revision,
        Material.child_id == child_id, Material.purpose == "notebook",
        Material.school_day_id == material.school_day_id,
        SchoolDay.child_id == child_id,
    ).limit(1)) is not None


def extraction_recheck(db, child_id, job):
    """Carry recorded reading difficulty into one explicit same-photo recheck.

    The new upload intentionally has no inherited transcription. Its route may
    use the guarded original's reading metadata without copying that text or
    starting/retrying a job. Worker authority/source guards remain mandatory.
    """
    if not job or job.child_id != child_id or job.kind != "extract" or job.status != "queued":
        return False
    data = job.payload if isinstance(job.payload, dict) else {}
    guard = data.get("reprocess_guard")
    if not isinstance(guard, dict):
        return False
    source_id, clone_id = guard.get("source_id"), data.get("material_id")
    if (not isinstance(source_id, str) or not source_id or not isinstance(clone_id, str)
            or not clone_id or source_id == clone_id
            or type(guard.get("source_revision")) is not int or guard["source_revision"] < 1
            or type(data.get("material_revision")) is not int or data["material_revision"] < 1):
        return False
    with db.no_autoflush:
        source = db.get(Material, source_id, populate_existing=True)
        clone = db.get(Material, clone_id, populate_existing=True)
    if (not source or not clone or source.child_id != child_id or clone.child_id != child_id
            or source.revision != guard["source_revision"] or clone.revision != data["material_revision"]
            or source.purpose != "notebook" or clone.purpose != "notebook"
            or source.synthetic or clone.synthetic or source.fixture_id or clone.fixture_id
            or not isinstance(source.image_digest, str) or not source.image_digest.strip()
            or source.image_digest != clone.image_digest):
        return False
    return bool(source.uncertainties or source.legibility in ("partial", "unreadable"))


def study_length_failed(db, child_id, job):
    """Recorded output need for this exact unpublished stage's next request.

    No retry, reservation or stored-plan change. Rebuild the current safe-source
    fingerprint; matching opaque values in old job JSON alone are insufficient.
    """
    if not job or job.child_id != child_id or job.kind != "study_block" or job.status != "queued":
        return False
    data = job.payload or {}
    if any(not isinstance(data.get(key), str) or not data[key] for key in ("day_id", "block_id", "source_hash", "planning")):
        return False
    previous = db.scalars(select(Job).where(
        Job.child_id == child_id, Job.kind == "study_block", Job.status == "failed", Job.id != job.id,
        Job.payload["day_id"].as_string() == data["day_id"],
        Job.payload["block_id"].as_string() == data["block_id"],
        Job.payload["source_hash"].as_string() == data["source_hash"],
        Job.payload["planning"].as_string() == data["planning"],
    ).order_by(Job.created.desc(), Job.id.desc()).limit(3))
    if not any(isinstance(old.error, str) and " ".join(old.error.split()) == _EXTRACTION_LENGTH_MESSAGE for old in previous):
        return False
    day, child = db.get(SchoolDay, data["day_id"]), db.get(Child, child_id)
    if not day or day.child_id != child_id or not child:
        return False
    plan = day.learning_plan or {}
    block = next((row for row in plan.get("blocks", []) if row.get("id") == data["block_id"]), None)
    if not block or block.get("unit_id") or plan.get("source_hash") != data["source_hash"]:
        return False
    from .providers import ProviderError
    from .school_day import planning_fingerprint
    from .study_path import fingerprint, sources

    try:
        current = sources(db, day)
    except ProviderError:
        return False
    selected = block.get("material_ids") or []
    return (all(material.child_id == child_id and material.school_day_id == day.id for material in current)
        and bool(selected) and len(set(selected)) == len(selected)
        and set(selected) <= {material.id for material in current}
        and fingerprint(current, db) == data["source_hash"]
        and planning_fingerprint(db, child) == data["planning"])


def features_for(db, child_id, job_id):
    """Use bounded recorded facts, never client-selected difficulty or model IDs."""
    job = db.get(Job, job_id) if job_id is not None else None
    if job and job.child_id != child_id:
        raise HTTPException(403, "Dieser Auftrag gehört zu einem anderen Zugang.")
    data = job.payload if job else {}
    turn = db.get(TutorTurn, data.get("turn_id")) if data.get("turn_id") else None
    if turn and turn.child_id != child_id:
        raise HTTPException(403, "Diese Heftfrage gehört zu einem anderen Zugang.")
    unit_id = data.get("unit_id") or (turn.unit_id if turn else None)
    unit = db.get(LearningUnit, unit_id) if unit_id else None
    if unit and unit.child_id != child_id:
        raise HTTPException(403, "Diese Lernrunde gehört zu einem anderen Zugang.")
    attempts = list(db.scalars(select(Attempt).where(Attempt.unit_id == unit.id)
        .order_by(Attempt.created.desc(), Attempt.id.desc()).limit(40))) if unit else []
    material = db.get(Material, data.get("material_id")) if data.get("material_id") else None
    if material and material.child_id != child_id:
        raise HTTPException(403, "Diese Heftseite gehört zu einem anderen Zugang.")
    ids = {material.id} if material else set()
    refs = [*(data.get("sources") or []), *(data.get("material_revisions") or []),
            *(turn.source_revisions if turn else [])]
    if unit:
        if unit.material_id:
            ids.add(unit.material_id)
        ids.update(db.scalars(select(UnitSource.material_id).where(UnitSource.unit_id == unit.id)))
    day_id = data.get("day_id")
    if day_id and data.get("block_id"):
        day = db.get(SchoolDay, day_id)
        if day and day.child_id != child_id:
            raise HTTPException(403, "Dieser Lernplan gehört zu einem anderen Zugang.")
        if day:
            block = next((b for b in (day.learning_plan or {}).get("blocks", [])
                          if b.get("id") == data["block_id"]), {})
            ids.update(block.get("material_ids", []))
    ids.update(ref.get("id") or ref.get("material_id") for ref in refs if isinstance(ref, dict))
    ids.discard(None)
    sources = list(db.scalars(select(Material).where(Material.child_id == child_id, Material.id.in_(ids)))) if ids else []
    from .coach_routing import output_need as coach_output_need
    from .material_review import routing_check
    from .material_routing import extended_output as material_extended_output
    from .notebook_routing import extended_output as notebook_extended_output
    from .notebook_routing import length_failed as notebook_length_failed
    from .study_routing import extended_output as study_extended_output

    return {
        **coach_output_need(db, child_id, job),
        "errors": sum(a.outcome == "incorrect" for a in attempts),
        "uncertain": sum(a.outcome == "uncertain" for a in attempts),
        "poor_image": any(m.uncertainties or m.quality_warnings or m.legibility in ("partial", "unreadable") for m in sources),
        "extraction_failed": extraction_failed(db, child_id, material.id,
            material_revision=data.get("material_revision")) if material else False,
        "transcription_review": extraction_recheck(db, child_id, job) or routing_check(db, child_id, job),
        "study_length_failed": study_length_failed(db, child_id, job),
        "study_extended_output": study_extended_output(db, child_id, job),
        "notebook_length_failed": notebook_length_failed(db, child_id, job),
        "notebook_extended_output": notebook_extended_output(db, child_id, job),
        "material_extended_output": material_extended_output(db, child_id, job),
        "sources_known": bool(ids) and len(sources) == len(ids),
        "source_count": len(sources),
        "source_chars": sum(len(m.content or "") for m in sources),
        "subject_count": len({m.subject for m in sources}),
        "question_chars": len(turn.question) if turn else 0,
    }


def choose_tier(function, features, *, economy=False):
    # Start difficult material on the suitable route, without a trial cascade.
    if function == "extract" and features.get("extraction_failed"):
        return "sol", "recorded_transcription_failure"
    if function == "extract" and features.get("transcription_review"):
        return "sol", "recorded_transcription_review"
    if function in ("unit", "study_block") and features.get("study_length_failed"):
        return "sol", "recorded_study_output_length"
    if function == "unit" and features.get("notebook_length_failed"):
        return "sol", "recorded_notebook_output_length"
    if function == "coach_practice" and features.get("coach_length_failed"):
        return "sol", "recorded_coach_output_length"
    if economy:
        if function in ("unit", "study_block") and features.get("study_extended_output"):
            return "sol", "study_graphic_teaching"
        if function == "coach_practice" and features.get("coach_extended_output"):
            return "sol", "coach_graphic_teaching"
        if function == "unit" and features.get("notebook_extended_output"):
            return "sol", "notebook_graphic_teaching"
        if function == "unit" and features.get("material_extended_output"):
            return "sol", "material_graphic_teaching"
        if features.get("poor_image") or features.get("errors", 0) >= 2 or features.get("uncertain", 0):
            return "sol", "recorded_difficulty"
        if function in ("extract", "coach", "decision", "vocabulary_import"):
            if features.get("source_chars", 0) <= 8000:
                return "luna", "bounded_source_or_review"
        if features.get("sources_known"):
            if (function == "tutor" and features["source_count"] <= 4
                    and features["source_chars"] <= 8000 and features.get("question_chars", 0) <= 800):
                return "luna", "bounded_source_help"
            if (function in ("unit", "coach_practice", "controller_check", "study_block", "package")
                    and features["source_count"] <= 2 and features["source_chars"] <= 6000
                    and features.get("subject_count", 0) <= 1):
                return "luna", "focused_source_practice"
        return "sol", "extended_or_unclassified_teaching"
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
    tier, reason = choose_tier(function, features or {}, economy=policy.economy_mode)
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
        reasoning_effort=ROUTING_REASONING_EFFORT, image_capable=route.image_capable, structured_capable=route.evaluated,
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
