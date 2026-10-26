"""Normal source-bound material rounds reuse the proved expansion renderer.

No study/notebook flag, new allocation, fallback or learner evidence is created.
The existing normal entry determines the slots; arithmetic fills practice only.
"""
import copy
import re
import unicodedata
from dataclasses import dataclass

from . import notebook_fraction_expansions as notebook
from . import study_fraction_expansions as expansion
from .math_tasks import _catalog, _procedure_quote, _task, fraction_tasks
from .package_prepared_graphics import _digest, _fraction_bases

REVISION = "material-fraction-expansion-1"
KEY = "material_expansion_plan"
HISTORY = "material_expansion_exclusions"
ERROR = "Die neue Lernrunde ist nicht vollständig an Erweiterungsregel, Lernstart und geprüfte Grafiken gebunden. Es wurde keine KI-Anfrage gesendet."
EXHAUSTED = "Für diese bestätigte Erweiterungsseite stehen keine neuen darstellbaren Aufgaben bereit. Wähle eine andere bestätigte Heftseite. Es wurde keine KI-Anfrage gesendet."
CURRENT_ERROR = "Eine Erweiterungsaufgabe wurde inzwischen bereits verwendet. Die neue Runde wurde nicht übernommen. Deine bisherigen Antworten bleiben gespeichert."


def eligible(payload):
    context = payload.get("visual_context") or {}
    material = payload.get("material")
    if (payload.get("function") != "unit" or not isinstance(material, dict)
            or material.get("subject") != "Mathematik" or context.get("required") is not True
            or any(payload.get(key) for key in ("review", "goal", "study_block", "selected_groups", "notebook_practice",
                "homework_practice", "exam_preparation", "exam_review_practice"))):
        return False
    sources = expansion._sources(context)
    originals = [row for row in context.get("sources", []) if row.get("material_id")]
    if not sources or len(sources) != len(originals) or not _procedure_quote(sources, "Brüche erweitern"):
        return False
    catalog = _catalog(sources, "Mathematik", "")
    return "Brüche erweitern" in catalog and not any(label in catalog for label in ("Brüche kürzen", "Brüche addieren"))


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


def introduction_example(payload):
    context = payload.get("visual_context") or {}
    if not eligible(payload) or not any(ref.get("id") == expansion.RECIPE for ref in context.get("references", [])):
        return None
    return next((tuple(base["numbers"]) for source in expansion._sources(context)
        for base, _ in _fraction_bases(source["content"])), None)



_NUMBER_WORD = re.compile(
    r"\b(?:null|eins|zwo|zwei|drei|vier|fünf|fuenf|sechs|sieben|acht|neun|zehn|elf|zwölf|zwoelf|"
    r"one|two|three|four|five|six|seven|eight|nine|ten|zero)(?:en|er|es|e|n)?\b"
    r"|\b[a-zäöüß]*(?:zehn|zwanzig|dreißig|dreissig|vierzig|fünfzig|fuenfzig|sechzig|siebzig|achtzig|neunzig|"
    r"hundert|tausend|million|milliard|halb|drittel|viertel|fünftel|fuenftel|sechstel|siebtel|achtel|neuntel|"
    r"hundred|thousand)[a-zäöüß]*\b", re.I)


def _number_free_concept(prompt):
    """Only explicit concept questions without numerical or contextual tasks.

    Unicode numeric characters, written numbers, math/LaTeX and references to a
    displayed example remain unknown; saved prompts stay in unit_novelty.
    """
    return (bool(re.match(r"\s*(?:warum|weshalb|wieso|was|wie|welche[rsnm]?|erkläre|beschreibe|begründe)\b", prompt, re.I))
        and not any(character.isnumeric() or unicodedata.category(character) == "Sm" for character in prompt)
        and not _NUMBER_WORD.search(prompt)
        and not re.search(r"[\\/⁄∕／$=+*^_<>×÷√−{}-]|\b[IVXLCDM]+\b", prompt)
        and not re.search(r"\b(?:dies(?:er|e|es|en|em)|oben|unten|folgend\w*|gezeigt\w*|abgebildet\w*|"
            r"markiert\w*|gegeben\w*|nebenstehend\w*)\b|\bfaktor\s*(?:ein(?:e[rsnm]?)?|eins|zwei|drei|vier)\b", prompt, re.I))


def _history(payload, prompts):
    from .coaching import fraction_task_signature

    used, unknown, pool = set(), False, notebook._pool()
    for prompt in prompts:
        if not isinstance(prompt, str):
            raise ValueError(ERROR)
        signature = fraction_task_signature(prompt)
        if signature and signature[0] == "expand":
            # The legacy parser can read "mit 2/3" as factor 2. A known
            # numeric case must contain an actual whole-factor token.
            factor = re.search(r"\bmit\s+(?:(?:dem\s+)?faktor\s+)?([1-9]\d{0,3})(?!\d)(?!\s*[/⁄∕／])\b",
                unicodedata.normalize("NFKC", prompt).casefold())
            if factor is None or factor[1] != signature[2]:
                unknown = True
                continue
            values = (*map(int, signature[1]), int(signature[2]))
            if values in pool:
                used.add(values)
        elif re.search(r"\berweiter\w*", prompt, re.I) and not _number_free_concept(prompt):
            unknown = True
    return {"version": 1, "source_digest": _digest(expansion._sources(payload["visual_context"])),
        "signatures": [list(values) for values in sorted(used)], "unknown": unknown}


def with_history(payload, prompts):
    return {**payload, HISTORY: _history(payload, prompts)} if eligible(payload) else payload


