"""Own artificial source fixtures; no paid calls or claims of model success."""
import copy
import json
import re
from types import SimpleNamespace

import pytest
from schulpilot.db import DB, Base, engine
from schulpilot.provider_receipts import request_receipt
from schulpilot.schemas import Question, UnitOutput
from schulpilot.subject_content import PROFILES
from schulpilot.visual_reference_models import UnitVisualSnapshot, VisualReference
from schulpilot.visual_references import (
    bind_schema,
    candidates,
    public_steps,
    seed,
    validate_output,
    validate_steps,
)

SOURCE = "Ein Bruch 1/2 beschreibt 1 von 2 gleich großen Teilen."


def test_empty_visual_step_uses_saved_explanation_without_changing_snapshot():
    from schulpilot.visual_references import readable_single_step

    original = [{"id": "one", "text": "1", "presentation": {"blocks": []}}]
    explanation = "Satzglieder können mit passenden Fragen untersucht werden."
    shown = readable_single_step(original, explanation)
    assert shown[0]["text"] == explanation
    assert shown[0]["text_source"] == "saved_explanation"
    assert original[0]["text"] == "1"
    assert readable_single_step(original * 2, explanation) == original * 2
    assert readable_single_step([{"text": "x = 1"}], explanation)[0]["text"] == "x = 1"
    assert readable_single_step(original, "1") == original
    caption = {"id": "two", "text": "Die belegte Pfeilfolge: play → played",
               "reference": {"id": "general.source_relation.phases"},
               "presentation": {"blocks": [{"source_excerpt": "play → played"}]}}
    assert readable_single_step([caption], explanation)[0]["text"] == explanation
    different = {**caption, "text": "Die belegte Pfeilfolge: play → played. Hier geht es um Vergangenes."}
    assert readable_single_step([different], explanation) == [different]
    assert caption["text"] == "Die belegte Pfeilfolge: play → played"


def test_new_calendar_graphics_need_two_distinct_ordered_source_labels():
    from schulpilot.subject_content import Graphic
    from schulpilot.visual_references import _meaningful

    source = "Gestern und heute im Vergleich."
    value = {"kind": "timeline", "title": "Zeit", "disclosure": "given",
             "source_excerpt": source, "labels": [], "numbers": [], "connections": [],
             "marks": [], "unit": "", "variant": "calendar"}
    recipe = {"kind": "timeline", "id": "history.timeline.events"}
    for labels in ([], ["Gestern"], ["heute", "Gestern"], ["Gestern", "Gestern"], ["Gestern", "morgen"]):
        with pytest.raises(ValueError, match="Zeitachse"):
            _meaningful(Graphic.model_validate({**value, "labels": labels}), recipe)
    _meaningful(Graphic.model_validate({**value, "labels": ["Gestern", "heute"]}), recipe)


def block(stage="given"):
    return {"kind": "fraction", "title": "1/2", "disclosure": stage,
            "source_excerpt": SOURCE, "labels": [], "numbers": [1, 2], "connections": [], "unit": "", "variant": ""}


def step(stage="given"):
    return {"id": "e1", "text": SOURCE, "competence_id": None, "disclosure": stage,
            "reference": {"id": "math.fraction.part_whole", "version": 1}, "source_refs": ["p1"],
            "presentation": {"version": 1, "evidence_kind": "knowledge", "blocks": [block(stage)]}}


def context(db):
    return {"version": 1, "required": True, "reason": None,
            "references": candidates(db, "Mathematik", SOURCE),
            "sources": [{"ref": "p1", "subject": "Mathematik", "group_id": None, "content": SOURCE,
                         "material_id": "a" * 32, "revision": 1, "source_refs": []}]}


def question():
    return {"id": "q1", "type": "short", "prompt": "Welcher Bruch beschreibt 1 von 2 Teilen?",
            "answer": "1/2", "options": [], "accepted": [], "hints": ["Zähle die Teile."],
            "explanation": SOURCE, "explanation_steps": [step("solution")]}


def test_recipe_versions_are_seeded_idempotently_and_immutable():
    with DB.begin() as db:
        before = db.query(VisualReference).count()
        seed(db)
        assert db.query(VisualReference).count() == before
        row = db.get(VisualReference, ("math.fraction.part_whole", 1))
        row.digest = "0" * 64
        db.flush()
        with pytest.raises(ValueError, match="Version"):
            seed(db)


