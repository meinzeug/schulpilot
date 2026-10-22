'use strict';
(() => {
  const $ = id => document.getElementById(id);
  let generation = 0, viewEpoch = 0, next = null, closed = false;
  const pendingRequests = new Set();
  const statusNames = {
    received_unverified:'Zuordnung noch prüfen', received_verified:'Berechtigt eingegangen',
    linked_verified:'Geprüft zugeordnet', review_required:'Frist oder Einordnung prüfen',
  };
  async function api(path, options = {}) {
    const controller = new AbortController(); pendingRequests.add(controller);
    const timer = setTimeout(()=>controller.abort(),20000);
    try {
    const response = await fetch('/api' + path, {signal:controller.signal,
      credentials:'same-origin', cache:'no-store', redirect:'error', ...options,
      headers:{'X-Schulpilot-Request':'1','Content-Type':'application/json'},
    });
    const value = await response.json();
    if (!response.ok) throw new Error(typeof value.detail === 'string' ? value.detail : 'Dieser Vorgang konnte nicht übernommen werden.');
    return value;
    } finally {clearTimeout(timer);pendingRequests.delete(controller);}
  }
  function node(tag, text, cls) {
    const element = document.createElement(tag);
    if (text) element.textContent = text;
    if (cls) element.className = cls;
    return element;
  }
  function card(item, cardGeneration) {
    const value = item.declaration || {};
    const details = node('details', '', 'declaration-card');
    details.append(node('summary', (value.order_reference || 'Ohne Referenz') + ' · ' + (statusNames[item.status] || 'Status prüfen')));
    const list = node('dl');
    for (const [title, text] of [
      ['Name',value.buyer_name],['Kontakt',value.contact_email],['Eingegangen',item.received_at_iso],
      ['Herkunft',item.source === 'public' ? 'Öffentliches Formular' : 'Verifiziertes Elternkonto'],
      ['Mailübergabe',item.mail_status === 'accepted' ? 'Vom Maildienst angenommen; Zustellung unbestätigt' : 'Nicht bestätigt'],
    ]) { list.append(node('dt',title),node('dd',text || 'Nicht gemeldet')); }
    details.append(list, node('pre',item.receipt_text || ''),node('p',item.notice || 'Keine automatische Rückzahlung.'));
    if (item.source === 'public' && item.status === 'received_unverified' && /^[a-f0-9]{32}$/.test(item.id)) {
      const form = node('form'), label = node('label','Geprüfte Bestellreferenz'), input = node('input');
      input.type='text'; input.maxLength=80; input.required=true; input.value=value.order_reference || '';
      label.append(input);
      const checkedLabel = node('label','','confirm'), checkbox = node('input');
      checkbox.type='checkbox'; checkbox.required=true;
      checkedLabel.append(checkbox,node('span','Ich habe die Identität des Erklärenden und dessen Bezug zu dieser konkreten Bestellung eigenständig geprüft.'));
      const submit = node('button','Geprüfte Zuordnung speichern'); submit.type='submit';
      const result = node('p'); result.setAttribute('role','status');
      form.append(label,checkedLabel,submit,result);
      let sending=false;
      form.addEventListener('submit', async event => {
        event.preventDefault();
        if (sending || closed || cardGeneration!==viewEpoch || !details.isConnected || !form.reportValidity()) return;
        sending=true; submit.disabled=true; input.disabled=true; checkbox.disabled=true;
        try {
          const response = await api('/admin/withdrawals/' + item.id + '/link', {
            method:'POST',body:JSON.stringify({order_reference:input.value.trim(),identity_verified:checkbox.checked}),
          });
          if (!closed && cardGeneration===viewEpoch && details.isConnected) { result.textContent=response.notice || 'Geprüfte Zuordnung gespeichert. Keine Rückzahlung ausgeführt.'; form.replaceChildren(result); }
        } catch (error) { if (!closed && cardGeneration===viewEpoch && details.isConnected) result.textContent=error.message+' Bitte den aktuellen Stand prüfen.'; }
        finally { sending=false; if (!closed && cardGeneration===viewEpoch && details.isConnected) {submit.disabled=false; input.disabled=false; checkbox.disabled=false;} }
      });
      details.append(form);
    }
    return details;
  }
  async function load(append=false) {
    if (closed) return;
    const own=++generation;
    if (!append) viewEpoch++;
    const epoch=viewEpoch;
    const filter=$('status-filter').value;
    const query=new URLSearchParams({limit:'25'});
    if (Object.hasOwn(statusNames,filter)) query.set('status',filter);
    if (append && next && /^[0-9]{1,12}:[a-f0-9]{32}$/.test(next)) query.set('before',next);
    $('refresh').disabled=true; $('next').disabled=true; $('message').textContent='Eingänge werden gelesen …';
    try {
      const result=await api('/admin/withdrawals?'+query.toString());
      if (closed || own!==generation) return;
      if (!Array.isArray(result.items)) throw new Error('Der gespeicherte Eingang ist unvollständig.');
      if (!append) $('declarations').replaceChildren();
      for (const item of result.items) $('declarations').append(card(item, epoch));
      next=typeof result.next_before === 'string' ? result.next_before : null;
      $('next').hidden=!next;
      $('message').textContent=result.items.length ? 'Gespeicherte Eingänge geladen. Details zum Prüfen öffnen.' : 'Keine weiteren passenden Eingänge vorhanden.';
    } catch (error) {
      if (!closed && own===generation) { $('message').textContent=error.message; if (!append) $('declarations').replaceChildren(); }
    } finally {
      if (own===generation) { if (!closed) { $('refresh').disabled=false; $('next').disabled=false; } }
    }
  }
  $('refresh').addEventListener('click',()=>load());
  $('next').addEventListener('click',()=>load(true));
  $('status-filter').addEventListener('change',()=>load());
  window.addEventListener('pageshow', event=>{if(event.persisted) location.reload();});
  window.addEventListener('pagehide',()=>{closed=true;generation++;next=null;for(const controller of pendingRequests) controller.abort();pendingRequests.clear();$('declarations').replaceChildren();});
  load();
})();
