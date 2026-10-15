"""Deterministic pre-provider arithmetic, with literal artificial sources."""

import copy
import re
from fractions import Fraction

import pytest
from schulpilot.coaching import fraction_task_goal, fraction_task_signature, normalized_prompt, source_goals
from schulpilot.math_tasks import fraction_tasks
from schulpilot.providers import ProviderError
from schulpilot.schemas import Question

MATERIALS = [
    {
        "content": "Ein Bruch hat zwei Zahlen. Zähler: oben, Anzahl ausgewählter Teile. Nenner: unten, Einteilung des Ganzen."
    },
    {"content": "Brüche addieren: Bei gleichem Nenner werden die Zähler addiert. Der Nenner bleibt gleich."},
    {"content": "Brüche kürzen: Zähler und Nenner durch dieselbe ganze Zahl teilen."},
    {"content": "Brüche erweitern: Zähler und Nenner mit derselben ganzen Zahl multiplizieren."},
]
LABELS = ["Zähler und Nenner benennen", "Brüche addieren", "Brüche kürzen", "Brüche erweitern"]


def tasks(*, materials=None, previous=(), phase="understand", count=4, seed="synthetic-stage", labels=None):
    return fraction_tasks(
        MATERIALS if materials is None else materials,
        "Mathematik",
        "Brüche",
        list(previous),
        phase,
        count,
        seed,
        required_labels=labels,
    )


def assert_mathematically_correct(task):
    signature = fraction_task_signature(task["prompt"])
    assert signature is not None
    operation = signature[0]
    if operation == "component":
        _, component, (numerator, denominator) = signature
        expected = numerator if component == "zähler" else denominator
        assert task["answer"] == expected
    elif operation == "add":
        first, second = signature[1]
        expected = Fraction(int(first[0]), int(first[1])) + Fraction(int(second[0]), int(second[1]))
        assert Fraction(task["answer"]) == expected
        numerator, denominator = map(int, task["answer"].split("/"))
        assert numerator == int(first[0]) + int(second[0]) and denominator == int(first[1])
        assert first[1] == second[1]
        assert 0 < expected < 1
    elif operation == "reduce":
        numerator, denominator = map(int, signature[1])
        expected = Fraction(numerator, denominator)
        assert task["answer"] == f"{expected.numerator}/{expected.denominator}"
        assert expected.denominator < denominator
        assert "vollständig" in task["prompt"]
    else:
        _, (numerator, denominator), factor = signature
        expected = f"{int(numerator) * int(factor)}/{int(denominator) * int(factor)}"
        assert task["answer"] == expected
        assert int(factor) in (2, 3, 4)
    parsed = Question.model_validate(
        {
            **{key: value for key, value in task.items() if key != "source_excerpt"},
            "hints": ["Prüfe das bestätigte Rechenverfahren."],
            "explanation": "Künstlicher Platzhalter allein für die Strukturprüfung; kein KI-Aufruf.",
        }
    )
    assert parsed.answer == task["answer"]
    numbers = [int(number) for number in re.findall(r"\d+", task["prompt"])]
    assert numbers and all(0 < number <= 36 for number in numbers)


@pytest.mark.parametrize("phase", ["understand", "detective", "apply", "recall"])
def test_every_phase_is_exact_source_backed_and_mathematically_correct(phase):
    planned = tasks(phase=phase)
    assert len(planned) == 4
    assert [task["id"] for task in planned] == ["q1", "q2", "q3", "q4"]
    for task in planned:
        assert set(task) == {"id", "type", "prompt", "answer", "options", "accepted", "source_excerpt"}
        assert task["type"] == "short" and task["options"] == task["accepted"] == []
        assert "Neues Übungsbeispiel" in task["prompt"]
        assert any(task["source_excerpt"] in material["content"] for material in MATERIALS)
        assert_mathematically_correct(task)
    if phase == "detective":
        assert all("ist falsch" in task["prompt"] for task in planned)
    elif phase == "apply":
        assert all(
            any(word in task["prompt"] for word in ("Flasche", "Messbecher", "Bruchkarte", "Mengenkarte"))
            for task in planned
        )
    elif phase == "recall":
        assert all("Erinnern" in task["prompt"] for task in planned)
    else:
        assert all("Verstehen" in task["prompt"] for task in planned)


