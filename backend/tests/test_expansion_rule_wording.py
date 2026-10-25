"""Independent synthetic wording contracts; original quotes remain byte-for-byte."""

import pytest
from schulpilot.math_tasks import _catalog, _procedure_quote

EXPANSION = "Brüche erweitern"


@pytest.mark.parametrize("quote", [
    "Erweitere Zähler und Nenner mit der selben Zahl.",
    "Erweitere Zähler und Nenner mit derselben Zahl.",
    "Erweitere Zähler und Nenner mit der gleichen Zahl.",
    "Erweitere Zähler und Nenner mit der selben ganzen Zahl.",
    "Erweitere Zähler\nund Nenner mit der selben Zahl.",
    "Erweitere Zähler und Nenner mit der\r\nselben Zahl!",
    "Erweitere\u00a0Zähler und Nenner mit der\u00a0selben\u00a0Zahl.",
    "Beim Erweitern multiplizieren wir Zähler und Nenner mit der selben Zahl.",
    "Beim Erweitern werden Zähler und Nenner mit der selben Zahl multipliziert.",
    "Zähler und Nenner multiplizierst du beim Erweitern mit der selben Zahl.",
    "Beim Erweitern multiplizierst du Zähler und Nenner\nmit der selben Zahl.",
    "Beim Erweitern werden Zähler und Nenner\r\nmit der selben Zahl multipliziert.",
    "Beim Erweitern multiplizieren wir Zähler und Nenner mit der\u00a0selben ganzen Zahl.",
    "Beim Erweitern werden Zähler und Nenner eines Bruches\nmit der selben Zahl multipliziert.",
    "Beim Erweitern multipliziert man\nZähler und den Nenner mit derselben Zahl.",
])
def test_general_expansion_wordings_preserve_exact_original_quote_and_catalog(quote):
    content = "Regel für Brüche.\n" + quote + "\n\nEigene Übung: 1/4 und 2/7."
    sources = [{"content": content, "confirmed": True}]
    actual = _procedure_quote(sources, EXPANSION)
    assert actual == quote
    assert actual.encode("utf-8") == quote.encode("utf-8")
    assert actual in content
    assert _catalog(sources, "Mathematik", "") == {EXPANSION: {"expand": quote}}


@pytest.mark.parametrize("content", [
    "Beim Erweitern multiplizieren wir den Zähler mit 2 und den Nenner mit 3.",
    "Beim Erweitern multiplizieren wir Zähler und Nenner mit der selben Zahl. Heute nur mit Faktor 3.",
    "Brüche erweitern\n1/4 = 2/8\n2/5 = 4/10.",
    "Beim Erweitern werden Zähler und Nenner nicht mit der selben Zahl multipliziert.",
    "Nicht so: Erweitere Zähler und Nenner mit der selben Zahl.",
    "Gegenbeispiel: Beim Erweitern multiplizieren wir Zähler und Nenner mit der selben Zahl.",
    "Falsch: Erweitere Zähler und Nenner mit der selben Zahl.",
    "Fehlerhafte Regel: Beim Erweitern multiplizieren wir Zähler und Nenner mit der selben Zahl.",
    "Erweitere Zähler und Nenner\n\nmit der selben Zahl.",
    "Beim Erweitern multiplizieren wir Zähler und Nenner\n \nmit der selben Zahl.",
    "Beim Erweitern multiplizieren wir Zähler und Nenner\r\n\r\nmit der selben Zahl.",
    "Beim Kürzen teilen wir Zähler und Nenner durch dieselbe Zahl.",
    "Brüche erweitern\nZähler und Nenner: 1 und 2\nGleichungen: Multipliziere beide Seiten mit derselben Zahl.",
    "Brüche erweitern\nZähler und Nenner: Merkwörter\nGleichungen: Beide Seiten mit derselben Zahl multiplizieren.",
    "Erweitern\nZähler und Nenner\nZum Lösen von Gleichungen multiplizieren wir beide Seiten mit der selben Zahl.",
    "Beim Erweitern multiplizieren wir Zähler und Nenner\nmit derselben Zahl, aber nur mit\nFaktor 2.",
    "Beim Erweitern werden Zähler und Nenner\nmit der selben Zahl multipliziert, allerdings ausschließlich mit\r\nFaktor 4.",
])
def test_restrictions_examples_counterexamples_and_separate_paragraphs_do_not_authorize_expansion(content):
    sources = [{"content": content, "confirmed": True}]
    assert _procedure_quote(sources, EXPANSION) is None
    assert EXPANSION not in _catalog(sources, "Mathematik", "")
    if content.startswith("Beim Kürzen"):
        assert _procedure_quote(sources, "Brüche kürzen") == content
        assert _catalog(sources, "Mathematik", "") == {"Brüche kürzen": {"reduce": content}}


@pytest.mark.parametrize("space", ["\u00a0", "\u2003"])
@pytest.mark.parametrize("imperative", [False, True])
def test_unicode_blank_line_never_joins_a_rule(space, imperative):
    content = (("Erweitere Zähler und Nenner" if imperative else
                "Beim Erweitern multiplizieren wir Zähler und Nenner")
               + "\n" + space + "\nmit der selben Zahl.")
    assert _procedure_quote([{"content": content}], EXPANSION) is None
    assert EXPANSION not in _catalog([{"content": content}], "Mathematik", "")
