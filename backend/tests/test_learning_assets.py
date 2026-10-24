"""Public artificial selectors and mock results; never real provider requests."""
import copy
import json
from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4

import httpx
import pytest
from conftest import HEADERS, create_child, register
from fastapi.testclient import TestClient
from schulpilot import providers
from schulpilot.catalog_models import CatalogSnapshot, CatalogTopic
from schulpilot.db import (
    DB,
    Activity,
    Attempt,
    Child,
    Family,
    Job,
    LearningUnit,
    Membership,
    ProviderConfig,
    Session,
    Usage,
    User,
    now,
)
from schulpilot.learning_asset_models import LearningAssetBuild, LearningAssetInstance
from schulpilot.learning_assets import (
    BUILDER_VERSION,
    checked_output,
    export_user,
    process,
    profile_subjects,
    public_spec,
    purge_expired,
)
from schulpilot.main import app
from schulpilot.model_routing import choose_tier, job_config
from schulpilot.providers import ProviderError, Result
from schulpilot.subject_content import PROFILES
from schulpilot.visual_reference_models import VisualReference
from schulpilot.visual_references import candidates, digest
from sqlalchemy import select
from test_model_routing import setup_policy

REAL_ADAPTER = providers.request_provider

TEXT = "KI-Beispiel: Start → Ziel. Ziel → Abschluss."


def output(subject="Mathematik"):
    steps = []
    for caption, first, last in (("Start → Ziel", "a", "b"), ("Ziel → Abschluss", "b", "c")):
        steps.append({"caption": caption, "source_excerpt": caption,
            "placements": [{"object_id": key, "slot": index} for index, key in enumerate("abc")],
            "highlight": [first], "edges": [{"start": first, "end": last, "label": ""}]})
    graphic = {"kind": "scene", "title": "KI-Beispiel", "disclosure": "given", "source_excerpt": TEXT,
        "labels": ["Start", "Ziel", "Abschluss"], "numbers": [], "connections": [], "marks": [], "unit": "", "variant": "",
        "scene": {"version": 1, "layout": "row", "transition_ms": 300,
            "objects": [{"id": key, "label": label, "shape": "box", "tone": "neutral"}
                for key, label in zip("abc", ("Start", "Ziel", "Abschluss"), strict=True)], "steps": steps}}
    return {"subject": subject, "title": "Ein unbewertetes KI-Beispiel", "text": TEXT,
            "presentation": {"version": 1, "evidence_kind": "creative", "blocks": [graphic]},
            "explorations": [{"prompt": "Was ändert sich zwischen den beiden Schritten?"}]}


@pytest.fixture
def prepared(api, household, monkeypatch):
    parent, child = household
    setup_policy(parent["families"][0]["id"])
    api.headers["X-Schulpilot-Account"] = parent["id"]
    api.headers["X-Schulpilot-Capabilities"] = "visual-v1"
    with DB.begin() as db:
        db.add(CatalogSnapshot(id="public-artificial-v1", provider="test", schema_version="1", metadata_json={}, report={}, created=1, last_import=1))
        db.flush()
        subjects = list(profile_subjects(db).values())
        for subject in subjects:
            db.add(CatalogTopic(id="artificial-" + subject.key, subject_id=subject.id, title="Künstliches öffentliches Thema " + subject.title,
                entry_url="https://example.org/public", search_text="artificial", empty_curated=True, data={}, snapshot_id="public-artificial-v1"))
    calls = []
    def generate(config, function, payload, **kwargs):
        calls.append(copy.deepcopy(payload))
        return Result(output(payload["required_subject"]), 10, 20, 12)
    monkeypatch.setattr(providers, "request_provider", generate)
    return parent, child, calls


def spec(subject="Mathematik"):
    with DB() as db:
        row = profile_subjects(db)[subject]
        topic = "artificial-" + row.key
    return {"subject": subject, "recipe_id": "general.source_relation.phases", "recipe_version": 1,
            "foundation_ids": [], "catalog_topic_id": topic, "locale": "de-DE", "level_band": "lower_secondary"}


def start(api, child, body=None, key=None):
    return api.post(f"/api/children/{child}/learning-assets/prepare", json=body or spec(),
        headers={"Idempotency-Key": key or uuid4().hex})


