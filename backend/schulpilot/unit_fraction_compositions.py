"""Request-bound whole/remainder proofs using existing proper-fraction blocks.

Only this immutable recipe admits the proven input and decomposition together.
No model prose, learner answer or arithmetic equivalence creates source evidence.
"""
import copy
import re
from dataclasses import dataclass

from .package_prepared_graphics import Binding as PackageBinding
from .package_prepared_graphics import (
    _digest,
    _fraction_bases,
    _fraction_prompt_pattern,
    _question_anchor,
    bind_candidates,
)
from .subject_content import Graphic

RECIPE = "math.fraction.wholes_remainder"
REVISION = "unit-fraction-composition-1"
ERROR = "Ungültige vorabgeprüfte Ganzes-Rest-Komposition."
METHOD = re.compile(r"unecht\w*\s+br(?:ü|ue)ch\w*.{0,100}gemischt|br(?:ü|ue)ch\w*.{0,60}als\s+gemischt", re.I)
LITERAL = re.compile(r"(?<![\w/.,+−-])([0-9]{1,2})\s*/\s*([0-9]{1,2})(?![\w/]|[.,][0-9])|\\(?:d?frac)\{([0-9]{1,2})\}\{([0-9]{1,2})\}")
MIXED_GOAL = re.compile(r"(?:einen\s+)?unecht(?:e|en|er)\s+(?:bruch|brüche|brueche)\s+(?:als|in)\s+"
    r"(?:eine\s+)?gemischt(?:e|en)\s+zahl(?:en)?\s+(?:darstellen|umwandeln|schreiben)", re.I)


def eligible(source):
    return (source.get("subject") == "Mathematik" and not source.get("source_type")
        and bool(METHOD.search(" ".join((source.get("topic", "") + "\n" + source.get("content", "")).split()))))


def _focused_practice(payload):
    """Only the existing goal-bound, explicitly requested mixed-number follow-up."""
    if (payload.get("review") is not True or payload.get("practice_kind") not in ("repair", "check")
            or payload.get("required_subject") != "Mathematik"
            or payload.get("math_tasks")
            or not isinstance(payload.get("required_topic"), str) or not payload["required_topic"].strip()):
        return False
    focus, goals = payload.get("focus_goal_ids"), payload.get("learning_goals")
    if (not isinstance(focus, list) or not 1 <= len(focus) <= 2 or any(not isinstance(value, str) for value in focus)
            or len(set(focus)) != len(focus) or not isinstance(goals, list)
            or any(not isinstance(goal, dict) or goal.get("id") not in ("g1", "g2", "g3", "g4") for goal in goals)
            or len({goal["id"] for goal in goals}) != len(goals)):
        return False
    by_id = {goal["id"]: goal for goal in goals}
    if not set(focus) <= by_id.keys():
        return False
    from .learning_sources import exact_quote

    sources = [source["content"] for source in (payload.get("visual_context") or {}).get("sources", [])
        if eligible(source)]
    return bool(sources) and all(isinstance(by_id[key].get("label"), str)
        and MIXED_GOAL.fullmatch(" ".join(by_id[key]["label"].split()).rstrip(".!?"))
        and isinstance(by_id[key].get("source_excerpt"), str)
        and exact_quote(by_id[key]["source_excerpt"], sources) for key in focus)


def add_reference(db, payload):
    from .visual_reference_models import VisualReference

    context = payload.get("visual_context") or {}
    if (payload.get("selected_groups") or (payload.get("review") and not _focused_practice(payload))
            or any(payload.get(k) for k in ("study_block", "homework_practice", "exam_preparation", "exam_review_practice"))
            or not any(eligible(source) for source in context.get("sources", []))):
        return payload
    row = db.get(VisualReference, (RECIPE, 2)) or db.get(VisualReference, (RECIPE, 1))
    if row and _digest(row.recipe) == row.digest:
        context = {**context, "references": [*context["references"], {"id": row.id, "version": row.version,
            "digest": row.digest, "kind": "fraction", "subject": "Mathematik"}]}
        return {**payload, "visual_context": context}
    return payload