@pytest.mark.parametrize("subject", list(PROFILES))
def test_all_existing_subject_profiles_can_select_a_source_relation_scene(subject):
    with DB() as db:
        refs = candidates(db, subject)
    assert any(row["id"] == "general.source_relation.phases" and row["kind"] == "scene" for row in refs)
    assert all(row["kind"] in PROFILES[subject] for row in refs)


def test_unknown_subject_does_not_borrow_another_subjects_graphic():
    with DB() as db:
        assert candidates(db, "Unbekanntes Fach", "Brüche") == []


def test_required_schema_requires_steps_in_intro_and_every_question_without_changing_question_count():
    with DB() as db:
        schema = UnitOutput.model_json_schema()
        old = copy.deepcopy(schema["properties"]["questions"])
        bind_schema(schema, {"visual_context": context(db)})
    assert schema["properties"]["questions"] == old
    assert schema["properties"]["explanation_steps"]["minItems"] == 1
    assert schema["$defs"]["Question"]["properties"]["explanation_steps"]["minItems"] == 1
    assert "math.fraction.part_whole" in schema["$defs"]["VisualReferenceChoice"]["properties"]["id"]["enum"]


def test_valid_fraction_intro_and_solution_use_real_references_and_original_source():
    value = {"subject": "Mathematik", "topic": "Brüche", "explanation": SOURCE,
             "explanation_steps": [step()], "questions": [question()]}
    with DB() as db:
        validate_output(db, value, {"visual_context": context(db)})
    assert UnitOutput.model_validate(value).explanation_steps[0].reference.version == 1


@pytest.mark.parametrize("fault", ["missing", "unknown_reference", "unknown_version", "wrong_subject", "wrong_source", "wrong_value", "wrong_stage", "duplicate_id", "foreign_group"])
def test_readiness_rejects_missing_or_inconsistent_graphics(fault):
    steps = [step()]
    subject = "Mathematik"
    group = None
    if fault == "missing":
        steps = []
    if fault == "unknown_reference":
        steps[0]["reference"]["id"] = "unknown.reference"
    if fault == "unknown_version":
        steps[0]["reference"]["version"] = 2
    if fault == "wrong_subject":
        subject = "Deutsch"
    if fault == "wrong_source":
        steps[0]["source_refs"] = ["p2"]
    if fault == "wrong_value":
        steps[0]["text"] = "2/3 sind markiert."
    if fault == "wrong_stage":
        steps[0]["presentation"]["blocks"][0]["disclosure"] = "solution"
    if fault == "duplicate_id":
        steps.append(copy.deepcopy(steps[0]))
    if fault == "foreign_group":
        group = "other-group"
    with DB() as db, pytest.raises(ValueError):
        validate_steps(db, steps, subject, context(db), group_id=group, introduction=True)


def test_no_solution_text_or_private_step_quotes_before_explicit_disclosure():
    hidden = step("solution")
    hidden["source_refs"] = [{"material_id": "a" * 32, "revision": 1,
        "block_ids": ["b" * 32], "_content_digest": "c" * 64}]
    assert public_steps([hidden]) == []
    shown = public_steps([hidden], closed=True)
    assert shown[0]["text"] == SOURCE
    assert "source_excerpt" not in json.dumps(shown)
    assert "_content_digest" not in json.dumps(shown)
    assert shown[0]["source_refs"][0]["revision"] == 1
    assert len(shown[0]["presentation"]["blocks"]) == 1


def test_text_and_graphic_stage_must_agree_before_any_transport():
    hidden = step()
    hidden["presentation"]["blocks"][0]["disclosure"] = "solution"
    with pytest.raises(ValueError):
        UnitOutput.model_validate({"subject": "Mathematik", "topic": "Brüche", "explanation": SOURCE,
                                  "explanation_steps": [hidden], "questions": [question()]})


def test_existing_question_and_unit_contracts_still_accept_legacy_text():
    old = question()
    old.pop("explanation_steps")
    assert Question.model_validate(old).explanation_steps is None
    assert UnitOutput.model_validate({"subject": "Mathematik", "topic": "Brüche", "explanation": SOURCE, "questions": [old]}).explanation_steps is None


