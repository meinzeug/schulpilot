"""Prepared proofs for existing, source-backed StudyPath expansion tasks.

The model chooses an immutable ID, never new arithmetic, labels or parameters.
Only this versioned recipe validates a proved parameter transformation instead
of treating each derived value as an independently quoted source literal.
"""
import copy
import re
from dataclasses import dataclass

from .math_tasks import _procedure_quote, _task
from .package_prepared_graphics import Binding as PackageBinding
from .package_prepared_graphics import _digest, _fraction_bases, bind_candidates
from .subject_content import Graphic

RECIPE = "math.fraction.expansion"
VERSION = 1
REVISION = "study-fraction-expansion-1"
ERROR = "Ungültiger vorabgeprüfter Erweiterungsbeweis."
UNREPRESENTABLE = "Die geplante Erweiterung passt nicht vollständig in die geprüfte Bruchdarstellung. Es wurde keine KI-Anfrage gesendet."
CORE = ("id", "type", "prompt", "answer", "options", "accepted")
START = re.compile(r"Erweitere den Bruch ([0-9]+)/([0-9]+) mit dem Faktor ([0-9]+)\. ")


def eligible(payload):
    block = payload.get("study_block")
    return (isinstance(block, dict) and block.get("mode") in ("apply", "detective")
        and payload.get("required_subject") == "Mathematik"
        and not any(payload.get(k) for k in ("review", "selected_groups", "notebook_practice", "homework_practice",
            "exam_preparation", "exam_review_practice")))


def _sources(context):
    return [row for row in context.get("sources", []) if row.get("subject") == "Mathematik"
        and row.get("group_id") is None and not row.get("source_type")
        and isinstance(row.get("content"), str) and row["content"].strip()
        and re.fullmatch(r"[a-f0-9]{32}", row.get("material_id", ""))
        and type(row.get("revision")) is int and row["revision"] >= 1]


def add_reference(db, payload):
    from .visual_reference_models import VisualReference

    context = payload.get("visual_context") or {}
    if not eligible(payload) or not _procedure_quote(_sources(context), "Brüche erweitern"):
        return payload
    row = db.get(VisualReference, (RECIPE, VERSION))
    if row is None or row.digest != _digest(row.recipe):
        return payload
    ref = {"id": RECIPE, "version": VERSION, "digest": row.digest, "kind": "fraction", "subject": "Mathematik"}
    return {**payload, "visual_context": {**context, "references": [*context.get("references", []), ref]}}


def planning_limit(payload):
    context = payload.get("visual_context") or {}
    return 24 if (eligible(payload) and context.get("required")
        and any(r.get("id") == RECIPE and r.get("version") == VERSION and r.get("digest")
                for r in context.get("references", []))
        and _procedure_quote(_sources(context), "Brüche erweitern")) else None


def _planned(question, phase):
    """Require the exact existing planner template, not arbitrary model prose."""
    prompt = question.get("prompt")
    match = START.match(prompt) if isinstance(prompt, str) else None
    if not match or phase not in ("apply", "detective"):
        return None
    n, d, factor = map(int, match.groups())
    if not 1 <= n < d <= 12 or not 2 <= factor <= 4:
        return None
    expected_prompt, answer = _task("expand", (n, d, factor), phase)
    if (question.get("type") != "short" or prompt != expected_prompt or question.get("answer") != answer
            or question.get("options") != [] or question.get("accepted") != []
            or question.get("learning_goal_id") is not None):
        return None
    return n, d, factor


def _blocks(candidate):
    proof = candidate["proof"]
    return [Graphic.model_validate({"kind": "fraction", "title": title,
        "source_excerpt": proof["source_excerpt"], "labels": [], "numbers": pair,
        "connections": [], "marks": [], "unit": "", "variant": "", "disclosure": "solution"}).model_dump(mode="json")
        for title, pair in (("Vor dem Erweitern", proof["input"]), ("Nach dem Erweitern", proof["output"]))]