def run(instance):
    with DB.begin() as db:
        build = db.get(LearningAssetBuild, instance["build"]["build_key"])
        job = db.get(Job, build.job_id)
        job.status = "running"
        job_id = job.id
    process(job_id)
    return job_id


def read(api, instance):
    response = api.get("/api/learning-asset-instances/" + instance["id"])
    assert response.status_code == 200, response.text
    return response.json()


def test_complete_vertical_path_and_cache_hit_never_create_learning_evidence(api, prepared):
    parent, child, calls = prepared
    key = uuid4().hex
    created = start(api, child["id"], key=key)
    assert created.status_code == 202, created.text
    instance = created.json()
    assert instance["build"]["status"] == "queued" and instance["build"]["asset"] is None
    assert start(api, child["id"], key=key).json() == instance
    with DB() as db:
        checked_output(db, output(), db.get(LearningAssetBuild, instance["build"]["build_key"]).specification)
    job_id = run(instance)
    ready = read(api, instance)
    assert ready["build"]["status"] == "ready"
    assert ready["mode"] == "unassessed_exploration" and ready["build"]["factual_status"] == "unassessed"
    assert ready["build"]["asset"]["presentation"]["blocks"][0]["scene"]["steps"][1]["highlight"] == ["b"]
    assert "fachlich nicht unabhängig geprüft" in ready["build"]["notice"]
    assert len(calls) == 1
    hit = start(api, child["id"])
    assert hit.status_code == 202 and hit.json()["build"] == ready["build"]
    with DB() as db:
        assert db.query(Job).filter_by(kind="learning_asset").count() == db.query(Usage).count() == 1
        assert db.query(Attempt).count() == db.query(Activity).count() == db.query(LearningUnit).count() == 0
        assert db.get(Job, job_id).status == "completed"
        assert not any(row["id"].startswith("generated.") for row in candidates(db, "Mathematik", TEXT))
        reference = db.get(VisualReference, (ready["build"]["reference"]["id"], 1))
        assert reference.recipe["scope"] == "exploration_only" and reference.recipe["subjects"] == []
        # Even the pre-cache rollback reader (no scope filter) cannot select it.
        legacy = [row.id for row in db.scalars(select(VisualReference))
                  if "Mathematik" in row.recipe["subjects"] or "*" in row.recipe["subjects"]]
        assert reference.id not in legacy
        assert reference.recipe["asset"] == ready["build"]["asset"]
    assert calls[0].keys() == {"public_spec", "required_subject"}
    assert child["id"] not in json.dumps(calls) and parent["id"] not in json.dumps(calls)


def test_every_supported_subject_has_a_real_public_selector_and_renderer_contract(api, prepared):
    # Contract breadth, deliberately NOT 24 claims of factual content review.
    with DB() as db:
        for subject in PROFILES:
            public = public_spec(db, spec(subject))
            assert checked_output(db, output(subject), public)["subject"] == subject
            assert public["subject_id"] and public["catalog_topic"]["id"]



def test_catalogue_and_lookup_are_read_only_bounded_and_recommend_public_recipes(api, prepared):
    _, _, calls = prepared
    response = api.get("/api/learning-assets/catalogue")
    assert response.status_code == 200
    catalogue = response.json()
    assert set(catalogue["subjects"]) == set(PROFILES)
    assert catalogue["subject_definitions"] and catalogue["foundations"]
    assert len(catalogue["topics"]) <= 100 and catalogue["pagination"]["page_size"] == 100
    assert all("general.source_relation.phases" in topic["recommended_recipe_ids"] for topic in catalogue["topics"])
    assert all(topic["subject"] in PROFILES for topic in catalogue["topics"])
    assert api.get("/api/learning-assets/lookup", params={key: value for key, value in spec().items() if key not in ("locale", "foundation_ids")}).json()["status"] == "missing"
    with DB() as db:
        assert db.query(Job).count() == db.query(Usage).count() == db.query(LearningAssetInstance).count() == 0
    assert calls == []


