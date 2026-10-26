"""Closed source-rule-bound kgV tasks for explicitly selected notebook rounds.

All arithmetic and scene parameters are planned before inference. The model
cannot supply a replacement task, source, answer, label, relation or phase.
No DB writes, model calls, retries or saved-attempt changes live in this module.
"""
import copy
import json
import math
import re
import unicodedata
from dataclasses import dataclass
from pathlib import Path

from . import learning_entry
from .package_prepared_graphics import Binding as PackageBinding
from .package_prepared_graphics import _digest, bind_candidates
from .subject_content import Graphic
from .visual_reference_schemas import ExplanationStep

RECIPE = "math.multiples.common"
VERSION = 1
REVISION = "notebook-multiples-common-1"
KEY = "notebook_multiples_plan"
HISTORY_KEY = "notebook_multiples_exclusions"
CORE = learning_entry.CORE
ERROR = "Die kgV-Runde lässt sich nicht vollständig an ihre geprüfte Regel, Aufgaben und Grafik binden. Es wurde keine KI-Anfrage gesendet."
RULE_ERROR = "Auf den ausgewählten Seiten fehlt eine eindeutig bestätigte kgV-Regel. Bitte prüfe zuerst die Lehrgrundlage. Es wurde keine KI-Anfrage gesendet."
EXHAUSTED = "Für diese kgV-Regel sind keine neuen passenden kleinen Aufgaben mehr verfügbar. Wähle eine andere bestätigte Heftseite. Es wurde keine KI-Anfrage gesendet."
_TOPIC = re.compile(r"(?<!\w)kgv(?!\w)|\bkleinst(?:e|es|en)\s+gemeinsam(?:e|es|en)\s+vielfache[ns]?\b", re.I)
_PROMPT_PAIR = re.compile(r"(?:\bkgv\b|\bkleinste(?:s)?\s+gemeinsame(?:s)?\s+vielfache(?:s)?)\s*(?:\(kgv\)\s*)?(?:von|für)\s+([1-9][0-9]{0,3})\s+(?:und|,)\s*([1-9][0-9]{0,3})(?![\w/,]|\.[0-9])", re.I)
_ANCHOR_PAIR = re.compile(r"(?<!\w)kgv\s*(?:\}\s*)?(?:\\left\s*)?\(\s*([1-9][0-9]{0,3})\s*[;,]\s*([1-9][0-9]{0,3})\s*(?:\\right\s*)?\)", re.I)


def public_recipe():
    rows = json.loads((Path(__file__).with_name("reference") / "visual-v1.json").read_text())["references"]
    return next(row for row in rows if row["id"] == RECIPE and row["version"] == VERSION)


def _sources(context):
    return [source for source in context.get("sources", []) if not source.get("source_type")
        and source.get("subject") == "Mathematik" and source.get("group_id") is None]


def applies(payload):
    """A topic selects this gate, never by itself a mathematical teaching rule."""
    from .math_tasks import _procedure_quote
    from .notebook_practice import requested_count
    from .unit_fraction_compositions import eligible as composition_source

    context = payload.get("visual_context") or {}
    sources = _sources(context)
    return (requested_count(payload) is not None and payload.get("required_subject") == "Mathematik"
        and context.get("required") is True
        and not any(payload.get(key) for key in ("goal", "review", "study_block", "selected_groups",
            "homework_practice", "exam_preparation", "exam_review_practice"))
        and not any(composition_source(source) for source in sources)
        and not any(_procedure_quote(sources, label) for label in ("Brüche erweitern", "Brüche kürzen", "Brüche addieren"))
        and any(_TOPIC.search(source.get("topic", "") + "\n" + source.get("content", "")) for source in sources))


