// Actual public Flutter UI. Only the own regular artificial account from
// prepare_normal_ai_smoke.py is accepted. No model call is made by this driver.
// --prepare uploads six real JPGs through the normal authenticated upload API.
// --verify-final exercises controls; a separate explicit operator smoke may
// first OCR/confirm the first page. Reprocessing dialogs are cancelled here.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {chmod, readFile, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {chromium, request} from 'playwright';

const root = fileURLToPath(new URL('../', import.meta.url));
const out = path.join(root, 'artifacts');
const privateFile = path.join(out, '.school-day-qa-account.json');
const base = 'https://schulpilot.dorfspy.de';
const nativeHeaders = {'X-Schulpilot-Request': '1', 'X-Client-Platform': 'native'};
const args = process.argv.slice(2);
const buildIndex = args.indexOf('--build');
const build = Number(buildIndex < 0 ? 50 : args[buildIndex + 1]);
let browser, context, page, phase = 'setup';
const checks = [], errors = [], writes = [];
const button = name => page.getByRole('button', {name, exact: true});

async function accountData() {
  const account = JSON.parse(await readFile(privateFile, 'utf8'));
  assert(account.normal_account && account.verified &&
    /\+schulpilot-normal-qa-[a-f0-9]{12}@/.test(account.credentials.parent_username),
  'own_regular_artificial_household_required');
  return account;
}
async function save(account) {
  await writeFile(privateFile, JSON.stringify(account) + '\n', {mode: 0o600});
  await chmod(privateFile, 0o600);
}
async function json(response, status = 200) {
  assert.equal(response.status(), status, 'own_notebook_api_status_' + response.status());
  return response.json();
}
async function read(route) {
  return json(await context.request.get(base + '/api' + route, {headers: {'X-Schulpilot-Request': '1'}}));
}
async function open(route) {
  await page.goto(base + route, {waitUntil: 'domcontentloaded', timeout: 90000});
  await page.waitForSelector('flutter-view', {timeout: 90000});
  await page.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(node => node.click()));
  await page.waitForTimeout(450);
}
async function tap(locator) {
  const target = locator.first();
  for (let n = 0; n < 40; n++) {
    const box = await target.count() ? await target.boundingBox().catch(() => null) : null;
    if (box && box.width && box.height && box.y >= 0 && box.y + box.height < page.viewportSize().height - 80) {
      await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
      await page.waitForTimeout(250);
      return;
    }
    await page.mouse.move(page.viewportSize().width / 2, page.viewportSize().height / 2);
    await page.mouse.wheel(0, n === 0 && !box ? -5000 : box && box.y < 0 ? -300 : 300);
    await page.waitForTimeout(160);
  }
  throw new Error('owned_notebook_control_not_visible');
}
async function type(locator, value) {
  await tap(locator);
  await page.keyboard.press('Control+A');
  await page.keyboard.type(value, {delay: 5});
  await page.keyboard.press('Tab');
  await page.waitForTimeout(250);
}
async function login(account, role) {
  await open('/login');
  await type(page.getByRole('textbox', {name: 'E-Mail oder Benutzername', exact: true}), account.credentials[role + '_username']);
  await type(page.getByLabel('Passwort', {exact: true}), account.credentials[role + '_password']);
  await tap(button('Anmelden'));
  await page.waitForURL(base + '/app', {timeout: 30000});
}
function monitorWrites() {
  page.on('request', request => {
    const pathname = new URL(request.url()).pathname;
    if (pathname.startsWith('/api/') && request.method() !== 'GET') writes.push({path: pathname, method: request.method()});
  });
}
async function shot(name) {
  const destination = path.join(out, 'notebook-actions-' + name + '.png');
  await page.screenshot({path: destination});
  await chmod(destination, 0o600);
}
async function cancel() {
  await tap(button('Abbrechen'));
  await page.waitForTimeout(250);
}
async function unassignedCount(account) {
  return (await read('/children/' + account.child_id + '/materials?subject_id=unassigned')).total;
}
async function waitUnassignedCount(account, expected) {
  for (let n = 0; n < 40; n++) {
    if (await unassignedCount(account) === expected) return;
    await page.waitForTimeout(200);
  }
  assert.equal(await unassignedCount(account), expected);
}
function aiWriteCount() {
  return writes.filter(row => /\/(?:reprocess|extract|units)(?:\?|$)/.test(row.path)).length;
}
async function assertCancelledNoModel(action) {
  const before = aiWriteCount();
  await action();
  await cancel();
  assert.equal(aiWriteCount(), before, 'cancel_must_not_enqueue_ai');
}

