"""Artificial prerequisite probes and actual Attempt references; no model call."""

import copy
import json

import pytest
from schulpilot import competences, learning_entry
from schulpilot.competence_models import CompetenceSource, QuestionCompetence
from schulpilot.db import DB, Activity, Attempt, Child, LearningMemory, LearningUnit, Material, UnitSource, Usage
from schulpilot.learning import unit_data
from schulpilot.learning_controller import decide, projection, source_state
from schulpilot.providers import ProviderError, indexed_choice_schema, request_provider
from schulpilot.schemas import UnitOutput
from schulpilot.subject_registry import identity
from sqlalchemy import func, select
from test_learning_scenes import _config, _transport
from test_model_routing import setup_policy

CONTENT = "Brüche erweitern: Multipliziere Zähler und Nenner mit derselben Zahl. Beispiel: 1/2 = 2/4."


@pytest.fixture
def source(api, household):
    parent, child = household
    with DB.begin() as db:
        material = Material(child_id=child["id"], title="Eigene künstliche Regel", subject="Mathematik",
            subject_id=identity("mathematik"), topic="Brüche erweitern", content=CONTENT, confirmed=True, status="confirmed")
        db.add(material)
        db.flush()
        mid = material.id
    return parent, child, mid


def payload(db, child_id, mid, **kwargs):
    material = db.get(Material, mid)
    return learning_entry.with_learning_entry(db, db.get(Child, child_id), {
        "material": {"subject": material.subject, "topic": material.topic, "content": material.content},
        "required_subject": material.subject, **kwargs}, [material], enabled=True)


def output(value):
    plan = value["learning_entry"]["units"][0]
    count = min(5, max(4, len(plan["probes"]) + 2))
    result = {"subject": plan["subject"], "topic": "Brüche erweitern", "explanation": "GESPEICHERTE EINFÜHRUNG",
        "questions": []}
    for index, spec in enumerate(learning_entry._specs(plan, count)):
        question = {key: spec[key] for key in learning_entry.CORE if key in spec}
        if "type" not in question:
            question.update(type="short", prompt=f"Erweitere {index + 1}/7 mit 2.",
                answer=f"{2 * (index + 1)}/14", options=[], accepted=[])
        question.update(hints=["Vergleiche die gleich großen Teile."], explanation="PRIVATE LÖSUNGSERKLÄRUNG")
        result["questions"].append(question)
    return result


def saved(db, child_id, mid, value, *, status="active"):
    data = output(value)
    learning_entry.validate_entry_output(value, data)
    unit = LearningUnit(child_id=child_id, material_id=mid, subject=data["subject"], topic=data["topic"],
        explanation=data["explanation"], questions=data["questions"], status=status, round_kind="learning", provider="synthetic-fixture")
    db.add(unit)
    db.flush()
    db.add(UnitSource(unit_id=unit.id, material_id=mid, revision=db.get(Material, mid).revision))
    db.flush()
    learning_entry.remember_generated(db, unit, value)
    db.flush()
    return unit


def test_catalogue_is_finite_acyclic_and_unknown_subjects_remain_unbound(source):
    _, child, mid = source
    rows = competences.catalogue()
    assert rows and all(key == row["id"] for key, row in rows.items())
    assert "math.fractions.components" in rows["math.fractions.expand"]["prerequisites"]
    with DB() as db:
        material = db.get(Material, mid)
        assert competences.matches(db, [material], "Unbekanntes Fach") == []
        assert competences.matches(db, [material], "Deutsch") == []
        assert not db.new and not db.dirty
        reference = competences.resolve_reference("math.fractions.meaning", competences.VERSION)
        assert reference and competences.resolve_reference(reference["reference_id"], reference["version"], reference["digest"]) == reference
        assert competences.resolve_reference(reference["reference_id"], reference["version"], "0" * 64) is None


def test_disabled_entry_preserves_old_payload_identity_and_no_rows(source):
    _, child, mid = source
    with DB() as db:
        original = {"material": {"content": CONTENT}}
        assert learning_entry.with_learning_entry(db, db.get(Child, child["id"]), original, [db.get(Material, mid)]) is original
        assert db.scalar(select(func.count()).select_from(QuestionCompetence)) == 0


