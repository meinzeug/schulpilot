"""Exercise the actual PostgreSQL upgrade in a disposable isolated schema."""

import os
import subprocess
import sys
import uuid
from pathlib import Path

import pytest
from schulpilot.db import Base, Child, Family, GradeImport, SchoolGrade, User, engine
from sqlalchemy import inspect, select, text


def test_head_migration_matches_mapped_columns_and_grade_import_is_readable():
    """create_all fixtures hide ORM columns accidentally absent from migrations."""
    if engine.dialect.name != "postgresql":
        pytest.skip("Requires the disposable PostgreSQL migration runner")
    assert (engine.url.database or "").endswith("_test")
    schema = "grade_head_" + uuid.uuid4().hex
    with engine.begin() as con:
        con.execute(text(f'CREATE SCHEMA "{schema}"'))
    env = {**os.environ, "DATABASE_URL": os.environ["TEST_DATABASE_URL"], "ENVIRONMENT": "test",
           "PGOPTIONS": f"-c search_path={schema}"}
    config = Path(__file__).resolve().parents[1] / "alembic.ini"
    try:
        subprocess.run([sys.executable, "-m", "alembic", "-c", str(config), "upgrade", "head"],
                       env=env, capture_output=True, check=True)
        with engine.begin() as con:
            con.execute(text(f'SET LOCAL search_path TO "{schema}"'))
            inspector = inspect(con)
            for name, table in Base.metadata.tables.items():
                actual = {column["name"] for column in inspector.get_columns(name, schema=schema)}
                assert set(table.columns.keys()) <= actual, f"Mapped columns absent from migrated {name}"
            con.execute(Family.__table__.insert().values(id="f", name="Synthetic", synthetic=True))
            con.execute(User.__table__.insert().values(id="u", username="synthetic", display_name="Synthetic",
                        role="child", password_hash="SYNTHETIC-HASH", verified=True))
            con.execute(Child.__table__.insert().values(id="c", family_id="f", user_id="u", grade=6, subjects=[]))
            con.execute(GradeImport.__table__.insert().values(id="i", child_id="c", request_key="synthetic-import",
                        file_digest="a" * 64, school_year_start=2026, entries=[]))
            assert con.execute(select(GradeImport).where(GradeImport.id == "i")).first() is not None
    finally:
        with engine.begin() as con:
            con.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))


def test_real_postgres_grade_upgrade_preserves_dated_rows_and_unknown_dates():
    if engine.dialect.name != "postgresql":
        pytest.skip("Run with scripts/test_postgres.py for real PostgreSQL migration coverage")
    assert (engine.url.database or "").endswith("_test")
    schema = "grade_migration_" + uuid.uuid4().hex
    with engine.begin() as con:
        con.execute(text(f'CREATE SCHEMA "{schema}"'))
    env = {
        **os.environ,
        "DATABASE_URL": os.environ["TEST_DATABASE_URL"],
        "ENVIRONMENT": "test",
        "PGOPTIONS": f"-c search_path={schema}",
    }
    config = Path(__file__).resolve().parents[1] / "alembic.ini"
    command = [sys.executable, "-m", "alembic", "-c", str(config)]
    try:
        subprocess.run([*command, "upgrade", "0016"], env=env, capture_output=True, check=True)
        with engine.begin() as con:
            con.execute(text(f'SET LOCAL search_path TO "{schema}"'))
            con.execute(Family.__table__.insert().values(id="f", name="Synthetic", synthetic=True))
            con.execute(
                User.__table__.insert().values(
                    id="u",
                    username="synthetic",
                    display_name="Synthetic",
                    role="child",
                    password_hash="SYNTHETIC-HASH",
                    verified=True,
                )
            )
            con.execute(Child.__table__.insert().values(id="c", family_id="f", user_id="u", grade=6, subjects=[]))
            con.execute(
                text(
                    "INSERT INTO school_grades(id,child_id,subject,topic,kind,scale,value,weight,assessed_on,note,revision,created,updated) "
                    "VALUES('g','c','Mathe','','test','grade_1_6',3,1,'2026-10-10','',1,1,1)"
                )
            )
        subprocess.run([*command, "upgrade", "0017"], env=env, capture_output=True, check=True)
        with engine.begin() as con:
            con.execute(text(f'SET LOCAL search_path TO "{schema}"'))
            assert con.execute(text("SELECT assessed_on,value FROM school_grades WHERE id='g'")).first() == (
                "2026-10-10",
                3,
            )
            con.execute(
                SchoolGrade.__table__.insert().values(
                    id="unknown",
                    child_id="c",
                    subject="Englisch",
                    topic="",
                    kind="other",
                    scale="grade_1_6",
                    value=2,
                    weight=1,
                    assessed_on=None,
                    note="",
                    school_year_start=2026,
                    semester=1,
                )
            )
            assert con.scalar(text("SELECT version_num FROM alembic_version")) == "0017"
        result = subprocess.run([*command, "downgrade", "0016"], env=env, capture_output=True)
        assert result.returncode != 0  # Never manufacture dates to downgrade.
        with engine.begin() as con:
            con.execute(text(f'SET LOCAL search_path TO "{schema}"'))
            assert con.scalar(text("SELECT count(*) FROM school_grades")) == 2
            assert con.scalar(text("SELECT version_num FROM alembic_version")) == "0017"
    finally:
        with engine.begin() as con:
            con.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
