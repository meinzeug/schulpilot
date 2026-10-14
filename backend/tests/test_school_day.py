"""Only synthetic images/text and mocked provider transport in this test module."""

import io
import json
import uuid
import zipfile
from concurrent.futures import ThreadPoolExecutor

import pytest
from conftest import HEADERS, create_child
from fastapi.testclient import TestClient
from PIL import Image
from schulpilot.config import settings
from schulpilot.db import DB, Child, Job, LearningUnit, Material, ProviderConfig, SchoolDay, UnitSource, Usage
from schulpilot.main import app
from schulpilot.providers import Result
from schulpilot.security import encrypt
from schulpilot.synthetic import sample_unit
from schulpilot.worker import claim, process
from sqlalchemy import func, select


def allow_synthetic_test_transport():
    object.__setattr__(settings, "real_data_approved", True)
    object.__setattr__(settings, "privacy_evidence", "Isolated test; synthetic data and mocked transport only")
    with DB.begin() as db:
        c = db.get(ProviderConfig, 1)
        c.provider, c.model = "openai", "synthetic-mock-model"
        c.encrypted_key = encrypt("SYNTHETIC-TEST-KEY")
        c.emergency_stop = False
        c.image_capable = c.structured_capable = c.privacy_approved = True
        c.capability_evidence = c.privacy_evidence = c.pricing_evidence = "Synthetic isolated test fixture"
        c.input_per_million_micros = c.output_per_million_micros = 0
        c.reserve_micros = 1000


def image_bytes():
    output = io.BytesIO()
    Image.new("RGB", (80, 60), "white").save(output, "JPEG", exif=Image.Exif())
    return output.getvalue()


def finish_job(api, response):
    assert response.status_code == 202, response.text
    job_id = response.json()["id"]
    with DB() as db:
        assert claim(db) == job_id
    process(job_id)
    return api.get(f"/api/jobs/{job_id}").json()


def unit_for(subject):
    if subject == "Mathematik":
        return sample_unit()
    q = {
        "id": "word",
        "type": "choice",
        "prompt": "Was heißt cat auf Deutsch?",
        "options": ["Katze", "Hund"],
        "answer": "Katze",
        "accepted": [],
        "hints": ["Das Tier miaut."],
        "explanation": "Cat bedeutet Katze.",
    }
    q2 = {
        **q,
        "id": "gap",
        "type": "gap",
        "prompt": "dog heißt auf Deutsch __.",
        "options": [],
        "answer": "Hund",
        "hints": ["Das Tier bellt."],
        "explanation": "Dog bedeutet Hund.",
    }
    return {
        "subject": subject,
        "topic": "Tiere",
        "explanation": "Cat heißt Katze; dog heißt Hund.",
        "questions": [q, q2],
    }


