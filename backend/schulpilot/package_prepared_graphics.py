"""Private, request-bound graphic compilation; no DB, model, activity or writes.

The model selects a finite ID. This is a requested wire projection, hydrated
before canonical validation, never a repair of an invalid provider response.
"""
import copy
import hashlib
import json
import re
import unicodedata
from dataclasses import dataclass

from .subject_content import PROFILES, Graphic, validate_question
from .visual_reference_schemas import ExplanationStep
from .visual_references import _meaningful

REVISION = "package-prepared-graphics-2"
MAX_BASE_CANDIDATES = 8
STAGES = ("given", "hint1", "hint2", "hint3", "solution")
RULES = """
package-prepared-graphics-2: DIESER Auftrag verwendet ausschließlich servergeprüfte Grafiken.
prepared_graphics.candidates enthält endliche IDs mit genau gebundener Quelle, Referenz,
Stufe und Schritttext. Wähle eine zum tatsächlichen Lernziel passende ID. Im angeforderten
Wireformat ist presentation.blocks=[dieseID], NICHT ein neu abgeschriebener Graphic-Block.
Text/Referenz/source_refs/disclosure gehören unverändert zur selben ID und zum selben Fach.
Der Server stellt genau diese gespeicherte Grafik vor allen bisherigen Prüfungen wieder her.
Keine neuen Beschriftungen, Zitate, Zahlen, Grafikparameter oder Ersatzgrafiken erfinden.
Aufgaben, Antworten, Hinweise und Quellen werden weiterhin vollständig unabhängig geprüft.
FRAGEBEZUG: Jeder Fragezweig ist an genau EINE Bruchdarstellung mit ihren vier erlaubten
Aufdeckstufen-IDs gebunden. Wähle genau eine dieser IDs. Der Frageprompt
muss genau deren Zähler/Nenner ausdrücklich in ASCII als n/d enthalten, ohne Leerzeichen
am Bruchstrich. Dieser Bruchanker darf auch innerhalb einer LaTeX-Umgebung stehen,
aber nicht als \\frac{n}{d}/\\dfrac{n}{d}; keine andere wertgleiche Darstellung. Alle
übrigen Formeln dürfen wie bisher LaTeX verwenden. Die Originalquelle bleibt unverändert. Frage-Step-ID,
Text, Quelle und Aufdeckstufe gehören zum selben gewählten Zweig. Szenen sind in diesem
vorbereiteten Mathevertrag nur für die Einführung verfügbar, nicht als Fragegrafik.

"""


def _digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                    separators=(",", ":"), allow_nan=False).encode()).hexdigest()


def _fraction_bases(content):
    # Whole literal tokens only. Improper/negative/unsupported fractions are
    # never reinterpreted, rounded, reduced, capped or turned into percentages.
    patterns = (r"(?<![\w/.,+−-])([0-9]{1,2})[ \t]*/[ \t]*([0-9]{1,2})(?![\w/]|[.,][0-9])",
                r"\\(?:d?frac)[ \t]*\{[ \t]*([0-9]{1,2})[ \t]*\}[ \t]*\{[ \t]*([0-9]{1,2})[ \t]*\}")
    matches = sorted((match for pattern in patterns for match in re.finditer(pattern, content)), key=lambda match: match.start())
    seen = set()
    for match in matches:
        if re.search(r"[+−-][ \t]*$", content[:match.start()]):
            continue  # A separated sign is not a positive fraction either.
        n, d = map(int, match.groups())
        if not 0 <= n <= d <= 24 or d == 0 or (n, d) in seen:
            continue
        seen.add((n, d))
        yield ({"kind": "fraction", "title": f"{n}/{d}", "source_excerpt": match.group(),
                "labels": [], "numbers": [n, d], "connections": [], "marks": [], "unit": "", "variant": "",
                "scene": None, "text_probe": None, "lab": None},
               f"Der Bruch {n}/{d} beschreibt {n} von {d} gleich großen Teilen eines Ganzen.")


