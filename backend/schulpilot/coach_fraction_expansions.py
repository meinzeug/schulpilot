"""Closed expansion proofs for explicit, goal-bound follow-up exercises.

The existing arithmetic planner owns the questions. This adapter binds its
understand/recall variants to the existing reviewed two-fraction renderer.
"""
import copy
import re
from dataclasses import dataclass

from . import study_fraction_expansions as expansion
from .math_tasks import _numbers, _procedure_quote, _task
from .package_prepared_graphics import Binding as PackageBinding
from .package_prepared_graphics import _digest, _fraction_bases, bind_candidates

REVISION = "coach-fraction-expansion-1"
HISTORY = "coach_expansion_history"
ERROR = "Die Anschlussübung ist nicht vollständig an Erweiterungsregel, Lernziele und geprüfte Grafiken gebunden. Es wurde keine KI-Anfrage gesendet."
CURRENT_ERROR = "Eine Erweiterungsaufgabe wurde inzwischen bereits verwendet. Die neue Runde wurde nicht übernommen. Deine bisherigen Antworten bleiben gespeichert."
EXHAUSTED = "Für diese Erweiterungsregel stehen keine zwei neuen darstellbaren Aufgaben bereit. Wähle eine andere bestätigte Heftseite. Es wurde keine KI-Anfrage gesendet."
CORE = (*expansion.CORE, "learning_goal_id")


def eligible(payload):
    if (payload.get("review") is not True or payload.get("practice_kind") not in ("repair", "check")
            or payload.get("required_subject") != "Mathematik"
            or any(payload.get(key) for key in ("study_block", "selected_groups", "notebook_practice",
                "homework_practice", "exam_preparation", "exam_review_practice"))
            or (payload.get("visual_context") or {}).get("required") is not True):
        return False
    focus, goals = payload.get("focus_goal_ids"), payload.get("learning_goals")
    if (not isinstance(focus, list) or not 1 <= len(focus) <= 2
            or any(not isinstance(key, str) for key in focus) or len(set(focus)) != len(focus) or not isinstance(goals, list)
            or any(not isinstance(goal, dict) or goal.get("id") not in ("g1", "g2", "g3", "g4") for goal in goals)
            or len({goal["id"] for goal in goals}) != len(goals)):
        return False
    by_id = {goal["id"]: goal for goal in goals}
    sources = expansion._sources(payload["visual_context"])
    quote = _procedure_quote(sources, "Brüche erweitern")
    from .learning_sources import exact_quote

    return bool(quote) and set(focus) <= by_id.keys() and all(
        by_id[key].get("label") == "Brüche erweitern"
        and isinstance(by_id[key].get("source_excerpt"), str)
        and exact_quote(by_id[key]["source_excerpt"], [source["content"] for source in sources]) for key in focus)


def add_reference(db, payload):
    from .visual_reference_models import VisualReference

    if not eligible(payload):
        return payload
    row = db.get(VisualReference, (expansion.RECIPE, expansion.VERSION))
    context = payload["visual_context"]
    existing = [ref for ref in context.get("references", [])
        if ref.get("id") == expansion.RECIPE and ref.get("version") == expansion.VERSION]
    if row is None or row.digest != _digest(row.recipe):
        if existing:
            raise ValueError(ERROR)
        return payload
    ref = {"id": row.id, "version": row.version, "digest": row.digest, "kind": "fraction", "subject": "Mathematik"}
    if existing:
        if any(any(saved.get(key) != value for key, value in ref.items()) for saved in existing):
            raise ValueError(ERROR)
        return payload
    return {**payload, "visual_context": {**context, "references": [*context["references"], ref]}}


def _pool():
    return {tuple(values) for values in _numbers("expand") if values[1] * values[2] <= 24}


def _history(payload, prompts):
    from .coaching import fraction_task_signature

    used, unknown, pool = set(), False, _pool()
    for prompt in prompts:
        if not isinstance(prompt, str):
            raise ValueError(ERROR)
        signature = fraction_task_signature(prompt)
        if signature and signature[0] == "expand":
            values = (*map(int, signature[1]), int(signature[2]))
            if values in pool:
                used.add(values)
        elif re.search(r"\berweiter\w*", prompt, re.I):
            unknown = True
    return {"version": 1, "revision": REVISION,
        "source_digest": _digest(expansion._sources(payload["visual_context"])),
        "signatures": [list(values) for values in sorted(used)], "unknown": unknown}


def with_history(payload, prompts):
    return {**payload, HISTORY: _history(payload, prompts)} if eligible(payload) else payload


