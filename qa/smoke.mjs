// Actual public Flutter UI, with a fixed artificial family and no external AI.
import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {chmod, readFile, unlink, writeFile} from 'node:fs/promises';

const url = 'https://schulpilot.dorfspy.de';
const browser = await chromium.launch({headless: true, executablePath: process.env.CHROME_PATH || '/opt/google/chrome/chrome', timeout: 15000, args: ['--no-sandbox']});
const parent = await browser.newContext({viewport: {width: 1440, height: 1000}});
const child = await browser.newContext({viewport: {width: 390, height: 844}, isMobile: true, hasTouch: true});
const mobile = await browser.newContext({viewport: {width: 390, height: 844}, isMobile: true, hasTouch: true});
const checks = [];
const errors = [];
const headers = {'X-Schulpilot-Request': '1'};
const accountFile = '../artifacts/.qa-account.json';
let demo;
let passed = false;
try {
  demo = JSON.parse(await readFile(accountFile, 'utf8'));
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
}
function button(page, name) {
  return page.getByRole('button', {name, exact: true});
}
async function accessible(page) {
  await page.waitForSelector('flutter-view', {timeout: 90000});
  await page.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(node => node.click()));
  await page.waitForTimeout(350);
}
async function open(page, route) {
  await page.goto(url + route, {waitUntil: 'domcontentloaded', timeout: 90000});
  await accessible(page);
}
async function reveal(page, locator, {modal = false} = {}) {
  const target = locator.first();
  const viewport = page.viewportSize();
  const top = modal ? 4 : 75;
  const bottom = viewport.height - (modal ? 4 : 100);
  for (let attempt = 0; attempt < 32; attempt++) {
    const box = await target.count() ? await target.boundingBox({timeout: 500}).catch(() => null) : null;
    if (box && box.width > 0 && box.height > 0 && box.y >= top && box.y + box.height <= bottom) return target;
    await page.mouse.move(viewport.width - 28, viewport.height - 160);
    await page.mouse.wheel(0, !box && attempt === 0 ? -16000 : box && box.y < top ? -460 : 460);
    await page.waitForTimeout(250);
  }
  throw new Error('Expected browser touch control was not visible');
}
async function tap(page, locator, options) {
  const target = await reveal(page, locator, options);
  const box = await target.boundingBox();
  assert(box && box.width > 0 && box.height > 0, 'Touch control has no bounds');
  // Flutter modal semantics can overlap the DOM node; use a physical pointer,
  // without DOM event injection or calls into Flutter's application state.
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  await page.waitForTimeout(180);
}
async function typeField(page, locator, value) {
  const field = await reveal(page, locator);
  // Flutter's textarea accessibility bounds include its counter. Tap inside
  // the actual edit area, then verify the visible field accepted the keys.
  await field.click({position: {x: 20, y: 20}});
  await page.waitForTimeout(350);
  if (await field.inputValue()) {
    await page.keyboard.press('Control+A');
    await page.keyboard.press('Backspace');
  }
  await page.keyboard.type(value, {delay: 40});
  await page.waitForTimeout(200);
  assert(await field.inputValue() === value, 'The actual input did not accept the entered text');
}
async function tapResponse(page, locator, route, method, status) {
  const pending = page.waitForResponse(response => new URL(response.url()).pathname === '/api' + route && response.request().method() === method, {timeout: 45000});
  pending.catch(() => {});
  await tap(page, locator);
  const response = await pending;
  assert.equal(response.status(), status, 'Unexpected public UI response');
  return response.json();
}
async function jsonGet(context, route) {
  const response = await context.request.get(url + '/api' + route);
  assert.equal(response.status(), 200, 'Unexpected public API read');
  return response.json();
}
async function saveAccount() {
  await writeFile(accountFile, JSON.stringify(demo), {mode: 0o600});
  await chmod(accountFile, 0o600);
}
function questionClosed(question) {
  return question.attempts.length >= 3 || question.attempts.some(attempt => ['correct', 'uncertain'].includes(attempt.outcome));
}
function escaped(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
async function fillAnswer(page, question) {
  if (question.type === 'choice') {
    // Flutter combines the labelled choice and visible text in some browsers.
    const option = page.getByRole('button', {name: new RegExp('^' + escaped(question.answer) + '(?:\\s+' + escaped(question.answer) + ')?$')});
    await tap(page, option);
  } else if (['gap', 'short'].includes(question.type)) {
    await typeField(page, page.getByRole('textbox', {name: 'Deine Antwort', exact: true}), question.answer);
  } else if (question.type === 'match') {
    for (const pair of question.options) {
      const [left, right] = pair.split('|');
      assert(left && right, 'Authoritative matching pair is incomplete');
      const dropdown = page.getByRole('combobox', {name: left}).or(button(page, left)).or(page.getByLabel(left, {exact: true})).first();
      await tap(page, dropdown);
      const option = page.getByRole('menuitem', {name: right, exact: true}).or(page.getByRole('option', {name: right, exact: true})).or(page.getByLabel(right, {exact: true})).first();
      await tap(page, option, {modal: true});
    }
  } else {
    throw new Error('Unexpected structured task type');
  }
}
for (const context of [parent, child, mobile]) {
  context.on('page', page => page.on('pageerror', error => errors.push(error.message)));
}
try {
  const p = await parent.newPage();
  await open(p, '/');
  if (!demo) {
    demo = await tapResponse(p, button(p, 'Demo ausprobieren'), '/demo', 'POST', 201);
    assert(demo.token === undefined, 'Web login must use HttpOnly cookies');
    assert(demo.user.families.every(family => family.synthetic === true), 'Only the dedicated artificial demo family is allowed');
    await saveAccount();
  } else {
    assert(demo.user.families.every(family => family.synthetic === true), 'Only this artificial demo family may be resumed');
    const result = await parent.request.post(url + '/api/auth/login', {headers, data: {username: demo.credentials.parent_username, password: demo.credentials.parent_password}});
    assert.equal(result.status(), 200);
    await open(p, '/app');
  }
  await reveal(p, p.getByText('Deine Familie', {exact: true}));
  await reveal(p, button(p, 'Ansehen'));
  const cookie = (await parent.cookies()).find(value => value.name === 'sp_session');
  assert(cookie?.secure && cookie?.httpOnly && cookie.sameSite === 'Strict', 'Public session cookie must be secure');
  await p.screenshot({path: '../artifacts/public-parent.png'});
  checks.push('parent dashboard and secure cookie');
  console.log('Parent dashboard passed');
  let unitId = demo.unitId;
  if (!unitId) {
    await tap(p, button(p, 'Ansehen'));
    await tap(p, p.getByLabel('Materialien', {exact: true}));
    const material = await jsonGet(parent, '/materials/' + demo.material_id);
    await tap(p, button(p, material.confirmed ? 'Stoff ansehen' : 'Stoff & Unsicherheiten bestätigen'));
    if (!material.confirmed) {
      assert.equal(await p.getByRole('checkbox').count(), 0);
      const confirmed = await tapResponse(p, button(p, 'Stimmt, weiter'), '/materials/' + demo.material_id + '/confirm', 'PUT', 200);
      assert.equal(confirmed.confirmed, true);
      await reveal(p, p.getByText('Bestätigter Lernstoff', {exact: true}));
    }
    const queued = await tapResponse(p, button(p, 'Lerneinheit für das Kind vorbereiten'), '/children/' + demo.child_id + '/units', 'POST', 202);
    for (let poll = 0; poll < 45; poll++) {
      const job = await jsonGet(parent, '/jobs/' + queued.id);
      assert.notEqual(job.status, 'failed', 'Fixed synthetic preparation failed');
      if (job.status === 'completed') {
        unitId = job.result.unit_id;
        demo.unitId = unitId;
        await saveAccount();
        break;
      }
      await p.waitForTimeout(500);
    }
    assert(unitId, 'Unit must be generated by the actual material action');
  }
  const authoritative = await jsonGet(parent, '/units/' + unitId);
  assert.equal(authoritative.questions.length, 4);
  assert.deepEqual(new Set(authoritative.questions.map(question => question.type)), new Set(['choice', 'gap', 'match', 'short']));
  assert(authoritative.synthetic === true && authoritative.provider === 'synthetic', 'The four-widget smoke must make no external AI call');
  checks.push('material confirmation and durable unit generation through UI');
  console.log('Material confirmation and preparation passed');
  const c = await child.newPage();
  await open(c, '/login');
  await typeField(c, c.getByRole('textbox', {name: 'E-Mail oder Benutzername', exact: true}), demo.credentials.child_username);
  await typeField(c, c.getByLabel('Passwort', {exact: true}), demo.credentials.child_password);
  await tapResponse(c, button(c, 'Anmelden'), '/auth/login', 'POST', 200);
  if (authoritative.status === 'completed') {
    await open(c, '/unit/' + unitId);
  } else {
    const action = c.getByRole('button', {name: /^(Jetzt lernen|Weiterlernen|Freiwillig üben)$/});
    await tap(c, action);
    await c.waitForURL(url + '/unit/' + unitId, {timeout: 30000});
    if (!authoritative.introduction_seen) {
      await tapResponse(c, button(c, 'Weiter zu den Übungen'), '/units/' + unitId + '/introduction', 'POST', 200);
    }
    const firstOpen = authoritative.questions.find(question => !questionClosed(question));
    if (firstOpen && firstOpen.hints_used === 0) {
      const hinted = await tapResponse(c, button(c, 'Ein Hinweis bitte'), '/units/' + unitId + '/questions/' + firstOpen.id + '/hint', 'POST', 200);
      assert(typeof hinted.hint === 'string' && hinted.hint.length > 0);
    }
  }
  for (const question of authoritative.questions) {
    if (questionClosed(question)) continue;
    await reveal(c, c.getByText(question.prompt, {exact: true}));
    await fillAnswer(c, question);
    await c.screenshot({path: '../artifacts/public-task-' + question.type + '-390px.png'});
    const result = await tapResponse(c, button(c, 'Antwort prüfen'), '/units/' + unitId + '/questions/' + question.id + '/answer', 'POST', 200);
    assert.equal(result.outcome, 'correct');
    await reveal(c, c.getByText('Richtig!', {exact: true}));
    const next = result.unit.questions.find(value => !questionClosed(value));
    if (next) assert.equal(await c.getByText(next.prompt, {exact: true}).count(), 0, 'The next question must wait for Continue');
    await tap(c, button(c, result.unit.status === 'completed' ? 'Zum Rückblick' : 'Weiter'));
    console.log('Exercise and explicit feedback passed:', question.type);
  }
  await reveal(c, c.getByText('Runde geschafft!', {exact: true}));
  await c.screenshot({path: '../artifacts/public-child-completed.png'});
  checks.push('independent child login and all four real exercise widgets at 390 px');
  checks.push('explicit feedback and continue after each saved answer');
  await open(p, '/child/' + demo.child_id);
  await tap(p, p.getByLabel('Lernverlauf', {exact: true}));
  const stored = await jsonGet(parent, '/children/' + demo.child_id + '/overview');
  assert.equal(stored.day_summary.answer_count, 4);
  assert(stored.day_summary.hints_used >= 1);
  const completed = await jsonGet(parent, '/units/' + unitId);
  assert.equal(completed.status, 'completed');
  assert(completed.questions.every(question => question.attempts.some(attempt => attempt.outcome === 'correct')));
  assert(completed.questions.some(question => question.attempts.some(attempt => attempt.assisted === true)));
  await p.screenshot({path: '../artifacts/public-parent-history.png'});
  checks.push('saved answers and real assistance visible in parent history');
  const usage = await jsonGet(parent, '/families/' + demo.user.families[0].id + '/usage');
  assert.equal(usage.calls_used, 0, 'Fixed example tasks must not consume external AI');
  if (completed.coaching) assert.equal(completed.coaching.provider, 'synthetic');
  const m = await mobile.newPage();
  await open(m, '/');
  await reveal(m, button(m, 'Demo ausprobieren'));
  await m.screenshot({path: '../artifacts/public-mobile.png'});
  checks.push('mobile landing at 390 px');
  assert.deepEqual(errors, [], 'Browser runtime errors');
  passed = true;
  console.log(JSON.stringify({url, checks, external_ai_calls: 0, runtime_errors: errors}, null, 2));
} catch (error) {
  const pages = child.pages();
  if (pages.length) await pages.at(-1).screenshot({path: '../artifacts/public-smoke-debug.png'}).catch(() => {});
  throw error;
} finally {
  if (demo && passed) {
    const deleted = await parent.request.delete(url + '/api/account', {headers, data: {password: demo.credentials.parent_password}});
    assert.equal(deleted.status(), 200, 'Own artificial family cleanup failed');
    await unlink(accountFile);
    console.log('Own artificial demo family deleted');
  }
  await browser.close();
}