def test_decorative_unchanging_word_scene_does_not_satisfy_a_graphic_recipe():
    from schulpilot.visual_references import _meaningful

    scene = SimpleNamespace(steps=[SimpleNamespace(highlight=["water"], edges=[]), SimpleNamespace(highlight=["water"], edges=[])])
    with pytest.raises(ValueError):
        _meaningful(SimpleNamespace(kind="scene", variant="", scene=scene), {"kind": "scene"})


def test_request_receipt_contains_actual_openrouter_settings_but_no_private_text_image_or_key():
    body = {"model": "fixed/model", "max_tokens": 1234, "reasoning": {"effort": "medium", "exclude": True},
            "provider": {"only": ["pinned-upstream"]}, "messages": [
                {"role": "system", "content": "Private system text"},
                {"role": "user", "content": [{"type": "text", "text": "Private artificial text"},
                 {"type": "image_url", "image_url": {"url": "data:private-image", "detail": "high"}}]}]}
    schema = {"type": "object", "properties": {"test": {"type": "string"}}}
    receipt = request_receipt("openrouter", body, schema)
    assert receipt["max_output_tokens"] == 1234
    assert receipt["reasoning"] == body["reasoning"]
    assert receipt["image_detail"] == "high"
    assert receipt["upstreams"] == ["pinned-upstream"]
    assert "Private" not in json.dumps(receipt)
    assert "data:" not in json.dumps(receipt)
    assert len(receipt["schema_sha256"]) == len(receipt["prompt_sha256"]) == 64
    body["messages"][1]["content"][0]["text"] = "Changed artificial text"
    assert request_receipt("openrouter", body, schema)["prompt_sha256"] != receipt["prompt_sha256"]
    assert request_receipt("openrouter", body, schema)["schema_sha256"] == receipt["schema_sha256"]


def test_codex_receipt_does_not_claim_an_omitted_reasoning_field_was_transmitted():
    receipt = request_receipt("codex", {"model": "model", "system": "a", "payload": {}, "max_output_tokens": 800}, {})
    assert receipt["reasoning"] is None
    assert receipt["image_detail"] is None
    assert receipt["max_output_tokens"] == 800


def test_new_snapshot_table_is_additive_and_does_not_replace_attempts_or_mastery():
    assert next(iter(UnitVisualSnapshot.__table__.c.unit_id.foreign_keys)).ondelete == "CASCADE"
    assert {"attempts", "mastery", "learning_units", "visual_reference_versions", "unit_visual_snapshots"} <= set(Base.metadata.tables)
    assert engine is not None


@pytest.fixture
def generated_visual_unit(household):
    from schulpilot.db import Child, LearningUnit, Material, UnitSource
    from schulpilot.visual_references import remember, with_visual_context

    _, child = household
    with DB.begin() as db:
        material = Material(child_id=child["id"], title="Künstliche Bruchquelle", subject="Mathematik", topic="Brüche",
                            content=SOURCE, uncertainties=[], homework=[], confirmed=True, status="confirmed")
        db.add(material)
        db.flush()
        value = {"subject": "Mathematik", "topic": "Brüche", "explanation": SOURCE,
                 "explanation_steps": [step()], "questions": [question()]}
        unit = LearningUnit(child_id=child["id"], subject="Mathematik", topic="Brüche", explanation=SOURCE,
                            questions=value["questions"], provider="synthetic", model="own-fixture", status="paused")
        db.add(unit)
        db.flush()
        db.add(UnitSource(unit_id=unit.id, material_id=material.id, revision=material.revision))
        payload = with_visual_context(db, db.get(Child, child["id"]), {"material": {"subject": "Mathematik", "topic": "Brüche", "content": SOURCE}}, [material])
        remember(db, unit, value, payload)
        ids = unit.id, material.id, child["id"]
    return ids


