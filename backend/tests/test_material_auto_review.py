"""Artificial local pixels and scripted transport only; no real child data."""

import copy
import hashlib
import json

import pytest
from conftest import HEADERS
from fastapi.testclient import TestClient
from schulpilot import material_review as review
from schulpilot.config import runtime_settings, settings
from schulpilot.db import (
    DB,
    Audit,
    Child,
    Installation,
    Job,
    Material,
    ProviderConfig,
    SchoolDay,
    Session,
    Usage,
    User,
    now,
)
from schulpilot.extraction import TranscriptionOutput
from schulpilot.main import app
from schulpilot.provider_attempts import counts
from schulpilot.providers import ProviderError, Result, request_provider
from schulpilot.school_preparation import advance_one as advance_day
from schulpilot.security import digest, encrypt
from schulpilot.source_lineage import learning_source
from schulpilot.source_lineage_models import SourceRevision
from schulpilot.worker import claim, process
from sqlalchemy import func, select
from test_extraction import fake_transport, transcription
from test_school_day import allow_synthetic_test_transport, image_bytes

PATH = "/api/admin/installation/material-review"


@pytest.fixture
def operator():
    with DB.begin() as db:
        user = User(
            username="synthetic-review-operator",
            display_name="Test Admin",
            role="admin",
            verified=True,
            password_hash="no-password",
        )
        db.add(user)
        db.flush()
        db.add(
            Session(
                user_id=user.id,
                token_hash=digest("synthetic-review-token"),
                device="Synthetic test",
                expires=int(now()) + 3600,
            )
        )
        identifier = user.id
    with TestClient(
        app, headers={**HEADERS, "Authorization": "Bearer synthetic-review-token", "X-Schulpilot-Account": identifier}
    ) as client:
        yield client


def mode(value="automatic"):
    with DB.begin() as db:
        item = db.get(Installation, 1)
        item.encrypted_settings = encrypt(json.dumps({"material_review_mode": value}))
        item.revision += 1


def reading(text="Ein Bruch besteht aus Zähler und Nenner.", **changes):
    return TranscriptionOutput.model_validate(
        transcription(blocks=[dict(kind="paragraph", text=text)], **changes)
    ).as_material()


@pytest.fixture
def pipeline(api, household, monkeypatch):
    allow_synthetic_test_transport()
    mode()
    calls = []
    outputs = [reading()]

    def provider(config, function, payload, image_bytes=None, *, synthetic_fixture=False):
        assert function == "extract"
        calls.append(copy.deepcopy(payload))
        out = outputs.pop(0) if len(outputs) > 1 else outputs[0]
        if isinstance(out, Exception):
            raise out
        return Result(copy.deepcopy(out), 12, 30, 17, cost_source="reported")

    monkeypatch.setattr("schulpilot.worker.request_provider", provider)
    monkeypatch.setattr(review, "request_provider", provider)
    return dict(api=api, child=household[1], parent=household[0], calls=calls, outputs=outputs)


def upload(pipeline, day=None):
    url = f"/api/children/{pipeline['child']['id']}/materials" + (f"?school_day_id={day['id']}" if day else "")
    response = pipeline["api"].post(url, files={"file": ("synthetic.jpg", image_bytes(), "image/jpeg")})
    assert response.status_code == 201, response.text
    return response.json()


def first(pipeline, page):
    response = pipeline["api"].post(
        f"/api/materials/{page['id']}/extract", headers={"Idempotency-Key": "first-" + page["id"]}
    )
    assert response.status_code == 202, response.text
    with DB() as db:
        assert claim(db) == response.json()["id"]
    process(response.json()["id"])
    with DB() as db:
        assert db.get(Job, response.json()["id"]).status == "completed"
    return response.json()["id"]


def check(pipeline):
    review.advance_one()
    with DB() as db:
        identifier = claim(db)
        assert identifier
        assert db.get(Job, identifier).payload.get(review.KEY)
    process(identifier)
    return identifier


