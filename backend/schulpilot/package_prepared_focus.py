"""Literal list reading focus for two explicitly supported source subjects.

A finite options slot is part of the requested wire contract. Hydration restores
that exact original list before the ordinary Choice decoder; no answer repair.
"""
import copy
import re
import unicodedata

from . import package_prepared_graphics as prepared
from .subject_content import PROFILES, Graphic, validate_question

REFERENCE = "general.original_evidence.focused_list"
SENTENCE_REFERENCE = "general.original_evidence.focused_sentences"
REVISION = "package-original-focus-1"
SUBJECTS = ("Deutsch", "Geschichte")
_LIST = re.compile(r"^[ \t]*(?:[0-9]{1,3}[.)]|\([0-9]{1,3}\)|[-*•])[ \t]+(.+?)[ \t]*$")
RULES = """
package-original-focus-1: Die angebotenen Szenen zeigen ausschließlich vollständige
Originaleinträge einer Liste oder vollständige Originalsätze. Die zwei Hervorhebungen sind bewusste Lesefokusse,
KEINE zeitliche oder kausale Folge; keine Pfeile oder Grammatikurteile ergänzen.
Fragen sind type=choice. options ist im angeforderten Wireformat der eine angebotene
options_slot-String; der Server stellt daraus unverändert die zugehörigen original_options
in genau deren Reihenfolge her. answer folgt dem finalen Schema: bei Integer der strenge
nullbasierte Index in original_options, sonst der genaue Originaloptionstext. Alle Optionen
sind Originale: frage nach belegter Bedeutung, Zusammenhang oder Verständnis, NICHT welche
Schreibweise generell richtig/falsch sei oder welche Listennummer/alte Markierung vorliegt.
Nenne die richtige vollständige Option nicht bereits im Frageprompt. Gib nötigen Kontext,
ohne neue Tatsachen einzuführen. Die Grafik öffnet nur über ihre gebundene Hilfestufe.
Schreibe explanation_steps.text verständlich nach explanation-guidance-1, maximal350Zeichen.
Die sichtbaren Originalbeschriftungen/Quellen/Referenz/Stufe bleiben unverändert.
"""


def _normal(text):
    return " ".join(unicodedata.normalize("NFC", text).split())


def _mentions(text, label):
    return bool(re.search(r"(?<!\w)" + re.escape(_normal(label).casefold()) + r"(?!\w)", _normal(text).casefold()))


def focus_bases(content):
    """Whole consecutive list items only; never segments, prose or inferred edges."""
    run = []
    lines = content.splitlines(keepends=True)
    offset = 0
    runs = []
    for line in lines:
        match = _LIST.fullmatch(line.rstrip("\r\n"))
        if match and 1 <= len(match[1]) <= 160:
            run.append((offset, offset + len(line.rstrip("\r\n")), match[1]))
        elif line.strip():
            if run:
                runs.append(run)
            run = []
        offset += len(line)
    if run:
        runs.append(run)
    for run in runs:
        for start in range(len(run) - 1):
            for size in range(min(4, len(run) - start), 1, -1):
                selected = run[start:start + size]
                labels = [row[2] for row in selected]
                quote = content[selected[0][0]:selected[-1][1]]
                if len(quote) > 500 or len(set(map(_normal, labels))) != size:
                    continue
                # A short literal title is a caption, never a shortened item.
                title = labels[0] if len(labels[0]) <= 100 else labels[0].split()[0]
                if len(title) > 100:
                    continue
                objects = [{"id": f"o{i}", "label": label, "shape": "box", "tone": "neutral"}
                           for i, label in enumerate(labels)]
                placements = [{"object_id": row["id"], "slot": i} for i, row in enumerate(objects)]
                phases = [{"caption": labels[i], "source_excerpt": quote, "placements": placements,
                           "highlight": [objects[i]["id"]], "edges": []} for i in (0, 1)]
                yield {"kind": "scene", "title": title, "source_excerpt": quote, "labels": labels,
                    "numbers": [], "connections": [], "marks": [], "unit": "", "variant": "",
                    "scene": {"version": 1, "layout": "grid", "objects": objects, "steps": phases, "transition_ms": 0},
                    "text_probe": None, "lab": None}
                break


