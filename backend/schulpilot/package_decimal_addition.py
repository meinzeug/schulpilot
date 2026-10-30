"""Exact decimal practice, planned before generation from an explicit source rule.

The photographed worked example is an introduction, never an independent task.
Only the immutable column-addition recipe may derive fresh sums from that rule.
"""
import copy
import re
from decimal import Decimal

from . import package_prepared_graphics as prepared

REFERENCE = "math.decimal.column_sum"
REVISION = "decimal-column-sum-1"
KIND = "decimal_sum"
HISTORY = "decimal_addition_history"
_NUMBER = r"[0-9]{1,2}(?:(?:[,.]|\{,\})[0-9]{1,2})?"
_SUM = re.compile(r"(?<![\w.,/−-])(" + _NUMBER + r")\s*\+\s*(" + _NUMBER + r")\s*=\s*(" + _NUMBER + r")(?![\w.,/])")
_PAIR = re.compile(r"(?<![\w.,/−-])(" + _NUMBER + r")\s*\+\s*(" + _NUMBER + r")(?![\w.,/])")
_RULE = re.compile(r"(?m)^[ \t]*(?:Kommas? untereinander schreiben|Komma unter Komma schreiben)[.!]?[ \t]*$", re.I)
_PROMPT = re.compile(r"^Wie viel ist (" + _NUMBER + r") \+ (" + _NUMBER + r")\?$")


def number(text):
    return Decimal(text.replace("{,}", ".").replace(",", "."))


def written(value):
    return format(value, "f").replace(".", ",")


def signature(left, right):
    return sorted([str(left.normalize()), str(right.normalize())])


