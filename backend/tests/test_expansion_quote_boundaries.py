"""Synthetic literal quote endings; no early escape from later restrictions."""

import pytest
from schulpilot.math_tasks import _catalog, _procedure_quote

EXPANSION = "Brüche erweitern"


@pytest.mark.parametrize("rule,note", [
    (
        "Brüche erweitern: Zähler und Nenner mit derselben ganzen Zahl multiplizieren",
        "\nEine andere Notiz folgt darunter.",
    ),
    (
        "Beim Erweitern werden Zähler und Nenner\nmit der selben Zahl\nmultipliziert",
        "\nDie nächste Notiz steht am Rand.",
    ),
    (
        "Beim Erweitern multiplizieren wir Zähler und Nenner\r\nmit derselben ganzen Zahl",
        "\r\nEine Skizze folgt rechts.",
    ),
])
def test_unpunctuated_complete_rule_stops_before_a_neutral_following_note(rule, note):
    sources = [{"content": rule + note}]
    assert _procedure_quote(sources, EXPANSION) == rule
    assert _catalog(sources, "Mathematik", "") == {EXPANSION: {"expand": rule}}
    # The wrapped rules become complete only after their final physical line.
    lines = rule.splitlines(keepends=True)
    for boundary in range(1, len(lines)):
        partial = "".join(lines[:boundary]).rstrip("\r\n")
        assert _procedure_quote([{"content": partial}], EXPANSION) is None


@pytest.mark.parametrize("content", [
    "Beim Erweitern multiplizieren wir Zähler und Nenner mit der selben Zahl\nnicht",
    "Beim Erweitern multiplizieren wir Zähler und Nenner mit der selben Zahl\nFalsche Regel",
    "Beim Erweitern multiplizieren wir Zähler und Nenner mit der selben Zahl\nGegenbeispiel",
    "Beim Erweitern multiplizieren wir Zähler und Nenner mit der selben Zahl\nHeute nur mit\nFaktor 3",
    "Beim Erweitern werden Zähler und Nenner\nmit der selben Zahl\n\nmultipliziert",
])
def test_quote_trimming_never_hides_same_clause_negation_restrictions_or_a_missing_verb(content):
    sources = [{"content": content}]
    assert _procedure_quote(sources, EXPANSION) is None
    assert EXPANSION not in _catalog(sources, "Mathematik", "")
