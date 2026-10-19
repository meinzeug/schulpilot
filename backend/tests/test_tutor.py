"""Real routes/queue with artificial notebooks and a synthetic transport only."""

import copy
import json
import uuid
from concurrent.futures import ThreadPoolExecutor

import pytest
from conftest import HEADERS, create_child, register
from fastapi.testclient import TestClient
from schulpilot import coaching, tutor
from schulpilot.db import (
    DB,
    Activity,
    Attempt,
    Child,
    Family,
    Job,
    LearningUnit,
    Mastery,
    Material,
    Membership,
    ProviderConfig,
    SchoolDay,
    Session,
    TutorTurn,
    UnitSource,
    Usage,
    User,
    engine,
    now,
)
from schulpilot.learning import local_day
from schulpilot.main import app
from schulpilot.providers import ProviderError, Result
from schulpilot.security import digest
from schulpilot.worker import claim, process
from sqlalchemy import delete, func, select, update
from test_providers import configured

TEXT = "Die Sonne ist ein Stern. Die Erde dreht sich um die Sonne. Ein Umlauf dauert ein Jahr."
QUESTION = "Was ist die Sonne?"


@pytest.fixture
def notebook(api, household):
    parent, kid = household
    family_id = parent["families"][0]["id"]
    configured(family_id)
    with DB.begin() as db:
        family = db.get(Family, family_id)
        family.call_limit, family.budget_micros = 30, 30_000
        child = db.get(Child, kid["id"])
        child.preferences = {"weekdays": list(range(7))}
        day = SchoolDay(child_id=child.id, school_date=local_day(child).isoformat(), stage="ready")
        db.add(day)
        db.flush()
        material = Material(
            child_id=child.id,
            school_day_id=day.id,
            page_number=1,
            title="Künstliche Heftseite",
            subject="Sachunterricht",
            topic="Sonnensystem",
            content=TEXT,
            confirmed=True,
            status="confirmed",
            synthetic=False,
        )
        db.add(material)
        db.flush()
        unit = LearningUnit(
            child_id=child.id,
            school_day_id=day.id,
            material_id=material.id,
            subject=material.subject,
            topic=material.topic,
            explanation="Künstliche Testeinheit; keine abgegebenen Kinderantworten.",
            questions=[],
            provider="openai",
            model="synthetic-fixture",
        )
        db.add(unit)
        db.flush()
        db.add(UnitSource(unit_id=unit.id, material_id=material.id, revision=material.revision))
        ids = {"day_id": day.id, "material_id": material.id, "unit_id": unit.id}
    with TestClient(app, headers=HEADERS) as child_api:
        response = child_api.post(
            "/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}
        )
        assert response.status_code == 200
        child_api.headers["Authorization"] = "Bearer " + response.json()["token"]
        yield {"child": kid, "parent": parent, "client": child_api, "family_id": family_id, **ids}


@pytest.fixture
def transport(monkeypatch):
    state = {
        "calls": [],
        "effect": None,
        "output": {
            "answer": "Die Sonne ist ein Stern.",
            "kind": "answer",
            "sources": [{"ref": "p1", "quote": "Die Sonne ist ein Stern."}],
            "next_question": None,
        },
    }

    def request(config, function, payload):
        assert function == "tutor"
        state["calls"].append(copy.deepcopy(payload))
        if state["effect"]:
            state["effect"]()
        return Result(copy.deepcopy(state["output"]), 50, 80, 0)

    monkeypatch.setattr(tutor, "request_provider", request)
    return state


def route(book):
    return f"/api/children/{book['child']['id']}/tutor/questions"


def ask(book, scope="material_id", *, key=None, **extra):
    return book["client"].post(
        route(book),
        json={"question": QUESTION, scope: book[scope], **extra},
        headers={"Idempotency-Key": key or uuid.uuid4().hex},
    )


def finish():
    with DB() as db:
        job_id = claim(db)
    assert job_id
    process(job_id)
    return job_id


def saved(api, book, scope="material_id"):
    response = api.get(route(book), params={scope: book[scope]})
    assert response.status_code == 200, response.text
    return response.json()["questions"]


