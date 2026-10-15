// Actual public Flutter Web UI, only the temporary synthetic household prepared
// by prepare_library.py. No mocked API responses, real children or AI retries.
import {chromium} from 'playwright';
import {readFile, writeFile, chmod} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const base = 'https://schulpilot.dorfspy.de';
const account = JSON.parse(await readFile(path.join(root, 'artifacts/.library-qa-account.json'), 'utf8'));
if (account.marker !== 'library-qa-v1' || account.phase !== 'ready') throw new Error('Prepare the own synthetic fixture first');
const errors = [], checks = [];
let phase = 'launch', browser, childPage;
let mutations = 0, imageRequests = 0;
let uiAnswers = 0;
class Failure extends Error {}
const check = (value, code) => { if (!value) throw new Failure(code); };
const button = (page, name) => page.getByRole('button', {name, exact: typeof name === 'string'});
const chip = (page, name) => page.getByRole('checkbox', {name, exact: true}).or(button(page, name)).or(page.getByLabel(name, {exact: true})).first();
const apiPath = response => new URL(response.url()).pathname;
const materialPath = '/children/' + account.child_id + '/materials';
const learningPath = '/children/' + account.child_id + '/learning';
function step(name) { phase = name; console.log(JSON.stringify({phase})); }
function observe(page) {
  page.on('pageerror', () => errors.push('javascript_runtime_error'));
  page.on('request', request => {
    const url = new URL(request.url());
    if (request.method() === 'POST' && /\/(units|coach|coaching|package|tutor|extract)(?:\/|$)/.test(url.pathname)) mutations++;
    if (/\/materials\/[^/]+\/image$/.test(url.pathname)) imageRequests++;
  });
}
async function accessible(page) {
  await page.waitForSelector('flutter-view', {timeout: 90000});
  await page.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(node => node.click()));
  await page.waitForTimeout(350);
}
async function open(page, route) {
  await page.goto(base + route, {waitUntil: 'domcontentloaded', timeout: 90000});
  await accessible(page);
}
async function reveal(page, locator, modal = false) {
  const target = locator.first(), size = page.viewportSize();
  for (let attempt = 0; attempt < 40; attempt++) {
    const box = await target.count() ? await target.boundingBox({timeout: 500}).catch(() => null) : null;
    if (box && box.width > 0 && box.height > 0 && box.y >= (modal ? 3 : 73) && box.y + box.height <= size.height - (modal ? 3 : 95)) return target;
    await page.mouse.move(modal ? size.width / 2 : size.width - 22, size.height - 160);
    await page.mouse.wheel(0, !box && attempt === 0 ? -18000 : box && box.y < 73 ? -420 : 420);
    await page.waitForTimeout(180);
  }
  throw new Failure('expected_touch_target_not_visible');
}
async function tap(page, locator, modal = false) {
  const box = await (await reveal(page, locator, modal)).boundingBox();
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  await page.waitForTimeout(180);
}
async function type(page, locator, value, modal = false) {
  const input = await reveal(page, locator, modal);
  await input.click({position: {x: 20, y: 20}});
  await page.waitForTimeout(180);
  await page.keyboard.press('Control+A');
  await page.keyboard.type(value, {delay: 8});
  check(await input.inputValue() === value, 'keyboard_input_not_received');
}
async function responseFor(page, route, action, method = 'GET') {
  const pending = page.waitForResponse(r => apiPath(r) === '/api' + route && r.request().method() === method, {timeout: 40000});
  pending.catch(() => {});
  await action();
  const response = await pending;
  check(response.status() === 200, 'public_api_' + response.status());
  const data = await response.json();
  await page.waitForTimeout(250);
  return data;
}
async function get(context, route) {
  const response = await context.request.get(base + '/api' + route);
  check(response.status() === 200, 'authenticated_read_' + response.status());
  return response.json();
}
async function shot(page, name) {
  const file = path.join(root, 'artifacts/library-' + name + '.png');
  await page.screenshot({path: file});
  await chmod(file, 0o600);
}
async function dropdown(page, label, value) {
  const field = page.getByRole('combobox', {name: new RegExp(label)}).or(button(page, new RegExp('^' + escaped(label) + '(?:\\s|$)'))).or(page.getByLabel(label, {exact: true})).first();
  await tap(page, field, true);
  const item = page.getByRole('menuitem', {name: value, exact: true}).or(page.getByRole('option', {name: value, exact: true})).or(page.getByLabel(value, {exact: true})).last();
  await tap(page, item, true);
}
async function login(page, role) {
  step(role + '_login_open');
  await open(page, '/login');
  step(role + '_login_username');
  await type(page, page.getByRole('textbox', {name: 'E-Mail oder Benutzername', exact: true}), account.credentials[role + '_username']);
  step(role + '_login_password');
  await type(page, page.getByLabel('Passwort', {exact: true}), account.credentials[role + '_password']);
  step(role + '_login_submit');
  const result = await responseFor(page, '/auth/login', () => tap(page, button(page, 'Anmelden')), 'POST');
  check(result.user.role === role, 'independent_login_role_mismatch');
  await page.waitForURL(base + '/app', {timeout: 30000});
  step(role + '_login_complete');
}
function bounded(data) {
  check(data.items.length <= data.page_size, 'unbounded_page');
  check(data.items.every(item => !['content', 'questions', 'answers', 'path'].some(key => key in item)), 'private_bodies_in_list');
}
function escaped(value) { return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }
async function fillAnswer(page, q) {
  if (q.type === 'choice') await tap(page, button(page, new RegExp('^' + escaped(q.answer) + '(?:\\s+' + escaped(q.answer) + ')?$')));
  else if (['gap', 'short'].includes(q.type)) await type(page, page.getByRole('textbox', {name: 'Deine Antwort', exact: true}), q.answer);
  else if (q.type === 'match') {
    for (const pair of q.options) { const [left, right] = pair.split('|'); await dropdown(page, left, right); }
  } else throw new Failure('unknown_task_type');
}

