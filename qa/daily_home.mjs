// Public HTTPS browser acceptance after scripts/public_daily_routine_smoke.py.
// Run ONLY after Root's deployment + exclusive artificial-account handoff.
// No AI requests, source edits, answers, hints, account creation or cleanup.
// At most one already prepared unit is explicitly started through the UI.
// node qa/daily_home.mjs --check-inputs   (local only, no network)
// node qa/daily_home.mjs --run            (after the explicit handoff)
import {chromium} from 'playwright';
import {createHash} from 'node:crypto';
import {chmod, lstat, readFile, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const artifacts = fileURLToPath(new URL('../artifacts/', import.meta.url));
const accountFile = path.join(artifacts, '.school-day-qa-account.json');
const reportFile = path.join(artifacts, 'daily-home-browser-result.json');
const base = 'https://schulpilot.dorfspy.de';
const mode = process.argv[2] ?? '--help';
const errors = [], blocked = [], screenshots = [];
let account, browser, child, parent, childPage, parentPage;
let phase = 'local_inputs', allowStart = false, unitStartPosts = 0;
let unitStartExpected = null, baseline = null;
const preparedIds = new Set();
const authenticated = new Set();

class QaFailure extends Error {}
function check(value, code) { if (!value) throw new QaFailure(code); }
function digest(value) { return createHash('sha256').update(value).digest('hex'); }
function reason(error) {
  return error instanceof QaFailure && /^[a-z0-9_-]{1,180}$/.test(error.message)
    ? error.message : 'browser_or_local_io_operation_failed';
}
function step(value) { phase = value; console.log(JSON.stringify({qa_phase: phase})); }
async function privateWrite(filename, data) {
  await writeFile(filename, data, {mode: 0o600});
  await chmod(filename, 0o600);
}
async function inputs() {
  const info = await lstat(accountFile);
  check(info.isFile() && !info.isSymbolicLink() && (info.mode & 0o077) === 0,
    'private_artificial_account_must_be_protected');
  account = JSON.parse(await readFile(accountFile, 'utf8'));
  check(account.normal_account === true && account.verified === true &&
    account.user?.role === 'parent' && account.user.families?.length === 1 &&
    account.user.families[0].synthetic === false &&
    /\+schulpilot-normal-qa-[a-f0-9]{12}@(?:gmail|googlemail)\.com$/i.test(account.credentials?.parent_username ?? '') &&
    account.credentials?.child_username?.startsWith('normal-child-') &&
    account.credentials?.parent_password && account.credentials?.child_password && account.child_id,
    'only_the_prepared_owned_normal_artificial_family_is_allowed');
}
async function get(context, route) {
  const response = await context.request.get(base + '/api' + route);
  check(response.status() === 200, 'authorized_api_read_failed_' + response.status());
  return response.json();
}
async function usage() { return get(parent, '/families/' + account.user.families[0].id + '/usage'); }
function usageSignature(value) {
  return digest(JSON.stringify({calls: value.calls_used, known: value.known_cost_micros_usd,
    unknown: value.unknown_cost_calls, records: value.records.map(row => [row.id, row.status, row.cost_micros_usd])}));
}
function validatePlan(plan) {
  check(Array.isArray(plan.week) && plan.week.length === 7 && plan.week[0].date === plan.date,
    'actual_seven_day_proposal_required');
  check(Number.isFinite(plan.planned_minutes) && plan.planned_minutes >= 0 &&
    plan.planned_minutes <= plan.available_minutes && plan.planned_minutes <= plan.daily_limit_minutes,
    'today_portion_exceeds_actual_available_time');
  const weeks = new Map();
  for (const [index, day] of plan.week.entries()) {
    const date = new Date(plan.date + 'T00:00:00Z');
    date.setUTCDate(date.getUTCDate() + index);
    check(day.date === date.toISOString().slice(0, 10) && day.planned_minutes >= 0 &&
      day.planned_minutes <= plan.daily_limit_minutes &&
      (!(day.free_day || day.paused) || day.planned_minutes === 0),
      'proposal_violates_date_daily_or_pause_bounds');
    date.setUTCDate(date.getUTCDate() - (date.getUTCDay() + 6) % 7);
    const monday = date.toISOString().slice(0, 10);
    weeks.set(monday, (weeks.get(monday) ?? 0) + day.planned_minutes);
  }
  for (const [index, minutes] of [...weeks.values()].entries()) {
    // A seven-day horizon can cross a calendar-week boundary. Each week has
    // its own limit; the current one additionally retains prior consumption.
    check(minutes <= (index === 0 ? plan.weekly_remaining_minutes : plan.weekly_limit_minutes),
      'proposal_exceeds_remaining_calendar_week_limit');
  }
}
function answerSignature(units) {
  check(units.every(unit => unit.child_id === account.child_id && unit.synthetic === false),
    'only_own_prepared_artificial_source_units_are_allowed');
  return digest(JSON.stringify(units.map(unit => ({id: unit.id, questions: unit.questions.map(question => ({
    id: question.id, attempts: question.attempts, hints_used: question.hints_used,
  })), coaching: unit.coaching?.status}))));
}
async function requestGuard(route, role) {
  const request = route.request();
  if (request.method() === 'GET' || request.method() === 'HEAD') return route.continue();
  const pathname = new URL(request.url()).pathname;
  if (request.method() === 'POST' && pathname === '/api/auth/login') return route.continue();
  const start = pathname.match(/^\/api\/units\/([^/]+)\/start$/);
  if (role === 'child' && request.method() === 'POST' && start &&
    allowStart && unitStartPosts === 0 && preparedIds.has(start[1]) && start[1] === unitStartExpected) {
    allowStart = false;
    unitStartPosts++;
    return route.continue();
  }
  const heartbeat = pathname.match(/^\/api\/units\/([^/]+)\/heartbeat$/);
  if (role === 'child' && request.method() === 'POST' && heartbeat && preparedIds.has(heartbeat[1])) {
    return route.continue();
  }
  // Guard actual network requests; never fabricate a successful API response.
  // Any unexpected mutation fails this scenario, protecting against hidden AI.
  blocked.push({role, method: request.method(), action: pathname.split('/').at(-1)});
  return route.abort('blockedbyclient');
}
async function accessible(page) {
  await page.waitForSelector('flutter-view', {timeout: 90000});
  await page.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(node => node.click()));
  await page.waitForTimeout(350);
}
async function open(page, route) {
  const response = await page.goto(base + route, {waitUntil: 'domcontentloaded', timeout: 90000});
  check(response && response.ok() && response.url().startsWith(base), 'public_https_route_failed');
  await accessible(page);
}
async function top(page) {
  const size = page.viewportSize();
  await page.mouse.move(size.width - 28, size.height - 150);
  await page.mouse.wheel(0, -20000);
  await page.waitForTimeout(300);
}
async function reveal(page, locator) {
  const control = locator.first(), size = page.viewportSize();
  for (let attempt = 0; attempt < 36; attempt++) {
    const box = await control.count() ? await control.boundingBox({timeout: 500}).catch(() => null) : null;
    if (box && box.width > 0 && box.height > 0 && box.x >= 0 && box.x + box.width <= size.width + 1 &&
      box.y >= 75 && box.y + Math.min(box.height, size.height - 200) <= size.height - 95) return control;
    await page.mouse.move(size.width - 28, size.height - 160);
    await page.mouse.wheel(0, !box && attempt === 0 ? -20000 : box && box.y < 75 ? -400 : 400);
    await page.waitForTimeout(250);
  }
  throw new QaFailure('expected_responsive_text_or_control_not_visible');
}
async function tap(page, locator) {
  const control = await reveal(page, locator), box = await control.boundingBox();
  check(box && box.height < page.viewportSize().height, 'touch_control_has_no_usable_bounds');
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  await page.waitForTimeout(250);
}
function button(page, name) { return page.getByRole('button', {name, exact: true}); }
async function type(page, locator, value) {
  const field = await reveal(page, locator);
  await field.click({position: {x: 20, y: 20}});
  await page.waitForTimeout(250);
  await page.keyboard.press('Control+A');
  await page.keyboard.type(value, {delay: 8});
  check(await field.inputValue() === value, 'actual_login_editor_did_not_accept_typing');
}
async function login(page, context, role) {
  await open(page, '/login');
  await type(page, page.getByRole('textbox', {name: 'E-Mail oder Benutzername', exact: true}), account.credentials[role + '_username']);
  await type(page, page.getByLabel('Passwort', {exact: true}), account.credentials[role + '_password']);
  const waiting = page.waitForResponse(value => new URL(value.url()).pathname === '/api/auth/login' &&
    value.request().method() === 'POST', {timeout: 45000});
  waiting.catch(() => {});
  await tap(page, button(page, 'Anmelden'));
  const response = await waiting;
  check(response.status() === 200, 'regular_' + role + '_ui_login_failed');
  const identity = (await response.json()).user;
  check(identity?.role === role && (role === 'child' ? identity.child_id === account.child_id
    : identity.id === account.user.id && identity.families.some(f => f.id === account.user.families[0].id)),
    'authenticated_household_or_role_changed');
  await page.waitForURL(base + '/app', {timeout: 45000});
  authenticated.add(page);
  const session = (await context.cookies()).find(cookie => cookie.name === 'sp_session');
  check(session?.secure && session.httpOnly && session.sameSite === 'Strict', 'secure_web_session_required');
}
async function shot(page, name, scrollTop = false) {
  if (scrollTop) await top(page);
  const filename = 'daily-home-' + name + '.png';
  await privateWrite(path.join(artifacts, filename), await page.screenshot());
  screenshots.push(filename);
}
async function units() { return Promise.all([...preparedIds].map(id => get(parent, '/units/' + id))); }
async function run() {
  check(account.daily_background_smoke?.passed === true && account.school_day_id && account.package_unit_id,
    'wait_for_the_successful_server_background_smoke_and_exclusive_handoff');
  browser = await chromium.launch({headless: true, executablePath: process.env.CHROME_PATH || '/opt/google/chrome/chrome', args: ['--no-sandbox']});
  child = await browser.newContext({viewport: {width: 390, height: 844}, isMobile: true, hasTouch: true});
  parent = await browser.newContext({viewport: {width: 1280, height: 1000}});
  for (const [context, role] of [[child, 'child'], [parent, 'parent']]) {
    await context.route('**/api/**', route => requestGuard(route, role));
    context.on('page', page => page.on('pageerror', error => errors.push({
      name: /^[A-Za-z]+Error$/.test(error.name) ? error.name : 'RuntimeError', fingerprint: digest(error.message),
    })));
  }
  parentPage = await parent.newPage();
  step('regular_parent_ui_login');
  await login(parentPage, parent, 'parent');
  baseline = await usage();
  const sourceDay = await get(parent, '/school-days/' + account.school_day_id);
  check(sourceDay.child_id === account.child_id && sourceDay.stage === 'ready' &&
    sourceDay.preparation?.status === 'ready' && sourceDay.pages.length === 2 &&
    sourceDay.pages.every(source => source.confirmed && !source.synthetic) && sourceDay.units.length > 0,
    'background_smoke_must_have_two_real_confirmed_artificial_sources_and_ready_units');
  sourceDay.units.forEach(unit => preparedIds.add(unit.id));
  check(preparedIds.has(account.package_unit_id), 'checkpoint_unit_missing_from_owned_source_day');
  const originalAnswers = answerSignature(await units());
  check((await units()).every(unit => unit.questions.every(q => q.attempts.length === 0)),
    'exclusive_artificial_units_must_have_no_submitted_answers');
  childPage = await child.newPage();
  step('independent_child_ui_login_390px');
  await login(childPage, child, 'child');
  for (const width of [390, 320]) {
    step('child_today_' + width + 'px');
    await childPage.setViewportSize({width, height: 844});
    await open(childPage, '/app');
    const data = await get(child, '/children/' + account.child_id + '/overview?compact=true');
    validatePlan(data.plan);
    check(data.daily_capture?.day_id === sourceDay.id && data.daily_capture.date === data.plan.date &&
      data.daily_capture.page_count === 2, 'background_sources_must_belong_to_actual_today');
    await reveal(childPage, childPage.getByText('Heutige Heftseiten', {exact: true}));
    await shot(childPage, 'child-' + width, true);
    await tap(childPage, childPage.getByText('Mein Plan', {exact: true}));
    await reveal(childPage, childPage.getByText('Die nächsten Lerntage', {exact: true}));
    await shot(childPage, 'portion-' + width);
  }
  step('open_actual_owned_source_from_today_ui');
  await childPage.setViewportSize({width: 390, height: 844});
  await open(childPage, '/app');
  await tap(childPage, childPage.getByText('Heutige Heftseiten', {exact: true}));
  await childPage.waitForURL(base + '/after-school/' + account.child_id, {timeout: 45000});
  await tap(childPage, childPage.getByText('Heftseiten und bisherige Runden', {exact: true}));
  await tap(childPage, childPage.getByText('Heftseite 1', {exact: true}));
  await childPage.waitForURL(base + '/material/' + sourceDay.pages[0].id, {timeout: 45000});
  await shot(childPage, 'source-390', true);
  step('explicit_prepared_unit_only_if_current_plan_allows');
  await open(childPage, '/app');
  const data = await get(child, '/children/' + account.child_id + '/overview?compact=true');
  const next = data.plan.today[0];
  const mayStart = !data.plan.paused && !data.plan.free_day && data.plan.available_minutes > 0 &&
    next?.kind === 'unit' && preparedIds.has(next.id) && ['not_started', 'ready', 'paused', 'active'].includes(next.status);
  if (mayStart) {
    allowStart = !['active', 'completed'].includes(next.status);
    unitStartExpected = next.id;
    await tap(childPage, button(childPage, ['active', 'paused'].includes(next.status) ? 'Weiterlernen' : 'Jetzt lernen'));
    await childPage.waitForURL(base + '/unit/' + next.id, {timeout: 45000});
    const unit = await get(child, '/units/' + next.id);
    check(unit.status === 'active', 'explicit_prepared_unit_did_not_start');
    await shot(childPage, 'opened-unit-390', true);
    await open(childPage, '/app'); // Stop activity polling; never answer or ask AI.
  }
  step('parent_seven_day_proposal_and_preserved_limits_1280px');
  await open(parentPage, '/child/' + account.child_id);
  const parental = await get(parent, '/children/' + account.child_id + '/overview');
  validatePlan(parental.plan);
  await reveal(parentPage, parentPage.getByText('Die nächsten sieben Tage', {exact: true}));
  const heading = await parentPage.getByText('Die nächsten sieben Tage', {exact: true}).boundingBox();
  await parentPage.mouse.move(1250, 700);
  await parentPage.mouse.wheel(0, (heading?.y ?? 100) - 100);
  await parentPage.waitForTimeout(300);
  await shot(parentPage, 'parent-week-1280');
  await reveal(parentPage, parentPage.getByText('Zeitgrenzen:', {exact: false}));
  await shot(parentPage, 'parent-limits-1280');
  step('unchanged_answers_and_zero_additional_ai_reservations');
  check(answerSignature(await units()) === originalAnswers, 'browser_flow_changed_answers_hints_or_coach');
  const after = await usage();
  check(usageSignature(after) === usageSignature(baseline), 'reading_or_opening_reserved_ai_or_changed_costs');
  check(blocked.length === 0 && errors.length === 0, 'unexpected_mutation_or_browser_runtime_error');
  return {qa_passed: true, real_https: true, artificial_normal_family: true,
    child_viewports: [320, 390], parent_viewport: 1280, parent_horizon_days: 7,
    prepared_unit_explicitly_opened: mayStart, explicit_unit_start_posts: unitStartPosts,
    start_skipped_due_to_plan_or_prepared_unit_bound: !mayStart,
    submitted_answers: 0, additional_ai_calls: after.calls_used - baseline.calls_used,
    calls_used: after.calls_used, known_cost_micros_usd: after.known_cost_micros_usd,
    unknown_cost_calls: after.unknown_cost_calls, browser_runtime_errors: errors,
    blocked_mutations: blocked.length, screenshots, account_retained: true};
}

