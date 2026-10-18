// Actual deployed Flutter app, our artificial household and its own photographs.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {chromium} from 'playwright';
import {readFile, writeFile, chmod} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const base = 'https://schulpilot.dorfspy.de';
const out = fileURLToPath(new URL('../artifacts/', import.meta.url));
const privateFile = path.join(out, '.school-day-qa-account.json');
let browser, context, page, phase = 'setup';
const checks = [], errors = [], mutations = [];
const button = name => page.getByRole('button', {name, exact: true});
async function open(route) {
  await page.goto(base + route, {waitUntil: 'domcontentloaded', timeout: 90000});
  await page.waitForSelector('flutter-view', {timeout: 90000});
  await page.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(n => n.click()));
  await page.waitForTimeout(400);
}
async function tap(locator) {
  const target = locator.first();
  for (let n = 0; n < 35; n++) {
    const box = await target.count() ? await target.boundingBox().catch(() => null) : null;
    // Flutter's semantics rectangles can extend behind the fixed navigation.
    // Scroll the actual content clear of that overlay before a physical click.
    if (box && box.height && box.width && box.y >= 0 && box.y + box.height < page.viewportSize().height - 104) {
      await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
      await page.waitForTimeout(220); return;
    }
    await page.mouse.move(page.viewportSize().width / 2, page.viewportSize().height / 2);
    if (n === 0 && !await target.count()) {
      await page.mouse.wheel(0, -4000); await page.waitForTimeout(250); continue;
    }
    await page.mouse.wheel(0, box && box.y < 0 ? -250 : 250);
    await page.waitForTimeout(130);
  }
  throw new Error('own_album_control_not_visible');
}
async function type(locator, value) {
  await tap(locator); await page.keyboard.press('Control+A');
  await page.keyboard.type(value, {delay: 12});
  assert.equal(await locator.inputValue(), value);
  // Commit through Flutter's editing bridge before clicking another control;
  // a DOM inputValue alone can precede the framework's next frame.
  await page.keyboard.press('Tab');
  await page.waitForTimeout(300);
}
async function api(route) {
  const r = await context.request.get(base + '/api' + route, {headers: {'X-Schulpilot-Request': '1'}});
  assert.equal(r.status(), 200, 'owned_album_read_failed'); return r.json();
}
async function shot(name) {
  const file = path.join(out, 'notebooks-web-' + name + '.png');
  await page.screenshot({path: file}); await chmod(file, 0o600);
}
try {
  const account = JSON.parse(await readFile(privateFile, 'utf8'));
  const state = account.notebook_qa;
  assert(account.normal_account && account.verified && ['prepared', 'web_passed_native_pending', 'native_passed'].includes(state?.phase) &&
    /\+schulpilot-normal-qa-[a-f0-9]{12}@/.test(account.credentials.parent_username), 'own_artificial_album_required');
  const health = await (await fetch(base + '/api/health')).json();
  const [major, minor] = health.version.split('.').map(Number);
  assert(major > 1 || (major === 1 && minor >= 6), 'deploy_album_release_first');
  browser = await chromium.launch({headless: true, executablePath: '/opt/google/chrome/chrome', args: ['--no-sandbox']});
  context = await browser.newContext({viewport: {width: 390, height: 1000}, isMobile: true, hasTouch: true});
  page = await context.newPage();
  page.on('pageerror', () => errors.push(phase));
  phase = 'independent_child_login';
  await open('/login');
  await type(page.getByRole('textbox', {name: 'E-Mail oder Benutzername', exact: true}), account.credentials.child_username);
  await type(page.getByLabel('Passwort', {exact: true}), account.credentials.child_password);
  await tap(button('Anmelden'));
  await page.waitForURL(base + '/app');
  page.on('request', r => { if (new URL(r.url()).pathname.startsWith('/api/') && r.method() !== 'GET') mutations.push(r.method()); });
  phase = 'subject_shelf_and_empty_folder';
  await open('/library/' + account.child_id);
  const shelf = await api('/children/' + account.child_id + '/subjects');
  assert(shelf.items.length >= 24);
  const math = shelf.items.find(r => r.key === 'mathematik');
  const bio = shelf.items.find(r => r.key === 'biologie');
  assert.equal(math.page_count, 2); assert.equal(bio.page_count, 0);
  await shot('shelf-mobile');
  await tap(page.getByRole('button', {name: /^Biologie,.*Hefter öffnen$/s}));
  await page.getByText('Hier sind noch keine Heftseiten vorhanden.', {exact: true}).waitFor();
  checks.push('fixed_subjects_before_upload_and_empty_folder');
  phase = 'real_photos_turn_zoom_and_layouts';
  await open('/library/' + account.child_id + '/subject/' + math.id);
  await button('1 von 2').first().waitFor();
  await page.waitForResponse(r => new URL(r.url()).pathname.endsWith('/image') && r.status() === 200, {timeout: 15000}).catch(() => {});
  await shot('album-mobile');
  await tap(button('Nächste Seite'));
  await button('2 von 2').first().waitFor();
  await tap(button('Vergrößern'));
  await page.getByText('Heftfoto', {exact: true}).waitFor();
  await shot('zoom');
  await tap(button('Schließen'));
  phase = 'album_grid_and_list';
  await tap(page.getByRole('checkbox', {name: 'Kacheln', exact: true}));
  await button('1–2 von 2').first().waitFor();
  await shot('pages-grid');
  await tap(page.getByRole('checkbox', {name: 'Liste', exact: true}));
  await shot('pages-list');
  checks.push('authenticated_real_photos_turn_zoom_grid_and_list');
  phase = 'page_jump_across_metadata_batches';
  await open('/library/' + account.child_id + '/subject/unassigned');
  await button('1 von 24').first().waitFor();
  await tap(button('1 von 24'));
  await type(page.getByRole('textbox', {name: 'Seite 1 bis 24', exact: true}), '24');
  await tap(button('Seite öffnen'));
  await button('24 von 24').first().waitFor();
  await tap(button('Vorherige Seite'));
  await button('23 von 24').first().waitFor();
  await shot('last-batch');
  checks.push('stable_subject_filter_page_jump_and_second_batch');
  phase = 'responsive_desktop_and_metadata';
  await page.setViewportSize({width: 1440, height: 1100});
  await open('/library/' + account.child_id);
  await shot('shelf-desktop');
  await open('/library/' + account.child_id + '/subject/' + math.id);
  await shot('album-desktop');
  const pages = await api('/children/' + account.child_id + '/materials?subject_id=' + math.id);
  assert.equal(pages.total, 2);
  for (const row of pages.items) {
    assert(row.has_image); assert(!('path' in row)); assert(!('content' in row));
  }
  const childProgress = await api('/children/' + account.child_id + '/learning-progress');
  assert.equal(childProgress.totals.practiced_tasks, 0);
  assert.equal(mutations.length, 0);
  phase = 'parent_normal_login_and_same_subjects';
  context = await browser.newContext({viewport: {width: 1440, height: 1100}});
  page = await context.newPage();
  page.on('pageerror', () => errors.push(phase));
  await open('/login');
  await type(page.getByRole('textbox', {name: 'E-Mail oder Benutzername', exact: true}), account.credentials.parent_username);
  await type(page.getByLabel('Passwort', {exact: true}), account.credentials.parent_password);
  await tap(button('Anmelden'));
  await page.waitForURL(base + '/app');
  page.on('request', r => { if (new URL(r.url()).pathname.startsWith('/api/') && r.method() !== 'GET') mutations.push(r.method()); });
  await open('/library/' + account.child_id);
  const parentShelf = await api('/children/' + account.child_id + '/subjects');
  assert.equal(parentShelf.items.find(r => r.id === math.id).page_count, 2);
  await shot('parent-shelf');
  await open('/library/' + account.child_id + '/subject/' + math.id);
  await button('1 von 2').first().waitFor();
  await shot('parent-album');
  const parentProgress = await api('/children/' + account.child_id + '/learning-progress');
  assert.deepEqual(parentProgress.totals, childProgress.totals);
  checks.push('normal_parent_login_same_subjects_and_no_invented_progress');
  phase = 'offline_and_explicit_retry';
  await context.setOffline(true);
  await tap(button('Seiten aktualisieren'));
  await page.getByText('Keine Verbindung zu SCHULPILOT. Bitte prüfe deine Internetverbindung und versuche es erneut.', {exact: true}).waitFor();
  await shot('offline');
  await context.setOffline(false);
  await tap(button('Erneut laden'));
  await button('1 von 2').first().waitFor();
  checks.push('browser_offline_error_and_explicit_recovery');
  // No album operation is allowed to generate a model job, attempt or learning time.
  assert.equal(mutations.length, 0);
  assert.equal(errors.length, 0);
  const latest = JSON.parse(await readFile(privateFile, 'utf8'));
  assert.equal(latest.child_id, account.child_id);
  state.phase = latest.notebook_qa.phase === 'native_passed' ? 'native_passed' : 'web_passed_native_pending';
  state.math_subject_id = math.id;
  account.notebook_qa = state;
  await writeFile(privateFile, JSON.stringify(account) + '\n', {mode: 0o600});
  await chmod(privateFile, 0o600);
  const report = {success: true, actual_public_flutter: true, checks, javascript_errors: errors.length,
    album_mutations: mutations.length, own_photos: 26, additional_model_calls: 0, source_commit: health.source_commit,
    dataset_key: createHash('sha256').update(account.child_id).digest('hex')};
  await writeFile(path.join(out, 'notebooks-web-result.json'), JSON.stringify(report) + '\n');
  console.log(JSON.stringify(report));
} catch (e) {
  if (page) await shot('failure').catch(() => {});
  console.log(JSON.stringify({success: false, phase, error: String(e.message).slice(0, 240)}));
  process.exitCode = 1;
} finally { await browser?.close(); }
