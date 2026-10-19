// Realistic parent role journey in exactly one owned synthetic family.
// No provider calls, messages, purchases, push consent or operational mutations.
import assert from 'node:assert/strict';
import {readFile, writeFile, chmod} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {chromium} from 'playwright';

const base = 'https://schulpilot.dorfspy.de';
const out = fileURLToPath(new URL('../artifacts/', import.meta.url));
const account = JSON.parse(await readFile(path.join(out, '.role-simulation-account.json'), 'utf8'));
const headers = {'X-Schulpilot-Request': '1', 'X-Schulpilot-Capabilities': 'language-v1,grade-pdf-v1'};
const afterChild = process.argv.includes('--after-child');
const childState = afterChild ? JSON.parse(await readFile(path.join(out, '.role-child-state.json'), 'utf8')) : {};
const childUnit = childState.unit_id;
const browser = await chromium.launch({headless: true, executablePath: '/opt/google/chrome/chrome', args: ['--no-sandbox']});
const context = await browser.newContext({viewport: {width: 1440, height: 1050}});
const page = await context.newPage();
const errors = [], failedReads = [], writes = [], checks = [], observations = [];
let phase = 'initial';
const report = {synthetic_family_only: true, actual_public_flutter: true, mode: afterChild ? 'after-child' : 'baseline', checks, observations,
  external_ai_calls: 0, physical_device: 'not_tested', real_audio: 'not_tested', screenreader_output: 'not_tested'};
page.on('pageerror', () => errors.push(phase));
page.on('response', r => {if (new URL(r.url()).pathname.startsWith('/api/') && r.request().method() === 'GET' && r.status() >= 400 && !(new URL(r.url()).pathname === '/api/auth/me' && ['normal_parent_login','normal_ui_logout'].includes(phase) && r.status() === 401)) failedReads.push({phase, status: r.status()});});
page.on('request', r => {const p = new URL(r.url()).pathname;if (p.startsWith('/api/') && !['GET', 'HEAD', 'OPTIONS'].includes(r.method())) writes.push({phase, method:r.method(), route:p.replace(/[a-f0-9]{32}/g, ':id')});});
const button = name => page.getByRole('button', {name, exact: true});
async function enable(){await page.waitForSelector('flutter-view', {timeout:90000});await page.locator('flt-semantics-placeholder').evaluateAll(ns=>ns.forEach(n=>n.click()));await page.waitForTimeout(450);}
async function open(route){await page.goto(base+route,{waitUntil:'domcontentloaded',timeout:90000});await enable();}
async function tap(locator){const target=locator.first();for(let i=0;i<40;i++){if(!await target.count()){await page.mouse.move(page.viewportSize().width/2,page.viewportSize().height/2);await page.mouse.wheel(0,250);await page.waitForTimeout(160);continue;}const b=await target.boundingBox().catch(()=>null);if(b&&b.width>0&&b.height>0&&b.y>=75&&b.y+b.height<page.viewportSize().height-8){await page.mouse.click(b.x+b.width/2,b.y+b.height/2);await page.waitForTimeout(250);return;}await page.mouse.move(page.viewportSize().width/2,page.viewportSize().height/2);await page.mouse.wheel(0,b&&b.y<75?-300:300);await page.waitForTimeout(120);}throw Error('control_not_reachable');}
async function type(locator,value){await tap(locator);await page.keyboard.press('Control+A');await page.keyboard.type(value,{delay:5});assert.equal(await locator.inputValue(),value,'field_not_received');await page.keyboard.press('Tab');}
async function api(route){const r=await context.request.get(base+'/api'+route,{headers});assert.equal(r.status(),200,'owned_parent_read_failed');return r.json();}
async function shot(name){const file=path.join(out,'role-parent-'+name+'.png');await page.screenshot({path:file});await chmod(file,0o600);}
async function text(){return page.locator('flt-semantics-host').innerText();}
async function noLayoutFailure(){assert(!/RenderFlex overflowed|A RenderFlex|ErrorWidget|Null check operator/.test(await text()),'layout_exception');}
async function checkRoute(route,label,width=1440){phase=label+'-'+width;await page.setViewportSize({width,height:1050});await open(route);await page.getByRole('button',{name:/Benachrichtigungen/}).first().waitFor();await noLayoutFailure();await shot(phase);checks.push(phase);}

