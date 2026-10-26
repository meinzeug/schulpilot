"""Source-backed expansion slots inside an explicitly selected notebook round.

Saved entry probes and their own curated references stay unchanged. New probes
reserve an original introduction before the remaining practice slots are filled.
Only remaining practice slots receive finite arithmetic BEFORE generation.
"""
import copy
from dataclasses import dataclass

from . import learning_entry
from . import study_fraction_expansions as expansion
from .math_tasks import _catalog, _numbers, _procedure_quote, _task, fraction_tasks
from .package_prepared_graphics import Binding as PackageBinding
from .package_prepared_graphics import _digest, _fraction_bases, bind_candidates
from .schemas import ExplanationStep
from .subject_content import PROFILES, Graphic, validate_question

REVISION = "notebook-fraction-expansion-1"
ERROR = "Die Heft-Runde lässt sich nicht vollständig an die bestätigte Erweiterungsregel und den Lernstart binden. Es wurde keine KI-Anfrage gesendet."
EXHAUSTED = "Für diese bestätigte Erweiterungsseite sind keine neuen passenden kleinen Aufgaben mehr verfügbar. Wähle eine andere bestätigte Heftseite zum Weiterlernen. Es wurde keine KI-Anfrage gesendet."
KEY = "notebook_expansion_plan"
HISTORY_KEY = "notebook_expansion_exclusions"
CORE = learning_entry.CORE


def eligible(payload):
    from .notebook_practice import requested_count

    return (requested_count(payload) is not None and payload.get("required_subject") == "Mathematik"
        and (payload.get("visual_context") or {}).get("required") is True
        and not any(payload.get(key) for key in ("review", "study_block", "selected_groups", "homework_practice",
            "exam_preparation", "exam_review_practice"))
        and bool(_procedure_quote(expansion._sources(payload.get("visual_context") or {}), "Brüche erweitern")))



def _supported(payload):
    if not eligible(payload):
        return False
    catalog = _catalog(expansion._sources(payload["visual_context"]), "Mathematik", "")
    return "Brüche erweitern" in catalog and not any(label in catalog for label in ("Brüche kürzen", "Brüche addieren"))


def introduction_example(payload):
    """Reserve one literal original before selecting NEW prerequisite probes."""
    if not _supported(payload):
        return None
    for source in expansion._sources(payload["visual_context"]):
        for base, _ in _fraction_bases(source["content"]):
            return tuple(base["numbers"])
    return None


def add_reference(db, payload):
    from .visual_reference_models import VisualReference

    if not _supported(payload):
        return payload
    row = db.get(VisualReference, (expansion.RECIPE, expansion.VERSION))
    if row is None or row.digest != _digest(row.recipe):
        return payload
    context = payload["visual_context"]
    ref = {"id": row.id, "version": row.version, "digest": row.digest, "kind": "fraction", "subject": "Mathematik"}
    return {**payload, "visual_context": {**context, "references": [*context["references"], ref]}}


def _slots(payload, count):
    entry = payload.get("learning_entry")
    if not entry:
        return [{"id": f"q{index + 1}", "role": "practice"} for index in range(count)]
    plans = entry.get("units") or []
    if (len(plans) != 1 or plans[0].get("group_id") is not None or plans[0].get("subject") != "Mathematik"
            or plans[0].get("entry_mode") not in ("prerequisite_probe", "reuse_evidence")):
        raise ValueError(ERROR)
    slots = learning_entry._specs(plans[0], count)
    if (not any(slot.get("role") == "practice" for slot in slots)
            or any(slot.get("role") == "prior_check" and any(key not in slot for key in CORE) for slot in slots)):
        raise ValueError(ERROR)
    return slots



def _pool():
    return {tuple(numbers) for numbers in _numbers("expand") if numbers[1] * numbers[2] <= 24}


def with_history(payload, prompts):
    """Compact ALL authorized source/day prompts; never copy raw history here."""
    if not _supported(payload):
        return payload
    sources = expansion._sources(payload["visual_context"])
    from .coaching import fraction_task_signature

    used, pool = set(), _pool()
    for prompt in prompts:
        if not isinstance(prompt, str):
            raise ValueError(ERROR)
        signature = fraction_task_signature(prompt)
        if signature and signature[0] == "expand":
            numbers = (*map(int, signature[1]), int(signature[2]))
            if numbers in pool:
                used.add(numbers)
    return {**payload, HISTORY_KEY: {"version": 1, "source_digest": _digest(sources),
        "signatures": [list(numbers) for numbers in sorted(used)]}}