def _algorithm_rule(content):
    # One local, ordered worked procedure. A later Teiler section is outside
    # the captured quote and never becomes evidence for this rule.
    pattern = (r"kgv\s*(?:\}\s*)?(?:\\left\s*)?\(\s*([1-9][0-9]?)\s*[;,]\s*([1-9][0-9]?)\s*(?:\\right\s*)?\)"
        r"(?P<working>.{0,100}?)1\s*\.?\s*Schritt\s*:\s*Notiere\s+die\s+Vielfachenmengen\s*!?"
        r".{0,350}?2\s*\.?\s*Schritt\s*:\s*Finde\s+die\s+kleinste\s+gemeinsame\s+Zahl[.!]?")
    for match in re.finditer(pattern, content, re.I | re.S):
        a, b = map(int, match.group(1, 2))
        if not 2 <= a < b <= 50:
            continue
        working = re.sub(r"(?:\$|\\[)\]])", "", match["working"]).strip()
        result = re.fullmatch(r"(?:=\s*([0-9]{1,4})?)?", working)
        if result is None or (result[1] is not None and int(result[1]) != math.lcm(a, b)):
            continue  # A conflicting student equality is never teaching evidence.
        quote = match.group()
        if len(quote) > 500 or re.search(r"\b(?:nicht|kein\w*|falsch\w*)\b", quote, re.I):
            continue
        lists = []
        for number in (a, b):
            subscript = str(number).translate(str.maketrans("0123456789", "₀₁₂₃₄₅₆₇₈₉"))
            index = rf"(?:(?:_\s*)?(?:\{{\s*)?{number}(?:\s*\}})?|{subscript})"
            literal = (rf"\bV\s*{index}\s*=\s*"
                r"(?:\\left\s*)?(?:\\)?\{\s*([0-9]+(?:\s*[;,]\s*[0-9]+){1,11}\s*[;,]?)\s*(?:\\right\s*)?(?:\\)?\}")
            found = re.findall(literal, quote, re.I)
            if len(found) != 1:
                break
            values = [int(value) for value in re.findall(r"[0-9]+", found[0])]
            if values != [number * index for index in range(1, len(values) + 1)]:
                break
            lists.append(values)
        if len(lists) != 2 or not (common := set(lists[0]) & set(lists[1])) or min(common) != math.lcm(a, b):
            continue
        return quote
    return None


def _rule(context):
    for source in _sources(context):
        if (not re.fullmatch(r"[a-f0-9]{32}", source.get("material_id", ""))
                or type(source.get("revision")) is not int or source["revision"] < 1):
            raise ValueError(ERROR)
        content = source.get("content", "")
        for match in re.finditer(r"[^.!?]{15,500}(?:[.!?]|$)", content):
            quote = match.group().strip()
            flat = " ".join(unicodedata.normalize("NFC", quote).split())
            definition = (re.search(r"(?:kleinste(?:s)?\s+gemeinsame(?:s)?\s+vielfache(?:s)?|\bkgv\b)"
                r".{0,65}\bist\s+(?:die\s+)?kleinste\s+positive\s+zahl\b", flat, re.I)
                and (re.search(r"\bdurch\s+(?:beide|die\s+beiden)\s+(?:zahlen\s+)?(?:ohne\s+rest\s+)?teilbar\b", flat, re.I)
                    or re.search(r"\bein\s+vielfaches\s+(?:beider|der\s+beiden)\s+zahlen\b", flat, re.I)))
            if not definition or re.search(r"\b(?:nicht|kein\w*|falsch\w*|größt\w*|negativ\w*)\b", flat, re.I):
                continue
            return {"source_ref": source["ref"], "material_id": source["material_id"],
                "revision": source["revision"], "source_digest": _digest(source),
                "safe_content_digest": _digest(content), "source_refs": copy.deepcopy(source.get("source_refs", [])),
                "quote": quote, "method": "positive_definition"}
        quote = _algorithm_rule(content)
        if quote is not None:
            return {"source_ref": source["ref"], "material_id": source["material_id"],
                "revision": source["revision"], "source_digest": _digest(source),
                "safe_content_digest": _digest(content), "source_refs": copy.deepcopy(source.get("source_refs", [])),
                "quote": quote, "method": "verified_two_step_multiples"}
    return None


