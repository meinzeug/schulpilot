"""Versioned, conservative subject rules. Model opinions are not verdicts.

Content and a requested representation are separate dimensions. Only a
recognised mathematical question or an explicit closed concept is expanded;
unknown prose stays uncertain rather than being accepted by similarity.
"""

import re
import unicodedata
from fractions import Fraction
from math import gcd

from .checks import expanded_fraction, fraction_instruction, fraction_parts, fraction_result

VERSION = "subject_rules_v3"


def fraction_addition_hint(question, answer):
    """Recognize a denominator-sum mistake, without showing the full solution."""
    if question.get("language") or re.search(r"zähler|nenner|faktor|teiler", question["prompt"], re.I):
        return []
    expression = re.search(r"(\d{1,3})\s*/\s*([1-9]\d{0,2})\s*\+\s*(\d{1,3})\s*/\s*([1-9]\d{0,2})", question["prompt"])
    supplied, key = fraction_parts(answer), fraction_parts(question["answer"])
    if not expression or not supplied or not key:
        return []
    a, b, c, d = map(int, expression.groups())
    total = Fraction(a, b) + Fraction(c, d)
    if total != Fraction(*key) or total == Fraction(*supplied) or supplied[1] != b + d:
        return []
    denominator = b * d // gcd(b, d)
    return [
        f"Der Nenner {b + d} entsteht aus {b} + {d}. Beim Addieren zählst du die Nenner nicht zusammen. Teile beide Ganzen zuerst gleich ein.",
        f"Beide Brüche brauchen gleich große Teile. Überlege, wie du beide mit dem Nenner {denominator} schreiben kannst.",
        "Erweitere jeden Bruch: Multipliziere seinen Zähler und Nenner mit derselben Zahl. Danach addierst du nur die Zähler.",
    ]


def normalized(value):
    return " ".join(unicodedata.normalize("NFKC", value).casefold().strip().replace(",", ".").split())


def result(outcome, reason, *, content=None, form=None, method=VERSION):
    return {"version": 2, "outcome": outcome, "reason": reason, "method": method,
            "dimensions": {"content": content or outcome, "form": form or "not_requested"}}


def arithmetic(question, answer):
    if question["type"] not in ("short", "gap"):
        return None
    prompt = question["prompt"]
    instruction = fraction_instruction(prompt)
    expression = re.search(
        r"(?<![\d/])(\d{1,4})\s*/\s*([1-9]\d{0,3})\s*([+−-])\s*"
        r"(\d{1,4})\s*/\s*([1-9]\d{0,3})(?![\d/])", prompt)
    # Part questions and a numerator gap ask for a number, not the value of
    # the entire fraction. Leave their established exact evaluation intact.
    if re.search(r"\b(?:zähler|nenner|teiler|divisor|faktor)\b", prompt, re.I) and not instruction:
        if not re.search(r"\b(?:als\s+bruch\s+mit\s+(?:dem\s+)?nenner)\b", prompt, re.I):
            return None
    if re.search(r"(?:_{2,}|□|\?+)\s*/|/\s*(?:_{2,}|□|\?+)", prompt):
        return None
    calculation = re.search(r"berechne|rechne|ergibt|ergebnis|summe|addiere|subtrahiere|wie viel", prompt, re.I)
    equation_gap = re.search(r"=\s*(?:_{2,}|□|\?+)\s*[.!?]?\s*$", prompt)
    if not instruction and not (expression and (calculation or equation_gap)):
        return None
    key, supplied = fraction_parts(question["answer"]), fraction_parts(answer)
    if key is None or supplied is None:
        return None
    expected = Fraction(*key)
    if expression:
        a, b, op, c, d = expression.groups()
        computed = Fraction(int(a), int(b)) + (1 if op == "+" else -1) * Fraction(int(c), int(d))
        if computed != expected:
            return result("uncertain", "Die gespeicherte Musterlösung passt nicht zur Rechnung. Die Aufgabe muss geklärt werden.")
    if Fraction(*supplied) != expected:
        return result("incorrect", "Die beiden Brüche haben noch nicht denselben Wert.")
    try:
        fraction_result(prompt, answer, [], question_type=question["type"])
        if expression and re.search(r"\b(?:kürze\s+(?:das\s+ergebnis\s+)?vollständig|vollständig\s+gekürzt|vollständig\s+kürzen)\b", prompt, re.I) and supplied != (expected.numerator, expected.denominator):
            raise ValueError("fully reduced result")
        denominator = re.search(r"\b(?:als\s+)?bruch\s+mit\s+(?:dem\s+)?nenner\s+(\d{1,4})\b", prompt, re.I)
        if denominator and supplied[1] != int(denominator[1]):
            raise ValueError("requested denominator")
    except ValueError:
        return result("incorrect", "Der Wert stimmt. Die Aufgabe verlangt noch eine bestimmte Bruchdarstellung.",
                      content="correct", form="incorrect")
    equivalent = supplied != key
    return result("correct", (f"Das stimmt: {answer.strip()} ist genauso viel wie {question['answer']}."
                              if equivalent else "Wert und verlangte Darstellung stimmen."),
                  form="correct" if instruction or denominator or re.search(r"vollständig", prompt, re.I) else "not_requested")