@pytest.mark.parametrize("scope", ["day_id", "material_id", "unit_id"])
def test_source_question_is_persisted_cited_visible_to_parents_and_idempotent(api, notebook, transport, scope):
    key = uuid.uuid4().hex
    response = ask(notebook, scope, key=key)
    assert response.status_code == 202, response.text
    queued = response.json()
    assert queued["status"] == "queued" and queued["question"] == QUESTION and queued["reply"] is None
    assert saved(notebook["client"], notebook, scope)[0]["id"] == queued["id"]
    assert ask(notebook, scope, key=key).json()["id"] == queued["id"]
    finish()
    turn = saved(api, notebook, scope)[0]
    assert turn["status"] == "ready" and turn["source_changed"] is False
    assert turn["reply"]["sources"] == [
        {
            "ref": "p1",
            "quote": "Die Sonne ist ein Stern.",
            "label": "Seite 1 · Sachunterricht · Sonnensystem",
            "material_id": notebook["material_id"],
        }
    ]
    assert ask(notebook, scope, key=key).json()["id"] == queued["id"]
    assert ask(notebook, scope, key=key, question="Eine andere Frage?").status_code == 409
    assert len(transport["calls"]) == 1
    payload = transport["calls"][0]
    assert set(payload) == {"grade", "question", "sources", "history"}
    assert payload["sources"][0]["content"] == TEXT and payload["history"] == []
    for private_id in (
        notebook["child"]["id"],
        notebook["family_id"],
        notebook["material_id"],
        notebook["parent"]["id"],
    ):
        assert private_id not in json.dumps(payload)
    with DB() as db:
        job = db.get(Job, queued["job_id"])
        assert (
            job.status == "completed"
            and QUESTION not in json.dumps(job.payload)
            and TEXT not in json.dumps(job.payload)
        )
        usage = db.scalar(select(Usage))
        assert usage.function == "tutor" and usage.cost_micros == 0
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0
        assert db.scalar(select(func.count()).select_from(Mastery)) == 0
        assert len(list(db.scalars(select(Activity).where(Activity.kind.in_(["tutor_question", "tutor_answer"]))))) == 2


def test_scope_key_and_question_validation_happen_before_reserving_usage(notebook):
    client = notebook["client"]
    for data in (
        {"question": QUESTION},
        {"question": QUESTION, "day_id": notebook["day_id"], "material_id": notebook["material_id"]},
        {"question": " " * 20, "material_id": notebook["material_id"]},
        {"question": "a" * 1001, "material_id": notebook["material_id"]},
    ):
        assert client.post(route(notebook), json=data, headers={"Idempotency-Key": uuid.uuid4().hex}).status_code == 422
    assert (
        client.post(route(notebook), json={"question": QUESTION, "material_id": notebook["material_id"]}).status_code
        == 422
    )
    assert client.get(route(notebook)).status_code == 422
    assert (
        client.get(route(notebook), params={"day_id": notebook["day_id"], "unit_id": notebook["unit_id"]}).status_code
        == 422
    )
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_parent_view_guardian_foreign_family_sibling_and_admin_permissions(api, mailbox, notebook, transport):
    assert (
        api.post(
            route(notebook),
            json={"question": QUESTION, "material_id": notebook["material_id"]},
            headers={"Idempotency-Key": uuid.uuid4().hex},
        ).status_code
        == 403
    )
    assert ask(notebook).status_code == 202
    finish()
    sibling = create_child(api, notebook["parent"], "tutor-sibling")
    with TestClient(app, headers=HEADERS) as outsider:
        login = outsider.post(
            "/api/auth/login", json={"username": "tutor-sibling", "password": "secure-child-pass-123"}
        )
        outsider.headers["Authorization"] = "Bearer " + login.json()["token"]
        assert outsider.get(route(notebook), params={"material_id": notebook["material_id"]}).status_code == 404
        assert (
            outsider.post(
                f"/api/children/{sibling['id']}/tutor/questions",
                json={"question": QUESTION, "material_id": notebook["material_id"]},
                headers={"Idempotency-Key": uuid.uuid4().hex},
            ).status_code
            == 404
        )
        register(outsider, mailbox, "foreign-tutor-parent@example.org")
        assert outsider.get(route(notebook), params={"material_id": notebook["material_id"]}).status_code == 404
    with DB.begin() as db:
        parent = db.get(User, notebook["parent"]["id"])
        viewer = User(
            username="tutor-viewer",
            display_name="Test",
            password_hash=parent.password_hash,
            role="parent",
            verified=True,
        )
        admin = User(
            username="tutor-admin", display_name="Test", password_hash=parent.password_hash, role="admin", verified=True
        )
        db.add_all([viewer, admin])
        db.flush()
        db.add(Membership(user_id=viewer.id, family_id=notebook["family_id"], permission="view"))
        for user, token in ((viewer, "synthetic-tutor-viewer"), (admin, "synthetic-tutor-admin")):
            db.add(Session(user_id=user.id, token_hash=digest(token), device="Test", expires=int(now()) + 600))
    for token, expected in (("synthetic-tutor-viewer", 200), ("synthetic-tutor-admin", 403)):
        with TestClient(app, headers={**HEADERS, "Authorization": "Bearer " + token}) as actor:
            assert actor.get(route(notebook), params={"material_id": notebook["material_id"]}).status_code == expected
            assert (
                actor.post(
                    route(notebook),
                    json={"question": QUESTION, "material_id": notebook["material_id"]},
                    headers={"Idempotency-Key": uuid.uuid4().hex},
                ).status_code
                == 403
            )


