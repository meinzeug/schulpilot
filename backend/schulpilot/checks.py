"""Small deterministic checks for the arithmetic we can verify unambiguously."""

import re
from fractions import Fraction


def fraction_result(prompt, answer, accepted):
    lower = prompt.casefold()
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
        compact = re.sub(r"\s+", "", value)
        if re.fullmatch(r"-?\d+(?:/[1-9]\d*)?", compact) and Fraction(compact) != expected:
            raise ValueError("Die rechnerisch prüfbare Bruchlösung passt nicht zur Aufgabe.")
