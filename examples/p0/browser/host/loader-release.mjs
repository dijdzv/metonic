import { wasmImports, validateExports } from './loader-common.mjs';
export async function loadApp() {
  const response = await fetch('./app.wasm');
  if (!response.ok) throw new Error(`Unable to load application (${response.status})`);
  const bytes = await response.arrayBuffer();
  const result = await WebAssembly.instantiate(bytes, wasmImports());
  const app = validateExports(result.instance.exports, 'wasm-gc');
  app.init();
  return { app };
}