def _exclusions(payload):
    value, pool = payload.get(HISTORY), notebook._pool()
    if (not isinstance(value, dict) or set(value) != {"version", "source_digest", "signatures", "unknown"}
            or type(value.get("version")) is not int or value["version"] != 1
            or value.get("source_digest") != _digest(expansion._sources(payload["visual_context"]))
            or type(value.get("unknown")) is not bool or not isinstance(value.get("signatures"), list)
            or any(not isinstance(row, list) or len(row) != 3 or any(type(n) is not int for n in row)
                or tuple(row) not in pool for row in value["signatures"])
            or len({tuple(row) for row in value["signatures"]}) != len(value["signatures"])):
        raise ValueError(ERROR)
    if value["unknown"]:
        raise ValueError(EXHAUSTED)
    return value, [_task("expand", tuple(values), "apply")[0] for values in value["signatures"]]


def prepare(payload):
    if not eligible(payload):
        if KEY in payload or HISTORY in payload:
            raise ValueError(ERROR)
        return payload
    from .providers import ProviderError

    context = payload["visual_context"]
    reference = next((ref for ref in context.get("references", []) if ref.get("id") == expansion.RECIPE
        and ref.get("version") == 1 and ref.get("subject") == "Mathematik" and ref.get("digest")), None)
    if reference is None:
        raise ValueError(ERROR)
    plans = (payload.get("learning_entry") or {}).get("units") or []
    if payload.get("learning_entry") and len(plans) != 1:
        raise ValueError(ERROR)
    # Exactly the existing ordinary OpenRouter/entry count, never a new limit.
    count = min(5, max(4, len(plans[0]["probes"]) + 2)) if plans else 2
    slots = notebook._slots(payload, count)
    practice = [slot for slot in slots if slot["role"] == "practice"]
    history, exclusions = _exclusions(payload)
    example = introduction_example(payload)
    if example is None:
        raise ValueError(ERROR)
    exclusions.extend(_task("expand", values, "apply")[0] for values in sorted(notebook._pool())
        if (values[0] * values[2], values[1] * values[2]) == example)
    previous = payload.get("previous_prompts") or []
    try:
        tasks = fraction_tasks(expansion._sources(context), "Mathematik", "", previous, "apply", len(practice),
            _digest([REVISION, context, slots, previous]), required_labels=["Brüche erweitern"] * len(practice),
            expansion_denominator_limit=24, excluded_prompts=exclusions)
    except ProviderError as error:
        if error.args == ("Für diese Bruchverfahren sind keine neuen kleinen Zahlenaufgaben mehr verfügbar.",):
            raise ValueError(EXHAUSTED) from None
        raise
    if len(tasks) != len(practice):
        raise ValueError(ERROR)
    for task, slot in zip(tasks, practice, strict=True):
        task["id"] = slot["id"]
        candidate = expansion._candidate(context, task, "apply")
        if candidate is None or task["answer"] != "/".join(map(str, candidate["proof"]["output"])):
            raise ValueError(ERROR)
    if "math_tasks" in payload and payload["math_tasks"] != tasks:
        raise ValueError(ERROR)
    plan = {"version": 1, "revision": REVISION, "context_digest": _digest(context), "exclusion_digest": _digest(history),
        "question_count": count, "tasks": tasks, "probes": [{key: copy.deepcopy(slot[key]) for key in notebook.CORE}
            for slot in slots if slot["role"] == "prior_check"]}
    if KEY in payload and payload[KEY] != plan:
        raise ValueError(ERROR)
    return {**payload, KEY: plan, "math_tasks": tasks}


@dataclass(frozen=True)
class Binding(notebook.Binding):
    @property
    def rules(self):
        return ("\n" + REVISION + ": material_expansion_plan enthält die unveränderten Kerne der normalen Materialrunde. "
            "Die kuratierten Lernstandsproben bleiben exakt erhalten; nur math_tasks sind neue Erweiterungsübungen. "
            "Wähle für jede Frage ausschließlich ihre vorbereitete solution-ID und übernimm alle festen Werte, Texte, "
            "Referenzen, Quellen und Aufdeckstufen. given zeigt einen getrennten Originalbruch. Ergänze kurze "
            "verständliche Hinweise; keine neuen Zahlen, Grafikparameter oder Ersatzaufgaben.")

    @property
    def context(self):
        return {**super().context, "revision": REVISION}


def bind_schema(schema, payload):
    if KEY not in payload:
        return None
    if prepare(payload) != payload:
        raise ValueError(ERROR)
    plan = payload[KEY]
    bounds = schema["properties"]["questions"]
    if bounds.get("minItems") != plan["question_count"] or bounds.get("maxItems") != plan["question_count"]:
        raise ValueError(ERROR)
    return notebook.bind_prepared_plan(schema, payload, plan, binding_type=Binding, revision=REVISION)


def validate_output(payload, data):
    if KEY not in payload:
        return
    plan = prepare(payload)[KEY]
    cores = {row["id"]: {key: row[key] for key in notebook.CORE} for row in [*plan["probes"], *plan["tasks"]]}
    questions = data.get("questions", [])
    if (len(questions) != plan["question_count"] or {q["id"] for q in questions} != set(cores)
            or any(any(q.get(key) != value for key, value in cores[q["id"]].items()) for q in questions)):
        raise ValueError(ERROR)


def validate_history(payload, data, prompts):
    if KEY not in payload:
        return
    validate_output(payload, data)
    fresh = _history(payload, prompts)
    seen = {tuple(row) for row in fresh["signatures"]}
    if fresh["unknown"]:
        raise ValueError(CURRENT_ERROR)
    for task in payload[KEY]["tasks"]:
        candidate = expansion._candidate(payload["visual_context"], task, "apply")
        if candidate is None or (*candidate["proof"]["input"], candidate["proof"]["factor"]) in seen:
            raise ValueError(CURRENT_ERROR)
