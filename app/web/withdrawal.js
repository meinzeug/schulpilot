/* Local contract declaration only. No payment provider or learning service. */
'use strict';
(() => {
  const $ = id => document.getElementById(id);
  const mode = document.documentElement.dataset.mode;
  const orderId = document.documentElement.dataset.orderId;
  const owner = mode === 'owner' && /^[a-f0-9]{32}$/.test(orderId);
  const publicForm = mode === 'public' && orderId === '';
  let receiptText = '', busy = false, submitted = false, closed = false;
  const pendingRequests = new Set();
  const storageKey = 'schulpilot-withdrawal-v1-' + (owner ? orderId : 'public');
  let requestKey;
  try {
    requestKey = sessionStorage.getItem(storageKey);
    if (!/^[A-Za-z0-9_-]{16,60}$/.test(requestKey || '')) {
      requestKey = crypto.randomUUID();
      sessionStorage.setItem(storageKey, requestKey);
    }
  } catch (_) { requestKey = crypto.randomUUID(); }
  async function api(path, options = {}) {
    const controller = new AbortController();
    pendingRequests.add(controller);
    const timer = setTimeout(() => controller.abort(), 20000);
    try {
    const response = await fetch('/api' + path, {
      signal: controller.signal,
      credentials: 'same-origin', cache: 'no-store', redirect: 'error',
      ...options,
      headers: {'X-Schulpilot-Request': '1', 'Content-Type': 'application/json', ...(options.headers || {})},
    });
    let value;
    try { value = await response.json(); } catch (_) { throw new Error('Die Antwort konnte nicht sicher gelesen werden.'); }
    if (!response.ok) throw new Error(typeof value.detail === 'string' ? value.detail : 'Die Eingaben konnten nicht übernommen werden.');
    return value;
    } finally { clearTimeout(timer); pendingRequests.delete(controller); }
  }
  function render(value) {
    if (closed) return;
    if (!value || typeof value.receipt_text !== 'string' || !value.received_at_iso || value.refund_executed !== false) {
      throw new Error('Der Eingangsbeleg ist unvollständig. Bitte den gespeicherten Stand prüfen.');
    }
    receiptText = value.receipt_text;
    submitted = true;
    try { sessionStorage.removeItem(storageKey); } catch (_) { /* No personal data is cached. */ }
    $('result').hidden = false;
    $('withdrawal-form').hidden = true;
    $('receipt').textContent = receiptText;
    $('result-notice').textContent = value.notice || 'Deine Erklärung ist eingegangen. Eine Rückzahlung ist damit noch nicht bestätigt.';
    $('mail-status').textContent = value.mail_status === 'accepted'
      ? 'Die Bestätigung wurde an den E-Mail-Dienst übergeben. Das beweist noch keine Zustellung; speichere deinen Beleg hier.'
      : 'Eine E-Mail-Zustellung ist noch nicht bestätigt. Dein Eingangsbeleg bleibt hier verfügbar; speichere ihn jetzt.';
    $('message').textContent = '';
    $('result-heading').tabIndex = -1;
    $('result-heading').focus();
  }
  if (!owner && !publicForm) {
    $('withdrawal-form').hidden = true;
    $('message').textContent = 'Dieses Formular konnte nicht sicher zugeordnet werden. Öffne „Vertrag widerrufen“ erneut.';
    return;
  }
  if (owner) {
    $('contact-email').readOnly = true;
    $('order-reference').readOnly = true;
    $('scope').textContent = 'Diese Erklärung gehört zu deiner eigenen gespeicherten Bestellung. Die Bestätigung geht an die verifizierte E-Mail deines Elternkontos.';
    api('/orders/' + orderId + '/withdrawal').then(value => {
      if (value.withdrawal) render(value.withdrawal);
    }).catch(error => { if (!closed) $('message').textContent = error.message; });
  } else {
    $('scope').textContent = 'Ohne Anmeldung prüfen wir die Zuordnung deiner Erklärung. Allein durch dieses Formular werden weder eine fremde Bestellung geändert noch eine Zahlung oder Erstattung ausgeführt.';
  }
  $('withdrawal-form').addEventListener('submit', async event => {
    event.preventDefault();
    if (busy || submitted || closed || !$('withdrawal-form').reportValidity()) return;
    const data = {
      request_key: requestKey, buyer_name: $('buyer-name').value.trim(),
      contact_email: $('contact-email').value.trim(), confirm: $('confirm').checked,
    };
    if (!owner) data.order_reference = $('order-reference').value.trim();
    busy = true;
    for (const id of ['buyer-name', 'contact-email', 'order-reference', 'confirm', 'submit']) $(id).disabled = true;
    $('message').textContent = 'Deine Erklärung wird übermittelt …';
    try {
      render(await api(owner ? '/orders/' + orderId + '/withdrawals' : '/withdrawals/public', {method:'POST', body:JSON.stringify(data)}));
    } catch (error) {
      if (!closed) $('message').textContent = error.message + ' Der Eingang ist noch nicht sicher bestätigt. Ein bewusster erneuter Versuch verwendet denselben Auftragsschlüssel.';
    } finally {
      busy = false;
      if (!closed && !submitted) {
        for (const id of ['buyer-name', 'contact-email', 'order-reference', 'confirm', 'submit']) $(id).disabled = false;
      }
    }
  });
  $('download').addEventListener('click', () => {
    if (!receiptText || closed) return;
    const url = URL.createObjectURL(new Blob([receiptText], {type:'text/plain;charset=utf-8'}));
    const link = document.createElement('a');
    link.href = url; link.download = 'schulpilot-widerruf-eingangsbeleg.txt';
    document.body.append(link); link.click(); link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  });
  window.addEventListener('pageshow', event => {
    if (!event.persisted) return;
    if (owner) { location.reload(); return; }
    // Public receipts have no read token; restore only this tab's memory.
    closed = false; busy = false;
    if (submitted) receiptText = $('receipt').textContent;
    else for (const id of ['buyer-name', 'contact-email', 'order-reference', 'confirm', 'submit']) $(id).disabled = false;
  });
  window.addEventListener('pagehide', () => {
    closed = true; receiptText = '';
    if (owner) {
      for (const id of ['buyer-name', 'contact-email', 'order-reference']) $(id).value = '';
      $('receipt').textContent = ''; $('result-notice').textContent = ''; $('mail-status').textContent = '';
    }
    for (const controller of pendingRequests) controller.abort();
    pendingRequests.clear();
  });
})();
