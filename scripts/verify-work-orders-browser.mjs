import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { chromium } from 'playwright';

const root = path.resolve('consumers/metonic-work-orders/browser/.metonic-dist');
const key = 'metonic-work-orders-v1';
const mime = { '.html': 'text/html', '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.ttf': 'font/ttf' };
const server = createServer(async (request, response) => {
  const name = new URL(request.url, 'http://localhost').pathname;
  const file = path.resolve(root, `.${name === '/' ? '/index.html' : name}`);
  if (!file.startsWith(`${root}${path.sep}`)) {
    response.writeHead(403).end();
    return;
  }
  try {
    const data = await readFile(file);
    response.writeHead(200, { 'content-type': mime[path.extname(file)] ?? 'application/octet-stream' });
    response.end(data);
  } catch {
    response.writeHead(404).end();
  }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const base = `http://127.0.0.1:${server.address().port}`;
let browser;

async function open(context, target, setup) {
  const page = await context.newPage();
  if (setup) await page.addInitScript(setup);
  const errors = [];
  page.on('pageerror', error => errors.push(String(error)));
  await page.goto(`${base}/?target=${target}`);
  await page.waitForFunction(() => document.querySelector('#status')?.textContent?.startsWith('Ready:'), null, { timeout: 60000 });
  return { page, errors };
}

async function status(page, text) {
  await page.locator(`#controls span.gpu-text[aria-label="${text}"]`).waitFor();
}

try {
  browser = await chromium.launch({
    headless: true,
    channel: 'chromium',
    args: ['--use-webgpu-adapter=swiftshader', '--enable-unsafe-webgpu', '--use-angle=d3d11-warp', '--enable-unsafe-swiftshader'],
  });
  for (const target of ['js', 'wasm-gc']) {
    const context = await browser.newContext({ viewport: { width: 1000, height: 800 } });
    const { page, errors } = await open(context, target);
    const title = page.getByRole('textbox', { name: 'Title' });
    const save = page.getByRole('button', { name: 'Save', exact: true });
    assert.equal(await title.inputValue(), 'Inspect entry light');
    await status(page, 'Unsaved changes');
    await title.fill(`Saved ${target} 😀`);
    await save.click();
    await status(page, 'Saved');
    const valid = await page.evaluate(key => localStorage.getItem(key), key);
    assert.match(valid, new RegExp(`Saved ${target}`));
    await page.reload();
    await page.waitForFunction(() => document.querySelector('#status')?.textContent?.startsWith('Ready:'), null, { timeout: 60000 });
    assert.equal(await title.inputValue(), `Saved ${target} 😀`);
    await status(page, 'Saved');
    await title.fill('Uncommitted draft');
    await page.reload();
    await page.waitForFunction(() => document.querySelector('#status')?.textContent?.startsWith('Ready:'), null, { timeout: 60000 });
    assert.equal(await title.inputValue(), `Saved ${target} 😀`);
    await page.evaluate(key => localStorage.setItem(key, 'METONIC_WORK_ORDERS\n{'), key);
    await page.reload();
    await page.waitForFunction(() => document.querySelector('#status')?.textContent?.startsWith('Ready:'), null, { timeout: 60000 });
    await status(page, 'Load failed: Malformed work-order snapshot');
    assert.equal(await title.isEnabled(), false);
    assert.equal(await page.evaluate(key => localStorage.getItem(key), key), 'METONIC_WORK_ORDERS\n{');
    await page.evaluate(({ key, valid }) => localStorage.setItem(key, valid), { key, valid });
    await page.getByRole('button', { name: 'Retry load' }).click();
    await status(page, 'Saved');
    assert.equal(await title.inputValue(), `Saved ${target} 😀`);
    assert.deepEqual(errors, []);
    await context.close();

    const deniedContext = await browser.newContext();
    const denied = await open(deniedContext, target, () => {
      Object.defineProperty(window, 'localStorage', { configurable: true, get() { throw new DOMException('blocked', 'SecurityError'); } });
    });
    await status(denied.page, 'Load failed: Storage access denied');
    assert.equal(await denied.page.getByRole('textbox', { name: 'Title' }).isEnabled(), false);
    assert.deepEqual(denied.errors, []);
    await deniedContext.close();

    const quotaContext = await browser.newContext();
    const quota = await open(quotaContext, target, () => {
      Storage.prototype.setItem = function () { throw new DOMException('full', 'QuotaExceededError'); };
    });
    await quota.page.getByRole('button', { name: 'Save', exact: true }).click();
    await status(quota.page, 'Save failed: Storage capacity exceeded');
    assert.equal(await quota.page.getByRole('textbox', { name: 'Title' }).inputValue(), 'Inspect entry light');
    assert.equal(await quota.page.evaluate(key => localStorage.getItem(key), key), null);
    assert.deepEqual(quota.errors, []);
    await quotaContext.close();
    console.log(`WORK_ORDERS_BROWSER_STORAGE_OK target=${target} save reload unsaved malformed retry denied quota`);
  }
} finally {
  await browser?.close();
  await new Promise(resolve => server.close(resolve));
}
