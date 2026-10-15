"""Small deterministic checks for the arithmetic we can verify unambiguously."""

import re
import unicodedata
from fractions import Fraction


def fraction_instruction(prompt):
    """Recognize a single result fraction, never a requested divisor or part."""
    text = unicodedata.normalize("NFKC", prompt).casefold()
    if re.search(
        r"\b(?:welche[rnms]?|wie\s+(?:lautet|heißt)|nenne|bestimme|gib)\s+"
        r"(?:(?:nur|der|den|die|das|ist)\s+)*(?:zähler|nenner|teiler|divisor|(?:kürzungs|erweiterungs)?faktor)\b",
        text,
    ) or re.search(r"(?:\?+|_{2,}|□)\s*/|/\s*(?:\?+|_{2,}|□)", text):
        return None
    if not (
        re.match(r"\s*(?:kürze|erweitere)\b", text)
        or re.match(
            r"\s*(?:wie\s+(?:lautet|heißt)|welche[rns]?|gib|nenne|bestimme)\b"
            r"[^.!?\n]{0,70}\b(?:bruch|ergebnis)\b",
            text,
        )
    ):
        return None
    reduction = bool(re.search(r"\b(?:kürz\w*|gekürzt\w*)\b", text))
    expansion = bool(re.search(r"\berweiter\w*\b", text))
    fractions = list(dict.fromkeys(re.findall(r"(?<![\d/-])(\d{1,4})\s*/\s*([1-9]\d{0,3})(?![\d/])", text)))
    if reduction == expansion or len(fractions) != 1:
        return None
    factors = set(
        re.findall(
            r"\b(?:mit|durch)\s+(?:(?:dem|der|den|die)\s+)?"
            r"(?:(?:(?:kürzungs|erweiterungs)?faktor|teiler|zahl)\s+)?([+−-]?\d{1,4})\b",
            text,
        )
    )
    if len(factors) > 1:
        return None
    return {
        "parts": tuple(map(int, fractions[0])),
        "operation": "reduce" if reduction else "expand",
        "factor": int(next(iter(factors)).replace("−", "-")) if factors else None,
        "fully": bool(re.search(r"\b(?:vollständig|vollkommen)\b|so\s+weit\s+wie\s+möglich", text)),
        "step": bool(re.search(r"\b(?:erst\w*|nächst\w*|ein(?:em|en))\s+(?:kürz\w*|schritt)\b|\beinmal\b", text)),
    }


def expanded_fraction(prompt):
    """Only recognize an explicit fraction and a positive expansion factor."""
    match = re.search(
        r"\berweitere\s+(?:den\s+bruch\s+)?(\d{1,4})\s*/\s*([1-9]\d{0,3})"
        r"\s+(?:durch\s+multiplikation\s+)?mit\s+(?:(?:dem\s+)?faktor\s+)?([1-9]\d{0,3})\s*[.!?]?\s*$",
        prompt,
        re.I,
    )
    if match:
        numerator, denominator, factor = map(int, match.groups())
        return numerator * factor, denominator * factor
    instruction = fraction_instruction(prompt)
    if instruction and instruction["operation"] == "expand" and (instruction["factor"] or 0) > 0:
        numerator, denominator = instruction["parts"]
        return numerator * instruction["factor"], denominator * instruction["factor"]
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


def numeric_fraction_parts(value):
    value = re.sub(r"^\s*(?:\([A-H]\)|[A-H][).:])\s*", "", unicodedata.normalize("NFKC", value), flags=re.I)
    parts = fraction_parts(value)
    if parts is None and re.fullmatch(r"\s*-?\d{1,9}\s*", value):
        parts = int(value), 1
    if parts is None:
        raise ValueError("Die Bruchlösung ist nicht als eindeutige Zahl oder Bruch prüfbar.")
    return parts


def fraction_result(prompt, answer, accepted, *, question_type=None, options=None):
    instruction = fraction_instruction(prompt)
    if instruction:
        numerator, denominator = instruction["parts"]
        expected = Fraction(numerator, denominator)
        factor, operation = instruction["factor"], instruction["operation"]
        if factor is not None and factor <= 0:
            raise ValueError("Ein Kürzungsteiler oder Erweiterungsfaktor muss positiv sein.")
        if not factor and question_type != "choice" and (instruction["step"] or operation == "expand"):
            raise ValueError("Die Bruchaufgabe ist ohne ausdrücklich genannten Faktor oder Teiler mehrdeutig.")
        if operation == "reduce" and factor and (numerator % factor or denominator % factor):
            raise ValueError("Der genannte Teiler kürzt diesen Bruch nicht ganzzahlig.")

        def check(parts):
            if Fraction(*parts) != expected:
                raise ValueError("Die rechnerisch prüfbare Bruchlösung passt nicht zur Aufgabe.")
            if operation == "reduce":
                if factor and parts != (numerator // factor, denominator // factor):
                    raise ValueError("Die Bruchlösung entspricht nicht dem verlangten Kürzungsteiler.")
                if instruction["fully"] and parts != (expected.numerator, expected.denominator):
                    raise ValueError("Die Bruchlösung ist nicht vollständig gekürzt.")
                if not factor and (
                    parts[1] > denominator
                    or denominator % parts[1]
                    or (expected.denominator < denominator and parts[1] == denominator)
                ):
                    raise ValueError("Die Bruchlösung wurde nicht durch einen ganzzahligen Teiler gekürzt.")
            elif factor and parts != (numerator * factor, denominator * factor):
                raise ValueError("Die Bruchdarstellung entspricht nicht dem verlangten Erweiterungsfaktor.")
            elif not factor and (parts[1] <= denominator or parts[1] % denominator):
                raise ValueError("Die Bruchlösung wurde nicht mit einem ganzzahligen Faktor erweitert.")

        # Explicit expansion already has exact-form validation and alias
        # filtering in Question.consistent. Preserve that established behavior.
        values = [answer] if expanded_fraction(prompt) else [answer, *accepted]
        for value in values:
            check(numeric_fraction_parts(value))
        if question_type == "choice" and options is not None:
            correct = 0
            for option in options:
                parts = numeric_fraction_parts(option)
                try:
                    check(parts)
                except ValueError:
                    continue
                correct += 1
            if correct != 1:
                raise ValueError("Die Bruchauswahl hat nicht genau eine rechnerisch passende Antwort.")
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