def test_required_labels_preserve_order_and_repeat_goals_with_new_examples():
    required = ["Brüche erweitern", "Zähler und Nenner benennen", "Zähler und Nenner benennen", "Brüche kürzen"]
    planned = tasks(labels=required)
    goals = source_goals(MATERIALS, "Mathematik", "Brüche")
    by_label = {goal["label"]: goal["id"] for goal in goals}
    assert [fraction_task_goal(task["prompt"], goals) for task in planned] == [by_label[label] for label in required]
    assert "Zähler" in planned[1]["prompt"] and "Nenner" in planned[2]["prompt"]
    assert len({fraction_task_signature(task["prompt"]) for task in planned}) == 4
    for task in planned:
        assert_mathematically_correct(task)


def test_same_inputs_reproduce_exact_tasks_without_mutating_inputs():
    materials, previous, labels = copy.deepcopy(MATERIALS), ["Kürze 12/18 vollständig."], LABELS.copy()
    before = copy.deepcopy([materials, previous, labels])
    first = tasks(materials=materials, previous=previous, labels=labels)
    assert first == tasks(materials=materials, previous=previous, labels=labels)
    assert [materials, previous, labels] == before
    assert first != tasks(materials=materials, previous=previous, labels=labels, seed="another-stage")


def test_arithmetic_signatures_avoid_many_old_examples_despite_different_wording():
    materials = [MATERIALS[2]]
    previous = [
        f"Kürze {numerator}/{denominator} vollständig."
        for denominator in range(2, 25)
        for numerator in range(1, denominator)
    ]
    planned = tasks(materials=materials, previous=previous, count=5, labels=["Brüche kürzen"] * 5)
    old_signatures = {fraction_task_signature(prompt) for prompt in previous}
    signatures = [fraction_task_signature(task["prompt"]) for task in planned]
    assert len(set(signatures)) == 5 and not set(signatures) & old_signatures
    assert not {normalized_prompt(task["prompt"]) for task in planned} & {
        normalized_prompt(prompt) for prompt in previous
    }
    for task in planned:
        assert_mathematically_correct(task)


def test_repeated_planning_with_accumulated_history_keeps_every_example_new():
    previous = []
    for phase in ("understand", "detective", "apply", "recall", "understand", "recall"):
        planned = tasks(previous=previous, phase=phase, count=5)
        old = {fraction_task_signature(prompt) for prompt in previous}
        new = {fraction_task_signature(task["prompt"]) for task in planned}
        assert len(new) == 5 and not new & old
        previous.extend(task["prompt"] for task in planned)


def test_three_task_stages_prioritize_underpracticed_goals_and_include_the_fourth_goal():
    goals = source_goals(MATERIALS, "Mathematik", "Brüche")
    labels_by_id = {goal["id"]: goal["label"] for goal in goals}
    previous, stages = [], []
    for phase in ("understand", "detective", "apply"):
        planned = tasks(previous=previous, phase=phase, count=3)
        stages.append([labels_by_id[fraction_task_goal(task["prompt"], goals)] for task in planned])
        previous.extend(task["prompt"] for task in planned)
    assert stages[0] == LABELS[:3]
    assert stages[1] == [LABELS[3], LABELS[0], LABELS[1]]
    assert stages[2] == [LABELS[2], LABELS[3], LABELS[0]]
    assert set(stages[0] + stages[1]) == set(LABELS)
    totals = [sum(stage.count(label) for stage in stages) for label in LABELS]
    assert max(totals) - min(totals) == 1


def test_explicit_goal_order_overrides_historical_balancing_without_substitution():
    previous = [task["prompt"] for task in tasks(count=5, labels=["Brüche kürzen"] * 5)]
    required = ["Brüche kürzen", "Brüche erweitern", "Brüche kürzen"]
    planned = tasks(previous=previous, count=3, labels=required)
    goals = source_goals(MATERIALS, "Mathematik", "Brüche")
    labels_by_id = {goal["id"]: goal["label"] for goal in goals}
    assert [labels_by_id[fraction_task_goal(task["prompt"], goals)] for task in planned] == required


def test_single_component_task_per_stage_balances_numerator_and_denominator_across_history():
    previous, components = [], []
    for index in range(6):
        planned = tasks(previous=previous, count=1, labels=[LABELS[0]], seed=f"stage-{index}")
        assert len(planned) == 1
        components.append(fraction_task_signature(planned[0]["prompt"])[1])
        previous.append(planned[0]["prompt"])
    assert components == ["zähler", "nenner"] * 3


