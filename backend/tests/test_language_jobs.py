"""Artificial sources with real queue/auth/reservations; mock transport only."""

from concurrent.futures import ThreadPoolExecutor

import pytest
from conftest import HEADERS
from fastapi.testclient import TestClient
from schulpilot import language_projects, vocabulary
from schulpilot.db import (
    DB,
    Activity,
    Attempt,
    Child,
    Family,
    LanguageProject,
    LearningUnit,
    Material,
    Membership,
    ProviderConfig,
    PushDelivery,
    PushDevice,
    Session,
    Usage,
    User,
    VocabularyImport,
    VocabularyItem,
    VocabularyReview,
    VocabularyReviewEvent,
)
from schulpilot.families import export_child, remove_child
from schulpilot.learning import plan
from schulpilot.main import app
from schulpilot.providers import Result, indexed_choice_schema, prune_schema, strict_schema
from schulpilot.worker import claim, process
from sqlalchemy import func, select, update
from test_providers import configured
from test_vocabulary import child_login, correct_answer, import_words, round_


def test_provider_schema_keeps_real_title_and_every_required_property():
    from schulpilot.language_tasks import LanguageProjectOutput

    schema = strict_schema(LanguageProjectOutput, preserve_limits=True)
    indexed_choice_schema(schema)
    prune_schema(schema)
    assert schema["properties"]["title"] == {"type": "string", "minLength": 1, "maxLength": 160}

    def check(node):
        if isinstance(node, dict):
            if node.get("type") == "object":
                assert set(node["required"]) == set(node["properties"])
                assert node["additionalProperties"] is False
            for child in node.values():
                check(child)
        elif isinstance(node, list):
            for child in node:
                check(child)

    check(schema)


@pytest.fixture
def notebook(api, household):
    parent, child = household
    configured(parent["families"][0]["id"])
    with DB.begin() as db:
        material = Material(
            child_id=child["id"],
            title="Künstliche Englischseite",
            subject="Englisch",
            topic="Schulwörter",
            content="apple = Apfel\ndog = Hund\nschool = Schule\nSimple Present: He goes to school. I do not like tea. I don't like tea.",
            confirmed=True,
            status="confirmed",
            synthetic=False,
        )
        db.add(material)
        db.flush()
        material_id = material.id
    return parent, child, material_id


def run_job(job_id):
    with DB() as db:
        assert claim(db) == job_id
    process(job_id)


@pytest.mark.parametrize("effect", ["success", "source", "provider", "logout", "rights", "planning", "unquoted"])
def test_import_worker_checks_and_single_reservation(api, notebook, monkeypatch, effect):
    parent, child, material_id = notebook
    calls = []

    def transport(config, function, payload):
        calls.append(function)
        assert function == "vocabulary_import"
        assert payload["confirmed_text"].startswith("apple = Apfel")
        with DB.begin() as db:
            if effect == "source":
                db.get(Material, material_id).revision += 1
            if effect == "provider":
                db.get(ProviderConfig, 1).revision += 1
            if effect == "logout":
                db.execute(update(Session).values(revoked=True))
            if effect == "rights":
                db.scalar(select(Membership)).permission = "view"
            if effect == "planning":
                db.get(Child, child["id"]).preferences = {"daily_minutes": 25}
        return Result(
            {"pairs": [{"word": "apple", "meaning": "Apfel" if effect != "unquoted" else "Orangenbaum"}]}, 10, 10, 1
        )

    monkeypatch.setattr(vocabulary, "request_provider", transport)
    body = {"target_locale": "en-GB", "title": "Meine Wörter", "language_confirmed": True, "material_id": material_id}
    queued = api.post(
        f"/api/children/{child['id']}/vocabulary/imports",
        json=body,
        headers={"Idempotency-Key": "source-import-request-001"},
    )
    assert queued.status_code == 201, queued.text
    row = queued.json()
    for _ in range(3):
        response = api.get(f"/api/children/{child['id']}/vocabulary/imports/{row['id']}")
        assert response.status_code == 200
    run_job(row["job_id"])
    process(row["job_id"])
    with DB() as db:
        row = db.get(VocabularyImport, row["id"])
        assert row.status == ("review" if effect == "success" else "failed")
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
        assert db.scalar(select(func.count()).select_from(VocabularyItem)) == 0
    assert calls == ["vocabulary_import"]


