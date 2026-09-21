import process from 'node:process'
import assert from 'node:assert/strict'
import fs from 'node:fs/promises'
import path from 'node:path'
import { chromium } from 'playwright'
import { observedPage, reportFailure } from '../tools/devtools/browser-observation.mjs'
import { verifyDynamicControls } from '../tools/devtools/application-controls.mjs'
import { verify as verifyPixels, runScene, runFailures, runFontFailures, runText, runDpr, runSuite, runRelease, runEditorScroll, runQueryObservation } from '../_build/js/release/build/tools/verify_browser_pixels/verify_browser_pixels.js'

if (process.env.METONIC_BROWSER_SUPERVISED !== '1') throw new Error('Run mise run browser:async/headless')

const backend = process.env.METONIC_GPU_BACKEND ?? 'default'
assert(['default', 'swiftshader'].includes(backend), 'METONIC_GPU_BACKEND must be default or swiftshader')
const baseUrl = process.env.METONIC_BROWSER_BASE
assert(/^http:\/\/127\.0\.0\.1:\d{1,5}$/.test(baseUrl ?? ''), 'Missing supervised browser endpoint')
const outputDir = path.resolve('.work/browser-headless', backend)
let activePage
let gpuSession

async function pixelVerify(request) {
  const value = JSON.parse(await verifyPixels(JSON.stringify(request)))
  assert.equal(value.ok, true, value.error ?? 'browser pixel verification failed')
  return value.value
}

async function text(page, selector) {
  return (await page.locator(selector).textContent())?.trim() ?? ''
}

async function editorScrollHost(page, command) {
  const settle = () => page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  switch (command.op) {
    case 'trace-start': await page.evaluate(() => window.metonicInputTrace.start()); return null;
    case 'trace-stop': await page.evaluate(() => window.metonicInputTrace.stop()); return null;
    case 'trace-sample': return page.evaluate(() => window.metonicInputTrace.sample());
    case 'input-event':
      await page.locator(command.selector).evaluate((input, event) => {
        if (event.value !== undefined) input.value = event.value;
        if (event.start !== undefined) input.setSelectionRange(event.start, event.end);
        input.dispatchEvent(event.type.startsWith('composition') ? new CompositionEvent(event.type, { data: event.data ?? '' }) : new Event(event.type));
      }, command);
      await settle(); return null;
    case 'value': return page.locator(command.selector).inputValue();
    case 'fill': await page.locator(command.selector).fill(command.value); await settle(); return null;
    case 'press': await page.locator(command.selector).press(command.key); await settle(); return null;
    case 'editor-select':
      await page.locator('#text-input').evaluate(input => { input.setSelectionRange(0, input.value.length); input.dispatchEvent(new Event('select')); });
      await settle();
      return null;
    case 'editor-scroll': {
      const value = await page.locator('#text-input').evaluate((input, y) => {
        if (typeof y === 'number') {
          input.scrollTop = y;
          input.dispatchEvent(new Event('scroll'));
        }
        return input.scrollTop;
      }, command.y);
      await settle();
      return value;
    }
    case 'image': {
      await settle();
      return (await page.locator('#canvas').screenshot({ style: '#canvas { border-radius: 0 !important; }' })).toString('base64');
    }
    default: throw new Error(`Unknown editor scroll operation: ${command.op}`);
  }
}

async function diagnostic(page) {
  return page.evaluate(async () => ({
    target: document.querySelector('#target')?.textContent?.trim() ?? '',
    artifactBytes: Number(document.querySelector('#artifact-bytes')?.textContent?.replace(/\D/g, '') || 0),
    dimensions: document.querySelector('#dimensions')?.textContent?.trim() ?? '',
    revision: Number(document.querySelector('#revision')?.textContent || 0),
    submitted: Number(document.querySelector('#submitted')?.textContent || 0),
    transferred: parseInt(document.querySelector('#transferred')?.textContent || '0', 10) || 0,
    loadMs: Number(document.querySelector('#load-ms')?.textContent || 0),
    adapter: await (async () => {
      const adapter = await navigator.gpu?.requestAdapter()
      if (!adapter) return null
      return { vendor: adapter.info?.vendor, architecture: adapter.info?.architecture, device: adapter.info?.device, description: adapter.info?.description, isFallbackAdapter: adapter.info?.isFallbackAdapter }
    })(),
  }))
}

async function waitStatus(page, expected) {
  const actual = await page.waitForFunction(() => {
    const status = document.querySelector('#status')?.textContent?.trim() || ''
    return status && !/^loading/i.test(status) ? status : false
  }, undefined, { timeout: 30_000 }).then((handle) => handle.jsonValue())
  await pixelVerify({ action: 'ready', actual, expected })
}

