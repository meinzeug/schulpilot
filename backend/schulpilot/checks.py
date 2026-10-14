"""Small deterministic checks for the arithmetic we can verify unambiguously."""

import re
import unicodedata
from fractions import Fraction


def expanded_fraction(prompt):
    """Only recognize an explicit fraction and a positive expansion factor."""
    match = re.search(
        r"\berweitere\s+(?:den\s+bruch\s+)?(\d{1,4})\s*/\s*([1-9]\d{0,3})"
        r"\s+mit\s+(?:(?:dem\s+)?faktor\s+)?([1-9]\d{0,3})\s*[.!?]?\s*$",
        prompt,
        re.I,
    )
    if match:
        numerator, denominator, factor = map(int, match.groups())
        return numerator * factor, denominator * factor
    return None


def fraction_parts(answer):
    value = unicodedata.normalize("NFKC", answer)
    value = re.sub(r"^\s*(?:\([A-H]\)|[A-H][).:])\s*", "", value, flags=re.I)
    match = re.fullmatch(r"\s*(-?\d{1,9})\s*/\s*([1-9]\d{0,8})\s*", value)
    return tuple(map(int, match.groups())) if match else None


def canonical_choice(value):
    """Decode explicit, unique answer labels without guessing a letter's index."""
    if not isinstance(value, dict) or value.get("type") != "choice":
        return value
    options, answer = value.get("options"), value.get("answer")
    if not isinstance(options, list) or not options or not isinstance(answer, str):
        return value
    labels, texts = {}, {}
    for option in options:
        if not isinstance(option, str):
            return value
        match = re.fullmatch(r"\s*(?:\(([A-H])\)|([A-H])[).:])\s*(\S.*?)\s*", option, re.I | re.S)
        if not match:
            return value
        label, text = (match[1] or match[2]).upper(), match[3]
        if label in labels:
            return value
        if text in texts:
            raise ValueError("Doppelte Auswahlmöglichkeiten.")
        labels[label] = option
        texts[text] = option

    def decode(text):
        if not isinstance(text, str):
            return text
        if text in options:
            return text
        match = re.fullmatch(r"\s*(?:\(([A-H])\)|([A-H])[).:]?)\s*", text, re.I)
        if not match:
            return texts.get(text, text)
        decoded = labels.get((match[1] or match[2]).upper(), text)
        possible = [option for content, option in texts.items() if content.casefold() == text.strip().casefold()]
        if possible and decoded not in possible:
            raise ValueError("Mehrdeutiger Antwortbuchstabe.")
        return decoded

    result = {**value, "answer": decode(answer)}
    if isinstance(value.get("accepted"), list):
        result["accepted"] = [decode(item) for item in value["accepted"]]
    return result


def fraction_result(prompt, answer, accepted):
    lower = prompt.casefold()
    # A question about a numerator/denominator does not ask for the fraction's
    # value. In particular, 1/4 + 3/4 may be represented as 4/4 or 1/1; this
    # narrow whole-value check cannot infer the intended representation.
    if re.match(r"\s*(?:welche[nr]\s+|wie\s+(?:lautet|heißt)\s+der\s+)(?:zähler|nenner)\b", lower):
        return
    if not re.search(r"rechne|berechne|ergebnis|wie viel|ergibt", lower):
        return
    expression = re.search(r"(\d{1,4})\s*/\s*([1-9]\d{0,3})\s*([+−-])\s*(\d{1,4})\s*/\s*([1-9]\d{0,3})", prompt)
    if not expression:
        return
    a, b, op, c, d = expression.groups()
    expected = Fraction(int(a), int(b)) + (1 if op == "+" else -1) * Fraction(int(c), int(d))
    gap = re.search(r"=\s*(?:\?+|_{2,}|□)\s*/\s*([1-9]\d{0,3})", prompt)
    if gap:
        expected *= int(gap[1])
    for value in [answer, *accepted]:
        value = re.sub(r"^\s*(?:\([A-H]\)|[A-H][).:])\s*", "", value, flags=re.I)
        for variant in re.split(r"\s+(?:oder|bzw\.)\s+|=", value, flags=re.I):
            compact = re.sub(r"\s+", "", variant)
            if re.fullmatch(r"-?\d+(?:/[1-9]\d*)?", compact) and Fraction(compact) != expected:
                raise ValueError("Die rechnerisch prüfbare Bruchlösung passt nicht zur Aufgabe.")
