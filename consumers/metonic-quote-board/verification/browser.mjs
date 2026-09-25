import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { mkdir, stat } from 'node:fs/promises';
import { createServer } from 'node:http';
import { dirname, extname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const consumer = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const dist = join(consumer, 'browser', '.metonic-dist');
const output = join(consumer, 'verification-output');
const mime = new Map([
  ['.html', 'text/html; charset=utf-8'],
  ['.mjs', 'text/javascript; charset=utf-8'],
  ['.js', 'text/javascript; charset=utf-8'],
  ['.wasm', 'application/wasm'],
  ['.ttf', 'font/ttf'],
  ['.json', 'application/json; charset=utf-8'],
]);

const server = createServer(async (request, response) => {
  try {
    const pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
    const path = resolve(dist, `.${pathname === '/' ? '/index.html' : pathname}`);
    if (relative(dist, path).startsWith('..') || !((await stat(path)).isFile())) {
      response.writeHead(404).end();
      return;
    }
    response.setHeader('Content-Type', mime.get(extname(path)) ?? 'application/octet-stream');
    createReadStream(path).pipe(response);
  } catch {
    response.writeHead(404).end();
  }
});
await new Promise(resolveListen => server.listen(0, '127.0.0.1', resolveListen));
await mkdir(output, { recursive: true });
const base = `http://127.0.0.1:${server.address().port}/`;
const browser = await chromium.launch({
  headless: true,
  channel: 'chromium',
  args: [
    '--use-webgpu-adapter=swiftshader', '--use-angle=d3d11-warp',
    '--enable-unsafe-webgpu', '--enable-unsafe-swiftshader',
  ],
});

try {
  for (const target of ['js', 'wasm-gc']) {
    const page = await browser.newPage({ viewport: { width: 900, height: 600 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(`${base}?target=${target}`);
    await page.waitForFunction(() => document.querySelector('#status')?.textContent?.startsWith('Ready:'), null, { timeout: 30000 });
    assert.equal(await page.locator('#controls button').count(), 5);
    const canvas = page.locator('#canvas');
    const waitLines = (detail, stock, quote) => page.waitForFunction(expected => {
      const lines = [...document.querySelectorAll('#controls .gpu-text')].map(node => node.textContent);
      return lines[1] === expected[0] && lines[2] === expected[1] && lines[3] === expected[2];
    }, [detail, stock, quote], { timeout: 5000 });
    const shot = async name => {
      const bytes = await canvas.screenshot({ path: join(output, `${target}-${name}.png`) });
      return createHash('sha256').update(bytes).digest('hex');
    };
    await waitLines('Detail: Amber lamp', 'Stock: 12', 'Shipping: 112 for 1');
    const amber = await shot('amber-ready');
    await page.getByRole('button', { name: 'Amber lamp' }).click();
    await waitLines('Detail: loading', 'Stock: loading', 'Shipping: loading (previous 112)');
    await waitLines('Detail: loading', 'Stock: 12', 'Shipping: loading (previous 112)');
    const amberPartial = await shot('amber-stock-first');
    await waitLines('Detail: Amber lamp', 'Stock: 12', 'Shipping: 112 for 1');
    assert.notEqual(await shot('amber-refreshed'), amberPartial, `${target}: stock-first completion did not redraw`);
    await page.getByRole('button', { name: 'Blue stool' }).click();
    const pending = await shot('blue-pending');
    assert.notEqual(pending, amber, `${target}: item selection did not redraw`);
    await waitLines('Detail: Blue stool', 'Stock: loading', 'Shipping: waiting for item');
    const partial = await shot('blue-partial');
    assert.notEqual(partial, pending, `${target}: detail-first completion did not redraw`);
    await waitLines('Detail: Blue stool', 'Stock: 7', 'Shipping: 107 for 1');
    const blue = await shot('blue-ready');
    assert.notEqual(blue, partial, `${target}: stock and quote completion did not redraw`);
    await page.getByRole('button', { name: 'Quantity +' }).click();
    await waitLines('Detail: Blue stool', 'Stock: 7', 'Shipping: loading');
    const quantityPending = await shot('quantity-pending');
    assert.notEqual(quantityPending, blue, `${target}: quantity change did not redraw`);
    await waitLines('Detail: Blue stool', 'Stock: 7', 'Shipping: 214 for 2');
    const quantityReady = await shot('quantity-ready');
    assert.notEqual(quantityReady, quantityPending, `${target}: new downstream quote did not redraw`);
    await page.getByRole('button', { name: 'Quantity +' }).click();
    await waitLines('Detail: Blue stool', 'Stock: 7', 'Shipping: loading');
    await page.getByRole('button', { name: 'Toggle detail' }).click();
    await waitLines('Detail: Blue stool', 'Stock: 7', 'Shipping: detail hidden');
    assert.equal(await page.getByRole('button', { name: 'Quantity +' }).count(), 0);
    await page.getByRole('button', { name: 'Toggle detail' }).click();
    assert.equal(await page.getByRole('button', { name: 'Quantity +' }).count(), 1);
    await waitLines('Detail: Blue stool', 'Stock: 7', 'Shipping: 321 for 3');
    assert.deepEqual(errors, [], `${target}: browser errors`);
    await page.getByRole('button', { name: 'Stop' }).click();
    assert.equal(await page.locator('#status').textContent(), 'Stopped.');
    await page.close();
  }
  console.log('QUOTE_BOARD_BROWSER_OK targets=js,wasm-gc');
} finally {
  await browser.close();
  await new Promise(resolveClose => server.close(resolveClose));
}
