// Explicit normal-account synthetic provider smoke. At most one initial OCR,
// one reread and one new unit; recorded jobs are resumed with GETs, never retried.
// Credentials, snapshots, IDs and job checkpoints stay in ignored private files.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {chmod, readFile, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {chromium, request} from 'playwright';

const root = fileURLToPath(new URL('../', import.meta.url));
const out = path.join(root, 'artifacts');
const privateFile = path.join(out, '.school-day-qa-account.json');
const base = 'https://schulpilot.dorfspy.de';
const headers = {'X-Schulpilot-Request': '1', 'X-Client-Platform': 'native'};
let browser, context, page, phase = 'setup';
const checks = [], modelWrites = [], errors = [];
async function save(account) {
  await writeFile(privateFile, JSON.stringify(account) + '\n', {mode: 0o600});
  await chmod(privateFile, 0o600);
}
async function data() {
  const account = JSON.parse(await readFile(privateFile, 'utf8'));
  assert(account.normal_account && account.verified && account.notebook_actions?.material_ids?.length === 6 &&
    /\+schulpilot-normal-qa-[a-f0-9]{12}@/.test(account.credentials.parent_username), 'own_normal_artificial_account_required');
  account.notebook_reprocess_smoke ??= {source_id: account.notebook_actions.material_ids[0]};
  assert.equal(account.notebook_reprocess_smoke.source_id, account.notebook_actions.material_ids[0]);
  return account;
}
async function json(response, expected = 200) {
  assert.equal(response.status(), expected, 'owned_smoke_api_status_' + response.status());
  return response.json();
}
const snapshot = source => createHash('sha256').update(JSON.stringify(
  ['id', 'child_id', 'revision', 'confirmed', 'subject', 'topic', 'content', 'homework'].map(key => source[key]),
)).digest('hex');
function checkOriginal(source) {
  const compact = source.content.normalize('NFC').toLocaleLowerCase('de-DE')
    .replace(/\\frac\{(\d+)\}\{(\d+)\}/g, '$1/$2').replace(/\s+/g, '');
  assert(['mathematik', 'mathe'].includes(source.subject.trim().toLocaleLowerCase('de-DE')),
    'fixed_artificial_math_subject_required');
  for (const term of ['zähler', 'nenner', 'dieselbezahl', 'teilen', '3/9=1/3', '6/12=1/2']) {
    assert(compact.includes(term), 'fixed_artificial_source_transcription_mismatch');
  }
  assert.deepEqual(source.homework, [], 'printed_examples_must_not_become_homework');
  assert((source.uncertainties ?? []).length === 0, 'uncertain_ocr_requires_manual_source_check_no_retry');
}
async function poll(api, jobId) {
  const deadline = Date.now() + 210000;
  while (Date.now() < deadline) {
    const job = await json(await api.get('/api/jobs/' + jobId));
    if (job.status === 'failed') throw new Error('recorded_smoke_job_failed_no_automatic_retry');
    if (job.status === 'completed') return job;
    assert(['queued', 'running'].includes(job.status), 'unexpected_smoke_job_state');
    await new Promise(resolve => setTimeout(resolve, 2500));
  }
  throw new Error('recorded_smoke_job_pending_resume_only_get');
}
async function initial() {
  const account = await data();
  const state = account.notebook_reprocess_smoke;
  let api = await request.newContext({baseURL: base, extraHTTPHeaders: headers});
  try {
    const signed = await json(await api.post('/api/auth/login', {data: {
      username: account.credentials.child_username, password: account.credentials.child_password,
    }}));
    assert.equal(signed.user.child_id, account.child_id);
    await api.dispose();
    api = await request.newContext({baseURL: base,
      extraHTTPHeaders: {...headers, Authorization: 'Bearer ' + signed.token}});
    if (!state.initial_job_id) {
      const source = await json(await api.get('/api/materials/' + state.source_id));
      assert(!source.confirmed && source.synthetic === false);
      state.initial_request_started = true;
      await save(account);
      const job = await json(await api.post('/api/materials/' + state.source_id + '/extract', {
        data: {}, headers: {'Idempotency-Key': 'notebook-actions-original-ocr-v1'},
      }), 202);
      state.initial_job_id = job.id;
      await save(account);
    }
    phase = 'initial_extract_waiting';
    await poll(api, state.initial_job_id);
    const source = await json(await api.get('/api/materials/' + state.source_id));
    checkOriginal(source);
    if (!source.confirmed) {
      const confirmed = await json(await api.put('/api/materials/' + state.source_id + '/confirm', {data: {
        revision: source.revision, subject: source.subject, topic: source.topic,
        content: source.content, homework: [], uncertainties_resolved: true, task_decisions: [],
      }}));
      assert.equal(confirmed.confirmed, true);
    }
    const confirmed = await json(await api.get('/api/materials/' + state.source_id));
    state.original_snapshot = snapshot(confirmed);
    state.initial_confirmed = true;
    state.original_revision = confirmed.revision;
    state.phase = 'initial_confirmed_waiting_for_release50';
    await save(account);
    await json(await api.post('/api/auth/logout', {data: {}}));
    console.log(JSON.stringify({success: true, phase: state.phase, actual_reserved_jobs: 1,
      fixed_artificial_source_checked: true, explicitly_confirmed: true, external_provider_cost: 'unknown'}));
  } finally { await api.dispose(); }
}

