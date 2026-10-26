"""Finite new examples of an explicitly written, arithmetically checked rule.

The source supplies the procedure and a correct worked division, never the new
input numbers. All new answers and graphic parameters are computed locally
before generation. This is not an OCR correction or a model-output repair.
"""

import re
from fractions import Fraction

REVISION = "fraction-conversion-rule-1"
_RULE = re.compile(r"z(?:ä|ae)hler\s*(?::|÷|/|durch)\s*nenner", re.I)
_DIVISION = re.compile(
    r"(?<![\w.,/−-])([1-9][0-9]?)\s*(?::|÷|durch)\s*([1-9][0-9]?)\s*"
    r"(?:=|⇒|→|=>)\s*([1-3])\s*(?:Rest|R\.)\s*([0-9]{1,2})(?!\w|[.,][0-9])",
    re.I,
)


def evidence(content, literal_pairs):
    """Require the general rule AND a matching correct original example nearby."""
    for rule in _RULE.finditer(content):
        for division in _DIVISION.finditer(content, rule.end(), min(len(content), rule.end() + 240)):
            if not re.fullmatch(r"(?:\s|=>|⇒|→|\\Rightarrow|Beispiel\s*:)*", content[rule.end():division.start()], re.I):
                continue
            n, d, q, r = map(int, division.groups())
            if 2 <= d <= 24 and 0 < r < d and divmod(n, d) == (q, r) and (n, d) in literal_pairs:
                return {"version": 1, "revision": REVISION,
                    "quote": content[rule.start():division.end()], "worked_input": [n, d],
                    "worked_whole": q, "worked_remainder": r}
    return None


def inputs():
    """Small finite renderer-compatible values; equivalent inputs occur once."""
    seen = set()
    for d in range(2, 13):
        for q in range(1, 4):
            for r in range(1, d):
                n = q * d + r
                value = Fraction(n, d)
                if value.denominator == d and value not in seen:
                    seen.add(value)
                    yield n, d
