"""Normal Today material/review API rounds have an unknown pre-call count."""
import copy
import json

import httpx
import pytest
from conftest import create_child
from fastapi import HTTPException
from schulpilot import providers, worker
from schulpilot.db import (
    DB,
    Attempt,
    Family,
    Job,
    LearningUnit,
    Material,
    ProviderConfig,
    UnitSource,
    Usage,
    engine,
    now,
    uid,
)
from schulpilot.material_routing import MESSAGE, extended_output
from schulpilot.model_routing import features_for, job_config
from schulpilot.model_routing import selection as selected_route
from schulpilot.providers import reserve
from sqlalchemy import delete, event, select
from sqlalchemy.orm.attributes import flag_modified
from test_notebook_output_routing import counts, select_source
from test_notebook_output_routing import routed as routed
from test_notebook_practice import notebook as notebook


def selection(book, *, review=False, kind="free"):
    select_source(book, kind)
    with DB.begin() as db:
        old = db.get(LearningUnit, book.old_id)
        old.completed = old.created  # Match the real completed-unit contract.
        for ref in book.refs[1:]:
            db.get(Material, ref["id"]).confirmed = False
        if review:
            page = db.get(Material, book.refs[0]["id"])
            unit = LearningUnit(child_id=page.child_id, material_id=page.id, school_day_id=page.school_day_id,
                subject="Mathematik", topic="Künstliche Wiederholung", explanation="Gespeicherte künstliche Erklärung.",
                questions=[{"id": f"saved{i}", "type": "short", "prompt": f"Gespeicherte künstliche Frage{i}?",
                    "answer": "Künstlicher Altwert", "options": [], "accepted": [], "hints": [], "explanation": "Alter Text."}
                    for i in (1, 2)], status="completed", completed=now(), provider="synthetic", model="own-fixture")
            db.add(unit)
            db.flush()
            db.add(UnitSource(unit_id=unit.id, material_id=page.id, revision=page.revision))
            db.add(Attempt(unit_id=unit.id, question_id="saved1", answer="Eigener künstlicher Wert", outcome="incorrect", assisted=False))
            review_id = unit.id
    return {"material_id": book.refs[0]["id"], "review_of": review_id if review else None}


def post(book, value, key="normal-material-output-request"):
    return book.client.post(f"/api/children/{book.child['id']}/units", json=value, headers={"Idempotency-Key": key})


def test_material_detail_advertises_explicit_source_selection_without_writes(routed):
    material_id = routed.refs[0]["id"]
    with DB() as db:
        before = counts(db)
        subject_id = db.get(Material, material_id).subject_id
    for _ in range(2):
        response = routed.client.get(f"/api/materials/{material_id}")
        assert response.status_code == 200
        assert response.json()["subject_id"] == subject_id
        assert response.json()["supports_notebook_practice"] is True
        assert response.json()["fixed_example"] is False
    with DB() as db:
        assert counts(db) == before


@pytest.mark.parametrize("review", [False, True])
def test_real_today_api_unknown_count_reserves_sol_once_and_preserves_saved_evidence(routed, review):
    value = selection(routed, review=review)
    with DB() as db:
        old = list(db.execute(select(Attempt.id, Attempt.answer, Attempt.outcome, Attempt.assisted)))
        policy = copy.deepcopy(db.get(ProviderConfig, 1).routing_policy)
    first, second = post(routed, value), post(routed, value)
    assert first.status_code == second.status_code == 202 and first.json() == second.json()
    with DB() as db:
        job = db.get(Job, first.json()["id"])
        assert not job.payload.get("notebook_practice") and "question_count" not in job.payload
        before, statements, queries = counts(db), [], []

        def observed(_conn, _cursor, statement, _parameters, _context, _executemany):
            statements.append(statement.lstrip().split()[0].upper())
            queries.append(statement.lower())

        event.listen(engine, "before_cursor_execute", observed)
        try:
            facts = features_for(db, routed.child["id"], job.id)
        finally:
            event.remove(engine, "before_cursor_execute", observed)
        assert statements and set(statements) == {"SELECT"} and not db.new and not db.dirty
        assert not any("learning_units.questions" in query or "learning_units.explanation" in query for query in queries)
        assert counts(db) == before and facts["source_count"] == 1 and facts["sources_known"]
        assert facts["material_extended_output"] is True and facts["notebook_extended_output"] is False
        usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
        bound = job_config(db, job, "unit")
        assert usage.route_snapshot["tier"] == "sol" and usage.route_snapshot["reason"] == "material_graphic_teaching"
        assert usage.reserved_micros == bound.reserve_micros == 250000
        assert bound.max_output_tokens == 8000 and bound.reasoning_effort == "medium"
        assert db.get(ProviderConfig, 1).routing_policy == policy
        assert list(db.execute(select(Attempt.id, Attempt.answer, Attempt.outcome, Attempt.assisted))) == old
        assert before[:2] == [1, 1]
    before = None
    with DB() as db:
        before = counts(db)
    assert routed.client.get("/api/child/home?compact=true").status_code == 200
    with DB() as db:
        assert counts(db) == before