def _v2_text(n, d, q, r, stage):
    if stage == "given":
        return "Ein Ganzes besteht aus einem Teil." if d == 1 else f"Ein Ganzes besteht aus {d} gleich großen Teilen."
    bundle = "einen Teil" if d == 1 else f"{d} Teile"
    wholes = "So entsteht ein Ganzes." if q == 1 else f"So entstehen {q} Ganze."
    remainder = (f"Es bleibt ein Teil: 1/{d}." if r == 1 else
        f"Es bleiben {r} Teile: {r}/{d}." if r else "Es bleibt kein Bruchteil übrig.")
    return f"Bei {n}/{d} bündeln wir jeweils {bundle} zu einem Ganzen. {wholes} {remainder}"


def compile_candidates(context):
    if not context.get("required"):
        return []
    refs = context.get("references", [])
    special = max((r for r in refs if r.get("id") == RECIPE and type(r.get("version")) is int
        and r["version"] in (1, 2) and r.get("digest") and r.get("subject") == "Mathematik"),
        key=lambda r: r["version"], default=None)
    if not special:
        return []
    rows = []
    rule_sources = []
    for source in context.get("sources", []):
        if (not eligible(source) or type(source.get("revision")) is not int or source["revision"] < 1
                or not re.fullmatch(r"[a-f0-9]{32}", source.get("material_id", ""))
                or source.get("group_id") is not None):
            continue
        matches = list(LITERAL.finditer(source["content"]))
        from .fraction_conversion_rule import evidence

        rule = evidence(source["content"], {
            tuple(map(int, match.groups()[:2] if match[1] else match.groups()[2:])) for match in matches
        })
        if rule:
            rule_sources.append((source, rule))
        for match in matches:
            if len(rows) >= 6:
                break
            n, d = map(int, match.groups()[:2] if match[1] else match.groups()[2:])
            if not d or d > 24 or re.search(r"[+−-]\s*$", source["content"][:match.start()]):
                continue
            q, r = divmod(n, d)
            if not 1 <= q <= 3:
                continue
            proof = {"version": 1, "input": [n, d], "whole": q, "remainder": r,
                "source_digest": _digest(source), "reference_digest": special["digest"]}
            for stage in ("given", "solution"):
                pairs = [[d, d]] if stage == "given" else [[d, d]] * q + ([[r, d]] if r else [])
                blocks = [Graphic.model_validate({"kind": "fraction", "title": "Ein Ganzes" if a == d else "Verbleibender Bruchteil",
                    "disclosure": stage, "source_excerpt": match.group(), "labels": [], "numbers": [a, b],
                    "connections": [], "marks": [], "unit": "", "variant": ""}).model_dump(mode="json") for a, b in pairs]
                row = {"subject": "Mathematik", "group_id": None, "kind": "fraction",
                    "reference": {"id": RECIPE, "version": special["version"]}, "source_refs": [source["ref"]],
                    "disclosure": stage, "text": (f"Ein Ganzes besteht aus {d} gleich großen Teilen." if stage == "given" else
                        f"Bei {n}/{d} bündeln wir jeweils {d} Teile zu einem Ganzen. So entstehen {q} Ganze. "
                        + (f"Es bleiben {r} Teile: {r}/{d}." if r else "Es bleibt kein Bruchteil übrig.")),
                    "block": blocks[0], "proof": proof}
                if special["version"] == 2:
                    row["text"] = _v2_text(n, d, q, r, stage)
                row["id"] = "uc_" + _digest({"revision": REVISION, "candidate": row})[:24]
                if all(old["id"] != row["id"] for old in rows):
                    rows.append(row)
    # A copied worked example alone never licenses new inputs. The same safe
    # source must explicitly state division of numerator by denominator and
    # contain a correct, matching quotient/remainder example. Keep original
    # candidates/IDs intact and add only private solution candidates; the
    # existing planner sends just the selected questions, never this full pool.
    if rule_sources:
        from .fraction_conversion_rule import inputs

        source, rule = rule_sources[0]
        existing = {tuple(row["proof"]["input"]) for row in rows}
        for n, d in inputs():
            if (n, d) in existing:
                continue
            q, r = divmod(n, d)
            block = Graphic.model_validate({"kind": "fraction", "title": "Ein Ganzes",
                "disclosure": "solution", "source_excerpt": rule["quote"], "labels": [], "numbers": [d, d],
                "connections": [], "marks": [], "unit": "", "variant": ""}).model_dump(mode="json")
            row = {"subject": "Mathematik", "group_id": None, "kind": "fraction",
                "reference": {"id": RECIPE, "version": special["version"]}, "source_refs": [source["ref"]],
                "disclosure": "solution", "text": _v2_text(n, d, q, r, "solution"),
                "block": block, "proof": {"version": 1, "input": [n, d], "whole": q, "remainder": r,
                    "source_digest": _digest(source), "reference_digest": special["digest"], "rule": copy.deepcopy(rule)}}
            row["id"] = "uc_" + _digest({"revision": REVISION, "candidate": row})[:24]
            rows.append(row)
    return rows