def _scene_bases(content):
    # Only a COMPLETE short source line of 2..4 literal labels and arrows.
    # Do not guess semantic relations from prose, omit qualifiers or reverse an
    # arrow. The unchanged canonical scene/source validator checks every edge.
    for line in content.splitlines():
        quote = line.strip()
        if not quote or len(quote) > 300 or not re.search(r"→|->", quote):
            continue
        labels = [label.strip() for label in re.split(r"\s*(?:→|->)\s*", quote.removesuffix("."))]
        if not 2 <= len(labels) <= 4 or len(set(label.casefold() for label in labels)) != len(labels):
            continue
        if any(not label or len(label) > 60 or re.search(r"[.!?;:=<>\n]", label) for label in labels):
            continue
        objects = [{"id": f"o{i}", "label": label, "shape": "box", "tone": "neutral"} for i, label in enumerate(labels)]
        placements = [{"object_id": row["id"], "slot": i} for i, row in enumerate(objects)]
        edges = [{"start": objects[i]["id"], "end": objects[i + 1]["id"], "label": ""} for i in range(len(objects) - 1)]
        phases = [{"caption": labels[i], "source_excerpt": quote, "placements": placements,
                   "highlight": [objects[i]["id"]], "edges": edges} for i in (0, 1)]
        yield ({"kind": "scene", "title": labels[0], "source_excerpt": quote, "labels": labels,
                "numbers": [], "connections": [], "marks": [], "unit": "", "variant": "",
                "scene": {"version": 1, "layout": "row", "objects": objects, "steps": phases, "transition_ms": 400},
                "text_probe": None, "lab": None}, "Die belegte Pfeilfolge: " + quote)


def compile_candidates(payload):
    """Return bounded PRIVATE candidates from the exact current safe context.

    Callers may count kinds/validity, but must not log these source-bound blocks
    or private text. Identity binds the full source snapshot, plan and recipe.
    """
    if payload.get("package_partition") is None:
        return []
    context = payload.get("visual_context") or {}
    if not context.get("required"):
        return []
    result = []
    for group in payload.get("selected_groups", []):
        subject, group_id = group.get("subject"), group.get("id")
        refs = [row for row in context.get("references", []) if row.get("subject") == subject]
        sources = [row for row in context.get("sources", []) if row.get("subject") == subject
                   and row.get("group_id") == group_id and isinstance(row.get("content"), str)]
        count = 0
        for source in sources:
            bases = list(_fraction_bases(source["content"])) if subject == "Mathematik" else []
            bases.extend(_scene_bases(source["content"]))
            for base, text in bases:
                if count >= MAX_BASE_CANDIDATES:
                    break
                if base["kind"] not in PROFILES.get(subject, ()) or len(text) > 350:
                    continue
                references = [row for row in refs if row.get("kind") == base["kind"]]
                added = False
                for reference in references:
                    if type(reference.get("version")) is not int or not reference.get("digest"):
                        continue  # Actual immutable recipe metadata, not model/client aliases.
                    for stage in STAGES:
                        try:
                            block = Graphic.model_validate({**base, "disclosure": stage})
                            _meaningful(block, reference)
                            validate_question({"version": 1, "evidence_kind": "knowledge", "blocks": [block.model_dump()]},
                                {"prompt": "", "type": "short", "answer": "", "accepted": []},
                                [source["content"]], PROFILES[subject], structured=True, subject=subject)
                            value = ExplanationStep.model_validate({"id": "prepared", "text": text, "competence_id": None,
                                "disclosure": stage, "presentation": {"version": 1, "evidence_kind": "knowledge", "blocks": [block]},
                                "reference": {"id": reference["id"], "version": reference["version"]}, "source_refs": [source["ref"]]})
                        except ValueError:
                            continue  # Unsupported literal shape is not repaired or fabricated.
                        record = {"subject": subject, "group_id": group_id, "reference": value.reference.model_dump(),
                                  "disclosure": stage, "source_refs": value.source_refs, "text": value.text,
                                  "kind": block.kind, "block": block.model_dump(mode="json")}
                        identity = {"revision": REVISION, "plan_digest": payload.get("package_plan_digest"),
                                    "partition": payload["package_partition"], "source_digest": _digest(source),
                                    "reference_digest": reference["digest"], "candidate": record}
                        record["id"] = "pg_" + _digest(identity)[:24]
                        if all(item["id"] != record["id"] for item in result):
                            result.append(record)
                        added = True
                count += added
    return result


def _question_anchor(candidate, question):
    """Require explicit displayed parameters, without rewriting a question.

    This is a bounded relevance check, not a general semantic answer proof.
    Exact numerator/denominator identity preserves the requested representation;
    scene labels preserve case because scientific symbols can differ by case.
    """
    prompt = question.get("prompt")
    if not isinstance(prompt, str):
        return False
    block = candidate["block"]
    if block["kind"] == "fraction":
        pair = tuple(map(int, block["numbers"]))
        return any(tuple(map(int, base["numbers"])) == pair for base, _ in _fraction_bases(prompt))
    if block["kind"] == "scene":
        text = " ".join(unicodedata.normalize("NFC", prompt).split())
        labels = {" ".join(unicodedata.normalize("NFC", obj["label"]).split()) for obj in block["scene"]["objects"]}
        return sum(bool(re.search(r"(?<!\w)" + re.escape(label) + r"(?!\w)", text)) for label in labels) >= 2
    return False


