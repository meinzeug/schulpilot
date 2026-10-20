"""Artificial question/hint models, exact source evidence and disclosure gates."""

import copy
import json
from pathlib import Path

import pytest
from pydantic import ValidationError
from schulpilot.science_graphics import polynomial
from schulpilot.subject_content import PROFILES, Graphic, public_presentation, validate_question

CASES = json.loads((Path(__file__).parents[2] / "testdata/science_graphics_v1.json").read_text())["cases"]


@pytest.mark.parametrize("case", CASES, ids=lambda c: c["id"])
def test_scientific_help_is_source_bound_and_visible_only_at_its_saved_stage(case):
    q = case["question"]
    p = q["presentation"]
    validate_question(p, q, [case["source"]], PROFILES[case["subject"]])
    assert public_presentation(p)["blocks"] == []
    visible = public_presentation(p, hints=1, closed=True)["blocks"]
    assert len(visible) == 1 and "source_excerpt" not in visible[0]
    changed = copy.deepcopy(p)
    changed["blocks"][0]["source_excerpt"] += " Not in source"
    with pytest.raises(ValueError):
        validate_question(changed, q, [case["source"]], PROFILES[case["subject"]])


@pytest.mark.parametrize(
    "source,expected",
    [
        ("f(x)=x²", [1, 0, 0]),
        ("y=-2x+3", [0, -2, 3]),
        (r"\(f(x)=0,5x^{2}-x-2\)", [0.5, -1, -2]),
        ("y=x^3", None),
        ("y=eval(x)", None),
        ("y=x/0", None),
        ("y=x^2 und weiter", None),
        ("y=1000x", None),
        ("y=2", None),
        ("y=__import__(x)", None),
    ],
)
def test_polynomial_parser_accepts_only_the_declared_finite_function_family(source, expected):
    assert polynomial(source) == expected


@pytest.mark.parametrize(
    "index,changes",
    [
        (0, {"numbers": [2, 0, 0]}),
        (3, {"numbers": [0, 0, 1, 4]}),
        (5, {"labels": ["Zellkern", "Zellwand", "Zellmembran", "Cytoplasma", "Vakuole", "Chloroplast"]}),
        (7, {"source_excerpt": "Wasser: H2O"}),
        (10, {"labels": ["C", "C", "O", "H"]}),
        (11, {"disclosure": "given"}),
        (14, {"variant": "parallel"}),
        (16, {"numbers": [40, 20, 30]}),
    ],
)
def test_wrong_relations_or_hidden_solution_tables_are_rejected(index, changes):
    block = copy.deepcopy(CASES[index]["question"]["presentation"]["blocks"][0]) | changes
    with pytest.raises(ValidationError):
        Graphic.model_validate(block)


def test_model_relationship_cannot_be_invented_in_the_question_instead_of_confirmed_source():
    case = CASES[5]
    q = copy.deepcopy(case["question"])
    q["prompt"] = case["source"]
    with pytest.raises(ValueError, match="bestätigten Quellenstoff"):
        validate_question(q["presentation"], q, ["Andere bestätigte Quelle"], PROFILES["Biologie"])


@pytest.mark.parametrize(
    "source,expected",
    [
        (r"\(f(x)=\sin(x)\)", "sine"),
        (r"\[f(x)=\frac{1}{x}\]", "reciprocal"),
        (r"f(x)=\sqrt{x}", "square_root"),
        ("f(x)=sin(x)+1", None),
        ("f(x)=log(x)", None),
    ],
)
def test_standard_curve_parser_preserves_formula_family_and_domain(source, expected):
    from schulpilot.science_graphics import standard_curve

    assert standard_curve(source) == expected


def test_graph_instructions_are_limited_to_the_selected_subject_without_an_extra_call():
    from schulpilot.subject_content import rules_for

    rules = rules_for(["Mathematik"])
    assert "function_graph:" in rules and "function_curve:" in rules
    assert "molecule:" not in rules and "cell:" not in rules and "logic_table:" not in rules
    assert "molecule:" in rules_for(["Chemie"])


def test_data_plot_uses_exact_table_columns_and_keeps_their_order():
    case = copy.deepcopy(CASES[3])
    case["source"] = "Zeit t | Weg s\n--- | ---\n0 | 0\n1 | 2\n2 | 4"
    p = case["question"]["presentation"]
    p["blocks"][0]["source_excerpt"] = case["source"]
    validate_question(p, case["question"], [case["source"]], PROFILES["Physik"])
    p["blocks"][0]["numbers"] = [0, 0, 1, 4, 2, 2]
    with pytest.raises(ValueError):
        validate_question(p, case["question"], [case["source"]], PROFILES["Physik"])


def test_private_graphic_enum_is_bound_to_the_selected_subject():
    from schulpilot.providers import strict_schema
    from schulpilot.schemas import UnitOutput
    from schulpilot.subject_content import bind_graphic_schema

    schema = bind_graphic_schema(strict_schema(UnitOutput), ["Chemie"])
    kinds = schema["$defs"]["Graphic"]["properties"]["kind"]["enum"]
    assert "molecule" in kinds and "particles" in kinds
    assert "function_curve" not in kinds and "cell" not in kinds
    assert set(kinds) == set(PROFILES["Chemie"])


def test_molecule_accepts_literal_typesetting_but_does_not_infer_bonds_from_sum_formula():
    case = copy.deepcopy(CASES[10])
    case["source"] = r"\(\mathrm{CH}_3-\mathrm{CH}_2-\mathrm{OH}\)"
    p = case["question"]["presentation"]
    p["blocks"][0]["source_excerpt"] = case["source"]
    validate_question(p, case["question"], [case["source"]], PROFILES["Chemie"])
    p["blocks"][0]["source_excerpt"] = r"\(\mathrm{C}_2\mathrm{H}_6\mathrm{O}\)"
    with pytest.raises(ValueError):
        Graphic.model_validate(p["blocks"][0])
