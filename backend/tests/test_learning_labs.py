"""Own finite teaching labs through real validation, disclosure and private APIs."""
import json
from pathlib import Path

import pytest
from pydantic import ValidationError
from schulpilot import learning_labs, providers, subject_content, visual_references
from schulpilot.db import DB, Activity, Attempt, Child, Job, LearningUnit, Material, UnitSource, Usage
from schulpilot.learning_labs import LabV1, checked_view, parse_view, resolve, view_facts
from schulpilot.schemas import UnitOutput
from schulpilot.schulbuddy_graphics import bind
from schulpilot.schulbuddy_schemas import BuddyScope
from schulpilot.security import Principal
from schulpilot.visual_reference_models import UnitVisualPosition, UnitVisualSnapshot
from test_presentation_capability_paths import _config, _submitted, _transport


def block(recipe="physics.force_motion", disclosure="hint1"):
    actual = resolve(recipe)
    params = {"mass_kg": 2, "acceleration_m_s2": 1} if recipe.startswith("physics") else {"example_id": "mira_reads"}
    return {"kind": "lab", "title": "Eigenes kuratiertes Beispiel", "disclosure": disclosure,
        "source_excerpt": actual["content"], "labels": ["Masse" if recipe.startswith("physics") else "Mira"],
        "numbers": [], "connections": [], "marks": [], "unit": "", "variant": "",
        "lab": {"version": 1, "recipe_id": recipe, "recipe_version": 1, "parameters": params}}


def presentation(recipe="physics.force_motion", disclosure="hint1"):
    return {"version": 1, "evidence_kind": "knowledge", "blocks": [block(recipe, disclosure)]}


def step(recipe="physics.force_motion", disclosure="given"):
    return {"id": "e1", "text": resolve(recipe)["content"], "disclosure": disclosure, "competence_id": None,
        "reference": {"id": "lab." + recipe, "version": 1}, "source_refs": ["r1"],
        "presentation": presentation(recipe, disclosure)}


def question(recipe="physics.force_motion", qid="q1"):
    physics = recipe.startswith("physics")
    return {"id": qid, "type": "short", "prompt": "Welche Größe wird betrachtet?" if physics else "Wer liest?",
        "options": [], "answer": "Masse" if physics else "Mira", "accepted": [],
        "hints": ["Betrachte das eigene Beispiel."], "explanation": resolve(recipe)["content"],
        "presentation": presentation(recipe), "explanation_steps": [step(recipe, "solution")]}


def view(recipe="physics.force_motion", **changes):
    result = {"version": 1, "recipe_id": recipe, "recipe_version": 1}
    result.update({"mass_kg": 2, "acceleration_m_s2": 1, "time_ms": 1000} if recipe.startswith("physics") else
        {"order_id": "time_mira_book", "selected_group": "morning", "split_example": False})
    return result | changes


def make_unit(household, recipe="physics.force_motion", enabled=True):
    _, child = household
    subject, topic = ("Physik", "Kraft") if recipe.startswith("physics") else ("Deutsch", "Satzglieder")
    source = resolve(recipe)["content"]
    with DB.begin() as db:
        material = Material(child_id=child["id"], title="Künstliche Laborquelle", subject=subject, topic=topic,
            content=source, uncertainties=[], homework=[], confirmed=True, status="confirmed")
        db.add(material)
        db.flush()
        payload = visual_references.with_visual_context(db, db.get(Child, child["id"]),
            {"material": {"subject": subject, "topic": topic, "content": source}, "labs_enabled": enabled}, [material])
        data = {"subject": subject, "topic": topic, "explanation": source, "explanation_steps": [step(recipe)],
            "questions": [question(recipe), question(recipe, "q2")]}
        unit = LearningUnit(child_id=child["id"], subject=subject, topic=topic, explanation=source,
            questions=data["questions"], provider="synthetic", model="own-test", status="paused")
        db.add(unit)
        db.flush()
        db.add(UnitSource(unit_id=unit.id, material_id=material.id, revision=material.revision))
        if enabled:
            visual_references.remember(db, unit, data, payload)
        return unit.id, material.id, payload, data