def _offered(candidate):
    return candidate["kind"] == "fraction" or candidate["disclosure"] == "given"


def _fraction_prompt_pattern(candidate):
    n, d = map(int, candidate["block"]["numbers"])
    # No lookaround/conditional schema or numeric-equivalence guessing. A dot
    # or comma may end a sentence, but must not introduce a decimal suffix.
    return rf"(^|[^\w/.,+−-]){n}/{d}($|[^\w/.,]|\.(?:$|[^0-9])|,(?:$|[^0-9]))"


@dataclass(frozen=True)
class Binding:
    candidates: tuple

    @property
    def rules(self):
        return RULES

    @property
    def fixed_text(self):
        return True

    def offered(self, candidate):
        return _offered(candidate)

    def question_bound(self, candidate, question):
        return (candidate["kind"] == "fraction" and _question_anchor(candidate, question)
                and bool(re.search(_fraction_prompt_pattern(candidate), question.get("prompt", ""))))

    @property
    def context(self):
        return {"version": 1, "revision": REVISION,
                "candidates": [{key: copy.deepcopy(value) for key, value in row.items() if key != "block"}
                               for row in self.candidates if self.offered(row)]}

    def hydrate(self, data):
        """Restore only the exact requested ID; reject every scope/field mix."""
        result = copy.deepcopy(data)
        choices = {row["id"]: row for row in self.candidates if self.offered(row)}
        units = result.get("units") if isinstance(result, dict) else None
        if not isinstance(units, list) or len(units) != 1:
            raise ValueError("Ungültige Struktur der vorbereiteten Grafikzuordnung.")
        for unit in units:
            if not isinstance(unit, dict) or not isinstance(unit.get("questions"), list):
                raise ValueError("Ungültige Struktur der vorbereiteten Grafikzuordnung.")
            for item in [unit, *unit["questions"]]:
                steps = item.get("explanation_steps") if isinstance(item, dict) else None
                if not isinstance(steps, list) or len(steps) != 1 or not isinstance(steps[0], dict):
                    raise ValueError("Ungültige Struktur der vorbereiteten Grafikzuordnung.")
                for step in steps:
                    presentation = step.get("presentation")
                    if (not isinstance(presentation, dict) or set(presentation) != {"version", "evidence_kind", "blocks"}
                            or type(presentation["version"]) is not int or presentation["version"] != 1
                            or presentation["evidence_kind"] != "knowledge" or not isinstance(presentation["blocks"], list)
                            or len(presentation["blocks"]) != 1 or not isinstance(presentation["blocks"][0], str)):
                        raise ValueError("Ungültige Struktur der vorbereiteten Grafikzuordnung.")
                    selected = choices.get(presentation["blocks"][0])
                    if selected is None:
                        raise ValueError("Unbekannte vorbereitete Grafik-ID.")
                    if selected["subject"] != unit.get("subject") or selected["group_id"] != unit.get("group_id"):
                        raise ValueError("Vorbereitete Grafik gehört nicht zum Fach oder zur Paketgruppe.")
                    if step.get("disclosure") != selected["disclosure"] or (selected["disclosure"] == "given") != (item is unit):
                        raise ValueError("Vorbereitete Grafik gehört nicht zur erlaubten Aufdeckstufe.")
                    keys = ("reference", "source_refs", "text") if self.fixed_text else ("reference", "source_refs")
                    if any(_digest(step.get(key)) != _digest(selected[key]) for key in keys):
                        raise ValueError("Vorbereitete Grafikmetadaten stimmen nicht mit der Auswahl überein.")
                    if not self.fixed_text and (not isinstance(step.get("text"), str) or not step["text"].strip() or len(step["text"]) > 350):
                        raise ValueError("Ungültige Struktur der vorbereiteten Grafikzuordnung.")
                    if item is not unit and not self.question_bound(selected, item):
                        raise ValueError("Vorbereitete Grafik passt nicht zu den ausdrücklichen Frageparametern.")
                    presentation["blocks"] = [copy.deepcopy(selected["block"])]
        return result


def bind_schema(schema, payload):
    candidates = compile_candidates(payload)
    groups = payload.get("selected_groups") or []
    # Deliberately bounded first compiler: existing non-maths/legacy generation
    # keeps its original strict contract. No unsupported substitute is emitted.
    if len(groups) != 1 or groups[0].get("subject") != "Mathematik" or not any(row["kind"] == "fraction" for row in candidates):
        return None
    return bind_candidates(schema, Binding(tuple(candidates)))


