"""Artificial literal sources through existing paid paths; no external calls."""

import copy
from types import SimpleNamespace

import pytest
from schulpilot import coaching, language_projects, study_path, vocabulary
from schulpilot.db import (
    DB,
    Activity,
    Assignment,
    Attempt,
    Job,
    LanguageProject,
    LearningUnit,
    Material,
    UnitCoaching,
    UnitSource,
    Usage,
    VocabularyImport,
)
from schulpilot.learning import unit_source_texts
from schulpilot.learning_sources import UnusableSources, exact_quote, project
from schulpilot.providers import ProviderError
from sqlalchemy import delete, func, select
from test_coaching import normal_unit as normal_unit
from test_language_jobs import notebook as _language_notebook
from test_language_jobs import project_request
from test_study_path import study as study
from test_tutor import ask, finish
from test_tutor import notebook as _tutor_notebook
from test_tutor import transport as transport
from test_vocabulary import child_login, import_words


@pytest.fixture
def language_notebook(api, household):
    return _language_notebook.__wrapped__(api, household)


@pytest.fixture
def tutor_notebook(api, household):
    yield from _tutor_notebook.__wrapped__(api, household)


def set_blocks(material, blocks):
    material.source_blocks = blocks
    material.content = "\n\n".join(row["text"] for row in blocks)


def blocked(text="1+1=3"):
    return {"kind": "formula", "text": text, "literal_role": "student_work"}


def test_literal_identity_preserves_chemistry_case_and_divisibility_signs():
    assert exact_quote("CO", ["CO ist eine Formel."])
    assert not exact_quote("CO", ["Co ist eine andere Schreibweise."])
    assert exact_quote(r"3 \nmid 5", [r"3 \nmid 5"])
    assert not exact_quote(r"3 \mid 5", [r"3 \nmid 5"])


def test_actual_tutor_payload_omits_wrong_original_and_keeps_public_citation(tutor_notebook, transport):
    good = "Die Sonne ist ein Stern."
    with DB.begin() as db:
        material = db.get(Material, tutor_notebook["material_id"])
        set_blocks(material, [{"kind": "paragraph", "text": good}, blocked()])
        original = material.content
    assert ask(tutor_notebook).status_code == 202
    finish()
    payload = transport["calls"][0]
    assert payload["sources"][0]["content"] == good
    assert payload["sources"][0]["source_policy"]["excluded_reasons"] == ["false_equality"]
    with DB() as db:
        assert db.get(Material, tutor_notebook["material_id"]).content == original
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0


def test_tutor_all_blocked_stops_before_job_reservation(tutor_notebook, transport):
    with DB.begin() as db:
        set_blocks(db.get(Material, tutor_notebook["material_id"]), [blocked()])
    response = ask(tutor_notebook)
    assert response.status_code == 409
    assert not transport["calls"]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
        assert db.scalar(select(func.count()).select_from(Job)) == 0


def test_queued_tutor_rechecks_policy_before_inference(tutor_notebook, transport):
    queued = ask(tutor_notebook)
    assert queued.status_code == 202
    with DB.begin() as db:
        material = db.get(Material, tutor_notebook["material_id"])
        set_blocks(material, [blocked(material.content)])
    finish()
    assert not transport["calls"]
    with DB() as db:
        assert db.get(Job, queued.json()["job_id"]).status == "failed"
        usage = db.scalar(select(Usage))
        assert usage.status == "failed_not_sent" and usage.cost_micros == 0
        assert usage.settlement_version == 1
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0


