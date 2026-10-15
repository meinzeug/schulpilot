"""Real routes/queue with artificial notebooks and a synthetic transport only."""

import copy
import json
import uuid
from concurrent.futures import ThreadPoolExecutor

import pytest
from conftest import HEADERS, create_child, register
from fastapi.testclient import TestClient
from schulpilot import tutor
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


@pytest.mark.parametrize("kind", ["clarification", "not_in_material"])
def test_clarification_and_missing_content_remain_explicit(api, notebook, transport, kind):
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


@pytest.mark.parametrize("when", ["before", "during"])
@pytest.mark.parametrize("change", ["source", "logout"])
def test_changed_source_or_revoked_session_blocks_before_and_after_provider(api, notebook, transport, when, change):
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
