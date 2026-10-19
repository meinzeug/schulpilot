// Public parent UI after native answers; only the same owned artificial family.
import assert from 'node:assert/strict';
import {readFile, writeFile, chmod} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright';

const base = 'https://schulpilot.dorfspy.de';
const artifacts = fileURLToPath(new URL('../artifacts/', import.meta.url));
const account = JSON.parse(await readFile(artifacts + '.school-day-qa-account.json', 'utf8'));
assert(account.normal_account && account.verified && account.report_qa?.phase === 'native_passed');
assert(/\+schulpilot-normal-qa-[a-f0-9]{12}@/.test(account.credentials.parent_username));
const headers = {'X-Schulpilot-Request': '1', 'X-Schulpilot-Capabilities': 'language-v1'};
const browser = await chromium.launch({headless: true, executablePath: '/opt/google/chrome/chrome', args: ['--no-sandbox']});
const context = await browser.newContext({viewport: {width: 1440, height: 1100}});
const page = await context.newPage();
const errors = [], writes = [];
page.on('pageerror', () => errors.push('javascript_error'));
page.on('request', request => {
  const path = new URL(request.url()).pathname;
  if (path.startsWith('/api/') && !['GET', 'HEAD', 'OPTIONS'].includes(request.method()) && path !== '/api/auth/login') writes.push(path);
});
async function open(route) {
  await page.goto(base + route, {waitUntil: 'domcontentloaded', timeout: 90000});
  await page.waitForSelector('flutter-view', {timeout: 90000});
  await page.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(node => node.click()));
}
async function tap(locator) {
  await locator.waitFor({state: 'visible', timeout: 15000});
  const box = await locator.boundingBox();
  assert(box?.height && box?.width);
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
}
async function get(route) {
  const response = await context.request.get(base + '/api' + route, {headers});
  assert.equal(response.status(), 200);
  return response.json();
}
async function shot(name) {
  const path = artifacts + 'report-review-parent-after-' + name + '.png';
  await page.screenshot({path});
  await chmod(path, 0o600);
}
try {
  await open('/login');
  for (const [label, key] of [['E-Mail oder Benutzername', 'parent_username'], ['Passwort', 'parent_password']]) {
    const input = page.getByRole('textbox', {name: label, exact: true});
    // Flutter's password field exposes a label instead of the textbox role.
    const field = label === 'Passwort' ? page.getByLabel(label, {exact: true}) : input;
    await tap(field);
    await page.keyboard.type(account.credentials[key], {delay: 8});
    await page.keyboard.press('Tab');
  }
  await tap(page.getByRole('button', {name: 'Anmelden', exact: true}));
  await page.waitForURL(base + '/app');
  const child = account.child_id, unitId = account.report_qa.unit_id;
  const before = await get('/children/' + child + '/overview?compact=true');
  const unit = await get('/units/' + unitId);
  const attempts = unit.questions.flatMap(question => question.attempts);
  assert.equal(unit.status, 'completed');
  assert.deepEqual(attempts.map(a => a.id).sort(), [...account.report_qa.native_answer_ids].sort());
  assert(attempts.every(a => a.outcome === 'correct' && !a.assisted));
  await open('/child/' + child);
  await page.getByText('Das gelang', {exact: true}).waitFor();
  await shot('desktop');
  await open('/unit/' + unitId);
  await page.getByText('Einblick in die Lerneinheit', {exact: true}).waitFor();
  for (const question of unit.questions) await page.getByText(question.prompt, {exact: true}).waitFor({state: 'attached'});
  await shot('audit');
  await page.setViewportSize({width: 390, height: 1000});
  await open('/child/' + child);
  await page.getByText('Das gelang', {exact: true}).waitFor();
  await shot('mobile');
  const after = await get('/children/' + child + '/overview?compact=true');
  assert.equal(after.plan.daily_active_seconds, before.plan.daily_active_seconds);
  assert.equal((await get('/units/' + unitId)).questions.flatMap(q => q.attempts).length, attempts.length);
  assert.equal(writes.length, 0);
  assert.equal(errors.length, 0);
  const report = {success: true, actual_saved_answers: attempts.length, same_native_parent_verdicts: true,
    desktop_and_mobile: true, parent_generated_child_activity: false, application_write_requests: 0,
    javascript_errors: 0, additional_model_jobs: 0};
  await writeFile(artifacts + 'report-review-parent-after-result.json', JSON.stringify(report) + '\n');
  console.log(JSON.stringify(report));
} finally {
  await browser.close();
}
