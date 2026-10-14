// Real browser check: a prepared regular family exercises the entire photo
// wizard; a fixed-fixture family can also resume its already generated package.
import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {readFile, unlink, writeFile} from 'node:fs/promises';

const url = 'https://schulpilot.dorfspy.de';
const accountFile = '../artifacts/.school-day-qa-account.json';
const demo = JSON.parse(await readFile(accountFile, 'utf8'));
const browser = await chromium.launch({headless: true, executablePath: process.env.CHROME_PATH || '/opt/google/chrome/chrome', args: ['--no-sandbox']});
const child = await browser.newContext({viewport: {width: 1280, height: 1000}});
const parent = await browser.newContext({viewport: {width: 1440, height: 1000}});
const errors = [];
const headers = {'X-Schulpilot-Request': '1'};
let passed = false;
for (const context of [child, parent]) context.on('page', page => page.on('pageerror', e => errors.push(e.message)));
async function open(page, path) {
  await page.goto(url + path, {waitUntil: 'domcontentloaded'});
  await page.waitForSelector('flutter-view');
  await page.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(n => n.click()));
  await page.waitForTimeout(350);
}
async function login(context, role) {
  const r = await context.request.post(url + '/api/auth/login', {headers, data: {username: demo.credentials[role + '_username'], password: demo.credentials[role + '_password']}});
  assert.equal(r.status(), 200);
}
async function reveal(page, locator) {
  const target = locator.first();
  for (let i = 0; i < 10; i++) {
    const box = await target.count() ? await target.boundingBox({timeout: 500}).catch(() => null) : null;
    const viewport = page.viewportSize();
    if (box && box.y >= 0 && box.y + box.height <= viewport.height) return target;
    await page.mouse.move(viewport.width - 60, viewport.height - 120);
    await page.mouse.wheel(0, box && box.y < 0 ? -550 : 550);
    await page.waitForTimeout(300);
  }
  throw new Error('Expected wizard control was not visible after scrolling');
}
async function tapDialogControl(page, locator) {
  // Flutter's modal semantics barrier overlaps descendant DOM nodes. Send a
  // physical pointer at the rendered button, as a user does; no DOM dispatch
  // or application-state bypass. Later API assertions still verify the action.
  const box = await locator.boundingBox();
  assert(box && box.width > 0 && box.height > 0);
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
}
async function waitForCoaching(unitId) {
  for (let poll = 0; poll < 75; poll++) {
    const response = await child.request.get(url + '/api/units/' + unitId);
    assert.equal(response.status(), 200);
    const value = await response.json();
    if (value.coaching?.status === 'ready') return value;
    if (['blocked', 'failed'].includes(value.coaching?.status)) {
      throw new Error('Saved AI review was rejected: ' + value.coaching.reason);
    }
    await new Promise(resolve => setTimeout(resolve, 2000));
  }
  throw new Error('Saved AI review did not finish within the bounded wait');
}
async function answerSavedQuestions(page, questions) {
  for (const q of questions.filter(q => !q.attempts.some(a => a.outcome === 'correct' || a.outcome === 'uncertain'))) {
    const submit = page.getByRole('button', {name: 'Antwort prüfen', exact: true});
    await reveal(page, submit);
    if (q.type === 'choice') await page.getByRole('button', {name: q.answer}).first().click();
    if (q.type === 'gap' || q.type === 'short') {
      const input = page.getByRole('textbox', {name: q.type === 'gap' ? 'Deine Ergänzung' : 'Deine kurze Antwort', exact: false});
      await reveal(page, input);
      await input.click();
      await page.keyboard.type(q.answer, {delay: 20});
    }
    const saved = page.waitForResponse(r => r.url().endsWith('/questions/' + q.id + '/answer') && r.request().method() === 'POST');
    await reveal(page, submit);
    await submit.click();
    assert.equal((await (await saved).json()).outcome, 'correct');
    await page.waitForTimeout(500);
  }
}
try {
  await login(child, 'child');
  await login(parent, 'parent');
  const c = await child.newPage();
  const startButton = () => c.getByRole('button', {name: /Jetzt lernen & festigen|Weiterlernen/});
  await open(c, '/app');
  await c.getByRole('button', {name: 'Nach der Schule starten', exact: true}).click();
  if (demo.normal_account && !demo.package_unit_id) {
    const today = async () => {
      const response = await child.request.get(url + '/api/children/' + demo.child_id + '/school-day/today');
      assert.equal(response.status(), 200);
      return (await response.json()).day;
    };
    await c.getByText('Alles von heute einsammeln', {exact: true}).waitFor();
    let day = await today();
    assert.equal(day.synthetic, false);
    if (day.pages.length === 0) {
      const select = c.getByRole('button', {name: 'Mehrere Fotos auswählen', exact: true});
      await reveal(c, select);
      const picker = c.waitForEvent('filechooser');
      await select.click();
      await (await picker).setFiles(demo.image_paths);
      for (let index = 0; index < 2; index++) {
        const crop = c.getByRole('button', {name: 'Zuschnitt übernehmen', exact: true});
        await crop.waitFor({timeout: 30000});
        await tapDialogControl(c, crop);
        await c.waitForTimeout(800);
      }
    }
    const next = c.getByRole('button', {name: 'Alle Seiten sind da · Weiter', exact: true});
    await reveal(c, next);
    await next.click();
    const recognize = c.getByRole('button', {name: 'Heftseiten mit KI erkennen', exact: true});
    await reveal(c, recognize);
    await recognize.click();
    let recognized = false;
    for (let poll = 0; poll < 75; poll++) {
      day = await today();
      if (day.last_error) throw new Error('Normal OCR job failed; it was not retried');
      if (day.pages.length === 2 && day.pages.every(page => page.status === 'review')) { recognized = true; break; }
      await c.waitForTimeout(2000);
    }
    assert(recognized, 'Both normal OCR jobs must finish');
    const confirm = c.getByRole('button', {name: 'Stoff bestätigen', exact: true});
    for (let index = 0; index < 2; index++) {
      const consent = c.getByRole('checkbox', {name: /Ich habe den Stoff geprüft/});
      await reveal(c, consent);
      if (await consent.getAttribute('aria-checked') !== 'true') await consent.click();
      await reveal(c, confirm);
      const saved = c.waitForResponse(r => r.url().endsWith('/confirm') && r.request().method() === 'PUT');
      await confirm.click();
      assert.equal((await saved).status(), 200);
      await c.waitForTimeout(500);
    }
    const create = c.getByRole('button', {name: 'Lernpaket für heute erstellen', exact: true});
    await reveal(c, create);
    await create.click();
    await c.getByText('Dein Lernpaket ist bereit', {exact: true}).waitFor({timeout: 150000});
    day = await today();
    assert.equal(day.synthetic, false);
    assert.equal(day.pages.length, 2);
    assert(day.pages.every(page => page.synthetic === false && page.confirmed && page.extraction_provider === 'openrouter'));
    const content = day.pages.map(page => page.content).join(' ');
    assert(/3\s*\/\s*9|\\frac\s*\{3\}\s*\{9\}/.test(content), 'Normal OCR must preserve our original non-fixture example');
    assert.equal(day.units.length, 1);
    assert.equal(day.units[0].synthetic, false);
    demo.school_day_id = day.id;
    demo.package_unit_id = day.units[0].id;
    await writeFile(accountFile, JSON.stringify(demo), {mode: 0o600});
    console.log('regular child photo selection, cropping, two OCR calls, confirmations and AI package passed');
  }
  await c.getByText('Dein Lernpaket ist bereit', {exact: true}).waitFor();
  await reveal(c, startButton());
  await c.screenshot({path: '../artifacts/school-day-child-desktop.png'});
  // Direct links, fresh Flutter process, same saved day: no second package.
  await open(c, '/after-school/' + demo.child_id);
  await c.getByText('Dein Lernpaket ist bereit', {exact: true}).waitFor();
  await c.setViewportSize({width: 390, height: 844});
  await reveal(c, startButton());
  await c.screenshot({path: '../artifacts/school-day-child-mobile.png'});
  const unitResponse = await parent.request.get(url + '/api/units/' + demo.package_unit_id);
  assert.equal(unitResponse.status(), 200);
  const unit = await unitResponse.json();
  await startButton().click();
  if (!unit.introduction_seen) {
    const intro = c.getByRole('button', {name: 'Weiter zu den Übungen', exact: true});
    await reveal(c, intro);
    await intro.click();
  }
  await reveal(c, c.getByRole('button', {name: 'Ein Hinweis bitte', exact: true}));
  await c.getByRole('button', {name: 'Ein Hinweis bitte', exact: true}).click();
  const pending = unit.questions.filter(q => !q.attempts.some(a => a.outcome === 'correct' || a.outcome === 'uncertain'));
  assert(pending.length, 'An unanswered question must remain in this isolated test package');
  for (const q of demo.normal_account ? pending : pending.slice(0, 1)) {
    await c.getByRole('button', {name: 'Antwort prüfen', exact: true}).waitFor();
    if (q.type === 'choice') await c.getByRole('button', {name: q.answer}).first().click();
    if (q.type === 'gap' || q.type === 'short') {
      await c.getByRole('textbox', {name: q.type === 'gap' ? 'Deine Ergänzung' : 'Deine kurze Antwort', exact: false}).click();
      await c.keyboard.type(q.answer, {delay: 30});
    }
    if (q.type === 'match') {
      for (const pair of q.options) {
        const [left, right] = pair.split('|');
        await c.getByRole('button', {name: left}).or(c.getByRole('combobox', {name: left})).or(c.getByLabel(left)).first().click();
        await c.getByText(right, {exact: true}).or(c.getByLabel(right, {exact: true})).last().click();
      }
    }
    const saved = c.waitForResponse(r => r.url().endsWith('/questions/' + q.id + '/answer') && r.request().method() === 'POST');
    await c.getByRole('button', {name: 'Antwort prüfen', exact: true}).click();
    assert.equal((await (await saved).json()).outcome, 'correct');
    await c.waitForTimeout(500);
  }
  let learningRounds = 1;
  if (demo.normal_account) {
    let reviewed = await waitForCoaching(demo.package_unit_id);
    assert.equal(reviewed.coaching.decision, 'repair');
    assert.equal(reviewed.coaching.provider, 'openrouter');
    assert(reviewed.coaching.report.learning_goals.length >= 2);
    assert.equal(reviewed.learning_progress.secure_observation, false);
    console.log('Actual answer review and separately sourced learning goals passed');
    for (let round = 0; round < 2 && reviewed.coaching.next_unit_id; round++) {
      const nextId = reviewed.coaching.next_unit_id;
      const next = await (await parent.request.get(url + '/api/units/' + nextId)).json();
      assert.equal(next.followup_of, reviewed.id);
      assert.equal(next.learning_root_id, demo.package_unit_id);
      assert.deepEqual([...next.source_material_ids].sort(), [...reviewed.source_material_ids].sort());
      const continueButton = c.getByRole('button', {name: reviewed.coaching.decision === 'check' ? 'Jetzt selbstständig ausprobieren' : 'Mit passenden Übungen weiterlernen', exact: true});
      await reveal(c, continueButton);
      await continueButton.click();
      await c.waitForURL(url + '/unit/' + nextId);
      if (!next.introduction_seen) {
        const intro = c.getByRole('button', {name: 'Weiter zu den Übungen', exact: true});
        await reveal(c, intro);
        await intro.click();
      }
      await answerSavedQuestions(c, next.questions);
      reviewed = await waitForCoaching(nextId);
      assert.equal(reviewed.coaching.provider, 'openrouter');
      learningRounds++;
      console.log(JSON.stringify({completed_learning_rounds: learningRounds, next_action: reviewed.coaching.decision}));
    }
    assert.equal(learningRounds, 3);
    assert.equal(reviewed.coaching.next_unit_id, null);
    assert(['spaced', 'pause'].includes(reviewed.coaching.decision));
    assert.equal(reviewed.learning_progress.secure_observation, false);
    assert(reviewed.learning_progress.learning_goals.every(g => g.successful_check_days <= 1));
    demo.last_completed_unit_id = reviewed.id;
    await writeFile(accountFile, JSON.stringify(demo), {mode: 0o600});
    await reveal(c, c.getByText('Deine Lernbegleitung', {exact: true}));
    await c.screenshot({path: '../artifacts/coaching-child-mobile.png'});
    await open(c, '/unit/' + reviewed.id);
    await reveal(c, c.getByText('Deine Lernbegleitung', {exact: true}));
    const resumed = await (await child.request.get(url + '/api/units/' + reviewed.id)).json();
    assert.equal(resumed.coaching.status, 'ready');
    console.log('Repair, independent check, bounded finish and persisted review passed');
  }
  const p = await parent.newPage();
  await open(p, '/child/' + demo.child_id);
  await p.getByRole('button', {name: 'Heutiges Tagespaket ansehen', exact: true}).click();
  await p.getByText('Dein Lernpaket ist bereit', {exact: true}).waitFor();
  const day = await (await parent.request.get(url + '/api/school-days/' + demo.school_day_id)).json();
  assert.equal(day.units[0].questions[0].attempts[0].assisted, true);
  assert.equal(day.units[0].questions[0].attempts[0].outcome, 'correct');
  assert.equal(day.pages.length, 2);
  if (demo.normal_account) {
    const stored = await (await parent.request.get(url + '/api/units/' + demo.package_unit_id)).json();
    assert.equal(stored.status, 'completed');
    assert(stored.questions.every(q => q.attempts.some(a => a.outcome === 'correct')));
    const usage = await (await parent.request.get(url + '/api/families/' + demo.user.families[0].id + '/usage')).json();
    assert.equal(usage.calls_used, 3 + learningRounds);
    assert.equal(usage.unknown_cost_calls, 0);
    assert(usage.records.every(record => record.cost_micros_usd === 0));
    const finalReview = await (await parent.request.get(url + '/api/units/' + demo.last_completed_unit_id)).json();
    assert.equal(finalReview.coaching.status, 'ready');
    await open(p, '/unit/' + demo.last_completed_unit_id);
    await reveal(p, p.getByText('Deine Lernbegleitung', {exact: true}));
    console.log(JSON.stringify({regular_parent_and_child: true, synthetic_demo_used: false, normal_photo_uploads: 2, actual_free_ai_calls: usage.calls_used, cost_micros_usd: usage.known_cost_micros_usd, completed_questions: stored.questions.length + (learningRounds - 1) * 2, learning_rounds: learningRounds, parent_sees_saved_reviews: true, provider: stored.provider, model: stored.model}));
  }
  await p.screenshot({path: '../artifacts/school-day-parent.png'});
  assert.deepEqual(errors, []);
  passed = true;
  console.log(JSON.stringify({checks: ['child_wizard_entry', 'persisted_multi_page_package', 'direct_link_resume_without_duplicate_job', 'mobile_390px', 'real_interactive_hint_and_answer', 'parent_package_and_saved_assistance'], runtime_errors: errors}));
} finally {
  if (!passed) {
    const pages = child.pages();
    if (pages.length) await pages.at(-1).screenshot({path: '../artifacts/school-day-browser-debug.png'}).catch(() => {});
  }
  if (passed && !process.argv.includes('--keep-for-native')) {
    const deleted = await parent.request.delete(url + '/api/account', {headers, data: {password: demo.credentials.parent_password}});
    assert.equal(deleted.status(), 200);
    await unlink(accountFile);
  }
  await browser.close();
}
