"""Narrow legacy-review adapter for the existing fixed mixed-number compiler.

No job is relabelled. Only its already stored goals, current own notebook
sources and reserved Sol route may enable the existing two-question contract.
"""
import copy
import re

from . import unit_fraction_compositions as composition
from .db import LearningUnit
from .fraction_practice_plan import CURRENT_ERROR, INVALID, plan
from .package_prepared_graphics import _digest

_SPECIAL = ("assignment_id", "notebook_practice", "study_block", "homework_practice", "exam_round_id",
    "exam_review_practice", "controller_guard", "reprocess_guard", "groups")


def _id(value):
    return isinstance(value, str) and re.fullmatch(r"[a-f0-9]{32}", value) is not None


def _scope(db, job, child, material, pages, config, route, payload):
    data = job.payload
    if (job.kind != "unit" or job.status != "running" or job.child_id != child.id
            or config.provider != "openrouter" or route.get("tier") != "sol"
            or route.get("reason") != "material_graphic_teaching"
            or not _id(data.get("review_of")) or any(data.get(key) for key in _SPECIAL)
            or payload.get("practice_kind") not in (None, "check") or payload.get("practice_tasks")
            or any(payload.get(key) for key in ("goal", "selected_groups", "study_block", "notebook_practice",
                "homework_practice", "exam_preparation", "exam_review_practice", "math_tasks"))
            or material is None or material.child_id != child.id or material.id != data.get("material_id")
            or type(data.get("material_revision")) is not int or material.revision != data["material_revision"]
            or not pages or len({page.id for page in pages}) != len(pages)
            or material.id not in {page.id for page in pages}
            or any(not _id(page.id) or page.child_id != child.id or not page.confirmed
                or page.purpose != "notebook" or page.synthetic or page.fixture_id for page in pages)):
        return None
    refs = data.get("sources", []) or [{"id": material.id, "revision": material.revision}]
    if (not isinstance(refs, list) or any(not isinstance(ref, dict) or set(ref) != {"id", "revision"}
            or not _id(ref["id"]) or type(ref["revision"]) is not int for ref in refs)
            or len({ref["id"] for ref in refs}) != len(refs)
            or {(ref["id"], ref["revision"]) for ref in refs} != {(page.id, page.revision) for page in pages}):
        return None
    previous = db.get(LearningUnit, data["review_of"])
    if (previous is None or previous.child_id != child.id or previous.status != "completed"
            or previous.material_id != material.id or payload.get("review") is not True
            or payload.get("required_subject") != previous.subject or payload.get("required_topic") != previous.topic):
        return None
    sources = (payload.get("visual_context") or {}).get("sources", [])
    if "review_fraction_plan" in payload:
        sources = [source for source in sources if not source.get("source_type")]
    if (len(sources) != len(pages) or any(source.get("source_type") or source.get("group_id") is not None for source in sources)
            or {(source.get("material_id"), source.get("revision")) for source in sources}
                != {(page.id, page.revision) for page in pages}):
        return None
    return previous


def _goals(db, previous, payload):
    from .coaching import focus_ids, goals_for

    return (payload.get("learning_goals") == goals_for(db, previous)
        and payload.get("focus_goal_ids") == focus_ids(db, previous, "check"))


def _reference(db, payload):
    from .visual_reference_models import VisualReference

    existing = [ref for ref in payload["visual_context"]["references"] if ref.get("id") == composition.RECIPE]
    if existing:
        if len(existing) != 1 or type(existing[0].get("version")) is not int:
            raise ValueError(INVALID)
        ref = existing[0]
        row = db.get(VisualReference, (ref["id"], ref["version"]))
        if (row is None or row.digest != ref.get("digest") or _digest(row.recipe) != row.digest
                or ref.get("subject") != "Mathematik"):
            raise ValueError(INVALID)
        return payload
    result = composition.add_reference(db, payload)
    if not any(ref.get("id") == composition.RECIPE for ref in result["visual_context"]["references"]):
        raise ValueError(INVALID)
    return result