def test_only_three_short_prerequisites_share_the_normal_five_question_round(source):
    _, child, mid = source
    with DB() as db:
        value = payload(db, child["id"], mid)
        plan = value["learning_entry"]["units"][0]
        assert plan["entry_mode"] == "prerequisite_probe" and len(plan["probes"]) == 3
        assert [item["id"] for item in plan["targets"]] == ["math.fractions.expand"]
        data = output(value)
        assert len(UnitOutput.model_validate(data).questions) == 5
        schema = UnitOutput.model_json_schema()
        indexed_choice_schema(schema)
        learning_entry.bind_entry_schema(schema, value)
        assert schema["properties"]["questions"]["minItems"] == schema["properties"]["questions"]["maxItems"] == 5
        assert all(probe["type"] == "short" for probe in plan["probes"])
        assert len(value["learning_entry"]["references"]) == 3
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


@pytest.mark.parametrize("provider", ["openai", "openrouter", "codex"])
def test_real_provider_parse_keeps_exact_probe_cores_in_one_mock_transport(source, monkeypatch, provider):
    _, child, mid = source
    with DB() as db:
        value = payload(db, child["id"], mid)
    data = output(value)
    calls = []
    _transport(monkeypatch, provider, data, calls)
    result = request_provider(_config(provider), "unit", value)
    assert len(calls) == 1 and len(result.data["questions"]) == 5
    for expected, actual in zip(data["questions"], result.data["questions"], strict=True):
        assert {key: actual[key] for key in learning_entry.CORE} == {key: expected[key] for key in learning_entry.CORE}


@pytest.mark.parametrize("fault", ["answer", "prompt", "missing", "id", "extra", "subject"])
def test_model_cannot_replace_prerequisite_or_question_budget(source, fault):
    _, child, mid = source
    with DB() as db:
        value = payload(db, child["id"], mid)
    data = output(value)
    if fault in ("answer", "prompt", "id"):
        data["questions"][0][fault] = "forged"
    if fault == "missing":
        data["questions"].pop()
    if fault == "extra":
        data["questions"].append({**data["questions"][-1], "id": "extra"})
    if fault == "subject":
        data["subject"] = "Deutsch"
    with pytest.raises(ValueError):
        learning_entry.validate_entry_output(value, data)


@pytest.mark.parametrize("flag", ["review", "study_block", "homework_practice", "exam_preparation", "exam_review_practice"])
def test_existing_exact_generation_contracts_are_not_replanned(source, flag):
    _, child, mid = source
    with DB() as db:
        value = payload(db, child["id"], mid, **{flag: True})
    assert value["learning_entry"]["units"][0]["entry_mode"] == "existing_contract"
    schema = UnitOutput.model_json_schema()
    before = copy.deepcopy(schema)
    learning_entry.bind_entry_schema(schema, value)
    assert schema == before


def test_intro_is_redacted_on_child_projection_but_parent_preview_is_not_evidence(source):
    _, child, mid = source
    with DB.begin() as db:
        value = payload(db, child["id"], mid)
        unit = saved(db, child["id"], mid, value)
        uid = unit.id
    with DB() as db:
        unit = db.get(LearningUnit, uid)
        before = db.query(Attempt).count(), db.query(Activity).count(), db.query(Usage).count()
        public = unit_data(db, unit)
        assert public["explanation"] == "" and public["explanation_steps"] == []
        assert public["learning_session"]["learning_path"]["current_step_id"] == "prior_check"
        assert all("answer" not in question and "hints" not in question for question in public["questions"])
        assert "PRIVATE LÖSUNGSERKLÄRUNG" not in json.dumps(public)
        assert unit_data(db, unit, True)["explanation"] == "GESPEICHERTE EINFÜHRUNG"
        assert before == (db.query(Attempt).count(), db.query(Activity).count(), db.query(Usage).count())
        assert not db.new and not db.dirty


