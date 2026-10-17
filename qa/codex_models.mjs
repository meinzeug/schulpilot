// Read-only public admin acceptance. No provider save, probe or inference.
// Credentials stay in the local operator file and the normal secure session.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile, writeFile, chmod} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright';

const base = 'https://schulpilot.dorfspy.de';
const artifacts = fileURLToPath(new URL('../artifacts/', import.meta.url));
const headers = {'X-Schulpilot-Request': '1'};
const digest = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const escape = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const errors = [], blocked = [], screenshots = [];
let browser, context, passed = false, loggedOut = false;
let phase = 'local_guard', modelCount = 0, changedModel = false, changedReasoning = false;

function check(condition, code) { if (!condition) throw new Error(code); }
async function get(path) {
  const response = await context.request.get(base + '/api' + path);
  check(response.status() === 200, 'protected_metadata_read_failed');
  return response.json();
}
async function visible(page, locator, modal = false) {
  const target = locator.first();
  const size = page.viewportSize();
  for (let n = 0; n < 35; n++) {
    const box = await target.count() ? await target.boundingBox().catch(() => null) : null;
    if (box && box.width > 0 && box.height > 0 && box.y >= (modal ? 2 : 75) &&
        box.y + box.height <= size.height - (modal ? 2 : 90)) return target;
    await page.mouse.move(size.width - 20, size.height - 135);
    await page.mouse.wheel(0, box && box.y < 75 ? -400 : 400);
    await page.waitForTimeout(180);
  }
  throw new Error('admin_choice_not_reachable');
}
async function tap(page, locator, modal = false) {
  const target = await visible(page, locator, modal);
  const box = await target.boundingBox();
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  await page.waitForTimeout(250);
}
function field(page, label) {
  const name = new RegExp(escape(label));
  return page.getByRole('combobox', {name}).or(page.getByRole('button', {name}))
    .or(page.getByLabel(label, {exact: false})).first();
}
async function shot(page, name) {
  const path = artifacts + 'codex-models-' + name + '.png';
  await page.screenshot({path});
  await chmod(path, 0o600);
  screenshots.push(path.split('/').at(-1));
}

async function main() {
  if (process.argv[2] !== '--run') {
    assert.equal(escape('gpt-6.1-sol'), 'gpt-6\\.1-sol');
    assert.ok(new RegExp('\\(' + escape('gpt-6.1-sol') + '\\)$').test('Example (gpt-6.1-sol)'));
    console.log(JSON.stringify({public_requests: 0, next: 'node qa/codex_models.mjs --run'}));
    return;
  }
  let failure;
  try {
    browser = await chromium.launch({headless: true, executablePath: '/opt/google/chrome/chrome'});
    context = await browser.newContext({viewport: {width: 1280, height: 950}});
    const password = (await readFile('/home/dennis/brpw.txt', 'utf8')).replace(/[\r\n]+$/, '');
    phase = 'normal_admin_login';
    const login = await context.request.post(base + '/api/auth/login', {headers,
      data: {username: 'admin', password, device: 'Codex model selector read-only QA'}});
    check(login.status() === 200, 'normal_admin_login_failed');
    check((await get('/auth/me')).role === 'admin', 'admin_role_required');
    const before = await get('/admin/provider');
    check(before.provider === 'codex', 'existing_codex_selection_required');
    const catalog = await get('/admin/provider/codex/models');
    check(catalog.source === 'codex_cli' && catalog.cli_version === '0.162.1' &&
      Array.isArray(catalog.models) && catalog.models.length > 0, 'real_worker_catalog_required');
    modelCount = catalog.models.length;
    const original = catalog.models.find(model => model.id === before.model);
    const photo = catalog.models.find(model => model.id === (before.extraction_model || before.model));
    check(original && photo && original.reasoning_efforts.includes(before.reasoning_effort),
      'saved_selection_must_be_preserved');
    const savedIndex = catalog.models.findIndex(model => model.id === before.model);
    const alternate = catalog.models.filter(model => model.id !== before.model &&
      model.input_modalities.includes('text') &&
      model.reasoning_efforts.some(value => photo.reasoning_efforts.includes(value)))
      .sort((a, b) => Math.abs(catalog.models.indexOf(a) - savedIndex) -
        Math.abs(catalog.models.indexOf(b) - savedIndex))[0];
    const page = await context.newPage();
    page.on('pageerror', error => errors.push(digest(error.message)));
    await context.route('**/api/**', async route => {
      const request = route.request();
      if (!['GET', 'HEAD'].includes(request.method())) {
        blocked.push(digest(new URL(request.url()).pathname));
        return route.abort('blockedbyclient');
      }
      return route.continue();
    });
    for (const width of [1280, 390, 320]) {
      phase = 'model_select_' + width;
      await page.setViewportSize({width, height: width === 1280 ? 950 : 844});
      await page.goto(base + '/admin', {waitUntil: 'domcontentloaded'});
      await page.waitForSelector('flutter-view', {timeout: 90000});
      await page.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(node => node.click()));
      await page.waitForTimeout(600);
      await visible(page, field(page, 'Modell für Lerneinheiten'));
      await visible(page, field(page, 'Reasoning / Denkstufe'));
      await shot(page, 'saved-' + width);
      if (alternate) {
        await tap(page, field(page, 'Modell für Lerneinheiten'));
        const option = new RegExp('\\(' + escape(alternate.id) + '\\)$');
        await tap(page, page.getByRole('option', {name: option}).or(page.getByText(option)), true);
        changedModel = true;
        const efforts = alternate.reasoning_efforts.filter(value => photo.reasoning_efforts.includes(value));
        await tap(page, field(page, 'Reasoning / Denkstufe'));
        await tap(page, page.getByRole('option', {name: efforts.at(-1), exact: true})
          .or(page.getByText(efforts.at(-1), {exact: true})).last(), true);
        changedReasoning = true;
        await shot(page, 'local-selection-' + width);
      }
    }
    phase = 'unchanged_live_configuration';
    check(digest(await get('/admin/provider')) === digest(before), 'read_only_test_must_not_change_configuration');
    check(blocked.length === 0 && errors.length === 0, 'unexpected_ui_request_or_runtime_error');
    passed = true;
  } catch (error) {
    failure = /^[a-z0-9_]{1,100}$/.test(error.message) ? error.message : 'browser_or_local_operation_failed';
  } finally {
    if (context) {
      const logout = await context.request.post(base + '/api/auth/logout', {headers}).catch(() => null);
      loggedOut = logout?.status() === 200 &&
        (await context.request.get(base + '/api/auth/me')).status() === 401;
    }
    const report = {passed: passed && loggedOut, phase, failure: failure ?? null,
      model_count: modelCount, viewports: [1280, 390, 320], local_model_selection_tested: changedModel,
      local_reasoning_selection_tested: changedReasoning, provider_saves: 0, inference_requests: 0,
      own_admin_session_revoked: loggedOut, screenshots, runtime_errors: errors, blocked_mutations: blocked};
    const path = artifacts + 'codex-models-browser-result.json';
    await writeFile(path, JSON.stringify(report, null, 2), {mode: 0o600});
    await chmod(path, 0o600);
    console.log(JSON.stringify(report));
    if (browser) await browser.close();
    if (!report.passed) process.exitCode = 1;
  }
}
main().catch(() => { console.log('{"passed":false,"failure":"local_setup_failed"}'); process.exitCode = 1; });