def proposal(item_id, *, kind="context_gap", answer="apple", source="apple = Apfel"):
    return {
        "title": "Wörter anwenden",
        "explanation": "Lies den Zusammenhang und wähle das passende Wort.",
        "response": "Denk an die Bedeutung und den Zusammenhang.",
        "response_locale": "de-DE",
        "source_excerpt": source,
        "questions": [
            {
                "id": f"l{i}",
                "type": "short",
                "task_kind": kind,
                "vocabulary_item_id": item_id,
                "prompt": "Ergänze das passende Wort."
                if kind == "context_gap"
                else "Baue den bestätigten Satz zusammen.",
                "cue": ("I eat an ___." if i == 0 else "I see an ___.")
                if kind == "context_gap"
                else f"Bestätigtes Beispiel {i + 1} ordnen.",
                "cue_locale": "en-GB" if kind == "context_gap" else "de-DE",
                "source_excerpt": source,
                "options": [],
                "answer": answer,
                "accepted": [],
                "hints": ["Welche Bedeutung passt?"],
                "explanation": "Vergleiche die Bedeutung mit deinem Wortschatz.",
            }
            for i in range(2)
        ],
    }


def project_request(api, child, material_id=None, *, mode="context_gap", key="language-project-key-001", **extra):
    with DB() as db:
        items = list(
            db.scalars(
                select(VocabularyItem).where(VocabularyItem.child_id == child["id"]).order_by(VocabularyItem.word)
            )
        )
        item_ids = [item.id for item in items]
    body = {
        "mode": mode,
        "target_locale": "en-GB",
        "item_ids": item_ids,
        "material_id": material_id,
        "goal": "Meine Schulwörter im Zusammenhang üben",
        "language_confirmed": True,
        **extra,
    }
    result = api.post(f"/api/children/{child['id']}/language-projects", json=body, headers={"Idempotency-Key": key})
    return result, body, item_ids[0]


def test_project_worker_private_keys_and_exam(api, notebook, monkeypatch):
    _, child, material_id = notebook
    import_words(api, child)
    child_login(api)
    response, body, item_id = project_request(api, child, material_id, mode="exam")
    assert response.status_code == 202, response.text
    row = response.json()
    monkeypatch.setattr(language_projects, "request_provider", lambda *args: Result(proposal(item_id), 10, 10, 1))
    run_job(row["job_id"])
    row = api.get(f"/api/children/{child['id']}/language-projects/{row['id']}").json()
    assert row["status"] == "ready", row
    assert "source_excerpt" not in row["result"]
    unit = api.get(f"/api/units/{row['unit_id']}").json()
    assert "answer" not in unit["questions"][0]
    assert "evaluation_policy" not in unit["questions"][0]["language"]
    assert unit["questions"][0]["language"]["cue_locale"] == "en-GB"
    assert api.post(f"/api/units/{unit['id']}/start").status_code == 200
    for q in unit["questions"]:
        result = api.post(
            f"/api/units/{unit['id']}/questions/{q['id']}/answer",
            json={"answer": "apple", "request_id": "answer-project-" + q["id"]},
        )
        assert result.status_code == 200, result.text
    row = api.get(f"/api/children/{child['id']}/language-projects/{row['id']}").json()
    assert row["result"]["source_excerpt"] == "apple = Apfel"
    # A request replay creates neither another job nor another language round.
    again = api.post(
        f"/api/children/{child['id']}/language-projects",
        json=body,
        headers={"Idempotency-Key": "language-project-key-001"},
    )
    assert again.json()["id"] == row["id"]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 1


