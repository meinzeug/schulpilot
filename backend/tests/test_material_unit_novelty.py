"""Normal material rounds use new questions, never rewrite saved answers.

Artificial regular-family/API/worker fixtures only. Run through repository
conftest with a dedicated test database set before importing the application.
"""

import copy
from types import SimpleNamespace

import pytest
from schulpilot import worker
from schulpilot.db import DB, Attempt, Job, LearningUnit, Material, UnitSource, Usage
from schulpilot.providers import ProviderError, Result
from schulpilot.schemas import UnitOutput
from schulpilot.visual_reference_models import UnitVisualSnapshot
from sqlalchemy import func, select
from test_coaching import normal_unit as original_fixture


@pytest.fixture
def book(api, household):
    fixture = original_fixture.__wrapped__(api, household)
    client, unit_id, material_id, parent, child = next(fixture)
    with DB.begin() as db:
        unit = db.get(LearningUnit, unit_id)
        unit.status = "completed"
        for question in unit.questions:
            db.add(Attempt(unit_id=unit.id, question_id=question["id"], answer=question["answer"],
                outcome="correct", assisted=False))
        output = UnitOutput.model_validate({key: getattr(unit, key)
            for key in ("subject", "topic", "explanation", "questions")}).model_dump()
    yield SimpleNamespace(client=client, unit_id=unit_id, material_id=material_id,
        parent=parent, child=child, output=output)
    fixture.close()


def saved_attempts():
    with DB() as db:
        return [(row.id, row.unit_id, row.question_id, row.answer, row.outcome, row.assisted,
            copy.deepcopy(row.evaluation)) for row in db.scalars(select(Attempt).order_by(Attempt.id))]


def generated_counts():
    with DB() as db:
        return tuple(db.scalar(select(func.count()).select_from(model))
            for model in (LearningUnit, UnitSource, UnitVisualSnapshot))


def run(book, monkeypatch, output, *, respond=None, key="material-novelty-request-0001"):
    calls = []

    def model(_config, function, payload, *_args, **_kwargs):
        assert function == "unit"
        calls.append(copy.deepcopy(payload))
        if respond:
            respond(payload)
        # Simulate one normally billed successful adapter response. No HTTP.
        return Result(copy.deepcopy(output), 100, 200, 200, cost_source="reported")

    monkeypatch.setattr(worker, "request_provider", model)
    response = book.client.post(f"/api/children/{book.child['id']}/units",
        json={"material_id": book.material_id}, headers={"Idempotency-Key": key})
    assert response.status_code == 202, response.text
    job_id = response.json()["id"]
    with DB() as db:
        assert worker.claim(db) == job_id
    worker.process(job_id)
    with DB() as db:
        job = db.get(Job, job_id)
        value = {"id": job.id, "status": job.status, "error": job.error, "result": copy.deepcopy(job.result)}
        usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
        value["usage"] = {"status": usage.status, "cost": usage.cost_micros}
    return value, calls


def test_normal_material_round_rejects_old_questions_before_publish(book, monkeypatch):
    before_attempts, before_counts = saved_attempts(), generated_counts()
    repeated = copy.deepcopy(book.output)
    for index, question in enumerate(repeated["questions"]):
        question["id"] = f"new_id_{index}"
    job, calls = run(book, monkeypatch, repeated)
    assert job["status"] == "failed", job
    assert len(calls) == 1
    assert generated_counts() == before_counts
    assert saved_attempts() == before_attempts
    assert job["usage"] == {"status": "failed_billed", "cost": 200}


def fresh_output(book):
    value = copy.deepcopy(book.output)
    value["questions"] = [
        {"id": "new_sum", "type": "choice", "prompt": "Was ergibt 1/7 + 2/7?",
            "options": ["3/7", "3/14", "1/7"], "answer": "3/7", "accepted": [],
            "hints": ["Zähle die Siebtel."], "explanation": "Ein Siebtel und zwei Siebtel ergeben drei Siebtel."},
        {"id": "new_denominator", "type": "short", "prompt": "Wie lautet der Nenner des Bruchs 5/9?",
            "options": [], "answer": "9", "accepted": [], "hints": ["Der Nenner steht unter dem Bruchstrich."],
            "explanation": "Der Nenner des Bruchs 5/9 ist 9."},
    ]
    return UnitOutput.model_validate(value).model_dump()


def add_round(db, book, prompts, *, material=None, day_id=None, subject="Mathematik", child_id=None, created=None):
    unit = LearningUnit(child_id=child_id or book.child["id"], material_id=material.id if material else None,
        school_day_id=day_id, subject=subject, topic="Künstliche gespeicherte Etappe",
        explanation="Eigener künstlicher Übungsstoff.", questions=[
            {"id": f"saved_{i}", "type": "short", "prompt": prompt, "options": [], "answer": "Eigenes Beispiel",
                "accepted": [], "hints": ["Lies die Frage."], "explanation": "Künstliches Beispiel."}
            for i, prompt in enumerate(prompts)], status="not_started", provider="fixture", synthetic=False,
        **({"created": created} if created is not None else {}))
    db.add(unit)
    db.flush()
    if material:
        db.add(UnitSource(unit_id=unit.id, material_id=material.id, revision=material.revision))
    return unit