try {
  check(process.argv.length <= 3 && ['--help', '--check-inputs', '--run'].includes(mode), 'choose_help_check_inputs_or_run');
  if (mode === '--help') {
    console.log('Local validation: node qa/daily_home.mjs --check-inputs\nAfter explicit deployment + background-smoke handoff: node qa/daily_home.mjs --run\nNo AI, answers, retries, account changes or cleanup. At most one explicitly selected prepared unit starts.');
  } else {
    await inputs();
    if (mode === '--check-inputs') console.log(JSON.stringify({local_inputs_valid: true,
      background_smoke_ready: account.daily_background_smoke?.passed === true, network_requests: 0}));
    else {
      const report = await run();
      await privateWrite(reportFile, JSON.stringify(report, null, 2) + '\n');
      console.log(JSON.stringify(report));
    }
  }
} catch (error) {
  process.exitCode = 1;
  const report = {qa_passed: false, stopped_at: phase, reason: reason(error),
    browser_runtime_errors: errors, blocked_mutations: blocked.length,
    explicit_unit_start_posts: unitStartPosts, screenshots, account_retained: Boolean(account)};
  if (mode === '--run') {
    for (const [page, label] of [[childPage, 'child-debug'], [parentPage, 'parent-debug']]) {
      if (page && authenticated.has(page)) await shot(page, label).catch(() => {});
    }
    await privateWrite(reportFile, JSON.stringify(report, null, 2) + '\n').catch(() => {});
  }
  console.error(JSON.stringify(report));
} finally {
  if (browser) await browser.close().catch(() => {});
}