def _candidate(context, question, phase):
    parsed = _planned(question, phase)
    if parsed is None:
        return None
    n, d, factor = parsed
    if d * factor > 24:
        raise ValueError(UNREPRESENTABLE)
    reference = next((r for r in context.get("references", []) if r.get("id") == RECIPE
        and r.get("version") == VERSION and r.get("subject") == "Mathematik" and r.get("digest")), None)
    sources = _sources(context)
    quote = _procedure_quote(sources, "Brüche erweitern")
    if not reference or not quote:
        return None
    if "source_excerpt" in question and question["source_excerpt"] != quote:
        return None
    source = next((s for s in sources if quote in s["content"]), None)
    if source is None or not isinstance(question.get("id"), str) or not question["id"]:
        return None
    proof = {"version": 1, "input": [n, d], "output": [n * factor, d * factor], "factor": factor,
        "phase": phase, "source_excerpt": quote, "source_digest": _digest(source),
        "reference_digest": reference["digest"], "task": {key: copy.deepcopy(question[key]) for key in CORE}}
    text = (f"Beim Erweitern von {n}/{d} mit dem Faktor {factor} multiplizieren wir Zähler und Nenner "
        f"mit {factor}: {n} · {factor} = {n * factor} und {d} · {factor} = {d * factor}. "
        f"So entsteht {n * factor}/{d * factor}. Beide Bilder zeigen denselben Anteil; rechts ist er feiner unterteilt.")
    row = {"subject": "Mathematik", "group_id": None, "kind": "fraction", "disclosure": "solution",
        "reference": {"id": RECIPE, "version": VERSION}, "source_refs": [source["ref"]], "text": text, "proof": proof}
    row["block"] = _blocks(row)[0]
    row["id"] = "fx_" + _digest({"revision": REVISION, "candidate": row})[:24]
    return row


def _introductions(context, tasks):
    reference = next((r for r in context.get("references", []) if r.get("id") == "math.fraction.part_whole"
        and r.get("version") == 1 and r.get("subject") == "Mathematik" and r.get("digest")), None)
    if reference is None:
        return []
    result = []
    answers = {tuple(candidate["proof"]["output"]) for candidate in tasks}
    for source in _sources(context):
        for base, text in _fraction_bases(source["content"]):
            if tuple(base["numbers"]) in answers:
                continue  # Never turn a new task's derived answer into given data.
            row = {"subject": "Mathematik", "group_id": None, "kind": "fraction", "disclosure": "given",
                "reference": {"id": reference["id"], "version": reference["version"]}, "source_refs": [source["ref"]],
                "text": ("Beim Erweitern multiplizierst du Zähler und Nenner mit derselben Zahl. "
                    "Die Menge bleibt gleich; die Teile werden feiner. " + text),
                "block": {**base, "disclosure": "given"}}
            row["id"] = "fx_" + _digest({"revision": REVISION, "candidate": row,
                "source_digest": _digest(source), "reference_digest": reference["digest"]})[:24]
            result.append(row)
            if len(result) >= 2:
                return result
    return result


