import assert from 'node:assert/strict'
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { PNG } from 'pngjs'
import { NativeClient } from '../tools/devtools/native-client.mjs'

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const fallback = process.env.METONIC_GPU_FALLBACK === '1'
const mode = fallback ? 'fallback' : 'default'
const exe = path.join(repoRoot, '_build', 'native', 'release', 'build', 'examples', 'p0', 'native_headless', 'native_headless.exe')
const bridge = path.join(repoRoot, '.work', 'native-cargo', 'release', 'metonic_wgpu_probe.dll')
const resultDir = path.join(repoRoot, '.work', 'native-control')
await mkdir(resultDir, { recursive: true })
const tempRoot = await mkdtemp(path.join(resultDir, 'session-'))
const capturePath = path.join(tempRoot, 'capture.rgba')
const resultPath = path.join(resultDir, `${mode}.json`)
const client = new NativeClient({ executable: exe, bridge: path.resolve(bridge), capturePath: path.resolve(capturePath) })
const result = { mode, checks: [], adapter: null }

function pixelAssert(rgba, response, active) {
  const width = response.state[6]; const height = response.state[7]
  assert.equal(rgba.length, width * height * 4)
  const bg = [5, 20, 38, 255]
  const rect = active ? [242, 97, 26, 255] : [20, 166, 173, 255]
  const [rx, ry, rw, rh] = response.state
  for (let i = 0; i < rgba.length; i += 4) {
    const p = i / 4; const x = p % width; const y = Math.floor(p / width)
    const expected = x >= rx && x < rx + rw && y >= ry && y < ry + rh ? rect : bg
    for (let c = 0; c < 4; c++) assert(Math.abs(rgba[i + c] - expected[c]) <= 1, `pixel mismatch ${x},${y}`)
  }
}

try {
  let response = await client.request('snapshot')
  assert.equal(response.ok, true); assert.equal(response.frame, 0)
  const initialRevision = response.state[5]
  response = await client.request('move', { x: 10, y: 20, expected_revision: initialRevision })
  assert.equal(response.ok, true); assert.equal(response.state[0], 10); assert.equal(response.state[1], 20)
  response = await client.request('activate', { expected_revision: response.state[5] })
  assert.equal(response.ok, true); assert.equal(response.state[4], 1)
  const capture = await client.capture({ expected_revision: response.state[5] })
  assert.equal(capture.response.frame, 1); assert.equal(capture.response.state[0], 10); assert.equal(capture.response.state[1], 20)
  pixelAssert(capture.rgba, capture.response, true)
  const png = new PNG({ width: capture.response.state[6], height: capture.response.state[7] })
  capture.rgba.copy(png.data)
  await writeFile(path.join(resultDir, `${mode}.png`), PNG.sync.write(png))
  result.checks.push('snapshot/move/activate/capture/pixels')

  const stable = capture.response.state
  const stale = await client.request('move', { x: 0, y: 0, expected_revision: stable[5] - 1 })
  assert.equal(stale.ok, false); assert.equal(stale.error, 'stale_revision'); assert.deepEqual(stale.state, stable)
  await assert.rejects(client.capture({ expected_revision: stable[5] - 1 }))
  result.checks.push('stale mutation/capture')

  const concurrent = await Promise.allSettled([client.capture({ expected_revision: stable[5] }), client.capture({ expected_revision: stable[5] })])
  assert.equal(concurrent.filter((item) => item.status === 'fulfilled').length, 1)
  assert.equal(concurrent.filter((item) => item.status === 'rejected' && /busy/i.test(String(item.reason))).length, 1)
  result.checks.push('capture busy serialization')
  result.adapter = client.diagnostics
} finally {
  await client.close()
  await rm(tempRoot, { recursive: true, force: true })
  await writeFile(resultPath, JSON.stringify(result, null, 2))
}

console.log(JSON.stringify(result, null, 2))