def prepare_day(api, child, monkeypatch, *, subjects=("Mathematik", "Mathematik", "Englisch")):
    allow_synthetic_test_transport()
    with DB.begin() as db:
        db.get(Child, child["id"]).preferences = {
            "weekdays": list(range(7)),
            "daily_minutes": 40,
            "weekly_minutes": 240,
            "session_minutes": 10,
        }
    day = api.post(f"/api/children/{child['id']}/school-day/today").json()
    extraction_index = 0
    calls = []

    def provider(config, function, payload, image_bytes=None, *, synthetic_fixture=False):
        nonlocal extraction_index
        calls.append((function, payload))
        assert synthetic_fixture is False
        if function == "extract":
            index = extraction_index
            extraction_index += 1
            return Result(
                {
                    "subject": subjects[index],
                    "topic": f"Testthema {index + 1}",
                    "content": f"SYNTHETISCHER SEITENINHALT {index + 1}",
                    "uncertainties": ["Synthetische unsichere Stelle bitte prüfen"],
                    "homework": [],
                },
                10,
                20,
                0,
            )
        if function == "unit":
            return Result(sample_unit(), 20, 40, 0)
        assert function == "package"
        return Result(
            {"units": [{**unit_for(g["subject"]), "group_id": g["id"]} for g in payload["selected_groups"]]}, 50, 100, 0
        )

    monkeypatch.setattr("schulpilot.worker.request_provider", provider)
    for _ in subjects:
        response = api.post(
            f"/api/children/{child['id']}/materials?school_day_id={day['id']}",
            files={"file": ("synthetic.jpg", image_bytes(), "image/jpeg")},
        )
        assert response.status_code == 201, response.text
    assert api.put(f"/api/school-days/{day['id']}/stage", json={"stage": "review"}).status_code == 200
    day = api.get(f"/api/school-days/{day['id']}").json()
    for page in day["pages"]:
        response = api.post(f"/api/materials/{page['id']}/extract", headers={"Idempotency-Key": uuid.uuid4().hex})
        assert finish_job(api, response)["status"] == "completed"
        page = api.get(f"/api/materials/{page['id']}").json()
        response = api.put(
            f"/api/materials/{page['id']}/confirm",
            json={**{k: page[k] for k in ("subject", "topic", "content", "homework")}, "uncertainties_resolved": True},
        )
        assert response.status_code == 200, response.text
    return api.get(f"/api/school-days/{day['id']}").json(), calls


def test_multipage_package_resume_sources_answers_export_and_deletion(api, household, monkeypatch):
    user, child = household
    day, calls = prepare_day(api, child, monkeypatch)
    assert day["confirmed_count"] == 3
    assert len(day["plan"]["groups"]) == 2 and day["plan"]["estimated_minutes"] == 16
    assert api.post(f"/api/children/{child['id']}/school-day/today").json()["id"] == day["id"]
    key = {"Idempotency-Key": "daily-package"}
    response = api.post(f"/api/school-days/{day['id']}/package", headers=key)
    replay = api.post(f"/api/school-days/{day['id']}/package", headers=key)
    assert response.json()["id"] == replay.json()["id"]
    assert api.put(f"/api/school-days/{day['id']}/stage", json={"stage": "collecting"}).status_code == 409
    result = finish_job(api, response)
    assert result["status"] == "completed", result
    package_payload = calls[-1][1]
    assert [p["content"] for p in package_payload["materials"]][:2] == [
        "SYNTHETISCHER SEITENINHALT 1",
        "SYNTHETISCHER SEITENINHALT 2",
    ]
    assert [p["group_id"] for p in package_payload["materials"]] == ["g1", "g1", "g2"]
    finished = api.get(f"/api/children/{child['id']}/school-day/today").json()["day"]
    assert finished["stage"] == "ready" and len(finished["units"]) == 2
    math = next(u for u in finished["units"] if u["subject"] == "Mathematik")
    assert len(math["source_material_ids"]) == 2 and math["estimated_minutes"] == 8
    overview = api.get(f"/api/children/{child['id']}/overview").json()
    assert {x["id"] for x in overview["plan"]["today"]} == set(result["result"]["unit_ids"])
    with TestClient(app, headers=HEADERS) as kid:
        login = kid.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}).json()
        kid.headers["Authorization"] = "Bearer " + login["token"]
        view = kid.get(f"/api/school-days/{day['id']}").json()
        assert all("answer" not in q for u in view["units"] for q in u["questions"])
        assert kid.post(f"/api/units/{math['id']}/start").status_code == 200
        q = math["questions"][0]
        assert kid.post(f"/api/units/{math['id']}/questions/{q['id']}/hint").status_code == 200
        assert (
            kid.post(f"/api/units/{math['id']}/questions/{q['id']}/answer", json={"answer": q["answer"]}).json()[
                "outcome"
            ]
            == "correct"
        )
    parent = api.get(f"/api/school-days/{day['id']}").json()
    assert next(u for u in parent["units"] if u["id"] == math["id"])["questions"][0]["attempts"][0]["assisted"] is True
    export = api.get(f"/api/families/{user['families'][0]['id']}/export")
    with zipfile.ZipFile(io.BytesIO(export.content)) as archive:
        data = json.loads(archive.read("family.json"))
        assert data["children"][0]["school_days"][0]["id"] == day["id"]
        assert len(data["children"][0]["unit_sources"]) == 3
    paths = []
    with DB() as db:
        assert len(list(db.scalars(select(Usage)))) == 4  # three OCR calls and one package call
        paths = [settings.data_dir / "uploads" / m.path for m in db.scalars(select(Material))]
    assert api.request("DELETE", "/api/account", json={"password": "secure-parent-pass-123"}).status_code == 200
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(SchoolDay)) == 0
        assert db.scalar(select(func.count()).select_from(UnitSource)) == 0
    assert all(not p.exists() for p in paths)