def test_coach_filters_original_but_preserves_explicit_source_free_parent_goal(normal_unit):
    _, unit_id, material_id, _, child = normal_unit
    with DB.begin() as db:
        material = db.get(Material, material_id)
        original = material.content
        set_blocks(material, [{"kind": "paragraph", "text": original}, blocked()])
        unit = db.get(LearningUnit, unit_id)
        _, payload, _ = coaching.context(db, unit)
        assert payload["materials"][0]["content"] == original
        assert unit_source_texts(db, unit) == [original]
        assert "1+1=3" not in payload["materials"][0]["content"]
        db.execute(delete(UnitSource).where(UnitSource.unit_id == unit.id))
        unit.material_id = None
        assignment = Assignment(child_id=child["id"], kind="parent", subject=unit.subject,
                                topic=unit.topic, note="Nenner benennen")
        db.add(assignment)
        db.flush()
        unit.assignment_id, unit.goal_revision = assignment.id, assignment.revision
        _, payload, _ = coaching.context(db, unit)
        assert payload["materials"] == [] and payload["goal"]["note"] == "Nenner benennen"


def test_stored_goal_from_newly_excluded_quote_blocks_followup_without_rewriting_evidence(normal_unit):
    _, unit_id, material_id, _, child = normal_unit
    with DB.begin() as db:
        material = db.get(Material, material_id)
        quote = material.content
        report = {"learning_goals": [{"id": "g1", "label": "Brüche vergleichen", "source_excerpt": quote}]}
        db.add(UnitCoaching(unit_id=unit_id, status="ready", report=copy.deepcopy(report)))
        attempt = Attempt(unit_id=unit_id, question_id="sum", answer="2/4", outcome="correct", assisted=False)
        db.add(attempt)
        db.flush()
        attempt_id = attempt.id
        set_blocks(material, [blocked(quote), {"kind": "paragraph", "text": "Weiterer freigegebener Lernstoff."}])
        with pytest.raises(ProviderError, match="gespeichertes Lernziel"):
            coaching.context(db, db.get(LearningUnit, unit_id))
        assert db.get(UnitCoaching, unit_id).report == report
        assert db.get(Attempt, attempt_id).answer == "2/4"
        assert db.get(Attempt, attempt_id).outcome == "correct"
        assert db.get(LearningUnit, unit_id).active_seconds == 0
        assert db.scalar(select(func.count()).select_from(Activity)) == 0


def test_study_source_plan_and_anchors_use_only_remaining_literal_blocks(study):
    with DB.begin() as db:
        from schulpilot.db import SchoolDay

        for material_id in study["materials"]:
            set_blocks(db.get(Material, material_id), [blocked()])
        selected = db.get(Material, study["materials"][0])
        good = "Die Sonne ist ein Stern."
        set_blocks(selected, [{"kind": "paragraph", "text": good}, blocked()])
        day = db.get(SchoolDay, study["day_id"])
        items = study_path.sources(db, day)
        assert [row.id for row in items] == [selected.id]
        safe = project(db, items)
        briefs = study_path.task_briefs(items, [], "understand", 2, contents=[value["content"] for value in safe])
        assert {row["source_excerpt"] for row in briefs} == {good}
        assert study_path.bounded_extents(items, db)[0]["word_count"] == 5
        source_hash = study_path.fingerprint(items, db)
        set_blocks(selected, [blocked(good)])
        assert study_path.fingerprint(items, db) != source_hash
        with pytest.raises(ProviderError):
            study_path.sources(db, day)


def test_vocabulary_and_language_context_filter_same_original_without_omitting_manual_words(api, language_notebook):
    _, child, material_id = language_notebook
    with DB.begin() as db:
        material = db.get(Material, material_id)
        set_blocks(material, [{"kind": "paragraph", "text": "apple = Apfel"}, blocked("dog = Hund")])
        row = SimpleNamespace(child_id=child["id"], source_revisions=[{"id": material.id, "revision": material.revision}],
                              text="", target_locale="en-GB")
        assert vocabulary.context(db, row)["confirmed_text"] == "apple = Apfel"
    import_words(api, child)
    child_login(api)
    response, _, _ = project_request(api, child, material_id)
    assert response.status_code == 202, response.text
    with DB() as db:
        row = db.get(LanguageProject, response.json()["id"])
        payload = language_projects.context(db, row)
        assert payload["materials"][0]["content"] == "apple = Apfel"
        assert {word["word"] for word in payload["words"]} == {"apple", "dog", "school"}