@pytest.mark.parametrize("recipe", list(learning_labs.RECIPES))
def test_recipe_contract_real_validation_redaction_and_shared_public_fixture(recipe):
    source, value = resolve(recipe)["content"], presentation(recipe)
    subject = "Physik" if recipe.startswith("physics") else "Deutsch"
    subject_content.validate_question(value, question(recipe), [source], subject_content.PROFILES[subject], subject=subject)
    assert subject_content.public_presentation(value)["blocks"] == []
    public = subject_content.public_presentation(value, hints=1)
    assert public["blocks"][0]["lab"]["recipe_id"] == recipe
    assert "source_excerpt" not in json.dumps(public)
    fixture = json.loads((Path(__file__).parents[2] / "testdata/learning_labs_v1.json").read_text())
    assert fixture["provider_calls"] == 0
    assert any(case["public_presentation"]["blocks"][0]["lab"]["recipe_id"] == recipe for case in fixture["cases"])
    with pytest.raises(ValueError, match="geöffneter Hilfe|geöffnete|geöffnet"):
        subject_content.validate_question(presentation(recipe, "given"), question(recipe), [source],
            subject_content.PROFILES[subject], subject=subject)


@pytest.mark.parametrize("mutation", [
    {"version": 2}, {"version": True}, {"version": 1.0}, {"recipe_version": 2}, {"recipe_version": True}, {"recipe_id": "physics.free_simulation"},
    {"parameters": {"mass_kg": 0.49, "acceleration_m_s2": 1}},
    {"parameters": {"mass_kg": 10.1, "acceleration_m_s2": 1}},
    {"parameters": {"mass_kg": True, "acceleration_m_s2": 1}},
    {"parameters": {"mass_kg": 2, "acceleration_m_s2": float("nan")}},
    {"parameters": {"mass_kg": 2, "acceleration_m_s2": float("inf")}},
    {"parameters": {"mass_kg": 2, "acceleration_m_s2": 1, "code": "not executable"}},
    {"parameters": {"example_id": "mira_reads"}}, {"url": "https://example.invalid"},
])
def test_labs_reject_unknown_or_nonfinite_contract(mutation):
    with pytest.raises(ValidationError):
        LabV1.model_validate(block()["lab"] | mutation)


def test_lab_values_and_recipe_subject_need_exact_unit_source():
    b = block()
    for source in [resolve("physics.force_motion")["content"].replace("m = 2", "m = 12"),
                   resolve("physics.force_motion")["content"].replace("1 m/s²", "1 m/s")]:
        altered = {**b, "source_excerpt": source}
        with pytest.raises(ValueError):
            subject_content.validate_question({"version": 1, "evidence_kind": "knowledge", "blocks": [altered]}, question(), [source, resolve("physics.force_motion")["content"]],
                subject_content.PROFILES["Physik"], subject="Physik")
    with pytest.raises(ValueError, match="Fach"):
        learning_labs.validate(subject_content.Graphic.model_validate(b), question(), [b["source_excerpt"]], subject="Deutsch")


@pytest.mark.parametrize("provider", ["openai", "openrouter", "codex"])
@pytest.mark.parametrize("recipe", list(learning_labs.RECIPES))
def test_real_provider_parse_final_schema_reference_validation_and_projection(monkeypatch, household, recipe, provider):
    _, _, payload, output = make_unit(household, recipe)
    calls = _transport(monkeypatch, provider, output)
    result = providers.request_provider(_config(provider), "unit", payload)
    assert len(calls) == 1
    submitted, schema, system = _submitted(provider, calls[0])
    assert "lab" in schema["$defs"]["Graphic"]["properties"]["kind"]["enum"]
    assert schema["$defs"]["LabV1"]["properties"]["recipe_id"]["enum"] == [recipe]
    assert submitted["content_context"]["lab_recipes"] == {output["subject"]: [recipe]}
    assert "EIGENE LERNLABORE" in system and "source_excerpt" not in json.dumps(result.request_receipt)
    assert result.data["questions"][0]["presentation"]["blocks"][0]["lab"]["recipe_id"] == recipe
    assert _config(provider).max_output_tokens == 4000