async function prepare() {
  const account = await accountData();
  const api = await request.newContext({baseURL: base, extraHTTPHeaders: nativeHeaders});
  try {
    const signed = await json(await api.post('/api/auth/login', {data: {
      username: account.credentials.parent_username, password: account.credentials.parent_password,
    }}));
    assert.equal(signed.user.id, account.user.id);
    assert(signed.user.families.length === 1 && signed.user.families[0].synthetic === false);
    const authorization = {Authorization: 'Bearer ' + signed.token};
    account.notebook_actions ??= {material_ids: [], phase: 'uploading'};
    const state = account.notebook_actions;
    const generated = spawnSync(path.join(root, '.venv/bin/python'), ['-c', [
      'from pathlib import Path', 'from PIL import Image, ImageDraw, ImageFont',
      'root=Path("artifacts")', 'font=ImageFont.truetype("DejaVuSans.ttf",30)',
      'for n in range(2,6):',
      ' image=Image.new("RGB",(900,1250),"white")', ' draw=ImageDraw.Draw(image)',
      ' draw.text((45,80),"KÜNSTLICHER LÖSCHTEST",font=font,fill="black")',
      ' draw.text((45,170),f"Albumseite {n+1}",font=font,fill="black")',
      ' draw.text((45,260),"Keine echten Kinder- oder Lerndaten.",font=font,fill="black")',
      ' p=root/f"notebook-action-page-{n}.jpg"', ' image.save(p,"JPEG",quality=88)', ' p.chmod(0o600)',
    ].join('\n')], {cwd: root, encoding: 'utf8'});
    assert.equal(generated.status, 0, 'artificial_photo_creation_failed');
    for (let n = state.material_ids.length; n < 6; n++) {
      const filename = n < 2 ? account.image_paths[n] : path.join(out, `notebook-action-page-${n}.jpg`);
      const result = await json(await api.post('/api/children/' + account.child_id + '/materials', {
        headers: {...authorization, 'Idempotency-Key': `notebook-actions-photo-${n}-v1`},
        multipart: {file: {name: `artificial-notebook-${n}.jpg`, mimeType: 'image/jpeg', buffer: await readFile(filename)}},
      }), 201);
      state.material_ids.push(result.id);
      await save(account);
    }
    const replay = await json(await api.post('/api/children/' + account.child_id + '/materials', {
      headers: {...authorization, 'Idempotency-Key': 'notebook-actions-photo-0-v1'},
      multipart: {file: {name: 'artificial-notebook-0.jpg', mimeType: 'image/jpeg', buffer: await readFile(account.image_paths[0])}},
    }), 201);
    assert.equal(replay.id, state.material_ids[0], 'same_upload_key_must_reuse_same_source');
    state.phase = 'uploaded';
    await save(account);
    await json(await api.post('/api/auth/logout', {headers: authorization}));
    console.log(JSON.stringify({own_regular_household: true, actual_photos: state.material_ids.length,
      external_model_calls: 0, identical_upload_replayed_without_duplicate: true,
      checkpoint: 'artifacts/.school-day-qa-account.json'}));
  } finally { await api.dispose(); }
}

