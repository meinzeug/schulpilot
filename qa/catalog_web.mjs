// Real public Flutter/photo/provider/catalog integration, our artificial family only.
// Checkpoints retain reserved jobs; reruns never silently retry failed AI calls.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {chromium} from 'playwright';
import {readFile, writeFile, chmod} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const base = 'https://schulpilot.dorfspy.de';
const out = fileURLToPath(new URL('../artifacts/', import.meta.url));
const privateFile = path.join(out, '.school-day-qa-account.json');
const headers = {'X-Schulpilot-Request': '1', 'X-Schulpilot-Capabilities': 'language-v1'};
let browser, page, child, parent, account, state, phase = 'setup';
const checks = [], errors = [], modelActions = [];
const button = name => page.getByRole('button', {name, exact: true});
async function save() {
  account.catalog_qa = state;
  await writeFile(privateFile, JSON.stringify(account) + '\n', {mode: 0o600});
  await chmod(privateFile, 0o600);
}
async function open(route) {
  await page.goto(base + route, {waitUntil: 'domcontentloaded', timeout: 90000});
  await page.waitForSelector('flutter-view', {timeout: 90000});
  await page.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(n => n.click()));
  await page.waitForTimeout(400);
}
async function tap(locator, modal = false) {
  const target = locator.first();
  for (let i = 0; i < 40; i++) {
    const box = await target.count() ? await target.boundingBox().catch(() => null) : null;
    if (box && box.width && box.height && box.y >= 0 && box.y + box.height < page.viewportSize().height - (modal ? 8 : 104)) {
      await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
      await page.waitForTimeout(240); return;
    }
    await page.mouse.move(page.viewportSize().width / 2, page.viewportSize().height / 2);
    await page.mouse.wheel(0, i === 0 && !await target.count() ? -5000 : box && box.y < 0 ? -250 : 250);
    await page.waitForTimeout(130);
  }
  throw new Error('owned_catalog_control_not_visible');
}
async function type(locator, value, modal = false) {
  await tap(locator, modal); await page.keyboard.press('Control+A');
  await page.keyboard.type(value, {delay: 12});
  assert.equal(await locator.inputValue(), value, 'flutter_input_missing');
  await page.keyboard.press('Tab'); await page.waitForTimeout(350);
}
async function get(context, route) {
  const response = await context.request.get(base + '/api' + route, {headers});
  assert.equal(response.status(), 200, 'own_read_failed'); return response.json();
}
async function uiResponse(locator, route, method, status, modal = false) {
  const waiting = page.waitForResponse(r => new URL(r.url()).pathname === '/api' + route && r.request().method() === method, {timeout: 45000});
  waiting.catch(() => {});
  await tap(locator, modal);
  const response = await waiting;
  assert.equal(response.status(), status, 'explicit_ui_request_failed'); return response.json();
}
async function waitFor(read, predicate, seconds = 210) {
  const deadline = Date.now() + seconds * 1000;
  while (Date.now() < deadline) {
    const value = await read();
    assert.notEqual(value.status, 'failed', 'failed_job_checkpoint_retained_no_retry');
    if (predicate(value)) return value;
    await page.waitForTimeout(2000);
  }
  throw new Error('bounded_catalog_wait_expired');
}
async function shot(name) {
  const file = path.join(out, 'catalog-web-' + name + '.png');
  await page.screenshot({path: file}); await chmod(file, 0o600);
}
async function login(role, context) {
  page = await context.newPage();
  page.on('pageerror', () => errors.push(phase));
  await open('/login');
  await type(page.getByRole('textbox', {name: 'E-Mail oder Benutzername', exact: true}), account.credentials[role + '_username']);
  await type(page.getByLabel('Passwort', {exact: true}), account.credentials[role + '_password']);
  await tap(button('Anmelden')); await page.waitForURL(base + '/app');
}
function validateTips(tips) {
  assert.equal(tips.state, 'ready', 'local_tips_not_ready');
  const rows = [...tips.recommended, ...tips.additional];
  assert(rows.length, 'relevant_fraction_tips_required');
  for (const row of rows) {
    const url = new URL(row.url);
    assert(url.protocol === 'https:' && ['sofatutor.com', 'www.sofatutor.com'].includes(url.hostname));
    assert(['video', 'learning_text'].includes(row.content_type));
    assert(row.provider === 'Sofatutor' && row.title && row.topic_id);
  }
  assert(tips.recommended.every(r => r.relation === 'known_level' && r.curated_class_membership_verified));
  assert(tips.additional.every(r => r.relation === 'general_topic' && !r.curated_class_membership_verified));
  return rows;
}

