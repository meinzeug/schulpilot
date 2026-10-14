// Public HTTPS and protected views. No credentials, cookies or device tokens printed.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {chromium} from '@playwright/test';

const base = 'https://schulpilot.dorfspy.de';
const login = JSON.parse(await fs.readFile('/home/dennis/.local/share/schulpilot-firebase/test-login-private.json', 'utf8'));
const browser = await chromium.launch({headless:true,executablePath:'/opt/google/chrome/chrome'});
const contexts = [];
const errors = [];
const googleRequests = [];
const checks = [];
async function context(viewport) {
  const c = await browser.newContext({viewport}); contexts.push(c);
  c.on('request', r => {if (/firebaseinstallations|fcmregistrations|gstatic.com\/firebasejs/.test(r.url())) googleRequests.push(new URL(r.url()).hostname);});
  c.on('page', p => p.on('pageerror', e => errors.push(e.message)));
  return c;
}
async function open(page, path) {
  const response = await page.goto(base + path, {waitUntil:'domcontentloaded'});
  assert.equal(response.status(),200);
  await page.waitForSelector('flutter-view');
  await page.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(n => n.click()));
  await page.waitForTimeout(250);
}
const headers = {'X-Schulpilot-Request':'1'};
try {
  const publicContext = await context({width:1440,height:1000});
  const page = await publicContext.newPage();
  await open(page, '/angebote');
  await page.getByText('9,90 €',{exact:true}).waitFor();
  assert.equal(await page.getByRole('button',{name:'Verkauf startet bald',exact:true}).count(),3);
  await page.screenshot({path:'../artifacts/public-offers-desktop.png'});
  checks.push('public_prices_and_disabled_checkout');
  await open(page, '/bedingungen');
  await page.getByText(/Widerrufsbelehrung:/).first().waitFor();
  checks.push('public_terms_direct_link');
  const mobileContext = await context({width:390,height:844});
  const mobile = await mobileContext.newPage();
  await open(mobile, '/angebote');
  await mobile.getByText('9,90 €',{exact:true}).waitFor();
  assert(await mobile.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
  await mobile.screenshot({path:'../artifacts/public-offers-mobile.png'});
  checks.push('mobile_prices_fit_390px');
  const owner = await context({width:1280,height:1000});
  const signed = await owner.request.post(base+'/api/auth/login',{headers,data:{username:login.parent_username,password:login.parent_password}});
  assert.equal(signed.status(),200);
  const settings = await owner.newPage();
  await open(settings,'/settings');
  await settings.getByText('Künstliches Testkonto',{exact:true}).waitFor();
  const config = await (await owner.request.get(base+'/api/notifications/config')).json();
  assert.equal(config.available,true);assert.equal(config.test_mode,true);assert.equal(config.test_access,true);
  assert.notEqual(config.firebase.apiKey,config.firebase.androidApiKey);
  assert.equal(await (await publicContext.request.get(base+'/api/notifications/config')).json().then(x=>x.available),false);
  assert.equal((await owner.request.get(base+'/api/admin/orders')).status(),403);
  checks.push('scoped_synthetic_push_and_parent_role');
  const admin = await context({width:1440,height:1000});
  const password = (await fs.readFile('/home/dennis/brpw.txt','utf8')).replace(/[\r\n]+$/,'');
  assert.equal((await admin.request.post(base+'/api/auth/login',{headers,data:{username:'admin',password}})).status(),200);
  const adminPage = await admin.newPage();
  await open(adminPage,'/admin/push');
  await adminPage.getByText('Allgemeiner Push-Versand ist gesperrt',{exact:true}).waitFor();
  const status = await (await admin.request.get(base+'/api/notifications/admin/status')).json();
  assert.equal(status.sender_identity,'schulpilot-fcm-sender@schulpilot-f6bf3.iam.gserviceaccount.com');
  assert.equal(status.production_approved,false);assert.equal(status.test_available,true);
  assert.equal(status.private_key,undefined);
  checks.push('protected_push_status_and_private_credentials_absent');
  await open(adminPage,'/admin/verkauf');
  await adminPage.getByText('Verkauf einrichten',{exact:true}).waitFor();
  checks.push('protected_manual_payment_page');
  assert.deepEqual(googleRequests,[]);assert.deepEqual(errors,[]);
  checks.push('no_firebase_network_before_optin');
  assert.equal((await owner.request.post(base+'/api/auth/logout',{headers})).status(),200);
  assert.equal((await admin.request.post(base+'/api/auth/logout',{headers})).status(),200);
  console.log(JSON.stringify({checks,runtime_errors:0,actual_push_delivery:'not_performed'}));
} finally {await Promise.all(contexts.map(c=>c.close()));await browser.close();}
