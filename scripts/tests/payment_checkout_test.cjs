'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const { webcrypto } = require('node:crypto');
const source = fs.readFileSync(path.resolve(__dirname, '../../app/web/payment_checkout.js'), 'utf8');
const id = '1'.repeat(32), paymentId = '2'.repeat(32), providerId = 'SYNTHETICORDER123';
const defer = () => { let resolve, reject; const promise = new Promise((r, e) => { resolve = r; reject = e; }); return {promise, resolve, reject}; };
const flush = async () => { for(let i=0;i<25;i++) await Promise.resolve(); await new Promise(setImmediate); };
class Element {
  constructor(tag) { this.tagName = tag; this.children = []; this.events = {}; this.hidden = false; this.disabled = false; this.textContent = ''; this.style = {}; this.attributes = {}; }
  addEventListener(name, callback) { this.events[name] = callback; }
  setAttribute(name, value) { this.attributes[name] = value; }
  removeAttribute(name) { delete this.attributes[name]; }
  appendChild(child) { this.children.push(child); return child; }
  replaceChildren(...children) { this.children = children; }
  remove() { this.removed = true; }
  focus() { this.focused = true; }
  async click() { if (!this.disabled && !this.hidden && this.events.click) await this.events.click(); await flush(); }
}
function metadata(overrides = {}) {
  return {
    payment_id: null, provider_order_id: null, method: 'paypal', status: 'not_started',
    amount_cents: 1234, currency: 'EUR', environment: 'sandbox', client_id: 'synthetic-public-client-1234',
    config_revision: 1, config_matches: true, can_start: true, can_open: false, can_capture: false,
    can_reconcile: false, notice: 'Künstlicher Status', order: { id, amount_cents: 1234, currency: 'EUR', offer: { name: 'Künstlicher Tarif' } },
    ...overrides,
  };
}
function harness(options = {}) {
  const nodes = new Map(['offer','amount','method','status','notice','prepare','ready','payment-button','message','refresh','reconcile'].map(name => [name, new Element(name)]));
  const scripts = [], calls = [], events = [], hooks = {}, flow = defer();
  let reloads = 0;
  let current = metadata(options.initial || {});
  const approved = metadata({ ...current, payment_id: paymentId, provider_order_id: providerId,
    status: 'awaiting_approval', can_start: false, can_open: true, can_capture: true });
  const document = {
    documentElement: { dataset: { orderId: id } }, currentScript: { nonce: 'synthetic-nonce' },
    getElementById: name => nodes.get(name), createElement: tag => new Element(tag),
    head: { appendChild(script) { scripts.push(script); queueMicrotask(() => script.onload?.()); } },
  };
  const session = {
    hasReturned() { return options.returned === true; },
    resume() { events.push('resume'); return flow.promise; },
    cancel() { events.push('cancel'); }, destroy() { events.push('destroy'); },
    start(config, order) { events.push('start'); hooks.presentation = config; hooks.orderPromise = order; return flow.promise; },
    formatConfigForPaymentRequest(config) { hooks.config = config; return { apiVersion: 2, apiVersionMinor: 0, countryCode: 'DE', allowedPaymentMethods: [], merchantInfo: {} }; },
    async confirmOrder(data) { events.push('confirm'); hooks.confirmData = data; return { status: options.sca ? 'PAYER_ACTION_REQUIRED' : 'APPROVED' }; },
    async initiatePayerAction(data) { events.push('sca'); hooks.scaData = data; if (options.scaReject) throw Error('cancelled'); },
  };
  const sdk = {
    async findEligibleMethods() { return { isEligible: () => options.eligible !== false, getDetails: () => ({ config: { synthetic: true } }) }; },
    createPayPalOneTimePaymentSession(callbacks) { hooks.callbacks = callbacks; return session; },
    createGooglePayOneTimePaymentSession() { return session; },
  };
  const window = {
    paypal: { async createInstance(config) { hooks.instance = config; return sdk; } },
    addEventListener(name, callback) { hooks[name] = callback; },
    google: { payments: { api: { PaymentsClient: class {
      constructor(config) { hooks.googleOptions = config; }
      async isReadyToPay() { return { result: options.googleReady !== false }; }
      createButton(config) { const button = new Element('google-button'); button.addEventListener('click', config.onClick); return button; }
      loadPaymentData(data) {
        events.push('google-open'); hooks.googleData = data;
        return hooks.googleOptions.paymentDataCallbacks.onPaymentAuthorized({ paymentMethodData: { synthetic: true } }).then(result => {
          hooks.googleAuthorization = result; events.push('google-sheet-closed');
        });
      }
    } } } },
  };
  const context = vm.createContext({
    window, document, location: { pathname: options.path || '/api/orders/' + id + '/payment-checkout', search: '', reload() { reloads++; } },
    URLSearchParams, AbortController, setTimeout, clearTimeout, queueMicrotask, crypto: webcrypto,
    async fetch(url, request) {
      calls.push({url, method: request.method, body: request.body ? JSON.parse(request.body) : undefined, request});
      if (options.intercept) { const result = await options.intercept(url, request); if (result) return result; }
      if (request.method === 'POST' && url.endsWith('/paypal/create')) current = approved;
      if (request.method === 'POST' && url.endsWith('/paypal/capture')) {
        events.push('capture'); current = { ...approved, status: 'completed', can_open: false, can_capture: false };
      }
      if (request.method === 'POST' && url.endsWith('/paypal/reconcile')) current = { ...current, status: 'completed', can_open: false, can_start: false, can_capture: false, can_reconcile: false };
      return {ok: true, status: 200, async json() { return structuredClone(current); }};
    },
  });
  vm.runInContext(source, context);
  return { nodes, scripts, calls, events, hooks, flow, current: () => current, reloads: () => reloads, async ready() { await flush(); } };
}
test('opening and refreshing a disabled checkout remain GET-only without SDK scripts', async () => {
  const h = harness({initial: {can_start: false, client_id: null, environment: null}}); await h.ready();
  assert.equal(h.calls.length, 1); assert.equal(h.calls[0].method, 'GET'); assert.equal(h.scripts.length, 0);
  assert.equal(h.nodes.get('prepare').hidden, true);
  await h.nodes.get('refresh').click();
  assert.equal(h.calls.length, 2); assert.ok(h.calls.every(c => c.method === 'GET')); assert.equal(h.scripts.length, 0);
});
test('explicit preparation creates exactly one bound order then renders an official provider button', async () => {
  const h = harness(); await h.ready(); await h.nodes.get('prepare').click();
  assert.deepEqual(h.calls.filter(c => c.method === 'POST').map(c => c.body), [{ request_key: 'create-' + id }]);
  assert.equal(h.scripts.length, 1); assert.equal(h.scripts[0].src, 'https://www.sandbox.paypal.com/web-sdk/v6/core');
  assert.equal(h.scripts[0].nonce, 'synthetic-nonce'); assert.equal(h.hooks.instance.clientId, 'synthetic-public-client-1234');
  assert.deepEqual(Array.from(h.hooks.instance.components), ['paypal-payments']);
  assert.equal(h.nodes.get('payment-button').children[0].tagName, 'paypal-button');
  assert.ok(!h.events.includes('start')); assert.ok(!h.events.includes('capture'));
});
test('an existing approval is reused without another create POST or automatic capture', async () => {
  const h = harness({initial: {payment_id: paymentId, provider_order_id: providerId, status:'awaiting_approval', can_start:false, can_open:true, can_capture:true}}); await h.ready();
  assert.equal(h.scripts.length, 0); await h.nodes.get('prepare').click();
  assert.ok(h.calls.every(c => c.method === 'GET')); assert.equal(h.scripts.length, 1);
  const button = h.nodes.get('payment-button').children[0];
  await button.click(); assert.equal(h.events.filter(e => e === 'start').length, 1);
  assert.equal((await h.hooks.orderPromise).orderId, providerId);
  assert.ok(!h.events.includes('capture')); h.flow.resolve(); await flush();
});
test('only approval of the exact provider order captures once and confirms server completion', async () => {
  const h = harness(); await h.ready(); await h.nodes.get('prepare').click();
  await h.hooks.callbacks.onApprove({orderId: providerId}); assert.ok(!h.events.includes('capture'));
  await h.nodes.get('payment-button').children[0].click();
  await h.hooks.callbacks.onApprove({orderId:'WRONGORDER'}); assert.ok(!h.events.includes('capture'));
  await h.hooks.callbacks.onApprove({orderId:providerId}); await h.hooks.callbacks.onApprove({orderId:providerId});
  assert.equal(h.calls.filter(c => c.url.endsWith('/paypal/capture')).length, 1);
  assert.match(h.nodes.get('status').textContent, /Zahlung bestätigt/);
  assert.equal(h.nodes.get('payment-button').children.length, 0); h.flow.resolve(); await flush();
});
test('provider cancellation makes no capture call and leaves an honest saved-status notice', async () => {
  const h = harness(); await h.ready(); await h.nodes.get('prepare').click(); await h.nodes.get('payment-button').children[0].click();
  h.hooks.callbacks.onCancel(); h.flow.resolve(); await flush();
  assert.ok(!h.calls.some(c => c.url.endsWith('/paypal/capture')));
  assert.match(h.nodes.get('message').textContent, /nicht bestätigt/);
});
test('capture failure never reports success, retries itself or leaves another pay button', async () => {
  const h = harness({intercept: async url => url.endsWith('/paypal/capture') ? {ok:false,status:503} : null});
  await h.ready(); await h.nodes.get('prepare').click(); await h.nodes.get('payment-button').children[0].click();
  await h.hooks.callbacks.onApprove({orderId:providerId}); h.flow.resolve(); await flush();
  assert.equal(h.calls.filter(c => c.url.endsWith('/paypal/capture')).length, 1);
  assert.match(h.nodes.get('message').textContent, /unklar/); assert.equal(h.nodes.get('payment-button').children.length, 0);
  assert.doesNotMatch(h.nodes.get('status').textContent, /^Zahlung bestätigt$/);
});
test('a changed configuration cannot load SDKs from an old approval snapshot', async () => {
  const h = harness({initial: {payment_id:paymentId,provider_order_id:providerId,status:'awaiting_approval',can_start:false,can_open:true,can_capture:true,config_matches:false}});
  await h.ready(); assert.equal(h.nodes.get('prepare').hidden, true);
  assert.equal(h.scripts.length, 0); assert.ok(h.calls.every(c=>c.method==='GET'));
});
test('revoked authority clears private order text and prevents later capture callbacks', async () => {
  let revoke = false;
  const h = harness({intercept: async () => revoke ? {ok:false,status:401} : null});
  await h.ready(); await h.nodes.get('prepare').click(); const callbacks = h.hooks.callbacks;
  revoke = true; await h.nodes.get('refresh').click();
  assert.equal(h.nodes.get('amount').textContent, ''); assert.equal(h.nodes.get('payment-button').children.length, 0);
  await callbacks.onApprove({orderId:providerId}); assert.ok(!h.calls.some(c=>c.url.endsWith('/paypal/capture')));
});
test('an explicit reconcile is separate from GET status and has no create or capture', async () => {
  const h = harness({initial:{payment_id:paymentId,provider_order_id:providerId,status:'uncertain',can_start:false,can_reconcile:true}});
  await h.ready(); assert.equal(h.scripts.length,0); await h.nodes.get('reconcile').click();
  const writes=h.calls.filter(c=>c.method==='POST'); assert.equal(writes.length,1); assert.ok(writes[0].url.endsWith('/paypal/reconcile'));
  assert.match(writes[0].body.request_key,/^reconcile-/); assert.equal(h.scripts.length,0);
});
test('Google Pay requires readiness and captures only after its own authorization', async () => {
  const h = harness({initial:{method:'google_pay'}}); await h.ready(); await h.nodes.get('prepare').click();
  assert.equal(h.scripts.length,2); assert.equal(h.scripts[1].src,'https://pay.google.com/gp/p/js/pay.js');
  assert.equal(h.nodes.get('payment-button').children[0].tagName,'google-button');
  assert.ok(!h.events.includes('google-open'));
  await h.nodes.get('payment-button').children[0].click(); await flush();
  assert.equal(h.hooks.googleOptions.environment,'TEST'); assert.equal(h.hooks.googleData.transactionInfo.totalPrice,'12.34');
  assert.ok(h.events.indexOf('confirm') < h.events.indexOf('capture'));
  assert.equal(h.hooks.googleAuthorization.transactionState,'SUCCESS');
  assert.match(h.nodes.get('status').textContent,/Zahlung bestätigt/);
});
test('Google SCA closes its sheet before 3DS and captures only after authentication', async () => {
  const h=harness({initial:{method:'google_pay'},sca:true}); await h.ready(); await h.nodes.get('prepare').click();
  await h.nodes.get('payment-button').children[0].click(); await flush();
  assert.ok(h.events.indexOf('google-sheet-closed') < h.events.indexOf('sca'));
  assert.ok(h.events.indexOf('sca') < h.events.indexOf('capture'));
  assert.equal(h.hooks.scaData.orderId,providerId);
});
test('failed 3DS never captures or claims payment completed', async () => {
  const h=harness({initial:{method:'google_pay'},sca:true,scaReject:true}); await h.ready(); await h.nodes.get('prepare').click();
  await h.nodes.get('payment-button').children[0].click(); await flush();
  assert.ok(!h.events.includes('capture')); assert.doesNotMatch(h.nodes.get('status').textContent,/^Zahlung bestätigt$/);
});
test('unavailable Google Pay exposes no unusable provider button and makes no capture', async () => {
  const h=harness({initial:{method:'google_pay'},googleReady:false}); await h.ready(); await h.nodes.get('prepare').click();
  assert.equal(h.nodes.get('payment-button').children.length,0); assert.ok(!h.events.includes('capture'));
  assert.match(h.nodes.get('message').textContent,/nicht vorbereitet/);
});
test('page exit destroys its own SDK session and old callbacks cannot capture', async () => {
  const h=harness(); await h.ready(); await h.nodes.get('prepare').click(); const callbacks=h.hooks.callbacks;
  h.hooks.pagehide(); await callbacks.onApprove({orderId:providerId});
  assert.ok(h.events.includes('destroy')); assert.ok(!h.events.includes('capture'));
});

