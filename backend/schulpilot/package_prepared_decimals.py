"""Finite original, verified decimal additions, never replacement calculations."""

import re
from decimal import Decimal, InvalidOperation

from . import package_prepared_graphics as prepared
from .subject_content import Graphic, validate_question

REFERENCE = "math.decimal.original_addition"
REVISION = "package-decimal-original-1"
NUMBER = r"(?:0|[1-9]\d{0,3})(?:(?:,|\{,\})\d{1,3})?"
_EXPR = rf"{NUMBER}\s*\+\s*{NUMBER}\s*=\s*{NUMBER}"
LINE = re.compile(rf"^\s*(?:Beispiel\s*:\s*)?(?:\\\((?P<math>{_EXPR})\\\)|(?P<plain>{_EXPR}))\s*$", re.I)
EQUATION = re.compile(rf"^({NUMBER})\s*\+\s*({NUMBER})\s*=\s*({NUMBER})$")
RULES = """
package-decimal-original-1: Wähle ausschließlich eine angebotene Grafik-ID. Sie zeigt
eine unveränderte, rechnerisch geprüfte Addition aus der bestätigten Seite. Frage und
Antwort sind bereits an die Grafik gebunden. Verwende die angebotene Frage und das
geprüfte Ergebnis unverändert, als kurze freie Antwort ohne Antwortvarianten.
Die Lösungsgrafik erst auf solution zeigen. Die Einführung zeigt ein belegtes Beispiel,
keine neue Zahl und keine erfundene Darstellung. Verwende den zugehörigen Erklärungstext
unverändert. Alle Quellenprüfungen bleiben aktiv.
"""


def _number(value):
    return Decimal(value.replace("{,}", ",").replace(",", "."))


def bases(content):
    for line in content.splitlines():
        match = LINE.fullmatch(line)
        if not match:
            continue
        quote = match.group("math") or match.group("plain")
        equation = EQUATION.fullmatch(quote)
        if not equation or not any("," in value for value in equation.groups()):
            continue
        a, b, result = equation.groups()
        try:
            if _number(a) + _number(b) != _number(result):
                continue
        except InvalidOperation:
            continue
        left = quote[: quote.index("=")].rstrip()
        labels = [left, result]
        objects = [
            {"id": "sum", "label": left, "shape": "box", "tone": "neutral"},
            {"id": "result", "label": result, "shape": "box", "tone": "accent"},
        ]
        placements = [{"object_id": obj["id"], "slot": i} for i, obj in enumerate(objects)]
        phases = [
            {
                "caption": labels[i],
                "source_excerpt": quote,
                "placements": placements,
                "highlight": [objects[i]["id"]],
                "edges": [],
            }
            for i in (0, 1)
        ]
        yield {
            "kind": "scene",
            "title": left,
            "source_excerpt": quote,
            "labels": labels,
            "numbers": [],
            "connections": [],
            "marks": [],
            "unit": "",
            "variant": "",
            "scene": {"version": 1, "layout": "row", "objects": objects, "steps": phases, "transition_ms": 0},
            "text_probe": None,
            "lab": None,
        }


def validate_decimal(block, *, sources=None, question=None):
    actual = block.model_dump(mode="json")
    actual.pop("disclosure")
    if not any(actual == base for base in bases(block.source_excerpt)):
        raise ValueError("Die Dezimaldarstellung benötigt eine unveränderte richtige Originaladdition.")
    if sources is not None and not any(block.source_excerpt in source for source in sources):
        raise ValueError("Die Dezimaladdition benötigt den bestätigten Originalbeleg.")
    if question is not None and not question_bound(block.source_excerpt, question):
        raise ValueError("Die Frage muss zu den Summanden und dem geprüften Ergebnis der Grafik passen.")


def question_bound(quote, question):
    equation = EQUATION.fullmatch(quote)
    if not equation or not isinstance(question.get("prompt"), str) or question.get("accepted"):
        return False
    a, b, result = (value.replace("{,}", ",") for value in equation.groups())
    if question["prompt"] != f"Wie viel ist {a} + {b}?":
        return False
    answer = question.get("answer")
    options = question.get("options") or []
    return question.get("type") == "short" and not options and answer == result


