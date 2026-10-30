"""Finite disclosure receipts for different arithmetic examples.

Ordinary prose, graphics, language tasks and legacy activities remain unknown.
Receipts describe shown help, never an answer or a mastery observation.
"""
import hashlib
import json
import re
from fractions import Fraction

VERSION = "fraction-disclosure-1"
_TASK = re.compile(r"(?:Berechne|Was ergibt)\s+([0-9]{1,4})/([1-9][0-9]{0,3})\s*\+\s*([0-9]{1,4})/([1-9][0-9]{0,3})[?.]?(?: Gib den vollständigen Bruch an\.)?")
_FRACTION = re.compile(r"(?<![\w/])([0-9]{1,4})/([1-9][0-9]{0,3})(?![\w/])")


def _task(question):
    if question.get("language") or question.get("type") not in ("short", "gap", "choice"):
        return None
    match = _TASK.fullmatch(question.get("prompt", ""))
    if not match:
        return None
    a, b, c, d = map(int, match.groups())
    result = Fraction(a, b) + Fraction(c, d)
    try:
        if Fraction(question["answer"]) != result:
            return None
    except (KeyError, ValueError, TypeError, ZeroDivisionError):
        return None
    return a, b, c, d, result


def _identity(question):
    core = {key: question.get(key) for key in ("id", "type", "prompt", "answer")}
    return hashlib.sha256(json.dumps(core, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def receipt(question, text, *, adaptive=False):
    task = _task(question)
    if task is None or not isinstance(text, str):
        return None
    a, b, c, d, _ = task
    # The adaptive controller supplies its own finite explanatory template.
    # Other displayed explanations qualify only as this exact checked template
    # or a pure numeric equality chain; arbitrary model prose is not proof.
    if not adaptive:
        template = f"{a} + {c} = {a + c}. Der Nenner bleibt {b}. Das Ergebnis ist {a + c}/{b}."
        if b == d and text == template:
            pass
        else:
            expression = text.strip().removesuffix(".").replace(" ", "")
            if not re.fullmatch(r"[0-9/+=]+", expression) or "=" not in expression:
                return None
            try:
                values = [sum((Fraction(term) for term in side.split("+")), Fraction())
                          for side in expression.split("=")]
            except (ValueError, ZeroDivisionError):
                return None
            if any(value != task[-1] for value in values):
                return None
    visible = text + " " + question["prompt"]
    values = {str(Fraction(int(n), int(d))) for n, d in _FRACTION.findall(visible)}
    # Integer results, if displayed, also cannot count as fresh recall.
    values.update(str(Fraction(int(n))) for n in re.findall(r"(?<![\w/])[0-9]{1,4}(?![\w/])", visible))
    return {"version": VERSION, "question_sha256": _identity(question), "values": sorted(values)}


def independent_example(unit, question, events):
    """Rule out overlap only for every actually opened, receipted example."""
    if unit.subject.casefold() not in ("mathematik", "mathe") or (task := _task(question)) is None:
        return False
    questions = {item["id"]: item for item in unit.questions}
    relevant = [event for event in events if isinstance(event.detail, dict)
                and event.detail.get("question_id") != question["id"]]
    if not relevant:
        return False
    for event in relevant:
        data = event.detail.get("arithmetic_disclosure")
        prior = questions.get(event.detail.get("question_id"))
        if (event.kind != "explanation" or not prior or not isinstance(data, dict)
                or data.get("version") != VERSION or data.get("question_sha256") != _identity(prior)
                or not isinstance(data.get("values"), list) or not data["values"]
                or str(task[-1]) in data["values"]):
            return False
    return True