@pytest.mark.parametrize("blocked", ["unconfirmed", "oversize", "demo_family", "demo_material"])
def test_unconfirmed_oversize_or_demo_content_never_leaves_backend(notebook, transport, blocked):
    with DB.begin() as db:
        material = db.get(Material, notebook["material_id"])
        if blocked == "unconfirmed":
            material.confirmed = False
        elif blocked == "oversize":
            material.content = "a" * 60_001
        elif blocked == "demo_family":
            db.get(Family, notebook["family_id"]).synthetic = True
        else:
            material.synthetic = True
    response = ask(notebook, "day_id")
    assert response.status_code == (409 if blocked == "unconfirmed" else 422 if blocked == "oversize" else 403)
    assert transport["calls"] == []
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


@pytest.mark.parametrize("fault", ["invented_quote", "foreign_ref", "missing_citation", "duplicate_quote"])
def test_invalid_citations_fail_honestly_without_changing_learning_results(api, notebook, transport, fault):
    with DB.begin() as db:
        db.get(LearningUnit, notebook["unit_id"]).status = "active"
    if fault == "invented_quote":
        transport["output"]["sources"][0]["quote"] = "Dieser Satz steht nirgends im bestätigten Heft."
    elif fault == "foreign_ref":
        transport["output"]["sources"][0]["ref"] = "p2"
    elif fault == "missing_citation":
        transport["output"]["sources"] = []
    else:
        transport["output"]["sources"] *= 2
    assert ask(notebook).status_code == 202
    finish()
    turn = saved(api, notebook)[0]
    assert turn["status"] == "failed" and turn["reply"] is None and turn["error"]
    assert len(transport["calls"]) == 1
    with DB() as db:
        assert db.scalar(select(Usage)).cost_micros == 0
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0
        assert db.scalar(select(Activity.id).where(Activity.kind == "explanation")) is None


@pytest.mark.parametrize("kind", ["clarification", "not_in_material"])
def test_clarification_and_missing_content_remain_explicit(api, notebook, transport, kind):
    with DB.begin() as db:
        db.get(LearningUnit, notebook["unit_id"]).status = "active"
    transport["output"].update(
        kind=kind,
        answer="Welche Stelle meinst du?" if kind == "clarification" else "Das steht nicht auf diesen Heftseiten.",
        sources=[],
        next_question="Meinst du die Sonne oder die Erde?" if kind == "clarification" else None,
    )
    assert ask(notebook).status_code == 202
    finish()
    turn = saved(api, notebook)[0]
    assert turn["status"] == "ready" and turn["reply"]["kind"] == kind and turn["reply"]["sources"] == []
    with DB() as db:
        assert db.scalar(select(Activity.id).where(Activity.kind == "explanation")) is None


