// Actual public Flutter PDF selection/preview/confirmation; own artificial family only.
import assert from 'node:assert/strict';
import {chromium} from 'playwright';
import {readFile, writeFile, chmod} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const base = 'https://schulpilot.dorfspy.de';
const out = fileURLToPath(new URL('../artifacts/', import.meta.url));
const privateFile = path.join(out, '.school-day-qa-account.json');
const headers = {'X-Schulpilot-Request': '1', 'X-Schulpilot-Capabilities': 'language-v1,grade-pdf-v1'};
let browser, page, context, account, state, phase = 'initial';
const errors = [], checks = [];
const button = name => page.getByRole('button', {name, exact: true});
async function checkpoint(patch) {
  Object.assign(state, patch);
  account.grade_pdf_qa = state;
  await writeFile(privateFile, JSON.stringify(account) + '\n', {mode: 0o600});
  await chmod(privateFile, 0o600);
}
async function open(route) {
  await page.goto(base + route, {waitUntil: 'domcontentloaded', timeout: 90000});
  await page.waitForSelector('flutter-view', {timeout: 90000});
  await page.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(n => n.click()));
  await page.waitForTimeout(350);
}
async function tap(locator) {
  const target = locator.first();
  for (let i = 0; i < 30; i++) {
    const box = await target.count() ? await target.boundingBox().catch(() => null) : null;
    if (box && box.width > 0 && box.y >= 0 && box.y + box.height < page.viewportSize().height - 8) {
      await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
      await page.waitForTimeout(220);
      return;
    }
    await page.mouse.move(page.viewportSize().width / 2, page.viewportSize().height / 2);
    await page.mouse.wheel(0, box && box.y < 0 ? -260 : 260);
    await page.waitForTimeout(150);
  }
  throw new Error('grade_ui_control_not_visible');
}
async function type(locator, value) {
  await tap(locator);
  await page.keyboard.press('Control+A');
  await page.keyboard.type(value, {delay: 10});
  assert.equal(await locator.inputValue(), value, 'input_not_received');
}
async function api(route) {
  const r = await context.request.get(base + '/api' + route, {headers});
  assert.equal(r.status(), 200, 'owned_read_failed');
  return r.json();
}
async function upload(which) {
  await tap(button('PDF importieren'));
  const waiter = page.waitForEvent('filechooser', {timeout: 20000});
  waiter.catch(() => {});
  const response = page.waitForResponse(r => r.request().method() === 'POST' && new URL(r.url()).pathname === `/api/children/${account.child_id}/grade-imports`, {timeout: 45000});
  response.catch(() => {});
  await tap(button('PDF auswählen'));
  const chooser = await waiter;
  await chooser.setFiles(path.join(out, `grades-synthetic-${which}.pdf`));
  const r = await response;
  assert.equal(r.status(), 201, 'pdf_upload_failed');
  const preview = await r.json();
  await page.waitForTimeout(400);
  return preview;
}
async function confirm(preview) {
  const response = page.waitForResponse(r => r.request().method() === 'POST' && new URL(r.url()).pathname === `/api/children/${account.child_id}/grade-imports/${preview.id}/confirm`, {timeout: 30000});
  response.catch(() => {});
  await tap(button('Auswahl übernehmen'));
  const r = await response;
  assert.equal(r.status(), 200, 'pdf_confirmation_failed');
  await page.waitForTimeout(250);
  const result = await r.json();
  await tap(button('Fertig'));
  return result;
}
async function shot(name) {
  const file = path.join(out, `grade-pdf-web-${name}.png`);
  await page.screenshot({path: file});
  await chmod(file, 0o600);
}