def _reference(context):
    actual = public_recipe()
    digest = _digest(actual)
    return next((row for row in context.get("references", []) if row.get("id") == RECIPE
        and type(row.get("version")) is int and row["version"] == VERSION
        and row.get("subject") == "Mathematik" and row.get("kind") == "scene" and row.get("digest") == digest), None)


def add_reference(db, payload):
    from .visual_reference_models import VisualReference

    if not applies(payload) or _rule(payload["visual_context"]) is None:
        return payload
    actual = public_recipe()
    row = db.get(VisualReference, (RECIPE, VERSION))
    if row is None or row.digest != _digest(actual) or row.recipe != actual:
        return payload
    context = payload["visual_context"]
    reference = {"id": RECIPE, "version": VERSION, "digest": row.digest, "kind": "scene", "subject": "Mathematik"}
    return {**payload, "visual_context": {**context, "references": [*context["references"], reference]}}


def _arithmetic(pair):
    if (not isinstance(pair, (list, tuple)) or len(pair) != 2
            or any(type(value) is not int or not 2 <= value <= 8 for value in pair) or not pair[0] < pair[1]):
        raise ValueError(ERROR)
    a, b = pair
    result = math.lcm(a, b)
    if (result > 24 or result % a or result % b
            or any(number % a == number % b == 0 for number in range(1, result))):
        raise ValueError(ERROR)
    left, right = list(range(a, result + 1, a)), list(range(b, result + 1, b))
    if min(set(left) & set(right)) != result:
        raise ValueError(ERROR)
    return result, left, right


def _pool():
    return [(a, b) for a in range(2, 9) for b in range(a + 1, 9) if math.lcm(a, b) <= 24]


def _pairs(prompts):
    return {tuple(sorted(map(int, match.groups()))) for prompt in prompts if isinstance(prompt, str)
        for pattern in (_PROMPT_PAIR, _ANCHOR_PAIR)
        for match in pattern.finditer(unicodedata.normalize("NFC", prompt))}


def with_history(payload, prompts):
    if not applies(payload):
        return payload
    if any(not isinstance(prompt, str) for prompt in prompts):
        raise ValueError(ERROR)
    used = _pairs(prompts) & set(_pool())
    value = {"version": 1, "source_digest": _digest(_sources(payload["visual_context"])),
        "pairs": [list(pair) for pair in sorted(used)]}
    return {**payload, HISTORY_KEY: value}


def _history(payload):
    value = payload.get(HISTORY_KEY)
    if (not isinstance(value, dict) or set(value) != {"version", "source_digest", "pairs"}
            or type(value.get("version")) is not int or value["version"] != 1
            or value.get("source_digest") != _digest(_sources(payload["visual_context"]))
            or not isinstance(value.get("pairs"), list) or len(value["pairs"]) > len(_pool())
            or any(not isinstance(pair, list) or len(pair) != 2 or any(type(number) is not int for number in pair)
                or tuple(pair) not in _pool() for pair in value["pairs"])
            or len({tuple(pair) for pair in value["pairs"]}) != len(value["pairs"])):
        raise ValueError(ERROR)
    return value


def _core(identifier, pair):
    result, _, _ = _arithmetic(pair)
    return {"id": identifier, "type": "short", "prompt": f"Was ist das kleinste gemeinsame Vielfache von {pair[0]} und {pair[1]}?",
        "answer": str(result), "options": [], "accepted": []}


