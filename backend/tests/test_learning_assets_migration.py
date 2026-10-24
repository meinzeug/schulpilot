"""Actual 0039 -> 0040 DDL, never Base.create_all/stamp as a migration proof."""
import os
import subprocess
import sys
from pathlib import Path
from uuid import uuid4

from sqlalchemy import text
from sqlalchemy.engine import make_url

SCRIPT = r'''
from alembic import command
from alembic.config import Config
from sqlalchemy import MetaData, Table, inspect, select
from schulpilot.db import DB, engine, Family, User, Child, LearningUnit, Attempt
from schulpilot.parent_reminder_models import ParentGoalReminder
config = Config('backend/alembic.ini')
command.upgrade(config, '0039')
with DB.begin() as db:
    db.add(Family(id='f'*32, name='Artificial family'))
    db.add_all([User(id='a'*32, username='artificial-parent',display_name='Artificial parent',password_hash='not-a-login',role='parent',verified=True),
                User(id='b'*32, username='artificial-child',display_name='Artificial child',password_hash='not-a-login',role='child',verified=True)])
    db.flush()
    db.add(Child(id='c'*32, family_id='f'*32,user_id='b'*32,grade=7,preferences={'marker':'unchanged'}))
    db.flush()
    db.add(LearningUnit(id='d'*32,child_id='c'*32,subject='Mathematik',topic='Synthetic paused round',explanation='Unchanged',questions=[],provider='synthetic',status='paused'))
    db.add(ParentGoalReminder(user_id='a'*32,child_id='c'*32,revision=3,enabled=False,weekdays=[0,2],time='18:10',timezone='Europe/Berlin',daily_minimum=True,exam_sessions=False))
    db.flush()
    db.add(Attempt(id='e'*32,unit_id='d'*32,question_id='q1',answer='1/2 🧪 e\u0301',outcome='uncertain',evaluation={'preserve':True}))
old_tables = set(inspect(engine).get_table_names())
def snapshot():
    with engine.connect() as conn:
        return {name: list(conn.execute(select(Table(name,MetaData(),autoload_with=engine))).mappings()) for name in sorted(old_tables) if name!='alembic_version'}
before = snapshot()
command.upgrade(config, '0040')
command.upgrade(config, '0040')
command.upgrade(config, '0040')
assert snapshot()==before
inspector=inspect(engine)
assert set(inspector.get_table_names())-old_tables=={'learning_asset_builds','learning_asset_instances'}
assert {c['name'] for c in inspector.get_columns('learning_asset_builds')}=={'build_key','specification','status','job_id','reference_id','reference_version','reference_digest','technical_status','factual_status','created','updated'}
assert {c['name'] for c in inspector.get_columns('learning_asset_instances')}=={'id','child_id','user_id','build_key','request_key','request_digest','created'}
assert any(set(row['column_names'])=={'user_id','request_key'} for row in inspector.get_unique_constraints('learning_asset_instances'))
assert {row['referred_table'] for row in inspector.get_foreign_keys('learning_asset_instances')}=={'children','users','learning_asset_builds'}
assert any(row['constrained_columns']==['job_id'] and row['options'].get('ondelete')=='SET NULL' for row in inspector.get_foreign_keys('learning_asset_builds'))
with engine.connect() as conn:
    assert conn.exec_driver_sql('select count(*) from learning_asset_builds').scalar_one()==0
    assert conn.exec_driver_sql('select count(*) from learning_asset_instances').scalar_one()==0
    assert conn.exec_driver_sql('select version_num from alembic_version').scalar_one()=='0040'
print('actual 0039 -> 0040 migration / repeat / old data / schema: PASS')
'''


def test_actual_upgrade_preserves_old_child_attempt_and_reminder_data(tmp_path):
    original = os.environ.get("TEST_DATABASE_URL")
    schema = "assets_migration_" + uuid4().hex
    if original:
        from schulpilot.db import engine
        with engine.begin() as connection:
            connection.execute(text('CREATE SCHEMA "' + schema + '"'))
        url = make_url(original).update_query_dict({"options": "-csearch_path=" + schema}).render_as_string(hide_password=False)
    else:
        url = "sqlite:///" + str(tmp_path / "migration.sqlite")
    root = Path(__file__).resolve().parents[2]
    pythonpath = os.pathsep.join(filter(None, (str(root / "backend"), os.environ.get("PYTHONPATH"))))
    environment = {**os.environ, "DATABASE_URL": url, "DATA_DIR": str(tmp_path / "data"),
                   "TEST_DATABASE_URL": "", "PYTHONPATH": pythonpath}
    try:
        run = subprocess.run([sys.executable, "-c", SCRIPT], cwd=root, env=environment,
                             capture_output=True, text=True, timeout=90)
        assert run.returncode == 0, run.stdout + run.stderr
        assert "schema: PASS" in run.stdout
    finally:
        if original:
            with engine.begin() as connection:
                connection.execute(text('DROP SCHEMA "' + schema + '" CASCADE'))