def test_legacy_schema_never_offers_labs_or_curated_lab_source(household):
    _, _, payload, _ = make_unit(household, enabled=False)
    assert not any(row["kind"] == "lab" for row in payload["visual_context"]["references"])
    assert not any(row.get("source_type") == "curated_lab" for row in payload["visual_context"]["sources"])
    for subjects in [["Physik"], []]:
        schema = UnitOutput.model_json_schema()
        subject_content.bind_graphic_schema(schema, subjects)
        assert "lab" not in schema["$defs"]["Graphic"]["properties"]["kind"]["enum"]
        assert schema["$defs"]["Graphic"]["properties"]["lab"] == {"type": "null"}
    with pytest.raises(ValueError):
        subject_content.validate_output({"subject": "Physik", "questions": [question()]}, payload)


@pytest.mark.parametrize("recipe", list(learning_labs.RECIPES))
def test_position_and_buddy_use_exact_open_lab_facts_without_learning_evidence(api, household, recipe):
    uid, mid, _, _ = make_unit(household, recipe)
    api.headers["X-Schulpilot-Account"] = household[0]["id"]
    api.headers["X-Schulpilot-Capabilities"] = "visual-v1,labs-v1"
    route = f"/api/units/{uid}/visual-position"
    before = api.get(route).json()
    position = {"explanation_kind": "intro", "question_id": None, "explanation_step_id": "e1",
        "graphic_index": 0, "graphic_phase": "initial", "lab_view": view(recipe)}
    saved = api.put(route, json={"source_signature": before["source_signature"], "revision": 0, "position": position})
    assert saved.status_code == 200, saved.text
    assert saved.json()["position"] == position
    with DB() as db:
        unit = db.get(LearningUnit, uid)
        child = db.get(Child, household[1]["id"])
        from schulpilot.db import User
        user = db.get(User, child.user_id)
        payload = {}
        bind(db, Principal(user, None), BuddyScope(page_kind="learn", unit_id=uid, explanation_kind="intro",
            explanation_step_id="e1", graphic_index=0, graphic_phase="initial", lab_view=json.dumps(view(recipe))), unit, payload)
        facts = payload["current_explanation"]["graphic_state"]
        assert facts["unassessed_exploration"] is True
        if recipe.startswith("physics"):
            assert (facts["force_n"], facts["distance_m"], facts["velocity_m_s"]) == (2, .5, 1)
        else:
            assert facts["groups_in_order"] == ["am Morgen", "liest", "Mira", "ein Buch"]
        assert [db.query(table).count() for table in (Attempt, Activity, Job, Usage)] == [0, 0, 0, 0]
    api.headers["X-Schulpilot-Account"] = "f" * 32
    assert api.get(route).status_code == 409
    with DB.begin() as db:
        db.get(Material, mid).revision += 1
    api.headers["X-Schulpilot-Account"] = household[0]["id"]
    assert api.get(route).json()["position"] is None
    with DB() as db:
        assert db.query(UnitVisualPosition).count() == 1


@pytest.mark.parametrize("change", [{"time_ms": 1}, {"time_ms": 2050}, {"mass_kg": 2.1},
    {"acceleration_m_s2": 1.1}, {"recipe_version": 2}, {"time_ms": True}, {"anything": 1}])
def test_finite_view_rejects_arbitrary_ticks_keys_and_versions(change):
    with pytest.raises(ValueError):
        checked_view(view(**change), block())


def test_view_allows_actual_source_decimal_or_finite_ticks_and_never_claims_answer():
    source = block()
    source["lab"]["parameters"] = {"mass_kg": 2.1, "acceleration_m_s2": 1.1}
    assert checked_view(view(mass_kg=2.1, acceleration_m_s2=1.1), source)["mass_kg"] == 2.1
    assert checked_view(view(mass_kg=2.5, acceleration_m_s2=1.25), source)["mass_kg"] == 2.5
    assert view_facts(view(time_ms=2000), block())["distance_m"] == 2
    assert view_facts(view("german.sentence_shift", split_example=True), block("german.sentence_shift"))["split_example"] == ["am", "Morgen"]
    with pytest.raises(ValueError, match="Doppelte"):
        parse_view('{"version":1,"version":1}')
    with pytest.raises(ValueError):
        parse_view('[]')


def test_saved_labs_require_new_capability_without_modifying_history(api, household):
    uid, _, _, _ = make_unit(household)
    login = api.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"})
    api.headers["Authorization"] = "Bearer " + login.json()["token"]
    assert api.get(f"/api/units/{uid}").status_code == 409
    api.headers["X-Schulpilot-Capabilities"] = "visual-v1,labs-v1"
    got = api.get(f"/api/units/{uid}")
    assert got.status_code == 200, got.text
    assert got.json()["explanation_steps"][0]["presentation"]["blocks"][0]["kind"] == "lab"
    with DB() as db:
        assert db.query(Attempt).count() == db.query(Activity).count() == 0


