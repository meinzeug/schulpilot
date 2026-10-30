"""Source-bound, durable short plans. Attempts remain the only answer evidence.

This local recipe diagnoses one precise fraction hypothesis without an LLM.
It never replaces an existing question, answer, source or parent assignment.
New questions are appended only on a deliberate, revision-checked action.
"""

import copy
import hashlib
import math
import re
from fractions import Fraction

from fastapi import HTTPException

from .db import LearningMemory
from .schemas import Question

VERSION = "adaptive-plan-1"
CAPABILITY = "adaptive_controller_v2"
EXPRESSION = re.compile(r"(?<!\d)(\d{1,2})\s*/\s*([1-9]\d?)\s*\+\s*(\d{1,2})\s*/\s*([1-9]\d?)")


def enabled(db, unit):
    memory = db.get(LearningMemory, unit.id)
    return bool(memory and memory.working.get("controller_version") == 2)


def flow(db, unit):
    memory = db.get(LearningMemory, unit.id)
    return copy.deepcopy(memory.working.get("adaptive_flow")) if memory else None


def deferred(db, unit):
    value = flow(db, unit)
    return set(value.get("deferred_question_ids", [])) if value else set()


def current_question(db, unit):
    value = flow(db, unit)
    if value and value["phase"] in ("probe", "application", "retry"):
        return value.get("current_question_id")
    return None


def source_support(sources, db=None):
    """Do not prescribe unlike-denominator arithmetic from a same-only note."""
    from .math_tasks import unlike_quote
    from .source_lineage import learning_source

    for material in sources:
        text = learning_source(db, material)["content"]
        quote = unlike_quote([{"content": text}])
        if quote:
            return {"id": material.id, "revision": material.revision,
                "excerpt": quote}
    return None


def numbers(question):
    match = EXPRESSION.search(question["prompt"])
    if not match:
        return None
    a, b, c, d = map(int, match.groups())
    denominator = math.lcm(b, d)
    if b == d or denominator > 24 or min(a, c) <= 0 or Fraction(a, b) + Fraction(c, d) > 1:
        return None
    return a, b, c, d


def qid(unit, origin, kind):
    return "adaptive_" + hashlib.sha256((unit.id + origin + kind).encode()).hexdigest()[:24]


def question_value(value, goal_id):
    checked = Question.model_validate(value).model_dump(exclude_none=True)
    if goal_id:
        checked["learning_goal_id"] = goal_id
    return checked


