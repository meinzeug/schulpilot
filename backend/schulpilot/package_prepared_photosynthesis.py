"""A bounded, literal source-bound illustration for one explicit science relation.

This is not a general inference engine: only explicitly supported complete
source sentences qualify. No model output, photo or saved answer is rewritten.
"""
import copy
import re

from . import package_prepared_graphics as prepared
from .subject_content import PROFILES, Graphic, validate_question

REFERENCE = "biology.photosynthesis.exchange"
REVISION = "photosynthesis-exchange-3"
PROMPT_PATTERN = r"([Pp]flanzen.*(?:[Ff]oto|[Pp]hoto)synthese|(?:[Ff]oto|[Pp]hoto)synthese.*[Pp]flanzen)"
TERM = re.compile(r"\b(?:foto|photo)synthese\b", re.IGNORECASE)
_SOURCE = re.compile(
    r"\b(Pflanzen)\s+nehmen\s+(Wasser)\s+und\s+(Kohlenstoffdioxid)\s+auf\s*\.\s*"
    r"Mit\s+(Licht)\s+bilden\s+sie\s+(Zucker)\s+und\s+geben\s+(Sauerstoff)\s+ab\s*\.",
    re.IGNORECASE,
)
_SOURCE_PARTS = re.compile(
    r"\bBlätter\s+nehmen\s+(Kohlenstoffdioxid)\s+aus\s+der\s+Luft\s+auf\s*\.\s*"
    r"Die\s+Wurzeln\s+nehmen\s+(Wasser)\s+auf\s*\.\s*"
    r"Mit\s+(Licht)\s+bilden\s+(Pflanzen)\s+(Zucker)\s+und\s+geben\s+(Sauerstoff)\s+ab\s*\.",
    re.IGNORECASE,
)
_SOURCE_SPLIT = re.compile(
    r"\b(Pflanzen)\s+nehmen\s+(Wasser)\s+über\s+die\s+Wurzeln\s+auf\s*\.\s*"
    r"Die\s+Blätter\s+nehmen\s+(Kohlenstoffdioxid)\s+aus\s+der\s+Luft\s+auf\s*\.\s*"
    r"Mit\s+(Licht)\s+können\s+grüne\s+Pflanzen\s+(Zucker)\s+bilden\s*\.\s*"
    r"Dabei\s+entsteht\s+(Sauerstoff)\s*\.",
    re.IGNORECASE,
)


def bases(content):
    matches = [(match, False) for match in _SOURCE.finditer(content)]
    matches.extend((match, True) for match in _SOURCE_PARTS.finditer(content))
    matches.extend((match, False) for match in _SOURCE_SPLIT.finditer(content))
    for match, parts in sorted(matches, key=lambda row: row[0].start()):
        quote = match.group(0)
        if parts:
            carbon, water, light, plants, sugar, oxygen = match.groups()
        else:
            plants, water, carbon, light, sugar, oxygen = match.groups()
        labels = [water, carbon, sugar, oxygen]
        objects = [{"id": f"o{i}", "label": label, "shape": "box", "tone": "neutral"}
                   for i, label in enumerate(labels)]
        placements = [{"object_id": obj["id"], "slot": i} for i, obj in enumerate(objects)]
        phases = [
            {"caption": water, "source_excerpt": quote, "placements": placements,
             "highlight": ["o0", "o1"], "edges": []},
            {"caption": oxygen, "source_excerpt": quote, "placements": placements,
             "highlight": ["o2", "o3"], "edges": []},
        ]
        yield {"kind": "scene", "title": plants, "source_excerpt": quote, "labels": labels,
               "numbers": [], "connections": [], "marks": [], "unit": "", "variant": "",
               "scene": {"version": 1, "layout": "grid", "objects": objects, "steps": phases,
                         "transition_ms": 0}, "text_probe": None, "lab": None}


def validate(block, sources):
    actual = block.model_dump(mode="json")
    actual.pop("disclosure")
    if not any(actual == base for base in bases(block.source_excerpt)):
        raise ValueError("Die Fotosynthesegrafik benötigt den unveränderten vollständigen Quellbeleg.")
    if sources is not None and not any(block.source_excerpt in source for source in sources):
        raise ValueError("Die Fotosynthesegrafik benötigt eine bestätigte Originalquelle.")


