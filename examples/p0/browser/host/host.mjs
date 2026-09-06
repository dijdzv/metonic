import { loadApp } from './loader.mjs';

const $ = (id) => document.getElementById(id);
const canvas = $('canvas');
const status = $('status');
const target = new URLSearchParams(location.search).get('target') || 'js';
const els = { target: $('target'), bytes: $('artifact-bytes'), load: $('load-ms'), adapter: $('adapter'), dimensions: $('dimensions'), revision: $('revision'), submitted: $('submitted'), transferred: $('transferred') };
let app, device, context, pipeline, uniform, bindGroup, observer, raf = 0, disposed = false, dirty = false;
let cssW = 0, cssH = 0, backingW = 0, backingH = 0, submitted = 0, transferred = 0, format;

function setStatus(message, error = false) {
  status.textContent = message;
  status.style.color = error ? '#ff9b8a' : '';
}

function field(index) {
  return Number(app.field(index));
}

function renderStats() {
  els.revision.textContent = String(field(5));
  els.submitted.textContent = String(submitted);
  els.transferred.textContent = `${transferred} bytes`;
}

function schedule() {
  if (!disposed && !raf) raf = requestAnimationFrame(draw);
}
function draw() {
  raf = 0;
  if (disposed || !device || !dirty) return;
  dirty = false;
  try {
    const data = new Float32Array([field(0), field(1), field(2), field(3), cssW, cssH, field(4) === 1 ? 1 : 0, 0]);
    device.queue.writeBuffer(uniform, 0, data);
    transferred += data.byteLength;
    const encoder = device.createCommandEncoder();
    const view = context.getCurrentTexture().createView();
    const pass = encoder.beginRenderPass({ colorAttachments: [{ view, clearValue: { r: .02, g: .08, b: .15, a: 1 }, loadOp: 'clear', storeOp: 'store' }] });
    pass.setPipeline(pipeline);
    pass.setBindGroup(0, bindGroup);
    pass.draw(6);
    pass.end();
    device.queue.submit([encoder.finish()]);
    submitted += 1;
    renderStats();
  } catch (error) {
    stop(error?.message || String(error), true);
  }
}
function resize(force = false) {
  if (disposed || !app || !device) return;
  const rect = canvas.getBoundingClientRect();
  const nextCssW = Math.max(1, Math.round(rect.width));
  const nextCssH = Math.max(1, Math.round(rect.height));
  const dpr = Math.max(1, window.devicePixelRatio || 1);
  const max = device.limits.maxTextureDimension2D;
  const nextBackingW = Math.min(max, Math.max(1, Math.round(nextCssW * dpr)));
  const nextBackingH = Math.min(max, Math.max(1, Math.round(nextCssH * dpr)));
  const changedSize = force || nextCssW !== cssW || nextCssH !== cssH || nextBackingW !== backingW || nextBackingH !== backingH;
  if (!changedSize) return;
  cssW = nextCssW;
  cssH = nextCssH;
  backingW = nextBackingW;
  backingH = nextBackingH;
  canvas.width = backingW;
  canvas.height = backingH;
  context.configure({ device, format, alphaMode: 'opaque' });
  app.resize(cssW, cssH);
  els.dimensions.textContent = `${cssW} × ${cssH} CSS / ${backingW} × ${backingH} backing`;
  dirty = true;
  schedule();
}
function onResize() { resize(false); }
function changed(result = 1) {
  if (Number(result) !== 0) {
    dirty = true;
    schedule();
  }
}
function onPointer(event) {
  if (disposed) return;
  canvas.focus();
  const rect = canvas.getBoundingClientRect();
  const x = Math.trunc(event.clientX - rect.left);
  const y = Math.trunc(event.clientY - rect.top);
  const hit = x >= field(0) && x <= field(0) + field(2)
    && y >= field(1) && y <= field(1) + field(3);
  if (hit) {
    app.activate();
    changed();
  } else {
    changed(app.move_to(x, y));
  }
}
function onKey(event) {
  if (disposed) return;
  let result;
  if (event.key === 'ArrowLeft') {
    result = app.move_to(field(0) - 10, field(1));
  } else if (event.key === 'ArrowRight') {
    result = app.move_to(field(0) + 10, field(1));
  } else if (event.key === 'ArrowUp') {
    result = app.move_to(field(0), field(1) - 10);
  } else if (event.key === 'ArrowDown') {
    result = app.move_to(field(0), field(1) + 10);
  } else if (event.key === ' ' || event.key === 'Enter') {
    app.activate();
    result = 1;
  } else {
    return;
  }
  event.preventDefault();
  changed(result);
}
function onReset() {
  if (disposed || !app) return;
  app.init();
  resize(true);
  dirty = true;
  schedule();
}
function stop(reason = 'Stopped.', error = false) {
  if (disposed) return;
  disposed = true;
  if (raf) cancelAnimationFrame(raf);
  raf = 0;
  observer?.disconnect();
  observer = undefined;
  window.removeEventListener('resize', onResize);
  window.removeEventListener('pagehide', onStop);
  canvas.removeEventListener('pointerdown', onPointer);
  canvas.removeEventListener('keydown', onKey);
  $('reset').removeEventListener('click', onReset);
  $('stop').removeEventListener('click', onStop);
  $('stop').disabled = true;
  $('reset').disabled = true;
  try { context?.unconfigure?.(); } catch {}
  try { uniform?.destroy(); } catch {}
  try { device?.destroy(); } catch {}
  setStatus(reason, error);
}
async function main() {
  if (!['js', 'wasm-gc'].includes(target)) {
    throw new Error(`Unknown target “${target}”; choose js or wasm-gc.`);
  }
  if (!window.isSecureContext) {
    throw new Error('WebGPU requires a secure context (HTTPS or localhost).');
  }
  if (!navigator.gpu) {
    throw new Error('WebGPU is unavailable in this browser.');
  }
  const adapter = await navigator.gpu.requestAdapter();
  if (disposed) return;
  if (!adapter) throw new Error('WebGPU requestAdapter returned no adapter.');
  const nextDevice = await adapter.requestDevice();
  if (disposed) {
    nextDevice.destroy();
    return;
  }
  device = nextDevice;
  device.lost.then((info) => {
    if (!disposed) stop(`GPU device lost: ${info.message || info.reason}`, true);
  });
  device.addEventListener('uncapturederror', (event) => {
    if (!disposed) stop(`GPU error: ${event.error.message}`, true);
  });
  context = canvas.getContext('webgpu');
  if (!context) throw new Error('Could not acquire a WebGPU canvas context.');
  format = navigator.gpu.getPreferredCanvasFormat();
  const shader = device.createShaderModule({ code: `
struct U { rect: vec4f, viewport: vec2f, enabled: f32, pad: f32 };
@group(0) @binding(0) var<uniform> u: U;
@vertex fn vs(@builtin(vertex_index) i: u32) -> @builtin(position) vec4f {
  var p = array<vec2f, 6>(vec2f(0,0), vec2f(1,0), vec2f(0,1), vec2f(0,1), vec2f(1,0), vec2f(1,1));
  let px = u.rect.xy + p[i] * u.rect.zw;
  let clip = vec2f(px.x / u.viewport.x * 2.0 - 1.0, 1.0 - px.y / u.viewport.y * 2.0);
  return vec4f(clip, 0, 1);
}
@fragment fn fs() -> @location(0) vec4f {
  return select(vec4f(0.08, 0.65, 0.68, 1), vec4f(0.95, 0.38, 0.10, 1), u.enabled > 0.5);
}` });
  pipeline = await device.createRenderPipelineAsync({
    layout: 'auto',
    vertex: { module: shader },
    fragment: { module: shader, targets: [{ format }] },
    primitive: { topology: 'triangle-list' },
  });
  if (disposed) return;
  uniform = device.createBuffer({
    size: 32,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  });
  bindGroup = device.createBindGroup({
    layout: pipeline.getBindGroupLayout(0),
    entries: [{ binding: 0, resource: { buffer: uniform } }],
  });
  const loaded = await loadApp(target);
  if (disposed) return;
  app = loaded.app;
  els.target.textContent = target;
  els.bytes.textContent = String(loaded.artifactBytes);
  els.load.textContent = loaded.loadMs.toFixed(2);
  els.adapter.textContent = adapter.info?.description || adapter.info?.vendor || 'available';
  resize(true);
  if (disposed) return;
  observer = new ResizeObserver(onResize);
  observer.observe(canvas);
  window.addEventListener('resize', onResize);
  canvas.addEventListener('pointerdown', onPointer);
  canvas.addEventListener('keydown', onKey);
  $('reset').addEventListener('click', onReset);
  setStatus(`Ready: ${target}`);
}
const onStop = () => stop();
$('stop').addEventListener('click', onStop);
window.addEventListener('pagehide', onStop);
main().catch((error) => { if (!disposed) stop(error?.message || String(error), true); });