def test_policy_encrypted_admin_only_revision_cas_and_no_content(operator, api, household):
    assert runtime_settings().material_review_mode == "manual"
    assert api.get(PATH).status_code == 403
    current = operator.get(PATH).json()
    assert set(current) == {"mode", "revision"} and current["mode"] == "manual"
    body = dict(mode="automatic", expected_revision=current["revision"])
    changed = operator.put(PATH, json=body)
    assert changed.status_code == 200 and changed.json() == dict(mode="automatic", revision=current["revision"] + 1)
    assert operator.put(PATH, json=body).status_code == 409
    current = changed.json()
    assert operator.put(PATH, json=dict(mode="automatic", expected_revision=current["revision"])).json() == current
    with DB() as db:
        item = db.get(Installation, 1)
        assert "automatic" not in item.encrypted_settings
        assert runtime_settings(db).material_review_mode == "automatic"
        rows = list(db.scalars(select(Audit).where(Audit.action == "installation.material_review_update")))
        assert len(rows) == 1 and rows[0].target.endswith(":automatic")
    assert operator.put("/api/admin/installation/site", json={"material_review_mode": "manual"}).status_code == 409


@pytest.mark.parametrize(
    "body",
    [
        {"mode": "auto", "expected_revision": 1},
        {"mode": "automatic", "expected_revision": True},
        {"mode": "automatic", "expected_revision": 0},
        {"mode": "automatic", "expected_revision": 1, "child_id": "a" * 32},
    ],
)
def test_admin_policy_strict_contract(operator, body):
    assert operator.put(PATH, json=body).status_code == 422


def test_standalone_two_separate_saved_reserved_passes_and_idempotent_restart(pipeline):
    page = upload(pipeline)
    initial = first(pipeline, page)
    with DB() as db:
        assert not db.get(Material, page["id"]).confirmed
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
    identifier = check(pipeline)
    with DB() as db:
        job = db.get(Job, identifier)
        m = db.get(Material, page["id"])
        assert job.status == "completed", job.error
        assert m.confirmed and m.revision == 2 and m.confirmation_digest is None
        assert review.public_status(db, m)["status"] == "checked"
        assert learning_source(db, m)["content"] == m.content
        assert len(list(db.scalars(select(Usage)))) == 2
        old = db.get(Job, initial)
        assert old.status == "completed" and old.result["material_check_done"] == "queued"
        versions = list(
            db.scalars(
                select(SourceRevision).where(SourceRevision.material_id == m.id).order_by(SourceRevision.sequence)
            )
        )
        assert [v.cause for v in versions] == ["extraction", "auto_check_reading", "auto_check"]
        assert versions[2].receipt["first_snapshot_id"] == versions[0].id
        assert versions[2].receipt["second_snapshot_id"] == versions[1].id
        assert versions[2].receipt["base_prompt_digest"] == hashlib.sha256(review.CHECK_SYSTEM.encode()).hexdigest()
        assert counts(db, m.child_id, "extract", [dict(id=m.id, revision=1)], 0) == (1, 1)
    review.advance_one()
    review.advance_one()
    process(identifier)
    assert len(pipeline["calls"]) == 2
    assert pipeline["calls"][0] == {
        "task": "transcribe_entire_image_verbatim",
        "reading_order": "top_to_bottom_including_every_paragraph_and_example",
    }
    assert set(pipeline["calls"][1]) == {"task", "transcription_check"}


def test_manual_mode_never_queues_checks_or_confirms(pipeline):
    mode("manual")
    page = upload(pipeline)
    first(pipeline, page)
    review.advance_one()
    with DB() as db:
        m = db.get(Material, page["id"])
        assert not m.confirmed and m.status == "review"
        assert db.scalar(select(func.count()).select_from(Job)) == 1
    assert len(pipeline["calls"]) == 1


def test_ambiguous_block_excluded_while_safe_text_available(pipeline):
    first_text = reading()
    second = TranscriptionOutput.model_validate(
        transcription(
            blocks=[
                dict(kind="paragraph", text="Der Nenner zählt gleich große Teile."),
                dict(kind="formula", text="2/?", reading_uncertainties=["Nenner rechts unleserlich."]),
            ],
            legibility="partial",
            uncertainties=["Nenner rechts unleserlich."],
        )
    ).as_material()
    pipeline["outputs"][:] = [first_text, second]
    page = upload(pipeline)
    first(pipeline, page)
    identifier = check(pipeline)
    with DB() as db:
        assert db.get(Job, identifier).status == "completed"
        m = db.get(Material, page["id"])
        safe = learning_source(db, m)
        assert m.confirmed and m.uncertainties
        assert safe["content"] == "Der Nenner zählt gleich große Teile."
        assert safe["factual_status"] == "partly_excluded" and not m.confirmation_digest
        assert review.public_status(db, m)["status"] == "checked_with_gaps"


