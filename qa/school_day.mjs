// Real browser check of the exact package made by public_school_day_smoke.py.
// That preceding script performs the three actual, free, fixed-fixture AI calls.
import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {readFile, unlink} from 'node:fs/promises';

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
try {
  await login(child, 'child');
  await login(parent, 'parent');
  const c = await child.newPage();
  await open(c, '/app');
  await c.getByRole('button', {name: 'Nach der Schule starten', exact: true}).click();
  await c.getByText('Dein Lernpaket ist bereit', {exact: true}).waitFor();
  await c.getByText(/2 Heftseite(n)/).waitFor();
  await c.screenshot({path: '../artifacts/school-day-child-desktop.png'});
  // Direct links, fresh Flutter process, same saved day: no second package.
  await open(c, '/after-school/' + demo.child_id);
  await c.getByText('Dein Lernpaket ist bereit', {exact: true}).waitFor();
  await c.setViewportSize({width: 390, height: 844});
  await c.screenshot({path: '../artifacts/school-day-child-mobile.png'});
  const unitResponse = await parent.request.get(url + '/api/units/' + demo.package_unit_id);
  assert.equal(unitResponse.status(), 200);
  const unit = await unitResponse.json();
  await c.getByRole('button', {name: 'Jetzt lernen & festigen', exact: true}).click();
  await c.getByRole('button', {name: 'Ein Hinweis bitte', exact: true}).waitFor();
  await c.getByRole('button', {name: 'Ein Hinweis bitte', exact: true}).click();
  const q = unit.questions[0];
  if (q.type === 'choice') await c.getByRole('button', {name: q.answer, exact: true}).click();
  if (q.type === 'gap' || q.type === 'short') {
    await c.getByRole('textbox', {name: q.type === 'gap' ? 'Deine Ergänzung' : 'Deine kurze Antwort', exact: true}).click();
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
  const p = await parent.newPage();
  await open(p, '/child/' + demo.child_id);
  await p.getByRole('button', {name: 'Heutiges Tagespaket ansehen', exact: true}).click();
  await p.getByText('Dein Lernpaket ist bereit', {exact: true}).waitFor();
  const day = await (await parent.request.get(url + '/api/school-days/' + demo.school_day_id)).json();
  assert.equal(day.units[0].questions[0].attempts[0].assisted, true);
  assert.equal(day.units[0].questions[0].attempts[0].outcome, 'correct');
  assert.equal(day.pages.length, 2);
  await p.screenshot({path: '../artifacts/school-day-parent.png'});
  assert.deepEqual(errors, []);
  passed = true;
  console.log(JSON.stringify({checks: ['child_wizard_entry', 'persisted_multi_page_package', 'direct_link_resume_without_duplicate_job', 'mobile_390px', 'real_interactive_hint_and_answer', 'parent_package_and_saved_assistance'], runtime_errors: errors}));
} finally {
  if (passed) {
    const deleted = await parent.request.delete(url + '/api/account', {headers, data: {password: demo.credentials.parent_password}});
    assert.equal(deleted.status(), 200);
    await unlink(accountFile);
  }
  await browser.close();
}
