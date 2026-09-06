import { spawn } from 'node:child_process'
import process from 'node:process'
import assert from 'node:assert/strict'
import fs from 'node:fs/promises'
import path from 'node:path'
import { chromium } from 'playwright'
import { PNG } from 'pngjs'

const host = '127.0.0.1'
const port = 4173
const backend = process.env.METONIC_GPU_BACKEND ?? 'default'
assert(['default', 'swiftshader'].includes(backend), 'METONIC_GPU_BACKEND must be default or swiftshader')
const baseUrl = `http://${host}:${port}`
const outputDir = path.resolve('.work/browser-headless', backend)
const targets = ['js', 'wasm-gc']
let activePage

function waitForReady(child) {
  return new Promise((resolve, reject) => {
    let output = ''
    let timer
    const onData = (chunk) => {
      output += chunk.toString()
      if (output.includes(`http://${host}:${port}/\n`)) {
        cleanup()
        resolve()
      }
    }
    const onExit = (code) => {
      cleanup()
      reject(new Error(`browser server exited before ready (${code}): ${output}`))
    }
    const onError = (error) => { cleanup(); reject(error) }
    const cleanup = () => {
      clearTimeout(timer)
      child.stdout?.off('data', onData)
      child.off('exit', onExit)
      child.off('error', onError)
    }
    child.stdout?.on('data', onData)
    child.stderr?.on('data', (chunk) => { output += chunk.toString() })
    child.on('exit', onExit)
    child.on('error', onError)
    timer = setTimeout(() => { cleanup(); reject(new Error(`browser server ready timeout: ${output}`)) }, 10_000)
  })
}

async function readPng(file) {
  const data = await fs.readFile(file)
  return PNG.sync.read(data)
}

function bbox(png, predicate) {
  let minX = png.width
  let minY = png.height
  let maxX = -1
  let maxY = -1
  for (let y = 0; y < png.height; y++) {
    for (let x = 0; x < png.width; x++) {
      const i = (y * png.width + x) * 4
      if (predicate(png.data[i], png.data[i + 1], png.data[i + 2], png.data[i + 3])) {
        minX = Math.min(minX, x)
        minY = Math.min(minY, y)
        maxX = Math.max(maxX, x)
        maxY = Math.max(maxY, y)
      }
    }
  }
  return maxX < 0 ? null : { x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1 }
}