def prepare(payload):
    from .notebook_practice import requested_count

    if not applies(payload):
        if KEY in payload or HISTORY_KEY in payload:
            raise ValueError(ERROR)
        return payload
    context = payload["visual_context"]
    rule = _rule(context)
    if rule is None:
        raise ValueError(RULE_ERROR)
    if _reference(context) is None:
        raise ValueError(ERROR)
    history = _history(payload)
    count = requested_count(payload)
    plans = (payload.get("learning_entry") or {}).get("units")
    if plans is None:
        slots = [{"id": f"q{index + 1}"} for index in range(count)]
    else:
        if (len(plans) != 1 or plans[0].get("subject") != "Mathematik" or plans[0].get("group_id") is not None
                or plans[0].get("entry_mode") not in ("source_probe", "reuse_evidence") or plans[0].get("probes")):
            raise ValueError(ERROR)
        slots = learning_entry._specs(plans[0], count)
    # A distinct worked example is planned jointly. Its shown values cannot be
    # one of the pending answers. It is derived, never claimed to be a photo quote.
    introduction = (2, 4)
    _, intro_left, intro_right = _arithmetic(introduction)
    displayed = {*introduction, *intro_left, *intro_right}
    used = {tuple(pair) for pair in history["pairs"]}
    originals = {tuple(sorted(map(int, match.groups()))) for source in _sources(context)
        for match in _ANCHOR_PAIR.finditer(source["content"])}
    available = [pair for pair in _pool() if pair not in used | originals and pair != introduction
        and math.lcm(*pair) not in displayed]
    available.sort(key=lambda pair: _digest([REVISION, rule, history, slots, pair]))
    if len(available) < count:
        raise ValueError(EXHAUSTED)
    tasks = [_core(slot["id"], pair) for slot, pair in zip(slots, available[:count], strict=True)]
    plan = {"version": 1, "revision": REVISION, "context_digest": _digest(context), "rule": rule,
        "exclusion_digest": _digest(history), "question_count": count, "introduction": list(introduction), "tasks": tasks}
    if KEY in payload and payload[KEY] != plan:
        raise ValueError(ERROR)
    return {**payload, KEY: plan}


def _graphic(rule, pair, stage):
    result, left, right = _arithmetic(pair)
    labels = [f"Vielfache von {pair[0]}: " + ", ".join(map(str, left)),
        f"Vielfache von {pair[1]}: " + ", ".join(map(str, right)), f"Kleinstes gemeinsames Vielfaches: {result}"]
    ids = ("left", "right", "common")
    objects = [{"id": identifier, "label": label, "shape": "box", "tone": "accent" if identifier == "common" else "neutral"}
        for identifier, label in zip(ids, labels, strict=True)]
    placements = [{"object_id": identifier, "slot": index} for index, identifier in enumerate(ids)]
    block = {"kind": "scene", "title": "kgV verstehen", "disclosure": stage, "source_excerpt": rule["quote"],
        "labels": labels, "numbers": [], "connections": [], "marks": [], "unit": "", "variant": "", "text_probe": None, "lab": None,
        "scene": {"version": 1, "layout": "row", "objects": objects, "transition_ms": 300, "steps": [
            {"caption": "Vergleiche die beiden Vielfachenreihen.", "source_excerpt": rule["quote"],
                "placements": placements, "highlight": ["left", "right"], "edges": []},
            {"caption": f"Die kleinste gemeinsame Zahl ist {result}.", "source_excerpt": rule["quote"],
                "placements": placements, "highlight": ["common"], "edges": []}]}}
    return Graphic.model_validate(block).model_dump(mode="json")