def test_new_questions_publish_once_and_get_or_post_replay_never_generates(book, monkeypatch):
    before_attempts, before_counts = saved_attempts(), generated_counts()
    output = fresh_output(book)
    job, calls = run(book, monkeypatch, output)
    assert job["status"] == "completed", job
    assert len(calls) == 1
    assert set(q["prompt"] for q in book.output["questions"]) <= set(calls[0]["previous_prompts"])
    assert generated_counts() == tuple(value + 1 for value in before_counts)
    assert saved_attempts() == before_attempts
    assert job["usage"] == {"status": "completed", "cost": 200}
    uid = job["result"]["unit_id"]
    for _ in range(3):
        assert book.client.get(f"/api/units/{uid}").status_code == 200
        assert book.client.get(f"/api/jobs/{job['id']}").json()["status"] == "completed"
    replay = book.client.post(f"/api/children/{book.child['id']}/units", json={"material_id": book.material_id},
        headers={"Idempotency-Key": "material-novelty-request-0001"})
    assert replay.status_code == 202 and replay.json()["id"] == job["id"]
    worker.process(job["id"])
    assert len(calls) == 1
    assert generated_counts() == tuple(value + 1 for value in before_counts)
    assert saved_attempts() == before_attempts


def test_two_new_ids_cannot_publish_the_same_prompt_twice(book, monkeypatch):
    output = fresh_output(book)
    output["questions"][1] = {**output["questions"][0], "id": "another_new_id"}
    before = generated_counts()
    job, calls = run(book, monkeypatch, output)
    assert job["status"] == "failed", job
    assert len(calls) == 1 and generated_counts() == before
    assert job["usage"] == {"status": "failed_billed", "cost": 200}


@pytest.mark.parametrize("change", ["whitespace", "arithmetic_rewording"])
def test_text_or_finite_mathematical_rewording_does_not_repeat_old_questions(book, monkeypatch, change):
    output = fresh_output(book)
    if change == "whitespace":
        output["questions"][0] = {**book.output["questions"][0], "id": "new_id",
            "prompt": "  " + book.output["questions"][0]["prompt"].replace(" ", "  \n ") + "  "}
    else:
        output["questions"][0] = {**book.output["questions"][0], "id": "new_id",
            "prompt": "Neues Übungsbeispiel: Berechne 1/4 + 1/4."}
    before = generated_counts()
    job, calls = run(book, monkeypatch, output)
    assert job["status"] == "failed", job
    assert len(calls) == 1 and generated_counts() == before


def test_history_outside_bounded_provider_context_is_still_checked(book, monkeypatch):
    from schulpilot import unit_novelty
    from schulpilot.db import now

    with DB.begin() as db:
        source = db.get(Material, book.material_id)
        for i in range(100):
            add_round(db, book, [f"Künstliche historische Frage {i}: " + "Ganze eigene Beispielwörter. " * 2],
                material=source, created=int(now()) + 10 + i)
    before = generated_counts()
    output = copy.deepcopy(book.output)
    job, calls = run(book, monkeypatch, output)
    assert job["status"] == "failed", job
    context = calls[0]["previous_prompts"]
    assert len(context) <= unit_novelty.CONTEXT_QUESTIONS
    assert sum(map(len, context)) <= unit_novelty.CONTEXT_CHARACTERS
    assert book.output["questions"][0]["prompt"] not in context
    assert all(prompt.endswith("Ganze eigene Beispielwörter. ") for prompt in context)
    assert generated_counts() == before


@pytest.mark.parametrize("binding", ["day_pointer", "source_link"])
def test_other_same_subject_day_stage_is_excluded_even_outside_selected_source_subset(book, monkeypatch, binding):
    from schulpilot.db import Assignment, SchoolDay

    output = fresh_output(book)
    with DB.begin() as db:
        day = SchoolDay(child_id=book.child["id"], school_date="2026-10-25", stage="ready")
        db.add(day)
        db.flush()
        source = db.get(Material, book.material_id)
        source.school_day_id = day.id
        other = Material(child_id=source.child_id, school_day_id=day.id, subject=source.subject, topic=source.topic,
            title="Künstliche zweite Etappenquelle", content=source.content, confirmed=True, status="confirmed", synthetic=False)
        db.add(other)
        db.flush()
        add_round(db, book, [output["questions"][0]["prompt"]], material=other if binding == "source_link" else None,
            day_id=day.id if binding == "day_pointer" else None)
        assignment = Assignment(child_id=source.child_id, kind="parent", subject=source.subject, topic=source.topic,
            material_id=source.id, source_revisions=[{"id": source.id, "revision": source.revision}])
        db.add(assignment)
        db.flush()
        assignment_id = assignment.id
    before = generated_counts()
    calls = []

    def model(_config, _function, payload, *_a, **_k):
        calls.append(copy.deepcopy(payload))
        return Result(output, 100, 200, 200, cost_source="reported")

    monkeypatch.setattr(worker, "request_provider", model)
    response = book.client.post(f"/api/children/{book.child['id']}/units", json={"assignment_id": assignment_id},
        headers={"Idempotency-Key": "explicit-source-subset-new-unit"})
    assert response.status_code == 202, response.text
    with DB() as db:
        jid = worker.claim(db)
    worker.process(jid)
    with DB() as db:
        job = db.get(Job, jid)
        assert job.status == "failed", job.error
        assert job.payload["sources"] == [{"id": book.material_id, "revision": 1}]
    assert output["questions"][0]["prompt"] in calls[0]["previous_prompts"]
    assert generated_counts() == before


