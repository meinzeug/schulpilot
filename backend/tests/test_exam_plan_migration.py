"""The additive exam migration retains existing answers and avatar revisions."""

import os
import subprocess
import sys
import uuid
from pathlib import Path

import pytest
from schulpilot.db import engine
from sqlalchemy import create_engine, event, inspect, text


@pytest.mark.parametrize("dialect", ["sqlite", "postgresql"])
def test_exam_plan_migration_retains_old_data_and_private_foreign_keys(tmp_path, dialect):
    schema = None
    if dialect == "postgresql":
        if engine.dialect.name != "postgresql":
            pytest.skip("Requires the isolated PostgreSQL runner.")
        schema = "exam_migration_" + uuid.uuid4().hex
        with engine.begin() as con:
            con.execute(text(f'CREATE SCHEMA "{schema}"'))
        url, tested = os.environ["TEST_DATABASE_URL"], engine
    else:
        url = "sqlite:///" + str(tmp_path / "exams.sqlite")
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
        completed = subprocess.run([*command, direction, revision], env=env, capture_output=True)
        assert completed.returncode == 0, completed.stderr.decode(errors="replace")

    def scope(con):
        if schema:
            con.execute(text(f'SET LOCAL search_path TO "{schema}"'))

    try:
        migrate("upgrade", "0032")
        with tested.begin() as con:
            scope(con)
            for statement in [
                "INSERT INTO families(id,name,synthetic,created,child_limit,call_limit,budget_micros,plan) VALUES('f','Synthetic',true,1,4,100,2000000,'Pilot')",
                "INSERT INTO users(id,username,display_name,password_hash,role,verified,disabled,created) VALUES('u','synthetic','Synthetic','SYNTHETIC-HASH','child',true,false,1)",
                "INSERT INTO children(id,family_id,user_id,grade,subjects,school_type,region,preferences) VALUES('c','f','u',6,'[]','','','{}')",
                "INSERT INTO learning_units(id,child_id,subject,topic,explanation,questions,status,synthetic,provider,created,active_seconds) VALUES('unit','c','Mathematik','Brüche','Synthetic','[]','completed',true,'synthetic',1,0)",
                "INSERT INTO attempts(id,unit_id,question_id,answer,outcome,assisted,created) VALUES('attempt','unit','q1','\"synthetic\"','correct',false,1)",
                "INSERT INTO user_avatars(user_id,revision,image_digest,updated,request_key,request_digest) VALUES('u','synthetic-revision',NULL,1,'synthetic-key','synthetic-digest')",
            ]:
                con.execute(text(statement))
        for iteration in range(2):
            migrate("upgrade", "0033")
            with tested.begin() as con:
                scope(con)
                assert con.scalar(text("SELECT version_num FROM alembic_version")) == "0033"
                assert con.scalar(text("SELECT outcome FROM attempts WHERE id='attempt'")) == "correct"
                assert con.scalar(text("SELECT revision FROM user_avatars WHERE user_id='u'")) == "synthetic-revision"
                assert con.scalar(text("SELECT count(*) FROM exams")) == 0
                for table, columns in {
                    "exams": {"child_id", "topics", "schedule", "revision", "reminders"},
                    "exam_sessions": {"exam_id", "exam_revision", "date", "topics"},
                    "exam_rounds": {"session_id", "unit_id", "job_id", "source_revisions"},
                }.items():
                    assert columns <= {column["name"] for column in inspect(con).get_columns(table, schema=schema)}
            if iteration == 0:
                migrate("downgrade", "0032")
        with tested.begin() as con:
            scope(con)
            con.execute(text("INSERT INTO exams(id,child_id,title,purpose,kind,subject,timezone,revision,minutes,topics,schedule,reminders,reminder_time,archived,created,updated,create_key,request_digest) VALUES('e','c','Synthetic','preparation','test','Mathematik','Europe/Berlin',1,15,'[]','{}',false,'16:00',false,1,1,'e-key','e-digest')"))
            con.execute(text("INSERT INTO exam_sessions(id,exam_id,exam_revision,date,minutes,topics) VALUES('s','e',1,'2030-02-01',15,'[]')"))
            con.execute(text("INSERT INTO exam_rounds(id,session_id,ordinal,topic_id,topic_label,question_count,source_revisions,unit_id) VALUES('r','s',0,'t','Brüche',3,'[]','unit')"))
            con.execute(text("DELETE FROM learning_units WHERE id='unit'"))
            assert con.scalar(text("SELECT unit_id FROM exam_rounds WHERE id='r'")) is None
            assert con.scalar(text("SELECT count(*) FROM attempts")) == 0
            con.execute(text("DELETE FROM children WHERE id='c'"))
            assert con.scalar(text("SELECT count(*) FROM exams")) == 0
            assert con.scalar(text("SELECT count(*) FROM exam_sessions")) == 0
            assert con.scalar(text("SELECT count(*) FROM exam_rounds")) == 0
            assert con.scalar(text("SELECT count(*) FROM user_avatars")) == 1
    finally:
        if schema:
            with engine.begin() as con:
                con.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        else:
            tested.dispose()
