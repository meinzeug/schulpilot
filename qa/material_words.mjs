// Normal public photo wizard -> persisted words, using only our original fixture.
// No auto-retries, dictionaries, push sends or real-family access.
import assert from 'node:assert/strict';
import {chromium} from 'playwright';
import {readFile, writeFile, chmod, realpath} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const base = 'https://schulpilot.dorfspy.de';
const out = fileURLToPath(new URL('../artifacts/', import.meta.url));
const privateFile = path.join(out, '.school-day-qa-account.json');
const headers = {'X-Schulpilot-Request': '1', 'X-Schulpilot-Capabilities': 'language-v1'};
const expected = new Map([['Apfel', 'apple'], ['Schule', 'school'], ['Hund', 'dog'], ['Buch', 'book'], ['Freund', 'friend']]);
let account, state, browser, child, parent, page, phase = 'initial';
const errors = [], checks = [], calls = [];
const report = {artificial_regular_family_only: true, checks};
const button = name => page.getByRole('button', {name, exact: true});
async function checkpoint(value) {
  phase = value;
  state.phase = value;
  account.material_words_qa = state;
  await writeFile(privateFile, JSON.stringify(account) + '\n', {mode: 0o600});
  await chmod(privateFile, 0o600);
  console.log(JSON.stringify({material_words_phase: value}));
}
async function get(context, route) {
  const response = await context.request.get(base + '/api' + route, {headers});
  assert.equal(response.status(), 200, 'owned_api_read_failed');
  return response.json();
}
async function open(route) {
  await page.goto(base + route, {waitUntil: 'domcontentloaded', timeout: 90000});
  await page.waitForSelector('flutter-view', {timeout: 90000});
  await page.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(n => n.click()));
  await page.waitForTimeout(400);
}
async function reveal(locator, modal = false) {
  const target = locator.first();
  for (let i = 0; i < 35; i++) {
    const box = await target.count() ? await target.boundingBox().catch(() => null) : null;
    const bottom = modal ? 0 : page.url().includes('/unit/') ? 8 : 85;
    if (box && box.width > 0 && box.y >= (modal ? 0 : 65) && box.y + box.height < page.viewportSize().height - bottom) return target;
    await page.mouse.move(modal ? page.viewportSize().width / 2 : page.viewportSize().width - 20, page.viewportSize().height - 150);
    await page.mouse.wheel(0, box && box.y < 65 ? -420 : 420);
    await page.waitForTimeout(150);
  }
  throw new Error('visible_ui_control_missing');
}
async function tap(locator, modal = false) {
  const target = await reveal(locator, modal), box = await target.boundingBox();
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  await page.waitForTimeout(200);
}
async function type(locator, value) {
  const input = await reveal(locator);
  await input.click({position: {x: 18, y: 18}});
  await page.waitForTimeout(180);
  await page.keyboard.press('Control+A');
  await page.keyboard.type(value, {delay: 15});
  assert.equal(await input.inputValue(), value, 'editor_did_not_receive_input');
}
async function tapResponse(locator, route, method, status, modal = false) {
  const waiting = page.waitForResponse(r => new URL(r.url()).pathname === '/api' + route && r.request().method() === method, {timeout: 45000});
  waiting.catch(() => {});
  await tap(locator, modal);
  const response = await waiting;
  assert.equal(response.status(), status, 'explicit_ui_request_failed');
  return response.json();
}
async function waitFor(read, predicate) {
  for (let i = 0; i < 100; i++) {
    const result = await read();
    assert.notEqual(result.status, 'failed', 'failed_job_no_automatic_retry');
    if (predicate(result)) return result;
    await page.waitForTimeout(2000);
  }
  throw new Error('bounded_wait_expired');
}
async function shot(name) {
  const filename = path.join(out, 'material-words-' + name + '.png');
  await page.screenshot({path: filename});
  await chmod(filename, 0o600);
}

