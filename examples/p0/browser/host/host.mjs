import { loadApp } from './loader.mjs';
import { createTextRenderer } from './text-renderer.mjs';
import * as environment from './environment.mjs';

const $ = (id) => document.getElementById(id);
const canvas = $('canvas');
const status = $('status');
const target = environment.target;
let app, device, context, pipeline, uniform, bindGroup, observer, raf = 0, disposed = false, dirty = false;
let cssW = 0, cssH = 0, backingW = 0, backingH = 0, submitted = 0, transferred = 0, format;
const textInput = $('text-input');
const DEFAULT_TEXT = textInput.value;
let textRenderer;
const taskButtons = [$('task-start'), $('task-cancel'), $('rpc-load')];
let rpcTimer;
function rpcOutput(kind) {
  return new TextDecoder('utf-8', { fatal: true }).decode(Uint8Array.from({ length: Number(app.rpc_output_length(kind)) }, (_, i) => Number(app.rpc_output_byte(kind, i))));
}
function renderRpc() {
  $('rpc-result').textContent = rpcOutput(1);
  renderEditor();
  updateTaskDiagnostics();
}
function loadUser() {
  if (disposed || !app || app.inputs_composing() !== 0) return;
  app.view_focus(1);
  renderEditor();
  if (app.http_start() !== 1) return;
  clearTimeout(rpcTimer);
  rpcTimer = setTimeout(() => app.http_timeout(), 3000);
  updateTaskDiagnostics();
}
function onRpcChanged() {
  if (disposed) return;
  if (!app.http_active()) { clearTimeout(rpcTimer); rpcTimer = undefined; }
  renderRpc();
}
function cancelHttp() {
  clearTimeout(rpcTimer);
  rpcTimer = undefined;
  app?.http_cancel();
}
const taskTimers = new Map();
let taskEpoch = 0;
let rejectedCallbacks = 0;
let lastTaskStatus;

function taskField(index) { return Number(app.task_field(index)); }
function updateTaskDiagnostics() {
  const values = [];
  for (let index = 0; index < 6; index += 1) values.push(taskField(index));
  environment.task(values, taskTimers.size, rejectedCallbacks);
  if (!disposed && lastTaskStatus !== values[0]) { lastTaskStatus = values[0]; dirty = true; schedule(); }
}
function dispatchTask(delayMs, value, fail = false) {
  if (disposed || !app || !Number.isInteger(delayMs) || delayMs < 0 || delayMs > 5000
    || !Number.isInteger(value) || value < 0 || value > 2048 || typeof fail !== 'boolean'
    || taskTimers.size >= 16) return false;
  const id = app.task_begin();
  if (Number(id) < 0) return false;
  cancelHttp();
  const epoch = taskEpoch;
  const timer = setTimeout(() => {
    taskTimers.delete(id);
    if (disposed || epoch !== taskEpoch) return;
    const accepted = fail ? app.task_fail(id, 7) : app.task_complete(id, value);
    if (Number(accepted) === 1 && !fail) { dirty = true; schedule(); }
    else if (Number(accepted) !== 1) rejectedCallbacks += 1;
    updateTaskDiagnostics();
  }, delayMs);
  taskTimers.set(id, timer);
  updateTaskDiagnostics();
  return true;
}
function cancelTask() { if (!disposed && app) { app.task_cancel(); cancelHttp(); updateTaskDiagnostics(); } }
function resetTasks() {
  cancelHttp();
  for (const timer of taskTimers.values()) clearTimeout(timer);
  taskTimers.clear();
  taskEpoch += 1;
  if (app) updateTaskDiagnostics();
}
function onTaskStart() { if (!disposed && app) dispatchTask(1000, Number(app.task_movement_target())); }
function onTaskCancel() { cancelTask(); }

function setStatus(message, error = false) {
  status.textContent = message;
  status.style.color = error ? '#ff9b8a' : '';
}

function field(index) {
  return Number(app.field(index));
}

function renderStats() {
  environment.frame(field(5), submitted, transferred);
  if (textRenderer) {
    const stats = textRenderer.stats();
    environment.text(stats);
  }
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
    textRenderer?.record(pass, cssW, cssH);
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
  textRenderer?.rasterText(cssW);
  placeView();
  environment.dimensions(cssW, cssH, backingW, backingH);
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
  app.view_focus(2);
  renderEditor();
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
  resetTasks();
  app.inputs_stop();
  app.init();
  $('rpc-result').textContent = '';
  textInput.value = DEFAULT_TEXT;
  $('rpc-user').value = '1';
  app.inputs_start();
  textRenderer?.rasterText(cssW);
  updateTaskDiagnostics();
  resize(true);
  dirty = true;
  schedule();
}

