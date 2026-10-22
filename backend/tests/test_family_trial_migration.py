"""Actual additive 0028↔0029 preserves previous families and paid snapshots."""
import json
import os
import subprocess
import sys
import uuid
from pathlib import Path

import pytest
from schulpilot.db import engine
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.exc import IntegrityError


@pytest.mark.parametrize('dialect', ['sqlite', 'postgresql'])
def test_trial_migration_roundtrip_has_no_historical_backfill_or_paid_data_changes(tmp_path, dialect):
    schema = None
    if dialect == 'postgresql':
        if engine.dialect.name != 'postgresql':
            pytest.skip('Requires isolated PostgreSQL runner')
        schema = 'trial_migration_' + uuid.uuid4().hex
        with engine.begin() as con:
            con.execute(text(f'CREATE SCHEMA "{schema}"'))
        tested, url = engine, os.environ['TEST_DATABASE_URL']
    else:
        url = 'sqlite:///' + str(tmp_path / 'trial.sqlite')
        tested = create_engine(url)
    env = {**os.environ, 'DATABASE_URL': url, 'ENVIRONMENT': 'test'}
    if schema:
        env['PGOPTIONS'] = f'-c search_path={schema}'
    else:
        env.pop('PGOPTIONS', None)
    command = [sys.executable, '-m', 'alembic', '-c', str(Path(__file__).resolve().parents[1] / 'alembic.ini')]

    def scope(con):
        if schema:
            con.execute(text(f'SET LOCAL search_path TO "{schema}"'))

    def migrate(target, direction='upgrade'):
        result = subprocess.run([*command, direction, target], env=env, capture_output=True)
        assert result.returncode == 0, result.stderr.decode(errors='replace')[-2000:]

    try:
        migrate('0028')
        with tested.begin() as con:
            scope(con)
            con.execute(text("INSERT INTO families(id,name,synthetic,created,child_limit,call_limit,budget_micros,plan,commerce_required) VALUES('f','Synthetic paid',false,1,1,300,5000000,'Saved Start',true)"))
            con.execute(text("INSERT INTO families(id,name,synthetic,created,child_limit,call_limit,budget_micros,plan,commerce_required) VALUES('legacy','Synthetic legacy',false,1,4,100,2000000,'Pilot',false)"))
            con.execute(text("INSERT INTO users(id,username,display_name,password_hash,role,verified,disabled,created) VALUES('u','synthetic','Synthetic','SYNTHETIC-HASH','parent',true,false,1)"))
            con.execute(text("INSERT INTO store_configuration(id,encrypted_config,revision,ever_enabled) VALUES(1,'SYNTHETIC-ENCRYPTED-STORE',7,false)"))
            con.execute(text("INSERT INTO bank_orders(id,family_id,buyer_id,idempotency,payment_reference,status,amount_cents,offer,seller,bank,terms,terms_version,early_start,created,starts,ends,mail_status) VALUES('o','f','u','synthetic-order','SYNTHETIC-REF','paid',990,:offer,'{}','{}','Saved synthetic terms','2026-10-14.1',true,1,2,2000000000,'accepted')"), {"offer": json.dumps({"id": "start", "calls": 300})})
        migrate('0029')
        with tested.begin() as con:
            scope(con)
            assert {c['name'] for c in inspect(con).get_columns('family_trials', schema=schema)} == {
                'family_id', 'owner_user_id', 'created', 'starts', 'ends', 'child_limit', 'call_limit', 'budget_micros', 'version'}
            assert con.scalar(text('SELECT count(*) FROM family_trials')) == 0
            assert con.scalar(text('SELECT ever_trial_enabled FROM store_configuration WHERE id=1')) in (False, 0)
            assert con.scalar(text('SELECT encrypted_config FROM store_configuration WHERE id=1')) == 'SYNTHETIC-ENCRYPTED-STORE'
            assert con.scalar(text("SELECT commerce_required FROM families WHERE id='legacy'")) in (False, 0)
            assert con.scalar(text("SELECT plan FROM families WHERE id='f'")) == 'Saved Start'
            assert con.scalar(text("SELECT terms FROM bank_orders WHERE id='o'")) == 'Saved synthetic terms'
            # SQL CHECK permits UNKNOWN; both timestamps must explicitly be
            # non-NULL in the active branch. Exercise the actual migrated table
            # in both engines, before inserting any valid row for this family.
            for starts, ends in ((100, None), (None, 2592100), (100, 101)):
                with pytest.raises(IntegrityError), con.begin_nested():
                    con.execute(text("INSERT INTO family_trials(family_id,owner_user_id,created,starts,ends,child_limit,call_limit,budget_micros,version) VALUES('f','u',100,:starts,:ends,1,100,2000000,'verified-family-trial-1')"),
                                {"starts": starts, "ends": ends})
            con.execute(text("INSERT INTO family_trials(family_id,owner_user_id,created,starts,ends,child_limit,call_limit,budget_micros,version) VALUES('f','u',100,100,2592100,1,100,2000000,'verified-family-trial-1')"))
        migrate('0028', 'downgrade')
        with tested.begin() as con:
            scope(con)
            assert con.scalar(text('SELECT revision FROM store_configuration WHERE id=1')) == 7
            assert con.scalar(text("SELECT amount_cents FROM bank_orders WHERE id='o'")) == 990
            assert con.scalar(text("SELECT call_limit FROM families WHERE id='f'")) == 300
            assert con.scalar(text("SELECT commerce_required FROM families WHERE id='legacy'")) in (False, 0)
        migrate('0029')
    finally:
        if schema:
            with engine.begin() as con:
                con.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        else:
            tested.dispose()
