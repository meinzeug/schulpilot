"""Synthetic contract data is not evidence of imported official topic coverage."""

import uuid
from concurrent.futures import ThreadPoolExecutor

import pytest
from conftest import HEADERS
from fastapi.testclient import TestClient
from schulpilot import curriculum
from schulpilot.curriculum_models import (
    ChildCurriculumChange,
    ChildCurriculumProfile,
    CurriculumDocument,
    CurriculumTopic,
)
from schulpilot.db import DB, Activity, Child, Job, Usage
from schulpilot.main import app
from sqlalchemy import delete, func, select
from test_codex_models import operator as operator_fixture


@pytest.fixture
def operator():
    yield from operator_fixture.__wrapped__()


def package():
    # Tests use the allowed public portal only to test host binding. These
    # deliberately labelled strings are NOT asserted to be official content.
    return {"version": 1, "documents": [{"id": "synthetic.contract.doc.v1", "state_code": "DE-BY",
        "title": "SYNTHETIC CONTRACT DOCUMENT", "official_url": curriculum.inventory()["DE-BY"]["officialportalURL"],
        "edition": "SYNTHETIC", "effective_from": None, "school_form_label": "Gymnasium",
        "school_form_id": "de-by.gymnasium", "source_status": "version_not_verified", "retrieved": "2026-10-24"}],
        "topics": [{"id": f"synthetic.contract.topic.{index}", "document_id": "synthetic.contract.doc.v1",
            "subject_key": "mathematik", "title": f"SYNTHETIC TOPIC {index}", "grade_kind": "band", "grades": [5, 6],
            "phase_label": None, "section": "SYNTHETIC", "page": None, "quote": "SYNTHETIC", "common_fact_keywords": []}
            for index in range(3)]}


def inject():
    with DB.begin() as db:
        return curriculum.import_catalogue(db, package())


def url(child):
    return f"/api/children/{child['id']}/curriculum-profile"


def headers(parent, key=None):
    return {"X-Schulpilot-Account": parent["id"], "Idempotency-Key": key or uuid.uuid4().hex}


def payload(api, household, **kwargs):
    parent, child = household
    current = api.get(url(child), headers=headers(parent)).json()
    return {"revision": current["revision"], "profile_revision": current["profile_revision"],
        "state_code": "DE-BY", "school_form_id": "de-by.gymnasium", "grade": 6, **kwargs}


def save(api, household, **kwargs):
    parent, child = household
    response = api.put(url(child), headers=headers(parent), json=payload(api, household, **kwargs))
    assert response.status_code == 200, response.text
    return response.json()


def test_catalogue_has_16_inventory_states_without_false_complete_claim(api, household):
    result = api.get("/api/curriculum/catalog")
    assert result.status_code == 200
    value = result.json()
    assert len(value["states"]) == 16 and len({row["code"] for row in value["states"]}) == 16
    assert len(value["subjects"]) == 24 and value["coverage"]["complete"] is False
    assert all(row["coverage"] in ("partial", "sources_only") and row["school_forms_complete"] is False for row in value["states"])
    assert "keine vollständige Abdeckung" in value["notice"]
    assert all(form["id"].startswith(row["code"].lower() + ".") for row in value["states"] for form in row["school_forms"])


def test_legacy_labels_are_preserved_and_never_guessed(api, household):
    parent, child = household
    with DB.begin() as db:
        value = db.get(Child, child["id"])
        value.region, value.school_type = "Sachsen?", "alte unbekannte Schulform"
    for _ in range(2):
        value = api.get(url(child), headers=headers(parent)).json()
        assert value["revision"] == 0 and value["state_code"] is None and value["school_form_id"] is None
        assert value["configured"] is False and value["legacy_region"] == "Sachsen?"
        assert value["legacy_school_type"] == "alte unbekannte Schulform"
    with DB() as db:
        for model in (ChildCurriculumProfile, ChildCurriculumChange, Job, Usage, Activity):
            assert db.scalar(select(func.count()).select_from(model)) == 0