def test_persisted_intro_and_question_have_source_revision_reference_version_and_no_private_quote_on_get(generated_visual_unit):
    from schulpilot.db import Activity, Attempt, LearningUnit
    from schulpilot.learning import unit_data

    uid, mid, _ = generated_visual_unit
    with DB() as db:
        before = db.query(Activity).count(), db.query(Attempt).count()
        result = unit_data(db, db.get(LearningUnit, uid))
        assert result["explanation_visual_status"] == "ready"
        saved_step = result["explanation_steps"][0]
        assert saved_step["reference"]["version"] == 1
        assert saved_step["source_refs"][0]["material_id"] == mid
        assert saved_step["source_refs"][0]["revision"] == 1
        assert len(saved_step["reference"]["parameter_digest"]) == 64
        assert result["questions"][0]["explanation_steps"] == []
        assert "source_excerpt" not in json.dumps(result["explanation_steps"])
        assert before == (db.query(Activity).count(), db.query(Attempt).count())
        parent = unit_data(db, db.get(LearningUnit, uid), include_answers=True)
        assert parent["questions"][0]["explanation_steps"][0]["disclosure"] == "solution"
        assert "source_excerpt" not in json.dumps(parent["questions"][0]["explanation_steps"])


def test_legacy_bad_step_uses_saved_text_and_does_not_open_unseen_solution(generated_visual_unit):
    from schulpilot.db import LearningUnit
    from schulpilot.learning import introduction_reveals_answer
    from schulpilot.visual_references import projection, question_projection

    uid, _, _ = generated_visual_unit
    with DB.begin() as db:
        unit = db.get(LearningUnit, uid)
        unit.explanation = "Im Beispiel wird das Wort Zucker als Ergebnis genannt."
        row = db.get(UnitVisualSnapshot, uid)
        row.steps = [{**row.steps[0], "text": "1"}]
        row.question_steps = {"q1": [{**row.question_steps["q1"][0], "text": "1"}]}
    with DB() as db:
        unit = db.get(LearningUnit, uid)
        projected = projection(db, unit)
        assert projected["explanation_steps"][0]["text"] == unit.explanation
        assert projection(db, unit, show_introduction=False)["explanation_steps"] == []
        assert introduction_reveals_answer(db, unit, {"type": "short", "answer": "Zucker"},
                                           [SimpleNamespace(kind="introduction_read")])
        question = unit.questions[0]
        assert question_projection(db, unit, question) == []
        assert question_projection(db, unit, question, closed=True)[0]["text"] == question["explanation"]
        assert db.get(UnitVisualSnapshot, uid).steps[0]["text"] == "1"


def test_source_revision_change_marks_graphics_incomplete_without_rewriting_saved_work(generated_visual_unit):
    from schulpilot.db import LearningUnit, Material
    from schulpilot.visual_references import projection

    uid, mid, _ = generated_visual_unit
    with DB.begin() as db:
        original = copy.deepcopy(db.get(LearningUnit, uid).questions)
        db.get(Material, mid).revision += 1
    with DB() as db:
        unit = db.get(LearningUnit, uid)
        projected = projection(db, unit)
        assert projected["explanation_visual_status"] == "incomplete"
        assert projected["explanation_visual_reason"] == "source_changed"
        assert projected["explanation_steps"] == []
        assert unit.questions == original
        assert unit.status == "paused"
        assert db.get(UnitVisualSnapshot, uid).status == "ready"  # Historical receipt stays immutable.


def test_export_is_child_scoped_and_snapshot_delete_cascades_with_existing_unit(generated_visual_unit):
    from schulpilot.db import LearningUnit
    from schulpilot.visual_references import export_child

    uid, _, cid = generated_visual_unit
    with DB.begin() as db:
        assert export_child(db, "foreign-child") == []
        assert export_child(db, cid)[0]["unit_id"] == uid
        db.delete(db.get(LearningUnit, uid))
    with DB() as db:
        assert db.get(UnitVisualSnapshot, uid) is None


def test_generated_reference_cannot_bind_another_childs_material(generated_visual_unit):
    from schulpilot.visual_references import guard_context

    _, mid, _ = generated_visual_unit
    with DB() as db, pytest.raises(ValueError, match="geändert"):
        guard_context(db, "foreign-child", {"sources": [{"material_id": mid, "revision": 1, "content": SOURCE}]})


def test_unavailable_source_never_accepts_unsolicited_model_steps():
    with DB() as db, pytest.raises(ValueError, match="freigegebene"):
        validate_output(db, {"subject": "Mathematik", "explanation_steps": [step()], "questions": []},
                        {"visual_context": {"required": False, "reason": "no_confirmed_source"}})


def test_step_does_not_invent_a_competence_identity():
    value = step()
    value["competence_id"] = "math.invented.skill"
    with DB() as db, pytest.raises(ValueError, match="Kompetenz"):
        validate_steps(db, [value], "Mathematik", context(db), introduction=True)


