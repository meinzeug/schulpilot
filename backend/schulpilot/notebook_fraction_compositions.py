"""Finite source-backed cores for explicitly selected mixed-number notebook rounds.

The existing composition compiler owns source/reference/arithmetic proofs and
rendering. This local plan closes only the remaining ordinary practice slots;
curated prerequisite probes retain their exact independent learning-entry core.
"""

import copy

from . import learning_entry
from . import unit_fraction_compositions as composition
from .fraction_practice_plan import _bases, history
from .package_prepared_graphics import _digest

REVISION = "notebook-fraction-composition-1"
KEY = "notebook_composition_plan"
HISTORY_KEY = "notebook_composition_exclusions"
CORE = learning_entry.CORE
ERROR = (
    "Die Umwandlungsrunde lässt sich nicht vollständig an ihre bestätigten Originalbrüche und "
    "den Lernstart binden. Es wurde keine KI-Anfrage gesendet."
)
EXHAUSTED = (
    "Auf diesen Heftseiten sind keine weiteren neuen Umwandlungsaufgaben für die gewählte Runde verfügbar. "
    "Wähle eine andere bestätigte Heftseite oder weniger Aufgaben. Es wurde keine KI-Anfrage gesendet."
)
CURRENT_ERROR = (
    "Eine Umwandlungsaufgabe wurde inzwischen bereits verwendet oder ihr Lernstart geändert. "
    "Die neue Runde wurde nicht übernommen. Deine bisherigen Antworten bleiben gespeichert."
)


def applies(payload):
    from .notebook_fraction_expansions import _supported as expansion_supported
    from .notebook_practice import requested_count

    context = payload.get("visual_context") or {}
    sources = [source for source in context.get("sources", []) if not source.get("source_type")]
    return (
        requested_count(payload) is not None
        and payload.get("required_subject") == "Mathematik"
        and context.get("required") is True
        and bool(sources)
        and not expansion_supported(payload)
        and all(composition.eligible(source) for source in sources)
        and bool(composition.compile_candidates(context))
        and not any(
            payload.get(key)
            for key in (
                "goal",
                "review",
                "study_block",
                "selected_groups",
                "homework_practice",
                "exam_preparation",
                "exam_review_practice",
                "math_tasks",
                "notebook_expansion_plan",
                "notebook_multiples_plan",
            )
        )
    )


def with_history(payload, prompts):
    if not applies(payload):
        return payload
    candidates = composition.compile_candidates(payload["visual_context"])
    return {**payload, HISTORY_KEY: history(candidates, prompts)}


def _slots(payload, count):
    entry = payload.get("learning_entry")
    if not entry:
        return [{"id": f"q{index + 1}", "role": "practice"} for index in range(count)]
    plans = entry.get("units") or []
    if (
        len(plans) != 1
        or plans[0].get("group_id") is not None
        or plans[0].get("subject") != "Mathematik"
        or plans[0].get("entry_mode") not in ("prerequisite_probe", "reuse_evidence")
    ):
        raise ValueError(ERROR)
    slots = learning_entry._specs(plans[0], count)
    if not any(slot.get("role") == "practice" for slot in slots) or any(
        slot.get("role") == "prior_check" and any(key not in slot for key in CORE) for slot in slots
    ):
        raise ValueError(ERROR)
    return slots


def _history(candidates, payload):
    value = payload.get(HISTORY_KEY)
    empty = history(candidates, [])
    pool = {_digest(candidate["proof"]["input"]) for candidate in _bases(candidates)}
    if (
        not isinstance(value, dict)
        or set(value) != set(empty)
        or type(value.get("version")) is not int
        or value["version"] != 1
        or value.get("revision") != empty["revision"]
        or value.get("pool_digest") != empty["pool_digest"]
        or type(value.get("unknown_conversion")) is not bool
        or not isinstance(value.get("used_values"), list)
        or len(value["used_values"]) > len(pool)
        or any(not isinstance(item, str) for item in value["used_values"])
        or len(set(value["used_values"])) != len(value["used_values"])
    ):
        raise ValueError(ERROR)
    # The only legitimate values are the canonical values this same finite
    # compiler produces; no arbitrary private history can enter the payload.
    allowed = set(
        history(
            candidates,
            [
                f"Schreibe {c['proof']['input'][0]}/{c['proof']['input'][1]} als gemischte Zahl."
                for c in _bases(candidates)
            ],
        )["used_values"]
    )
    if not set(value["used_values"]) <= allowed:
        raise ValueError(ERROR)
    return value