def planning_inputs(payload):
    """Finite exclusions, including older prompts omitted from model context."""
    if not eligible(payload):
        if HISTORY in payload:
            raise ValueError(ERROR)
        return None
    value = payload.get(HISTORY)
    if (not isinstance(value, dict) or set(value) != {"version", "revision", "source_digest", "signatures", "unknown"}
            or type(value.get("version")) is not int or value["version"] != 1 or value.get("revision") != REVISION
            or value.get("source_digest") != _digest(expansion._sources(payload["visual_context"]))
            or type(value.get("unknown")) is not bool or not isinstance(value.get("signatures"), list)
            or any(not isinstance(row, list) or len(row) != 3 or any(type(n) is not int for n in row)
                or tuple(row) not in _pool() for row in value["signatures"])
            or len({tuple(row) for row in value["signatures"]}) != len(value["signatures"])):
        raise ValueError(ERROR)
    if value["unknown"]:
        raise ValueError(EXHAUSTED)
    context = payload["visual_context"]
    if not any(ref.get("id") == expansion.RECIPE and ref.get("version") == expansion.VERSION
            and ref.get("subject") == "Mathematik" and ref.get("digest") for ref in context.get("references", [])):
        raise ValueError(ERROR)
    example = next((tuple(base["numbers"]) for source in expansion._sources(context)
        for base, _ in _fraction_bases(source["content"])), None)
    if example is None:
        raise ValueError(ERROR)
    excluded = {tuple(row) for row in value["signatures"]}
    excluded.update(values for values in _pool() if (values[0] * values[2], values[1] * values[2]) == example)
    return {"denominator_limit": 24, "excluded_prompts": [_task("expand", values, "apply")[0] for values in sorted(excluded)]}


def _candidate(context, question, phase):
    prompt = question.get("prompt")
    match = expansion.START.match(prompt) if isinstance(prompt, str) else None
    if not match or phase not in ("understand", "recall"):
        return None
    values = tuple(map(int, match.groups()))
    n, d, factor = values
    if values not in _pool():
        return None
    expected_prompt, answer = _task("expand", values, phase)
    if (question.get("id") not in ("q1", "q2") or question.get("type") != "short"
            or prompt != expected_prompt or answer != f"{n * factor}/{d * factor}" or question.get("answer") != answer
            or question.get("options") != [] or question.get("accepted") != []
            or question.get("learning_goal_id") not in ("g1", "g2", "g3", "g4")):
        return None
    reference = next((r for r in context.get("references", []) if r.get("id") == expansion.RECIPE
        and r.get("version") == expansion.VERSION and r.get("subject") == "Mathematik" and r.get("digest")), None)
    sources = expansion._sources(context)
    quote = _procedure_quote(sources, "Brüche erweitern")
    if not reference or not quote or ("source_excerpt" in question and question["source_excerpt"] != quote):
        return None
    source = next((source for source in sources if quote in source["content"]), None)
    if source is None:
        return None
    proof = {"version": 1, "input": [n, d], "output": [n * factor, d * factor], "factor": factor,
        "phase": phase, "source_excerpt": quote, "source_digest": _digest(source),
        "reference_digest": reference["digest"], "task": {key: copy.deepcopy(question[key]) for key in CORE}}
    text = (f"Beim Erweitern von {n}/{d} mit dem Faktor {factor} multiplizieren wir Zähler und Nenner "
        f"mit {factor}: {n} · {factor} = {n * factor} und {d} · {factor} = {d * factor}. "
        f"So entsteht {n * factor}/{d * factor}. Beide Bilder zeigen denselben Anteil; rechts ist er feiner unterteilt.")
    row = {"subject": "Mathematik", "group_id": None, "kind": "fraction", "disclosure": "solution",
        "reference": {"id": expansion.RECIPE, "version": expansion.VERSION}, "source_refs": [source["ref"]],
        "text": text, "proof": proof}
    row["block"] = expansion._blocks(row)[0]
    row["id"] = "cf_" + _digest({"revision": REVISION, "candidate": row})[:24]
    return row


def validate_question_step(raw, context, question):
    for phase in ("understand", "recall"):
        candidate = _candidate(context, question or {}, phase)
        if candidate is not None:
            expansion.validate_step(raw, candidate)
            return
    raise ValueError(ERROR)


