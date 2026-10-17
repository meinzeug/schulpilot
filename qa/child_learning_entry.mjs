// Public child-entry acceptance. Run ONLY after Root's deployment and GO.
// One new fixed /demo family, one fixed synthetic unit, no external AI.
// --check: offline guard checks; --run: create/resume; --cleanup-only: recovery.
// --run --keep-for-timer retains ONLY the accepted own case on Root's order.
// --park-for-timer makes one normal own pause for a subsequent read-only check.
import assert from 'node:assert/strict';
import {createHash, randomBytes} from 'node:crypto';
import {chmod, lstat, mkdir, readFile, rename, unlink, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {chromium, devices} from 'playwright';

const base = 'https://schulpilot.dorfspy.de';
const artifacts = fileURLToPath(new URL('../artifacts/', import.meta.url));
const journalFile = path.join(artifacts, '.learning-room-home-qa.json');
const reportFile = path.join(artifacts, 'child-learning-entry-result.json');
const headers = {'X-Schulpilot-Request': '1'};
const mode = process.argv[2] ?? '--help';
const keepForTimer = process.argv.includes('--keep-for-timer');
const captureId = new Date().toISOString().replace(/[-:.]/g, '');
const screenshots = [], errors = [], blocked = [];
const intent = {login: false, start: false, pause: false, resume: false};
let journal, browser, parent, child, page, phase = 'local_check';
let writes = Promise.resolve();
const uuid = value => typeof value === 'string' && /^[a-f0-9]{32}$/.test(value);

class QaFailure extends Error {}
function check(value, code) { if (!value) throw new QaFailure(code); }
function digest(value) { return createHash('sha256').update(value).digest('hex'); }
function safeReason(error) {
  return error instanceof QaFailure && /^[a-z0-9_-]{1,180}$/.test(error.message)
    ? error.message : 'browser_or_local_io_operation_failed';
}
function step(value) { phase = value; console.log(JSON.stringify({qa_phase: value})); }
async function privateWrite(filename, body) {
  await writeFile(filename, body, {mode: 0o600});
  await chmod(filename, 0o600);
}
async function save() {
  const body = JSON.stringify(journal);
  const pending = writes.then(async () => {
    const temporary = journalFile + '.' + randomBytes(8).toString('hex') + '.tmp';
    try {
      await privateWrite(temporary, body);
      await rename(temporary, journalFile);
    } finally {
      await unlink(temporary).catch(error => { if (error.code !== 'ENOENT') throw error; });
    }
  });
  writes = pending.catch(() => {});
  await pending;
}
async function readJournal() {
  try {
    const info = await lstat(journalFile);
    check(info.isFile() && !info.isSymbolicLink() && !(info.mode & 0o077),
      'private_journal_must_be_a_protected_regular_file');
    return JSON.parse(await readFile(journalFile, 'utf8'));
  } catch (error) {
    if (error.code === 'ENOENT') return null;
    throw error;
  }
}
function ownDemo(demo) {
  const c = demo?.credentials, f = demo?.user?.families;
  return demo?.user?.role === 'parent' && uuid(demo.user.id) && f?.length === 1 &&
    uuid(f[0].id) && f[0].synthetic === true && f[0].permission === 'owner' &&
    uuid(demo.child_id) && uuid(demo.material_id) && demo.token === undefined &&
    /^eltern-[a-f0-9]{10}$/.test(c?.parent_username ?? '') &&
    /^kind-[a-f0-9]{10}$/.test(c?.child_username ?? '') &&
    c.parent_username.slice(7) === c.child_username.slice(5) &&
    typeof c.parent_password === 'string' && c.parent_password.length >= 12 &&
    typeof c.child_password === 'string' && c.child_password.length >= 12;
}
function permitted(method, pathname, body, choice) {
  if (method === 'GET' || method === 'HEAD') return true;
  if (method !== 'POST') return false;
  if (pathname === '/api/auth/login') return choice.login === true;
  const id = journal?.job?.unit_id;
  if (!uuid(id)) return false;
  if (pathname === '/api/units/' + id + '/start')
    return choice.start === true && !journal.start_attempted ||
      choice.resume === true && journal.started === true && journal.paused === true && !journal.resume_attempted;
  if (pathname === '/api/units/' + id + '/pause')
    return choice.pause === true && !journal.pause_attempted;
  return pathname === '/api/units/' + id + '/heartbeat' && journal.start_attempted === true &&
    (journal.heartbeat_posts ?? 0) < 12 && body && Object.keys(body).length === 1 &&
    typeof body.baseline === 'boolean';
}
async function context(role, cookies = []) {
  const ctx = await browser.newContext({viewport: {width: 390, height: 844},
    userAgent: devices['Pixel 7'].userAgent, deviceScaleFactor: 1,
    isMobile: true, hasTouch: true, storageState: {cookies, origins: []}});
  ctx.on('page', opened => opened.on('pageerror', error => errors.push({
    name: /^[A-Za-z]+Error$/.test(error.name) ? error.name : 'RuntimeError',
    fingerprint: digest(error.message),
  })));
  await ctx.route('**/api/**', async route => {
    const request = route.request(), pathname = new URL(request.url()).pathname;
    let body = null;
    try { body = request.postDataJSON(); } catch { /* Checked by permitted. */ }
    if (role !== 'child' && !['GET', 'HEAD'].includes(request.method()) ||
        !permitted(request.method(), pathname, body, intent)) {
      blocked.push({role, method: request.method(), path_fingerprint: digest(pathname)});
      return route.abort('blockedbyclient');
    }
    if (request.method() === 'POST') {
      if (pathname === '/api/auth/login') intent.login = false;
      else if (pathname.endsWith('/start')) {
        if (intent.resume) { intent.resume = false; journal.resume_attempted = true; }
        else { intent.start = false; journal.start_attempted = true; }
      }
      else if (pathname.endsWith('/pause')) { intent.pause = false; journal.pause_attempted = true; }
      else journal.heartbeat_posts = (journal.heartbeat_posts ?? 0) + 1;
      await save();
    }
    return route.continue();
  });
  return ctx;
}
async function get(ctx, route, expected = 200) {
  const response = await ctx.request.get(base + '/api' + route, {maxRedirects: 0, timeout: 15000});
  check(response.status() === expected, 'normal_authorized_read_failed_' + response.status());
  return expected === 200 ? response.json() : null;
}
async function parentIdentity() {
  let response = await parent.request.get(base + '/api/auth/me', {maxRedirects: 0});
  if (response.status() === 401 && !journal.deleted) {
    const login = await parent.request.post(base + '/api/auth/login', {headers, maxRedirects: 0,
      data: {username: journal.demo.credentials.parent_username,
        password: journal.demo.credentials.parent_password, device: 'Child entry QA recovery'}});
    check(login.status() === 200, 'owned_parent_recovery_login_failed');
    journal.parent_cookies = await parent.cookies();
    await save();
    response = await parent.request.get(base + '/api/auth/me');
  }
  check(response.status() === 200, 'owned_parent_session_required');
  const user = await response.json();
  check(user.role === 'parent' && user.id === journal.demo.user.id && user.families?.length === 1 &&
    user.families[0].id === journal.demo.user.families[0].id &&
    user.families[0].synthetic === true && user.families[0].permission === 'owner',
    'refuse_access_outside_the_new_owned_demo');
}
async function zeroAi() {
  const usage = await get(parent, '/families/' + journal.demo.user.families[0].id + '/usage');
  check(usage.synthetic === true && usage.calls_used === 0 && usage.records.length === 0 &&
    usage.known_cost_micros_usd === 0 && usage.unknown_cost_calls === 0 && usage.encumbered_micros_usd === 0,
    'external_ai_calls_or_reservations_are_forbidden');
  const limits = digest(JSON.stringify({plan: usage.plan, calls: usage.calls_limit, budget: usage.budget_micros_usd}));
  check(!journal.limits_signature || journal.limits_signature === limits, 'financial_limits_must_not_change');
  journal.limits_signature = limits;
  journal.zero_ai = true;
  await save();
}
function unitProof(unit) {
  check(unit.id === journal.job.unit_id && unit.child_id === journal.demo.child_id &&
    unit.material_id === journal.demo.material_id && unit.synthetic === true && unit.provider === 'synthetic' &&
    unit.model === 'fixed-fractions-v1' && unit.questions.length > 0 &&
    unit.questions.every(q => q.attempts.length === 0 && q.hints_used === 0),
    'only_the_owned_fixed_unanswered_synthetic_round_is_allowed');
}
async function prepare() {
  if (!journal.demo) {
    step('create_one_owned_fixed_demo');
    check(!journal.creation_attempted, 'uncertain_demo_creation_needs_operator_review');
    journal.creation_attempted = true;
    await save();
    const response = await parent.request.post(base + '/api/demo', {headers, maxRedirects: 0});
    check(response.status() === 201, 'fixed_demo_creation_failed_' + response.status());
    journal.demo = await response.json();
    journal.parent_cookies = await parent.cookies();
    await save();
  }
  check(ownDemo(journal.demo), 'owned_fixed_demo_required');
  await parentIdentity();
  await zeroAi();
  step('confirm_only_the_fixed_demo_source');
  const source = await get(parent, '/materials/' + journal.demo.material_id);
  check(source.child_id === journal.demo.child_id && source.synthetic === true && !source.fixture_id &&
    source.school_day_id === null && source.homework.length === 0, 'fixed_demo_source_required');
  if (!source.confirmed) {
    check(source.status === 'review', 'fixed_demo_source_must_be_reviewable');
    const confirmed = await parent.request.put(base + '/api/materials/' + source.id + '/confirm', {headers,
      data: {subject: source.subject, topic: source.topic, content: source.content,
        homework: source.homework, uncertainties_resolved: true}, maxRedirects: 0});
    check(confirmed.status() === 200 && (await confirmed.json()).confirmed === true,
      'normal_explicit_parent_source_confirmation_failed');
  }
  step('prepare_one_fixed_synthetic_round');
  if (!journal.job) {
    journal.job = {key: 'child-entry-' + randomBytes(16).toString('hex')};
    await save();
  }
  if (!journal.job.id) {
    check(!journal.job.attempted, 'uncertain_unit_submission_needs_operator_review');
    journal.job.attempted = true;
    await save();
    const response = await parent.request.post(base + '/api/children/' + journal.demo.child_id + '/units', {
      headers: {...headers, 'Idempotency-Key': journal.job.key}, data: {material_id: journal.demo.material_id}, maxRedirects: 0});
    check(response.status() === 202, 'fixed_synthetic_round_submission_failed_' + response.status());
    const queued = await response.json();
    check(uuid(queued.id), 'fixed_synthetic_job_id_required');
    journal.job.id = queued.id;
    await save();
  }
  const deadline = Date.now() + 120000;
  for (let attempt = 0; !journal.job.unit_id && attempt < 120 && Date.now() < deadline; attempt++) {
    const data = await get(parent, '/jobs/' + journal.job.id);
    check(data.kind === 'unit' && data.status !== 'failed', 'fixed_synthetic_job_failed_without_retry');
    if (data.status === 'completed') {
      check(uuid(data.result?.unit_id), 'completed_synthetic_job_needs_its_real_round');
      journal.job.unit_id = data.result.unit_id;
      await save();
    } else {
      check(['queued', 'running'].includes(data.status), 'unexpected_synthetic_job_status');
      await new Promise(resolve => setTimeout(resolve, 1000));
    }
  }
  check(uuid(journal.job.unit_id), 'fixed_synthetic_preparation_deadline');
  unitProof(await get(parent, '/units/' + journal.job.unit_id));
  await zeroAi();
}
async function accessible() {
  await page.waitForSelector('flutter-view', {timeout: 90000});
  // Flutter's pinned mobile enabler requires an actual pointer at the exact
  // centre; HTMLElement.click() has offset(0,0) and only enables desktop AT.
  // This activates the accessibility layer, never an application action.
  for (const placeholder of await page.locator('flt-semantics-placeholder').all()) {
    const box = await placeholder.boundingBox();
    if (box && box.width > 1 && box.height > 1) {
      await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
    } else {
      await placeholder.evaluate(node => node.click());
    }
  }
  await page.waitForTimeout(450);
}
async function open(route) {
  const response = await page.goto(base + route, {waitUntil: 'domcontentloaded', timeout: 90000});
  check(response?.ok() && response.url().startsWith(base + '/'), 'public_https_page_unavailable');
  await accessible();
}
function button(name) { return page.getByRole('button', {name, exact: true}); }
async function reveal(locator) {
  const target = locator.first(), size = page.viewportSize();
  const upper = new URL(page.url()).pathname.startsWith('/unit/') ? 0 : size.width >= 1040 ? 4 : 75;
  for (let attempt = 0; attempt < 30; attempt++) {
    const box = await target.count() ? await target.boundingBox({timeout: 500}).catch(() => null) : null;
    if (box && box.width > 0 && box.height > 0 && box.x >= 0 && box.x + box.width <= size.width + 1 &&
      box.y >= upper && box.y + Math.min(box.height, size.height - 200) <= size.height - 95) return target;
    await page.mouse.move(size.width - 28, size.height - 150);
    await page.mouse.wheel(0, !box && attempt === 0 ? -20000 : box && box.y < upper ? -350 : 350);
    await page.waitForTimeout(250);
  }
  throw new QaFailure('expected_flutter_control_not_visible');
}
async function tap(locator) {
  const target = await reveal(locator), box = await target.boundingBox();
  check(box && box.height >= 44 && box.height < page.viewportSize().height, 'touch_control_not_usable');
  journal.touch_bounds ??= [];
  journal.touch_bounds.push({width: Math.round(box.width), height: Math.round(box.height),
    viewport: page.viewportSize().width});
  await save();
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  await page.waitForTimeout(250);
}
async function type(locator, value) {
  const field = await reveal(locator);
  await field.click({position: {x: 20, y: 20}});
  await page.waitForTimeout(250);
  await page.keyboard.press('Control+A');
  await page.keyboard.type(value, {delay: 8});
  check(await field.inputValue() === value, 'visible_login_field_did_not_accept_typing');
}
async function uiResponse(method, route, action) {
  const waiting = page.waitForResponse(r => new URL(r.url()).pathname === '/api' + route &&
    r.request().method() === method, {timeout: 45000});
  waiting.catch(() => {});
  await action();
  return waiting;
}
async function shot(label) {
  check(journal.child_authenticated === true, 'never_capture_login_credentials');
  const filename = 'child-learning-entry-' + journal.run_id + '-' + captureId + '-' + label + '.png';
  await privateWrite(path.join(artifacts, filename), await page.screenshot());
  screenshots.push(filename);
}
async function childLogin() {
  step('independent_child_login_through_visible_ui');
  page = await child.newPage();
  if (journal.child_authenticated) {
    const response = await child.request.get(base + '/api/auth/me');
    if (response.status() === 200) {
      const user = await response.json();
      check(user.role === 'child' && user.child_id === journal.demo.child_id, 'resumed_child_identity_mismatch');
      return open('/app');
    }
    check(response.status() === 401, 'resumed_child_session_unavailable');
  }
  await open('/login');
  await type(page.getByRole('textbox', {name: 'E-Mail oder Benutzername', exact: true}), journal.demo.credentials.child_username);
  await type(page.getByLabel('Passwort', {exact: true}), journal.demo.credentials.child_password);
  intent.login = true;
  const response = await uiResponse('POST', '/auth/login', () => tap(button('Anmelden')));
  check(response.status() === 200, 'independent_child_ui_login_failed');
  const user = (await response.json()).user;
  check(user.role === 'child' && user.child_id === journal.demo.child_id && user.synthetic === true,
    'child_ui_login_must_match_the_new_owned_demo');
  journal.child_authenticated = true;
  journal.child_cookies = await child.cookies();
  await save();
  await page.waitForURL(base + '/app', {timeout: 45000});
}
async function layoutBounds(locator) {
  const node = await reveal(locator), box = await node.boundingBox(), size = page.viewportSize();
  check(box.x >= -1 && box.x + box.width <= size.width + 1, 'visible_control_has_horizontal_overflow');
}
async function homeAndList(width, stateLabel) {
  step('child_home_and_other_topic_' + stateLabel + '_' + width);
  await page.setViewportSize({width, height: 844});
  await open('/app');
  await reveal(page.getByText('DEINE LERNRUNDE', {exact: true}));
  check(await button('Weiterlernen').count() === 1, 'home_requires_one_primary_saved_learning_action');
  const primary = await button('Weiterlernen').boundingBox();
  check(primary && primary.y >= 70 && primary.y + primary.height < 750,
    'primary_saved_round_must_be_visible_on_first_mobile_screen');
  await layoutBounds(button('Heutige Seiten scannen'));
  await layoutBounds(button('Anderes Thema'));
  check(await page.getByText('Verstehen · Üben · Rückblick', {exact: true}).count() === 1,
    'home_shows_the_same_three_learning_phases');
  await shot(stateLabel + '-home-' + width);
  await tap(button('Anderes Thema'));
  await page.waitForURL(base + '/learn/' + journal.demo.child_id, {timeout: 45000});
  await reveal(button('Suchen & filtern'));
  check(await page.getByRole('textbox').count() === 0 && await page.getByRole('combobox').count() === 0,
    'child_learning_list_must_show_rounds_before_search_filters');
  await layoutBounds(button('Suchen & filtern'));
  const rows = page.getByRole('button', {name: /Brüche[\s\S]*(Runde starten|Hier weiterlernen)/});
  await reveal(rows);
  await shot(stateLabel + '-other-topic-' + width);
  await tap(button('Suchen & filtern'));
  await reveal(page.getByRole('textbox', {name: 'Thema suchen', exact: true}));
  await tap(button('Suche schließen'));
  check(await page.getByRole('textbox').count() === 0, 'search_disclosure_can_close_again');
  journal.layouts ??= [];
  if (!journal.layouts.some(value => value.width === width && value.state === stateLabel)) {
    journal.layouts.push({width, state: stateLabel, home: true, secondary_photos: true, simple_list: true});
    await save();
  }
}
async function run() {
  const health = await get(parent, '/health');
  check(typeof health.source_commit === 'string' && /^[a-f0-9]{40}$/.test(health.source_commit),
    'deployed_source_commit_required');
  journal.source_commit = health.source_commit;
  await save();
  await prepare();
  await childLogin();
  const currentState = journal.resumed ? 'active' : journal.paused ? 'paused' : journal.started ? 'active' : 'prepared';
  for (const width of [390, 320, 1280]) await homeAndList(width, currentState);
  if (!journal.started) {
    check(!journal.start_attempted, 'uncertain_start_requires_normal_read_only_operator_review');
    step('explicit_home_start_without_an_extra_gate');
    await page.setViewportSize({width: 390, height: 844});
    await open('/app');
    intent.start = true;
    const response = await uiResponse('POST', '/units/' + journal.job.unit_id + '/start', () => tap(button('Weiterlernen')));
    check(response.status() === 200, 'explicit_saved_round_start_failed_' + response.status());
    const unit = await response.json();
    unitProof(unit);
    check(unit.status === 'active', 'explicit_saved_round_must_be_active');
    journal.started = true;
    await save();
    await page.waitForURL(base + '/unit/' + journal.job.unit_id, {timeout: 45000});
    check(await button('Einheit starten').count() === 0, 'the_round_must_not_require_a_second_start_gate');
    await reveal(button('Lernrunde verlassen'));
    await shot('focused-learning-round-390');
  }
  if (!journal.paused) {
    check(!journal.pause_attempted, 'uncertain_pause_requires_operator_review');
    step('explicitly_leave_and_resume_the_saved_round');
    if (page.url() !== base + '/unit/' + journal.job.unit_id) await open('/unit/' + journal.job.unit_id);
    intent.pause = true;
    const response = await uiResponse('POST', '/units/' + journal.job.unit_id + '/pause', () => tap(button('Lernrunde verlassen')));
    check(response.status() === 200, 'explicit_child_leave_did_not_save_pause');
    await page.waitForURL(base + '/app', {timeout: 45000});
    const unit = await get(parent, '/units/' + journal.job.unit_id);
    unitProof(unit);
    check(unit.status === 'paused', 'paused_round_must_persist_before_home_resume');
    journal.paused = true;
    await save();
  }
  if (!journal.resumed) {
    for (const width of [390, 320, 1280]) await homeAndList(width, 'paused');
  }
  if (!journal.resumed) {
    check(!journal.resume_attempted, 'uncertain_resume_requires_normal_read_only_operator_review');
    step('resume_the_saved_round_through_the_primary_home_action');
    await page.setViewportSize({width: 390, height: 844});
    await open('/app');
    intent.resume = true;
    const response = await uiResponse('POST', '/units/' + journal.job.unit_id + '/start', () => tap(button('Weiterlernen')));
    check(response.status() === 200, 'explicit_home_resume_failed_' + response.status());
    const unit = await response.json();
    unitProof(unit);
    check(unit.status === 'active', 'resuming_the_saved_round_must_be_active');
    journal.resumed = true;
    await save();
    await page.waitForURL(base + '/unit/' + journal.job.unit_id, {timeout: 45000});
    check(await button('Einheit starten').count() === 0 && await button('Lernen fortsetzen').count() === 0,
      'home_resume_must_return_to_the_saved_step_without_an_extra_gate');
    await shot('resumed-learning-round-390');
  }
  step('prepared_status_direct_link_is_read_only');
  await page.setViewportSize({width: 390, height: 844});
  await open('/learning-preparation/' + journal.demo.child_id + '/' + journal.job.id);
  await reveal(page.getByText('Deine Runde ist bereit.', {exact: true}));
  check(await button('Los geht’s').count() === 1, 'completed_preparation_must_offer_a_deliberate_start');
  await shot('prepared-status-read-only-390');
  const finalUnit = await get(parent, '/units/' + journal.job.unit_id);
  unitProof(finalUnit);
  check(finalUnit.status === 'active', 'reading_preparation_must_not_change_the_resumed_round');
  await zeroAi();
  check(errors.length === 0 && blocked.length === 0, 'browser_runtime_or_unintended_mutation_detected');
  journal.acceptance_passed = true;
  await save();
}
async function cleanup() {
  check(ownDemo(journal.demo), 'refuse_cleanup_outside_the_owned_fixed_demo');
  step('normal_owned_family_deletion_and_session_invalidation');
  for (const ctx of [parent, child]) await Promise.all(ctx.pages().map(opened => opened.close()));
  if (!journal.deleted) {
    await parentIdentity();
    const response = await parent.request.delete(base + '/api/account', {headers,
      data: {password: journal.demo.credentials.parent_password}, maxRedirects: 0});
    check(response.status() === 200, 'normal_owned_family_cleanup_failed');
    journal.deleted = true;
    await save();
  }
  await get(parent, '/auth/me', 401);
  await get(child, '/auth/me', 401);
  journal.sessions_invalidated = true;
  await save();
}
async function parkForTimer() {
  check(journal.acceptance_passed === true && journal.cleanup_held_for_timer === true && ownDemo(journal.demo),
    'timer_parking_requires_the_completed_owned_held_acceptance');
  step('normally_pause_only_the_verified_owned_round_for_read_only_timer_check');
  await parentIdentity();
  const identity = await get(child, '/auth/me');
  check(identity.role === 'child' && identity.child_id === journal.demo.child_id, 'owned_child_session_required_for_pause');
  let unit = await get(child, '/units/' + journal.job.unit_id);
  unitProof(unit);
  if (unit.status === 'active') {
    check(!journal.timer_pause_attempted, 'an_uncertain_final_pause_must_not_be_repeated');
    journal.timer_pause_attempted = true;
    await save();
    const response = await child.request.post(base + '/api/units/' + unit.id + '/pause', {headers, maxRedirects: 0});
    check(response.status() === 200, 'normal_owned_timer_pause_failed_' + response.status());
    unit = await response.json();
    unitProof(unit);
  }
  check(unit.status === 'paused', 'read_only_timer_followup_requires_the_real_paused_unit');
  journal.parked_for_timer = true;
  await zeroAi();
  await save();
}
function localChecks() {
  const previous = journal, id = 'a'.repeat(32);
  journal = {job: {unit_id: id}};
  assert.equal(permitted('POST', '/api/units/' + id + '/start', null, {start: true}), true);
  assert.equal(permitted('POST', '/api/units/' + id + '/start', null, {}), false);
  assert.equal(permitted('POST', '/api/units/' + 'b'.repeat(32) + '/start', null, {start: true}), false);
  for (const suffix of ['coaching', 'practice', 'tutor', 'extract', 'answer', 'continue'])
    assert.equal(permitted('POST', '/api/units/' + id + '/' + suffix, {}, {start: true}), false);
  assert.equal(permitted('POST', '/api/children/' + id + '/units', {}, {}), false);
  journal.start_attempted = true;
  assert.equal(permitted('POST', '/api/units/' + id + '/start', null, {start: true}), false);
  assert.equal(permitted('POST', '/api/units/' + id + '/start', null, {resume: true}), false);
  journal.started = true;
  journal.paused = true;
  assert.equal(permitted('POST', '/api/units/' + id + '/start', null, {resume: true}), true);
  journal.resume_attempted = true;
  assert.equal(permitted('POST', '/api/units/' + id + '/start', null, {resume: true}), false);
  assert.equal(permitted('POST', '/api/units/' + id + '/heartbeat', {baseline: true}, {}), true);
  assert.equal(permitted('POST', '/api/units/' + id + '/heartbeat', {baseline: true, seconds: 300}, {}), false);
  journal.heartbeat_posts = 12;
  assert.equal(permitted('POST', '/api/units/' + id + '/heartbeat', {baseline: false}, {}), false);
  assert.equal(safeReason(new Error('private value')), 'browser_or_local_io_operation_failed');
  journal = previous;
}
async function main() {
  localChecks();
  if (mode === '--check' || mode === '--help') {
    console.log(JSON.stringify({qa_driver: 'child_learning_entry', local_checks: 'passed', public_requests: 0,
      run_after_root_go: 'node qa/child_learning_entry.mjs --run', cleanup_recovery: 'node qa/child_learning_entry.mjs --cleanup-only',
      explicit_root_timer_hold: 'node qa/child_learning_entry.mjs --run --keep-for-timer',
      normal_own_pause_for_timer: 'node qa/child_learning_entry.mjs --park-for-timer',
      own_fixed_demo_families: 1, maximum_fixed_synthetic_jobs: 1, maximum_explicit_ui_starts: 2,
      maximum_ui_heartbeats: 12, external_ai_allowed: false, answers_allowed: false,
      widths: [390, 320, 1280], pending_status_is_covered_offline: true}));
    return;
  }
  check(['--run', '--cleanup-only', '--park-for-timer'].includes(mode), 'use_check_run_cleanup_or_park_for_timer');
  await mkdir(artifacts, {recursive: true});
  journal = await readJournal();
  if (!journal) {
    check(mode === '--run', 'cleanup_requires_the_existing_owned_journal');
    journal = {purpose: 'child-learning-entry-fixed-demo-only', version: 1,
      run_id: new Date().toISOString().replace(/[-:.]/g, ''), heartbeat_posts: 0};
    await save();
  }
  check(journal.purpose === 'child-learning-entry-fixed-demo-only' && journal.version === 1 &&
    (!journal.demo || ownDemo(journal.demo)) && Number.isInteger(journal.heartbeat_posts) &&
    journal.heartbeat_posts >= 0 && journal.heartbeat_posts <= 12, 'only_this_owned_protected_journal_can_resume');
  let passed = false, failure = null, failedPhase = null;
  try {
    browser = await chromium.launch({headless: true, executablePath: process.env.CHROME_PATH || '/opt/google/chrome/chrome',
      args: ['--no-sandbox'], timeout: 15000});
    parent = await context('parent', journal.parent_cookies ?? []);
    child = await context('child', journal.child_cookies ?? []);
    if (mode === '--run') {
      check(!journal.deleted, 'never_recreate_a_deleted_demo_on_resume');
      await run();
    }
    if (mode === '--park-for-timer') {
      await parkForTimer();
    } else if (keepForTimer && mode === '--run') {
      step('hold_owned_demo_for_root_timer_verification');
      check(journal.acceptance_passed === true, 'only_a_completed_acceptance_can_be_held');
      journal.cleanup_held_for_timer = true;
      await save();
    } else {
      await cleanup();
    }
    passed = true;
  } catch (error) {
    failedPhase = phase;
    failure = safeReason(error);
    if (journal.child_authenticated && page && !new URL(page.url()).pathname.startsWith('/login')) {
      await shot('failure-current').catch(() => {});
      journal.failure_ui = await page.evaluate(() => ({
        semantics_nodes: document.querySelectorAll('flt-semantics').length,
        placeholders: document.querySelectorAll('flt-semantics-placeholder').length,
        android_user_agent: /Android/.test(navigator.userAgent),
        has_password_field: document.querySelector('input[type="password"]') !== null,
        width: innerWidth,
      })).catch(() => null);
      await save();
    }
    // Recovery keeps ONLY this protected own journal. It cannot recreate an
    // uncertain account/job or send an extra start. Operator can clean up.
  } finally {
    if (browser) await browser.close();
    await writes;
    const report = {url: base, source_commit: journal.source_commit ?? null, mode,
      qa_passed: passed && (mode === '--cleanup-only' || journal.acceptance_passed === true),
      failure, failed_phase: failedPhase, own_child_ui_login: journal.child_authenticated === true,
      synthetic_jobs: journal.job?.id ? 1 : 0, external_ai_zero_verified: journal.zero_ai === true,
      explicit_start: journal.started === true, saved_pause: journal.paused === true,
      explicit_home_resume: journal.resumed === true,
      real_paused_state_for_root_timer_check: journal.parked_for_timer === true,
      layouts: journal.layouts ?? [], preparation_direct_link_read_only: journal.acceptance_passed === true,
      browser_profile: 'Android Pixel 7 user-agent, CSS viewport sizes, deviceScaleFactor 1',
      prior_driver_failure_ui: journal.failure_ui ?? null,
      actual_clicked_control_bounds: journal.touch_bounds ?? [],
      child_answers_submitted: 0, ordinary_ui_heartbeats: journal.heartbeat_posts,
      cleanup_complete: journal.deleted === true && journal.sessions_invalidated === true,
      cleanup_held_for_root_timer_check: journal.cleanup_held_for_timer === true && journal.deleted !== true,
      browser_runtime_errors: errors, blocked_mutations: blocked, screenshots,
      cleanup_recovery: 'node qa/child_learning_entry.mjs --cleanup-only', completed: new Date().toISOString()};
    const reportSuffix = mode === '--park-for-timer' ? '-timer-park' : mode === '--cleanup-only' ? '-cleanup' : '';
    const destination = reportSuffix ? path.join(artifacts, 'child-learning-entry' + reportSuffix + '-result.json') : reportFile;
    await privateWrite(destination, JSON.stringify(report, null, 2));
    await privateWrite(path.join(artifacts, 'child-learning-entry-' + journal.run_id + reportSuffix + '-result.json'), JSON.stringify(report, null, 2));
    if (report.cleanup_complete) await unlink(journalFile);
    console.log(JSON.stringify(report));
    if (!report.qa_passed) process.exitCode = 1;
  }
}
main().catch(error => {
  console.log(JSON.stringify({qa_passed: false, phase, failure: safeReason(error)}));
  process.exitCode = 1;
});
