// Ordinary photo wizard + vocabulary + real provider, only our artificial family.
// --run performs explicit UI actions. Failed jobs are never retried implicitly.
// The protected account/checkpoints survive interruption for a bounded resume.
import {chromium} from 'playwright';
import {readFile, writeFile, chmod, realpath} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const base = 'https://schulpilot.dorfspy.de';
const artifacts = fileURLToPath(new URL('../artifacts/', import.meta.url));
const privateFile = path.join(artifacts, '.school-day-qa-account.json');
const headers = {'X-Schulpilot-Request': '1', 'X-Schulpilot-Capabilities': 'language-v1'};
const expected = new Map([['Apfel','apple'],['Schule','school'],['Hund','dog'],['Buch','book'],['Freund','friend']]);
class QaFailure extends Error {}
function check(value, code) { if (!value) throw new QaFailure(code); }
let account, state, browser, child, parent, page;
let phase = 'offline';
const errors = [], mutations = [];
const button = name => page.getByRole('button', {name, exact: true});
async function checkpoint(value) {
  phase = value;
  state.phase = value;
  account.language_qa = state;
  await writeFile(privateFile, JSON.stringify(account) + '\n', {mode:0o600});
  await chmod(privateFile, 0o600);
  console.log(JSON.stringify({language_qa_phase:value}));
}
async function get(context, route) {
  const response = await context.request.get(base + '/api' + route, {headers});
  check(response.status() === 200, 'owned_api_read_failed');
  return response.json();
}
async function open(route) {
  await page.goto(base + route, {waitUntil:'domcontentloaded',timeout:90000});
  await page.waitForSelector('flutter-view',{timeout:90000});
  await page.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(n => n.click()));
  await page.waitForTimeout(350);
}
async function reveal(locator, modal=false) {
  const target = locator.first();
  for(let i=0;i<35;i++) {
    const box = await target.count() ? await target.boundingBox().catch(()=>null) : null;
    const bottom=modal?0:(page.url().includes('/unit/')?8:85);
    if(box && box.width>0 && box.y>=(modal?0:70) && box.y+box.height<page.viewportSize().height-bottom) return target;
    await page.mouse.move(modal?page.viewportSize().width/2:page.viewportSize().width-20,page.viewportSize().height-150);
    await page.mouse.wheel(0,box && box.y<70 ? -420 : 420);
    await page.waitForTimeout(150);
  }
  if(phase!=='own_child_login') console.log(JSON.stringify({missing_control:target.toString()}));
  throw new QaFailure('visible_ui_control_missing');
}
async function tap(locator, modal=false) {
  const target = await reveal(locator,modal), box=await target.boundingBox();
  await page.mouse.click(box.x+box.width/2,box.y+box.height/2);
  await page.waitForTimeout(180);
}
async function type(locator,value,modal=false) {
  const input=await reveal(locator,modal);
  await input.click({position:{x:18,y:18}});
  await page.waitForTimeout(250);
  await page.keyboard.press('Control+A');
  await page.keyboard.type(value,{delay:20});
  await page.waitForTimeout(150);
  check(await input.inputValue()===value,'editor_did_not_receive_input');
}
async function tapResponse(locator,route,method,status,modal=false) {
  const waiting=page.waitForResponse(r=>new URL(r.url()).pathname==='/api'+route && r.request().method()===method,{timeout:45000});
  waiting.catch(()=>{});
  await tap(locator,modal);
  const response=await waiting;
  check(response.status()===status,'explicit_ui_request_failed_'+response.status());
  return response.json();
}
async function waitFor(read, predicate) {
  for(let i=0;i<100;i++) {
    const result=await read();
    check(result.status!=='failed','provider_job_failed_no_automatic_retry');
    if(predicate(result))return result;
    await page.waitForTimeout(2000);
  }
  throw new QaFailure('bounded_processing_wait_expired');
}
async function shot(name) { await page.screenshot({path:path.join(artifacts,'language-'+name+'.png')}); }

