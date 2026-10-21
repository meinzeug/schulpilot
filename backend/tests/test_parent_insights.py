"""Artificial parent evidence, real permissions, durable jobs and accounting."""

import copy
import uuid

import pytest
from schulpilot import parent_insights, providers, worker
from schulpilot.db import (
    DB,
    Assignment,
    Attempt,
    Child,
    Job,
    LearningUnit,
    Material,
    ParentLearningReview,
    Session,
    Usage,
)
from schulpilot.synthetic import sample_unit
from sqlalchemy import func, select
from test_tutor import notebook as _notebook


@pytest.fixture
def book(api, household):
    yield from _notebook.__wrapped__(api, household)


def seed(book):
    with DB.begin() as db:
        unit = db.get(LearningUnit, book["unit_id"])
        unit.subject, unit.topic = "Mathematik", "Bruchaddition"
        unit.questions = [{"id": f"q{i}", "type": "short", "prompt": f"Künstliche Frage {i}", "answer": "1/2",
                           "accepted": [], "options": [], "hints": ["Künstlicher Hinweis"], "explanation": "Künstliches Beispiel."} for i in range(3)]
        for i, outcome in enumerate(("incorrect", "correct", "uncertain")):
            db.add(Attempt(unit_id=unit.id, question_id=f"q{i}", answer="PRIVATE-SYNTHETIC-ANSWER", outcome=outcome,
                           assisted=i == 1, evaluation={"method": "synthetic"}))
    return unit.id


def endpoint(book):
    return f"/api/children/{book['child']['id']}/parent-insights"


def request(api, book, key=None):
    return api.post(endpoint(book) + "/review", headers={"Idempotency-Key": key or uuid.uuid4().hex})


def finish():
    with DB() as db:
        job = worker.claim(db)
    assert job
    worker.process(job)


@pytest.fixture
def transport(monkeypatch):
    data = {"calls": [], "effect": None, "invalid": None}
    def call(config, function, payload):
        assert function == "decision"
        data["calls"].append(copy.deepcopy(payload))
        if data["effect"]:
            data["effect"]()
        ref = payload["topics"][0]["ref"]
        out = {"summary": "Hier sind gespeicherte Übungen und nächste Prüfschritte.",
            "findings": [{"topic_ref": ref, "need": "support", "interpretation": "Bei diesem Thema wurde Unterstützung gebraucht.",
                          "next_check": "Eine neue ähnliche Aufgabe ohne Hinweis versuchen."}],
            "plan": [{"topic_ref": ref, "action": "explain", "purpose": "Die Bedeutung der Bruchteile mit einem Beispiel klären.",
                      "expected_result": "Den nächsten Rechenschritt selbst erklären."}]}
        if data["invalid"]:
            data["invalid"](out)
        return providers.Result(out, 100, 150, 37)
    monkeypatch.setattr(providers, "request_provider", call)
    return data


def test_reads_are_pure_and_reports_preserve_observations(api, book, transport):
    seed(book)
    for _ in range(2):
        data = api.get(endpoint(book)).json()
        assert data["totals"]["practiced_tasks"] == 3
        assert data["topics"][0]["assisted_tasks"] == data["topics"][0]["uncertain_tasks"] == 1
        assert data["latest"] is None and not data["settings"]["enabled"]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
    key = uuid.uuid4().hex
    start = request(api, book, key)
    assert start.status_code == 202, start.text
    assert request(api, book, key).json()["id"] == start.json()["id"]
    finish()
    latest = api.get(endpoint(book)).json()
    assert latest["latest"]["status"] == "ready" and not latest["stale"]
    assert latest["latest"]["observations"]["totals"]["needs_practice_tasks"] == 1
    assert request(api, book).json()["id"] == start.json()["id"]
    assert len(transport["calls"]) == 1
    assert "PRIVATE-SYNTHETIC-ANSWER" not in str(transport["calls"])
    assert book["child"]["id"] not in str(transport["calls"])
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Attempt)) == 3
        assert db.scalar(select(Usage)).cost_micros == 37


