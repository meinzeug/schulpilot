"""Verified real-family trials; all identities/content/payments are synthetic."""
import io
import json
import zipfile
from concurrent.futures import ThreadPoolExecutor

import pytest
from conftest import HEADERS, create_child, register
from fastapi import HTTPException
from fastapi.testclient import TestClient
from schulpilot import auth, commerce, mail
from schulpilot.config import settings
from schulpilot.db import (
    DB,
    Audit,
    BankOrder,
    Family,
    FamilyTrial,
    GoogleFlow,
    Job,
    Material,
    Membership,
    ProviderConfig,
    Usage,
    UsageBucket,
    User,
    now,
    uid,
)
from schulpilot.main import app
from schulpilot.providers import reserve, settle
from sqlalchemy import func, select
from test_commerce import check
from test_commerce import operator as operator_fixture
from test_google_login import begin, callback, registration, result
from test_google_login import google as google_fixture
from test_providers import configured


@pytest.fixture
def operator(api):
    yield from operator_fixture.__wrapped__(api)


@pytest.fixture
def google(monkeypatch):
    return google_fixture.__wrapped__(monkeypatch)


@pytest.fixture
def trial_store(operator, monkeypatch):
    for key, value in {
        'operator_name': 'Künstlicher Anbieter', 'operator_address': 'Künstliche Straße 1, 12345 Beispielort',
        'operator_support_email': 'synthetic@example.org', 'smtp_host': 'smtp.invalid',
        'smtp_from': 'synthetic@example.org',
    }.items():
        object.__setattr__(settings, key, value)
    monkeypatch.setattr(mail, 'send_message', lambda *args: None)
    response = operator.put('/api/admin/store', json={'revision': 0, 'enabled': False, 'trial_enabled': True})
    assert response.status_code == 200, response.text
    return operator


def pending(api, mailbox, email='trial-parent@example.org'):
    response = api.post('/api/auth/register', json={
        'email': email, 'password': 'secure-parent-pass-123', 'display_name': 'Künstliche Eltern',
        'family_name': 'Künstliche Testfamilie', 'adult_consent': True})
    assert response.status_code == 201, response.text
    with DB() as db:
        user = db.scalar(select(User).where(User.email == email))
        family = db.scalar(select(Membership.family_id).where(Membership.user_id == user.id))
        return user.id, family, mailbox[-1]['token']


def data(operator):
    value = operator.get('/api/admin/store').json()
    value.pop('missing')
    value.pop('trial_missing')
    return value


def counts():
    with DB() as db:
        return tuple(db.scalar(select(func.count()).select_from(model)) for model in (BankOrder, Job, Usage))


def test_trial_defaults_off_and_incomplete_legal_details_cannot_advertise_or_enable_it(api, operator):
    catalog = api.get('/api/store/catalog').json()
    assert catalog['trial']['enabled'] is False and catalog['trial']['duration_days'] == 30
    assert catalog['trial']['payment_required'] is False and catalog['trial']['auto_renew'] is False
    denied = operator.put('/api/admin/store', json={'revision': 0, 'trial_enabled': True})
    assert denied.status_code == 422 and 'Betreiberangaben' in denied.json()['detail']
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(FamilyTrial)) == 0


def test_real_admin_trial_contract_reports_readiness_separately_from_paid_sale(api, operator):
    before = counts()
    initial = operator.get('/api/admin/store')
    assert initial.status_code == 200
    values = initial.json()
    assert values['trial_enabled'] is False
    assert isinstance(values['trial_missing'], list)
    assert 'Vollständige Betreiberangaben' in values['trial_missing']
    assert api.get('/api/admin/store').status_code == 401
    for key, value in {
        'operator_name': 'Künstlicher Anbieter', 'operator_address': 'Künstliche Straße 1, 12345 Beispielort',
        'operator_support_email': 'synthetic@example.org', 'smtp_host': 'smtp.invalid',
        'smtp_from': 'synthetic@example.org',
    }.items():
        object.__setattr__(settings, key, value)
    ready = operator.get('/api/admin/store').json()
    assert ready['trial_missing'] == [] and ready['missing']
    changed = operator.put('/api/admin/store', json={
        'revision': ready['revision'], 'enabled': False, 'trial_enabled': True})
    assert changed.status_code == 200, changed.text
    saved = operator.get('/api/admin/store').json()
    assert saved['trial_enabled'] is True and saved['trial_missing'] == []
    catalog = api.get('/api/store/catalog').json()
    assert catalog['trial']['enabled'] is True and catalog['enabled'] is False
    assert counts() == before == (0, 0, 0)