@pytest.mark.parametrize("path", ["vocabulary", "grammar"])
def test_all_excluded_import_or_grammar_stops_before_reserve(api, language_notebook, path):
    _, child, material_id = language_notebook
    if path == "grammar":
        import_words(api, child)
        child_login(api)
    with DB.begin() as db:
        material = db.get(Material, material_id)
        set_blocks(material, [blocked(material.content)])
    with DB() as db:
        before_usage = db.scalar(select(func.count()).select_from(Usage))
        before_jobs = db.scalar(select(func.count()).select_from(Job))
    if path == "vocabulary":
        response = api.post(f"/api/children/{child['id']}/vocabulary/imports", headers={"Idempotency-Key": "unsafe-import-107-0001"},
                            json={"target_locale": "en-GB", "language_confirmed": True, "title": "Wörter", "material_id": material_id})
    else:
        response, _, _ = project_request(api, child, material_id, mode="grammar", grammar_topic="simple_present", grammar_confirmed=True)
    assert response.status_code == 409, response.text
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == before_usage
        assert db.scalar(select(func.count()).select_from(Job)) == before_jobs
        assert db.get(Material, material_id).confirmed


def test_explicit_manual_vocabulary_keeps_manual_origin_when_original_is_excluded(api, language_notebook):
    _, child, material_id = language_notebook
    with DB.begin() as db:
        set_blocks(db.get(Material, material_id), [blocked("apple = Apfel")])
    # A previously extracted proposal can still be explicitly checked by the
    # parent, but no longer receives material-grounded provenance.
    parent, _, _ = language_notebook
    with DB.begin() as db:
        material = db.get(Material, material_id)
        row = VocabularyImport(child_id=child["id"], user_id=parent["id"], request_key="manual-confirm-107-0001",
                               request_digest="a" * 64, target_locale="en-GB", title="Geprüfte eigene Wörter",
                               source_revisions=[{"id": material_id, "revision": material.revision}],
                               pairs=[{"word": "apple", "meaning": "Apfel"}], status="review")
        db.add(row)
        db.flush()
        import_id = row.id
    response = api.post(f"/api/children/{child['id']}/vocabulary/imports/{import_id}/confirm",
                        json={"pairs": [{"word": "apple", "meaning": "Apfel"}], "target_locale": "en-GB", "language_confirmed": True})
    assert response.status_code == 200, response.text
    from schulpilot.db import VocabularyItem

    with DB() as db:
        assert db.scalar(select(VocabularyItem)).origin == "manual"
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_all_excluded_sources_raise_without_mutating_literal_text():
    material = SimpleNamespace(id="a" * 32, revision=1, purpose="notebook", confirmed=True, legibility="readable",
                               content="1+1=3", source_blocks=[blocked()], uncertainties=[])
    with pytest.raises(UnusableSources):
        project(None, [material])
    assert material.content == "1+1=3"


def test_homework_task_cannot_reintroduce_excluded_original_after_safe_tutor_projection(tutor_notebook, transport):
    from test_homework import TEXT, analyze
    from test_homework import ask as homework_ask

    analysis_id = analyze(tutor_notebook, transport)
    with DB.begin() as db:
        material = db.get(Material, tutor_notebook["material_id"])
        set_blocks(material, [blocked(TEXT), {"kind": "paragraph", "text": "Die Fläche beschreibt eine Größe."}])
        before_usage = db.scalar(select(func.count()).select_from(Usage))
    response = homework_ask(tutor_notebook, "explain", analysis=analysis_id)
    assert response.status_code == 409, response.text
    assert len(transport["calls"]) == 1
    from schulpilot.db import TutorTurn

    with DB() as db:
        assert db.get(TutorTurn, analysis_id).reply["tasks"][0]["source_quote"] == TEXT
        assert db.scalar(select(func.count()).select_from(Usage)) == before_usage
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0


