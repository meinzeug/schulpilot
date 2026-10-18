// Public release: actual Flutter pages, only the operator's artificial family.
// No generation, sending, consent changes or private-content access by admins.
import assert from 'node:assert/strict';
import {readFile, writeFile, chmod} from 'node:fs/promises';
import {homedir} from 'node:os';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {chromium} from 'playwright';

const apiBase = 'https://schulpilot.dorfspy.de';
const base = process.env.DESIGN_PREVIEW_BASE || apiBase;
const preview = base !== apiBase;
assert(!preview || /^http:\/\/127\.0\.0\.1:\d+$/.test(base), 'preview_must_be_loopback');
const out = fileURLToPath(new URL('../artifacts/', import.meta.url));
const headers = {'X-Schulpilot-Request': '1', 'X-Schulpilot-Capabilities': 'language-v1'};
const fixture = JSON.parse(await readFile(path.join(out, '.design-qa-account.json'), 'utf8'));
const credentials = fixture.credentials;
const browser = await chromium.launch({headless: true, executablePath: '/opt/google/chrome/chrome', args: ['--no-sandbox']});
const checks = [], errors = [], failedReads = [], changes = [];
const contexts = [];
let phase = 'initial';
const report = {ui_origin: base, public_https_api: apiBase, preview, synthetic_family_only: true, checks, external_ai_calls: 0};

async function contextFor(role) {
  const context = await browser.newContext({viewport: {width: 1440, height: 1000}});
  contexts.push(context);
  const admin = role === 'admin';
  const response = await context.request.post(apiBase + '/api/auth/login', {headers, data: {
    username: admin ? 'admin' : credentials[role + '_username'],
    password: admin ? (await readFile(path.join(homedir(), 'brpw.txt'), 'utf8')).trim() : credentials[role + '_password'],
  }});
  assert.equal(response.status(), 200, 'normal_login_failed');
  const account = await response.json();
  assert.equal(account.user.role, role, 'incorrect_role');
  if (role === 'child') assert.equal(account.user.synthetic, true, 'artificial_child_required');
  if (role === 'parent') assert(account.user.families.length > 0 && account.user.families.every(f => f.synthetic === true), 'artificial_parent_required');
  if (preview) {
    // A loopback-only visual preview of the actual release bundle. Forward
    // only through this authenticated test context, never expose a proxy port.
    await context.route(base + '/api/**', async route => {
      const request = route.request();
      const response = await context.request.fetch(apiBase + new URL(request.url()).pathname + new URL(request.url()).search, {
        headers, method: request.method(), data: request.postData() || undefined,
      });
      await route.fulfill({response});
    });
  }
  context.on('page', page => page.on('pageerror', () => errors.push(phase)));
  context.on('request', request => {
    const pathname = new URL(request.url()).pathname;
    if (pathname.startsWith('/api/') && !['GET', 'HEAD', 'OPTIONS'].includes(request.method())) {
      changes.push({phase, method: request.method(), route: pathname.replace(/[a-f0-9]{32}/g, ':id')});
    }
  });
  context.on('response', response => {
    const pathname = new URL(response.url()).pathname;
    if (pathname.startsWith('/api/') && response.request().method() === 'GET' && response.status() >= 400) {
      failedReads.push({phase, status: response.status()});
    }
  });
  return {context, account: account.user};
}

async function open(page, route) {
  await page.goto(base + route, {waitUntil: 'domcontentloaded', timeout: 90000});
  await page.waitForSelector('flutter-view', {timeout: 90000});
  await page.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(node => node.click()));
  await page.waitForTimeout(900);
}

async function shot(page, name) {
  const filename = path.join(out, 'design-' + name + '.png');
  await page.screenshot({path: filename});
  await chmod(filename, 0o600);
}