def test_free_trial_is_independent_of_missing_bank_tax_and_paid_checkout(api, trial_store):
    before = counts()
    first = api.get('/api/store/catalog').json()
    second = api.get('/api/store/catalog').json()
    assert first == second and not first['enabled']
    assert first['trial']['enabled'] and first['trial']['children'] == 1 and first['trial']['calls'] == settings.default_call_limit
    assert first['trial']['starts_on'] == 'verified_email' and 'budget_micros_usd' not in first['trial']
    assert counts() == before == (0, 0, 0)


def test_registration_prepares_trial_but_the_30_days_begin_only_on_verification(api, mailbox, trial_store, monkeypatch):
    user_id, fid, token = pending(api, mailbox)
    with DB() as db:
        trial = db.get(FamilyTrial, fid)
        assert trial.starts is None and trial.ends is None
        assert commerce.access(db, db.get(Family, fid))['state'] == 'inactive'
        assert not db.get(User, user_id).verified
        with pytest.raises(HTTPException):
            commerce.usage_terms(db, db.get(Family, fid), enforce=True)
    started = int(now()) + 123
    monkeypatch.setattr(commerce, 'now', lambda: started)
    assert api.post('/api/auth/verify', json={'token': token}).status_code == 200
    with DB() as db:
        trial = db.get(FamilyTrial, fid)
        assert trial.starts == started and trial.ends == started + 30 * 86400
        family = db.get(Family, fid)
        assert family.expires is None and family.commerce_required
        assert family.child_limit == 1
        assert commerce.access(db, family)['state'] == 'trial'
        assert commerce.usage_terms(db, family, enforce=True) == (f'{fid}:trial', settings.default_call_limit, settings.default_budget_micros)
    assert counts() == (0, 0, 0)


def test_resend_duplicate_links_and_two_parallel_verifications_start_exactly_once(api, mailbox, trial_store):
    user_id, fid, token = pending(api, mailbox)
    with DB.begin() as db:
        second = auth.new_token(db, 'verify', user_id, ttl=86400)
    def verify(value):
        with TestClient(app, headers=HEADERS) as client:
            return client.post('/api/auth/verify', json={'token': value}).status_code
    with ThreadPoolExecutor(max_workers=2) as pool:
        assert list(pool.map(verify, [token, second])) == [200, 200]
    with DB() as db:
        original = (db.get(FamilyTrial, fid).starts, db.get(FamilyTrial, fid).ends)
        assert db.scalar(select(func.count()).select_from(Audit).where(Audit.action == 'trial.started')) == 1
    assert api.post('/api/auth/verify', json={'token': token}).status_code == 400
    assert api.post('/api/auth/resend-verification', json={'email': 'trial-parent@example.org'}).status_code == 200
    with DB() as db:
        assert (db.get(FamilyTrial, fid).starts, db.get(FamilyTrial, fid).ends) == original


def test_pending_promised_trial_survives_disabling_new_trials_without_opening_free_pilot_access(api, mailbox, trial_store):
    _, fid, token = pending(api, mailbox)
    config = data(trial_store)
    config['trial_enabled'] = False
    assert trial_store.put('/api/admin/store', json=config).status_code == 200
    assert api.post('/api/auth/verify', json={'token': token}).status_code == 200
    with DB() as db:
        assert commerce.access(db, db.get(Family, fid))['state'] == 'trial'
    user = register(api, mailbox, email='after-trial-paused@example.org')
    with DB() as db:
        other = db.get(Family, user['families'][0]['id'])
        assert other.commerce_required and not db.get(FamilyTrial, other.id)
        with pytest.raises(HTTPException):
            commerce.usage_terms(db, other, enforce=True)