INVALID_SELECTORS = [
    {"text": "private source"}, {"unit_id": "a" * 32}, {"subject": "Eigener Fachalias"},
    {"level_band": "invented"}, {"locale": "xx"}, {"recipe_id": "triangle.invalid"},
    {"recipe_version": True}, {"foundation_ids": ["unknown"]}, {"foundation_ids": [], "catalog_topic_id": None},
    {"catalog_topic_id": "private-material-id"}, {"subject": "Deutsch", "catalog_topic_id": "artificial-mathematik"}
]

def test_private_free_text_and_untrusted_ids_cannot_enter_global_key_or_start_provider(api, prepared):
    _, child, calls = prepared
    for change in INVALID_SELECTORS:
        result = start(api, child["id"], {**spec(), **change})
        assert result.status_code == 422, result.text
    with DB() as db:
        assert db.query(Job).count() == db.query(Usage).count() == db.query(LearningAssetBuild).count() == 0
    assert not calls


def test_foundation_keys_are_canonical_and_include_real_public_version_and_digest(api, prepared):
    _, _, _ = prepared
    body = {**spec(), "foundation_ids": ["math.fractions.components", "math.fractions.meaning"], "catalog_topic_id": None}
    with DB() as db:
        first = public_spec(db, body)
        second = public_spec(db, {**body, "foundation_ids": list(reversed(body["foundation_ids"]))})
        assert first == second
        assert first["foundations"][0]["version"] == "competencies-1"
        assert all(len(row["digest"]) == 64 for row in first["foundations"])
        assert first["builder_version"] == BUILDER_VERSION
        assert digest(first) != digest({**first, "renderer_version": "future"})


def test_parallel_same_build_creates_one_paid_job_and_private_request_receipts(api, prepared):
    parent, child, _ = prepared
    sibling = create_child(api, parent, "shared-sibling")
    token, account = api.headers["Authorization"], parent["id"]
    body = spec()
    def concurrent(cid):
        with TestClient(app, headers={**HEADERS, "Authorization": token, "X-Schulpilot-Account": account, "X-Schulpilot-Capabilities": "visual-v1"}) as client:
            return client.post(f"/api/children/{cid}/learning-assets/prepare", json=body, headers={"Idempotency-Key": uuid4().hex})
    with ThreadPoolExecutor(max_workers=2) as executor:
        responses = list(executor.map(concurrent, [child["id"], sibling["id"]]))
    assert [r.status_code for r in responses] == [202, 202], [r.text for r in responses]
    assert len({r.json()["build"]["build_key"] for r in responses}) == 1
    assert len({r.json()["id"] for r in responses}) == 2
    with DB() as db:
        assert db.query(Job).count() == db.query(Usage).count() == db.query(LearningAssetBuild).count() == 1
        assert db.query(LearningAssetInstance).count() == 2


def test_idempotency_is_actor_private_and_conflicting_child_or_spec_is_rejected(api, prepared):
    parent, child, _ = prepared
    key = uuid4().hex
    assert start(api, child["id"], key=key).status_code == 202
    assert start(api, child["id"], {**spec(), "level_band": "primary"}, key=key).status_code == 409
    sibling = create_child(api, parent, "idem-sibling")
    assert start(api, sibling["id"], key=key).status_code == 409
    with DB() as db:
        assert db.query(Usage).count() == 1


def test_cross_family_follower_gets_no_other_job_usage_or_error_and_pays_nothing(api, prepared, mailbox):
    _, child, _ = prepared
    first = start(api, child["id"]).json()
    other = register(api, mailbox, "other@example.org")
    other_child = create_child(api, other, "other-test-child")
    api.headers["X-Schulpilot-Account"] = other["id"]
    second = start(api, other_child["id"]).json()
    assert first["build"] == second["build"]
    assert api.get("/api/learning-asset-instances/" + first["id"]).status_code == 404
    forbidden = {"job_id", "error", "error_code", "session_id", "user_id", "family_id", "usage", "cost", "model"}
    assert not forbidden.intersection(second["build"])
    with DB() as db:
        assert db.query(Job).count() == db.query(Usage).count() == 1
        job = db.scalar(select(Job))
        job.status = "failed"
        job.error = "private diagnostic"
        db.commit()
    assert read(api, second)["build"]["status"] == "failed"
    assert "private diagnostic" not in json.dumps(read(api, second))
    assert start(api, other_child["id"]).json()["build"]["status"] == "failed"
    with DB() as db:
        assert db.query(Usage).count() == 1