@dataclass(frozen=True)
class Binding(PackageBinding):
    @property
    def rules(self):
        return ("\n" + REVISION + ": Die beiden math_tasks und practice_tasks sind unverändert verbindlich. "
            "Wähle pro TaskID ausschließlich ihre vorbereitete solution-ID; presentation.blocks=[ID]. "
            "ID, Lernziel-ID, Frage, Antwort, Text, Quellen, Referenz und Aufdeckstufe exakt übernehmen. "
            "Der Server zeigt zwei gleich große Bruchmodelle vor und nach dem geprüften Erweitern. "
            "given zeigt einen getrennten Originalbruch, keine neue Aufgabenlösung. Ergänze kurze verständliche Hinweise; "
            "keine neuen Zahlen, Grafikparameter oder Ersatzaufgaben.")

    @property
    def context(self):
        return {"version": 1, "revision": REVISION, "candidates": [{key: copy.deepcopy(value)
            for key, value in row.items() if key != "block"} for row in self.candidates]}

    def question_bound(self, candidate, question):
        core = (candidate.get("proof") or {}).get("task")
        return bool(core) and all(question.get(key) == value for key, value in core.items())

    def hydrate(self, data):
        result = super().hydrate({"units": [data]})["units"][0]
        choices = {row["id"]: row for row in self.candidates}
        for item in [data, *data["questions"]]:
            selected = choices[item["explanation_steps"][0]["presentation"]["blocks"][0]]
            if item["explanation_steps"][0].get("id") != selected["id"]:
                raise ValueError(ERROR)
        for original, restored in zip(data["questions"], result["questions"], strict=True):
            selected = choices[original["explanation_steps"][0]["presentation"]["blocks"][0]]
            restored["explanation_steps"][0]["presentation"]["blocks"] = expansion._blocks(selected)
            expansion.validate_step(restored["explanation_steps"][0], selected)
        return result


def bind_schema(schema, payload):
    if not eligible(payload):
        return None
    planning_inputs(payload)
    from .providers import practice_tasks

    prescribed = practice_tasks(payload)
    tasks = payload.get("math_tasks")
    phase = "understand" if payload["practice_kind"] == "repair" else "recall"
    if not isinstance(tasks, list) or len(tasks) != 2:
        raise ValueError(ERROR)
    candidates = []
    for task, fixed in zip(tasks, prescribed, strict=True):
        candidate = _candidate(payload["visual_context"], {**task, "learning_goal_id": fixed["learning_goal_id"]}, phase)
        if candidate is None or task.get("id") != fixed["id"]:
            raise ValueError(ERROR)
        candidates.append(candidate)
    introductions = expansion._introductions(payload["visual_context"], candidates)
    if not introductions:
        raise ValueError(ERROR)
    binding = Binding(tuple([*introductions, *candidates]))
    wrapper = {"$defs": schema["$defs"], "properties": {"units": {"items": copy.deepcopy(
        {key: value for key, value in schema.items() if key != "$defs"})}}}

    def question_binding(node, candidate):
        props, core = node["properties"], candidate["proof"]["task"]
        if any(props[key].get("enum") != [core[key]] for key in ("id", "type", "prompt", "answer", "learning_goal_id")):
            return None
        props["presentation"] = {"type": "null"}
        return node

    bind_candidates(wrapper, binding, question_binding=question_binding)
    for definition in wrapper["$defs"].values():
        props = definition.get("properties", {})
        ids = props.get("presentation", {}).get("properties", {}).get("blocks", {}).get("items", {}).get("enum", [])
        if len(ids) == 1 and ids[0] in {row["id"] for row in binding.candidates}:
            props["id"] = {"type": "string", "enum": ids}
            props["competence_id"] = {"type": "null"}
    body = wrapper["properties"]["units"]["items"]
    schema.clear()
    schema.update(body, **{"$defs": wrapper["$defs"]})
    return binding


def validate_practice_history(payload, data, prompts):
    if not eligible(payload):
        return
    planning_inputs(payload)
    current = _history(payload, prompts)
    used = {tuple(row) for row in current["signatures"]}
    if current["unknown"]:
        raise ValueError(CURRENT_ERROR)
    from .providers import practice_tasks

    prescribed = {task["id"]: task for task in practice_tasks(payload)}
    questions = data.get("questions")
    if not isinstance(questions, list) or len(questions) != 2 or {q.get("id") for q in questions} != set(prescribed):
        raise ValueError(CURRENT_ERROR)
    phase = "understand" if payload["practice_kind"] == "repair" else "recall"
    for question in questions:
        candidate = _candidate(payload["visual_context"], question, phase)
        if (candidate is None or question.get("learning_goal_id") != prescribed[question["id"]]["learning_goal_id"]
                or tuple([*candidate["proof"]["input"], candidate["proof"]["factor"]]) in used):
            raise ValueError(CURRENT_ERROR)
