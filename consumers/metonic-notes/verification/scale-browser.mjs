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
const smoke = process.argv.includes('--smoke');
const server = await serve(root);
let browser;
const observations = [];
try {
  browser = await chromium.launch({
    headless: true, channel: 'chromium',
    args: ['--use-webgpu-adapter=swiftshader', '--use-angle=d3d11-warp',
      '--enable-unsafe-webgpu', '--enable-unsafe-swiftshader'],
  });
  const cases = (smoke ? ['warmup'] : ['warmup', 1, 2, 3]).flatMap(sample =>
    ['js', 'wasm-gc'].map(target => ({ sample, target })));
  for (const { sample, target } of cases) {
    const context = await browser.newContext({
      viewport: { width: 800, height: 600 },
      storageState: { cookies: [], origins: [{
        origin: new URL(server.url).origin,
        localStorage: [{ name: 'metonic-notes.snapshot.v1', value: snapshot }],
      }] },
    });
    await context.addInitScript(() => {
      // WhyNot: CDP's JS heap omits app-created WebGPU resources.
      const stats = {
        textureCreates: 0, textureDestroys: 0, liveTextures: 0, peakTextures: 0,
        liveTextureBytes: 0, peakTextureBytes: 0,
        bufferCreates: 0, bufferDestroys: 0, liveBuffers: 0, peakBuffers: 0,
        liveBufferBytes: 0, peakBufferBytes: 0, unknownTextureFormats: [],
      };
      const textures = new WeakMap();
      const buffers = new WeakMap();
      window.__metonicGpuResourceStats = () => ({ ...stats });
      if (!window.GPUDevice || !window.GPUTexture || !window.GPUBuffer) {
        stats.error = 'WebGPU interface prototypes unavailable at document initialization';
        return;
      }
      const textureBytes = descriptor => {
        if (descriptor.format !== 'rgba8unorm') {
          stats.unknownTextureFormats.push(descriptor.format);
          return 0;
        }
        const size = descriptor.size;
        const width = Array.isArray(size) ? size[0] : size.width;
        const height = Array.isArray(size) ? size[1] : size.height ?? 1;
        const layers = Array.isArray(size) ? size[2] ?? 1 : size.depthOrArrayLayers ?? 1;
        const mips = descriptor.mipLevelCount ?? 1;
        const samples = descriptor.sampleCount ?? 1;
        let bytes = 0;
        for (let level = 0; level < mips; level++) {
          bytes += Math.max(1, width >> level) * Math.max(1, height >> level) * layers * 4 * samples;
        }
        return bytes;
      };
      const createTexture = GPUDevice.prototype.createTexture;
      GPUDevice.prototype.createTexture = function (descriptor) {
        const texture = createTexture.call(this, descriptor);
        const bytes = textureBytes(descriptor);
        textures.set(texture, bytes);
        stats.textureCreates++;
        stats.liveTextures++;
        stats.liveTextureBytes += bytes;
        stats.peakTextures = Math.max(stats.peakTextures, stats.liveTextures);
        stats.peakTextureBytes = Math.max(stats.peakTextureBytes, stats.liveTextureBytes);
        return texture;
      };
      const destroyTexture = GPUTexture.prototype.destroy;
      GPUTexture.prototype.destroy = function () {
        if (textures.has(this)) {
          stats.liveTextureBytes -= textures.get(this);
          stats.liveTextures--;
          stats.textureDestroys++;
          textures.delete(this);
        }
        return destroyTexture.call(this);
      };
      const createBuffer = GPUDevice.prototype.createBuffer;
      GPUDevice.prototype.createBuffer = function (descriptor) {
        const buffer = createBuffer.call(this, descriptor);
        const bytes = Number(descriptor.size);
        buffers.set(buffer, bytes);
        stats.bufferCreates++;
        stats.liveBuffers++;
        stats.liveBufferBytes += bytes;
        stats.peakBuffers = Math.max(stats.peakBuffers, stats.liveBuffers);
        stats.peakBufferBytes = Math.max(stats.peakBufferBytes, stats.liveBufferBytes);
        return buffer;
      };
      const destroyBuffer = GPUBuffer.prototype.destroy;
      GPUBuffer.prototype.destroy = function () {
        if (buffers.has(this)) {
          stats.liveBufferBytes -= buffers.get(this);
          stats.liveBuffers--;
          stats.bufferDestroys++;
          buffers.delete(this);
        }
        return destroyBuffer.call(this);
      };
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
      observation.gpuResourcesAtReady = await page.evaluate(() =>
        window.__metonicGpuResourceStats?.());
      observation.initialButtons = await page.getByRole('button').count();
      const memoRows = page.getByRole('button', { name: /^\*? ?Memo \d+$/ });
      observation.initialMemoButtons = await memoRows.count();
      const query = page.getByRole('textbox', { name: 'Search memos', exact: true });
      const editor = page.getByRole('textbox', { name: 'Memo', exact: true });
      await measure('search100', () => query.fill('alpha'), () =>
        document.querySelector('[aria-label="Memo 10"]') &&
        !document.querySelector('[aria-label="Memo 1"]'));
      await measure('select', () => page.getByRole('button', { name: 'Memo 10', exact: true }).click(),
        () => document.querySelector('[aria-label="Memo"]')?.value === 'Memo 10 alpha');
      await measure('clearSearch', () => query.fill(''), () =>
        document.querySelector('[aria-label="Memo 1"]'));
      const firstRowBox = await page.locator('[aria-label="Memo 1"]').boundingBox();
      await page.mouse.move(firstRowBox.x + firstRowBox.width / 2,
        firstRowBox.y + firstRowBox.height / 2);
      await measure('scroll', () => page.mouse.wheel(0, 720), () =>
        !document.querySelector('[aria-label="Memo 1"]') &&
        [...document.querySelectorAll('button')].some(button => {
          const match = /^\*? ?Memo (\d+)$/.exec(button.getAttribute('aria-label') || '');
          return match && Number(match[1]) >= 20;
        }));
      await measure('reorder', () => page.getByRole('button', { name: 'Move up', exact: true }).click(),
        () => document.querySelector('[aria-label="* Memo 10"]'));
      await measure('edit', () => editor.fill('Memo 10 alpha edited'), () =>
        document.querySelector('[aria-label="Memo"]')?.value === 'Memo 10 alpha edited');
      await measure('save', () => page.getByRole('button', { name: 'Save all', exact: true }).click(),
        () => localStorage.getItem('metonic-notes.snapshot.v1')?.includes('Memo 10 alpha edited'));
      await measure('autosave', () => editor.fill('Memo 10 alpha autosaved'), () =>
        localStorage.getItem('metonic-notes.snapshot.v1')?.includes('Memo 10 alpha autosaved'));
      observation.gpuResourcesBeforeReload = await page.evaluate(() =>
        window.__metonicGpuResourceStats?.());
      await measure('reopen', () => page.reload(), target =>
        document.querySelector('#status')?.textContent === `Ready: Memo (${target})`, target);
      await measure('restoreSelection', async () => {
        await query.fill('alpha');
        await page.waitForFunction(() =>
          document.querySelector('[aria-label="Memo 10"]') &&
          !document.querySelector('[aria-label="Memo 1"]'));
        await page.getByRole('button', { name: 'Memo 10', exact: true }).click();
      },
        () => document.querySelector('[aria-label="Memo"]')?.value === 'Memo 10 alpha autosaved');
      observation.finalButtons = await page.getByRole('button').count();
      observation.finalMemoButtons = await memoRows.count();
      assert.ok(observation.initialMemoButtons <= 32);
      assert.ok(observation.finalMemoButtons <= 32);
      const cdp = await context.newCDPSession(page);
      await cdp.send('Performance.enable');
      const metrics = (await cdp.send('Performance.getMetrics')).metrics;
      observation.jsHeapUsedBytes = metrics.find(metric => metric.name === 'JSHeapUsedSize')?.value;
      observation.domNodes = (await cdp.send('Memory.getDOMCounters')).nodes;
      await cdp.detach();
      observation.gpuResourcesAfterReload = await page.evaluate(() =>
        window.__metonicGpuResourceStats?.());
      await page.locator('#stop').click();
      await page.waitForFunction(() => document.querySelector('#status')?.textContent === 'Stopped.');
      observation.gpuResourcesAfterStop = await page.evaluate(() =>
        window.__metonicGpuResourceStats?.());
      for (const stats of [observation.gpuResourcesAtReady,
        observation.gpuResourcesBeforeReload,
        observation.gpuResourcesAfterReload]) {
        assert.ok(stats && !stats.error, stats?.error || 'missing WebGPU resource ledger');
        assert.ok(stats.textureCreates > 0 && stats.bufferCreates > 0);
        assert.deepEqual(stats.unknownTextureFormats, []);
        assert.equal(stats.textureCreates - stats.textureDestroys, stats.liveTextures);
        assert.equal(stats.bufferCreates - stats.bufferDestroys, stats.liveBuffers);
        assert.ok(stats.liveTextures <= 16 && stats.peakTextures <= 32);
        assert.ok(stats.liveBuffers <= 16 && stats.peakBuffers <= 32);
        assert.ok(stats.liveTextureBytes <= 2 * 1024 * 1024);
        assert.ok(stats.peakTextureBytes <= 4 * 1024 * 1024);
        assert.ok(stats.liveBufferBytes <= 1024 && stats.peakBufferBytes <= 2048);
      }
      const stopped = observation.gpuResourcesAfterStop;
      assert.ok(stopped && !stopped.error, stopped?.error || 'missing stopped WebGPU ledger');
      assert.equal(stopped.textureCreates, stopped.textureDestroys);
      assert.equal(stopped.bufferCreates, stopped.bufferDestroys);
      assert.equal(stopped.liveTextures, 0);
      assert.equal(stopped.liveBuffers, 0);
      assert.equal(stopped.liveTextureBytes, 0);
      assert.equal(stopped.liveBufferBytes, 0);
      assert.deepEqual(pageErrors, [], 'page errors during scale sequence');
    } catch (error) {
      observation.error = String(error);
      observation.status = await page.locator('#status').textContent().catch(() => null);
      observation.buttonsAtFailure = await page.getByRole('button').count().catch(() => null);
      observation.visibleRowsAtFailure = await page.locator('#controls > button').evaluateAll(buttons =>
        buttons.map(button => button.getAttribute('aria-label')).filter(label =>
          /^\*? ?Memo \d+$/.test(label || ''))).catch(() => null);
    } finally {
      await page.close();
      await context.close();
    }
    console.log(`NOTES_SCALE_BROWSER sample=${sample} target=${target} startup=${observation.steps.startup ?? 'failed'} error=${Boolean(observation.error)}`);
  }
} finally {
  await browser?.close();
  await server.close();
  await writeFile(smoke ? '.work/scale/browser-smoke.json' : '.work/scale/browser-baseline.json',
    JSON.stringify(observations, null, 2));
}
if (observations.some(item => item.error)) process.exitCode = 1;
for (const target of ['js', 'wasm-gc']) {
  const samples = observations.filter(item => item.target === target && item.sample !== 'warmup');
  if (samples.length === 0 || samples.some(item => item.error)) continue;
  const median = name => samples.map(item => item.steps[name]).sort((a, b) => a - b)[1];
  console.log(JSON.stringify({
    target, measuredSamples: samples.length,
    startupMs: median('startup'), search100Ms: median('search100'),
    selectMs: median('select'), clearSearchMs: median('clearSearch'),
    scrollMs: median('scroll'), reorderMs: median('reorder'),
    editMs: median('edit'), saveMs: median('save'), autosaveMs: median('autosave'),
    reopenMs: median('reopen'), restoreSelectionMs: median('restoreSelection'),
    initialButtons: samples[0].initialButtons,
    initialMemoButtons: samples[0].initialMemoButtons,
  }));
}