@pytest.mark.parametrize("when", ["before", "during"])
@pytest.mark.parametrize("change", ["source", "logout"])
def test_changed_source_or_revoked_session_blocks_before_and_after_provider(api, notebook, transport, when, change):
    with DB.begin() as db:
        db.get(LearningUnit, notebook["unit_id"]).status = "active"
    assert ask(notebook).status_code == 202

    def changed():
        with DB.begin() as db:
            if change == "source":
                db.get(Material, notebook["material_id"]).revision += 1
            else:
                turn = db.scalar(select(TutorTurn))
                db.get(Session, turn.session_id).revoked = True

    if when == "before":
        changed()
    else:
        transport["effect"] = changed
    finish()
    turn = saved(api, notebook)[0]
    assert turn["status"] == "failed" and turn["reply"] is None
    assert len(transport["calls"]) == (1 if when == "during" else 0)
    with DB() as db:
        assert db.scalar(select(Usage)).cost_micros == (0 if when == "during" else None)
        assert db.scalar(select(Activity.id).where(Activity.kind == "explanation")) is None


@pytest.mark.parametrize("change", ["provider", "preferences", "disabled", "session_deleted"])
def test_live_configuration_access_and_parent_planning_are_rechecked(api, notebook, transport, change):
    assert ask(notebook).status_code == 202

    def changed():
        with DB.begin() as db:
            turn = db.scalar(select(TutorTurn))
            if change == "provider":
                db.get(ProviderConfig, 1).revision += 1
            elif change == "preferences":
                db.get(Child, notebook["child"]["id"]).preferences = {"weekdays": [0]}
            elif change == "disabled":
                db.get(User, turn.user_id).disabled = True
            else:
                db.execute(delete(Session).where(Session.id == turn.session_id))

    transport["effect"] = changed
    finish()
    turn = saved(api, notebook)[0]
    assert turn["status"] == "failed" and turn["reply"] is None and len(transport["calls"]) == 1
    with DB() as db:
        assert db.scalar(select(Usage)).cost_micros == 0


def test_followup_uses_only_own_same_scope_confirmed_history(api, notebook, transport):
    first = ask(notebook).json()
    finish()
    assert ask(notebook, reply_to=first["id"]).status_code == 202
    finish()
    assert transport["calls"][1]["history"] == [
        {"question": QUESTION, "answer": "Die Sonne ist ein Stern.", "kind": "answer"}
    ]
    assert ask(notebook, "day_id", reply_to=first["id"]).status_code == 409
    assert ask(notebook, reply_to="f" * 32).status_code == 409
    with DB.begin() as db:
        db.get(Material, notebook["material_id"]).revision += 1
    assert ask(notebook, reply_to=first["id"]).status_code == 409
    assert all(turn["source_changed"] for turn in saved(api, notebook))


def test_parallel_idempotency_and_one_active_job_share_reservation(notebook, transport):
    key = uuid.uuid4().hex
    with ThreadPoolExecutor(max_workers=4) as pool:
        responses = list(pool.map(lambda _: ask(notebook, key=key), range(6)))
    assert all(r.status_code == 202 for r in responses)
    assert len({r.json()["id"] for r in responses}) == 1
    assert ask(notebook).status_code == 409
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 1
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
    finish()
    assert len(transport["calls"]) == 1


def test_limits_failed_status_and_explicit_new_attempt_preserve_history(api, notebook, transport, monkeypatch):
    with DB.begin() as db:
        db.get(Family, notebook["family_id"]).call_limit = 0
    assert ask(notebook).status_code == 429
    with DB.begin() as db:
        db.get(Family, notebook["family_id"]).call_limit = 30

    def unavailable(*args):
        raise ProviderError("Der Anbieter ist vorübergehend nicht erreichbar.")

    monkeypatch.setattr(tutor, "request_provider", unavailable)
    key = uuid.uuid4().hex
    old = ask(notebook, key=key).json()
    finish()
    assert ask(notebook, key=key).json()["status"] == "failed"
    assert saved(api, notebook)[0]["id"] == old["id"]
    new = ask(notebook)
    assert new.status_code == 202 and new.json()["id"] != old["id"]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 2


