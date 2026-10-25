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


def eligible(source):
    return (source.get("subject") == "Mathematik" and not source.get("source_type")
        and bool(METHOD.search(" ".join((source.get("topic", "") + "\n" + source.get("content", "")).split()))))


def add_reference(db, payload):
    from .visual_reference_models import VisualReference

    context = payload.get("visual_context") or {}
    if (payload.get("selected_groups") or any(payload.get(k) for k in (
            "review", "study_block", "homework_practice", "exam_preparation", "exam_review_practice"))
            or not any(eligible(source) for source in context.get("sources", []))):
        return payload
    row = db.get(VisualReference, (RECIPE, 1))
    if row and _digest(row.recipe) == row.digest:
        context = {**context, "references": [*context["references"], {"id": row.id, "version": 1,
            "digest": row.digest, "kind": "fraction", "subject": "Mathematik"}]}
        return {**payload, "visual_context": context}
    return payload


def compile_candidates(context):
    if not context.get("required"):
        return []
    refs = context.get("references", [])
    special = next((r for r in refs if r.get("id") == RECIPE and type(r.get("version")) is int
        and r["version"] == 1 and r.get("digest") and r.get("subject") == "Mathematik"), None)
    if not special:
        return []
    rows = []
    for source in context.get("sources", []):
        if (not eligible(source) or type(source.get("revision")) is not int or source["revision"] < 1
                or not re.fullmatch(r"[a-f0-9]{32}", source.get("material_id", ""))
                or source.get("group_id") is not None):
            continue
        for match in LITERAL.finditer(source["content"]):
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
                    "reference": {"id": RECIPE, "version": 1}, "source_refs": [source["ref"]],
                    "disclosure": stage, "text": (f"Ein Ganzes besteht aus {d} gleich großen Teilen." if stage == "given" else
                        f"Bei {n}/{d} bündeln wir jeweils {d} Teile zu einem Ganzen. So entstehen {q} Ganze. "
                        + (f"Es bleiben {r} Teile: {r}/{d}." if r else "Es bleibt kein Bruchteil übrig.")),
                    "block": blocks[0], "proof": proof}
                row["id"] = "uc_" + _digest({"revision": REVISION, "candidate": row})[:24]
                if all(old["id"] != row["id"] for old in rows):
                    rows.append(row)
            if len(rows) >= 6:
                return rows
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
        return ("\n" + REVISION + ": Wähle ausschließlich eine vorbereitete Grafik-ID für den genau passenden "
            "ASCII-n/d-Frageanker. Die ID bindet Originalquelle, Rezeptversion, Ganzes/Rest und Aufdeckstufe. "
            "presentation.blocks=[ID]; keine Grafikparameter selbst erzeugen. Introtext exakt übernehmen. "
            "Grafikstufen: given zeigt nur ein Ganzes; die vollständige Zerlegung gehört ausschließlich in solution. "
            "Den vorab geprüften kurzen Schritttext unverändert übernehmen. Bei der Komposition darfst du ausschließlich "
            "den gebundenen Eingangsbruch und seine geprüften Ganzes-/Restanteile erklären. Antworten und feste "
            "Einstiegsfragen niemals ändern. Gegebene Einführung zeigt nur EIN allgemeines Ganzes, keine Aufgabenlösung.")

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
    if any(payload.get(k) for k in ("review", "study_block", "homework_practice", "exam_preparation", "exam_review_practice")):
        return None
    context = payload.get("visual_context") or {}
    candidates = compile_candidates(context)
    if not candidates:
        return None
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
            if props["id"].get("enum") != [core["id"]] or props["prompt"].get("enum") != [core["prompt"]]:
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
