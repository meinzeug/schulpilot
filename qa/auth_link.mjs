// Input contains one-time mail secrets: stdin only, never log URLs or values.
import {chromium} from 'playwright';

let browser;
let step = 'input';
try {
  let input = '';
  for await (const chunk of process.stdin) input += chunk;
  const data = JSON.parse(input);
  if (!['verify', 'reset', 'invite'].includes(data.route)) throw new Error();
  const origin = new URL(data.public_url).origin;
  step = 'launch';
  browser = await chromium.launch({
    headless: true,
    executablePath: process.env.CHROME_PATH || '/opt/google/chrome/chrome',
    args: ['--no-sandbox'],
  });
  const context = await browser.newContext();
  const page = await context.newPage();
  let runtimeErrors = 0;
  page.on('pageerror', () => runtimeErrors++);
  step = 'open';
  await page.goto(`${origin}/${data.route}#token=${encodeURIComponent(data.token)}`, {waitUntil: 'domcontentloaded'});
  await page.waitForSelector('flutter-view');
  step = 'form';
  await page.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(node => node.click()));
  const code = page.getByLabel('Sicherer Link-Code', {exact: false});
  await code.waitFor();
  step = 'prefill';
  if (await code.inputValue() !== data.token) {
    throw new Error('prefill');
  }
  // Reload must preserve the fragment and refill the form again.
  step = 'reload';
  await page.reload({waitUntil: 'domcontentloaded'});
  await page.waitForSelector('flutter-view');
  await page.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(node => node.click()));
  await code.waitFor();
  if (await code.inputValue() !== data.token) throw new Error('reload');
  step = 'fields';
  const type = async (label, value) => {
    await page.getByLabel(label, {exact: false}).click();
    await page.waitForTimeout(150);
    await page.keyboard.insertText(value);
  };
  if (data.route === 'invite') {
    await type('Dein Anzeigename', 'Synthetischer eingeladener Elternteil');
    await type('Bestehendes oder neues Elternpasswort', data.password);
  } else if (data.route === 'reset') {
    await type('Passwort (mindestens 12 Zeichen)', data.password);
  }
  const path = data.route === 'invite' ? '/invitations/accept' : '/auth/' + data.route;
  const result = page.waitForResponse(response =>
    response.url() === origin + '/api' + path && response.request().method() === 'POST');
  const label = {verify: 'E-Mail bestätigen', reset: 'Passwort erneuern', invite: 'Einladung annehmen'}[data.route];
  step = 'submit';
  await page.getByRole('button', {name: label, exact: true}).click();
  if ((await result).status() !== 200 || runtimeErrors) throw new Error('submit');
  console.log(JSON.stringify({route: data.route, prefill: true, reload: true, form_submitted: true, runtime_errors: 0}));
} catch {
  // Browser exceptions can contain the navigated URL; do not expose them.
  console.error(JSON.stringify({email_link_check: 'failed', step}));
  process.exitCode = 1;
} finally {
  await browser?.close();
}