@pytest.mark.parametrize("change", ["session", "user", "membership", "family", "recipe", "topic", "config"])
def test_late_results_require_same_authority_public_versions_and_provider_revision(api, prepared, monkeypatch, change):
    parent, child, calls = prepared
    created = start(api, child["id"]).json()
    original = providers.request_provider
    def stale(*args, **kwargs):
        result = original(*args, **kwargs)
        with DB.begin() as db:
            build = db.get(LearningAssetBuild, created["build"]["build_key"])
            job = db.get(Job, build.job_id)
            if change == "session":
                db.get(Session, job.payload["session_id"]).revoked = True
            elif change == "user":
                db.get(User, parent["id"]).disabled = True
            elif change == "membership":
                db.scalar(select(Membership).where(Membership.user_id == parent["id"])).permission = "view"
            elif change == "family":
                db.get(Family, job.payload["family_id"]).expires = int(now()) - 1
            elif change == "recipe":
                db.get(VisualReference, ("general.source_relation.phases", 1)).digest = "0" * 64
            elif change == "topic":
                db.get(CatalogTopic, spec()["catalog_topic_id"]).title = "Andere öffentliche Fassung"
            else:
                db.get(ProviderConfig, 1).revision += 1
        return result
    monkeypatch.setattr(providers, "request_provider", stale)
    job_id = run(created)
    with DB() as db:
        assert db.get(Job, job_id).status == "failed"
        assert db.get(LearningAssetBuild, created["build"]["build_key"]).status == "failed"
        assert db.query(VisualReference).filter(VisualReference.id.like("generated.%")).count() == 0
        assert db.query(Attempt).count() == db.query(Activity).count() == 0
    assert len(calls) == 1


@pytest.mark.parametrize("change", ["answer", "subject", "label", "phase", "disclosure", "too_many"])
def test_unvalidated_outputs_never_publish_or_become_answer_keys(api, prepared, monkeypatch, change):
    _, child, _ = prepared
    bad = output()
    if change == "answer":
        bad["answer"] = "safe key"
    elif change == "subject":
        bad["subject"] = "Deutsch"
    elif change == "label":
        bad["presentation"]["blocks"][0]["scene"]["objects"][0]["label"] = "Unbelegte Beschriftung"
    elif change == "phase":
        bad["presentation"]["blocks"][0]["scene"]["steps"][1] = copy.deepcopy(bad["presentation"]["blocks"][0]["scene"]["steps"][0])
    elif change == "disclosure":
        bad["presentation"]["blocks"][0]["disclosure"] = "solution"
    else:
        bad["presentation"]["blocks"] *= 2
    monkeypatch.setattr(providers, "request_provider", lambda *args, **kwargs: Result(bad, 1, 1, 1))
    created = start(api, child["id"]).json()
    run(created)
    assert read(api, created)["build"]["status"] == "failed"
    with DB() as db:
        assert db.query(VisualReference).filter(VisualReference.id.like("generated.%")).count() == 0


def test_existing_job_quota_bad_actor_and_view_parent_remain_fail_closed(api, prepared):
    parent, child, _ = prepared
    assert start(api, child["id"], key="bad").status_code == 422
    api.headers["X-Schulpilot-Account"] = "f" * 32
    assert start(api, child["id"]).status_code == 409
    api.headers["X-Schulpilot-Account"] = parent["id"]
    with DB.begin() as db:
        db.add(Job(child_id=child["id"], kind="unit", payload={}, idempotency=uuid4().hex))
    assert start(api, child["id"]).status_code == 409
    with DB.begin() as db:
        db.scalar(select(Membership).where(Membership.user_id == parent["id"])).permission = "view"
    assert start(api, child["id"]).status_code == 403
    with DB() as db:
        assert db.query(Usage).count() == db.query(LearningAssetBuild).count() == 0


