import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { createInterface } from 'node:readline'
import { fileURLToPath } from 'node:url'
import fs from 'node:fs/promises'
import path from 'node:path'
import { PNG } from 'pngjs'

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const fallback = process.env.METONIC_GPU_FALLBACK === '1'
const mode = fallback ? 'fallback' : 'default'
const outDir = path.join(repoRoot, '.work', 'native-headless', mode)
const capturePath = path.join(outDir, 'capture.rgba')
const exe = path.join(repoRoot, '_build', 'native', 'release', 'build', 'examples', 'p0', 'native_headless', 'native_headless.exe')
const bridge = path.join(repoRoot, '.work', 'native-cargo', 'release', 'metonic_wgpu_probe.dll')
const reqTimeout = 15_000

await fs.mkdir(outDir, { recursive: true })
const stderrFile = path.join(outDir, 'stderr.log')
const child = spawn(exe, [], { cwd: repoRoot, env: { ...process.env, METONIC_GPU_BRIDGE: path.resolve(bridge), METONIC_CAPTURE_PATH: path.resolve(capturePath) }, stdio: ['pipe', 'pipe', 'pipe'] })
const exitPromise = new Promise((resolve) => { child.once('error', (error) => resolve({ error })); child.once('exit', (code, signal) => resolve({ code, signal })) })
let stderr = ''
child.stderr.on('data', (chunk) => { stderr += chunk.toString() })
const rl = createInterface({ input: child.stdout })
const pending = []
rl.on('line', (line) => pending.shift()?.(line))

function nextLine(timeout = reqTimeout) {
  return new Promise((resolve, reject) => {
    let waiter
    const timer = setTimeout(() => { const index = pending.indexOf(waiter); if (index >= 0) pending.splice(index, 1); reject(new Error('native response timeout')) }, timeout)
    waiter = (line) => { clearTimeout(timer); resolve(line) }
    pending.push(waiter)
  })
}

async function request(value, expect = true) {
  const responsePromise = expect ? nextLine() : undefined
  child.stdin.write(typeof value === 'string' ? `${value}\n` : `${JSON.stringify(value)}\n`)
  if (!expect) return undefined
  const response = JSON.parse(await responsePromise)
  if (typeof value !== 'string') { assert.equal(response.id, value.id); assert.equal(response.version, 1) }
  return response
}

function state(response) { return response.state }
function assertState(response, previous) { assert.deepEqual(state(response), previous) }

async function capturePng(name, response) {
  const rgba = await fs.readFile(capturePath)
  const width = state(response)[6]
  const height = state(response)[7]
  assert.equal(rgba.length, width * height * 4)
  const png = new PNG({ width, height })
  rgba.copy(png.data)
  await fs.writeFile(path.join(outDir, `${name}.png`), PNG.sync.write(png))
  const background = [Math.round(.02 * 255), Math.round(.08 * 255), Math.round(.15 * 255), 255]
  const rect = response.state[4] ? [Math.round(.95 * 255), Math.round(.38 * 255), Math.round(.10 * 255), 255] : [Math.round(.08 * 255), Math.round(.65 * 255), Math.round(.68 * 255), 255]
  const [rx, ry, rw, rh] = [response.state[0], response.state[1], response.state[2], response.state[3]]
  for (let i = 0; i < rgba.length; i += 4) {
    const p = i / 4; const x = p % width; const y = Math.floor(p / width)
    const expected = x >= rx && x < rx + rw && y >= ry && y < ry + rh ? rect : background
    for (let c = 0; c < 4; c++) assert(Math.abs(rgba[i + c] - expected[c]) <= 1, `${name}: pixel mismatch at ${x},${y}`)
  }
  return { width, height, bytes: rgba.length }
}

