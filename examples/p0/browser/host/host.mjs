import { createSurface } from './surface.mjs';
import { loadApp } from './loader.mjs';
import { createTextRenderer } from './text-renderer.mjs';
import * as environment from './environment.mjs';

const $ = (id) => document.getElementById(id);
const canvas = $('canvas');
const status = $('status');
const target = environment.target;
let app, device, context, disposed = false, dirty = false;
let cssW = 0, cssH = 0, backingW = 0, backingH = 0, submitted = 0, transferred = 0, format;
const textInput = $('text-input');
const DEFAULT_TEXT = textInput.value;
let textRenderer;
const taskButtons = [$('task-start'), $('task-cancel'), $('rpc-load')];
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
  updateTaskDiagnostics();
}
function onRpcChanged() {
  if (disposed) return;
  renderRpc();
}
function cancelHttp() {
  app?.http_cancel();
}
let lastTaskStatus;

function taskField(index) { return Number(app.task_field(index)); }
function updateTaskDiagnostics() {
  const values = [];
  for (let index = 0; index < 6; index += 1) values.push(taskField(index));
  environment.task(values, Number(app.scheduled_task_count()), Number(app.scheduled_task_rejections()));
  if (!disposed && lastTaskStatus !== values[0]) { lastTaskStatus = values[0]; renderEditor(); }
}
function dispatchTask(delayMs, value, fail = false) {
  if (disposed || !app || !Number.isSafeInteger(delayMs) || delayMs < -2147483648 || delayMs > 2147483647
    || !Number.isSafeInteger(value) || value < -2147483648 || value > 2147483647 || typeof fail !== 'boolean') return false;
  if (Number(app.schedule_task(delayMs, value, fail ? 1 : 0)) !== 1) return false;
  cancelHttp();
  updateTaskDiagnostics();
  return true;
}
function onTaskChanged(event) {
  if (disposed) return;
  if (event.type === 'metonic-task-render') { dirty = true; schedule(); }
  updateTaskDiagnostics();
}
function cancelTask() { if (!disposed && app) { app.task_cancel(); cancelHttp(); updateTaskDiagnostics(); } }
function resetTasks() {
  cancelHttp();
  app?.scheduled_tasks_reset();
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

const surface = createSurface({
  canvas,
  onError: message => stop(message, true),
  onFrame: draw,
  onResize: size => {
    cssW = size.width; cssH = size.height;
    backingW = size.backingWidth; backingH = size.backingHeight;
    app.resize(cssW, cssH);
    textRenderer?.rasterText(cssW);
    app.view_place();
    environment.dimensions(cssW, cssH, backingW, backingH);
    dirty = true;
    schedule();
  },
});
function schedule() { if (!disposed) surface.schedule(); }
function draw() {
  if (disposed || !device || !dirty) return;
  dirty = false;
  try {
    const data = new Float32Array([field(0), field(1), field(2), field(3), cssW, cssH, field(4) === 1 ? 1 : 0, 0]);
    transferred += data.byteLength;
    if (app.gpu_frame_begin(context) !== 1) throw new Error('MoonBit GPU rejected frame');
    if (app.gpu_frame_scene(data) !== 1) throw new Error('MoonBit scene GPU rejected draw');
    textRenderer?.record(cssW, cssH);
    if (app.gpu_frame_submit() !== 1) throw new Error('MoonBit GPU rejected submission');
    submitted += 1;
    renderStats();
  } catch (error) {
    app.gpu_frame_abort();
    stop(error?.message || String(error), true);
  }
}
function resize(force = false) { if (!disposed && app) surface.resize(force); }
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
  changed(app.scene_pointer(x, y));
}
function onKey(event) {
  if (disposed) return;
  const result = Number(app.scene_key(event.key));
  if (result < 0) return;
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
  app?.font_fetch_cancel?.();
  document.removeEventListener('metonic-input', onInputChanged);
  document.removeEventListener('metonic-rpc', onRpcChanged);
  document.removeEventListener('metonic-task', onTaskChanged);
  document.removeEventListener('metonic-task-render', onTaskChanged);
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
  app?.scheduled_tasks_reset();
  try { app?.task_dispose?.(); } catch {}
  if (app) updateTaskDiagnostics();
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
  try { app?.scene_gpu_dispose(); } catch {}
  surface.dispose();
  setStatus(reason, error);
}
async function main() {
  if (!['js', 'wasm-gc'].includes(target)) {
    throw new Error(`Unknown target “${target}”; choose js or wasm-gc.`);
  }
  const resources = await surface.start();
  if (!resources || disposed) return;
  const adapter = resources.adapter;
  ({ device, context, format } = resources);
  const loaded = await loadApp(target);
  if (disposed) return;
  app = loaded.app;
  const sceneReady = await app.scene_gpu_init(device, format);
  if (disposed) return;
  if (sceneReady !== 1) throw new Error('MoonBit scene GPU initialization rejected format');
  textRenderer = await createTextRenderer({ app, device, format, disposed: () => disposed });
  if (disposed) return;
  environment.loaded(loaded, adapter);
  app.inputs_start();
  if (app.inputs_error() !== 0) throw new Error('Initial text input rejected');
  resize(true);
  if (disposed) return;
  document.addEventListener('metonic-input', onInputChanged);
  document.addEventListener('metonic-rpc', onRpcChanged);
  document.addEventListener('metonic-task', onTaskChanged);
  document.addEventListener('metonic-task-render', onTaskChanged);
  surface.observe();
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
    app, dispatchTask, cancelTask,
    get rejectedCallbacks() { return Number(app.scheduled_task_rejections()); },
    get disposed() { return disposed; },
  });
  setStatus(environment.ready);
}
const onStop = () => stop();
$('stop').addEventListener('click', onStop);
window.addEventListener('pagehide', onStop);
main().catch((error) => { if (!disposed) stop(error?.message || String(error), true); });
