import process from 'node:process'
import assert from 'node:assert/strict'
import fs from 'node:fs/promises'
import path from 'node:path'
import { chromium } from 'playwright'
import { verify as verifyPixels, runScene, runFailures, runFontFailures, runText, runDpr, runSuite, runRelease } from '../_build/js/release/build/tools/verify_browser_pixels/verify_browser_pixels.js'

if (process.env.METONIC_BROWSER_SUPERVISED !== '1') throw new Error('Run mise run browser:async/headless')

const host = '127.0.0.1'
const port = 4173
const backend = process.env.METONIC_GPU_BACKEND ?? 'default'
assert(['default', 'swiftshader'].includes(backend), 'METONIC_GPU_BACKEND must be default or swiftshader')
const baseUrl = `http://${host}:${port}`
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

async function runTargetUnsafe(browser, target) {
  const page = await browser.newPage({ viewport: { width: 1000, height: 800 }, deviceScaleFactor: 1 })
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
        page = await browser.newPage({ viewport: { width: 1000, height: 800 }, deviceScaleFactor: 1 })
        errors = []
        page.on('pageerror', (error) => errors.push(String(error)))
        break
      case 'close': release?.(); await page.close(); page = undefined; break
      case 'fail-route': await page.route(request.pattern, (route) => route.fulfill({ status: 503, body: 'unavailable' })); break
      case 'respond-route': await page.route(request.pattern, (route) => route.fulfill({ status: request.status, body: request.body })); break
      case 'unroute': await page.unroute(request.pattern); break
      case 'reload': await page.reload({ waitUntil: 'domcontentloaded' }); break
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
  finally { release?.(); await page?.close() }
}

async function runTarget(browser, target) {
  try {
    return await runTargetUnsafe(browser, target)
  } catch (error) {
    console.error(error);
    let status = ''
    if (activePage) {
      status = await activePage.locator('#status').textContent().catch(() => '')
      await activePage.screenshot({ path: path.join(outputDir, `${target}-failure.png`) }).catch(() => {})
    }
    throw new Error(`${target} failed (status=${status?.trim() || 'unknown'})`, { cause: error })
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
      const page = await browser.newPage({ viewport: { width: 1000, height: 800 }, deviceScaleFactor: 1 })
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
      } finally { await page.close() }
  }
  async function dprTarget(browser, reference) {
    const dpr = await browser.newPage({ viewport: { width: 1000, height: 800 }, deviceScaleFactor: 2 })
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
    } finally { await dpr.close() }
    return true
  }
  const output = await runSuite(async (request) => {
    switch (request.op) {
      case 'release': {
        const page = await browser.newPage({ viewport: { width: 1000, height: 800 }, deviceScaleFactor: 1 });
        const fixture = process.env.METONIC_RPC_FIXTURE;
        if (!fixture || !/^http:\/\/127\.0\.0\.1:\d+$/.test(fixture)) throw new Error('Missing supervised HTTP fixture');
        const faultRoute = (route) => route.continue({ url: `${fixture}/rpc` });
        const errors = [], resources = [];
        page.on('pageerror', (error) => errors.push(error.message));
        page.on('request', (request) => resources.push(new URL(request.url()).pathname));
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
              case 'click': await page.locator(command.selector).click(); break;
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
              case 'rpc-count': return resources.filter((path) => path === '/rpc').length;
              case 'input-event': await page.locator(command.selector).evaluate((input, event) => {
                if (event.value !== undefined) input.value = event.value;
                if (event.start !== undefined) input.setSelectionRange(event.start, event.end);
                input.dispatchEvent(event.type.startsWith('composition')
                  ? new CompositionEvent(event.type, { data: event.data ?? '', bubbles: true })
                  : new InputEvent(event.type, { data: event.data ?? '', isComposing: event.composing ?? false, bubbles: true }));
              }, command); await settle(); break;
              case 'disabled': return page.locator(command.selector).isDisabled();
              case 'no-probe': return page.evaluate(() => !('metonicAsyncProbe' in window));
              case 'width': return page.locator('#canvas').evaluate((element) => element.width);
              case 'viewport': await page.setViewportSize({ width: command.width, height: 800 }); await settle(); break;
              case 'canvas-height': await page.locator('#canvas').evaluate((element, height) => { element.style.height = height; window.dispatchEvent(new Event('resize')); }, command.height); await settle(); break;
              case 'errors': return errors;
              case 'late-input': await page.evaluate(() => { const input = document.querySelector('#text-input'); input.value = 'late'; input.dispatchEvent(new Event('input')); window.dispatchEvent(new Event('resize')); }); await page.waitForTimeout(350); break;
              case 'image': {
                await settle();
                const canvas = page.locator('#canvas');
                await canvas.evaluate((element) => { element.style.position = 'relative'; element.style.left = '0px'; element.style.top = '0px'; const rect = element.getBoundingClientRect(); element.style.left = `${Math.ceil(rect.x) - rect.x}px`; element.style.top = `${Math.ceil(rect.y) - rect.y}px`; });
                const image = await canvas.screenshot();
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
        } finally { await page.close(); }
      }
      case 'default-target': {
        const page = await browser.newPage();
        try {
          await page.goto(`${baseUrl}/`);
          await waitStatus(page, 'Ready: wasm-gc');
          return await text(page, '#target');
        } finally { await page.close(); }
      }
      case 'editor-flow': {
        const page = await browser.newPage();
        try {
          await page.goto(`${baseUrl}/?target=${encodeURIComponent(request.target)}`);
          await waitStatus(page, `Ready: ${request.target}`);
          await page.locator('#text-input').fill('A😀B');
          const preview = await page.evaluate(() => {
            const input = document.querySelector('#text-input');
            input.setSelectionRange(1, 3);
            input.dispatchEvent(new Event('select'));
            input.dispatchEvent(new CompositionEvent('compositionstart', { data: '' }));
            input.dispatchEvent(new CompositionEvent('compositionupdate', { data: '日本' }));
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
          return { preview, committed, reset, stopped };
        } finally { await page.close(); }
      }
      case 'rpc': {
        const page = await browser.newPage();
        let release;
        try {
          await page.goto(`${baseUrl}/?target=${encodeURIComponent(request.target)}`);
          await waitStatus(page, `Ready: ${request.target}`);
          await page.locator('#text-input').fill(request.text);
          let seen;
          if (request.mode) {
            let notify;
            seen = new Promise(resolve => { notify = resolve; });
            const held = new Promise(resolve => { release = resolve; });
            await page.route('**/rpc', async route => {
              notify();
              await held;
              await route.abort();
            }, { times: 1 });
          }
          await page.locator('#rpc-user').fill(request.user);
          await page.locator('#rpc-load').click();
          if (request.mode) {
            await seen;
            if (request.mode === 'cancel') await page.locator('#task-cancel').click();
            else {
              await page.locator('#rpc-user').fill('missing');
              await page.locator('#rpc-load').click();
            }
            release();
          }
          if (request.mode !== 'cancel') await page.waitForFunction(() => document.querySelector('#rpc-result').textContent !== '');
          await page.waitForLoadState('networkidle');
          if (request.after_text !== undefined) {
            await page.setViewportSize({ width: 740, height: 800 });
            await page.locator('#text-input').fill(request.after_text);
          }
          return await page.evaluate(() => ({
            text: document.querySelector('#text-input').value,
            result: document.querySelector('#rpc-result').textContent,
            status: JSON.parse(document.querySelector('#task-state').textContent)[0],
          }));
        } finally { release?.(); await page.close(); }
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