function placeView() {
  for (const [element, target] of [[0, textInput], [1, $('rpc-load')], [3, $('task-start')], [4, $('task-cancel')], [6, $('rpc-user')]]) {
    if (element === 6) target.classList.add('gpu-input');
    else if (element !== 0) target.classList.add('gpu-button');
    target.style.left = (canvas.offsetLeft + Number(app.view_field(element, 0))) + 'px';
    target.style.top = (canvas.offsetTop + Number(app.view_field(element, 1))) + 'px';
    target.style.width = Number(app.view_field(element, 2)) + 'px';
    target.style.height = Number(app.view_field(element, 3)) + 'px';
  }
  $('rpc-load').textContent = String.fromCharCode(...Array.from({ length: Number(app.view_field(1, 4)) }, (_, i) => Number(app.view_label_unit(i))));
}
function onRequestFocus() { if (!disposed && app) { app.view_focus(1); renderEditor(); } }
function onStartFocus() { if (!disposed && app) { app.view_focus(3); renderEditor(); } }
function onCancelFocus() { if (!disposed && app) { app.view_focus(4); renderEditor(); } }
function onSceneFocus() { if (!disposed && app) { app.view_focus(2); renderEditor(); } }
function onInputChanged() {
  if (disposed || !app) return;
  if (app.inputs_error() !== 0) { stop('Text input rejected', true); return; }
  renderEditor();
}
function renderEditor() {
  if (disposed || !textRenderer) return;
  try {
    textRenderer.rasterText(cssW);
    const stats = textRenderer.stats();
    environment.text(stats);
    dirty = true;
    schedule();
  } catch (error) {
    stop(error?.message || String(error), true);
  }
}
function stop(reason = 'Stopped.', error = false) {
  if (disposed) return;
  disposed = true;
  document.removeEventListener('metonic-input', onInputChanged);
  document.removeEventListener('metonic-rpc', onRpcChanged);
  app?.inputs_stop?.();
  cancelHttp();
  $('rpc-load').removeEventListener('click', loadUser);
  $('rpc-load').removeEventListener('focus', onRequestFocus);
  $('task-start').removeEventListener('focus', onStartFocus);
  $('task-cancel').removeEventListener('focus', onCancelFocus);
  canvas.removeEventListener('focus', onSceneFocus);
  $('rpc-user').disabled = true;
  textRenderer?.dispose();
  textRenderer = undefined;
  try { app?.text_dispose?.(); } catch {}
  textInput.disabled = true;
  try { app?.editor_dispose?.(); } catch {}
  for (const timer of taskTimers.values()) clearTimeout(timer);
  taskTimers.clear();
  taskEpoch += 1;
  try { app?.task_dispose?.(); } catch {}
  if (app) updateTaskDiagnostics();
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
  for (const button of taskButtons) button.disabled = true;
  $('task-start').removeEventListener('click', onTaskStart);
  environment.detach();
  $('task-cancel').removeEventListener('click', onTaskCancel);
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
  textRenderer = await createTextRenderer({ app, device, format, disposed: () => disposed });
  if (disposed) return;
  environment.loaded(loaded, adapter);
  app.inputs_start();
  if (app.inputs_error() !== 0) throw new Error('Initial text input rejected');
  resize(true);
  if (disposed) return;
  document.addEventListener('metonic-input', onInputChanged);
  document.addEventListener('metonic-rpc', onRpcChanged);
  observer = new ResizeObserver(onResize);
  observer.observe(canvas);
  window.addEventListener('resize', onResize);
  canvas.addEventListener('pointerdown', onPointer);
  canvas.addEventListener('keydown', onKey);
  $('reset').addEventListener('click', onReset);
  textInput.disabled = false;
  $('task-start').addEventListener('click', onTaskStart);
  $('rpc-load').addEventListener('click', loadUser);
  $('rpc-load').addEventListener('focus', onRequestFocus);
  $('task-start').addEventListener('focus', onStartFocus);
  $('task-cancel').addEventListener('focus', onCancelFocus);
  canvas.addEventListener('focus', onSceneFocus);
  $('rpc-user').disabled = false;
  $('task-cancel').addEventListener('click', onTaskCancel);
  for (const button of taskButtons) button.disabled = false;
  updateTaskDiagnostics();
  environment.attach({
    app, dispatchTask, cancelTask, taskTimers,
    get rejectedCallbacks() { return rejectedCallbacks; },
    get disposed() { return disposed; },
  });
  setStatus(environment.ready);
}
const onStop = () => stop();
$('stop').addEventListener('click', onStop);
window.addEventListener('pagehide', onStop);
main().catch((error) => { if (!disposed) stop(error?.message || String(error), true); });