async function open(route) {
  await page.goto(base + route, {waitUntil: 'domcontentloaded', timeout: 90000});
  await page.waitForSelector('flutter-view', {timeout: 90000});
  await page.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(node => node.click()));
  await page.waitForTimeout(400);
}
async function tap(locator) {
  const target = locator.first();
  for (let n = 0; n < 45; n++) {
    const box = await target.count() ? await target.boundingBox().catch(() => null) : null;
    if (box && box.width && box.height && box.y >= 0 && box.y + box.height < page.viewportSize().height - 80) {
      await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
      await page.waitForTimeout(250); return;
    }
    await page.mouse.move(page.viewportSize().width / 2, page.viewportSize().height / 2);
    await page.mouse.wheel(0, n === 0 && !box ? -4000 : box && box.y < 0 ? -300 : 300);
    await page.waitForTimeout(160);
  }
  throw new Error('owned_smoke_control_not_visible');
}
const button = name => page.getByRole('button', {name, exact: true});
async function type(locator, value) {
  await tap(locator); await page.keyboard.press('Control+A'); await page.keyboard.type(value, {delay: 5});
  await page.keyboard.press('Tab'); await page.waitForTimeout(250);
}
async function reprocess() {
  // Implemented only as the deliberate browser continuation of the recorded
  // successful initial OCR; the separate caller waits for release50 deployment.
  const account = await data();
  const state = account.notebook_reprocess_smoke;
  assert(state.initial_confirmed && state.original_snapshot, 'confirm_initial_artificial_source_first');
  const release = await (await fetch(base + '/api/app-release')).json();
  assert.equal(release.version_code, 50, 'public_release50_required');
  browser = await chromium.launch({headless: true, executablePath: '/opt/google/chrome/chrome', args: ['--no-sandbox']});
  context = await browser.newContext({viewport: {width: 390, height: 1000}, isMobile: true, hasTouch: true});
  page = await context.newPage();
  page.on('pageerror', () => errors.push(phase));
  await open('/login');
  await type(page.getByRole('textbox', {name: 'E-Mail oder Benutzername', exact: true}), account.credentials.child_username);
  await type(page.getByLabel('Passwort', {exact: true}), account.credentials.child_password);
  await tap(button('Anmelden'));
  await page.waitForURL(base + '/app');
  const get = async route => json(await context.request.get(base + '/api' + route, {headers: {'X-Schulpilot-Request': '1'}}));
  const original = await get('/materials/' + state.source_id);
  assert.equal(snapshot(original), state.original_snapshot, 'original_source_changed_before_reread');
  page.on('request', request => {
    const pathname = new URL(request.url()).pathname;
    if (request.method() === 'POST' && /\/(reprocess|extract|units)$/.test(pathname)) modelWrites.push(pathname);
  });
  if (!state.reprocess_job_id) {
    assert(!state.reprocess_request_started, 'uncertain_reread_submission_manual_inspection_required');
    phase = 'explicit_browser_reread';
    await open('/material/' + state.source_id);
    await tap(button('Mit KI neu lesen'));
    await page.getByText('Seite neu einlesen?', {exact: true}).waitFor();
    state.reprocess_request_started = true;
    await save(account);
    const reply = page.waitForResponse(response => response.request().method() === 'POST' &&
      new URL(response.url()).pathname === '/api/materials/' + state.source_id + '/reprocess', {timeout: 45000});
    await tap(button('Bestätigen'));
    const result = await json(await reply, 202);
    state.reprocess_job_id = result.id;
    state.new_source_id = result.material_id;
    assert.notEqual(state.new_source_id, state.source_id);
    await save(account);
  }
  phase = 'reread_status_reload';
  const statusRoute = '/material/' + state.new_source_id + '/processing/' + state.reprocess_job_id;
  await open(statusRoute);
  const beforeReload = modelWrites.length;
  await page.reload({waitUntil: 'domcontentloaded'});
  await page.waitForSelector('flutter-view');
  await page.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(node => node.click()));
  await button('Seite prüfen').waitFor({timeout: 210000});
  assert.equal(modelWrites.length, beforeReload, 'status_reload_must_not_restart_ai');
  await tap(button('Seite prüfen'));
  const newSource = await get('/materials/' + state.new_source_id);
  checkOriginal(newSource);
  if (!newSource.confirmed) {
    const previewResponse = page.waitForResponse(response => response.request().method() === 'POST' &&
      new URL(response.url()).pathname === '/api/materials/' + state.new_source_id + '/task-preview');
    await tap(button('Stimmt, weiter'));
    const preview = await json(await previewResponse);
    assert(preview.items.every(item => item.classification !== 'homework'), 'printed_examples_must_not_become_compulsory_tasks');
    if ((preview.items ?? []).length || (preview.duplicates ?? []).length) {
      const keep = preview.duplicates.length && !preview.items.length ? 'Seite bewusst behalten' : 'Auswahl übernehmen';
      await tap(button(keep));
    }
  }
  for (let n = 0; n < 30; n++) {
    if ((await get('/materials/' + state.new_source_id)).confirmed) break;
    await page.waitForTimeout(250);
  }
  assert.equal((await get('/materials/' + state.new_source_id)).confirmed, true);
  assert.equal(snapshot(await get('/materials/' + state.source_id)), state.original_snapshot);
  state.reprocess_confirmed = true;
  await save(account);
  checks.push('normal_browser_reread_new_photo_source_existing_original_unchanged');
  phase = 'explicit_new_learning_round';
  if (!state.unit_job_id) {
    assert(!state.unit_request_started, 'uncertain_unit_submission_manual_inspection_required');
    state.unit_request_started = true;
    await save(account);
    const unitResponse = page.waitForResponse(response => response.request().method() === 'POST' &&
      new URL(response.url()).pathname === '/api/children/' + account.child_id + '/units', {timeout: 45000});
    await tap(button('Jetzt lernen'));
    const result = await json(await unitResponse, 202);
    state.unit_job_id = result.id;
    await save(account);
  }
  const job = await poll({get: route => context.request.get(base + route, {headers: {'X-Schulpilot-Request': '1'}})}, state.unit_job_id);
  assert.equal(job.kind, 'unit');
  assert(typeof job.result?.unit_id === 'string');
  state.unit_id = job.result.unit_id;
  await save(account);
  const unit = await get('/units/' + state.unit_id);
  assert(unit.questions.length >= 2 && unit.questions.length <= 5);
  assert.equal(unit.attempts?.length ?? 0, 0);
  assert.equal(snapshot(await get('/materials/' + state.source_id)), state.original_snapshot);
  // The ordinary material action may start the newly created round. Stop at
  // its explanation and pause explicitly; never submit artificial answers.
  if (unit.status === 'active') {
    await page.waitForURL(base + '/unit/' + state.unit_id, {timeout: 20000});
    await button('Pause').first().waitFor();
    await tap(button('Pause'));
  }
  assert.equal((await get('/units/' + state.unit_id)).attempts?.length ?? 0, 0);
  assert(modelWrites.length <= 2, 'at_most_reread_and_one_new_unit_from_browser');
  assert.equal(errors.length, 0, 'browser_runtime_error_during_normal_smoke');
  checks.push('new_round_explicitly_generated_from_confirmed_new_source_without_answers');
  checks.push('source_confirmation_and_status_reload_generate_no_additional_jobs');
  state.phase = 'normal_browser_smoke_passed';
  await save(account);
  await json(await context.request.post(base + '/api/auth/logout', {headers: {'X-Schulpilot-Request': '1'}, data: {}}));
  const report = {success: true, phase: state.phase, checks, public_flutter_build: release.version_code,
    actual_reserved_jobs: 3, browser_model_writes: modelWrites.length, generated_questions: unit.questions.length,
    submitted_answers: 0, original_source_unchanged: true, external_provider_cost: 'unknown',
    dataset_key: createHash('sha256').update(account.child_id).digest('hex')};
  await writeFile(path.join(out, 'notebook-reprocess-smoke-result.json'), JSON.stringify(report) + '\n', {mode: 0o600});
  console.log(JSON.stringify(report));
}

try {
  if (process.argv.includes('--initial')) await initial();
  else if (process.argv.includes('--reprocess')) await reprocess();
  else throw new Error('choose_initial_or_reprocess');
} catch (error) {
  console.log(JSON.stringify({success: false, phase, error: String(error.message).slice(0, 180)}));
  process.exitCode = 1;
} finally { await browser?.close(); }