def _blocks(candidate):
    proof = candidate["proof"]
    d, q, r = proof["input"][1], proof["whole"], proof["remainder"]
    pairs = [[d, d]] if candidate["disclosure"] == "given" else [[d, d]] * q + ([[r, d]] if r else [])
    return [{**copy.deepcopy(candidate["block"]), "numbers": [float(value) for value in pair],
        "title": "Ein Ganzes" if pair[0] == d else "Verbleibender Bruchteil"} for pair in pairs]


def _bound_question(candidate, question):
    prompt = question.get("prompt", "")
    pairs = [(int(m[1] or m[3]), int(m[2] or m[4])) for m in LITERAL.finditer(prompt)]
    return bool(re.search(_pattern(candidate), prompt) and pairs
        and all(pair == tuple(candidate["proof"]["input"]) for pair in pairs))


def _pattern(candidate):
    if candidate.get("proof"):
        n, d = candidate["proof"]["input"]
        return rf"(^|[^\w/.,+−-]){n}/{d}($|[^\w/.,]|\.(?:$|[^0-9])|,(?:$|[^0-9]))"
    return _fraction_prompt_pattern(candidate)


@dataclass(frozen=True)
class Binding(PackageBinding):
    @property
    def fixed_text(self):
        return True

    @property
    def rules(self):
        rules = ("\n" + REVISION + ": Wähle ausschließlich eine vorbereitete Grafik-ID für den genau passenden "
            "ASCII-n/d-Frageanker. Die ID bindet Originalquelle, Rezeptversion, Ganzes/Rest und Aufdeckstufe. "
            "presentation.blocks=[ID]; keine Grafikparameter selbst erzeugen. Introtext exakt übernehmen. "
            "Grafikstufen: given zeigt nur ein Ganzes; die vollständige Zerlegung gehört ausschließlich in solution. "
            "Den vorab geprüften kurzen Schritttext unverändert übernehmen. Bei der Komposition darfst du ausschließlich "
            "den gebundenen Eingangsbruch und seine geprüften Ganzes-/Restanteile erklären. Antworten und feste "
            "Einstiegsfragen niemals ändern. Gegebene Einführung zeigt nur EIN allgemeines Ganzes, keine Aufgabenlösung.")
        if any(candidate.get("planned_notebook") for candidate in self.candidates):
            from .notebook_fraction_compositions import REVISION as notebook_revision

            rules += ("\n" + notebook_revision + ": Jede verbleibende Heftaufgabe ist vorab vollständig geplant. "
                "Übernimm id, type, prompt, answer, options und accepted exakt aus question_core der zugeordneten "
                "solution-ID. Keine weiteren Brüche oder Aufgaben ergänzen. Voraussetzungen behalten ihren eigenen "
                "festen Lernstart-Core und ihre eigene Grundlagenquelle. Nur Hinweise und kurze Erklärungen ergänzen.")
        if any(candidate.get("planned_practice") for candidate in self.candidates):
            from .fraction_practice_plan import REVISION as practice_revision

            rules += ("\n" + practice_revision + ": Die beiden Anschlussfragen sind bereits vollständig geplant. "
                "Übernimm id, learning_goal_id, type, prompt, answer, options und accepted exakt aus question_core "
                "der zugeordneten solution-ID. Keine ausgeschriebene Ersatzfrage, keine anderen Zahlen, "
                "keine weiteren Aufgaben und keine neue Musterantwort. Nur passende kurze Hinweise und eine "
                "verständliche Erklärung ergänzen; der feste Grafikschritt bleibt unverändert.")
        return rules

    def question_bound(self, candidate, question):
        if candidate.get("question_core"):
            return all(question.get(k) == v for k, v in candidate["question_core"].items())
        return _bound_question(candidate, question) if candidate.get("proof") else _question_anchor(candidate, question)

    @property
    def context(self):
        return {"version": 1, "revision": REVISION, "candidates": [{k: copy.deepcopy(v) for k, v in c.items()
            if k not in ("block", "blocks")} for c in self.candidates]}

    def hydrate(self, data):
        wrapped = super().hydrate({"units": [data]})["units"][0]
        choices = {c["id"]: c for c in self.candidates}
        for item in [data, *data["questions"]]:
            selected = choices[item["explanation_steps"][0]["presentation"]["blocks"][0]]
            target = wrapped if item is data else next(q for q in wrapped["questions"] if q["id"] == item["id"])
            if selected.get("proof"):
                target["explanation_steps"][0]["presentation"]["blocks"] = _blocks(selected)
                validate_step(target["explanation_steps"][0], self.candidates, introduction=item is data, question=None if item is data else item)
        return wrapped


