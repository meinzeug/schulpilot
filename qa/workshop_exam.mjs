// A real reserved workshop exam through public Flutter UI, only our own fixture.
// Failed jobs/checkpoints stay visible; there is no automatic generation retry.
import assert from 'node:assert/strict';
import {chromium} from 'playwright';
import {readFile, writeFile, chmod} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';

const base = 'https://schulpilot.dorfspy.de';
const dir = fileURLToPath(new URL('../artifacts/', import.meta.url));
const privateFile = dir + '.school-day-qa-account.json';
const headers = {'X-Schulpilot-Request': '1', 'X-Schulpilot-Capabilities': 'language-v1'};
const pairs = [['apple','Apfel'],['school','Schule'],['friend','Freund'],['pencil','Bleistift'],
  ['notebook','Heft'],['classroom','Klassenzimmer'],['breakfast','Frühstück'],['homework','Hausaufgaben'],
  ['playground','Spielplatz'],['water bottle','Trinkflasche']];
let account, state, browser, page, child, parent, phase = 'initial', createdHere = false;
const checks = [], errors = [], posts = [];
const button = name => page.getByRole('button', {name, exact: true});
async function checkpoint(value) {
  phase = value; state.phase = value; account.workshop_exam_qa = state;
  await writeFile(privateFile, JSON.stringify(account) + '\n', {mode:0o600});
  await chmod(privateFile, 0o600);
  console.log(JSON.stringify({workshop_exam_phase:value}));
}
async function get(context, route) {
  const r = await context.request.get(base + '/api' + route, {headers});
  assert.equal(r.status(), 200, 'own_api_read_failed'); return r.json();
}
async function open(route) {
  await page.goto(base + route, {waitUntil:'domcontentloaded', timeout:90000});
  await page.waitForSelector('flutter-view', {timeout:90000});
  await page.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(n => n.click()));
  await page.waitForTimeout(400);
}
async function reveal(locator, modal=false) {
  const target = locator.first();
  for (let i=0;i<35;i++) {
    const box = await target.count() ? await target.boundingBox().catch(()=>null) : null;
    const top = modal?0:65, bottom = modal?0:page.url().includes('/unit/')?8:85;
    if (box && box.width>0 && box.y>=top && box.y+box.height<page.viewportSize().height-bottom) return target;
    await page.mouse.move(page.viewportSize().width-25,page.viewportSize().height-150);
    await page.mouse.wheel(0,box && box.y<top?-400:400); await page.waitForTimeout(140);
  }
  throw new Error('visible_workshop_control_missing');
}
async function tap(locator,modal=false) {
  const target = await reveal(locator,modal), box = await target.boundingBox();
  await page.mouse.click(box.x+box.width/2,box.y+box.height/2); await page.waitForTimeout(220);
}
async function type(locator,value) {
  const target=await reveal(locator); await target.click({position:{x:18,y:18}});
  await page.waitForTimeout(180); await page.keyboard.press('Control+A');
  await page.keyboard.type(value,{delay:10}); assert(await target.inputValue()===value,'own_editor_did_not_receive_input');
}
async function tapResponse(locator,route,status) {
  const waiting=page.waitForResponse(r=>new URL(r.url()).pathname==='/api'+route && r.request().method()==='POST',{timeout:45000});
  waiting.catch(()=>{}); await tap(locator); const r=await waiting;
  assert.equal(r.status(),status,'own_ui_post_failed'); return r.json();
}
async function pollProject() {
  for (let i=0;i<100;i++) {
    const row=await get(child,'/children/'+account.child_id+'/language-projects/'+state.project_id);
    assert.notEqual(row.status,'failed','workshop_provider_failed_no_auto_retry');
    if(row.status==='ready') return row;
    await page.waitForTimeout(2000);
  }
  throw new Error('bounded_workshop_wait_expired');
}