def test_explicit_profile_update_dual_cas_replay_and_no_learning_writes(api, household):
    parent, child = household
    value = payload(api, household)
    key = uuid.uuid4().hex
    result = api.put(url(child), headers=headers(parent, key), json=value)
    assert result.status_code == 200
    current = result.json()
    assert current["configured"] and current["state_code"] == "DE-BY" and current["revision"] == 1
    assert current["profile_revision"] != value["profile_revision"]
    assert api.put(url(child), headers=headers(parent, key), json=value).json() == current
    assert api.put(url(child), headers=headers(parent), json=value).status_code == 409
    assert api.put(url(child), headers=headers(parent, key), json={**value, "grade": 7}).status_code == 409
    with DB() as db:
        stored = db.get(Child, child["id"])
        assert (stored.grade, stored.region, stored.school_type) == (6, "Bayern", "Gymnasium")
        assert db.scalar(select(func.count()).select_from(ChildCurriculumChange)) == 1
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
        assert db.scalar(select(func.count()).select_from(Activity)) == 0


def test_old_child_editor_change_invalidates_new_form_cas_and_binding(api, household):
    parent, child = household
    saved = save(api, household)
    stale = payload(api, household)
    child_value = api.get(f"/api/families/{parent['families'][0]['id']}").json()["children"][0]
    old_body = {key: child_value[key] for key in ("display_name", "grade", "subjects", "school_type", "region")}
    response = api.put(f"/api/children/{child['id']}", json={**old_body, "grade": 7, "region": "neue Freitextregion"})
    assert response.status_code == 200
    assert api.put(url(child), headers=headers(parent), json=stale).status_code == 409
    value = api.get(url(child), headers=headers(parent)).json()
    assert value["revision"] == saved["revision"] and value["grade"] == 7
    assert value["configured"] is False and value["state_binding_stale"] and value["state_code"] is None
    assert value["legacy_region"] == "neue Freitextregion" and value["notice"]


@pytest.mark.parametrize("changes", [{"state_code": "DE-XX"}, {"state_code": "DE-SN", "school_form_id": "de-by.gymnasium"}, {"grade": 0}, {"grade": 14}, {"grade": True}, {"profile_revision": "wrong"}])
def test_invalid_state_school_scope_and_grade_do_not_mutate(api, household, changes):
    parent, child = household
    value = payload(api, household, **changes)
    assert api.put(url(child), headers=headers(parent), json=value).status_code == 422
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(ChildCurriculumProfile)) == 0


def test_unknown_school_form_is_explicit_and_not_inferred(api, household):
    value = save(api, household, school_form_id=None, grade=13)
    assert value["configured"] and value["school_form_id"] is None and value["grade"] == 13


def test_child_can_only_read_own_profile_and_operator_cannot_read_private_profile(api, household, operator):
    parent, child = household
    save(api, household)
    assert operator.get(url(child), headers={"X-Schulpilot-Account": operator.get("/api/auth/me").json()["id"]}).status_code == 403
    with TestClient(app, headers=HEADERS) as kid:
        login = kid.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}).json()
        kid.headers["Authorization"] = "Bearer " + login["token"]
        own_headers = {"X-Schulpilot-Account": login["user"]["id"], "Idempotency-Key": uuid.uuid4().hex}
        response = kid.get(url(child), headers=own_headers)
        assert response.status_code == 200 and response.json()["can_manage"] is False
        assert kid.put(url(child), headers=own_headers, json={"revision": 1, "profile_revision": response.json()["profile_revision"],
            "state_code": "DE-BY", "school_form_id": None, "grade": 7}).status_code == 403
    assert api.get(url(child), headers=headers(parent)).json()["grade"] == 6


def test_cross_tab_actor_claim_prevents_private_read_or_write(api, household):
    _, child = household
    for method in ("get", "put"):
        kwargs = {"json": payload(api, household)} if method == "put" else {}
        assert getattr(api, method)(url(child), **kwargs).status_code == 422
        assert getattr(api, method)(url(child), headers={"X-Schulpilot-Account": "f" * 32,
            "Idempotency-Key": uuid.uuid4().hex}, **kwargs).status_code == 409


