"""Synthetic regressions for R01–R15, not observations of a real child's skills."""

import pytest
from schulpilot.material_vocabulary import preview
from test_coaching import normal_unit as normal_unit
from test_material_vocabulary import counts, source


@pytest.mark.parametrize(
    "title", ["Simple Past: irregular verbs", "Simple Past – unregelmäßige Verben", "Grammar: past tense"]
)
def test_n010_grammar_timeline_and_metadata_are_not_translations(title):
    text = f"{title}\nSimple Past: abgeschlossene Vergangenheit\ngo → went\nsee → saw\nbuy → bought\n"
    text += "Beispiele:\nYesterday I went to the park.\nZeitstrahl:\nyesterday   now\nKünstliche Testseite – keine echte Hausaufgabe"
    assert preview("Englisch", title, text) is None


def test_mixed_sections_resume_only_for_actual_bilingual_words():
    data = preview(
        "Englisch",
        "Mein Heft",
        "Simple Past: irregular verbs\ngo → went\n"
        "English | Deutsch | Kontext\ncat | Katze | a pet\nbank | Bank | a place for money\n"
        "Beispiele:\nYesterday: I saw a cat\nAPP-TEST 19.10.2026 – Englisch – Seite 1",
    )
    assert [(p["word"], p["meaning"]) for p in data["pairs"]] == [("cat", "Katze"), ("bank", "Bank")]
    assert all(p["source_line"] and p["key"] for p in data["pairs"])
    assert data["requires_pair_confirmation"]


def test_individual_choice_correction_and_old_client_never_confirms_unchecked_words(api, household):
    _, child = household
    text = "English | Deutsch\ncat | Katze\ndog | Hud\nbank | Bank"
    material, revision = source(child, text)
    proposal = preview("Englisch", "Vokabeln", text)
    assert (
        api.put(
            f"/api/materials/{material}/confirm",
            json={
                "subject": "Englisch",
                "topic": "Vokabeln",
                "content": text,
                "homework": [],
                "uncertainties_resolved": True,
                "revision": revision,
                "vocabulary": {"target_locale": "en-GB", "language_confirmed": True, "revision": revision},
            },
        ).status_code
        == 200
    )
    assert counts()[0] == 0  # Older bundled approval is only a review proposal.
    selected = [{"key": proposal["pairs"][1]["key"], "word": "dog", "meaning": "Hund", "confirmed": True}]
    body = {"target_locale": "en-GB", "language_confirmed": True, "revision": revision + 1, "selections": selected}
    for _ in range(2):
        result = api.post(f"/api/materials/{material}/vocabulary", json=body)
        assert result.status_code == 200, result.text
        assert result.json()["confirmed_words"] == 1
    assert counts()[0] == 1  # Correction is manual provenance, not fake OCR.
    bad = {**body, "selections": [{**selected[0], "key": "f" * 24}]}
    assert api.post(f"/api/materials/{material}/vocabulary", json=bad).status_code == 409
    assert api.post(f"/api/materials/{material}/vocabulary", json={**body, "selections": []}).status_code == 200
    assert counts()[0] == 1


def test_mixed_math_round_never_inherits_fraction_only_goal_catalogue(normal_unit):
    from schulpilot import coaching
    from schulpilot.db import DB, LearningUnit, Material

    _, unit_id, material_id, _, _ = normal_unit
    with DB.begin() as db:
        unit = db.get(LearningUnit, unit_id)
        db.get(
            Material, material_id
        ).content += "\nEin Dreieck hat eine Grundseite und eine senkrechte Höhe. Die Flächenregel wurde hier noch nicht notiert."
        unit.questions = [
            *unit.questions,
            {
                "id": "area",
                "type": "short",
                "prompt": "Ein Dreieck hat g = 6 cm und h = 3 cm. Wie groß ist seine Fläche?",
                "answer": "9 cm²",
                "accepted": [],
                "options": [],
                "hints": ["Halbiere das Rechteck."],
                "explanation": "6 * 3 / 2 = 9 cm².",
            },
        ]
        _, payload, _ = coaching.context(db, unit)
        assert payload["learning_goals"] == []
        assert len(payload["completed_questions"]) == 3


def test_audited_mixed_math_prompts_receive_stable_server_assignments(normal_unit):
    from schulpilot import coaching
    from schulpilot.db import DB, LearningUnit, Material
    from test_subject_content import CASES

    _, unit_id, material_id, _, _ = normal_unit
    with DB.begin() as db:
        unit = db.get(LearningUnit, unit_id)
        unit.questions = [CASES[0]["question"], CASES[1]["question"]]
        db.get(
            Material, material_id
        ).content = "Brüche addieren: Auf gleichen Nenner bringen und die Zähler addieren.\nDreieck: A = g * h / 2."
        _, payload, _ = coaching.context(db, unit)
        assert [g["label"] for g in payload["learning_goals"]] == ["Brüche addieren", "Fläche eines Dreiecks berechnen"]
        assert [q["learning_goal_id"] for q in payload["completed_questions"]] == ["g1", "g2"]
        assert "learning_goal_id" not in unit.questions[0]  # Do not rewrite old question snapshots.


def test_old_bundled_client_can_save_grammar_page_without_forcing_invalid_word_import(api, household):
    _, child = household
    content = "Simple Past: irregular verbs\ngo → went\nyesterday  now\nKünstliche Testseite – keine echte Hausaufgabe"
    material, revision = source(child, content)
    result = api.put(
        f"/api/materials/{material}/confirm",
        json={
            "subject": "Englisch",
            "topic": "Simple Past",
            "content": content,
            "homework": [],
            "uncertainties_resolved": True,
            "revision": revision,
            "vocabulary": {"target_locale": "en-GB", "language_confirmed": True, "revision": revision},
        },
    )
    assert result.status_code == 200 and result.json()["confirmed"]
    assert counts()[0] == 0