async function verify() {
  const account = await accountData();
  const state = account.notebook_actions;
  assert(state?.material_ids?.length === 6, 'six_owned_artificial_photos_required');
  const manifest = await (await fetch(base + '/api/app-release')).json();
  assert.equal(manifest.version_code, build, 'requested_public_release_required');
  const health = await (await fetch(base + '/api/health')).json();
  browser = await chromium.launch({headless: true, executablePath: '/opt/google/chrome/chrome', args: ['--no-sandbox']});
  context = await browser.newContext({viewport: {width: 390, height: 1000}, isMobile: true, hasTouch: true});
  page = await context.newPage();
  page.on('pageerror', () => errors.push(phase));
  await login(account, 'child');
  monitorWrites();
  const before = await read('/children/' + account.child_id + '/learning-progress');
  const initialSources = await read('/children/' + account.child_id + '/materials');
  assert(initialSources.items.filter(row => !state.material_ids.includes(row.id))
    .every(row => row.confirmed === true && row.subject_id !== null),
  'finish_confirming_owned_reprocessed_copies_before_destructive_browser_qa');
  phase = 'unassigned_album_and_cancel';
  await open('/library/' + account.child_id + '/subject/unassigned');
  await button('Mit KI neu lesen').first().waitFor();
  await button('Heftseite löschen').first().waitFor();
  await shot('album-mobile');
  await assertCancelledNoModel(() => tap(button('Mit KI neu lesen')));
  await tap(button('Heftseite löschen'));
  await cancel();
  checks.push('album_delete_and_ai_icons_visible_cancel_preserves_page_and_no_model_job');

  phase = 'grid_controls';
  await tap(page.getByRole('checkbox', {name: 'Kacheln', exact: true}));
  await button('Heftseite löschen').first().waitFor();
  await button('Mit KI neu lesen').first().waitFor();
  await shot('grid-mobile');
  await assertCancelledNoModel(() => tap(button('Mit KI neu lesen')));
  checks.push('grid_actions_visible_and_reprocess_cancelled_without_ai');

  phase = 'list_selection_all_and_cancel';
  await tap(page.getByRole('checkbox', {name: 'Liste', exact: true}));
  const unassigned = await read('/children/' + account.child_id + '/materials?subject_id=unassigned');
  assert(unassigned.total >= 5);
  await tap(button('Heftseite löschen'));
  await tap(button('Bestätigen'));
  await waitUnassignedCount(account, unassigned.total - 1);
  checks.push('single_page_delete_from_list_removes_exactly_one_owned_photo');
  await tap(button('Seiten auswählen'));
  await tap(page.getByRole('checkbox', {name: /^Seite \d+ auswählen/}));
  await tap(page.getByRole('checkbox', {name: /^Seite \d+ auswählen/}));
  await button('Auswahl löschen (2)').waitFor();
  await tap(button('Auswahl löschen (2)'));
  await cancel();
  await waitUnassignedCount(account, unassigned.total - 1);
  await tap(button('Auswahl löschen (2)'));
  await tap(button('Bestätigen'));
  await waitUnassignedCount(account, unassigned.total - 3);
  checks.push('explicit_two_page_selection_deletes_exactly_two_photos_atomically');
  // Reenter selection if the completed operation closed it.
  if (await button('Seiten auswählen').count()) await tap(button('Seiten auswählen'));
  await tap(button('Alle auswählen'));
  const remaining = unassigned.total - 3;
  await button(`Auswahl löschen (${remaining})`).waitFor();
  await shot('list-selection-mobile');
  await tap(button(`Auswahl löschen (${remaining})`));
  await cancel();
  assert.equal(await unassignedCount(account), remaining);
  assert.equal(aiWriteCount(), 0);
  checks.push('list_multi_select_select_all_delete_cancel_preserves_all_photos');

  phase = 'bulk_filter_binding';
  // Destructive proof is explicit and confined to our unassigned test photos.
  // The operator's separately confirmed Mathematics source must remain intact.
  const allBefore = await read('/children/' + account.child_id + '/materials');
  const protectedSources = allBefore.items.filter(row => row.subject_id !== null);
  assert(protectedSources.length > 0, 'operator_must_confirm_owned_first_source_before_bulk_qa');
  await tap(button('Auswahl aufheben'));
  await tap(button('Alles löschen'));
  await page.getByText(`${remaining} Heftseiten löschen?`, {exact: true}).waitFor();
  await cancel();
  assert.equal(await unassignedCount(account), remaining);
  await tap(button('Alles löschen'));
  await tap(button('Bestätigen'));
  await waitUnassignedCount(account, 0);
  for (const source of protectedSources) await read('/materials/' + source.id);
  checks.push('all_delete_is_bound_to_current_subject_filter_and_preserves_other_confirmed_sources');

  phase = 'confirmed_child_controls';
  const protectedSource = protectedSources[0];
  await open('/library/' + account.child_id + '/subject/' + protectedSource.subject_id);
  await button('Mit KI neu lesen').first().waitFor();
  await button('Heftseite löschen').first().waitFor();
  await assertCancelledNoModel(() => tap(button('Mit KI neu lesen')));
  await tap(button('Heftseite löschen'));
  await cancel();
  await shot('confirmed-child-mobile');
  checks.push('confirmed_child_page_has_delete_and_reprocess_actions');
  await page.setViewportSize({width: 320, height: 900});
  await open('/library/' + account.child_id + '/subject/' + protectedSource.subject_id);
  await tap(button('Heftseite löschen'));
  await cancel();
  await shot('confirmed-child-320');
  checks.push('confirmed_actions_reachable_on_320px_phone');

  phase = 'desktop_and_parent_visibility';
  await page.setViewportSize({width: 1440, height: 1100});
  await open('/library/' + account.child_id + '/subject/' + protectedSource.subject_id);
  await button('Heftseite löschen').first().waitFor();
  await shot('album-desktop');
  const after = await read('/children/' + account.child_id + '/learning-progress');
  assert.deepEqual(after.totals, before.totals, 'photo_management_must_not_create_learning_evidence');
  assert.equal(aiWriteCount(), 0, 'browser_qa_must_not_make_model_calls');
  assert.equal(errors.length, 0);
  await json(await context.request.post(base + '/api/auth/logout', {headers: {'X-Schulpilot-Request': '1'}}));
  await context.close();
  context = await browser.newContext({viewport: {width: 1440, height: 1100}});
  page = await context.newPage();
  page.on('pageerror', () => errors.push(phase));
  await login(account, 'parent');
  monitorWrites();
  await open('/library/' + account.child_id + '/subject/' + protectedSource.subject_id);
  await button('Mit KI neu lesen').first().waitFor();
  await button('Heftseite löschen').first().waitFor();
  await assertCancelledNoModel(() => tap(button('Mit KI neu lesen')));
  const parentProgress = await read('/children/' + account.child_id + '/learning-progress');
  assert.deepEqual(parentProgress.totals, after.totals);
  await shot('parent-confirmed-desktop');
  await json(await context.request.post(base + '/api/auth/logout', {headers: {'X-Schulpilot-Request': '1'}}));
  checks.push('normal_parent_access_same_confirmed_controls_and_consistent_progress');
  state.phase = 'web_actions_passed';
  await save(account);
  const report = {success: true, public_flutter_build: build, source_commit: health.source_commit,
    checks, javascript_errors: errors.length, external_model_calls_from_browser_driver: aiWriteCount(),
    dataset_key: createHash('sha256').update(account.child_id).digest('hex')};
  await writeFile(path.join(out, 'notebook-actions-web-result.json'), JSON.stringify(report) + '\n', {mode: 0o600});
  console.log(JSON.stringify(report));
}

try {
  if (args.includes('--prepare')) await prepare();
  else if (args.includes('--verify-final')) await verify();
  else throw new Error('use_prepare_or_verify_final');
} catch (error) {
  if (page) await shot('failure').catch(() => {});
  console.log(JSON.stringify({success: false, phase, error: String(error.message).slice(0, 180)}));
  process.exitCode = 1;
} finally { await browser?.close(); }
