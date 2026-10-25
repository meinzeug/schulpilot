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

REVISION = "package-prepared-graphics-1"
MAX_BASE_CANDIDATES = 8
STAGES = ("given", "hint1", "hint2", "hint3", "solution")
RULES = """
package-prepared-graphics-1: DIESER Auftrag verwendet ausschließlich servergeprüfte Grafiken.
prepared_graphics.candidates enthält endliche IDs mit genau gebundener Quelle, Referenz,
Stufe und Schritttext. Wähle eine zum tatsächlichen Lernziel passende ID. Im angeforderten
Wireformat ist presentation.blocks=[dieseID], NICHT ein neu abgeschriebener Graphic-Block.
Text/Referenz/source_refs/disclosure gehören unverändert zur selben ID und zum selben Fach.
Der Server stellt genau diese gespeicherte Grafik vor allen bisherigen Prüfungen wieder her.
Keine neuen Beschriftungen, Zitate, Zahlen, Grafikparameter oder Ersatzgrafiken erfinden.
Aufgaben, Antworten, Hinweise und Quellen werden weiterhin vollständig unabhängig geprüft.
FRAGEBEZUG: Eine Bruchgrafik darf nur gewählt werden, wenn derselbe Zähler UND Nenner
im Frageprompt ausdrücklich als n/d oder LaTeX-frac/dfrac stehen. Wertgleiche andere
Brüche ersetzen diese Darstellung nicht. Für eine Szene müssen mindestens zwei
verschiedene vollständige Objektbezeichnungen im Frageprompt wortgetreu vorkommen;
Teilwörter und andere Themen genügen nicht. Einführungen sind davon ausgenommen.
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


@dataclass(frozen=True)
class Binding:
    candidates: tuple

    @property
    def rules(self):
        return RULES

    @property
    def context(self):
        return {"version": 1, "revision": REVISION,
                "candidates": [{key: copy.deepcopy(value) for key, value in row.items() if key != "block"} for row in self.candidates]}

    def hydrate(self, data):
        """Restore only the exact requested ID; reject every scope/field mix."""
        result = copy.deepcopy(data)
        choices = {row["id"]: row for row in self.candidates}
        units = result.get("units") if isinstance(result, dict) else None
        if not isinstance(units, list) or len(units) != 1:
            raise ValueError("Ungültige vorbereitete Grafikzuordnung.")
        for unit in units:
            for item in [unit, *unit.get("questions", [])]:
                steps = item.get("explanation_steps")
                if not isinstance(steps, list) or len(steps) != 1:
                    raise ValueError("Ungültige vorbereitete Grafikzuordnung.")
                for step in steps:
                    presentation = step.get("presentation")
                    if (not isinstance(presentation, dict) or set(presentation) != {"version", "evidence_kind", "blocks"}
                            or type(presentation["version"]) is not int or presentation["version"] != 1
                            or presentation["evidence_kind"] != "knowledge" or not isinstance(presentation["blocks"], list)
                            or len(presentation["blocks"]) != 1 or not isinstance(presentation["blocks"][0], str)):
                        raise ValueError("Ungültige vorbereitete Grafikzuordnung.")
                    selected = choices.get(presentation["blocks"][0])
                    if (selected is None or selected["subject"] != unit.get("subject") or selected["group_id"] != unit.get("group_id")
                            or any(_digest(step.get(key)) != _digest(selected[key]) for key in ("reference", "disclosure", "source_refs", "text"))
                            or (step["disclosure"] == "given") != (item is unit)
                            or (item is not unit and not _question_anchor(selected, item))):
                        raise ValueError("Ungültige vorbereitete Grafikzuordnung.")
                    presentation["blocks"] = [copy.deepcopy(selected["block"])]
        return result


def bind_schema(schema, payload):
    candidates = compile_candidates(payload)
    groups = payload.get("selected_groups") or []
    # Deliberately bounded first compiler: existing non-maths/legacy generation
    # keeps its original strict contract. No unsupported substitute is emitted.
    if len(groups) != 1 or groups[0].get("subject") != "Mathematik" or not any(row["kind"] == "fraction" for row in candidates):
        return None
    binding = Binding(tuple(candidates))
    definitions = schema["$defs"]
    step_template = copy.deepcopy(definitions["ExplanationStep"])
    presentation_template = copy.deepcopy(definitions["Presentation"])
    registered = {}

    def resolved(node):
        return copy.deepcopy(definitions[node["$ref"].rsplit("/", 1)[-1]] if "$ref" in node else node)

    def steps(introduction):
        branches = []
        for candidate in candidates:
            if (candidate["disclosure"] == "given") != introduction:
                continue
            step = copy.deepcopy(step_template)
            props = step["properties"]
            for key in ("text", "disclosure"):
                props[key] = {"type": "string", "enum": [candidate[key]]}
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
            branches.append(registered[key])
        return {"type": "array", "minItems": 1, "maxItems": 1, "items": {"anyOf": branches}}

    def questions(node):
        node = resolved(node)
        if "anyOf" in node:
            node["anyOf"] = [questions(branch) for branch in node["anyOf"]]
        else:
            node["properties"]["explanation_steps"] = steps(False)
        return node

    def units(node):
        node = resolved(node)
        if "anyOf" in node:
            node["anyOf"] = [units(branch) for branch in node["anyOf"]]
        else:
            node["properties"]["explanation_steps"] = steps(True)
            field = node["properties"]["questions"]
            field["items"] = questions(field["items"])
        return node

    schema["properties"]["units"]["items"] = units(schema["properties"]["units"]["items"])
    return binding