def test_visible_wrong_student_work_preserved_not_replaced_with_right_answer(pipeline):
    wrong = TranscriptionOutput.model_validate(
        transcription(blocks=[dict(kind="formula", text="1+1=3", literal_role="student_work")])
    ).as_material()
    pipeline["outputs"][:] = [wrong, reading("1+1=2")]
    page = upload(pipeline)
    first(pipeline, page)
    check(pipeline)
    with DB() as db:
        m = db.get(Material, page["id"])
        assert "1+1=3" in m.content
        assert learning_source(db, m)["content"] == ""
        versions = list(db.scalars(select(SourceRevision).where(SourceRevision.material_id == m.id)))
        assert any(row.cause == "extraction" and row.snapshot["content"] == "1+1=3" for row in versions)
        assert any(row.cause == "auto_check_reading" and row.snapshot["content"] == "1+1=2" for row in versions)


@pytest.mark.parametrize("fault", ["revoked", "expired", "family", "source", "image", "policy", "provider", "snapshot"])
def test_second_pass_guard_rejects_change_before_transport(pipeline, fault):
    page = upload(pipeline)
    initial = first(pipeline, page)
    review.advance_one()
    with DB.begin() as db:
        job = db.scalar(select(Job).where(Job.payload[review.KEY]["version"].as_integer() == 1))
        identifier = job.id
        if fault == "revoked":
            db.get(Session, job.payload[review.KEY]["origin"]["session_id"]).revoked = True
        elif fault == "expired":
            db.get(Session, job.payload[review.KEY]["origin"]["session_id"]).expires = 1
        elif fault == "family":
            job.payload = {
                **job.payload,
                review.KEY: {
                    **job.payload[review.KEY],
                    "origin": {**job.payload[review.KEY]["origin"], "family_id": "f" * 32},
                },
            }
        elif fault == "source":
            db.get(Material, page["id"]).content = "Different saved source"
        elif fault == "image":
            (settings.data_dir / "uploads" / db.get(Material, page["id"]).path).write_bytes(b"changed")
        elif fault == "policy":
            db.get(Installation, 1).revision += 1
        elif fault == "provider":
            db.get(ProviderConfig, 1).revision += 1
        elif fault == "snapshot":
            job.payload = {**job.payload, review.KEY: {**job.payload[review.KEY], "snapshot_digest": "0" * 64}}
        assert claim(db) == identifier
    process(identifier)
    assert len(pipeline["calls"]) == 1
    with DB() as db:
        assert db.get(Job, identifier).status == "failed"
        assert not db.get(Material, page["id"]).confirmed
        assert db.get(Job, initial).status == "completed"


@pytest.mark.parametrize("change", ["source", "revoked", "policy", "provider", "image"])
def test_post_transport_guard_does_not_publish_late_check(pipeline, monkeypatch, change):
    page = upload(pipeline)
    first(pipeline, page)

    def late(*args, **kwargs):
        with DB.begin() as db:
            m = db.get(Material, page["id"])
            if change == "source":
                m.revision += 1
            elif change == "revoked":
                for session in db.scalars(select(Session).where(Session.user_id == pipeline["parent"]["id"])):
                    session.revoked = True
            elif change == "policy":
                db.get(Installation, 1).revision += 1
            elif change == "provider":
                db.get(ProviderConfig, 1).revision += 1
            else:
                (settings.data_dir / "uploads" / m.path).write_bytes(b"changed")
        return Result(reading(), 14, 40, 19, cost_source="reported")

    monkeypatch.setattr(review, "request_provider", late)
    identifier = check(pipeline)
    with DB() as db:
        assert db.get(Job, identifier).status == "failed"
        assert not db.get(Material, page["id"]).confirmed
        usage = db.scalar(select(Usage).where(Usage.job_id == identifier))
        assert usage.cost_micros == 19 and usage.status == "failed_billed"


