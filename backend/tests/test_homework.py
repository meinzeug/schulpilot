"""Artificial homework, real API/queue, mocked transport only."""

import copy
import json
import uuid

import pytest
from schulpilot import homework
from schulpilot.db import DB, Activity, Attempt, Job, LearningUnit, Material, Session, TutorTurn, UnitSource, Usage
from schulpilot.providers import Result
from schulpilot.worker import claim, process
from sqlalchemy import func, select
from test_tutor import notebook as _notebook
from test_tutor import transport as _transport

TEXT = "Ein Rechteck ist 7 cm lang und 4 cm breit. Wie groß ist seine Fläche in cm²?"


@pytest.fixture
def book(api, household):
    yield from _notebook.__wrapped__(api, household)


@pytest.fixture
def transport(monkeypatch):
    return _transport.__wrapped__(monkeypatch)


def output(*, analyze=False, **changes):
    return {"phase": "analyzed" if analyze else "scaffold",
            "tasks": [{"title": "Rechteckfläche", "source_quote": TEXT}] if analyze else [],
            "more_tasks": False, "explanation": "Die Fläche beschreibt die Größe der ganzen Innenfläche.",
            "next_step": "Notiere Länge und Breite.", "understanding_question": "Welche Größen sind gegeben?",
            "steps": [], "source_quote": TEXT, "example": None, **changes}


def prepare(book):
    with DB.begin() as db:
        material = db.get(Material, book["material_id"])
        material.purpose, material.subject, material.topic, material.content = "homework", "Mathematik", "Flächen", TEXT


def ask(book, action, *, analysis=None, key=None, draft="", **changes):
    body = {"material_id": book["material_id"], "question": "Hilf mir beim Verstehen.",
            "homework": {"action": action, "draft": draft,
                         **({"analysis_id": analysis, "task_id": "t1"} if analysis else {})}, **changes}
    return book["client"].post(f"/api/children/{book['child']['id']}/tutor/questions", json=body,
                               headers={"Idempotency-Key": key or uuid.uuid4().hex})


def finish():
    with DB() as db:
        jid = claim(db)
    assert jid
    process(jid)


def detail(book, client=None):
    r = (client or book["client"]).get(f"/api/materials/{book['material_id']}/homework")
    assert r.status_code == 200, r.text
    return r.json()


def analyze(book, transport):
    prepare(book)
    transport["output"] = output(analyze=True)
    response = ask(book, "analyze")
    assert response.status_code == 202, response.text
    finish()
    turn = detail(book)["turns"][-1]
    assert turn["status"] == "ready", turn
    return turn["id"]


def test_complete_source_scaffold_draft_resume_and_explicit_check_without_mastery(api, book, transport):
    aid = analyze(book, transport)
    transport["output"] = output()
    key = uuid.uuid4().hex
    first = ask(book, "explain", analysis=aid, key=key)
    assert first.status_code == 202, first.text
    assert ask(book, "explain", analysis=aid, key=key).json()["id"] == first.json()["id"]
    finish()
    body = {"revision": 0, "source_revision": detail(book)["material"]["revision"], "request_key": uuid.uuid4().hex,
            "analysis_id": aid, "task_id": "t1", "draft": "Ich multipliziere beide Seiten.",
            "drafts": {"t1": "Ich multipliziere beide Seiten."}, "question": "Wie kann ich meinen Weg erklären?", "done": ["t1"]}
    route = f"/api/materials/{book['material_id']}/homework"
    saved = book["client"].put(route, json=body)
    assert saved.status_code == 200, saved.text
    assert book["client"].put(route, json=body).json()["revision"] == 1
    assert book["client"].put(route, json={**body, "request_key": uuid.uuid4().hex}).status_code == 409
    assert detail(book)["state"]["draft"] == body["draft"]
    parent = detail(book, api)
    assert "draft" not in parent["state"] and "drafts" not in parent["state"]
    assert "question" not in parent["state"]
    assert parent["state"]["done"] == ["t1"]
    assert api.put(route, json=body).status_code == 403
    assert ask(book, "check", analysis=aid).status_code == 422
    # A repeated successful analysis is reused without reserving again.
    assert ask(book, "analyze").json()["id"] == aid
    for _ in range(3):
        assert detail(book)["turns"][-1]["reply"]["next_question"]
        overview = book["client"].get(f"/api/children/{book['child']['id']}/homework").json()
        assert len(overview["photos"]) == 1
        assert "content" not in overview["photos"][0]
    assert len(transport["calls"]) == 2
    payload = transport["calls"][-1]
    assert payload["homework"]["task"]["source_quote"] == TEXT
    assert aid not in json.dumps(payload) and book["child"]["id"] not in json.dumps(payload)
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 2
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0
        assert not list(db.scalars(select(Activity).where(Activity.kind.in_(["answer", "heartbeat", "unit_completed"]))))
    assert book["client"].post("/api/auth/logout").status_code == 200
    with DB() as db:
        assert not db.get(Material, book["material_id"]).homework_state["drafts"]
        assert not db.get(Material, book["material_id"]).homework_state["question"]


def practice(book, *, key=None, source_revision=None, client=None):
    if source_revision is None:
        with DB() as db:
            source_revision = db.get(Material, book["material_id"]).revision
    return (client or book["client"]).post(f"/api/materials/{book['material_id']}/homework/practice",
        json={"source_revision": source_revision}, headers={"Idempotency-Key": key or uuid.uuid4().hex})


