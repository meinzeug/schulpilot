"""Source-bound exclusions for consciously requested general notebook rounds.

Only question prompts leave the DB as bounded exclusion context. Saved answers
and evidence never change; complete fresh history remains the publication gate.
"""

import unicodedata

from sqlalchemy import and_, func, or_, select

from .db import LearningUnit, Material, UnitSource
from .grades import subject_key
from .providers import ProviderError

CONTEXT_QUESTIONS = 80
CONTEXT_CHARACTERS = 12_000
_SPECIAL = ("review_of", "homework_practice", "exam_round_id", "exam_review_practice")


def applies(job, material):
    return (job.kind == "unit" and material is not None and not material.synthetic
        and not material.fixture_id and not any(job.payload.get(key) for key in _SPECIAL))


def normalized_prompt(value):
    # A capital letter can change a scientific symbol or an original word.
    return " ".join(unicodedata.normalize("NFC", value).split())


def _subject(columns, source):
    labels = [source.subject.strip().lower()]
    if subject_key(source.subject) == "mathematik":
        labels = ["mathematik", "mathe"]
    by_label = func.lower(func.trim(columns.subject)).in_(labels)
    if source.subject_id:
        return or_(columns.subject_id == source.subject_id,
            and_(columns.subject_id.is_(None), by_label))
    return by_label


def _current_sources(db, child_id, sources):
    snapshots = [(source.id, source.revision) for source in sources]
    if not snapshots or len(set(snapshots)) != len(snapshots):
        raise ProviderError("Die Quellen der neuen Heft-Runde sind nicht mehr aktuell.")
    current = []
    for identifier, revision in snapshots:
        source = db.get(Material, identifier, populate_existing=True)
        if (not source or source.child_id != child_id or not source.confirmed
                or source.purpose == "exam" or source.revision != revision):
            raise ProviderError("Die Quellen der neuen Heft-Runde sind nicht mehr aktuell.")
        current.append(source)
    return current


def previous_prompts(db, child_id, sources):
    """All relevant saved prompts, ordered oldest first; no Attempt values.

    Exact source revisions include standalone rounds. Related day stages also
    qualify through their day pointer or current same-subject source links.
    A legacy direct material pointer without links is an exclusion, never proof
    that its old question was generated from today's material revision.
    """
    current = _current_sources(db, child_id, sources)
    exact_links = select(UnitSource.unit_id).where(or_(*[
        and_(UnitSource.material_id == source.id, UnitSource.revision == source.revision)
        for source in current]))
    linked = select(UnitSource.unit_id)
    selection = [LearningUnit.id.in_(exact_links), and_(
        LearningUnit.material_id.in_([source.id for source in current]),
        LearningUnit.id.not_in(linked))]
    seen_days = set()
    for source in current:
        scope = (source.school_day_id, source.subject_id, subject_key(source.subject))
        if not source.school_day_id or scope in seen_days:
            continue
        seen_days.add(scope)
        selection.append(and_(LearningUnit.school_day_id == source.school_day_id,
            _subject(LearningUnit, source)))
        day_materials = select(Material.id).where(Material.child_id == child_id,
            Material.school_day_id == source.school_day_id, _subject(Material, source))
        day_links = select(UnitSource.unit_id).join(Material, Material.id == UnitSource.material_id).where(
            Material.id.in_(day_materials), UnitSource.revision == Material.revision)
        selection.append(LearningUnit.id.in_(day_links))
        selection.append(and_(LearningUnit.material_id.in_(day_materials), LearningUnit.id.not_in(linked)))
    rows = db.execute(select(LearningUnit.questions).where(LearningUnit.child_id == child_id,
        or_(*selection)).order_by(LearningUnit.created, LearningUnit.id))
    return [question["prompt"] for (questions,) in rows for question in questions
        if isinstance(question.get("prompt"), str) and question["prompt"].strip()]


def provider_context(prompts):
    """Keep complete recent questions within both bounds; never cut a prompt."""
    selected, used, seen = [], 0, set()
    for prompt in reversed(prompts):
        signature = normalized_prompt(prompt)
        if signature in seen:
            continue
        seen.add(signature)
        if len(prompt) + used > CONTEXT_CHARACTERS:
            continue
        selected.append(prompt)
        used += len(prompt)
        if len(selected) == CONTEXT_QUESTIONS:
            break
    return list(reversed(selected))


def validate_output(db, child_id, sources, data):
    """Call after the existing Child publication lock and source checks."""
    current = _current_sources(db, child_id, sources)
    history = previous_prompts(db, child_id, current)
    seen = {normalized_prompt(prompt) for prompt in history}
    mathematical = (subject_key(data["subject"]) == "mathematik"
        and any(subject_key(source.subject) == "mathematik" for source in current))
    if mathematical:
        from .coaching import fraction_task_signature

        numbers = {fraction_task_signature(prompt) for prompt in history} - {None}
    else:
        numbers = set()
    for question in data["questions"]:
        prompt = question["prompt"]
        signature = normalized_prompt(prompt)
        arithmetic = fraction_task_signature(prompt) if mathematical else None
        if signature in seen or (arithmetic is not None and arithmetic in numbers):
            raise ProviderError("Die neue Heft-Runde wiederholt eine bereits gestellte Frage. Deine bisherigen Antworten bleiben erhalten.")
        seen.add(signature)
        if arithmetic is not None:
            numbers.add(arithmetic)