@pytest.mark.parametrize(
    "effect", ["source", "item", "provider", "logout", "planning", "unquoted", "foreign_item", "mode"]
)
def test_project_rechecks_after_provider(api, notebook, monkeypatch, effect):
    _, child, material_id = notebook
    import_words(api, child)
    child_login(api)
    response, _, item_id = project_request(api, child, material_id)
    assert response.status_code == 202, response.text
    row = response.json()

    def transport(*args):
        with DB.begin() as db:
            if effect == "source":
                db.get(Material, material_id).revision += 1
            if effect == "item":
                db.get(VocabularyItem, item_id).revision += 1
            if effect == "provider":
                db.get(ProviderConfig, 1).revision += 1
            if effect == "logout":
                db.execute(update(Session).values(revoked=True))
            if effect == "planning":
                db.get(Child, child["id"]).preferences = {"daily_minutes": 25}
        output = proposal(item_id)
        if effect == "unquoted":
            output["questions"][0]["answer"] = "a made up form"
        if effect == "foreign_item":
            output["questions"][0]["vocabulary_item_id"] = "f" * 32
        if effect == "mode":
            output["questions"][0]["task_kind"] = "grammar"
        return Result(output, 10, 10, 1)

    monkeypatch.setattr(language_projects, "request_provider", transport)
    run_job(row["job_id"])
    with DB() as db:
        assert db.get(LanguageProject, row["id"]).status == "failed"
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 0


def test_grammar_requires_confirmed_source_and_own_work(api, notebook):
    _, child, material_id = notebook
    import_words(api, child)
    child_login(api)
    result, _, _ = project_request(api, child, mode="grammar", grammar_confirmed=True, grammar_topic="simple_present")
    assert result.status_code == 422
    result, _, _ = project_request(api, child, material_id, mode="writing_feedback")
    assert result.status_code == 422
    result, _, _ = project_request(
        api, child, material_id, mode="grammar", grammar_confirmed=True, grammar_topic="simple_past"
    )
    assert result.status_code == 422
    result, _, _ = project_request(
        api, child, material_id, mode="grammar", grammar_confirmed=True, grammar_topic="simple_present"
    )
    assert result.status_code == 202, result.text


def test_parallel_answers_import_rounds_and_no_double_ledger(api, household):
    _, child = household
    _, request, _ = import_words(api, child)
    headers = dict(api.headers)

    def reimport(_):
        with TestClient(app, headers=headers) as other:
            return other.post(
                f"/api/children/{child['id']}/vocabulary/imports",
                json=request,
                headers={"Idempotency-Key": "concurrent-import-001"},
            )

    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(reimport, range(4)))
    assert {response.status_code for response in results} == {201}
    assert len({response.json()["id"] for response in results}) == 1
    child_login(api)
    unit = round_(api, child)
    headers = dict(api.headers)
    q = unit["questions"][0]
    body = {"answer": correct_answer(unit["id"], q["id"]), "request_id": "parallel-language-answer-001"}

    def answer(_):
        with TestClient(app, headers=headers) as other:
            return other.post(f"/api/units/{unit['id']}/questions/{q['id']}/answer", json=body)

    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(answer, range(4)))
    assert {r.status_code for r in results} == {200}, [r.text for r in results]
    assert len({r.json()["attempt_id"] for r in results}) == 1
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Attempt)) == 1
        assert db.scalar(select(func.count()).select_from(VocabularyReviewEvent)) == 1
        assert db.scalar(select(VocabularyReview)).stage == 1