def sentence_bases(content):
    """Whole source sentences, including OCR line wraps within a paragraph."""
    runs, current, offset = [], [], 0
    pending, start = [], None
    for line in content.splitlines(keepends=True):
        text = line.rstrip("\r\n")
        stripped = text.strip()
        if not stripped:
            # Blank space can separate complete sentences, but never join an
            # unfinished heading or partial sentence to the next paragraph.
            if pending and current:
                runs.append(current)
                current = []
            pending, start = [], None
        elif _LIST.fullmatch(text) or (not pending and ":" in stripped and not re.search(r"[.!?]$", stripped)):
            if current:
                runs.append(current)
            current = []
            pending, start = [], None
        else:
            if start is None:
                start = offset + len(text) - len(text.lstrip())
            pending.append(stripped)
            sentence = " ".join(pending)
            if re.search(r"[.!?]$", stripped):
                if 15 <= len(sentence) <= 160 and not re.search(r"[.!?]\s+\S", sentence):
                    current.append((start, offset + len(text.rstrip()), sentence))
                else:
                    if current:
                        runs.append(current)
                    current = []
                pending, start = [], None
            elif len(sentence) > 160:
                if current:
                    runs.append(current)
                current, pending, start = [], [], None
        offset += len(line)
    if current:
        runs.append(current)
    for run in runs:
        for start in range(len(run) - 1):
            selected = run[start:start + min(4, len(run) - start)]
            labels = [row[2] for row in selected]
            quote = content[selected[0][0]:selected[-1][1]]
            if len(quote) > 500 or len(set(map(_normal, labels))) != len(labels):
                continue
            title = labels[0] if len(labels[0]) <= 100 else labels[0].split()[0]
            objects = [{"id": f"o{i}", "label": label, "shape": "box", "tone": "neutral"}
                       for i, label in enumerate(labels)]
            placements = [{"object_id": row["id"], "slot": i} for i, row in enumerate(objects)]
            phases = [{"caption": labels[i], "source_excerpt": quote, "placements": placements,
                       "highlight": [objects[i]["id"]], "edges": []} for i in (0, 1)]
            yield {"kind": "scene", "title": title, "source_excerpt": quote, "labels": labels,
                "numbers": [], "connections": [], "marks": [], "unit": "", "variant": "",
                "scene": {"version": 1, "layout": "grid", "objects": objects, "steps": phases, "transition_ms": 0},
                "text_probe": None, "lab": None}


def validate_focus(block, *, sources=None, question=None, sentences=False):
    """New-reference-only exact compilation proof; old scenes still need edges."""
    actual = block.model_dump(mode="json")
    actual.pop("disclosure")
    bases = sentence_bases if sentences else focus_bases
    if not any(actual == base for base in bases(block.source_excerpt)):
        raise ValueError("Der Originalfokus benötigt eine unveränderte vollständige Original-Liste ohne erfundene Beziehungen.")
    if sources is not None and not any(block.source_excerpt in source for source in sources):
        raise ValueError("Der Originalfokus benötigt den exakt bestätigten Quellenbeleg.")
    if question is not None:
        labels = block.labels
        if (question.get("type") != "choice" or question.get("options") != labels
                or not isinstance(question.get("answer"), str) or question["answer"] not in labels
                or _mentions(question.get("prompt", ""), question["answer"])):
            raise ValueError("Die Originalfokus-Frage benötigt dieselben Originaloptionen ohne Antwort im Prompt.")


def compile_candidates(payload):
    context, groups = payload.get("visual_context") or {}, payload.get("selected_groups") or []
    if payload.get("package_partition") is None or not context.get("required") or len(groups) != 1:
        return []
    subject, group = groups[0].get("subject"), groups[0].get("id")
    if subject not in SUBJECTS:
        return []
    references = [row for row in context.get("references", []) if row.get("id") in (REFERENCE, SENTENCE_REFERENCE)
                  and row.get("subject") == subject and type(row.get("version")) is int and row.get("digest")]
    result, bases = [], set()
    for source in context.get("sources", []):
        if source.get("subject") != subject or source.get("group_id") != group or not isinstance(source.get("content"), str):
            continue
        source_bases = [(REFERENCE, base) for base in focus_bases(source["content"])]
        source_bases += [(SENTENCE_REFERENCE, base) for base in sentence_bases(source["content"])]
        for reference_id, base in source_bases:
            identity = prepared._digest({"base": base, "source": source})
            if identity in bases or len(bases) >= 4:
                continue
            added = False
            for reference in references:
                if reference["id"] != reference_id:
                    continue
                for stage in prepared.STAGES:
                    try:
                        block = Graphic.model_validate({**base, "disclosure": stage})
                        validate_focus(block, sources=[source["content"]], sentences=reference_id == SENTENCE_REFERENCE)
                        validate_question({"version": 1, "evidence_kind": "knowledge", "blocks": [block.model_dump()]},
                            {"prompt": "", "type": "short", "answer": "", "accepted": []},
                            [source["content"]], PROFILES[subject], structured=True, subject=subject)
                    except ValueError:
                        continue
                    row = {"subject": subject, "group_id": group,
                        "reference": {"id": reference["id"], "version": reference["version"]}, "disclosure": stage,
                        "source_refs": [source["ref"]], "text": "Vergleiche die vollständig belegten Originaleinträge.",
                        "kind": "scene", "block": block.model_dump(mode="json")}
                    row["id"] = "pf_" + prepared._digest({"revision": REVISION, "plan": payload.get("package_plan_digest"),
                        "partition": payload["package_partition"], "source": source,
                        "reference_digest": reference["digest"], "candidate": row})[:24]
                    result.append(row)
                    added = True
            if added:
                bases.add(identity)
    return result