@pytest.mark.parametrize("bad", ["1/2 = 2/3", "2 von 3 Teilen sind markiert.", r"\(\frac{2}{3}\) ist markiert."])
def test_fraction_text_and_graphic_must_share_the_same_actual_parameters(bad):
    value = step()
    value["text"] = bad
    with DB() as db, pytest.raises(ValueError):
        validate_steps(db, [value], "Mathematik", context(db), introduction=True)


@pytest.mark.parametrize("provider", ["openai", "openrouter", "codex"])
def test_actual_provider_transport_sends_step_reference_contract_and_safe_receipt(monkeypatch, provider, generated_visual_unit):
    from schulpilot import providers
    from schulpilot.db import Child, Material
    from schulpilot.visual_references import with_visual_context
    from test_learning_scenes import _config, _transport

    _, mid, cid = generated_visual_unit
    with DB() as db:
        payload = with_visual_context(db, db.get(Child, cid),
            {"material": {"subject": "Mathematik", "topic": "Brüche", "content": SOURCE}}, [db.get(Material, mid)])
    output = {"subject": "Mathematik", "topic": "Brüche", "explanation": SOURCE,
              "explanation_steps": [step()], "questions": [question(), {**question(), "id": "q2"}]}
    calls = []
    _transport(monkeypatch, provider, output, calls)
    result = providers.request_provider(_config(provider), "unit", payload)
    assert len(calls) == 1
    body = calls[0]
    schema = (body["text"]["format"]["schema"] if provider == "openai" else
              body["response_format"]["json_schema"]["schema"] if provider == "openrouter" else body["schema"])
    assert "explanation_steps" in schema["required"]
    assert schema["$defs"]["VisualReferenceChoice"]["properties"]["id"]["enum"]
    assert result.data["explanation_steps"][0]["reference"]["version"] == 1
    assert len(result.request_receipt["schema_sha256"]) == 64
    assert SOURCE not in json.dumps(result.request_receipt)


def test_no_usable_source_blocks_cannot_fall_through_to_model_knowledge(generated_visual_unit, monkeypatch):
    from schulpilot import source_lineage
    from schulpilot.db import Child, Material
    from schulpilot.visual_references import with_visual_context

    _, mid, cid = generated_visual_unit
    monkeypatch.setattr(source_lineage, "learning_source", lambda *args, **kwargs: {"content": "", "source_refs": [], "factual_status": "blocked"})
    with DB() as db, pytest.raises(ValueError, match="Lehrgrundlage"):
        with_visual_context(db, db.get(Child, cid), {"material": {"subject": "Mathematik", "content": "not eligible"}}, [db.get(Material, mid)])