def test_no_forced_route_or_unknown_legacy_provider_and_economy_still_uses_regular_sol(api, prepared):
    _, child, _ = prepared
    assert choose_tier("unit", {}, economy=True)[0] == "sol"
    with DB.begin() as db:
        config = db.get(ProviderConfig, 1)
        config.routing_policy = {**config.routing_policy, "enabled": False}
    assert start(api, child["id"]).status_code == 503
    with DB() as db:
        assert db.query(Usage).count() == db.query(Job).count() == 0


def test_instances_export_expire_and_cascade_without_deleting_shared_public_reference(api, prepared):
    parent, child, _ = prepared
    created = start(api, child["id"]).json()
    run(created)
    with DB.begin() as db:
        exported = export_user(db, parent["id"], [child["id"]])
        assert len(exported) == 1 and "request_key" not in exported[0]
        db.get(LearningAssetInstance, created["id"]).created = int(now()) - 366 * 86400
        purge_expired(db)
        assert db.query(LearningAssetInstance).count() == 0
        assert db.query(VisualReference).filter(VisualReference.id.like("generated.%")).count() == 1
    again = start(api, child["id"]).json()
    with DB.begin() as db:
        db.delete(db.get(Child, child["id"]))
        db.flush()
        assert db.get(LearningAssetInstance, again["id"]) is None
        assert db.query(LearningAssetBuild).count() == 1


def test_missing_or_erased_worker_job_projects_terminal_failure_without_retry(api, prepared):
    _, child, calls = prepared
    created = start(api, child["id"]).json()
    with DB.begin() as db:
        build = db.get(LearningAssetBuild, created["build"]["build_key"])
        build.job_id = None
    assert read(api, created)["build"]["status"] == "failed"
    assert not calls


@pytest.mark.parametrize("finish", ["stop", "length"])
def test_real_adapter_contract_is_compact_private_free_and_truncation_cannot_publish(api, prepared, monkeypatch, finish):
    _, child, _ = prepared
    created = start(api, child["id"]).json()
    with DB() as db:
        build = db.get(LearningAssetBuild, created["build"]["build_key"])
        job = db.get(Job, build.job_id)
        config = job_config(db, job, "unit")
        public = copy.deepcopy(build.specification)
    bodies = []
    class Client:
        def __init__(self, **kwargs):
            pass
        def __enter__(self):
            return self
        def __exit__(self, *args):
            pass
        def post(self, url, headers, json):
            bodies.append(json)
            return httpx.Response(200, json={"choices": [{"finish_reason": finish, "message": {"content": __import__("json").dumps(output())}}],
                "usage": {"prompt_tokens": 20, "completion_tokens": 30}})
    monkeypatch.setattr(providers.httpx, "Client", Client)
    # Restore the actual adapter; the HTTP boundary above is synthetic.
    original = REAL_ADAPTER
    payload = {"public_spec": public, "required_subject": public["subject"]}
    if finish == "length":
        with pytest.raises(ProviderError, match="Ausgabelänge"):
            original(config, "learning_asset", payload)
    else:
        result = original(config, "learning_asset", payload)
        assert result.data["subject"] == public["subject"]
    assert len(bodies) == 1 and bodies[0]["max_tokens"] == config.max_output_tokens <= 4000
    assert bodies[0]["provider"]["allow_fallbacks"] is False
    text = json.dumps(bodies, ensure_ascii=False)
    assert child["id"] not in text and "questions" not in bodies[0]["response_format"]["json_schema"]["schema"]["properties"]
    assert len(text.encode()) < 24000


