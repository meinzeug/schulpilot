// Real public activity acceptance, ONLY after Root's deployment/GO.
// One owned fixed /demo family, two fixed synthetic jobs, no external AI.
// No clock overrides or direct heartbeat calls: normal Flutter UI earns time.
// --check: local guards only. --run: create/resume this owned journal.
// --cleanup-only: normal account deletion after an interrupted/failed run.
import assert from 'node:assert/strict';
import {createHash, randomBytes} from 'node:crypto';
import {chmod, lstat, mkdir, readFile, rename, unlink, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright';

const base = 'https://schulpilot.dorfspy.de';
const artifacts = fileURLToPath(new URL('../artifacts/', import.meta.url));
const journalFile = path.join(artifacts, '.minimum-time-qa-account.json');
const reportFile = path.join(artifacts, 'minimum-learning-time-result.json');
const mode = process.argv[2] ?? '--help';
const recoverObservedTime = process.argv.includes('--recover-observed-time');
const headers = {'X-Schulpilot-Request': '1'};
const screenshots = [], runtimeErrors = [], blocked = [], heartbeatResults = [];
const responseWork = new Set(), heartbeatUnits = new Set();
const heartbeatSequences = new WeakMap();
const intent = {login: false, checkIn: false, start: null, introduction: null};
let journal, browser, parent, child, page, phase = 'local_check', stopRequested = false;
let heartbeatPosts = 0, browserStarts = 0, measurementWallSeconds = null;
let journalWrites = Promise.resolve();
const uuid = value => typeof value === 'string' && /^[a-f0-9]{32}$/.test(value);

class QaFailure extends Error {}
function check(value, code) { if (!value) throw new QaFailure(code); }
function digest(value) { return createHash('sha256').update(value).digest('hex'); }
function safeReason(error) {
  return error instanceof QaFailure && /^[a-z0-9_-]{1,180}$/.test(error.message)
    ? error.message : 'browser_or_local_io_operation_failed';
}
function step(value, metadata = {}) {
  phase = value;
  console.log(JSON.stringify({qa_phase: value, ...metadata}));
}
async function privateWrite(filename, body) {
  await writeFile(filename, body, {mode: 0o600});
  await chmod(filename, 0o600);
}
async function save() {
  const body = JSON.stringify(journal);
  const work = journalWrites.then(async () => {
    const temporary = journalFile + '.' + randomBytes(8).toString('hex') + '.tmp';
    try {
      await privateWrite(temporary, body);
      await rename(temporary, journalFile);
    } finally {
      await unlink(temporary).catch(error => { if (error.code !== 'ENOENT') throw error; });
    }
  });
  journalWrites = work.catch(() => {});
  await work;
}
async function readJournal() {
  try {
    const info = await lstat(journalFile);
    check(info.isFile() && !info.isSymbolicLink() && !(info.mode & 0o077),
      'private_journal_requires_a_protected_regular_file');
    return JSON.parse(await readFile(journalFile, 'utf8'));
  } catch (error) {
    if (error.code === 'ENOENT') return null;
    throw error;
  }
}
function ownDemo(demo) {
  const credentials = demo?.credentials;
  return demo?.user?.role === 'parent' && uuid(demo.user.id) &&
    demo.user.families?.length === 1 && uuid(demo.user.families[0].id) &&
    demo.user.families[0].synthetic === true && demo.user.families[0].permission === 'owner' &&
    uuid(demo.child_id) && uuid(demo.material_id) && demo.token === undefined &&
    /^eltern-[a-f0-9]{10}$/.test(credentials?.parent_username ?? '') &&
    /^kind-[a-f0-9]{10}$/.test(credentials?.child_username ?? '') &&
    credentials.parent_username.slice(7) === credentials.child_username.slice(5) &&
    typeof credentials.parent_password === 'string' && credentials.parent_password.length >= 12 &&
    typeof credentials.child_password === 'string' && credentials.child_password.length >= 12;
}
function ownedUnit(id) { return (journal.jobs ?? []).some(job => job.unit_id === id); }
function allowedBrowserMutation(method, pathname, data, choice) {
  if (method === 'GET' || method === 'HEAD') return true;
  if (method === 'POST' && pathname === '/api/auth/login') return choice.login === true;
  if (!journal?.demo || method !== 'POST') return false;
  if (pathname === '/api/children/' + journal.demo.child_id + '/day-check-in') return choice.checkIn === true;
  const start = pathname.match(/^\/api\/units\/([a-f0-9]{32})\/start$/);
  if (start) return choice.start === start[1] && ownedUnit(start[1]) &&
    !journal.start_requests?.[start[1]];
  const introduction = pathname.match(/^\/api\/units\/([a-f0-9]{32})\/introduction$/);
  if (introduction) return choice.introduction === introduction[1] && ownedUnit(introduction[1]);
  const heartbeat = pathname.match(/^\/api\/units\/([a-f0-9]{32})\/heartbeat$/);
  return Boolean(heartbeat && heartbeatUnits.has(heartbeat[1]) && (journal.heartbeat_posts_total ?? 0) < 35 &&
    data && Object.keys(data).length === 1 && typeof data.baseline === 'boolean');
}
async function browserContext(role, cookies = []) {
  const context = await browser.newContext({viewport: {width: 390, height: 844},
    isMobile: true, hasTouch: true, storageState: {cookies, origins: []}});
  context.on('page', opened => opened.on('pageerror', error => runtimeErrors.push({
    name: /^[A-Za-z]+Error$/.test(error.name) ? error.name : 'RuntimeError',
    fingerprint: digest(error.message),
  })));
  await context.route('**/api/**', async route => {
    const request = route.request(), pathname = new URL(request.url()).pathname;
    let data = null;
    try { data = request.postDataJSON(); } catch { /* Missing JSON is checked above. */ }
    if (role !== 'child' && !['GET', 'HEAD'].includes(request.method()) ||
      !allowedBrowserMutation(request.method(), pathname, data, intent)) {
      blocked.push({role, method: request.method(), path_fingerprint: digest(pathname)});
      return route.abort('blockedbyclient');
    }
    if (request.method() === 'POST') {
      if (pathname === '/api/auth/login') intent.login = false;
      else if (pathname.endsWith('/day-check-in')) intent.checkIn = false;
      else if (pathname.endsWith('/start')) {
        intent.start = null;
        browserStarts++;
        journal.start_requests ??= {};
        journal.start_requests[pathname.split('/').at(-2)] = {attempted: true};
        await save();
      }
      else if (pathname.endsWith('/introduction')) intent.introduction = null;
      else if (pathname.endsWith('/heartbeat')) {
        heartbeatPosts++;
        journal.heartbeat_posts_total = (journal.heartbeat_posts_total ?? 0) + 1;
        heartbeatSequences.set(request, journal.heartbeat_posts_total);
        // Spend the finite browser budget durably BEFORE releasing the real
        // app request. A process restart never restores a spent heartbeat.
        await save();
      }
    }
    return route.continue();
  });
  return context;
}
async function get(context, route, expected = 200) {
  const response = await context.request.get(base + '/api' + route, {maxRedirects: 0, timeout: 10000});
  check(response.status() === expected, 'authorized_api_read_failed_' + response.status());
  return expected === 200 ? response.json() : null;
}
async function put(context, route, data, expected = 200) {
  const response = await context.request.put(base + '/api' + route, {headers, data, maxRedirects: 0});
  check(response.status() === expected, 'own_api_update_failed_' + response.status());
  return expected === 200 ? response.json() : null;
}
async function overview() { return get(parent, '/children/' + journal.demo.child_id + '/overview?compact=true'); }
function validateTimePlan(plan) {
  check(plan.daily_goal_minutes === 5 && plan.weekly_goal_minutes === 5 &&
    plan.session_minutes === 5 && plan.goal_required === (journal.goal_required === true) && plan.optional_learning === true &&
    Number.isInteger(plan.daily_active_seconds) && plan.daily_active_seconds >= 0 &&
    Number.isInteger(plan.weekly_active_seconds) && plan.weekly_active_seconds >= 0 &&
    typeof plan.daily_goal_met === 'boolean' && typeof plan.weekly_goal_met === 'boolean',
    'new_actual_minimum_goal_contract_required');
  check(plan.daily_goal_met === (plan.daily_active_seconds >= 300) &&
    plan.weekly_goal_met === (plan.weekly_active_seconds >= 300),
    'goals_must_depend_on_actual_seconds_only');
}
function validateLearningTime(time, expectedRequired) {
  check(time && time.daily_goal_minutes === 5 && time.weekly_goal_minutes === 5 &&
    typeof time.goal_required === 'boolean' &&
    (expectedRequired === undefined || time.goal_required === expectedRequired) &&
    Number.isInteger(time.daily_active_seconds) &&
    time.daily_active_seconds >= 0 && Number.isInteger(time.weekly_active_seconds) &&
    time.weekly_active_seconds >= 0 &&
    time.daily_goal_met === (time.daily_active_seconds >= 300) &&
    time.weekly_goal_met === (time.weekly_active_seconds >= 300) &&
    time.daily_remaining_seconds === Math.max(0, 300 - time.daily_active_seconds),
    'unit_and_heartbeat_must_return_actual_learning_time');
}
function cleanLearningTime(time) {
  return Object.fromEntries(['daily_active_seconds', 'weekly_active_seconds',
    'daily_goal_minutes', 'weekly_goal_minutes', 'daily_goal_met', 'weekly_goal_met',
    'daily_remaining_seconds', 'goal_required'].map(key => [key, time[key]]));
}
function hasRequiredHeartbeatProgress() {
  const evidence = journal.heartbeat_evidence ?? [];
  return evidence.some(open => open.learning_time?.goal_required === true &&
    open.learning_time.daily_goal_met === false && evidence.some(met =>
      met.sequence > open.sequence && met.learning_time?.goal_required === true &&
      met.learning_time.daily_goal_met === true));
}
function validateHeartbeatEvidence() {
  const evidence = journal.heartbeat_evidence ?? [];
  const knownUnknowns = new Set(journal.time_observer_recovery?.unknown_body_sequences ?? []);
  check(Number.isInteger(journal.heartbeat_posts_total) && journal.heartbeat_posts_total <= 35 &&
    evidence.length <= journal.heartbeat_posts_total && !journal.heartbeat_evidence_error &&
    new Set(evidence.map(value => value.sequence)).size === evidence.length &&
    evidence.every(value => Number.isInteger(value.sequence) && value.sequence > 0 &&
      value.sequence <= journal.heartbeat_posts_total && value.http_status === 200 &&
      (value.unreadable ? knownUnknowns.has(value.sequence) && !value.contract_invalid
        : value.status === 'active')),
    'ordinary_ui_heartbeat_failed_or_exceeded_the_persisted_budget');
  check(hasRequiredHeartbeatProgress(),
    'ordinary_child_heartbeats_must_show_required_goal_open_then_fulfilled');
  for (const result of evidence) {
    if (!result.unreadable) validateLearningTime(result.learning_time);
  }
}
function afterGoalStartRecorded() {
  return journal.second_start?.http_status === 200 &&
    journal.start_after_goal?.validated === true &&
    journal.start_after_goal.unit_id === journal.second_unit_id && ownedUnit(journal.second_unit_id);
}
function needsChildUI() { return !journal.counter_passed || !afterGoalStartRecorded(); }
function validateSavedCounterProof() {
  check(journal.counter_passed && Number.isInteger(journal.required_goal_initial_seconds) &&
    journal.required_goal_initial_seconds >= 0 && journal.required_goal_initial_seconds < 300 &&
    Number.isInteger(journal.measurement_wall_seconds) && journal.measurement_wall_seconds <= 420 && journal.after_goal_wall_seconds >= 20 &&
    journal.after_goal_extra_seconds >= 10 && journal.actual_observations.some(value =>
      value.daily_seconds >= 310 && value.daily_goal_met && value.weekly_goal_met),
    'resume_requires_the_saved_real_bounded_actual_activity_proof');
  validateHeartbeatEvidence();
}
function pristineUnit(unit) {
  const job = (journal.jobs ?? []).find(value => value.unit_id === unit.id);
  if (job) job.provenance_verified = false;
  check(ownedUnit(unit.id) && unit.child_id === journal.demo.child_id &&
    unit.material_id === journal.demo.material_id && unit.synthetic === true &&
    unit.provider === 'synthetic' && unit.model === 'fixed-fractions-v1' &&
    unit.questions.length > 0 && unit.questions.every(question =>
      question.attempts.length === 0 && question.hints_used === 0),
    'only_own_fixed_unanswered_synthetic_units_allowed');
  job.provenance_verified = true;
}
async function zeroUsage() {
  journal.zero_external_usage_verified = false;
  const usage = await get(parent, '/families/' + journal.demo.user.families[0].id + '/usage');
  journal.observed_usage = {calls_used: usage.calls_used ?? null,
    records: Array.isArray(usage.records) ? usage.records.length : null,
    known_cost_micros_usd: usage.known_cost_micros_usd ?? null,
    unknown_cost_calls: usage.unknown_cost_calls ?? null,
    encumbered_micros_usd: usage.encumbered_micros_usd ?? null};
  await save();
  check(usage.synthetic === true && usage.calls_used === 0 && usage.records.length === 0 &&
    usage.known_cost_micros_usd === 0 && usage.unknown_cost_calls === 0 &&
    usage.encumbered_micros_usd === 0, 'external_inference_or_reservation_is_forbidden');
  const limits = digest(JSON.stringify({calls: usage.calls_limit, budget: usage.budget_micros_usd, plan: usage.plan}));
  check(!journal.limits_signature || journal.limits_signature === limits, 'financial_entitlements_must_remain_unchanged');
  journal.limits_signature = limits;
  journal.zero_external_usage_verified = true;
  await save();
}
async function accessible() {
  await page.waitForSelector('flutter-view', {timeout: 90000});
  await page.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(node => node.click()));
  await page.waitForTimeout(350);
}
async function open(route) {
  const response = await page.goto(base + route, {waitUntil: 'domcontentloaded', timeout: 90000});
  check(response?.ok() && response.url().startsWith(base + '/'), 'public_https_route_unavailable');
  await accessible();
}
function button(name) { return page.getByRole('button', {name, exact: true}); }
async function reveal(locator) {
  const target = locator.first(), size = page.viewportSize();
  for (let attempt = 0; attempt < 36; attempt++) {
    const box = await target.count() ? await target.boundingBox({timeout: 500}).catch(() => null) : null;
    if (box && box.width > 0 && box.height > 0 && box.x >= 0 && box.x + box.width <= size.width + 1 &&
      box.y >= 75 && box.y + Math.min(box.height, size.height - 200) <= size.height - 95) return target;
    await page.mouse.move(size.width - 28, size.height - 160);
    await page.mouse.wheel(0, !box && attempt === 0 ? -20000 : box && box.y < 75 ? -400 : 400);
    await page.waitForTimeout(250);
  }
  throw new QaFailure('expected_flutter_mobile_control_not_visible');
}
async function tap(locator) {
  const target = await reveal(locator), box = await target.boundingBox();
  check(box && box.height < page.viewportSize().height, 'touch_control_not_usable');
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  await page.waitForTimeout(250);
}
async function type(locator, value) {
  const field = await reveal(locator);
  await field.click({position: {x: 20, y: 20}});
  await page.waitForTimeout(250);
  await page.keyboard.press('Control+A');
  await page.keyboard.type(value, {delay: 8});
  await page.waitForTimeout(150);
  check(await field.inputValue() === value, 'actual_login_field_did_not_accept_typing');
}
async function uiResponse(method, route, action) {
  const waiting = page.waitForResponse(response => new URL(response.url()).pathname === '/api' + route &&
    response.request().method() === method, {timeout: 45000});
  waiting.catch(() => {});
  await action();
  return waiting;
}
async function shot(label) {
  check(journal.child_authenticated === true, 'never_capture_login_credentials');
  const filename = 'minimum-time-' + journal.run_id + '-' + label + '.png';
  await privateWrite(path.join(artifacts, filename), await page.screenshot());
  screenshots.push(filename);
}
async function createDemo() {
  check(!journal.demo_creation_attempted, 'never_create_a_second_demo_after_an_uncertain_response');
  step('create_one_owned_fixed_demo');
  journal.demo_creation_attempted = true;
  await save();
  const response = await parent.request.post(base + '/api/demo', {headers, maxRedirects: 0});
  check(response.status() === 201, 'fixed_demo_creation_failed_' + response.status());
  journal.demo = await response.json();
  journal.parent_cookies = await parent.cookies();
  await save();
  check(ownDemo(journal.demo), 'only_the_new_owned_fixed_demo_is_allowed');
}
async function parentIdentity() {
  let response = await parent.request.get(base + '/api/auth/me');
  if (response.status() === 401 && !journal.deleted) {
    const login = await parent.request.post(base + '/api/auth/login', {headers, maxRedirects: 0,
      data: {username: journal.demo.credentials.parent_username,
        password: journal.demo.credentials.parent_password, device: 'Minimum time QA recovery'}});
    check(login.status() === 200, 'own_parent_recovery_login_failed');
    journal.parent_cookies = await parent.cookies();
    await save();
    response = await parent.request.get(base + '/api/auth/me');
  }
  check(response.status() === 200, 'owned_parent_session_required');
  const user = await response.json();
  check(user.role === 'parent' && user.id === journal.demo.user.id && user.families?.length === 1 &&
    user.families[0].id === journal.demo.user.families[0].id && user.families[0].synthetic === true &&
    user.families[0].permission === 'owner', 'owned_parent_identity_mismatch');
}
async function prepareFixedUnits() {
  step('confirm_only_fixed_demo_source');
  let source = await get(parent, '/materials/' + journal.demo.material_id);
  check(source.child_id === journal.demo.child_id && source.synthetic === true && !source.fixture_id &&
    source.school_day_id === null && source.homework.length === 0,
    'source_must_be_the_fixed_demo_without_an_external_ai_fixture');
  if (!source.confirmed) {
    check(source.status === 'review', 'fixed_demo_source_must_be_reviewable');
    source = await put(parent, '/materials/' + source.id + '/confirm', {
      subject: source.subject, topic: source.topic, content: source.content,
      homework: source.homework, uncertainties_resolved: true,
    });
  }
  check(source.confirmed === true && source.status === 'confirmed', 'source_confirmation_not_persisted');
  journal.jobs ??= [];
  for (let index = 0; index < 2; index++) {
    step('prepare_fixed_synthetic_unit_' + (index + 1));
    if (!journal.jobs[index]) {
      journal.jobs[index] = {key: 'minimum-time-' + randomBytes(16).toString('hex'), attempted: false};
      await save();
    }
    const job = journal.jobs[index];
    if (!job.id) {
      check(!job.attempted, 'uncertain_job_submission_requires_operator_review_not_a_new_job');
      job.attempted = true;
      await save();
      const response = await parent.request.post(base + '/api/children/' + journal.demo.child_id + '/units', {
        headers: {...headers, 'Idempotency-Key': job.key}, data: {material_id: journal.demo.material_id}, maxRedirects: 0,
      });
      check(response.status() === 202, 'synthetic_unit_submission_failed_' + response.status());
      const queued = await response.json();
      check(uuid(queued.id), 'synthetic_job_id_missing');
      job.id = queued.id;
      await save();
    }
    const deadline = Date.now() + 120000;
    while (!job.unit_id && Date.now() < deadline) {
      const data = await get(parent, '/jobs/' + job.id);
      check(data.kind === 'unit' && data.status !== 'failed', 'fixed_synthetic_job_failed_without_retry');
      if (data.status === 'completed') {
        check(uuid(data.result?.unit_id), 'completed_synthetic_job_has_no_unit');
        job.unit_id = data.result.unit_id;
        await save();
        break;
      }
      check(['queued', 'running'].includes(data.status), 'unexpected_synthetic_job_status');
      await new Promise(resolve => setTimeout(resolve, 1000));
    }
    check(job.unit_id, 'fixed_synthetic_job_deadline_exceeded');
    pristineUnit(await get(parent, '/units/' + job.unit_id));
  }
  check(journal.jobs.length === 2 && new Set(journal.jobs.map(job => job.unit_id)).size === 2,
    'exactly_two_distinct_fixed_units_required');
  await zeroUsage();
}
async function configureOwnMinimumGoals() {
  step('set_owned_parent_minimum_goals_and_calendar_pause');
  const data = await overview();
  check(data.child.id === journal.demo.child_id && data.child.preferences, 'owned_child_preferences_required');
  const next = new Date(data.plan.date + 'T00:00:00Z');
  check(Number.isFinite(next.getTime()), 'server_calendar_date_required');
  next.setUTCDate(next.getUTCDate() + 1);
  journal.desired_preferences ??= {...data.child.preferences, weekdays: [], daily_minutes: 5,
    weekly_minutes: 5, session_minutes: 5, pause_until: next.toISOString().slice(0, 10)};
  if (!journal.preferences_saved) {
    await put(parent, '/children/' + journal.demo.child_id + '/preferences', journal.desired_preferences);
    journal.preferences_saved = true;
    await save();
  }
  const updated = await overview();
  validateTimePlan(updated.plan);
  check(journal.required_goal_started
    ? updated.child.preferences.weekdays.length === 7 && !updated.plan.paused &&
      updated.child.preferences.pause_until === null
    : updated.child.preferences.weekdays.length === 0 && updated.plan.paused === true &&
      updated.child.preferences.pause_until === journal.desired_preferences.pause_until,
    'owned_parent_pause_and_free_days_must_remain_configured');
  journal.school_date ??= updated.plan.date;
  await save();
}
async function loginChild() {
  step('independent_child_login_through_visible_ui');
  page = await child.newPage();
  page.on('response', response => {
    if (!/\/api\/units\/[a-f0-9]{32}\/heartbeat$/.test(new URL(response.url()).pathname) ||
      response.request().method() !== 'POST') return;
    const work = (async () => {
      let evidence;
      const sequence = heartbeatSequences.get(response.request());
      let result;
      try { result = await response.json(); }
      catch (error) {
        evidence = {sequence, http_status: response.status(), unreadable: true,
          observer_stage: 'response_body_read', error_fingerprint: digest(String(error.message))};
      }
      if (!evidence) {
        try {
          validateLearningTime(result.learning_time);
          evidence = {sequence, http_status: response.status(), status: result.status,
            baseline: response.request().postDataJSON()?.baseline === true,
            active_seconds: result.active_seconds_approx, break_recommended: result.break_recommended === true,
            learning_time: cleanLearningTime(result.learning_time)};
        } catch (error) {
          evidence = {sequence, http_status: response.status(), unreadable: true,
            contract_invalid: true, observer_stage: 'learning_time_contract', validation_code: safeReason(error)};
        }
      }
      heartbeatResults.push(evidence);
      check(Number.isInteger(sequence), 'observed_heartbeat_must_have_its_persisted_request_sequence');
      journal.heartbeat_evidence ??= [];
      check(!journal.heartbeat_evidence.some(value => value.sequence === sequence), 'heartbeat_evidence_must_not_be_replaced');
      journal.heartbeat_evidence.push(evidence);
      journal.heartbeat_evidence.sort((a, b) => a.sequence - b.sequence);
      await save();
    })().catch(async () => {
      journal.heartbeat_evidence_error = true;
      await save().catch(() => {});
    });
    responseWork.add(work);
    work.finally(() => responseWork.delete(work));
  });
  if (journal.child_authenticated) {
    const current = await child.request.get(base + '/api/auth/me', {maxRedirects: 0});
    if (current.status() === 200) {
      const identity = await current.json();
      check(identity.role === 'child' && identity.child_id === journal.demo.child_id,
        'resumed_child_cookie_must_belong_to_this_owned_demo');
      await open('/app');
      return;
    }
    check(current.status() === 401, 'resumed_child_session_read_failed');
  }
  await open('/login');
  await type(page.getByRole('textbox', {name: 'E-Mail oder Benutzername', exact: true}), journal.demo.credentials.child_username);
  await type(page.getByLabel('Passwort', {exact: true}), journal.demo.credentials.child_password);
  intent.login = true;
  const response = await uiResponse('POST', '/auth/login', () => tap(button('Anmelden')));
  check(response.status() === 200, 'independent_child_ui_login_failed');
  const identity = (await response.json()).user;
  check(identity.role === 'child' && identity.child_id === journal.demo.child_id && identity.synthetic === true,
    'child_login_identity_mismatch');
  journal.child_authenticated = true;
  journal.child_cookies = await child.cookies();
  await save();
  for (const context of [parent, child]) {
    check((await context.cookies()).some(cookie => cookie.name === 'sp_session' && cookie.secure &&
      cookie.httpOnly && cookie.sameSite === 'Strict'), 'secure_independent_session_cookie_required');
  }
  await page.waitForURL(base + '/app', {timeout: 45000});
  if (await button('Heute keine neuen Seiten').count()) {
    intent.checkIn = true;
    const checked = await uiResponse('POST', '/children/' + journal.demo.child_id + '/day-check-in',
      () => tap(button('Heute keine neuen Seiten')));
    check(checked.status() === 200, 'normal_today_without_new_pages_checkin_failed');
  }
}
async function homeProof(label) {
  for (const width of [390, 320]) {
    await page.setViewportSize({width, height: 844});
    await open('/app');
    await reveal(button('Freiwillig weiterlernen'));
    check(await button('Jetzt lernen').count() === 0, 'a_calendar_pause_must_label_learning_as_voluntary');
    await shot(label + '-home-' + width);
  }
  await page.setViewportSize({width: 390, height: 844});
}
async function requireActualMinimumGoal() {
  step('parent_requires_five_actual_minutes_after_explicit_free_day_start');
  if (!journal.required_goal_started) {
    await put(parent, '/children/' + journal.demo.child_id + '/preferences', {
      ...journal.desired_preferences, weekdays: [0, 1, 2, 3, 4, 5, 6], pause_until: null,
    });
    journal.required_goal_started = true;
    journal.goal_required = true;
    await save();
  }
  const data = await overview();
  validateTimePlan(data.plan);
  check(data.plan.goal_required && (journal.required_goal_initial_seconds !== undefined ||
    data.plan.daily_active_seconds < 300 && !data.plan.daily_goal_met),
    'required_actual_minimum_must_begin_open');
  // Read the normal unit response after the ordinary parent's preference PUT;
  // the app receives the same persisted contract on its next heartbeat.
  const unit = await get(parent, '/units/' + journal.counter_unit_id);
  validateLearningTime(unit.learning_time, true);
  journal.required_goal_initial_seconds ??= unit.learning_time.daily_active_seconds;
  await save();
}
async function openPreparedCard({second = false} = {}) {
  await open('/app');
  await tap(page.getByText('Mein Lernen', {exact: false}));
  await page.waitForURL(base + '/learn/' + journal.demo.child_id, {timeout: 45000});
  // Both fixtures have the same visible topic. Before starting, choose the
  // first genuinely unstarted card; afterwards only the second is unstarted.
  const cards = page.getByRole('button', {name: /Brüche[\s\S]*Nicht begonnen/});
  await tap(cards.first());
  await page.waitForURL(value => /^\/unit\/[a-f0-9]{32}$/.test(value.pathname), {timeout: 45000});
  const id = new URL(page.url()).pathname.split('/').at(-1);
  check(ownedUnit(id) && (!second || id !== journal.counter_unit_id), 'visible_learning_card_must_open_the_owned_prepared_unit');
  await reveal(button('Einheit starten'));
  return id;
}
async function startThroughUnitUI(id, stage) {
  intent.start = id;
  heartbeatUnits.add(id);
  const response = await uiResponse('POST', '/units/' + id + '/start', () => tap(button('Einheit starten')));
  journal[stage] = {http_status: response.status()};
  await save();
  check(response.status() === 200, 'voluntary_start_denied_' + response.status());
  const unit = await response.json();
  pristineUnit(unit);
  validateLearningTime(unit.learning_time, journal.goal_required === true);
  check(unit.status === 'active', 'voluntary_unit_did_not_become_active');
  if (stage === 'second_start') {
    check(unit.learning_time.daily_goal_met && unit.learning_time.daily_active_seconds >= 310,
      'second_explicit_start_requires_the_already_proven_actual_minimum');
    journal.start_after_goal = {unit_id: id, validated: true, http_status: 200,
      daily_active_seconds: unit.learning_time.daily_active_seconds};
    await save();
  }
  return unit;
}
async function roleProof() {
  step('check_child_and_parent_role_boundaries');
  await put(child, '/children/' + journal.demo.child_id + '/preferences', journal.desired_preferences, 403);
  await get(child, '/admin/provider', 403);
  const response = await parent.request.post(base + '/api/units/' + journal.jobs[0].unit_id + '/start',
    {headers, maxRedirects: 0});
  check(response.status() === 403, 'parent_must_not_start_a_child_activity_session');
  journal.role_checks = {child_preferences: 403, child_admin: 403, parent_child_start: 403};
  await save();
}
async function maintainRealForegroundActivity() {
  step('earn_actual_foreground_activity_without_answers');
  await page.bringToFront();
  let turn = 0, goalAt = journal.goal_seen_unix_ms ?? null, breakSeen = false;
  const started = journal.measurement_started_unix_ms;
  check(Number.isFinite(started), 'actual_measurement_start_required');
  while (Date.now() - started <= 420000) {
    check(!stopRequested, 'operator_interrupted_actual_activity');
    check(await page.evaluate(() => document.visibilityState === 'visible'), 'child_page_must_stay_actually_visible');
    const size = page.viewportSize();
    await page.mouse.move(size.width - 28, size.height - 160);
    await page.mouse.wheel(0, turn++ % 2 ? -60 : 60);
    const data = await overview();
    validateTimePlan(data.plan);
    check(data.plan.date === journal.school_date, 'school_day_changed_during_actual_activity');
    const unit = await get(parent, '/units/' + journal.counter_unit_id);
    pristineUnit(unit);
    validateLearningTime(unit.learning_time, true);
    check(Math.abs(unit.learning_time.daily_active_seconds - data.plan.daily_active_seconds) <= 25 &&
      Math.abs(unit.learning_time.weekly_active_seconds - data.plan.weekly_active_seconds) <= 25,
      'parent_overview_and_child_unit_actual_time_must_stay_current');
    check(unit.status === 'active' && unit.break_until == null, 'time_goal_or_pause_must_not_stop_the_unit');
    const seconds = data.plan.daily_active_seconds;
    check(seconds >= (journal.actual_observations.at(-1)?.daily_seconds ?? 0), 'actual_activity_must_not_go_backwards');
    const observation = {wall_seconds: Math.floor((Date.now() - started) / 1000),
      daily_seconds: seconds, weekly_seconds: data.plan.weekly_active_seconds,
      unit_seconds: unit.active_seconds_approx, daily_goal_met: data.plan.daily_goal_met,
      weekly_goal_met: data.plan.weekly_goal_met, status: unit.status,
      unit_learning_time: unit.learning_time};
    journal.actual_observations.push(observation);
    await save();
    step('actual_foreground_progress', observation);
    if (seconds >= 300 && !goalAt) {
      goalAt = Date.now();
      journal.goal_seen_unix_ms = goalAt;
      check(data.plan.daily_goal_met && data.plan.weekly_goal_met,
        'both_minimum_goals_must_be_met_after_five_actual_minutes');
      check(unit.break_recommended === true, 'five_minute_session_must_only_recommend_a_break');
      if (await page.getByText('Zeit für eine kurze Pause?', {exact: true}).count()) {
        await reveal(page.getByText('Zeit für eine kurze Pause?', {exact: true}));
        breakSeen = true;
        await shot('optional-break-after-five-minutes-390');
        if (await button('Weiterlernen').count()) await tap(button('Weiterlernen'));
      } else {
        await shot('still-active-after-five-minutes-390');
      }
      journal.break_recommendation_seen = breakSeen;
      await save();
    }
    if (goalAt && seconds >= 310 && Date.now() - goalAt >= 20000) {
      check(Date.now() - started <= 420000, 'actual_activity_deadline_exceeded');
      journal.after_goal_extra_seconds = seconds - 300;
      journal.after_goal_wall_seconds = Math.floor((Date.now() - goalAt) / 1000);
      measurementWallSeconds = Math.floor((Date.now() - started) / 1000);
      await Promise.allSettled([...responseWork]);
      validateHeartbeatEvidence();
      journal.measurement_wall_seconds = measurementWallSeconds;
      journal.counter_passed = true;
      await save();
      return;
    }
    // Real, bounded waiting. No browser timers, clocks, server timestamps or
    // heartbeat bodies are modified; the Flutter app sends its own heartbeat.
    await page.waitForTimeout(12000);
  }
  throw new QaFailure('actual_five_minute_activity_not_reached_within_420_seconds');
}
function clockLabel(seconds, minutes) {
  const total = Math.floor(seconds);
  return Math.floor(total / 60) + ':' + String(total % 60).padStart(2, '0') + ' / ' + minutes + ' Min.';
}
async function recoverSavedActualActivity() {
  step('recover_observed_actual_activity_with_independent_read_only_confirmation');
  check(recoverObservedTime && !journal.counter_passed && journal.jobs.length === 2 &&
    journal.jobs.every(job => job.id && job.unit_id) && journal.first_start?.http_status === 200 &&
    !journal.second_start && journal.child_authenticated && journal.required_goal_started,
    'recovery_is_only_for_the_existing_completed_observation_attempt');
  const filename = path.join(artifacts, 'minimum-learning-time-first-attempt.json');
  const info = await lstat(filename);
  check(info.isFile() && !info.isSymbolicLink() && !(info.mode & 0o077), 'recovery_report_must_be_protected');
  const serialized = await readFile(filename, 'utf8'), report = JSON.parse(serialized);
  const proof = report.time_proof, unknown = journal.heartbeat_evidence.filter(value => value.unreadable);
  check(report.failure === 'ordinary_ui_heartbeat_failed_or_exceeded_the_persisted_budget' &&
    report.first_start_http === 200 && report.second_start_http === null &&
    report.external_ai_usage_calls === 0 && report.synthetic_jobs === 2 &&
    report.source_commit === journal.activity_source_commit &&
    report.browser_runtime_errors.length === 0 && report.blocked_mutations.length === 0 &&
    digest(JSON.stringify(proof.observations)) === digest(JSON.stringify(journal.actual_observations)) &&
    digest(JSON.stringify(report.heartbeat_results)) === digest(JSON.stringify(journal.heartbeat_evidence)) &&
    unknown.length === 2 && unknown.every(value => value.http_status === 200 && !value.contract_invalid) &&
    Number.isInteger(proof.wall_seconds) && proof.wall_seconds <= 420 &&
    proof.continued_wall_seconds >= 20 && proof.extra_actual_seconds >= 10,
    'recovery_requires_original_real_artifacts_not_a_new_timer_or_synthetic_credit');
  const last = journal.actual_observations.at(-1), data = await overview();
  validateTimePlan(data.plan);
  const unit = await get(parent, '/units/' + journal.counter_unit_id);
  pristineUnit(unit);
  validateLearningTime(unit.learning_time, true);
  check(last.wall_seconds === proof.wall_seconds && last.daily_seconds >= 310 &&
    last.daily_goal_met && last.weekly_goal_met && unit.status === 'active' &&
    data.plan.date === journal.school_date && data.plan.daily_active_seconds >= last.daily_seconds &&
    unit.learning_time.daily_active_seconds >= last.daily_seconds && data.plan.daily_goal_met &&
    data.plan.weekly_goal_met && unit.active_seconds_approx >= last.unit_seconds,
    'normal_persisted_api_reads_must_independently_confirm_the_original_actual_credit');
  journal.time_observer_recovery = {
    partial_reconstruction: true, original_report_sha256: digest(serialized),
    unknown_body_sequences: unknown.map(value => value.sequence),
    observer_limit: 'Two original HTTP200 bodies were not captured; their body or contract cannot be reconstructed.',
    confirmed_with_normal_api_reads: true,
    confirmed_daily_seconds: data.plan.daily_active_seconds,
    confirmed_weekly_seconds: data.plan.weekly_active_seconds,
    historical_screenshots: report.screenshots,
  };
  journal.measurement_wall_seconds = proof.wall_seconds;
  journal.after_goal_wall_seconds = proof.continued_wall_seconds;
  journal.after_goal_extra_seconds = proof.extra_actual_seconds;
  validateHeartbeatEvidence();
  journal.counter_passed = true;
  await save();
}
async function assertParentLayoutFits(labels) {
  const viewport = page.viewportSize();
  const dimensions = await page.evaluate(() => ({
    viewport: window.innerWidth,
    document: document.documentElement.scrollWidth,
    body: document.body.scrollWidth,
    scroll_x: window.scrollX,
  }));
  check(dimensions.document <= dimensions.viewport + 1 &&
    dimensions.body <= dimensions.viewport + 1 && Math.abs(dimensions.scroll_x) <= 1,
    'parent_page_must_not_overflow_horizontally');
  // Flutter paints its content in a canvas; also inspect the real accessible
  // goal labels, rather than inferring a sound layout from document width.
  // The deliberately scrollable parent tab strip is not a page overflow.
  for (const label of [...new Set(labels)]) {
    const target = page.getByText(label, {exact: true}).first();
    const box = await target.boundingBox();
    check(box && box.width > 0 && box.x >= -1 && box.x + box.width <= viewport.width + 1,
      'parent_measured_goal_label_must_fit_the_viewport');
  }
  return dimensions;
}
async function parentBrowserProof() {
  step('parent_reads_measured_goals_after_both_explicit_child_starts');
  check(journal.counter_passed && journal.second_start?.http_status === 200,
    'parent_browser_must_not_interrupt_the_actual_activity_measurement');
  // The counter proof and second start have finished. End the child's page,
  // keeping its independent session for the final real revocation check.
  if (page && !page.isClosed()) await page.close();
  await Promise.allSettled([...responseWork]);
  const identity = await get(parent, '/auth/me');
  check(identity.role === 'parent' && identity.id === journal.demo.user.id,
    'parent_browser_requires_the_existing_owned_parent_session');
  page = await parent.newPage();
  await page.bringToFront();
  const views = [];
  for (const width of [1280, 390, 320]) {
    await page.setViewportSize({width, height: 844});
    for (const kind of ['family', 'child']) {
      const route = kind === 'family' ? '/app' : '/child/' + journal.demo.child_id;
      const apiRoute = kind === 'family'
        ? '/families/' + journal.demo.user.families[0].id
        : '/children/' + journal.demo.child_id + '/overview';
      const response = await uiResponse('GET', apiRoute, () => open(route));
      check(response.status() === 200 && new URL(page.url()).pathname === route,
        'normal_parent_browser_route_must_load_with_its_own_cookie');
      const payload = await response.json();
      const time = kind === 'family'
        ? payload.children?.find(value => value.id === journal.demo.child_id)?.learning_time
        : payload.plan;
      if (kind === 'family') validateLearningTime(time, true);
      else validateTimePlan(time);
      check(time.daily_active_seconds >= 310 && time.daily_goal_met && time.weekly_goal_met,
        'parent_browser_must_read_fulfilled_actual_minimum_goals');
      const daily = clockLabel(time.daily_active_seconds, time.daily_goal_minutes);
      const weekly = clockLabel(time.weekly_active_seconds, time.weekly_goal_minutes);
      const labels = [daily, weekly, 'Tagesziel erfüllt', 'Wochenziel erfüllt'];
      for (const label of [...new Set(labels)]) {
        await reveal(page.getByText(label, {exact: true}));
      }
      check(daily !== weekly || await page.getByText(daily, {exact: true}).count() >= 2,
        'both_parent_period_counters_must_be_rendered');
      check(await page.getByText('Tagesziel offen', {exact: true}).count() === 0 &&
        await page.getByText('Wochenziel offen', {exact: true}).count() === 0,
        'parent_goal_labels_must_match_stored_actual_completion');
      const layout = await assertParentLayoutFits(labels);
      await shot('parent-' + kind + '-fulfilled-' + width);
      views.push({view: kind, width, daily_seconds: time.daily_active_seconds,
        weekly_seconds: time.weekly_active_seconds, daily_goal_met: true,
        weekly_goal_met: true, horizontal_overflow: false, layout});
      journal.parent_ui = {passed: false, views};
      await save();
    }
  }
  journal.parent_ui = {passed: true, views};
  await save();
}
async function run() {
  const health = await get(parent, '/health');
  journal.source_commit = health.source_commit ?? null;
  journal.activity_source_commit ??= journal.source_commit;
  if (!journal.demo) await createDemo();
  check(ownDemo(journal.demo), 'owned_fixed_demo_required');
  await parentIdentity();
  await zeroUsage();
  if (recoverObservedTime && !journal.counter_passed) await recoverSavedActualActivity();
  const needChild = needsChildUI();
  if (journal.counter_passed) validateSavedCounterProof();
  if (needChild) {
    await prepareFixedUnits();
    await configureOwnMinimumGoals();
    await loginChild();
    if (!journal.role_checks) await roleProof();
  } else {
    step('resume_saved_counter_and_second_start_with_parent_reads_only');
    check(journal.child_authenticated && journal.role_checks,
      'parent_only_resume_requires_the_original_ui_login_and_role_proofs');
  }
  if (!journal.counter_passed) {
    if (!journal.counter_unit_id) {
      await homeProof('before');
      const id = await openPreparedCard();
      journal.counter_unit_id = id;
      journal.actual_observations ??= [];
      await save();
      const unit = await startThroughUnitUI(id, 'first_start');
      journal.measurement_started_unix_ms ??= Date.now();
      await save();
      if (!unit.introduction_seen) {
        intent.introduction = id;
        const response = await uiResponse('POST', '/units/' + id + '/introduction',
          () => tap(button('Weiter zu den Übungen')));
        check(response.status() === 200, 'explicit_unit_introduction_failed');
      }
    } else {
      check(journal.first_start?.http_status === 200, 'resume_requires_a_recorded_successful_ui_start');
      heartbeatUnits.add(journal.counter_unit_id);
      await open('/unit/' + journal.counter_unit_id);
      check((await get(parent, '/units/' + journal.counter_unit_id)).status === 'active',
        'resume_never_restarts_or_modifies_a_stopped_unit');
    }
    await requireActualMinimumGoal();
    await maintainRealForegroundActivity();
  }
  if (needChild) await homeProof('after');
  if (!afterGoalStartRecorded()) {
    step('start_other_prepared_unit_after_the_actual_goal');
    let id = journal.second_unit_id;
    if (!id) {
      id = await openPreparedCard({second: true});
      journal.second_unit_id = id;
      await save();
    } else {
      check(!journal.second_start && !journal.start_requests?.[id],
        'never_repeat_an_attempted_second_start_after_an_uncertain_response');
      const existing = await get(parent, '/units/' + id);
      pristineUnit(existing);
      check(existing.status === 'not_started', 'resume_may_only_start_the_still_unstarted_second_unit');
      await open('/unit/' + id);
      await reveal(button('Einheit starten'));
    }
    await startThroughUnitUI(id, 'second_start');
    await shot('second-voluntary-unit-active-390');
  }
  const final = await overview();
  validateTimePlan(final.plan);
  check(final.plan.daily_active_seconds >= 310 && final.plan.daily_goal_met && final.plan.weekly_goal_met,
    'final_actual_minimum_goal_proof_missing');
  for (const job of journal.jobs) pristineUnit(await get(parent, '/units/' + job.unit_id));
  check((await get(parent, '/units/' + journal.second_unit_id)).status === 'active' &&
    journal.first_start?.http_status === 200 && journal.second_start?.http_status === 200,
    'both_explicit_prepared_unit_starts_must_succeed');
  await parentBrowserProof();
  await zeroUsage();
  await Promise.allSettled([...responseWork]);
  check(blocked.length === 0 && runtimeErrors.length === 0, 'unexpected_browser_mutation_or_runtime_error');
  validateSavedCounterProof();
}
async function cleanup() {
  check(ownDemo(journal.demo), 'cleanup_is_limited_to_the_owned_fixed_demo');
  step('normal_own_family_deletion_and_session_invalidation');
  for (const context of [parent, child]) {
    await Promise.all(context.pages().map(opened => opened.close()));
  }
  if (!journal.deleted) {
    await parentIdentity();
    const response = await parent.request.delete(base + '/api/account', {headers,
      data: {password: journal.demo.credentials.parent_password}, maxRedirects: 0});
    check(response.status() === 200, 'normal_own_family_cleanup_failed');
    journal.deleted = true;
    await save();
  }
  await get(parent, '/auth/me', 401);
  await get(child, '/auth/me', 401);
  journal.sessions_invalidated = true;
  await save();
}
function localChecks() {
  const before = journal;
  journal = {demo: {child_id: 'a'.repeat(32)}, jobs: [{unit_id: 'b'.repeat(32)}]};
  assert.equal(allowedBrowserMutation('POST', '/api/children/' + 'a'.repeat(32) + '/units', {}, {}), false);
  assert.equal(allowedBrowserMutation('POST', '/api/units/' + 'b'.repeat(32) + '/questions/sum/answer', {}, {}), false);
  assert.equal(allowedBrowserMutation('POST', '/api/units/' + 'b'.repeat(32) + '/start', {}, {start: 'b'.repeat(32)}), true);
  assert.equal(allowedBrowserMutation('POST', '/api/units/' + 'c'.repeat(32) + '/start', {}, {start: 'c'.repeat(32)}), false);
  assert.equal(allowedBrowserMutation('POST', '/api/units/' + 'b'.repeat(32) + '/heartbeat', {baseline: false}, {}), false);
  heartbeatUnits.add('b'.repeat(32));
  assert.equal(allowedBrowserMutation('POST', '/api/units/' + 'b'.repeat(32) + '/heartbeat', {baseline: false}, {}), true);
  assert.equal(allowedBrowserMutation('POST', '/api/units/' + 'b'.repeat(32) + '/heartbeat', {baseline: false, seconds: 300}, {}), false);
  journal.heartbeat_posts_total = 35;
  assert.equal(allowedBrowserMutation('POST', '/api/units/' + 'b'.repeat(32) + '/heartbeat', {baseline: false}, {}), false);
  journal.start_requests = {['b'.repeat(32)]: {attempted: true}};
  assert.equal(allowedBrowserMutation('POST', '/api/units/' + 'b'.repeat(32) + '/start', {}, {start: 'b'.repeat(32)}), false);
  journal.counter_passed = true;
  journal.second_unit_id = 'b'.repeat(32);
  journal.second_start = {http_status: 200};
  journal.start_after_goal = {unit_id: 'b'.repeat(32), validated: true};
  assert.equal(needsChildUI(), false);
  delete journal.start_after_goal;
  assert.equal(needsChildUI(), true);
  const learningTime = seconds => ({daily_active_seconds: seconds, weekly_active_seconds: seconds,
    daily_goal_minutes: 5, weekly_goal_minutes: 5, daily_goal_met: seconds >= 300,
    weekly_goal_met: seconds >= 300, daily_remaining_seconds: Math.max(0, 300 - seconds), goal_required: true});
  journal.heartbeat_posts_total = 2;
  journal.heartbeat_evidence = [
    {sequence: 1, http_status: 200, status: 'active', learning_time: learningTime(20)},
    {sequence: 2, http_status: 200, status: 'active', learning_time: learningTime(320)},
  ];
  validateHeartbeatEvidence();
  journal.heartbeat_evidence.reverse();
  validateHeartbeatEvidence();
  journal.heartbeat_evidence[0].sequence = 0;
  assert.throws(validateHeartbeatEvidence, QaFailure);
  assert.equal(safeReason(new Error('private value')), 'browser_or_local_io_operation_failed');
  assert.equal(clockLabel(319, 5), '5:19 / 5 Min.');
  assert.equal(clockLabel(720, 20), '12:00 / 20 Min.');
  heartbeatUnits.clear();
  journal = before;
}
async function main() {
  localChecks();
  if (mode === '--check' || mode === '--help') {
    console.log(JSON.stringify({qa_driver: 'minimum_learning_time', local_guard_checks: 'passed', public_requests: 0,
      run_only_after_deployment_go: 'node qa/minimum_learning_time.mjs --run',
      cleanup_recovery: 'node qa/minimum_learning_time.mjs --cleanup-only',
      explicit_observer_recovery: 'node qa/minimum_learning_time.mjs --run --recover-observed-time',
      recovery_requires_existing_owned_journal: true, maximum_persisted_ui_heartbeats: 35,
      actual_activity_deadline_seconds: 420, external_ai_allowed: false, maximum_synthetic_jobs: 2}));
    return;
  }
  check(['--run', '--cleanup-only'].includes(mode), 'use_check_run_or_cleanup_only');
  await mkdir(artifacts, {recursive: true});
  journal = await readJournal();
  if (!journal) {
    check(mode === '--run', 'cleanup_requires_the_private_owned_journal');
    check(!recoverObservedTime, 'observer_recovery_never_creates_a_new_account_or_journal');
    journal = {purpose: 'minimum-learning-time-fixed-demo-only', version: 1,
      run_id: new Date().toISOString().replace(/[-:.]/g, ''), jobs: [], actual_observations: []};
    await save();
  } else {
    check(journal.purpose === 'minimum-learning-time-fixed-demo-only' && journal.version === 1 &&
      Array.isArray(journal.jobs) && journal.jobs.length <= 2 && (!journal.demo || ownDemo(journal.demo)),
      'only_this_protected_owned_demo_journal_can_be_resumed');
  }
  journal.heartbeat_posts_total ??= 0;
  journal.heartbeat_evidence ??= [];
  check(Number.isInteger(journal.heartbeat_posts_total) && journal.heartbeat_posts_total >= 0 &&
    journal.heartbeat_posts_total <= 35 && Array.isArray(journal.heartbeat_evidence) &&
    journal.heartbeat_evidence.length <= journal.heartbeat_posts_total,
    'private_journal_heartbeat_budget_is_invalid');
  await save();
  let passed = false, failure = null, failedPhase = null;
  process.once('SIGINT', () => { stopRequested = true; });
  process.once('SIGTERM', () => { stopRequested = true; });
  try {
    browser = await chromium.launch({headless: true, executablePath: process.env.CHROME_PATH || '/opt/google/chrome/chrome',
      args: ['--no-sandbox'], timeout: 15000});
    parent = await browserContext('parent', journal.parent_cookies ?? []);
    child = await browserContext('child', journal.child_cookies ?? []);
    if (mode === '--run') {
      check(!journal.deleted, 'deleted_qa_family_cannot_be_recreated_by_resume');
      await run();
    }
    await cleanup();
    passed = true;
  } catch (error) {
    failure = safeReason(error);
    failedPhase = phase;
    // Keep only this protected owned journal for diagnosis/explicit cleanup.
    // Never create another family or silently rerun work after a failure.
  } finally {
    if (browser) await browser.close();
    await Promise.allSettled([...responseWork]);
    await journalWrites;
    const report = {url: base, source_commit: journal.source_commit ?? null, mode,
      qa_passed: passed, failure, failed_phase: failedPhase,
      cleanup_complete: journal.deleted === true && journal.sessions_invalidated === true,
      family_created: Boolean(journal.demo), family_deleted: journal.deleted === true,
      own_child_ui_login: journal.child_authenticated === true,
      synthetic_jobs: journal.jobs.filter(job => job.id).length,
      fixed_units: journal.jobs.filter(job => job.unit_id).length,
      fixed_unit_provenance: journal.jobs.length === 2 && journal.jobs.every(job =>
        job.unit_id && job.provenance_verified === true) ? 'synthetic' : null,
      external_ai_usage_calls: journal.observed_usage?.calls_used ?? null,
      zero_external_usage_verified: journal.zero_external_usage_verified === true,
      observed_usage: journal.observed_usage ?? null,
      time_proof: {observations: journal.actual_observations,
        source_commit: journal.activity_source_commit ?? null,
        wall_seconds: measurementWallSeconds ?? journal.measurement_wall_seconds ?? null,
        required_goal_initial_seconds: journal.required_goal_initial_seconds ?? null,
        extra_actual_seconds: journal.after_goal_extra_seconds ?? null,
        continued_wall_seconds: journal.after_goal_wall_seconds ?? null,
        optional_break_seen: journal.break_recommendation_seen ?? false},
      first_start_http: journal.first_start?.http_status ?? null,
      second_start_http: journal.second_start?.http_status ?? null,
      parent_ui: journal.parent_ui ?? null,
      role_checks: journal.role_checks ?? null, browser_starts_this_run: browserStarts,
      ordinary_ui_heartbeats_this_run: heartbeatPosts,
      ordinary_ui_heartbeats_total: journal.heartbeat_posts_total,
      unobserved_ui_heartbeat_requests: journal.heartbeat_posts_total - journal.heartbeat_evidence.length,
      heartbeat_body_observation_complete: journal.heartbeat_evidence.every(value => !value.unreadable) &&
        journal.heartbeat_evidence.length === journal.heartbeat_posts_total,
      heartbeat_observer_limitation: journal.time_observer_recovery ?? null,
      heartbeat_results_this_run: heartbeatResults, heartbeat_results: journal.heartbeat_evidence,
      blocked_mutations: blocked, browser_runtime_errors: runtimeErrors, screenshots,
      operator_cleanup_if_needed: 'node qa/minimum_learning_time.mjs --cleanup-only',
      completed: new Date().toISOString()};
    await privateWrite(reportFile, JSON.stringify(report, null, 2));
    await privateWrite(path.join(artifacts, 'minimum-time-' + journal.run_id + '-result.json'), JSON.stringify(report, null, 2));
    if (report.cleanup_complete) await unlink(journalFile);
    console.log(JSON.stringify(report));
    if (!passed) process.exitCode = 1;
  }
}
main().catch(error => {
  console.log(JSON.stringify({qa_passed: false, phase, failure: safeReason(error)}));
  process.exitCode = 1;
});
