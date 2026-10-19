"""Synthetic examples for the build43 desktop practice report; no child data."""

from schulpilot import language_evaluation
from schulpilot.answer_evaluation import evaluate
from schulpilot.db import DB, Activity, LearningUnit, VocabularyImport, VocabularyItem
from schulpilot.language_tasks import EvaluationPolicy, LanguageTask
from schulpilot.learning_hints import next_hint
from schulpilot.library import group_learning_items
from schulpilot.subject_content import legacy_presentation, public_presentation
from sqlalchemy import func, select
from test_learning import child_client, prepared


def word_question(word="swimming pool", *, locale="en-GB", optional=None, variants=()):
    task = LanguageTask(target_locale=locale if locale != "de-DE" else "en-GB", answer_locale=locale,
        task_kind="spelling", skill="spelling", direction="target_to_de" if locale == "de-DE" else "de_to_target",
        vocabulary_item_id="a" * 32, vocabulary_revision=1,
        evaluation_policy=EvaluationPolicy(criterion="spelling", case_sensitive=True,
            sentence_initial_optional=optional, apostrophe_equivalent=True))
    return {"id":"word", "type":"short", "prompt":"Schreibe das Wort auf Englisch.", "answer":word,
        "accepted":list(variants), "hints":["Prüfe die Bedeutung.", "Prüfe den ersten Buchstaben."],
        "explanation":"Künstliches Wortpaar.", "language":task.model_dump()}


def test_target_specific_case_unicode_and_variants_without_fuzzy_success():
    for answer in ("swimming pool", "Swimming pool", "  swimming\u00a0 pool  "):
        assert language_evaluation.evaluate(word_question(), answer)["outcome"] == "correct"
    for expected, answer, locale in (("swimming pool", "swimming Pool", "en-GB"),
        ("London", "london", "en-GB"), ("Schwimmbad", "schwimmbad", "de-DE"),
        ("Straße", "Strasse", "de-DE"), ("école", "ecole", "fr-FR"),
        ("were", "where", "en-GB"), ("your", "you're", "en-GB"),
        ("He goes to school", "He go to school", "en-GB")):
        assert language_evaluation.evaluate(word_question(expected, locale=locale), answer)["outcome"] == "incorrect"
    assert language_evaluation.evaluate(word_question("école", locale="fr-FR"), "e\u0301cole")["outcome"] == "correct"
    q = word_question("I don't like tea", variants=["I do not like tea"])
    assert language_evaluation.evaluate(q, "I don’t like tea")["outcome"] == "correct"
    assert language_evaluation.evaluate(q, "I do not like tea")["outcome"] == "correct"
    q = word_question(optional=False)
    verdict = language_evaluation.evaluate(q, "Swimming pool")
    assert verdict["outcome"] == "incorrect"
    assert verdict["dimensions"]["capitalization"] == "incorrect"
    assert "kleinem s" in verdict["reason"]
    assert next_hint(q, "Swimming pool", []) == verdict["reason"]
    q = word_question(optional=True)
    q["prompt"] = "Schreibe das Wort ausdrücklich mit kleinem Anfangsbuchstaben."
    assert language_evaluation.evaluate(q, "Swimming pool")["outcome"] == "incorrect"
    q["prompt"] = "Schreibe das Wort auf Englisch (Großbritannien)."
    assert language_evaluation.evaluate(q, "Swimming pool")["outcome"] == "correct"
    assert "capitalization" not in language_evaluation.evaluate(word_question("Straße", locale="de-DE"), "Strasse")["dimensions"]


def test_denominator_feedback_and_progressive_help_preserve_equivalence():
    q = {"id":"sum", "type":"short", "prompt":"Berechne 1/3 + 1/6.", "answer":"1/2", "accepted":[],
        "hints":["Teile beide Ganzen gleich ein."], "explanation":"1/3 = 2/6. 2/6 + 1/6 = 3/6 = 1/2."}
    assert "Nenner" in evaluate(q, "3/9")["reason"]
    first = next_hint(q, "3/9", [])
    second = next_hint(q, "3/9", [first])
    assert first != second and "Nenner 6" in second
    assert evaluate(q, "6/12")["outcome"] == "correct"
    q.update(prompt="Berechne 1/4 + 1/8.", answer="3/8")
    assert evaluate(q, "6/16")["outcome"] == "correct"
    q["prompt"] += " Kürze das Ergebnis vollständig."
    assert evaluate(q, "6/16")["dimensions"] == {"content":"correct", "form":"incorrect"}


def test_biology_solution_graphics_are_private_until_deliberate_help_or_feedback():
    for text, kind in (("Die Wurzel nimmt Wasser auf und gibt der Pflanze Halt.", "plant"),
        ("Bei der Bestäubung gelangt Pollen auf die Narbe. Bei der Befruchtung verschmilzt eine männliche Keimzelle mit der Eizelle.", "forms")):
        q = {"prompt":"Erkläre den Vorgang.", "explanation":text}
        assert legacy_presentation(q) is None
        private = legacy_presentation(q, [text])
        assert private["blocks"][0]["kind"] == kind
        assert public_presentation(private)["blocks"] == []
        assert public_presentation(private, hints=3)["blocks"] == []
        public = public_presentation(private, closed=True)
        assert len(public["blocks"]) == 1 and "source_excerpt" not in public["blocks"][0]
    assert legacy_presentation({"prompt":"Wozu dient die Wurzel?", "explanation":"Sie gibt Halt."},
        ["Die Wurzel nimmt Wasser auf und gibt Halt."])["blocks"][0]["kind"] == "plant"
    assert legacy_presentation({"prompt":"Was ist Bestäubung?", "explanation":"Pollen gelangt auf die Narbe."},
        ["Bestäubung: Pollen auf Narbe. Befruchtung: männliche Keimzelle und Eizelle."])["blocks"][0]["kind"] == "forms"
    assert legacy_presentation({"prompt":"Pflanzen", "explanation":"Unbekannter Stoff."}) is None