@pytest.mark.parametrize("review,entry,kind,uncertain_other", [(False, True, "free", False), (True, True, "free", False), (False, False, "composition", False), (False, True, "free", True)])
def test_actual_worker_native_schema_uses_full_output_contract_and_reserved_sol(routed, monkeypatch, review, entry, kind, uncertain_other):
    value = selection(routed, review=review, kind=kind)
    if uncertain_other:
        with DB.begin() as db:
            anchor = db.get(Material, routed.refs[0]["id"])
            other = db.get(Material, routed.refs[1]["id"])
            other.school_day_id, other.confirmed = anchor.school_day_id, True
            other.uncertainties = ["Künstliche unklare Lesestelle."]
    if entry:
        routed.client.headers["X-Schulpilot-Capabilities"] = "learning-entry-v1"
    result = post(routed, value)
    assert result.status_code == 202, result.text
    job_id, captures = result.json()["id"], []
    with DB() as db:
        reserved_snapshot = copy.deepcopy(db.scalar(select(Usage).where(Usage.job_id == job_id)).route_snapshot)
    actual_request = worker.request_provider
    decisions = []

    def observe_decision(config, *args, **kwargs):
        decisions.append(copy.deepcopy(selected_route(config)))
        assert selected_route(config) == reserved_snapshot
        return actual_request(config, *args, **kwargs)

    monkeypatch.setattr(worker, "request_provider", observe_decision)
    real = httpx.Client

    class CaptureComplete(BaseException):
        pass

    def handler(request):
        captures.append(json.loads(request.content))
        raise CaptureComplete

    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real(transport=httpx.MockTransport(handler)))
    with DB() as db:
        assert len(db.get(Job, job_id).payload["sources"]) == (2 if uncertain_other else 1)
        assert worker.claim(db) == job_id
    with pytest.raises(CaptureComplete):
        worker.process(job_id)
    assert len(captures) == 1
    assert decisions == [reserved_snapshot]
    sent = captures[0]
    assert sent["max_tokens"] == 8000 and sent["reasoning"]["effort"] == "medium"
    payload = json.loads(sent["messages"][1]["content"][0]["text"])
    assert "notebook_practice" not in payload
    assert {source["material_id"] for source in payload["visual_context"]["sources"] if source.get("material_id")} == {routed.refs[0]["id"]}
    schema = sent["response_format"]["json_schema"]["schema"]
    questions = schema["properties"]["questions"]
    if entry and not review:
        assert payload["learning_entry"]["units"][0]["entry_mode"] != "existing_contract"
        assert questions["minItems"] == questions["maxItems"] and 4 <= questions["maxItems"] <= 5
    else:
        assert questions["minItems"] == questions["maxItems"] == 2
    if review:
        assert payload["review"] is True and payload["learning_entry"]["units"][0]["entry_mode"] == "existing_contract"
    if kind == "composition":
        assert payload["prepared_graphics"]["revision"] == "unit-fraction-composition-1"
    with DB() as db:
        assert db.scalar(select(Usage).where(Usage.job_id == job_id)).route_snapshot["reason"] == "material_graphic_teaching"


def unreserved(book, *, review=False, two_sources=False):
    value = selection(book, review=review)
    with DB.begin() as db:
        page = db.get(Material, book.refs[0]["id"])
        refs = [{"id": page.id, "revision": page.revision}]
        if two_sources:
            other = db.get(Material, book.refs[1]["id"])
            other.confirmed = True
            refs.append({"id": other.id, "revision": other.revision})
            if review:
                db.add(UnitSource(unit_id=value["review_of"], material_id=other.id, revision=other.revision))
        job = Job(child_id=book.child["id"], kind="unit", payload={**value, "material_revision": page.revision, "sources": refs}, idempotency=uid())
        db.add(job)
        db.flush()
        return job.id