def test_history_pagination_and_expired_session_cleanup_preserve_answers(api, notebook, transport):
    response = ask(notebook)
    assert response.status_code == 202
    finish()
    with DB.begin() as db:
        first = db.get(TutorTurn, response.json()["id"])
        for index in range(23):
            db.add(
                TutorTurn(
                    child_id=first.child_id,
                    user_id=first.user_id,
                    session_id=first.session_id,
                    material_id=first.material_id,
                    question=f"Künstliche Frage {index}",
                    status="ready",
                    reply=first.reply,
                    source_revisions=first.source_revisions,
                    created=first.created + index + 1,
                )
            )
        db.execute(delete(Session).where(Session.id == first.session_id))
    page = api.get(route(notebook), params={"material_id": notebook["material_id"]}).json()
    assert len(page["questions"]) == 20 and page["next_cursor"]
    second = api.get(
        route(notebook), params={"material_id": notebook["material_id"], "cursor": page["next_cursor"]}
    ).json()
    assert len(second["questions"]) == 4 and second["next_cursor"] is None
    assert not {q["id"] for q in second["questions"]} & {q["id"] for q in page["questions"]}
    assert all(q["status"] == "ready" and q["reply"] for q in page["questions"] + second["questions"])
    with DB() as db:
        assert db.get(TutorTurn, response.json()["id"]).session_id is None


def test_deleting_a_source_purges_quotes_in_day_and_unit_scopes(api, notebook, transport):
    assert ask(notebook, "unit_id").status_code == 202
    finish()
    assert ask(notebook, "day_id").status_code == 202
    with DB.begin() as db:
        assert tutor.purge_source_turns(db, [notebook["material_id"]], child_id=notebook["child"]["id"]) == 2
        db.execute(delete(Material).where(Material.id == notebook["material_id"]))
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(TutorTurn)) == 0
        assert db.scalar(select(Job).where(Job.status == "queued")) is None
        assert all(usage.cost_micros == 0 for usage in db.scalars(select(Usage)))
    assert saved(api, notebook, "day_id") == []


def test_source_erasure_does_not_claim_zero_cost_if_worker_already_claimed_job(notebook, monkeypatch):
    queued = ask(notebook)
    assert queued.status_code == 202
    job_id = queued.json()["job_id"]
    with DB.begin() as db:
        original_scalars = db.scalars

        def racing_claim(statement, *args, **kwargs):
            result = original_scalars(statement, *args, **kwargs)
            if statement.column_descriptions[0].get("entity") is Job:
                rows = list(result)
                db.execute(
                    update(Job)
                    .where(Job.id == job_id)
                    .values(status="running")
                    .execution_options(synchronize_session=False)
                )
                return iter(rows)
            return result

        monkeypatch.setattr(db, "scalars", racing_claim)
        assert tutor.purge_source_turns(db, [notebook["material_id"]]) == 1
        db.expire_all()
        assert db.get(Job, job_id).status == "running"
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        assert usage.cost_micros is None and usage.status == "reserved"


def tutor_practice_questions():
    return [
        {
            "id": "q1",
            "type": "choice",
            "prompt": "Was ist die Sonne?",
            "options": ["Stern", "Planet"],
            "answer": "Stern",
            "accepted": [],
            "hints": ["Sie leuchtet selbst."],
            "explanation": "Die Sonne ist ein Stern.",
        },
        {
            "id": "q2",
            "type": "choice",
            "prompt": "Um was dreht sich die Erde?",
            "options": ["Sonne", "Mond"],
            "answer": "Sonne",
            "accepted": [],
            "hints": ["Lies den zweiten Satz."],
            "explanation": "Die Erde dreht sich um die Sonne.",
        },
    ]


