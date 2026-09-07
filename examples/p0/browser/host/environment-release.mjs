export const target = 'wasm-gc';
export const ready = 'Ready';
export function task(values) {
  document.getElementById('task-state').textContent = ['Idle', 'Working…', 'Completed', 'Failed', 'Canceled', 'Stopped'][values[0]] ?? 'Unavailable';
}
export function frame() {}
export function text() {}
export function dimensions() {}
export function loaded() {}
export function attach() {}
export function detach() {}
