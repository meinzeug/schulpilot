// Public, real-provider QA for one explicitly owned, wholly artificial family.
// No household creation, deletion, automatic retry, provider change, or
// operator API here. Explicit correction modes preserve the original history.
//
//   node qa/learning_journey.mjs --prepare-images  (local fixtures only)
//   node qa/learning_journey.mjs --check-inputs    (local validation only)
//   node qa/learning_journey.mjs --run            (after the new deployment)
//   node qa/learning_journey.mjs --run --retry-ocr-after-fix
//     (only after the operator has deployed/approved the transcription fix;
//      exactly one normal reserved retry per already uploaded artificial page)
//   node qa/learning_journey.mjs --run --continue-valid-initial
//     (operator-authorized partial continuation: preserve the failed invalid
//      stage, test two tutor turns and one practice generation from the valid
//      initial review; no new stage answer, review retry, or practice answer)
//   node qa/learning_journey.mjs --run --read-saved-results
//     (existing data only: parent readback and unchanged usage, no inference)
//   node qa/learning_journey.mjs --run --prepare-fresh-child
//     (ONLY on a separate explicit operator instruction after the math/focus
//      fix: one second child, same family/limits, original history archived in
//      the same protected account file; no AI calls or fixture replacement)
//   node qa/learning_journey.mjs --run --retry-stage-after-math-fix
//     (ONLY after a separate explicit instruction and a new backend deployment:
//      one additional normal UI request for the second child's failed block;
//      original 16 family calls remain historical, saved retry jobs read only)
//
// Re-run --run to observe/continue saved work. An ambiguously dispatched or
// failed AI operation stops the run; it is never submitted a second time.
// The household and protected checkpoint always remain available for Android.
import {chromium} from 'playwright';
import {createHash, randomBytes} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {chmod, lstat, readFile, realpath, rename, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const artifacts = path.join(root, 'artifacts');
const accountFile = path.join(artifacts, '.school-day-qa-account.json');
const reportFile = path.join(artifacts, 'learning-journey-result.json');
const base = 'https://schulpilot.dorfspy.de';
const headers = {'X-Schulpilot-Request': '1'};
const arguments_ = process.argv.slice(2);
const mode = arguments_[0];
const retryOcrAfterFix = arguments_.includes('--retry-ocr-after-fix');
const continueValidInitial = arguments_.includes('--continue-valid-initial');
const readSavedResults = arguments_.includes('--read-saved-results');
const prepareFreshChild = arguments_.includes('--prepare-fresh-child');
const retryStageAfterMathFix = arguments_.includes('--retry-stage-after-math-fix');
const allowedModes = new Set(['--prepare-images', '--check-inputs', '--run', '--help']);
const runtimeErrors = [];
const blockedRequests = [];
const unexpectedAudioStarts = [];
const permits = new Map();
let account, journey, browser, child, parent, page;
let phase = 'local_inputs';
let authenticated = false;
let passed = false;
let lastUsage = null;
let persistence = Promise.resolve();

// Fixed original source pages. Nothing from a user's account enters fixtures.
// Fractions and all examples are deliberate, exact mathematical statements.
const sourcePages = [
  {
    title: 'Brüche kürzen',
    paragraphs: [
      'Ein Bruch beschreibt einen Anteil. Der Nenner sagt, in wie viele gleich große Teile das Ganze geteilt ist. Der Zähler sagt, wie viele dieser Teile gemeint sind. Bei 12/18 sind zwölf von achtzehn gleich großen Teilen gemeint.',
      'Beim Kürzen teilen wir Zähler und Nenner durch dieselbe Zahl größer als eins. Beide müssen ohne Rest durch diese Zahl teilbar sein. Der Wert des Bruchs bleibt gleich. Nur die Schreibweise wird einfacher, weil wir kleine Teile zu größeren Teilen zusammenfassen.',
      'Beispiel: 12/18 lässt sich zuerst durch 2 kürzen. Dann erhalten wir 6/9. Teilen wir anschließend beide Zahlen durch 3, erhalten wir 2/3. Direkt durch 6 zu teilen führt ebenfalls zu 2/3. Zwei und drei haben keinen gemeinsamen Teiler größer als eins.',
      'Weitere Beispiele: 3/9 = 1/3, weil beide Zahlen durch 3 geteilt werden. 6/12 = 1/2, weil beide Zahlen durch 6 geteilt werden. 8/20 = 2/5, weil beide Zahlen durch 4 geteilt werden.',
      'Merksatz: Immer beide Zahlen durch dieselbe Zahl teilen. Nur den Zähler zu teilen verändert den Anteil. Vollständig gekürzt bedeutet: Zähler und Nenner haben keinen gemeinsamen Teiler größer als eins.',
    ],
  },
  {
    title: 'Brüche erweitern',
    paragraphs: [
      'Beim Erweitern multiplizieren wir den Zähler und den Nenner mit derselben ganzen Zahl größer als eins. Der Wert des Bruchs bleibt gleich. Wir teilen jedes vorhandene Teilstück in gleich viele kleinere Teilstücke und zählen entsprechend mehr davon.',
      'Beispiel: 2/3 wird mit dem Faktor 2 zu 4/6 erweitert. Zwei mal zwei ist vier. Drei mal zwei ist sechs. Mit dem Faktor 4 entsteht aus 2/3 dagegen 8/12. Alle drei Brüche beschreiben denselben Anteil.',
      'Wenn ausdrücklich mit dem Faktor 3 erweitert werden soll, ist die verlangte Darstellung wichtig. Aus 1/4 wird dann 3/12. Der Bruch 2/8 hat zwar denselben Wert, wurde aber mit dem Faktor 2 erweitert und erfüllt diesen Auftrag deshalb nicht.',
      'Weitere Beispiele: 1/2 mit dem Faktor 5 ergibt 5/10. 3/5 mit dem Faktor 4 ergibt 12/20. 2/7 mit dem Faktor 3 ergibt 6/21. Prüfe immer beide Rechnungen, also Zähler und Nenner.',
      'Erweitern und Kürzen sind Gegenwege. Wenn wir 4/6 durch 2 kürzen, erhalten wir wieder 2/3. Beim Erweitern wird die Anzahl der Teilstücke größer und jedes Teilstück kleiner. Der markierte Anteil verändert sich dabei nicht. Multipliziere niemals nur eine der beiden Zahlen.',
    ],
  },
];

class QaFailure extends Error {}
function check(condition, code) {
  if (!condition) throw new QaFailure(code);
}
function digest(value) {
  return createHash('sha256').update(value).digest('hex');
}
function artifactPrefix() {
  return journey?.artifact_tag === 'fresh-second-child'
    ? 'learning-journey-fresh-second-child' : 'learning-journey';
}
function resultPath() {
  return journey?.artifact_tag === 'fresh-second-child'
    ? path.join(artifacts, artifactPrefix() + '-result.json') : reportFile;
}
function words(text) {
  return text.match(/[\p{L}\p{N}]+/gu)?.length ?? 0;
}
function button(target, name) {
  return target.getByRole('button', {name, exact: true});
}
function apiPath(response) {
  return new URL(response.url()).pathname;
}
function isAiRoute(route) {
  return /^\/api\/(?:materials\/[^/]+\/extract|school-days\/[^/]+\/(?:package|blocks\/[^/]+)|units\/[^/]+\/(?:coaching|practice)|children\/[^/]+\/tutor\/questions)$/.test(route);
}
function safeReason(error) {
  return error instanceof QaFailure && /^[a-z0-9_-]{1,180}$/.test(error.message)
    ? error.message : 'browser_or_local_io_operation_failed';
}
async function privateWrite(filename, value) {
  await writeFile(filename, value, {mode: 0o600});
  await chmod(filename, 0o600);
}
async function persist(nextPhase, announce = true) {
  phase = nextPhase;
  journey.phase = phase;
  journey.updated_at = new Date().toISOString();
  // Serialize checkpoints, retaining unrelated fields written by another QA
  // tool. Credentials are read only; they are never sent to stdout or reports.
  persistence = persistence.then(async () => {
    const latest = JSON.parse(await readFile(accountFile, 'utf8'));
    check(latest.child_id === account.child_id && latest.user?.id === account.user.id,
      'private_account_changed_during_qa');
    latest.learning_journey_qa = journey;
    if (journey.day_id && !latest.school_day_id) latest.school_day_id = journey.day_id;
    if (journey.initial_unit_id && !latest.package_unit_id) latest.package_unit_id = journey.initial_unit_id;
    const temporary = accountFile + '.learning-journey-' + process.pid + '.tmp';
    await privateWrite(temporary, JSON.stringify(latest) + '\n');
    await rename(temporary, accountFile);
    account = latest;
  });
  await persistence;
  if (announce) console.log(JSON.stringify({qa_phase: phase}));
}
async function localInputs() {
  const info = await lstat(accountFile);
  check(info.isFile() && !info.isSymbolicLink() && (info.mode & 0o077) === 0,
    'prepared_account_must_be_a_protected_regular_file');
  account = JSON.parse(await readFile(accountFile, 'utf8'));
  check(account.normal_account === true && account.verified === true &&
    /\+schulpilot-normal-qa-[a-f0-9]{12}@(?:gmail|googlemail)\.com$/i.test(account.credentials?.parent_username ?? ''),
    'only_the_prepared_owned_artificial_family_is_allowed');
  check(account.user?.role === 'parent' && account.user.families?.length === 1 &&
    account.user.families[0].synthetic === false && account.child_id &&
    account.credentials?.child_username?.startsWith('normal-child-') &&
    account.credentials?.parent_password && account.credentials?.child_password &&
    account.image_paths?.length === 2, 'prepared_regular_account_is_incomplete');
  for (const [index, filename] of account.image_paths.entries()) {
    check(await realpath(filename) === path.join(await realpath(artifacts), 'normal-school-page-' + (index + 1) + '.jpg'),
      'only_the_two_owned_artificial_image_paths_are_allowed');
  }
  journey = account.learning_journey_qa ?? {version: 1, ai_intents: {}, evidence: {}};
  check(journey.version === 1, 'unsupported_checkpoint_version');
  journey.ai_intents ??= {};
  journey.evidence ??= {};
}
async function prepareImages() {
  check(!journey.source_upload_started && !account.package_unit_id &&
    !account.browser_qa?.evidence?.confirmed_pages && !Object.keys(journey.ai_intents).length,
    'original_fixtures_cannot_change_after_upload_or_ai_started');
  const counts = sourcePages.map(source => words(source.title + ' ' + source.paragraphs.join(' ')));
  check(counts.every(count => count >= 150 && count <= 220), 'fixed_artificial_pages_need_150_to_220_words_each');
  // Fixed code plus JSON stdin: no shell, user interpolation, provider call,
  // image-generation service, or credentials. Pillow only renders our originals.
  const renderer = String.raw`
import json, os, sys, textwrap
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
target = Path(sys.argv[1])
pages = json.load(sys.stdin)
body = ImageFont.truetype('DejaVuSans.ttf', 29)
title = ImageFont.truetype('DejaVuSans.ttf', 46)
small = ImageFont.truetype('DejaVuSans.ttf', 24)
for number, page in enumerate(pages, 1):
    image = Image.new('RGB', (1500, 1900), 'white')
    draw = ImageDraw.Draw(image)
    draw.text((70, 45), 'KÜNSTLICHER FUNKTIONSTEST - KEINE KINDERDATEN', font=small, fill='#175b51')
    draw.text((70, 95), 'Mathematik - Klasse 6 - Seite ' + str(number), font=small, fill='#334155')
    draw.text((70, 165), page['title'], font=title, fill='black')
    y = 255
    for paragraph in page['paragraphs']:
        for line in textwrap.wrap(paragraph, width=81, break_long_words=False):
            if y > 1815:
                raise RuntimeError('Fixed source text exceeds image area')
            draw.text((70, y), line, font=body, fill='black')
            y += 44
        y += 25
    filename = target / ('normal-school-page-' + str(number) + '.jpg')
    image.save(filename, 'JPEG', quality=94, exif=b'')
    os.chmod(filename, 0o600)
`;
  execFileSync(path.join(root, '.venv/bin/python'), ['-c', renderer, artifacts], {
    input: JSON.stringify(sourcePages), encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], timeout: 30000,
  });
  journey.source_fixtures = {
    version: 1,
    word_counts: counts,
    sha256: await Promise.all(account.image_paths.map(async filename => digest(await readFile(filename)))),
  };
  await persist('original_artificial_images_prepared');
  console.log(JSON.stringify({local_only: true, original_artificial_images: 2, word_counts: counts}));
}
async function verifyImages() {
  check(journey.source_fixtures?.version === 1 && journey.source_fixtures.sha256?.length === 2,
    'run_prepare_images_before_the_first_upload');
  const hashes = await Promise.all(account.image_paths.map(async filename => digest(await readFile(filename))));
  check(hashes.every((hash, index) => hash === journey.source_fixtures.sha256[index]),
    'artificial_original_image_changed_since_preparation');
}
async function jsonGet(context, route) {
  const response = await context.request.get(base + '/api' + route);
  check(response.status() === 200, 'api_read_failed_' + response.status());
  return response.json();
}
async function usage() {
  lastUsage = await jsonGet(parent, '/families/' + account.user.families[0].id + '/usage');
  return lastUsage;
}
async function dayState() {
  return journey.day_id ? jsonGet(child, '/school-days/' + journey.day_id)
    : (await jsonGet(child, '/children/' + account.child_id + '/school-day/today')).day;
}
function wizardRoute() {
  return '/after-school/' + account.child_id + (journey.day_id ? '?day=' + journey.day_id : '');
}
async function accessible(target) {
  await target.waitForSelector('flutter-view', {timeout: 90000});
  await target.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(node => node.click()));
  await target.waitForTimeout(350);
}
async function open(target, route) {
  const response = await target.goto(base + route, {waitUntil: 'domcontentloaded', timeout: 90000});
  await accessible(target);
  return response;
}
async function top(target) {
  const viewport = target.viewportSize();
  await target.mouse.move(viewport.width - 30, viewport.height - 150);
  await target.mouse.wheel(0, -18000);
  await target.waitForTimeout(300);
}
async function reveal(target, locator, {modal = false, partial = false, reader = false} = {}) {
  const item = locator.first();
  const viewport = target.viewportSize();
  const min = reader ? 120 : modal ? 5 : 75;
  let max = viewport.height - (modal ? 5 : 100);
  if (reader) {
    // Flutter retains offscreen semantics nodes underneath the fixed tutor
    // composer. Such a node is not a usable touch target. Scroll the reader
    // until the control is above its first chip/input, then tap physically.
    for (const composer of [target.getByText('Erklär es einfacher', {exact: true}),
      target.getByRole('textbox', {name: 'Deine Frage', exact: true})]) {
      if (await composer.count()) {
        const box = await composer.first().boundingBox().catch(() => null);
        if (box && box.y > min + 70) max = Math.min(max, box.y - 10);
      }
    }
  }
  for (let attempt = 0; attempt < 36; attempt++) {
    const box = await item.count() ? await item.boundingBox({timeout: 500}).catch(() => null) : null;
    // A tutor answer can exceed the sheet's independently scrollable reading
    // area. It must be present and visibly intersect that area; requiring its
    // whole paragraph to fit between the fixed header/composer is impossible.
    if (partial && box && box.width > 0 && box.height > 0 &&
      box.y < max && box.y + box.height > min) return item;
    if (box && box.width > 0 && box.height > 0 && box.y >= min &&
      (box.y + box.height <= max || box.height > max - min && box.y < max - 40)) return item;
    await target.mouse.move(viewport.width - 30, reader ? Math.round((min + max) / 2)
      : modal ? Math.round(viewport.height * .48) : viewport.height - 160);
    await target.mouse.wheel(0, !box && attempt === 0 ? -18000 : box && box.y < min ? -430 : 430);
    await target.waitForTimeout(250);
  }
  throw new QaFailure('expected_mobile_control_or_text_not_visible');
}
async function tap(target, locator, options) {
  const item = await reveal(target, locator, options);
  const box = await item.boundingBox();
  check(box && box.height < target.viewportSize().height && box.width > 0,
    'touch_control_has_no_usable_bounds');
  await target.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  await target.waitForTimeout(200);
}
async function typeField(target, locator, value, options) {
  const item = await reveal(target, locator, options);
  await item.click({position: {x: 20, y: 20}});
  await target.waitForTimeout(250);
  await target.keyboard.press('Control+A');
  await target.keyboard.type(value, {delay: 8});
  await target.waitForTimeout(150);
  check(await item.inputValue() === value, 'visible_editor_did_not_accept_keyboard_input');
}
async function uiResponse(target, locator, route, method = 'POST', status = 200, options) {
  const waiting = target.waitForResponse(response => apiPath(response) === '/api' + route &&
    response.request().method() === method, {timeout: 45000});
  waiting.catch(() => {});
  await tap(target, locator, options);
  const response = await waiting;
  check(response.status() === status, 'ui_request_failed_' + response.status());
  return response.json();
}
async function screenshot(target, filename, {scroll = true} = {}) {
  if (scroll) await top(target);
  await privateWrite(path.join(artifacts, artifactPrefix() + '-' + filename + '.png'), await target.screenshot());
}
async function intent(key, function_) {
  check(!journey.ai_intents[key], 'saved_ai_intent_must_not_be_repeated');
  journey.ai_intents[key] = {function: function_, attempted_at: new Date().toISOString(), dispatches: 0};
  await persist(phase, false);
}
async function permitAi(key, function_, route) {
  if (journey.ai_intents[key]) {
    // A pre-click checkpoint can exist even though no request ever left the
    // browser. Only that undispatched operation may continue on an explicit
    // resumed --run. A possibly sent request is never repeated.
    check(journey.ai_intents[key].function === function_ && journey.ai_intents[key].dispatches === 0,
      'saved_ai_dispatch_must_not_be_repeated');
  } else await intent(key, function_);
  permits.set('/api' + route, key);
}
async function guardRequest(route) {
  const request = route.request();
  const routePath = new URL(request.url()).pathname;
  if (request.method() !== 'POST' || !isAiRoute(routePath)) return route.continue();
  const key = permits.get(routePath);
  const entry = key && journey.ai_intents[key];
  if (!entry || entry.dispatches !== 0) {
    blockedRequests.push({reason: 'unrequested_or_duplicate_ai_post', function: routePath.split('/').at(-1)});
    return route.abort('blockedbyclient');
  }
  permits.delete(routePath);
  if (entry.retry_reason === 'deployed_math_task_fix') {
    const requestKey = request.headers()['idempotency-key'];
    // Keep only a fingerprint. The normal Flutter control creates this key;
    // the driver never injects a request or changes the client's key.
    if (typeof requestKey !== 'string' || !requestKey || requestKey.length > 80) {
      blockedRequests.push({reason: 'explicit_stage_retry_missing_ui_idempotency_key', function: 'unit'});
      return route.abort('blockedbyclient');
    }
    entry.idempotency_key_sha256 = digest(requestKey);
  }
  entry.dispatches = 1;
  await persist(phase, false);
  return route.continue();
}
async function waitJob(id, code) {
  for (let poll = 0; poll < 110; poll++) {
    const job = await jsonGet(child, '/jobs/' + id);
    check(job.status !== 'failed', code + '_failed_no_retry');
    if (job.status === 'completed') return job;
    check(['queued', 'running'].includes(job.status), 'unexpected_ai_job_state');
    await page.waitForTimeout(2000);
  }
  throw new QaFailure(code + '_bounded_wait_expired');
}
async function waitDay(predicate, code) {
  for (let poll = 0; poll < 110; poll++) {
    const day = await dayState();
    check(day?.id === journey.day_id && !day.last_error, code + '_failed_no_retry');
    if (predicate(day)) return day;
    await page.waitForTimeout(2000);
  }
  throw new QaFailure(code + '_bounded_wait_expired');
}
async function loginChild() {
  await persist('independent_child_login_390px');
  const documentResponse = await open(page, '/login');
  const policyHeader = (await documentResponse.allHeaders())['permissions-policy'] ?? '';
  const browserPolicy = await page.evaluate(() => {
    const policy = document.permissionsPolicy ?? document.featurePolicy;
    return {secure: window.isSecureContext, supported: typeof policy?.allowsFeature === 'function',
      microphone_allowed: typeof policy?.allowsFeature === 'function' ? policy.allowsFeature('microphone') : null};
  });
  check(/(?:^|,)\s*microphone\s*=\s*\([^)]*\bself\b[^)]*\)/i.test(policyHeader) &&
    browserPolicy.secure && browserPolicy.supported && browserPolicy.microphone_allowed === true,
    'public_permissions_policy_does_not_allow_explicit_microphone_use');
  check(unexpectedAudioStarts.length === 0, 'automatic_microphone_start_detected');
  journey.evidence.public_microphone_policy_allows_explicit_use = true;
  await typeField(page, page.getByRole('textbox', {name: 'E-Mail oder Benutzername', exact: true}), account.credentials.child_username);
  await typeField(page, page.getByLabel('Passwort', {exact: true}), account.credentials.child_password);
  const data = await uiResponse(page, button(page, 'Anmelden'), '/auth/login');
  check(data.user?.role === 'child' && data.user.child_id === account.child_id,
    'child_ui_login_has_wrong_identity');
  await page.waitForURL(base + '/app', {timeout: 30000});
  authenticated = true;
  const cookie = (await child.cookies()).find(value => value.name === 'sp_session');
  check(cookie?.secure && cookie.httpOnly && cookie.sameSite === 'Strict', 'child_session_cookie_is_not_secure');
  journey.evidence.child_ui_login = true;
  await screenshot(page, 'mobile-home');
}
async function prepareDay() {
  await persist('normal_photo_wizard');
  if (journey.day_id || account.school_day_id) {
    journey.day_id ??= account.school_day_id;
    await open(page, wizardRoute());
  } else {
    await tap(page, page.getByRole('button', {name: /^(Nach der Schule starten|Neue Heftfotos|Heftfotos sammeln|Heftfotos fortsetzen)$/}).first());
    await page.waitForURL(new RegExp('/after-school/' + account.child_id + '(?:\\?|$)'), {timeout: 30000});
  }
  let day;
  for (let poll = 0; poll < 30; poll++) {
    day = await dayState();
    if (day) break;
    await page.waitForTimeout(500);
  }
  check(day?.child_id === account.child_id && day.synthetic === false, 'regular_owned_school_day_missing');
  journey.day_id = day.id;
  journey.day_date ??= day.date;
  check(journey.day_date === day.date && (!day.read_only || day.stage === 'ready'),
    'saved_day_is_read_only_do_not_create_another_household');
  await persist('owned_day_identified');
  check(day.pages.length <= 2 && !day.last_error, 'saved_photo_or_package_failure_no_retry');
  if (day.active_job) await waitJob(day.active_job.id, 'existing_photo_or_package_job');
  day = await dayState();
  if (day.pages.length < 2) {
    check(day.stage === 'collecting' && !journey.source_upload_started,
      'interrupted_upload_needs_manual_check_not_duplicate_photos');
    journey.source_upload_started = true;
    await persist('real_photo_picker_and_crops');
    const chosen = page.waitForEvent('filechooser', {timeout: 30000});
    chosen.catch(() => {});
    await tap(page, button(page, 'Fotos auswählen'));
    await (await chosen).setFiles(account.image_paths);
    for (let index = 0; index < 2; index++) {
      await button(page, 'Zuschnitt übernehmen').waitFor({state: 'attached', timeout: 30000});
      await tap(page, button(page, 'Zuschnitt übernehmen'), {modal: true});
      await page.waitForTimeout(700);
    }
    day = await waitDay(value => value.pages.length === 2, 'two_original_photo_uploads');
    journey.evidence.normal_uploads_and_crops = 2;
    await screenshot(page, 'mobile-photos');
  }
  check(day.pages.length === 2 && day.pages.every(value => value.synthetic === false),
    'expected_two_regular_artificial_materials');
  const pending = day.pages.filter(value => value.status === 'uploaded');
  if (pending.length) {
    await persist('explicit_continue_recognizes_each_page_once');
    for (const material of pending) await permitAi('extract:' + material.id, 'extract', '/materials/' + material.id + '/extract');
    await tap(page, button(page, 'Weiter'));
    day = await waitDay(value => value.pages.every(material => ['review', 'confirmed'].includes(material.status)), 'photo_recognition');
  }
  if (retryOcrAfterFix && day.pages.some(value => words(value.content) < 130)) {
    day = await retryShortOcrAfterFix(day);
  }
  check(day.pages.every(value => value.extraction_provider === 'openrouter' && words(value.content) >= 130),
    'real_ocr_or_original_page_density_missing');
  const content = day.pages.map(value => value.content).join(' ');
  check(/12\s*[/⁄]\s*18/.test(content) && /2\s*[/⁄]\s*3/.test(content),
    'ocr_lost_fixed_artificial_fraction_examples');
  for (const material of day.pages.filter(value => !value.confirmed)) {
    await persist('explicitly_confirm_page_' + material.page_number);
    await reveal(page, page.getByText('Seite ' + material.page_number + ' prüfen', {exact: true}));
    const checks = page.getByRole('checkbox');
    check(await checks.count() === Math.max(1, material.uncertainties.length),
      'photo_uncertainties_must_each_be_visible');
    for (let index = 0; index < await checks.count(); index++) {
      const checkbox = checks.nth(index);
      if (await checkbox.getAttribute('aria-checked') !== 'true') await tap(page, checkbox);
      check(await checkbox.getAttribute('aria-checked') === 'true', 'uncertainty_checkbox_not_checked');
    }
    await screenshot(page, 'mobile-review-page-' + material.page_number, {scroll: false});
    await uiResponse(page, button(page, 'Stimmt, weiter'), '/materials/' + material.id + '/confirm', 'PUT');
  }
  day = await dayState();
  check(day.pages.every(value => value.confirmed), 'package_requires_every_source_confirmation');
  journey.evidence.confirmed_original_pages = 2;
  const initial = day.units.filter(unit => !unit.followup_of && unit.round_kind !== 'study_block');
  if (!initial.length) {
    check(day.stage === 'review' && !day.last_error && day.plan.estimated_minutes > 0,
      'package_not_available_under_existing_parent_plan');
    await persist('explicit_initial_package_once');
    await permitAi('package:' + day.id, 'package', '/school-days/' + day.id + '/package');
    const job = await uiResponse(page, button(page, 'Jetzt lernen'), '/school-days/' + day.id + '/package', 'POST', 202);
    journey.ai_intents['package:' + day.id].job_id = job.id;
    await persist('package_job_saved');
    await waitJob(job.id, 'initial_package');
    day = await dayState();
  }
  const roots = day.units.filter(unit => !unit.followup_of && unit.round_kind !== 'study_block');
  check(day.stage === 'ready' && roots.length === 1 && roots[0].provider === 'openrouter' &&
    roots[0].model?.endsWith(':free') && roots[0].questions.length >= 2 && roots[0].questions.length <= 5,
    'initial_package_is_not_one_real_bounded_free_unit');
  journey.initial_unit_id ??= roots[0].id;
  check(journey.initial_unit_id === roots[0].id, 'saved_initial_package_changed');
  await persist('initial_package_persisted');
  return day;
}
async function retryShortOcrAfterFix(day) {
  check(retryOcrAfterFix && day.pages.length === 2 && day.pages.every(value => !value.confirmed) &&
    day.units.length === 0 && day.pages.every(value => value.extraction_provider === 'openrouter'),
    'ocr_fix_retry_only_for_the_two_unconfirmed_owned_originals');
  const health = await jsonGet(child, '/health');
  check(typeof health.source_commit === 'string' && /^[a-f0-9]{7,40}$/.test(health.source_commit) &&
    !health.source_commit.startsWith('b3dbfa9'), 'ocr_fix_must_be_deployed_before_explicit_retry');
  journey.ocr_before_fix ??= day.pages.map(value => ({id: value.id, model: value.extraction_model,
    provider: value.extraction_provider, content_sha256: digest(value.content)}));
  await persist('explicit_operator_approved_ocr_retry_after_fix');
  for (const original of day.pages) {
    if (words(original.content) >= 130) continue;
    const key = 'extract-fix:' + original.id;
    const previous = journey.ai_intents[key];
    if (previous?.job_id) {
      await waitJob(previous.job_id, 'explicit_ocr_fix_retry');
    } else {
      // This saved review has no retry button in the child UI. The operator's
      // explicit one-off correction uses the same normal child API/session,
      // reservation and worker; no material/status/answer is patched directly.
      check(!previous?.dispatches, 'explicit_ocr_fix_retry_already_dispatched_no_more_retries');
      if (!previous) await intent(key, 'extract');
      journey.ai_intents[key].dispatches = 1;
      journey.ai_intents[key].operator_approved_retry = true;
      journey.ai_intents[key].source_commit = health.source_commit;
      await persist('one_explicit_ocr_fix_retry_page_' + original.page_number);
      const response = await child.request.post(base + '/api/materials/' + original.id + '/extract', {
        headers: {...headers, 'Idempotency-Key': 'qa-transcription-fix-' + original.id}, data: {},
      });
      check(response.status() === 202, 'explicit_ocr_fix_retry_not_accepted_no_repeat');
      const job = await response.json();
      check(typeof job.id === 'string', 'explicit_ocr_fix_retry_job_missing');
      journey.ai_intents[key].job_id = job.id;
      await persist('explicit_ocr_fix_job_saved');
      await waitJob(job.id, 'explicit_ocr_fix_retry');
    }
    const updated = await jsonGet(child, '/materials/' + original.id);
    const before = journey.ocr_before_fix.find(value => value.id === original.id);
    check(before && updated.extraction_provider === before.provider && updated.extraction_model === before.model &&
      words(updated.content) >= 130 && !updated.confirmed, 'corrected_ocr_lost_original_model_or_full_transcript');
  }
  journey.evidence.explicit_ocr_fix_retries = Object.values(journey.ai_intents)
    .filter(value => value.operator_approved_retry).length;
  check(journey.evidence.explicit_ocr_fix_retries <= 2, 'explicit_ocr_fix_retry_limit_exceeded');
  await persist('two_original_pages_retranscribed_after_deployed_fix');
  await open(page, wizardRoute());
  return dayState();
}
async function pathState() {
  return jsonGet(child, '/school-days/' + journey.day_id + '/study-path');
}
async function ensurePath() {
  await persist('planned_and_ready_learning_path');
  await open(page, wizardRoute());
  let route = await pathState();
  if (!route.available) {
    route = await uiResponse(page, button(page, 'Lernweg planen'), '/school-days/' + journey.day_id + '/study-path');
  }
  check(!route.stale && route.available && route.total_questions >= 8 &&
    (route.blocks.some(value => value.status === 'planned') || journey.evidence.planned_and_ready_distinguished),
    'source_plan_needs_at_least_eight_tasks_and_another_planned_stage');
  check(route.blocks.some(value => value.unit_id === journey.initial_unit_id),
    'initial_package_not_linked_to_saved_learning_path');
  await reveal(page, page.getByText('Dein Lernweg', {exact: true}));
  await reveal(page, page.getByText(route.ready_questions + ' bereit · ' + route.total_questions + ' im Lernweg geplant', {exact: true}));
  await tap(page, page.getByText('Alle Etappen', {exact: true}));
  for (const block of route.blocks) {
    const label = {planned: 'Geplant', ready: 'Bereit', completed: 'Bearbeitet', generating: 'Wird vorbereitet'}[block.status];
    // Flutter merges a ListTile's title and subtitle into one semantics node.
    await reveal(page, page.getByText(block.label + ' · ' + block.question_count + ' Aufgaben · ' + label, {exact: false}));
  }
  journey.evidence.planned_task_count = route.total_questions;
  if (!journey.evidence.planned_and_ready_distinguished) {
    check(route.ready_questions > 0 && route.blocks.some(value => value.status === 'planned'),
      'initial_ready_and_planned_stages_not_both_present');
    journey.evidence.planned_and_ready_distinguished = true;
  }
  await screenshot(page, 'mobile-planned-path');
  const before = await usage();
  const fingerprint = digest(JSON.stringify(route.blocks.map(block => [block.id, block.unit_id, block.question_count])));
  await open(page, wizardRoute());
  await page.reload({waitUntil: 'domcontentloaded'});
  await accessible(page);
  const after = await usage();
  const reloaded = await pathState();
  check(before.calls_used === after.calls_used &&
    fingerprint === digest(JSON.stringify(reloaded.blocks.map(block => [block.id, block.unit_id, block.question_count]))),
    'reloading_path_reserved_ai_or_replaced_saved_stages');
  journey.evidence.path_reload_without_ai = true;
  await persist('saved_learning_path_reload_verified');
  return reloaded;
}
function closed(question) {
  return question.attempts.length >= 3 || question.attempts.some(attempt => ['correct', 'uncertain'].includes(attempt.outcome));
}
function escaped(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
function independentFractionAudit(question) {
  // Independent QA arithmetic: do not import the application's validator or
  // treat its stored answer as proof. These checks cover the finite original
  // fraction fixtures; natural-language teaching quality is not proven here.
  const normalize = value => value.normalize('NFC').replace(/\s+/g, '').replaceAll('⁄', '/');
  const gcd = (a, b) => { while (b) [a, b] = [b, a % b]; return a; };
  let expected = null;
  let match = question.prompt.match(/^Kürze den Bruch (\d+)\/(\d+) vollständig\./);
  if (match) {
    const numerator = BigInt(match[1]), denominator = BigInt(match[2]);
    check(numerator > 0n && denominator > 0n, 'qa_fraction_inputs_must_be_positive');
    const divisor = gcd(numerator, denominator);
    expected = `${numerator / divisor}/${denominator / divisor}`;
  } else if ((match = question.prompt.match(/^Erweitere den Bruch (\d+)\/(\d+) mit dem Faktor (\d+)\./))) {
    expected = `${BigInt(match[1]) * BigInt(match[3])}/${BigInt(match[2]) * BigInt(match[3])}`;
  } else if ((match = question.prompt.match(/^Wie lautet der (Zähler|Nenner) des Bruchs (\d+)\/(\d+)\?/))) {
    expected = BigInt(match[match[1] === 'Zähler' ? 2 : 3]).toString();
  } else if ((match = question.prompt.match(/^Berechne (\d+)\/(\d+) \+ (\d+)\/(\d+)\./))) {
    check(match[2] === match[4], 'qa_addition_requires_explicit_shared_denominator');
    expected = `${BigInt(match[1]) + BigInt(match[3])}/${BigInt(match[2])}`;
  }
  if (expected !== null) check(normalize(question.answer) === expected,
    'independent_qa_fraction_answer_disagrees_with_stored_solution');
  let checkedEqualities = 0;
  for (const text of [...(question.hints ?? []), question.explanation ?? '']) {
    // A deliberately false counterexample is not a positive arithmetic claim.
    // Leave such prose for human review rather than reject it as a true claim.
    for (const sentence of text.split(/[.!?\n]/)) {
      if (/\b(?:falsch|fehler|behauptung|nicht)\b/i.test(sentence)) continue;
      for (const equality of sentence.matchAll(/(?=\b(\d+)\s*\/\s*(\d+)\s*=\s*(\d+)\s*\/\s*(\d+))/g)) {
        check(BigInt(equality[2]) !== 0n && BigInt(equality[4]) !== 0n &&
          BigInt(equality[1]) * BigInt(equality[4]) === BigInt(equality[3]) * BigInt(equality[2]),
          'independent_qa_hint_or_explanation_has_invalid_fraction_equality');
        checkedEqualities++;
      }
      for (const equality of sentence.matchAll(/\b(\d+)\s*(mal|×|·|\*|durch|:|÷)\s*(\d+)\s*(?:=|ist|ergibt)\s*(\d+)(?!\s*[\d/])/gi)) {
        const left = BigInt(equality[1]), right = BigInt(equality[3]), result = BigInt(equality[4]);
        check(/^(?:mal|×|·|\*)$/i.test(equality[2]) ? left * right === result
          : right !== 0n && result * right === left,
          'independent_qa_hint_or_explanation_has_invalid_integer_equality');
        checkedEqualities++;
      }
    }
  }
  return {answer_checked: expected !== null, explicit_equalities_checked: checkedEqualities};
}
async function fillAnswer(question) {
  check(typeof question.answer === 'string' && question.answer.length > 0, 'parent_cannot_read_authoritative_qa_answer');
  if (question.type === 'choice') {
    await tap(page, page.getByRole('button', {name: new RegExp('^' + escaped(question.answer) + '(?:\\s+' + escaped(question.answer) + ')?$')}));
  } else if (['short', 'gap'].includes(question.type)) {
    await typeField(page, page.getByRole('textbox', {name: 'Deine Antwort', exact: true}), question.answer);
  } else if (question.type === 'match') {
    for (const pair of question.options) {
      const [left, right] = pair.split('|');
      check(left && right, 'invalid_saved_matching_question');
      await tap(page, page.getByRole('combobox', {name: left}).or(button(page, left)).or(page.getByLabel(left, {exact: true})).first());
      await tap(page, page.getByRole('menuitem', {name: right, exact: true})
        .or(page.getByRole('option', {name: right, exact: true})).or(page.getByLabel(right, {exact: true})).last(), {modal: true});
    }
  } else throw new QaFailure('unsupported_saved_structured_question');
}
async function finishUnit(unitId, label, {hint = false} = {}) {
  await persist('answer_' + label + '_through_actual_ui');
  let unit = await jsonGet(parent, '/units/' + unitId);
  check(unit.child_id === account.child_id && unit.synthetic === false && unit.provider === 'openrouter' &&
    unit.model?.endsWith(':free') && unit.questions.length >= 2 && unit.questions.length <= 5,
    'owned_free_structured_unit_required');
  await open(page, '/unit/' + unitId);
  if (unit.status !== 'completed' && unit.status !== 'active') {
    await uiResponse(page, button(page, unit.status === 'paused' ? 'Lernen fortsetzen' : 'Einheit starten'), '/units/' + unitId + '/start');
  }
  if (unit.status !== 'completed' && !unit.introduction_seen) {
    await uiResponse(page, button(page, 'Weiter zu den Übungen'), '/units/' + unitId + '/introduction');
  }
  for (let index = 0; index < unit.questions.length; index++) {
    const question = unit.questions[index];
    if (closed(question)) continue;
    try {
      const audit = independentFractionAudit(question);
      journey.math_audits ??= {};
      journey.math_audits[unitId + ':' + question.id] = audit;
    } catch (error) {
      await privateWrite(path.join(artifacts, '.' + artifactPrefix() + '-math-audit-failed.json'),
        JSON.stringify({unit_id: unitId, question, reason: safeReason(error)}, null, 2) + '\n');
      throw error;
    }
    await reveal(page, page.getByText(question.prompt, {exact: true}));
    if (hint && index === 0 && question.hints_used === 0) {
      const saved = await uiResponse(page, button(page, 'Ein Hinweis bitte'), '/units/' + unitId + '/questions/' + question.id + '/hint');
      check(typeof saved.hint === 'string' && saved.hint.trim(), 'actual_saved_hint_missing');
      await reveal(page, page.getByText(saved.hint, {exact: true}));
      journey.evidence.used_actual_hint = true;
    }
    await fillAnswer(question);
    const last = unit.questions.filter(value => !closed(value)).length === 1;
    if (last && !journey.ai_intents['review:' + unitId]) {
      // The final answer commits first; the server then queues exactly one
      // independent coach request. This is not a browser-generated fake report.
      await intent('review:' + unitId, 'coach');
    }
    const response = await uiResponse(page, button(page, 'Antwort prüfen'), '/units/' + unitId + '/questions/' + question.id + '/answer');
    check(response.outcome === 'correct', 'stored_authoritative_artificial_answer_was_not_correct');
    await reveal(page, page.getByText('Richtig!', {exact: true}));
    check(!response.explanation || await page.getByText(response.explanation, {exact: true}).count() > 0,
      'educational_answer_explanation_not_rendered');
    const next = unit.questions.slice(index + 1).find(value => !closed(value));
    check(!next || !await page.getByText(next.prompt, {exact: true}).isVisible(),
      'feedback_disappeared_before_explicit_continue');
    if (index === 0) await screenshot(page, 'mobile-feedback-' + label, {scroll: false});
    unit = response.unit;
    // Keep authoritative private answer keys only in memory, not the client
    // response (where hiding unanswered solutions is the correct behavior).
    await tap(page, button(page, unit.status === 'completed' ? 'Zum Rückblick' : 'Weiter'));
    journey.evidence.feedback_steps = (journey.evidence.feedback_steps ?? 0) + 1;
    unit = await jsonGet(parent, '/units/' + unitId);
    await persist('saved_answer_' + label + '_' + (index + 1));
  }
  await reveal(page, page.getByText('Runde geschafft!', {exact: true}));
  return waitReview(unitId, label);
}
function reportSignature(coach) {
  return digest(JSON.stringify({provider: coach.provider, model: coach.model, request_count: coach.request_count,
    summary: coach.report?.summary, explanation: coach.report?.explanation, question_reviews: coach.report?.question_reviews}));
}
async function waitReview(unitId, label) {
  for (let poll = 0; poll < 110; poll++) {
    const unit = await jsonGet(parent, '/units/' + unitId);
    check(!['blocked', 'failed'].includes(unit.coaching?.status), 'saved_review_failed_no_retry');
    if (unit.coaching?.status === 'ready') {
      check(unit.status === 'completed' && unit.coaching.provider === 'openrouter' &&
        unit.coaching.model?.endsWith(':free') && unit.coaching.request_count === 1,
        'real_separate_review_or_single_request_missing');
      const progress = unit.learning_progress;
      check(progress?.required_check_days === 3 && progress.secure_observation === false &&
        progress.learning_goals.every(goal => goal.successful_check_days <= 1 &&
          goal.successful_check_dates.every(date => date === journey.day_date)),
        'single_day_invented_secure_mastery_or_later_observations');
      if (!journey.ai_intents['practice:' + unitId]) {
        check(unit.coaching.next_unit_id === null && unit.coaching.practice_job_id === null,
          'review_automatically_generated_unrequested_practice');
      }
      await open(page, '/unit/' + unitId);
      await tap(page, page.getByText('Mein Rückblick', {exact: true}));
      await reveal(page, page.getByText(unit.coaching.report.summary, {exact: true}));
      await screenshot(page, 'mobile-review-' + label, {scroll: false});
      journey.completed_unit_ids = [...new Set([...(journey.completed_unit_ids ?? []), unitId])];
      journey.evidence.separate_ready_review = true;
      await persist('ready_review_' + label);
      return unit;
    }
    check(unit.coaching?.status === 'pending', 'review_not_automatically_queued_after_saved_answers');
    await page.waitForTimeout(2000);
  }
  throw new QaFailure('separate_review_bounded_wait_expired');
}
function stageFixKey(blockId) {
  return 'stage-math-fix:' + blockId;
}
function validateStageFixCheckpoint(block, entry) {
  const original = journey.ai_intents['stage:' + block.id];
  check(journey.artifact_tag === 'fresh-second-child' && account.previous_qa_children?.length === 1 &&
    journey.usage_baseline?.calls_used === 11 && original?.function === 'unit' &&
    original.dispatches === 1 && typeof original.job_id === 'string' && !journey.preserved_invalid_stage,
    'stage_fix_only_for_the_existing_second_child_failed_block');
  const fixKeys = Object.keys(journey.ai_intents).filter(key => key.startsWith('stage-math-fix:'));
  check(fixKeys.length <= 1 && fixKeys.every(key => key === stageFixKey(block.id)),
    'only_one_explicit_stage_fix_is_allowed');
  if (entry) {
    check(entry.function === 'unit' && entry.operator_approved_retry === true &&
      entry.retry_reason === 'deployed_math_task_fix' && entry.previous_job_id === original.job_id &&
      entry.previous_intent_sha256 === digest(JSON.stringify(original)) &&
      entry.family_calls_before === 16 && entry.original_family_baseline === 11 &&
      typeof entry.source_commit === 'string' && /^[a-f0-9]{7,40}$/.test(entry.source_commit) &&
      !entry.source_commit.startsWith('e37f14a') && [0, 1].includes(entry.dispatches),
      'stage_fix_checkpoint_or_original_history_changed');
    check(!entry.job_id || entry.dispatches === 1 && entry.job_id !== original.job_id &&
      typeof entry.idempotency_key_sha256 === 'string' && /^[a-f0-9]{64}$/.test(entry.idempotency_key_sha256),
      'stage_fix_job_must_have_a_new_normal_ui_request_key');
  }
  return original;
}
async function retryFailedStageAfterMathFix(route, block) {
  const key = stageFixKey(block.id);
  let entry = journey.ai_intents[key];
  const original = validateStageFixCheckpoint(block, entry);
  const oldJob = await jsonGet(child, '/jobs/' + original.job_id);
  check(oldJob.id === original.job_id && oldJob.status === 'failed',
    'stage_fix_requires_the_preserved_original_failed_job');
  if (entry?.job_id) {
    check(block.job_id === entry.job_id, 'stage_fix_path_job_changed_since_saved_retry');
    // A restarted driver only observes the already accepted job. In particular,
    // another deployment or another --run must never create a second retry.
    await waitJob(entry.job_id, 'explicit_stage_math_fix');
    return;
  }
  check(retryStageAfterMathFix && !entry?.dispatches,
    'stage_fix_retry_missing_explicit_flag_or_already_dispatched');
  check(!block.unit_id && block.error && block.job_id === original.job_id &&
    route.stale === false && route.can_continue && route.next_block_id === block.id,
    'stage_fix_blocked_by_existing_sources_or_parent_plan');
  const health = await jsonGet(child, '/health');
  check(typeof health.source_commit === 'string' && /^[a-f0-9]{7,40}$/.test(health.source_commit) &&
    !['e37f14a', '55e0904', 'b3dbfa9'].some(old => health.source_commit.startsWith(old)),
    'new_math_task_fix_must_be_deployed_before_explicit_stage_retry');
  const consumed = await verifyUsage();
  check(consumed.calls_used === 16 && consumed.journey_calls === 5,
    'original_sixteen_calls_must_remain_before_the_single_stage_retry');
  if (!entry) {
    entry = journey.ai_intents[key] = {function: 'unit', attempted_at: new Date().toISOString(), dispatches: 0,
      operator_approved_retry: true, retry_reason: 'deployed_math_task_fix', source_commit: health.source_commit,
      previous_job_id: original.job_id, previous_intent_sha256: digest(JSON.stringify(original)),
      family_calls_before: consumed.calls_used, original_family_baseline: journey.usage_baseline.calls_used};
  } else check(entry.source_commit === health.source_commit,
    'unsent_stage_fix_checkpoint_requires_the_same_approved_live_commit');
  await persist('single_explicit_stage_math_fix_prepared');
  const endpoint = '/school-days/' + journey.day_id + '/blocks/' + block.id;
  await permitAi(key, 'unit', endpoint);
  const job = await uiResponse(page, button(page, /^(?:Nächste Etappe|Erneut vorbereiten)$/), endpoint, 'POST', 202);
  check(typeof job.id === 'string' && job.id !== original.job_id,
    'stage_fix_did_not_create_a_new_normal_reserved_job');
  entry.job_id = job.id;
  await persist('explicit_stage_math_fix_job_saved');
  validateStageFixCheckpoint(block, entry);
  await waitJob(job.id, 'explicit_stage_math_fix');
}
async function newStage() {
  await persist('explicitly_generate_and_open_one_new_stage');
  await open(page, wizardRoute());
  let route = await pathState();
  let block = journey.stage_block_id ? route.blocks.find(value => value.id === journey.stage_block_id)
    : route.blocks.find(value => value.id === route.next_block_id);
  check(block && block.phase !== 'learning', 'next_new_planned_stage_missing');
  journey.stage_block_id ??= block.id;
  const savedFix = journey.ai_intents[stageFixKey(block.id)];
  if (savedFix) validateStageFixCheckpoint(block, savedFix);
  if (!block.unit_id) {
    if (savedFix || retryStageAfterMathFix && block.error) {
      await retryFailedStageAfterMathFix(route, block);
    } else {
      check(!block.error && route.can_continue && route.next_block_id === block.id,
        'new_stage_failed_or_blocked_by_existing_parent_plan');
      if (block.status === 'generating') {
        await waitJob(block.job_id, 'new_stage');
      } else {
        const endpoint = '/school-days/' + journey.day_id + '/blocks/' + block.id;
        await permitAi('stage:' + block.id, 'unit', endpoint);
        const job = await uiResponse(page, button(page, 'Nächste Etappe'), endpoint, 'POST', 202);
        journey.ai_intents['stage:' + block.id].job_id = job.id;
        await persist('new_stage_job_saved');
        await waitJob(job.id, 'new_stage');
      }
    }
    route = await pathState();
    block = route.blocks.find(value => value.id === journey.stage_block_id);
  }
  check(block?.unit_id && ['ready', 'completed'].includes(block.status), 'generated_stage_not_saved_as_ready');
  if (journey.ai_intents[stageFixKey(block.id)]) {
    const entry = journey.ai_intents[stageFixKey(block.id)];
    validateStageFixCheckpoint(block, entry);
    check(entry.job_id === block.job_id, 'ready_stage_does_not_match_the_saved_explicit_fix_job');
    journey.evidence.explicit_stage_math_fix_retries = 1;
  }
  journey.stage_unit_id = block.unit_id;
  await persist('new_stage_ready');
  await open(page, wizardRoute());
  if (block.status === 'ready') {
    await tap(page, button(page, 'Etappe öffnen'));
    await page.waitForURL(base + '/unit/' + block.unit_id, {timeout: 30000});
    journey.evidence.stage_opened_by_child_ui = true;
  }
  const unit = await jsonGet(parent, '/units/' + block.unit_id);
  check(unit.round_kind === 'study_block' && unit.questions.length === block.question_count &&
    unit.source_material_ids.length > 0, 'new_stage_lost_planned_extent_or_sources');
  await screenshot(page, 'mobile-new-stage');
  await finishUnit(block.unit_id, 'stage');
}
async function separatePractice(initial, {complete = true} = {}) {
  await persist('explicit_practice_after_preserved_review');
  let unit = await jsonGet(parent, '/units/' + initial.id);
  journey.initial_report_signature ??= reportSignature(unit.coaching);
  if (!unit.coaching.next_unit_id) {
    check(unit.coaching.status === 'ready' && unit.coaching.practice_deferred &&
      ['repair', 'check'].includes(unit.coaching.decision) && unit.coaching.practice_status !== 'failed',
      'explicit_practice_is_not_available_no_retry');
    await open(page, '/unit/' + unit.id);
    if (['queued', 'running'].includes(unit.coaching.practice_status)) {
      await waitJob(unit.coaching.practice_job_id, 'separate_practice');
    } else {
      const endpoint = '/units/' + unit.id + '/practice';
      await permitAi('practice:' + unit.id, 'coach_practice', endpoint);
      const job = await uiResponse(page, button(page, unit.coaching.decision === 'check'
        ? 'Ohne Hilfe ausprobieren' : 'Gezielt weiterüben'), endpoint, 'POST', 202);
      journey.ai_intents['practice:' + unit.id].job_id = job.id;
      await persist('separate_practice_job_saved');
      const during = await jsonGet(parent, '/units/' + unit.id);
      check(during.coaching.status === 'ready' && reportSignature(during.coaching) === journey.initial_report_signature,
        'preparing_practice_lost_finished_review');
      await waitJob(job.id, 'separate_practice');
    }
    unit = await jsonGet(parent, '/units/' + unit.id);
  }
  check(unit.coaching.status === 'ready' && unit.coaching.next_unit_id &&
    reportSignature(unit.coaching) === journey.initial_report_signature,
    'practice_generation_changed_finished_review_or_its_provenance');
  journey.practice_unit_id = unit.coaching.next_unit_id;
  await persist('saved_review_survived_practice_generation');
  const next = await jsonGet(parent, '/units/' + journey.practice_unit_id);
  check(next.followup_of === unit.id && next.learning_root_id === unit.id &&
    JSON.stringify([...next.source_material_ids].sort()) === JSON.stringify([...unit.source_material_ids].sort()),
    'separate_practice_lost_learning_chain_or_sources');
  if (next.status !== 'completed') {
    await open(page, '/unit/' + unit.id);
    await uiResponse(page, button(page, unit.coaching.decision === 'check' ? 'Selbst ausprobieren' : 'Weiter üben'),
      '/units/' + next.id + '/start');
    await page.waitForURL(base + '/unit/' + next.id, {timeout: 30000});
  }
  if (complete) {
    await finishUnit(next.id, 'practice');
  } else {
    check(next.questions.every(question => question.attempts.length === 0),
      'partial_continuation_must_not_modify_existing_practice_answers');
    await screenshot(page, 'mobile-practice-ready');
    journey.evidence.practice_generated_and_opened_without_answer = true;
    await persist('new_practice_opened_without_more_answers_or_coaching');
  }
  journey.evidence.practice_explicit_and_review_preserved = true;
}
async function preserveKnownInvalidStage() {
  check((continueValidInitial || readSavedResults) && journey.stage_unit_id && journey.initial_unit_id,
    'targeted_continuation_needs_existing_failed_stage_and_valid_initial');
  const invalid = await jsonGet(parent, '/units/' + journey.stage_unit_id);
  check(invalid.child_id === account.child_id && invalid.status === 'completed' &&
    invalid.coaching?.status === 'failed' && invalid.coaching.request_count === 1,
    'invalid_stage_must_remain_completed_with_one_failed_review');
  const signature = digest(JSON.stringify({status: invalid.status, questions: invalid.questions,
    coaching: invalid.coaching}));
  journey.preserved_invalid_stage ??= {id: invalid.id, signature,
    answer_count: invalid.questions.reduce((sum, question) => sum + question.attempts.length, 0)};
  check(journey.preserved_invalid_stage.id === invalid.id && journey.preserved_invalid_stage.signature === signature,
    'known_invalid_stage_or_its_answers_were_changed');
  journey.completed_unit_ids = (journey.completed_unit_ids ?? []).filter(id => id !== invalid.id);
  journey.evidence.invalid_stage_preserved_and_excluded = true;
  journey.evidence.completed = false;
  await persist('known_invalid_stage_preserved_without_retry');
}
async function tutorHistory(context) {
  return jsonGet(context, '/children/' + account.child_id + '/tutor/questions?day_id=' + journey.day_id);
}
function validateCitations(turn, materials) {
  check(turn.status === 'ready' && turn.reply?.kind === 'answer' && turn.reply.sources.length > 0 && !turn.source_changed,
    'ready_teacher_answer_with_actual_sources_missing');
  const normalize = value => value.normalize('NFC').replace(/\s+/g, ' ').trim();
  for (const citation of turn.reply.sources) {
    const material = materials.find(value => value.id === citation.material_id);
    check(material?.confirmed && typeof citation.label === 'string' &&
      citation.quote.length >= 3 && normalize(material.content).includes(normalize(citation.quote)),
      'teacher_citation_not_in_confirmed_original_source');
  }
}
async function waitTutor(id, materials) {
  for (let poll = 0; poll < 110; poll++) {
    const history = await tutorHistory(child);
    const turn = history.questions.find(value => value.id === id);
    check(turn && turn.status !== 'failed', 'teacher_question_failed_no_retry');
    if (turn.status === 'ready') {
      validateCitations(turn, materials);
      return turn;
    }
    check(['queued', 'running'].includes(turn.status), 'unexpected_teacher_turn_state');
    await page.waitForTimeout(2000);
  }
  throw new QaFailure('teacher_bounded_wait_expired');
}
async function teacherQuestions(materials) {
  await persist('teacher_question_and_conscious_followup');
  await open(page, wizardRoute());
  await tap(page, button(page, 'Fragen zu meinen Heftseiten'));
  await reveal(page, page.getByText('Frag zu deinem Stoff', {exact: true}), {modal: true});
  const endpoint = '/children/' + account.child_id + '/tutor/questions';
  const drafts = [
    'Wie kürze ich 12/18 vollständig, und warum bleibt der Wert dabei gleich?',
    'Warum muss ich beim Kürzen beide Zahlen durch dieselbe Zahl teilen? Erkläre es an 12/18.',
  ];
  const savedIds = journey.tutor_turn_ids ?? [];
  const turns = [];
  for (let index = 0; index < 2; index++) {
    let history = await tutorHistory(child);
    let turn = savedIds[index] ? history.questions.find(value => value.id === savedIds[index]) :
      history.questions.find(value => value.question === drafts[index] && value.reply_to === (index ? savedIds[0] : null));
    if (!turn) {
      check(!journey.ai_intents['teacher:' + index]?.dispatches, 'ambiguous_teacher_submission_must_not_be_repeated');
      if (index === 1) {
        const before = await usage();
        await tap(page, button(page, 'Dazu nachfragen'), {modal: true, reader: true});
        await reveal(page, page.getByText('Zu deiner letzten Antwort', {exact: true}), {modal: true});
        const after = await usage();
        check(before.calls_used === after.calls_used, 'selecting_followup_sent_an_automatic_question');
      }
      await typeField(page, page.getByRole('textbox', {name: 'Deine Frage', exact: true}), drafts[index], {modal: true});
      const before = await usage();
      await page.waitForTimeout(350);
      check((await usage()).calls_used === before.calls_used,
        'editable_teacher_draft_was_sent_without_confirmation');
      await permitAi('teacher:' + index, 'tutor', endpoint);
      turn = await uiResponse(page, button(page, 'Frage stellen'), endpoint, 'POST', 202, {modal: true});
      check(turn.id && turn.reply_to === (index ? savedIds[0] : null), 'teacher_followup_not_linked_to_previous_answer');
      savedIds[index] = turn.id;
      journey.tutor_turn_ids = savedIds;
      journey.ai_intents['teacher:' + index].job_id = turn.job_id;
      await persist('teacher_turn_' + (index + 1) + '_saved');
    } else {
      savedIds[index] = turn.id;
      journey.tutor_turn_ids = savedIds;
    }
    turn = await waitTutor(turn.id, materials);
    turns.push(turn);
    // The latest turn is rendered; earlier turns are intentionally disclosed.
    if (index === 1 || (await tutorHistory(child)).questions.at(-1)?.id === turn.id) {
      await reveal(page, page.getByText(turn.reply.answer, {exact: true}), {modal: true, partial: true, reader: true});
      await tap(page, page.getByText('Wo steht das?', {exact: true}), {modal: true, reader: true});
      await reveal(page, page.getByText('„' + turn.reply.sources[0].quote + '“', {exact: true}), {modal: true, reader: true, partial: true});
      await screenshot(page, 'mobile-teacher-source-' + (index + 1), {scroll: false});
    }
    await persist('teacher_answer_' + (index + 1) + '_with_verified_citations');
  }
  check(turns[1].reply_to === turns[0].id, 'teacher_conscious_followup_chain_missing');
  journey.evidence.teacher_question_with_sources_and_explicit_followup = true;
  await tap(page, button(page, 'Schließen'), {modal: true});
  return turns;
}
async function parentReadback(turns) {
  await persist('parent_reads_saved_learning_and_teacher_history');
  const parentPage = await parent.newPage();
  await open(parentPage, '/child/' + account.child_id);
  await tap(parentPage, parentPage.getByLabel('Lernverlauf', {exact: true})
    .or(button(parentPage, 'Lernverlauf')).first());
  await screenshot(parentPage, 'parent-learning-history');
  let answerCount = 0;
  for (const id of journey.completed_unit_ids) {
    const unit = await jsonGet(parent, '/units/' + id);
    check(unit.child_id === account.child_id && unit.status === 'completed' && unit.coaching.status === 'ready' &&
      unit.questions.every(question => question.attempts.length === 1 && question.attempts[0].outcome === 'correct'),
      'parent_cannot_read_exactly_once_saved_answers_and_ready_review');
    answerCount += unit.questions.length;
    await open(parentPage, '/unit/' + id);
    await reveal(parentPage, parentPage.getByText('Deine Lernbegleitung', {exact: true}));
    await reveal(parentPage, parentPage.getByText(unit.coaching.report.summary, {exact: true}));
    for (const question of unit.questions) {
      await reveal(parentPage, parentPage.getByText(question.prompt, {exact: true}));
      await reveal(parentPage, parentPage.getByText('Antwort: ' + question.attempts[0].answer, {exact: false}));
      if (question.hints_used > 0) {
        check(question.attempts[0].assisted && question.hints?.length > 0,
          'parent_cannot_read_saved_hint_assistance');
        await reveal(parentPage, parentPage.getByText(question.hints_used + ' Hinweise genutzt. Verfügbare Hinweise:', {exact: true}));
      }
    }
  }
  const overview = await jsonGet(parent, '/children/' + account.child_id + '/overview');
  check(overview.day_summary.answer_count >= answerCount && overview.day_summary.hints_used >= 1,
    'parent_summary_does_not_include_saved_activities');
  const history = await tutorHistory(parent);
  check(turns.every(turn => history.questions.some(saved => saved.id === turn.id &&
    saved.question === turn.question && JSON.stringify(saved.reply) === JSON.stringify(turn.reply))),
    'parent_cannot_read_stored_teacher_questions_answers_and_citations');
  await open(parentPage, wizardRoute());
  await tap(parentPage, button(parentPage, 'Fragen zum Heft ansehen'));
  await reveal(parentPage, parentPage.getByText('Fragen zum Stoff', {exact: true}), {modal: true});
  const latest = turns.at(-1);
  await reveal(parentPage, parentPage.getByText(latest.reply.answer, {exact: true}), {modal: true, partial: true, reader: true});
  await tap(parentPage, parentPage.getByText('Wo steht das?', {exact: true}), {modal: true, reader: true});
  await reveal(parentPage, parentPage.getByText('„' + latest.reply.sources[0].quote + '“', {exact: true}), {modal: true, reader: true, partial: true});
  check(await parentPage.getByRole('textbox', {name: 'Deine Frage', exact: true}).count() === 0,
    'parent_teacher_view_unexpectedly_allows_child_question_submission');
  await screenshot(parentPage, 'parent-teacher-history', {scroll: false});
  for (const turn of turns.slice(0, -1)) {
    await tap(parentPage, parentPage.getByText(turn.question, {exact: true}), {modal: true, reader: true});
    await reveal(parentPage, parentPage.getByText(turn.reply.answer, {exact: true}), {modal: true, partial: true, reader: true});
  }
  journey.evidence.parent_reads_answers_hints_reports_and_teacher_history = true;
  return answerCount;
}
function functionCounts(records) {
  const counts = {};
  for (const record of records) counts[record.function] = (counts[record.function] ?? 0) + 1;
  return counts;
}
async function prepareOneFreshChild() {
  check(prepareFreshChild && journey.evidence.invalid_stage_preserved_and_excluded &&
    journey.evidence.parent_reads_answers_hints_reports_and_teacher_history &&
    journey.evidence.failed_practice_kept_ready_report && !account.previous_qa_children?.length,
    'fresh_child_requires_completed_historical_diagnosis_no_more_than_one_second_child');
  const health = await jsonGet(parent, '/health');
  check(health.version === '1.1.1' && typeof health.source_commit === 'string' &&
    !health.source_commit.startsWith('55e0904') && !health.source_commit.startsWith('b3dbfa9'),
    'math_and_focus_fix_must_be_live_before_preparing_second_child');
  const route = '/families/' + account.user.families[0].id;
  const family = await jsonGet(parent, route);
  check(family.synthetic === false && family.children.some(value => value.id === account.child_id),
    'original_artificial_child_not_in_owned_family');
  const before = await usage();
  account.fresh_child_preparation ??= {
    username: 'normal-child-' + randomBytes(6).toString('hex') + '-2',
    password: randomBytes(24).toString('base64url'), source_commit: health.source_commit,
  };
  const preparation = account.fresh_child_preparation;
  // persist() deliberately merges the latest private file. Save this one
  // additional private preparation field explicitly before a possible POST.
  const oldChild = account.child_id;
  const latest = JSON.parse(await readFile(accountFile, 'utf8'));
  check(latest.child_id === oldChild && latest.user.id === account.user.id, 'account_changed_before_child_preparation');
  latest.fresh_child_preparation ??= preparation;
  check(latest.fresh_child_preparation.username === preparation.username,
    'another_second_child_preparation_is_already_pending');
  const temporary = accountFile + '.learning-journey-' + process.pid + '.tmp';
  await privateWrite(temporary, JSON.stringify(latest) + '\n');
  await rename(temporary, accountFile);
  account = latest;
  let fresh = family.children.find(value => value.username === preparation.username);
  if (!fresh) {
    check(!preparation.dispatched && family.children.length < family.child_limit,
      'second_child_dispatch_ambiguous_or_existing_child_limit_reached');
    preparation.dispatched = true;
    latest.fresh_child_preparation = preparation;
    await privateWrite(temporary, JSON.stringify(latest) + '\n');
    await rename(temporary, accountFile);
    const response = await parent.request.post(base + '/api' + route + '/children', {headers, data: {
      display_name: 'Künstliches Testkind 2', username: preparation.username,
      password: preparation.password, grade: 6, subjects: ['Mathematik'],
    }});
    check(response.status() === 201, 'second_child_creation_failed_no_repeat_or_limit_increase');
    fresh = await response.json();
  }
  check(fresh.id !== oldChild && fresh.username === preparation.username, 'fresh_child_identity_mismatch');
  const after = await usage();
  const afterFamily = await jsonGet(parent, route);
  check(before.calls_used === after.calls_used && before.records.length === after.records.length &&
    before.calls_limit === after.calls_limit && before.budget_micros_usd === after.budget_micros_usd &&
    before.encumbered_micros_usd === after.encumbered_micros_usd &&
    afterFamily.child_limit === family.child_limit && afterFamily.plan === family.plan,
    'preparing_second_child_changed_usage_or_family_entitlements');
  const preserveKeys = new Set(['normal_account', 'verified', 'credentials', 'user', 'image_paths',
    'previous_qa_children', 'fresh_child_preparation']);
  const previous = Object.fromEntries(Object.entries(account).filter(([key]) => !preserveKeys.has(key)));
  previous.credentials = {child_username: account.credentials.child_username, child_password: account.credentials.child_password};
  const migrated = Object.fromEntries(Object.entries(account).filter(([key]) => preserveKeys.has(key)));
  migrated.previous_qa_children = [previous];
  migrated.child_id = fresh.id;
  migrated.credentials = {...account.credentials, child_username: preparation.username, child_password: preparation.password};
  migrated.fresh_child_preparation = {...preparation, child_id: fresh.id};
  migrated.learning_journey_qa = {version: 1, artifact_tag: 'fresh-second-child',
    source_fixtures: journey.source_fixtures, ai_intents: {}, evidence: {},
    usage_baseline: {calls_used: after.calls_used, function_counts: functionCounts(after.records)},
  };
  await privateWrite(temporary, JSON.stringify(migrated) + '\n');
  await rename(temporary, accountFile);
  account = migrated;
  journey = migrated.learning_journey_qa;
  await persist('second_artificial_child_prepared_with_original_history_preserved');
  passed = true;
  return {fresh_second_child_prepared: true, original_child_and_all_history_retained: true,
    same_family_and_unchanged_limits: true, family_calls_used: after.calls_used,
    additional_ai_calls: 0, images_reused_without_changes: 2};
}
async function verifyUsage() {
  const consumed = await usage();
  check(consumed.synthetic === false && consumed.records.length < 200,
    'regular_complete_usage_ledger_required');
  const ownedChildren = new Set([account.child_id, ...(account.previous_qa_children ?? []).map(value => value.child_id)]);
  check(consumed.records.every(record => ownedChildren.has(record.child_id) &&
    record.provider === 'openrouter' && record.model.endsWith(':free') &&
    (record.cost_micros_usd === 0 || record.cost_micros_usd === null)),
    'usage_provider_or_cost_not_free_or_explicitly_unknown');
  check(consumed.unknown_cost_calls === consumed.records.filter(record => record.cost_micros_usd === null).length,
    'unknown_costs_falsely_reported_as_zero');
  const expected = Object.entries(journey.ai_intents)
    .filter(([_key, value]) => value.function === 'coach' || value.dispatches === 1);
  check(consumed.calls_used - journey.usage_baseline.calls_used === expected.length,
    'additional_or_unaccounted_ai_reservation');
  const currentCounts = functionCounts(consumed.records);
  const expectedCounts = {};
  for (const [key, value] of expected) {
    // The practice generator uses the unit model but is reserved under its
    // distinct coach_practice feature. Preserve old journal entries that
    // recorded the model function, and compare the actual ledger category.
    const feature = key.startsWith('practice:') ? 'coach_practice' : value.function;
    expectedCounts[feature] = (expectedCounts[feature] ?? 0) + 1;
  }
  for (const function_ of new Set([...Object.keys(currentCounts), ...Object.keys(journey.usage_baseline.function_counts)])) {
    check((currentCounts[function_] ?? 0) - (journey.usage_baseline.function_counts[function_] ?? 0) === (expectedCounts[function_] ?? 0),
      'ai_function_ledger_does_not_match_explicit_intents');
  }
  return {calls_used: consumed.calls_used, journey_calls: expected.length,
    known_cost_micros_usd: consumed.known_cost_micros_usd, unknown_cost_calls: consumed.unknown_cost_calls};
}
async function run() {
  await verifyImages();
  await persist('start_public_mobile_learning_journey');
  browser = await chromium.launch({headless: true, executablePath: process.env.CHROME_PATH || '/opt/google/chrome/chrome', args: ['--no-sandbox']});
  child = await browser.newContext({viewport: {width: 390, height: 844}, isMobile: true, hasTouch: true});
  parent = await browser.newContext({viewport: {width: 1440, height: 1000}});
  // No voice control is pressed in this scenario. Fail on an unexpected start,
  // while preventing a regression from recording or calling a speech service.
  // This checks the absence of autoplay; it is not a microphone device test.
  await child.exposeBinding('__schulpilotQaUnexpectedAudio', (_source, kind) => {
    unexpectedAudioStarts.push(kind === 'speech_recognition' ? 'speech_recognition' : 'microphone');
  });
  await child.addInitScript(() => {
    const blocked = kind => {
      void window.__schulpilotQaUnexpectedAudio(kind);
      return new DOMException('QA does not request audio recording.', 'NotAllowedError');
    };
    if (navigator.mediaDevices?.getUserMedia) {
      const original = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
      navigator.mediaDevices.getUserMedia = constraints => constraints?.audio
        ? Promise.reject(blocked('microphone')) : original(constraints);
    }
    const constructors = new Set([window.SpeechRecognition, window.webkitSpeechRecognition].filter(Boolean));
    for (const recognition of constructors) {
      recognition.prototype.start = function () { throw blocked('speech_recognition'); };
    }
  });
  for (const context of [child, parent]) context.on('page', target => target.on('pageerror', error => {
    // Runtime messages can quote private text. Keep only a fingerprint and an
    // allowlisted error class; screenshots show this artificial household.
    runtimeErrors.push({name: /^[A-Za-z]+Error$/.test(error.name) ? error.name : 'RuntimeError', signature: digest(error.message)});
  }));
  await child.route('**/api/**', guardRequest);
  const login = await parent.request.post(base + '/api/auth/login', {
    headers, data: {username: account.credentials.parent_username, password: account.credentials.parent_password},
  });
  check(login.status() === 200, 'prepared_parent_login_failed');
  const identity = (await login.json()).user;
  check(identity?.role === 'parent' && identity.id === account.user.id &&
    identity.families.length === 1 && identity.families[0].id === account.user.families[0].id &&
    identity.families[0].synthetic === false, 'prepared_parent_family_identity_changed');
  const status = await jsonGet(parent, '/status');
  check(status.real_data_enabled && status.ai_available && status.ai_free_only && status.ai_data_collection === 'deny',
    'approved_free_data_collection_denied_provider_is_not_available');
  const baseline = await usage();
  if (!journey.usage_baseline) {
    journey.usage_baseline = {calls_used: baseline.calls_used, function_counts: functionCounts(baseline.records)};
    await persist('regular_family_budget_baseline_saved');
  }
  if (prepareFreshChild) return prepareOneFreshChild();
  page = await child.newPage();
  await loginChild();
  if (readSavedResults) {
    check(journey.day_id && journey.initial_unit_id && journey.tutor_turn_ids?.length === 2 &&
      journey.preserved_invalid_stage, 'saved_results_mode_requires_existing_private_checkpoints');
    await preserveKnownInvalidStage();
    const initial = await jsonGet(parent, '/units/' + journey.initial_unit_id);
    check(initial.coaching?.status === 'ready' && initial.coaching.practice_status === 'failed' &&
      initial.coaching.request_count === 1 && initial.coaching.next_unit_id === null &&
      reportSignature(initial.coaching) === journey.initial_report_signature,
      'saved_initial_report_did_not_survive_failed_practice');
    const day = await dayState();
    const history = await tutorHistory(child);
    const turns = journey.tutor_turn_ids.map(id => history.questions.find(turn => turn.id === id));
    for (const turn of turns) { check(turn, 'saved_tutor_turn_missing'); validateCitations(turn, day.pages); }
    const before = await usage();
    const answerCount = await parentReadback(turns);
    const consumed = await verifyUsage();
    check(consumed.calls_used === before.calls_used && blockedRequests.length === 0 &&
      runtimeErrors.length === 0 && unexpectedAudioStarts.length === 0,
      'readback_reserved_ai_or_had_browser_failures');
    journey.evidence.failed_practice_kept_ready_report = true;
    await persist('saved_parent_readback_passed_with_known_failures_retained');
    passed = true;
    return {qa_passed: false, saved_results_readback_passed: true, known_invalid_stage_preserved: true,
      preserved_invalid_stage_answers: journey.preserved_invalid_stage.answer_count,
      original_report_ready_after_failed_practice: true, teacher_questions: turns.length,
      valid_saved_answers: answerCount, additional_ai_calls_for_readback: 0, ...consumed,
      runtime_errors: runtimeErrors, automatic_audio_starts: unexpectedAudioStarts.length,
      household_retained_for_android_and_fresh_test: true};
  }
  const day = await prepareDay();
  await ensurePath();
  const initial = await finishUnit(journey.initial_unit_id, 'initial', {hint: true});
  let turns;
  if (continueValidInitial) {
    await preserveKnownInvalidStage();
    turns = await teacherQuestions(day.pages);
    await separatePractice(initial, {complete: false});
    await preserveKnownInvalidStage();
  } else {
    await newStage();
    await separatePractice(initial);
    turns = await teacherQuestions(day.pages);
  }
  const answers = await parentReadback(turns);
  await persist('saved_feature_reload_without_ai');
  const before = await usage();
  await open(page, '/unit/' + journey.initial_unit_id);
  await open(page, wizardRoute());
  await tap(page, button(page, 'Fragen zu meinen Heftseiten'));
  await reveal(page, page.getByText(turns.at(-1).reply.answer, {exact: true}), {modal: true, partial: true, reader: true});
  check((await usage()).calls_used === before.calls_used, 'saved_feature_reload_triggered_another_ai_request');
  const consumed = await verifyUsage();
  check(blockedRequests.length === 0, 'unexpected_or_duplicate_ai_ui_requests_blocked');
  check(unexpectedAudioStarts.length === 0, 'automatic_microphone_start_detected');
  check(runtimeErrors.length === 0, 'browser_runtime_errors_detected');
  journey.evidence.no_automatic_microphone_start = true;
  journey.evidence.completed = !continueValidInitial;
  await persist(continueValidInitial ? 'authorized_partial_continuation_passed' : 'passed');
  passed = true;
  return {qa_passed: !continueValidInitial, authorized_partial_continuation_passed: continueValidInitial,
    known_invalid_stage_requires_fresh_test: continueValidInitial,
    preserved_invalid_stage_answers: continueValidInitial ? journey.preserved_invalid_stage.answer_count : 0,
    mobile_viewport: 390, real_openrouter: true, artificial_original_pages: 2,
    completed_units: journey.completed_unit_ids.length, saved_answers: answers,
    teacher_questions: turns.length, ...consumed, runtime_errors: runtimeErrors,
    independent_fraction_answers_checked: Object.values(journey.math_audits ?? {})
      .filter(value => value.answer_checked).length,
    explicit_teaching_equalities_checked: Object.values(journey.math_audits ?? {})
      .reduce((sum, value) => sum + value.explicit_equalities_checked, 0),
    natural_language_teaching_fully_verified: false,
    automatic_audio_starts: unexpectedAudioStarts.length,
    explicit_ai_retries: Object.values(journey.ai_intents).filter(value => value.operator_approved_retry).length,
    explicit_stage_math_fix_retries: Object.values(journey.ai_intents)
      .filter(value => value.retry_reason === 'deployed_math_task_fix' && value.dispatches === 1).length,
    household_retained_for_android: true, evidence: journey.evidence};
}

try {
  check(allowedModes.has(mode) && (arguments_.length === 1 ||
    mode === '--run' && arguments_.length === 2 &&
      ['--retry-ocr-after-fix', '--continue-valid-initial', '--read-saved-results', '--prepare-fresh-child',
        '--retry-stage-after-math-fix'].includes(arguments_[1])),
    'choose_help_prepare_images_check_inputs_or_run');
  if (mode === '--help') {
    console.log('Local fixtures: node qa/learning_journey.mjs --prepare-images\nLocal check: node qa/learning_journey.mjs --check-inputs\nAfter deployment: node qa/learning_journey.mjs --run\nOperator-approved OCR correction only after deployed fix: add --retry-ocr-after-fix (one retry per original page).\nTargeted partial continuation from the valid initial review: add --continue-valid-initial (no stage retry or new answers).\nSaved parent views only: add --read-saved-results (no AI requests).\nONLY after a separate explicit instruction, with math/focus fix live: add --prepare-fresh-child (one second child, same family, no AI/limit reset); then --run uses it and retains the original child privately.\nONLY after a separate explicit instruction and a newer backend deployment: add --retry-stage-after-math-fix (one extra UI generation for the existing second-child failed block; original 16 calls retained, saved retry jobs read only).\nNo automatic retries or household cleanup.');
  } else {
    await localInputs();
    if (mode === '--prepare-images') await prepareImages();
    else if (mode === '--check-inputs') {
      await verifyImages();
      console.log(JSON.stringify({local_inputs_valid: true, artificial_pages: 2,
        word_counts: journey.source_fixtures.word_counts, network_requests: 0}));
    } else {
      const report = await run();
      await privateWrite(resultPath(), JSON.stringify(report, null, 2) + '\n');
      console.log(JSON.stringify(report));
    }
  }
} catch (error) {
  process.exitCode = 1;
  const report = {qa_passed: false, stopped_at: phase, reason: safeReason(error),
    explicit_ai_retries: Object.values(journey?.ai_intents ?? {}).filter(value => value.operator_approved_retry).length,
    explicit_stage_math_fix_retries: Object.values(journey?.ai_intents ?? {})
      .filter(value => value.retry_reason === 'deployed_math_task_fix' && value.dispatches === 1).length,
    private_account_retained: Boolean(account), runtime_errors: runtimeErrors,
    blocked_ai_requests: blockedRequests.length,
    automatic_audio_starts: unexpectedAudioStarts.length,
    usage: lastUsage && {calls_used: lastUsage.calls_used, known_cost_micros_usd: lastUsage.known_cost_micros_usd,
      unknown_cost_calls: lastUsage.unknown_cost_calls}};
  if (mode === '--run' && parent) {
    const consumed = await usage().catch(() => null);
    if (consumed) report.usage = {calls_used: consumed.calls_used, known_cost_micros_usd: consumed.known_cost_micros_usd,
      unknown_cost_calls: consumed.unknown_cost_calls};
  }
  if (mode === '--run' && authenticated && page) await screenshot(page, 'debug', {scroll: false}).catch(() => {});
  if (mode === '--run') await privateWrite(resultPath(), JSON.stringify(report, null, 2) + '\n').catch(() => {});
  console.error(JSON.stringify(report));
} finally {
  if (browser) await browser.close().catch(() => {});
}
