"""Fixed artificial seeds cover the rare collision of all source introductions."""
import copy
import hashlib

import test_notebook_fraction_expansions as fixtures
from schulpilot import learning_entry
from schulpilot import notebook_fraction_expansions as notebook_expansion
from schulpilot.notebook_fraction_expansions import KEY
from test_notebook_fraction_expansions import binding_and_wire, prepared


def test_new_probes_leave_a_source_backed_introduction_without_exposing_their_answers(household, monkeypatch):
    original = learning_entry._probe

    def colliding(competence, _seed, previous, ordinal, *args, **kwargs):
        # These fixed hashes initially choose1/5 and2/7, the only two original
        # fractions on this artificial page. No source or answer is rewritten.
        seed = "public-collision-31" if competence["probe"] == "fraction_components" else "public-collision-77"
        return original(competence, seed, previous, ordinal, *args, **kwargs)

    monkeypatch.setattr(learning_entry, "_probe", colliding)
    _, payload, planned, binding, _ = prepared(household, count=5, entry=True)
    before = copy.deepcopy(payload)
    probes = payload["learning_entry"]["units"][0]["probes"]
    assert len(probes) == 3 and len(planned[KEY]["tasks"]) == 2
    originals = {(1, 5), (2, 7)}
    introductions = [candidate for candidate in binding.candidates if candidate["disclosure"] == "given"]
    assert introductions and all(tuple(candidate["block"]["numbers"]) in originals for candidate in introductions)
    given_pairs = {tuple(candidate["block"]["numbers"]) for candidate in introductions}
    for probe in probes:
        example = probe["visual_example"]
        assert (example["numerator"], example["denominator"]) not in given_pairs
        if example["factor"] == 2 and "/" in probe["answer"]:
            assert tuple(map(int, probe["answer"].split("/"))) not in given_pairs
    assert binding_and_wire(payload)[0] == planned and payload == before


def test_single_reducible_original_remains_available_for_introduction(household, monkeypatch):
    monkeypatch.setattr(fixtures, "CONTENT",
        "Beim Erweitern multiplizierst du Zähler und Nenner mit derselben Zahl. Originalbeispiel: 2/4.")
    pool = list(notebook_expansion._pool())
    seed = next(f"public-task-collision-{i}" for i in range(2000) if min(pool, key=lambda numbers:
        hashlib.sha256(f"public-task-collision-{i}|apply|expand|{numbers}".encode()).digest()) == (1, 2, 2))
    original = notebook_expansion.fraction_tasks

    def colliding(materials, subject, topic, previous, phase, count, _seed, **kwargs):
        return original(materials, subject, topic, previous, phase, count, seed, **kwargs)

    monkeypatch.setattr(notebook_expansion, "fraction_tasks", colliding)
    _, _, planned, binding, _ = prepared(household, count=2, entry=False)
    assert len(planned[KEY]["tasks"]) == 2
    assert all(task["answer"] != "2/4" for task in planned[KEY]["tasks"])
    assert any(candidate["disclosure"] == "given" and candidate["block"]["numbers"] == [2, 4]
        for candidate in binding.candidates)
