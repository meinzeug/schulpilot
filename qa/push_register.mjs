// Explicit opt-in on an operator-owned artificial browser. Never print FCM tokens.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {chromium} from '@playwright/test';
const base='https://schulpilot.dorfspy.de';
const credentials=JSON.parse(await fs.readFile('/home/dennis/.local/share/schulpilot-firebase/test-login-private.json','utf8'));
// Chrome refuses PushManager.subscribe in incognito contexts. A private,
// disposable persistent profile exercises the normal supported browser mode.
const profile=await fs.mkdtemp(path.join(os.tmpdir(),'schulpilot-push-'));
await fs.chmod(profile,0o700);
const context=await chromium.launchPersistentContext(profile,{headless:true,executablePath:'/opt/google/chrome/chrome',viewport:{width:1280,height:1000},permissions:['notifications']});
const headers={'X-Schulpilot-Request':'1'};
const validate=process.argv.includes('--validate')||process.argv.includes('--send');
const send=process.argv.includes('--send');
if(validate)await context.route(base+'/api/notifications/device',async route=>{
  // Only this artificial, disposable device: explicitly disable its quiet
  // hours for the bounded operator test. The token stays in memory.
  if(route.request().method()!=='PUT')return route.continue();
  await route.continue({postData:JSON.stringify({...route.request().postDataJSON(),quiet_start:0,quiet_end:0})});
});
const hosts=[];
context.on('response',r=>{const h=new URL(r.url()).hostname;if(/firebaseinstallations|fcmregistrations/.test(h))hosts.push({host:h,status:r.status()});});
const page=await context.newPage();
const report={explicit_optin:false,registration:false,visible_delivery:'not_tested',firebase_requests:hosts};
const safeError=text=>text.replace(/https?:\/\/\S+|AIza[\w-]+|[A-Za-z0-9_:\-.]{48,}/g,'[REDACTED]').slice(0,350);
const requestHosts=[];
context.on('request',r=>{if(new URL(r.url()).hostname!=='schulpilot.dorfspy.de') requestHosts.push(new URL(r.url()).hostname);});
context.on('requestfailed',r=>{
  if(new URL(r.url()).hostname!=='schulpilot.dorfspy.de')report.failed_request={host:new URL(r.url()).hostname,error:safeError(r.failure()?.errorText||'unknown')};
});
page.on('pageerror',error=>{report.runtime_error=safeError(error.message);});
page.on('console',m=>{if(m.type()==='error') {
  report.browser_error_count=(report.browser_error_count||0)+1;
  const text=m.text();
  const firebaseCode=text.match(/\b(?:app|messaging)\/[a-z-]+/g);
  if(firebaseCode)report.firebase_error_codes=firebaseCode;
  report.error_category=safeError(text);
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
  await page.goto(base+'/app');await page.waitForSelector('flutter-view');
  await page.locator('flt-semantics-placeholder').evaluateAll(ns=>ns.forEach(n=>n.click()));
  await page.getByRole('button',{name:/Benachrichtigungen/}).click();
  await page.getByText('Deine Neuigkeiten',{exact:true}).waitFor();
  report.bell_opens_inbox=true;
  // An actual saved request from our own artificial child, never another family.
  const childContext=await (await import('@playwright/test')).request.newContext({baseURL:base,extraHTTPHeaders:{...headers,'X-Client-Platform':'native'}});
  let childHeaders;
  try {
    const login=await childContext.post('/api/auth/login',{data:{username:credentials.child_username,password:credentials.child_password}});
    assert.equal(login.status(),200);
    const child=await login.json();assert.equal(child.user.synthetic,true);
    childHeaders={Authorization:'Bearer '+child.token};
    const saved=await childContext.post('/api/children/'+child.user.child_id+'/messages',{headers:childHeaders,data:{kind:'help',body:'Künstlicher Hinweis für die Benachrichtigungsprüfung.'}});
    assert.equal(saved.status(),201);
    const {id}=await saved.json();
    const refreshed=page.waitForResponse(r=>new URL(r.url()).pathname==='/api/notifications/inbox'&&r.request().method()==='GET');
    await tap(page.getByRole('button',{name:'Aktualisieren',exact:true}));
    assert.equal((await refreshed).status(),200);
    await page.waitForTimeout(200);
    // Flutter merges a ListTile's title and timestamp into one semantics node.
    await page.getByText('Unterstützung gewünscht').first().waitFor();
    const feed=await (await context.request.get(base+'/api/notifications/inbox')).json();
    assert(feed.items.some(item=>item.id==='message:'+id&&!item.read));
    const marked=page.waitForResponse(r=>new URL(r.url()).pathname==='/api/notifications/inbox/read'&&r.request().method()==='POST');
    await tap(page.getByRole('button',{name:'Alle als gelesen markieren',exact:true}));
    assert.equal((await marked).status(),200);
    const after=await (await context.request.get(base+'/api/notifications/inbox')).json();assert.equal(after.unread,0);
    assert.equal((await context.request.post(base+'/api/children/'+child.user.child_id+'/messages/'+id+'/resolve',{headers})).status(),200);
    report.saved_request_read_consistent=true;
    await page.reload();await page.waitForSelector('flutter-view');
    await page.locator('flt-semantics-placeholder').evaluateAll(ns=>ns.forEach(n=>n.click()));
    await page.getByText('Deine Neuigkeiten',{exact:true}).waitFor();
    assert.equal((await (await context.request.get(base+'/api/notifications/inbox')).json()).unread,0);
    report.read_ack_survives_reload=true;
  } finally {
    if(childHeaders)await childContext.post('/api/auth/logout',{headers:childHeaders}).catch(()=>{});
    await childContext.dispose();
  }
  await tap(page.getByRole('button',{name:'Gerät einstellen',exact:true}));
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
    if(validate) {
      async function ownTest(mode) {
        const response=page.waitForResponse(r=>new URL(r.url()).pathname==='/api/notifications/test'&&r.request().method()==='POST');
        await tap(page.getByRole('button',{name:mode==='validate'?'FCM-Anfrage validieren':'Test an dieses Gerät senden',exact:true}));
        const queued=await response;assert.equal(queued.status(),202);
        const {id}=await queued.json();
        for(let i=0;i<20;i++) {
          const tests=await (await context.request.get(base+'/api/notifications/tests')).json();
          const result=tests.results.find(r=>r.id===id);
          if(result&&!['queued','sending'].includes(result.status))return result.status;
          await page.waitForTimeout(1500);
        }
        throw new Error('Own test did not finish within 30 seconds');
      }
      report.own_device_validation=await ownTest('validate');
      assert.equal(report.own_device_validation,'validated');
      if(send) {
        const foreground=page.getByText('Es gibt Neuigkeiten in SCHULPILOT.',{exact:true}).waitFor({timeout:25000});
        foreground.catch(()=>{});
        report.own_device_send=await ownTest('send');
        assert.equal(report.own_device_send,'accepted');
        await foreground;
        report.visible_delivery='observed_foreground_in_app_banner';
      }
    }
  }
  await page.goto(base+'/settings');await page.waitForSelector('flutter-view');
  await page.locator('flt-semantics-placeholder').evaluateAll(ns=>ns.forEach(n=>n.click()));
  const logout=page.getByRole('button',{name:'Abmelden',exact:true});
  if(await logout.count())await tap(logout);
  else await context.request.post(base+'/api/auth/logout',{headers});
  await page.waitForTimeout(1000);
  report.session_revoked=(await context.request.get(base+'/api/auth/me')).status()===401;
  console.log(JSON.stringify(report));
  if(!report.registration || !report.session_revoked)process.exitCode=1;
} catch(error) {
  report.failure_category=safeError(error.message||'unknown');
  console.log(JSON.stringify(report));
  process.exitCode=1;
} finally {
  await context.request.post(base+'/api/auth/logout',{headers}).catch(()=>{});
  await context.close();
  await fs.rm(profile,{recursive:true,force:true});
}
