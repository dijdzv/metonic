import { createSurface } from './surface.mjs';
import { createLayerRenderer } from './layer-renderer.mjs';
import { wasmImports } from './wasm-imports.mjs';

const canvas = document.getElementById('canvas');
const note = document.getElementById('note'), clear = document.getElementById('clear');
const status = document.getElementById('status'), stopButton = document.getElementById('stop');
let app, renderer, context, width = 0, height = 0, disposed = false;
const surface = createSurface({ canvas, onError: message => stop(message),
  onResize: size => {
    width = size.width; height = size.height;
    if (app.resize(width, height) !== 1) throw new Error('Notes resize failed');
    refresh();
  },
  onFrame: () => {
    if (disposed || !renderer) return;
    try {
      if (app.frame_begin(context) !== 1) throw new Error('Notes frame failed');
      renderer.record(width, height);
      if (app.frame_submit() !== 1) throw new Error('Notes submission failed');
    } catch (error) { app.frame_abort(); throw error; }
  },
});
function refresh() {
  if (disposed || !renderer) return;
  try { renderer.refresh(width); surface.schedule(); }
  catch (error) { stop(error?.message || String(error)); }
}
function clearNote() { if (!disposed) app.clear(); }
function stop(message = 'Stopped.') {
  if (disposed) return;
  disposed = true;
  document.removeEventListener('metonic-notes', refresh);
  window.removeEventListener('pagehide', stopPage);
  clear.removeEventListener('click', clearNote);
  stopButton.removeEventListener('click', stopPage);
  renderer?.dispose();
  app?.stop();
  surface.dispose();
  note.disabled = clear.disabled = stopButton.disabled = true;
  status.textContent = message;
}
function stopPage() { stop(); }
async function main() {
  const target = new URL(location.href).searchParams.get('target') || 'wasm-gc';
  if (!['js', 'wasm-gc'].includes(target)) throw new Error('Unknown Notes target');
  const resources = await surface.start();
  if (!resources || disposed) return;
  context = resources.context;
  if (target === 'js') app = await import('./notes.mjs');
  else {
    const response = await fetch('./notes.wasm');
    if (!response.ok) throw new Error(`Notes load failed: ${response.status}`);
    const { instance } = await WebAssembly.instantiateStreaming(response, wasmImports(),
      { builtins: ['js-string'], importedStringConstants: '_' });
    app = instance.exports;
  }
  if (disposed) { app.stop(); return; }
  const font = await app.load_font();
  if (disposed) return;
  if (app.install_font(font) !== 1 || app.start(resources.device, resources.format) !== 1)
    throw new Error('Notes initialization failed');
  renderer = createLayerRenderer({
    raster: () => app.render(), width: () => width,
    layerCount: () => app.layer_count(), layerField: (i, f) => app.layer_field(i, f),
    layerBytes: i => app.layer_bytes(i), beginUpload: () => app.upload_begin(),
    upload: (i, pixels) => app.upload_layer(i, pixels), commitUpload: () => app.upload_commit(),
    record: (i, uniform) => app.frame_text(i, uniform), dispose: () => app.stop(),
  });
  surface.resize(true);
  if (disposed) return;
  surface.observe();
  document.addEventListener('metonic-notes', refresh);
  clear.addEventListener('click', clearNote);
  note.disabled = clear.disabled = false;
  status.textContent = `Ready: Notes (${target})`;
}
stopButton.addEventListener('click', stopPage);
window.addEventListener('pagehide', stopPage);
main().catch(error => { if (!disposed) stop(error?.message || String(error)); });