test('a returned SDK session resumes only after a fresh explicit provider-button click', async () => {
  const h=harness({returned:true,initial:{payment_id:paymentId,provider_order_id:providerId,status:'awaiting_approval',can_start:false,can_open:true,can_capture:true}});
  await h.ready(); assert.equal(h.scripts.length,0); assert.ok(!h.events.includes('resume'));
  await h.nodes.get('prepare').click(); assert.ok(!h.events.includes('resume')); assert.ok(!h.events.includes('capture'));
  await h.nodes.get('payment-button').children[0].click();
  assert.ok(h.events.includes('resume')); assert.ok(!h.events.includes('start')); assert.ok(!h.events.includes('capture'));
  await h.hooks.callbacks.onApprove({orderId:providerId}); h.flow.resolve(); await flush();
  assert.equal(h.calls.filter(c=>c.url.endsWith('/paypal/capture')).length,1);
});


test('leaving a checkout clears private data and BFCache requires a fresh authenticated document', async () => {
  const h = harness(); await h.ready(); await h.nodes.get('prepare').click();
  const callbacks = h.hooks.callbacks, callsBeforeExit = h.calls.length;
  assert.match(h.nodes.get('offer').textContent, /Künstlicher Tarif/);
  assert.notEqual(h.nodes.get('amount').textContent, '');
  h.hooks.pagehide();
  for (const name of ['amount', 'method', 'notice', 'message']) assert.equal(h.nodes.get(name).textContent, '');
  assert.doesNotMatch(h.nodes.get('offer').textContent, /Künstlicher Tarif/);
  assert.equal(h.nodes.get('payment-button').children.length, 0);
  assert.equal(h.nodes.get('refresh').disabled, true);
  assert.equal(h.nodes.get('prepare').hidden, true);
  await callbacks.onApprove({orderId: providerId});
  h.hooks.pageshow({persisted: false}); assert.equal(h.reloads(), 0);
  h.hooks.pageshow({persisted: true}); assert.equal(h.reloads(), 1);
  assert.equal(h.calls.length, callsBeforeExit);
  assert.ok(!h.calls.some(c => c.url.endsWith('/paypal/capture')));
});