def test_closed_question_cannot_receive_lab_state_from_intro_or_before_help(api, household):
    uid, _, _, _ = make_unit(household)
    login = api.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"})
    api.headers["Authorization"] = "Bearer " + login.json()["token"]
    api.headers["X-Schulpilot-Account"] = login.json()["user"]["id"]
    route = f"/api/units/{uid}/visual-position"
    current = api.get(route).json()
    position = {"explanation_kind": "question", "question_id": "q1", "explanation_step_id": "e1",
        "graphic_index": 0, "graphic_phase": "initial", "lab_view": view()}
    def put():
        return api.put(route, json={"source_signature": current["source_signature"], "revision": 0, "position": position})
    assert put().status_code == 409
    assert api.post(f"/api/units/{uid}/explanation", json={"question_id": "q1"}).status_code == 200
    assert put().status_code == 200
    with DB() as db:
        assert db.query(Attempt).count() == 0


@pytest.mark.parametrize("enabled", [False, True])
def test_actual_api_queue_worker_provider_and_saved_graphics_retain_origin_capability(api, household, monkeypatch, enabled):
    from schulpilot import worker
    from test_providers import configured

    _, mid, _, output = make_unit(household)
    _config("openai")
    configured(household[0]["families"][0]["id"])
    calls = _transport(monkeypatch, "openai", output)
    headers = {"Idempotency-Key": "own-lab-api-queue-to-worker"}
    if enabled:
        headers["X-Schulpilot-Capabilities"] = "labs-v1,visual-v1"
    sent = api.post(f"/api/children/{household[1]['id']}/units", json={"material_id": mid}, headers=headers)
    assert sent.status_code == 202, sent.text
    job_id = sent.json()["id"]
    replay = api.post(f"/api/children/{household[1]['id']}/units", json={"material_id": mid},
        headers={**headers, "X-Schulpilot-Capabilities": "" if enabled else "labs-v1,visual-v1"})
    assert replay.status_code == 202 and replay.json()["id"] == job_id
    with DB() as db:
        assert db.get(Job, job_id).payload.get("labs_enabled", False) is enabled
        assert worker.claim(db) == job_id
    worker.process(job_id)
    assert len(calls) == 1
    submitted, schema, _ = _submitted("openai", calls[0])
    assert ("lab" in schema["$defs"]["Graphic"]["properties"]["kind"]["enum"]) is enabled
    assert bool(learning_labs.context_sources(submitted, "Physik")) is enabled
    with DB() as db:
        job = db.get(Job, job_id)
        if enabled:
            assert job.status == "completed", job.error
            unit = db.get(LearningUnit, job.result["unit_id"])
            assert unit.questions[0]["answer"] == "Masse"
            assert db.get(UnitVisualSnapshot, unit.id).status == "ready"
        else:
            # A model-emitted unsupported format is rejected, never silently
            # stored as a working old-client lab or invented replacement.
            assert job.status == "failed" and not job.result
            assert db.query(LearningUnit).count() == 1
        assert db.query(Usage).count() == 1 and db.query(Attempt).count() == 0



def test_lab_requires_explicit_own_model_source_instead_of_deriving_motion_from_two_numbers():
    value = block()
    value["source_excerpt"] = "Masse m = 2 kg; Beschleunigung a = 1 m/s²."
    with pytest.raises(ValueError, match="Modellgrundlage"):
        subject_content.validate_question({"version": 1, "evidence_kind": "knowledge", "blocks": [value]}, question(), [value["source_excerpt"]],
            subject_content.PROFILES["Physik"], subject="Physik")
    subject_content.validate_question({"version": 1, "evidence_kind": "knowledge", "blocks": [value]}, question(),
        [value["source_excerpt"], resolve("physics.force_motion")["content"]], subject_content.PROFILES["Physik"], subject="Physik")