def test_failed_check_is_honest_persistent_and_not_retried(pipeline):
    pipeline["outputs"][:] = [reading(), ProviderError("artificial failed call")]
    page = upload(pipeline)
    first(pipeline, page)
    identifier = check(pipeline)
    for _ in range(3):
        review.advance_one()
    with DB() as db:
        m = db.get(Material, page["id"])
        assert not m.confirmed and review.held(db, m)
        assert review.public_status(db, m)["status"] == "failed"
        assert learning_source(db, m)["content"] == ""
        assert db.get(Job, identifier).status == "failed"
        assert db.scalar(select(func.count()).select_from(Job)) == 2
    assert len(pipeline["calls"]) == 2


def test_second_pass_transport_uses_image_and_full_bounded_literal_not_history(pipeline, monkeypatch):
    page = upload(pipeline)
    first(pipeline, page)
    with DB() as db:
        firstjob = db.scalar(select(Job).where(Job.status == "completed"))
        snap = db.get(SourceRevision, firstjob.result["source_snapshot_id"])
        payload = review.request(snap)
        config = db.get(ProviderConfig, 1)
    captured = fake_transport(monkeypatch, transcription(), provider="openai")
    result = request_provider(
        config, "extract", {**payload, "grade": 6, "recent_outcomes": ["private not allowed"]}, image_bytes()
    )
    assert result.data["content"]
    assert len(captured) == 1
    body = json.dumps(captured[0], ensure_ascii=False)
    assert "EIGENEN ZWEITEN" in body and "transcription_check" in body
    assert "recent_outcomes" not in body and "private not allowed" not in body
    assert "data:image/jpeg;base64," in body


def test_multiple_day_pages_each_get_own_check_and_technical_failure_does_not_block_others(pipeline):
    api = pipeline["api"]
    day = api.post(f"/api/children/{pipeline['child']['id']}/school-day/today").json()
    p1 = upload(pipeline, day)
    p2 = upload(pipeline, day)
    pipeline["outputs"][:] = [reading(), ProviderError("artificial check failure"), reading(), reading()]
    response = api.post(f"/api/school-days/{day['id']}/prepare", headers={"Idempotency-Key": "day-auto-test"})
    assert response.status_code == 202, response.text
    for _ in range(4):
        advance_day()
        with DB() as db:
            identifier = claim(db)
        assert identifier
        process(identifier)
    # Do not execute package generation in this reading-only regression.
    with DB() as db:
        m1, m2 = db.get(Material, p1["id"]), db.get(Material, p2["id"])
        assert not m1.confirmed and review.held(db, m1)
        assert m2.confirmed
        saved = db.get(SchoolDay, day["id"])
        assert review.pipeline_ready(db, saved, [m1, m2])
        assert len(list(db.scalars(select(Usage)))) == 4
    assert len(pipeline["calls"]) == 4


def test_empty_first_and_second_reading_persist_without_fabricated_text(pipeline):
    empty = TranscriptionOutput.model_validate(
        transcription(blocks=[], legibility="unreadable", uncertainties=["Das künstliche Foto ist leer."])
    ).as_material()
    pipeline["outputs"][:] = [empty, empty]
    page = upload(pipeline)
    first(pipeline, page)
    check(pipeline)
    with DB() as db:
        m = db.get(Material, page["id"])
        assert m.confirmed and not m.content and review.held(db, m)
        assert learning_source(db, m)["content"] == ""
        assert db.scalar(select(func.count()).select_from(SourceRevision)) == 3


