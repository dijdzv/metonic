const REQUIRED = ['init', 'resize', 'move_to', 'activate', 'field'];

function validateExports(exports, target) {
  for (const name of REQUIRED) {
    if (typeof exports[name] !== 'function') {
      throw new Error(`${target} artifact is missing required export: ${name}`);
    }
  }
  return exports;
}

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
    const result = await WebAssembly.instantiate(bytes, {});
    const app = validateExports(result.instance.exports, target);
    app.init();
    return { app, loadMs: performance.now() - started, artifactBytes: bytes.byteLength };
  }
  throw new Error(`Unknown target “${target}”; choose js or wasm-gc.`);
}
