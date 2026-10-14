// Real mobile-browser journey, using only the regular artificial family made by
// scripts/prepare_normal_ai_smoke.py. Run from qa/; interruption keeps the private
// account/checkpoints for resume. This driver never creates another family.
// --keep-for-native retains the successful household for native APK checks.
// --retry-failed-package permits one explicit UI retry of this day's failed
// package. --retry-failed-coaching permits one explicit UI retry per failed unit.
// OCR is never retried by this driver and no replacement model is used.
import {chromium} from 'playwright';
import {chmod, readFile, realpath, rename, unlink, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const base = 'https://schulpilot.dorfspy.de';
const artifacts = fileURLToPath(new URL('../artifacts/', import.meta.url));
const accountFile = path.join(artifacts, '.school-day-qa-account.json');
const allowedFlags = new Set(['--keep-for-native', '--retry-failed-package', '--retry-failed-coaching', '--diagnose-package-once']);
const flags = new Set(process.argv.slice(2));
const headers = {'X-Schulpilot-Request': '1'};
const errors = [];
let account;
let browser;
let parent;
let child;
let childPage;
let phase = 'private_account';
let passed = false;
let aiMutationRequests = 0;

class QaFailure extends Error {}
function check(value, code) {
  if (!value) throw new QaFailure(code);
}
function button(page, name) {
  return page.getByRole('button', {name, exact: true});
}
function apiPath(response) {
  return new URL(response.url()).pathname;
}
async function checkpoint(nextPhase) {
  phase = nextPhase;
  account.browser_qa ??= {evidence: {}};
  account.browser_qa.evidence ??= {};
  account.browser_qa.phase = phase;
  account.browser_qa.updated_at = new Date().toISOString();
  const temporary = accountFile + '.tmp';
  await writeFile(temporary, JSON.stringify(account) + '\n', {mode: 0o600});
  await chmod(temporary, 0o600);
  await rename(temporary, accountFile);
  console.log(JSON.stringify({qa_phase: phase}));
}
async function jsonGet(context, route) {
  const response = await context.request.get(base + '/api' + route);
  check(response.status() === 200, 'api_read_failed_' + response.status());
  return response.json();
}
async function dayState() {
  if (account.school_day_id) return jsonGet(child, '/school-days/' + account.school_day_id);
  return (await jsonGet(child, '/children/' + account.child_id + '/school-day/today')).day;
}
async function usage() {
  return jsonGet(parent, '/families/' + account.user.families[0].id + '/usage');
}
async function accessible(page) {
  await page.waitForSelector('flutter-view', {timeout: 90000});
  await page.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(node => node.click()));
  await page.waitForTimeout(350);
}
async function open(page, route) {
  await page.goto(base + route, {waitUntil: 'domcontentloaded', timeout: 90000});
  await accessible(page);
}
async function scrollTop(page) {
  const viewport = page.viewportSize();
  await page.mouse.move(viewport.width - 32, Math.max(200, viewport.height - 150));
  await page.mouse.wheel(0, -16000);
  await page.waitForTimeout(300);
}
async function reveal(page, locator, {modal = false} = {}) {
  const target = locator.first();
  const viewport = page.viewportSize();
  const top = modal ? 4 : 75;
  const bottom = viewport.height - (modal ? 4 : 100);
  for (let attempt = 0; attempt < 32; attempt++) {
    const box = await target.count() ? await target.boundingBox({timeout: 500}).catch(() => null) : null;
    // The app bar and bottom navigation are fixed. A DOM element underneath them
    // is not a usable touch target even when Playwright calls it visible.
    if (box && box.width > 0 && box.height > 0 && box.y >= top && box.y + box.height <= bottom) return target;
    await page.mouse.move(viewport.width - 28, viewport.height - 160);
    await page.mouse.wheel(0, !box && attempt === 0 ? -16000 : box && box.y < top ? -460 : 460);
    await page.waitForTimeout(250);
  }
  throw new QaFailure('expected_touch_control_not_visible');
}
async function tap(page, locator, options) {
  const target = await reveal(page, locator, options);
  const box = await target.boundingBox();
  check(box && box.width > 0 && box.height > 0, 'touch_control_has_no_bounds');
  // Physical pointer input also works across Flutter's modal semantics barrier;
  // no DOM event injection or application-state calls substitute for the UI.
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  await page.waitForTimeout(180);
}
async function typeField(page, locator, value) {
  const field = await reveal(page, locator);
  // Flutter's textarea semantics also encloses its counter. Click in the
  // actual input area and verify that keyboard input reached the editor.
  await field.click({position: {x: 20, y: 20}});
  await page.waitForTimeout(250);
  if (await field.inputValue()) {
    await page.keyboard.press('Control+A');
    await page.keyboard.press('Backspace');
  }
  await page.keyboard.type(value, {delay: 15});
  await page.waitForTimeout(150);
  check(await field.inputValue() === value, 'native_web_input_did_not_receive_keyboard_text');
}
async function tapResponse(page, locator, route, method, status) {
  const pending = page.waitForResponse(response => apiPath(response) === '/api' + route && response.request().method() === method, {timeout: 45000});
  pending.catch(() => {});
  await tap(page, locator);
  const response = await pending;
  check(response.status() === status, 'ui_request_failed_' + response.status());
  return response.json();
}
async function screenshot(page, filename) {
  await scrollTop(page);
  await page.screenshot({path: path.join(artifacts, filename)});
}
async function loginChild() {
  await checkpoint('child_login_ui_390px');
  await open(childPage, '/login');
  await typeField(childPage, childPage.getByRole('textbox', {name: 'E-Mail oder Benutzername', exact: true}), account.credentials.child_username);
  await typeField(childPage, childPage.getByLabel('Passwort', {exact: true}), account.credentials.child_password);
  const loggedIn = await tapResponse(childPage, button(childPage, 'Anmelden'), '/auth/login', 'POST', 200);
  check(loggedIn.user?.role === 'child' && loggedIn.user?.child_id === account.child_id, 'independent_child_login_identity_mismatch');
  await childPage.waitForURL(base + '/app', {timeout: 30000});
  const session = (await child.cookies()).find(cookie => cookie.name === 'sp_session');
  check(session?.secure && session?.httpOnly && session.sameSite === 'Strict', 'child_cookie_is_not_secure');
  account.browser_qa.evidence.independent_child_ui_login = true;
  await screenshot(childPage, 'school-day-child-home-mobile.png');
}
async function enterWizard() {
  await checkpoint('child_home_to_photo_wizard');
  const homeAction = childPage.getByRole('button', {name: /^(Nach der Schule starten|Neue Heftfotos|Heftfotos fortsetzen|Heftfotos sammeln)$/}).first();
  await tap(childPage, homeAction);
  await childPage.waitForURL(new RegExp('/after-school/' + account.child_id + '(?:\\?|$)'), {timeout: 30000});
  let day;
  for (let poll = 0; poll < 30; poll++) {
    day = await dayState();
    if (day) break;
    await childPage.waitForTimeout(500);
  }
  check(day && day.synthetic === false && day.child_id === account.child_id, 'regular_photo_day_not_created');
  account.school_day_id ??= day.id;
  check(account.school_day_id === day.id, 'stored_qa_day_changed');
  check(!day.read_only || day.stage === 'ready', 'saved_day_is_now_read_only_resume_without_creating_another_family');
  await checkpoint('photo_wizard_open');
  return day;
}
async function waitDay(predicate, code, polls = 165) {
  for (let poll = 0; poll < polls; poll++) {
    const day = await dayState();
    check(day && day.id === account.school_day_id, 'saved_day_identity_changed');
    check(!day.last_error, code + '_failed_no_automatic_retry');
    if (predicate(day)) return day;
    await childPage.waitForTimeout(2000);
  }
  throw new QaFailure(code + '_bounded_wait_expired');
}
async function uploadAndConfirm(day) {
  check(day.pages.length <= 2, 'unexpected_pages_in_owned_qa_day');
  if (day.active_job?.kind === 'package') day = await waitPackageJob(day.active_job.id);
  else if (day.active_job) day = await waitDay(value => !value.active_job, 'resume_existing_job');
  // Once every page is confirmed, day.last_error can describe the previous
  // package job. Its single operator-requested retry is handled separately;
  // never repeat the already successful image recognition or confirmations.
  if (day.last_error && day.stage === 'review' && day.units.length === 0 && day.pages.length === 2 && day.pages.every(page => page.confirmed)) {
    check(flags.has('--retry-failed-package'), 'existing_package_failed_requires_explicit_retry_flag');
    return day;
  }
  check(!day.last_error, 'existing_photo_job_failed_no_automatic_retry');
  if (day.stage === 'ready') return day;
  if (day.stage === 'collecting') {
    if (day.pages.length < 2) {
      await checkpoint('real_file_picker_and_crops');
      const images = account.image_paths.slice(day.pages.length);
      const picked = childPage.waitForEvent('filechooser', {timeout: 30000});
      picked.catch(() => {});
      await tap(childPage, button(childPage, 'Fotos auswählen'));
      await (await picked).setFiles(images);
      for (let index = 0; index < images.length; index++) {
        const crop = button(childPage, 'Zuschnitt übernehmen');
        await crop.waitFor({state: 'attached', timeout: 30000});
        await tap(childPage, crop, {modal: true});
        await childPage.waitForTimeout(700);
      }
      day = await waitDay(value => value.pages.length === 2, 'two_real_uploads', 45);
    }
    await screenshot(childPage, 'school-day-child-mobile.png');
    await checkpoint('continue_automatically_recognizes_two_pages');
    await tap(childPage, button(childPage, 'Weiter'));
  } else if (day.pages.some(page => page.status === 'uploaded')) {
    // A stopped browser can have uploaded photos without having started OCR.
    // Reopening the persisted review shows one Continue button for those pages;
    // an active or failed request above is never silently started a second time.
    await checkpoint('resume_unprocessed_uploaded_pages');
    await tap(childPage, button(childPage, 'Weiter'));
  }
  day = await waitDay(value => value.pages.length === 2 && value.pages.every(page => ['review', 'confirmed'].includes(page.status)), 'real_page_recognition');
  check(day.pages.every(page => page.synthetic === false && page.extraction_provider === 'openrouter'), 'photo_recognition_was_not_actual_openrouter');
  const contents = day.pages.map(page => page.content).join(' ');
  check(/3\s*[/⁄]\s*9|\\(?:t)?frac\s*\{3\}\s*\{9\}/.test(contents), 'original_artificial_fraction_example_not_recognized');
  for (const page of day.pages.filter(value => !value.confirmed)) {
    await checkpoint('confirm_page_' + page.page_number);
    await reveal(childPage, childPage.getByText('Seite ' + page.page_number + ' prüfen', {exact: true}));
    const checks = childPage.getByRole('checkbox');
    const expected = Math.max(1, page.uncertainties.length);
    check(await checks.count() === expected, 'each_page_uncertainty_requires_its_own_confirmation');
    for (let index = 0; index < expected; index++) {
      const checkbox = checks.nth(index);
      await reveal(childPage, checkbox);
      if (await checkbox.getAttribute('aria-checked') !== 'true') await tap(childPage, checkbox);
      check(await checkbox.getAttribute('aria-checked') === 'true', 'page_confirmation_checkbox_not_checked');
    }
    await screenshot(childPage, 'school-day-child-review-page-' + page.page_number + '.png');
    await tapResponse(childPage, button(childPage, 'Stimmt, weiter'), '/materials/' + page.id + '/confirm', 'PUT', 200);
    await childPage.waitForTimeout(450);
  }
  day = await dayState();
  check(day.pages.length === 2 && day.pages.every(page => page.confirmed), 'all_pages_must_be_confirmed_before_package');
  account.browser_qa.evidence.confirmed_pages = 2;
  return day;
}
async function ensurePackage(day) {
  await checkpoint('create_or_resume_saved_package');
  if (day.active_job?.kind === 'package') day = await waitPackageJob(day.active_job.id);
  else if (day.active_job) day = await waitDay(value => !value.active_job, 'resume_package_job');
  let retry = false;
  let diagnostic = false;
  if (day.last_error && day.units.length === 0) {
    const retried = account.package_retry_day_ids ?? [];
    check(day.stage === 'review' && day.pages.length === 2 && day.pages.every(page => page.confirmed), 'package_retry_cannot_repeat_or_skip_page_review');
    const consumed = await usage();
    check(consumed.records.some(record => record.function === 'package' && record.status.startsWith('failed')), 'failed_package_reservation_missing_from_ledger');
    if (flags.has('--retry-failed-package') && !retried.includes(day.id)) {
      account.package_retry_day_ids = [...retried, day.id];
      await checkpoint('one_explicit_package_retry');
    } else {
      // A separately requested diagnosis after a server correction must never
      // erase the first failed attempt or its already consumed retry marker.
      const attempts = account.package_diagnostic_attempts ?? [];
      check(flags.has('--diagnose-package-once') && retried.includes(day.id) && attempts.length === 0, 'saved_package_failed_no_further_authorized_retry');
      const health = await jsonGet(child, '/health');
      account.package_diagnostic_attempts = [{day_id: day.id, source_commit: health.source_commit}];
      diagnostic = true;
      await checkpoint('one_explicit_package_diagnosis');
    }
    retry = true;
  }
  if (day.units.length === 0) {
    const queued = await tapResponse(childPage, button(childPage, 'Jetzt lernen'), '/school-days/' + day.id + '/package', 'POST', 202);
    check(queued.id, 'package_job_identifier_missing');
    if (retry) {
      account.browser_qa.package_retry_job_id = queued.id;
      await checkpoint(diagnostic ? 'explicit_package_diagnosis_accepted' : 'explicit_package_retry_accepted');
    }
    day = await waitPackageJob(queued.id);
    // Keep the IDs before navigation assertions, so an interrupted browser can
    // resume this exact package instead of creating another family or package.
    account.package_unit_id = day.units[0].id;
    await checkpoint('actual_package_saved');
    await childPage.waitForURL(base + '/unit/' + account.package_unit_id, {timeout: 45000});
  }
  check(day.units.length === 1, 'two_same_subject_pages_should_form_one_package_unit');
  account.package_unit_id ??= day.units[0].id;
  check(account.package_unit_id === day.units[0].id && day.units[0].synthetic === false && day.units[0].provider === 'openrouter', 'saved_package_identity_or_real_provider_mismatch');
  await checkpoint('saved_package_identity_checked');
  return day;
}
async function waitPackageJob(jobId) {
  for (let poll = 0; poll < 100; poll++) {
    const job = await jsonGet(child, '/jobs/' + jobId);
    if (job.status === 'failed') throw new QaFailure('saved_package_job_failed_no_further_retry');
    if (job.status === 'completed') {
      const day = await dayState();
      check(day.stage === 'ready' && day.units.length > 0, 'finished_package_job_has_no_saved_unit');
      return day;
    }
    check(['queued', 'running'].includes(job.status), 'unexpected_package_job_status');
    await childPage.waitForTimeout(2000);
  }
  throw new QaFailure('package_bounded_wait_expired');
}
async function waitCoaching(unitId, page) {
  for (let poll = 0; poll < 100; poll++) {
    const unit = await jsonGet(child, '/units/' + unitId);
    if (unit.coaching?.status === 'ready') return unit;
    if (['blocked', 'failed'].includes(unit.coaching?.status)) {
      const retried = account.coaching_retry_unit_ids ?? [];
      if (flags.has('--retry-failed-coaching') && unit.coaching.can_retry && !retried.includes(unitId)) {
        // Mark before touching the button: interruption can never authorize an
        // unintended second retry. Failed and unknown-cost calls stay counted.
        account.coaching_retry_unit_ids = [...retried, unitId];
        await checkpoint('one_explicit_coaching_retry');
        await tapResponse(page, button(page, 'Noch einmal versuchen'), '/units/' + unitId + '/coaching', 'POST', 200);
        continue;
      }
      throw new QaFailure('saved_coaching_failed_no_automatic_retry');
    }
    await page.waitForTimeout(2000);
  }
  throw new QaFailure('coaching_bounded_wait_expired');
}
async function proveSavedResume(day) {
  // Settle an already started review on interrupted runs before comparing usage;
  // its existing worker may finish, but reload itself must reserve nothing.
  let current = await jsonGet(child, '/units/' + account.package_unit_id);
  for (let depth = 0; depth < 3 && current.status === 'completed'; depth++) {
    if (current.coaching?.status === 'pending') {
      await open(childPage, '/unit/' + current.id);
      current = await waitCoaching(current.id, childPage);
    }
    if (!current.coaching?.next_unit_id) break;
    current = await jsonGet(child, '/units/' + current.coaching.next_unit_id);
  }
  const before = await usage();
  const requestCount = aiMutationRequests;
  const wizard = '/after-school/' + account.child_id + '?day=' + account.school_day_id;
  await open(childPage, wizard);
  await childPage.reload({waitUntil: 'domcontentloaded', timeout: 90000});
  await accessible(childPage);
  const stored = await dayState();
  check(stored.units.length === day.units.length && stored.units[0].id === account.package_unit_id && stored.package_version === day.package_version, 'reload_created_another_package_version');
  if (stored.units[0].status !== 'completed') {
    await tapResponse(childPage, button(childPage, 'Jetzt lernen'), '/units/' + account.package_unit_id + '/start', 'POST', 200);
    await childPage.waitForURL(base + '/unit/' + account.package_unit_id, {timeout: 30000});
  } else {
    await open(childPage, '/unit/' + account.package_unit_id);
  }
  const after = await usage();
  check(before.calls_used === after.calls_used && before.records.length === after.records.length && before.encumbered_micros_usd === after.encumbered_micros_usd && aiMutationRequests === requestCount, 'resume_reserved_an_additional_ai_call');
  account.browser_qa.evidence.saved_package_resume_without_ai = true;
  await checkpoint('reload_and_second_start_used_saved_package');
}
function questionClosed(question) {
  return question.attempts.length >= 3 || question.attempts.some(attempt => ['correct', 'uncertain'].includes(attempt.outcome));
}
function escaped(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
async function fillAnswer(page, question) {
  if (question.type === 'choice') {
    const option = page.getByRole('button', {name: new RegExp('^' + escaped(question.answer) + '(?:\\s+' + escaped(question.answer) + ')?$')});
    await tap(page, option);
  } else if (['gap', 'short'].includes(question.type)) {
    await typeField(page, page.getByRole('textbox', {name: 'Deine Antwort', exact: true}), question.answer);
  } else if (question.type === 'match') {
    for (const pair of question.options) {
      const [left, right] = pair.split('|');
      check(left && right, 'invalid_authoritative_matching_pair');
      const dropdown = page.getByRole('combobox', {name: left}).or(button(page, left)).or(page.getByLabel(left, {exact: true})).first();
      await tap(page, dropdown);
      const option = page.getByRole('menuitem', {name: right, exact: true}).or(page.getByRole('option', {name: right, exact: true})).or(page.getByLabel(right, {exact: true})).last();
      await tap(page, option, {modal: true});
    }
  } else throw new QaFailure('unsupported_structured_task_type');
}
async function finishRound(unit, round) {
  if (unit.status === 'completed') return;
  if (unit.status !== 'active') {
    await tapResponse(childPage, button(childPage, unit.status === 'paused' ? 'Lernen fortsetzen' : 'Einheit starten'), '/units/' + unit.id + '/start', 'POST', 200);
  }
  if (!unit.introduction_seen) {
    await tapResponse(childPage, button(childPage, 'Weiter zu den Übungen'), '/units/' + unit.id + '/introduction', 'POST', 200);
  }
  for (const [index, question] of unit.questions.entries()) {
    if (questionClosed(question)) continue;
    await checkpoint('round_' + round + '_question_' + (index + 1));
    await reveal(childPage, childPage.getByText(question.prompt, {exact: true}));
    if (round === 1 && index === 0 && question.hints_used === 0) {
      await tap(childPage, button(childPage, 'Erklärung'));
      await reveal(childPage, childPage.getByText('Kurz erklärt', {exact: true}), {modal: true});
      if (unit.questions[index + 1]) check(!await childPage.getByText(unit.questions[index + 1].prompt, {exact: true}).isVisible(), 'explanation_advanced_to_next_question');
      await tap(childPage, button(childPage, 'Weiter üben'), {modal: true});
      const hint = await tapResponse(childPage, button(childPage, 'Ein Hinweis bitte'), '/units/' + unit.id + '/questions/' + question.id + '/hint', 'POST', 200);
      check(typeof hint.hint === 'string' && hint.hint.length > 0, 'actual_saved_hint_missing');
      account.browser_qa.evidence.used_hint = true;
    }
    await fillAnswer(childPage, question);
    const result = await tapResponse(childPage, button(childPage, 'Antwort prüfen'), '/units/' + unit.id + '/questions/' + question.id + '/answer', 'POST', 200);
    check(result.outcome === 'correct', 'authoritative_test_answer_was_not_correct');
    await reveal(childPage, childPage.getByText('Richtig!', {exact: true}));
    if (result.explanation?.trim()) check(await childPage.getByText(result.explanation, {exact: true}).count() > 0, 'saved_educational_feedback_not_rendered');
    const nextQuestion = unit.questions.slice(index + 1).find(value => !questionClosed(value));
    if (nextQuestion) check(!await childPage.getByText(nextQuestion.prompt, {exact: true}).isVisible(), 'feedback_skipped_continue_and_exposed_next_question');
    if (round === 1 && index === 0) await screenshot(childPage, 'school-day-child-feedback-mobile.png');
    const forward = result.unit.status === 'completed' ? 'Zum Rückblick' : 'Weiter';
    await tap(childPage, button(childPage, forward));
    account.browser_qa.evidence.feedback_steps = (account.browser_qa.evidence.feedback_steps ?? 0) + 1;
  }
  await reveal(childPage, childPage.getByText('Runde geschafft!', {exact: true}));
}
async function exerciseThreeRounds() {
  const units = [];
  let currentId = account.package_unit_id;
  let previous;
  for (let round = 1; round <= 3; round++) {
    await checkpoint('learning_round_' + round);
    const authoritative = await jsonGet(parent, '/units/' + currentId);
    check(authoritative.synthetic === false && authoritative.provider === 'openrouter' && authoritative.model?.endsWith(':free'), 'learning_round_not_using_the_actual_free_provider');
    check(authoritative.questions.length === 2, 'unexpected_task_count_in_bounded_round');
    if (previous) {
      check(authoritative.followup_of === previous.id && authoritative.learning_root_id === account.package_unit_id, 'followup_lost_learning_chain');
      check(JSON.stringify([...authoritative.source_material_ids].sort()) === JSON.stringify([...previous.source_material_ids].sort()), 'followup_lost_confirmed_sources');
      if (authoritative.status !== 'completed') {
        await open(childPage, '/unit/' + previous.id);
        await tapResponse(childPage, button(childPage, previous.coaching.decision === 'check' ? 'Selbst ausprobieren' : 'Weiter üben'), '/units/' + currentId + '/start', 'POST', 200);
        await childPage.waitForURL(base + '/unit/' + currentId, {timeout: 30000});
        authoritative.status = 'active';
      } else await open(childPage, '/unit/' + currentId);
    } else await open(childPage, '/unit/' + currentId);
    await finishRound(authoritative, round);
    let reviewed = await waitCoaching(currentId, childPage);
    check(reviewed.coaching.provider === 'openrouter' && reviewed.coaching.model === authoritative.model, 'coaching_silently_changed_provider_or_model');
    check(reviewed.learning_progress.secure_observation === false && reviewed.learning_progress.required_check_days === 3, 'single_day_invented_secure_mastery');
    check(reviewed.learning_progress.learning_goals.length >= 2, 'separate_confirmed_source_goals_missing');
    check(reviewed.learning_progress.learning_goals.every(goal => goal.successful_check_days <= 1 && goal.successful_check_dates.every(date => date === account.browser_qa.day_date)), 'review_invented_later_check_days');
    const saved = await jsonGet(parent, '/units/' + currentId);
    check(saved.status === 'completed' && saved.coaching.status === 'ready', 'parent_cannot_read_saved_completion_and_review');
    check(saved.questions.every(question => question.attempts.length === 1 && question.attempts[0].outcome === 'correct'), 'saved_answers_missing_or_duplicated');
    if (round === 1) {
      check(saved.questions[0].hints_used >= 1 && saved.questions[0].attempts[0].assisted === true, 'parent_cannot_read_actual_hint_assistance');
      check(reviewed.coaching.decision === 'repair', 'assisted_first_round_requires_targeted_repair');
    }
    if (round === 2) check(reviewed.coaching.decision === 'check', 'independent_repair_requires_fresh_check');
    units.push(saved);
    previous = reviewed;
    account.last_completed_unit_id = currentId;
    account.browser_qa.completed_unit_ids = units.map(unit => unit.id);
    await checkpoint('saved_round_' + round + '_with_actual_ai_report');
    if (round < 3) {
      check(reviewed.coaching.next_unit_id, 'required_followup_was_not_created');
      currentId = reviewed.coaching.next_unit_id;
    } else {
      check(reviewed.coaching.next_unit_id === null && ['spaced', 'pause'].includes(reviewed.coaching.decision), 'three_round_limit_not_respected');
    }
  }
  const prompts = units.flatMap(unit => unit.questions.map(question => question.prompt.normalize('NFKC').trim().toLowerCase()));
  check(new Set(prompts).size === prompts.length, 'followup_repeated_old_question_prompts');
  return units;
}
async function checkParentAndUsage(units) {
  await checkpoint('parent_reads_saved_answers_hints_and_reviews');
  const page = await parent.newPage();
  await open(page, '/child/' + account.child_id);
  const history = page.getByLabel('Lernverlauf', {exact: true}).or(button(page, 'Lernverlauf')).first();
  await tap(page, history);
  const overview = await jsonGet(parent, '/children/' + account.child_id + '/overview');
  const answerCount = units.reduce((sum, unit) => sum + unit.questions.reduce((total, question) => total + question.attempts.length, 0), 0);
  check(overview.day_summary.answer_count === answerCount && overview.day_summary.hints_used >= 1, 'parent_activity_summary_not_based_on_saved_facts');
  await screenshot(page, 'school-day-parent-history.png');
  for (const unit of units) {
    await open(page, '/unit/' + unit.id);
    await reveal(page, page.getByText('Deine Lernbegleitung', {exact: true}));
    await reveal(page, page.getByText(unit.coaching.report.summary, {exact: true}));
    if (unit.id === units.at(-1).id) await page.screenshot({path: path.join(artifacts, 'school-day-parent.png')});
    for (const question of unit.questions) {
      await reveal(page, page.getByText(question.prompt, {exact: true}));
      for (const answer of question.attempts) {
        await reveal(page, page.getByText('Antwort: ' + answer.answer, {exact: false}));
      }
      if (question.hints_used > 0) {
        await reveal(page, page.getByText(question.hints_used + ' Hinweise genutzt. Verfügbare Hinweise:', {exact: true}));
        check(question.hints?.length > 0, 'parent_saved_hint_text_missing');
        await reveal(page, page.getByText('• ' + question.hints[0], {exact: true}));
        await page.screenshot({path: path.join(artifacts, 'school-day-parent-assistance.png')});
      }
    }
  }
  const consumed = await usage();
  const retries = account.coaching_retry_unit_ids ?? [];
  const packageRetries = account.package_retry_day_ids ?? [];
  const diagnostics = account.package_diagnostic_attempts ?? [];
  check(new Set(retries).size === retries.length && retries.length <= 3, 'explicit_retry_limit_exceeded');
  check(new Set(packageRetries).size === packageRetries.length && packageRetries.length <= 1, 'explicit_package_retry_limit_exceeded');
  check(diagnostics.length <= 1, 'explicit_diagnosis_limit_exceeded');
  check(consumed.calls_used === 3 + units.length + retries.length + packageRetries.length + diagnostics.length, 'unexpected_or_unaccounted_ai_reservations');
  check(consumed.records.length === consumed.calls_used, 'usage_ledger_does_not_match_reservations');
  check(consumed.records.every(record => record.provider === 'openrouter' && record.model === units[0].model && (record.cost_micros_usd === 0 || record.cost_micros_usd === null)), 'provider_or_cost_did_not_stay_free_or_explicitly_unknown');
  check(consumed.unknown_cost_calls === consumed.records.filter(record => record.cost_micros_usd === null).length, 'unknown_costs_were_reported_as_zero');
  return {answerCount, consumed, retryCount: retries.length, packageRetryCount: packageRetries.length};
}

try {
  check([...flags].every(flag => allowedFlags.has(flag)), 'unsupported_driver_argument');
  account = JSON.parse(await readFile(accountFile, 'utf8'));
  check(account.normal_account && account.verified && /\+schulpilot-normal-qa-[a-f0-9]{12}@(?:gmail|googlemail)\.com$/i.test(account.credentials?.parent_username ?? ''), 'prepare_or_resume_only_the_owned_regular_artificial_qa_family');
  check(account.child_id && account.user?.families?.length === 1 && account.image_paths?.length === 2, 'private_prepared_account_is_incomplete');
  for (const [index, image] of account.image_paths.entries()) {
    const actual = await realpath(image);
    check(path.dirname(actual) === artifacts.replace(/\/$/, '') && path.basename(actual) === 'normal-school-page-' + (index + 1) + '.jpg', 'only_prepared_artificial_images_are_allowed');
  }
  await checkpoint('starting_mobile_child_journey');
  browser = await chromium.launch({headless: true, executablePath: process.env.CHROME_PATH || '/opt/google/chrome/chrome', args: ['--no-sandbox']});
  child = await browser.newContext({viewport: {width: 390, height: 844}, isMobile: true, hasTouch: true});
  parent = await browser.newContext({viewport: {width: 1440, height: 1000}});
  for (const context of [child, parent]) context.on('page', page => page.on('pageerror', error => errors.push(error.message)));
  childPage = await child.newPage();
  childPage.on('request', request => {
    if (request.method() === 'POST' && /\/(?:extract|package|coaching)$/.test(new URL(request.url()).pathname)) aiMutationRequests++;
  });
  const parentLogin = await parent.request.post(base + '/api/auth/login', {headers, data: {username: account.credentials.parent_username, password: account.credentials.parent_password}});
  check(parentLogin.status() === 200, 'prepared_parent_login_failed');
  const parentIdentity = (await parentLogin.json()).user;
  check(parentIdentity?.role === 'parent' && parentIdentity.id === account.user.id, 'parent_identity_mismatch');
  await loginChild();
  let day = await enterWizard();
  account.browser_qa.day_date ??= day.date;
  check(day.date === account.browser_qa.day_date, 'test_day_changed_without_explicit_replanning');
  day = await uploadAndConfirm(day);
  day = await ensurePackage(day);
  await proveSavedResume(day);
  const units = await exerciseThreeRounds();
  await checkpoint('child_saved_review_and_details');
  await tap(childPage, childPage.getByText('Mein Rückblick', {exact: true}));
  check(await childPage.getByText(units.at(-1).coaching.report.summary, {exact: true}).count() > 0, 'child_cannot_open_saved_review_details');
  await screenshot(childPage, 'coaching-child-mobile.png');
  const before = await usage();
  await open(childPage, '/unit/' + account.last_completed_unit_id);
  await reveal(childPage, childPage.getByText('Runde geschafft!', {exact: true}));
  const resumed = await jsonGet(child, '/units/' + account.last_completed_unit_id);
  check(resumed.coaching.status === 'ready', 'completed_coaching_was_not_persistent');
  const after = await usage();
  check(before.calls_used === after.calls_used && before.records.length === after.records.length, 'reopening_saved_review_reserved_another_ai_call');
  const {answerCount, consumed, retryCount, packageRetryCount} = await checkParentAndUsage(units);
  check(errors.length === 0, 'browser_runtime_errors_detected');
  account.browser_qa.evidence.completed = true;
  await checkpoint('passed');
  passed = true;
  console.log(JSON.stringify({regular_parent_and_child: true, synthetic_demo_used: false, normal_photo_uploads: 2, mobile_viewport: 390, learning_rounds: units.length, completed_questions: answerCount, actual_free_ai_calls: consumed.calls_used, known_cost_micros_usd: consumed.known_cost_micros_usd, unknown_cost_calls: consumed.unknown_cost_calls, explicit_coaching_retries: retryCount, explicit_package_retries: packageRetryCount, saved_package_resume_without_ai: true, feedback_waited_for_continue: true, parent_sees_saved_answers_hints_and_reviews: true, runtime_errors: errors}));
} catch (error) {
  process.exitCode = 1;
  // Playwright's detailed errors may quote the selected answer or typed value.
  // Only our fixed failure codes leave this process; the own-family screenshot
  // supports visual debugging without logging credentials or child responses.
  console.error(JSON.stringify({qa_passed: false, stopped_at: phase, reason: error instanceof QaFailure ? error.message : 'browser_or_io_operation_failed', private_account_kept_for_resume: Boolean(account)}));
} finally {
  if (!passed && childPage) await childPage.screenshot({path: path.join(artifacts, 'school-day-browser-debug.png')}).catch(() => {});
  if (!passed && parent && account?.user?.families?.length === 1) {
    const consumed = await usage().catch(() => null);
    if (consumed) console.log(JSON.stringify({failed_run_usage: {calls_used: consumed.calls_used, known_cost_micros_usd: consumed.known_cost_micros_usd, unknown_cost_calls: consumed.unknown_cost_calls, explicit_package_retries: (account.package_retry_day_ids ?? []).length, explicit_coaching_retries: (account.coaching_retry_unit_ids ?? []).length}}));
  }
  if (passed && !flags.has('--keep-for-native')) {
    try {
      const deleted = await parent.request.delete(base + '/api/account', {headers, data: {password: account.credentials.parent_password}});
      check(deleted.status() === 200, 'owned_qa_family_cleanup_failed');
      await unlink(accountFile);
      console.log(JSON.stringify({own_regular_qa_family_deleted: true}));
    } catch {
      process.exitCode = 1;
      console.error(JSON.stringify({qa_cleanup_failed: true, private_account_kept_for_resume: true}));
    }
  }
  if (browser) await browser.close().catch(() => {});
}