def test_audio_needs_stimulus_speech_assisted_and_source_delete_export(api, notebook):
    _, child, material_id = notebook
    import_words(api, child)
    child_login(api)
    unit = round_(api, child, skill="listening", direction="target_to_de")
    q = unit["questions"][0]
    assert q["language"]["stimulus"]
    assert not q["language"]["cue"]
    body = {"answer": correct_answer(unit["id"], q["id"]), "request_id": "listening-answer-001"}
    assert api.post(f"/api/units/{unit['id']}/questions/{q['id']}/answer", json=body).status_code == 409
    assert (
        api.post(f"/api/units/{unit['id']}/questions/{q['id']}/language-stimulus", json={"kind": "listen"}).status_code
        == 200
    )
    result = api.post(f"/api/units/{unit['id']}/questions/{q['id']}/answer", json={**body, "input_method": "speech"})
    assert result.status_code == 200, result.text
    assert result.json()["assisted"]
    with DB.begin() as db:
        child_row = db.get(Child, child["id"])
        exported = export_child(db, child_row)
        assert len(exported["vocabulary_items"]) == 3
        assert len(exported["vocabulary_review_events"]) == 1
        daily = plan(db, child_row)
        assert daily["vocabulary"]["confirmed_words"] == 3
        assert "vocabulary" in {row["kind"] for row in daily["voluntary"]}
        remove_child(db, child_row)
    with DB() as db:
        for model in (
            VocabularyItem,
            VocabularyReview,
            VocabularyReviewEvent,
            VocabularyImport,
            Attempt,
            LanguageProject,
        ):
            assert db.scalar(select(func.count()).select_from(model)) == 0


def test_source_deletion_purges_import_items_and_projects(api, notebook):
    _, child, material_id = notebook
    import_words(api, child)
    with DB.begin() as db:
        item = db.scalar(select(VocabularyItem))
        item.source_revisions = [{"id": material_id, "revision": 1}]
        vocabulary.purge_sources(db, [material_id], child["id"])
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(VocabularyItem)) == 2


def test_source_delete_removes_linked_language_round_and_answers(api, notebook):
    _, child, material_id = notebook
    import_words(api, child)
    with DB.begin() as db:
        for item in db.scalars(select(VocabularyItem)):
            item.source_revisions = [{"id": material_id, "revision": 1}]
    child_login(api)
    unit = round_(api, child)
    first, second = unit["questions"][:2]
    result = api.post(
        f"/api/units/{unit['id']}/questions/{first['id']}/answer",
        json={"answer": correct_answer(unit["id"], first["id"]), "request_id": "before-source-delete-001"},
    )
    assert result.status_code == 200
    later_answer = correct_answer(unit["id"], second["id"])
    with TestClient(app, headers=HEADERS) as parent:
        logged = parent.post(
            "/api/auth/login", json={"username": "parent@example.org", "password": "secure-parent-pass-123"}
        )
        parent.headers["Authorization"] = "Bearer " + logged.json()["token"]
        assert parent.delete("/api/materials/" + material_id).status_code == 409
        selection = parent.post(f"/api/children/{child['id']}/materials/delete-preview",
                                json={"ids": [material_id]}).json()
        assert selection['unit_count'] == selection['answer_count'] == 1
        deleted = parent.post(f"/api/children/{child['id']}/materials/bulk-delete",
                              json={"selection_token": selection['selection_token'], "delete_linked_units": True})
        assert deleted.status_code == 200, deleted.text
    assert api.get("/api/units/" + unit["id"]).status_code == 404
    result = api.post(
        f"/api/units/{unit['id']}/questions/{second['id']}/answer",
        json={"answer": later_answer, "request_id": "after-source-delete-0001"},
    )
    assert result.status_code == 404
    with DB() as db:
        assert db.get(LearningUnit, unit["id"]) is None
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0
        assert db.scalar(select(func.count()).select_from(VocabularyItem)) == 0