def prepare(payload):
    from .notebook_practice import requested_count

    if not applies(payload):
        if KEY in payload or HISTORY_KEY in payload:
            raise ValueError(ERROR)
        return payload
    candidates = composition.compile_candidates(payload["visual_context"])
    exclusions = _history(candidates, payload)
    slots = _slots(payload, requested_count(payload))
    practices = [slot for slot in slots if slot["role"] == "practice"]
    probes = [{key: copy.deepcopy(slot[key]) for key in CORE} for slot in slots if slot["role"] == "prior_check"]
    for probe in probes:
        source = next(
            (
                source
                for source in payload["visual_context"]["sources"]
                if source.get("source_type") == "curated_foundation"
                and source.get("example_question_id") == probe["id"]
                and source.get("example_digest") == _digest(probe)
            ),
            None,
        )
        if source is None:
            raise ValueError(ERROR)
    # A newly shown prerequisite input is teaching/checking within this round,
    # not historical achievement; avoid repeating its value as a practice task.
    probe_values = history(candidates, [probe["prompt"] for probe in probes])["used_values"]
    used = set(exclusions["used_values"]) | set(probe_values)
    from fractions import Fraction

    available = [
        candidate for candidate in _bases(candidates) if str(Fraction(*candidate["proof"]["input"])) not in used
    ]
    if exclusions["unknown_conversion"] or len(available) < len(practices):
        raise ValueError(EXHAUSTED)
    tasks = []
    for slot, candidate in zip(practices, available[: len(practices)], strict=True):
        n, d = candidate["proof"]["input"]
        whole, remainder = candidate["proof"]["whole"], candidate["proof"]["remainder"]
        core = {
            "id": slot["id"],
            "type": "short",
            "prompt": f"Schreibe {n}/{d} als gemischte Zahl.",
            "answer": f"{whole} {remainder}/{d}",
            "options": [],
            "accepted": [],
        }
        tasks.append({"candidate_id": candidate["id"], "question_core": core})
    plan = {
        "version": 1,
        "revision": REVISION,
        "context_digest": _digest(payload["visual_context"]),
        "exclusion_digest": _digest(exclusions),
        "question_count": requested_count(payload),
        "tasks": tasks,
        "probes": probes,
    }
    if KEY in payload and payload[KEY] != plan:
        raise ValueError(ERROR)
    return {**payload, KEY: plan}


def bind_candidates(payload, candidates):
    if KEY not in payload:
        return candidates
    if prepare(payload) != payload:
        raise ValueError(ERROR)
    choices = {candidate["id"]: candidate for candidate in candidates}
    selected = []
    for task in payload[KEY]["tasks"]:
        candidate = copy.deepcopy(choices.get(task["candidate_id"]))
        if not candidate or candidate.get("disclosure") != "solution" or not candidate.get("proof"):
            raise ValueError(ERROR)
        candidate.update(question_core=copy.deepcopy(task["question_core"]), planned_notebook=REVISION)
        selected.append(candidate)
    return [*[candidate for candidate in candidates if candidate["disclosure"] == "given"], *selected]


def validate_output(payload, data):
    if KEY not in payload:
        return
    plan = prepare(payload)[KEY]
    cores = {core["id"]: core for core in [*plan["probes"], *[task["question_core"] for task in plan["tasks"]]]}
    questions = data.get("questions")
    if (
        not isinstance(questions, list)
        or len(questions) != plan["question_count"]
        or {q.get("id") for q in questions} != set(cores)
        or any(any(q.get(key) != value for key, value in cores[q["id"]].items()) for q in questions)
    ):
        raise ValueError(ERROR)


def validate_history(payload, data, prompts):
    if KEY not in payload:
        return
    try:
        current = prepare(with_history({key: value for key, value in payload.items() if key != KEY}, prompts))
        validate_output(current, data)
    except ValueError as error:
        if error.args not in ((ERROR,), (EXHAUSTED,)):
            raise
        raise ValueError(CURRENT_ERROR) from None
