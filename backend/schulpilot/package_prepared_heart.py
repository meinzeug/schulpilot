"""Source-bound elementary heart-pump model, without anatomical guesses."""
import copy
import re

from . import package_prepared_graphics as prepared
from .subject_content import PROFILES, Graphic, validate_question

REFERENCE = "biology.heart.pump"
REVISION = "heart-pump-1"
_SOURCE = re.compile(r"\bDas\s+(Herz)\s+pumpt\s+(Blut)\s+durch\s+den\s+(Körper)\s*\.", re.IGNORECASE)


def bases(content):
    """Only the complete explicitly stated relation, never a negation or inference."""
    for match in _SOURCE.finditer(content):
        heart, blood, body = match.groups()
        yield {"kind": "heart_pump", "title": heart, "source_excerpt": match.group(0),
               "labels": [heart, blood, body], "numbers": [], "connections": [], "marks": [],
               "unit": "", "variant": "", "scene": None, "text_probe": None, "lab": None}


def validate(block, sources):
    actual = block.model_dump(mode="json")
    actual.pop("disclosure")
    if not any(actual == candidate for candidate in bases(block.source_excerpt)):
        raise ValueError("Das Herzschema benötigt den unveränderten belegten Zusammenhang.")
    if sources is not None and not any(block.source_excerpt in source for source in sources):
        raise ValueError("Das Herzschema benötigt eine bestätigte Originalquelle.")


def compile_candidates(payload):
    groups, context = payload.get("selected_groups") or [], payload.get("visual_context") or {}
    if (payload.get("package_partition") is None or not context.get("required") or len(groups) != 1
            or groups[0].get("subject") != "Biologie"):
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
                for stage in ("given", "solution"):
                    block = Graphic.model_validate({**base, "disclosure": stage})
                    validate(block, [source["content"]])
                    validate_question({"version": 1, "evidence_kind": "knowledge", "blocks": [block.model_dump()]},
                                      {"prompt": "", "type": "short", "answer": "", "accepted": []},
                                      [source["content"]], PROFILES["Biologie"], structured=True, subject="Biologie")
                    row = {"subject": "Biologie", "group_id": group,
                           "reference": {"id": REFERENCE, "version": ref["version"]}, "disclosure": stage,
                           "source_refs": [source["ref"]], "text": " ".join(base["source_excerpt"].split()),
                           "kind": "heart_pump", "block": block.model_dump(mode="json")}
                    row["id"] = "ph_" + prepared._digest({"revision": REVISION, "plan": payload.get("package_plan_digest"),
                        "partition": payload["package_partition"], "source": source,
                        "reference_digest": ref["digest"], "candidate": row})[:24]
                    rows.append(row)
    return rows


class Binding(prepared.Binding):
    @property
    def rules(self):
        return ("\nheart-pump-1: Die Grafik ist ein vereinfachtes Schema zum belegten Satz: "
                "Das Herz pumpt Blut durch den Körper. Keine Herzteile, vollständigen Blutkreislauf "
                "oder weiteren Angaben ergänzen. Jede Frage nennt das Herz und prüft den belegten "
                "Zusammenhang. Wähle nur dieselbe angebotene Quellen- und Aufdeckstufen-ID.")

    def offered(self, candidate):
        return candidate["reference"]["id"] == REFERENCE

    def question_bound(self, candidate, question):
        prompt = question.get("prompt", "")
        return isinstance(prompt, str) and bool(re.search(r"(?<!\w)herz(?!\w)", prompt, re.IGNORECASE))


def bind_schema(schema, payload):
    candidates = compile_candidates(payload)
    if not candidates:
        return None
    return prepared.bind_candidates(schema, Binding(tuple(candidates)), question_kinds=("heart_pump",),
                                    prompt_pattern=lambda _: r"[Hh]erz")


class UnitBinding(Binding):
    def hydrate(self, data):
        return super().hydrate({"units": [data]})["units"][0]


def bind_followup(schema, payload):
    """Keep an explicitly requested, goal-bound follow-up on the same source."""
    is_followup = payload.get("review") is True and payload.get("practice_kind") in ("repair", "check")
    is_notebook = (payload.get("function") == "unit" and bool(payload.get("notebook_practice"))
                   and not payload.get("review"))
    if (not (is_followup or is_notebook) or payload.get("required_subject") != "Biologie"
            or payload.get("selected_groups") or any(payload.get(key) for key in
                ("study_block", "homework_practice", "exam_preparation", "exam_review_practice"))):
        return None
    unit_payload = {**payload, "package_partition": 0, "selected_groups": [{"id": None, "subject": "Biologie"}]}
    candidates = compile_candidates(unit_payload)
    if not candidates:
        return None
    binding = UnitBinding(tuple(candidates))
    wrapper = {"$defs": schema["$defs"], "properties": {"units": {"items": copy.deepcopy(
        {key: value for key, value in schema.items() if key != "$defs"})}}}

    def question_binding(node, candidate):
        props, pattern = node["properties"], r"[Hh]erz"
        prompt = props["prompt"]
        if prompt.get("pattern") and prompt["pattern"] != pattern:
            return None
        if prompt.get("enum") and not all(re.search(pattern, value) for value in prompt["enum"]):
            return None
        prompt["pattern"] = pattern
        props["presentation"] = {"type": "null"}
        return node

    prepared.bind_candidates(wrapper, binding, question_kinds=("heart_pump",), question_binding=question_binding)
    body = wrapper["properties"]["units"]["items"]
    schema.clear()
    schema.update(body, **{"$defs": wrapper["$defs"]})
    return binding