try {
  assert(process.argv.includes('--run'),'explicit_run_required');
  const expected=process.argv[process.argv.indexOf('--expected-commit')+1];
  assert.match(expected??'',/^[a-f0-9]{40}$/,'verified_release_commit_required');
  account=JSON.parse(await readFile(privateFile,'utf8')); state=account.workshop_exam_qa??{};
  assert(account.normal_account && account.verified && /\+schulpilot-normal-qa-[a-f0-9]{12}@/.test(account.credentials?.parent_username??''),'own_regular_artificial_family_required');
  browser=await chromium.launch({headless:true,executablePath:'/opt/google/chrome/chrome',args:['--no-sandbox']});
  parent=await browser.newContext({viewport:{width:1280,height:1000}});
  child=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true});
  const health=await parent.request.get(base+'/api/health');
  assert.equal((await health.json()).source_commit,expected,'only_fixed_release_may_run_this_probe');
  const login=await parent.request.post(base+'/api/auth/login',{headers,data:{username:account.credentials.parent_username,password:account.credentials.parent_password}});
  assert.equal(login.status(),200); assert.equal((await login.json()).user.id,account.user.id);
  if(!state.import_id) {
    const r=await parent.request.post(base+'/api/children/'+account.child_id+'/vocabulary/imports',{
      headers:{...headers,'Idempotency-Key':'owned-workshop-exam-words-001'},
      data:{target_locale:'en-GB',title:'Künstliche Schulwörter · Prüfmodus',pairs:pairs.map(([word,meaning])=>({word,meaning})),language_confirmed:true}});
    assert.equal(r.status(),201); state.import_id=(await r.json()).id; await checkpoint('manual_artificial_words_staged');
  }
  const imported=await get(parent,'/children/'+account.child_id+'/vocabulary/imports/'+state.import_id);
  if(imported.status==='review') {
    const r=await parent.request.post(base+'/api/children/'+account.child_id+'/vocabulary/imports/'+state.import_id+'/confirm',{
      headers,data:{target_locale:'en-GB',language_confirmed:true,pairs:imported.pairs}});
    assert.equal(r.status(),200);
  }
  page=await child.newPage(); page.on('pageerror',()=>errors.push('runtime_error'));
  page.on('request',r=>{if(r.method()==='POST' && new URL(r.url()).pathname.endsWith('/language-projects'))posts.push('project');});
  await checkpoint('own_child_login'); await open('/login');
  await type(page.getByRole('textbox',{name:'E-Mail oder Benutzername',exact:true}),account.credentials.child_username);
  await type(page.getByLabel('Passwort',{exact:true}),account.credentials.child_password);
  const signed=await tapResponse(button('Anmelden'),'/auth/login',200);
  assert.equal(signed.user.child_id,account.child_id); await page.waitForURL(base+'/app');
  if(!state.project_id) {
    await checkpoint('explicit_exam_ui_action'); await open('/language-projects/'+account.child_id);
    await tap(page.getByText('Wörter im Zusammenhang',{exact:true}));
    await tap(page.getByText('Probe mit verdeckten Lösungen',{exact:true}),true);
    await type(page.getByRole('textbox',{name:'Dein konkretes Lernziel'}),'Prüfe meine Schulwörter mit eindeutigen Wortlücken. Keine freien Sätze.');
    for(const [word] of pairs) await tap(page.getByLabel(word,{exact:true}).or(page.getByText(word,{exact:true})));
    const project=await tapResponse(button('Mein Lernprojekt vorbereiten'),'/children/'+account.child_id+'/language-projects',202);
    createdHere=true;
    state.project_id=project.id; await checkpoint('one_reserved_exam_queued');
  }
  const project=await pollProject(); state.unit_id=project.unit_id;
  assert.equal(project.mode,'exam'); assert(!Object.hasOwn(project.result,'source_excerpt'));
  checks.push('actual_codex_exam_ready_after_single_explicit_ui_request');
  let unit=await get(child,'/units/'+state.unit_id);
  assert(unit.questions.length>=2 && unit.questions.length<=5);
  assert(unit.questions.every(q=>!Object.hasOwn(q,'answer') && !Object.hasOwn(q,'accepted') && !Object.hasOwn(q.language,'evaluation_policy')));
  checks.push('solutions_and_exam_review_hidden_before_attempt');
  await open('/language-projects/'+account.child_id+'?project='+state.project_id);
  await tap(button('Mit den Aufgaben üben'));
  await page.waitForURL(base+'/unit/'+state.unit_id);
  if(unit.status!=='active') await tapResponse(button(unit.status==='paused'?'Lernen fortsetzen':'Einheit starten'),'/units/'+unit.id+'/start',200);
  const q=unit.questions.find(q=>q.attempts.length===0);
  if(q) {
    const words=await get(child,'/children/'+account.child_id+'/vocabulary?page_size=50');
    const word=words.items.find(w=>w.id===q.language.vocabulary_item_id);
    assert(word && q.language.task_kind==='context_gap','probe_requires_known_closed_word_target');
    if(q.type==='choice') await tap(page.getByText(word.word,{exact:true}));
    else await type(page.getByRole('textbox',{name:/^Deine Antwort/}),word.word);
    const answer=await tapResponse(button('Antwort prüfen'),'/units/'+unit.id+'/questions/'+q.id+'/answer',200);
    assert.equal(answer.outcome,'correct'); state.web_attempt_id=answer.attempt_id;
    await open('/unit/'+unit.id); unit=await get(child,'/units/'+unit.id);
    assert.equal(unit.pending_feedback?.attempt_id,state.web_attempt_id);
    checks.push('actual_answer_saved_and_feedback_restored_after_reload');
  }
  const childProgress=await get(child,'/children/'+account.child_id+'/learning-progress');
  assert.deepEqual(await get(parent,'/children/'+account.child_id+'/learning-progress'),childProgress);
  assert.equal(childProgress.totals.practiced_tasks,1);
  assert.equal(posts.length,Number(createdHere));
  checks.push('child_parent_progress_consistent');
  for(const width of [390,1280]) {
    await page.setViewportSize({width,height:900}); await open('/language-projects/'+account.child_id+'?project='+state.project_id);
    await page.screenshot({path:dir+'workshop-exam-web-'+width+'.png'});
  }
  assert.equal(errors.length,0); await checkpoint('web_passed_keep_for_native');
  await writeFile(dir+'workshop-exam-web-result.json',JSON.stringify({success:true,checks,questions:unit.questions.length,project_posts:posts.length,additional_import_ai_calls:0,runtime_errors:0})+'\n');
  console.log(JSON.stringify({success:true,checks}));
} catch(error) {
  await writeFile(dir+'workshop-exam-web-result.json',JSON.stringify({success:false,phase,error:process.argv.includes('--run')?error.message:'explicit_run_required'})+'\n');
  console.error(JSON.stringify({success:false,phase,error:error.message})); process.exitCode=1;
} finally {await browser?.close();}
