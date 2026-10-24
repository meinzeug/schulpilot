"""Separate public asset building from source-bound lab lessons, no provider."""
import uuid

import pytest
from fastapi import HTTPException
from schulpilot.db import DB, Job, Usage
from schulpilot.learning_asset_models import LearningAssetBuild
from schulpilot.learning_assets import public_spec
from schulpilot.visual_references import candidates
from test_learning_assets import prepared as original_prepared
from test_learning_assets import spec


@pytest.fixture
def prepared(api, household, monkeypatch):
    return original_prepared.__wrapped__(api, household, monkeypatch)


def test_public_asset_menu_filters_labs_while_lesson_candidates_keep_them(api, prepared):
    catalogue = api.get("/api/learning-assets/catalogue").json()
    assert not any(row["kind"] == "lab" for row in catalogue["recipes"])
    for row in [*catalogue["topics"], *catalogue["foundations"]]:
        assert not any(key.startswith("lab.") for key in row["recommended_recipe_ids"])
    with DB() as db:
        assert "lab.physics.force_motion" in {row["id"] for row in candidates(db, "Physik", "Kraft Masse Beschleunigung")}
        assert "lab.german.sentence_shift" in {row["id"] for row in candidates(db, "Deutsch", "Satzglied Umstellprobe")}


@pytest.mark.parametrize("subject,recipe", [("Physik", "lab.physics.force_motion"), ("Deutsch", "lab.german.sentence_shift")])
def test_forged_public_lab_build_rejected_before_job_or_reservation(api, prepared, subject, recipe):
    _, child, calls = prepared
    body = {**spec(subject), "recipe_id": recipe}
    with DB() as db:
        with pytest.raises(HTTPException) as error:
            public_spec(db, body)
        assert error.value.status_code == 422
    response = api.post(f"/api/children/{child['id']}/learning-assets/prepare", json=body,
                        headers={"Idempotency-Key": uuid.uuid4().hex})
    assert response.status_code == 422, response.text
    with DB() as db:
        assert db.query(Job).count() == db.query(Usage).count() == db.query(LearningAssetBuild).count() == 0
    assert calls == []