def test_curated_foundation_graphic_has_own_provenance_and_keeps_real_material_revision_guard(generated_visual_unit):
    from schulpilot.db import Child, LearningUnit, Material
    from schulpilot.learning_entry import with_learning_entry
    from schulpilot.visual_references import (
        _hydrate,
        guard_context,
        projection,
        remember,
        with_foundation_context,
        with_visual_context,
    )

    uid, mid, cid = generated_visual_unit
    with DB.begin() as db:
        material = db.get(Material, mid)
        material.content = 'Beim Erweitern werden Zähler und Nenner mit derselben Zahl multipliziert.'
        payload = with_visual_context(db, db.get(Child, cid), {'material': {'subject': 'Mathematik', 'topic': 'Erweitern', 'content': material.content}}, [material])
        payload = with_learning_entry(db, db.get(Child, cid), payload, [material], enabled=True)
        payload = with_foundation_context(db, payload)
        foundation = next(row for row in payload['visual_context']['sources'] if row['ref'] == 'r1')
        probe = payload['learning_entry']['units'][0]['probes'][0]
        n, d = map(int, probe['answer'].split('/'))
        explanation = step()
        explanation.update(text=f'{n} von {d} gleich großen Teilen.', source_refs=['r1'])
        explanation['presentation']['blocks'][0].update(numbers=[n, d], source_excerpt=foundation['content'])
        validate_steps(db, [explanation], 'Mathematik', payload['visual_context'], introduction=True)
        ref = _hydrate([explanation], payload['visual_context'])[0]['source_refs'][0]
        assert ref['source_kind'] == 'curated_foundation'
        assert 'material_id' not in ref
        assert ref['reference_id'] == probe['reference_id']
        assert ref['label'] == 'Eigenes kuratiertes Zusatzwissen'
        value = {'subject': 'Mathematik', 'topic': 'Erweitern', 'explanation': explanation['text'],
            'explanation_steps': [explanation], 'questions': [{key: probe[key] for key in ('id', 'type', 'prompt', 'answer', 'accepted', 'options')} | {
                'explanation': explanation['text'], 'hints': ['Zähle die gleich großen Teile.'],
                'explanation_steps': [{**copy.deepcopy(explanation), 'disclosure': 'solution', 'presentation': {
                    **copy.deepcopy(explanation['presentation']), 'blocks': [{**copy.deepcopy(explanation['presentation']['blocks'][0]), 'disclosure': 'solution'}]}}]}]}
        value['questions'] = []
        for own_probe in payload['learning_entry']['units'][0]['probes']:
            own_ref = next(row for row in payload['visual_context']['sources'] if row.get('example_question_id') == own_probe['id'])
            pair = own_probe['answer'] if '/' in own_probe['answer'] else re.search(r'(\d+/\d+)', own_probe['prompt']).group(1)
            a, b = map(int, pair.split('/'))
            own_step = step('solution')
            own_step.update(text=f'{a} von {b} gleich großen Teilen.', source_refs=[own_ref['ref']])
            own_step['presentation']['blocks'][0].update(numbers=[a,b],source_excerpt=own_ref['content'])
            value['questions'].append({key: own_probe[key] for key in ('id','type','prompt','answer','options','accepted')} | {
                'hints':['Prüfe die gleich großen Teile.'],'explanation':own_step['text'],'explanation_steps':[own_step]})
        unit = db.get(LearningUnit, uid)
        db.delete(db.get(UnitVisualSnapshot, uid))
        db.flush()
        unit.questions = value['questions']
        remember(db, unit, value, payload)
        db.flush()
        assert projection(db, unit)['explanation_visual_status'] == 'ready'
        guard_context(db, cid, payload['visual_context'])
        material.revision += 1
        db.flush()
        assert projection(db, unit)['explanation_visual_status'] == 'incomplete'


def test_forged_curated_rule_digest_is_not_a_photo_or_valid_graphic_source(generated_visual_unit):
    from schulpilot.visual_references import with_foundation_context

    with DB() as db, pytest.raises(ValueError, match='Grundlagenregel'):
        with_foundation_context(db, {'visual_context': {'sources': [], 'references': []},
            'learning_entry': {'references': [{'reference_id': 'math.fractions.meaning', 'version': 'competencies-1', 'digest': '0' * 64}],
                'units': [{'subject': 'Mathematik', 'group_id': None, 'probes': [{'reference_id': 'math.fractions.meaning'}]}]}})


def test_same_revision_new_block_exclusion_invalidates_saved_graphics_without_rewriting(generated_visual_unit, monkeypatch):
    from schulpilot import source_lineage
    from schulpilot.db import LearningUnit
    from schulpilot.visual_references import projection, source_bindings_current

    uid, _, _ = generated_visual_unit
    with DB() as db:
        unit = db.get(LearningUnit, uid)
        before = copy.deepcopy(unit.questions)
        assert source_bindings_current(db, unit, require_question_binding=True)
        original = source_lineage.learning_source
        def partly_excluded(*args, **kwargs):
            return {**original(*args, **kwargs), 'content': 'Ein anderer weiterhin lesbarer Absatz.',
                    'source_refs': [], 'exclusions': [{'reason': 'newly_excluded'}], 'factual_status': 'partly_excluded'}
        monkeypatch.setattr(source_lineage, 'learning_source', partly_excluded)
        assert projection(db, unit)['explanation_visual_status'] == 'incomplete'
        assert not source_bindings_current(db, unit, require_question_binding=True)
        assert unit.questions == before


def test_private_source_safety_digests_are_not_published(generated_visual_unit):
    from schulpilot.db import LearningUnit
    from schulpilot.visual_references import projection

    uid, _, _ = generated_visual_unit
    with DB() as db:
        result = projection(db, db.get(LearningUnit, uid))
        assert '_content_digest' not in json.dumps(result)
        assert '_question_source_bound' not in json.dumps(result)
