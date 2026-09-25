import { createSurface } from './surface.mjs';
import { createLayerRenderer } from './layer-renderer.mjs';
import { wasmImports } from './wasm-imports.mjs';

export function runApplication({ title, artifact, eventName, canvasId, statusId, stopId, controls = [], onLoaded = () => {} }) {
  const canvas = document.getElementById(canvasId);
  const status = document.getElementById(statusId), stopButton = document.getElementById(stopId);
  const elements = controls.map(control => ({ ...control, element: document.getElementById(control.id) }));
  let app, renderer, context, width = 0, height = 0, disposed = false;
  const actions = elements.filter(control => control.action !== undefined).map(control => ({
    element: control.element,
    callback: () => { if (!disposed) app.activate(control.action); },
  }));
  const surface = createSurface({ canvas, onError: message => stop(message),
    onResize: size => {
      width = size.width; height = size.height;
      if (app.resize(width, height) !== 1) throw new Error('Application resize failed');
      refresh();
    },
    onFrame: () => {
      if (disposed || !renderer) return;
      try {
        if (app.frame_begin(context) !== 1) throw new Error('Application frame failed');
        renderer.record(width, height);
        if (app.frame_submit() !== 1) throw new Error('Application submission failed');
      } catch (error) { app.frame_abort(); throw error; }
    },
  });
  function refresh() {
    if (disposed || !renderer) return;
    if (app.close_ready() === 1 && app.can_close() === 1) { stop(); return; }
    try { renderer.refresh(width); surface.schedule(); }
    catch (error) { stop(error?.message || String(error)); }
  }
  function stop(message = 'Stopped.') {
    if (disposed) return;
    disposed = true;
    document.removeEventListener(eventName, refresh);
    window.removeEventListener('pagehide', stopPage);
    window.removeEventListener('beforeunload', beforeUnload);
    for (const action of actions) action.element.removeEventListener('click', action.callback);
    stopButton.removeEventListener('click', requestStop);
    renderer?.dispose();
    app?.stop();
    surface.dispose();
    for (const control of elements) control.element.disabled = true;
    stopButton.disabled = true;
    status.textContent = message;
  }
  function stopPage() { stop(); }
  function requestStop() {
    if (app && app.can_close() !== 1) {
      app.request_close();
      if (disposed) return true;
      status.textContent = 'Save or discard changes before stopping.';
      return false;
    }
    stop();
    return true;
  }
  function beforeUnload(event) {
    if (!disposed && app && app.can_close() !== 1) {
      event.preventDefault();
      event.returnValue = '';
    }
  }
  async function main() {
    const target = new URL(location.href).searchParams.get('target') || 'wasm-gc';
    if (!['js', 'wasm-gc'].includes(target)) throw new Error('Unknown application target');
    const resources = await surface.start();
    if (!resources || disposed) return;
    context = resources.context;
    if (target === 'js') {
      const module = await import(`${artifact}.mjs`);
      app = module.create();
      onLoaded(module);
    }
    else {
      const response = await fetch(`${artifact}.wasm`);
      if (!response.ok) throw new Error(`Application load failed: ${response.status}`);
      const { instance } = await WebAssembly.instantiateStreaming(response, wasmImports(),
        { builtins: ['js-string'], importedStringConstants: '_' });
      app = instance.exports.create();
      onLoaded(instance.exports);
    }
    if (disposed) { app.stop(); return; }
    const font = await app.load_font();
    if (disposed) return;
    if (app.install_font(font) !== 1 || app.start(resources.device, resources.format) !== 1)
      throw new Error('Application initialization failed');
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
    document.addEventListener(eventName, refresh);
    for (const action of actions) action.element.addEventListener('click', action.callback);
    status.textContent = `Ready: ${title} (${target})`;
  }
  stopButton.addEventListener('click', requestStop);
  window.addEventListener('beforeunload', beforeUnload);
  window.addEventListener('pagehide', stopPage);
  main().catch(error => { if (!disposed) stop(error?.message || String(error)); });
  return { stop: requestStop };
}