def validate_step(raw, candidates, *, introduction=False, question=None):
    step = raw.model_dump(mode="json") if hasattr(raw, "model_dump") else raw
    presentation = step.get("presentation", {})
    if (set(presentation) != {"version", "evidence_kind", "blocks"} or type(presentation.get("version")) is not int
            or presentation["version"] != 1 or presentation.get("evidence_kind") != "knowledge"):
        raise ValueError(ERROR)
    selected = [c for c in candidates if c.get("proof") and c["id"] == step.get("id") and _digest(c["reference"]) == _digest(step.get("reference"))
        and c["source_refs"] == step.get("source_refs") and c["disclosure"] == step.get("disclosure")
        and _digest(_blocks(c)) == _digest(step.get("presentation", {}).get("blocks"))]
    if not selected or (step["disclosure"] == "given") != introduction:
        raise ValueError(ERROR)
    for candidate in selected:
        if introduction:
            if step["text"] == candidate["text"]:
                return
            continue
        if question is None or not _bound_question(candidate, question):
            continue
        if step["text"] != candidate["text"]:
            continue
        proof = candidate["proof"]
        pairs = {tuple(proof["input"]), *(tuple(b["numbers"]) for b in _blocks(candidate))}
        mentioned = [(int(m[1] or m[3]), int(m[2] or m[4])) for m in LITERAL.finditer(step["text"])]
        if all(pair in pairs for pair in mentioned):
            return
    raise ValueError(ERROR)


