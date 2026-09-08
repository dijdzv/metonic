import fs from 'node:fs';

const js = await import('../.work/browser-dist/app.mjs');
const { wasmImports } = await import('../.work/browser-dist/loader.mjs');
const wasm = await WebAssembly.instantiate(
  fs.readFileSync(new URL('../.work/browser-dist/app.wasm', import.meta.url)),
  wasmImports(),
  { builtins: ['js-string'], importedStringConstants: '_' },
);
const { verify } = await import('../_build/js/release/build/tools/verify_browser_artifacts/verify_browser_artifacts.js');
await verify(js, wasm.instance.exports);
console.log('browser artifacts verified: JS and WasmGC APIs agree');