def test_child_cannot_read_or_configure_private_parent_analysis(api, book):
    for method, suffix, body in [("GET", "", None), ("PUT", "/settings", {"revision": 0, "enabled": True}), ("POST", "/review", None)]:
        response = book["client"].request(method, endpoint(book) + suffix, json=body, headers={"Idempotency-Key": uuid.uuid4().hex})
        assert response.status_code == 403
    assert book["client"].get(f"/api/children/{book['child']['id']}/learning-plan").status_code == 403


@pytest.mark.parametrize("damage", ["foreign_ref", "unsupported_error", "changed_source", "revoked", "quota", "unwanted_exercises"])
def test_rejects_unproved_or_stale_analysis_without_retries(api, book, transport, damage):
    seed(book)
    if damage == "quota":
        from schulpilot.db import Family
        with DB.begin() as db:
            db.get(Family, book["family_id"]).budget_micros = 0
        assert request(api, book).status_code == 429
        assert not transport["calls"]
        return
    if damage == "foreign_ref":
        transport["invalid"] = lambda out: out["findings"][0].update(topic_ref="foreign-topic")
    if damage == "unwanted_exercises":
        transport["invalid"] = lambda out: out.update(summary="Aufgabe 1: Rechne 4 + 3. Antwort: 7.")
    if damage == "unsupported_error":
        with DB.begin() as db:
            for a in db.scalars(select(Attempt)):
                a.outcome = "uncertain"
        transport["invalid"] = lambda out: out["findings"][0].update(need="practice")
    if damage in ("changed_source", "revoked"):
        def effect():
            with DB.begin() as db:
                if damage == "changed_source":
                    db.get(Material, book["material_id"]).revision += 1
                else:
                    review = db.scalars(select(ParentLearningReview)).first()
                    job = db.get(Job, review.job_id)
                    db.get(Session, job.payload["session_id"]).revoked = True
        transport["effect"] = effect
    response = request(api, book)
    assert response.status_code == 202, response.text
    finish()
    with DB() as db:
        row = db.get(ParentLearningReview, response.json()["id"])
        assert row.status == "failed" and row.report is None
        assert db.get(Job, row.job_id).attempts == 1
        assert db.scalar(select(Usage)).cost_micros == 37
    assert len(transport["calls"]) == 1
    with DB() as db:
        assert worker.claim(db) is None


def test_explicit_daily_grant_survives_logout_and_never_repeats_same_evidence(api, book, transport):
    seed(book)
    assert api.put(endpoint(book) + "/settings", json={"revision": 0, "enabled": True}).status_code == 200
    assert api.put(endpoint(book) + "/settings", json={"revision": 0, "enabled": False}).status_code == 409
    assert api.post("/api/auth/logout").status_code == 200
    assert parent_insights.schedule_one()
    finish()
    assert not parent_insights.schedule_one()
    assert len(transport["calls"]) == 1
    with DB.begin() as db:
        child = db.get(Child, book["child"]["id"])
        child.parent_review_settings = {**child.parent_review_settings, "last_attempt": 1}
    assert not parent_insights.schedule_one()  # no new data despite elapsed interval


def test_disabled_grant_before_dispatch_has_no_provider_call_and_known_zero_cost(api, book, transport):
    seed(book)
    assert api.put(endpoint(book) + "/settings", json={"revision": 0, "enabled": True}).status_code == 200
    assert parent_insights.schedule_one()
    assert api.put(endpoint(book) + "/settings", json={"revision": 1, "enabled": False}).status_code == 200
    finish()
    assert not transport["calls"]
    with DB() as db:
        assert db.scalar(select(Usage)).cost_micros == 0


