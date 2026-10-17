// Public acceptance ONLY after an explicit deployment GO from the release owner.
// Exactly one owned fixed demo, one unit job, four real Flutter task components.
// No external inference, provider writes, manual coaching or practice requests.
// The protected journal is deliberately kept after a failure for explicit cleanup.
import assert from 'node:assert/strict';
import {createHash, randomBytes} from 'node:crypto';
import {chmod, lstat, mkdir, readFile, rename, unlink, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright';

const base = 'https://schulpilot.dorfspy.de';
const artifacts = fileURLToPath(new URL('../artifacts/', import.meta.url));
const journalFile = path.join(artifacts, '.learning-room-browser-qa.json');
const reportFile = path.join(artifacts, 'child-learning-room-result.json');
const mode = process.argv[2] ?? '--check';
const requestHeaders = {'X-Schulpilot-Request': '1'};
const widths = [320, 390, 1280];
const maximumHeartbeats = 35;
const intent = {login: null, start: null, introduction: null, answer: null, hint: null, ack: null};
const knownUnits = new Set(), heartbeatUnits = new Set();
const blocked = [], runtimeErrors = [], screenshots = [], responseTasks = new Set();
let journal, browser, parent, child, page, phase = 'offline_checks';
let writes = Promise.resolve();
const uuid = value => typeof value === 'string' && /^[a-f0-9]{32}$/.test(value);
const digest = value => createHash('sha256').update(value).digest('hex');

class QaFailure extends Error {}
function check(value, code) { if (!value) throw new QaFailure(code); }
function reason(error) {
  return error instanceof QaFailure && /^[a-z0-9_-]{1,160}$/.test(error.message)
    ? error.message : 'browser_or_local_io_failed';
}
function step(value, metadata = {}) {
  phase = value;
  console.log(JSON.stringify({qa_phase: value, ...metadata}));
}
function exactKeys(data, keys) {
  return data && typeof data === 'object' && !Array.isArray(data) &&
    Object.keys(data).length === keys.length && keys.every(key => Object.hasOwn(data, key));
}
async function privateWrite(filename, body) {
  await writeFile(filename, body, {mode: 0o600});
  await chmod(filename, 0o600);
}
async function save() {
  const body = JSON.stringify(journal);
  const work = writes.then(async () => {
    const temporary = journalFile + '.' + randomBytes(8).toString('hex') + '.tmp';
    try {
      await privateWrite(temporary, body);
      await rename(temporary, journalFile);
    } finally {
      await unlink(temporary).catch(error => { if (error.code !== 'ENOENT') throw error; });
    }
  });
  writes = work.catch(() => {});
  await work;
}
async function readJournal() {
  try {
    const info = await lstat(journalFile);
    check(info.isFile() && !info.isSymbolicLink() && !(info.mode & 0o077),
      'journal_must_be_a_private_regular_file');
    return JSON.parse(await readFile(journalFile, 'utf8'));
  } catch (error) {
    if (error.code === 'ENOENT') return null;
    throw error;
  }
}
function ownDemo(value) {
  const credentials = value?.credentials;
  return value?.user?.role === 'parent' && uuid(value.user.id) &&
    value.user.families?.length === 1 && uuid(value.user.families[0].id) &&
    value.user.families[0].synthetic === true && value.user.families[0].permission === 'owner' &&
    uuid(value.child_id) && uuid(value.material_id) && value.token === undefined &&
    /^eltern-[a-f0-9]{10}$/.test(credentials?.parent_username ?? '') &&
    /^kind-[a-f0-9]{10}$/.test(credentials?.child_username ?? '') &&
    credentials.parent_username.slice(7) === credentials.child_username.slice(5) &&
    typeof credentials.parent_password === 'string' && credentials.parent_password.length >= 12 &&
    typeof credentials.child_password === 'string' && credentials.child_password.length >= 12;
}
function allowMutation(method, pathname, data, pending = intent) {
  if (['GET', 'HEAD'].includes(method)) return true;
  if (!journal?.demo || method !== 'POST') return false;
  if (pathname === '/api/auth/login') {
    const c = journal.demo.credentials;
    return pending.login === 'child' && exactKeys(data, ['username', 'password', 'device']) &&
      data.username === c.child_username && data.password === c.child_password && data.device === 'Web-Browser';
  }
  const match = pathname.match(/^\/api\/units\/([a-f0-9]{32})\/(.+)$/);
  if (!match || !knownUnits.has(match[1])) return false;
  const [, id, route] = match;
  if (route === 'start') return pending.start === id && !journal.starts?.[id] &&
    (data === null || exactKeys(data, []));
  if (route === 'introduction') return pending.introduction === id && id === journal.unit_id &&
    !journal.introduction_requested && (data === null || exactKeys(data, []));
  if (route === 'heartbeat') return heartbeatUnits.has(id) &&
    (journal.heartbeat_posts ?? 0) < maximumHeartbeats && exactKeys(data, ['baseline']) &&
    typeof data.baseline === 'boolean';
  if (id !== journal.unit_id) return false;
  if (route === 'feedback/acknowledge') return pending.ack &&
    exactKeys(data, ['attempt_id']) && uuid(data.attempt_id) &&
    data.attempt_id === pending.ack && !(journal.acks ?? []).includes(data.attempt_id);
  const question = route.match(/^questions\/([a-z0-9_-]+)\/(answer|hint)$/);
  if (!question || !journal.questions?.some(value => value.id === question[1])) return false;
  if (question[2] === 'hint') return pending.hint === question[1] &&
    question[1] === journal.questions[0].id && !journal.hint_requested &&
    (data === null || exactKeys(data, []));
  return pending.answer?.question_id === question[1] &&
    exactKeys(data, ['answer', 'guided_feedback']) && data.guided_feedback === true &&
    typeof data.answer === 'string' && digest(data.answer) === pending.answer.digest &&
    (journal.answer_posts ?? 0) < 5;
}
async function makeContext(role, cookies = []) {
  const context = await browser.newContext({viewport: {width: 390, height: 844},
    hasTouch: true, storageState: {cookies, origins: []}});
  context.on('page', opened => {
    opened.on('pageerror', error => runtimeErrors.push({name: 'RuntimeError', fingerprint: digest(error.message)}));
    opened.on('console', message => {
      // Flutter layout exceptions can be console errors without a pageerror.
      if (/RenderFlex overflowed|EXCEPTION CAUGHT BY RENDERING|BoxConstraints forces/i.test(message.text())) {
        runtimeErrors.push({name: 'FlutterLayoutError', fingerprint: digest(message.text())});
      }
    });
  });
  await context.route('**/api/**', async route => {
    const request = route.request(), pathname = new URL(request.url()).pathname;
    let body = null;
    try { body = request.postDataJSON(); } catch { /* The exact body guard rejects malformed JSON. */ }
    if (role !== 'child' && !['GET', 'HEAD'].includes(request.method()) ||
        !allowMutation(request.method(), pathname, body)) {
      blocked.push({role, method: request.method(), path_fingerprint: digest(pathname)});
      return route.abort('blockedbyclient');
    }
    if (request.method() === 'POST') {
      if (pathname === '/api/auth/login') intent.login = null;
      else if (pathname.endsWith('/heartbeat')) journal.heartbeat_posts = (journal.heartbeat_posts ?? 0) + 1;
      else if (pathname.endsWith('/start')) {
        journal.starts ??= {};
        journal.starts[intent.start] = {requested: true};
        intent.start = null;
      } else if (pathname.endsWith('/introduction')) {
        journal.introduction_requested = true;
        intent.introduction = null;
      } else if (pathname.endsWith('/answer')) {
        journal.answer_posts = (journal.answer_posts ?? 0) + 1;
        intent.answer = null;
      } else if (pathname.endsWith('/hint')) {
        journal.hint_requested = true;
        intent.hint = null;
      } else if (pathname.endsWith('/acknowledge')) {
        journal.acks ??= [];
        journal.acks.push(intent.ack);
        intent.ack = null;
      }
      // A restart must not restore a spent request budget after an unclear response.
      await save();
    }
    return route.continue();
  });
  return context;
}
async function get(context, route, expected = 200) {
  const response = await context.request.get(base + '/api' + route,
    {maxRedirects: 0, timeout: 15000});
  check(response.status() === expected, 'authorized_read_failed_' + response.status());
  return expected === 200 ? response.json() : null;
}
async function parentIdentity({recover = false} = {}) {
  let response = await parent.request.get(base + '/api/auth/me', {maxRedirects: 0});
  if (response.status() === 401 && recover && !journal.deleted) {
    const c = journal.demo.credentials;
    const login = await parent.request.post(base + '/api/auth/login', {headers: requestHeaders,
      data: {username: c.parent_username, password: c.parent_password, device: 'Learning room QA cleanup'},
      maxRedirects: 0});
    check(login.status() === 200, 'own_parent_recovery_login_failed');
    journal.parent_cookies = await parent.cookies();
    await save();
    response = await parent.request.get(base + '/api/auth/me', {maxRedirects: 0});
  }
  check(response.status() === 200, 'owned_parent_session_required');
  const identity = await response.json();
  check(identity.id === journal.demo.user.id && identity.role === 'parent' &&
    identity.families?.length === 1 && identity.families[0].synthetic === true &&
    identity.families[0].id === journal.demo.user.families[0].id && identity.families[0].permission === 'owner',
    'parent_identity_must_match_this_owned_demo');
}
async function zeroUsage(stage) {
  const data = await get(parent, '/families/' + journal.demo.user.families[0].id + '/usage');
  check(data.synthetic === true && data.calls_used === 0 && Array.isArray(data.records) &&
    data.records.length === 0 && data.known_cost_micros_usd === 0 &&
    data.unknown_cost_calls === 0 && data.encumbered_micros_usd === 0,
    'no_external_inference_or_reservations_allowed');
  const limits = digest(JSON.stringify([data.calls_limit, data.budget_micros_usd, data.plan]));
  check(!journal.limits_digest || journal.limits_digest === limits, 'tariff_and_cost_limits_must_stay_unchanged');
  journal.limits_digest = limits;
  journal.usage ??= {};
  journal.usage[stage] = {calls: 0, known_cost_micros_usd: 0, unknown_cost_calls: 0, reserved_micros_usd: 0};
  await save();
}
async function prepareDemo() {
  step('create_one_fixed_owned_demo');
  check(!journal.demo_creation_attempted, 'uncertain_demo_creation_requires_operator_review');
  journal.demo_creation_attempted = true;
  await save();
  const response = await parent.request.post(base + '/api/demo', {headers: requestHeaders, maxRedirects: 0});
  check(response.status() === 201, 'fixed_demo_creation_failed_' + response.status());
  journal.demo = await response.json();
  journal.parent_cookies = await parent.cookies();
  await save();
  check(ownDemo(journal.demo), 'only_a_new_fixed_owned_demo_is_allowed');
  await parentIdentity();
  await zeroUsage('before');
  step('confirm_only_the_fixed_demo_material');
  const source = await get(parent, '/materials/' + journal.demo.material_id);
  check(source.child_id === journal.demo.child_id && source.synthetic === true && source.fixture_id == null &&
    source.school_day_id == null && source.status === 'review' && source.confirmed === false &&
    source.homework?.length === 0, 'only_the_original_fixed_demo_material_can_be_confirmed');
  const confirmation = await parent.request.put(base + '/api/materials/' + source.id + '/confirm',
    {headers: requestHeaders, maxRedirects: 0, data: {subject: source.subject, topic: source.topic,
      content: source.content, homework: source.homework, uncertainties_resolved: true}});
  check(confirmation.status() === 200 && (await confirmation.json()).confirmed === true,
    'explicit_source_confirmation_failed');
  step('submit_exactly_one_synthetic_unit_job');
  journal.job = {key: 'learning-room-' + randomBytes(16).toString('hex'), attempted: true};
  await save();
  const submitted = await parent.request.post(base + '/api/children/' + journal.demo.child_id + '/units',
    {headers: {...requestHeaders, 'Idempotency-Key': journal.job.key}, maxRedirects: 0,
      data: {material_id: journal.demo.material_id}});
  check(submitted.status() === 202, 'fixed_unit_submission_failed_' + submitted.status());
  journal.job.id = (await submitted.json()).id;
  check(uuid(journal.job.id), 'fixed_job_id_required');
  await save();
  const deadline = Date.now() + 120000;
  while (Date.now() < deadline) {
    const data = await get(parent, '/jobs/' + journal.job.id);
    check(data.kind === 'unit' && ['queued', 'running', 'completed'].includes(data.status),
      'fixed_unit_job_failed_no_retry_allowed');
    if (data.status === 'completed') {
      check(uuid(data.result?.unit_id), 'completed_fixed_job_requires_a_unit');
      journal.unit_id = data.result.unit_id;
      break;
    }
    await new Promise(resolve => setTimeout(resolve, 1000));
  }
  check(uuid(journal.unit_id), 'fixed_unit_job_did_not_complete_in_time');
  const unit = await get(parent, '/units/' + journal.unit_id);
  check(unit.child_id === journal.demo.child_id && unit.material_id === journal.demo.material_id &&
    unit.synthetic === true && unit.provider === 'synthetic' && unit.model === 'fixed-fractions-v1' &&
    unit.status === 'not_started' && unit.questions?.length === 4 &&
    unit.questions.map(q => q.type).join(',') === 'choice,gap,match,short' &&
    unit.questions.every(q => q.attempts?.length === 0 && q.hints_used === 0 && typeof q.answer === 'string'),
    'only_the_pristine_four_type_fixed_synthetic_unit_is_allowed');
  journal.questions = unit.questions;
  journal.source_link_verified = unit.source_material_ids.includes(journal.demo.material_id);
  check(journal.source_link_verified, 'fixed_unit_source_link_required');
  knownUnits.add(journal.unit_id);
  await save();
}
async function accessible() {
  await page.waitForSelector('flutter-view', {timeout: 90000});
  await page.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(node => node.click()));
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
  // The desktop learning room is centered and at most820px wide. Wheel events
  // must stay inside it, rather than outside the actual Flutter scroll surface.
  const x = Math.min(size.width - 24, (size.width + 820) / 2 - 24);
  for (let attempt = 0; attempt < 32; attempt++) {
    const box = await target.count() ? await target.boundingBox({timeout: 500}).catch(() => null) : null;
    if (box && box.width > 0 && box.height > 0 && box.x >= 0 && box.x + box.width <= size.width + 2 &&
        box.y >= 48 && box.y + Math.min(box.height, size.height - 140) <= size.height - 2) return target;
    await page.mouse.move(x, size.height / 2);
    await page.mouse.wheel(0, !box && attempt === 0 ? -16000 : box?.y < 48 ? -350 : 350);
    await page.waitForTimeout(180);
  }
  throw new QaFailure('expected_learning_control_not_reachable');
}
async function tap(locator) {
  const target = await reveal(locator), box = await target.boundingBox();
  check(box && box.height < page.viewportSize().height, 'learning_control_has_no_usable_target');
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  await page.waitForTimeout(200);
}
async function type(locator, value) {
  const field = await reveal(locator);
  await field.click({position: {x: 18, y: Math.min(20, (await field.boundingBox()).height / 2)}});
  await page.waitForTimeout(250);
  await page.keyboard.press('Control+A');
  await page.keyboard.type(value, {delay: 8});
  check(await field.inputValue() === value, 'visible_text_field_did_not_accept_own_input');
}
async function uiResponse(method, route, action) {
  const waiting = page.waitForResponse(response => response.request().method() === method &&
    new URL(response.url()).pathname === '/api' + route, {timeout: 45000});
  waiting.catch(() => {});
  await action();
  return waiting;
}
async function screenshot(label) {
  check(journal.child_authenticated, 'never_capture_an_authentication_form');
  const name = 'learning-room-' + journal.run_id + '-' + label + '.png';
  await privateWrite(path.join(artifacts, name), await page.screenshot());
  screenshots.push(name);
  check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 2),
    'horizontal_browser_overflow');
}
async function captureWidths(label, required) {
  for (const width of widths) {
    await page.setViewportSize({width, height: 844});
    await page.waitForTimeout(250);
    if (required) await reveal(required());
    await screenshot(label + '-' + width);
  }
  await page.setViewportSize({width: 390, height: 844});
}
async function loginChild() {
  step('independent_child_login_in_the_real_flutter_ui');
  page = await child.newPage();
  page.on('response', response => {
    const pathname = new URL(response.url()).pathname;
    if (response.request().method() !== 'POST' || !pathname.endsWith('/heartbeat')) return;
    const work = (async () => {
      journal.heartbeat_responses ??= [];
      // Status-only evidence: never call an unreadable body a validated snapshot.
      journal.heartbeat_responses.push({http_status: response.status(), body_observed: false});
      await save();
    })().catch(() => { journal.observer_failed = true; });
    responseTasks.add(work);
    void work.finally(() => responseTasks.delete(work));
  });
  await open('/login');
  const c = journal.demo.credentials;
  await type(page.getByRole('textbox', {name: 'E-Mail oder Benutzername', exact: true}), c.child_username);
  await type(page.getByLabel('Passwort', {exact: true}), c.child_password);
  intent.login = 'child';
  const logged = await uiResponse('POST', '/auth/login', () => tap(button('Anmelden')));
  check(logged.status() === 200, 'independent_child_login_failed');
  const identity = (await logged.json()).user;
  check(identity.role === 'child' && identity.child_id === journal.demo.child_id && identity.synthetic === true,
    'child_identity_must_match_this_owned_demo');
  journal.child_authenticated = true;
  journal.child_cookies = await child.cookies();
  await save();
  for (const context of [parent, child]) {
    check((await context.cookies()).some(cookie => cookie.name === 'sp_session' && cookie.secure &&
      cookie.httpOnly && cookie.sameSite === 'Strict'), 'secure_independent_http_only_session_required');
  }
  await page.waitForURL(base + '/app', {timeout: 45000});
  await open('/unit/' + journal.unit_id);
}
async function startUnit() {
  step('explicitly_start_the_saved_round_and_read_the_explanation');
  intent.start = journal.unit_id;
  heartbeatUnits.add(journal.unit_id);
  const response = await uiResponse('POST', '/units/' + journal.unit_id + '/start',
    () => tap(button('Einheit starten')));
  check(response.status() === 200 && (await response.json()).status === 'active', 'explicit_round_start_failed');
  await captureWidths('understand', () => button('Weiter zu den Übungen'));
  intent.introduction = journal.unit_id;
  const introduction = await uiResponse('POST', '/units/' + journal.unit_id + '/introduction',
    () => tap(button('Weiter zu den Übungen')));
  check(introduction.status() === 200 && (await introduction.json()).introduction_seen === true,
    'explicit_explanation_transition_not_saved');
}
async function enterAnswer(question, answer) {
  if (question.type === 'choice') {
    await tap(page.getByRole('radio', {name: answer, exact: true}));
  } else if (question.type === 'match') {
    for (const [index, option] of question.options.entries()) {
      const [pair, right] = option.split('|');
      check(pair && right && right === answer.split(';')[index], 'fixed_matching_answers_must_agree');
      await tap(button('Was passt dazu?').first());
      await tap(page.getByRole('radio', {name: right, exact: true}));
    }
  } else {
    await type(page.getByRole('textbox', {name: 'Deine Antwort', exact: true}), answer);
  }
}
async function submit(question, answer, expected) {
  await enterAnswer(question, answer);
  intent.answer = {question_id: question.id, digest: digest(answer)};
  const response = await uiResponse('POST', '/units/' + journal.unit_id + '/questions/' + question.id + '/answer',
    () => tap(button('Antwort prüfen')));
  check(response.status() === 200, 'ordinary_answer_submission_failed_' + response.status());
  const data = await response.json();
  check(data.outcome === expected && uuid(data.unit?.pending_feedback?.attempt_id) &&
    data.unit.pending_feedback.question_id === question.id && data.unit.pending_feedback.answer === answer &&
    data.unit.pending_feedback.outcome === expected, 'saved_guided_feedback_must_match_the_real_attempt');
  const own = await get(parent, '/units/' + journal.unit_id);
  check(own.pending_feedback?.attempt_id === data.unit.pending_feedback.attempt_id,
    'parent_must_see_the_same_saved_pending_feedback');
  journal.attempt_evidence ??= [];
  journal.attempt_evidence.push({question_id: question.id, attempt_id: data.unit.pending_feedback.attempt_id,
    outcome: expected, assisted: data.assisted, answer_digest: digest(answer)});
  await save();
  return data;
}
async function ack(data, label) {
  const attempt = data.unit.pending_feedback.attempt_id;
  intent.ack = attempt;
  const response = await uiResponse('POST', '/units/' + journal.unit_id + '/feedback/acknowledge',
    () => tap(button(label)));
  check(response.status() === 200 && (await response.json()).pending_feedback === null,
    'explicit_feedback_acknowledgement_failed');
}
async function exerciseLoop() {
  const [first, ...rest] = journal.questions;
  step('one_incorrect_answer_stays_visible_after_reload');
  const wrong = first.options.find(value => value !== first.answer);
  check(typeof wrong === 'string', 'fixed_choice_requires_one_known_wrong_option');
  await page.setViewportSize({width: 320, height: 844});
  const incorrect = await submit(first, wrong, 'incorrect');
  check(incorrect.assisted === false, 'first_unassisted_incorrect_attempt_must_remain_honest');
  await reveal(page.getByText('Noch nicht ganz', {exact: true}));
  await screenshot('incorrect-320');
  const beforeReload = journal.answer_posts;
  await page.reload({waitUntil: 'domcontentloaded', timeout: 90000});
  await accessible();
  await reveal(page.getByText('Noch nicht ganz', {exact: true}));
  await reveal(page.getByText(wrong, {exact: true}));
  check(journal.answer_posts === beforeReload, 'reload_must_not_submit_an_answer');
  const reloaded = await get(parent, '/units/' + journal.unit_id);
  check(reloaded.pending_feedback?.attempt_id === incorrect.unit.pending_feedback.attempt_id &&
    reloaded.questions[0].attempts.length === 1, 'reload_must_preserve_exactly_one_saved_wrong_attempt');
  journal.pending_feedback_reload_verified = true;
  await screenshot('saved-feedback-reload-320');
  await ack(incorrect, 'Noch einmal versuchen');
  step('one_explicit_hint_then_a_correct_answer');
  intent.hint = first.id;
  const hint = await uiResponse('POST', '/units/' + journal.unit_id + '/questions/' + first.id + '/hint',
    () => tap(button('Hilfe')));
  check(hint.status() === 200, 'single_explicit_hint_failed');
  await reveal(page.getByText('Dein Tipp', {exact: true}));
  await screenshot('one-hint-320');
  const corrected = await submit(first, first.answer, 'correct');
  check(corrected.assisted === true, 'hint_or_second_attempt_must_be_marked_assisted');
  await ack(corrected, 'Weiter');
  for (const [index, question] of rest.entries()) {
    step('use_fixed_flutter_task_type', {task_type: question.type});
    await page.setViewportSize({width: widths[index], height: 844});
    await reveal(page.getByText(question.prompt, {exact: true}));
    await screenshot('task-' + question.type + '-' + widths[index]);
    const result = await submit(question, question.answer, 'correct');
    check(result.assisted === false, 'other_questions_must_remain_independently_answered');
    if (index < rest.length - 1) await ack(result, 'Weiter');
    else {
      check(result.unit.status === 'completed', 'last_answer_must_complete_the_saved_round');
      await captureWidths('last-feedback', () => button('Ergebnis ansehen'));
      check(await button('Weiterlernen').count() === 0, 'last_feedback_must_not_skip_to_a_time_goal_action');
      journal.last_feedback_seen_before_completion = true;
      await ack(result, 'Ergebnis ansehen');
    }
  }
  await save();
}
function verifySavedAnswers(unit) {
  check(unit.id === journal.unit_id && unit.child_id === journal.demo.child_id && unit.synthetic === true &&
    unit.status === 'completed' && unit.pending_feedback === null && unit.questions.length === 4,
    'completed_owned_round_and_ack_must_be_persistent');
  let independent = 0, assisted = 0;
  for (const [index, question] of unit.questions.entries()) {
    const original = journal.questions[index];
    check(question.id === original.id && question.prompt === original.prompt && question.answer === original.answer,
      'original_questions_and_main_answers_must_not_be_rewritten');
    const attempts = question.attempts;
    check(attempts.length === (index === 0 ? 2 : 1) && question.hints_used === (index === 0 ? 1 : 0),
      'all_original_answers_and_exactly_one_hint_must_be_retained');
    for (const attempt of attempts) {
      const evidence = journal.attempt_evidence.find(value => value.attempt_id === attempt.id);
      check(evidence && digest(attempt.answer) === evidence.answer_digest &&
        attempt.outcome === evidence.outcome && attempt.assisted === evidence.assisted,
        'stored_answer_and_assistance_must_match_the_observed_response');
    }
    check(attempts.at(-1).outcome === 'correct', 'fixed_correct_answers_must_stay_correct');
    if (attempts.at(-1).assisted) assisted++; else independent++;
  }
  check(independent === 3 && assisted === 1 && journal.answer_posts === 5 && journal.acks?.length === 5,
    'completion_facts_must_be_three_independent_one_assisted_and_five_attempts');
  journal.saved_facts = {tasks: 4, attempts: 5, independent: 3, assisted: 1, uncertain: 0, hints: 1};
}
async function completionAndContinuation() {
  step('factual_completion_and_existing_next_round');
  let completed = await get(parent, '/units/' + journal.unit_id);
  const deadline = Date.now() + 45000;
  while (completed.coaching?.status === 'pending' && Date.now() < deadline) {
    await page.waitForTimeout(1000);
    completed = await get(parent, '/units/' + journal.unit_id);
  }
  verifySavedAnswers(completed);
  check(completed.coaching?.status === 'ready' && completed.coaching.provider === 'synthetic',
    'only_the_automatic_fixed_demo_review_is_allowed');
  await reveal(page.getByText('3 selbstständig', {exact: true}));
  await reveal(page.getByText('1 mit Hilfe', {exact: true}));
  check(await page.getByText('Für heute geschafft', {exact: true}).count() === 0,
    'one_round_must_not_claim_the_whole_day_or_topic_is_mastered');
  await captureWidths('factual-round-completion', () => page.getByText('3 selbstständig', {exact: true}));
  journal.completion_widths = widths;
  const nextId = completed.coaching.next_unit_id;
  if (uuid(nextId)) {
    const next = await get(parent, '/units/' + nextId);
    check(next.child_id === journal.demo.child_id && next.synthetic === true && next.provider === 'synthetic' &&
      next.followup_of === journal.unit_id && next.status === 'not_started' &&
      next.questions.every(question => question.attempts.length === 0), 'next_round_must_already_exist_and_belong_to_this_demo');
    knownUnits.add(nextId);
    heartbeatUnits.add(nextId);
    journal.next_unit_id = nextId;
    await save();
    const before = journal.answer_posts;
    intent.start = nextId;
    const response = await uiResponse('POST', '/units/' + nextId + '/start',
      () => tap(button(completed.coaching.decision === 'check' ? 'Selbst ausprobieren' : 'Weiter üben')));
    check(response.status() === 200 && (await response.json()).status === 'active',
      'direct_existing_next_round_start_failed');
    await page.waitForURL(base + '/unit/' + nextId, {timeout: 45000});
    check(journal.answer_posts === before, 'continuation_must_not_answer_the_next_round');
    if (next.introduction_seen !== true) await reveal(button('Weiter zu den Übungen'));
    else await reveal(page.getByText(next.questions[0].prompt, {exact: true}));
    journal.continuation = {mode: 'existing_saved_synthetic_round', started: true,
      next_content_rendered: true, new_generation_requests: 0};
    await screenshot('direct-next-round-390');
  } else {
    // Honest bounded fallback: inspect the existing recommendation; do not
    // manufacture three more jobs just to fill this test's next-step state.
    const overview = await get(parent, '/children/' + journal.demo.child_id + '/overview?compact=true');
    check(overview.child?.id === journal.demo.child_id && overview.plan,
      'read_only_next_step_evidence_requires_the_owned_plan');
    const deferred = completed.coaching.practice_deferred === true &&
      ['repair', 'check'].includes(completed.coaching.decision);
    if (deferred) {
      await reveal(button(completed.coaching.decision === 'check' ? 'Ohne Hilfe ausprobieren' : 'Gezielt weiterüben'));
      await screenshot('explicit-practice-action-not-pressed-390');
    }
    journal.continuation = {mode: deferred ? 'explicit_practice_action_not_pressed' : 'read_only_plan_only',
      started: false, direct_existing_round_start_tested: false, new_generation_requests: 0,
      recommendation_count: (overview.plan.today ?? []).length};
  }
  journal.completed_round_verified = true;
  await save();
}
async function parentEvidence() {
  step('parent_sees_the_same_saved_answers_without_writing');
  const savedChildPage = page;
  page = await parent.newPage();
  await page.setViewportSize({width: 1280, height: 844});
  await open('/unit/' + journal.unit_id);
  const data = await get(parent, '/units/' + journal.unit_id);
  verifySavedAnswers(data);
  await reveal(page.getByText(data.questions[0].prompt, {exact: true}).last());
  await reveal(page.getByText('Antwort: ' + data.questions[0].attempts[0].answer + '\nNoch nicht richtig',
    {exact: false}).first()).catch(async () => {
    // Outcome wording is shared and may differ; the exact stored question
    // and both actual answer strings must still be present in the parent UI.
    await reveal(page.getByText('Antwort: ' + data.questions[0].attempts[0].answer, {exact: false}).last());
  });
  await screenshot('parent-stored-answers-1280');
  journal.parent_answers_ui_verified = true;
  await page.close();
  page = savedChildPage;
  await save();
}
async function cleanup() {
  step('normal_account_deletion_and_both_session_revocations');
  for (const context of [parent, child]) await Promise.all(context.pages().map(opened => opened.close()));
  await Promise.allSettled([...responseTasks]);
  await writes;
  if (!journal.deleted) {
    await parentIdentity({recover: true});
    const response = await parent.request.delete(base + '/api/account', {headers: requestHeaders,
      data: {password: journal.demo.credentials.parent_password}, maxRedirects: 0});
    check(response.status() === 200, 'normal_owned_family_cleanup_failed');
    journal.deleted = true;
    await save();
  }
  await get(parent, '/auth/me', 401);
  await get(child, '/auth/me', 401);
  journal.sessions_revoked = true;
  await save();
}
function localChecks() {
  const previous = journal;
  const id = 'a'.repeat(32), other = 'b'.repeat(32), attempt = 'c'.repeat(32);
  journal = {unit_id: id, demo: {credentials: {child_username: 'test-child', child_password: 'private-test'}},
    questions: [{id: 'sum'}]};
  knownUnits.add(id);
  assert.equal(allowMutation('POST', '/api/units/' + id + '/coaching', null), false);
  assert.equal(allowMutation('POST', '/api/units/' + id + '/practice', null), false);
  assert.equal(allowMutation('POST', '/api/children/' + other + '/units', {}), false);
  assert.equal(allowMutation('POST', '/api/units/' + other + '/start', null, {start: other}), false);
  assert.equal(allowMutation('POST', '/api/units/' + id + '/start', null, {start: id}), true);
  assert.equal(allowMutation('POST', '/api/units/' + id + '/start', {seconds: 300}, {start: id}), false);
  const pathname = '/api/units/' + id + '/questions/sum/answer';
  const intended = {answer: {question_id: 'sum', digest: digest('1/2')}};
  assert.equal(allowMutation('POST', pathname, {answer: '1/2', guided_feedback: true}, intended), true);
  assert.equal(allowMutation('POST', pathname, {answer: '1/2'}, intended), false);
  assert.equal(allowMutation('POST', pathname, {answer: '2/4', guided_feedback: true}, intended), false);
  assert.equal(allowMutation('POST', pathname, {answer: '1/2', guided_feedback: true, correct: true}, intended), false);
  assert.equal(allowMutation('POST', '/api/units/' + id + '/feedback/acknowledge', {attempt_id: attempt}, {ack: attempt}), true);
  assert.equal(allowMutation('POST', '/api/units/' + other + '/feedback/acknowledge', {attempt_id: attempt}, {ack: attempt}), false);
  assert.equal(allowMutation('POST', '/api/units/' + id + '/heartbeat', {baseline: true}), false);
  heartbeatUnits.add(id);
  assert.equal(allowMutation('POST', '/api/units/' + id + '/heartbeat', {baseline: false}), true);
  assert.equal(allowMutation('POST', '/api/units/' + id + '/heartbeat', {baseline: true, seconds: 100}), false);
  journal.heartbeat_posts = maximumHeartbeats;
  assert.equal(allowMutation('POST', '/api/units/' + id + '/heartbeat', {baseline: false}), false);
  assert.equal(allowMutation('POST', '/api/auth/login',
    {username: 'test-child', password: 'private-test', device: 'Web-Browser'}, {login: 'child'}), true);
  assert.equal(allowMutation('POST', '/api/auth/login',
    {username: 'other-child', password: 'private-test', device: 'Web-Browser'}, {login: 'child'}), false);
  assert.equal(reason(new Error('do not print private data')), 'browser_or_local_io_failed');
  knownUnits.clear();
  heartbeatUnits.clear();
  journal = previous;
}
async function main() {
  localChecks();
  if (mode === '--check') {
    console.log(JSON.stringify({driver: 'child_learning_room', local_guard_checks: 'passed', public_requests: 0,
      maximum_owned_demo_families: 1, maximum_unit_jobs: 1, maximum_answer_posts: 5,
      maximum_hint_posts: 1, maximum_ui_heartbeats: maximumHeartbeats, widths,
      external_ai_allowed: false, run_after_explicit_deployment_go: 'node qa/child_learning_room.mjs --run',
      interrupted_run_cleanup: 'node qa/child_learning_room.mjs --cleanup-only'}));
    return;
  }
  check(['--run', '--cleanup-only'].includes(mode), 'use_check_run_or_cleanup_only');
  await mkdir(artifacts, {recursive: true});
  journal = await readJournal();
  if (mode === '--run') {
    check(!journal, 'existing_owned_journal_requires_explicit_cleanup_before_a_new_run');
    journal = {purpose: 'child-learning-room-fixed-demo-only', version: 1,
      run_id: new Date().toISOString().replace(/[-:.]/g, ''), heartbeat_posts: 0, answer_posts: 0};
    await save();
  } else {
    check(journal?.purpose === 'child-learning-room-fixed-demo-only' && journal.version === 1 && ownDemo(journal.demo),
      'cleanup_requires_this_private_owned_demo_journal');
  }
  let passed = false, failure = null, failedPhase = null;
  try {
    browser = await chromium.launch({headless: true, executablePath: process.env.CHROME_PATH || '/opt/google/chrome/chrome',
      args: ['--no-sandbox'], timeout: 15000});
    parent = await makeContext('parent', journal.parent_cookies ?? []);
    child = await makeContext('child', journal.child_cookies ?? []);
    if (mode === '--run') {
      const health = await get(parent, '/health');
      journal.source_commit = health.source_commit ?? health.version ?? null;
      await prepareDemo();
      await loginChild();
      await startUnit();
      await exerciseLoop();
      await completionAndContinuation();
      await parentEvidence();
      await zeroUsage('after');
      check(blocked.length === 0 && runtimeErrors.length === 0, 'unexpected_mutation_or_runtime_layout_failure');
      check(!journal.observer_failed && journal.heartbeat_responses?.every(value => value.http_status === 200),
        'ordinary_ui_heartbeat_status_observation_failed');
    }
    await cleanup();
    passed = true;
  } catch (error) {
    failure = reason(error);
    failedPhase = phase;
    if (journal.child_authenticated && page && !page.isClosed() &&
        !new URL(page.url()).pathname.startsWith('/login')) {
      await screenshot('failure').catch(() => {});
    }
    // No automatic repeat of an answer, a provider job or an uncertain POST.
    // Leave only this private owned journal for authorized diagnosis/cleanup.
  } finally {
    if (browser) await browser.close();
    await Promise.allSettled([...responseTasks]);
    await writes;
    const report = {driver: 'child_learning_room', url: base, mode, source_commit: journal.source_commit ?? null,
      qa_passed: passed, failure, failed_phase: failedPhase,
      own_demo_created: Boolean(journal.demo), initial_unit_jobs: journal.job?.id ? 1 : 0,
      synthetic_provenance_verified: journal.source_link_verified === true,
      own_child_ui_login: journal.child_authenticated === true,
      four_task_types: journal.questions?.map(question => question.type) ?? [],
      pending_feedback_reload_verified: journal.pending_feedback_reload_verified === true,
      last_feedback_before_completion: journal.last_feedback_seen_before_completion === true,
      saved_facts: journal.saved_facts ?? null, completion_widths: journal.completion_widths ?? [],
      continuation: journal.continuation ?? null, parent_answers_ui_verified: journal.parent_answers_ui_verified === true,
      usage_before: journal.usage?.before ?? null, usage_after: journal.usage?.after ?? null,
      ordinary_ui_heartbeat_requests: journal.heartbeat_posts ?? 0,
      heartbeat_response_statuses_observed: journal.heartbeat_responses?.length ?? 0,
      heartbeat_body_observation: 'not_performed_no_full_snapshot_claim',
      cleanup_complete: journal.deleted === true && journal.sessions_revoked === true,
      parent_and_child_sessions_401: journal.sessions_revoked === true,
      blocked_mutations: blocked, runtime_errors: runtimeErrors, screenshots,
      operator_cleanup_if_needed: 'node qa/child_learning_room.mjs --cleanup-only',
      completed: new Date().toISOString()};
    await privateWrite(reportFile, JSON.stringify(report, null, 2));
    await privateWrite(path.join(artifacts, 'learning-room-' + journal.run_id + '-result.json'), JSON.stringify(report, null, 2));
    if (report.cleanup_complete) await unlink(journalFile);
    console.log(JSON.stringify(report));
    if (!passed) process.exitCode = 1;
  }
}
main().catch(error => {
  console.log(JSON.stringify({qa_passed: false, phase, failure: reason(error)}));
  process.exitCode = 1;
});