def test_a_newly_saved_question_during_the_call_is_checked_again_before_publish(book, monkeypatch):
    output = fresh_output(book)
    before_attempts = saved_attempts()
    before = generated_counts()

    def another_stage(_payload):
        with DB.begin() as db:
            add_round(db, book, [output["questions"][0]["prompt"]], material=db.get(Material, book.material_id))

    job, calls = run(book, monkeypatch, output, respond=another_stage)
    assert output["questions"][0]["prompt"] not in calls[0]["previous_prompts"]
    assert job["status"] == "failed", job
    assert generated_counts() == (before[0] + 1, before[1] + 1, before[2])
    assert saved_attempts() == before_attempts
    assert len(calls) == 1


def test_source_revision_change_during_the_call_preserves_old_answers_and_discards_output(book, monkeypatch):
    before_attempts, before_counts = saved_attempts(), generated_counts()

    def correction(_payload):
        with DB.begin() as db:
            source = db.get(Material, book.material_id)
            source.revision += 1

    job, calls = run(book, monkeypatch, fresh_output(book), respond=correction)
    assert job["status"] == "failed", job
    assert len(calls) == 1 and generated_counts() == before_counts
    assert saved_attempts() == before_attempts
    assert job["usage"] == {"status": "failed_billed", "cost": 200}


def test_history_uses_current_revision_and_child_scope_with_explicit_legacy_fallback(book, api):
    from conftest import create_child
    from schulpilot import unit_novelty

    other = create_child(api, book.parent, username="artificial-other-child")
    with DB.begin() as db:
        source = db.get(Material, book.material_id)
        # Deliberately malformed legacy link: the outer child guard still must
        # never expose another child's question even if a bad link exists.
        add_round(db, book, ["OTHER CHILD CONTENT MUST NOT LEAVE"], material=source, child_id=other["id"])
        old = add_round(db, book, ["Old source revision only"], material=source)
        db.flush()
        db.get(UnitSource, (old.id, source.id)).revision = source.revision + 1
        add_round(db, book, ["Known legacy pointer exclusion"], material=None).material_id = source.id
    with DB() as db:
        source = db.get(Material, book.material_id)
        prompts = unit_novelty.previous_prompts(db, book.child["id"], [source])
    assert "OTHER CHILD CONTENT MUST NOT LEAVE" not in prompts
    assert "Old source revision only" not in prompts
    assert "Known legacy pointer exclusion" in prompts


def test_case_sensitive_originals_remain_distinct_and_oversized_history_is_not_truncated(book):
    from schulpilot import unit_novelty

    with DB.begin() as db:
        source = db.get(Material, book.material_id)
        source.subject = "Chemie"
        add_round(db, book, ["Beschreibe CO."], material=source, subject="Chemie")
    with DB() as db:
        source = db.get(Material, book.material_id)
        unit_novelty.validate_output(db, book.child["id"], [source],
            {"subject": "Chemie", "questions": [{"prompt": "Beschreibe Co."}]})
        with pytest.raises(ProviderError, match="bereits gestellte Frage"):
            unit_novelty.validate_output(db, book.child["id"], [source],
                {"subject": "Chemie", "questions": [{"prompt": "Beschreibe CO."}]})
    assert unit_novelty.provider_context(["x" * 12_001, "Eine vollständige Frage."]) == ["Eine vollständige Frage."]


def test_demo_and_existing_special_contracts_are_not_reinterpreted_as_new_material_rounds(book):
    from schulpilot import unit_novelty

    with DB() as db:
        source = db.get(Material, book.material_id)
        generic = SimpleNamespace(kind="unit", payload={})
        assert unit_novelty.applies(generic, source)
        for flag in ("review_of", "homework_practice", "exam_round_id", "exam_review_practice"):
            assert not unit_novelty.applies(SimpleNamespace(kind="unit", payload={flag: "existing"}), source)
        assert not unit_novelty.applies(SimpleNamespace(kind="package", payload={}), source)
        source.synthetic = True
        assert not unit_novelty.applies(generic, source)