def test_wizard_guards_unconfirmed_pages_siblings_and_real_data_gate(api, household):
    user, child = household
    sibling = create_child(api, user, "test-sibling")
    day = api.post(f"/api/children/{child['id']}/school-day/today").json()
    assert (
        api.post(f"/api/school-days/{day['id']}/package", headers={"Idempotency-Key": "unconfirmed"}).status_code == 409
    )
    assert (
        api.post(
            f"/api/children/{child['id']}/materials?school_day_id={day['id']}",
            files={"file": ("synthetic.jpg", image_bytes())},
        ).status_code
        == 503
    )
    assert api.post(f"/api/school-days/{day['id']}/synthetic-pages").status_code == 403
    with TestClient(app, headers=HEADERS) as kid:
        login = kid.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}).json()
        kid.headers["Authorization"] = "Bearer " + login["token"]
        other = api.post(f"/api/children/{sibling['id']}/school-day/today").json()
        assert kid.get(f"/api/school-days/{other['id']}").status_code == 404
        assert kid.post(f"/api/children/{sibling['id']}/school-day/today").status_code == 404
        assert kid.put(f"/api/school-days/{other['id']}/stage", json={"stage": "review"}).status_code == 404
        assert (
            kid.post(f"/api/school-days/{other['id']}/package", headers={"Idempotency-Key": "foreign"}).status_code
            == 404
        )
    allow_synthetic_test_transport()
    assert (
        api.post(
            f"/api/children/{child['id']}/materials?school_day_id={other['id']}",
            files={"file": ("synthetic.jpg", image_bytes())},
        ).status_code
        == 404
    )


@pytest.mark.parametrize("change", ["source", "preferences", "missing_group", "wrong_subject"])
def test_package_is_atomic_and_rejects_changed_sources_goals_or_bad_output(api, household, monkeypatch, change):
    _, child = household
    day, _ = prepare_day(api, child, monkeypatch)

    def provider(*args, **kwargs):
        if change in ("source", "preferences"):
            with DB.begin() as db:
                if change == "source":
                    db.get(Material, day["pages"][1]["id"]).revision += 1
                else:
                    db.get(Child, child["id"]).preferences = {"weekdays": [], "daily_minutes": 10}
        units = [{**unit_for(g["subject"]), "group_id": g["id"]} for g in day["plan"]["groups"]]
        if change == "missing_group":
            units.pop()
        if change == "wrong_subject":
            units[-1]["subject"] = "Falsches Fach"
        return Result({"units": units}, 20, 100, 0)

    monkeypatch.setattr("schulpilot.worker.request_provider", provider)
    response = api.post(f"/api/school-days/{day['id']}/package", headers={"Idempotency-Key": "atomic"})
    result = finish_job(api, response)
    assert result["status"] == "failed" and result["error"]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 0
        assert db.get(SchoolDay, day["id"]).stage == "review"
        assert len(list(db.scalars(select(Usage)))) == 4
    assert api.get(f"/api/school-days/{day['id']}").json()["last_error"]