def test_manual_topic_creation_is_idempotent_revision_bound_and_can_prepare_once(api, book, monkeypatch):
    calls = []
    def generate(config, function, payload, *args, **kwargs):
        calls.append(payload)
        data = sample_unit(0)
        data["subject"], data["topic"] = payload["required_subject"], payload["required_topic"]
        return providers.Result(data, 50, 100, 42)
    monkeypatch.setattr(worker, "request_provider", generate)
    uri = f"/api/children/{book['child']['id']}/assignments"
    body = {"subject": "Mathematik", "topic": "Bruchaddition", "note": "Brüche mit gleichem Nenner addieren.", "mandatory": True}
    key = uuid.uuid4().hex
    first = api.post(uri, json=body, headers={"Idempotency-Key": key})
    assert first.status_code == 201, first.text
    assert api.post(uri, json=body, headers={"Idempotency-Key": key}).json()["id"] == first.json()["id"]
    assert api.post(uri, json={**body, "topic": "Anderes"}, headers={"Idempotency-Key": key}).status_code == 409
    aid = first.json()["id"]
    prepare = uri + "/" + aid + "/prepare"
    job_key = uuid.uuid4().hex
    result = api.post(prepare, headers={"Idempotency-Key": job_key})
    assert result.status_code == 202, result.text
    finish()
    assert calls[0]["parent_topic"] and calls[0]["material"] is None
    assert api.post(prepare, headers={"Idempotency-Key": job_key}).json()["id"] == result.json()["id"]
    existing = api.post(prepare, headers={"Idempotency-Key": uuid.uuid4().hex})
    assert existing.status_code == 202 and existing.json()["kind"] == "unit", existing.text
    assert len(calls) == 1
    edited = api.put(uri + "/" + aid, json={**body, "revision": 1, "note": "Geänderter Elternauftrag"})
    assert edited.status_code == 200 and edited.json()["revision"] == 2
    assert api.put(uri + "/" + aid, json={**body, "revision": 1}).status_code == 409
    with DB() as db:
        assert db.get(LearningUnit, existing.json()["id"]).goal_revision == 1
        assert db.scalar(select(func.count()).select_from(Assignment)) == 1


def test_saved_ai_priority_changes_order_but_preserves_parent_dates_and_started_work(api, book, transport):
    from datetime import date

    from schulpilot.daily_planner import distribute
    from schulpilot.schemas import Preferences

    seed(book)
    assert request(api, book).status_code == 202
    finish()
    def candidate(id, topic="Bruchaddition", **kw):
        return {"id": id, "topic": topic, "subject": "Mathematik", "kind": "unit", "status": "ready", "estimated_minutes": 5, **kw}
    with DB() as db:
        child = db.get(Child, book["child"]["id"])
        values = [candidate("a", "Anderes Thema"), candidate("z"), candidate("started", "Anderes Thema", status="active"),
            candidate("parent", "Anderes Thema", mandatory=True, due="2026-10-21"),
            candidate("future", scheduled_for="2026-10-25")]
        assert parent_insights.apply_guidance(db, child, values)
        assert values[1]["planning_source"] == "ai_priority"
        output = distribute(values, Preferences(weekdays=list(range(7)), daily_minutes=30), date(2026, 10, 21))
        assert [v["id"] for v in output["today"]] == ["parent", "started", "z", "a"]
        assert not any(k.startswith("_") for k in output["today"][2])
    before = len(transport["calls"])
    for _ in range(2):
        assert api.get(f"/api/children/{book['child']['id']}/learning-plan").json()["ai_guidance"]
    assert len(transport["calls"]) == before
    with DB.begin() as db:
        db.get(Material, book["material_id"]).revision += 1
    assert api.get(endpoint(book)).json()["stale"]
    assert not api.get(f"/api/children/{book['child']['id']}/learning-plan").json()["ai_guidance"]


def test_daily_report_needs_new_practice_and_unrelated_upload_does_not_trigger_paid_rework(api, book, transport):
    seed(book)
    assert api.put(endpoint(book) + "/settings", json={"revision": 0, "enabled": True}).status_code == 200
    assert parent_insights.schedule_one()
    finish()
    with DB.begin() as db:
        child = db.get(Child, book["child"]["id"])
        child.parent_review_settings = {**child.parent_review_settings, "last_attempt": 1}
        db.add(Material(child_id=child.id, title="Weiteres künstliches Foto", purpose="homework"))
        unit = db.get(LearningUnit, book["unit_id"])
        unit.active_seconds += 60
        unit.status = "paused"  # time/status alone is not new learning evidence
    assert not parent_insights.schedule_one()
    with DB.begin() as db:
        db.add(Attempt(unit_id=book["unit_id"], question_id="q0", answer="1/2", outcome="correct", assisted=True))
    assert parent_insights.schedule_one()
    finish()
    assert len(transport["calls"]) == 2
    assert not parent_insights.schedule_one()