def probe_question(unit, value):
    origin = next(q for q in unit.questions if q["id"] == value["origin_question_id"])
    a, b, _, d = numbers(origin)
    denominator = math.lcm(b, d)
    numerator = a * (denominator // b)
    # When the first fraction already has the common denominator, subdivide it.
    if denominator == b:
        numerator, denominator = a * 2, b * 2
    correct = f"{numerator}/{denominator}"
    options = [correct]
    for candidate in (f"{a + 1}/{b + d}", f"{a}/{denominator}", f"{a}/{b + d}", "0/1"):
        if candidate not in options and Fraction(candidate) != Fraction(a, b):
            options.append(candidate)
        if len(options) == 3:
            break
    assert sum(Fraction(item) == Fraction(a, b) for item in options) == 1
    question = question_value({"id": qid(unit, origin["id"], "equivalence"), "type": "choice",
        "prompt": f"Welcher Bruch beschreibt dieselbe Menge wie {a}/{b}?",
        "options": options, "answer": correct, "accepted": [],
        "hints": ["Die Stücke dürfen kleiner werden. Die gesamte markierte Menge muss gleich bleiben."],
        "explanation": f"{a}/{b} = {correct}. Zähler und Nenner werden mit derselben Zahl multipliziert."},
        None)
    # Recognising an equivalent value is not proof of adding fractions.
    question["controller_goal"] = {"key": "equivalent_fractions", "label": "Gleichwertige Brüche erkennen",
        "source_id": value["source"]["id"], "source_revision": value["source"]["revision"],
        "source_excerpt": value["source"]["excerpt"], "origin": "reviewed_source_bound_rule", "status": "checked"}
    return question


def application_question(db, unit, value):
    from .coaching import fraction_task_signature, root_and_units

    _, chain = root_and_units(db, unit)
    used = {fraction_task_signature(q["prompt"]) for old in chain for q in old.questions}
    origin = next(q for q in unit.questions if q["id"] == value["origin_question_id"])
    for a, b, c, d in ((1, 4, 1, 8), (2, 5, 1, 10), (1, 6, 1, 3), (1, 3, 1, 12), (1, 4, 1, 6)):
        prompt = f"Berechne {a}/{b} + {c}/{d}. Gib den vollständigen Bruch an."
        if fraction_task_signature(prompt) in used:
            continue
        denominator = math.lcm(b, d)
        left, right = a * (denominator // b), c * (denominator // d)
        result = Fraction(a, b) + Fraction(c, d)
        return question_value({"id": qid(unit, origin["id"], "application"), "type": "short", "prompt": prompt,
            "options": [], "answer": str(result), "accepted": [],
            "hints": ["Suche eine gemeinsame Einteilung. Erweitere zuerst beide Brüche."],
            "explanation": f"{a}/{b} + {c}/{d} = {left}/{denominator} + {right}/{denominator} = {result}."},
            origin.get("learning_goal_id"))
    raise HTTPException(409, "Die neuen Zahlenbeispiele sind hier aufgebraucht. Deine bisherigen Antworten bleiben gespeichert.")


def save(db, unit, value):
    memory = db.get(LearningMemory, unit.id)
    memory.working = {**memory.working, "adaptive_flow": value}


def answer_recorded(db, unit, question, attempt, sources):
    """Only derive a hypothesis from an actual wrong attempt; never a diagnosis."""
    if not enabled(db, unit) or unit.synthetic or unit.subject.casefold() not in ("mathe", "mathematik"):
        return
    value = flow(db, unit)
    if value and question["id"] == value.get("current_question_id"):
        hypothesis = value["hypothesis"]
        if value["phase"] == "offer_probe":
            hypothesis["attempt_refs"] = list(dict.fromkeys([*hypothesis["attempt_refs"], "attempt:" + attempt.id]))
            if attempt.outcome in ("correct", "uncertain"):
                hypothesis["status"] = "inconclusive"
                value["phase"] = "closed"
        elif value["phase"] == "probe":
            hypothesis["probe_attempt_refs"] = ["attempt:" + attempt.id]
            hypothesis["prerequisite"] = ("independent_correct" if attempt.outcome == "correct" and not attempt.assisted
                else "uncertain" if attempt.outcome == "uncertain" else "needs_support")
            value["phase"] = "explanation"
            value["explanation_seen"] = False
            value["deferred_question_ids"] = list(dict.fromkeys([*value["deferred_question_ids"], question["id"]]))
        elif value["phase"] in ("application", "retry"):
            hypothesis["application_attempt_refs"] = [*hypothesis.get("application_attempt_refs", []), "attempt:" + attempt.id]
            hypothesis["status"] = ("new_independent_success" if attempt.outcome == "correct" and not attempt.assisted
                else "supported_success" if attempt.outcome == "correct" else "assessment_open" if attempt.outcome == "uncertain"
                else "needs_more_support")
            exhausted = attempt.evaluation.get("attempt_number", 1) >= 3
            value["phase"] = "closed" if exhausted or attempt.outcome in ("correct", "uncertain") else "change_support"
            value["explanation_seen"] = False
        save(db, unit, value)
        return
    if value:
        # A later independent observation never rewrites the original mistake.
        return
    parts = numbers(question)
    source = source_support(sources, db)
    if not parts or not source or attempt.outcome != "incorrect":
        return
    a, b, c, d = parts
    try:
        observed = Fraction(str(attempt.answer).strip()) == Fraction(a + c, b + d)
    except (ValueError, ZeroDivisionError):
        observed = False
    if not observed:
        return
    save(db, unit, {"version": 1, "strategy_version": VERSION, "origin_question_id": question["id"],
        "learning_goal_id": question.get("learning_goal_id"), "source": source,
        "phase": "offer_probe", "current_question_id": question["id"], "deferred_question_ids": [],
        "hypothesis": {"kind": "denominators_added", "status": "unconfirmed", "attempt_refs": ["attempt:" + attempt.id],
            "observation": "In dieser falschen Antwort wurden Zähler und Nenner jeweils addiert.",
            "interpretation": "Möglicherweise ist die gemeinsame Einteilung noch unklar. Das wird erst überprüft."}})


def decision(db, unit):
    value = flow(db, unit)
    if not value or value["phase"] == "closed":
        return None
    phase = value["phase"]
    kind, title, reason = {
        "offer_probe": ("review_prerequisite", "Einen Zwischenschritt prüfen", "Eine kurze neue Frage prüft die Vermutung. Ein Fehler allein belegt keine Wissenslücke."),
        "probe": ("practice", "Gleich große Bruchteile erkennen", "Prüfe zuerst die gleiche Menge bei einer anderen Einteilung."),
        "explanation": ("visual_example", "Vergleiche die gleich großen Mengen", "Die nächste Erklärung richtet sich nach deinem gespeicherten Zwischenschritt."),
        "application": ("practice", "Probiere eine neue Rechnung", "Die neue Aufgabe zeigt, was du jetzt selbst anwenden kannst."),
        "change_support": ("visual_example", "Eine andere Erklärung hilft weiter", "Die neue Rechnung ist noch offen. Vergleiche die Bruchteile oder nutze einen anderen Lerntipp."),
        "retry": ("practice", "Probiere den Schritt noch einmal", "Dieser weitere Versuch wird als Übung mit Unterstützung gespeichert."),
    }[phase]
    return {"kind": kind, "phase": "help" if phase in ("offer_probe", "explanation", "change_support") else "practice",
        "question_id": value["current_question_id"], "learning_goal_id": value["learning_goal_id"],
        "evidence_refs": value["hypothesis"]["attempt_refs"] + value["hypothesis"].get("probe_attempt_refs", [])
            + value["hypothesis"].get("application_attempt_refs", []),
        "reason_code": "adaptive_" + phase, "reason": reason, "title": title,
        "expected_result": "Eine neue eigene Antwort auf den bestätigten Lernstoff.",
        "on_success": "check_understanding", "on_error": "visual_example", "model_needed": False}


def public_plan(db, unit):
    value = flow(db, unit)
    if not value:
        return None
    result = {k: value[k] for k in ("version", "strategy_version", "phase", "origin_question_id", "current_question_id", "learning_goal_id", "hypothesis")}
    result["steps"] = [{"kind": kind, "title": title} for kind, title in (
        ("review_prerequisite", "Zwischenschritt prüfen"), ("visual_example", "Passende Erklärung ansehen"),
        ("check_understanding", "Neue Rechnung selbst probieren"), ("schedule_review", "Später erneut abrufen"))]
    result["explanation_seen"] = bool(value.get("explanation_seen"))
    if value["phase"] in ("explanation", "change_support") and value.get("explanation_seen"):
        target_id = value["current_question_id"] if value["phase"] == "change_support" else value["origin_question_id"]
        origin = next(q for q in unit.questions if q["id"] == target_id)
        a, b, c, d = numbers(origin)
        denominator = math.lcm(b, d)
        if value["hypothesis"].get("prerequisite") == "independent_correct":
            text = "Gleichwertige Brüche hast du im Zwischenschritt erkannt. Jetzt brauchst du dieselbe Einteilung für beide Brüche. "
        else:
            text = "Die Menge bleibt gleich, wenn jedes Stück gleichmäßig unterteilt wird. Zähler und Nenner werden dabei mit derselben Zahl multipliziert. "
        text += (f"{a}/{b} = {a * (denominator // b)}/{denominator} und "
            f"{c}/{d} = {c * (denominator // d)}/{denominator}. Erst danach werden die Zähler addiert. Der gemeinsame Nenner bleibt stehen.")
        result["explanation"] = {"text": text, "prompt": origin["prompt"], "question_id": origin["id"]}
    return result


def execute(db, unit, kind):
    """Called under unit lock, after auth/CAS/source validation by the controller."""
    value = flow(db, unit)
    if not value or value["phase"] == "closed":
        return False
    if value["phase"] == "offer_probe" and kind == "practice":
        value["phase"], value["hypothesis"]["status"] = "closed", "inconclusive"
        save(db, unit, value)
        return True
    if value["phase"] in ("explanation", "change_support") and kind == "visual_example":
        from .learning import record

        target = value["current_question_id"] if value["phase"] == "change_support" else value["origin_question_id"]
        if not value.get("explanation_seen"):
            from .learning_disclosures import receipt

            value["explanation_seen"] = True
            save(db, unit, value)
            shown = public_plan(db, unit)["explanation"]
            question = next(q for q in unit.questions if q["id"] == target)
            detail = {"question_id": target, "via": "adaptive_plan"}
            if proof := receipt(question, shown["text"], adaptive=True):
                detail["arithmetic_disclosure"] = proof
            record(db, unit.child_id, "explanation", detail, unit.id)
        value["explanation_seen"] = True
        save(db, unit, value)
        return True
    if value["phase"] == "offer_probe" and kind == "review_prerequisite":
        question = probe_question(unit, value)
        value["phase"] = "probe"
        value["deferred_question_ids"] = [value["origin_question_id"]]
    elif value["phase"] == "explanation" and kind == "check_understanding":
        if not value.get("explanation_seen"):
            raise HTTPException(409, "Öffne zuerst die vorbereitete Erklärung.")
        question = application_question(db, unit, value)
        value["phase"] = "application"
    elif value["phase"] == "change_support" and kind == "practice":
        if not value.get("explanation_seen"):
            raise HTTPException(409, "Öffne zuerst die andere Erklärung oder einen passenden Lerntipp.")
        value["phase"] = "retry"
        from .learning import record

        record(db, unit.child_id, "explanation", {"question_id": value["current_question_id"], "via": "adaptive_plan_retry"}, unit.id)
        save(db, unit, value)
        return True
    else:
        return False
    if any(q["id"] == question["id"] for q in unit.questions):
        raise HTTPException(409, "Dieser Lernschritt wurde bereits vorbereitet. Bitte lade den gespeicherten Stand.")
    unit.questions = [*unit.questions, question]
    value["current_question_id"] = question["id"]
    save(db, unit, value)
    return True