try {
  browser = await chromium.launch({headless: true, executablePath: process.env.CHROME_PATH || '/opt/google/chrome/chrome', args: ['--no-sandbox']});
  const child = await browser.newContext({viewport: {width: 390, height: 844}, deviceScaleFactor: 1});
  const parent = await browser.newContext({viewport: {width: 1280, height: 900}, deviceScaleFactor: 1});
  const page = await child.newPage(), pp = await parent.newPage();
  childPage = page;
  observe(page); observe(pp);
  step('independent_child_ui_login');
  await login(page, 'child');
  await page.waitForTimeout(500);
  await writeFile(path.join(root, 'artifacts/library-home-aria.txt'), await page.locator('body').ariaSnapshot(), {mode: 0o600});
  await reveal(page, button(page, /Meine Heftseiten 601 Seiten in deiner Bibliothek/));
  check(await page.getByText(/^Künstliche Bibliotheksseite /).count() === 0, 'home_contains_archive');
  checks.push('compact_home_601_pages');
  const before = mutations;
  step('child_library_page_and_back');
  let list = await responseFor(page, materialPath, () => tap(page, button(page, /^Meine Heftseiten /)));
  check(list.total === 601 && list.items.length === 20 && list.page === 1 && list.pages === 31, 'initial_pagination'); bounded(list);
  list = await responseFor(page, materialPath, () => tap(page, button(page, 'Nächste Seite')));
  check(list.page === 2, 'next_page_not_loaded');
  const selected = list.items[0];
  await tap(page, button(page, new RegExp(escaped(selected.topic))));
  await page.waitForURL(base + '/material/' + selected.id);
  list = await responseFor(page, materialPath, async () => { await page.goBack(); await accessible(page); });
  check(list.page === 2 && list.total === 601, 'back_lost_page');
  checks.push('pagination_details_back_preserves_page');
  step('subject_search_and_filters');
  list = await responseFor(page, materialPath, () => dropdown(page, 'Fach', 'Englisch'));
  check(list.total === 150 && list.page === 1 && list.items.every(item => item.subject === 'Englisch'), 'subject_filter');
  list = await responseFor(page, materialPath, () => type(page, page.getByRole('textbox', {name: 'Heftseiten durchsuchen', exact: true}), 'Beispiel 003'));
  check(list.total === 1 && list.page === 1, 'search_not_applied');
  await shot(page, 'child-search-390');
  list = await responseFor(page, materialPath, () => tap(page, button(page, 'Filter zurücksetzen')));
  check(list.total === 601 && list.page === 1, 'reset_failed');
  await tap(page, button(page, 'Filter und Sortierung'));
  await dropdown(page, 'Seiten', 'Bitte prüfen');
  await dropdown(page, 'Sortierung', 'Neueste zuerst');
  await dropdown(page, 'Ergebnisse pro Seite', '10');
  list = await responseFor(page, materialPath, () => tap(page, button(page, 'Anwenden'), true));
  check(list.total === 120 && list.page_size === 10 && list.items.every(item => !item.confirmed), 'combined_modal_filters');
  bounded(list);
  await page.setViewportSize({width: 320, height: 812});
  await page.waitForTimeout(350);
  await tap(page, button(page, 'Filter und Sortierung'));
  await shot(page, 'filters-320');
  await tap(page, button(page, 'Abbrechen'), true);
  await page.setViewportSize({width: 390, height: 844});
  await responseFor(page, materialPath, () => tap(page, button(page, 'Filter zurücksetzen')));
  await shot(page, 'child-library-390');
  check(mutations === before && imageRequests === 0, 'browsing_started_ai_or_loaded_photos');
  checks.push('subject_search_review_sort_page_size_320px', 'no_ai_or_photo_downloads_while_browsing');

  step('saved_learning_round_and_explicit_feedback');
  const beforeRound = await get(child, '/units/' + account.unit_id);
  let learning = await responseFor(page, learningPath, () => open(page, '/learn/' + account.child_id));
  if (beforeRound.status === 'completed') learning = await responseFor(page, learningPath, () => tap(page, chip(page, 'Erledigt')));
  bounded(learning);
  check(learning.items.some(item => item.id === account.unit_id), 'own_saved_round_not_listed');
  await tap(page, button(page, /^Brüche\b/));
  await page.waitForURL(base + '/unit/' + account.unit_id);
  await login(pp, 'parent');
  let unit = await get(parent, '/units/' + account.unit_id);
  if (unit.status !== 'completed') {
    if (unit.status !== 'active') await responseFor(page, '/units/' + unit.id + '/start', () => tap(page, button(page, unit.status === 'paused' ? 'Lernen fortsetzen' : 'Einheit starten')), 'POST');
    if (!unit.introduction_seen) await responseFor(page, '/units/' + unit.id + '/introduction', () => tap(page, button(page, 'Weiter zu den Übungen')), 'POST');
    for (const [index, q] of unit.questions.entries()) {
      if (q.attempts.some(a => ['correct', 'uncertain'].includes(a.outcome)) || q.attempts.length >= 3) continue;
      await reveal(page, page.getByText(q.prompt, {exact: true}));
      await fillAnswer(page, q);
      const answer = await responseFor(page, '/units/' + unit.id + '/questions/' + q.id + '/answer', () => tap(page, button(page, 'Antwort prüfen')), 'POST');
      check(answer.outcome === 'correct', 'synthetic_answer_not_saved');
      uiAnswers++;
      console.log(JSON.stringify({ui_answer_saved: q.type}));
      await reveal(page, page.getByText('Richtig!', {exact: true}));
      if (unit.questions[index + 1]) check(!await page.getByText(unit.questions[index + 1].prompt, {exact: true}).isVisible(), 'feedback_skipped_continue');
      await tap(page, button(page, answer.unit.status === 'completed' ? 'Zum Rückblick' : 'Weiter'));
    }
  }
  await reveal(page, page.getByText('Runde geschafft!', {exact: false}));
  const savedAnswer = unit.questions[0].answer + ' · Richtig';
  check(!await page.getByText(savedAnswer, {exact: false}).isVisible(), 'saved_answers_visible_in_review');
  await tap(page, chip(page, 'Antworten'));
  await reveal(page, page.getByText(savedAnswer, {exact: false}));
  await shot(page, 'saved-answers-390');
  await tap(page, chip(page, 'Rückblick'));
  check(!await page.getByText(savedAnswer, {exact: false}).isVisible(), 'answers_not_hidden_in_review');
  learning = await responseFor(page, learningPath, () => open(page, '/learn/' + account.child_id));
  // The saved section can already be selected after returning from the round.
  if (await chip(page, 'Erledigt').getAttribute('aria-checked') !== 'true') learning = await responseFor(page, learningPath, () => tap(page, chip(page, 'Erledigt')));
  const finished = learning.items.find(item => item.id === account.unit_id);
  check(finished && finished.closed_questions === 4 && finished.question_count === 4, 'completed_summary_not_from_answers'); bounded(learning);
  await shot(page, 'learning-completed-390');
  checks.push('four_structured_task_types_saved', 'separate_review_and_saved_answers', 'completed_learning_pagination');
  if (uiAnswers > 0) checks.push('feedback_waited_for_continue');

  step('parent_library_history_and_paged_picker');
  await open(pp, '/child/' + account.child_id);
  list = await responseFor(pp, materialPath, () => tap(pp, chip(pp, 'Materialien')));
  check(list.total === 601 && list.items.length === 20, 'parent_library_not_paged'); bounded(list);
  await shot(pp, 'parent-library-1280');
  await tap(pp, chip(pp, 'Plan & Vorgaben'));
  await tap(pp, button(pp, 'Auftrag oder Klassenarbeit anlegen'));
  list = await responseFor(pp, materialPath, () => tap(pp, button(pp, 'Heftseite auswählen (optional)'), true));
  check(list.total === 481 && list.items.every(item => item.confirmed), 'picker_must_show_confirmed_metadata'); bounded(list);
  list = await responseFor(pp, materialPath, () => type(pp, pp.getByRole('textbox', {name: 'Heftseiten durchsuchen', exact: true}), 'Beispiel 003', true));
  check(list.total === 1, 'picker_search_failed');
  await tap(pp, button(pp, /^Present simple · Beispiel 003/), true);
  await reveal(pp, button(pp, 'Present simple · Beispiel 003'), true);
  await tap(pp, button(pp, 'Abbrechen'), true);
  checks.push('parent_searchable_confirmed_material_picker');
  learning = await responseFor(pp, learningPath, () => tap(pp, chip(pp, 'Lernverlauf')));
  check(learning.items.some(item => item.id === account.unit_id), 'parent_history_missing_round');
  await tap(pp, button(pp, /^Brüche\b/));
  await pp.waitForURL(base + '/unit/' + account.unit_id);
  await reveal(pp, pp.getByText('Antwort: ' + unit.questions[0].answer, {exact: false}));
  unit = await get(parent, '/units/' + account.unit_id);
  check(unit.questions.every(q => q.attempts.length === 1 && q.attempts[0].outcome === 'correct'), 'saved_attempts_wrong');
  checks.push('parent_paged_sources_and_saved_answers');
  check(errors.length === 0, 'browser_runtime_error');
  const usage = await get(parent, '/families/' + account.family_id + '/usage');
  check(usage.records.every(record => record.provider === 'synthetic'), 'unexpected_external_provider_record');
  const report = {passed: true, artificial_pages: 601, checks, ui_answers_this_run: uiAnswers, stored_correct_answers: 4, external_ai_calls: 0, runtime_errors: errors};
  await writeFile(path.join(root, 'artifacts/library-browser-result.json'), JSON.stringify(report) + '\n', {mode: 0o600});
  console.log(JSON.stringify(report));
} catch (error) {
  // Only the artificial child's authenticated screens; never login fields.
  if (childPage && !/\/(login|register)(?:$|[?#])/.test(childPage.url())) {
    await writeFile(path.join(root, 'artifacts/library-debug-aria.txt'), await childPage.locator('body').ariaSnapshot(), {mode: 0o600});
    await shot(childPage, 'debug');
  }
  const report = {passed: false, phase, checks, failure: error instanceof Failure ? error.message : error.name, runtime_errors: errors};
  await writeFile(path.join(root, 'artifacts/library-browser-result.json'), JSON.stringify(report) + '\n', {mode: 0o600});
  console.log(JSON.stringify(report));
  process.exitCode = 1;
} finally { if (browser) await browser.close(); }