def test_day_after_check_failure_creates_only_safe_sources_package_and_path(pipeline, monkeypatch):
    from schulpilot.db import LearningUnit, UnitSource
    from schulpilot.study_path import sources
    from test_school_day import unit_for

    api = pipeline["api"]
    day = api.post(f"/api/children/{pipeline['child']['id']}/school-day/today").json()
    p1, p2 = upload(pipeline, day), upload(pipeline, day)
    pipeline["outputs"][:] = [
        reading("Unsafe first reading"),
        ProviderError("synthetic failed countercheck"),
        reading(),
        reading(),
    ]
    assert api.post(f"/api/school-days/{day['id']}/prepare", headers={"Idempotency-Key": "safe-day"}).status_code == 202
    for _ in range(4):
        advance_day()
        with DB() as db:
            identifier = claim(db)
        assert identifier
        process(identifier)

    calls = []

    def package(config, function, payload, *args, **kwargs):
        assert function == "package"
        calls.append(copy.deepcopy(payload))
        assert "Unsafe first reading" not in json.dumps(payload)
        return Result(
            {"units": [{**unit_for(g["subject"]), "group_id": g["id"]} for g in payload["selected_groups"]]},
            20,
            50,
            23,
            cost_source="reported",
        )

    monkeypatch.setattr("schulpilot.worker.request_provider", package)
    advance_day()
    with DB() as db:
        identifier = claim(db)
        assert identifier
    process(identifier)
    advance_day()
    with DB() as db:
        job = db.get(Job, identifier)
        assert job.status == "completed", job.error
        saved = db.get(SchoolDay, day["id"])
        assert saved.preparation["status"] == "ready", saved.preparation.get("error")
        assert [m.id for m in sources(db, saved)] == [p2["id"]]
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 1
        assert set(db.scalars(select(UnitSource.material_id))) == {p2["id"]}
        assert not db.get(Material, p1["id"]).confirmed
        assert len(list(db.scalars(select(Usage)))) == 5
    assert len(calls) == 1


def test_policy_toggle_does_not_scan_old_manual_readings(pipeline):
    mode("manual")
    page = upload(pipeline)
    first(pipeline, page)
    mode("automatic")
    review.advance_one()
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 1
        assert not db.get(Material, page["id"]).confirmed


def test_explicit_day_resubmit_can_check_existing_manual_reading(pipeline):
    mode("manual")
    api = pipeline["api"]
    day = api.post(f"/api/children/{pipeline['child']['id']}/school-day/today").json()
    page = upload(pipeline, day)
    assert (
        api.post(f"/api/school-days/{day['id']}/prepare", headers={"Idempotency-Key": "manual-day"}).status_code == 202
    )
    advance_day()
    with DB() as db:
        identifier = claim(db)
    process(identifier)
    advance_day()
    with DB() as db:
        assert db.get(SchoolDay, day["id"]).preparation["status"] == "needs_review"
    mode("automatic")
    response = api.post(f"/api/school-days/{day['id']}/prepare", headers={"Idempotency-Key": "explicit-auto-day"})
    assert response.status_code == 202, response.text
    advance_day()
    with DB() as db:
        identifier = claim(db)
        assert db.get(Job, identifier).payload.get(review.KEY)
    process(identifier)
    with DB() as db:
        assert db.get(Material, page["id"]).confirmed
        assert db.scalar(select(func.count()).select_from(Usage)) == 2


def test_failed_reservation_is_not_an_automatic_retry_loop(pipeline):
    page = upload(pipeline)
    initial = first(pipeline, page)
    with DB.begin() as db:
        db.get(ProviderConfig, 1).emergency_stop = True
    for _ in range(3):
        review.advance_one()
    with DB() as db:
        assert db.get(Job, initial).result["material_check_done"] == "blocked"
        assert db.scalar(select(func.count()).select_from(Job)) == 1
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
        assert not db.get(Material, page["id"]).confirmed
    assert len(pipeline["calls"]) == 1


@pytest.mark.parametrize(
    "region",
    [
        dict(left=0, top=0, right=500, bottom=500),
        dict(left=0, top=0, right=501, bottom=501),
        dict(left=10, top=10, right=501, bottom=501),
        None,
    ],
)
def test_nearby_or_missing_boxes_cannot_make_substituted_student_answer_groundtruth(pipeline, region):
    old = TranscriptionOutput.model_validate(
        transcription(
            blocks=[
                dict(
                    kind="formula",
                    text="2+2=5",
                    literal_role="student_work",
                    image_region=dict(left=0, top=0, right=500, bottom=500),
                )
            ]
        )
    ).as_material()
    replacement = dict(kind="formula", text="2+2=4", literal_role="example")
    if region:
        replacement["image_region"] = region
    new = TranscriptionOutput.model_validate(transcription(blocks=[replacement])).as_material()
    pipeline["outputs"][:] = [old, new]
    page = upload(pipeline)
    first(pipeline, page)
    check(pipeline)
    with DB() as db:
        m = db.get(Material, page["id"])
        assert "2+2=5" in m.content
        assert learning_source(db, m)["content"] == ""
        assert m.confirmed and m.uncertainties


