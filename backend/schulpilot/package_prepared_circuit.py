"""Closed/open circuit graphics from an exact, confirmed source passage."""
import re

from . import package_prepared_graphics as prepared
from .subject_content import PROFILES, Graphic, validate_question

REFERENCE = "physics.circuit.confirmed_states"
REVISION = "circuit-confirmed-1"
_SOURCE = re.compile(
    r"\bEin\s+Stromkreis\s+enthält\s+eine\s+(Batterie),\s+eine\s+(Lampe)\s+und\s+(Leitungen)\s*\.\s*"
    r"Die\s+Lampe\s+leuchtet,\s+wenn\s+der\s+Stromkreis\s+geschlossen\s+ist\s*\.\s*"
    r"Ein\s+geöffneter\s+(Schalter)\s+unterbricht\s+den\s+Stromkreis\s*\.", re.IGNORECASE,
)


def bases(content):
    for match in _SOURCE.finditer(content):
        for variant in ("closed", "open"):
            yield {"kind": "circuit", "title": "Stromkreis", "source_excerpt": match.group(0),
                   "labels": list(match.groups()), "numbers": [], "connections": [], "marks": [], "unit": "",
                   "variant": variant, "scene": None, "text_probe": None, "lab": None}


def validate(block, sources):
    actual = block.model_dump(mode="json")
    actual.pop("disclosure")
    if not any(actual == base for base in bases(block.source_excerpt)):
        raise ValueError("Die Stromkreisgrafik benötigt den vollständigen belegten Schalterzustand.")
    if sources is not None and not any(block.source_excerpt in source for source in sources):
        raise ValueError("Die Stromkreisgrafik benötigt eine bestätigte Originalquelle.")


def compile_candidates(payload):
    groups, context = payload.get("selected_groups") or [], payload.get("visual_context") or {}
    if (payload.get("package_partition") is None or not context.get("required")
            or len(groups) != 1 or groups[0].get("subject") != "Physik"):
        return []
    group = groups[0]["id"]
    refs = [r for r in context.get("references", []) if r.get("id") == REFERENCE
            and r.get("subject") == "Physik" and type(r.get("version")) is int and r.get("digest")]
    rows = []
    for source in context.get("sources", []):
        if (source.get("subject") != "Physik" or source.get("group_id") != group
                or not isinstance(source.get("content"), str)):
            continue
        for base in list(bases(source["content"]))[:2]:
            for ref in refs:
                for stage in ("given", "solution"):
                    block = Graphic.model_validate({**base, "disclosure": stage})
                    validate(block, [source["content"]])
                    validate_question({"version": 1, "evidence_kind": "knowledge", "blocks": [block.model_dump()]},
                                      {"prompt": "", "type": "short", "answer": "", "accepted": []},
                                      [source["content"]], PROFILES["Physik"], structured=True, subject="Physik")
                    row = {"subject": "Physik", "group_id": group,
                           "reference": {"id": REFERENCE, "version": ref["version"]}, "disclosure": stage,
                           "source_refs": [source["ref"]], "text": " ".join(base["source_excerpt"].split()),
                           "kind": "circuit", "block": block.model_dump(mode="json")}
                    row["id"] = "pc_" + prepared._digest({"revision": REVISION, "plan": payload.get("package_plan_digest"),
                        "partition": payload["package_partition"], "source": source,
                        "reference_digest": ref["digest"], "candidate": row})[:24]
                    rows.append(row)
    return rows


def prompt_pattern(candidate):
    state = r"[Gg]eschlossen\w*" if candidate["block"]["variant"] == "closed" else r"(?:[Gg]eöffnet\w*|[Oo]ffen\w*)"
    return r"^[^.!?؟？\n]{0,200}" + state


class Binding(prepared.Binding):
    @property
    def rules(self):
        return ("\ncircuit-confirmed-1: Wähle eine Grafik-ID derselben Quelle und Offenlegungsstufe. "
                "Fragen nennen im eigentlichen Fragesatz den gewählten offenen oder geschlossenen Zustand "
                "und prüfen diesen; keine fachfremden Fragen mit einem nachgeschobenen Grafikbezug. "
                "Gib nur die belegten Bauteile und den belegten Zusammenhang wieder.")

    def offered(self, candidate):
        return candidate["reference"]["id"] == REFERENCE

    def question_bound(self, candidate, question):
        prompt = question.get("prompt", "")
        return (isinstance(prompt, str) and bool(re.fullmatch(r"[^.!?؟？\n]{1,299}\?", prompt.strip()))
                and bool(re.search(prompt_pattern(candidate), prompt)))


def bind_schema(schema, payload):
    candidates = compile_candidates(payload)
    if not candidates:
        return None
    return prepared.bind_candidates(schema, Binding(tuple(candidates)), question_kinds=("circuit",),
                                    prompt_pattern=prompt_pattern)