def test_attempts_complete_probe_then_saved_explanation_precedes_application(source):
    _, child, mid = source
    with DB.begin() as db:
        value = payload(db, child["id"], mid)
        unit = saved(db, child["id"], mid, value)
        unit.introduction_seen = True
        probes = value["learning_entry"]["units"][0]["probes"]
        for probe in probes:
            db.add(Attempt(unit_id=unit.id, question_id=probe["id"], answer=probe["answer"], outcome="correct", assisted=False))
        db.flush()
        action, facts = decide(db, unit)
        assert action["kind"] == "explain" and action["reason_code"] == "entry_probe_followup"
        assert unit_data(db, unit)["explanation"] == "GESPEICHERTE EINFÜHRUNG"
        db.add(Activity(child_id=child["id"], unit_id=unit.id, kind="explanation", detail={"question_id": facts["question"]["id"]}))
        db.flush()
        assert decide(db, unit)[0]["kind"] == "practice"
        states = competences.evidence(db, child["id"])
        assert any(row["independent"] for row in states)
        assert not any(row["confidence"] == "repeated_recall" for row in states)


def test_chat_read_media_and_drafts_never_become_competence_evidence(source):
    _, child, mid = source
    with DB.begin() as db:
        unit = saved(db, child["id"], mid, payload(db, child["id"], mid))
        for kind in ("hint", "explanation", "feedback", "introduction"):
            db.add(Activity(child_id=child["id"], unit_id=unit.id, kind=kind, detail={"question_id": unit.questions[0]["id"]}))
        memory = db.get(LearningMemory, unit.id)
        memory.working = {**memory.working, "draft": {"text": "answer"}, "media_return": {"watched": True}}
        db.flush()
        states = competences.evidence(db, child["id"])
        assert all(row["attempts"] == 0 and row["confidence"] == "unverified" for row in states)


def test_same_competence_new_photo_reuses_actual_legacy_attempt_without_rewriting_it(source):
    _, child, mid = source
    with DB.begin() as db:
        question = {"id": "old", "type": "short", "prompt": "Erweitere 1/2 mit 2.", "answer": "2/4",
            "options": [], "accepted": [], "hints": ["Beide Teile."], "explanation": CONTENT}
        unit = LearningUnit(child_id=child["id"], material_id=mid, subject="Mathematik", topic="Brüche", explanation=CONTENT,
            questions=[question], status="completed", provider="synthetic-fixture")
        db.add(unit)
        db.flush()
        db.add(UnitSource(unit_id=unit.id, material_id=mid, revision=1))
        attempt = Attempt(unit_id=unit.id, question_id="old", answer="2/4", outcome="correct", assisted=False)
        db.add(attempt)
        second = Material(child_id=child["id"], subject="Mathematik", subject_id=identity("mathematik"),
            title="Andere neue Seite", topic="Weitere Brüche", content=CONTENT, confirmed=True, status="confirmed")
        db.add(second)
        db.flush()
        old = attempt.id, attempt.created, copy.deepcopy(unit.questions)
        value = payload(db, child["id"], second.id)
        plan = value["learning_entry"]["units"][0]
        assert plan["entry_mode"] == "reuse_evidence" and plan["probes"] == []
        proof = next(row for row in plan["evidence"] if row["id"] == "math.fractions.expand")
        assert proof["evidence_refs"] == ["attempt:" + attempt.id]
        assert (attempt.id, attempt.created, unit.questions) == old
        assert db.query(QuestionCompetence).count() == 0  # Legacy discovery is read-only.
        assert db.query(Attempt).count() == 1


@pytest.mark.parametrize("fault", ["source_revision", "source_quality", "answer_evidence"])
def test_generation_is_rechecked_against_sources_and_new_actual_attempts(source, monkeypatch, fault):
    _, child, mid = source
    with DB.begin() as db:
        value = payload(db, child["id"], mid)
        if fault == "source_revision":
            db.get(Material, mid).revision += 1
        elif fault == "source_quality":
            monkeypatch.setattr(competences, "source_value", lambda *args: None)
        else:
            unit = saved(db, child["id"], mid, value)
            q = unit.questions[0]
            db.add(Attempt(unit_id=unit.id, question_id=q["id"], answer=q["answer"], outcome="correct", assisted=False))
            db.flush()
        with pytest.raises(ValueError):
            learning_entry.guard_entry_context(db, db.get(Child, child["id"]), value, [db.get(Material, mid)])