def _candidate(context, rule, pair, *, question=None):
    reference = _reference(context)
    if reference is None:
        raise ValueError(ERROR)
    result, left, right = _arithmetic(pair)
    stage = "given" if question is None else "solution"
    text = ("Ein eigenes Rechenbeispiel: " if question is None else "") + (
        f"Die Vielfachen von {pair[0]} sind " + ", ".join(map(str, left)) + f". Die Vielfachen von {pair[1]} sind "
        + ", ".join(map(str, right)) + f". Die kleinste gemeinsame Zahl ist {result}; daher ist das kgV {result}.")
    proof = {"version": 1, "revision": REVISION, "rule": copy.deepcopy(rule), "reference_digest": reference["digest"],
        "pair": list(pair), "result": result, "left": left, "right": right, "task": copy.deepcopy(question)}
    row = {"subject": "Mathematik", "group_id": None, "kind": "scene", "disclosure": stage,
        "reference": {"id": RECIPE, "version": VERSION}, "source_refs": [rule["source_ref"]],
        "text": text, "block": _graphic(rule, pair, stage), "proof": proof}
    row["id"] = "mc_" + _digest([REVISION, _digest(context), row])[:24]
    ExplanationStep.model_validate({"id": row["id"], "text": text, "competence_id": None, "disclosure": stage,
        "reference": row["reference"], "source_refs": row["source_refs"],
        "presentation": {"version": 1, "evidence_kind": "knowledge", "blocks": [row["block"]]}})
    return row


def _pair_for_question(question):
    prompt = question.get("prompt", "")
    match = re.fullmatch(r"Was ist das kleinste gemeinsame Vielfache von ([1-9][0-9]*) und ([1-9][0-9]*)\?", prompt)
    if not match:
        raise ValueError(ERROR)
    pair = tuple(map(int, match.groups()))
    if any(question.get(key) != value for key, value in _core(question.get("id"), pair).items()):
        raise ValueError(ERROR)
    return pair


def validate_step(raw, context, question=None):
    # Client capability models omit unsupported nullable Graphic members.
    # Reparse with the SAME canonical model; only its defined defaults return.
    # No labels/numbers/core fields are inferred or repaired.
    step = ExplanationStep.model_validate(raw).model_dump(mode="json")
    if _reference(context) is None or (rule := _rule(context)) is None:
        raise ValueError(ERROR)
    pair = (2, 4) if question is None else _pair_for_question(question)
    expected = _candidate(context, rule, pair, question=None if question is None else {key: question[key] for key in CORE})
    expected_step = {"id": expected["id"], "text": expected["text"], "competence_id": None,
        "disclosure": expected["disclosure"], "reference": expected["reference"], "source_refs": expected["source_refs"],
        "presentation": {"version": 1, "evidence_kind": "knowledge", "blocks": [expected["block"]]}}
    if _digest(step) != _digest(expected_step):
        raise ValueError(ERROR)


@dataclass(frozen=True)
class Binding(PackageBinding):
    @property
    def rules(self):
        return ("\n" + REVISION + ": notebook_multiples_plan enthält sämtliche festen Aufgabenkerne. "
            "Alle id/type/prompt/answer/options/accepted exakt übernehmen. Jede Frage verwendet ausschließlich "
            "ihre vorbereitete solution-ID; Intro ausschließlich die gegebene andere Beispiel-ID. "
            "presentation.blocks=[ID]. Schritt-id, -text, Quelle, Referenz und Stufe bleiben exakt. "
            "Unit.explanation ist exakt der andere gegebene Beispieltext; keine späteren Antworten darin nennen. "
            "Keine Grafikparameter oder Ersatzfragen erfinden. Ergänze kurze Hinweise und Frage-Erklärungen zur selben Rechnung.")

    @property
    def context(self):
        return {"version": 1, "revision": REVISION, "candidates": [{key: copy.deepcopy(value)
            for key, value in row.items() if key != "block"} for row in self.candidates]}

    def offered(self, candidate):
        return True

    def question_bound(self, candidate, question):
        core = candidate["proof"]["task"]
        return bool(core) and all(question.get(key) == value for key, value in core.items())

    def hydrate(self, data):
        intro = next(row for row in self.candidates if row["disclosure"] == "given")
        if data.get("explanation") != intro["text"]:
            raise ValueError(ERROR)
        if any(question.get("presentation") is not None for question in data.get("questions", [])):
            raise ValueError(ERROR)
        result = super().hydrate({"units": [data]})["units"][0]
        choices = {row["id"]: row for row in self.candidates}
        for before, after in [(data, result), *zip(data["questions"], result["questions"], strict=True)]:
            row = choices[before["explanation_steps"][0]["presentation"]["blocks"][0]]
            if after["explanation_steps"][0]["id"] != row["id"]:
                raise ValueError(ERROR)
        return result