def test_parent_time_budget_and_focus_leave_excess_subjects_visible(api, household, monkeypatch):
    _, child = household
    day, _ = prepare_day(api, child, monkeypatch)
    with DB.begin() as db:
        db.get(Child, child["id"]).preferences = {
            "weekdays": list(range(7)),
            "daily_minutes": 10,
            "weekly_minutes": 60,
            "session_minutes": 8,
            "focus_subjects": ["Englisch"],
        }
    view = api.get(f"/api/school-days/{day['id']}").json()
    assert [g["subject"] for g in view["plan"]["groups"] if g["selected"]] == ["Englisch"]
    result = finish_job(api, api.post(f"/api/school-days/{day['id']}/package", headers={"Idempotency-Key": "bounded"}))
    assert result["status"] == "completed"
    view = api.get(f"/api/school-days/{day['id']}").json()
    assert [u["subject"] for u in view["units"]] == ["Englisch"]
    assert len(view["pages"]) == 3 and any(g["subject"] == "Mathematik" for g in view["plan"]["groups"])


def test_parent_goal_keeps_its_time_and_package_fits_remaining_five_minutes(api, household, monkeypatch):
    _, child = household
    day, _ = prepare_day(api, child, monkeypatch)
    with DB.begin() as db:
        db.get(Child, child["id"]).preferences = {
            "weekdays": list(range(7)),
            "daily_minutes": 15,
            "weekly_minutes": 100,
            "session_minutes": 10,
        }
    goal = api.post(
        f"/api/children/{child['id']}/assignments",
        json={
            "kind": "parent",
            "subject": "Deutsch",
            "topic": "Lesen",
            "note": "Synthetischer verbindlicher Testauftrag",
            "mandatory": True,
        },
    )
    assert goal.status_code == 201, goal.text
    preview = api.get(f"/api/school-days/{day['id']}").json()["plan"]
    assert preview["estimated_minutes"] == 5 and preview["available_minutes"] == 5
    result = finish_job(
        api, api.post(f"/api/school-days/{day['id']}/package", headers={"Idempotency-Key": "parent-time"})
    )
    assert result["status"] == "completed", result
    overview = api.get(f"/api/children/{child['id']}/overview").json()
    assert overview["plan"]["today"][0]["id"] == goal.json()["id"]
    assert any(x["estimated_minutes"] == 5 for x in overview["plan"]["today"] if x["kind"] == "unit")


def test_parallel_package_requests_reserve_only_one_call(api, household, monkeypatch):
    _, child = household
    day, _ = prepare_day(api, child, monkeypatch)
    token = api.headers["Authorization"]

    def submit(index):
        with TestClient(app, headers={**HEADERS, "Authorization": token}) as client:
            return client.post(
                f"/api/school-days/{day['id']}/package", headers={"Idempotency-Key": f"parallel-{index}"}
            ).status_code

    with ThreadPoolExecutor(max_workers=2) as pool:
        codes = list(pool.map(submit, range(2)))
    assert sorted(codes) == [202, 409]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job).where(Job.kind == "package")) == 1
        assert len(list(db.scalars(select(Usage)))) == 4


