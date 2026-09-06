import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';
import { PNG } from 'pngjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const out = path.join(repo, '.work/browser-async', process.env.METONIC_GPU_BACKEND ?? 'default');
await mkdir(out, { recursive: true });
const server = spawn(process.execPath, [path.join(repo, 'scripts/serve-browser.mjs')], { cwd: repo, stdio: ['ignore', 'pipe', 'pipe'] });
let serverError = '';
server.stderr.setEncoding('utf8');
server.stderr.on('data', (value) => { serverError += value; });
const ready = new Promise((resolve, reject) => {
  let output = '';
  const timer = setTimeout(() => reject(new Error('browser server readiness timeout')), 10_000);
  server.stdout.setEncoding('utf8');
  server.stdout.on('data', (value) => {
    output += value;
    if (output === 'http://127.0.0.1:4173/\n') { clearTimeout(timer); resolve(); }
  });
  server.once('error', reject);
  server.once('exit', (code) => reject(new Error(`browser server exited: ${code}`)));
});

let browser;
try {
  await ready;
  const backend = process.env.METONIC_GPU_BACKEND ?? 'default';
  const launchOptions = { headless: true, channel: 'chromium' };
  if (backend === 'swiftshader') launchOptions.args = ['--use-angle=d3d11-warp', '--use-webgpu-adapter=swiftshader', '--enable-unsafe-webgpu', '--enable-unsafe-swiftshader'];
  browser = await chromium.launch(launchOptions);
  const results = [];
  for (const target of ['js', 'wasm-gc']) {
    const page = await browser.newPage();
    const errors = [];
    page.on('pageerror', (error) => errors.push(String(error)));
    await page.goto(`http://127.0.0.1:4173/?target=${target}`, { waitUntil: 'load' });
    try {
      await page.waitForFunction(() => document.querySelector('#status')?.textContent?.includes('Ready:'), null, { polling: 25, timeout: 10_000 });
    } catch (error) {
      const status = await page.locator('#status').textContent().catch(() => '<missing>');
      throw new Error(`target ${target} was not ready: status=${status}; pageerrors=${errors.join(' | ')}`, { cause: error });
    }
  const probe = () => page.evaluate(() => window.metonicAsyncProbe.snapshot());
  const wait = (predicate, arg = null) => page.waitForFunction(predicate, arg, { polling: 25, timeout: 3_000 });
  const screenshot = async (name) => page.locator('canvas').screenshot({ path: path.join(out, `${target}-${name}.png`) });
  const tealBounds = (buffer) => {
    const png = PNG.sync.read(buffer);
    let minX = png.width, minY = png.height, maxX = -1, maxY = -1;
    for (let y = 0; y < png.height; y += 1) for (let x = 0; x < png.width; x += 1) {
      const i = (y * png.width + x) * 4;
      if (png.data[i] < 100 && png.data[i + 1] > 120 && png.data[i + 2] > 120) {
        minX = Math.min(minX, x); minY = Math.min(minY, y); maxX = Math.max(maxX, x); maxY = Math.max(maxY, y);
      }
    }
    return { minX, minY, maxX, maxY, width: maxX - minX + 1, height: maxY - minY + 1 };
  };

  let initial = await probe();
  assert.equal(initial.task[0], 0);
  await page.evaluate(() => window.metonicAsyncProbe.start(500, 40));
  const beforeInputRevision = Number(await page.locator('#revision').innerText());
  await page.locator('canvas').focus();
  await page.keyboard.press('ArrowRight');
  await wait((revision) => Number(document.querySelector('#revision')?.textContent) > revision, beforeInputRevision);
  await wait(() => window.metonicAsyncProbe.snapshot().task[0] === 1);
  const pending = await probe();
  assert.equal(pending.pending, 1);
  await screenshot('pending');
  assert.notDeepEqual(await probe(), initial);
  await wait(() => window.metonicAsyncProbe.snapshot().task[0] === 2 && window.metonicAsyncProbe.snapshot().pending === 0);
  const success = await probe();
  assert.equal(success.task[2], 40);
  const successImage = await page.locator('canvas').screenshot({ path: path.join(out, `${target}-success.png`) });
  const successBox = tealBounds(successImage);
  assert.ok(Math.abs(successBox.minX - 40) <= 1);
  assert.ok(Math.abs(successBox.width - 120) <= 1);

  await page.evaluate(() => window.metonicAsyncProbe.start(150, 70));
  await page.evaluate(() => window.metonicAsyncProbe.start(10, 90));
  await wait(() => window.metonicAsyncProbe.snapshot().task[2] === 90 && window.metonicAsyncProbe.snapshot().pending === 0);
  const superseded = await probe();
  assert.equal(superseded.rejected, success.rejected + 1);
  assert.equal(superseded.task[2], 90);
  const supersededImage = await page.locator('canvas').screenshot({ path: path.join(out, `${target}-superseded.png`) });
  const supersededBox = tealBounds(supersededImage);
  assert.ok(Math.abs(supersededBox.minX - 90) <= 1);
  assert.ok(Math.abs(supersededBox.width - 120) <= 1);

  const submittedBeforeCancel = Number(await page.locator('#submitted').innerText());
  await page.evaluate(() => window.metonicAsyncProbe.start(100, 110));
  await page.evaluate(() => window.metonicAsyncProbe.cancel());
  await wait(() => window.metonicAsyncProbe.snapshot().task[0] === 4 && window.metonicAsyncProbe.snapshot().pending === 0);
  const canceled = await probe();
  assert.equal(canceled.task[2], 90);
  assert.equal(Number(await page.locator('#submitted').innerText()), submittedBeforeCancel);

  const submittedBeforeFail = Number(await page.locator('#submitted').innerText());
  await page.evaluate(() => window.metonicAsyncProbe.start(10, 7, true));
  await wait(() => window.metonicAsyncProbe.snapshot().task[0] === 3);
  const failed = await probe();
  assert.equal(failed.task[3], 7);
  assert.equal(Number(await page.locator('#submitted').innerText()), submittedBeforeFail);

  const submittedBeforeReset = Number(await page.locator('#submitted').innerText());
  await page.evaluate(() => window.metonicAsyncProbe.start(100, 120));
  await page.locator('#reset').click();
  await wait(() => window.metonicAsyncProbe.snapshot().task[0] === 0 && window.metonicAsyncProbe.snapshot().pending === 0);
  await wait((submitted) => Number(document.querySelector('#submitted')?.textContent) > submitted, submittedBeforeReset);
  const reset = await probe();
  assert.equal(reset.task[0], 0);
  const submittedAfterReset = Number(await page.locator('#submitted').innerText());
  await new Promise((resolve) => setTimeout(resolve, 200));
  assert.deepEqual(await probe(), reset);
  assert.equal(Number(await page.locator('#submitted').innerText()), submittedAfterReset);

  const submittedBeforeStop = Number(await page.locator('#submitted').innerText());
  await page.evaluate(() => window.metonicAsyncProbe.start(100, 130));
  await page.locator('#stop').click();
  await wait(() => window.metonicAsyncProbe.snapshot().disposed === true);
  const stopped = await probe();
  assert.equal(stopped.task[0], 5);
  assert.equal(stopped.disposed, true);
  await new Promise((resolve) => setTimeout(resolve, 200));
  assert.deepEqual(await probe(), stopped);
  assert.equal(Number(await page.locator('#submitted').innerText()), submittedBeforeStop);
  assert.equal(await page.evaluate(() => window.metonicAsyncProbe.start(1, 1)), false);
  assert.deepEqual(errors, []);
  const png = PNG.sync.read(await page.locator('canvas').screenshot());
  assert.ok(png.width > 0 && png.height > 0);
  results.push({ target, initial, pending, success, superseded, failed, stopped, errors });
  await page.close();
  }
  await writeFile(path.join(out, 'results.json'), JSON.stringify({ backend, results }, null, 2));
} catch (error) {
  if (serverError) console.error(serverError.trim());
  throw error;
} finally {
  await browser?.close();
  server.kill();
}