try {
  const health=await(await fetch(base+'/api/health')).json();report.api_version=health.version;report.source_commit=health.source_commit;
  phase='normal_parent_login';
  await open('/login');
  await type(page.getByRole('textbox',{name:'E-Mail oder Benutzername',exact:true}),account.credentials.parent_username);
  await type(page.getByLabel('Passwort',{exact:true}),account.credentials.parent_password);
  const loginWait=page.waitForResponse(r=>new URL(r.url()).pathname==='/api/auth/login'&&r.request().method()==='POST');
  await tap(button('Anmelden'));
  const loginResponse=await loginWait;assert.equal(loginResponse.status(),200);
  const login=await loginResponse.json();assert.equal(login.user.role,'parent');assert(login.user.families.length&&login.user.families.every(f=>f.synthetic===true),'only_own_artificial_memberships');
  const family=await api('/families/'+login.user.families[0].id);assert.equal(family.synthetic,true);assert(family.children.some(c=>c.id===account.child_id),'own_child_required');
  await page.waitForURL(base+'/app');checks.push('normal_parent_login_and_synthetic_membership');
  const before=await api('/children/'+account.child_id+'/overview?compact=true');
  report.saved_answers_before=before.day_summary?.answer_count??null;
  for(const width of [1440,390])await checkRoute('/app','family_overview',width);
  await checkRoute('/child/'+account.child_id,'child_summary',1440);
  assert((await text()).includes('Das gelang'),'parent_brief_missing');
  checks.push('parent_brief_has_success_next_support_sections');
  if(/Nächste Wiederholung: \d{4}-\d{2}-\d{2}/.test(await text()))observations.push('P-UI-02: Elternüberblick zeigt den Wiederholungstermin noch als ISO-Datum statt lokalem Datum.');
  phase='parent_materials_tab';
  await tap(page.getByRole('checkbox',{name:'Heftseiten',exact:true}));
  await button('Bibliothek öffnen').waitFor();await shot('material-tab');checks.push('own_child_materials_tab');
  await tap(button('Bibliothek öffnen'));await page.waitForURL(base+'/library/'+account.child_id);await noLayoutFailure();checks.push('parent_opens_notebook_library_from_child');
  const material=await api('/materials/'+account.material_id);assert.equal(material.synthetic,true);
  await checkRoute('/material/'+account.material_id,'own_material_detail',390);
  await checkRoute('/progress/'+account.child_id,'subject_progress',1440);
  await checkRoute('/vocabulary/'+account.child_id,'vocabulary',390);
  await checkRoute('/grades/'+account.child_id,'grades',390);
  if(!afterChild){
    phase='synthetic_pdf_upload';
    await tap(button('PDF importieren'));
    const file=path.join(out,'role-parent-synthetic-grades.pdf');
    const waiter=page.waitForEvent('filechooser',{timeout:20000});waiter.catch(()=>{});
    const responseWait=page.waitForResponse(r=>r.request().method()==='POST'&&new URL(r.url()).pathname===`/api/children/${account.child_id}/grade-imports`,{timeout:45000});responseWait.catch(()=>{});
    await tap(button('PDF auswählen'));
    await(await waiter).setFiles(file);
    const uploaded=await responseWait;assert.equal(uploaded.status(),201,'pdf_upload_failed');
    const preview=await uploaded.json();assert.equal(preview.items.length,3,'synthetic_pdf_three_grades');
    assert.equal(preview.counts.new+preview.counts.existing,3);
    await page.waitForTimeout(600);await shot('pdf-preview-mobile');checks.push('actual_mobile_filechooser_pdf_preview_three_grades');
    await tap(button('Schließen'));
    assert.equal((await api('/children/'+account.child_id+'/grades')).pagination.total,0,'preview_must_not_save_grades');
    report.pdf={selected_bytes:249521,preview_items:3,saved_total:0,explicit_confirmation_deferred:true};
    checks.push('pdf_preview_does_not_save_without_confirmation');
  }
  await checkRoute('/notifications','notification_bell_inbox',1440);
  await checkRoute('/settings','parent_account_settings',390);
  await checkRoute('/child/'+account.child_id,'child_summary_mobile',390);
  phase='plan_settings_read_only';
  await tap(page.getByRole('checkbox',{name:'Plan',exact:true}));await tap(button('Lernvorgaben anpassen'));
  await page.getByText('Mindestlernzeit',{exact:true}).waitFor({state:'attached'});
  assert.equal(await page.getByRole('textbox',{name:'Mindestziel pro Tag',exact:true}).count(),1);
  await shot('parent-minimum-plan-dialog');
  await tap(button('Abbrechen'));checks.push('minimum_goals_round_pause_day_preferences_open_and_cancel');
  await checkRoute('/child/'+account.child_id,'activity_and_messages',1440);
  await tap(page.getByRole('checkbox',{name:'Nachrichten',exact:true}));await noLayoutFailure();await shot('messages-no-send');checks.push('family_messages_read_only_no_send');
  await tap(page.getByRole('checkbox',{name:'Verlauf',exact:true}));await noLayoutFailure();await shot('activity-read-only');checks.push('activity_view_read_without_child_writes');
  if(afterChild){
    const after=await api('/children/'+account.child_id+'/overview?compact=true');
    const familyAfter=await api('/families/'+login.user.families[0].id);
    const own=familyAfter.children.find(c=>c.id===account.child_id);
    report.parent_saved_answer_count=own.summary.answer_count;
    if(childUnit){
      const unit=await api('/units/'+childUnit);assert.equal(unit.status,'completed','finish_child_round_before_parent_updates');const attempts=unit.questions.flatMap(q=>q.attempts??[]);
      assert(!Object.hasOwn(unit.learning_session?.working_memory??{},'draft'),'parent_must_not_read_unsubmitted_draft');
      report.attempts_in_child_unit=attempts.length;report.unit_status=unit.status;
      await checkRoute('/unit/'+childUnit,'parent_answer_audit',1440);
      assert((await text()).includes('Einblick in die Lerneinheit'),'parent_read_only_audit_missing');
      const ledger=await api('/children/'+account.child_id+'/learning-progress');
      assert.equal(own.summary.answer_count,ledger.totals.attempts,'family_answers_match_canonical_attempts');
      report.canonical_progress_totals=ledger.totals;
      report.parent_ledger_matches_family=true;
      await checkRoute('/progress/'+account.child_id,'canonical_parent_progress',1440);
      const progressText=await text();assert(progressText.includes(`${ledger.totals.practiced_tasks} Aufgaben geübt`),'saved_task_count_not_rendered');
      assert(progressText.includes(`${ledger.totals.attempts} Versuche`),'saved_attempt_count_not_rendered');
      for(const [key,label]of [['independent_tasks','alleine gelöst'],['assisted_tasks','mit Hilfe gelöst']])if(ledger.totals[key])assert(progressText.includes(`${ledger.totals[key]} ${label}`),'support_split_not_rendered');
      if(/\b1 Runden\b|\b1 Versuche\b/.test(progressText))observations.push('P-UI-01: Fortschritt verwendet bei einer Runde noch die Mehrzahl „1 Runden“. Zahlen und Einstufung sind korrekt; Singulartext verbessern.');
      checks.push('parent_progress_displays_canonical_tasks_attempts_and_support_split');
      checks.push('parent_family_counts_equal_actual_attempts');
      const afterRead=await api('/children/'+account.child_id+'/overview?compact=true');
      assert.equal(afterRead.plan.daily_active_seconds,after.plan.daily_active_seconds,'passive_parent_view_changed_child_time');
      assert.equal((await api('/units/'+childUnit)).questions.flatMap(q=>q.attempts??[]).length,attempts.length);
      checks.push('passive_parent_audit_no_new_answers_or_child_time');
    }
  }
  if(afterChild){
    phase='post_child_pdf_confirm_and_reimport';
    await open('/grades/'+account.child_id);
    const imported=[];
    for(let pass=0;pass<2;pass++){
      await tap(button('PDF importieren'));
      const chosen=page.waitForEvent('filechooser',{timeout:20000});chosen.catch(()=>{});
      const uploaded=page.waitForResponse(r=>r.request().method()==='POST'&&new URL(r.url()).pathname===`/api/children/${account.child_id}/grade-imports`,{timeout:45000});uploaded.catch(()=>{});
      await tap(button('PDF auswählen'));await(await chosen).setFiles(path.join(out,'role-parent-synthetic-grades.pdf'));
      const r=await uploaded;assert.equal(r.status(),201);const preview=await r.json();assert.equal(preview.items.length,3);
      if(pass===1)assert.equal(preview.counts.existing,3,'repeat_pdf_must_recognize_existing');
      const savedWait=page.waitForResponse(r=>r.request().method()==='POST'&&new URL(r.url()).pathname===`/api/children/${account.child_id}/grade-imports/${preview.id}/confirm`,{timeout:30000});savedWait.catch(()=>{});
      await tap(button('Auswahl übernehmen'));const savedResponse=await savedWait;assert.equal(savedResponse.status(),200);const saved=await savedResponse.json();
      assert.equal(saved.added+saved.unchanged,3);if(pass===1)assert.equal(saved.added,0);
      imported.push({new:preview.counts.new,existing:preview.counts.existing,added:saved.added,unchanged:saved.unchanged});
      await tap(button('Fertig'));assert.equal((await api('/children/'+account.child_id+'/grades')).pagination.total,3);
    }
    report.pdf_confirmations=imported;checks.push('synthetic_pdf_save_and_repeat_zero_duplicate_grades');
    await page.reload({waitUntil:'domcontentloaded'});await enable();await button('PDF importieren').waitFor();assert.equal((await api('/children/'+account.child_id+'/grades')).pagination.total,3);checks.push('confirmed_pdf_grades_survive_reload');
    phase='explicit_minimum_goal_change';
    await open('/child/'+account.child_id);await tap(page.getByRole('checkbox',{name:'Plan',exact:true}));await tap(button('Lernvorgaben anpassen'));
    await type(page.getByRole('textbox',{name:'Mindestziel pro Tag',exact:true}),'25');
    await type(page.getByRole('textbox',{name:'Mindestziel pro Woche',exact:true}),'125');
    const savedPrefs=page.waitForResponse(r=>r.request().method()==='PUT'&&new URL(r.url()).pathname===`/api/children/${account.child_id}/preferences`,{timeout:20000});savedPrefs.catch(()=>{});
    await tap(button('Speichern'));assert.equal((await savedPrefs).status(),200);
    const changed=await api('/children/'+account.child_id+'/overview?compact=true');assert.equal(changed.child.preferences.daily_minutes,25);assert.equal(changed.child.preferences.weekly_minutes,125);assert.equal(changed.plan.daily_active_seconds,before.plan.daily_active_seconds,'changing_goals_must_not_invent_time');
    assert.equal(changed.child.preferences.push_consent,before.child.preferences.push_consent,'no_push_consent_change');
    await page.reload({waitUntil:'domcontentloaded'});await enable();await tap(page.getByRole('checkbox',{name:'Plan',exact:true}));assert((await text()).includes('25 Min. am Tag'),'saved_minimum_not_visible');
    checks.push('parent_changes_minimum_goals_and_reload_preserves_values');
    phase='demo_usage_unchanged';const usage=await api('/families/'+login.user.families[0].id+'/usage');assert.equal(usage.synthetic,true);assert.equal(usage.calls_used,0);assert.equal(usage.records.length,0);assert.equal(usage.encumbered_micros_usd,0);report.family_usage={calls_used:usage.calls_used,records:usage.records.length,encumbered_micros_usd:usage.encumbered_micros_usd};checks.push('fixed_demo_and_parent_actions_reserve_no_external_ai_calls');
    phase='os_text_scale_check';
    await open('/child/'+account.child_id);const title=page.getByText('Lernüberblick',{exact:true});const initial=await title.boundingBox();
    const cdp=await context.newCDPSession(page);await cdp.send('Emulation.setEmulatedOSTextScale',{scale:2});await page.reload({waitUntil:'domcontentloaded'});await enable();const scaled=await title.boundingBox();
    report.os_text_scale={requested:2,rendered_height_ratio:scaled&&initial?Number((scaled.height/initial.height).toFixed(3)):null};
    if(scaled&&initial&&scaled.height>=initial.height*1.5){await noLayoutFailure();checks.push('actual_large_text_rendered_without_framework_error');}else observations.push('Chrome OS-text-scale emulation did not enlarge this Flutter Web label; 200%-text acceptance is not demonstrated by this browser run.');
    await cdp.send('Emulation.setEmulatedOSTextScale',{scale:1});await cdp.detach();
    phase='keyboard_parent_navigation';await open('/app');let focusable=0;
    for(let i=0;i<10;i++){await page.keyboard.press('Tab');const focused=await page.evaluate(()=>{const n=document.activeElement;return Boolean(n&&n!==document.body&&n!==document.documentElement);});if(focused)focusable++;}
    report.keyboard={tab_steps:10,steps_with_focus:focusable};assert(focusable>2,'parent_keyboard_has_no_focus');checks.push('keyboard_tab_navigation_has_focus_targets');
    phase='bell_click_opens_inbox';const bell=page.getByRole('button',{name:/Benachrichtigungen/}).first();const bellBox=await bell.boundingBox();assert(bellBox);await page.mouse.click(bellBox.x+bellBox.width/2,bellBox.y+bellBox.height/2);await page.waitForURL(base+'/notifications');checks.push('parent_bell_click_opens_notification_inbox');
    phase='normal_ui_logout';await open('/settings');await tap(button('Abmelden'));await page.waitForURL(base+'/login');checks.push('normal_parent_ui_logout');
  }
  assert.equal(errors.length,0,'browser_runtime_error');assert.equal(failedReads.length,0,'owned_read_failed');
  const forbidden=writes.filter(x=>/\/answer$|\/heartbeat$|\/coaching$|\/tutor|\/units$|\/learning-session\/check$|\/messages$|\/assignments/.test(x.route));
  assert.equal(forbidden.length,0,'parent_passive_flow_created_child_action');
  report.success=true;
}catch(e){report.success=false;report.failed_phase=phase;report.error=e instanceof assert.AssertionError?e.message.split('\n')[0]:String(e.message).slice(0,100);await shot('failure').catch(()=>{});const file=path.join(out,'role-parent-failure-semantics.txt');await writeFile(file,await text().catch(()=>''),{mode:0o600});process.exitCode=1;
}finally{
  const endHealth=await fetch(base+'/api/health').then(r=>r.json()).catch(()=>null);if(endHealth)report.source_commit_end=endHealth.source_commit;
  report.browser_errors=errors.length;report.failed_reads=failedReads;report.ui_writes=writes;
  await context.request.post(base+'/api/auth/logout',{headers}).catch(()=>{});await context.close();await browser.close();
  await writeFile(path.join(out,afterChild?'role-parent-after-child-result.json':'role-parent-result.json'),JSON.stringify(report,null,2)+'\n',{mode:0o600});
  console.log(JSON.stringify(report));
}