def test_component_count_tie_follows_actual_definition_order_in_the_source():
    materials = [{"content": "Ein Bruch hat zwei Zahlen. Nenner: unten. Zähler: oben."}]
    planned = tasks(materials=materials, count=2, labels=[LABELS[0], LABELS[0]])
    assert [fraction_task_signature(task["prompt"])[1] for task in planned] == ["nenner", "zähler"]


def test_exhausted_finite_number_pool_fails_instead_of_repeating_or_falling_back():
    previous = [
        f"Kürze {numerator}/{denominator} vollständig."
        for denominator in range(2, 37)
        for numerator in range(1, denominator)
    ]
    with pytest.raises(ProviderError, match="keine neuen kleinen Zahlenaufgaben"):
        tasks(materials=[MATERIALS[2]], previous=previous, count=1)


@pytest.mark.parametrize(
    "subject,topic,materials",
    [
        ("Deutsch", "Brüche", MATERIALS),
        ("Sachunterricht", "Sonnensystem", [{"content": "Die Sonne ist ein Stern."}]),
        ("Mathematik", "Prozentrechnung", [{"content": "Prozent bedeutet von Hundert."}]),
        (
            "Mathematik",
            "Brüche multiplizieren",
            [{"content": "Beim Multiplizieren von Brüchen rechnen wir oben mal oben."}],
        ),
        ("Mathematik", "Brüche", [{"content": "Morgen üben wir Brüche kürzen."}]),
        ("Mathematik", "Brüche", [{"content": "Brüche mit ungleichen Nennern addieren wir später."}]),
        ("Mathematik", "Brüche", [{**MATERIALS[2], "confirmed": False}]),
    ],
)
def test_other_subjects_or_unconfirmed_unsupported_procedures_have_no_planned_tasks(subject, topic, materials):
    assert fraction_tasks(materials, subject, topic, [], "understand", 2, "artificial") == []


def test_missing_requested_goal_returns_no_partial_or_substitute_tasks():
    assert tasks(materials=[MATERIALS[2]], count=2, labels=["Brüche kürzen", "Brüche erweitern"]) == []
    assert tasks(count=1, labels=["Brüche subtrahieren"]) == []


def test_only_source_defined_fraction_component_is_used():
    materials = [{"content": "Ein Bruch teilt ein Ganzes. Nenner: unten, Anzahl aller gleich großen Teile."}]
    planned = tasks(materials=materials, count=2, labels=["Zähler und Nenner benennen"] * 2)
    assert len(planned) == 2 and all("Nenner" in task["prompt"] for task in planned)
    for task in planned:
        assert task["source_excerpt"] in materials[0]["content"]
        assert_mathematically_correct(task)


def test_addition_alone_does_not_require_an_unconfirmed_reduction_procedure():
    planned = tasks(materials=[MATERIALS[1]], count=5)
    assert len(planned) == 5
    for task in planned:
        assert fraction_task_signature(task["prompt"])[0] == "add"
        assert "kürz" not in task["prompt"].casefold() and "vereinfach" not in task["prompt"].casefold()
        assert_mathematically_correct(task)


@pytest.mark.parametrize("index,label", [(2, "Brüche kürzen"), (3, "Brüche erweitern")])
def test_single_procedure_does_not_introduce_other_fraction_methods(index, label):
    planned = tasks(materials=[MATERIALS[index]], count=5)
    goals = source_goals([MATERIALS[index]], "Mathematik", "Brüche")
    assert len(planned) == 5 and all(fraction_task_goal(task["prompt"], goals) == goals[0]["id"] for task in planned)
    for task in planned:
        assert label.casefold().split()[-1][:4] in task["source_excerpt"].casefold()
        assert_mathematically_correct(task)


def test_wide_combined_page_and_existing_two_page_fixture_keep_all_confirmed_methods():
    from schulpilot.fixtures import CONTENT, SECOND_PAGE_CONTENT

    for materials in (
        [{"content": " ".join(material["content"] for material in MATERIALS)}],
        [{"content": CONTENT}, {"content": SECOND_PAGE_CONTENT}],
    ):
        planned = tasks(materials=materials, labels=LABELS)
        assert len(planned) == 4
        goals = source_goals(materials, "Mathematik", "Brüche")
        by_label = {goal["label"]: goal["id"] for goal in goals}
        assert [fraction_task_goal(task["prompt"], goals) for task in planned] == [by_label[label] for label in LABELS]
        for task in planned:
            assert any(task["source_excerpt"] in material["content"] for material in materials)
            assert_mathematically_correct(task)