def practice_unit():
    return {"subject": "Mathematik", "topic": "Flächen", "explanation": "Die Fläche beschreibt die Größe der Innenfläche.",
        "questions": [{"id": f"q{i}", "type": "short", "prompt": f"Ein Rechteck ist {a} cm lang und {b} cm breit. Wie groß ist seine Fläche in cm²?",
            "options": [], "answer": str(a * b), "accepted": [], "hints": ["Multipliziere die Seitenlängen."],
            "explanation": f"Die Fläche beträgt {a * b} cm²."} for i, (a, b) in enumerate(((6, 3), (8, 5)), 1)]}


def test_homework_practice_is_explicit_idempotent_single_source_and_resumable(book, monkeypatch):
    from schulpilot import worker

    prepare(book)
    with DB.begin() as db:
        original = db.get(Material, book["material_id"])
        db.add(Material(child_id=original.child_id, school_day_id=original.school_day_id, page_number=2, title="Künstliche zweite Seite",
            subject=original.subject, topic="Andere Hausaufgaben", content="Anderes bestätigtes Material.",
            confirmed=True, status="confirmed"))
    assert detail(book)["practice"] is None
    assert detail(book)["practice"] is None
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
    key = uuid.uuid4().hex
    first = practice(book, key=key)
    assert first.status_code == 202, first.text
    assert first.json()["kind"] == "job"
    assert practice(book, key=key).json() == first.json()
    assert detail(book)["practice"] == first.json()
    assert practice(book).json() == first.json()
    calls = []

    def generate(config, function, payload, *args, **kwargs):
        calls.append(payload)
        assert function == "unit" and payload["homework_practice"] is True
        assert "Anderes bestätigtes Material" not in payload["material"]["content"]
        assert payload["required_subject"] == "Mathematik" and payload["required_topic"] == "Flächen"
        assert "session_id" not in json.dumps(payload) and book["child"]["id"] not in json.dumps(payload)
        return Result(practice_unit(), 50, 80, 12)

    monkeypatch.setattr(worker, "request_provider", generate)
    finish()
    saved = detail(book)["practice"]
    assert saved["kind"] == "unit" and saved["status"] == "not_started"
    assert practice(book).json() == saved
    assert practice(book, key=key).json()["id"] == first.json()["id"]
    with DB() as db:
        unit = db.get(LearningUnit, saved["id"])
        assert unit.introduction_seen is False and unit.active_seconds == 0
        refs = list(db.scalars(select(UnitSource).where(UnitSource.unit_id == unit.id)))
        assert [(ref.material_id, ref.revision) for ref in refs] == [(book["material_id"], 1)]
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0
    assert len(calls) == 1


@pytest.mark.parametrize("damage", ["original", "revision", "revoked", "subject", "intro"])
def test_homework_practice_rejects_repetition_stale_sources_or_revocation(book, monkeypatch, damage):
    from schulpilot import worker

    prepare(book)
    response = practice(book)
    assert response.status_code == 202, response.text

    def generate(*args, **kwargs):
        data = practice_unit()
        if damage == "original":
            data["questions"][0]["prompt"] = "Neue Übung: Ein Rechteck ist 4 cm lang und 7 cm breit. Berechne seine Fläche."
        if damage == "subject":
            data["subject"] = "Physik"
        if damage == "intro":
            data["explanation"] = "Neues Beispiel: Ein Rechteck ist 6 cm lang und 3 cm breit. Seine Fläche ist 18 cm²."
        with DB.begin() as db:
            if damage == "revision":
                db.get(Material, book["material_id"]).revision += 1
            if damage == "revoked":
                job = db.get(Job, response.json()["id"])
                db.get(Session, job.payload["session_id"]).revoked = True
        return Result(data, 50, 80, 12)

    monkeypatch.setattr(worker, "request_provider", generate)
    finish()
    with DB() as db:
        job = db.get(Job, response.json()["id"])
        assert job.status == "failed" and job.result is None
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 1
        usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
        assert usage.cost_micros == 12
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0


def test_homework_practice_rechecks_authority_and_revision_before_any_reservation(api, book):
    prepare(book)
    assert practice(book, client=api).status_code == 403
    assert practice(book, source_revision=999).status_code == 409
    with DB.begin() as db:
        db.get(Material, book["material_id"]).confirmed = False
    assert practice(book).status_code == 409
    assert detail(book)["practice"] is None
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_homework_practice_only_reuses_an_open_round_from_the_current_source_revision(book):
    prepare(book)
    with DB.begin() as db:
        unit = db.get(LearningUnit, book["unit_id"])
        unit.subject, unit.topic, unit.questions = "Mathematik", "Flächen", practice_unit()["questions"]
        unit.status = "paused"
    saved = detail(book)["practice"]
    assert saved == {"kind": "unit", "id": book["unit_id"], "status": "paused"}
    assert practice(book).json() == saved
    with DB.begin() as db:
        db.get(Material, book["material_id"]).revision += 1
    assert detail(book)["practice"] is None
    assert practice(book, source_revision=1).status_code == 409
    response = practice(book)
    assert response.status_code == 202 and response.json()["kind"] == "job"
    with DB() as db:
        assert db.get(LearningUnit, book["unit_id"]).status == "paused"
        assert db.scalar(select(func.count()).select_from(Usage)) == 1