def test_buddy_intro_cannot_bypass_pending_entry_probe_redaction(api, household):
    from fastapi import HTTPException
    from schulpilot.db import User
    from schulpilot.source_lineage import learning_source
    from test_learning_entry import payload, saved
    from test_learning_entry import source as entry_source
    from test_visual_references import step as fraction_step

    _, child, mid = entry_source.__wrapped__(api, household)
    with DB.begin() as db:
        content = payload(db, child["id"], mid)
        unit = saved(db, child["id"], mid, content)
        material = db.get(Material, mid)
        safe = learning_source(db, material)
        source = {"material_id": mid, "revision": material.revision, "content": safe["content"], "source_refs": safe["source_refs"]}
        hidden = fraction_step()
        hidden["source_refs"] = [visual_references.source_binding(source)]
        db.add(UnitVisualSnapshot(unit_id=unit.id, source_signature="f" * 64, status="ready", steps=[hidden],
            question_steps={}, source_bindings=[visual_references.source_binding(source)], receipts=[]))
        db.flush()
        user = db.get(User, db.get(Child, child["id"]).user_id)
        scope = BuddyScope(page_kind="learn", unit_id=unit.id, explanation_kind="intro", explanation_step_id="e1", graphic_index=0)
        with pytest.raises(HTTPException) as blocked:
            bind(db, Principal(user, None), scope, unit, {})
        assert blocked.value.status_code == 409
        parent = db.get(User, household[0]["id"])
        preview = {}
        bind(db, Principal(parent, None), scope, unit, preview)
        assert preview["current_explanation"]["step_id"] == "e1"
        assert db.query(Attempt).count() == db.query(Activity).count() == db.query(Usage).count() == 0


def test_late_curriculum_profile_change_rejects_new_unit_but_preserves_existing_history(api, household, monkeypatch):
    from schulpilot import worker
    from test_curriculum import save as save_curriculum
    from test_providers import configured

    save_curriculum(api, household)
    _, mid, _, output = make_unit(household)
    _config("openai")
    configured(household[0]["families"][0]["id"])
    calls = _transport(monkeypatch, "openai", output)
    original = worker.request_provider
    def changed(*args, **kwargs):
        result = original(*args, **kwargs)
        with DB.begin() as db:
            db.get(Child, household[1]["id"]).grade = 7
        return result
    monkeypatch.setattr(worker, "request_provider", changed)
    sent = api.post(f"/api/children/{household[1]['id']}/units", json={"material_id": mid},
        headers={"Idempotency-Key": "lab-stale-curriculum-source", "X-Schulpilot-Capabilities": "labs-v1,visual-v1"})
    assert sent.status_code == 202, sent.text
    with DB() as db:
        job_id = worker.claim(db)
    worker.process(job_id)
    assert len(calls) == 1
    submitted, _, _ = _submitted("openai", calls[0])
    assert submitted["curriculum_context"]["state_code"] == "DE-BY"
    assert submitted["curriculum_context"]["grade"] == 6
    with DB() as db:
        assert db.get(Job, job_id).status == "failed"
        assert db.query(LearningUnit).count() == 1
        assert db.query(Usage).count() == 1 and db.query(Attempt).count() == 0



@pytest.mark.parametrize("provider", ["openai", "openrouter", "codex"])
def test_labs_capability_does_not_offer_empty_recipe_enums_to_other_subjects(monkeypatch, household, provider):
    from test_visual_references import generated_visual_unit
    from test_visual_references import question as fraction_question
    from test_visual_references import step as fraction_step

    _, mid, child_id = generated_visual_unit.__wrapped__(household)
    with DB() as db:
        material = db.get(Material, mid)
        payload = visual_references.with_visual_context(db, db.get(Child, child_id),
            {"material": {"subject": material.subject, "topic": material.topic, "content": material.content},
             "labs_enabled": True}, [material])
    output = {"subject": "Mathematik", "topic": "Brüche", "explanation": material.content,
        "explanation_steps": [fraction_step()], "questions": [fraction_question(), {**fraction_question(), "id": "q2"}]}
    calls = _transport(monkeypatch, provider, output)
    result = providers.request_provider(_config(provider), "unit", payload)
    assert len(calls) == 1 and result.data["subject"] == "Mathematik"
    _, schema, _ = _submitted(provider, calls[0])
    assert "lab" not in schema["$defs"]["Graphic"]["properties"]["kind"]["enum"]
    assert schema["$defs"]["Graphic"]["properties"]["lab"] == {"type": "null"}
    assert "LabV1" not in schema["$defs"]