async function verifyNotes(browser) {
  const results = [];
  for (const target of ['js', 'wasm-gc']) {
    const page = await observedPage(browser, { viewport: { width: 800, height: 600 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    const settle = () => page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    try {
      await page.goto(`${baseUrl}/notes/?target=${target}`);
      await page.waitForFunction(() => {
        const status = document.querySelector('#status')?.textContent;
        return status && !status.startsWith('Loading');
      }, null, { timeout: 30000 });
      assert.equal(await text(page, '#status'), `Ready: Notes (${target})`);
      const artifact = await page.evaluate(async target => {
        const exports = target === 'js' ? Object.keys(await import('./notes.mjs'))
          : WebAssembly.Module.exports(await WebAssembly.compile(await (await fetch('./notes.wasm')).arrayBuffer(),
            { builtins: ['js-string'], importedStringConstants: '_' })).filter(entry => entry.kind === 'function').map(entry => entry.name);
        return { exports: exports.sort(), dev: typeof globalThis.metonicAsyncProbe, trace: typeof globalThis.metonicInputTrace };
      }, target);
      assert.deepEqual(artifact, {
        exports: ['create'], dev: 'undefined', trace: 'undefined',
      });
      const stoppedInstance = await page.evaluate(async target => {
        let factory;
        if (target === 'js') factory = (await import('./notes.mjs')).create;
        else {
          const { wasmImports } = await import('./wasm-imports.mjs');
          const { instance } = await WebAssembly.instantiateStreaming(await fetch('./notes.wasm'), wasmImports(),
            { builtins: ['js-string'], importedStringConstants: '_' });
          factory = instance.exports.create;
        }
        const unused = factory();
        unused.stop();
        unused.stop();
        let rejected = false;
        try { await unused.load_font(); } catch { rejected = true; }
        return { rejected, start: unused.start(null, ''), resize: unused.resize(480, 240),
          render: unused.render(), activate: unused.activate(1), layers: unused.layer_count() };
      }, target);
      assert.deepEqual(stoppedInstance, { rejected: true, start: 0, resize: 0, render: 0, activate: 0, layers: 0 });
      await settle();
      const canvas = page.locator('#canvas');
      const initial = await canvas.screenshot();
      const note = page.locator('#controls textarea');
      assert.equal(await note.inputValue(), 'A small independent application');
      await note.fill('日本語のノート\nSecond line');
      await settle();
      const edited = await canvas.screenshot({ path: path.join(outputDir, `notes-${target}.png`) });
      assert.notDeepEqual(edited, initial, 'Notes editing did not change GPU output');
      await note.evaluate(element => {
        element.focus();
        element.setSelectionRange(0, 3);
        document.dispatchEvent(new Event('selectionchange'));
      });
      await settle();
      assert.notDeepEqual(await canvas.screenshot(), edited, 'Notes selection did not change GPU output');
      await page.locator('#controls button').click();
      await settle();
      assert.equal(await note.inputValue(), '');
      assert.notDeepEqual(await canvas.screenshot(), edited, 'Notes clear did not change GPU output');
      await page.setViewportSize({ width: 420, height: 600 });
      await settle();
      assert.equal(await canvas.evaluate(element => element.width), 372);
      assert.equal(await text(page, '#status'), `Ready: Notes (${target})`);
      const detachedNote = await note.elementHandle();
      await page.locator('#stop').click();
      assert.equal(await text(page, '#status'), 'Stopped.');
      assert.equal(await note.count(), 0);
      assert.equal(await page.locator('#controls button').count(), 0);
      const stopped = await canvas.screenshot();
      await detachedNote.evaluate(element => { element.value = 'late'; element.dispatchEvent(new Event('input')); });
      await detachedNote.dispose();
      await settle();
      assert.deepEqual(await canvas.screenshot(), stopped, 'Stopped Notes accepted a late input');
      const gpuSessions = await page.evaluate(async target => {
        let probe;
        if (target === 'js') probe = await import('/gpu-probe.mjs');
        else {
          const { wasmImports } = await import('/wasm-imports.mjs');
          const { instance } = await WebAssembly.instantiateStreaming(fetch('/gpu-probe.wasm'), wasmImports(),
            { builtins: ['js-string'], importedStringConstants: '_' });
          probe = instance.exports;
        }
        const adapter = await navigator.gpu.requestAdapter();
        const device = await adapter.requestDevice();
        const canvas = document.createElement('canvas');
        canvas.width = canvas.height = 16;
        const context = canvas.getContext('webgpu');
        const format = navigator.gpu.getPreferredCanvasFormat();
        context.configure({ device, format });
        device.pushErrorScope('validation');
        try {
          const result = probe.verify_sessions(device, context, format, new Uint8Array([255, 0, 255, 255]),
            new Float32Array([16, 16, 0, 0, 1, 1, 0, 0]));
          await device.queue.onSubmittedWorkDone();
          const error = await device.popErrorScope();
          return { result, error: error?.message ?? null };
        } finally { context.unconfigure(); device.destroy(); }
      }, target);
      assert.deepEqual(gpuSessions, { result: 1, error: null });
      assert.deepEqual(errors, []);
      results.push({ target, editing: true, selection: true, clear: true, resize: true, stop: true, independentGpuSessions: true });
    } catch (error) { await reportFailure(page); throw error; }
    finally { await page.close(); }
    for (const stage of ['adapter', 'device', 'font']) {
      const pending = await observedPage(browser);
      const errors = [];
      pending.on('pageerror', error => errors.push(error.message));
      try {
        await pending.addInitScript(stage => {
          const state = globalThis.notesLifetime = { held: false, created: 0, destroyed: 0, aborted: 0, canceled: 0, submitted: 0, released: false };
          const hold = value => new Promise(resolve => {
            state.held = true;
            globalThis.releaseNotes = () => { state.released = true; resolve(value); };
          });
          const acquire = navigator.gpu.requestAdapter.bind(navigator.gpu);
          navigator.gpu.requestAdapter = async (...args) => {
            const adapter = await acquire(...args);
            if (stage === 'adapter') return hold(adapter);
            const requestDevice = adapter.requestDevice.bind(adapter);
            adapter.requestDevice = async (...args) => {
              const device = await requestDevice(...args);
              state.created++;
              const destroy = device.destroy.bind(device);
              device.destroy = () => { state.destroyed++; destroy(); };
              const submit = device.queue.submit.bind(device.queue);
              device.queue.submit = (...args) => { state.submitted++; submit(...args); };
              return stage === 'device' ? hold(device) : device;
            };
            return adapter;
          };
          if (stage === 'font') {
            const fetch = window.fetch.bind(window);
            window.fetch = (url, options) => {
              if (!String(url).endsWith('/NotoSansJP.ttf')) return fetch(url, options);
              options.signal.addEventListener('abort', () => state.aborted++, { once: true });
              const stream = globalThis.notesPendingStream = new ReadableStream({
                pull() { state.held = true; }, cancel() { state.canceled++; },
              });
              globalThis.releaseNotes = () => { state.released = true; };
              return Promise.resolve(new Response(stream));
            };
          }
        }, stage);
        await pending.goto(`${baseUrl}/notes/?target=${target}`);
        await pending.waitForFunction(() => globalThis.notesLifetime?.held);
        await pending.locator('#stop').click();
        await pending.evaluate(() => globalThis.releaseNotes());
        await pending.waitForFunction(stage => {
          const state = globalThis.notesLifetime;
          return state.released && (stage === 'adapter' || state.destroyed === 1)
            && (stage !== 'font' || state.aborted === 1 && state.canceled === 1 && !globalThis.notesPendingStream.locked);
        }, stage);
        await pending.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
        assert.equal(await text(pending, '#status'), 'Stopped.');
        assert.equal(await pending.locator('#controls textarea').count(), 0);
        const state = await pending.evaluate(() => globalThis.notesLifetime);
        assert.equal(state.created, stage === 'adapter' ? 0 : 1);
        assert.equal(state.destroyed, stage === 'adapter' ? 0 : 1);
        assert.equal(state.submitted, 0);
        assert.deepEqual(errors, []);
        results.push({ target, stopDuring: stage, released: true });
      } catch (error) { await reportFailure(pending); throw error; }
      finally { await pending.close(); }
    }
  }
  await fs.writeFile(path.join(outputDir, 'notes-results.json'), JSON.stringify(results, null, 2));
  console.log('NOTES_BROWSER_OK js wasm-gc editing selection clear resize stop');
}

async function runTargetUnsafe(browser, target) {
  const page = await observedPage(browser, { viewport: { width: 1000, height: 800 }, deviceScaleFactor: 1 })
  await page.route('**/text-renderer.mjs', async (route) => {
    const response = await route.fetch()
    const source = await response.text()
    const marker = 'upload: (index, pixels) => app.text_gpu_add(index, pixels),'
    assert.equal(source.split(marker).length, 2)
    const transferSource = await fs.readFile('browser_host/runtime/layer-renderer.mjs', 'utf8')
    const transferStart = transferSource.indexOf('const transferred = layerBytes(index);')
    assert(transferStart >= 0)
    const transfer = transferSource.slice(transferStart, transferSource.indexOf('if (upload(index, pixels)'))
      .replace('layerBytes(index)', 'app.view_layer_bytes(index)')
    const verification = `
        const width = app.view_layer_field(index, 2), height = app.view_layer_field(index, 3);
        for (let offset = 0; offset < pixels.length; offset += 4) {
          const expected = app.view_layer_pixel(index, offset / 4);
          const actual = pixels[offset] | (pixels[offset + 1] << 8) | (pixels[offset + 2] << 16) | (pixels[offset + 3] << 24);
          if (actual !== expected) throw new Error('Bulk RGBA differs from per-pixel reference');
        }
        globalThis.rgbaComparedBytes = (globalThis.rgbaComparedBytes ?? 0) + pixels.length;
        if (!globalThis.rgbaTransferTiming && pixels.length >= 240000) {
          const bulk = () => { ${transfer} return pixels; };
          const scalar = () => {
            const bytes = new Uint8Array(width * height * 4);
            for (let at = 0; at < width * height; at += 1) {
              const word = app.view_layer_pixel(index, at);
              bytes[at * 4] = word; bytes[at * 4 + 1] = word >>> 8;
              bytes[at * 4 + 2] = word >>> 16; bytes[at * 4 + 3] = word >>> 24;
            }
            return bytes;
          };
          const samples = { scalar: [], bulk: [] };
          for (let run = 0; run < 40; run += 1) {
            for (const name of run % 2 ? ['bulk', 'scalar'] : ['scalar', 'bulk']) {
              const start = performance.now();
              const output = name === 'bulk' ? bulk() : scalar();
              const elapsed = performance.now() - start;
              for (let at = 0; at < pixels.length; at += 1) {
                if (output[at] !== pixels[at]) throw new Error('Timed transfer changed bytes');
              }
              if (run >= 10) samples[name].push(elapsed);
            }
          }
          globalThis.rgbaTransferTiming = {
            bytes: pixels.length, scalarCalls: pixels.length / 4, bulkCalls: 1,
            scalarMedianMs: samples.scalar.sort((a, b) => a - b)[15],
            bulkMedianMs: samples.bulk.sort((a, b) => a - b)[15],
          };
        }
        `
    await route.fulfill({ response, body: "import { unpack } from './browser-buffer.mjs';\n" + source.replace(marker,
      `upload: (index, pixels) => { ${verification} return app.text_gpu_add(index, pixels); },`) })
  })
  activePage = page
  const pageErrors = []
  page.on('pageerror', (error) => pageErrors.push(String(error)))
  const result = { target, pageerrors: pageErrors, images: {}, idle: {}, stop: {} }
  const targetUrl = new URL(baseUrl)
  targetUrl.searchParams.set('target', target)
  await page.goto(targetUrl.href, { waitUntil: 'domcontentloaded' })
  await waitStatus(page, `Ready: ${target}`)
  const canvas = page.locator('canvas')
  const screenshot = async (name) => {
    const file = path.join(outputDir, `${target}-${name}.png`)
    await canvas.screenshot({ path: file })
    return file
  }
  const hostCommand = async (request) => {
    switch (request.op) {
      case 'diagnostic': return diagnostic(page)
      case 'capture': {
        const file = await screenshot(request.name)
        const size = await canvas.evaluate((c) => ({ width: c.width, height: c.height }))
        return { capture: { png: (await fs.readFile(file)).toString('base64'), canvasWidth: size.width, canvasHeight: size.height } }
      }
      case 'click': await canvas.click({ position: { x: request.x, y: request.y } }); break
      case 'key': await canvas.press('ArrowRight'); break
      case 'viewport': await page.setViewportSize({ width: request.width, height: request.height }); break
      case 'button': await page.locator(request.selector).click(); break
      case 'status': await waitStatus(page, request.expected); break
      case 'sleep': await page.waitForTimeout(request.milliseconds); break
      case 'wait-increment': await page.waitForFunction(({ key, value }) => Number(document.querySelector(`#${key}`)?.textContent) > value, request); break
      case 'wait-dimensions': await page.waitForFunction((old) => document.querySelector('#dimensions')?.textContent !== old, request.value); break
      default: throw new Error(`Unknown browser command: ${request.op}`)
    }
    return null
  }
  Object.assign(result, JSON.parse(await runScene(hostCommand, target)))
  result.rgbaComparedBytes = await page.evaluate(() => globalThis.rgbaComparedBytes ?? 0)
  assert(result.rgbaComparedBytes > 0, 'No real text layer RGBA bytes compared')
  result.rgbaTransferTiming = await page.evaluate(() => globalThis.rgbaTransferTiming ?? null)
  assert(result.rgbaTransferTiming, 'No real text layer transfer measured')
  Object.assign(result, await diagnostic(page))
  return result
}

async function negativeTests(browser, verifier = runFailures) {
  let page
  let errors = []
  let release
  let seen
  const hostCommand = async (request) => {
    switch (request.op) {
      case 'open':
        page = await observedPage(browser, { viewport: { width: 1000, height: 800 }, deviceScaleFactor: 1 })
        errors = []
        page.on('pageerror', (error) => errors.push(String(error)))
        break
      case 'close': release?.(); await page.close(); page = undefined; break
      case 'fail-route': await page.route(request.pattern, (route) => route.fulfill({ status: 503, body: 'unavailable' })); break
      case 'respond-route': await page.route(request.pattern, (route) => route.fulfill({ status: request.status, body: request.body.repeat(request.repeat ?? 1) })); break
      case 'unroute': await page.unroute(request.pattern); break
      case 'reload': await page.reload({ waitUntil: 'domcontentloaded' }); break
      case 'stream-font':
        await page.addInitScript(() => {
          const fetch = window.fetch.bind(window)
          window.fetch = (input, init) => {
            if (!String(input).endsWith('/NotoSansJP.ttf')) return fetch(input, init)
            const observation = globalThis.fontStreamObservation = { pulls: 0, aborts: 0, cancels: 0 }
            init.signal.addEventListener('abort', () => { observation.aborts++ }, { once: true })
            const stream = new ReadableStream({
              pull(controller) {
                observation.pulls++
                if (observation.pulls === 1) controller.enqueue(new Uint8Array(1024))
              },
              cancel() { observation.cancels++ },
            })
            globalThis.fontTestStream = stream
            return Promise.resolve(new Response(stream))
          }
        })
        break
      case 'hold-digest':
        await page.addInitScript(() => {
          const digest = crypto.subtle.digest.bind(crypto.subtle)
          crypto.subtle.digest = async (...args) => {
            const result = await digest(...args)
            globalThis.fontDigestHeld = true
            await new Promise(resolve => { globalThis.releaseFontDigest = resolve })
            globalThis.fontDigestReleased = true
            return result
          }
        })
        break
      case 'digest-held': await page.waitForFunction(() => globalThis.fontDigestHeld === true); break
      case 'scene-gpu-lifecycle': return page.evaluate(async (target) => {
        const { loadApp } = await import('/loader.mjs')
        const { app } = await loadApp(target)
        const result = {}
        const fixture = (failGroup = false) => {
          const counts = { created: 0, destroyed: 0, writes: 0, draws: 0 }
          let resolve, reject
          const pending = new Promise((yes, no) => { resolve = yes; reject = no })
          const device = {
            createShaderModule: () => ({}),
            createRenderPipelineAsync: () => pending,
            createBuffer: () => { counts.created++; return { destroy: () => counts.destroyed++ } },
            createBindGroup: () => { if (failGroup) throw new Error('group failure'); return {} },
            queue: { writeBuffer: () => counts.writes++ },
          }
          return { counts, device, resolve: () => resolve({ getBindGroupLayout: () => ({}) }), reject: () => reject(new Error('pipeline failure')) }
        }
        const pass = (entry) => ({ setPipeline() {}, setBindGroup() {}, draw() { entry.counts.draws++ } })
        const canceled = fixture()
        const canceledInit = app.scene_gpu_init(canceled.device, 'bgra8unorm')
        app.scene_gpu_dispose()
        canceled.resolve()
        result.canceled = { ready: await canceledInit, ...canceled.counts }
        const obsolete = fixture(), current = fixture()
        const oldInit = app.scene_gpu_init(obsolete.device, 'bgra8unorm')
        const currentInit = app.scene_gpu_init(current.device, 'bgra8unorm')
        current.resolve()
        const ready = await currentInit
        obsolete.resolve()
        const oldReady = await oldInit
        const drawn = app.scene_gpu_record(pass(current), new Float32Array(8))
        app.scene_gpu_dispose()
        app.scene_gpu_dispose()
        const afterDispose = app.scene_gpu_record(pass(current), new Float32Array(8))
        result.replaced = { ready, oldReady, drawn, afterDispose, obsoleteCreated: obsolete.counts.created, ...current.counts }
        const failed = fixture()
        const failedInit = app.scene_gpu_init(failed.device, 'bgra8unorm')
        failed.reject()
        let rejected = false
        try { await failedInit } catch { rejected = true }
        app.scene_gpu_dispose()
        result.rejected = { rejected, ...failed.counts }
        const partial = fixture(true)
        const partialInit = app.scene_gpu_init(partial.device, 'bgra8unorm')
        partial.resolve()
        rejected = false
        try { await partialInit } catch { rejected = true }
        app.scene_gpu_dispose()
        result.partial = { rejected, ...partial.counts }
        const frames = fixture()
        let submitted = 0, ended = 0, finished = 0, failFinish = false
        const context = { getCurrentTexture: () => ({ createView: () => ({}) }) }
        frames.device.queue.submit = () => submitted++
        frames.device.createCommandEncoder = () => ({
          beginRenderPass(descriptor) {
            const attachment = descriptor.colorAttachments[0]
            if (attachment.loadOp !== 'clear' || attachment.storeOp !== 'store'
              || attachment.clearValue.r !== .02 || attachment.clearValue.g !== .08
              || attachment.clearValue.b !== .15 || attachment.clearValue.a !== 1) throw new Error('frame attachment changed')
            return { ...pass(frames), end() { ended++ } }
          },
          finish() { finished++; if (failFinish) throw new Error('finish failure'); return {} },
        })
        const frameInit = app.scene_gpu_init(frames.device, 'bgra8unorm')
        frames.resolve()
        await frameInit
        const empty = app.gpu_frame_submit()
        const begun = app.gpu_frame_begin(context)
        const nested = app.gpu_frame_begin(context)
        const scene = app.gpu_frame_scene(new Float32Array(8))
        const sent = app.gpu_frame_submit()
        const duplicate = app.gpu_frame_submit()
        app.gpu_frame_begin(context)
        const invalidText = app.gpu_frame_text(-1, new Float32Array(8))
        const rejectedFrame = app.gpu_frame_submit()
        app.gpu_frame_begin(context)
        failFinish = true
        let finishRejected = false
        try { app.gpu_frame_submit() } catch { finishRejected = true }
        const retryFailed = app.gpu_frame_submit()
        failFinish = false
        let acquisitionRejected = false
        try { app.gpu_frame_begin({ getCurrentTexture() { throw new Error('surface failure') } }) } catch { acquisitionRejected = true }
        const absentAfterAcquisition = app.gpu_frame_submit()
        app.gpu_frame_begin(context)
        app.scene_gpu_dispose()
        const disposedFrame = app.gpu_frame_submit()
        result.frames = { empty, begun, nested, scene, sent, duplicate, invalidText, rejectedFrame,
          finishRejected, retryFailed, acquisitionRejected, absentAfterAcquisition, disposedFrame,
          submitted, ended, finished }
        return result
      }, request.target)
      case 'font-replace': return page.evaluate(async (target) => {
        const { loadApp } = await import('./loader.mjs')
        const { app } = await loadApp(target)
        const originalFetch = window.fetch.bind(window)
        let resolveOld, reads = 0, oldAborts = 0, newAborts = 0, cancels = 0
        let stream
        window.fetch = (input, init) => {
          if (!String(input).endsWith('/NotoSansJP.ttf')) return originalFetch(input, init)
          if (++reads === 1) {
            init.signal.addEventListener('abort', () => oldAborts++, { once: true })
            return new Promise(resolve => { resolveOld = resolve })
          }
          init.signal.addEventListener('abort', () => newAborts++, { once: true })
          stream = new ReadableStream({ cancel() { cancels++ } })
          return Promise.resolve(new Response(stream))
        }
        try {
          const old = app.font_fetch().then(() => false, () => true)
          const current = app.font_fetch().then(() => false, () => true)
          resolveOld(new Response(new Uint8Array([1, 2, 3])))
          const oldRejected = await old
          app.font_fetch_cancel()
          const currentRejected = await current
          await Promise.resolve()
          window.fetch = originalFetch
          const fresh = await app.font_fetch()
          return { oldRejected, currentRejected, oldAborts, newAborts, cancels, locked: stream.locked, freshBytes: fresh.byteLength }
        } finally { window.fetch = originalFetch; app.font_fetch_cancel() }
      }, request.target)
      case 'release-digest':
        await page.evaluate(() => globalThis.releaseFontDigest())
        await page.waitForFunction(() => globalThis.fontDigestReleased === true)
        break
      case 'stream-reading':
        await page.waitForFunction(() => globalThis.fontStreamObservation?.pulls >= 2 && globalThis.fontTestStream.locked)
        break
      case 'stream-cleaned':
        await page.waitForFunction(() => globalThis.fontStreamObservation?.cancels > 0 && !globalThis.fontTestStream.locked)
        return page.evaluate(() => ({ ...globalThis.fontStreamObservation, locked: globalThis.fontTestStream.locked }))
      case 'hold-route': {
        let markSeen
        seen = new Promise((resolve) => { markSeen = resolve })
        const held = new Promise((resolve) => { release = resolve })
        await page.route(request.pattern, async (route) => { markSeen(); await held; await route.continue() })
        break
      }
      case 'goto': await page.goto(`${baseUrl}/?target=${encodeURIComponent(request.target)}`, { waitUntil: 'domcontentloaded' }); break
      case 'request-seen': {
        let timer
        try {
          await Promise.race([seen, new Promise((_, reject) => {
            timer = setTimeout(() => reject(new Error('Held request was not observed')), 30_000)
          })])
        } finally { clearTimeout(timer) }
        break
      }
      case 'release': release(); break
      case 'stop': await page.locator('#stop').click(); break
      case 'network-idle': await page.waitForLoadState('networkidle', { timeout: request.timeout ?? 30_000 }); break
      case 'sleep': await page.waitForTimeout(request.milliseconds); break
      case 'settled-status':
        await page.waitForFunction(() => document.querySelector('#status')?.textContent?.trim() && !/^loading/i.test(document.querySelector('#status').textContent), undefined, { timeout: 30_000 })
        break
      case 'observe': return {
        status: await text(page, '#status'), submitted: (await diagnostic(page)).submitted,
        resetDisabled: await page.locator('#reset').isDisabled(),
        stopDisabled: await page.locator('#stop').isDisabled(),
        textDisabled: await page.locator('#text-input').isDisabled(), errors,
      }
      default: throw new Error(`Unknown failure command: ${request.op}`)
    }
    return null
  }
  try { return JSON.parse(await verifier(hostCommand)) }
  catch (error) { await reportFailure(page); throw error }
  finally { release?.(); await page?.close() }
}

async function runTarget(browser, target) {
  try {
    return await runTargetUnsafe(browser, target)
  } catch (error) {
    console.error(error);
    await reportFailure(activePage)
    throw error
  } finally {
    await activePage?.close().catch(() => {})
    activePage = undefined
  }
}

let browser
try {
  await fs.mkdir(outputDir, { recursive: true })
  const swiftshaderFlags = [
    '--use-webgpu-adapter=swiftshader',
    '--enable-unsafe-webgpu',
    process.platform === 'win32' ? '--use-angle=d3d11-warp' : '--use-angle=swiftshader',
    '--enable-unsafe-swiftshader',
  ]
  browser = await chromium.launch({ headless: true, channel: 'chromium', ...(backend === 'swiftshader' ? { args: swiftshaderFlags } : {}) })
  gpuSession = await browser.newBrowserCDPSession()
  const systemInfo = await gpuSession.send('SystemInfo.getInfo')
  const gpu = systemInfo.gpu ?? {}
  const gpuInfo = { devices: gpu.devices, featureStatus: gpu.featureStatus, auxAttributes: { glRenderer: gpu.auxAttributes?.glRenderer, glVendor: gpu.auxAttributes?.glVendor } }
  await fs.writeFile(path.join(outputDir, 'gpu-info.json'), JSON.stringify(gpuInfo, null, 2))
  let cropIndex = 0
  async function textTarget(browser, target, reference) {
      const page = await observedPage(browser, { viewport: { width: 1000, height: 800 }, deviceScaleFactor: 1 })
      try {
        await page.goto(`${baseUrl}/?target=${target}`)
        await page.waitForFunction((expected) => document.querySelector('#status')?.textContent?.trim() === expected, `Ready: ${target}`, { timeout: 60000 })
        const input = page.locator('#text-input')
        const canvas = page.locator('canvas')
        const crop = async () => {
          // Fractional locator clipping can add a row; align layout origin only for pixel comparison.
          const rect = await canvas.evaluate((element) => { element.style.transform = ''; element.style.position = 'relative'; element.style.left = '0px'; element.style.top = '0px'; const before = element.getBoundingClientRect(); element.style.left = `${Math.ceil(before.x) - before.x}px`; element.style.top = `${Math.ceil(before.y) - before.y}px`; const after = element.getBoundingClientRect(); return { x: after.x, y: after.y, width: after.width, height: after.height } })
          const buffer = await canvas.screenshot()
          await fs.writeFile(path.join(outputDir, `${target}-text-${cropIndex}.png`), buffer)
          cropIndex += 1
          const width = Number(await page.locator('#text-width').innerText())
          const value = await pixelVerify({ action: 'crop', png: buffer.toString('base64'), width })
          return { ...value, rect }
        }
        const hostCommand = async (request) => {
          switch (request.op) {
            case 'crop': return crop()
            case 'focus-scene': await canvas.focus(); await page.waitForTimeout(50); break;
            case 'original': return input.inputValue()
            case 'counts': return {
              width: Number(await page.locator('#text-width').innerText()),
              renders: Number(await page.locator('#text-renders').innerText()),
              uploaded: Number(await page.locator('#text-uploaded').innerText()),
              submitted: Number(await page.locator('#submitted').innerText()),
            }
            case 'fill': await input.fill(request.value); break
            case 'sleep': await page.waitForTimeout(request.milliseconds); break
            case 'key': await canvas.focus(); await canvas.press('ArrowRight'); break
            case 'viewport': await page.setViewportSize({ width: request.width, height: request.height }); break
            case 'wait-submit': await page.waitForFunction((old) => Number(document.querySelector('#submitted')?.textContent) > old, request.value); break
            case 'wait-width': await page.waitForFunction((old) => Number(document.querySelector('#text-width')?.textContent) !== old, request.value); break
            default: throw new Error(`Unknown text command: ${request.op}`)
          }
          return null
        }
        return JSON.parse(await runText(hostCommand, target, reference))
      } catch (error) { await reportFailure(page); throw error }
      finally { await page.close() }
  }
  async function dprTarget(browser, reference) {
    const dpr = await observedPage(browser, { viewport: { width: 1000, height: 800 }, deviceScaleFactor: 2 })
    try {
      await runDpr(async (request) => {
        switch (request.op) {
          case 'goto': await dpr.goto(`${baseUrl}/?target=${encodeURIComponent(request.target)}`); break
          case 'ready':
            await dpr.waitForFunction(() => document.querySelector('#status')?.textContent?.startsWith('Ready:'), null, { timeout: 60000 })
            return text(dpr, '#status')
          case 'align':
            await dpr.locator('canvas').evaluate((element) => { element.style.transform = ''; element.style.position = 'relative'; element.style.left = '0px'; element.style.top = '0px'; const rect = element.getBoundingClientRect(); element.style.left = `${Math.ceil(rect.x) - rect.x}px`; element.style.top = `${Math.ceil(rect.y) - rect.y}px` })
            break
          case 'screenshot': return (await dpr.locator('canvas').screenshot()).toString('base64')
          default: throw new Error(`Unknown DPR command: ${request.op}`)
        }
        return null
      }, reference)
    } catch (error) { await reportFailure(dpr); throw error }
    finally { await dpr.close() }
    return true
  }
  await verifyNotes(browser)
  await verifyDynamicControls(browser, baseUrl, outputDir)
  const output = await runSuite(async (request) => {
    if (request.op === 'input-lifetime' || request.op === 'input-diagnostics') {
      const page = await observedPage(browser);
      const errors = [];
      page.on('pageerror', error => errors.push(error.message));
      const target = request.target;
      const assets = new Map();
      try {
        for (const [url, file, contentType] of [
          ['/app.js', request.op === 'input-diagnostics' ? 'browser_host/_build/js/release/build/local/browser_host/diagnostics/probe/probe.js' : 'browser_host/_build/js/release/build/local/browser_host/probe/probe.js', 'text/javascript'],
          ['/app.wasm', 'browser_host/_build/wasm-gc/release/build/local/browser_host/probe/probe.wasm', 'application/wasm'],
          ['/loader-common.mjs', 'examples/p0/browser/host/loader-common.mjs', 'text/javascript'],
          ['/wasm-imports.mjs', 'browser_host/runtime/wasm-imports.mjs', 'text/javascript'],
          ['/websys-input.mjs', '.work/browser-dist/websys-input.mjs', 'text/javascript'],
        ]) assets.set(url, { body: await fs.readFile(file), contentType });
        const script = target === 'js' ? "import '/app.js';" : `import { wasmImports } from '/loader-common.mjs'; const {instance} = await WebAssembly.instantiateStreaming(fetch('/app.wasm'), wasmImports(), {builtins:['js-string'], importedStringConstants:'_'}); instance.exports._start();`;
        await page.route('http://metonic-input.test/**', route => {
          const pathname = new URL(route.request().url()).pathname;
          if (pathname === '/') return route.fulfill({ contentType: 'text/html', body: `<meta charset="utf-8"><div id="app"></div><script type="module">${script}</script>` });
          return route.fulfill(assets.get(pathname) ?? { status: 404, body: '' });
        });
        await page.goto('http://metonic-input.test/');
        await page.waitForFunction(() => /^(PASS|FAIL)/.test(document.querySelector('#app').textContent), null, { timeout: 10000 });
        return { text: await page.locator('#app').textContent(), errors: errors.length };
      } catch (error) { await reportFailure(page); throw error; }
      finally { await page.close(); }
    }
    switch (request.op) {
      case 'release': {
        const page = await observedPage(browser, { viewport: { width: 1000, height: 800 }, deviceScaleFactor: 1 });
        const fixture = process.env.METONIC_RPC_FIXTURE;
        if (!fixture || !/^http:\/\/127\.0\.0\.1:\d+$/.test(fixture)) throw new Error('Missing supervised HTTP fixture');
        const faultRoute = (route) => route.continue({ url: `${fixture}/rpc` });
        const errors = [], resources = [];
        let lastRpcBody = null;
        page.on('pageerror', (error) => errors.push(error.message));
        page.on('request', (request) => {
          const pathname = new URL(request.url()).pathname;
          resources.push(pathname);
          if (pathname === '/rpc') lastRpcBody = request.postData();
        });
        const settle = () => page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
        try {
          return JSON.parse(await runRelease(async (command) => {
            switch (command.op) {
              case 'fault-route': await page.route('**/rpc', faultRoute); break;
              case 'fault-route-off': await page.unroute('**/rpc', faultRoute); break;
              case 'fixture-active': return Number(await (await page.request.get(`${fixture}/active`)).text());
              case 'sleep': await page.waitForTimeout(command.milliseconds); break;
              case 'goto': await page.goto(`${baseUrl}/release/`); break;
              case 'wait-text': await page.waitForFunction(({ selector, text }) => document.querySelector(selector)?.textContent?.trim() === text, command); break;
              case 'fill': await page.locator(command.selector).fill(command.value); await settle(); break;
              case 'click': await page.locator(command.selector).click(command.x === undefined ? {} : { position: { x: command.x, y: command.y } }); break;
              case 'focus': await page.locator(command.selector).focus(); await settle(); break;
              case 'press': await page.locator(command.selector).press(command.key); break;
              case 'view-bounds': return page.evaluate(() => {
                const canvas = document.querySelector('#canvas').getBoundingClientRect();
                return ['#text-input', '#rpc-load', '#task-start', '#task-cancel', '#rpc-user'].map((selector) => {
                  const element = document.querySelector(selector), rect = element.getBoundingClientRect();
                  return { x: rect.x - canvas.x, y: rect.y - canvas.y, width: rect.width, height: rect.height, opacity: getComputedStyle(element).opacity };
                });
              });
              case 'value': return page.locator(command.selector).inputValue();
              case 'editor-scroll': return editorScrollHost(page, command);
              case 'editor-select': return editorScrollHost(page, command);
              case 'rpc-count': return resources.filter((path) => path === '/rpc').length;
              case 'rpc-body': return lastRpcBody;
              case 'input-event': await page.locator(command.selector).evaluate((input, event) => {
                if (event.value !== undefined) input.value = event.value;
                if (event.start !== undefined) input.setSelectionRange(event.start, event.end);
                input.dispatchEvent(event.type.startsWith('composition')
                  ? new CompositionEvent(event.type, { data: event.data ?? '', bubbles: true })
                  : new InputEvent(event.type, { data: event.data ?? '', isComposing: event.composing ?? false, bubbles: true }));
              }, command); await settle(); break;
              case 'disabled': return page.locator(command.selector).isDisabled();
              case 'no-probe': return page.evaluate(async () => {
                const module = await WebAssembly.compile(await (await fetch('/release/app.wasm')).arrayBuffer(), { builtins: ['js-string'], importedStringConstants: '_' });
                return !('metonicAsyncProbe' in window) && !WebAssembly.Module.exports(module).some(entry => entry.name === 'query_state_json');
              });
              case 'width': return page.locator('#canvas').evaluate((element) => element.width);
              case 'viewport': await page.setViewportSize({ width: command.width, height: 800 }); await settle(); break;
              case 'canvas-height': await page.locator('#canvas').evaluate((element, height) => { element.style.height = height; window.dispatchEvent(new Event('resize')); }, command.height); await settle(); break;
              case 'errors': return errors;
              case 'late-input': await page.evaluate(() => { const input = document.querySelector('#text-input'); input.value = 'late'; input.dispatchEvent(new Event('input')); window.dispatchEvent(new Event('resize')); }); await page.waitForTimeout(350); break;
              case 'image': {
                await settle();
                const canvas = page.locator('#canvas');
                await canvas.evaluate((element) => { element.style.position = 'relative'; element.style.left = '0px'; element.style.top = '0px'; const rect = element.getBoundingClientRect(); element.style.left = `${Math.ceil(rect.x) - rect.x}px`; element.style.top = `${Math.ceil(rect.y) - rect.y}px`; });
                // CSS corner antialiasing is not part of the canvas pixel contract.
                const image = await canvas.screenshot({ style: '#canvas { border-radius: 0 !important; }' });
                await fs.writeFile(path.join(outputDir, `release-${command.name}.png`), image);
                return image.toString('base64');
              }
              case 'excluded-assets': {
                const statuses = await Promise.all(['app.mjs', 'environment-dev.mjs'].map(async (file) => (await page.request.get(`${baseUrl}/release/${file}`)).status()));
                return statuses.every((status) => status === 404) && resources.includes('/release/app.wasm') && resources.every((path) => path === '/rpc' || path.startsWith('/release/'));
              }
              default: throw new Error(`Unknown release operation: ${command.op}`);
            }
            return null;
          }));
        } catch (error) { await reportFailure(page); throw error }
        finally { await page.close(); }
      }
      case 'default-target': {
        const page = await observedPage(browser);
        try {
          await page.goto(`${baseUrl}/`);
          await waitStatus(page, 'Ready: wasm-gc');
          return await text(page, '#target');
        } catch (error) { await reportFailure(page); throw error }
        finally { await page.close(); }
      }
      case 'editor-flow': {
        const page = await observedPage(browser);
        try {
          await page.goto(`${baseUrl}/?target=${encodeURIComponent(request.target)}`);
          await waitStatus(page, `Ready: ${request.target}`);
          await runEditorScroll(command => editorScrollHost(page, command));
          await runQueryObservation(command => editorScrollHost(page, command));
          await page.locator('#text-input').fill('A😀B');
          const preview = await page.evaluate(() => {
            const input = document.querySelector('#text-input');
            input.setSelectionRange(1, 3);
            input.dispatchEvent(new Event('select'));
            input.dispatchEvent(new CompositionEvent('compositionstart', { data: '' }));
            input.dispatchEvent(new CompositionEvent('compositionupdate', { data: '日本' }));
            input.value = 'A日本B';
            input.setSelectionRange(3, 3);
            input.dispatchEvent(new InputEvent('input', { data: '日本', isComposing: true }));
            return window.metonicAsyncProbe.editor();
          });
          await page.evaluate(() => {
            const input = document.querySelector('#text-input');
            input.value = 'A日本B';
            input.setSelectionRange(3, 3);
            input.dispatchEvent(new CompositionEvent('compositionend', { data: '日本' }));
          });
          await page.locator('#rpc-load').click();
          await page.waitForFunction(() => document.querySelector('#rpc-result').textContent !== '');
          await page.setViewportSize({ width: 900, height: 700 });
          await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
          const committed = await page.evaluate(() => window.metonicAsyncProbe.editor());
          await page.locator('#text-input').fill('あうえお');
          await page.evaluate(() => {
            const input = document.querySelector('#text-input');
            input.setSelectionRange(1, 1);
            input.dispatchEvent(new CompositionEvent('compositionstart', { data: '' }));
            input.dispatchEvent(new CompositionEvent('compositionupdate', { data: 'あ' }));
          });
          await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
          const existing = await page.evaluate(() => window.metonicAsyncProbe.editor());
          await page.locator('#reset').click();
          const reset = await page.evaluate(() => window.metonicAsyncProbe.editor());
          await page.locator('#stop').click();
          const stopped = await page.evaluate(() => {
            const input = document.querySelector('#text-input');
            input.value = 'late';
            input.dispatchEvent(new Event('input'));
            input.dispatchEvent(new CompositionEvent('compositionend', { data: 'late' }));
            return window.metonicAsyncProbe.editor();
          });
          return { preview, committed, existing, reset, stopped };
        } catch (error) { await reportFailure(page); throw error }
        finally { await page.close(); }
      }
      case 'rpc': {
        const page = await observedPage(browser);
        const started = performance.now();
        const timeline = [];
        const mark = (event, details = {}) => {
          if (timeline.length < 32) timeline.push({ event, ms: Math.round(performance.now() - started), ...details });
        };
        const rpcRequests = new Map();
        page.on('request', req => {
          if (new URL(req.url()).pathname !== '/rpc') return;
          const id = rpcRequests.size + 1;
          rpcRequests.set(req, id);
          mark('request', { id });
        });
        page.on('response', response => {
          const id = rpcRequests.get(response.request());
          if (id) mark('response', { id, status: response.status() });
        });
        page.on('requestfinished', req => {
          const id = rpcRequests.get(req);
          if (id) mark('finished', { id });
        });
        page.on('requestfailed', req => {
          const id = rpcRequests.get(req);
          if (id) mark('failed', { id, error: req.failure()?.errorText });
        });
        let release;
        try {
          await page.goto(`${baseUrl}/?target=${encodeURIComponent(request.target)}`);
          await waitStatus(page, `Ready: ${request.target}`);
          await page.locator('#text-input').fill(request.text);
          if (request.prior_success) {
            await page.locator('#rpc-user').fill('1');
            await page.locator('#rpc-load').click();
            await page.waitForFunction(() => JSON.parse(document.querySelector('#task-state').textContent)[0] === 2);
            mark('prior-success');
          }
          let seen;
          if (request.mode) {
            let notify;
            seen = new Promise(resolve => { notify = resolve; });
            const held = new Promise(resolve => { release = resolve; });
            let intercepted = false;
            // Expiring interception while aborting the held fetch can stall its
            // replacement in this integrated scenario (#321). Keep routing active.
            await page.route('**/rpc', async route => {
              if (intercepted) {
                mark('continued');
                await route.continue();
                return;
              }
              intercepted = true;
              mark('held');
              notify();
              await held;
              await route.abort();
            });
          }
          await page.locator('#rpc-user').fill(request.user);
          await page.locator('#rpc-load').click();
          if (request.mode) {
            await seen;
            if (request.mode !== 'cancel') {
              await page.locator('#rpc-user').fill('missing');
            }
            await page.evaluate(mode => {
              const status = JSON.parse(document.querySelector('#task-state').textContent)[0];
              if (status !== 1) throw new Error(`RPC pending precondition expired: status=${status}, result=${document.querySelector('#rpc-result').textContent}`);
              document.querySelector(mode === 'cancel' ? '#task-cancel' : '#rpc-load').click();
            }, request.mode);
            mark('action', { mode: request.mode });
            release();
            mark('released');
          }
          // A previous result remains visible while its replacement is still working.
          if (request.mode !== 'cancel') await page.waitForFunction(() => {
            const status = JSON.parse(document.querySelector('#task-state').textContent)[0];
            return status === 2 || status === 3;
          });
          await page.waitForLoadState('networkidle');
          if (request.after_text !== undefined) {
            await page.setViewportSize({ width: 740, height: 800 });
            await page.locator('#text-input').fill(request.after_text);
          }
          const result = await page.evaluate(() => ({
            text: document.querySelector('#text-input').value,
            result: document.querySelector('#rpc-result').textContent,
            status: JSON.parse(document.querySelector('#task-state').textContent)[0],
          }));
          if (request.mode && result.result.includes('RPC: timeout')) {
            console.error('RPC_TIMELINE ' + JSON.stringify({ target: request.target, mode: request.mode, priorSuccess: !!request.prior_success, timeline, result }));
            await reportFailure(page);
          }
          return result;
        } catch (error) {
          console.error('RPC_TIMELINE ' + JSON.stringify({ target: request.target, mode: request.mode, timeline }));
          await reportFailure(page); throw error;
        }
        finally { release?.(); await page.close(); }
      }
      case 'rpc-stream-cleanup': {
        const page = await observedPage(browser);
        let stage = 'ready';
        try {
          await page.goto(`${baseUrl}/?target=${encodeURIComponent(request.target)}`);
          await waitStatus(page, `Ready: ${request.target}`);
          await page.evaluate(() => {
            const original = window.fetch.bind(window);
            const observation = globalThis.rpcStreamObservation = { aborts: 0, cancels: 0, pulls: 0 };
            window.fetch = (url, init) => {
              if (!String(url).endsWith('/rpc')) return original(url, init);
              init.signal.addEventListener('abort', () => observation.aborts++, { once: true });
              const stream = globalThis.rpcTestStream = new ReadableStream({
                pull() { observation.pulls++; },
                cancel() { observation.cancels++; },
              });
              return Promise.resolve(new Response(stream, { headers: { 'Content-Type': 'application/json' } }));
            };
          });
          await page.locator('#rpc-user').fill('1');
          await page.locator('#rpc-load').click();
          stage = 'reading';
          await page.waitForFunction(() => globalThis.rpcTestStream?.locked && globalThis.rpcStreamObservation.pulls > 0);
          if (request.mode === 'cancel') await page.locator('#task-cancel').click();
          stage = 'released';
          await page.waitForFunction(() => globalThis.rpcStreamObservation.cancels === 1 && !globalThis.rpcTestStream.locked);
          return await page.evaluate(() => ({
            ...globalThis.rpcStreamObservation,
            locked: globalThis.rpcTestStream.locked ? 1 : 0,
            status: JSON.parse(document.querySelector('#task-state').textContent)[0],
            result: document.querySelector('#rpc-result').textContent,
          }));
        } catch (error) {
          const observed = await page.evaluate(() => ({
            counts: globalThis.rpcStreamObservation,
            locked: globalThis.rpcTestStream?.locked,
            state: document.querySelector('#task-state')?.textContent,
            result: document.querySelector('#rpc-result')?.textContent,
          })).catch(() => null);
          await reportFailure(page);
          throw new Error(`RPC stream ${request.target}/${request.mode} ${stage}: ${JSON.stringify(observed)}; ${error}`);
        }
        finally { await page.close(); }
      }
      case 'scene': return runTarget(browser, request.target)
      case 'failures': return negativeTests(browser)
      case 'text': return textTarget(browser, request.target, request.reference)
      case 'dpr': return dprTarget(browser, request.reference)
      case 'font-failures': return negativeTests(browser, runFontFailures)
      default: throw new Error(`Unknown suite command: ${request.op}`)
    }
  }, JSON.stringify({ backend, browser: browser.version(), node: process.version }))
  await fs.writeFile(path.join(outputDir, 'results.json'), output)
  console.log(JSON.stringify({ backend, gpu: gpuInfo }, null, 2))
} catch (error) {
  console.error(error)
  process.exitCode = 1
} finally {
  await gpuSession?.detach().catch(() => {})
  await browser?.close().catch(() => {})
}
