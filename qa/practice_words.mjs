// Explicit artificial vocabulary practice through the public release. No AI.
import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import {chromium} from 'playwright';

const base = 'https://schulpilot.dorfspy.de';
const fixture = JSON.parse(await readFile(new URL('../artifacts/.design-qa-account.json', import.meta.url)));
const headers = {'X-Schulpilot-Request': '1', 'X-Schulpilot-Capabilities': 'language-v1'};
const browser = await chromium.launch({headless: true, executablePath: '/opt/google/chrome/chrome', args: ['--no-sandbox']});
const context = await browser.newContext({viewport: {width: 390, height: 950}});
const report = {synthetic_family_only: true, checks: [], external_ai_calls: 0};
let phase = 'login';
async function post(route, data, expected=200, key) {
  const response = await context.request.post(base+'/api'+route, {headers: {...headers, ...(key ? {'Idempotency-Key': key} : {})}, data});
  assert.equal(response.status(), expected, 'own_synthetic_request_failed');
  return response.json();
}
async function open(page, route) {
  await page.goto(base+route, {waitUntil: 'domcontentloaded'});
  await page.waitForSelector('flutter-view');
  await page.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(n => n.click()));
}
try {
  const login = await post('/auth/login', {username: fixture.credentials.child_username, password: fixture.credentials.child_password});
  assert(login.user.synthetic && login.user.child_id === fixture.child_id, 'own_artificial_child_required');
  phase = 'confirm_words';
  const route = '/children/'+fixture.child_id+'/vocabulary';
  const draft = await post(route+'/imports', {target_locale: 'en-GB', title: 'Künstlicher Praxistest', language_confirmed: true,
    pairs: [{word: 'swimming pool', meaning: 'Schwimmbad'}, {word: 'exercise', meaning: 'Übung'}]}, 201, 'practice-audit-words-v1');
  await post(route+'/imports/'+draft.id+'/confirm', {target_locale: 'en-GB', language_confirmed: true, pairs: draft.pairs});
  const round = await post(route+'/rounds', {target_locale: 'en-GB', skill: 'spelling', direction: 'de_to_target', count: 2, voluntary: true}, 201, 'practice-audit-round-v1');
  const page = await context.newPage();
  let errors = 0;
  page.on('pageerror', () => errors++);
  phase = 'start_round';
  await open(page, '/unit/'+round.unit_id);
  const start = page.getByRole('button', {name: /Jetzt lernen|Weiterlernen|Freiwillig üben/, exact: true});
  if (await start.count()) await start.first().click();
  const intro = page.getByRole('button', {name: 'Weiter zu den Übungen', exact: true});
  if (await intro.count()) await intro.click();
  const seen = new Set();
  for (let index=0; index<2; index++) {
    phase = 'answer_'+index;
    const response = await context.request.get(base+'/api/units/'+round.unit_id, {headers});
    const unit = await response.json();
    const question = unit.questions.find(q => !q.attempts.length);
    assert(question && !question.answer && !question.accepted, 'solution_must_not_be_projected');
    const answer = question.language.cue === 'Schwimmbad' ? 'Swimming pool' : 'exercise';
    assert(['Schwimmbad', 'Übung'].includes(question.language.cue), 'fixed_artificial_cue_required');
    seen.add(question.language.cue);
    await page.getByRole('textbox').first().fill(answer);
    // Real Tab navigation must reach a labelled control; no hidden autoplay.
    await page.keyboard.press('Tab');
    await page.getByRole('button', {name:'Antwort prüfen', exact:true}).click();
    await page.getByText('Richtig!', {exact:true}).first().waitFor();
    if (index === 0) {
      await open(page, '/unit/'+round.unit_id);
      const feedback = page.getByRole('button', {name:'Rückmeldung ansehen', exact:true});
      if (await feedback.count()) await feedback.click();
      await page.getByText('Richtig!', {exact:true}).first().waitFor();
      report.checks.push('saved_feedback_after_browser_reload');
    }
    await page.screenshot({path: new URL('../artifacts/practice-word-feedback-'+index+'.png', import.meta.url).pathname});
    const next = page.getByRole('button', {name: /^(Weiter|Ergebnis ansehen|Zum Rückblick)$/});
    await next.first().click();
  }
  assert.equal(seen.size, 2);
  const saved = await (await context.request.get(base+'/api/units/'+round.unit_id, {headers})).json();
  assert.equal(saved.status, 'completed');
  assert(saved.questions.every(q => q.attempts.length === 1 && q.attempts[0].outcome === 'correct' && !q.attempts[0].assisted));
  for (const width of [320, 1440]) {
    await page.setViewportSize({width, height: 950});
    await open(page, '/vocabulary/'+fixture.child_id);
    await page.getByText('Meine Wörter', {exact: true}).first().waitFor();
    report.checks.push('vocabulary_'+width);
  }
  assert.equal(errors, 0);
  report.checks.push('capital_initial_accepted', 'two_answers_exactly_once', 'round_completed', 'keyboard_tab_and_submit');
  report.success = true;
} catch (error) {
  report.success = false;
  report.failed_phase = phase;
  report.error = error instanceof assert.AssertionError ? error.message.split('\n')[0] : 'browser_action_failed';
  process.exitCode = 1;
} finally {
  await context.request.post(base+'/api/auth/logout', {headers}).catch(() => {});
  await context.close();
  await browser.close();
  await writeFile(new URL('../artifacts/practice-words-result.json', import.meta.url), JSON.stringify(report)+'\n', {mode: 0o600});
  console.log(JSON.stringify(report));
}