def test_review_reuses_all_confirmed_pages_of_the_original_package(api, household, monkeypatch):
    from schulpilot import coaching, worker

    _, child = household
    day, calls = prepare_day(api, child, monkeypatch, subjects=("Mathematik", "Mathematik"))
    result = finish_job(api, api.post(f"/api/school-days/{day['id']}/package", headers={"Idempotency-Key": "original"}))
    unit_id = result["result"]["unit_ids"][0]
    unit = api.get(f"/api/units/{unit_id}").json()
    original_provider = worker.request_provider

    def coach_provider(config, function, payload):
        with DB() as db:
            item = db.scalar(select(coaching.UnitCoaching).where(coaching.UnitCoaching.status == "pending"))
            return Result(
                coaching.synthetic_report(db, db.get(LearningUnit, item.unit_id), payload["next_action"]), cost_micros=0
            )

    def review_provider(config, function, payload, image_bytes=None, **kwargs):
        if function == "unit" and payload.get("review"):
            calls.append((function, payload))
            with DB() as db:
                return Result(
                    coaching.synthetic_report(db, db.get(LearningUnit, unit_id), "check")["next_unit"], cost_micros=0
                )
        return original_provider(config, function, payload, image_bytes, **kwargs)

    monkeypatch.setattr(coaching, "request_provider", coach_provider)
    monkeypatch.setattr(worker, "request_provider", review_provider)
    with TestClient(app, headers=HEADERS) as kid:
        login = kid.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}).json()
        kid.headers["Authorization"] = "Bearer " + login["token"]
        assert kid.post(f"/api/units/{unit_id}/start").status_code == 200
        for question in unit["questions"]:
            assert (
                kid.post(
                    f"/api/units/{unit_id}/questions/{question['id']}/answer", json={"answer": question["answer"]}
                ).status_code
                == 200
            )
        assert kid.get(f"/api/units/{unit_id}").json()["status"] == "completed"
        with DB() as db:
            coaching_job = claim(db)
        process(coaching_job)
        check_id = kid.get(f"/api/units/{unit_id}").json()["coaching"]["next_unit_id"]
        assert kid.post(f"/api/units/{check_id}/start").status_code == 200
        check = api.get(f"/api/units/{check_id}").json()
        for q in check["questions"]:
            assert (
                kid.post(f"/api/units/{check_id}/questions/{q['id']}/answer", json={"answer": q["answer"]}).status_code
                == 200
            )
        with DB() as db:
            coaching_job = claim(db)
        process(coaching_job)
        result = finish_job(
            kid,
            kid.post(
                f"/api/children/{child['id']}/units", json={"review_of": unit_id}, headers={"Idempotency-Key": "review"}
            ),
        )
        assert result["status"] == "completed", result
    assert calls[-1][0] == "unit"
    assert "SEITENINHALT 1" in calls[-1][1]["material"]["content"]
    assert "SEITENINHALT 2" in calls[-1][1]["material"]["content"]
    review = api.get(f"/api/units/{result['result']['unit_id']}").json()
    assert set(review["source_material_ids"]) == set(unit["source_material_ids"])
    assert review["review_of"] == unit_id


def test_unconfirmed_page_can_be_replaced_but_confirmed_homework_cannot_be_removed(api, household, monkeypatch):
    _, child = household
    day, _ = prepare_day(api, child, monkeypatch, subjects=("Mathematik",))
    assert api.put(f"/api/school-days/{day['id']}/stage", json={"stage": "collecting"}).status_code == 200
    assert api.delete(f"/api/school-days/{day['id']}/pages/{day['pages'][0]['id']}").status_code == 409
    page = api.post(
        f"/api/children/{child['id']}/materials?school_day_id={day['id']}",
        files={"file": ("synthetic.jpg", image_bytes())},
    ).json()
    with DB() as db:
        path = settings.data_dir / "uploads" / db.get(Material, page["id"]).path
    assert path.is_file()
    response = api.delete(f"/api/school-days/{day['id']}/pages/{page['id']}")
    assert response.status_code == 200 and len(response.json()["pages"]) == 1
    assert not path.exists()