const results = { mode, captures: [], checks: [] }
async function captureFailure(extraEnv, name) {
  const p = spawn(exe, [], { cwd: repoRoot, env: { ...process.env, METONIC_GPU_BRIDGE: path.resolve(bridge), METONIC_CAPTURE_PATH: path.resolve(capturePath), ...extraEnv }, stdio: ['pipe', 'pipe', 'ignore'] })
  const processExit = new Promise((resolve) => { p.once('error', (error) => resolve({ error })); p.once('exit', (code, signal) => resolve({ code, signal })) })
  const lines = []
  const reader = createInterface({ input: p.stdout })
  reader.on('line', (line) => lines.push(line))
  const send = async (value) => { p.stdin.write(`${JSON.stringify(value)}\n`); for (let i = 0; i < 150; i++) { if (lines.length) return JSON.parse(lines.shift()); await new Promise((resolve) => setTimeout(resolve, 10)) } throw new Error(`${name}: response timeout`) }
  try {
    const snap = await send({ version: 1, id: 1, op: 'snapshot' })
    const cap = await send({ version: 1, id: 2, op: 'capture', expected_revision: snap.state[5] })
    assert.equal(cap.error, 'capture_failed'); assert.equal(cap.frame, 0); assertState(cap, snap.state)
    await send({ version: 1, id: 3, op: 'shutdown' }); p.stdin.end()
    let timer
    let exit
    try {
      exit = await Promise.race([processExit, new Promise((_, reject) => { timer = setTimeout(() => reject(new Error(`${name}: exit timeout`)), 10_000) })])
    } finally { clearTimeout(timer) }
    assert.equal(exit.error, undefined); assert.equal(exit.code, 0)
    results.checks.push(name)
  } finally { reader.close(); if (p.exitCode === null) p.kill('SIGTERM') }
}
try {
  let r = await request({ version: 1, id: 1, op: 'snapshot' })
  assert.equal(r.ok, true)
  const initial = state(r)
  assert.equal(r.frame, 0)

  r = await request({ version: 1, id: 2, op: 'capture', expected_revision: initial[5] })
  assert.equal(r.ok, true); assert.equal(r.frame, 1)
  results.captures.push(await capturePng('initial', r))

  r = await request({ version: 1, id: 3, op: 'move', x: 10, y: 20, expected_revision: initial[5] })
  assert.equal(r.ok, true); assert.equal(r.state[0], 10); assert.equal(r.state[1], 20); assert.equal(r.state[5], initial[5] + 1)
  r = await request({ version: 1, id: 4, op: 'capture', expected_revision: r.state[5] }); assert.equal(r.ok, true)
  assert.equal(r.frame, 2)
  results.captures.push(await capturePng('moved', r))

  const moved = state(r)
  r = await request({ version: 1, id: 5, op: 'activate', expected_revision: moved[5] }); assert.equal(r.ok, true)
  r = await request({ version: 1, id: 6, op: 'capture', expected_revision: r.state[5] }); assert.equal(r.ok, true)
  assert.equal(r.frame, 3)
  results.captures.push(await capturePng('active', r))

  r = await request({ version: 1, id: 7, op: 'resize', width: 317, height: 193, expected_revision: r.state[5] }); assert.equal(r.ok, true)
  r = await request({ version: 1, id: 8, op: 'capture', expected_revision: r.state[5] }); assert.equal(r.ok, true)
  assert.equal(r.frame, 4)
  results.captures.push(await capturePng('resized', r))

  const stable = state(r)
  r = await request({ version: 1, id: 9, op: 'move', x: 0, y: 0, expected_revision: stable[5] - 1 }); assert.equal(r.error, 'stale_revision'); assertState(r, stable)
  r = await request({ version: 1, id: 10, op: 'snapshot' }); assert.equal(r.frame, 4); assertState(r, stable)
  for (const [id, value] of [[11, { version: 1, id: 11, op: 'resize', width: 0, height: 1 }], [12, { version: 1, id: 12, op: 'nope' }], [13, { version: 2, id: 13, op: 'snapshot' }]]) {
    r = await request(value); assert.equal(r.ok, false); assertState(r, stable)
  }
  r = await request('{malformed'); assert.equal(r.ok, false); assertState(r, stable)
  r = await request('x'.repeat(5000)); assert.equal(r.error, 'line_too_long'); assert.equal(r.frame, 4); assertState(r, stable)
  r = await request({ version: 1, id: 14, op: 'snapshot' }); assert.equal(r.ok, true); assertState(r, stable)
  r = await request({ version: 1, id: 15, op: 'shutdown' }); assert.equal(r.ok, true)
  let exitTimer
  let exit
  try {
    exit = await Promise.race([exitPromise, new Promise((_, reject) => { exitTimer = setTimeout(() => reject(new Error('native exit timeout')), 10_000) })])
  } finally { clearTimeout(exitTimer) }
  assert.equal(exit.code, 0)
  assert.match(stderr, /DX12/i)
  const eofChild = spawn(exe, [], { cwd: repoRoot, env: { ...process.env, METONIC_GPU_BRIDGE: path.resolve(bridge), METONIC_CAPTURE_PATH: path.resolve(capturePath) }, stdio: ['pipe', 'pipe', 'ignore'] })
  const eofExit = new Promise((resolve) => { eofChild.once('error', (error) => resolve({ error })); eofChild.once('exit', (code, signal) => resolve({ code, signal })) })
  eofExit.then(() => { if (eofChild.exitCode === null) eofChild.kill('SIGTERM') })
  let eofOutput = ''
  const eofStdoutClosed = new Promise((resolve) => eofChild.stdout.once('close', resolve))
  eofChild.stdout.on('data', (chunk) => { eofOutput += chunk.toString() })
  eofChild.stdin.end()
  let eofTimer
  let eofResult
  try {
    eofResult = await Promise.race([eofExit, new Promise((_, reject) => { eofTimer = setTimeout(() => reject(new Error('EOF process exit timeout')), 10_000) })])
  } finally {
    clearTimeout(eofTimer)
    if (eofChild.exitCode === null) eofChild.kill('SIGTERM')
  }
  assert.equal(eofResult.error, undefined); assert.equal(eofResult.code, 0)
  await eofStdoutClosed
  assert.equal(eofOutput.trim(), '')
  results.adapter = stderr.trim()
  await captureFailure({ METONIC_GPU_BRIDGE: path.join(outDir, 'missing-probe.dll') }, 'gpu-failure')
  await captureFailure({ METONIC_CAPTURE_PATH: undefined }, 'capture-path-failure')
  results.checks.push('protocol/state/errors/shutdown')
} finally {
  await fs.writeFile(stderrFile, stderr)
  rl.close()
  if (child.exitCode === null) child.kill('SIGTERM')
}
await fs.writeFile(path.join(outDir, 'results.json'), JSON.stringify(results, null, 2))
console.log(JSON.stringify(results, null, 2))