def test_stage_redaction_and_source_guard_follow_reviewed_source_change(source, monkeypatch):
    _, child, mid = source
    with DB.begin() as db:
        unit = saved(db, child["id"], mid, payload(db, child["id"], mid))
        q = unit.questions[0]
        db.add(Attempt(unit_id=unit.id, question_id=q["id"], answer=q["answer"], outcome="correct", assisted=False))
        db.flush()
        assert competences.evidence(db, child["id"], ["math.fractions.meaning"])[0]["independent"] == 1
        monkeypatch.setattr(competences, "source_value", lambda *args: None)
        assert source_state(db, unit)[1] is False
        assert decide(db, unit)[0]["kind"] == "confirm_source"
        assert competences.evidence(db, child["id"], ["math.fractions.meaning"])[0]["historical_tasks"] == 1


def test_session_capability_and_idempotent_job_survive_client_upgrade(source, api):
    parent, child, mid = source
    setup_policy(parent["families"][0]["id"])
    headers = {"Idempotency-Key": "stable-source-unit-request"}
    url = f"/api/children/{child['id']}/units"
    first = api.post(url, headers=headers, json={"material_id": mid})
    assert first.status_code == 202, first.text
    replay = api.post(url, headers={**headers, "X-Schulpilot-Capabilities": "learning-entry-v1"}, json={"material_id": mid})
    assert replay.status_code == 202 and replay.json() == first.json()
    with DB() as db:
        assert db.query(Usage).count() == 1


def test_bindings_and_private_entry_recipe_export_without_answers_and_cascade(source):
    _, child, mid = source
    with DB.begin() as db:
        unit = saved(db, child["id"], mid, payload(db, child["id"], mid))
        projection_value = projection(db, unit, include_draft=False)
        assert "PRIVATE LÖSUNGSERKLÄRUNG" not in json.dumps(projection_value)
        exported = competences.export_child(db, child["id"])
        assert exported["source_bindings"] and exported["question_bindings"]
        assert "answer" not in json.dumps(exported)
        db.delete(unit)
        db.flush()
        assert db.query(QuestionCompetence).count() == 0
        db.delete(db.get(Material, mid))
        db.flush()
        assert db.query(CompetenceSource).count() == 0


def test_uncertain_probe_closes_workflow_without_claiming_correct_or_mastered(source):
    _, child, mid = source
    with DB.begin() as db:
        unit = saved(db, child["id"], mid, payload(db, child["id"], mid))
        q = unit.questions[0]
        db.add(Attempt(unit_id=unit.id, question_id=q["id"], answer="ungeklärt", outcome="uncertain", assisted=False))
        db.flush()
        path = learning_entry.public_path(db, unit)
        assert path["steps"][0]["status"] == "current"  # Other probe questions remain.
        state = next(row for row in path["competences"] if row["id"] == "math.fractions.meaning")
        assert state["uncertain"] == 1 and state["independent"] == 0
        assert state["confidence"] == "unverified"


def test_explicit_parent_goal_without_photo_keeps_its_existing_contract(source):
    _, child, _ = source
    with DB() as db:
        original = {"goal": {"subject": "Mathematik", "topic": "Brüche", "note": "Bewusstes Elternziel"}}
        assert learning_entry.with_learning_entry(db, db.get(Child, child["id"]), original, [], enabled=True) is original


def test_readonly_parent_receives_no_graphic_prepare_permission(source, api):
    from schulpilot.db import Membership

    _, child, mid = source
    with DB.begin() as db:
        unit = saved(db, child["id"], mid, payload(db, child["id"], mid))
        identifier = unit.id
        db.scalar(select(Membership)).permission = "view"
    response = api.get(f"/api/units/{identifier}")
    assert response.status_code == 200 and response.json()["can_prepare_visual"] is False
    assert response.json()["explanation"] == "GESPEICHERTE EINFÜHRUNG"
    with DB() as db:
        assert db.query(Attempt).count() == db.query(Activity).count() == db.query(Usage).count() == 0


def test_child_requires_compatible_client_before_viewing_new_entry(source, api):
    from conftest import HEADERS
    from fastapi.testclient import TestClient
    from schulpilot.main import app

    _, child, mid = source
    with DB.begin() as db:
        identifier = saved(db, child["id"], mid, payload(db, child["id"], mid)).id
    with TestClient(app, headers=HEADERS) as own:
        login = own.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"})
        assert login.status_code == 200
        own.headers["Authorization"] = "Bearer " + login.json()["token"]
        assert own.get(f"/api/units/{identifier}").status_code == 426
        own.headers["X-Schulpilot-Capabilities"] = "learning-entry-v1"
        response = own.get(f"/api/units/{identifier}")
        assert response.status_code == 200, response.text
        assert response.json()["explanation"] == ""


