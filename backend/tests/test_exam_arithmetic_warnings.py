"""Do not lose literal student work or confuse a calculation with a grade."""

import pytest

from schulpilot.exam_review import arithmetic_warnings


@pytest.mark.parametrize("answer", [
    r"\(\frac{6}{8}=\frac{2}{4}\) weiter kürzen",
    r"\(\frac{1}{4}+\frac{2}{4}=\frac{3}{8}\) \(\frac{3}{4}\)",
    "6/8 = 2/4",
])
def test_literal_false_equations_get_a_separate_warning(answer):
    warnings = arithmetic_warnings(answer)
    assert len(warnings) == 1
    assert "abgeschrieben" in warnings[0]["message"]


def test_the_warning_explains_the_two_exact_values():
    warning = arithmetic_warnings(r"\(\frac{6}{8}=\frac{2}{4}\) weiter kürzen")[0]
    assert "Links steht 3/4, rechts 1/2" in warning["message"]
    warning = arithmetic_warnings(r"\(\frac{1}{4}+\frac{2}{4}=\frac{3}{8}\)")[0]
    assert "Links steht 3/4, rechts 3/8" in warning["message"]


@pytest.mark.parametrize("answer", [
    r"\(\frac{6}{8}=\frac{3}{4}\)", "6/8 = 3/4", "x = 2", "1/0 = 0",
    "Vielleicht 6/8 = 2/4", "", None,
])
def test_unclear_or_correct_text_is_not_called_a_false_equation(answer):
    assert arithmetic_warnings(answer) == []