const teal = (r, g, b, a) => a > 180 && r < 80 && g > 100 && b > 100
const orange = (r, g, b, a) => a > 180 && r > 180 && g >= 50 && g <= 150 && b < 80

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
  assert.equal(actual, expected)
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
  const initial = await screenshot('initial')
  const initialPng = await readPng(initial)
  const initialBox = bbox(initialPng, teal)
  if (!initialBox || Math.abs(initialBox.width - 120) > 2 || Math.abs(initialBox.height - 72) > 2) throw new Error(`${target}: invalid initial teal bbox ${JSON.stringify(initialBox)}`)
  result.images.initial = initialBox
  const initialCanvasSize = await canvas.evaluate((c) => ({ width: c.width, height: c.height }))
  // DPR 1 locator screenshots can round fractional CSS clip edges by one pixel.
  assert(Math.abs(initialPng.width - initialCanvasSize.width) <= 1)
  assert(Math.abs(initialPng.height - initialCanvasSize.height) <= 1)
  const beforeActivate = await diagnostic(page)
  await canvas.click({ position: { x: initialBox.x + 60, y: initialBox.y + 36 } })
  await page.waitForFunction((old) => Number(document.querySelector('#revision')?.textContent || 0) > old, beforeActivate.revision)
  await page.waitForFunction((old) => Number(document.querySelector('#submitted')?.textContent || 0) > old, beforeActivate.submitted)
  const active = await screenshot('active')
  const activeBox = bbox(await readPng(active), orange)
  if (!activeBox || Math.abs(activeBox.width - 120) > 2 || Math.abs(activeBox.height - 72) > 2) throw new Error(`${target}: invalid active orange bbox ${JSON.stringify(activeBox)}`)
  result.images.active = activeBox
  assert(Math.abs(activeBox.x - initialBox.x) <= 2 && Math.abs(activeBox.y - initialBox.y) <= 2)
  const beforeMove = await diagnostic(page)
  await canvas.press('ArrowRight')
  await page.waitForFunction((old) => Number(document.querySelector('#revision')?.textContent || 0) > old, beforeMove.revision)
  await page.waitForFunction((old) => Number(document.querySelector('#submitted')?.textContent || 0) > old, beforeMove.submitted)
  const moved = await screenshot('moved')
  result.images.moved = bbox(await readPng(moved), orange)
  assert(result.images.moved)
  assert(Math.abs(result.images.moved.x - activeBox.x - 10) <= 1 && Math.abs(result.images.moved.y - activeBox.y) <= 1)
  const beforeResize = await diagnostic(page)
  const beforeDimensions = await text(page, '#dimensions')
  await page.setViewportSize({ width: 800, height: 700 })
  await page.waitForFunction((old) => (document.querySelector('#dimensions')?.textContent || '') !== old, beforeDimensions)
  await page.waitForFunction((old) => Number(document.querySelector('#submitted')?.textContent || 0) > old, beforeResize.submitted)
  const resized = await screenshot('resized')
  result.images.resized = bbox(await readPng(resized), orange)
  const resizedPng = await readPng(resized)
  const canvasSize = await canvas.evaluate((c) => ({ width: c.width, height: c.height }))
  // DPR 1 locator screenshots can round fractional CSS clip edges by one pixel.
  assert(Math.abs(resizedPng.width - canvasSize.width) <= 1)
  assert(Math.abs(resizedPng.height - canvasSize.height) <= 1)
  assert(result.images.resized && result.images.resized.x + result.images.resized.width <= canvasSize.width && result.images.resized.y + result.images.resized.height <= canvasSize.height)
  const idleBefore = await diagnostic(page)
  await new Promise((resolve) => setTimeout(resolve, 250))
  const idleAfter = await diagnostic(page)
  result.idle = { before: idleBefore, after: idleAfter, unchanged: JSON.stringify(idleBefore) === JSON.stringify(idleAfter) }
  assert.equal(idleBefore.submitted, idleAfter.submitted)
  const beforeReset = await diagnostic(page)
  await page.locator('#reset').click()
  await waitStatus(page, `Ready: ${target}`)
  await page.waitForFunction((old) => Number(document.querySelector('#submitted')?.textContent || 0) > old, beforeReset.submitted)
  const reset = await screenshot('reset')
  result.images.reset = bbox(await readPng(reset), teal)
  assert(result.images.reset && Math.abs(result.images.reset.width - 120) <= 2 && Math.abs(result.images.reset.height - 72) <= 2)
  await page.locator('#stop').click()
  await waitStatus(page, 'Stopped.')
  const stopped = await diagnostic(page)
  await canvas.click({ position: { x: 10, y: 10 } }).catch(() => {})
  await canvas.press('ArrowRight').catch(() => {})
  await page.setViewportSize({ width: 700, height: 600 })
  await new Promise((resolve) => setTimeout(resolve, 250))
  const stoppedAfter = await diagnostic(page)
  result.stop = { before: stopped, after: stoppedAfter, frameUnchanged: stopped.revision === stoppedAfter.revision && stopped.submitted === stoppedAfter.submitted }
  assert.equal(stopped.revision, stoppedAfter.revision)
  assert.equal(stopped.submitted, stoppedAfter.submitted)
  Object.assign(result, await diagnostic(page))
  if (backend === 'swiftshader') assert(/swiftshader/i.test(`${result.adapter?.description} ${result.adapter?.architecture}`))
  if (pageErrors.length) throw new Error(`${target}: page errors: ${pageErrors.join('; ')}`)
  return result
}

