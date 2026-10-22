"""Isolated neutral operator metadata, never learning contents or provider work."""
import base64
import json
from datetime import datetime, timezone

import pytest
from conftest import HEADERS
from fastapi.testclient import TestClient
from schulpilot.db import DB, Audit
from schulpilot.main import app
from sqlalchemy import select
from test_codex_models import operator as operator_fixture
from test_parent_workflows_ux90 import snapshot


@pytest.fixture
def operator():
    yield from operator_fixture.__wrapped__()


def seed(count=225):
    with DB.begin() as db:
        db.add_all(Audit(id=f'{index:032x}', actor=f'{index % 2 + 1:032x}', action='synthetic.read' if index % 2 else 'synthetic.write',
            target=f'synthetic-target-{index}', created=1609459200 + index // 3) for index in range(count))


@pytest.mark.parametrize('order', ['oldest', 'newest'])
def test_operator_can_reach_older_than_200_with_stable_tie_break_and_no_inference(operator, order):
    seed()
    before = snapshot()
    cursor, frozen, found = None, None, []
    for _ in range(5):
        response = operator.get('/api/admin/audit-events', params={'q': 'synthetic-target-', 'order': order,
            **({'cursor': cursor, 'snapshot': frozen} if cursor else {})})
        assert response.status_code == 200, response.text
        value = response.json()
        assert value['total'] == 225
        if frozen is not None:
            assert value['snapshot'] == frozen
        frozen, cursor = value['snapshot'], value['next_cursor']
        assert all(set(item) == {'id', 'actor', 'action', 'target', 'created'} for item in value['items'])
        found += [(item['created'], item['id']) for item in value['items']]
    assert len(found) == len(set(found)) == 225 and cursor is None
    assert found == sorted(found, reverse=order == 'newest')
    assert snapshot() == before
    with DB() as db:
        assert db.scalar(select(Audit).where(Audit.action == 'admin.audit_read', Audit.target == 'audit-pages')) is not None


def test_full_history_search_is_literal_and_actor_action_are_exact(operator):
    seed()
    for literal in ['%', '_', 'synthetic-target-9999']:
        assert operator.get('/api/admin/audit-events', params={'q': literal}).json()['items'] == []
    value = operator.get('/api/admin/audit-events', params={'actor': f'{1:032x}', 'action': 'synthetic.write', 'q': 'target-2'}).json()
    assert value['total'] == 19
    assert all(row['actor'] == f'{1:032x}' and row['action'] == 'synthetic.write' and 'target-2' in row['target'] for row in value['items'])
    assert value['action_counts'] == [{'action': 'synthetic.write', 'count': 19}]


def test_audit_date_interval_is_utc_inclusive_and_snapshot_excludes_new_actions(operator):
    seed(3)
    selected = operator.get('/api/admin/audit-events', params={'start': '2021-01-01', 'end': '2021-01-01', 'q': 'synthetic-target-'}).json()
    assert selected['total'] == 3
    assert selected['filters']['start'] == selected['filters']['end'] == '2021-01-01'
    with DB.begin() as db:
        db.add(Audit(actor='1' * 32, action='synthetic.read', target='synthetic-target-later', created=selected['snapshot'] + 1))
    repeat = operator.get('/api/admin/audit-events', params={'q': 'synthetic-target-', 'snapshot': selected['snapshot']}).json()
    assert repeat['total'] == 3
    assert operator.get('/api/admin/audit-events', params={'start': '2021-01-02', 'end': '2021-01-01'}).status_code == 422
    assert operator.get('/api/admin/audit-events', params={'end': '9999-12-31'}).status_code == 422
    assert operator.get('/api/admin/audit-events', params={'snapshot': int(datetime.now(timezone.utc).timestamp())+1000}).status_code == 422


@pytest.mark.parametrize('cursor', ['x', 'A', '%%%%', 'e30', base64.urlsafe_b64encode(json.dumps({'created': 'bad', 'id': 'a'*32}).encode()).decode().rstrip('='),
    base64.urlsafe_b64encode(json.dumps({'created': 10, 'id': 'a'*32, 'extra': 1}).encode()).decode().rstrip('=')])
def test_invalid_cursor_is_controlled_validation_not_internal_error(operator, cursor):
    assert operator.get('/api/admin/audit-events', params={'cursor': cursor}).status_code == 422


def test_new_audit_history_keeps_existing_admin_only_scope(api, household, operator):
    assert api.get('/api/admin/audit-events').status_code == 403
    with TestClient(app, headers=HEADERS) as child:
        assert child.get('/api/admin/audit-events').status_code == 401
        login = child.post('/api/auth/login', json={'username': 'test-child', 'password': 'secure-child-pass-123'}).json()
        child.headers['Authorization'] = 'Bearer ' + login['token']
        assert child.get('/api/admin/audit-events').status_code == 403
    assert isinstance(operator.get('/api/admin/audit').json(), list)


def entitlement_data():
    return {'plan':'Synthetischer Tarif','child_limit':2,'call_limit':80,'budget_micros':1000000}


def test_operator_tariff_revision_conflict_preserves_current_limits_and_legacy_contract(operator):
    from schulpilot.db import Family

    with DB.begin() as db:
        row = Family(name='Synthetisch',**entitlement_data())
        db.add(row)
        db.flush()
        identifier = row.id
    initial = operator.get('/api/admin/families',params={'paginated':'true','search':identifier}).json()['items'][0]
    revision = initial['entitlement_revision']
    path = f'/api/admin/families/{identifier}/entitlements'
    response = operator.put(path,json={**entitlement_data(),'child_limit':3},headers={'If-Match':revision})
    assert response.status_code == 200 and response.json()['entitlement_revision'] != revision
    assert operator.put(path,json=entitlement_data(),headers={'If-Match':revision}).status_code == 409
    with DB() as db:
        assert db.get(Family,identifier).child_limit == 3
    assert operator.put(path,json=entitlement_data()).status_code == 200


def test_parallel_operator_tariff_writes_claim_exactly_one_current_snapshot(operator):
    from concurrent.futures import ThreadPoolExecutor

    from schulpilot.db import Family

    with DB.begin() as db:
        row = Family(name='Synthetisch',**entitlement_data())
        db.add(row)
        db.flush()
        identifier = row.id
    initial = operator.get('/api/admin/families',params={'paginated':'true','search':identifier}).json()['items'][0]
    def write(limit):
        return operator.put(f'/api/admin/families/{identifier}/entitlements',json={**entitlement_data(),'child_limit':limit},
            headers={'If-Match':initial['entitlement_revision']}).status_code
    with ThreadPoolExecutor(max_workers=2) as pool:
        assert sorted(pool.map(write,[3,4])) == [200,409]


@pytest.mark.parametrize('revoke', ['session','role'])
def test_operator_tariff_waiting_for_family_rechecks_admin_session_after_lock(operator, revoke):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Event

    from schulpilot.db import Family, Session, User, engine
    from sqlalchemy import event, update

    if engine.dialect.name != 'postgresql':
        pytest.skip('PostgreSQL row-lock concurrency case')
    with DB.begin() as db:
        row = Family(name='Synthetisch',**entitlement_data())
        db.add(row)
        db.flush()
        identifier = row.id
    entered = Event()
    def reached(_connection, _cursor, statement, _parameters, _context, _many):
        if 'FROM families' in statement and 'FOR UPDATE' in statement:
            entered.set()
    with ThreadPoolExecutor(max_workers=1) as pool:
        with DB.begin() as blocker:
            blocker.scalar(select(Family).where(Family.id==identifier).with_for_update())
            event.listen(engine,'before_cursor_execute',reached)
            try:
                future = pool.submit(operator.put,f'/api/admin/families/{identifier}/entitlements',json={**entitlement_data(),'child_limit':3})
                assert entered.wait(5), 'Request must actually reach its blocked row lock'
                with DB.begin() as db:
                    user = db.scalar(select(User).where(User.role=='admin'))
                    if revoke == 'role':
                        db.execute(update(User).where(User.id==user.id).values(role='parent'))
                    else:
                        db.execute(update(Session).where(Session.user_id==user.id).values(revoked=True))
            finally:
                event.remove(engine,'before_cursor_execute',reached)
        response = future.result(timeout=10)
        assert response.status_code == (401 if revoke=='session' else 403)
    with DB() as db:
        assert db.get(Family,identifier).child_limit == 2