if(!process.argv.includes('--run')) {
  console.log(JSON.stringify({ready:true,requires:'prepare_language_smoke.py then --run',synthetic_only:true}));
  process.exit(0);
}
try {
  account=JSON.parse(await readFile(privateFile,'utf8')); state=account.language_qa ?? {};
  check(account.normal_account && account.verified && /\+schulpilot-normal-qa-[a-f0-9]{12}@/.test(account.credentials?.parent_username??''),'owned_regular_artificial_household_required');
  check(await realpath(state.image)===path.join(artifacts,'language-school-page.jpg'),'only_original_artificial_english_page_allowed');
  browser=await chromium.launch({headless:true,executablePath:'/opt/google/chrome/chrome',args:['--no-sandbox']});
  child=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true});
  parent=await browser.newContext({viewport:{width:1280,height:1000}});
  for(const context of [child,parent])context.on('page',p=>p.on('pageerror',()=>errors.push('runtime_error')));
  const parentLogin=await parent.request.post(base+'/api/auth/login',{headers,data:{username:account.credentials.parent_username,password:account.credentials.parent_password}});
  check(parentLogin.status()===200,'own_parent_login_failed');
  check((await parentLogin.json()).user.id===account.user.id,'own_parent_identity_mismatch');
  if(process.argv.includes('--retry-failed-context')) {
    check(state.project_id && !state.context_retry_used,'only_one_explicit_context_retry_allowed');
    // This flag is a deliberate post-fix QA action, never a runtime retry.
    const old=await get(parent,'/children/'+account.child_id+'/language-projects/'+state.project_id);
    check(old.status==='failed','previous_context_project_must_remain_failed');
    state.failed_context_ids=[...(state.failed_context_ids??[]),state.project_id];
    state.project_id=null; state.context_retry_used=true;
  }
  if(!state.preferences_set) {
    const prefs=await parent.request.put(base+'/api/children/'+account.child_id+'/preferences',{headers,data:{weekdays:[0,1,2,3,4,5,6],daily_minutes:20,weekly_minutes:20,session_minutes:5,break_minutes:5,timezone:'Europe/Berlin'}});
    check(prefs.status()===200,'own_parent_preferences_failed'); state.preferences_set=true;
  }
  page=await child.newPage();
  page.on('request',request=>{if(!['GET','HEAD','OPTIONS'].includes(request.method()))mutations.push(new URL(request.url()).pathname);});
  await checkpoint('own_child_login');
  await open('/login');
  await type(page.getByRole('textbox',{name:'E-Mail oder Benutzername',exact:true}),account.credentials.child_username);
  await type(page.getByLabel('Passwort',{exact:true}),account.credentials.child_password);
  const login=await tapResponse(button('Anmelden'),'/auth/login','POST',200);
  check(login.user.child_id===account.child_id,'own_child_identity_mismatch');
  await page.waitForURL(base+'/app');
  if(!state.material_id) {
    await checkpoint('normal_photo_wizard');
    await open('/after-school/'+account.child_id);
    let day=(await waitFor(()=>get(child,'/children/'+account.child_id+'/school-day/today'),r=>r.day!=null)).day;
    check(day && day.child_id===account.child_id && day.pages.length<=1,'own_photo_day_mismatch');
    state.day_id=day.id; await checkpoint('own_photo_day');
    if(day.pages.length===0) {
      const picker=page.waitForEvent('filechooser');
      await tap(button('Fotos auswählen'));
      await (await picker).setFiles(state.image);
      await tap(button('Zuschnitt übernehmen'),true);
      day=await waitFor(()=>get(child,'/school-days/'+state.day_id),d=>d.pages.length===1);
    }
    if(day.pages[0].status==='uploaded') await tap(button('Fotos abgeben'));
    day=await waitFor(()=>get(child,'/school-days/'+state.day_id),d=>d.pages[0] && ['review','confirmed'].includes(d.pages[0].status));
    const material=day.pages[0];
    check(!material.synthetic && material.extraction_provider==='codex','normal_photo_did_not_use_actual_codex');
    check([...expected].every(([meaning,word])=>material.content.includes(word)&&material.content.includes(meaning)),'recognition_lost_artificial_word_pair');
    if(!material.confirmed) await tapResponse(button('Stimmt, weiter'),'/materials/'+material.id+'/confirm','PUT',200);
    state.material_id=material.id; await checkpoint('confirmed_photo_source');
  }
  await open('/material/'+state.material_id);
  await tap(button('Wörter & Sprache üben'));
  if(!state.import_id) {
    await checkpoint('explicit_vocabulary_import');
    await tap(button('Wörter hinzufügen'));
    const queued=await tapResponse(button('Wörter erkennen'),'/children/'+account.child_id+'/vocabulary/imports','POST',201,true);
    state.import_id=queued.id; await checkpoint('vocabulary_import_queued');
  }
  let imported=await waitFor(()=>get(child,'/children/'+account.child_id+'/vocabulary/imports/'+state.import_id),r=>['review','confirmed'].includes(r.status));
  if(imported.status==='review') {
    check([...expected].every(([meaning,word])=>imported.pairs.some(pair=>pair.meaning===meaning&&pair.word===word)),'known_artificial_pairs_missing_requires_review');
    await tap(button('Prüfen'));
    // Grammar examples are not translated vocabulary pairs. If proposed with
    // missing meaning, explicitly omit them through the normal review UI.
    for(let index=imported.pairs.length-1;index>=0;index--) {
      const pair=imported.pairs[index];
      if(expected.get(pair.meaning)!==pair.word) {
        check(!pair.meaning || pair.uncertainty,'unexpected_unambiguous_pair_requires_human_review');
        const remove=page.getByRole('button',{name:'Wort weglassen',exact:true}).nth(index);
        await tap(remove,true); state.omitted_uncertain_rows=(state.omitted_uncertain_rows??0)+1;
      }
    }
    for(const pair of imported.pairs.filter(pair=>expected.get(pair.meaning)===pair.word && pair.uncertainty)) {
      await tap(button('Unklare Stelle geklärt').first(),true);
    }
    await tapResponse(button('Stimmt, Wörter speichern'),'/children/'+account.child_id+'/vocabulary/imports/'+state.import_id+'/confirm','POST',200,true);
  }
  await checkpoint('confirmed_vocabulary');
  const before=await get(parent,'/families/'+account.user.families[0].id+'/usage');
  check(before.calls_used===2+(state.failed_context_ids?.length??0)+Number(!!state.project_id)+Number(!!state.grammar_id)+Number(!!state.writing_id),'unexpected_model_reservations_before_resume');
  if(!state.unit_id) {
    await tap(button('Wörter üben'));
    const round=await tapResponse(button('Runde beginnen'),'/children/'+account.child_id+'/vocabulary/rounds','POST',201,true);
    state.unit_id=round.unit_id; await checkpoint('stored_word_round');
  }
  await open('/unit/'+state.unit_id);
  let unit=await get(child,'/units/'+state.unit_id);
  if(unit.status!=='completed') {
    if(unit.status!=='active') await tapResponse(button(unit.status==='paused'?'Lernen fortsetzen':'Einheit starten'),'/units/'+unit.id+'/start','POST',200);
    if(!unit.introduction_seen) await tapResponse(button('Weiter zu den Übungen'),'/units/'+unit.id+'/introduction','POST',200);
    let disconnected=state.offline_checked===true;
    for(let i=0;i<8;i++) {
      unit=await get(child,'/units/'+state.unit_id);
      const pending=unit.pending_feedback;
      if(pending) {
        await tapResponse(button(unit.status==='completed'?'Ergebnis ansehen':'Weiter'),'/units/'+unit.id+'/feedback/acknowledge','POST',200);
        continue;
      }
      const q=unit.questions.find(q=>!q.attempts.some(a=>['correct','uncertain'].includes(a.outcome))&&q.attempts.length<3);
      if(!q)break;
      check(!Object.hasOwn(q,'answer')&&!Object.hasOwn(q,'accepted')&&!Object.hasOwn(q.language,'evaluation_policy'),'child_solution_key_leak');
      const answer=expected.get(q.language.cue);
      check(answer,'unexpected_artificial_translation_cue');
      await type(page.getByRole('textbox',{name:/^Deine Antwort/}),answer);
      if(!disconnected) {
        await child.setOffline(true); await tap(button('Antwort prüfen'));
        await page.getByText(/Keine Verbindung zu SCHULPILOT/).waitFor();
        await child.setOffline(false); disconnected=true; state.offline_checked=true;
      }
      const answered=await tapResponse(button('Antwort prüfen'),'/units/'+unit.id+'/questions/'+q.id+'/answer','POST',200);
      check(answered.outcome==='correct' && answered.assisted===true,'newly_confirmed_words_must_be_guided_practice');
      const attempt=answered.attempt_id;
      if(!state.feedback_reload_checked) {
        await open('/unit/'+unit.id);
        const resumed=await get(child,'/units/'+unit.id);
        check(resumed.pending_feedback?.attempt_id===attempt,'feedback_reload_lost_or_duplicated_attempt');
        state.feedback_reload_checked=true;
      }
      await tapResponse(button(answered.unit.status==='completed'?'Ergebnis ansehen':'Weiter'),'/units/'+unit.id+'/feedback/acknowledge','POST',200);
    }
  }
  unit=await get(child,'/units/'+state.unit_id);
  check(unit.status==='completed' && unit.questions.length===3,'complete_small_word_round_required');
  const progress=await get(parent,'/children/'+account.child_id+'/learning-progress');
  check(progress.totals.practiced_tasks===3 && progress.totals.assisted_tasks===3,'parent_progress_does_not_match_saved_word_answers');
  const own=await get(child,'/children/'+account.child_id+'/vocabulary');
  const parentWords=await get(parent,'/children/'+account.child_id+'/vocabulary');
  check(JSON.stringify(own.summary)===JSON.stringify(parentWords.summary),'parent_child_vocabulary_summary_mismatch');
  check(own.items.flatMap(item=>item.reviews).every(review=>review.skill==='spelling' && review.stage===0),'guided_spelling_promoted_or_wrong_skill');
  const overview=await get(child,'/children/'+account.child_id+'/overview?compact=true');
  check(overview.plan.goal_required && !overview.plan.daily_goal_met && overview.plan.daily_active_seconds<1200,'estimated_round_minutes_falsely_met_minimum');
  check(overview.plan.voluntary.some(item=>item.kind==='vocabulary'),'word_practice_missing_from_daily_plan');
  await checkpoint('web_word_chain_passed');
  for(const width of [320,390,1280]) {
    await page.setViewportSize({width,height:900}); await open('/vocabulary/'+account.child_id); await shot('words-'+width);
  }
  if(!state.project_id) {
    await checkpoint('explicit_context_project');
    await open('/language-projects/'+account.child_id+'?material='+state.material_id);
    await tap(page.getByLabel('apple',{exact:true}).or(page.getByText('apple',{exact:true})));
    await tap(page.getByLabel('school',{exact:true}).or(page.getByText('school',{exact:true})));
    const project=await tapResponse(button('Mein Lernprojekt vorbereiten'),'/children/'+account.child_id+'/language-projects','POST',202);
    state.project_id=project.id; await checkpoint('context_project_queued');
  }
  const project=await waitFor(()=>get(child,'/children/'+account.child_id+'/language-projects/'+state.project_id),r=>r.status==='ready');
  state.project_unit_id=project.unit_id;
  check(project.result?.generated===true,'context_help_not_labelled_as_generated');
  const contextUnit=await get(child,'/units/'+project.unit_id);
  check(contextUnit.questions.length>=2 && contextUnit.questions.length<=5 && contextUnit.questions.every(q=>q.language.task_kind==='context_gap'),'actual_model_context_tasks_missing');
  if(!state.grammar_id) {
    await checkpoint('explicit_grammar_provider_probe');
    const response=await child.request.post(base+'/api/children/'+account.child_id+'/language-projects',{headers:{...headers,'Idempotency-Key':'owned-grammar-'+state.material_id},data:{
      mode:'grammar',target_locale:'en-GB',item_ids:[own.items.find(item=>item.word==='school').id],material_id:state.material_id,
      goal:'Simple Present aus der bestätigten Heftseite anwenden',draft:'',grammar_topic:'simple_present',grammar_confirmed:true,language_confirmed:true}});
    check(response.status()===202,'grammar_provider_probe_not_queued'); state.grammar_id=(await response.json()).id;
    await checkpoint('grammar_probe_queued');
  }
  const grammar=await waitFor(()=>get(child,'/children/'+account.child_id+'/language-projects/'+state.grammar_id),r=>r.status==='ready');
  const grammarUnit=await get(child,'/units/'+grammar.unit_id);
  check(grammarUnit.questions.every(q=>q.language.skill==='grammar' && q.language.grammar_topic==='simple_present'),'grammar_probe_wrong_target');
  if(!state.writing_id) {
    await checkpoint('explicit_writing_provider_probe');
    const response=await child.request.post(base+'/api/children/'+account.child_id+'/language-projects',{headers:{...headers,'Idempotency-Key':'owned-writing-'+state.material_id},data:{
      mode:'writing_feedback',target_locale:'en-GB',item_ids:[own.items.find(item=>item.word==='school').id],material_id:state.material_id,
      goal:'Meinen eigenen kurzen Englischtext überarbeiten',draft:'I go to school. I like my school.',language_confirmed:true}});
    check(response.status()===202,'writing_provider_probe_not_queued'); state.writing_id=(await response.json()).id;
    await checkpoint('writing_probe_queued');
  }
  const writing=await waitFor(()=>get(child,'/children/'+account.child_id+'/language-projects/'+state.writing_id),r=>r.status==='ready');
  check(writing.result.criteria?.length>=2 && writing.draft==='I go to school. I like my school.','own_draft_or_advisory_criteria_not_preserved');
  await open('/language-projects/'+account.child_id+'?project='+writing.id); await shot('writing-advice');
  const used=await get(parent,'/families/'+account.user.families[0].id+'/usage');
  check(used.calls_used===5+(state.failed_context_ids?.length??0),'unexpected_extra_model_call');
  page=await parent.newPage();
  await open('/vocabulary/'+account.child_id);
  await page.getByText(parentWords.child.display_name+' · Wortschatz',{exact:true}).waitFor();
  await page.getByRole('button',{name:/Vorbereitet · noch nicht begonnen/}).first().waitFor();
  await shot('parent-words-1280');
  await page.setViewportSize({width:390,height:900});
  await shot('parent-words-390');
  check(errors.length===0,'browser_runtime_errors');
  await checkpoint('passed_keep_for_native');
  const report={web:true,photo_pages:1,confirmed_pairs:5,answered_tasks:3,feedback_reload:true,offline_retry:true,
    parent_child_consistent:true,parent_browser_view:true,minimum_uses_actual_seconds:true,actual_provider:'codex',reserved_calls:used.calls_used,
    generated_context_tasks:contextUnit.questions.length,context_tasks_answered:false,
    grammar_tasks:grammarUnit.questions.length,writing_criteria:writing.result.criteria.length,
    grammar_and_writing_creation:'authenticated_API',omitted_uncertain_rows:state.omitted_uncertain_rows??0,
    failed_context_reservations:state.failed_context_ids?.length??0,
    created_model_reservations_this_run:used.calls_used-before.calls_used,prepared_round_status:true,
    widths:[320,390,1280],runtime_errors:0,audio_device_acceptance:false,native_acceptance:false};
  await writeFile(path.join(artifacts,'language-web-result.json'),JSON.stringify(report)+'\n');
  console.log(JSON.stringify(report));
} catch(error) {
  if(page && phase!=='own_child_login') {
    await shot('failure-'+phase).catch(()=>{});
    const controls=await page.getByRole('button').evaluateAll(nodes=>nodes.map(node=>node.getAttribute('aria-label')??node.textContent).filter(Boolean)).catch(()=>[]);
    console.log(JSON.stringify({owned_synthetic_ui_controls:controls}));
  }
  const reason=error instanceof QaFailure && /^[a-z0-9_]+$/.test(error.message)?error.message:'browser_or_local_io_failed';
  console.error(JSON.stringify({failed_phase:phase,reason,private_state_preserved:true}));
  process.exitCode=1;
} finally { if(child)await child.setOffline(false).catch(()=>{}); if(browser)await browser.close(); }