def bind_candidates(schema, binding, *, question_kinds=("fraction",), prompt_pattern=_fraction_prompt_pattern, question_binding=None):
    """Reuse the strict ID/stage binder; ordinary maths retains its own policy."""
    candidates = binding.candidates
    definitions = schema["$defs"]
    step_template = copy.deepcopy(definitions["ExplanationStep"])
    presentation_template = copy.deepcopy(definitions["Presentation"])
    registered = {}

    def resolved(node):
        return copy.deepcopy(definitions[node["$ref"].rsplit("/", 1)[-1]] if "$ref" in node else node)

    def step_ref(candidate):
        step = copy.deepcopy(step_template)
        props = step["properties"]
        for key in (("text", "disclosure") if binding.fixed_text else ("disclosure",)):
            props[key] = {"type": "string", "enum": [candidate[key]]}
        if not binding.fixed_text:
            props["text"].update(minLength=1, maxLength=350)
        choice = resolved(props["reference"])
        for key in ("id", "version"):
            choice["properties"][key]["enum"] = [candidate["reference"][key]]
        props["reference"] = choice
        props["source_refs"].update(minItems=1, maxItems=1)
        props["source_refs"]["items"]["enum"] = candidate["source_refs"]
        presentation = copy.deepcopy(presentation_template)
        presentation["properties"]["version"] = {"type": "integer", "enum": [1]}
        presentation["properties"]["evidence_kind"] = {"type": "string", "enum": ["knowledge"]}
        presentation["properties"]["blocks"] = {"type": "array", "minItems": 1, "maxItems": 1,
            "items": {"type": "string", "enum": [candidate["id"]]}}
        props["presentation"] = presentation
        key = _digest(step)
        if key not in registered:
            name = "PreparedStep" + str(len(registered) + 1)
            definitions[name] = step
            registered[key] = {"$ref": "#/$defs/" + name}
        return registered[key]

    def steps(introduction, choices=None):
        choices = choices if choices is not None else [row for row in candidates if row["disclosure"] == "given"]
        branches = [step_ref(row) for row in choices]
        return {"type": "array", "minItems": 1, "maxItems": 1, "items": {"anyOf": branches}}

    # Share only the Question template. Every stage retains its own complete
    # strict step and immutable ID, with identical source/ref/parameter scope.
    question_bases = {}
    for candidate in candidates:
        if candidate["kind"] not in question_kinds or candidate["disclosure"] == "given":
            continue
        base = copy.deepcopy(candidate)
        base.pop("id")
        base.pop("disclosure")
        base["block"].pop("disclosure")
        question_bases.setdefault(_digest(base), []).append(candidate)

    def questions(node):
        node = resolved(node)
        if "anyOf" in node:
            choices = [questions(branch) for branch in node["anyOf"]]
            if question_binding is not None:
                choices = [branch for branch in choices if branch is not None]
                if not choices:
                    return None
            node["anyOf"] = choices
            return node
        branches = []
        for stage_candidates in question_bases.values():
            candidate = stage_candidates[0]
            if question_binding is not None:
                branch = question_binding(copy.deepcopy(node), candidate)
                if branch is not None:
                    branch["properties"]["explanation_steps"] = steps(False, stage_candidates)
                    branches.append(branch)
                continue
            pattern = prompt_pattern(candidate)
            prompt = node["properties"]["prompt"]
            if "pattern" in prompt and prompt["pattern"] != pattern:
                raise ValueError("Der feste Fragevertrag lässt sich nicht verlustfrei an die Grafik binden.")
            fixed = prompt.get("enum", [prompt["const"]] if "const" in prompt else [])
            if fixed and not any(isinstance(value, str) and re.search(pattern, value) for value in fixed):
                continue
            branch = copy.deepcopy(node)
            branch["properties"]["prompt"]["pattern"] = pattern
            branch["properties"]["explanation_steps"] = steps(False, stage_candidates)
            branches.append(branch)
        if not branches:
            if question_binding is not None:
                return None
            raise ValueError("Die festgelegte Frage besitzt keine passende vorbereitete Grafik mit ausdrücklichem Bruchanker.")
        return {"anyOf": branches}

    def units(node):
        node = resolved(node)
        if "anyOf" in node:
            node["anyOf"] = [units(branch) for branch in node["anyOf"]]
        else:
            node["properties"]["explanation_steps"] = steps(True)
            field = node["properties"]["questions"]
            selected = questions(field["items"])
            if selected is None:
                raise ValueError("Die festgelegte Frage besitzt keine passende vorbereitete Grafik mit ausdrücklichem Bruchanker.")
            field["items"] = selected
        return node

    schema["properties"]["units"]["items"] = units(schema["properties"]["units"]["items"])
    return binding