@pytest.mark.parametrize("scope", ["unit_id", "day_id", "material_id"])
def test_tutor_help_marks_only_matching_ongoing_practice_and_never_independent_mastery(
    api, notebook, transport, monkeypatch, scope
):
    monkeypatch.setattr(coaching, "schedule", lambda *args, **kwargs: None)
    sibling = create_child(api, notebook["parent"], "tutor-help-sibling")
    with DB.begin() as db:
        unit = db.get(LearningUnit, notebook["unit_id"])
        unit.status, unit.questions = "active", tutor_practice_questions()
        material = db.get(Material, notebook["material_id"])
        unrelated = Material(
            child_id=unit.child_id,
            title="Andere künstliche Seite",
            subject="Sachunterricht",
            topic="Bäume",
            content="Eine Eiche ist ein Baum.",
            confirmed=True,
            status="confirmed",
        )
        db.add(unrelated)
        db.flush()
        practice = {}
        for name, status, source, explicit_sources, revision in (
            ("overlap", "active", material, True, material.revision),
            ("legacy", "active", material, False, material.revision),
            ("other_source", "active", unrelated, True, unrelated.revision),
            ("stale_revision", "active", material, True, material.revision + 1),
            ("paused", "paused", material, True, material.revision),
            ("not_started", "not_started", material, True, material.revision),
            ("ready", "ready", material, True, material.revision),
            ("completed", "completed", material, True, material.revision),
            # Even an inconsistent cross-child source link must never allow
            # this child's response to change another child's help history.
            ("sibling", "active", material, True, material.revision),
        ):
            practice_unit = LearningUnit(
                child_id=sibling["id"] if name == "sibling" else unit.child_id,
                material_id=source.id,
                subject=source.subject,
                topic=source.topic,
                explanation="Künstliche gespeicherte Übung.",
                questions=tutor_practice_questions(),
                status=status,
                completed=int(now()) - 60 if status == "completed" else None,
                provider="openai",
                model="synthetic-fixture",
            )
            db.add(practice_unit)
            db.flush()
            practice[name] = practice_unit.id
            if explicit_sources:
                db.add(UnitSource(unit_id=practice_unit.id, material_id=source.id, revision=revision))
        earlier = Attempt(
            unit_id=practice["completed"],
            question_id="q1",
            answer="Stern",
            outcome="correct",
            assisted=False,
            created=int(now()) - 60,
        )
        db.add(earlier)
        db.flush()
        old_attempt_id = earlier.id
    path = f"/api/units/{notebook['unit_id']}/questions"
    first = notebook["client"].post(f"{path}/q1/answer", json={"answer": "Stern"})
    assert first.status_code == 200, first.text
    assert first.json()["assisted"] is False
    response = ask(notebook, scope)
    assert response.status_code == 202, response.text
    turn_id = response.json()["id"]
    with DB() as db:
        assert db.scalar(select(Activity.id).where(Activity.kind == "explanation")) is None
    job_id = finish()
    process(job_id)  # Re-delivery of a completed job cannot duplicate help.
    with DB() as db:
        help_events = list(db.scalars(select(Activity).where(Activity.kind == "explanation")))
        assert {event.unit_id for event in help_events} == {
            notebook["unit_id"],
            practice["overlap"],
            practice["legacy"],
            practice["paused"],
        }
        assert len(help_events) == 4
        assert all(
            event.child_id == notebook["child"]["id"] and event.detail == {"via": "tutor", "turn_id": turn_id}
            for event in help_events
        )
        old_attempt = db.get(Attempt, old_attempt_id)
        assert old_attempt.outcome == "correct" and old_attempt.assisted is False
        first_attempt = db.scalar(select(Attempt).where(Attempt.unit_id == notebook["unit_id"]))
        assert first_attempt.assisted is False
    second = notebook["client"].post(f"{path}/q2/answer", json={"answer": "Sonne"})
    assert second.status_code == 200, second.text
    assert second.json()["assisted"] is True
    assert second.json()["unit"]["status"] == "completed"
    with DB() as db:
        mastery = db.scalar(select(Mastery).where(Mastery.child_id == notebook["child"]["id"]))
        assert mastery.independent == 0 and mastery.assisted == 1
        assert not coaching.independently_correct(db, db.get(LearningUnit, notebook["unit_id"]))


def test_pausing_before_tutor_help_and_resuming_cannot_count_as_independent(notebook, transport, monkeypatch):
    monkeypatch.setattr(coaching, "schedule", lambda *args, **kwargs: None)
    with DB.begin() as db:
        db.get(LearningUnit, notebook["unit_id"]).questions = tutor_practice_questions()
    path = f"/api/units/{notebook['unit_id']}"
    client = notebook["client"]
    assert client.post(path + "/start").json()["status"] == "active"
    assert client.post(path + "/pause").json()["status"] == "paused"
    response = ask(notebook)
    assert response.status_code == 202, response.text
    finish()
    assert client.post(path + "/start").json()["status"] == "active"
    for question_id, answer in (("q1", "Stern"), ("q2", "Sonne")):
        result = client.post(f"{path}/questions/{question_id}/answer", json={"answer": answer})
        assert result.status_code == 200, result.text
        assert result.json()["assisted"] is True
    assert result.json()["unit"]["status"] == "completed"
    with DB() as db:
        help_events = list(db.scalars(select(Activity).where(Activity.kind == "explanation")))
        assert len(help_events) == 1 and help_events[0].detail["turn_id"] == response.json()["id"]
        mastery = db.scalar(select(Mastery))
        assert mastery.independent == 0 and mastery.assisted == 1
        assert not coaching.independently_correct(db, db.get(LearningUnit, notebook["unit_id"]))


