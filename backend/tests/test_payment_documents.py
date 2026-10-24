"""Isolated document, cookie, provider-boundary and private export integration."""
import io
import json
import re
import zipfile

from conftest import HEADERS, create_child, register
from fastapi.testclient import TestClient
from pydantic import ValidationError
from schulpilot import payment_documents
from schulpilot.config import settings
from schulpilot.db import DB, BankOrder, Membership, User
from schulpilot.installation import SiteUpdate
from schulpilot.main import app
from schulpilot.security import password_hash
from test_order_withdrawals import body, seed


def cookie_only(client):
    client.headers.pop("Authorization", None)
    assert client.cookies.get("sp_session")


def test_public_forms_have_escaped_fields_and_unique_nonce_without_provider(api, monkeypatch):
    object.__setattr__(settings, "web_dir", "")
    first = api.get("/api/legal/withdrawal")
    second = api.get("/api/legal/withdrawal")
    assert first.status_code == second.status_code == 200
    assert 'data-mode="public"' in first.text and 'data-order-id=""' in first.text
    nonce = re.search(r'nonce="([A-Za-z0-9_-]+)"', first.text).group(1)
    assert len(nonce) >= 32 and nonce in first.headers['content-security-policy']
    assert not re.search(r'__[A-Z][A-Z0-9_]*__', first.text.replace(nonce, ''))
    assert nonce not in second.text
    assert 'paypal.com' not in first.headers['content-security-policy']
    assert first.headers['cache-control'] == 'no-store'
    assert first.headers['referrer-policy'] == 'no-referrer'
    assert first.headers['x-frame-options'] == 'DENY'


def test_public_form_allows_valid_double_underscore_nonces_and_binds_each_csp(api, monkeypatch):
    object.__setattr__(settings, "web_dir", "")
    values = ("A" * 14 + "__" + "B" * 16, "C" * 32)
    nonces = iter(values)
    monkeypatch.setattr(payment_documents.secrets, "token_urlsafe", lambda _size: next(nonces))
    responses = (api.get("/api/legal/withdrawal"), api.get("/api/legal/withdrawal"))
    for nonce, response in zip(values, responses, strict=True):
        assert response.status_code == 200
        assert f'nonce="{nonce}"' in response.text
        assert f"'nonce-{nonce}'" in response.headers['content-security-policy']
        assert not re.search(r'__[A-Z][A-Z0-9_]*__', response.text.replace(nonce, ''))
        assert 'data-mode="public"' in response.text and 'data-order-id=""' in response.text
    assert values[0] not in responses[1].text and values[1] not in responses[0].text


def test_checkout_requires_real_cookie_owner_and_safe_id(api, mailbox):
    user = register(api, mailbox)
    identifier, _ = seed(user)
    with DB.begin() as db:
        db.get(BankOrder, identifier).payment_method = 'paypal'
    # Native bearer credentials never get copied into document links.
    assert api.get(f'/api/orders/{identifier}/payment-checkout', follow_redirects=False).status_code == 303
    cookie_only(api)
    response = api.get(f'/api/orders/{identifier}/payment-checkout')
    assert response.status_code == 200
    assert f'data-order-id="{identifier}"' in response.text
    assert 'https://*.paypal.com' in response.headers['content-security-policy']
    assert 'wasm-unsafe-eval' not in response.headers['content-security-policy']
    assert api.get('/api/orders/not-an-id/payment-checkout').status_code == 404
    with TestClient(app, headers=HEADERS) as stranger:
        register(stranger, mailbox, 'stranger@example.org')
        cookie_only(stranger)
        assert stranger.get(f'/api/orders/{identifier}/payment-checkout').status_code == 404
    with DB.begin() as db:
        db.get(BankOrder, identifier).payment_method = 'bank_transfer'
    assert api.get(f'/api/orders/{identifier}/payment-checkout', follow_redirects=False).headers['location'] == '/bestellungen'
    assert api.get('/api/admin/withdrawals/dashboard').status_code == 403
    assert api.post('/api/auth/logout').status_code == 200
    assert api.get(f'/api/orders/{identifier}/payment-checkout', follow_redirects=False).headers['location'] == '/login'


def test_owner_form_escapes_personal_values_and_uses_authenticated_scope(api, mailbox):
    user = register(api, mailbox)
    identifier, _ = seed(user)
    with DB.begin() as db:
        db.get(User, user['id']).display_name = 'Testperson " onfocus="alert(1) <script>x</script>'
    cookie_only(api)
    response = api.get(f'/api/orders/{identifier}/withdrawal-form')
    assert response.status_code == 200
    assert 'data-mode="owner"' in response.text
    assert '&quot; onfocus=&quot;alert(1) &lt;script&gt;x&lt;/script&gt;' in response.text
    assert '<script>x</script>' not in response.text
    assert 'value="parent@example.org"' in response.text
    assert '__BUYER_NAME__' not in response.text