@pytest.mark.parametrize("damage", ["revision", "unconfirmed", "foreign", "all_unsafe", "duplicate", "boolean_revision", "missing_anchor", "foreign_review", "active_review", "missing_review", "review_sources", "review_anchor", "anchor_not_in_refs", "null_refs", "object_refs"])
def test_all_sources_and_review_scope_are_current_before_any_reservation(routed, damage):
    review = "review" in damage
    job_id = unreserved(routed, review=review, two_sources=True)
    sibling = create_child(routed.parent_api, routed.parent, "normal-output-sibling") if damage in ("foreign", "foreign_review") else None
    with DB.begin() as db:
        job = db.get(Job, job_id)
        page = db.get(Material, routed.refs[1]["id"])
        if damage == "revision":
            page.revision += 1
        elif damage == "unconfirmed":
            page.confirmed = False
        elif damage == "foreign":
            page.child_id = sibling["id"]
        elif damage == "all_unsafe":
            page.content = ""
            db.get(Material, routed.refs[0]["id"]).content = ""
        elif damage == "duplicate":
            job.payload = {**job.payload, "sources": [*job.payload["sources"], job.payload["sources"][0]]}
        elif damage == "boolean_revision":
            job.payload = {**job.payload, "material_revision": True}
            flag_modified(job, "payload")
        elif damage == "missing_anchor":
            job.payload = {**job.payload, "material_id": uid()}
        elif damage == "foreign_review":
            db.get(LearningUnit, job.payload["review_of"]).child_id = sibling["id"]
        elif damage == "active_review":
            db.get(LearningUnit, job.payload["review_of"]).status = "active"
        elif damage == "missing_review":
            job.payload = {**job.payload, "review_of": uid()}
        elif damage == "review_anchor":
            db.get(LearningUnit, job.payload["review_of"]).material_id = page.id
        elif damage == "anchor_not_in_refs":
            job.payload = {**job.payload, "sources": job.payload["sources"][1:]}
        elif damage in ("null_refs", "object_refs"):
            job.payload = {**job.payload, "sources": None if damage == "null_refs" else {}}
        else:
            job.payload = {**job.payload, "sources": job.payload["sources"][:1]}
    with DB.begin() as db:
        before = counts(db)
        with pytest.raises(HTTPException) as error:
            reserve(db, db.get(Family, routed.parent["families"][0]["id"]), routed.child["id"], job_id, "unit")
        assert error.value.status_code == 409 and error.value.detail == MESSAGE
        assert counts(db) == before and db.scalar(select(Usage)) is None


def test_more_than_one_current_source_is_never_ignored_by_the_route_projection(routed):
    job_id = unreserved(routed, two_sources=True)
    with DB() as db:
        facts = features_for(db, routed.child["id"], job_id)
        assert facts["source_count"] == 2 and facts["sources_known"] and facts["material_extended_output"]
        assert not db.new and not db.dirty


@pytest.mark.parametrize("fake_count", [2, True, "2"])
def test_unrecognized_payload_count_is_not_a_two_question_compiler_contract(routed, fake_count):
    job_id = unreserved(routed)
    with DB.begin() as db:
        job = db.get(Job, job_id)
        job.payload = {**job.payload, "question_count": fake_count}
    with DB() as db:
        assert extended_output(db, routed.child["id"], db.get(Job, job_id)) is True


@pytest.mark.parametrize("key", ["assignment_id", "study_block", "homework_practice", "exam_round_id", "exam_review_practice", "controller_guard", "reprocess_guard"])
def test_specialist_flows_keep_their_own_routing_contracts(routed, key):
    job_id = unreserved(routed)
    with DB.begin() as db:
        job = db.get(Job, job_id)
        job.payload = {**job.payload, key: "own-specialist-fixture"}
    with DB() as db:
        assert extended_output(db, routed.child["id"], db.get(Job, job_id)) is False


def test_valid_legacy_review_without_source_link_rows_keeps_its_own_material_binding(routed):
    value = selection(routed, review=True)
    with DB.begin() as db:
        db.execute(delete(UnitSource).where(UnitSource.unit_id == value["review_of"]))
    response = post(routed, value)
    assert response.status_code == 202, response.text
    with DB() as db:
        job = db.get(Job, response.json()["id"])
        assert job.payload["material_id"] == db.get(LearningUnit, value["review_of"]).material_id
        assert features_for(db, routed.child["id"], job.id)["material_extended_output"] is True
        assert db.scalar(select(Usage).where(Usage.job_id == job.id)).route_snapshot["tier"] == "sol"


def test_mixed_homework_sources_are_outside_this_normal_notebook_hook(routed):
    job_id = unreserved(routed, two_sources=True)
    with DB.begin() as db:
        db.get(Material, routed.refs[1]["id"]).purpose = "homework"
    with DB() as db:
        before = counts(db)
        assert extended_output(db, routed.child["id"], db.get(Job, job_id)) is False
        assert counts(db) == before and not db.new and not db.dirty