def test_old_admin_payload_preserves_the_separate_trial_flag_and_stale_revision_is_rejected(api, trial_store):
    config = data(trial_store)
    config.pop('trial_enabled')
    assert trial_store.put('/api/admin/store', json=config).status_code == 200
    assert trial_store.get('/api/admin/store').json()['trial_enabled'] is True
    assert trial_store.put('/api/admin/store', json=config).status_code == 409


def test_existing_pilot_family_is_never_backfilled_or_reset(household, trial_store):
    parent, _ = household
    # Explicitly reconstruct the pre-launch pilot fixture, not a new signup.
    with DB.begin() as db:
        previous = db.get(Family, parent['families'][0]['id'])
        previous.commerce_required, previous.plan = False, settings.default_plan
        previous.child_limit, previous.call_limit = settings.default_child_limit, settings.default_call_limit
    with DB() as db:
        family = db.get(Family, parent['families'][0]['id'])
        assert not family.commerce_required and family.plan == settings.default_plan
        assert not db.get(FamilyTrial, family.id)
        assert commerce.access(db, family)['state'] == 'existing'
        assert commerce.usage_terms(db, family, enforce=True)[1:] == (settings.default_call_limit, settings.default_budget_micros)


def test_trial_has_one_child_and_does_not_increase_any_global_budget(api, mailbox, trial_store):
    with DB() as db:
        global_limit = db.get(ProviderConfig, 1).global_limit_micros
    parent = register(api, mailbox, email='bounded-trial@example.org')
    fid = parent['families'][0]['id']
    create_child(api, parent)
    second = api.post(f'/api/families/{fid}/children', json={
        'display_name': 'Anderes künstliches Kind', 'username': 'trial-second-child',
        'password': 'secure-child-pass-123', 'grade': 6, 'subjects': ['Mathematik']})
    assert second.status_code == 409
    assert api.get(f'/api/families/{fid}').json()['child_limit'] == 1
    with DB() as db:
        trial = db.get(FamilyTrial, fid)
        assert trial.call_limit == settings.default_call_limit and trial.budget_micros == settings.default_budget_micros
        assert db.get(ProviderConfig, 1).global_limit_micros == global_limit


def test_expiry_at_exact_end_blocks_new_ai_but_keeps_saved_own_material_and_account(api, mailbox, trial_store, monkeypatch):
    parent = register(api, mailbox, email='expiry-trial@example.org')
    child = create_child(api, parent)
    fid = parent['families'][0]['id']
    with DB.begin() as db:
        item = Material(child_id=child['id'], title='Künstliche gespeicherte Seite', subject='Mathematik',
            topic='Brüche', content='Künstlicher bestätigter Text.', confirmed=True, status='confirmed')
        db.add(item)
        db.flush()
        mid, end = item.id, db.get(FamilyTrial, fid).ends
    monkeypatch.setattr(commerce, 'now', lambda: end - 1)
    with DB() as db:
        assert commerce.access(db, db.get(Family, fid))['state'] == 'trial'
    monkeypatch.setattr(commerce, 'now', lambda: end)
    with DB() as db:
        assert commerce.access(db, db.get(Family, fid))['state'] == 'trial_expired'
        with pytest.raises(HTTPException):
            commerce.usage_terms(db, db.get(Family, fid), enforce=True)
        assert db.get(Family, fid).expires is None
    assert api.get(f'/api/materials/{mid}').status_code == 200
    assert api.get(f'/api/families/{fid}').status_code == 200