@dataclass(frozen=True)
class Binding(PackageBinding):
    @property
    def rules(self):
        return ("\n" + REVISION + ": math_tasks ist unverändert verbindlich. Wähle für jede Aufgabe ausschließlich "
            "die vorbereitete solution-ID genau dieser TaskID; presentation.blocks=[ID]. ID, Text, Quellen, "
            "Referenz und Aufdeckstufe exakt übernehmen. Der Server stellt zwei geordnete gleich große "
            "Bruchmodelle mit dem geprüften Erweiterungsfaktor bereit. Keine Zahlen, Fragen, Antworten oder "
            "Lernziele ändern. given zeigt ausschließlich einen getrennten Originalbruch, keine neue Aufgabenlösung. "
            "Weitere allgemeine Hilfen gehören in hints; der geprüfte Lösungsschritt bleibt geschlossen.")

    def question_bound(self, candidate, question):
        return bool(candidate.get("proof")) and all(question.get(key) == value
            for key, value in candidate["proof"]["task"].items()) and question.get("learning_goal_id") is None

    @property
    def context(self):
        return {"version": 1, "revision": REVISION, "candidates": [{key: copy.deepcopy(value)
            for key, value in row.items() if key != "block"} for row in self.candidates]}

    def hydrate(self, data):
        result = super().hydrate({"units": [data]})["units"][0]
        choices = {row["id"]: row for row in self.candidates}
        for item in [data, *data["questions"]]:
            selected = choices[item["explanation_steps"][0]["presentation"]["blocks"][0]]
            if item["explanation_steps"][0].get("id") != selected["id"]:
                raise ValueError(ERROR)
        for original, restored in zip(data["questions"], result["questions"], strict=True):
            selected = choices[original["explanation_steps"][0]["presentation"]["blocks"][0]]
            restored["explanation_steps"][0]["presentation"]["blocks"] = _blocks(selected)
            validate_step(restored["explanation_steps"][0], selected)
        return result


def validate_step(raw, candidate):
    step = raw.model_dump(mode="json") if hasattr(raw, "model_dump") else raw
    expected = {"id": candidate["id"], "text": candidate["text"], "competence_id": None,
        "disclosure": "solution", "reference": candidate["reference"], "source_refs": candidate["source_refs"],
        "presentation": {"version": 1, "evidence_kind": "knowledge", "blocks": _blocks(candidate)}}
    if _digest(step) != _digest(expected):
        raise ValueError(ERROR)


def validate_question_step(raw, context, question):
    if question is None:
        raise ValueError(ERROR)
    for phase in ("apply", "detective"):
        candidate = _candidate(context, question, phase)
        if candidate is not None:
            validate_step(raw, candidate)
            return
    raise ValueError(ERROR)


def bind_schema(schema, payload):
    if not eligible(payload) or not (payload.get("visual_context") or {}).get("required"):
        return None
    tasks = payload.get("math_tasks")
    if not isinstance(tasks, list) or not tasks or not any(START.match(str(t.get("prompt", ""))) for t in tasks):
        return None
    phase = payload["study_block"]["mode"]
    context = payload.get("visual_context") or {}
    if not context.get("required") or len(tasks) != payload["study_block"].get("question_count"):
        raise ValueError(ERROR)
    candidates = [_candidate(context, task, phase) for task in tasks]
    if any(candidate is None for candidate in candidates) or len({t["id"] for t in tasks}) != len(tasks):
        raise ValueError(ERROR)
    introductions = _introductions(context, candidates)
    if not introductions:
        raise ValueError(ERROR)
    binding = Binding(tuple([*introductions, *candidates]))
    wrapper = {"$defs": schema["$defs"], "properties": {"units": {"items": copy.deepcopy(
        {key: value for key, value in schema.items() if key != "$defs"})}}}

    def question_binding(node, candidate):
        core = candidate["proof"]["task"]
        props = node["properties"]
        if any(props[key].get("enum") != [core[key]] for key in ("id", "type", "prompt", "answer")):
            return None  # Never replace or broaden an already bound task branch.
        props["presentation"] = {"type": "null"}
        return node

    bind_candidates(wrapper, binding, question_binding=question_binding)
    for definition in wrapper["$defs"].values():
        props = definition.get("properties", {})
        block = props.get("presentation", {}).get("properties", {}).get("blocks", {})
        ids = block.get("items", {}).get("enum", [])
        if len(ids) == 1 and ids[0] in {c["id"] for c in binding.candidates}:
            props["id"] = {"type": "string", "enum": ids}
            props["competence_id"] = {"type": "null"}
    body = wrapper["properties"]["units"]["items"]
    schema.clear()
    schema.update(body, **{"$defs": wrapper["$defs"]})
    return binding
