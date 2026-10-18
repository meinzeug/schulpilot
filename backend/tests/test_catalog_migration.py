"""The additive production migration preserves existing attempts and subjects."""

import os
import subprocess
import sys
import uuid
from pathlib import Path

import pytest
from schulpilot.db import Attempt, Child, Family, LearningUnit, Material, User, engine
from sqlalchemy import text


def test_postgres_catalog_upgrade_keeps_private_sources_answers_and_stable_subjects():
    if engine.dialect.name != "postgresql":
        pytest.skip("Use scripts/test_postgres.py for actual PostgreSQL migration")
    assert (engine.url.database or "").endswith("_test")
    schema = "catalog_migration_" + uuid.uuid4().hex
    with engine.begin() as db:
        db.execute(text(f'CREATE SCHEMA "{schema}"'))
    env = {
        **os.environ,
        "DATABASE_URL": os.environ["TEST_DATABASE_URL"],
        "ENVIRONMENT": "test",
        "PGOPTIONS": f"-c search_path={schema}",
    }
    command = [sys.executable, "-m", "alembic", "-c", str(Path(__file__).resolve().parents[1] / "alembic.ini")]
    try:
        subprocess.run([*command, "upgrade", "0018"], env=env, capture_output=True, check=True)
        with engine.begin() as db:
            db.execute(text(f'SET LOCAL search_path TO "{schema}"'))
            db.execute(Family.__table__.insert().values(id="f", name="Synthetic"))
            db.execute(
                User.__table__.insert().values(
                    id="u",
                    username="synthetic",
                    role="child",
                    display_name="Synthetic",
                    password_hash="SYNTHETIC",
                    verified=True,
                )
            )
            db.execute(Child.__table__.insert().values(id="c", family_id="f", user_id="u", grade=6))
            subject = db.scalar(text("SELECT id FROM subjects WHERE key='mathematik'"))
            db.execute(
                Material.__table__.insert().values(
                    id="m",
                    child_id="c",
                    title="Synthetic",
                    subject="Mathe",
                    subject_id=subject,
                    topic="Brüche",
                    content="Artificial source",
                    confirmed=True,
                )
            )
            db.execute(
                LearningUnit.__table__.insert().values(
                    id="l",
                    child_id="c",
                    subject="Mathe",
                    subject_id=subject,
                    topic="Brüche",
                    explanation="Artificial",
                    questions=[],
                    provider="synthetic",
                    model="fixed",
                    material_id="m",
                )
            )
            db.execute(
                Attempt.__table__.insert().values(
                    id="a", unit_id="l", question_id="q1", answer="Synthetic answer", outcome="uncertain"
                )
            )
        subprocess.run([*command, "upgrade", "0019"], env=env, capture_output=True, check=True)
        subprocess.run([*command, "upgrade", "head"], env=env, capture_output=True, check=True)
        with engine.begin() as db:
            db.execute(text(f'SET LOCAL search_path TO "{schema}"'))
            assert db.scalar(text("SELECT version_num FROM alembic_version")) == "0019"
            assert db.scalar(text("SELECT id FROM subjects WHERE key='mathematik'")) == subject
            assert db.scalar(text("SELECT content FROM materials WHERE id='m'")) == "Artificial source"
            assert db.scalar(text("SELECT answer FROM attempts WHERE id='a'")) == "Synthetic answer"
            assert db.scalar(text("SELECT count(*) FROM subjects")) == 24
            assert db.scalar(text("SELECT count(*) FROM catalog_topics")) == 0
            assert "gin" in db.scalar(
                text(
                    "SELECT indexdef FROM pg_indexes WHERE schemaname=:schema AND indexname='ix_catalog_topic_search'"
                ),
                {"schema": schema},
            )
    finally:
        with engine.begin() as db:
            db.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