@pytest.mark.parametrize(
    "mode",
    [
        "context_gap",
        "sentence_order",
        "grammar",
        "dialog",
        "exam",
        "writing_feedback",
        "model_text",
        "writing_help",
        "simplify",
        "presentation",
        "speech",
        "study_notes",
        "worksheet",
        "topic_practice",
        "debate",
        "translation",
        "summary",
        "email",
    ],
)
def test_each_workshop_mode_has_real_saved_tasks_and_no_invented_attempts(api, notebook, monkeypatch, mode):
    _, child, material_id = notebook
    import_words(api, child)
    child_login(api)
    extra = {"draft": "I like my school and my dog."}
    if mode == "grammar":
        extra.update(grammar_confirmed=True, grammar_topic="simple_present")
    response, _, item_id = project_request(api, child, material_id, mode=mode, **extra)
    assert response.status_code == 202, response.text
    output = proposal(item_id)
    if mode in ("sentence_order", "grammar"):
        with DB() as db:
            school = db.scalar(select(VocabularyItem).where(VocabularyItem.word == "school"))
            item_id = school.id
        output = proposal(item_id, kind=mode, answer="He goes to school.", source="He goes to school.")
        if mode == "grammar":
            for question in output["questions"]:
                question["type"] = "choice"
                question["options"] = ["He goes to school.", "He go to school."]
    output["criteria"] = [
        {
            "criterion": "clarity",
            "draft_quote": "I like my school",
            "observation": "Der eigene Entwurf nennt die Schule.",
            "suggestion": "Ergänze einen konkreten Zusammenhang.",
        },
        {
            "criterion": "word_choice",
            "draft_quote": "my dog",
            "observation": "Ein bestätigtes Wort wird benutzt.",
            "suggestion": "Vergleiche die Bedeutung mit deinem Wortschatz.",
        },
    ]
    monkeypatch.setattr(language_projects, "request_provider", lambda *args: Result(output, 10, 10, 1))
    run_job(response.json()["job_id"])
    with DB() as db:
        project = db.get(LanguageProject, response.json()["id"])
        assert project.status == "ready", project.error
        unit = db.get(LearningUnit, project.unit_id)
        assert len(unit.questions) == 2
        assert all(q["language"]["generated_example"] for q in unit.questions)
        assert project.result["is_student_work"] is False
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0
        if mode == "sentence_order":
            assert sorted(unit.questions[0]["language"]["word_bank"]) == sorted("He goes to school.".split())
        if mode == "grammar":
            assert unit.questions[0]["language"]["grammar_topic"] == "simple_present"


def test_dialog_is_bounded_and_cannot_branch_on_duplicate_requests(api, notebook, monkeypatch):
    parent, child, material_id = notebook
    with DB.begin() as db:
        family = db.get(Family, parent["families"][0]["id"])
        family.call_limit, family.budget_micros = 10, 10000
    import_words(api, child)
    child_login(api)
    previous = None
    last_body = None
    for step in range(1, 5):
        response, body, item_id = project_request(
            api,
            child,
            material_id,
            mode="dialog",
            key=f"language-dialog-key-{step:04}",
            previous_id=previous,
            draft="I like my school.",
        )
        assert response.status_code == 202, response.text
        monkeypatch.setattr(language_projects, "request_provider", lambda *args: Result(proposal(item_id), 10, 10, 1))
        run_job(response.json()["job_id"])
        project = api.get(f"/api/children/{child['id']}/language-projects/{response.json()['id']}").json()
        assert project["step"] == step
        assert project["can_continue"] is (step < 4)
        if step > 1:
            branch = api.post(
                f"/api/children/{child['id']}/language-projects",
                json=body,
                headers={"Idempotency-Key": f"dialog-fork-key-{step:06}"},
            )
            assert branch.status_code == 409
        previous = project["id"]
        last_body = body
    result = api.post(
        f"/api/children/{child['id']}/language-projects",
        json={**last_body, "previous_id": previous},
        headers={"Idempotency-Key": "dialog-key-fifth-step"},
    )
    assert result.status_code == 409
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 4