def test_provider_outage_keeps_reserved_cost_and_has_no_automatic_retry(api, book, monkeypatch):
    seed(book)
    def outage(*args):
        raise providers.ProviderError("Künstlicher Providerausfall")
    monkeypatch.setattr(providers, "request_provider", outage)
    assert request(api, book).status_code == 202
    finish()
    with DB() as db:
        usage = db.scalar(select(Usage))
        assert usage.cost_micros is None and usage.reserved_micros > 0
        assert worker.claim(db) is None
    assert not parent_insights.schedule_one()
    assert api.get(endpoint(book)).json()["latest_attempt"]["status"] == "failed"


def test_report_export_erasure_and_private_homework_reading(api, book, transport, monkeypatch):
    from schulpilot.families import export_child
    from schulpilot.unit_erasure import remove
    from test_homework import analyze, detail
    from test_tutor import transport as tutor_transport

    seed(book)
    assert request(api, book).status_code == 202
    finish()
    with DB() as db:
        exported = export_child(db, db.get(Child, book["child"]["id"]))
        assert exported["parent_learning_reviews"][0]["report"]["findings"]
    hwtransport = tutor_transport.__wrapped__(monkeypatch)
    aid = analyze(book, hwtransport)
    route = f"/api/materials/{book['material_id']}/homework"
    value = {"revision": 0, "source_revision": detail(book)["material"]["revision"], "request_key": uuid.uuid4().hex,
        "analysis_id": aid, "task_id": "t1", "draft": "PRIVATE UNSENT", "drafts": {"t1": "PRIVATE UNSENT"},
        "question": "PRIVATE QUESTION", "done": ["t1", "t1"]}
    assert book["client"].put(route, json=value).status_code == 200
    listing = f"/api/children/{book['child']['id']}/homework-review"
    assert book["client"].get(listing).status_code == 403
    for _ in range(2):
        data = api.get(listing + "?state=worked").json()
        assert data["total"] == 1 and data["photos"][0]["marked_done"] == 1
        assert "PRIVATE" not in str(data)
        assert "draft" not in api.get(route).json()["state"]
    assert api.get(listing + "?state=open").json()["total"] == 0
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 2
    with DB.begin() as db:
        remove(db, db.get(Child, book["child"]["id"]), [book["unit_id"]])
    assert api.get(endpoint(book)).json()["latest"] is None


def test_existing_round_topic_keeps_all_confirmed_source_revisions(api, book):
    from schulpilot.db import UnitSource

    with DB.begin() as db:
        second = Material(child_id=book["child"]["id"], title="Künstliche zweite Seite", subject="Mathematik", topic="Bruchaddition", content="Künstliche zweite Seite.", confirmed=True)
        db.add(second)
        db.flush()
        db.add(UnitSource(unit_id=book["unit_id"], material_id=second.id, revision=second.revision))
    uri = f"/api/children/{book['child']['id']}/assignments"
    body = {"subject": "Mathematik", "topic": "Bruchaddition", "source_unit_id": book["unit_id"]}
    created = api.post(uri, json=body, headers={"Idempotency-Key": uuid.uuid4().hex})
    assert created.status_code == 201, created.text
    a = created.json()
    assert len(a["source_revisions"]) == 2
    edited = api.put(uri + "/" + a["id"], json={**body, "material_id": a["material_id"], "revision": 1, "note": "Neuer Termin, beide Quellen behalten."})
    assert edited.status_code == 200, edited.text
    assert len(edited.json()["source_revisions"]) == 2
    with DB.begin() as db:
        db.get(Material, book["material_id"]).revision += 1
    bad = api.post(uri, json=body, headers={"Idempotency-Key": uuid.uuid4().hex})
    assert bad.status_code == 409


