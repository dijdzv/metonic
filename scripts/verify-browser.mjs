import assert from 'node:assert/strict';
import fs from 'node:fs';

const js = await import('../.work/browser-dist/app.mjs');
const { wasmImports } = await import('../examples/p0/browser/host/loader.mjs');
const wasm = await WebAssembly.instantiate(
  fs.readFileSync(new URL('../.work/browser-dist/app.wasm', import.meta.url)),
  wasmImports(),
);
const wasmExports = wasm.instance.exports;

const names = ['init', 'resize', 'move_to', 'activate', 'field'];
for (const name of names) {
  assert.equal(typeof js[name], 'function', `JS export ${name}`);
  assert.equal(typeof wasmExports[name], 'function', `Wasm export ${name}`);
}

function snapshot(api) {
  return Array.from({ length: 8 }, (_, index) => api.field(index));
}

function run(api) {
  const history = [];
  api.init();
  history.push(snapshot(api));
  assert.deepEqual(history.at(-1), [260, 144, 120, 72, 0, 0, 640, 360]);
  assert.equal(api.resize(100, 50), 1);
  history.push(snapshot(api));
  assert.deepEqual(history.at(-1), [0, 0, 100, 50, 0, 1, 100, 50]);
  assert.equal(api.move_to(-100, 1000), 0);
  history.push(snapshot(api));
  assert.deepEqual(history.at(-1), [0, 0, 100, 50, 0, 1, 100, 50]);
  assert.equal(api.resize(640, 360), 1);
  history.push(snapshot(api));
  assert.deepEqual(history.at(-1), [0, 0, 120, 72, 0, 2, 640, 360]);
  assert.equal(api.move_to(5000, 5000), 1);
  history.push(snapshot(api));
  assert.deepEqual(history.at(-1), [520, 288, 120, 72, 0, 3, 640, 360]);
  api.activate();
  history.push(snapshot(api));
  assert.deepEqual(history.at(-1), [520, 288, 120, 72, 1, 4, 640, 360]);
  assert.equal(api.move_to(5000, 5000), 0);
  history.push(snapshot(api));
  assert.deepEqual(history.at(-1), [520, 288, 120, 72, 1, 4, 640, 360]);
  api.init();
  history.push(snapshot(api));
  assert.deepEqual(history.at(-1), [260, 144, 120, 72, 0, 0, 640, 360]);
  return history;
}

const jsHistory = run(js);
const wasmHistory = run(wasmExports);
assert.deepEqual(jsHistory, wasmHistory);
console.log('browser artifacts verified: JS and WasmGC APIs agree');