def _history(db, previous):
    """Relevant own chain across days plus all own questions on this day."""
    from .coaching import _practice_history_prompts, root_and_units

    _, chain = root_and_units(db, previous)
    prompts = [question["prompt"] for unit in chain if unit.child_id == previous.child_id
        for question in unit.questions]
    if previous.school_day_id:
        # The existing query is child-bound and unbounded; its day must augment,
        # never replace, older questions in the same relevant learning chain.
        prompts.extend(_practice_history_prompts(db, previous))
    if any(not isinstance(prompt, str) for prompt in prompts):
        raise ValueError(INVALID)
    return list(dict.fromkeys(prompts))


def prepare(db, job, child, material, pages, config, route, payload):
    """Before dispatch: prove scope and compute exactly two existing-goal cores."""
    previous = _scope(db, job, child, material, pages, config, route, payload)
    candidate = {**payload, "practice_kind": "check"}
    from . import review_fraction_plan

    mixed = review_fraction_plan.supported(candidate)
    if previous is None or not (composition._focused_practice(candidate) or mixed):
        return payload, None
    if not _goals(db, previous, candidate):
        raise ValueError(INVALID)
    from .providers import practice_tasks

    if mixed:
        candidate = review_fraction_plan.add_references(db, candidate)
        candidate = review_fraction_plan.prepare(review_fraction_plan.with_history(
            candidate, _history(db, previous), _digest([job.id, job.payload])))
    else:
        candidate = _reference(db, candidate)
        candidate = composition.with_practice_history(candidate, _history(db, previous))
        plan(composition.compile_candidates(candidate["visual_context"]), practice_tasks(candidate),
            candidate["fraction_practice_history"])
    receipt = {"job": _digest(job.payload), "previous": previous.id,
        "sources": copy.deepcopy(candidate["visual_context"]["sources"]),
        "goals": copy.deepcopy(candidate["learning_goals"]), "focus": copy.deepcopy(candidate["focus_goal_ids"])}
    return candidate, receipt


def validate(db, job, child, material, pages, config, route, payload, data, receipt):
    """After the Child lock: reject changed sources/goals or newly used values."""
    if receipt is None:
        return
    from . import review_fraction_plan

    previous = _scope(db, job, child, material, pages, config, route, payload)
    if (previous is None or previous.id != receipt["previous"] or _digest(job.payload) != receipt["job"]
            or not (composition._focused_practice(payload) or review_fraction_plan.supported(payload)) or not _goals(db, previous, payload)
            or payload.get("learning_goals") != receipt["goals"] or payload.get("focus_goal_ids") != receipt["focus"]
            or payload["visual_context"]["sources"] != receipt["sources"]):
        raise ValueError(CURRENT_ERROR)
    from .source_lineage import learning_source

    for page in pages:
        original = next(source for source in receipt["sources"] if source.get("material_id") == page.id)
        current = learning_source(db, page, revision=page.revision)
        if (original["subject"] != page.subject or original["topic"] != page.topic
                or any(original.get(key) != current.get(key) for key in ("content", "source_refs", "factual_status"))):
            raise ValueError(CURRENT_ERROR)
    try:
        _reference(db, payload)
    except ValueError:
        raise ValueError(CURRENT_ERROR) from None
    try:
        prompts = _history(db, previous)
    except ValueError:
        raise ValueError(CURRENT_ERROR) from None
    if review_fraction_plan.KEY in payload:
        try:
            if review_fraction_plan.add_references(db, payload) != payload:
                raise ValueError(CURRENT_ERROR)
        except ValueError:
            raise ValueError(CURRENT_ERROR) from None
        review_fraction_plan.validate_history(payload, data, prompts)
    else:
        composition.validate_practice_history(payload, data, prompts)