def options_slot(candidate):
    return "original_" + prepared._digest(candidate["block"]["labels"])[:24]


class Binding(prepared.Binding):
    @property
    def fixed_text(self):
        return False

    @property
    def rules(self):
        return RULES

    def offered(self, candidate):
        return candidate["reference"]["id"] in (REFERENCE, SENTENCE_REFERENCE)

    @property
    def context(self):
        value = super().context
        for row, candidate in zip(value["candidates"], self.candidates, strict=True):
            row["source_caption"] = row.pop("text")
            row["options_slot"] = options_slot(candidate)
            row["original_options"] = list(candidate["block"]["labels"])
        return {**value, "revision": REVISION}

    def question_bound(self, candidate, question):
        labels, answer = candidate["block"]["labels"], question.get("answer")
        if type(answer) is int:
            if not 0 <= answer < len(labels):
                return False
            answer = labels[answer]
        return (question.get("type") == "choice" and question.get("options") == labels
                and question.get("accepted") == [] and isinstance(answer, str) and answer in labels
                and not _mentions(question.get("prompt", ""), answer))

    def hydrate(self, data):
        value = copy.deepcopy(data)
        candidates = {row["id"]: row for row in self.candidates}
        units = value.get("units") if isinstance(value, dict) else None
        if not isinstance(units, list):
            return super().hydrate(value)
        for unit in units:
            questions = unit.get("questions") if isinstance(unit, dict) else None
            if not isinstance(questions, list):
                return super().hydrate(value)
            for question in questions:
                steps = question.get("explanation_steps") if isinstance(question, dict) else None
                if not isinstance(steps, list) or len(steps) != 1 or not isinstance(steps[0], dict):
                    continue  # The shared strict structure guard supplies the closed error.
                presentation = steps[0].get("presentation")
                ids = presentation.get("blocks") if isinstance(presentation, dict) else None
                candidate = candidates.get(ids[0]) if isinstance(ids, list) and len(ids) == 1 and isinstance(ids[0], str) else None
                if candidate is None:
                    continue
                if question.get("options") != options_slot(candidate):
                    raise ValueError("Vorbereitete Grafikmetadaten stimmen nicht mit der Auswahl überein.")
                question["options"] = list(candidate["block"]["labels"])
        return super().hydrate(value)


def _question_schema(branch, candidate):
    props = branch["properties"]
    if "choice" not in props["type"].get("enum", []):
        return None
    # Do not replace an existing server-fixed probe with a different question.
    if props["prompt"].get("enum") or "const" in props["prompt"] or props["options"].get("enum"):
        return None
    labels = candidate["block"]["labels"]
    props["type"] = {"type": "string", "enum": ["choice"]}
    props["options"] = {"type": "string", "enum": [options_slot(candidate)]}
    if props["answer"].get("type") == "integer":
        props["answer"] = {"type": "integer", "enum": list(range(len(labels)))}
    elif props["answer"].get("type") == "string":
        props["answer"] = {"type": "string", "enum": labels}
    else:
        return None
    props["accepted"].update(maxItems=0)
    props["field_group"] = {"type": "null"}
    return branch


def bind_schema(schema, payload):
    candidates = compile_candidates(payload)
    if not candidates:
        return None
    return prepared.bind_candidates(schema, Binding(tuple(candidates)), question_kinds=("scene",), question_binding=_question_schema)
