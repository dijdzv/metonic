import assert from 'node:assert/strict';
import { createReadStream } from 'node:fs';
import { mkdir, readFile, readdir, stat, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { performance } from 'node:perf_hooks';
import { dirname, extname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';
import { gzipSync } from 'node:zlib';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const sizeOnly = process.argv.includes('--size-only');
const dist = join(root, 'browser', '.metonic-dist');
const output = join(root, 'verification-output');
const mime = new Map([
  ['.html', 'text/html; charset=utf-8'], ['.mjs', 'text/javascript; charset=utf-8'],
  ['.js', 'text/javascript; charset=utf-8'], ['.wasm', 'application/wasm'],
  ['.ttf', 'font/ttf'],
]);
const server = createServer(async (request, response) => {
  try {
    const pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
    const path = resolve(dist, `.${pathname === '/' ? '/index.html' : pathname}`);
    if (relative(dist, path).startsWith('..') || !(await stat(path)).isFile()) {
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
const base = `http://127.0.0.1:${server.address().port}/`;
const browser = await chromium.launch({
  headless: true,
  channel: 'chromium',
  args: [
    '--use-webgpu-adapter=swiftshader', '--use-angle=d3d11-warp',
    '--enable-unsafe-webgpu', '--enable-unsafe-swiftshader',
    '--enable-precise-memory-info',
  ],
});

const samples = [];
try {
  for (const target of sizeOnly ? [] : ['js', 'wasm-gc']) {
    for (let sample = 0; sample < 4; sample++) {
      const page = await browser.newPage({ viewport: { width: 900, height: 600 } });
      const errors = [];
      const requestedFiles = new Set();
      page.on('pageerror', error => errors.push(error.message));
      page.on('request', request => requestedFiles.add(
        new URL(request.url()).pathname.replace(/^\//, '') || 'index.html'));
      const lines = expected => page.waitForFunction(value => {
        const text = [...document.querySelectorAll('#controls .gpu-text, #controls .gpu-status')].map(node => node.textContent);
        return value.every(([index, content]) => text[index] === content);
      }, expected, { timeout: 10000 });
      const elapsed = started => Math.round(performance.now() - started);
      const result = { target, sample, metricsMs: {} };
      let started = performance.now();
      await page.goto(`${base}?target=${target}`);
      await page.waitForFunction(() => document.querySelector('#status')?.textContent?.startsWith('Ready:'), null, { timeout: 30000 });
      result.metricsMs.startup = elapsed(started);
      await lines([[1, 'Detail: Amber lamp'], [2, 'Stock: 12'], [3, 'Shipping: 112 for 1']]);
      result.metricsMs.initial_quote_ready = elapsed(started);

      started = performance.now();
      await page.getByRole('button', { name: 'Blue stool' }).click();
      await lines([[3, 'Shipping: waiting for item']]);
      result.metricsMs.item_pending = elapsed(started);
      await lines([[1, 'Detail: Blue stool'], [2, 'Stock: 7'], [3, 'Shipping: 107 for 1']]);
      result.metricsMs.item_ready = elapsed(started);

      started = performance.now();
      await page.getByRole('button', { name: 'USD' }).click();
      await lines([[3, 'Shipping: loading']]);
      result.metricsMs.currency_pending = elapsed(started);
      await lines([[3, 'Shipping: 214 USD for 1']]);
      result.metricsMs.currency_ready = elapsed(started);

      started = performance.now();
      await page.getByRole('button', { name: 'Toggle detail' }).click();
      await lines([[3, 'Shipping: detail hidden']]);
      assert.equal(await page.getByRole('button', { name: 'Quantity +' }).count(), 0);
      result.metricsMs.detail_hidden = elapsed(started);
      started = performance.now();
      await page.getByRole('button', { name: 'Toggle detail' }).click();
      await lines([[3, 'Shipping: 214 USD for 1']]);
      assert.equal(await page.getByRole('button', { name: 'Quantity +' }).count(), 1);
      result.metricsMs.detail_recreated = elapsed(started);

      started = performance.now();
      await page.getByRole('textbox', { name: 'Note' }).fill('measurement draft');
      await lines([[4, 'Note: unsaved revision 1']]);
      result.metricsMs.input_visible = elapsed(started);
      started = performance.now();
      await page.getByRole('button', { name: 'Save note' }).click();
      await lines([[4, 'Note: saved revision 1']]);
      result.metricsMs.save_acknowledged = elapsed(started);

      const cdp = await page.context().newCDPSession(page);
      await cdp.send('Performance.enable');
      const values = (await cdp.send('Performance.getMetrics')).metrics;
      result.browserResources = Object.fromEntries(values
        .filter(({ name }) => ['JSHeapUsedSize', 'Nodes', 'Documents', 'Frames'].includes(name))
        .map(({ name, value }) => [name, value]));
      result.requestedFiles = [...requestedFiles].sort();
      await cdp.detach();
      assert.deepEqual(errors, [], `${target} sample ${sample}: browser errors`);
      samples.push(result);
      await page.close();
      console.log(`QUOTE_BOARD_BROWSER_MEASURE target=${target} sample=${sample} result=ok`);
    }
  }
  await mkdir(output, { recursive: true });
  if (!sizeOnly) {
    await writeFile(join(output, 'browser-measurements.json'), JSON.stringify(samples, null, 2));
  }
  const files = [];
  for (const name of await readdir(dist)) {
    const path = join(dist, name);
    if (!(await stat(path)).isFile()) continue;
    const bytes = await readFile(path);
    const category = name === 'app.mjs' ? 'application-js'
      : name === 'app.wasm' ? 'application-wasm-gc'
      : name.endsWith('.mjs') ? 'host-js'
      : name.endsWith('.ttf') ? 'font'
      : name.startsWith('LICENSE') || name === 'OFL.txt' ? 'license'
      : 'other-asset';
    files.push({ name, category, rawBytes: bytes.length, gzipBytes: gzipSync(bytes, { level: 6 }).length });
  }
  await writeFile(join(output, 'browser-size.json'), JSON.stringify(files, null, 2));
  if (!sizeOnly) {
    console.log('QUOTE_BOARD_BROWSER_MEASUREMENT_OK warmup=1 measured=3 targets=js,wasm-gc');
  }
  console.log('QUOTE_BOARD_BROWSER_SIZE_OK gzip=level-6 files=' + files.length);
} finally {
  await browser.close();
  await new Promise(resolveClose => server.close(resolveClose));
}