def test_view_permission_and_admin_cannot_manage_or_access_private_reports(api, book, transport):
    from schulpilot.db import Membership, User

    seed(book)
    with DB.begin() as db:
        membership = db.scalar(select(Membership).where(Membership.family_id == book["family_id"]))
        membership.permission = "view"
    assert api.get(endpoint(book)).status_code == 200
    assert request(api, book).status_code == 403
    assert api.put(endpoint(book) + "/settings", json={"enabled": True, "revision": 0}).status_code == 403
    uri = f"/api/children/{book['child']['id']}"
    assert api.post(uri + "/assignments", json={"subject": "Mathematik", "topic": "Brüche"}).status_code == 403
    assert api.get(uri + "/learning-plan").json()["can_manage"] is False
    with DB.begin() as db:
        db.get(User, book["parent"]["id"]).role = "admin"
    for route in (endpoint(book), uri + "/learning-plan", uri + "/homework-review"):
        assert api.get(route).status_code == 403
    assert not transport["calls"]


def test_actual_openrouter_parent_prompt_has_no_task_generation_instructions(api, book, monkeypatch):
    import json

    import httpx
    from schulpilot.db import ProviderConfig
    from test_free_standard import free_config

    seed(book)
    free_config(book["parent"])
    with DB() as db:
        payload = parent_insights.facts(db, db.get(Child, book["child"]["id"]))[1]
        config = db.get(ProviderConfig, 1)
    payload.pop("_basis")
    ref = payload["topics"][0]["ref"]
    output = {"summary": "Die bisherigen Übungsbelege sprechen für eine gezielte nächste Überprüfung.",
        "findings": [{"topic_ref": ref, "need": "support", "interpretation": "Unterstützung wurde genutzt.", "next_check": "Eine neue eigene Anwendung prüfen."}],
        "plan": [{"topic_ref": ref, "action": "practice", "purpose": "Selbst anwenden lassen.", "expected_result": "Eine neue eigene Antwort."}]}
    requests = []
    class Client:
        def __init__(self, **kwargs): pass
        def __enter__(self): return self
        def __exit__(self, *args): pass
        def post(self, url, headers, json):
            requests.append(json)
            return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {"content": __import__("json").dumps(output)}}],
                "usage": {"prompt_tokens": 100, "completion_tokens": 100, "cost": 0}})
    monkeypatch.setattr(providers, "verify_free_endpoint", lambda *a: None)
    monkeypatch.setattr(providers.httpx, "Client", Client)
    assert providers.request_provider(config, "decision", payload).data == output
    instructions = json.dumps(requests[0]["messages"][0], ensure_ascii=False)
    assert "GENAU 2 Aufgaben" not in instructions and "AUSGABEFORMAT FÜR AUSWAHLAUFGABEN" not in instructions
    schema = requests[0]["response_format"]["json_schema"]["schema"]
    finding = schema["properties"]["findings"]["items"]["anyOf"][0]["properties"]
    assert finding["topic_ref"]["enum"] == [ref]
    assert finding["need"]["enum"] == ["practice", "support", "assessment_open"]


def test_selected_historical_report_stays_in_picker_beyond_the_latest_twelve(api, book):
    seed(book)
    with DB.begin() as db:
        signature = parent_insights.facts(db, db.get(Child, book["child"]["id"]))[0]
        old_id = uuid.uuid4().hex
        for n in range(14):
            db.add(ParentLearningReview(id=old_id if n == 0 else uuid.uuid4().hex, child_id=book["child"]["id"],
                family_id=book["family_id"], signature=signature, status="ready", observations={},
                report={"summary": "Künstliche historische Einschätzung", "findings": [], "plan": []}, created=n+1, finished=n+1))
    ordinary = api.get(endpoint(book)).json()
    assert len(ordinary["history"]) == 12 and old_id not in {r["id"] for r in ordinary["history"]}
    historical = api.get(endpoint(book), params={"review_id": old_id}).json()
    assert historical["latest"]["id"] == old_id
    assert old_id in {r["id"] for r in historical["history"]} and len(historical["history"]) == 13
    assert not historical["plan_applies"]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
