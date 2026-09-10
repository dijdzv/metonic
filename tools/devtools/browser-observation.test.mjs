import assert from 'node:assert/strict';
import test from 'node:test';
import { chromium } from 'playwright';
import { observedPage, observeFailure } from './browser-observation.mjs';

test('failed asset requests survive page closure without query contents', async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await observedPage(browser);
  try {
    await page.route('http://fixture.invalid/**', route => route.abort('failed'));
    for (let index = 0; index < 10; index += 1) {
      const failed = page.waitForEvent('requestfailed');
      await page.evaluate(async index => {
        try { await fetch(`http://fixture.invalid/asset-${index}.wasm?token=private-value`); } catch {}
      }, index);
      await failed;
    }
    await page.close();
    const result = await observeFailure(page);
    assert.equal(result.observation, 'closed');
    assert.equal(result.requests.length, 8);
    assert.equal(result.requests[0].path, '/asset-2.wasm');
    assert.equal(result.requests[7].path, '/asset-9.wasm');
    assert(result.requests.every(request => request.method === 'GET' && request.error.length > 0));
    assert(!JSON.stringify(result).includes('private-value'));
  } finally { await browser.close(); }
});

test('timeout retains bounded status and page errors before cleanup', async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext();
  const page = await observedPage(context);
  try {
    await page.setContent('<div id="status">Loading fixture</div><div id="target">wasm-gc</div>');
    const emitted = page.waitForEvent('pageerror');
    await page.evaluate(() => setTimeout(() => { throw Error('fixture GPU failure'); }, 0));
    await emitted;
    await assert.rejects(page.waitForFunction(() => false, null, { timeout: 50 }), { name: 'TimeoutError' });
    const observation = await observeFailure(page);
    assert.equal(observation.observation, 'available');
    assert.equal(observation.status, 'Loading fixture');
    assert.equal(observation.target, 'wasm-gc');
    assert.match(observation.errors[0], /fixture GPU failure/);
    for (let index = 0; index < 12; index += 1) {
      const event = page.waitForEvent('pageerror');
      await page.evaluate(index => setTimeout(() => { throw Error(index + ':' + 'x'.repeat(1000)); }, 0), index);
      await event;
    }
    await page.evaluate(() => { document.querySelector('#status').textContent = 's'.repeat(2000); });
    const bounded = await observeFailure(page);
    assert.equal(bounded.status.length, 512);
    assert.equal(bounded.errors.length, 8);
    assert(bounded.errors.every(error => error.length <= 512));
    assert.match(bounded.errors[0], /4:/);
  } finally {
    await page.close();
    assert.equal(context.pages().length, 0);
    await browser.close();
  }
  assert.equal(browser.isConnected(), false);
  assert.equal((await observeFailure(page)).observation, 'closed');
});

test('unresponsive page evaluation cannot delay diagnostics indefinitely', async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await observedPage(browser);
  try {
    const evaluate = page.evaluate.bind(page);
    // Keep the browser alive while the diagnostic evaluation never resolves.
    page.evaluate = () => evaluate(() => new Promise(() => {}));
    const start = performance.now();
    const result = await observeFailure(page);
    assert.equal(result.observation, 'timeout');
    assert(performance.now() - start < 2500);
  } finally { await page.close(); await browser.close(); }
  assert.equal(browser.isConnected(), false);
});