def compile_candidates(payload):
    groups, context = payload.get("selected_groups") or [], payload.get("visual_context") or {}
    if (payload.get("package_partition") is None or not context.get("required")
            or len(groups) != 1 or groups[0].get("subject") != "Biologie"):
        return []
    group = groups[0]["id"]
    refs = [r for r in context.get("references", []) if r.get("id") == REFERENCE
            and r.get("subject") == "Biologie" and type(r.get("version")) is int and r.get("digest")]
    rows = []
    for source in context.get("sources", []):
        if (source.get("subject") != "Biologie" or source.get("group_id") != group
                or not isinstance(source.get("content"), str)):
            continue
        for base in list(bases(source["content"]))[:2]:
            for ref in refs:
                # The complete source includes the answers. It can be shown in
                # the introduction or an explicitly opened solution, not as an
                # incremental hint to a question.
                for stage in ("given", "solution"):
                    block = Graphic.model_validate({**base, "disclosure": stage})
                    validate(block, [source["content"]])
                    validate_question({"version": 1, "evidence_kind": "knowledge", "blocks": [block.model_dump()]},
                                      {"prompt": "", "type": "short", "answer": "", "accepted": []},
                                      [source["content"]], PROFILES["Biologie"], structured=True, subject="Biologie")
                    row = {"subject": "Biologie", "group_id": group,
                           "reference": {"id": REFERENCE, "version": ref["version"]}, "disclosure": stage,
                           "source_refs": [source["ref"]], "text": " ".join(base["source_excerpt"].split()),
                           "kind": "scene", "block": block.model_dump(mode="json"),
                           "term_in_source": bool(TERM.search(source["content"]))}
                    row["id"] = "pp_" + prepared._digest({"revision": REVISION, "plan": payload.get("package_plan_digest"),
                        "partition": payload["package_partition"], "source": source,
                        "reference_digest": ref["digest"], "candidate": row})[:24]
                    rows.append(row)
    return rows


class Binding(prepared.Binding):
    @property
    def rules(self):
        return ("\nphotosynthesis-exchange-3: Wähle eine angebotene Grafik-ID derselben Quelle und Aufdeckstufe. "
                "Die Grafik hebt die im Original ausdrücklich aufgenommenen beziehungsweise gebildeten "
                "oder abgegebenen Stoffe hervor. Keine neuen Stoffe oder Pfeile erfinden. "
                "Übernimm den mitgelieferten quellengebundenen Erklärungstext unverändert; er gilt für beide Bildzustände. "
                "Jede Frage nennt Pflanzen und prüft den belegten Zusammenhang ohne die Lösung vorwegzunehmen. "
                "Nur bei term_in_source=true darf und soll die Frage Fotosynthese nennen; "
                "sonst verwende dieses nicht eingeführte Wort nicht.")

    def offered(self, candidate):
        return candidate["reference"]["id"] == REFERENCE

    def question_bound(self, candidate, question):
        prompt = question.get("prompt", "")
        return (isinstance(prompt, str)
                and bool(re.search(r"(?<!\w)pflanzen(?!\w)", prompt, re.IGNORECASE))
                and bool(TERM.search(prompt)) == candidate["term_in_source"])


def prompt_pattern(candidate):
    return PROMPT_PATTERN if candidate["term_in_source"] else r"[Pp]flanzen"


def bind_schema(schema, payload):
    candidates = compile_candidates(payload)
    if not candidates:
        return None
    return prepared.bind_candidates(schema, Binding(tuple(candidates)), question_kinds=("scene",),
        prompt_pattern=prompt_pattern)


class UnitBinding(Binding):
    def hydrate(self, data):
        return super().hydrate({"units": [data]})["units"][0]


def bind_followup(schema, payload):
    """Bind the exact source in explicit Biology notebook or goal-bound rounds."""
    is_followup = payload.get("review") is True and payload.get("practice_kind") in ("repair", "check")
    is_notebook = (payload.get("function") == "unit" and bool(payload.get("notebook_practice"))
                   and not payload.get("review"))
    if (not (is_followup or is_notebook)
            or payload.get("required_subject") != "Biologie" or payload.get("selected_groups")
            or any(payload.get(key) for key in ("study_block", "homework_practice", "exam_preparation", "exam_review_practice"))):
        return None
    unit_payload = {**payload, "package_partition": 0,
                    "selected_groups": [{"id": None, "subject": "Biologie"}]}
    candidates = compile_candidates(unit_payload)
    if not candidates:
        return None
    binding = UnitBinding(tuple(candidates))
    wrapper = {"$defs": schema["$defs"], "properties": {"units": {"items": copy.deepcopy(
        {key: value for key, value in schema.items() if key != "$defs"})}}}

    def question_binding(node, candidate):
        props = node["properties"]
        prompt = props["prompt"]
        pattern = prompt_pattern(candidate)
        if prompt.get("pattern") and prompt["pattern"] != pattern:
            return None
        if prompt.get("enum") and not all(re.search(pattern, value) for value in prompt["enum"]):
            return None
        prompt["pattern"] = pattern
        props["presentation"] = {"type": "null"}
        return node

    prepared.bind_candidates(wrapper, binding, question_kinds=("scene",), question_binding=question_binding)
    body = wrapper["properties"]["units"]["items"]
    schema.clear()
    schema.update(body, **{"$defs": wrapper["$defs"]})
    return binding