def triangle_area(question, answer):
    from .subject_content import legacy_presentation

    if not re.search(r"fläch", question["prompt"], re.I) or not (p := legacy_presentation(question)):
        return None
    block = p["blocks"][0]
    if block["kind"] != "triangle":
        return None
    g, h = (Fraction(str(n)) for n in block["numbers"])
    expected = g * h / 2
    def quantity(text):
        match = re.fullmatch(r"\s*(\d+(?:[.,]\d+)?)(?:\s*(cm|m)(?:²|\^2|2))?\s*", text)
        return (Fraction(match[1].replace(",", ".")), match[2]) if match else None
    key, supplied = quantity(question["answer"]), quantity(answer)
    if not key or key[0] != expected:
        return result("uncertain", "Die gespeicherte Musterlösung passt nicht zur Dreiecksfläche. Die Prüfung ist offen.")
    if not supplied:
        return None
    if supplied[0] == g * h:
        return result("incorrect", "Grundseite mal Höhe ergibt die Rechteckfläche. Das Dreieck ist die Hälfte davon. Welcher Schritt fehlt noch?")
    if supplied[0] != expected:
        return result("incorrect", "Prüfe erst Grundseite mal senkrechte Höhe. Danach halbierst du das Ergebnis.")
    if supplied[1] and supplied[1] != block["unit"]:
        return result("incorrect", "Der Zahlenwert stimmt; prüfe die Flächeneinheit.", content="correct", form="incorrect")
    if re.search(r"mit\s+(?:der\s+)?einheit|in\s+(?:cm|m)(?:²|\^2|2)", question["prompt"], re.I) and not supplied[1]:
        return result("incorrect", "Der Zahlenwert stimmt. Ergänze noch die verlangte Flächeneinheit.", content="correct", form="incorrect")
    return result("correct", "Du hast Grundseite und senkrechte Höhe multipliziert und das Ergebnis halbiert.")


def closed_concept(question, answer):
    """Small audited phrase rules, not a general semantic grader."""
    expected = normalized(question["answer"])
    value = " ".join(unicodedata.normalize("NFKC", answer).casefold().split()).rstrip(".! ")
    # An answer wrapper may contain exactly the key, no added factual claim.
    if len(expected.split()) <= 4 and any(value == prefix + expected for prefix in (
        "die antwort ist ", "das ist ", "es ist ", "der begriff ist ")):
        return result("correct", "Deine Formulierung nennt den gesuchten Begriff.")
    prompt = normalized(question["prompt"])
    if not re.search(r"wirbelsäule|wirbellos", prompt):
        return None
    if not re.fullmatch(r"(?:die |den |zu den )?wirbellosen?(?: tiere[ns]?)?", expected):
        return None
    # This precise positive classification accepts inflection and an optional
    # matching reason. Negation, contradictory additions and other sentences
    # intentionally fail the full match and remain open.
    phrase = (r"(?:(?:es|das tier) (?:gehört|zählt) zu den |(?:es|das tier) ist (?:ein )?|(?:zu den |den |die ))?"
              r"wirbellosen?(?:[rs] tier| tieren| tiere)?"
              r"(?:,? (?:weil|da) (?:es|das tier) keine wirbelsäule (?:hat|besitzt))?")
    if re.fullmatch(phrase, value):
        return result("correct", "Du ordnest das Tier richtig als wirbellos ein.")
    return None


def evaluate(question, answer):
    if (question.get("presentation") or {}).get("evidence_kind") in ("reflection", "creative", "self_report", "movement"):
        return result("uncertain", "Deine Idee ist gespeichert. Gefühle, kreative Ideen oder körperliche Ausführung werden hier nicht als richtig oder falsch gemessen.", method="open_learning_v1")
    if checked := triangle_area(question, answer):
        return checked
    if question.get("language"):
        from .language_evaluation import evaluate as language_evaluate

        return language_evaluate(question, answer)
    if hints := fraction_addition_hint(question, answer):
        return result("incorrect", hints[0])
    form = expanded_fraction(question["prompt"]) if question["type"] in ("choice", "gap", "short") else None
    if form and (supplied := fraction_parts(answer)) is not None:
        value_ok = Fraction(*supplied) == Fraction(*form)
        return result("correct" if supplied == form else "incorrect",
                      "Die verlangte Erweiterung stimmt." if supplied == form else "Multipliziere beide Zahlen mit dem verlangten Faktor.",
                      content="correct" if value_ok else "incorrect", form="correct" if supplied == form else "incorrect")
    if checked := arithmetic(question, answer):
        return checked
    if normalized(answer) in {normalized(v) for v in [question["answer"], *question.get("accepted", [])]}:
        return result("correct", "Deine Antwort entspricht einer geprüften Lösung.")
    if question["type"] == "short":
        if checked := closed_concept(question, answer):
            return checked
        return result("uncertain", "Deine Antwort ist gespeichert. Du kannst die Prüfung öffnen oder den gesuchten Begriff präzisieren.")
    return result("incorrect", "Die Antwort passt noch nicht zur Aufgabe.")