test('page exit aborts a pending status read and a late response cannot restore private order text', async () => {
  const pending = defer();
  const h = harness({intercept: () => pending.promise}); await flush();
  assert.equal(h.calls.length, 1); const signal = h.calls[0].request.signal;
  h.hooks.pagehide(); assert.equal(signal.aborted, true);
  pending.resolve({ok: true, status: 200, async json() { return metadata(); }}); await h.ready();
  assert.equal(h.nodes.get('amount').textContent, '');
  assert.doesNotMatch(h.nodes.get('offer').textContent, /Künstlicher Tarif/);
  assert.equal(h.nodes.get('prepare').hidden, true);
  assert.equal(h.nodes.get('refresh').disabled, true);
  h.hooks.pageshow({persisted: true}); assert.equal(h.reloads(), 1);
  assert.equal(h.calls.length, 1); assert.equal(h.scripts.length, 0);
});

test('page exit while JSON is pending cannot restore a previously read private snapshot', async () => {
  const body = defer();
  const h = harness({intercept: async () => ({ok: true, status: 200, json() { return body.promise; }})}); await flush();
  h.hooks.pagehide(); body.resolve(metadata()); await h.ready();
  assert.equal(h.nodes.get('amount').textContent, '');
  assert.doesNotMatch(h.nodes.get('offer').textContent, /Künstlicher Tarif/);
  assert.equal(h.nodes.get('prepare').hidden, true);
  assert.equal(h.calls.length, 1); assert.equal(h.scripts.length, 0);
});
