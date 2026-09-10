const $ = (id) => document.getElementById(id);
export const target = new URLSearchParams(location.search).get('target') || 'wasm-gc';
export const ready = `Ready: ${target}`;
let fail;
export function task(values, pending, rejected) {
  $('task-state').textContent = JSON.stringify(values);
  $('task-pending').textContent = String(pending);
  $('task-rejected').textContent = String(rejected);
}
export function frame(revision, submitted, transferred) {
  $('revision').textContent = String(revision);
  $('submitted').textContent = String(submitted);
  $('transferred').textContent = `${transferred} bytes`;
}
export function text(stats) {
  $('text-width').textContent = String(stats.width);
  $('text-renders').textContent = String(stats.renders);
  $('text-uploaded').textContent = String(stats.uploaded);
}
export function dimensions(w, h, bw, bh) {
  $('dimensions').textContent = `${w} × ${h} CSS / ${bw} × ${bh} backing`;
}
export function loaded(value, adapter) {
  $('target').textContent = target;
  $('artifact-bytes').textContent = String(value.artifactBytes);
  $('load-ms').textContent = value.loadMs.toFixed(2);
  $('adapter').textContent = adapter.info?.description || adapter.info?.vendor || 'available';
}
export function attach(session) {
  const { app, dispatchTask, cancelTask } = session;
  fail = () => dispatchTask(250, 0, true);
  $('task-fail').addEventListener('click', fail);
  $('task-fail').disabled = false;
  const units = (length, unit) => Array.from({ length: Math.max(0, Number(length)) }, (_, i) => String.fromCharCode(Number(unit(i)))).join('');
  window.metonicAsyncProbe = {
    editor: () => ({ text: units(app.editor_field(0), (i) => app.editor_unit(i)), display: units(app.editor_field(4), (i) => app.editor_display_unit(i)), start: Number(app.editor_field(1)), end: Number(app.editor_field(2)), composing: Number(app.editor_field(5)), disposed: session.disposed }),
    start: (delayMs, value, failure = false) => dispatchTask(delayMs, value, failure),
    cancel: cancelTask,
    snapshot: () => ({ task: Array.from({ length: 6 }, (_, i) => Number(app.task_field(i))), pending: Number(app.scheduled_task_count()), rejected: session.rejectedCallbacks, disposed: session.disposed }),
  };
}
export function detach() {
  $('task-fail').removeEventListener('click', fail);
  $('task-fail').disabled = true;
}
