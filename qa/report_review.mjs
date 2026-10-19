// Public Flutter regression with one owned artificial family; never real pupils.
import assert from 'node:assert/strict';
import {chromium} from 'playwright';
import {readFile,writeFile,chmod} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
const base='https://schulpilot.dorfspy.de';
const artifacts=fileURLToPath(new URL('../artifacts/',import.meta.url));
const privateFile=artifacts+'.school-day-qa-account.json';
const headers={'X-Schulpilot-Request':'1','X-Schulpilot-Capabilities':'language-v1'};
let account,state,browser,page,child,parent,phase='setup';
const checks=[],errors=[];
const button=name=>page.getByRole('button',{name,exact:true});
async function save(){account.report_qa=state;await writeFile(privateFile,JSON.stringify(account)+'\n',{mode:0o600});await chmod(privateFile,0o600);}
async function get(context,route){const r=await context.request.get(base+'/api'+route,{headers});assert.equal(r.status(),200,'owned_get_failed');return r.json();}
async function open(route){await page.goto(base+route,{waitUntil:'domcontentloaded',timeout:90000});await page.waitForSelector('flutter-view',{timeout:90000});await page.locator('flt-semantics-placeholder').evaluateAll(ns=>ns.forEach(n=>n.click()));await page.waitForTimeout(400);}
async function tap(locator,modal=false){for(let i=0;i<35;i++){const target=locator.first();const box=await target.count()?await target.boundingBox().catch(()=>null):null;if(box&&box.width&&box.height&&box.y>=0&&box.y+box.height<page.viewportSize().height-(modal?8:98)){await page.mouse.click(box.x+Math.min(box.width/2,180),box.y+box.height/2);await page.waitForTimeout(250);return;}await page.mouse.move(160,400);await page.mouse.wheel(0,box&&box.y<0?-260:300);await page.waitForTimeout(130);}throw Error('owned_control_not_visible');}
async function type(locator,value,modal=false){await tap(locator,modal);await page.keyboard.press('Control+A');await page.keyboard.type(value,{delay:10});await page.keyboard.press('Tab');await page.waitForTimeout(350);assert.equal(await locator.inputValue(),value,'typed_value_missing');}
async function ui(locator,route,method,status,modal=false){const waiting=page.waitForResponse(r=>new URL(r.url()).pathname==='/api'+route&&r.request().method()===method,{timeout:45000});waiting.catch(()=>{});await tap(locator,modal);const r=await waiting;assert.equal(r.status(),status,'explicit_owned_action_failed');return r.json();}
async function wait(read,done,seconds=340){const end=Date.now()+seconds*1000;while(Date.now()<end){const v=await read();assert(!['failed','unreadable'].includes(v.status),'failed_job_preserved_no_retry');assert.notEqual(v.preparation?.status,'failed','failed_preparation_preserved_no_retry');if(done(v))return v;await page.waitForTimeout(2000);}throw Error('bounded_wait_expired');}
async function shot(name){const f=artifacts+'report-review-'+name+'.png';await page.screenshot({path:f});await chmod(f,0o600);}
async function login(role,context){page=await context.newPage();page.on('pageerror',()=>errors.push(phase));await open('/login');await type(page.getByRole('textbox',{name:'E-Mail oder Benutzername',exact:true}),account.credentials[role+'_username']);await type(page.getByLabel('Passwort',{exact:true}),account.credentials[role+'_password']);await tap(button('Anmelden'));await page.waitForURL(base+'/app');}
try{
 account=JSON.parse(await readFile(privateFile,'utf8'));
 assert(account.normal_account&&account.verified&&/\+schulpilot-normal-qa-[a-f0-9]{12}@/.test(account.credentials.parent_username),'owned_family_required');
 state=account.report_qa??{materials:[],phase:'new'};
 const health=await(await fetch(base+'/api/health')).json();assert.equal(health.version,'1.8.0','deploy_review_release_first');
 browser=await chromium.launch({headless:true,executablePath:'/opt/google/chrome/chrome',args:['--no-sandbox']});
 child=await browser.newContext({viewport:{width:390,height:1000},isMobile:true,hasTouch:true});
 parent=await browser.newContext({viewport:{width:1440,height:1100}});
 await login('child',child);const childPage=page;
 phase='normal_photo_capture';
 if(!state.day_id){await open('/after-school/'+account.child_id+'?capture=1');const d=await wait(()=>get(child,'/children/'+account.child_id+'/school-day/today'),v=>v.day!=null,30);state.day_id=d.day.id;await save();}
 let day=await get(child,'/school-days/'+state.day_id);
 if(!day.pages.length){await open('/after-school/'+account.child_id+'?capture=1');const chooser=page.waitForEvent('filechooser');await tap(button('Fotos auswählen'));await(await chooser).setFiles(account.image_paths);for(const _ of account.image_paths)await tap(button('Zuschnitt übernehmen'),true);await shot('crop-import');await tap(button('Fotos abgeben'));state.phase='submitted';await save();}
 day=await wait(()=>get(child,'/school-days/'+state.day_id),d=>d.pages.length===account.image_paths.length&&d.pages.every(p=>['review','confirmed'].includes(p.status)),480);
 state.materials=day.pages.map(p=>p.id);await save();
 checks.push('actual_public_photo_picker_crop_explicit_submission_and_reserved_ocr');
 phase='source_and_homework_preview';
 for(const id of state.materials){const m=await get(child,'/materials/'+id);assert(m.content&&m.supports_task_confirmation,'current_source_capability_required');if(!m.confirmed){await open('/material/'+id);await tap(button('Stimmt, weiter'));if(await button('Auswahl übernehmen').count()){await shot('homework-preview');await tap(button('Auswahl übernehmen'),true);}await wait(()=>get(child,'/materials/'+id),v=>v.confirmed,30);} }
 const before=await get(child,'/children/'+account.child_id+'/overview?compact=true');
 state.assignments=before.assignments.length;assert(state.assignments<=2,'headings_or_examples_not_binding');await save();
 checks.push('explicit_source_task_preview_examples_not_automatic_homework');
 phase='real_learning_unit';
 day=await get(child,'/school-days/'+state.day_id);
 if(!state.unit_id){await open('/after-school/'+account.child_id);if(!day.units.length){await tap(button('Im Hintergrund vorbereiten').or(button('Lernpaket für heute erstellen')).or(button('Jetzt lernen')));}
 day=await wait(()=>get(child,'/school-days/'+state.day_id),d=>d.units.length>0,240);state.unit_id=day.units[0].id;await save();}
 let u=await get(child,'/units/'+state.unit_id);assert(!u.synthetic&&u.questions.length,'real_generated_round_required');
 await open('/unit/'+state.unit_id);
 if(await button('Einheit starten').count())await tap(button('Einheit starten'));
 if(await button('Lernen fortsetzen').count())await tap(button('Lernen fortsetzen')); 
 if(await button('Weiter zu den Übungen').count())await tap(button('Weiter zu den Übungen'));
 u=await get(child,'/units/'+state.unit_id);state.question_count=u.questions.length;await save();
 checks.push('actual_generated_round_open_and_saved_introduction');await shot('learning-mobile');
 phase='real_curated_tutor';
 const bioId=state.materials[state.materials.length-1];
 if(!state.tutor_id){
  await open('/material/'+bioId);await tap(button('Frag nach'));
  await type(page.getByRole('textbox',{name:'Deine Frage',exact:true}),
    'Warum ist ein Wal ein Säugetier, obwohl er im Wasser lebt? Erkläre es einfach.',true);
  const t=await ui(button('Frage stellen'),'/children/'+account.child_id+'/tutor/questions','POST',202,true);
  state.tutor_id=t.id;await save();
 }
 const tutor=await wait(async()=>{
  const h=await get(child,'/children/'+account.child_id+'/tutor/questions?material_id='+bioId);
  return h.questions.find(t=>t.id===state.tutor_id)??{status:'queued'};
 },t=>t.status==='ready',210);
 assert(tutor.reply.kind==='foundation'&&tutor.reply.sources.some(s=>s.origin==='reviewed_supplement'),'curated_whale_source_required');
 checks.push('real_reserved_whale_tutor_reviewed_supplement_separate_from_notebook');
 await open('/material/'+bioId);await tap(button('Frag nach'));await page.waitForTimeout(600);
 await shot('curated-tutor-mobile');
 if(tutor.reply.next_question&&!state.followup_id){
  await type(page.getByRole('textbox',{name:'Deine Antwort',exact:true}),'Wale atmen Luft mit Lungen.',true);
  const follow=await ui(button('Antwort senden'),'/children/'+account.child_id+'/tutor/questions','POST',202,true);
  assert.equal(follow.reply_to,tutor.id,'direct_teacher_answer_relation_required');state.followup_id=follow.id;await save();
 }
 if(state.followup_id){
  await wait(async()=>{
   const h=await get(child,'/children/'+account.child_id+'/tutor/questions?material_id='+bioId);
   return h.questions.find(t=>t.id===state.followup_id)??{status:'queued'};
  },t=>t.status==='ready',210);
  checks.push('real_conscious_teacher_followup_and_saved_answer');
 }
 // Leave the child route before isolating parent reading from child activity.
 await open('/app');await page.waitForTimeout(500);
 phase='parent_readonly_and_brief';
 const preRead=await get(child,'/children/'+account.child_id+'/overview?compact=true');
 await login('parent',parent);await open('/child/'+account.child_id);
 await page.getByText('Das gelang',{exact:true}).waitFor({timeout:15000});
 await page.getByText('Das übernimmt die App',{exact:true}).waitFor();
 await shot('parent-brief-desktop');await page.waitForTimeout(1600);
 await open('/unit/'+state.unit_id);await shot('parent-audit');
 const after=await get(parent,'/children/'+account.child_id+'/overview?compact=true');
 assert.equal(after.plan.daily_active_seconds,preRead.plan.daily_active_seconds,'parent_read_must_not_create_child_time');
 const afterUnit=await get(parent,'/units/'+state.unit_id);
 assert.equal(afterUnit.questions.reduce((s,q)=>s+q.attempts.length,0),u.questions.reduce((s,q)=>s+q.attempts.length,0),'parent_read_must_not_create_answers');
 checks.push('actual_parent_short_brief_and_readonly_no_child_time_or_answers');
 phase='mobile_parent_form';await page.setViewportSize({width:390,height:1000});await open('/child/'+account.child_id);
 // Read-only baseline and generated unit stay available for a native continuation.
 page=childPage;await open('/learn/'+account.child_id);await shot('learning-list');
 assert.equal(await page.getByText('01.01.1970',{exact:true}).count(),0,'invalid_epoch_hidden');
 assert.equal(await page.getByText('ready',{exact:true}).count(),0,'raw_state_hidden');
 checks.push('learning_list_no_internal_states_or_epoch');
 state.phase='web_passed_native_pending';await save();
 const report={success:true,checks,source_commit:health.source_commit,actual_ocr_jobs:account.image_paths.length,actual_package_jobs:1,actual_tutor_jobs:state.followup_id?2:1,actual_public_flutter:true,javascript_errors:errors.length,physical_audio_observed:false};
 assert.equal(errors.length,0,'javascript_errors');
 await writeFile(artifacts+'report-review-web-result.json',JSON.stringify(report)+'\n');console.log(JSON.stringify(report));
}catch(error){if(page)await shot('failure').catch(()=>{});console.log(JSON.stringify({success:false,phase,error:String(error.message).slice(0,140)}));process.exitCode=1;}finally{await browser?.close();}
