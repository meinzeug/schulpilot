// Explicit opt-in on an operator-owned artificial browser. Never print FCM tokens.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {chromium} from '@playwright/test';
const base='https://schulpilot.dorfspy.de';
const credentials=JSON.parse(await fs.readFile('/home/dennis/.local/share/schulpilot-firebase/test-login-private.json','utf8'));
const browser=await chromium.launch({headless:true,executablePath:'/opt/google/chrome/chrome'});
const context=await browser.newContext({viewport:{width:1280,height:1000},permissions:['notifications']});
const headers={'X-Schulpilot-Request':'1'};
const hosts=[];
context.on('response',r=>{const h=new URL(r.url()).hostname;if(/firebaseinstallations|fcmregistrations/.test(h))hosts.push({host:h,status:r.status()});});
const page=await context.newPage();
const report={explicit_optin:false,registration:false,visible_delivery:'not_tested',firebase_requests:hosts};
const requestHosts=[];
context.on('request',r=>{if(new URL(r.url()).hostname!=='schulpilot.dorfspy.de') requestHosts.push(new URL(r.url()).hostname);});
page.on('console',m=>{if(m.type()==='error') {
  report.browser_error_count=(report.browser_error_count||0)+1;
  const text=m.text();
  const firebaseCode=text.match(/\b(?:app|messaging)\/[a-z-]+/g);
  if(firebaseCode)report.firebase_error_codes=firebaseCode;
  if(/Content Security Policy|Refused to|Cannot read properties|initializeApp|Firebase has not/.test(text))report.error_category=text.replace(/https?:\/\/\S+|AIza[\w-]+/g,'[URL]').slice(0,350);
}});
async function tap(locator) {
  for(let i=0;i<30;i++) {
    const box=await locator.boundingBox().catch(()=>null);
    if(box&&box.y>80&&box.y+box.height<925) {await page.mouse.click(box.x+box.width/2,box.y+box.height/2);return;}
    await page.mouse.move(1190,800);await page.mouse.wheel(0,box&&box.y<80?-450:450);await page.waitForTimeout(130);
  }
  throw new Error('Test control was not reachable');
}
try {
  assert.equal((await context.request.post(base+'/api/auth/login',{headers,data:{username:credentials.parent_username,password:credentials.parent_password}})).status(),200);
  await page.goto(base+'/settings');await page.waitForSelector('flutter-view');
  await page.locator('flt-semantics-placeholder').evaluateAll(ns=>ns.forEach(n=>n.click()));
  const button=page.getByRole('button',{name:'Auf diesem Gerät einschalten',exact:true});
  await button.waitFor();assert.equal(hosts.length,0);
  const registration=page.waitForResponse(r=>new URL(r.url()).pathname==='/api/notifications/device'&&r.request().method()==='PUT',{timeout:50000});
  registration.catch(()=>{});
  report.explicit_optin=true;
  await tap(button);
  await page.waitForTimeout(800);
  report.notice_after_click=(await page.locator('flt-semantics').allTextContents()).filter(t=>/Benachrichtigungen konnten|Push konnte|nicht erlaubt|unterstützt keine|Keine Verbindung/.test(t)).map(t=>t.slice(0,240));
  try {const result=await registration;report.registration=result.status()===200;report.registration_http=result.status();}
  catch {
    report.registration_error='No completed registration within 50 seconds';
    const texts=await page.locator('flt-semantics').allTextContents();
    report.visible_notice=texts.filter(t=>/Benachrichtigungen konnten|Push konnte|nicht erlaubt|unterstützt keine|Keine Verbindung/.test(t)).map(t=>t.slice(0,240));
    report.request_hosts=[...new Set(requestHosts)];
    await page.screenshot({path:'../artifacts/push-registration-state.png'});
  }
  if(report.registration) {
    const registrations=await (await context.request.get(base+'/api/notifications/devices')).json();
    assert(registrations.some(d=>d.current));
    const workers=await page.evaluate(async()=> (await navigator.serviceWorker.getRegistrations()).map(r=>({scope:new URL(r.scope).pathname,script:new URL(r.active?.scriptURL||r.installing?.scriptURL||r.waiting?.scriptURL).pathname})));
    report.dedicated_worker=workers.some(r=>r.scope==='/push/'&&r.script==='/push/firebase-messaging-sw.js');
    assert(report.dedicated_worker);
    // Do not send here. Visible foreground/background delivery is a separate
    // browser/device test and is not inferred from registration success.
  }
  const logout=page.getByRole('button',{name:'Abmelden',exact:true});
  if(await logout.count())await tap(logout);
  else await context.request.post(base+'/api/auth/logout',{headers});
  await page.waitForTimeout(1000);
  report.session_revoked=(await context.request.get(base+'/api/auth/me')).status()===401;
  console.log(JSON.stringify(report));
  if(!report.registration || !report.session_revoked)process.exitCode=1;
} finally {await context.request.post(base+'/api/auth/logout',{headers}).catch(()=>{});await context.close();await browser.close();}