def test_child_and_admin_cannot_open_private_order_documents(api, mailbox):
    user = register(api, mailbox)
    identifier, _ = seed(user)
    create_child(api, user)
    with TestClient(app, headers=HEADERS) as child:
        assert child.post('/api/auth/login', json={'username':'test-child','password':'secure-child-pass-123'}).status_code == 200
        for suffix in ('payment-checkout', 'withdrawal-form'):
            assert child.get(f'/api/orders/{identifier}/{suffix}').status_code == 403
        assert child.get('/api/admin/withdrawals/dashboard').status_code == 403
    with DB.begin() as db:
        db.add(User(username='documents-admin',display_name='Betrieb',role='admin',verified=True,
                    password_hash=password_hash('synthetic-documents-admin-123')))
    with TestClient(app, headers=HEADERS) as operator:
        assert operator.post('/api/auth/login',json={'username':'documents-admin','password':'synthetic-documents-admin-123'}).status_code == 200
        assert operator.get('/api/admin/withdrawals/dashboard').status_code == 200
        for suffix in ('payment-checkout', 'withdrawal-form'):
            assert operator.get(f'/api/orders/{identifier}/{suffix}').status_code == 403


def test_template_missing_is_explicitly_unavailable(api, monkeypatch, tmp_path):
    object.__setattr__(settings, 'web_dir', str(tmp_path))
    assert api.get('/api/legal/withdrawal').status_code == 503
    (tmp_path/'withdrawal.html').write_text('x'*65537)
    assert api.get('/api/legal/withdrawal').status_code == 503


def test_get_documents_never_create_payment_or_withdrawal(api, mailbox, monkeypatch):
    from schulpilot import paypal_client
    from schulpilot.order_withdrawal_models import OrderWithdrawal, PublicWithdrawal
    from schulpilot.payment_models import PaymentAttempt
    from sqlalchemy import func, select
    def forbidden(*args, **kwargs):
        raise AssertionError('A document GET must not call a payment provider')
    monkeypatch.setattr(paypal_client, 'client', forbidden)
    user = register(api, mailbox)
    identifier, _ = seed(user)
    with DB.begin() as db:
        db.get(BankOrder, identifier).payment_method = 'paypal'
    cookie_only(api)
    for _ in range(2):
        for path in (f'/api/orders/{identifier}/payment-checkout', f'/api/orders/{identifier}/withdrawal-form', '/api/legal/withdrawal'):
            assert api.get(path).status_code == 200
    with DB() as db:
        for model in (PaymentAttempt, OrderWithdrawal, PublicWithdrawal):
            assert db.scalar(select(func.count()).select_from(model)) == 0


def test_webhook_csrf_exception_is_exact_and_body_limit_remains(api):
    # No provider call: missing signature headers are rejected locally.
    headers = {'Origin':'https://untrusted.invalid', 'X-Schulpilot-Request':''}
    webhook = api.post('/api/payments/paypal/webhook', json={}, headers=headers)
    assert webhook.status_code in (400, 422)
    assert api.post('/api/payments/paypal/webhook/extra', json={}, headers=headers).status_code == 403
    assert api.post('/api/withdrawals/public', json={}, headers=headers).status_code == 403
    assert api.post('/api/payments/paypal/webhook', content=b'x'*65537, headers=headers).status_code == 413


def test_imprint_phone_and_optional_operator_facts_are_published_safely(api, monkeypatch):
    for field, value in {'operator_name':'Synthetic <script>name</script>', 'operator_address':'Synthetic address',
        'operator_support_email':'synthetic@example.org', 'operator_phone':'+49 (30) 00000',
        'operator_complaints_address':'Synthetic <extra>', 'operator_legal_info':'Synthetic register <value>'}.items():
        object.__setattr__(settings, field, value)
    response = api.get('/api/legal/imprint')
    assert response.status_code == 200 and '<script>' not in response.text
    assert 'Synthetic &lt;script&gt;name&lt;/script&gt;' in response.text
    assert 'Synthetic &lt;extra&gt;' in response.text
    assert 'Synthetic register &lt;value&gt;' in response.text
    assert api.get('/api/legal').json()['imprint_complete'] is True
    object.__setattr__(settings, 'operator_phone', '')
    assert api.get('/api/legal').json()['imprint_complete'] is False
    assert 'Noch nicht hinterlegt' in api.get('/api/legal/imprint').text
    assert SiteUpdate(operator_phone='+49 (30) 123-4').operator_phone == '+49 (30) 123-4'
    try:
        SiteUpdate(operator_phone='<script>')
    except ValidationError:
        pass
    else:
        raise AssertionError('Phone controls must reject markup')


def exported(client, fid):
    response = client.get(f'/api/families/{fid}/export')
    assert response.status_code == 200, response.text
    with zipfile.ZipFile(io.BytesIO(response.content)) as archive:
        return json.loads(archive.read('family.json'))


def test_family_owner_export_keeps_receipt_but_viewer_has_no_financial_declaration(api, mailbox, monkeypatch):
    from schulpilot import mail
    monkeypatch.setattr(mail, 'send_message', lambda *args: None)
    user = register(api, mailbox)
    fid = user['families'][0]['id']
    identifier, _ = seed(user)
    assert api.post(f'/api/orders/{identifier}/withdrawals',json=body()).status_code == 201
    own = exported(api, fid)
    assert len(own['orders']) == 1 and own['orders'][0]['withdrawals']
    assert 'Künstliche Testperson' in json.dumps(own, ensure_ascii=False)
    with TestClient(app, headers=HEADERS) as viewer:
        other = register(viewer, mailbox, 'viewer@example.org')
        with DB.begin() as db:
            db.add(Membership(user_id=other['id'], family_id=fid, permission='view'))
        view = exported(viewer, fid)
        assert view['orders'] == []
        assert 'Künstliche Testperson' not in json.dumps(view, ensure_ascii=False)
