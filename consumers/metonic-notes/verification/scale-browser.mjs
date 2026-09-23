import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { performance } from 'node:perf_hooks';
import { serve } from './static-server.mjs';

const root = path.resolve('browser/.metonic-dist');
const snapshot = await readFile('.work/scale/fixture.snapshot', 'utf8');
assert.ok(snapshot.startsWith('METONIC_NOTES\n'));
assert.equal(JSON.parse(snapshot.split('\n', 2)[1]).notes.length, 1000);
const server = await serve(root);
let browser;
const observations = [];
try {
  browser = await chromium.launch({
    headless: true, channel: 'chromium',
    args: ['--use-webgpu-adapter=swiftshader', '--use-angle=d3d11-warp',
      '--enable-unsafe-webgpu', '--enable-unsafe-swiftshader'],
  });
  const cases = ['warmup', 1, 2, 3].flatMap(sample =>
    ['js', 'wasm-gc'].map(target => ({ sample, target })));
  for (const { sample, target } of cases) {
    const context = await browser.newContext({
      viewport: { width: 800, height: 600 },
      storageState: { cookies: [], origins: [{
        origin: new URL(server.url).origin,
        localStorage: [{ name: 'metonic-notes.snapshot.v1', value: snapshot }],
      }] },
    });
    const page = await context.newPage();
    const pageErrors = [];
    page.on('pageerror', error => pageErrors.push(error.message));
    const observation = {
      sample, target, browser: browser.version(), platform: process.platform,
      osRelease: os.release(), osVersion: os.version(), arch: process.arch,
      cpu: os.cpus()[0]?.model, ramBytes: os.totalmem(),
      fixtureBytes: Buffer.byteLength(snapshot), steps: {}, pageErrors,
    };
    observations.push(observation);
    const measure = async (name, action, expected, expectedArg = null) => {
      const started = performance.now();
      await action();
      await page.waitForFunction(expected, expectedArg, { timeout: 30000 });
      observation.steps[name] = Math.round(performance.now() - started);
    };
    try {
      const started = performance.now();
      await page.goto(`${server.url}?target=${target}`);
      await page.waitForFunction(target => document.querySelector('#status')?.textContent ===
        `Ready: Memo (${target})`, target, { timeout: 30000 });
      observation.steps.startup = Math.round(performance.now() - started);
      observation.initialButtons = await page.getByRole('button').count();
      const query = page.getByRole('textbox', { name: 'Search memos', exact: true });
      const editor = page.getByRole('textbox', { name: 'Memo', exact: true });
      await measure('search100', () => query.fill('alpha'), () =>
        [...document.querySelectorAll('button')].filter(button =>
          /^\*? ?Memo \d+$/.test(button.getAttribute('aria-label') || '')).length === 100);
      await measure('select', () => page.getByRole('button', { name: 'Memo 10', exact: true }).click(),
        () => document.querySelector('[aria-label="Memo"]')?.value === 'Memo 10 alpha');
      await measure('clearSearch', () => query.fill(''), () =>
        [...document.querySelectorAll('button')].filter(button =>
          /^\*? ?Memo \d+$/.test(button.getAttribute('aria-label') || '')).length === 1000);
      await page.mouse.move(40, 200);
      const beforeScrollY = await page.locator('[aria-label="Memo 1"]').evaluate(element =>
        element.getBoundingClientRect().y);
      await measure('scroll', () => page.mouse.wheel(0, 720), before =>
        document.querySelector('[aria-label="Memo 1"]')?.getBoundingClientRect().y < before,
      beforeScrollY);
      await measure('reorder', () => page.getByRole('button', { name: 'Move up', exact: true }).click(),
        () => [...document.querySelectorAll('button')].filter(button =>
          /^\*? ?Memo \d+$/.test(button.getAttribute('aria-label') || ''))[8]?.getAttribute('aria-label') === '* Memo 10');
      await measure('edit', () => editor.fill('Memo 10 alpha edited'), () =>
        document.querySelector('[aria-label="Memo"]')?.value === 'Memo 10 alpha edited');
      await measure('save', () => page.getByRole('button', { name: 'Save all', exact: true }).click(),
        () => localStorage.getItem('metonic-notes.snapshot.v1')?.includes('Memo 10 alpha edited'));
      await measure('reopen', () => page.reload(), target =>
        document.querySelector('#status')?.textContent === `Ready: Memo (${target})`, target);
      await measure('restoreSelection', async () => {
        await query.fill('alpha');
        await page.waitForFunction(() =>
          [...document.querySelectorAll('button')].filter(button =>
            /^\*? ?Memo \d+$/.test(button.getAttribute('aria-label') || '')).length === 100);
        await page.getByRole('button', { name: 'Memo 10', exact: true }).click();
      },
        () => document.querySelector('[aria-label="Memo"]')?.value === 'Memo 10 alpha edited');
      observation.finalButtons = await page.getByRole('button').count();
      const cdp = await context.newCDPSession(page);
      await cdp.send('Performance.enable');
      const metrics = (await cdp.send('Performance.getMetrics')).metrics;
      observation.jsHeapUsedBytes = metrics.find(metric => metric.name === 'JSHeapUsedSize')?.value;
      observation.domNodes = (await cdp.send('Memory.getDOMCounters')).nodes;
      await cdp.detach();
      assert.deepEqual(pageErrors, [], 'page errors during scale sequence');
    } catch (error) {
      observation.error = String(error);
      observation.status = await page.locator('#status').textContent().catch(() => null);
      observation.buttonsAtFailure = await page.getByRole('button').count().catch(() => null);
    } finally {
      await page.close();
      await context.close();
    }
    console.log(`NOTES_SCALE_BROWSER sample=${sample} target=${target} startup=${observation.steps.startup ?? 'failed'} error=${Boolean(observation.error)}`);
  }
} finally {
  await browser?.close();
  await server.close();
  await writeFile('.work/scale/browser-baseline.json', JSON.stringify(observations, null, 2));
}
if (observations.some(item => item.error)) process.exitCode = 1;
for (const target of ['js', 'wasm-gc']) {
  const samples = observations.filter(item => item.target === target && item.sample !== 'warmup');
  if (samples.some(item => item.error)) continue;
  const median = name => samples.map(item => item.steps[name]).sort((a, b) => a - b)[1];
  console.log(JSON.stringify({
    target, measuredSamples: samples.length,
    startupMs: median('startup'), search100Ms: median('search100'),
    selectMs: median('select'), clearSearchMs: median('clearSearch'),
    scrollMs: median('scroll'), reorderMs: median('reorder'),
    editMs: median('edit'), saveMs: median('save'),
    reopenMs: median('reopen'), restoreSelectionMs: median('restoreSelection'),
    initialButtons: samples[0].initialButtons,
  }));
}