@pytest.mark.parametrize("original,new", [
    ("Berechne 1/3 + 1/6.", r"Neue Übung: Berechne \(\frac{1}{6}+\frac{1}{3}\)."),
    ("Aufgabe 1: 47 + 26", "Berechne 26 + 47."),
    ("Was ist ein Stern?", "Neue Aufgabe: Was ist ein Stern?"),
    (TEXT, "Ein Rechteck ist 4 cm lang und 7 cm breit. Berechne seine Fläche."),
])
def test_homework_new_practice_rejects_original_signatures(original, new):
    from schulpilot.providers import ProviderError

    with pytest.raises(ProviderError, match="wiederholt"):
        homework.validate_practice_output({"questions": [{"prompt": new}]}, [original])
    homework.validate_practice_output({"questions": [{"prompt": "Berechne 1/4 + 1/8."}]}, [original])


def test_homework_practice_prompt_is_scoped_and_normal_unit_requests_stay_unchanged(book, monkeypatch):
    import httpx
    from schulpilot import providers
    from schulpilot.db import ProviderConfig

    calls = []

    class Client:
        def __init__(self, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def post(self, url, headers, json):
            calls.append(json)
            return httpx.Response(200, json={"status": "completed", "output": [{"type": "message",
                "content": [{"type": "output_text", "text": __import__("json").dumps(practice_unit())}]}],
                "usage": {"input_tokens": 50, "output_tokens": 80}})

    monkeypatch.setattr(providers.httpx, "Client", Client)
    with DB() as db:
        config = db.get(ProviderConfig, 1)
    payload = {"material": {"subject": "Mathematik", "topic": "Flächen", "content": TEXT}}
    providers.request_provider(config, "unit", payload)
    providers.request_provider(config, "unit", {**payload, "homework_practice": True,
        "required_subject": "Mathematik", "required_topic": "Flächen", "previous_prompts": [TEXT]})
    assert "Neue Anwendung nach bearbeiteten Hausaufgaben" not in calls[0]["instructions"]
    assert "Neue Anwendung nach bearbeiteten Hausaufgaben" in calls[1]["instructions"]
    assert "andere Zahlen" in calls[1]["instructions"]


FRACTION_HOMEWORK = ("Mathematik • Brüche addieren\n\n"
    "Zum Addieren brauchen die Brüche denselben\nNenner. Erweitere Zähler und Nenner mit\nderselben Zahl.\n\n"
    "Hausaufgaben\n\n" r"1) Berechne \(\frac{1}{3} + \frac{1}{6}\)." "\n\n"
    r"2) Berechne \(\frac{2}{5} + \frac{1}{10}\).")


@pytest.mark.parametrize("damage", [None, "key", "missing", "goal"])
def test_homework_fraction_practice_is_preplanned_and_goal_bound_before_transport(book, monkeypatch, damage):
    import httpx
    from schulpilot import providers
    from schulpilot.coaching import fraction_task_goal, fraction_task_signature, source_goals
    from schulpilot.db import ProviderConfig

    calls = []

    class Client:
        def __init__(self, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def post(self, url, headers, json):
            calls.append(json)
            outgoing = __import__("json").loads(json["input"][0]["content"][0]["text"])
            planned = outgoing["math_tasks"]
            assert len(planned) == 2 and outgoing["homework_practice_focus"] == ["Brüche erweitern"]
            schema = json["text"]["format"]["schema"]
            assert schema["properties"]["questions"]["minItems"] == schema["properties"]["questions"]["maxItems"] == 2
            branches = schema["$defs"]["Question"]["anyOf"]
            assert len(branches) == 2
            for task, branch in zip(planned, branches, strict=True):
                props = branch["properties"]
                for field in ("id", "type", "prompt", "answer"):
                    assert props[field]["enum"] == [task[field]]
                assert "learning_goal_id" not in props
                assert props["options"]["maxItems"] == props["accepted"]["maxItems"] == 0
                signature = fraction_task_signature(task["prompt"])
                assert signature[0] == "expand" and signature[2] in ("2", "3", "4")
                assert signature[1] not in {("1", "3"), ("1", "6"), ("2", "5"), ("1", "10")}
            unit = {"subject": "Mathematik", "topic": "Brüche addieren",
                "explanation": "Für das Addieren prüfen wir zuerst das Erweitern. Neues Erklärbeispiel: Erweitere 1/13 mit dem Faktor 2: 2/26.",
                "questions": [{**{key: value for key, value in task.items() if key != "source_excerpt"},
                    "hints": ["Erweitere beide Zahlen mit dem angegebenen Faktor."],
                    "explanation": "Multipliziere Zähler und Nenner mit dem genannten Faktor."} for task in planned]}
            if damage == "key":
                unit["questions"][0]["answer"] = "999/1000"
            elif damage == "missing":
                unit["questions"] = unit["questions"][:1]
            elif damage == "goal":
                unit["questions"][0]["learning_goal_id"] = "g1"
            return httpx.Response(200, json={"status": "completed", "output": [{"type": "message",
                "content": [{"type": "output_text", "text": __import__("json").dumps(unit)}]}],
                "usage": {"input_tokens": 50, "output_tokens": 80}})

    monkeypatch.setattr(providers.httpx, "Client", Client)
    with DB() as db:
        config = db.get(ProviderConfig, 1)
    payload = {"material": {"subject": "Mathematik", "topic": "Brüche addieren", "content": FRACTION_HOMEWORK},
        "homework_practice": True, "required_subject": "Mathematik", "required_topic": "Brüche addieren",
        "previous_prompts": [r"Berechne \(\frac{1}{3}+\frac{1}{6}\) und \(\frac{2}{5}+\frac{1}{10}\)."]}
    if damage:
        with pytest.raises(providers.ProviderError):
            providers.request_provider(config, "unit", payload)
    else:
        result = providers.request_provider(config, "unit", payload)
        goals = source_goals([payload["material"]], "Mathematik", "Brüche addieren")
        expansion = next(goal["id"] for goal in goals if goal["label"] == "Brüche erweitern")
        assert len(result.data["questions"]) == 2
        assert all(q["learning_goal_id"] == expansion == fraction_task_goal(q["prompt"], goals) for q in result.data["questions"])
        homework.validate_practice_output(result.data, [FRACTION_HOMEWORK])
    assert len(calls) == 1  # Rejected transport output never causes a fallback.


def test_homework_fraction_planning_excludes_all_original_latex_terms():
    from schulpilot.coaching import fraction_task_signature

    history = homework.practice_math_history([{"content": FRACTION_HOMEWORK}], [])
    signatures = {fraction_task_signature(prompt) for prompt in history}
    assert fraction_task_signature("1/3 + 1/6") in signatures
    assert fraction_task_signature("2/5 + 1/10") in signatures
    assert FRACTION_HOMEWORK in history
    excluded = homework.practice_math_exclusions([{"content": FRACTION_HOMEWORK}])
    assert len(excluded) == 12
    assert {fraction_task_signature(prompt) for prompt in excluded} == {
        ("expand", operand, str(factor)) for operand in (("1", "3"), ("1", "6"), ("2", "5"), ("1", "10")) for factor in (2, 3, 4)}


def test_homework_original_addition_operand_is_not_a_new_expansion_check():
    from schulpilot.providers import ProviderError

    for factor in (2, 3, 4):
        with pytest.raises(ProviderError, match="wiederholt"):
            homework.validate_practice_output({"questions": [{"prompt": f"Erweitere 1/3 mit dem Faktor {factor}."}]}, [FRACTION_HOMEWORK])
    homework.validate_practice_output({"questions": [{"prompt": "Erweitere 2/7 mit dem Faktor 3."}]}, [FRACTION_HOMEWORK])


def test_homework_coach_context_keeps_verified_prerequisite_goals_and_originals(book):
    from schulpilot import coaching
    from schulpilot.db import UnitCoaching

    prepare(book)
    with DB.begin() as db:
        material, unit = db.get(Material, book["material_id"]), db.get(LearningUnit, book["unit_id"])
        material.content, material.topic = FRACTION_HOMEWORK, "Brüche addieren"
        unit.subject, unit.topic = "Mathematik", material.topic
        unit.questions = [{"id": "q1", "type": "short", "prompt": "Erweitere 2/7 mit dem Faktor 3.",
            "answer": "6/21", "accepted": [], "options": [], "hints": ["Multipliziere beide Zahlen."],
            "explanation": "Beide Zahlen werden mit drei multipliziert.", "learning_goal_id": "g2"}]
    with DB() as db:
        unit = db.get(LearningUnit, book["unit_id"])
        signature, context, _ = coaching.context(db, unit)
        assert [(g["id"], g["label"]) for g in context["learning_goals"]] == [("g2", "Brüche erweitern")]
        assert context["homework_practice"] is True and context["homework_original_prompts"] == [FRACTION_HOMEWORK]
        assert context["completed_questions"][0]["learning_goal_id"] == "g2"
        # A previous complete catalogue is never narrowed or renumbered.
        previous = coaching.source_goals([{"content": FRACTION_HOMEWORK}], "Mathematik", "Brüche addieren")
    with DB.begin() as db:
        db.add(UnitCoaching(unit_id=book["unit_id"], status="ready", report={"learning_goals": previous}))
    with DB() as db:
        _, context, _ = coaching.context(db, db.get(LearningUnit, book["unit_id"]))
        assert context["learning_goals"] == previous
        assert context["homework_original_prompts"] == [FRACTION_HOMEWORK]
    with DB.begin() as db:
        db.get(Material, book["material_id"]).content += "\nNeue bestätigte Ergänzung."
    with DB() as db:
        assert coaching.context(db, db.get(LearningUnit, book["unit_id"]))[0] != signature


def test_non_math_homework_coach_keeps_originals_without_inventing_goal_ids(book):
    from schulpilot import coaching

    prepare(book)
    with DB.begin() as db:
        material, unit = db.get(Material, book["material_id"]), db.get(LearningUnit, book["unit_id"])
        material.subject, material.topic, material.content = "Englisch", "Simple past", "Yesterday I ____ (play) football."
        unit.subject, unit.topic = material.subject, material.topic
        unit.questions = [{"id": "q1", "type": "short", "prompt": "Complete: Last week we ____ (visit) our aunt.",
            "answer": "visited", "accepted": [], "options": [], "hints": ["Think about the past."],
            "explanation": "A regular verb has an ed ending."}]
    with DB() as db:
        _, context, _ = coaching.context(db, db.get(LearningUnit, book["unit_id"]))
        assert context["homework_practice"] is True
        assert context["homework_original_prompts"] == ["Yesterday I ____ (play) football."]
        assert context["learning_goals"] == []
        assert context["completed_questions"][0]["learning_goal_id"] is None


@pytest.mark.parametrize("damage", [None, "goal", "intro"])
@pytest.mark.parametrize("kind,phase", [("repair", "zum Verstehen"), ("check", "zum Erinnern")])
def test_homework_followup_preserves_existing_goal_ids_repair_phase_and_original_exclusions(book, monkeypatch, damage, kind, phase):
    import httpx
    from schulpilot import providers
    from schulpilot.coaching import fraction_task_signature
    from schulpilot.db import ProviderConfig

    calls = []

    class Client:
        def __init__(self, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def post(self, url, headers, json):
            calls.append(json)
            outgoing = __import__("json").loads(json["input"][0]["content"][0]["text"])
            planned = outgoing["math_tasks"]
            assert len(planned) == 2 and all(phase in task["prompt"] for task in planned)
            assert outgoing["homework_original_prompts"] == [FRACTION_HOMEWORK]
            assert all(fraction_task_signature(task["prompt"])[1] not in {("1", "3"), ("1", "6"), ("2", "5"), ("1", "10")} for task in planned)
            schema = json["text"]["format"]["schema"]
            assert schema["properties"]["questions"]["minItems"] == schema["properties"]["questions"]["maxItems"] == 2
            assert all(branch["properties"]["learning_goal_id"]["enum"] == ["g1"]
                       for branch in schema["$defs"]["PracticeQuestion"]["anyOf"])
            unit = {"subject": "Mathematik", "topic": "Brüche addieren",
                "explanation": "Für das Addieren prüfen wir zuerst das Erweitern. Neues Erklärbeispiel: Erweitere 1/13 mit dem Faktor 2: 2/26.",
                "questions": [{**{key: value for key, value in task.items() if key != "source_excerpt"},
                    "hints": ["Multipliziere beide Zahlen mit dem angegebenen Faktor."],
                    "explanation": "Erweitere beide Zahlen mit derselben Zahl.", "learning_goal_id": "g1"} for task in planned]}
            if damage == "goal":
                unit["questions"][0]["learning_goal_id"] = "g2"
            elif damage == "intro":
                unit["explanation"] = planned[0]["prompt"] + " " + planned[0]["answer"]
            return httpx.Response(200, json={"status": "completed", "output": [{"type": "message",
                "content": [{"type": "output_text", "text": __import__("json").dumps(unit)}]}],
                "usage": {"input_tokens": 50, "output_tokens": 80}})

    monkeypatch.setattr(providers.httpx, "Client", Client)
    with DB() as db:
        config = db.get(ProviderConfig, 1)
    payload = {"material": {"subject": "Mathematik", "topic": "Brüche addieren", "content": FRACTION_HOMEWORK},
        "review": True, "practice_kind": kind, "homework_practice": True,
        "homework_original_prompts": [FRACTION_HOMEWORK], "required_subject": "Mathematik", "required_topic": "Brüche addieren",
        "learning_goals": [{"id": "g1", "label": "Brüche erweitern", "source_excerpt": "Erweitere Zähler und Nenner mit\nderselben Zahl."}],
        "focus_goal_ids": ["g1"], "previous_prompts": ["Andere Tagesrunde: Erweitere 2/7 mit dem Faktor 3."]}
    if damage:
        with pytest.raises(providers.ProviderError):
            providers.request_provider(config, "unit", payload)
    else:
        result = providers.request_provider(config, "unit", payload)
        assert all(q["learning_goal_id"] == "g1" for q in result.data["questions"])
    assert len(calls) == 1


def test_generic_homework_recall_job_preserves_original_context_without_new_job_authority_flags(book, monkeypatch):
    from schulpilot import worker
    from schulpilot.db import UnitCoaching, now

    prepare(book)
    with DB.begin() as db:
        source, unit = db.get(Material, book["material_id"]), db.get(LearningUnit, book["unit_id"])
        source.content, source.topic = FRACTION_HOMEWORK, "Brüche addieren"
        unit.subject, unit.topic, unit.status, unit.completed = "Mathematik", source.topic, "completed", int(now())
        unit.questions = [{"id": "q1", "type": "short", "prompt": "Erweitere 2/7 mit dem Faktor 3.",
            "answer": "6/21", "accepted": [], "options": [], "hints": ["Multipliziere beide Zahlen."],
            "explanation": "Beide Zahlen werden mit drei multipliziert.", "learning_goal_id": "g2"}]
        db.add(UnitCoaching(unit_id=unit.id, status="ready", decision="check", report={"learning_goals": [
            {"id": "g2", "label": "Brüche erweitern", "source_excerpt": "Erweitere Zähler und Nenner mit\nderselben Zahl."}]}))
    response = book["client"].post(f"/api/children/{book['child']['id']}/units",
        json={"review_of": book["unit_id"]}, headers={"Idempotency-Key": uuid.uuid4().hex})
    assert response.status_code == 202, response.text
    calls = []

    def generate(config, function, payload, *args, **kwargs):
        calls.append(payload)
        assert function == "unit" and payload["review"] is True and payload["homework_practice"] is True
        assert payload["homework_original_prompts"] == [FRACTION_HOMEWORK] and payload["focus_goal_ids"] == ["g2"]
        return Result({"subject": "Mathematik", "topic": "Brüche addieren", "explanation": "Prüfe erneut das Erweitern.",
            "questions": [{"id": f"q{i}", "type": "short", "prompt": f"Erweitere {a}/{b} mit dem Faktor 2.",
                "answer": f"{a * 2}/{b * 2}", "accepted": [], "options": [], "hints": ["Multipliziere beide Zahlen."],
                "explanation": "Beide Zahlen werden verdoppelt.", "learning_goal_id": "g2"} for i, (a, b) in enumerate(((3, 7), (4, 9)), 1)]},
            50, 80, 12)

    monkeypatch.setattr(worker, "request_provider", generate)
    finish()
    with DB() as db:
        job = db.get(Job, response.json()["id"])
        assert job.status == "completed", job.error
        assert "homework_practice" not in job.payload and "session_id" not in job.payload
        saved = db.get(LearningUnit, job.result["unit_id"])
        assert saved.round_kind == "spaced_review" and all(q["learning_goal_id"] == "g2" for q in saved.questions)
    assert len(calls) == 1


@pytest.mark.parametrize("explanation", [
    r"Neues Beispiel: Berechne \(\frac{1}{3} + \frac{1}{6}\). Das ergibt 1/2.",
    "Neues Beispiel: Erweitere 2/7 mit dem Faktor 3: 6/21.",
])
def test_homework_intro_cannot_work_out_an_original_or_new_fraction_check(explanation):
    from schulpilot.providers import ProviderError

    data = {"explanation": explanation, "questions": [{"prompt": "Erweitere 2/7 mit dem Faktor 3."}]}
    with pytest.raises(ProviderError, match="vorweg"):
        homework.validate_practice_output(data, [FRACTION_HOMEWORK])
    data["explanation"] = "Neues Beispiel: Erweitere 1/13 mit dem Faktor 2: 2/26."
    homework.validate_practice_output(data, [FRACTION_HOMEWORK])


@pytest.mark.parametrize("action", ["explain", "hint", "plan", "example", "check", "question"])
def test_help_is_explicit_bounded_and_uses_existing_accounting(book, transport, action):
    aid = analyze(book, transport)
    transport["output"] = output(phase="feedback" if action == "check" else "scaffold",
        example={"task": "Ein Rechteck ist 3 cm lang und 2 cm breit.", "first_step": "Notiere die beiden Seiten."} if action == "example" else None)
    response = ask(book, action, analysis=aid, draft="Ich habe die Länge und Breite notiert.")
    assert response.status_code == 202, response.text
    finish()
    result = detail(book)["turns"][-1]
    assert result["status"] == "ready", result
    assert result["reply"]["action"] == action
    assert "28" not in result["reply"]["answer"]


@pytest.mark.parametrize("damage", ["leak", "quote", "task", "provider", "revision", "revoked"])
def test_rejects_unsafe_stale_or_failed_responses_and_never_retries(book, transport, damage):
    aid = analyze(book, transport)
    transport["output"] = output()
    if damage == "leak":
        transport["output"]["explanation"] = "Rechne 7 mal 4. Das ergibt 28 Quadratzentimeter."
    if damage == "quote":
        transport["output"]["source_quote"] = "Diese erfundene Aufgabe steht nicht im Foto."
    if damage == "task":
        transport["output"]["tasks"] = [{"title": "Andere Aufgabe", "source_quote": TEXT}]
    if damage in ("revision", "revoked", "provider"):
        def effect():
            if damage == "provider":
                raise RuntimeError("synthetic provider outage")
            with DB.begin() as db:
                if damage == "revision":
                    db.get(Material, book["material_id"]).revision += 1
                else:
                    from schulpilot.db import Session

                    turn = db.scalars(select(TutorTurn).order_by(TutorTurn.created.desc())).first()
                    db.get(Session, turn.session_id).revoked = True
        transport["effect"] = effect
    response = ask(book, "explain", analysis=aid)
    assert response.status_code == 202
    finish()
    with DB() as db:
        turn = db.get(TutorTurn, response.json()["id"])
        assert turn.status == "failed" and turn.reply is None
        job = db.get(Job, turn.job_id)
        assert job.status == "failed" and job.attempts == 1
    with DB() as db:
        assert claim(db) is None
    assert len(transport["calls"]) == 2


def test_three_hint_stages_are_cached_after_third_and_old_analysis_is_invalidated(book, transport):
    aid = analyze(book, transport)
    transport["output"] = output()
    for stage in range(1, 4):
        r = ask(book, "hint", analysis=aid)
        assert r.status_code == 202
        finish()
        assert transport["calls"][-1]["homework"]["hint_level"] == stage
    assert ask(book, "hint", analysis=aid).json()["status"] == "ready"
    assert len(transport["calls"]) == 4
    with DB.begin() as db:
        db.get(Material, book["material_id"]).revision += 1
    assert ask(book, "explain", analysis=aid).status_code == 409


def test_long_conversation_keeps_task_overview_and_cached_hints_without_new_cost(book, transport):
    aid = analyze(book, transport)
    transport["output"] = output()
    for _ in range(3):
        assert ask(book, "hint", analysis=aid).status_code == 202
        finish()
    with DB.begin() as db:
        original = db.get(TutorTurn, aid)
        for index in range(105):
            db.add(TutorTurn(child_id=original.child_id, user_id=original.user_id,
                material_id=original.material_id, session_id=original.session_id,
                created=original.created + index + 10, question="Künstliche gespeicherte Rückfrage",
                status="ready", source_revisions=original.source_revisions, reply=output(),
                homework_context={"action": "question", "analysis_id": aid, "task_id": "t1", "sequence": index + 5}))
        usage = db.scalar(select(func.count()).select_from(Usage))
        jobs = db.scalar(select(func.count()).select_from(Job))
    for _ in range(2):
        body = detail(book)
        assert body["older_history"] is True
        assert len(body["turns"]) == 41
        assert body["turns"][0]["id"] == aid
        assert body["turns"][0]["reply"]["tasks"][0]["id"] == "t1"
    assert ask(book, "analyze").json()["id"] == aid
    hint = ask(book, "hint", analysis=aid)
    assert hint.status_code == 202 and hint.json()["status"] == "ready"
    assert hint.json()["homework"]["hint_level"] == 3
    assert len(transport["calls"]) == 4
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == usage
        assert db.scalar(select(func.count()).select_from(Job)) == jobs


def test_child_checklist_preview_does_not_count_a_previous_source_revision(book, transport):
    aid = analyze(book, transport)
    with DB.begin() as db:
        material = db.get(Material, book["material_id"])
        material.homework_state = {"analysis_id": aid, "source_revision": material.revision, "done": ["t1", "t1"]}
    route = f"/api/children/{book['child']['id']}/homework"
    assert book["client"].get(route).json()["photos"][0]["marked_done"] == 1
    with DB.begin() as db:
        db.get(Material, book["material_id"]).revision += 1
    assert book["client"].get(route).json()["photos"][0]["marked_done"] == 0


@pytest.mark.parametrize("text, task", [
    ("Das ergibt 1/2.", "Berechne 1/3 + 1/6."),
    (r"Das ergibt \(\frac{1}{2}\).", r"Berechne \(\frac{1}{3}+\frac{1}{6}\)."),
    ("Die Dichte beträgt 3 g/cm³.", "Ein Körper hat eine Masse von 120 g und ein Volumen von 40 cm³. Berechne seine Dichte."),
])
def test_known_numeric_solution_leaks_are_detected(text, task):
    assert homework.reveals_result(text, task)


def test_analysis_refuses_invented_tasks_or_answer_titles():
    revisions = [{"id": "fake", "revision": 1, "ref": "p1", "label": "Künstlich"}]
    payload = {"homework": {"action": "analyze"}, "sources": [{"content": TEXT}]}
    from schulpilot.providers import ProviderError

    for task in ({"title": "Erfundene Übung", "source_quote": "Berechne 8 + 9."},
                 {"title": "Fläche 28", "source_quote": TEXT}):
        data = copy.deepcopy(output(analyze=True))
        data["tasks"] = [task]
        with pytest.raises(ProviderError):
            homework.checked_reply(data, payload, revisions)


@pytest.mark.parametrize("answer, expected", [("28", "correct"), ("28,0", "correct"), ("11", "incorrect"), ("28 m²", "incorrect")])
def test_clear_own_answers_are_checked_without_any_model_or_new_usage(book, transport, answer, expected):
    aid = analyze(book, transport)
    response = ask(book, "check", analysis=aid, draft=answer)
    assert response.status_code == 202, response.text
    finish()
    turn = next(t for t in detail(book)["turns"] if t["id"] == response.json()["id"])
    assert turn["status"] == "ready", turn
    assert turn["reply"]["method"] == "homework_math_v1" and turn["reply"]["outcome"] == expected
    assert len(transport["calls"]) == 1  # only the analysis, no grading model
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0


def test_analysis_instruction_and_language_gap_disclosure_are_validated():
    from schulpilot.providers import ProviderError

    quote = "Yesterday, Tom ___ (play) football."
    instruction = "Setze die regelmäßigen Verben ins simple past."
    payload = {"homework": {"action": "explain", "task": {"source_quote": quote, "instruction_quote": instruction}, "draft": ""},
               "sources": [{"content": instruction + "\n" + quote}]}
    revisions = [{"id": "fake", "revision": 1, "ref": "p1", "label": "Künstlich"}]
    with pytest.raises(ProviderError):
        homework.checked_reply(output(source_quote=quote, explanation="Setze hier played ein."), payload, revisions)
    valid = homework.checked_reply(output(source_quote=quote, explanation="Das Signalwort beschreibt einen vergangenen Zeitpunkt."), payload, revisions)
    assert valid["mode"] == "homework"
    data = output(analyze=True)
    data["tasks"][0]["instruction_quote"] = "Diese erfundene Anleitung ist nicht im Foto."
    with pytest.raises(ProviderError):
        homework.checked_reply(data, {"homework": {"action": "analyze"}, "sources": [{"content": TEXT}]}, revisions)


def test_literal_formula_evidence_survives_index_transport_without_retyping():
    from schulpilot.providers import strict_schema

    text = "Erweitere beide Brüche.\n\n1) Berechne \\(\\frac{1}{3}+\\frac{1}{6}\\)."
    schema = strict_schema(homework.HomeworkOutput, preserve_limits=True)
    payload, candidates = homework.bind_sources(schema, {"sources": [{"content": text}]})
    assert candidates == payload["homework_source_candidates"]
    assert all(candidate in text for candidate in candidates)
    assert "source_quote" not in schema["properties"]
    assert "source_quote_index" in schema["$defs"]["Task"]["required"]
    original = output(analyze=True)
    original["tasks"] = [{"title": "Brüche addieren", "source_quote_index": 1, "instruction_quote_index": 0}]
    del original["source_quote"]
    original["source_quote_index"] = None
    restored = homework.decode_sources(original, candidates)
    result = homework.checked_reply(restored, {"homework": {"action": "analyze"}, "sources": [{"content": text}]},
                                    [{"id": "fake", "revision": 1, "label": "Künstlich"}])
    assert result["tasks"][0]["source_quote"] == candidates[1]
    for index in [True, -1, len(candidates), "1", None]:
        bad = {"source_quote_index": None, "tasks": [{"source_quote_index": index, "instruction_quote_index": None}]}
        with pytest.raises((ValueError, TypeError)):
            homework.decode_sources(bad, candidates)


def test_provider_adapter_decodes_bound_homework_evidence(book, monkeypatch):
    import httpx
    from schulpilot import providers
    from schulpilot.db import ProviderConfig

    calls = []
    class Client:
        def __init__(self, **kwargs):
            pass
        def __enter__(self):
            return self
        def __exit__(self, *args):
            pass
        def post(self, url, headers, json):
            calls.append(json)
            result = output(analyze=True)
            result["tasks"] = [{"title": "Rechteckfläche", "source_quote_index": 0, "instruction_quote_index": None}]
            del result["source_quote"]
            result["source_quote_index"] = 0
            return httpx.Response(200, json={"status": "completed", "output": [{"type": "message", "content": [
                {"type": "output_text", "text": __import__("json").dumps(result)}]}],
                "usage": {"input_tokens": 100, "output_tokens": 100}})
    monkeypatch.setattr(providers.httpx, "Client", Client)
    with DB() as db:
        config = db.get(ProviderConfig, 1)
    result = providers.request_provider(config, "tutor", {"homework": {"action": "analyze"}, "sources": [{"content": TEXT}]})
    assert result.data["tasks"][0]["source_quote"] == TEXT
    assert result.data["source_quote"] == TEXT
    assert "source_quote_index" in calls[0]["text"]["format"]["schema"]["required"]


@pytest.mark.parametrize("action,phase", [("question", "scaffold"), ("explain", "scaffold"), ("check", "feedback"), ("example", "scaffold")])
def test_help_schema_binds_phase_and_selected_task_instead_of_guessing(action, phase):
    from schulpilot.providers import strict_schema

    schema = strict_schema(homework.HomeworkOutput, preserve_limits=True)
    _, candidates = homework.bind_sources(schema, {"homework": {"action": action, "task": {"source_quote": TEXT}},
                                                   "sources": [{"content": TEXT}]})
    assert schema["properties"]["phase"]["enum"] == [phase, "clarify"]
    indices = schema["properties"]["source_quote_index"]["enum"]
    assert [candidates[index] for index in indices] == [TEXT]
    assert schema["properties"]["tasks"]["maxItems"] == 0
    assert schema["properties"]["understanding_question"]["type"] == "string"
    if action != "example":
        assert schema["properties"]["example"] == {"type": "null"}


def test_existing_instruction_is_not_duplicated_and_example_is_in_followup_context(book, transport):
    aid = analyze(book, transport)
    with DB.begin() as db:
        turn = db.get(TutorTurn, aid)
        reply = copy.deepcopy(turn.reply)
        reply["tasks"][0]["instruction_quote"] = TEXT
        turn.reply = reply
    example = {"task": "Ein anderes Rechteck ist 5 cm lang und 3 cm breit.", "first_step": "Notiere 5 mal 3."}
    transport["output"] = output(example=example)
    previous = ask(book, "example", analysis=aid)
    finish()
    transport["output"] = output()
    assert ask(book, "question", analysis=aid, reply_to=previous.json()["id"]).status_code == 202
    finish()
    context = transport["calls"][-1]
    assert context["sources"][0]["content"] == TEXT
    assert context["history"][-1]["example"] == example


def test_validation_audit_is_static_and_does_not_store_model_text(book, transport):
    aid = analyze(book, transport)
    transport["output"] = output(source_quote="Private invented reference must not appear in audit")
    r = ask(book, "explain", analysis=aid)
    finish()
    with DB() as db:
        turn = db.get(TutorTurn, r.json()["id"])
        job = db.get(Job, turn.job_id)
        assert job.error_code == "invalid_output"
        assert job.result == {"validation_reason": "Unverified quotation"}
        assert "Private" not in job.error


@pytest.mark.parametrize("prefix", ["1\n", "1) ", "1. ", ""])
def test_standalone_photo_task_number_is_not_a_third_measurement(prefix):
    reply = homework.deterministic_reply({"homework": {"action": "check", "draft": "28",
        "task": {"source_quote": prefix + TEXT}}}, [{"id": "fake", "label": "Künstlich"}])
    assert reply and reply["outcome"] == "correct"