async function negativeTests(browser) {
  const negative = []
  const invalid = await browser.newPage({ viewport: { width: 1000, height: 800 }, deviceScaleFactor: 1 })
  const invalidErrors = []
  invalid.on('pageerror', (error) => invalidErrors.push(String(error)))
  try {
    await invalid.goto(`${baseUrl}/?target=invalid`, { waitUntil: 'domcontentloaded' })
    await invalid.waitForFunction(() => document.querySelector('#status')?.textContent?.trim() && !/^loading/i.test(document.querySelector('#status').textContent), undefined, { timeout: 30_000 })
    assert.match(await text(invalid, '#status'), /unknown target/i)
    assert.equal(Number((await diagnostic(invalid)).submitted), 0)
    assert.deepEqual(invalidErrors, [])
    negative.push({ name: 'invalid-target', status: await text(invalid, '#status'), frames: 0 })
  } finally { await invalid.close() }

  for (const target of targets) {
    const fail = await browser.newPage({ viewport: { width: 1000, height: 800 }, deviceScaleFactor: 1 })
    const failErrors = []
    fail.on('pageerror', (error) => failErrors.push(String(error)))
    try {
      await fail.route('**/app.mjs', (route) => route.fulfill({ status: 503, body: 'unavailable' }))
      await fail.route('**/app.wasm', (route) => route.fulfill({ status: 503, body: 'unavailable' }))
      await fail.goto(`${baseUrl}/?target=${target}`, { waitUntil: 'domcontentloaded' })
      await fail.waitForFunction(() => document.querySelector('#status')?.textContent?.trim() && !/^loading/i.test(document.querySelector('#status').textContent), undefined, { timeout: 30_000 })
      assert.match(await text(fail, '#status'), /Unable to fetch/i)
      const d = await diagnostic(fail)
      assert.equal(d.submitted, 0)
      assert.equal(await fail.locator('#reset').isDisabled(), true)
      assert.equal(await fail.locator('#stop').isDisabled(), true)
      assert.deepEqual(failErrors, [])
      negative.push({ name: `${target}-load-failure`, status: await text(fail, '#status'), frames: 0 })
    } finally { await fail.close() }
  }

  const race = await browser.newPage({ viewport: { width: 1000, height: 800 }, deviceScaleFactor: 1 })
  const raceErrors = []
  race.on('pageerror', (error) => raceErrors.push(String(error)))
  let release
  const held = new Promise((resolve) => { release = resolve })
  const requestSeen = race.waitForRequest('**/app.wasm', { timeout: 30_000 })
  try {
    await race.route('**/app.wasm', async (route) => { await held; await route.continue() })
    await race.goto(`${baseUrl}/?target=wasm-gc`, { waitUntil: 'domcontentloaded' })
    await requestSeen
    await race.locator('#stop').click()
    await waitStatus(race, 'Stopped.')
    assert.equal((await diagnostic(race)).submitted, 0)
    assert.equal(await race.locator('#reset').isDisabled(), true)
    assert.equal(await race.locator('#stop').isDisabled(), true)
    assert.deepEqual(raceErrors, [])
    release()
    await race.waitForLoadState('networkidle')
    await new Promise((resolve) => setTimeout(resolve, 500))
    assert.equal(await text(race, '#status'), 'Stopped.')
    assert.equal((await diagnostic(race)).submitted, 0)
    negative.push({ name: 'wasm-init-race', status: 'Stopped.', frames: 0 })
  } finally { release(); await race.close() }
  return negative
}

async function runTarget(browser, target) {
  try {
    return await runTargetUnsafe(browser, target)
  } catch (error) {
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

const server = spawn(process.execPath, ['scripts/serve-browser.mjs'], { stdio: ['ignore', 'pipe', 'pipe'] })
let browser
try {
  await fs.mkdir(outputDir, { recursive: true })
  await waitForReady(server)
  browser = await chromium.launch({ headless: true, channel: 'chromium', ...(backend === 'swiftshader' ? { args: ['--use-webgpu-adapter=swiftshader', '--enable-unsafe-webgpu'] } : {}) })
  const results = []
  for (const target of targets) results.push(await runTarget(browser, target))
  const output = { backend, browser: browser.version(), node: process.version, targets: results, negative: await negativeTests(browser) }
  await fs.writeFile(path.join(outputDir, 'results.json'), JSON.stringify(output, null, 2))
  console.log(JSON.stringify(output, null, 2))
} catch (error) {
  console.error(error)
  process.exitCode = 1
} finally {
  await browser?.close().catch(() => {})
  if (!server.killed) server.kill('SIGTERM')
}
