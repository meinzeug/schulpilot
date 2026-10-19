// Actual public child journey, isolated fixed synthetic household only.
import assert from 'node:assert/strict';
import {readFile, writeFile, chmod} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright';
const root=fileURLToPath(new URL('../',import.meta.url)), base='https://schulpilot.dorfspy.de';
const art=path.join(root,'artifacts');
const fixture=JSON.parse(await readFile(path.join(art,'.role-simulation-account.json'),'utf8'));
const stateFile=path.join(art,'.role-child-state.json');
let state={}; try {state=JSON.parse(await readFile(stateFile,'utf8'));}catch(e){if(e.code!=='ENOENT')throw e;}
const report={synthetic_only:true,external_ai_calls:0,checks:[],issues:[],coverage_gaps:[],browser:'Chrome Playwright',started_at:new Date().toISOString()};
const headers={'X-Schulpilot-Request':'1','X-Schulpilot-Capabilities':'language-v1'};
const browser=await chromium.launch({headless:true,executablePath:'/opt/google/chrome/chrome',args:['--no-sandbox']});
const ctx=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true});
const page=await ctx.newPage(); let phase='login', intent=null; const errors=[], failures=[], mutations=[];
page.on('pageerror',e=>errors.push({phase,name:e.name}));
page.on('response',r=>{const u=new URL(r.url());if(u.pathname.startsWith('/api/')&&r.status()>=400)failures.push({phase,status:r.status(),path:u.pathname.replace(/[a-f0-9]{32}/g,':id')});});
await ctx.route('**/api/**',async route=>{const r=route.request(),u=new URL(r.url()),p=u.pathname,m=r.method();if(['GET','HEAD','OPTIONS'].includes(m))return route.continue();
 const unitPrefix=state.unit_id?'/api/units/'+state.unit_id:'';
 const suffix=unitPrefix&&p.startsWith(unitPrefix+'/')?p.slice(unitPrefix.length):'';
 const ownUnitWrite=m==='PUT'&&suffix==='/learning-session/draft'||m==='POST'&&(/^(?:\/(?:start|pause|heartbeat|introduction)|\/learning-session\/action|\/feedback\/acknowledge)$/.test(suffix)||/^\/questions\/(?:sum|reduce|parts|name)\/(?:answer|hint)$/.test(suffix));
 const authWrite=m==='POST'&&['/api/auth/login','/api/auth/logout'].includes(p);
 const safe=authWrite||!process.argv.includes('--read-only')&&(ownUnitWrite||intent===m+' '+p);
 if(!safe){report.issues.push({phase,kind:'blocked_unintended_mutation',path:p.replace(/[a-f0-9]{32}/g,':id')});return route.abort('blockedbyclient');}
 mutations.push({phase,method:m,path:p.replace(/[a-f0-9]{32}/g,':id')});return route.continue();});