@pytest.mark.parametrize(
    "content,label",
    [
        (
            "Brüche kürzen lernen wir erst nächste Woche. Der Zähler zählt die ausgewählten Teile, der Nenner gibt die Anzahl aller Teile an.",
            "Brüche kürzen",
        ),
        (
            "Brüche kürzen. Die Zähler und Nenner benennen wir heute. Ausgewählte Teile und alle Teile werden gezählt.",
            "Brüche kürzen",
        ),
        (
            "Brüche erweitern: Heute multiplizieren wir Zähler und Nenner ausschließlich mit dem Faktor 2. Andere Faktoren sind nicht Teil dieser Übung.",
            "Brüche erweitern",
        ),
        (
            "Brüche kürzen: Wir teilen Zähler und Nenner nur durch 2, vollständig noch nicht.",
            "Brüche kürzen",
        ),
        (
            "Beim Erweitern multipliziert man Zähler und Nenner mit derselben Zahl. Heute üben wir nur mit dem Faktor 2.",
            "Brüche erweitern",
        ),
        (
            "Beim Kürzen teilt man Zähler und Nenner durch dieselbe Zahl. Vollständig noch nicht.",
            "Brüche kürzen",
        ),
        (
            "Brüche addieren: Bei gleichem Nenner werden die Nenner addiert; die Zähler bleiben gleich.",
            "Brüche addieren",
        ),
        (
            "Brüche addieren wir später. Die Zähler zählen Teile. Der Nenner ist gleich.",
            "Brüche addieren",
        ),
        (
            "Bei ungleichen Nennern werden die Zähler addiert.",
            "Brüche addieren",
        ),
        (
            "Beim Erweitern werden Zähler und Nenner nicht mit derselben Zahl multipliziert.",
            "Brüche erweitern",
        ),
    ],
)
def test_announcements_nouns_and_limited_or_unrelated_rules_never_authorize_general_procedures(content, label):
    materials = [{"content": content}]
    assert tasks(materials=materials, count=2, labels=[label, label]) == []
    planned = tasks(materials=materials, count=2)
    assert all(fraction_task_signature(task["prompt"])[0] == "component" for task in planned)


def test_restriction_is_not_overridden_by_a_general_rule_on_another_page():
    materials = [MATERIALS[3], {"content": "Brüche erweitern üben wir heute nur mit dem Faktor 2."}]
    assert tasks(materials=materials, count=1, labels=["Brüche erweitern"]) == []


@pytest.mark.parametrize("reverse", [False, True])
@pytest.mark.parametrize(
    "rule,restriction,label",
    [
        (MATERIALS[3], "Brüche erweitern üben wir heute nur mit dem Faktor zwei.", "Brüche erweitern"),
        (MATERIALS[2], "Brüche kürzen wir heute ausschließlich durch zwei.", "Brüche kürzen"),
    ],
)
def test_written_number_restrictions_also_override_general_rules(rule, restriction, label, reverse):
    materials = [rule, {"content": restriction}]
    assert tasks(materials=list(reversed(materials)) if reverse else materials, count=1, labels=[label]) == []


def test_numerator_addition_rule_in_one_clause_with_same_denominator_is_sufficient():
    materials = [{"content": "Bei gleichem Nenner addierst du nur die Zähler."}]
    planned = tasks(materials=materials, count=2, labels=["Brüche addieren"] * 2)
    assert len(planned) == 2
    assert all(task["source_excerpt"] == materials[0]["content"] for task in planned)
    for task in planned:
        assert_mathematically_correct(task)


@pytest.mark.parametrize("count,phase", [(0, "recall"), (6, "apply"), (True, "understand"), (2, "unknown")])
def test_invalid_stage_limits_are_rejected(count, phase):
    with pytest.raises(ProviderError, match="ungültig"):
        tasks(count=count, phase=phase)


def test_mismatched_requested_goal_count_is_rejected():
    with pytest.raises(ProviderError, match="Aufgabenumfang"):
        tasks(count=2, labels=["Brüche kürzen"])