if (!process.argv.includes('--run')) {
  console.log(JSON.stringify({ready: true, requires: 'prepare_grade_smoke.py, deployed 1.5.0, then --run'}));
  process.exit(0);
}
try {
  account = JSON.parse(await readFile(privateFile, 'utf8'));
  state = account.grade_pdf_qa;
  assert(account.normal_account && account.verified && state?.manual_id && /\+schulpilot-normal-qa-[a-f0-9]{12}@/.test(account.credentials.parent_username), 'own_fixture_required');
  const health = await (await fetch(base + '/api/health')).json();
  assert.equal(health.version, '1.5.0', 'deploy_pdf_release_first');
  browser = await chromium.launch({headless: true, executablePath: '/opt/google/chrome/chrome', args: ['--no-sandbox']});
  context = await browser.newContext({viewport: {width: 390, height: 900}, isMobile: true, hasTouch: true});
  page = await context.newPage();
  page.on('pageerror', () => errors.push(phase));
  phase = 'normal_parent_login';
  await open('/login');
  await type(page.getByRole('textbox', {name: 'E-Mail oder Benutzername', exact: true}), account.credentials.parent_username);
  await type(page.getByLabel('Passwort', {exact: true}), account.credentials.parent_password);
  const loginWait = page.waitForResponse(r => new URL(r.url()).pathname === '/api/auth/login' && r.request().method() === 'POST');
  await tap(button('Anmelden'));
  const login = await (await loginWait).json();
  assert.equal(login.user.id, account.user.id);
  await page.waitForURL(base + '/app');
  await open('/grades/' + account.child_id);
  await button('PDF importieren').waitFor();
  if (!state.first_done) {
    phase = 'first_pdf_and_manual_match';
    const preview = await upload('first');
    assert.equal(preview.items.length, 4);
    if (preview.counts.possible_match === 1) {
      assert.equal(preview.counts.new, 3);
      const manual = preview.items.find(r => r.status === 'possible_match');
      assert.equal(manual.matches.length, 1);
      assert.equal(manual.matches[0].id, state.manual_id);
      await tap(page.getByRole('button', {name: /^Übernahme$/}));
      await tap(page.getByRole('menuitem', {name: /Schon erfasst.*Künstliche Kontrollnote/s}));
    } else {
      assert.equal(preview.counts.existing, 4, 'only_resume_an_already_committed_first_import');
    }
    await shot('mobile-preview');
    const saved = await confirm(preview);
    assert.equal(saved.added + saved.linked + saved.unchanged, 4);
    const listed = await api('/children/' + account.child_id + '/grades');
    assert.equal(listed.pagination.total, 4);
    assert.equal(listed.items.find(r => r.id === state.manual_id).date_precision, 'day');
    assert.equal(listed.items.filter(r => r.assessed_on === null).length, 3);
    await checkpoint({first_done: true, phase: 'first_confirmed'});
    checks.push('native_browser_file_dialog_and_manual_match_without_duplicate');
  }
  phase = 'repeat_pdf_no_duplicate';
  const repeated = await upload('first');
  assert.equal(repeated.counts.existing, 4);
  assert.equal(repeated.counts.new, 0);
  const unchanged = await confirm(repeated);
  assert.equal(unchanged.unchanged, 4);
  assert.equal(unchanged.added, 0);
  checks.push('repeat_pdf_four_existing_zero_added');
  await page.reload({waitUntil: 'domcontentloaded'});
  await page.waitForSelector('flutter-view');
  await page.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(n => n.click()));
  await button('PDF importieren').waitFor();
  assert.equal((await api('/children/' + account.child_id + '/grades')).pagination.total, 4);
  await shot('mobile-saved');
  await page.setViewportSize({width: 1280, height: 1000});
  await page.waitForTimeout(350);
  await shot('desktop-saved');
  assert.deepEqual(errors, []);
  await checkpoint({phase: 'web_passed_native_pending'});
  await context.request.post(base + '/api/auth/logout', {headers, data: {}});
  const report = {success: true, actual_public_flutter: true, checks,
    grades: 4, undated: 3, preserved_manual_date: true, javascript_errors: errors.length, provider_calls: 0, source_commit: health.source_commit};
  await writeFile(path.join(out, 'grade-pdf-web-result.json'), JSON.stringify(report) + '\n');
  console.log(JSON.stringify(report));
} catch (e) {
  if (page) {
    await shot('failure').catch(() => {});
    const html = await page.locator('flt-semantics-host').innerHTML().catch(() => '');
    const file = path.join(out, 'grade-pdf-web-failure-semantics.html');
    await writeFile(file, html, {mode: 0o600});
  }
  console.log(JSON.stringify({success: false, phase, error: String(e.message).slice(0, 220), no_automatic_generation: true}));
  process.exitCode = 1;
} finally {
  await browser?.close();
}