@pytest.mark.parametrize("count,length", [(80, 4), (3, 11000)])
def test_conservative_merge_stays_within_original_schema_or_fails_honestly(pipeline, count, length):
    # Each individual provider result is valid, but retaining the old protected
    # reading must not silently overflow the shared block/content limits.
    old_blocks = [
        dict(kind="paragraph", text=("A" * length) + str(i), literal_role="student_work") for i in range(count)
    ]
    new_blocks = [dict(kind="paragraph", text=("B" * length) + str(i)) for i in range(count)]
    if count == 3:
        old_blocks, new_blocks = old_blocks[:2], new_blocks[:2]
    old = TranscriptionOutput.model_validate(transcription(blocks=old_blocks)).as_material()
    new = TranscriptionOutput.model_validate(transcription(blocks=new_blocks)).as_material()
    pipeline["outputs"][:] = [old, new]
    page = upload(pipeline)
    first(pipeline, page)
    identifier = check(pipeline)
    with DB() as db:
        m = db.get(Material, page["id"])
        assert db.get(Job, identifier).status == "failed"
        assert review.held(db, m) and not m.confirmed
        assert m.content == old["content"]
        assert learning_source(db, m)["content"] == ""


def test_auto_check_routing_uses_verified_binding_and_preserves_reserved_reason(pipeline, monkeypatch):
    from schulpilot.model_routing import selection
    from test_model_routing import setup_policy

    setup_policy(pipeline["parent"]["families"][0]["id"])
    with DB.begin() as db:
        family = db.get(
            __import__("schulpilot.db", fromlist=["Family"]).Family, pipeline["parent"]["families"][0]["id"]
        )
        family.budget_micros = 2_000_000
    page = upload(pipeline)
    first(pipeline, page)
    captured = []

    def bound(config, function, payload, *args, **kwargs):
        captured.append(selection(config))
        return Result(reading(), 12, 30, 17, cost_source="reported")

    monkeypatch.setattr(review, "request_provider", bound)
    identifier = check(pipeline)
    with DB() as db:
        usage = db.scalar(select(Usage).where(Usage.job_id == identifier))
        assert usage.route_snapshot["tier"] == "sol"
        assert usage.route_snapshot["reason"] == "recorded_transcription_review"
        assert captured == [usage.route_snapshot]
        assert db.get(Job, identifier).status == "completed"


def test_double_coordinator_does_not_reserve_second_check_again(pipeline):
    page = upload(pipeline)
    first(pipeline, page)
    review.advance_one()
    for _ in range(5):
        review.advance_one()
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 2
        assert db.scalar(select(func.count()).select_from(Usage)) == 2
    assert len(pipeline["calls"]) == 1


@pytest.mark.parametrize("fault", ["status", "settled", "family", "child", "function", "key", "amount"])
def test_only_current_real_unsettled_bound_reservation_can_dispatch(pipeline, fault):
    page = upload(pipeline)
    first(pipeline, page)
    review.advance_one()
    with DB.begin() as db:
        job = db.scalar(select(Job).where(Job.payload[review.KEY]["version"].as_integer() == 1))
        identifier = job.id
        usage = db.scalar(select(Usage).where(Usage.job_id == identifier))
        if fault == "status":
            usage.status = "failed_not_sent"
        elif fault == "settled":
            usage.settlement_version = 1
        elif fault in ("family", "child"):
            # Closed synthetic mismatch: existing FK identifiers avoid invalid
            # database fixtures while a mocked guard-facing projection proves
            # these fields are checked independently of provider metadata.
            from schulpilot.db import Family

            family = db.get(Family, usage.family_id)
            family_id = usage.family_id
            if fault == "family":
                other = Family(name="Other synthetic family", commerce_required=False)
                db.add(other)
                db.flush()
                usage.family_id = other.id
            else:
                other_user = User(
                    username="other-synthetic-reservation-child",
                    display_name="Other synthetic child",
                    role="child",
                    verified=True,
                    password_hash="synthetic",
                )
                db.add(other_user)
                db.flush()
                other = Child(family_id=family_id, user_id=other_user.id, grade=6)
                db.add(other)
                db.flush()
                usage.child_id = other.id
            assert family
        elif fault == "function":
            usage.function = "unit"
        elif fault == "key":
            usage.reservation_key = "0" * 64
        else:
            usage.reserved_micros += 1
        assert claim(db) == identifier
    process(identifier)
    assert len(pipeline["calls"]) == 1
    with DB() as db:
        assert not db.get(Material, page["id"]).confirmed
        assert db.get(Job, identifier).status == "failed"