try {
  account = JSON.parse(await readFile(privateFile, 'utf8'));
  assert(account.normal_account && account.verified && /\+schulpilot-normal-qa-[a-f0-9]{12}@/.test(account.credentials.parent_username), 'own_regular_family_required');
  const health = await (await fetch(base + '/api/health')).json();
  assert.equal(health.version, '1.7.0', 'deploy_catalog_release_first');
  state = account.catalog_qa ?? {phase: 'new', materials: []};
  await save();
  browser = await chromium.launch({headless: true, executablePath: '/opt/google/chrome/chrome', args: ['--no-sandbox']});
  child = await browser.newContext({viewport: {width: 390, height: 1000}, isMobile: true, hasTouch: true});
  parent = await browser.newContext({viewport: {width: 1440, height: 1100}});
  if (!state.preferences_set) {
    const signed = await parent.request.post(base + '/api/auth/login', {headers, data: {
      username: account.credentials.parent_username, password: account.credentials.parent_password,
    }});
    assert.equal(signed.status(), 200, 'owned_parent_configuration_login_failed');
    assert.equal((await signed.json()).user.id, account.user.id);
    const prefs = await parent.request.put(base + '/api/children/' + account.child_id + '/preferences', {headers, data: {
      weekdays: [0, 1, 2, 3, 4, 5, 6], daily_minutes: 20, weekly_minutes: 20,
      session_minutes: 5, break_minutes: 5, timezone: 'Europe/Berlin',
    }});
    assert.equal(prefs.status(), 200, 'owned_parent_preferences_failed');
    state.preferences_set = true; await save();
  }
  phase = 'independent_child_login';
  await login('child', child);
  page.on('request', request => {
    const route = new URL(request.url()).pathname;
    if (request.method() === 'POST' && /\/(extract|prepare|package|tutor\/questions|units)$/.test(route)) modelActions.push(route.replace(/[a-f0-9]{32}/g, ':id'));
  });
  const subjects = await get(child, '/children/' + account.child_id + '/subjects');
  assert(subjects.items.length >= 24);
  const math = subjects.items.find(s => s.key === 'mathematik');
  state.math_subject_id = math.id;
  phase = 'fixed_empty_subject_and_catalog_browser';
  await open('/library/' + account.child_id + '/subject/' + math.id);
  if (!state.materials.length) await page.getByText('Hier sind noch keine Heftseiten vorhanden.', {exact: true}).waitFor();
  const beforeBrowse = modelActions.length;
  await tap(button('Themen entdecken'));
  await type(page.getByRole('textbox', {name: 'Thema suchen', exact: true}), 'Brüche', true);
  await page.getByRole('checkbox', {name: 'Meine Stufe', exact: true}).waitFor();
  await tap(page.getByRole('checkbox', {name: 'Meine Stufe', exact: true}), true);
  await page.waitForTimeout(650);
  assert.equal(await button('Stufe einstellen').count(), 0, 'child_may_not_set_parent_stufe');
  const topics = await get(child, '/children/' + account.child_id + '/subjects/' + math.id + '/topics?q=Br%C3%BCche&scope=known');
  assert(topics.has_known_level && topics.items.length, 'known_class_topics_missing');
  await shot('empty-subject-topics-mobile');
  await tap(button('Schließen'), true);
  assert.equal(modelActions.length, beforeBrowse, 'browse_must_not_generate_ai');
  checks.push('fixed_subject_empty_folder_known_class_topics_pure_gets');
  phase = 'normal_photo_wizard';
  if (!state.materials.length) {
    if (!state.day_id) {
      await tap(button('Heftfoto hinzufügen'));
      await page.waitForURL(base + '/after-school/' + account.child_id);
      const created = (await waitFor(() => get(child, '/children/' + account.child_id + '/school-day/today'), d => d.day != null, 30)).day;
      assert.equal(created.pages.length, 0, 'new_owned_school_day_required');
      state.day_id = created.id; await save();
      const chooser = page.waitForEvent('filechooser');
      await tap(button('Fotos auswählen'));
      await (await chooser).setFiles(account.image_paths);
      for (let i = 0; i < account.image_paths.length; i++) await tap(button('Zuschnitt übernehmen'), true);
      // The wizard deliberately retains photos locally until explicit submission.
      await tap(button('Fotos abgeben'));
      state.phase = 'photos_submitted'; await save();
    }
    const day = await waitFor(() => get(child, '/school-days/' + state.day_id), d => {
      assert(!d.pages.some(p => p.status === 'unreadable'), 'actual_ocr_failed_no_retry');
      assert.notEqual(d.preparation?.status, 'failed', 'background_preparation_failed_no_retry');
      return d.pages.length === 2 && d.pages.every(p => ['review', 'confirmed'].includes(p.status));
    }, 390);
    assert(day.pages.every(p => !p.synthetic && p.extraction_provider === 'codex'), 'real_reserved_codex_ocr_required');
    state.materials = day.pages.map(p => p.id); await save();
  }
  let day = await get(child, '/school-days/' + state.day_id);
  await open('/after-school/' + account.child_id);
  for (const id of state.materials) {
    const material = await get(child, '/materials/' + id);
    // Historical full-material projection retains its label; the indexed list
    // and tips projection carry the stable subject ID.
    assert(material.content.trim() && material.subject === math.title);
    if (!material.confirmed) {
      await uiResponse(button('Stimmt, weiter'), '/materials/' + id + '/confirm', 'PUT', 200);
      await page.waitForTimeout(1200);
    }
  }
  checks.push('actual_public_photo_crop_two_reserved_ocr_and_explicit_confirmation');
  phase = 'source_bound_tips_and_external_link';
  await open('/material/' + state.materials[0]);
  const tipPath = '/children/' + account.child_id + '/learning-tips/material/' + state.materials[0];
  let tips = await waitFor(() => get(child, tipPath), t => t.state === 'ready', 40);
  const rows = validateTips(tips);
  await tap(button('Lerntipps'));
  await page.getByText(rows[0].title, {exact: true}).first().waitFor();
  await shot('source-tips-mobile');
  if (!state.external_opened) {
    const navigations = [];
    const recordNavigation = request => {
      const uri = new URL(request.url());
      if (request.isNavigationRequest() && ['sofatutor.com', 'www.sofatutor.com'].includes(uri.hostname)) navigations.push(uri);
    };
    child.on('request', recordNavigation);
    const popupWait = child.waitForEvent('page', {timeout: 15000});
    popupWait.catch(() => {});
    await tap(button('Bei Sofatutor ansehen').first());
    const external = await popupWait;
    await external.waitForURL(url => ['sofatutor.com', 'www.sofatutor.com'].includes(url.hostname), {timeout: 15000});
    const expected = new URL(rows[0].url);
    // Provider login/canonical redirects may remove parameters afterwards. The
    // app's initial external navigation must preserve the stored catalog URI.
    assert(navigations.some(uri => uri.pathname === expected.pathname && uri.search === expected.search), 'stored_topic_parameters_not_forwarded');
    await external.waitForLoadState('domcontentloaded', {timeout: 20000}).catch(() => {});
    assert.equal(await external.evaluate(() => document.referrer), '', 'private_referrer_must_be_absent');
    await external.close();
    child.off('request', recordNavigation);
    state.external_opened = true; await save();
  }
  checks.push('real_source_tips_exact_https_external_page_no_referrer');
  phase = 'real_tutor_with_catalog_schema';
  await open('/material/' + state.materials[0]);
  if (!state.tutor_id) {
    await tap(button('Frag nach'));
    await type(page.getByRole('textbox', {name: 'Deine Frage', exact: true}), 'Wie kuerze ich 6/12?', true);
    const turn = await uiResponse(button('Frage stellen'), '/children/' + account.child_id + '/tutor/questions', 'POST', 202, true);
    state.tutor_id = turn.id; state.tutor_job_id = turn.job_id; await save();
  }
  const tutor = await waitFor(async () => {
    const history = await get(child, '/children/' + account.child_id + '/tutor/questions?material_id=' + state.materials[0]);
    return history.questions.find(t => t.id === state.tutor_id) ?? {status: 'queued'};
  }, t => t.status === 'ready');
  assert(tutor.reply.answer && tutor.reply.sources.length, 'grounded_actual_tutor_answer_required');
  const tutorTips = await waitFor(() => get(child, '/children/' + account.child_id + '/learning-tips/tutor/' + state.tutor_id), t => t.state === 'ready', 40);
  validateTips(tutorTips);
  checks.push('real_reserved_tutor_schema_and_grounded_tips');
  phase = 'real_package_with_catalog_schema';
  if (!state.unit_id) {
    await open('/after-school/' + account.child_id);
    day = await get(child, '/school-days/' + state.day_id);
    if (!day.units.length && day.preparation?.status !== 'processing') {
      await tap(button('Im Hintergrund vorbereiten').or(button('Lernpaket für heute erstellen')).or(button('Jetzt lernen')));
    }
    day = await waitFor(() => get(child, '/school-days/' + state.day_id), d => {
      assert.notEqual(d.preparation?.status, 'failed', 'actual_package_failed_no_retry');
      return d.units.length > 0;
    });
    state.unit_id = day.units[0].id; await save();
  }
  const unit = await get(child, '/units/' + state.unit_id);
  assert(unit.questions.length >= 2 && unit.questions.length <= 5);
  for (const q of unit.questions) assert(!('answer' in q) && !('accepted' in q) && !('evaluation_policy' in (q.language ?? {})), 'private_answers_must_not_leak');
  assert.equal(unit.synthetic, false);
  await open('/unit/' + state.unit_id);
  await shot('prepared-round');
  const unitTips = await waitFor(() => get(child, '/children/' + account.child_id + '/learning-tips/unit/' + state.unit_id), t => t.state === 'ready', 40);
  validateTips(unitTips);
  checks.push('actual_reserved_school_day_package_private_keys_hidden');
  phase = 'album_regression';
  await open('/library/' + account.child_id + '/subject/' + math.id);
  await button('1 von 2').first().waitFor();
  await tap(button('Nächste Seite')); await button('2 von 2').first().waitFor();
  await tap(button('Vergrößern')); await page.getByText('Heftfoto', {exact: true}).waitFor();
  await tap(button('Schließen'));
  await tap(page.getByRole('checkbox', {name: 'Kacheln', exact: true}));
  await button('1–2 von 2').first().waitFor();
  await tap(page.getByRole('checkbox', {name: 'Liste', exact: true}));
  checks.push('current_release_real_album_turn_zoom_grid_list');
  const childProgress = await get(child, '/children/' + account.child_id + '/learning-progress');
  assert.equal(childProgress.totals.practiced_tasks, 0, 'links_and_preparation_are_not_solved_tasks');
  phase = 'normal_parent_desktop';
  await login('parent', parent);
  await open('/material/' + state.materials[0]);
  await tap(button('Lerntipps'));
  await tap(page.getByRole('button', {name: 'Aufgerufene Links', exact: true}));
  await page.getByText('Ein Linkaufruf belegt kein angesehenes Video oder eine gelöste Übung.', {exact: true}).waitFor();
  await shot('parent-tips-and-real-link-history');
  const parentTips = await get(parent, tipPath);
  assert(parentTips.recent_links.length > 0);
  assert.deepEqual((await get(parent, '/children/' + account.child_id + '/learning-progress')).totals, childProgress.totals);
  await open('/library/' + account.child_id + '/subject/' + math.id);
  await tap(button('Themen entdecken'));
  await button('Stufe einstellen').waitFor();
  await shot('parent-subject-topics');
  checks.push('parent_same_progress_real_link_history_and_exclusive_level_settings');
  assert.equal(errors.length, 0, 'javascript_errors');
  state.phase = 'web_passed_native_pending'; await save();
  const report = {success: true, checks, actual_public_flutter: true, actual_ocr_jobs: 2,
    actual_tutor_jobs: 1, actual_package_jobs: 1, invented_attempts: 0, javascript_errors: errors.length,
    source_commit: health.source_commit, dataset_key: createHash('sha256').update(account.child_id).digest('hex')};
  await writeFile(path.join(out, 'catalog-web-result.json'), JSON.stringify(report) + '\n');
  console.log(JSON.stringify(report));
} catch (error) {
  if (page) await shot('failure').catch(() => {});
  console.log(JSON.stringify({success: false, phase, error: String(error.message).slice(0, 200)}));
  process.exitCode = 1;
} finally { await browser?.close(); }
