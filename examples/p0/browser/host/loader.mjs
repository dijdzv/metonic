import { wasmImports, validateExports } from './loader-common.mjs';
export { wasmImports } from './loader-common.mjs';

export async function loadApp(target) {
  if (target === 'js') {
    const response = await fetch('./app.mjs', { cache: 'no-cache' });
    if (!response.ok) throw new Error(`Unable to fetch app.mjs (${response.status})`);
    const source = await response.text();
    const started = performance.now();
    const app = await import('./app.mjs');
    validateExports(app, target);
    app.init();
    return { app, loadMs: performance.now() - started, artifactBytes: new TextEncoder().encode(source).byteLength };
  }
  if (target === 'wasm-gc') {
    const response = await fetch('./app.wasm', { cache: 'no-cache' });
    if (!response.ok) throw new Error(`Unable to fetch app.wasm (${response.status})`);
    const bytes = await response.arrayBuffer();
    const started = performance.now();
    const result = await WebAssembly.instantiate(bytes, wasmImports(), { builtins: ['js-string'], importedStringConstants: '_' });
    const app = validateExports(result.instance.exports, target);
    app.init();
    return { app, loadMs: performance.now() - started, artifactBytes: bytes.byteLength };
  }
  throw new Error(`Unknown target “${target}”; choose js or wasm-gc.`);
}
