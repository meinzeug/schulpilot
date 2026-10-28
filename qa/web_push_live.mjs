// Explicitly authorized, isolated Chrome + artificial household only.
// No Google login, real recipients, private payloads or printed FCM tokens.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {chromium} from '@playwright/test';

const input = process.argv[2];
const output = process.argv[3];
assert(input && output, 'Pass a protected artificial fixture and output folder');
const fixture = JSON.parse(await fs.readFile(input, 'utf8'));
assert(fixture.synthetic_only === true);
await fs.mkdir(output, {recursive:true, mode:0o700});
const profile = await fs.mkdtemp(path.join(os.tmpdir(), 'schulpilot-push-qa-'));
await fs.chmod(profile, 0o700);
const base = 'https://schulpilot.dorfspy.de';
const headers = {'X-Schulpilot-Request':'1'};
const report = {synthetic_only:true, browser_permission_pregranted:true,
  requested_messages:0, firebase_responses:[]};
const context = await chromium.launchPersistentContext(profile, {
  executablePath:'/opt/google/chrome/chrome', headless:true,
  viewport:{width:1280,height:1000}, permissions:['notifications'],
});
let loggedIn = false;
let page;
try {
  // Only our disposable fixture: no quiet interval during this bounded test.
  await context.route(base + '/api/notifications/device', async route => {
    if (route.request().method() !== 'PUT') return route.continue();
    await route.continue({postData:JSON.stringify({
      ...route.request().postDataJSON(), quiet_start:0, quiet_end:0,
    })});
  });
  context.on('response', response => {
    const host = new URL(response.url()).hostname;
    if (['firebaseinstallations.googleapis.com','fcmregistrations.googleapis.com'].includes(host)) {
      report.firebase_responses.push({host,status:response.status()});
    }
  });
  report.phase = 'artificial_login';
  const login = await context.request.post(base + '/api/auth/login', {
    headers, data:{username:fixture.credentials.parent_username,
      password:fixture.credentials.parent_password},
  });
  assert.equal(login.status(), 200);
  loggedIn = true;
  const account = (await login.json()).user;
  assert.equal(account.role, 'parent');
  assert(account.families.length === 1 && account.families[0].synthetic === true);
  assert.equal(account.families[0].id, fixture.family_id);
  page = await context.newPage();
  page.on('pageerror', () => { report.runtime_errors = (report.runtime_errors || 0) + 1; });
  async function semantics() {
    await page.waitForSelector('flutter-view');
    const entry = page.locator('flt-semantics-placeholder');
    // Flutter's accessibility placeholder intentionally has no painted box.
    if (await entry.count()) await entry.evaluateAll(nodes => nodes.forEach(node => node.click()));
  }
  async function tap(name) {
    const locator = page.getByRole('button', {name,exact:true});
    for (let i=0; i<24; i++) {
      const box = await locator.boundingBox({timeout:400}).catch(() => null);
      if (box && box.y > 80 && box.y + box.height < 940) {
        await page.mouse.click(box.x + box.width/2,box.y + box.height/2);
        return;
      }
      await page.mouse.move(1180,800);
      await page.mouse.wheel(0,box && box.y < 80 ? -450 : 450);
      await page.waitForTimeout(150);
    }
    throw new Error('own_test_control_not_reachable');
  }
  report.phase = 'document';
  await page.goto(base + '/notifications');
  await semantics();
  await page.getByText('Auf diesem Gerät', {exact:true}).waitFor();
  assert.equal(report.firebase_responses.length, 0);
  report.no_firebase_before_optin = true;
  report.phase = 'explicit_optin';
  const registered = page.waitForResponse(r =>
    new URL(r.url()).pathname === '/api/notifications/device' && r.request().method() === 'PUT',
    {timeout:55000});
  registered.catch(() => {});
  await tap('Auf diesem Gerät einschalten');
  report.explicit_optin = true;
  assert.equal((await registered).status(), 200);
  report.registration = true;
  const devices = await (await context.request.get(base + '/api/notifications/devices')).json();
  const ownDevice = devices.find(device => device.current && device.platform === 'web');
  assert(ownDevice);
  report.own_session_bound_device = true;
  report.dedicated_worker = await page.evaluate(async () =>
    (await navigator.serviceWorker.getRegistrations()).some(registration =>
      new URL(registration.scope).pathname === '/push/' &&
      new URL(registration.active?.scriptURL || '').pathname === '/push/firebase-messaging-sw.js'));
  assert(report.dedicated_worker);
  async function ownTest(mode) {
    const queued = page.waitForResponse(r =>
      new URL(r.url()).pathname === '/api/notifications/test' && r.request().method() === 'POST');
    queued.catch(() => {});
    await tap(mode === 'validate' ? 'FCM-Anfrage validieren' : 'Test an dieses Gerät senden');
    const response = await queued;
    assert.equal(response.status(), 202);
    const result = await response.json();
    for (let i=0; i<25; i++) {
      const tests = await (await context.request.get(base + '/api/notifications/tests')).json();
      const item = tests.results.find(item => item.id === result.id);
      if (item && !['queued','sending'].includes(item.status)) return item.status;
      await new Promise(resolve => setTimeout(resolve,1000));
    }
    throw new Error('own_test_status_timeout_no_retry');
  }
  async function reserveSend(caseName) {
    const claim = await fs.open(path.join(output, '.web-send-' + caseName + '.json'),'wx',0o600);
    await claim.writeFile(JSON.stringify({reserved:true,case:caseName}));
    await claim.close();
    report.requested_messages++;
  }
  report.phase = 'validate';
  report.validation = await ownTest('validate');
  assert.equal(report.validation, 'validated');
  const visible = page.getByText('Es gibt Neuigkeiten in SchuleSchlau.', {exact:true})
    .waitFor({timeout:35000}).then(async () => {
      report.foreground_banner_visible = true;
      await page.screenshot({path:path.join(output,'web-foreground.png')});
    });
  visible.catch(() => {});
  await reserveSend('foreground');
  report.phase = 'foreground';
  report.send = await ownTest('send');
  assert.equal(report.send,'accepted');
  await visible;
  // No Schulpilot document remains open. Check the actual background handler,
  // while distinguishing a registered Notification from a visible OS banner.
  await page.goto('about:blank');
  report.phase = 'background';
  const worker = context.serviceWorkers().find(worker =>
    new URL(worker.url()).pathname === '/push/firebase-messaging-sw.js');
  assert(worker);
  await reserveSend('background');
  const queuedBackground = await context.request.post(base + '/api/notifications/test', {
    headers, data:{mode:'send'},
  });
  assert.equal(queuedBackground.status(),202);
  const backgroundId = (await queuedBackground.json()).id;
  for (let i=0; i<35; i++) {
    const tests = await (await context.request.get(base + '/api/notifications/tests')).json();
    const item = tests.results.find(item => item.id === backgroundId);
    if (item && !['queued','sending'].includes(item.status)) {
      report.background_send = item.status;
      break;
    }
    await new Promise(resolve => setTimeout(resolve,1000));
  }
  assert.equal(report.background_send,'accepted');
  for (let i=0; i<35; i++) {
    report.background_notification_registered = await worker.evaluate(async () =>
      (await self.registration.getNotifications()).some(notification =>
        notification.title === 'SchuleSchlau' &&
        notification.body === 'Es gibt Neuigkeiten in SchuleSchlau. Öffne deinen Lernraum.'));
    if (report.background_notification_registered) break;
    await new Promise(resolve => setTimeout(resolve,1000));
  }
  assert(report.background_notification_registered);
  await worker.evaluate(async () => {
    for (const notification of await self.registration.getNotifications()) notification.close();
  });
  await page.goto(base + '/notifications');
  await semantics();
  await page.getByText('Für dieses Gerät eingeschaltet.',{exact:true}).waitFor();
  report.restore_after_reload = true;
  report.phase = 'logout';
  await page.goto(base + '/settings');
  await semantics();
  await tap('Abmelden');
  await page.getByText('Willkommen zurück',{exact:true}).waitFor();
  assert.equal((await context.request.get(base + '/api/auth/me')).status(),401);
  loggedIn = false;
  report.ui_logged_out = true;
  const observer = await context.request.post(base + '/api/auth/login', {
    headers, data:{username:fixture.credentials.parent_username,
      password:fixture.credentials.parent_password},
  });
  assert.equal(observer.status(),200);
  loggedIn = true;
  const remaining = await context.request.get(base + '/api/notifications/devices');
  assert.equal(remaining.status(),200);
  assert(!(await remaining.json()).some(device => device.id === ownDevice.id));
  report.registration_removed_on_logout = true;
  report.os_background_notification_observed = false;
  assert.equal(report.runtime_errors || 0,0);
  report.phase = 'complete';
} catch (error) {
  // Never include raw URLs, provider errors, payloads or authentication data.
  report.failure = error instanceof assert.AssertionError ? 'assertion' :
    /^[a-z_]+$/.test(error.message || '') ? error.message : error.constructor.name;
  let safe = String(error.message || '');
  for (const value of Object.values(fixture.credentials)) safe = safe.split(value).join('[REDACTED]');
  report.failure_detail = safe.replace(/https?:\/\/\S+|[A-Za-z0-9_:\-.]{48,}/g,'[REDACTED]').slice(0,600);
  if (page) await page.screenshot({path:path.join(output,'web-failure.png')}).catch(() => {});
  process.exitCode = 1;
} finally {
  if (loggedIn) {
    try {
      const logout = await context.request.post(base + '/api/auth/logout', {headers});
      report.cleanup_logout_http_success = [200,401].includes(logout.status());
      if (!report.cleanup_logout_http_success) process.exitCode = 1;
    }
    catch { report.cleanup_logout_failed = true; process.exitCode = 1; }
  }
  await context.close();
  await fs.rm(profile,{recursive:true,force:true});
  await fs.writeFile(path.join(output,'web-push-result.json'),JSON.stringify(report,null,2));
  console.log(JSON.stringify(report));
}