async function inspect(page, role, width, route, label) {
  phase = role + '-' + label + '-' + width;
  await page.setViewportSize({width, height: 1000});
  await open(page, route);
  await page.getByRole('button', {name: role === 'admin' ? 'Push-Status' : /Benachrichtigungen/}).first().waitFor();
  // A framework layout exception must not hide behind a successful HTTP 200.
  const ui = await page.locator('flt-semantics-host').innerText();
  assert(!/RenderFlex overflowed|ErrorWidget|A RenderFlex|Null check operator/.test(ui), 'flutter_layout_failure');
  await shot(page, phase);
  checks.push(phase);
}

try {
  const health = await (await fetch(apiBase + '/api/health')).json();
  if (!preview) assert.equal(health.version, '1.4.2', 'deploy_design_release_before_review');
  report.source_commit = health.source_commit;
  const {context: parent, account} = await contextFor('parent');
  const familyResponse = await parent.request.get(apiBase + '/api/families/' + account.families[0].id, {headers});
  assert.equal(familyResponse.status(), 200);
  const family = await familyResponse.json();
  assert(family.children.length > 0, 'own_artificial_child_required');
  const childId = family.children[0].id;
  const p = await parent.newPage();
  for (const width of [1440, 960, 390, 320]) await inspect(p, 'parent', width, '/app', 'family');
  await inspect(p, 'parent', 1440, '/child/' + childId, 'child-detail');
  await inspect(p, 'parent', 390, '/child/' + childId, 'child-detail');
  await inspect(p, 'parent', 390, '/settings', 'settings');
  await inspect(p, 'parent', 1440, '/notifications', 'notifications');

  const {context: child, account: childAccount} = await contextFor('child');
  assert.equal(childAccount.child_id, childId, 'same_artificial_family_required');
  assert.equal(childId, fixture.child_id, 'dedicated_design_fixture_required');
  const c = await child.newPage();
  for (const width of [1440, 960, 390, 320]) await inspect(c, 'child', width, '/app', 'today');
  for (const [route, label] of [
    ['/library/' + childId, 'notebooks'], ['/learn/' + childId, 'learning'],
    ['/vocabulary/' + childId, 'vocabulary'], ['/progress/' + childId, 'progress'],
    ['/notifications', 'notifications'], ['/settings', 'settings'],
  ]) {
    await inspect(c, 'child', 390, route, label);
  }
  // This exact fixed unit was prepared in our own artificial household.
  // Opening the saved round creates no model job or additional answers.
  phase = 'child-learning-room';
  assert(fixture.unit_id, 'prepare_fixed_fixture_first');
  await open(c, '/unit/' + fixture.unit_id);
  await c.getByRole('button', {name: 'Lernrunde verlassen', exact: true}).waitFor();
  await shot(c, phase);
  checks.push(phase);

  const {context: admin} = await contextFor('admin');
  const a = await admin.newPage();
  for (const width of [1440, 960, 390, 320]) await inspect(a, 'admin', width, '/admin', 'operations');
  // Stay on operational status: never visit a family's private learning pages.
  await inspect(a, 'admin', 1440, '/admin/push', 'push-status');
  assert.equal(errors.length, 0, 'browser_runtime_failure');
  assert.equal(failedReads.length, 0, 'public_read_failed');
  assert(changes.every(change => change.route.endsWith('/heartbeat')), 'unexpected_mutation_during_visual_review');
  report.success = true;
  report.browser_runtime_errors = errors.length;
  report.failed_reads = failedReads.length;
  report.physical_phone = 'not_tested';
} catch (error) {
  report.success = false;
  report.failed_phase = phase;
  report.error = error.code || (error instanceof assert.AssertionError ? error.message.split('\n')[0] : 'visual_review_failed');
  process.exitCode = 1;
} finally {
  for (const context of contexts) {
    await context.request.post(apiBase + '/api/auth/logout', {headers}).catch(() => {});
    await context.close();
  }
  await browser.close();
  await writeFile(path.join(out, preview ? 'design-preview-result.json' : 'design-web-result.json'), JSON.stringify(report) + '\n', {mode: 0o600});
  console.log(JSON.stringify(report));
}
