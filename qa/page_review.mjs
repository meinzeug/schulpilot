// Public Flutter acceptance of direct page confirmation and safe deletion.
// Run only after deployment and Root's explicit GO. Two NEW fixed /demo
// households; never use the regular AI QA account or any external provider.
// node qa/page_review.mjs --check          local assertions, no network
// node qa/page_review.mjs --run            live UI + own-family cleanup
// node qa/page_review.mjs --cleanup-only   recover an interrupted own run
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {chmod, lstat, mkdir, readFile, unlink, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright';

const base = 'https://schulpilot.dorfspy.de';
const artifacts = fileURLToPath(new URL('../artifacts/', import.meta.url));
const journalFile = path.join(artifacts, '.page-review-qa-account.json');
const reportFile = path.join(artifacts, 'page-review-browser-result.json');
const headers = {'X-Schulpilot-Request': '1'};
const mode = process.argv[2] ?? '--help';
const screenshots = [], errors = [], blocked = [], live = new Map();
const created = [], completedCases = [];
let browser, journal, phase = 'local_check', passed = false, cleanupComplete = false;

class QaFailure extends Error {}
function check(value, code) { if (!value) throw new QaFailure(code); }
function digest(value) { return createHash('sha256').update(value).digest('hex'); }
function sourceSignature(source) {
  // Revisions are internal. Compare the actual public source representation.
  return digest(JSON.stringify(Object.fromEntries([
    'id', 'child_id', 'school_day_id', 'subject', 'topic', 'content',
    'uncertainties', 'homework', 'confirmed', 'status', 'synthetic', 'fixture_id',
  ].map(key => [key, source[key]]))));
}
function safeReason(error) {
  return error instanceof QaFailure && /^[a-z0-9_-]{1,160}$/.test(error.message)
    ? error.message : 'browser_or_local_io_operation_failed';
}
function step(value) { phase = value; console.log(JSON.stringify({qa_phase: value})); }
async function privateWrite(filename, data) {
  await writeFile(filename, data, {mode: 0o600});
  await chmod(filename, 0o600);
}
async function save() { await privateWrite(journalFile, JSON.stringify(journal)); }
async function readJournal() {
  try {
    const info = await lstat(journalFile);
    check(info.isFile() && !info.isSymbolicLink() && (info.mode & 0o077) === 0,
      'own_demo_journal_must_be_a_protected_regular_file');
    return JSON.parse(await readFile(journalFile, 'utf8'));
  } catch (error) {
    if (error.code === 'ENOENT') return null;
    throw error;
  }
}
function ownDemo(entry) {
  const demo = entry?.demo, credentials = demo?.credentials;
  return demo?.user?.role === 'parent' && demo.user.families?.length === 1 &&
    demo.user.families[0].synthetic === true && demo.user.families[0].permission === 'owner' &&
    typeof demo.user.id === 'string' && typeof demo.child_id === 'string' &&
    typeof demo.material_id === 'string' && demo.token === undefined &&
    /^eltern-[a-f0-9]{10}$/.test(credentials?.parent_username ?? '') &&
    /^kind-[a-f0-9]{10}$/.test(credentials?.child_username ?? '') &&
    credentials.parent_username.slice(7) === credentials.child_username.slice(5) &&
    typeof credentials.parent_password === 'string' && credentials.parent_password.length >= 12 &&
    typeof credentials.child_password === 'string' && credentials.child_password.length >= 12;
}
function permittedMutation(role, method, pathname, intent) {
  if (method === 'GET' || method === 'HEAD') return true;
  if (method === 'POST' && pathname === '/api/demo') return role === 'parent' && intent.demo === true;
  if (method === 'POST' && pathname === '/api/auth/login') return role === 'child' && intent.login === true;
  if (role !== 'child' || !intent.material) return false;
  if (method === 'PUT' && pathname === '/api/materials/' + intent.material + '/confirm') return intent.confirm === true;
  return method === 'DELETE' && pathname === '/api/materials/' + intent.material && intent.remove === true;
}
async function context(role, intent, storageState) {
  const ctx = await browser.newContext({viewport: {width: 390, height: 844},
    isMobile: true, hasTouch: true, ...(storageState ? {storageState} : {})});
  ctx.on('page', page => page.on('pageerror', error => errors.push({
    name: /^[A-Za-z]+Error$/.test(error.name) ? error.name : 'RuntimeError',
    fingerprint: digest(error.message),
  })));
  await ctx.route('**/api/**', async route => {
    const request = route.request(), pathname = new URL(request.url()).pathname;
    if (!permittedMutation(role, request.method(), pathname, intent)) {
      blocked.push({role, method: request.method(), path_fingerprint: digest(pathname)});
      return route.abort('blockedbyclient');
    }
    if (request.method() !== 'GET' && request.method() !== 'HEAD') {
      if (pathname === '/api/demo') { intent.demo = false; intent.demoPosts++; }
      else if (pathname === '/api/auth/login') { intent.login = false; intent.loginPosts++; }
      else if (request.method() === 'PUT') { intent.confirm = false; intent.confirmPosts++; }
      else { intent.remove = false; intent.deletePosts++; }
    }
    return route.continue();
  });
  return ctx;
}
async function accessible(page) {
  await page.waitForSelector('flutter-view', {timeout: 90000});
  await page.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(node => node.click()));
  await page.waitForTimeout(350);
}
async function open(page, route) {
  const response = await page.goto(base + route, {waitUntil: 'domcontentloaded', timeout: 90000});
  check(response?.ok() && response.url().startsWith(base + '/'), 'public_https_page_unavailable');
  await accessible(page);
}
async function reveal(page, locator, {modal = false} = {}) {
  const target = locator.first(), size = page.viewportSize();
  const upper = modal ? 4 : 75, lower = size.height - (modal ? 4 : 95);
  for (let attempt = 0; attempt < 36; attempt++) {
    const box = await target.count() ? await target.boundingBox({timeout: 500}).catch(() => null) : null;
    if (box && box.width > 0 && box.height > 0 && box.x >= 0 && box.x + box.width <= size.width + 1 &&
      box.y >= upper && box.y + Math.min(box.height, size.height - 200) <= lower) return target;
    await page.mouse.move(size.width - 28, size.height - 160);
    await page.mouse.wheel(0, !box && attempt === 0 ? -20000 : box && box.y < upper ? -400 : 400);
    await page.waitForTimeout(250);
  }
  throw new QaFailure('expected_mobile_control_not_visible');
}
async function tap(page, locator, options) {
  const control = await reveal(page, locator, options), box = await control.boundingBox();
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
  await page.waitForTimeout(150);
  check(await field.inputValue() === value, 'visible_login_field_did_not_accept_typing');
}
async function responseFor(page, method, route, action) {
  const waiting = page.waitForResponse(value => new URL(value.url()).pathname === '/api' + route &&
    value.request().method() === method, {timeout: 45000});
  waiting.catch(() => {});
  await action();
  return waiting;
}
async function get(ctx, route, expected = 200) {
  const response = await ctx.request.get(base + '/api' + route, {maxRedirects: 0});
  check(response.status() === expected, 'authorized_read_unexpected_status_' + response.status());
  return expected === 200 ? response.json() : null;
}
async function noAi(entry, parent) {
  const usage = await get(parent, '/families/' + entry.demo.user.families[0].id + '/usage');
  check(usage.calls_used === 0 && usage.known_cost_micros_usd === 0 &&
    usage.unknown_cost_calls === 0 && usage.records.length === 0, 'demo_must_not_reserve_or_consume_external_ai');
  entry.zero_usage_verified = true;
  await save();
}
async function shot(page, entry, label) {
  check(entry.child_authenticated === true, 'never_capture_login_credentials');
  const filename = `page-review-${journal.run_id}-case${entry.index}-${label}.png`;
  await privateWrite(path.join(artifacts, filename), await page.screenshot());
  screenshots.push(filename);
}
async function makeDemo(index) {
  step('create_own_fixed_demo_' + index);
  const intent = {demo: true, demoPosts: 0, loginPosts: 0, confirmPosts: 0, deletePosts: 0};
  const parent = await context('parent', intent), parentPage = await parent.newPage();
  await open(parentPage, '/');
  const response = await responseFor(parentPage, 'POST', '/demo', () => tap(parentPage, button(parentPage, 'Demo ausprobieren')));
  check(response.status() === 201, 'own_fixed_demo_creation_failed_' + response.status());
  const entry = {index, demo: await response.json(), deleted: false};
  // Persist the newly returned credentials before any subsequent UI assertion.
  journal.entries.push(entry);
  created.push(entry);
  live.set(index, {parent, parentPage, intent});
  await save();
  check(ownDemo(entry) && intent.demoPosts === 1, 'only_new_fixed_owned_demo_households_allowed');
  entry.parentCookies = await parent.cookies();
  await save();
  check(entry.parentCookies.some(cookie => cookie.name === 'sp_session' && cookie.secure &&
    cookie.httpOnly && cookie.sameSite === 'Strict'), 'secure_demo_parent_cookie_required');
  await parentPage.waitForURL(base + '/app', {timeout: 45000});
  await noAi(entry, parent);
  return entry;
}
async function childLogin(entry) {
  step('independent_child_ui_login_' + entry.index);
  const runtime = live.get(entry.index);
  runtime.childIntent = {login: true, material: entry.demo.material_id,
    demoPosts: 0, loginPosts: 0, confirmPosts: 0, deletePosts: 0};
  const child = await context('child', runtime.childIntent), page = await child.newPage();
  Object.assign(runtime, {child, page});
  await open(page, '/login');
  await type(page, page.getByRole('textbox', {name: 'E-Mail oder Benutzername', exact: true}), entry.demo.credentials.child_username);
  await type(page, page.getByLabel('Passwort', {exact: true}), entry.demo.credentials.child_password);
  const response = await responseFor(page, 'POST', '/auth/login', () => tap(page, button(page, 'Anmelden')));
  check(response.status() === 200, 'independent_child_ui_login_failed');
  const identity = (await response.json()).user;
  check(identity?.role === 'child' && identity.child_id === entry.demo.child_id && identity.synthetic === true,
    'child_login_must_match_the_new_owned_demo');
  entry.child_authenticated = true;
  entry.childCookies = await child.cookies();
  await save();
  check(entry.childCookies.some(cookie => cookie.name === 'sp_session' && cookie.secure &&
    cookie.httpOnly && cookie.sameSite === 'Strict'), 'secure_independent_child_cookie_required');
  await page.waitForURL(base + '/app', {timeout: 45000});
  const source = await get(child, '/materials/' + entry.demo.material_id);
  check(source.child_id === entry.demo.child_id && source.synthetic === true && !source.fixture_id &&
    source.status === 'review' && source.confirmed === false && source.uncertainties.length > 0,
    'fresh_demo_must_contain_one_fixed_unconfirmed_source_with_visible_uncertainty');
  runtime.source = source;
  return source;
}
async function reviewAt(entry, width) {
  const {page} = live.get(entry.index);
  await page.setViewportSize({width, height: 844});
  await open(page, '/material/' + entry.demo.material_id);
  await reveal(page, button(page, 'Stimmt, weiter'));
  check(await page.getByRole('checkbox').count() === 0, 'page_review_must_not_require_any_checkbox');
  await reveal(page, page.getByText('Hier bitte genau hinschauen:', {exact: true}));
  for (const warning of live.get(entry.index).source.uncertainties) {
    await reveal(page, page.getByText(warning, {exact: true}));
  }
  await reveal(page, button(page, 'Seite löschen'));
  const box = await (await reveal(page, button(page, 'Stimmt, weiter'))).boundingBox();
  check(box.width >= 120 && box.height >= 44, 'direct_confirmation_needs_mobile_touch_target');
  await shot(page, entry, 'review-' + width);
}
async function confirmCase(entry) {
  const before = await childLogin(entry);
  const runtime = live.get(entry.index);
  for (const width of [390, 320]) await reviewAt(entry, width);
  step('direct_child_confirmation_without_checkbox');
  runtime.childIntent.confirm = true;
  const response = await responseFor(runtime.page, 'PUT', '/materials/' + entry.demo.material_id + '/confirm',
    () => tap(runtime.page, button(runtime.page, 'Stimmt, weiter')));
  check(response.status() === 200, 'direct_child_confirmation_failed');
  const sent = response.request().postDataJSON(), saved = await response.json();
  check(sent.uncertainties_resolved === true && saved.confirmed === true && saved.status === 'confirmed' &&
    saved.uncertainties.length === 0 && saved.content === before.content &&
    saved.subject === before.subject && saved.topic === before.topic &&
    JSON.stringify(saved.homework) === JSON.stringify(before.homework),
    'direct_confirmation_must_explicitly_save_unchanged_reviewed_source');
  check(runtime.childIntent.confirmPosts === 1, 'only_one_deliberate_confirmation_is_allowed');
  for (const width of [320, 390]) {
    await runtime.page.setViewportSize({width, height: 844});
    await open(runtime.page, '/material/' + entry.demo.material_id);
    await reveal(runtime.page, runtime.page.getByText('Seite geprüft', {exact: true}));
    check(await button(runtime.page, 'Seite löschen').count() === 0 &&
      await button(runtime.page, 'Stimmt, weiter').count() === 0 &&
      await runtime.page.getByRole('checkbox').count() === 0,
      'confirmed_child_source_must_show_no_delete_or_confirmation_control');
    await shot(runtime.page, entry, 'confirmed-' + width);
  }
  const persisted = await get(runtime.child, '/materials/' + entry.demo.material_id);
  check(persisted.confirmed && sourceSignature(persisted) === sourceSignature(saved),
    'confirmation_must_survive_reload_without_another_write');
  await noAi(entry, runtime.parent);
  completedCases.push('direct_confirmation_320_390_and_confirmed_source_protection');
}
async function deletionCase(entry) {
  const before = await childLogin(entry), runtime = live.get(entry.index);
  await reviewAt(entry, 320);
  step('cancel_child_page_deletion');
  await tap(runtime.page, button(runtime.page, 'Seite löschen'));
  await reveal(runtime.page, runtime.page.getByText('Seite löschen?', {exact: true}), {modal: true});
  check(runtime.childIntent.deletePosts === 0, 'opening_delete_dialog_must_not_delete');
  await shot(runtime.page, entry, 'delete-dialog-320');
  await tap(runtime.page, button(runtime.page, 'Abbrechen'), {modal: true});
  check(runtime.page.url() === base + '/material/' + entry.demo.material_id &&
    runtime.childIntent.deletePosts === 0, 'cancel_must_keep_the_page_and_send_no_delete');
  const untouched = await get(runtime.child, '/materials/' + entry.demo.material_id);
  check(!untouched.confirmed && sourceSignature(untouched) === sourceSignature(before),
    'cancelled_deletion_must_preserve_source');
  step('explicit_child_page_deletion_and_return_home');
  await tap(runtime.page, button(runtime.page, 'Seite löschen'));
  await reveal(runtime.page, runtime.page.getByText('Seite löschen?', {exact: true}), {modal: true});
  runtime.childIntent.remove = true;
  const response = await responseFor(runtime.page, 'DELETE', '/materials/' + entry.demo.material_id,
    () => tap(runtime.page, button(runtime.page, 'Bestätigen'), {modal: true}));
  check(response.status() === 200 && runtime.childIntent.deletePosts === 1, 'confirmed_delete_must_send_exactly_one_real_delete');
  await runtime.page.waitForURL(base + '/app', {timeout: 45000});
  await get(runtime.child, '/materials/' + entry.demo.material_id, 404);
  await get(runtime.parent, '/materials/' + entry.demo.material_id, 404);
  await shot(runtime.page, entry, 'deleted-return-home-320');
  await noAi(entry, runtime.parent);
  completedCases.push('delete_cancel_preserves_source_then_real_delete_returns_home');
}
async function cleanup(entry) {
  check(ownDemo(entry), 'refuse_cleanup_outside_this_owned_fixed_demo');
  let runtime = live.get(entry.index);
  if (!runtime) {
    const intent = {};
    runtime = {parent: await context('parent', intent, {cookies: entry.parentCookies ?? [], origins: []}),
      child: await context('child', intent, {cookies: entry.childCookies ?? [], origins: []})};
    live.set(entry.index, runtime);
  }
  // Close Flutter pages first: cleanup must not trigger UI refresh or any work.
  for (const ctx of [runtime.parent, runtime.child].filter(Boolean)) {
    await Promise.all(ctx.pages().map(page => page.close()));
  }
  if (!entry.deleted) {
    step('delete_own_demo_family_' + entry.index);
    let identityResponse = await runtime.parent.request.get(base + '/api/auth/me');
    if (identityResponse.status() === 401) {
      const login = await runtime.parent.request.post(base + '/api/auth/login', {headers,
        data: {username: entry.demo.credentials.parent_username, password: entry.demo.credentials.parent_password,
          device: 'Page review QA cleanup'}});
      check(login.status() === 200, 'own_demo_cleanup_login_failed');
      identityResponse = await runtime.parent.request.get(base + '/api/auth/me');
    }
    check(identityResponse.status() === 200, 'own_demo_cleanup_identity_unavailable');
    const identity = await identityResponse.json();
    check(identity.id === entry.demo.user.id && identity.role === 'parent' &&
      identity.families?.length === 1 && identity.families[0].id === entry.demo.user.families[0].id &&
      identity.families[0].synthetic === true && identity.families[0].permission === 'owner',
      'own_demo_cleanup_identity_mismatch');
    // A failed usage assertion must never prevent deleting this owned family.
    try { await noAi(entry, runtime.parent); }
    catch { entry.zero_usage_verified = false; entry.usage_check_failed = true; }
    const removed = await runtime.parent.request.delete(base + '/api/account',
      {headers, data: {password: entry.demo.credentials.parent_password}});
    check(removed.status() === 200, 'normal_own_demo_family_cleanup_failed');
    entry.deleted = true;
    await save();
  }
  await get(runtime.parent, '/auth/me', 401);
  if (runtime.child) await get(runtime.child, '/auth/me', 401);
  entry.sessions_invalidated = true;
  await save();
  await runtime.parent.close();
  if (runtime.child) await runtime.child.close();
  live.delete(entry.index);
}
function localChecks() {
  const intent = {material: 'own-source'};
  for (const suffix of ['/prepare', '/extract', '/units', '/tutor', '/coaching']) {
    assert.equal(permittedMutation('child', 'POST', '/api' + suffix, intent), false);
  }
  assert.equal(permittedMutation('child', 'DELETE', '/api/materials/own-source', intent), false);
  assert.equal(permittedMutation('child', 'DELETE', '/api/materials/own-source', {...intent, remove: true}), true);
  assert.equal(permittedMutation('child', 'DELETE', '/api/materials/another-source', {...intent, remove: true}), false);
  assert.equal(permittedMutation('child', 'PUT', '/api/materials/own-source/confirm', {...intent, confirm: true}), true);
  assert.equal(permittedMutation('parent', 'PUT', '/api/materials/own-source/confirm', {...intent, confirm: true}), false);
  assert.equal(permittedMutation('parent', 'POST', '/api/demo', {demo: true}), true);
  assert.equal(permittedMutation('child', 'POST', '/api/demo', {demo: true}), false);
  assert.equal(ownDemo({demo: {user: {role: 'parent', id: 'p', families: [{id: 'f', synthetic: false, permission: 'owner'}]},
    child_id: 'c', material_id: 'm', credentials: {parent_username: 'eltern-0123456789', child_username: 'kind-0123456789',
      parent_password: 'artificial-password', child_password: 'artificial-password'}}}), false);
  assert.equal(safeReason(new Error('sensitive value')), 'browser_or_local_io_operation_failed');
}
async function main() {
  localChecks();
  if (mode === '--help' || mode === '--check') {
    console.log(JSON.stringify({qa_driver: 'page_review', local_guard_checks: 'passed', public_requests: 0,
      next_command_after_deployment_go: 'node qa/page_review.mjs --run',
      recovery_command: 'node qa/page_review.mjs --cleanup-only'}));
    return;
  }
  check(mode === '--run' || mode === '--cleanup-only', 'use_check_run_or_cleanup_only');
  await mkdir(artifacts, {recursive: true});
  journal = await readJournal();
  if (mode === '--run') {
    check(!journal, 'previous_own_demo_journal_requires_cleanup_only_before_a_new_run');
    journal = {purpose: 'page-review-fixed-demo-only', version: 1,
      run_id: new Date().toISOString().replace(/[-:.]/g, ''), entries: []};
    await save();
  } else {
    check(journal?.purpose === 'page-review-fixed-demo-only' && journal.version === 1 &&
      Array.isArray(journal.entries) && journal.entries.length <= 2 && journal.entries.every(ownDemo),
      'cleanup_requires_the_protected_owned_demo_journal');
  }
  let failure, failedPhase;
  try {
    browser = await chromium.launch({headless: true, executablePath: process.env.CHROME_PATH || '/opt/google/chrome/chrome',
      timeout: 15000, args: ['--no-sandbox']});
    if (mode === '--run') {
      const confirm = await makeDemo(1);
      await confirmCase(confirm);
      await cleanup(confirm);
      const remove = await makeDemo(2);
      await deletionCase(remove);
      await cleanup(remove);
      check(blocked.length === 0, 'unexpected_mutation_was_blocked');
      check(errors.length === 0, 'browser_runtime_errors_detected');
      check(created.length === 2 && created.every(entry => entry.zero_usage_verified), 'two_fixed_demo_cases_required');
    }
    passed = true;
  } catch (error) {
    failure = safeReason(error);
    failedPhase = phase;
  } finally {
    const cleanupErrors = [];
    if (browser) for (const entry of journal.entries) {
      if (entry.deleted && entry.sessions_invalidated) continue;
      try { await cleanup(entry); } catch (error) { cleanupErrors.push(safeReason(error)); }
    }
    cleanupComplete = journal.entries.every(entry => entry.deleted && entry.sessions_invalidated);
    const zeroAiVerified = journal.entries.every(entry => entry.zero_usage_verified && !entry.usage_check_failed);
    const report = {url: base, mode, qa_passed: passed && cleanupComplete && cleanupErrors.length === 0 &&
        (mode === '--cleanup-only' || zeroAiVerified),
      failure: failure ?? null, failed_phase: failedPhase ?? null,
      cleanup_complete: cleanupComplete, cleanup_errors: cleanupErrors,
      demo_families_created: journal.entries.length, demo_families_deleted: journal.entries.filter(entry => entry.deleted).length,
      independent_child_ui_logins: journal.entries.filter(entry => entry.child_authenticated).length,
      external_ai_calls: zeroAiVerified ? 0 : null,
      viewports: mode === '--run' ? [320, 390] : [], checks: completedCases,
      screenshots, blocked_mutations: blocked, browser_runtime_errors: errors, completed: new Date().toISOString()};
    await privateWrite(reportFile, JSON.stringify(report, null, 2));
    if (cleanupComplete) await unlink(journalFile);
    if (browser) await browser.close();
    console.log(JSON.stringify(report));
    if (!report.qa_passed) process.exitCode = 1;
  }
}
main().catch(error => {
  console.log(JSON.stringify({qa_passed: false, phase, failure: safeReason(error)}));
  process.exitCode = 1;
});