def test_provider_failure_during_active_practice_does_not_mark_help(api, notebook, transport):
    with DB.begin() as db:
        db.get(LearningUnit, notebook["unit_id"]).status = "active"

    def unavailable():
        raise ProviderError("Synthetischer Verbindungsfehler.")

    transport["effect"] = unavailable
    assert ask(notebook).status_code == 202
    finish()
    assert saved(api, notebook)[0]["status"] == "failed"
    with DB() as db:
        assert db.scalar(select(Activity.id).where(Activity.kind == "explanation")) is None


@pytest.mark.skipif(engine.dialect.name != "postgresql", reason="Requires PostgreSQL row-lock semantics")
def test_simultaneous_last_answer_finishes_before_tutor_without_retrospective_help(notebook, transport, monkeypatch):
    from threading import Event

    from schulpilot import learning, schemas
    from schulpilot.security import Principal

    monkeypatch.setattr(coaching, "schedule", lambda *args, **kwargs: None)
    with DB.begin() as db:
        unit = db.get(LearningUnit, notebook["unit_id"])
        unit.status, unit.questions = "active", tutor_practice_questions()
    first = notebook["client"].post(f"/api/units/{notebook['unit_id']}/questions/q1/answer", json={"answer": "Stern"})
    assert first.status_code == 200 and first.json()["assisted"] is False
    assert ask(notebook).status_code == 202
    called = Event()
    transport["effect"] = called.set
    with ThreadPoolExecutor(max_workers=1) as pool:
        with DB() as db:
            db.execute(
                update(LearningUnit).where(LearningUnit.id == notebook["unit_id"]).values(status=LearningUnit.status)
            )
            turn = db.scalar(select(TutorTurn))
            principal = Principal(db.get(User, turn.user_id), db.get(Session, turn.session_id))
            future = pool.submit(finish)
            assert called.wait(10), "Synthetic provider was not reached"
            answer = learning.answer(notebook["unit_id"], "q2", schemas.AnswerRequest(answer="Sonne"), principal, db)
            assert answer["assisted"] is False and answer["unit"]["status"] == "completed"
        future.result(timeout=15)
    with DB() as db:
        assert db.scalar(select(TutorTurn)).status == "ready"
        assert db.scalar(select(Activity.id).where(Activity.kind == "explanation")) is None
        mastery = db.scalar(select(Mastery))
        assert mastery.independent == 1 and mastery.assisted == 0
        assert coaching.independently_correct(db, db.get(LearningUnit, notebook["unit_id"]))


@pytest.mark.skipif(engine.dialect.name != "postgresql", reason="Requires PostgreSQL row-lock semantics")
def test_parent_source_deletion_racing_tutor_completion_succeeds_and_removes_reply(api, notebook, transport):
    from threading import Event, get_ident
    from time import monotonic

    from sqlalchemy import event, text

    with DB.begin() as db:
        db.get(LearningUnit, notebook["unit_id"]).status = "active"
    response = ask(notebook)
    assert response.status_code == 202, response.text
    completion_waiting, resume_completion = Event(), Event()
    parent_statement_seen = Event()
    state = {"tutor_thread": None, "parent_pid": None}

    def provider_returning():
        state["tutor_thread"] = get_ident()

    def before_statement(connection, cursor, statement, parameters, context, executemany):
        if get_ident() == state["tutor_thread"] and statement.startswith("UPDATE children"):
            # The tutor holds the unit row, but has not taken the child lock.
            completion_waiting.set()
            assert resume_completion.wait(10), "Tutor completion barrier was not released"
        elif completion_waiting.is_set() and state["parent_pid"] is None:
            if ("learning_units" in statement and "FOR UPDATE" in statement) or statement.startswith("UPDATE children"):
                state["parent_pid"] = connection.connection.driver_connection.info.backend_pid
                parent_statement_seen.set()

    transport["effect"] = provider_returning
    event.listen(engine, "before_cursor_execute", before_statement)
    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            tutor_future = pool.submit(finish)
            try:
                assert completion_waiting.wait(10), "Tutor did not reach its locked completion phase"
                deletion = pool.submit(api.delete, f"/api/materials/{notebook['material_id']}")
                assert parent_statement_seen.wait(10), "Deletion did not attempt its first row lock"
                # Prove there is real lock contention, rather than two requests
                # that happened to execute sequentially. No timing-only sleep.
                deadline = monotonic() + 10
                blocked = False
                while monotonic() < deadline:
                    with DB() as db:
                        blocked = db.scalar(
                            text("SELECT wait_event_type = 'Lock' FROM pg_stat_activity WHERE pid = :pid"),
                            {"pid": state["parent_pid"]},
                        )
                    if blocked:
                        break
                    resume_completion.wait(0.02)
                assert blocked, "Deletion never waited for the tutor's unit lock"
            finally:
                resume_completion.set()
            tutor_future.result(timeout=15)
            deleted = deletion.result(timeout=15)
            assert deleted.status_code == 200, deleted.text
    finally:
        resume_completion.set()
        event.remove(engine, "before_cursor_execute", before_statement)
    with DB() as db:
        assert db.get(Material, notebook["material_id"]) is None
        assert db.get(TutorTurn, response.json()["id"]) is None
        assert db.scalar(select(func.count()).select_from(TutorTurn)) == 0
        assert db.scalar(select(Job).where(Job.id == response.json()["job_id"])).status == "completed"