def _history(payload):
    value = payload.get(HISTORY_KEY)
    pool = _pool()
    if (not isinstance(value, dict) or set(value) != {"version", "source_digest", "signatures"}
            or type(value.get("version")) is not int or value["version"] != 1
            or value.get("source_digest") != _digest(expansion._sources(payload["visual_context"]))
            or not isinstance(value.get("signatures"), list) or len(value["signatures"]) > len(pool)
            or any(not isinstance(row, list) or len(row) != 3 or any(type(number) is not int for number in row)
                or tuple(row) not in pool for row in value["signatures"])
            or len({tuple(row) for row in value["signatures"]}) != len(value["signatures"])):
        raise ValueError(ERROR)
    # Only private planner exclusions, not additional prompt text in the wire.
    return value, [_task("expand", tuple(numbers), "apply")[0] for numbers in value["signatures"]]


def prepare(payload):
    """Pure request-only plan, no database access, changed questions or retries."""
    from .notebook_practice import requested_count
    from .providers import ProviderError

    if not _supported(payload):
        if KEY in payload or HISTORY_KEY in payload:
            raise ValueError(ERROR)
        return payload
    context = payload["visual_context"]
    sources = expansion._sources(context)
    if not context.get("required") or not any(ref.get("id") == expansion.RECIPE and ref.get("version") == 1 for ref in context["references"]):
        raise ValueError(ERROR)
    count = requested_count(payload)
    slots = _slots(payload, count)
    practice = [slot for slot in slots if slot["role"] == "practice"]
    previous = payload.get("previous_prompts") or []
    exclusions, excluded_prompts = _history(payload)
    example = introduction_example(payload)
    if example is not None:
        # An introduction is teaching, not practice history. Keep its literal
        # pair out of derived answers without adding any learner evidence.
        excluded_prompts = [*excluded_prompts, *[_task("expand", numbers, "apply")[0]
            for numbers in sorted(_pool()) if (numbers[0] * numbers[2], numbers[1] * numbers[2]) == example]]
    try:
        tasks = fraction_tasks(sources, "Mathematik", "", previous, "apply", len(practice),
            _digest([REVISION, context, slots, previous]), required_labels=["Brüche erweitern"] * len(practice),
            expansion_denominator_limit=24, excluded_prompts=excluded_prompts)
    except ProviderError as error:
        if error.args == ("Für diese Bruchverfahren sind keine neuen kleinen Zahlenaufgaben mehr verfügbar.",):
            raise ValueError(EXHAUSTED) from None
        raise
    if len(tasks) != len(practice):
        raise ValueError(ERROR)
    for task, slot in zip(tasks, practice, strict=True):
        task["id"] = slot["id"]
    plan = {"version": 1, "revision": REVISION, "context_digest": _digest(context),
        "exclusion_digest": _digest(exclusions), "question_count": count,
        "tasks": tasks, "probes": [{key: copy.deepcopy(slot[key]) for key in CORE}
            for slot in slots if slot["role"] == "prior_check"]}
    if KEY in payload and payload[KEY] != plan:
        raise ValueError(ERROR)
    return {**payload, KEY: plan}


def _probe_candidates(payload, *, plan=None, revision=REVISION):
    context = payload["visual_context"]
    plan = payload[KEY] if plan is None else plan
    result = []
    reference = next((ref for ref in context["references"] if ref.get("id") == "math.fraction.part_whole"
        and ref.get("version") == 1 and ref.get("subject") == "Mathematik" and ref.get("digest")), None)
    if plan["probes"] and reference is None:
        raise ValueError(ERROR)
    entry_probes = {probe["id"]: probe for unit in (payload.get("learning_entry") or {}).get("units", [])
        for probe in unit.get("probes", [])}
    for core in plan["probes"]:
        probe = entry_probes.get(core["id"], {})
        source = next((source for source in context["sources"] if source.get("source_type") == "curated_foundation"
            and source.get("example_question_id") == core["id"] and source.get("example_digest") == _digest(core)
            and source.get("subject") == "Mathematik" and source.get("group_id") is None), None)
        if source is None or not probe.get("visual_example"):
            raise ValueError(ERROR)
        numbers = [probe["visual_example"]["numerator"], probe["visual_example"]["denominator"]]
        base = next(((base, text) for base, text in _fraction_bases(source["content"]) if base["numbers"] == numbers), None)
        if base is None:
            raise ValueError(ERROR)
        block = Graphic.model_validate({**base[0], "disclosure": "solution"})
        validate_question({"version": 1, "evidence_kind": "knowledge", "blocks": [block.model_dump()]},
            core, [source["content"]], PROFILES["Mathematik"], structured=True, subject="Mathematik")
        row = {"subject": "Mathematik", "group_id": None, "kind": "fraction", "disclosure": "solution",
            "reference": {"id": reference["id"], "version": 1}, "source_refs": [source["ref"]],
            "text": base[1], "block": block.model_dump(mode="json"), "question_core": copy.deepcopy(core)}
        row["id"] = "nf_" + _digest([revision, row, _digest(source), reference["digest"]])[:24]
        ExplanationStep.model_validate({"id": row["id"], "text": row["text"], "competence_id": None,
            "disclosure": "solution", "reference": row["reference"], "source_refs": row["source_refs"],
            "presentation": {"version": 1, "evidence_kind": "knowledge", "blocks": [block]}})
        result.append(row)
    return result