@pytest.mark.parametrize("provider_failure", [False, True])
def test_terminal_job_changed_while_waiting_for_child_lock_is_never_published_or_resettled(api, prepared, monkeypatch, provider_failure):
    from sqlalchemy.orm import Session as SQLSession
    from sqlalchemy.sql.dml import Update

    _, child, _ = prepared
    created = start(api, child["id"]).json()
    with DB.begin() as db:
        build = db.get(LearningAssetBuild, created["build"]["build_key"])
        job_id = build.job_id
        db.get(Job, job_id).status = "running"
    if provider_failure:
        def fail(*args, **kwargs):
            raise ProviderError("Synthetic interrupted request")
        monkeypatch.setattr(providers, "request_provider", fail)
    original_execute = SQLSession.execute
    intercepted = []
    def execute(self, statement, *args, **kwargs):
        if isinstance(statement, Update) and statement.table.name == "children" and not intercepted:
            intercepted.append(True)
            # This interposition models a maintenance decision committed while
            # the result worker was waiting to acquire the Child lock.
            with DB.begin() as other:
                other.get(Job, job_id).status = "failed"
                usage = other.scalar(select(Usage).where(Usage.job_id == job_id))
                usage.status, usage.settlement_version = "failed_unknown", 1
        return original_execute(self, statement, *args, **kwargs)
    monkeypatch.setattr(SQLSession, "execute", execute)
    process(job_id)
    with DB() as db:
        assert db.get(Job, job_id).status == "failed"
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        assert usage.status == "failed_unknown" and usage.settlement_version == 1
        assert db.query(VisualReference).filter(VisualReference.id.like("generated.%")).count() == 0
    assert intercepted == [True]


def test_same_public_key_in_two_families_parallel_is_one_global_claim(api, prepared, mailbox):
    first_parent, first_child, _ = prepared
    first_auth = api.headers["Authorization"]
    # A separate browser is required: logging in as another parent in the
    # original browser correctly revokes that browser's previous session.
    with TestClient(app, headers=HEADERS) as second_api:
        second_parent = register(second_api, mailbox, "parallel-public-parent@example.org")
        second_child = create_child(second_api, second_parent, "parallel-public-child")
        second_auth = second_api.headers["Authorization"]
    body = spec()
    entries = [(first_parent["id"], first_auth, first_child["id"]),
               (second_parent["id"], second_auth, second_child["id"])]
    def request(entry):
        account, authorization, child = entry
        with TestClient(app, headers={**HEADERS, "Authorization": authorization,
                "X-Schulpilot-Account": account, "X-Schulpilot-Capabilities": "visual-v1"}) as client:
            return client.post(f"/api/children/{child}/learning-assets/prepare", json=body, headers={"Idempotency-Key": uuid4().hex})
    with ThreadPoolExecutor(max_workers=2) as executor:
        responses = list(executor.map(request, entries))
    assert [r.status_code for r in responses] == [202, 202], [r.text for r in responses]
    assert responses[0].json()["build"] == responses[1].json()["build"]
    with DB() as db:
        assert db.query(Job).count() == db.query(Usage).count() == db.query(LearningAssetBuild).count() == 1
        assert db.query(LearningAssetInstance).count() == 2


def test_legacy_client_and_demo_miss_cannot_start_but_demo_may_reuse_a_public_hit(api, prepared):
    parent, child, calls = prepared
    api.headers["X-Schulpilot-Capabilities"] = ""
    assert start(api, child["id"]).status_code == 426
    api.headers["X-Schulpilot-Capabilities"] = "visual-v1"
    with DB.begin() as db:
        db.get(Family, parent["families"][0]["id"]).synthetic = True
    assert start(api, child["id"]).status_code == 409
    with DB.begin() as db:
        db.get(Family, parent["families"][0]["id"]).synthetic = False
    created = start(api, child["id"]).json()
    run(created)
    with DB.begin() as db:
        db.get(Family, parent["families"][0]["id"]).synthetic = True
    assert start(api, child["id"]).json()["build"]["status"] == "ready"
    assert len(calls) == 1


def test_actual_adapter_rejects_injected_private_payload_before_http(api, prepared, monkeypatch):
    _, _, _ = prepared
    from schulpilot.model_routing import select_route

    with DB() as db:
        public = public_spec(db, spec())
        config = select_route(db.get(ProviderConfig, 1), "unit", {})
    requests = []
    class ForbiddenClient:
        def __init__(self, *args, **kwargs):
            requests.append(True)
            raise AssertionError("No HTTP client may be opened")
    monkeypatch.setattr(providers.httpx, "Client", ForbiddenClient)
    with pytest.raises(ProviderError, match="nicht freigegebene Daten"):
        REAL_ADAPTER(config, "learning_asset", {"public_spec": public,
            "required_subject": public["subject"], "private_unit_text": "must never be sent"})
    assert not requests