if (!process.argv.includes('--run')) {
  console.log(JSON.stringify({ready: true,requires: 'prepare_language_smoke.py, deployed 1.4.3, then --run'}));
  process.exit(0);
}
try {
  account = JSON.parse(await readFile(privateFile, 'utf8'));
  state = account.material_words_qa ?? {};
  assert(account.normal_account && account.verified && /\+schulpilot-normal-qa-[a-f0-9]{12}@/.test(account.credentials?.parent_username ?? ''), 'owned_regular_fixture_required');
  assert.equal(await realpath(account.language_qa.image), path.join(out, 'language-school-page.jpg'));
  const health = await (await fetch(base + '/api/health')).json();
  assert.equal(health.version, '1.4.3', 'deploy_current_release_first');
  report.source_commit = health.source_commit;
  browser = await chromium.launch({headless: true, executablePath: '/opt/google/chrome/chrome', args: ['--no-sandbox']});
  child = await browser.newContext({viewport: {width: 390, height: 900}, isMobile: true, hasTouch: true});
  parent = await browser.newContext({viewport: {width: 1440, height: 1050}});
  for (const context of [child, parent]) context.on('page', p => p.on('pageerror', () => errors.push(phase)));
  const login = await parent.request.post(base + '/api/auth/login', {headers, data: {username: account.credentials.parent_username, password: account.credentials.parent_password}});
  assert.equal(login.status(), 200);
  const parentAccount = (await login.json()).user;
  assert.equal(parentAccount.id, account.user.id);
  assert(parentAccount.families.length === 1 && !parentAccount.families[0].synthetic);
  const familyId = parentAccount.families[0].id;
  if (!state.preferences_set) {
    const preferences = await parent.request.put(base + '/api/children/' + account.child_id + '/preferences', {headers, data: {
      weekdays: [0, 1, 2, 3, 4, 5, 6], daily_minutes: 20, weekly_minutes: 20, session_minutes: 5, break_minutes: 5, timezone: 'Europe/Berlin',
    }});
    assert.equal(preferences.status(), 200);
    state.preferences_set = true;
  }
  page = await child.newPage();
  page.on('request', request => {
    const route = new URL(request.url()).pathname;
    if (route.startsWith('/api/') && ['POST', 'PUT', 'DELETE'].includes(request.method())) calls.push(route.replace(/[a-f0-9]{32}/g, ':id'));
  });
  await checkpoint('normal_child_login');
  await open('/login');
  await type(page.getByRole('textbox', {name: 'E-Mail oder Benutzername', exact: true}), account.credentials.child_username);
  await type(page.getByLabel('Passwort', {exact: true}), account.credentials.child_password);
  const signedIn = await tapResponse(button('Anmelden'), '/auth/login', 'POST', 200);
  assert.equal(signedIn.user.child_id, account.child_id);
  await page.waitForURL(base + '/app');
  if (!state.material_id) {
    await checkpoint('normal_photo_wizard');
    await open('/after-school/' + account.child_id);
    let day = (await waitFor(() => get(child, '/children/' + account.child_id + '/school-day/today'), d => d.day != null)).day;
    assert.equal(day.child_id, account.child_id);
    assert(day.pages.length <= 1, 'only_owned_original_fixture_allowed');
    state.day_id = day.id;
    await checkpoint('own_photo_day_saved');
    if (!day.pages.length) {
      const picker = page.waitForEvent('filechooser');
      await tap(button('Fotos auswählen'));
      await (await picker).setFiles(account.language_qa.image);
      await tap(button('Zuschnitt übernehmen'), true);
      day = await waitFor(() => get(child, '/school-days/' + day.id), d => d.pages.length === 1);
    }
    if (day.pages[0].status === 'uploaded') await tap(button('Fotos abgeben'));
    day = await waitFor(() => get(child, '/school-days/' + day.id), d => {
      assert.notEqual(d.pages[0]?.status, 'unreadable', 'ocr_failed_no_automatic_retry');
      return ['review', 'confirmed'].includes(d.pages[0]?.status);
    });
    const material = day.pages[0];
    assert(!material.synthetic && material.extraction_provider === 'codex', 'actual_approved_ocr_required');
    assert([...expected].every(([meaning, word]) => material.vocabulary_preview?.pairs.some(p => p.word === word && p.meaning === meaning)), 'literal_word_preview_missing');
    await reveal(page.getByText('5 Wörter übernehmen', {exact: true}));
    await shot('before-source-confirmation');
    const confirmed = material.confirmed ? material : await tapResponse(button('Stimmt, weiter'), '/materials/' + material.id + '/confirm', 'PUT', 200);
    if (!material.confirmed) assert.equal(confirmed.vocabulary_transfer.confirmed_words, 5);
    state.material_id = material.id;
    await checkpoint('source_and_five_words_saved_together');
    checks.push('actual_photo_crop_ocr_and_atomic_word_save');
  }
  const material = await get(child, '/materials/' + state.material_id);
  const wordStatus = await get(child, '/materials/' + state.material_id + '/vocabulary');
  assert.equal(wordStatus.confirmed_words, 5);
  assert.equal(wordStatus.review_words, 0);
  const before = await get(parent, '/families/' + familyId + '/usage');
  assert.equal(before.calls_used, 1, 'only_one_photo_ocr_call_expected');
  for (let i = 0; i < 3; i++) await get(child, '/materials/' + material.id + '/vocabulary');
  const repeat = await child.request.post(base + '/api/materials/' + material.id + '/vocabulary', {headers, data: {
    target_locale: 'en-GB', language_confirmed: true, revision: material.revision,
  }});
  assert.equal(repeat.status(), 200);
  assert.equal((await repeat.json()).confirmed_words, 5);
  await checkpoint('regular_child_menu');
  await open('/app');
  await page.getByRole('button', {name: 'Wörter', exact: true}).or(page.getByRole('tab', {name: /^Wörter/})).first().click();
  await page.waitForURL(base + '/vocabulary/' + account.child_id);
  await page.getByText('Meine Wörter', {exact: true}).waitFor();
  await shot('regular-child-menu');
  if (!state.unit_id) {
    await tap(button('Wörter üben'));
    const round = await tapResponse(button('Runde beginnen'), '/children/' + account.child_id + '/vocabulary/rounds', 'POST', 201, true);
    state.unit_id = round.unit_id;
    await checkpoint('word_round_created');
  }
  await open('/unit/' + state.unit_id);
  let unit = await get(child, '/units/' + state.unit_id);
  if (unit.status !== 'completed') {
    if (unit.status !== 'active') await tapResponse(button(unit.status === 'paused' ? 'Lernen fortsetzen' : 'Einheit starten'), '/units/' + unit.id + '/start', 'POST', 200);
    if (!unit.introduction_seen) await tapResponse(button('Weiter zu den Übungen'), '/units/' + unit.id + '/introduction', 'POST', 200);
    for (let i = 0; i < 8; i++) {
      unit = await get(child, '/units/' + state.unit_id);
      if (unit.pending_feedback) {
        await tapResponse(button(unit.status === 'completed' ? 'Ergebnis ansehen' : 'Weiter'), '/units/' + unit.id + '/feedback/acknowledge', 'POST', 200);
        continue;
      }
      const question = unit.questions.find(q => !q.attempts.some(a => ['correct', 'uncertain'].includes(a.outcome)) && q.attempts.length < 3);
      if (!question) break;
      assert(!Object.hasOwn(question, 'answer') && !Object.hasOwn(question, 'accepted') && !Object.hasOwn(question.language, 'evaluation_policy'), 'private_solution_leak');
      const answer = expected.get(question.language.cue);
      assert(answer, 'only_original_artificial_answers_allowed');
      await type(page.getByRole('textbox', {name: /^Deine Antwort/}), answer);
      if (!state.offline_checked) {
        await child.setOffline(true);
        await tap(button('Antwort prüfen'));
        await page.getByText(/Keine Verbindung zu SCHULPILOT/).waitFor();
        await child.setOffline(false);
        state.offline_checked = true;
      }
      const result = await tapResponse(button('Antwort prüfen'), '/units/' + unit.id + '/questions/' + question.id + '/answer', 'POST', 200);
      assert.equal(result.outcome, 'correct');
      if (!state.feedback_reload_checked) {
        await open('/unit/' + unit.id);
        assert.equal((await get(child, '/units/' + unit.id)).pending_feedback?.attempt_id, result.attempt_id);
        state.feedback_reload_checked = true;
      }
      await tapResponse(button(result.unit.status === 'completed' ? 'Ergebnis ansehen' : 'Weiter'), '/units/' + unit.id + '/feedback/acknowledge', 'POST', 200);
    }
  }
  unit = await get(child, '/units/' + state.unit_id);
  assert.equal(unit.status, 'completed');
  assert.equal(unit.questions.length, 3);
  assert(unit.questions.every(q => q.attempts.length === 1 && q.attempts[0].outcome === 'correct'));
  checks.push('three_actual_answers_feedback_reload_offline_recovery');
  const own = await get(child, '/children/' + account.child_id + '/vocabulary');
  const parents = await get(parent, '/children/' + account.child_id + '/vocabulary');
  assert.deepEqual(own.summary, parents.summary);
  assert.equal(own.pagination.total, 5);
  const progress = await get(parent, '/children/' + account.child_id + '/learning-progress');
  assert.equal(progress.totals.practiced_tasks, 3);
  const overview = await get(child, '/children/' + account.child_id + '/overview?compact=true');
  assert(overview.plan.goal_required && !overview.plan.daily_goal_met && overview.plan.daily_active_seconds < 1200, 'estimated_minutes_must_not_fulfil_time_minimum');
  assert(overview.plan.voluntary.some(item => item.kind === 'vocabulary'));
  const after = await get(parent, '/families/' + familyId + '/usage');
  assert.equal(after.calls_used, before.calls_used, 'word_save_or_round_reserved_unexpected_ai');
  checks.push('same_child_parent_progress_no_duplicate_words_or_extra_ai');
  for (const width of [320, 390, 960, 1440]) {
    await page.setViewportSize({width, height: 1050});
    await open('/vocabulary/' + account.child_id);
    await page.getByText('Meine Wörter', {exact: true}).waitFor();
    await shot('child-' + width);
  }
  page = await parent.newPage();
  await open('/app');
  await page.getByRole('button', {name: 'Wörter', exact: true}).or(page.getByRole('tab', {name: /^Wörter/})).first().click();
  await page.waitForURL(base + '/words');
  await page.getByText('Wörter deiner Kinder', {exact: true}).waitFor();
  await tap(page.getByText('Künstliches Testkind', {exact: true}).or(page.getByRole('button', {name: /Künstliches Testkind/})));
  await page.waitForURL(base + '/vocabulary/' + account.child_id);
  await page.getByText('Künstliches Testkind · Wortschatz', {exact: true}).waitFor();
  await shot('regular-parent-menu');
  await page.setViewportSize({width: 320, height: 1050});
  await open('/words');
  await shot('parent-320');
  checks.push('regular_parent_child_menu_and_responsive_word_pages');
  assert.equal(errors.length, 0, 'browser_runtime_error');
  assert(!calls.some(route => route.endsWith('/vocabulary/imports')), 'literal_import_must_not_call_model');
  report.success = true;
  report.browser_runtime_errors = errors.length;
  report.confirmed_words = 5;
  report.web_answers = 3;
  report.actual_ocr_calls = before.calls_used;
  report.additional_word_ai_calls = after.calls_used - before.calls_used;
  await checkpoint('web_passed_keep_for_native');
} catch (error) {
  report.success = false;
  report.failed_phase = phase;
  report.error = error instanceof assert.AssertionError ? error.message.split('\n')[0] : 'photo_word_review_failed';
  report.failure_type = error.name;
  const privateError = path.join(out, 'material-words-web-private-error.txt');
  await writeFile(privateError, String(error.stack ?? error), {mode: 0o600});
  await chmod(privateError, 0o600);
  if (page && phase !== 'normal_child_login') await shot('interrupted-' + phase).catch(() => {});
  process.exitCode = 1;
} finally {
  for (const context of [child, parent].filter(Boolean)) {
    await context.request.post(base + '/api/auth/logout', {headers}).catch(() => {});
    await context.close();
  }
  if (browser) await browser.close();
  await writeFile(path.join(out, 'material-words-web-result.json'), JSON.stringify(report) + '\n', {mode: 0o600});
  console.log(JSON.stringify(report));
}
