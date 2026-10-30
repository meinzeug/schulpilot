"""A literal, source-bound spatial example; never infer a general map."""
import re

from . import package_prepared_graphics as prepared
from .subject_content import PROFILES, Graphic, canonical_profile, validate_question

REFERENCE = "geography.atlantic.between"
REVISION = "atlantic-between-1"
_SOURCE = re.compile(
    r"\b(Der\s+Atlantische\s+Ozean)\s+liegt\s+zwischen\s+(Amerika)\s+und\s+(Europa)\s*\.",
    re.IGNORECASE,
)


def bases(content):
    for match in _SOURCE.finditer(content):
        ocean, america, europe = match.groups()
        quote = match.group(0)
        labels = [america, ocean, europe]
        objects = [{"id": f"o{i}", "label": label, "shape": "box", "tone": "neutral"}
                   for i, label in enumerate(labels)]
        placements = [{"object_id": obj["id"], "slot": i} for i, obj in enumerate(objects)]
        steps = [{"caption": label, "source_excerpt": quote, "placements": placements,
                  "highlight": [f"o{index}"], "edges": []} for index, label in ((0, america), (2, europe))]
        yield {"kind": "scene", "title": ocean, "source_excerpt": quote, "labels": labels,
               "numbers": [], "connections": [], "marks": [], "unit": "", "variant": "",
               "scene": {"version": 1, "layout": "row", "objects": objects, "steps": steps,
                         "transition_ms": 0}, "text_probe": None, "lab": None}


def validate(block, sources):
    actual = block.model_dump(mode="json")
    actual.pop("disclosure")
    if not any(actual == base for base in bases(block.source_excerpt)):
        raise ValueError("Die Atlantikgrafik benötigt den unveränderten vollständigen Quellbeleg.")
    if sources is not None and not any(block.source_excerpt in source for source in sources):
        raise ValueError("Die Atlantikgrafik benötigt eine bestätigte Originalquelle.")


def compile_candidates(payload):
    groups, context = payload.get("selected_groups") or [], payload.get("visual_context") or {}
    if (payload.get("package_partition") is None or not context.get("required")
            or len(groups) != 1 or canonical_profile(groups[0].get("subject")) != "Geographie"):
        return []
    group = groups[0]["id"]
    subject = groups[0]["subject"]
    refs = [r for r in context.get("references", []) if r.get("id") == REFERENCE
            and r.get("subject") == subject and type(r.get("version")) is int and r.get("digest")]
    rows = []
    for source in context.get("sources", []):
        if (source.get("subject") != subject or source.get("group_id") != group
                or not isinstance(source.get("content"), str)):
            continue
        for base in list(bases(source["content"]))[:2]:
            for ref in refs:
                for stage in ("given", "solution"):
                    block = Graphic.model_validate({**base, "disclosure": stage})
                    validate(block, [source["content"]])
                    validate_question({"version": 1, "evidence_kind": "knowledge", "blocks": [block.model_dump()]},
                                      {"prompt": "", "type": "short", "answer": "", "accepted": []},
                                      [source["content"]], PROFILES[subject], structured=True, subject=subject)
                    row = {"subject": subject, "group_id": group,
                           "reference": {"id": REFERENCE, "version": ref["version"]}, "disclosure": stage,
                           "source_refs": [source["ref"]], "text": " ".join(base["source_excerpt"].split()),
                           "kind": "scene", "block": block.model_dump(mode="json")}
                    row["id"] = "pa_" + prepared._digest({"revision": REVISION, "plan": payload.get("package_plan_digest"),
                        "partition": payload["package_partition"], "source": source,
                        "reference_digest": ref["digest"], "candidate": row})[:24]
                    rows.append(row)
    return rows


class Binding(prepared.Binding):
    @property
    def rules(self):
        return ("\natlantic-between-1: Die vorbereitete Grafik zeigt den bestätigten Atlantischen Ozean "
                "zwischen Amerika und Europa. Verwende nur die vorgegebene Grafik-ID, Quelle und Stufe. "
                "Der Fragetext nennt den Atlantischen Ozean, verrät aber die gesuchte Antwort nicht. "
                "Erfinde keine weiteren Orte oder räumlichen Beziehungen.")

    def offered(self, candidate):
        return candidate["reference"]["id"] == REFERENCE

    def question_bound(self, candidate, question):
        prompt = question.get("prompt", "")
        if not isinstance(prompt, str):
            return False
        prompt = prompt.strip()
        single_question = re.fullmatch(r"[^.!?؟？\n]{1,299}\?", prompt)
        # An explicit setup followed by the unambiguous "which pair" is
        # still one question about the between-relation. Arbitrary unrelated
        # questions after a decorative setup must not pass.
        pair_question = re.fullmatch(
            r"(?i)[^.!?؟？\n]{1,200}\bzwischen\b[^.!?؟？\n]*\.\s*welches\s+paar\s+ist\s+es\?",
            prompt,
        )
        if not single_question and not pair_question:
            return False
        return (bool(re.search(r"(?i)\batlantisch\w*\s+ozean\b", prompt))
                and bool(re.search(r"(?i)\b(?:zwischen|anlieg\w*|grenz\w*|lieg\w*|gebiet\w*|seite\w*)\b", prompt)))


def bind_schema(schema, payload):
    candidates = compile_candidates(payload)
    if not candidates:
        return None
    return prepared.bind_candidates(schema, Binding(tuple(candidates)), question_kinds=("scene",),
        prompt_pattern=lambda _: r"^[^.!?؟？\n]{0,200}[Aa]tlantisch\w*\s+[Oo]zean")