@pytest.mark.parametrize("invalid_output", [False, True])
def test_day_fixture_provider_discards_all_arbitrary_caller_data(api, monkeypatch, invalid_output):
    import httpx
    from schulpilot import providers
    from schulpilot.fixtures import PACKAGE_FIXTURE_ID
    from test_live_fixture import setup_free

    setup_free()
    captured = []

    class Client:
        def __init__(self, **_):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *_):
            pass

        def post(self, url, headers, json):
            captured.append(json)
            data = {"units": [{**sample_unit(), "group_id": "g1"}]}
            if invalid_output:
                data["units"][0]["PRIVATE-FIELD"] = "PRIVATE-ANSWER"
            return httpx.Response(
                200,
                json={
                    "choices": [{"finish_reason": "stop", "message": {"content": __import__("json").dumps(data)}}],
                    "usage": {"prompt_tokens": 1, "completion_tokens": 1, "cost": 0},
                },
            )

    monkeypatch.setattr(providers, "verify_free_endpoint", lambda *_: None)
    monkeypatch.setattr(providers.httpx, "Client", Client)
    with DB() as db:
        config = db.get(ProviderConfig, 1)

    def invoke():
        return providers.request_provider(
            config,
            "package",
            {"materials": ["PRIVATE-CONTENT"], "name": "PRIVATE-NAME"},
            b"PRIVATE-IMAGE",
            synthetic_fixture=PACKAGE_FIXTURE_ID,
        )

    if invalid_output:
        with pytest.raises(providers.ProviderError) as error:
            invoke()
        assert "PRIVATE-" not in str(error.value) and "units.0.field" in str(error.value)
    else:
        result = invoke()
        assert result.cost_micros == 0 and len(result.data["units"]) == 1
    body = json.dumps(captured[0])
    assert "PRIVATE-" not in body
    assert "page_number" in body and "Kürzen" in json.dumps(captured[0], ensure_ascii=False)


def test_extension_keeps_answers_and_only_generates_for_new_material(api, household, monkeypatch):
    _, child = household
    day, calls = prepare_day(api, child, monkeypatch, subjects=("Mathematik",))
    first = finish_job(api, api.post(f"/api/school-days/{day['id']}/package", headers={"Idempotency-Key": "v1"}))
    old_id = first["result"]["unit_ids"][0]
    with TestClient(app, headers=HEADERS) as kid:
        login = kid.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}).json()
        kid.headers["Authorization"] = "Bearer " + login["token"]
        original = api.get(f"/api/units/{old_id}").json()
        assert kid.post(f"/api/units/{old_id}/start").status_code == 200
        q = original["questions"][0]
        assert (
            kid.post(f"/api/units/{old_id}/questions/{q['id']}/answer", json={"answer": q["answer"]}).status_code == 200
        )
        assert kid.post(f"/api/school-days/{day['id']}/extend").json()["package_version"] == 1
        assert kid.post(f"/api/school-days/{day['id']}/extend").status_code == 200
    page = api.post(
        f"/api/children/{child['id']}/materials?school_day_id={day['id']}", files={"file": ("extra.jpg", image_bytes())}
    ).json()
    with DB.begin() as db:
        m = db.get(Material, page["id"])
        m.subject, m.topic, m.content, m.confirmed, m.status = "Mathematik", "Erweitern", "1/2 = 2/4", True, "confirmed"
    api.put(f"/api/school-days/{day['id']}/stage", json={"stage": "review"})
    preview = api.get(f"/api/school-days/{day['id']}").json()["plan"]
    assert preview["available_minutes"] == 32
    assert preview["groups"][0]["new_material_ids"] == [page["id"]]
    second = finish_job(api, api.post(f"/api/school-days/{day['id']}/package", headers={"Idempotency-Key": "v2"}))
    assert second["status"] == "completed", second
    assert second["result"]["package_version"] == 2
    final = api.get(f"/api/school-days/{day['id']}").json()
    assert len(final["units"]) == 2 and final["plan"]["estimated_minutes"] == 0
    old = next(u for u in final["units"] if u["id"] == old_id)
    assert len(old["questions"][0]["attempts"]) == 1 and old["package_version"] == 1
    assert len(calls[-1][1]["materials"]) == 2  # shared context without replacing v1
    assert sorted(u["package_version"] for u in final["units"]) == [1, 2]
    assert api.post(f"/api/school-days/{day['id']}/extend").status_code == 200
    closed = api.post(f"/api/school-days/{day['id']}/finish-additions").json()
    assert closed["stage"] == "ready" and closed["package_version"] == 2 and len(closed["units"]) == 2