@dataclass(frozen=True)
class Binding(PackageBinding):
    @property
    def rules(self):
        return ("\n" + REVISION + ": notebook_expansion_plan enthält die festen Kerne dieser Heft-Runde. "
            "Übernimm id, type, prompt, answer, options und accepted exakt. Die eigenen Lernstandsproben "
            "bleiben unverändert; nur tasks sind neue Erweiterungsübungen. Wähle für jede Frage ausschließlich "
            "die zugehörige vorbereitete solution-ID. Keine Zahlen, Antworten, Quellen oder Aufdeckstufen ändern. "
            "Ergänze verständliche kurze Einführung, Hinweise und Erklärungen; der feste Grafikschritt bleibt geschlossen.")

    @property
    def context(self):
        return {"version": 1, "revision": REVISION, "candidates": [{key: copy.deepcopy(value)
            for key, value in row.items() if key != "block"} for row in self.candidates]}

    def question_bound(self, candidate, question):
        core = candidate.get("question_core") or (candidate.get("proof") or {}).get("task")
        return bool(core) and all(question.get(key) == value for key, value in core.items()) and question.get("learning_goal_id") is None

    def hydrate(self, data):
        result = super().hydrate({"units": [data]})["units"][0]
        choices = {candidate["id"]: candidate for candidate in self.candidates}
        for item in [data, *data["questions"]]:
            selected = choices[item["explanation_steps"][0]["presentation"]["blocks"][0]]
            if item["explanation_steps"][0].get("id") != selected["id"]:
                raise ValueError(ERROR)
        for original, restored in zip(data["questions"], result["questions"], strict=True):
            selected = choices[original["explanation_steps"][0]["presentation"]["blocks"][0]]
            if original["explanation_steps"][0].get("id") != selected["id"]:
                raise ValueError(ERROR)
            if selected.get("proof"):
                restored["explanation_steps"][0]["presentation"]["blocks"] = expansion._blocks(selected)
                expansion.validate_step(restored["explanation_steps"][0], selected)
        return result


def bind_schema(schema, payload):
    if KEY not in payload:
        return None
    if prepare(payload) != payload:
        raise ValueError(ERROR)
    return bind_prepared_plan(schema, payload, payload[KEY])


def bind_prepared_plan(schema, payload, plan, *, binding_type=Binding, revision=REVISION):
    """Shared pure renderer binding; each caller verifies its own real contract."""
    context = payload["visual_context"]
    candidates = [expansion._candidate(context, task, "apply") for task in plan["tasks"]]
    if any(candidate is None for candidate in candidates):
        raise ValueError(ERROR)
    probe_candidates = _probe_candidates(payload, plan=plan, revision=revision)
    probes = {probe["id"]: probe for unit in (payload.get("learning_entry") or {}).get("units", [])
        for probe in unit.get("probes", [])}
    exclusions = []
    for core in plan["probes"]:
        example = probes[core["id"]]["visual_example"]
        exclusions.append((example["numerator"], example["denominator"]))
        exclusions.extend(base["numbers"] for base, _ in _fraction_bases(core["answer"]))
    introductions = expansion._introductions(context, candidates, excluded_pairs=exclusions)
    if not introductions:
        raise ValueError(ERROR)
    binding = binding_type(tuple([*introductions, *probe_candidates, *candidates]))
    wrapper = {"$defs": schema["$defs"], "properties": {"units": {"items": copy.deepcopy(
        {key: value for key, value in schema.items() if key != "$defs"})}}}

    def question_binding(node, candidate):
        core = candidate.get("question_core") or candidate["proof"]["task"]
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

    bind_candidates(wrapper, binding, question_binding=question_binding)
    for definition in wrapper["$defs"].values():
        props = definition.get("properties", {})
        ids = props.get("presentation", {}).get("properties", {}).get("blocks", {}).get("items", {}).get("enum", [])
        if len(ids) == 1 and ids[0] in {candidate["id"] for candidate in binding.candidates}:
            props["id"] = {"type": "string", "enum": ids}
            props["competence_id"] = {"type": "null"}
    body = wrapper["properties"]["units"]["items"]
    schema.clear()
    schema.update(body, **{"$defs": wrapper["$defs"]})
    return binding


def validate_output(payload, data):
    if KEY not in payload:
        return
    plan = prepare(payload)[KEY]
    cores = {row["id"]: {key: row[key] for key in CORE} for row in [*plan["probes"], *plan["tasks"]]}
    questions = data.get("questions", [])
    if (len(questions) != plan["question_count"] or {question["id"] for question in questions} != set(cores)
            or any(any(question.get(key) != value for key, value in cores[question["id"]].items()) for question in questions)):
        raise ValueError(ERROR)