@pytest.mark.parametrize("entered", [False, True])
def test_only_proven_before_provider_failures_release_reservation(source, api, monkeypatch, entered):
    from schulpilot import worker
    from schulpilot.db import Job, UsageBucket

    parent, child, mid = source
    setup_policy(parent["families"][0]["id"])
    created = api.post(f"/api/children/{child['id']}/units", json={"material_id": mid},
        headers={"Idempotency-Key": "before-after-provider-proof"})
    assert created.status_code == 202, created.text
    calls = []
    def fail(*args, **kwargs):
        calls.append(True)
        raise ProviderError("Künstlicher Fehler nach Funktionseintritt.")
    monkeypatch.setattr(worker, "request_provider", fail)
    with DB.begin() as db:
        if not entered:
            db.get(Material, mid).revision += 1
    with DB() as db:
        identifier = worker.claim(db)
    worker.process(identifier)
    with DB() as db:
        job = db.get(Job, identifier)
        assert job.status == "failed"
        usage = db.scalar(select(Usage).where(Usage.job_id == identifier))
        assert usage.cost_micros == (None if entered else 0)
        assert usage.status == ("failed_unknown" if entered else "failed_not_sent")
        assert db.get(UsageBucket, usage.bucket_ids[0]).unknown_calls == int(entered)
        assert calls == ([True] if entered else [])


def test_completely_excluded_source_is_rejected_before_reserving(source, api):
    parent, child, mid = source
    setup_policy(parent["families"][0]["id"])
    with DB.begin() as db:
        material = db.get(Material, mid)
        material.content = "Sichtbare ungeklärte Schülerlösung."
        material.source_blocks = [{"kind": "paragraph", "text": material.content, "literal_role": "student_work"}]
    response = api.post(f"/api/children/{child['id']}/units", json={"material_id": mid},
        headers={"Idempotency-Key": "excluded-source-no-paid-call", "X-Schulpilot-Capabilities": "learning-entry-v1"})
    assert response.status_code == 409, response.text
    with DB() as db:
        assert db.query(Usage).count() == 0


def test_package_keeps_excluded_group_visible_but_never_reserves_it(source, api):
    from schulpilot.db import Job, SchoolDay
    from schulpilot.learning import local_day
    from schulpilot.school_day import package_plan

    parent, child, mid = source
    setup_policy(parent["families"][0]["id"])
    with DB.begin() as db:
        pupil = db.get(Child, child["id"])
        day = SchoolDay(child_id=child["id"], school_date=local_day(pupil).isoformat(), stage="review")
        db.add(day)
        db.flush()
        db.get(Material, mid).school_day_id = day.id
        bad = Material(child_id=child["id"], school_day_id=day.id, page_number=2, subject="Englisch",
            title="Ungeklärte Quelle", content="Ungeklärte Schülerlösung.", confirmed=True, status="confirmed",
            source_blocks=[{"kind": "paragraph", "text": "Ungeklärte Schülerlösung.", "literal_role": "student_work"}])
        db.add(bad)
        db.flush()
        plan = package_plan(db, day, pupil)
        blocked = next(group for group in plan["groups"] if group["subject"] == "Englisch")
        assert blocked["blocked_reason"] and not blocked["selected"] and not blocked["covered"]
        assert blocked["excluded_sources"][0]["reasons"] == ["student_work"]
        assert any("Englisch" in notice and "ausgeschlossen" in notice for notice in plan["notices"])
        identifier = day.id
    response = api.post(f"/api/school-days/{identifier}/package", headers={"Idempotency-Key": "one-safe-package-group-only", "X-Schulpilot-Capabilities": "learning-entry-v1"})
    assert response.status_code == 202, response.text
    with DB() as db:
        job = db.get(Job, response.json()["id"])
        assert [group["subject"] for group in job.payload["groups"]] == ["Mathematik"]
        assert len(job.payload["sources"]) == 2  # Original revision context retained.
        assert job.payload["learning_entry_enabled"] is True
        assert db.query(Usage).count() == 1