def test_upload_replay_after_stage_change_and_conflicting_key(api, household):
    _, child = household
    allow_synthetic_test_transport()
    day = api.post(f"/api/children/{child['id']}/school-day/today").json()
    path = f"/api/children/{child['id']}/materials?school_day_id={day['id']}"
    key = {"Idempotency-Key": "fixed-upload-key-123456"}
    first = api.post(path, headers=key, files={"file": ("x.jpg", image_bytes())})
    assert first.status_code == 201
    assert first.json()["quality_warnings"]
    api.put(f"/api/school-days/{day['id']}/stage", json={"stage": "review"})
    second = api.post(path, headers=key, files={"file": ("x.jpg", image_bytes())})
    assert first.json()["id"] == second.json()["id"]
    other = io.BytesIO()
    Image.new("RGB", (80, 60), "black").save(other, "JPEG")
    assert api.post(path, headers=key, files={"file": ("x.jpg", other.getvalue())}).status_code == 409
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Material)) == 1


def test_history_pagination_ordering_and_sibling_guards(api, household, monkeypatch):
    user, child = household
    day, _ = prepare_day(api, child, monkeypatch, subjects=("Mathematik", "Mathematik"))
    api.put(f"/api/school-days/{day['id']}/stage", json={"stage": "collecting"})
    ids = [m["id"] for m in reversed(day["pages"])]
    ordered = api.put(f"/api/school-days/{day['id']}/page-order", json={"material_ids": ids})
    assert ordered.status_code == 200
    assert [m["id"] for m in ordered.json()["pages"]] == ids
    assert api.put(f"/api/school-days/{day['id']}/page-order", json={"material_ids": [ids[0]] * 2}).status_code == 422
    with DB.begin() as db:
        db.add(SchoolDay(child_id=child["id"], school_date="2000-01-01"))
    first = api.get(f"/api/children/{child['id']}/school-days?limit=1").json()
    assert first["days"][0]["id"] == day["id"] and first["next_before"] == day["date"]
    older = api.get(f"/api/children/{child['id']}/school-days?before={first['next_before']}").json()
    archived_id = older["days"][0]["id"]
    assert api.get(f"/api/school-days/{archived_id}").json()["read_only"] is True
    assert api.post(f"/api/school-days/{archived_id}/extend").status_code == 409
    sibling = create_child(api, user, "history-sibling")
    with TestClient(app, headers=HEADERS) as kid:
        login = kid.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}).json()
        kid.headers["Authorization"] = "Bearer " + login["token"]
        assert kid.get(f"/api/children/{sibling['id']}/school-days").status_code == 404
        assert kid.put(f"/api/school-days/{archived_id}/page-order", json={"material_ids": []}).status_code == 409


def test_introduction_is_saved_idempotently_without_claiming_assistance(api, household, monkeypatch):
    _, child = household
    day, _ = prepare_day(api, child, monkeypatch, subjects=("Mathematik",))
    result = finish_job(api, api.post(f"/api/school-days/{day['id']}/package", headers={"Idempotency-Key": "intro"}))
    unit_id = result["result"]["unit_ids"][0]
    assert api.post(f"/api/units/{unit_id}/introduction").status_code == 403
    with TestClient(app, headers=HEADERS) as kid:
        login = kid.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}).json()
        kid.headers["Authorization"] = "Bearer " + login["token"]
        assert kid.post(f"/api/units/{unit_id}/introduction").status_code == 409
        kid.post(f"/api/units/{unit_id}/start")
        for _ in range(2):
            assert kid.post(f"/api/units/{unit_id}/introduction").json()["introduction_seen"] is True
        unit = api.get(f"/api/units/{unit_id}").json()
        q = unit["questions"][0]
        answer = kid.post(f"/api/units/{unit_id}/questions/{q['id']}/answer", json={"answer": q["answer"]}).json()
        assert answer["assisted"] is False
        assert kid.get(f"/api/units/{unit_id}").json()["introduction_seen"] is True


