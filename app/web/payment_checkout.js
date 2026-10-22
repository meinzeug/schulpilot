/* Same-origin authenticated checkout document. No application secrets or logs. */
(() => {
  'use strict';
  const declaredId = document.documentElement.dataset.orderId || '';
  const match = location.pathname.match(/^\/(?:pay\/([a-f0-9]{32})|api\/orders\/([a-f0-9]{32})\/payment-checkout)$/);
  const id = /^[a-f0-9]{32}$/.test(declaredId) ? declaredId : match?.[1] || match?.[2] || '';
  const scriptNonce = document.currentScript?.nonce || '';
  const validId = /^[a-f0-9]{32}$/.test(id);
  const el = (name) => document.getElementById(name);
  const labels = {
    not_started: 'Noch keine Zahlung gestartet', awaiting_approval: 'Freigabe im Zahlungsfenster ausstehend',
    capture_pending: 'Zahlung wird geprüft', completed: 'Zahlung bestätigt', denied: 'Zahlung nicht bestätigt',
    cancelled: 'Zahlung abgebrochen', uncertain: 'Zahlungsausgang noch unklar',
    refunded: 'Zahlung erstattet', partially_refunded: 'Zahlung teilweise erstattet', reversed: 'Zahlung zurückgebucht',
  };
  let payment = null, session = null, google = null, googleConfig = null;
  let active = true, busy = false, generation = 0, approved = null, payerAction = false;
  let flowTimeout = null;
  const requests = new Set();
  let sdkEnvironment = null, sdkPromise = null, googlePromise = null;
  const theme = new URLSearchParams(location.search).get('theme');
  if (theme === 'light' || theme === 'dark') document.documentElement.dataset.theme = theme;
  function text(name, value) { el(name).textContent = value; }
  function message(value, focus = false) {
    text('message', value);
    if (focus) { el('message').setAttribute('tabindex', '-1'); el('message').focus(); }
  }
  function controls() {
    el('refresh').disabled = busy || !active;
    el('prepare').disabled = busy || !active;
    el('reconcile').disabled = busy || !active;
    if (busy) el('payment-button').setAttribute('inert', '');
    else el('payment-button').removeAttribute('inert');
  }
  function destroySession() {
    generation++;
    if (flowTimeout) { clearTimeout(flowTimeout); flowTimeout = null; }
    try { if (session && session.cancel) session.cancel(); } catch (_) {}
    try { if (session && session.destroy) session.destroy(); } catch (_) {}
    session = google = googleConfig = approved = null;
    el('payment-button').replaceChildren();
    el('ready').hidden = true;
  }
  function clearPrivate() {
    payment = null;
    text('offer', 'Dieser Zahlungszugang ist nicht mehr verfügbar.');
    for (const name of ['amount', 'method', 'notice', 'message']) text(name, '');
    text('status', 'Bitte im eigenen Familienkonto erneut anmelden.');
    el('prepare').hidden = el('reconcile').hidden = true;
  }
  async function api(path, method = 'GET', body) {
    if (!active) throw new Error('access');
    const controller = new AbortController();
    requests.add(controller);
    const timeout = setTimeout(() => controller.abort(), 25000);
    try {
      const response = await fetch('/api' + path, {
        method, credentials: 'same-origin', redirect: 'error', cache: 'no-store',
        headers: { 'X-Schulpilot-Request': '1', ...(body ? { 'Content-Type': 'application/json' } : {}) },
        ...(body ? { body: JSON.stringify(body) } : {}), signal: controller.signal,
      });
      if (!active) throw new Error('access');
      if (response.status === 401 || response.status === 403) {
        active = false;
        destroySession();
        clearPrivate();
        throw new Error('access');
      }
      if (!response.ok) throw new Error('unconfirmed');
      const value = await response.json();
      if (!active) throw new Error('access');
      return value;
    } finally { clearTimeout(timeout); requests.delete(controller); }
  }
  function render(value) {
    if (!value || value.order?.id !== id || !Number.isSafeInteger(value.amount_cents) ||
        value.amount_cents <= 0 || value.amount_cents > 100000000 || value.currency !== 'EUR' || !['paypal', 'google_pay'].includes(value.method)) {
      throw new Error('payment-contract');
    }
    payment = value;
    text('offer', String(value.order.offer?.name || 'Gespeicherter Familientarif'));
    text('amount', (value.amount_cents / 100).toLocaleString('de-DE', { style: 'currency', currency: 'EUR' }));
    text('method', value.method === 'google_pay' ? 'Zahlungsart: Google Pay über PayPal' : 'Zahlungsart: PayPal');
    text('status', labels[value.status] || 'Zahlungsstatus nicht sicher gemeldet');
    text('notice', typeof value.notice === 'string' ? value.notice : '');
    const open = value.can_open === true && value.config_matches === true;
    el('prepare').hidden = value.can_start !== true && !open;
    text('prepare', open ? 'Zahlungsfenster vorbereiten' : 'Zahlung vorbereiten');
    el('reconcile').hidden = value.can_reconcile !== true;
  }
  async function refresh() {
    if (!validId || busy || !active) return;
    busy = true; controls();
    destroySession();
    try { render(await api('/orders/' + id + '/payment')); }
    catch (_) { message('Der gespeicherte Status konnte nicht bestätigt werden. Es wurde keine neue Zahlung ausgelöst.', true); }
    finally { busy = false; controls(); }
  }
  function loadScript(url) {
    return new Promise((resolve, reject) => {
      const script = document.createElement('script');
      let settled = false;
      const timeout = setTimeout(() => finish(false), 20000);
      function finish(ok) {
        if (settled) return;
        settled = true; clearTimeout(timeout);
        script.onload = script.onerror = null;
        if (ok) resolve(); else { script.remove(); reject(new Error('sdk-load')); }
      }
      script.src = url; script.async = true;
      if (scriptNonce) script.nonce = scriptNonce;
      script.onload = () => finish(true); script.onerror = () => finish(false);
      document.head.appendChild(script);
    });
  }
  function validConfig(value) {
    return value?.can_open === true && value.can_capture === true && value.config_matches === true && value.status === 'awaiting_approval' &&
      /^[A-Za-z0-9]{6,40}$/.test(value.provider_order_id || '') &&
      /^[A-Za-z0-9_-]{16,300}$/.test(value.client_id || '') &&
      /^[A-Za-z0-9_-]{6,100}$/.test(value.payment_id || '') &&
      ['sandbox', 'live'].includes(value.environment);
  }
  async function capture(stamp, snapshot) {
    if (!active || !busy || stamp !== generation || snapshot !== payment || snapshot.can_capture !== true) return false;
    if (approved) return approved;
    el('payment-button').replaceChildren();
    el('ready').hidden = true;
    approved = (async () => {
      try {
        const value = await api('/orders/' + id + '/paypal/capture', 'POST', {
          payment_id: snapshot.payment_id, request_key: 'capture-' + snapshot.payment_id,
        });
        if (!active || stamp !== generation) return false;
        render(value);
        if (value.status === 'completed') {
          message('Zahlung bestätigt. Den Laufzeitbeginn findest du in deiner gespeicherten Bestellung.', true);
          return true;
        }
        message('Die Zahlung ist noch nicht bestätigt. Prüfe den gespeicherten Status, bevor du etwas erneut auslöst.', true);
      } catch (_) {
        if (active && stamp === generation) message('Der Zahlungsausgang ist unklar. Bitte den gespeicherten Status lesen; nicht ungeprüft erneut bezahlen.', true);
      }
      return false;
    })();
    return approved;
  }
  function googleError() {
    return { transactionState: 'ERROR', error: { intent: 'PAYMENT_AUTHORIZATION', reason: 'PAYMENT_DATA_INVALID', message: 'Zahlung nicht bestätigt. Bitte den gespeicherten Status in Schulpilot prüfen.' } };
  }
  async function prepare() {
    if (busy || !active || !payment || (payment.can_start !== true && payment.can_open !== true)) return;
    busy = true; controls(); destroySession();
    try {
      render(await api('/orders/' + id + '/payment'));
      if (payment.can_start === true) {
        render(await api('/orders/' + id + '/paypal/create', 'POST', { request_key: 'create-' + id }));
      }
      if (!active || !validConfig(payment)) throw new Error('configuration-changed');
      const snapshot = payment, stamp = generation;
      if (sdkEnvironment && sdkEnvironment !== snapshot.environment) throw new Error('environment-changed');
      sdkEnvironment = snapshot.environment;
      if (!sdkPromise) {
        const host = snapshot.environment === 'live' ? 'www.paypal.com' : 'www.sandbox.paypal.com';
        sdkPromise = loadScript('https://' + host + '/web-sdk/v6/core').catch((error) => { sdkPromise = null; throw error; });
      }
      await sdkPromise;
      if (!active || stamp !== generation) return;
      const sdk = await window.paypal.createInstance({
        clientId: snapshot.client_id, pageType: 'checkout',
        components: [snapshot.method === 'google_pay' ? 'googlepay-payments' : 'paypal-payments'],
      });
      const eligible = await sdk.findEligibleMethods({ currencyCode: 'EUR', amount: (snapshot.amount_cents / 100).toFixed(2) });
      if (!active || stamp !== generation) return;
      if (!eligible.isEligible(snapshot.method === 'google_pay' ? 'googlepay' : 'paypal')) throw new Error('not-eligible');
      if (snapshot.method === 'google_pay') {
        if (!googlePromise) googlePromise = loadScript('https://pay.google.com/gp/p/js/pay.js').catch((error) => { googlePromise = null; throw error; });
        await googlePromise;
        if (!active || stamp !== generation) return;
        session = sdk.createGooglePayOneTimePaymentSession();
        googleConfig = session.formatConfigForPaymentRequest(eligible.getDetails('googlepay').config);
        google = new window.google.payments.api.PaymentsClient({
          environment: snapshot.environment === 'live' ? 'PRODUCTION' : 'TEST',
          paymentDataCallbacks: {
            onPaymentAuthorized: async (data) => {
              if (!active || stamp !== generation || !busy) return googleError();
              try {
                const result = await session.confirmOrder({ orderId: snapshot.provider_order_id, paymentMethodData: data.paymentMethodData });
                if (!active || stamp !== generation) return googleError();
                if (result.status === 'PAYER_ACTION_REQUIRED') {
                  payerAction = true;
                  return { transactionState: 'SUCCESS' }; // Close Google sheet before 3DS; not a server payment confirmation.
                }
                if (result.status !== 'APPROVED') return googleError();
                return await capture(stamp, snapshot) ? { transactionState: 'SUCCESS' } : googleError();
              } catch (_) { return googleError(); }
            },
          },
        });
        const ready = await google.isReadyToPay({
          apiVersion: googleConfig.apiVersion, apiVersionMinor: googleConfig.apiVersionMinor,
          allowedPaymentMethods: googleConfig.allowedPaymentMethods,
        });
        if (!active || stamp !== generation) return;
        if (!ready.result) throw new Error('not-ready');
        el('payment-button').appendChild(google.createButton({
          onClick: () => open(stamp, snapshot), buttonType: 'pay', buttonColor: 'black', buttonSizeMode: 'fill', buttonLocale: 'de',
        }));
      } else {
        session = sdk.createPayPalOneTimePaymentSession({
          onApprove: async (data) => {
            if (!active || !busy || stamp !== generation || data.orderId !== snapshot.provider_order_id) return;
            await capture(stamp, snapshot);
          },
          onCancel: () => { if (active && stamp === generation) message('Zahlungsfenster geschlossen. Prüfe den gespeicherten Status; eine Zahlung wurde hier nicht bestätigt.'); },
          onError: () => { if (active && stamp === generation) message('Das Zahlungsfenster konnte nicht abgeschlossen werden. Bitte den gespeicherten Status prüfen.', true); },
        });
        const button = document.createElement('paypal-button');
        button.addEventListener('click', () => open(stamp, snapshot));
        el('payment-button').appendChild(button);
      }
      if (!active || stamp !== generation) return;
      el('ready').hidden = false;
      el('prepare').hidden = true;
      message('Zahlungsfenster ist bereit. Noch keine Zahlung bestätigt.');
    } catch (_) {
      destroySession();
      if (active) message('Die Zahlungsart konnte nicht vorbereitet werden. Deine Bestellung bleibt gespeichert. Lies zuerst den Status oder versuche die Vorbereitung bewusst erneut.', true);
    } finally { busy = false; controls(); }
  }
  function open(stamp, snapshot) {
    if (!active || busy || stamp !== generation || snapshot !== payment || !session) return;
    busy = true; payerAction = false; controls();
    message('Zahlungsfenster geöffnet. Der Zahlungsstatus wird anschließend gesondert bestätigt.');
    flowTimeout = setTimeout(() => {
      if (active && stamp === generation) {
        destroySession(); busy = false; controls();
        message('Das Zahlungsfenster ist abgelaufen. Bitte den gespeicherten Status lesen; nicht ungeprüft erneut bezahlen.', true);
      }
    }, 600000);
    let flow;
    try {
      // No await before the provider popup or native sheet.
      flow = google ? google.loadPaymentData({
        ...googleConfig, callbackIntents: ['PAYMENT_AUTHORIZATION'],
        transactionInfo: { countryCode: googleConfig.countryCode, currencyCode: 'EUR', totalPriceStatus: 'FINAL', totalPrice: (snapshot.amount_cents / 100).toFixed(2) },
      }) : typeof session.hasReturned === 'function' && session.hasReturned() &&
          typeof session.resume === 'function'
        ? session.resume()
        : session.start({ presentationMode: 'auto', fullPageOverlay: { enabled: true } }, Promise.resolve({ orderId: snapshot.provider_order_id }));
    } catch (_) { flow = Promise.reject(new Error('popup')); }
    Promise.resolve(flow).then(async () => {
      if (!active || stamp !== generation) return;
      if (google && payerAction) {
        await session.initiatePayerAction({ orderId: snapshot.provider_order_id });
        if (active && stamp === generation) await capture(stamp, snapshot);
      }
    }).catch(() => {
      if (active && stamp === generation) message('Zahlungsfenster beendet oder nicht verfügbar. Prüfe den gespeicherten Status.', true);
    }).finally(() => {
      if (flowTimeout) { clearTimeout(flowTimeout); flowTimeout = null; }
      if (active && stamp === generation) { busy = false; controls(); }
    });
  }
  async function reconcile() {
    if (!active || busy || payment?.can_reconcile !== true) return;
    busy = true; controls(); destroySession();
    try {
      render(await api('/orders/' + id + '/paypal/reconcile', 'POST', { request_key: 'reconcile-' + crypto.randomUUID() }));
      message('Der Anbieterabgleich wurde gelesen. Maßgeblich ist der jetzt gespeicherte Status.', true);
    } catch (_) { message('Der Anbieterabgleich konnte nicht bestätigt werden. Es wurde keine neue Zahlung gestartet.', true); }
    finally { busy = false; controls(); }
  }
  el('prepare').addEventListener('click', prepare);
  el('refresh').addEventListener('click', refresh);
  el('reconcile').addEventListener('click', reconcile);
  window.addEventListener('pagehide', () => {
    active = false;
    for (const request of requests) request.abort();
    destroySession(); clearPrivate(); busy = false; controls();
  });
  window.addEventListener('pageshow', (event) => { if (event.persisted) location.reload(); });
  if (validId) refresh();
  else { active = false; text('offer', 'Dieser Zahlungslink ist ungültig.'); controls(); }
})();