def test_vocabulary_due_uses_existing_neutral_daily_bundle_and_quiet_times(api, household, tmp_path):
    from datetime import datetime
    from zoneinfo import ZoneInfo

    from schulpilot import notifications as n
    from test_notifications import device, enable

    _, child = household
    import_words(api, child)
    child_login(api)
    enable(tmp_path)
    fixed = int(datetime(2026, 10, 17, 17, tzinfo=ZoneInfo("Europe/Berlin")).timestamp())
    with DB.begin() as db:
        row = db.get(Child, child["id"])
        row.preferences = {
            "weekdays": list(range(7)),
            "push_consent": True,
            "reminders": True,
            "quiet_start": 20,
            "quiet_end": 8,
        }
    registered = device(api)
    with DB.begin() as db:
        session = db.get(Session, db.get(PushDevice, registered["id"]).session_id)
        session.seen, session.expires = fixed, fixed + 86400
        item = db.scalar(select(VocabularyItem))
        db.add(
            VocabularyReview(
                child_id=child["id"],
                item_id=item.id,
                revision=item.revision,
                direction="de_to_target",
                skill="spelling",
                due="2026-10-17",
                stage=1,
            )
        )
        # A different completed lesson does not conceal due vocabulary.
        db.add(Activity(child_id=child["id"], kind="unit_completed", created=fixed - 60, detail={}))
        db.flush()
        n.prepare(db, fixed)
        n.prepare(db, fixed)
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(PushDelivery)) == 1
        d = db.get(PushDevice, registered["id"])
        assert n.due_kinds(db, d, fixed) == ["reminder"]
        assert n.due_kinds(db, d, fixed + 4 * 3600) == []


def test_admin_denied_private_vocabulary_and_view_parent_cannot_manage(api, household):
    parent, child = household
    import_words(api, child)
    with DB.begin() as db:
        db.scalar(select(Membership)).permission = "view"
    assert api.get(f"/api/children/{child['id']}/vocabulary").status_code == 200
    response = api.post(
        f"/api/children/{child['id']}/vocabulary/imports",
        json={
            "target_locale": "en-GB",
            "title": "View cannot manage",
            "language_confirmed": True,
            "pairs": [{"word": "book", "meaning": "Buch"}],
        },
        headers={"Idempotency-Key": "forbidden-view-import-001"},
    )
    assert response.status_code == 403
    with DB.begin() as db:
        db.get(User, parent["id"]).role = "admin"
    for path in ("vocabulary", "vocabulary/imports", "language-projects"):
        assert api.get(f"/api/children/{child['id']}/{path}").status_code == 403


def test_indexed_language_choices_do_not_invent_group_fields_or_question_types():
    from schulpilot.language_tasks import LanguageProjectOutput

    schema = strict_schema(LanguageProjectOutput, preserve_limits=True)
    original = schema["$defs"]["LanguageGeneratedQuestion"]
    fields = set(original["properties"])
    types = set(original["properties"]["type"]["enum"])
    assert "field_group" not in fields and types == {"choice", "gap", "short"}
    indexed_choice_schema(schema)
    prune_schema(schema)
    branches = schema["$defs"]["LanguageGeneratedQuestion"]["anyOf"]
    assert len(branches) == 2
    assert {kind for branch in branches for kind in branch["properties"]["type"]["enum"]} == types
    for branch in branches:
        assert set(branch["properties"]) == set(branch["required"]) == fields
        assert "field_group" not in branch["properties"]
        assert branch["additionalProperties"] is False
    assert "FieldGroup" not in schema["$defs"]


def test_indexed_normal_questions_keep_group_field_required_and_nullable_only_outside_grouped():
    from schulpilot.schemas import UnitOutput

    schema = strict_schema(UnitOutput, preserve_limits=True)
    indexed_choice_schema(schema, bounded_matches=True)
    prune_schema(schema)
    branches = schema["$defs"]["Question"]["anyOf"]
    for branch in branches:
        props = branch["properties"]
        assert set(props) == set(branch["required"])
        assert "field_group" in branch["required"]
        if props["type"]["enum"] == ["grouped"]:
            assert props["field_group"] == {"$ref": "#/$defs/FieldGroup"}
        else:
            assert props["field_group"] == {"type": "null"}
    assert "FieldGroup" in schema["$defs"]