def evidence(content):
    """Require an exact positive rule line and an adjacent correct worked sum.

    LaTeX decimal commas are accepted as notation, never rewritten in the quote.
    Restrict this first recipe to addition without carrying; a new method is not
    inferred from an arbitrary equation or a title alone.
    """
    for rule in _RULE.finditer(content):
        for match in _SUM.finditer(content, rule.end(), min(len(content), rule.end() + 300)):
            if re.search(r"[+−-]\s*$", content[:match.start()]):
                continue
            left, right, total = map(number, match.groups())
            places = max(-left.as_tuple().exponent, -right.as_tuple().exponent)
            scale = 10 ** places
            a, b = int(left * scale), int(right * scale)
            if (left + right != total or not 0 < a < 1000 or not 0 < b < 1000
                    or not 1 <= places <= 2 or a + b >= 10 * scale
                    or any((a // 10**i) % 10 + (b // 10**i) % 10 >= 10 for i in range(4))):
                continue
            quote = content[rule.start():match.end()].strip()
            if len(quote) <= 500:
                return {"quote": quote, "numbers": [a, b, places]}
    return None


def original_pairs(contents):
    return [signature(number(m[1]), number(m[2])) for content in contents for m in _PAIR.finditer(content)]


def history(db, child_id):
    """Numeric exclusions from own tasks/material, never saved child answers."""
    from sqlalchemy import select

    from .db import LearningUnit, Material
    from .grades import subject_key

    found = set()
    for subject, questions in db.execute(select(LearningUnit.subject, LearningUnit.questions).where(LearningUnit.child_id == child_id)):
        if subject_key(subject) != "mathematik":
            continue
        for question in questions:
            for match in _PAIR.finditer(question.get("prompt", "")):
                found.add(tuple(signature(number(match[1]), number(match[2]))))
    for subject, content in db.execute(select(Material.subject, Material.content).where(
            Material.child_id == child_id, Material.confirmed.is_(True))):
        if subject_key(subject) == "mathematik":
            found.update(tuple(pair) for pair in original_pairs([content]))
    return [list(value) for value in sorted(found)]


def inputs(places):
    # Finite, no carrying, same decimal precision and modest whole part. Each
    # commutative pair occurs once. Exhaustion never repeats an old example.
    for a in range(11, 90):
        for b in range(a + 1, 90):
            if any((a // 10**i) % 10 + (b // 10**i) % 10 >= 10 for i in range(3)):
                continue
            if places == 2 and (a % 10 == 0 or b % 10 == 0):
                continue
            yield [a, b, places]


def core(numbers):
    a, b, places = numbers
    scale = Decimal(10) ** places
    left, right = Decimal(a) / scale, Decimal(b) / scale
    return {"type": "short", "prompt": f"Wie viel ist {written(left)} + {written(right)}?",
            "answer": written(left + right), "options": [], "accepted": []}


def block(numbers, quote, stage):
    return {"kind": KIND, "title": "Komma unter Komma", "disclosure": stage,
            "source_excerpt": quote, "numbers": numbers, "labels": [], "connections": [], "marks": [],
            "unit": "", "variant": "", "scene": None, "text_probe": None, "lab": None}


def validate(graphic, sources, question=None):
    """Prove the local arithmetic and rule; no generic source relaxation."""
    raw = graphic.model_dump(mode="json")
    numbers = graphic.numbers
    if (len(numbers) != 3 or any(x != int(x) for x in numbers)
            or int(numbers[2]) not in (1, 2)):
        raise ValueError("Ungültige Stellenwertparameter.")
    numbers = list(map(int, numbers))
    if raw != block(numbers, graphic.source_excerpt, graphic.disclosure):
        raise ValueError("Die Stellenwertgrafik enthält fremde Parameter.")
    proof = evidence(graphic.source_excerpt)
    if proof is None or proof["quote"] != graphic.source_excerpt or not any(graphic.source_excerpt in text for text in sources or []):
        raise ValueError("Die Stellenwertgrafik benötigt eine bestätigte Regel mit richtigem Originalbeispiel.")
    if question and question.get("prompt"):
        if (graphic.disclosure != "solution" or numbers not in list(inputs(proof["numbers"][2]))
                or not all(question.get(k) == v for k, v in core(numbers).items())
                or signature(Decimal(numbers[0]) / 10**numbers[2], Decimal(numbers[1]) / 10**numbers[2]) in original_pairs(sources)):
            raise ValueError("Neue Dezimalaufgabe, Lösung und Grafik stimmen nicht überein.")
    elif numbers != proof["numbers"] or graphic.disclosure != "given":
        raise ValueError("Die Einführung muss das tatsächliche Originalbeispiel zeigen.")


def compile_candidates(payload, *, count=2, slots=None):
    groups, context = payload.get("selected_groups") or [], payload.get("visual_context") or {}
    if (type(payload.get("package_partition")) is not int or not context.get("required")
            or len(groups) != 1 or groups[0].get("subject") != "Mathematik"):
        return []
    references = [r for r in context.get("references", []) if r.get("id") == REFERENCE
        and r.get("version") == 1 and r.get("digest") and r.get("subject") == "Mathematik"]
    sources = [s for s in context.get("sources", []) if s.get("subject") == "Mathematik"
        and s.get("group_id") == groups[0].get("id") and s.get("source_type") != "curated_foundation"]
    from .learning_entry import _specs

    plan = next((p for p in (payload.get("learning_entry") or {}).get("units", [])
                 if p.get("subject") == "Mathematik" and p.get("group_id") == groups[0].get("id")), None)
    slots = slots or (_specs(plan, count) if plan and plan["entry_mode"] != "existing_contract" else [{"id": f"q{i + 1}"} for i in range(count)])
    foundations = [r for r in prepared.compile_candidates(payload) if r.get("question_core") and r["disclosure"] == "solution"]
    contents = [s["content"] for s in sources]
    excluded = original_pairs(contents + payload.get("previous_prompts", [])) + payload.get(HISTORY, [])
    for source in sources:
        proof = evidence(source["content"])
        if not proof:
            continue
        fresh = [n for n in inputs(proof["numbers"][2]) if signature(Decimal(n[0]) / 10**n[2], Decimal(n[1]) / 10**n[2]) not in excluded]
        if len(fresh) < count:
            raise ValueError("Für diese Regel sind alle vorbereiteten neuen Zahlenpaare bereits geübt.")
        # Stable source/plan-specific starting point, not always the same pair
        # for every child/upload. History is still the authoritative exclusion.
        offset = int(prepared._digest({"source": source, "plan": payload.get("package_plan_digest")})[:8], 16) % len(fresh)
        ordered = fresh[offset:] + fresh[:offset]
        fresh = []
        for candidate in ordered:
            if all(not set(candidate[:2]) & set(n[:2]) and sum(candidate[:2]) != sum(n[:2]) for n in fresh):
                fresh.append(candidate)
                if len(fresh) == count:
                    break
        if len(fresh) != count:
            raise ValueError("Für diese Regel fehlen ausreichend verschiedene neue Zahlenpaare.")
        result = []
        for ref in references:
            for index, numbers in enumerate([proof["numbers"], *fresh]):
                stage = "given" if index == 0 else "solution"
                task = core(numbers)
                text = (f"Schreibe die Kommas untereinander. Addiere zuerst die Nachkommastellen, dann die Einer. "
                        f"So wird {task['prompt'][13:-1]} = {task['answer']}. Die Grafik zeigt dir die passenden Spalten.")
                row = {"subject": "Mathematik", "group_id": groups[0]["id"], "kind": KIND,
                       "reference": {"id": REFERENCE, "version": ref["version"]}, "source_refs": [source["ref"]],
                       "disclosure": stage, "text": text, "block": block(numbers, proof["quote"], stage)}
                if index:
                    slot = slots[index - 1]
                    if slot.get("type"):
                        fixed = next((r for r in foundations if r["question_core"]["id"] == slot["id"]), None)
                        if fixed is None:
                            return []  # Leave unsupported fixed diagnostics with their established compiler.
                        result.append(fixed)
                        continue
                    row["question_core"] = {"id": slot["id"], **task, **({"learning_goal_id": slot["learning_goal_id"]} if slot.get("learning_goal_id") else {})}
                row["id"] = "pd_" + prepared._digest({"revision": REVISION, "source": source, "candidate": row,
                    "plan": payload.get("package_plan_digest"), "partition": payload["package_partition"], "reference": ref["digest"]})[:24]
                result.append(row)
        if result:
            return result
    return []


class Binding(prepared.Binding):
    @property
    def rules(self):
        return ("\ndecimal-column-sum-1: Einführung zeigt das Originalbeispiel. Die geplanten Aufgaben "
                "verwenden die festen question_core-Felder und jeweils dieselbe zugehörige solution-Grafik-ID. "
                "Jede geplante Aufgaben-ID genau einmal. Eine feste Vorwissensfrage bleibt unverändert mit ihrer eigenen Grafik. Keine eigenen Zahlen/Antwortvarianten ergänzen. "
                "Hinweise erklären das Untereinanderschreiben der Kommas, ohne die Lösung zu verraten. "
                "Erklärungstext und Grafiken sind vollständig vorab geprüft; unverändert übernehmen.")

    def offered(self, candidate):
        return True

    def hydrate(self, data):
        value = super().hydrate(data)
        questions = value["units"][0]["questions"]
        expected_ids = {r["question_core"]["id"] for r in self.candidates if r.get("question_core")}
        if (len(questions) != len(expected_ids) or {q["id"] for q in questions} != expected_ids
                or len({q["prompt"] for q in questions}) != len(questions)):
            raise ValueError("Die geplanten Aufgaben müssen vollständig und verschieden sein.")
        for question in value["units"][0]["questions"]:
            if question["explanation"] != question["explanation_steps"][0]["text"]:
                raise ValueError("Dezimalaufgabe und Erklärung müssen dieselbe geprüfte Rechnung verwenden.")
        return value


def question_binding(node, candidate):
    props = node["properties"]
    for key, value in candidate["question_core"].items():
        old = props[key]
        if ("enum" in old and value not in old["enum"]) or ("const" in old and value != old["const"]):
            return None  # Never overwrite an existing fixed prerequisite.
        props[key] = {"type": "array", "items": {"type": "string"}, "minItems": 0, "maxItems": 0} if isinstance(value, list) else {"type": "string", "enum": [value]}
    props["explanation"] = {"type": "string", "enum": [candidate["text"]]}
    props["presentation"] = {"type": "null"}
    if "field_group" in props:
        props["field_group"] = {"type": "null"}
    return node


def bind_schema(schema, payload):
    candidates = compile_candidates(payload)
    if not candidates:
        return None

    return prepared.bind_candidates(schema, Binding(tuple(candidates)), question_kinds=(KIND, "fraction"), question_binding=question_binding)


def validate_history(db, child_id, data):
    if not any(step.get("reference", {}).get("id") == REFERENCE
            for unit in data.get("units", []) for question in unit.get("questions", [])
            for step in (question.get("explanation_steps") or [])):
        return
    previous = history(db, child_id)
    for unit in data.get("units", []):
        for question in unit.get("questions", []):
            if not any(step.get("reference", {}).get("id") == REFERENCE for step in (question.get("explanation_steps") or [])):
                continue
            match = _PROMPT.fullmatch(question.get("prompt", ""))
            if not match or signature(number(match[1]), number(match[2])) in previous:
                raise ValueError("Diese Zahlenaufgabe wurde zwischenzeitlich schon vorbereitet. Bitte erneut eine neue Runde anfordern.")


class UnitBinding(Binding):
    def hydrate(self, data):
        return super().hydrate({"units": [data]})["units"][0]


def bind_unit(schema, payload):
    """Same proved method for a consciously requested subsequent round.

    Preserve exact requested cardinality, diagnostic cores and goal identities;
    never relabel another fixed task or an exam/homework request as addition.
    """
    if payload.get("selected_groups") or any(payload.get(k) for k in (
            "homework_practice", "exam_preparation", "exam_review_practice")):
        return None
    if not any(r.get("id") == REFERENCE for r in (payload.get("visual_context") or {}).get("references", [])):
        return None
    requested = (payload.get("study_block") or {}).get("question_count")
    from .notebook_practice import requested_count

    count = requested_count(payload) or requested or 2
    if type(count) is not int or not 2 <= count <= 5:
        return None
    slots = payload.get("practice_tasks")
    if slots:
        goals = {g["id"]: g for g in payload.get("learning_goals", [])}
        if len(slots) != count or any(not re.search(r"dezimal", goals.get(s["learning_goal_id"], {}).get("label", ""), re.I)
                or not re.search(r"add|sum", goals.get(s["learning_goal_id"], {}).get("label", ""), re.I) for s in slots):
            return None
    value = {**payload, "package_partition": 0, "selected_groups": [{"id": None, "subject": "Mathematik"}]}
    rows = compile_candidates(value, count=count, slots=slots)
    if not rows:
        return None
    binding = UnitBinding(tuple(rows))
    wrapper = {"$defs": schema["$defs"], "properties": {"units": {"items": copy.deepcopy(
        {key: val for key, val in schema.items() if key != "$defs"})}}}
    prepared.bind_candidates(wrapper, binding, question_kinds=(KIND, "fraction"), question_binding=question_binding)
    body = wrapper["properties"]["units"]["items"]
    schema.clear()
    schema.update(body, **{"$defs": wrapper["$defs"]})
    return binding