def test_question_explanation_has_matching_values_and_support_does_not_spread(api):
    demo, unit_id = prepared(api)
    with DB.begin() as db:
        unit = db.get(LearningUnit, unit_id)
        unit.explanation = "Anderes Beispiel: 1/2 + 1/4 = 3/4."
        unit.questions = [{"id":f"q{i}", "type":"short", "prompt":"Berechne 1/3 + 1/6.",
            "answer":"1/2", "accepted":[], "options":[], "hints":["Gleich einteilen."],
            "explanation":"1/3 = 2/6. Zusammen sind es 3/6 = 1/2."} for i in (1,2)]
    with child_client(demo) as kid:
        assert kid.post(f"/api/units/{unit_id}/start").status_code == 200
        response = kid.post(f"/api/units/{unit_id}/explanation", json={"question_id":"q1"})
        assert response.status_code == 200, response.text
        assert "1/3" in response.json()["explanation"] and "1/4" not in response.json()["explanation"]
        first = kid.post(f"/api/units/{unit_id}/questions/q1/answer", json={"answer":"1/2", "request_id":"audit-answer-first-001"})
        assert first.json()["evaluation"]["support_reasons"] == ["explanation"]
        second = kid.post(f"/api/units/{unit_id}/questions/q2/answer", json={"answer":"1/2", "request_id":"audit-answer-second-001"})
        assert second.json()["assisted"] is False
        assert second.json()["evaluation"]["support_reasons"] == []
        repeated = kid.post(f"/api/units/{unit_id}/questions/q2/answer", json={"answer":"1/2", "request_id":"audit-answer-second-001"})
        assert repeated.json()["attempt_id"] == second.json()["attempt_id"]
        for kind in ("answer_seems_right", "solution_seems_wrong", "display_unclear"):
            assert kid.post(f"/api/units/{unit_id}/feedback", json={"kind":kind,"question_id":"q2"}).status_code == 200
        assert kid.post(f"/api/units/{unit_id}/feedback", json={"kind":"display_unclear","question_id":"foreign"}).status_code == 404
    with DB() as db:
        before = db.scalar(select(func.count()).select_from(Activity))
    for _ in range(2):
        assert api.get(f"/api/units/{unit_id}").status_code == 200
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Activity)) == before


def test_deferred_words_remain_private_source_bound_and_confirmation_replays(api, household):
    _, child = household
    data = {"target_locale":"en-GB", "title":"Künstliche Prüfliste", "language_confirmed":True,
        "pairs":[{"word":"swimming pool","meaning":"Schwimmbad"},{"word":"exercise","meaning":"Übung"}]}
    draft = api.post(f"/api/children/{child['id']}/vocabulary/imports", json=data,
        headers={"Idempotency-Key":"audit-words-deferred-001"}).json()
    request = {"target_locale":"en-GB", "language_confirmed":True,
        "pairs":[draft["pairs"][0]], "deferred_pairs":[draft["pairs"][1]]}
    route = f"/api/children/{child['id']}/vocabulary/imports/{draft['id']}/confirm"
    assert api.post(route, json=request).status_code == 200
    assert api.post(route, json=request).status_code == 200
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(VocabularyItem)) == 1
        rows = list(db.scalars(select(VocabularyImport).where(VocabularyImport.status == "review")))
        assert len(rows) == 1 and rows[0].pairs[0]["word"] == "exercise"
        pending_id = rows[0].id
    assert api.post(f"/api/children/{child['id']}/vocabulary/imports/{pending_id}/confirm",
        json={"pairs":[draft["pairs"][1]], "target_locale":"en-GB", "language_confirmed":True}).status_code == 200
    assert api.post(route, json=request).status_code == 200


def test_topic_grouping_preserves_all_rounds_and_does_not_hide_mandatory_or_active_work():
    base = {"kind":"review","subject":"Biologie","topic":"Blütenpflanzen","status":"planned","mandatory":False}
    rows = [{**base,"id":str(i),"scheduled_for":"2026-10-20"} for i in range(26)]
    rows += [{**base,"kind":"unit","status":"active","id":"active"}, {**base,"mandatory":True,"id":"parent"}]
    grouped = group_learning_items(rows)
    assert len(grouped) == 3 and len(grouped[0]["entries"]) == 26
    assert {r["id"] for r in grouped[0]["entries"]} == {str(i) for i in range(26)}
    assert grouped[1]["id"] == "active" and grouped[2]["id"] == "parent"
    assert all(row["kind"] == "review" for row in rows[:26])
