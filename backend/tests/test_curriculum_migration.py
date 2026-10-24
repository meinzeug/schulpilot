"""0041 adds curated metadata while preserving reminders and real evidence."""
import os
import subprocess
import sys
import uuid
from pathlib import Path

import pytest
from schulpilot.db import engine
from sqlalchemy import create_engine, event, inspect, text


@pytest.mark.parametrize("dialect", ["sqlite", "postgresql"])
def test_curriculum_migration_is_additive_idempotent_and_cascades_private_profile(tmp_path, dialect):
    schema = None
    if dialect == "postgresql":
        if engine.dialect.name != "postgresql":
            pytest.skip("Requires isolated PostgreSQL runner.")
        schema = "curriculum_migration_" + uuid.uuid4().hex
        with engine.begin() as con:
            con.execute(text(f'CREATE SCHEMA "{schema}"'))
        url, tested = os.environ["TEST_DATABASE_URL"], engine
    else:
        url = "sqlite:///" + str(tmp_path / "curriculum.sqlite")
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
    def scope(con):
        if schema:
            con.execute(text(f'SET LOCAL search_path TO "{schema}"'))
    try:
        migrate("upgrade", "0040")
        with tested.begin() as con:
            scope(con)
            for statement in [
                "INSERT INTO families(id,name,synthetic,created,child_limit,call_limit,budget_micros,plan) VALUES('f','Synthetic',true,1,4,100,2000000,'Pilot')",
                "INSERT INTO users(id,username,display_name,password_hash,role,verified,disabled,created) VALUES('u','synthetic','Synthetic','SYNTHETIC-HASH','parent',true,false,1)",
                "INSERT INTO children(id,family_id,user_id,grade,subjects,school_type,region,preferences) VALUES('c','f','u',6,'[]','','','{}')",
                "INSERT INTO parent_goal_reminders(user_id,child_id,revision,enabled,weekdays,time,timezone,daily_minimum,exam_sessions,updated,next_check) VALUES('u','c',1,true,'[0]','18:00','Europe/Berlin',true,true,1,0)",
                "INSERT INTO learning_units(id,child_id,subject,topic,explanation,questions,status,synthetic,provider,created,active_seconds) VALUES('unit','c','Mathematik','Brüche','Synthetic','[]','completed',true,'synthetic',1,300)",
                "INSERT INTO attempts(id,unit_id,question_id,answer,outcome,assisted,created) VALUES('attempt','unit','q1','\"synthetic\"','correct',false,1)",
            ]:
                con.execute(text(statement))
        for index in range(2):
            migrate("upgrade", "0041")
            migrate("upgrade", "0041")
            with tested.begin() as con:
                scope(con)
                assert con.scalar(text("SELECT version_num FROM alembic_version")) == "0041"
                assert con.scalar(text("SELECT active_seconds FROM learning_units WHERE id='unit'")) == 300
                assert con.scalar(text("SELECT outcome FROM attempts WHERE id='attempt'")) == "correct"
                assert con.scalar(text("SELECT revision FROM parent_goal_reminders WHERE child_id='c'")) == 1
                assert {"curriculum_documents", "curriculum_topics", "child_curriculum_profiles", "child_curriculum_changes"} <= set(inspect(con).get_table_names(schema=schema))
                assert con.scalar(text("SELECT count(*) FROM curriculum_documents")) >= 20
                assert con.scalar(text("SELECT count(*) FROM curriculum_topics")) >= 264
                assert con.scalar(text("SELECT count(*) FROM child_curriculum_profiles")) == 0
            if index == 0:
                migrate("downgrade", "0040")
        with tested.begin() as con:
            scope(con)
            for statement in [
                "INSERT INTO child_curriculum_profiles(child_id,revision,state_code,school_form_id,legacy_binding,updated) VALUES('c',1,'DE-SN',NULL,'{}',1)",
                "INSERT INTO child_curriculum_changes(id,child_id,actor_id,request_key,digest,revision,data,created) VALUES('change','c','u','synthetic','synthetic',1,'{}',1)",
                "DELETE FROM children WHERE id='c'",
            ]:
                con.execute(text(statement))
            for table in ("child_curriculum_profiles", "child_curriculum_changes"):
                assert con.scalar(text("SELECT count(*) FROM " + table)) == 0
            assert con.scalar(text("SELECT count(*) FROM curriculum_topics")) >= 264
            assert con.scalar(text("SELECT count(*) FROM users WHERE id='u'")) == 1
    finally:
        if schema:
            with engine.begin() as con:
                con.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        else:
            tested.dispose()