def test_import_is_immutable_idempotent_public_only_and_needs_operator(api, household, operator):
    assert api.post("/api/admin/curriculum/import", json=package()).status_code == 403
    first = operator.post("/api/admin/curriculum/import", json=package())
    assert first.status_code == 200, first.text
    assert first.json()["documents_added"] == 1 and first.json()["topics_added"] == 3
    repeat = operator.post("/api/admin/curriculum/import", json=package()).json()
    assert repeat["topics_added"] == 0 and repeat["documents_added"] == 0
    changed = package()
    changed["documents"][0]["edition"] = "changed without new id"
    assert operator.post("/api/admin/curriculum/import", json=changed).status_code == 422
    changed = package()
    changed["topics"][0]["title"] = "changed without new id"
    assert operator.post("/api/admin/curriculum/import", json=changed).status_code == 422
    with DB() as db:
        assert db.get(CurriculumTopic, "synthetic.contract.topic.0").title == "SYNTHETIC TOPIC 0"


@pytest.mark.parametrize("change", ["unknown_subject", "wrong_host", "cross_state_form", "unfounded_exact", "unknown_doc", "markup_url"])
def test_import_rejects_unbound_metadata_atomically(operator, change):
    value = package()
    if change == "unknown_subject":
        value["topics"][0]["subject_key"] = "invented"
    if change == "wrong_host":
        value["documents"][0]["official_url"] = "https://example.invalid/plan"
    if change == "cross_state_form":
        value["documents"][0]["school_form_id"] = "de-sn.gymnasium"
    if change == "unfounded_exact":
        value["topics"][0]["grade_kind"] = "exact"
    if change == "unknown_doc":
        value["topics"][0]["document_id"] = "unknown.doc"
    if change == "markup_url":
        value["documents"][0]["official_url"] = "javascript:alert(1)"
    assert operator.post("/api/admin/curriculum/import", json=value).status_code == 422
    with DB() as db:
        assert db.get(CurriculumDocument, "synthetic.contract.doc.v1") is None


def test_topics_keep_band_and_source_and_cursor_without_get_writes(api, household):
    inject()
    first = api.get("/api/curriculum/topics?state_code=DE-BY&grade=5&query=SYNTHETIC&limit=1").json()
    assert len(first["items"]) == 1 and first["next_cursor"]
    row = first["items"][0]
    assert row["grade_kind"] == "band" and row["grades"] == [5, 6]
    assert row["source"]["section"] == "SYNTHETIC" and row["source"]["status"] == "version_not_verified"
    second = api.get("/api/curriculum/topics", params={"state_code": "DE-BY", "grade": 6, "query": "SYNTHETIC", "limit": 1,
        "cursor": first["next_cursor"]}).json()
    assert second["items"][0]["id"] != row["id"]
    assert api.get("/api/curriculum/topics?grade=7&query=SYNTHETIC").json()["items"] == []
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Activity)) == 0
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_phase_records_have_no_fabricated_grade_and_cross_form_is_not_a_school_option(api, household):
    value = package()
    doc = value["documents"][0]
    doc.update(school_form_id="de-by.schulartuebergreifend", school_form_label="Schulartübergreifend",
        school_form_scope="cross_form")
    value["topics"] = [{**value["topics"][0], "grades": None, "grade_kind": "phase", "phase_label": "Niveaustufe H"}]
    with DB.begin() as db:
        curriculum.import_catalogue(db, value)
    assert api.get("/api/curriculum/topics?query=SYNTHETIC&grade=8").json()["items"] == []
    phase = api.get("/api/curriculum/topics?query=SYNTHETIC&phase=Niveaustufe%20H").json()["items"]
    assert len(phase) == 1 and phase[0]["grades"] is None
    state = next(row for row in api.get("/api/curriculum/catalog").json()["states"] if row["code"] == "DE-BY")
    assert "de-by.schulartuebergreifend" not in {row["id"] for row in state["school_forms"]}


def test_concurrent_profile_edit_allows_one_claim(api, household):
    parent, child = household
    value = payload(api, household)
    token = api.headers["Authorization"]
    def request(grade):
        with TestClient(app, headers={**HEADERS, "Authorization": token}) as client:
            return client.put(url(child), headers=headers(parent), json={**value, "grade": grade}).status_code
    with ThreadPoolExecutor(max_workers=2) as pool:
        assert sorted(pool.map(request, [5, 7])) == [200, 409]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(ChildCurriculumChange)) == 1


