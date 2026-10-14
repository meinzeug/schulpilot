// Actual public admin login; the operator password never leaves local stdin/file reads.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {chromium} from '@playwright/test';
const base='https://schulpilot.dorfspy.de';
const password=(await fs.readFile('/home/dennis/brpw.txt','utf8')).replace(/[\r\n]+$/,'');
const browser=await chromium.launch({executablePath:'/opt/google/chrome/chrome',headless:true});
const context=await browser.newContext({viewport:{width:1440,height:1000}});
const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
const headers={'X-Schulpilot-Request':'1'};
async function open(route) {await page.goto(base+route);await page.waitForSelector('flutter-view');await page.locator('flt-semantics-placeholder').evaluateAll(ns=>ns.forEach(n=>n.click()));await page.waitForTimeout(300);}
async function fill(label,value) {const f=page.getByLabel(label,{exact:true});await f.click();await page.waitForTimeout(250);await page.keyboard.press('Control+A');await page.keyboard.insertText(value);}
try {
 await open('/login');await page.getByLabel('E-Mail oder Benutzername',{exact:true}).waitFor();
 assert.equal(await page.locator('input').count(),2);
 await fill('E-Mail oder Benutzername','admin');await fill('Passwort',password);
 const login=page.waitForResponse(r=>r.url().endsWith('/auth/login')&&r.request().method()==='POST');
 await page.getByRole('button',{name:'Anmelden',exact:true}).click();assert.equal((await login).status(),200);
 await page.waitForURL('**/app');
 const me=await (await context.request.get(base+'/api/auth/me')).json();assert.equal(me.role,'admin');assert.equal(me.username,'admin');
 const cookie=(await context.cookies()).find(c=>c.name==='sp_session');assert(cookie?.httpOnly&&cookie.secure&&cookie.sameSite==='Strict');
 assert.equal((await (await context.request.get(base+'/api/setup/status')).json()).required,false);
 assert.equal((await context.request.post(base+'/api/setup/unlock',{headers,data:{code:'x'.repeat(48)}})).status(),409);
 await open('/admin');await page.getByRole('button',{name:'Betriebseinstellungen',exact:true}).waitFor();
 const provider=await (await context.request.get(base+'/api/admin/provider')).json();
 assert.equal(provider.provider,'openrouter');assert.equal(provider.openrouter_free_only,true);assert.equal(provider.emergency_stop,false);assert.equal(provider.api_key,undefined);
 await page.getByRole('button',{name:'Betriebseinstellungen',exact:true}).click();await page.getByText('Betreiber & Datenschutz',{exact:true}).waitFor();
 const config=await (await context.request.get(base+'/api/admin/installation')).json();
 assert.equal(config.site.smtp_password,undefined);assert.equal(config.site.fcm_service_account_json,undefined);
 await page.screenshot({path:'../artifacts/public-admin-settings.png'});
 assert.deepEqual(errors,[]);
 assert.equal((await context.request.post(base+'/api/auth/logout',{headers})).status(),200);
 assert.equal((await context.request.get(base+'/api/admin/provider')).status(),401);
 console.log(JSON.stringify({public_admin_password_only:true,secure_cookie:true,setup_closed:true,free_provider_preserved:true,secrets_not_returned:true,logout_revoked:true,runtime_errors:errors}));
} finally {await browser.close();}