def bind_schema(schema, payload):
    if KEY not in payload:
        return None
    if prepare(payload) != payload:
        raise ValueError(ERROR)
    context, plan = payload["visual_context"], payload[KEY]
    intro = _candidate(context, plan["rule"], plan["introduction"])
    schema["properties"]["explanation"].update(type="string", enum=[intro["text"]])
    rows = [intro, *[_candidate(context, plan["rule"], _pair_for_question(task), question=task) for task in plan["tasks"]]]
    binding = Binding(tuple(rows))
    wrapper = {"$defs": schema["$defs"], "properties": {"units": {"items": copy.deepcopy(
        {key: value for key, value in schema.items() if key != "$defs"})}}}

    def question_binding(node, candidate):
        core = candidate["proof"]["task"]
        props = node["properties"]
        for key in ("id", "type", "prompt", "answer"):
            allowed = props[key].get("enum", [props[key]["const"]] if "const" in props[key] else [])
            if allowed and core[key] not in allowed:
                return None
            props[key].update(type="string", enum=[core[key]])
        props["options"].update(minItems=0, maxItems=0)
        props["accepted"].update(minItems=0, maxItems=0)
        props["presentation"] = {"type": "null"}
        return node

    graphic = schema.get("$defs", {}).get("Graphic", {}).get("properties", {})
    if "scene" not in graphic.get("kind", {}).get("enum", []):
        raise ValueError(ERROR)
    try:
        bind_candidates(wrapper, binding, question_kinds=("scene",), question_binding=question_binding)
    except ValueError:
        raise ValueError(ERROR) from None
    for definition in wrapper["$defs"].values():
        props = definition.get("properties", {})
        ids = props.get("presentation", {}).get("properties", {}).get("blocks", {}).get("items", {}).get("enum", [])
        if len(ids) == 1 and ids[0] in {row["id"] for row in rows}:
            props["id"] = {"type": "string", "enum": ids}
            props["competence_id"] = {"type": "null"}
    schema.clear()
    schema.update(wrapper["properties"]["units"]["items"], **{"$defs": wrapper["$defs"]})
    return binding


def validate_output(payload, data):
    if KEY not in payload:
        return
    if prepare(payload) != payload:
        raise ValueError(ERROR)
    plan = payload[KEY]
    if (data.get("subject") != "Mathematik" or len(data.get("questions", [])) != plan["question_count"]
            or {question["id"] for question in data["questions"]} != {task["id"] for task in plan["tasks"]}):
        raise ValueError(ERROR)
    tasks = {task["id"]: task for task in plan["tasks"]}
    for question in data["questions"]:
        if any(question.get(key) != value for key, value in tasks[question["id"]].items()):
            raise ValueError(ERROR)
    intro = _candidate(payload["visual_context"], plan["rule"], plan["introduction"])
    if data.get("explanation") != intro["text"]:
        raise ValueError(ERROR)
    if len(data.get("explanation_steps") or []) != 1:
        raise ValueError(ERROR)
    validate_step(data["explanation_steps"][0], payload["visual_context"])
    for question in data["questions"]:
        if len(question.get("explanation_steps") or []) != 1:
            raise ValueError(ERROR)
        validate_step(question["explanation_steps"][0], payload["visual_context"], question)
        if int(question["answer"]) in {2, 4}:
            raise ValueError(ERROR)


def validate_history(payload, data, prompts):
    if KEY not in payload:
        return
    validate_output(payload, data)
    old = _pairs(prompts)
    planned = [_pair_for_question(question) for question in data["questions"]]
    if len(set(planned)) != len(planned) or old & set(planned):
        raise ValueError(EXHAUSTED)
