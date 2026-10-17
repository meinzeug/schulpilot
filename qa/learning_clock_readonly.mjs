// Read-only follow-up for the Web clock rendering regression. Explicit GO only.
// Borrow exactly the home-entry agent's existing owned fixed demo session.
// Never create/login/start/pause/heartbeat/answer/generate/delete an account.
// The owning agent retains its private journal and handles normal cleanup.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {chmod, lstat, readFile, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright';

const base = 'https://schulpilot.dorfspy.de';
const artifacts = fileURLToPath(new URL('../artifacts/', import.meta.url));
const journalFile = path.join(artifacts, '.learning-room-home-qa.json');
const reportFile = path.join(artifacts, 'learning-clock-readonly-result.json');
const mode = process.argv[2] ?? '--check';
const widths = [320, 390, 1280];
const blocked = [], errors = [], screenshots = [], observations = [];
const uuid = value => typeof value === 'string' && /^[a-f0-9]{32}$/.test(value);
const digest = value => createHash('sha256').update(value).digest('hex');
let browser, sourceCommit = null, phase = 'offline_checks';

class QaFailure extends Error {}
function check(value, code) { if (!value) throw new QaFailure(code); }
function failure(error) {
  return error instanceof QaFailure && /^[a-z0-9_-]{1,180}$/.test(error.message)
    ? error.message : 'read_only_browser_or_local_io_failed';
}
function readonly(method, url) {
  return ['GET', 'HEAD'].includes(method) && new URL(url).origin === base;
}
function clock(seconds) {
  check(Number.isSafeInteger(seconds) && seconds >= 0, 'clock_requires_saved_nonnegative_integer_seconds');
  return Math.floor(seconds / 60) + ':' + String(seconds % 60).padStart(2, '0');
}
function validJournal(value) {
  const demo = value?.demo, family = demo?.user?.families;
  return value?.purpose === 'child-learning-entry-fixed-demo-only' && value.version === 1 &&
    value.deleted !== true && value.child_authenticated === true &&
    uuid(value.job?.unit_id) && demo?.user?.role === 'parent' && uuid(demo.user.id) &&
    uuid(demo.child_id) && uuid(demo.material_id) && family?.length === 1 &&
    uuid(family[0].id) && family[0].synthetic === true && family[0].permission === 'owner' &&
    Array.isArray(value.parent_cookies) && Array.isArray(value.child_cookies);
}
function timeSnapshot(unit) {
  const time = unit.learning_time;
  check(time && Number.isSafeInteger(time.daily_active_seconds) && time.daily_active_seconds >= 0 &&
    Number.isSafeInteger(time.daily_goal_minutes) && time.daily_goal_minutes >= 5 &&
    Number.isSafeInteger(unit.active_seconds_approx) && unit.active_seconds_approx >= 0 &&
    typeof time.goal_required === 'boolean' && typeof time.daily_goal_met === 'boolean' &&
    time.daily_goal_met === (time.daily_active_seconds >= time.daily_goal_minutes * 60),
    'saved_learning_time_contract_invalid');
  return {daily_active_seconds: time.daily_active_seconds, daily_goal_minutes: time.daily_goal_minutes,
    daily_goal_met: time.daily_goal_met, goal_required: time.goal_required,
    unit_active_seconds: unit.active_seconds_approx};
}
function unchangedDigest(unit) {
  return digest(JSON.stringify({status: unit.status, completed: unit.completed,
    active: unit.active_seconds_approx, pending: unit.pending_feedback,
    questions: unit.questions.map(q => ({id: q.id, attempts: q.attempts, hints_used: q.hints_used}))}));
}
function zeroUsage(value) {
  check(value.synthetic === true && value.calls_used === 0 && value.records?.length === 0 &&
    value.known_cost_micros_usd === 0 && value.unknown_cost_calls === 0 && value.encumbered_micros_usd === 0,
    'external_inference_or_reservation_not_allowed');
  return digest(JSON.stringify([value.calls_limit, value.budget_micros_usd, value.plan]));
}
async function privateWrite(filename, body) {
  await writeFile(filename, body, {mode: 0o600});
  await chmod(filename, 0o600);
}
async function context(cookies) {
  const result = await browser.newContext({viewport: {width: 390, height: 844}, hasTouch: true,
    storageState: {cookies, origins: []}});
  result.on('page', page => {
    page.on('pageerror', error => errors.push({kind: 'runtime', fingerprint: digest(error.message)}));
    page.on('console', message => {
      if (/RenderFlex overflowed|EXCEPTION CAUGHT BY RENDERING/i.test(message.text())) {
        errors.push({kind: 'layout', fingerprint: digest(message.text())});
      }
    });
  });
  await result.route('**/api/**', async route => {
    const request = route.request();
    if (!readonly(request.method(), request.url())) {
      blocked.push({method: request.method(), path_fingerprint: digest(new URL(request.url()).pathname)});
      return route.abort('blockedbyclient');
    }
    return route.continue();
  });
  return result;
}
async function get(ctx, route) {
  const response = await ctx.request.get(base + '/api' + route, {maxRedirects: 0, timeout: 15000});
  check(response.status() === 200, 'existing_owned_session_read_failed_' + response.status());
  return response.json();
}
async function visible(page, text) {
  const target = page.getByText(text, {exact: true}).first();
  await target.waitFor({state: 'visible', timeout: 45000});
  const box = await target.boundingBox();
  check(box && box.x >= 0 && box.y >= 0 && box.x + box.width <= page.viewportSize().width + 2 &&
    box.y + box.height <= page.viewportSize().height, 'saved_clock_label_not_visible_inside_the_viewport');
}
async function run() {
  phase = 'validate_existing_private_owned_journal';
  const info = await lstat(journalFile);
  check(info.isFile() && !info.isSymbolicLink() && !(info.mode & 0o077), 'existing_journal_requires_private_file_mode');
  const journal = JSON.parse(await readFile(journalFile, 'utf8'));
  check(validJournal(journal), 'only_the_handed_over_existing_home_demo_is_allowed');
  const originalJournalDigest = digest(await readFile(journalFile));
  const demo = journal.demo, id = journal.job.unit_id;
  browser = await chromium.launch({headless: true, executablePath: process.env.CHROME_PATH || '/opt/google/chrome/chrome',
    args: ['--no-sandbox'], timeout: 15000});
  const parent = await context(journal.parent_cookies), child = await context(journal.child_cookies);
  const [owner, pupil, health, original] = await Promise.all([
    get(parent, '/auth/me'), get(child, '/auth/me'), get(parent, '/health'), get(parent, '/units/' + id),
  ]);
  sourceCommit = health.source_commit ?? null;
  check(owner.id === demo.user.id && owner.role === 'parent' && owner.families?.length === 1 &&
    owner.families[0].id === demo.user.families[0].id && owner.families[0].synthetic === true &&
    owner.families[0].permission === 'owner' && pupil.role === 'child' && pupil.child_id === demo.child_id &&
    pupil.synthetic === true, 'existing_parent_and_child_sessions_must_match_the_owned_demo');
  check(original.id === id && original.child_id === demo.child_id && original.synthetic === true &&
    original.provider === 'synthetic' && original.material_id === demo.material_id &&
    ['not_started', 'paused', 'completed'].includes(original.status),
    'read_only_clock_check_requires_a_nonactive_owned_fixed_unit');
  const snapshot = timeSnapshot(original), originalDigest = unchangedDigest(original);
  check(snapshot.goal_required, 'this_regression_requires_an_existing_positive_daily_minimum');
  const overview = await get(child, '/children/' + demo.child_id + '/overview?compact=true');
  check(overview.child?.id === demo.child_id && overview.plan.daily_goal_minutes === snapshot.daily_goal_minutes &&
    overview.plan.daily_active_seconds === snapshot.daily_active_seconds,
    'unit_and_overview_must_agree_on_saved_time_and_goal');
  const usageRoute = '/families/' + demo.user.families[0].id + '/usage';
  const originalLimits = zeroUsage(await get(parent, usageRoute));
  const page = await child.newPage();
  const now = new Date().toISOString().replace(/[-:.]/g, '');
  phase = 'compare_real_web_clock_with_saved_server_seconds';
  for (const width of widths) {
    await page.setViewportSize({width, height: 844});
    const response = await page.goto(base + '/unit/' + id, {waitUntil: 'domcontentloaded', timeout: 90000});
    check(response?.ok(), 'public_unit_direct_link_failed');
    await page.waitForSelector('flutter-view', {timeout: 90000});
    await page.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(node => node.click()));
    const expectedDay = 'Heute ' + clock(snapshot.daily_active_seconds) + ' / ' + clock(snapshot.daily_goal_minutes * 60);
    const expectedUnit = 'Diese Einheit ' + clock(snapshot.unit_active_seconds);
    await visible(page, expectedDay);
    await visible(page, expectedUnit);
    if (!snapshot.daily_goal_met) {
      const remaining = clock(snapshot.daily_goal_minutes * 60 - snapshot.daily_active_seconds);
      await visible(page, original.status === 'completed'
        ? 'Tagesziel noch offen · Noch ' + remaining + ' Min.' : 'Noch ' + remaining + ' Min.');
    }
    check(await page.getByText('Heute 0:00 / 0:00', {exact: true}).count() === 0,
      'web_clock_must_not_zero_a_positive_saved_daily_goal');
    const filename = 'learning-clock-readonly-' + now + '-' + width + '.png';
    await privateWrite(path.join(artifacts, filename), await page.screenshot());
    screenshots.push(filename);
    observations.push({width, saved_time: snapshot, correct_day_label: true, correct_unit_label: true});
  }
  await page.close();
  const after = await get(parent, '/units/' + id);
  check(unchangedDigest(after) === originalDigest && JSON.stringify(timeSnapshot(after)) === JSON.stringify(snapshot),
    'read_only_browser_must_not_change_answers_status_or_activity');
  check(zeroUsage(await get(parent, usageRoute)) === originalLimits, 'tariff_or_cost_limits_changed');
  check(digest(await readFile(journalFile)) === originalJournalDigest, 'borrowed_private_journal_must_remain_unchanged');
  check(blocked.length === 0 && errors.length === 0, 'unexpected_browser_mutation_or_runtime_error');
}
async function main() {
  assert.equal(readonly('GET', base + '/api/units/' + 'a'.repeat(32)), true);
  assert.equal(readonly('POST', base + '/api/units/' + 'a'.repeat(32) + '/heartbeat'), false);
  assert.equal(readonly('PUT', base + '/api/admin/provider'), false);
  assert.equal(readonly('GET', 'https://example.invalid/api/auth/me'), false);
  assert.equal(clock(1200), '20:00');
  assert.equal(clock(1259), '20:59');
  assert.equal(clock(0), '0:00');
  assert.throws(() => clock(-1), QaFailure);
  if (mode === '--check') {
    console.log(JSON.stringify({driver: 'learning_clock_readonly', offline_checks: 'passed', public_requests: 0,
      existing_owned_home_demo_required: true, allowed_methods: ['GET', 'HEAD'], widths,
      run_after_explicit_handover_and_deployment_go: 'node qa/learning_clock_readonly.mjs --run'}));
    return;
  }
  check(mode === '--run', 'use_check_or_run_after_explicit_handover');
  let passed = false, error = null;
  try {
    await run();
    passed = true;
  } catch (value) {
    error = failure(value);
  } finally {
    if (browser) await browser.close();
    const report = {driver: 'learning_clock_readonly', url: base, qa_passed: passed, failure: error, phase,
      source_commit: sourceCommit, observations, screenshots, blocked_mutations: blocked, runtime_errors: errors,
      new_families: 0, new_jobs: 0, child_answers_submitted: 0, explicit_activity_mutations: 0,
      borrowed_journal_unchanged: passed, existing_family_cleanup: 'retained_for_the_owning_agent',
      completed: new Date().toISOString()};
    await privateWrite(reportFile, JSON.stringify(report, null, 2));
    console.log(JSON.stringify(report));
    if (!passed) process.exitCode = 1;
  }
}
main().catch(error => {
  console.log(JSON.stringify({qa_passed: false, phase, failure: failure(error)}));
  process.exitCode = 1;
});