def test_snapshot_caps_and_usage_period_do_not_reset_on_month_or_setting_changes(api, mailbox, trial_store, monkeypatch):
    user = register(api, mailbox, email='snapshot-trial@example.org')
    fid = user['families'][0]['id']
    with DB() as db:
        trial = db.get(FamilyTrial, fid)
        original = commerce.usage_terms(db, db.get(Family, fid), enforce=True)
        started = trial.starts
    object.__setattr__(settings, 'default_call_limit', 50)
    object.__setattr__(settings, 'default_budget_micros', 1000000)
    monkeypatch.setattr(commerce, 'now', lambda: started + 29 * 86400)
    with DB() as db:
        assert commerce.usage_terms(db, db.get(Family, fid), enforce=True) == original
    assert api.get('/api/store/catalog').json()['trial']['calls'] == 50


def test_paid_access_keeps_original_start_rules_and_overrides_without_resetting_trial(api, mailbox, trial_store):
    parent = register(api, mailbox, email='paid-trial@example.org')
    fid = parent['families'][0]['id']
    with DB() as db:
        row = db.get(FamilyTrial, fid)
        snapshot = (row.starts, row.ends, row.call_limit, row.budget_micros)
    config = data(trial_store)
    config.update(enabled=True, recipient='Künstlicher Anbieter', iban='DE89370400440532013000', tax_mode='standard19')
    assert trial_store.put('/api/admin/store', json=config).status_code == 200
    catalog = api.get('/api/store/catalog').json()
    submitted = api.post(f'/api/families/{fid}/orders', json={
        'plan_id': 'start', 'catalog_revision': catalog['revision'], 'request_key': 'synthetic-trial-paid-0001',
        'accept_terms': True, 'early_start': True})
    assert submitted.status_code == 201, submitted.text
    approved = check(trial_store, submitted.json()['id'])
    assert approved.status_code == 200, approved.text
    assert approved.json()['starts'] < snapshot[1]
    assert approved.json()['ends'] - approved.json()['starts'] == 30 * 86400
    with DB() as db:
        row = db.get(FamilyTrial, fid)
        assert (row.starts, row.ends, row.call_limit, row.budget_micros) == snapshot
        family = db.get(Family, fid)
        assert commerce.access(db, family)['state'] == 'active'
        assert ':paid:' in commerce.usage_terms(db, family, enforce=True)[0]
        assert commerce.effective_child_limit(db, family) == 1
    with DB.begin() as db:
        # A later explicit operator tariff override retains its old authority.
        db.get(Family, fid).child_limit = 2
    with DB() as db:
        assert commerce.effective_child_limit(db, db.get(Family, fid)) == 2


def test_trial_export_and_normal_family_erasure_preserve_then_cascade_grant(api, mailbox, trial_store):
    parent = register(api, mailbox, email='export-trial@example.org')
    fid = parent['families'][0]['id']
    exported = api.get(f'/api/families/{fid}/export')
    assert exported.status_code == 200
    with zipfile.ZipFile(io.BytesIO(exported.content)) as archive:
        value = json.loads(archive.read('family.json'))
        assert value['trial']['state'] == 'active' and value['trial']['duration_days'] == 30
        assert value['orders'] == [] and 'owner_user_id' not in value['trial']
    removed = api.request('DELETE', '/api/account', json={'password': 'secure-parent-pass-123'})
    assert removed.status_code == 200, removed.text
    with DB() as db:
        assert not db.get(FamilyTrial, fid) and not db.get(Family, fid)


def test_google_authoritative_new_registration_starts_the_same_bounded_trial(api, google, trial_store):
    _, state = begin(api, google)
    callback(api, state)
    with DB() as db:
        flow = db.scalar(select(GoogleFlow))
        flow_id = flow.id
    created = result(api, {'flow_id': flow_id}, registration=registration())
    assert created.status_code == 200, created.text
    assert created.json()['status'] == 'authenticated'
    with DB() as db:
        user = db.scalar(select(User).where(User.email == registration()['email']))
        fid = db.scalar(select(Membership.family_id).where(Membership.user_id == user.id))
        trial = db.get(FamilyTrial, fid)
        assert trial.starts is not None and trial.ends - trial.starts == 30 * 86400 and trial.child_limit == 1


