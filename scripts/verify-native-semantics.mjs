import assert from 'node:assert/strict'
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { NativeClient } from '../tools/devtools/native-client.mjs'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const mode = process.env.METONIC_GPU_FALLBACK === '1' ? 'fallback' : 'default'
const exe = path.join(root, '_build', 'native', 'release', 'build', 'examples', 'p0', 'native_headless', 'native_headless.exe')
const bridge = path.join(root, '.work', 'native-cargo', 'release', 'metonic_wgpu_probe.dll')
const out = path.join(root, '.work', 'native-semantics')
await mkdir(out, { recursive: true })
const tmp = await mkdtemp(path.join(out, 'session-'))
const client = new NativeClient({ executable: exe, bridge: path.resolve(bridge), capturePath: path.join(tmp, 'capture.rgba') })
const result = { mode, checks: [] }
const node = (n) => ({ session: n.session, window: n.window, id: n.id, generation: n.generation })

function pixels(rgba, response, active) {
  const width = response.state[6]; const height = response.state[7]
  const bg = [5, 20, 38, 255]; const fg = active ? [242, 97, 26, 255] : [20, 166, 173, 255]
  assert.equal(rgba.length, width * height * 4)
  for (let i = 0; i < rgba.length; i += 4) {
    const p = i / 4; const x = p % width; const y = Math.floor(p / width)
    const inside = x >= response.state[0] && x < response.state[0] + response.state[2] && y >= response.state[1] && y < response.state[1] + response.state[3]
    const expected = inside ? fg : bg
    for (let c = 0; c < 4; c++) assert(Math.abs(rgba[i + c] - expected[c]) <= 1)
  }
}

try {
  let r = await client.request('snapshot')
  assert.equal(r.nodes.length, 2)
  const button = r.nodes[0]; const input = r.nodes[1]
  let semanticRevision = r.semantic_revision
  r = await client.request('semantic_activate', { node: node(button), expected_semantic_revision: semanticRevision })
  assert.equal(r.ok, true); assert.equal(r.nodes[0].value, 'on'); semanticRevision = r.semantic_revision
  r = await client.capture(); assert.equal(r.response.state[4], 1); pixels(r.rgba, r.response, true)
  result.checks.push('activate/capture')
  r = await client.request('semantic_set_text', { node: node(input), text: 'A😀日本', expected_semantic_revision: semanticRevision })
  assert.equal(r.ok, true); assert.equal(r.nodes[1].selection_end, 5); semanticRevision = r.semantic_revision
  r = await client.request('semantic_set_selection', { node: node(input), start: 1, end: 3, expected_semantic_revision: semanticRevision })
  assert.equal(r.ok, true); semanticRevision = r.semantic_revision
  const stable = r.nodes
  r = await client.request('semantic_set_selection', { node: node(input), start: 2, end: 2, expected_semantic_revision: semanticRevision })
  assert.equal(r.ok, false); assert.equal(r.error, 'invalid_selection'); assert.deepEqual(r.nodes, stable)
  r = await client.request('semantic_focus', { node: node(input), expected_semantic_revision: semanticRevision }); assert.equal(r.ok, true); semanticRevision = r.semantic_revision
  r = await client.request('semantic_focus', { node: node(button), expected_semantic_revision: semanticRevision }); assert.equal(r.ok, true); assert.equal(r.nodes[0].focused, true); assert.equal(r.nodes[1].focused, false); semanticRevision = r.semantic_revision
  r = await client.request('semantic_set_enabled', { node: node(button), enabled: false, expected_semantic_revision: semanticRevision }); assert.equal(r.ok, true); semanticRevision = r.semantic_revision
  const disabled = r.nodes; const scene = r.state; const frame = r.frame
  r = await client.request('semantic_activate', { node: node(button), expected_semantic_revision: semanticRevision }); assert.equal(r.ok, false); assert.deepEqual(r.nodes, disabled); assert.deepEqual(r.state, scene); assert.equal(r.frame, frame)
  r = await client.request('activate'); assert.equal(r.ok, false); assert.deepEqual(r.state, scene); assert.equal(r.frame, frame)
  r = await client.request('semantic_remove', { node: node(input), expected_semantic_revision: semanticRevision }); assert.equal(r.ok, true); semanticRevision = r.semantic_revision
  r = await client.request('semantic_recreate_input', { expected_semantic_revision: semanticRevision }); assert.equal(r.ok, true); const fresh = r.nodes.find((item) => item.role === 'text_input'); assert(fresh.generation > input.generation); semanticRevision = r.semantic_revision
  r = await client.request('semantic_focus', { node: node(input), expected_semantic_revision: semanticRevision }); assert.equal(r.ok, false); assert.equal(r.error, 'stale_target')
  r = await client.request('semantic_focus', { node: { ...node(fresh), window: fresh.window + 1 }, expected_semantic_revision: semanticRevision }); assert.equal(r.ok, false); assert.equal(r.error, 'stale_target')
  r = await client.request('semantic_focus', { node: node(fresh), expected_semantic_revision: semanticRevision - 1 }); assert.equal(r.ok, false); assert.equal(r.error, 'stale_semantic_revision')
  result.checks.push('text/selection/focus/disable/remove/recreate/stale')
} finally {
  result.adapter = client.diagnostics
  await client.close()
  await rm(tmp, { recursive: true, force: true })
  await writeFile(path.join(out, `${mode}.json`), JSON.stringify(result, null, 2))
}
console.log(JSON.stringify(result, null, 2))