def test_settled_during_transport_rejects_publication_without_double_settlement(pipeline, monkeypatch):
    from schulpilot.providers import settle

    page = upload(pipeline)
    first(pipeline, page)

    def concurrent_cancel(*args, **kwargs):
        with DB.begin() as db:
            job = db.scalar(select(Job).where(Job.payload[review.KEY]["version"].as_integer() == 1))
            usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
            settle(db, usage, Result({}, 0, 0, 0, cost_source="cancelled"), failed=True)
        return Result(reading(), 30, 40, 19, cost_source="reported")

    monkeypatch.setattr(review, "request_provider", concurrent_cancel)
    identifier = check(pipeline)
    with DB() as db:
        assert db.get(Job, identifier).status == "failed"
        assert not db.get(Material, page["id"]).confirmed
        usage = db.scalar(select(Usage).where(Usage.job_id == identifier))
        assert usage.settlement_version == 1 and usage.cost_micros == 0


def test_all_unreadable_day_is_saved_without_false_learning_or_human_blocker(pipeline):
    from schulpilot.db import LearningUnit

    api = pipeline["api"]
    day = api.post(f"/api/children/{pipeline['child']['id']}/school-day/today").json()
    page = upload(pipeline, day)
    empty = TranscriptionOutput.model_validate(
        transcription(blocks=[], legibility="unreadable", uncertainties=["Künstliche unleserliche Fläche."])
    ).as_material()
    pipeline["outputs"][:] = [empty, empty]
    assert (
        api.post(f"/api/school-days/{day['id']}/prepare", headers={"Idempotency-Key": "empty-day"}).status_code == 202
    )
    for _ in range(2):
        advance_day()
        with DB() as db:
            identifier = claim(db)
        process(identifier)
    for _ in range(3):
        advance_day()
    response = api.get(f"/api/school-days/{day['id']}")
    assert response.status_code == 200
    assert response.json()["preparation"]["status"] == "saved"
    assert response.json()["preparation"]["error"] is None
    assert response.json()["stage"] == "ready"
    with DB() as db:
        assert db.get(Material, page["id"])
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 0
        assert db.scalar(select(func.count()).select_from(Job)) == 2


def test_completed_gets_never_create_or_advance_ai_jobs(pipeline):
    page = upload(pipeline)
    first(pipeline, page)
    for _ in range(3):
        assert pipeline["api"].get(f"/api/materials/{page['id']}").status_code == 200
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 1
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
    assert len(pipeline["calls"]) == 1


def test_failed_first_read_is_not_retried_and_other_day_page_continues(pipeline):
    api = pipeline["api"]
    day = api.post(f"/api/children/{pipeline['child']['id']}/school-day/today").json()
    p1, p2 = upload(pipeline, day), upload(pipeline, day)
    pipeline["outputs"][:] = [ProviderError("artificial first read unavailable"), reading(), reading()]
    assert (
        api.post(f"/api/school-days/{day['id']}/prepare", headers={"Idempotency-Key": "failed-first-day"}).status_code
        == 202
    )
    for _ in range(3):
        advance_day()
        with DB() as db:
            identifier = claim(db)
        assert identifier
        process(identifier)
    with DB() as db:
        bad, good = db.get(Material, p1["id"]), db.get(Material, p2["id"])
        assert not bad.confirmed and review.held(db, bad)
        assert good.confirmed
        assert review.pipeline_ready(db, db.get(SchoolDay, day["id"]), [bad, good])
        receipt = db.scalar(select(SourceRevision).where(SourceRevision.material_id == bad.id))
        assert receipt.receipt["second_check_performed"] is False
        assert review.public_status(db, bad)["status"] == "failed"
        assert db.scalar(select(func.count()).select_from(Job)) == 3
    assert len(pipeline["calls"]) == 3