def bind_schema(schema, payload):
    if ((payload.get("review") and not _focused_practice(payload))
            or any(payload.get(k) for k in ("study_block", "homework_practice", "exam_preparation", "exam_review_practice"))):
        return None
    context = payload.get("visual_context") or {}
    candidates = compile_candidates(context)
    # New rule-derived values are private planner input, never an unbounded
    # menu for ordinary generation. Only the consciously selected notebook or
    # goal-bound follow-up planner may pick and close their exact task cores.
    if "notebook_composition_plan" not in payload and not _focused_practice(payload):
        candidates = [candidate for candidate in candidates if not candidate.get("proof", {}).get("rule")]
    if not candidates:
        if _focused_practice(payload):
            from .fraction_practice_plan import ERROR as practice_pool_error

            raise ValueError(practice_pool_error)
        return None
    if _focused_practice(payload):
        from .fraction_practice_plan import plan
        from .providers import practice_tasks

        selected = plan(candidates, payload.get("practice_tasks") or practice_tasks(payload),
            payload.get("fraction_practice_history"))
        candidates = [*[c for c in candidates if c["disclosure"] == "given"], *selected]
    from .notebook_fraction_compositions import bind_candidates as bind_notebook_candidates

    candidates = bind_notebook_candidates(payload, candidates)
    # Fixed prerequisite probes retain their own curated source and reference.
    for source in context.get("sources", []):
        if source.get("source_type") != "curated_foundation":
            continue
        reference = next((r for r in context["references"] if r.get("id") == "math.fraction.part_whole"), None)
        if not reference:
            continue
        probe = next((p for unit in (payload.get("learning_entry") or {}).get("units", [])
            for p in unit.get("probes", []) if p["id"] == source.get("example_question_id")), None)
        if not probe or not probe.get("visual_example"):
            continue
        for base, text in _fraction_bases(source["content"]):
            if base["numbers"] != [probe["visual_example"]["numerator"], probe["visual_example"]["denominator"]]:
                continue
            for stage in ("solution",):
                row = {"subject": "Mathematik", "group_id": None, "kind": "fraction", "disclosure": stage,
                    "reference": {"id": reference["id"], "version": reference["version"]},
                    "source_refs": [source["ref"]], "text": text, "block": {**base, "disclosure": stage},
                    "question_core": {key: probe[key] for key in ("id", "type", "prompt", "answer", "options", "accepted")}}
                row["id"] = "uc_" + _digest(row)[:24]
                candidates.append(row)
    binding = Binding(tuple(candidates))
    wrapper = {"$defs": schema["$defs"], "properties": {"units": {"items": copy.deepcopy({k: v for k, v in schema.items() if k != "$defs"})}}}
    def question_binding(node, candidate):
        props = node["properties"]
        core = candidate.get("question_core")
        if core:
            if candidate.get("planned_practice") or candidate.get("planned_notebook"):
                if ((candidate.get("planned_practice") and props["id"].get("enum") != [core["id"]])
                        or (candidate.get("planned_notebook") and props["id"].get("enum") not in (None, [core["id"]]))
                        or (candidate.get("planned_practice")
                            and props.get("learning_goal_id", {}).get("enum") != [core["learning_goal_id"]])
                        or "short" not in props["type"].get("enum", [])):
                    return None
                for key in ("id", "type", "prompt", "answer"):
                    fixed = props[key].get("enum", [props[key]["const"]] if "const" in props[key] else [])
                    if fixed and core[key] not in fixed:
                        return None
                    props[key].update(type="string", enum=[core[key]])
                props["options"].update(minItems=0, maxItems=0)
                props["accepted"].update(minItems=0, maxItems=0)
            elif props["id"].get("enum") != [core["id"]] or props["prompt"].get("enum") != [core["prompt"]]:
                return None
        else:
            prompt = props["prompt"]
            pattern = _pattern(candidate)
            if prompt.get("pattern") and prompt["pattern"] != pattern:
                raise ValueError(ERROR)
            if prompt.get("enum") and not all(re.search(pattern, p) for p in prompt["enum"]):
                return None
            props["prompt"]["pattern"] = pattern
        props["presentation"] = {"type": "null"}
        return node

    bind_candidates(wrapper, binding, prompt_pattern=_pattern, question_binding=question_binding)
    body = wrapper["properties"]["units"]["items"]
    schema.clear()
    schema.update(body, **{"$defs": wrapper["$defs"]})
    # Bind given prose too: no model-written solution can enter the introduction.
    for name, node in schema["$defs"].items():
        props = node.get("properties", {})
        if name.startswith("PreparedStep") and "presentation" in props and props.get("disclosure", {}).get("enum"):
            identifier = props["presentation"]["properties"]["blocks"]["items"]["enum"][0]
            props["id"] = {"type": "string", "enum": [identifier]}
            if props["disclosure"]["enum"] == ["given"]:
                props["text"] = {"type": "string", "enum": [next(c["text"] for c in candidates if c["id"] == identifier)]}
    return binding


def with_practice_history(payload, prompts):
    """Called privately with complete own chain/day prompts before dispatch."""
    if not _focused_practice(payload):
        return payload
    from .fraction_practice_plan import history

    candidates = compile_candidates(payload.get("visual_context") or {})
    return {**payload, "fraction_practice_history": history(candidates, prompts)}


def validate_practice_history(payload, data, prompts):
    """Recheck after the existing Child lock; never repair a returned question."""
    if not _focused_practice(payload):
        return
    from .fraction_practice_plan import CURRENT_ERROR, ERROR, INVALID, history, plan
    from .providers import practice_tasks

    candidates = compile_candidates(payload.get("visual_context") or {})
    try:
        expected = plan(candidates, practice_tasks(payload), history(candidates, prompts))
    except ValueError as error:
        if error.args in ((ERROR,), (INVALID,)):
            raise ValueError(CURRENT_ERROR) from None
        raise
    cores = {candidate["question_core"]["id"]: candidate["question_core"] for candidate in expected}
    questions = data.get("questions")
    if (not isinstance(questions, list) or len(questions) != 2
            or {question.get("id") for question in questions} != set(cores)
            or any(any(question.get(key) != value for key, value in cores[question["id"]].items()) for question in questions)):
        raise ValueError(CURRENT_ERROR)