def compile_candidates(payload):
    context, groups = payload.get("visual_context") or {}, payload.get("selected_groups") or []
    if (
        payload.get("package_partition") is None
        or not context.get("required")
        or len(groups) != 1
        or groups[0].get("subject") != "Mathematik"
    ):
        return []
    group = groups[0]["id"]
    refs = [
        row
        for row in context.get("references", [])
        if row.get("id") == REFERENCE
        and row.get("subject") == "Mathematik"
        and type(row.get("version")) is int
        and row.get("digest")
    ]
    result, seen = [], set()
    for source in context.get("sources", []):
        if (
            source.get("subject") != "Mathematik"
            or source.get("group_id") != group
            or not isinstance(source.get("content"), str)
        ):
            continue
        topic_context = str(source.get("topic", "")) + "\n" + source["content"]
        if not (re.search(r"dezimal|komma", topic_context, re.I)
                and re.search(r"addier|addition|summe|zusammenz[äa]hl", topic_context, re.I)):
            continue
        for base in bases(source["content"]):
            values = EQUATION.fullmatch(base["source_excerpt"]).groups()
            identity = tuple(sorted((_number(values[0]), _number(values[1]))))
            if identity in seen or len(seen) >= 2:
                continue
            seen.add(identity)
            a, b, total = (value.replace("{,}", ",") for value in EQUATION.fullmatch(base["source_excerpt"]).groups())
            for ref in refs:
                for stage in prepared.STAGES:
                    block = Graphic.model_validate({**base, "disclosure": stage})
                    validate_decimal(block, sources=[source["content"]])
                    validate_question(
                        {"version": 1, "evidence_kind": "knowledge", "blocks": [block.model_dump()]},
                        {"prompt": "", "type": "short", "answer": "", "accepted": []},
                        [source["content"]],
                        ("scene",),
                        structured=True,
                        subject="Mathematik",
                    )
                    row = {
                        "subject": "Mathematik",
                        "group_id": group,
                        "kind": "scene",
                        "disclosure": stage,
                        "reference": {"id": REFERENCE, "version": ref["version"]},
                        "source_refs": [source["ref"]],
                        "text": f"Schreibe {a} und {b} so untereinander, dass die Kommas genau untereinander stehen. "
                                f"Addiere die Ziffern stellenweise. Zusammen ergibt das {total}.",
                        "block": block.model_dump(mode="json"),
                    }
                    row["id"] = (
                        "pd_"
                        + prepared._digest(
                            {
                                "revision": REVISION,
                                "source": source,
                                "candidate": row,
                                "reference_digest": ref["digest"],
                                "plan": payload.get("package_plan_digest"),
                                "partition": payload["package_partition"],
                            }
                        )[:24]
                    )
                    result.append(row)
    return result if len(seen) >= 2 else []


class Binding(prepared.Binding):
    @property
    def rules(self):
        return RULES

    def offered(self, candidate):
        return candidate["reference"]["id"] == REFERENCE

    def question_bound(self, candidate, question):
        return question_bound(candidate["block"]["source_excerpt"], question)

    def hydrate(self, data):
        result = super().hydrate(data)
        questions = result["units"][0]["questions"]
        prompts = [question.get("prompt") for question in questions]
        if len(set(prompts)) != len(prompts):
            raise ValueError("Eine Teilrunde darf dieselbe Originaladdition nicht mehrfach fragen.")
        return result

    @property
    def context(self):
        value = super().context
        for row, candidate in zip(value["candidates"], self.candidates, strict=True):
            equation = candidate["block"]["source_excerpt"].replace("{,}", ",")
            row["original_equation"] = equation
            a, b, total = EQUATION.fullmatch(equation).groups()
            row["original_question"], row["original_answer"] = f"Wie viel ist {a} + {b}?", total
        return {**value, "revision": REVISION}


def bind_schema(schema, payload):
    candidates = compile_candidates(payload)
    if not candidates:
        return None

    def bind_question(node, candidate):
        match = EQUATION.fullmatch(candidate["block"]["source_excerpt"])
        a, b, result = (value.replace("{,}", ",") for value in match.groups())
        props = node["properties"]
        exact = f"Wie viel ist {a} + {b}?"
        prompt = props["prompt"]
        if prompt.get("pattern") and not re.search(prompt["pattern"], exact):
            return None
        fixed = prompt.get("enum", [prompt["const"]] if "const" in prompt else [])
        if fixed and exact not in fixed:
            return None
        if props["type"].get("enum") and "short" not in props["type"]["enum"]:
            return None
        if props["answer"].get("type") != "string":
            return None
        existing = props["answer"].get("enum")
        if existing and result not in existing:
            return None
        prompt["enum"] = [exact]
        props["type"] = {"type": "string", "enum": ["short"]}
        props["answer"]["enum"] = [result]
        props["options"].update(maxItems=0)
        props["accepted"].update(maxItems=0)
        return node

    return prepared.bind_candidates(
        schema, Binding(tuple(candidates)), question_kinds=("scene",), question_binding=bind_question
    )
