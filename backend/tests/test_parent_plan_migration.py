"""Filled SQLite/PostgreSQL upgrades retain round and answer provenance."""

import json
import os
import subprocess
import sys
import uuid
from pathlib import Path

import pytest
from schulpilot.db import engine
from sqlalchemy import create_engine, event, text


@pytest.mark.parametrize("dialect", ["sqlite", "postgresql"])
def test_parent_plan_migration_preserves_filled_assignments_and_fk(tmp_path, dialect):
    schema = None
    if dialect == "postgresql":
        if engine.dialect.name != "postgresql":
            pytest.skip("Requires the isolated PostgreSQL runner.")
        schema = "parent_migration_" + uuid.uuid4().hex
        with engine.begin() as con:
            con.execute(text(f'CREATE SCHEMA "{schema}"'))
        url = os.environ["TEST_DATABASE_URL"]
        tested = engine
    else:
        url = "sqlite:///" + str(tmp_path / "parent-migration.sqlite")
        tested = create_engine(url)

        @event.listens_for(tested, "connect")
        def foreign_keys(connection, _):
            connection.execute("PRAGMA foreign_keys=ON")

    env = {**os.environ, "DATABASE_URL": url, "ENVIRONMENT": "test"}
    if schema:
        env["PGOPTIONS"] = f"-c search_path={schema}"
    config = Path(__file__).resolve().parents[1] / "alembic.ini"
    command = [sys.executable, "-m", "alembic", "-c", str(config)]

    def migrate(direction, revision):
        result = subprocess.run([*command, direction, revision], env=env, capture_output=True)
        assert result.returncode == 0, result.stderr.decode(errors="replace")

    def scoped(con):
        if schema:
            con.execute(text(f'SET LOCAL search_path TO "{schema}"'))

    try:
        migrate("upgrade", "0024")
        with tested.begin() as con:
            scoped(con)
            for statement in [
                "INSERT INTO families(id,name,synthetic,created,child_limit,call_limit,budget_micros,plan) VALUES('f','Synthetic',true,1,4,100,2000000,'Pilot')",
                "INSERT INTO users(id,username,display_name,password_hash,role,verified,disabled,created) VALUES('u','synthetic','Synthetic','SYNTHETIC-HASH','child',true,false,1)",
                "INSERT INTO children(id,family_id,user_id,grade,subjects,school_type,region,preferences) VALUES('c','f','u',6,'[]','','','{}')",
                "INSERT INTO assignments(id,child_id,kind,subject,topic,note,mandatory,done,created) VALUES('a','c','parent','Mathematik','Brüche','Ursprünglicher Auftrag',true,false,1)",
                "INSERT INTO learning_units(id,child_id,assignment_id,subject,topic,explanation,questions,status,synthetic,provider,created,active_seconds) VALUES('unit','c','a','Mathematik','Brüche','Synthetic','[]','active',true,'synthetic',1,0)",
                "INSERT INTO attempts(id,unit_id,question_id,answer,outcome,assisted,created) VALUES('attempt','unit','q1','\"synthetic\"','correct',false,1)",
            ]:
                con.execute(text(statement))
        for index in range(2):
            migrate("upgrade", "0025")
            with tested.begin() as con:
                scoped(con)
                assert con.scalar(text("SELECT version_num FROM alembic_version")) == "0025"
                assert con.scalar(text("SELECT assignment_id FROM learning_units WHERE id='unit'")) == "a"
                answer, outcome = con.execute(text("SELECT answer,outcome FROM attempts WHERE id='attempt'")).first()
                assert (json.loads(answer) if dialect == "sqlite" else answer) == "synthetic"
                assert outcome == "correct"
                assert con.scalar(text("SELECT note FROM assignments WHERE id='a'")) == "Ursprünglicher Auftrag"
                assert con.scalar(text("SELECT source_unit_id FROM assignments WHERE id='a'")) is None
                if index == 0:
                    con.execute(text("UPDATE assignments SET source_unit_id='unit' WHERE id='a'"))
            if index == 0:
                migrate("downgrade", "0024")
        with tested.begin() as con:
            scoped(con)
            con.execute(text("UPDATE assignments SET source_unit_id='unit' WHERE id='a'"))
            con.execute(text("DELETE FROM learning_units WHERE id='unit'"))
            assert con.scalar(text("SELECT source_unit_id FROM assignments WHERE id='a'")) is None
            assert con.scalar(text("SELECT count(*) FROM attempts")) == 0
    finally:
        if schema:
            with engine.begin() as con:
                con.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        else:
            tested.dispose()