def test_google_non_authoritative_mail_starts_only_after_our_own_verification(api, google, mailbox, trial_store):
    google[0].pop('hd')
    _, state = begin(api, google)
    callback(api, state)
    with DB() as db:
        flow = db.scalar(select(GoogleFlow))
        flow_id = flow.id
    created = result(api, {'flow_id': flow_id}, registration=registration())
    assert created.status_code == 200 and created.json()['status'] == 'verification_required'
    with DB() as db:
        trial = db.scalar(select(FamilyTrial))
        fid = trial.family_id
        assert trial.starts is None
    assert api.post('/api/auth/verify', json={'token': mailbox[-1]['token']}).status_code == 200
    with DB() as db:
        assert db.get(FamilyTrial, fid).starts is not None


def test_never_enabled_store_and_trial_are_fail_closed_for_new_password_accounts(api, mailbox):
    first = pending(api, mailbox, email='not-yet-open@example.org')
    user_id, fid, token = first
    duplicate = api.post('/api/auth/register', json={
        'email': 'not-yet-open@example.org', 'password': 'secure-parent-pass-123',
        'display_name': 'Künstliche Eltern', 'family_name': 'Künstliche Familie', 'adult_consent': True})
    assert 'noch vorbereitet' in duplicate.json()['access_notice']
    assert api.post('/api/auth/verify', json={'token': token}).status_code == 200
    with DB() as db:
        family = db.get(Family, fid)
        assert family.commerce_required and family.plan == 'Noch kein Tarif' and family.call_limit == 0
        assert not db.get(FamilyTrial, fid) and family.expires is None
        with pytest.raises(HTTPException):
            commerce.usage_terms(db, family, enforce=True)
    user = register(api, mailbox, email='explicit-current-signup@example.org', historical_pilot=False)
    with DB() as db:
        assert db.get(Family, user['families'][0]['id']).commerce_required


def test_never_enabled_store_and_trial_are_fail_closed_for_new_google_accounts(api, google):
    flow, state = begin(api, google)
    callback(api, state)
    created = result(api, flow, registration=registration())
    assert created.status_code == 200 and created.json()['status'] == 'authenticated'
    assert 'noch vorbereitet' in created.json()['access_notice']
    fid = created.json()['user']['families'][0]['id']
    with DB() as db:
        family = db.get(Family, fid)
        assert family.commerce_required and family.call_limit == 0 and not db.get(FamilyTrial, fid)
        with pytest.raises(HTTPException):
            commerce.usage_terms(db, family, enforce=True)


def test_trial_reservations_use_the_existing_atomic_cap_and_retain_unknown_costs(api, mailbox, trial_store):
    parent = register(api, mailbox, email='atomic-trial@example.org', historical_pilot=False)
    child = create_child(api, parent)
    fid = parent['families'][0]['id']
    configured(fid)  # Mock credentials/prices only; reserve never calls a provider.
    with DB.begin() as db:
        trial = db.get(FamilyTrial, fid)
        trial.call_limit, trial.budget_micros = 2, 2000
    def attempt(_):
        try:
            with DB.begin() as db:
                usage = reserve(db, db.get(Family, fid), child['id'], uid(), 'unit')
                settle(db, usage, failed=True)
            return 'held'
        except HTTPException as error:
            return error.status_code
    with ThreadPoolExecutor(max_workers=6) as pool:
        values = list(pool.map(attempt, range(8)))
    assert values.count('held') == 2 and values.count(429) == 6
    with DB() as db:
        bucket = db.get(UsageBucket, f'{fid}:trial')
        assert bucket.calls == 2 and bucket.encumbered_micros == 2000 and bucket.unknown_calls == 2
        rows = list(db.scalars(select(Usage)))
        assert len(rows) == 2 and all(row.status == 'failed_unknown' and row.cost_micros is None for row in rows)
        assert db.scalar(select(func.count()).select_from(BankOrder)) == 0