def test_unreadable_page_requests_a_retake_and_cannot_be_confirmed(api, household, monkeypatch):
    _, child = household
    allow_synthetic_test_transport()
    day = api.post(f"/api/children/{child['id']}/school-day/today").json()
    page = api.post(
        f"/api/children/{child['id']}/materials?school_day_id={day['id']}",
        files={"file": ("synthetic.jpg", image_bytes())},
    ).json()
    api.put(f"/api/school-days/{day['id']}/stage", json={"stage": "review"})
    monkeypatch.setattr(
        "schulpilot.worker.request_provider",
        lambda *a, **kw: Result(
            {
                "legibility": "unreadable",
                "subject": "",
                "topic": "",
                "content": "",
                "uncertainties": ["Bitte ein lesbares Foto aufnehmen."],
                "homework": [],
            },
            1,
            1,
            0,
        ),
    )
    result = finish_job(
        api, api.post(f"/api/materials/{page['id']}/extract", headers={"Idempotency-Key": "unreadable"})
    )
    assert result["status"] == "completed"
    material = api.get(f"/api/materials/{page['id']}").json()
    assert material["status"] == "unreadable" and material["content"] == ""
    assert (
        api.put(
            f"/api/materials/{page['id']}/confirm",
            json={
                "subject": "Mathematik",
                "topic": "Brüche",
                "content": "Erfunden",
                "homework": [],
                "uncertainties_resolved": True,
            },
        ).status_code
        == 409
    )
    assert (
        api.post(f"/api/school-days/{day['id']}/package", headers={"Idempotency-Key": "no-invention"}).status_code
        == 409
    )
    assert api.delete(f"/api/school-days/{day['id']}/pages/{page['id']}").status_code == 200


def test_deferred_parent_goal_starts_on_selected_day_and_reuses_related_pages(api, household, monkeypatch):
    from datetime import timedelta

    from schulpilot.learning import local_day

    _, child = household
    day, calls = prepare_day(api, child, monkeypatch, subjects=("Mathematik", "Mathematik"))
    with DB() as db:
        today = local_day(db.get(Child, child["id"]))
    body = {
        "kind": "parent",
        "subject": "Mathematik",
        "topic": "Brüche später",
        "material_id": day["pages"][0]["id"],
        "scheduled_for": (today + timedelta(days=2)).isoformat(),
        "mandatory": True,
    }
    goal = api.post(f"/api/children/{child['id']}/assignments", json=body).json()
    legacy_edit = {k: v for k, v in body.items() if k != "scheduled_for"}
    legacy_edit["note"] = "Zusätzlicher Hinweis aus einem älteren Client"
    preserved = api.put(f"/api/children/{child['id']}/assignments/{goal['id']}", json=legacy_edit)
    assert preserved.status_code == 200 and preserved.json()["scheduled_for"] == body["scheduled_for"]
    plan = api.get(f"/api/children/{child['id']}/overview").json()["plan"]
    assert not any(x["id"] == goal["id"] for x in plan["today"])
    assert any(x["id"] == goal["id"] for x in plan["later"])
    response = api.post(
        f"/api/children/{child['id']}/units", json={"assignment_id": goal["id"]}, headers={"Idempotency-Key": "not-yet"}
    )
    assert response.status_code == 409
    body["scheduled_for"] = today.isoformat()
    assert api.put(f"/api/children/{child['id']}/assignments/{goal['id']}", json=body).status_code == 200
    result = finish_job(
        api,
        api.post(
            f"/api/children/{child['id']}/units", json={"assignment_id": goal["id"]}, headers={"Idempotency-Key": "now"}
        ),
    )
    assert result["status"] == "completed", result
    assert (
        "SEITENINHALT 1" in calls[-1][1]["material"]["content"]
        and "SEITENINHALT 2" in calls[-1][1]["material"]["content"]
    )