@pytest.mark.parametrize("entered", [False, True])
def test_source_preflight_only_cancels_before_actual_provider_function_entry(entered):
    from schulpilot.learning_sources import failure_billing
    from schulpilot.providers import Result

    assert (failure_billing(None, ValueError("guard"), provider_requested=entered) is None) is entered
    reported = Result({}, 11, 13, 17)
    assert failure_billing(reported, ValueError("guard"), provider_requested=False) is reported
    error = ProviderError("Guard nach Rückgabe")
    error.billing_result = reported
    assert failure_billing(None, error, provider_requested=False) is reported


def test_explicit_reading_confirmation_is_current_literal_bound_not_factual_validation(api, tutor_notebook):
    from schulpilot.source_lineage import learning_source, usable_source
    from schulpilot.source_lineage_models import SourceRevision

    with DB.begin() as db:
        material = db.get(Material, tutor_notebook["material_id"])
        blocks = [{"kind": "paragraph", "text": "Die Sonne ist ein Stern.", "reading_uncertainties": ["Stern prüfen"]},
                  blocked(), blocked("2+2=4")]
        set_blocks(material, blocks)
        material.uncertainties = ["Lesestelle prüfen"]
        assert not usable_source(db, material)
        body = {"subject": material.subject, "topic": material.topic, "content": material.content,
                "revision": material.revision, "homework": [], "uncertainties_resolved": True}
    route = f"/api/materials/{tutor_notebook['material_id']}/confirm"
    response = api.put(route, json=body)
    assert response.status_code == 200, response.text
    with DB() as db:
        material = db.get(Material, tutor_notebook["material_id"])
        safe = learning_source(db, material)
        assert safe["content"] == blocks[0]["text"]
        assert safe["reading_status"] == "explicitly_confirmed"
        assert {row["reason"] for row in safe["exclusions"]} == {"false_equality", "student_work"}
        assert material.uncertainties == ["Lesestelle prüfen"]
        assert material.source_blocks == blocks
        confirmations = db.scalar(select(func.count()).select_from(SourceRevision).where(SourceRevision.cause == "confirmation"))
    assert api.put(route, json=body).status_code == 200
    with DB.begin() as db:
        assert db.scalar(select(func.count()).select_from(SourceRevision).where(SourceRevision.cause == "confirmation")) == confirmations
        material = db.get(Material, tutor_notebook["material_id"])
        # A retained older marker must not acknowledge newly changed bytes.
        material.content = "Anderer Text ohne neue Bestätigung."
        material.source_blocks = []
        assert not usable_source(db, material)
        assert learning_source(db, material)["reading_status"] == "unresolved"


def test_literal_source_transport_keeps_critical_math_signs_and_wrong_originals_distinct():
    from schulpilot.subject_content import SourceBlock

    literals = [r"3 \mid 6", r"3 \nmid 5", r"5\frac{2}{3}=\frac{17}{3}", "7⅗=38/5", "9²⁄₇=65/7",
                "V31=31;62;93;114;145", "124;155", "CO ≠ Co", "2⁴", "2,4", "2/4"]
    blocks = [SourceBlock(kind="formula", text=text).model_dump()["text"] for text in literals]
    assert blocks == literals and len(set(blocks)) == len(literals)


def test_legacy_tutor_source_without_alias_stays_readable_but_cannot_invent_one(tutor_notebook):
    from schulpilot.learning_sources import citations_current

    child, material_id = tutor_notebook["child"], tutor_notebook["material_id"]
    with DB() as db:
        material = db.get(Material, material_id)
        refs = [{"id": material.id, "revision": material.revision}]
        assert citations_current(db, child["id"], refs, [])
        assert not citations_current(db, child["id"], refs, [{"ref": "p1", "quote": material.content}])
        assert not citations_current(db, child["id"], [{"id": material.id}], [])