def test_reviewed_whale_supplement_is_separate_and_has_real_checked_provenance(notebook, transport):
    from schulpilot.foundations import WHALE

    with DB.begin() as db:
        material = db.get(Material, notebook['material_id'])
        material.subject = 'Biologie'
        material.content = 'Mensch und Hund gehören zu den Säugetieren. Fische leben im Wasser.'
    transport['output'] = {'answer':'Wale atmen mit Lungen und ihre Jungen bekommen Milch.', 'kind':'foundation',
                           'sources':[{'ref':'k1','quote':'Wale sind Säugetiere.'}],
                           'next_question':'Welches dieser Merkmale hilft dir bei der Einordnung?'}
    response = ask(notebook, question='Warum ist ein Wal ein Säugetier, obwohl er im Wasser lebt?')
    assert response.status_code == 202, response.text
    finish()
    stored = saved(notebook['client'], notebook, 'material_id')[-1]
    assert stored['status'] == 'ready', stored
    assert len(transport['calls']) == 1 and transport['calls'][0]['foundations'] == [WHALE]
    citation = stored['reply']['sources'][0]
    assert citation['origin'] == 'reviewed_supplement' and citation['reference_url'] == WHALE['reference_url']
    assert 'material_id' not in citation and stored['reply']['kind'] == 'foundation'
    transport['output'] = {'answer':'Ja, die Lungenatmung hilft bei dieser Einordnung.', 'kind':'foundation',
                           'sources':[{'ref':'k1','quote':'Wale sind Säugetiere.'}], 'next_question':None}
    assert ask(notebook, question='Die Atmung mit Lungen.', reply_to=stored['id']).status_code == 202
    finish()
    assert transport['calls'][1]['history'][0]['next_question'] == stored['reply']['next_question']
    assert transport['calls'][1]['foundations'] == [WHALE]


def test_unknown_foundation_id_or_quote_is_rejected_and_does_not_fabricate_sources():
    from schulpilot.foundations import WHALE

    payload = {'sources':[], 'foundations':[WHALE]}
    for citation in ({'ref':'k2','quote':'Wale sind Säugetiere.'}, {'ref':'k1','quote':'Wale atmen mit Kiemen.'}):
        with pytest.raises(ProviderError):
            tutor.checked_reply({'kind':'foundation','answer':'Künstliche falsche Ausgabe.',
                                 'sources':[citation],'next_question':None}, payload, [])


def test_foundation_selection_is_contextual_and_does_not_guess_other_courses():
    from schulpilot.foundations import for_question

    assert for_question('Warum ist ein Wal ein Säugetier?', [{'subject':'Biologie'}])
    assert not for_question('Was ist im Wald?', [{'subject':'Biologie'}])
    assert not for_question('Was ist ein Wal?', [{'subject':'Englisch'}])
    assert not for_question('Wie lautet Present Perfect?', [{'subject':'Englisch'}])
