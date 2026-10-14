// Isolated first-install browser acceptance. Never runs against the public host.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import crypto from 'node:crypto';
import {chromium} from '@playwright/test';

const base = 'http://127.0.0.1:3841';
const live = process.argv.includes('--live-free-probe');
const liveMail = process.argv.includes('--live-email');
const browser = await chromium.launch({executablePath:'/opt/google/chrome/chrome',headless:true});
const stateFile='../artifacts/.setup-browser-state.json';
const savedState=await fs.access(stateFile).then(()=>stateFile).catch(()=>undefined);
const context = await browser.newContext({viewport:{width:1280,height:1000},...(savedState?{storageState:savedState}:{})});
const page = await context.newPage();
const errors=[];
page.on('pageerror',e=>errors.push(e.message));
const accountFile='../artifacts/.setup-browser-account.json';
const account=await fs.readFile(accountFile,'utf8').then(JSON.parse).catch(()=>({username:'setup-qa-admin',password:crypto.randomBytes(24).toString('base64url')}));
assert.equal(account.username,'setup-qa-admin');
await fs.writeFile(accountFile,JSON.stringify(account)+'\n',{mode:0o600});await fs.chmod(accountFile,0o600);
const password=account.password;
const headers={'X-Schulpilot-Request':'1'};
async function open(route) {
 await page.goto(base+route);await page.waitForSelector('flutter-view');
 await page.locator('flt-semantics-placeholder').evaluateAll(nodes=>nodes.forEach(n=>n.click()));
 await page.waitForTimeout(350);
}
async function reveal(locator) {
 for(let i=0;i<30;i++) {
  const box=await locator.count()?await locator.boundingBox({timeout:400}).catch(()=>null):null;
  if(box&&box.y>=0&&box.y+box.height<=page.viewportSize().height) return;
  await page.mouse.move(640,850);await page.mouse.wheel(0,!box&&i===0?-16000:box&&box.y<0?-550:550);await page.waitForTimeout(180);
 }
 const lastBox=await locator.boundingBox({timeout:400}).catch(()=>null);
 throw new Error('Setup control not reachable: '+JSON.stringify({count:await locator.count(),box:lastBox}));
}
async function fill(name,value) {
 const field=page.getByLabel(name,{exact:true});
 await reveal(field);await field.click();await page.waitForTimeout(250);await page.keyboard.press('Control+A');await page.waitForTimeout(80);await page.keyboard.insertText(value);await page.waitForTimeout(100);
 if(await field.inputValue()!==value) throw new Error('Setup input did not persist: '+name);
}
async function click(name) {
 // Commit the active Flutter editor before its widget is replaced by the next
 // step. Leaving the hidden browser input focused can retain the old semantic
 // scroll offset after a short step replaces a long form.
 await page.mouse.click(page.viewportSize().width/2,18);await page.waitForTimeout(120);
 const button=page.getByRole('button',{name,exact:true}).or(page.getByText(name,{exact:true})).first();
 await reveal(button);await button.waitFor({state:'visible'});const box=await button.boundingBox();assert(box);await page.mouse.click(box.x+box.width/2,box.y+box.height/2);await page.waitForTimeout(450);
}
async function setSwitch(name,value) {
 const control=page.getByRole('switch',{name,exact:true});await reveal(control);
 if((await control.getAttribute('aria-checked')==='true')!==value) await control.click();
}
async function next() {
 const [result]=await Promise.all([page.waitForResponse(r=>r.url().endsWith('/setup/site')&&r.request().method()==='PUT'),click('Speichern & weiter')]);assert.equal(result.status(),200,JSON.stringify(await result.json()));
}
async function mobileChildScreenshot() {
 const mobile=await browser.newContext({viewport:{width:390,height:844}});
 const childPage=await mobile.newPage();
 const childErrors=[];childPage.on('pageerror',e=>childErrors.push(e.message));
 const created=await mobile.request.post(base+'/api/demo',{headers});assert.equal(created.status(),201);
 const demo=await created.json();
 assert.equal(demo.user.role,'parent');assert.equal(demo.user.families.length,1);assert.equal(demo.user.families[0].synthetic,true);
 const familyId=demo.user.families[0].id;
 try {
  assert.equal((await mobile.request.post(base+'/api/auth/logout',{headers})).status(),200);
  await childPage.goto(base+'/login');await childPage.waitForSelector('flutter-view');
  await childPage.locator('flt-semantics-placeholder').evaluateAll(nodes=>nodes.forEach(n=>n.click()));
  for(const [label,value] of [['E-Mail oder Benutzername',demo.credentials.child_username],['Passwort',demo.credentials.child_password]]) {
   const field=childPage.getByLabel(label,{exact:true});await field.click();await childPage.waitForTimeout(250);
   await childPage.keyboard.press('Control+A');await childPage.keyboard.insertText(value);
  }
  await childPage.mouse.click(195,18);await childPage.waitForTimeout(120);
  const submit=childPage.getByRole('button',{name:'Anmelden',exact:true});
  await submit.scrollIntoViewIfNeeded();const button=await submit.boundingBox();assert(button);
  await childPage.mouse.click(button.x+button.width/2,button.y+button.height/2);
  await childPage.waitForURL('**/app');
  const me=await(await mobile.request.get(base+'/api/auth/me')).json();assert.equal(me.role,'child');assert.equal(me.child_id,demo.child_id);
  await childPage.waitForTimeout(900);
  await childPage.getByText('Heute',{exact:true}).first().waitFor({timeout:8000}).catch(()=>{});
  await childPage.screenshot({path:'../artifacts/local-child-modern.png'});await fs.chmod('../artifacts/local-child-modern.png',0o600);
  assert.deepEqual(childErrors,[]);
  const parentLogin=await mobile.request.post(base+'/api/auth/login',{headers,data:{username:demo.credentials.parent_username,password:demo.credentials.parent_password}});
  assert.equal(parentLogin.status(),200);const parentUser=(await parentLogin.json()).user;
  assert.equal(parentUser.role,'parent');assert.equal(parentUser.families[0].id,familyId);
  const usage=await(await mobile.request.get(base+'/api/families/'+familyId+'/usage')).json();assert.equal(usage.calls_used,0);
  const removed=await mobile.request.delete(base+'/api/account',{headers,data:{password:demo.credentials.parent_password}});assert.equal(removed.status(),200);
  console.log(JSON.stringify({local_demo_child_screenshot:'artifacts/local-child-modern.png',viewport:390,external_ai_calls:0,own_demo_family_deleted:true,browser_errors:childErrors}));
 } finally {
  // This isolated demo belongs only to this run. Remove it even when a visual
  // assertion fails so retries do not leave orphaned synthetic families.
  try {
   const cleanup=await mobile.request.post(base+'/api/auth/login',{headers,data:{username:demo.credentials.parent_username,password:demo.credentials.parent_password}});
   if(cleanup.status()===200) await mobile.request.delete(base+'/api/account',{headers,data:{password:demo.credentials.parent_password}});
  } finally {await mobile.close();}
 }
}
try {
 const status=await (await context.request.get(base+'/api/setup/status')).json();
 if(status.required) {
 assert.equal((await context.request.post(base+'/api/auth/register',{headers,data:{}})).status(),503);
 await open('/');await page.waitForURL('**/setup');
 await page.getByLabel('Installationscode',{exact:true}).or(page.getByLabel('Admin-Benutzername',{exact:true})).waitFor();
 if(await page.getByLabel('Installationscode',{exact:true}).count()) {
  await page.screenshot({path:'../artifacts/setup-unlock.png'});
  await fill('Installationscode',(await fs.readFile('../artifacts/setup-qa-data/setup-code.txt','utf8')).trim());
  await click('Einrichtung öffnen');
  await page.getByLabel('Admin-Benutzername',{exact:true}).waitFor();
 }
 await context.storageState({path:stateFile});await fs.chmod(stateFile,0o600);
 await fill('Admin-Benutzername','setup-qa-admin');
 await fill('Admin-Passwort (mindestens 12 Zeichen)',password);await fill('Admin-Passwort wiederholen',password);
 await click('Speichern & weiter');
 await fill('Betreiber','Setup QA (künstlich)');await fill('Anschrift','Künstliche Testanschrift');await fill('Support-E-Mail','setup@example.org');
 await setSwitch('Verarbeitung echter Lerninhalte freigeben',true);
 await fill('Dokumentierte Anbieter- und Datenschutzfreigabe','Synthetischer Einrichtungstest; Betreiberfreigabe vom 14.10.2026. Keine Kinderdaten.');
 await setSwitch('KI-Tests mit künstlichen Daten erlauben',true);
 await next();
 if(liveMail) {
  const mail=JSON.parse(await fs.readFile('../artifacts/.setup-mail-qa.json','utf8'));
  for(const [label,key] of [['SMTP-Server','SMTP_HOST'],['Benutzername','SMTP_USER'],['SMTP-Passwort','SMTP_PASSWORD'],['Absender-E-Mail','SMTP_FROM']]) await fill(label,mail[key]);
  await fill('Port',mail.SMTP_PORT||'587');await fill('Testnachricht an',mail.SMTP_USER);
  const sent=page.waitForResponse(r=>r.url().endsWith('/setup/mail-test'));
  await click('Speichern & Testmail senden');const result=await sent;assert.equal(result.status(),200,JSON.stringify(await result.json()));
 }
 await next();
 if(live) {
  await click('Kostenlosen OpenRouter-Standard wählen');
  await fill('Neuer API-Schlüssel (optional)',(await fs.readFile('/home/dennis/or.txt','utf8')).trim());
  await setSwitch('Anbieterspezifische Datenschutzfreigabe dokumentiert',true);
  await fill('Verweis auf Datenschutz-/Minderjährigenfreigabe','Betreiberfreigabe vom 14.10.2026; ausschließlich künstlicher Einrichtungstest.');
  const saved=page.waitForResponse(r=>r.url().endsWith('/setup/provider')&&r.request().method()==='PUT');
  await click('Konfiguration sicher speichern');assert.equal((await saved).status(),200);
  await page.waitForTimeout(400);
  const checked=page.waitForResponse(r=>r.url().endsWith('/setup/provider/check'));
  await click('Verbindung ohne Lernanfrage prüfen');assert.equal((await checked).status(),200);
  const queued=page.waitForResponse(r=>r.url().endsWith('/setup/provider/probe'));
  await click('Bild & Aufgaben mit Beispieldaten prüfen');
  const queuedResponse=await queued;assert.equal(queuedResponse.status(),202);
  const job=await queuedResponse.json();
  let report;
  for(let i=0;i<180;i++) {
   report=await (await context.request.get(base+'/api/setup/provider/probes/'+job.id)).json();
   if(['completed','failed'].includes(report.status)) break;
   await page.waitForTimeout(2000);
  }
  assert.equal(report.status,'completed',report.error||'Probe did not complete');
  assert.equal(report.report.length,3);
  console.log(JSON.stringify({real_operator_probe:report.status,steps:report.report.map(s=>({function:s.function,cost_micros_usd:s.cost_micros_usd}))}));
  await page.getByText('Bild- und Aufgabenprüfung erfolgreich.',{exact:true}).waitFor({timeout:12000});
 }
 await next();await fill('Kinder je Familie','3');await fill('KI-Aufrufe pro Monat','120');await next();
 await next();
 await page.screenshot({path:'../artifacts/setup-summary.png'});
 await click('Einrichtung abschließen');await page.waitForURL('**/login');
 } else {await open('/login');}
 assert.equal((await (await context.request.get(base+'/api/setup/status')).json()).required,false);
 assert.equal((await context.request.post(base+'/api/setup/unlock',{headers,data:{code:'x'.repeat(48)}})).status(),409);
 await fill('E-Mail oder Benutzername','setup-qa-admin');await fill('Passwort',password);
 await click('Anmelden');await page.waitForURL('**/app');
 assert.equal((await (await context.request.get(base+'/api/auth/me')).json()).role,'admin');
 await open('/admin/settings');await page.getByText('Betreiber & Datenschutz',{exact:true}).waitFor();
 const operator=page.getByLabel('Betreiber',{exact:true});await operator.click();await page.waitForTimeout(250);assert.equal(await operator.inputValue(),'Setup QA (künstlich)');
 const stored=await (await context.request.get(base+'/api/admin/installation')).json();
 assert.equal(stored.site.default_child_limit,3);assert.equal(stored.site.default_call_limit,120);
 assert.equal(stored.site.smtp_password,undefined);assert.equal(stored.provider.api_key,undefined);
 if(liveMail) assert.equal(stored.site.has_smtp_password,true);
 await page.screenshot({path:'../artifacts/setup-admin-settings.png'});
 await context.request.post(base+'/api/auth/logout',{headers});
 assert.equal((await context.request.get(base+'/api/admin/installation')).status(),401);
 await context.storageState({path:stateFile});await fs.chmod(stateFile,0o600);
 assert.deepEqual(errors,[]);
 console.log(JSON.stringify({first_install_wizard:status.required,resumed_completed_installation:!status.required,admin_password_only:true,closed_setup_rejected:true,settings_persisted:true,logout_revoked:true,real_mail:liveMail,real_free_probe:live,browser_errors:errors}));
 await mobileChildScreenshot();
} catch(e) {
 await page.screenshot({path:'../artifacts/setup-browser-failure.png'}).catch(()=>{});
 throw e;
} finally {await browser.close();}
