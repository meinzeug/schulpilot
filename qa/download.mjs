// Real UI clicks before login and in the parent dashboard; verify APK bytes.
import { chromium } from '@playwright/test';
import fs from 'node:fs/promises';
import crypto from 'node:crypto';
import path from 'node:path';

const base = 'https://schulpilot.dorfspy.de';
const artifact = path.resolve('../artifacts/public-downloaded.apk');
const browser = await chromium.launch({executablePath: process.env.CHROME_PATH || '/opt/google/chrome/chrome', headless: true});
const context = await browser.newContext({viewport: {width: 1280, height: 1000}, acceptDownloads: true});
const page = await context.newPage();
let demo;
const checks = [];

async function open(route) {
  await page.goto(base + route);
  await page.waitForSelector('flutter-view');
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
}

async function download(label) {
  const button = page.getByRole('button', {name: 'Android-APK herunterladen', exact: true});
  await page.mouse.move(920, 700);
  for (let i = 0; i < 12 && !(await button.isVisible()); i++) {
    await page.mouse.wheel(0, 750);
    await page.waitForTimeout(400);
  }
  await button.waitFor({state: 'visible', timeout: 15000});
  const result = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('No browser download event')), 30000);
    const completed = item => { clearTimeout(timer); resolve(item); };
    page.once('download', completed);
    context.once('page', popup => popup.once('download', completed));
  });
  await button.click();
  const item = await result;
  await item.saveAs(artifact);
  await fs.chmod(artifact, 0o600);
  const manifest = await (await context.request.get(base + '/api/app-release')).json();
  const bytes = await fs.readFile(artifact);
  if (crypto.createHash('sha256').update(bytes).digest('hex') !== manifest.sha256 || bytes.length !== manifest.size_bytes) {
    throw new Error('Downloaded APK does not match release manifest');
  }
  checks.push(label);
  await page.screenshot({path: path.resolve('../artifacts/' + label + '.png')});
}

try {
  await open('/');
  await download('public-apk-before-login');
  const response = await context.request.post(base + '/api/demo', {headers: {'X-Schulpilot-Request': '1'}});
  if (response.status() !== 201) throw new Error('Cannot create isolated synthetic account: ' + response.status());
  demo = await response.json();
  await open('/app');
  await download('public-apk-after-login');
  console.log(JSON.stringify({checks, actual_browser_downloads: 2, checksum_verified: true}));
} finally {
  if (demo) {
    const response = await context.request.delete(base + '/api/account', {headers: {'X-Schulpilot-Request': '1'}, data: {password: demo.credentials.parent_password}});
    if (response.status() !== 200) throw new Error('Own synthetic download-test family could not be deleted');
  }
  await browser.close();
}