def test_child_erasure_removes_private_profile_not_public_curricula(api, household):
    inject()
    save(api, household)
    with DB.begin() as db:
        db.execute(delete(Child).where(Child.id == household[1]["id"]))
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(ChildCurriculumProfile)) == 0
        assert db.scalar(select(func.count()).select_from(ChildCurriculumChange)) == 0
        assert db.get(CurriculumDocument, "synthetic.contract.doc.v1") is not None



def test_planning_context_uses_explicit_profile_and_original_bands_without_evidence(api, household):
    inject()
    # Isolate artificial rows from the real reviewed seed so assertions test
    # selection semantics, never treat synthetic labels as official coverage.
    with DB.begin() as db:
        db.execute(delete(CurriculumTopic).where(~CurriculumTopic.id.startswith("synthetic.")))
    save(api, household)
    with DB() as db:
        child = db.get(Child, household[1]["id"])
        before = (db.query(Activity).count(), db.query(Usage).count(), db.query(Job).count())
        context = curriculum.planning_context(db, child, ["Mathematik"])
        assert len(context["topics"]) == 3
        assert all(row["grade_kind"] == "band" and row["grades"] == [5, 6] for row in context["topics"])
        assert all(row["subject_key"] == "mathematik" for row in context["topics"])
        assert context["coverage"] == "partial" and "Kein Antwortschlüssel" in context["use"]
        assert "SYNTHETIC" in context["topics"][0]["source"]["section"]
        assert not curriculum.planning_context(db, child, ["Biologie"])["topics"]
        assert before == (db.query(Activity).count(), db.query(Usage).count(), db.query(Job).count())
        assert not db.new and not db.dirty
        curriculum.guard_planning_context(db, child, context)
    with DB.begin() as db:
        db.get(Child, household[1]["id"]).grade = 7
    with DB() as db, pytest.raises(ValueError, match="Lehrplanangaben"):
        curriculum.guard_planning_context(db, db.get(Child, household[1]["id"]), context)


def test_unknown_or_stale_profile_does_not_infer_curriculum_from_legacy_region(api, household):
    with DB() as db:
        assert curriculum.planning_context(db, db.get(Child, household[1]["id"]), ["Mathematik"]) is None
    save(api, household, school_form_id=None)
    with DB() as db:
        current = curriculum.planning_context(db, db.get(Child, household[1]["id"]), ["Mathematik"])
        assert current["topics"] == []
    with DB.begin() as db:
        db.get(Child, household[1]["id"]).region = "Sachsen"
    with DB() as db:
        assert curriculum.planning_context(db, db.get(Child, household[1]["id"]), ["Mathematik"]) is None


def test_curriculum_metadata_joins_existing_visual_request_without_becoming_graphic_source(api, household):
    from schulpilot.db import Material
    from schulpilot.visual_references import guard_context, with_visual_context

    inject()
    save(api, household)
    with DB.begin() as db:
        child = db.get(Child, household[1]["id"])
        material = Material(child_id=child.id, title="Künstlich", subject="Mathematik", topic="Brüche",
            content="Ein Bruch 1/2 beschreibt 1 von 2 Teilen.", status="confirmed", confirmed=True)
        db.add(material)
        db.flush()
        value = with_visual_context(db, child, {"material": {"subject": "Mathematik", "content": material.content}}, [material])
        assert value["curriculum_context"]["state_code"] == "DE-BY"
        assert len(value["curriculum_context"]["topics"]) <= 8
        assert len(value["visual_context"]["sources"]) == 1
        assert value["visual_context"]["sources"][0]["material_id"] == material.id
        assert "topics" not in value["visual_context"]["curriculum_binding"]
        guard_context(db, child.id, value["visual_context"])
        child_id = child.id
    with DB.begin() as db:
        db.get(ChildCurriculumProfile, child_id).revision += 1
    with DB() as db, pytest.raises(ValueError, match="Lehrplanangaben"):
        guard_context(db, child_id, value["visual_context"])



def test_topic_search_preserves_german_sharp_s_in_the_actual_title(api, household):
    value = package()
    value["topics"][0]["title"] = "SYNTHETIC Größen und Maße"
    with DB.begin() as db:
        curriculum.import_catalogue(db, value)
    for query in ("SYNTHETIC Größen", "synthetic größen"):
        result = api.get("/api/curriculum/topics", params={"query": query})
        assert result.status_code == 200
        assert [row["id"] for row in result.json()["items"]] == [value["topics"][0]["id"]]