def test_automatic_many_pages_use_existing_finite_separately_reserved_package_parts(pipeline, monkeypatch):
    from schulpilot.db import LearningUnit
    from test_package_parts_worker import CASE, bounded_output

    api = pipeline["api"]
    day = api.post(f"/api/children/{pipeline['child']['id']}/school-day/today").json()
    pages = [upload(pipeline, day) for _ in range(4)]
    pipeline["outputs"][:] = [reading(CASE["source"], subject=CASE["subject"], topic="Künstlicher Wasserkreislauf")]
    assert (
        api.post(f"/api/school-days/{day['id']}/prepare", headers={"Idempotency-Key": "four-auto-pages"}).status_code
        == 202
    )
    for _ in range(8):
        advance_day()
        with DB() as db:
            identifier = claim(db)
        assert identifier
        process(identifier)
    calls = []

    def package(config, function, payload, *args, **kwargs):
        assert function == "package"
        assert type(payload["package_partition"]) is int
        assert len(payload["materials"]) <= 3
        calls.append(copy.deepcopy(payload))
        return Result(bounded_output(payload), 30, 70, 31, cost_source="reported")

    monkeypatch.setattr("schulpilot.worker.request_provider", package)
    for _ in range(2):
        advance_day()
        with DB() as db:
            identifier = claim(db)
        assert identifier
        process(identifier)
        with DB() as db:
            job = db.get(Job, identifier)
            assert job.status == "completed", job.error
    advance_day()
    with DB() as db:
        saved = db.get(SchoolDay, day["id"])
        assert saved.preparation["status"] == "ready", saved.preparation.get("error")
        assert saved.preparation["package_completed_parts"] == 2
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 2
        assert db.scalar(select(func.count()).select_from(Usage)) == 10
        assert all(db.get(Material, p["id"]).confirmed for p in pages)
    assert [c["package_partition"] for c in calls] == [0, 1]


def test_parallel_auto_policy_saves_use_one_revision_and_one_audit(operator):
    from concurrent.futures import ThreadPoolExecutor

    from schulpilot.db import engine

    if engine.dialect.name != "postgresql":
        pytest.skip("Real row-lock policy CAS is covered on PostgreSQL")
    revision = operator.get(PATH).json()["revision"]
    headers = dict(operator.headers)

    def save(_):
        with TestClient(app, headers=headers) as client:
            return client.put(PATH, json={"mode": "automatic", "expected_revision": revision}).status_code

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(save, range(2)))
    assert sorted(results) == [200, 409]
    with DB() as db:
        assert db.get(Installation, 1).revision == revision + 1
        assert (
            db.scalar(
                select(func.count()).select_from(Audit).where(Audit.action == "installation.material_review_update")
            )
            == 1
        )


def test_parallel_auto_coordinators_reserve_exactly_one_second_job(pipeline):
    from concurrent.futures import ThreadPoolExecutor

    from schulpilot.db import engine

    if engine.dialect.name != "postgresql":
        pytest.skip("Real row-lock coordinator race is covered on PostgreSQL")
    page = upload(pipeline)
    first(pipeline, page)
    with ThreadPoolExecutor(max_workers=2) as pool:
        list(pool.map(lambda _: review.advance_one(), range(2)))
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 2
        assert db.scalar(select(func.count()).select_from(Usage)) == 2
    assert len(pipeline["calls"]) == 1


@pytest.mark.parametrize("marker", [{}, None, [], "invalid", False])
def test_malformed_check_marker_fails_closed_without_becoming_first_ocr(pipeline, marker):
    page = upload(pipeline)
    first(pipeline, page)
    review.advance_one()
    with DB.begin() as db:
        job = db.scalar(select(Job).where(Job.payload[review.KEY]["version"].as_integer() == 1))
        identifier = job.id
        job.payload = {**job.payload, review.KEY: marker}
        assert claim(db) == identifier
    process(identifier)
    with DB() as db:
        assert db.get(Job, identifier).status == "failed"
        assert not db.get(Material, page["id"]).confirmed
    assert len(pipeline["calls"]) == 1