const b=n=>page.getByRole('button',{name:n,exact:true});
function check(x,label){assert(x,label);report.checks.push(label);}
async function save(){await writeFile(stateFile,JSON.stringify(state),{mode:0o600});await chmod(stateFile,0o600);}
async function enable(){await page.waitForSelector('flutter-view',{timeout:90000});await page.waitForTimeout(1200);await page.locator('flt-semantics-placeholder').evaluateAll(ns=>ns.forEach(n=>n.click()));for(const q of await page.locator('flt-semantics-placeholder').all()){const z=await q.boundingBox();if(z&&z.width>1&&z.height>1)await page.mouse.click(z.x+z.width/2,z.y+z.height/2);}await page.waitForTimeout(500);}
async function open(route){await page.goto(base+route,{waitUntil:'domcontentloaded',timeout:90000});await enable();}
async function reveal(loc,modal=false){const l=loc.first();for(let i=0;i<30;i++){const z=await l.count()?await l.boundingBox().catch(()=>null):null;const v=page.viewportSize(), inRound=new URL(page.url()).pathname.startsWith('/unit/');if(z&&z.width>0&&z.height>0&&z.y>=(inRound?0:modal?3:65)&&z.y+Math.min(z.height,v.height-180)<=v.height-(modal||inRound?3:90))return l;await page.mouse.move(v.width-24,v.height-160);await page.mouse.wheel(0,!z&&i===0?-18000:z&&z.y<65?-400:400);await page.waitForTimeout(180);}throw new Error('control_not_reachable');}
async function tap(loc,modal=false){const l=await reveal(loc,modal),z=await l.boundingBox();await page.mouse.click(z.x+z.width/2,z.y+z.height/2);await page.waitForTimeout(300);}
async function type(loc,value){const l=await reveal(loc);await l.click({position:{x:20,y:20}});await page.waitForTimeout(150);await page.keyboard.press('Control+A');await page.keyboard.type(value,{delay:5});assert.equal(await l.inputValue(),value);}
async function readField(label){const l=await reveal(page.getByRole('textbox',{name:label,exact:true}));await l.click({position:{x:20,y:20}});await page.waitForTimeout(200);return l.inputValue();}
async function dump(label){if(new URL(page.url()).pathname==='/login')return '';const t=await page.locator('flt-semantics-host').innerText();await writeFile(path.join(art,'role-child-'+label+'.txt'),t,{mode:0o600});await page.screenshot({path:path.join(art,'role-child-'+label+'.png')});await chmod(path.join(art,'role-child-'+label+'.png'),0o600);return t;}
async function get(route){const r=await ctx.request.get(base+'/api'+route);assert.equal(r.status(),200,'own_get_failed');return r.json();}
async function clickResponse(method,route,action,status=200){const p=page.waitForResponse(r=>r.request().method()===method&&new URL(r.url()).pathname==='/api'+route,{timeout:45000});p.catch(()=>{});await action();const r=await p;assert.equal(r.status(),status,'normal_ui_response_failed');return r.json();}
try{
 const health=await (await fetch(base+'/api/health')).json();report.version=health.version;report.source_commit=health.source_commit;report.release=health.release;
 await open('/login');await type(page.getByRole('textbox',{name:'E-Mail oder Benutzername',exact:true}),fixture.credentials.child_username);await type(page.getByLabel('Passwort',{exact:true}),fixture.credentials.child_password);
 const login=await clickResponse('POST','/auth/login',()=>tap(b('Anmelden')));check(login.user.role==='child'&&login.user.child_id===fixture.child_id&&login.user.synthetic===true,'independent_child_login');
 await page.waitForURL(base+'/app',{timeout:30000});await page.waitForTimeout(700);await dump('today-initial');
 const cookie=(await ctx.cookies()).find(c=>c.name==='sp_session');check(cookie?.secure&&cookie.httpOnly&&cookie.sameSite==='Strict','secure_web_session');
 const material=await get('/materials/'+fixture.material_id);assert.equal(material.child_id,fixture.child_id);assert.equal(material.synthetic,true);state.material_id=material.id;await save();
 phase='review';await open('/material/'+material.id);await dump('source-initial');
 // Discovery mode safely stops before any generation and preserves normal UI state.
 if(process.argv.includes('--read-only')){
  for(const width of [320,390,1440]){phase='layout_'+width;await page.setViewportSize({width,height:844});await open('/app');await b('Ich brauche Hilfe').waitFor();await dump('home-'+width);assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+2));check(true,'home_layout_'+width+'_no_document_horizontal_overflow');}
  await page.setViewportSize({width:390,height:844});await open('/app');phase='help_chooser';await tap(b('Ich brauche Hilfe'));for(const label of ['Etwas erklären lassen','Eine Aufgabe verstehen','Etwas funktioniert nicht','Meine Eltern fragen']){await page.getByText(label,{exact:true}).waitFor();}await dump('help-chooser');check(true,'help_chooser_offers_learning_technical_and_explicit_parent_help');await page.keyboard.press('Escape');
  phase='notification_bell';await open('/app');await tap(b('Benachrichtigungen'),true);await page.waitForURL(base+'/notifications');await page.waitForTimeout(500);await dump('notifications');check(true,'notification_bell_opens_in_app_inbox_without_push_opt_in');
  phase='notebooks';await open('/library/'+fixture.child_id);await page.getByRole('button',{name:/^Mathematik,.*Hefter öffnen$/s}).waitFor();await dump('notebooks-all');const shelves=await get('/children/'+fixture.child_id+'/subjects');check(shelves.items.length>=16,'fixed_subject_shelf_available');
  await tap(b('Meine Fächer'));await page.waitForTimeout(400);const ownCards=page.getByRole('button',{name:/Hefter öffnen$/s});assert.equal(await ownCards.count(),1);check(true,'my_subjects_filter_hides_all_empty_notebooks');await dump('notebooks-filtered');await tap(ownCards);await page.waitForTimeout(400);await dump('notebook-demo-page');check(true,'subject_cover_opens_own_saved_source_album');
  phase='vocabulary';await open('/vocabulary/'+fixture.child_id);await dump('vocabulary');check(true,'vocabulary_page_reachable_in_regular_child_workspace');
  phase='account';await open('/settings');await dump('settings');check(true,'child_account_settings_render');
  const final=await get('/units/'+state.unit_id);assert.equal(final.status,'completed');report.answer_count=final.questions.reduce((n,q)=>n+q.attempts.length,0);assert.equal(report.answer_count,5);report.question_count=final.questions.length;check(true,'navigation_did_not_add_answers');
  check(mutations.every(m=>m.path==='/api/auth/login'),'read_only_navigation_did_not_write_learning_data');report.success=true;
 }else if(process.argv.includes('--discover')){await page.waitForTimeout(1000);await writeFile(path.join(art,'role-child-controls.json'),JSON.stringify(await page.getByRole('button').evaluateAll(ns=>ns.map(n=>({label:n.getAttribute('aria-label'),text:n.innerText,rect:n.getBoundingClientRect().toJSON()})))),{mode:0o600});report.success=true;}
 else {
  if(!material.confirmed){intent='PUT /api/materials/'+material.id+'/confirm';const confirmed=await clickResponse('PUT','/materials/'+material.id+'/confirm',()=>tap(b('Stimmt, weiter')));intent=null;check(confirmed.confirmed===true,'explicit_source_confirmation_without_checkbox');}
  await page.waitForTimeout(1000);await dump('source-confirmed');
  if(!state.unit_id){
   const launch=page.getByRole('button',{name:/^(Jetzt lernen|Lerneinheit für das Kind vorbereiten)$/});
   assert(!state.generation_attempted,'uncertain_previous_generation_requires_operator_review');state.generation_attempted=true;await save();await launch.first().waitFor({timeout:30000});intent='POST /api/children/'+fixture.child_id+'/units';
   const job=await clickResponse('POST','/children/'+fixture.child_id+'/units',()=>tap(launch),202);intent=null;state.job_id=job.id;await save();
   for(let i=0;i<90;i++){const j=await get('/jobs/'+state.job_id);assert.notEqual(j.status,'failed','fixed_demo_preparation_failed');if(j.status==='completed'){state.unit_id=j.result.unit_id;await save();break;}await page.waitForTimeout(500);}
   assert(state.unit_id,'fixed_demo_preparation_timeout');check(true,'fixed_synthetic_round_prepared_by_explicit_ui_action');
  }
  await open('/unit/'+state.unit_id);await dump('unit-initial');
  phase='start_round';let unit=await get('/units/'+state.unit_id);assert(unit.child_id===fixture.child_id&&unit.synthetic===true&&unit.provider==='synthetic','only_fixed_demo_unit');
  if(!['active','completed'].includes(unit.status)){const startName=unit.status==='paused'?'Lernen fortsetzen':'Einheit starten';await clickResponse('POST','/units/'+state.unit_id+'/start',()=>tap(b(startName)));check(true,'explicit_start_or_resume');}
  unit=await get('/units/'+state.unit_id);
  if(!unit.introduction_seen){if(unit.learning_session?.action?.kind==='check_prior'){await clickResponse('POST','/units/'+state.unit_id+'/learning-session/action',()=>tap(b('Erst selbst probieren')));check(true,'prior_knowledge_check_chosen_by_child');}else{await clickResponse('POST','/units/'+state.unit_id+'/introduction',()=>tap(b('Weiter zu den Übungen')));check(true,'understand_then_practice');}}
  await page.waitForTimeout(600);await dump('first-question');
  await writeFile(path.join(art,'role-child-questions.json'),JSON.stringify((await get('/units/'+state.unit_id)).questions),{mode:0o600});
  if(process.argv.includes('--start-only')){report.success=true;}else{
   const closed=q=>q.attempts.length>=3||q.attempts.some(a=>['correct','uncertain'].includes(a.outcome));
   async function ack(){await tap(page.getByRole('button',{name:/^(Noch einmal versuchen|Weiter|Ergebnis ansehen)$/}));await page.waitForTimeout(350);}
   unit=await get('/units/'+state.unit_id);
   if(unit.pending_feedback){await ack();unit=await get('/units/'+state.unit_id);}
   for(const original of unit.questions){
    let latest=await get('/units/'+state.unit_id),q=latest.questions.find(x=>x.id===original.id);if(closed(q))continue;
    phase='answer_'+q.type;
    if(q.id==='sum'&&q.attempts.length===0){
     await tap(page.getByRole('radio').nth(1));const wrong=await clickResponse('POST','/units/'+state.unit_id+'/questions/'+q.id+'/answer',()=>tap(b('Antwort prüfen')));assert.equal(wrong.outcome,'incorrect');check(true,'deliberate_synthetic_denominator_error_rejected');await dump('wrong-feedback');
     await page.reload({waitUntil:'domcontentloaded'});await enable();check((await page.locator('flt-semantics-host').innerText()).includes('Noch nicht ganz'),'saved_feedback_survives_reload');await ack();
     const hint=await clickResponse('POST','/units/'+state.unit_id+'/questions/'+q.id+'/hint',()=>tap(b('Hilfe')));assert(typeof hint.hint==='string'&&hint.hint.length>0);check(true,'explicit_help_gives_specific_saved_hint');await dump('hint');
    }
    if(q.type==='choice'){await tap(page.getByRole('radio').nth(0));}
    else if(q.type==='gap'){
     if(state.draft_saved&&!state.draft_pause_checked){assert.equal(await readField('Zähler'),'1');assert.equal(await readField('Nenner'),'2');state.draft_pause_checked=true;await save();check(true,'fraction_draft_survives_pause_reload_and_new_login');}
     await type(page.getByRole('textbox',{name:'Zähler',exact:true}),'1');await type(page.getByRole('textbox',{name:'Nenner',exact:true}),'2');
     if(!state.draft_pause_checked){await page.waitForTimeout(1600);await clickResponse('POST','/units/'+state.unit_id+'/pause',()=>tap(b('Pause')));state.draft_saved=true;await save();await dump('paused-draft');await page.reload({waitUntil:'domcontentloaded'});await enable();await clickResponse('POST','/units/'+state.unit_id+'/start',()=>tap(b('Lernen fortsetzen')));for(let i=0;i<25;i++){if(await page.getByRole('textbox',{name:'Zähler',exact:true}).inputValue()==='1'&&await page.getByRole('textbox',{name:'Nenner',exact:true}).inputValue()==='2')break;await page.waitForTimeout(150);}assert.equal(await readField('Zähler'),'1');assert.equal(await readField('Nenner'),'2');state.draft_pause_checked=true;await save();check(true,'fraction_draft_survives_pause_and_reload');}
    }else if(q.type==='match'){
     await tap(b('Was passt dazu?').first());await tap(page.getByRole('radio',{name:'Anzahl ausgewählter Teile',exact:true}),true);
     await tap(b('Was passt dazu?').first());await tap(page.getByRole('radio',{name:'Anzahl aller gleich großen Teile',exact:true}),true);
    }else if(q.type==='short'){await type(page.getByRole('textbox',{name:'Deine Antwort',exact:true}),'Nenner');}
    await dump('answer-'+q.type);const right=await clickResponse('POST','/units/'+state.unit_id+'/questions/'+q.id+'/answer',()=>tap(b('Antwort prüfen')));assert.equal(right.outcome,'correct');check(true,'correct_'+q.type+'_answer_saved_with_feedback');await dump('feedback-'+q.type);await ack();
   }
   const final=await get('/units/'+state.unit_id);assert.equal(final.status,'completed');assert.equal(final.questions.reduce((n,q)=>n+q.attempts.length,0),5);assert.equal(final.questions[0].attempts[1].assisted,true);assert(final.questions.slice(1).every(q=>q.attempts[0].assisted===false));state.round_complete=true;await save();check(true,'completed_round_with_five_preserved_attempts_and_honest_support');await dump('completed');report.answer_count=5;report.question_count=4;report.minimum_time_achieved=false;report.success=true;
  }

 }

}catch(e){await dump('failure-private').catch(()=>{});report.success=false;report.failed_phase=phase;report.failure=e instanceof assert.AssertionError?e.message.split('\n')[0]:e.message==='control_not_reachable'?e.message:'browser_journey_incomplete';process.exitCode=1;}
finally{state.checks=[...new Set([...(state.checks||[]),...report.checks])];await save();report.checks=state.checks;report.runtime_errors=errors;report.expected_unauthenticated_reads=failures.filter(f=>f.phase==='login'&&f.path==='/api/auth/me'&&f.status===401);report.http_failures=failures.filter(f=>!(f.phase==='login'&&f.path==='/api/auth/me'&&f.status===401));report.coverage_gaps=['Only a fixed explicitly synthetic demonstration source; no new camera/photo upload, crop or live OCR was exercised.','No external AI inference was requested by this journey; no model-quality acceptance can be inferred.','Browser viewport checks are not physical Android device tests.','Actual sound, microphone capture and spoken output were not observed.','Actual screenreader output and 200-percent text scaling were not exercised in this browser journey.','Only the fixed mathematics round was answered; no cross-subject end-to-end coverage is claimed.'];report.mutations=mutations;await writeFile(path.join(art,'role-child-result.json'),JSON.stringify(report,null,2)+'\n',{mode:0o600});await ctx.request.post(base+'/api/auth/logout',{headers}).catch(()=>{});await browser.close();console.log(JSON.stringify(report));}
