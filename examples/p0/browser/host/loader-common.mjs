const REQUIRED = ['init', 'resize', 'move_to', 'activate', 'field', 'task_begin', 'task_complete', 'task_fail', 'task_cancel', 'task_dispose', 'task_field', 'font_begin', 'font_put', 'font_commit', 'text_begin', 'text_put', 'text_commit', 'text_width', 'text_pixel', 'text_dispose'];

export function wasmImports() {
  let buffer = '';
  return { spectest: { print_char(codepoint) {
    buffer += String.fromCodePoint(Number(codepoint));
    if (buffer.includes('\n') || buffer.length >= 1024) {
      console.warn(buffer);
      buffer = '';
    }
  } } };
}

export function validateExports(exports, target) {
  for (const name of REQUIRED) {
    if (typeof exports[name] !== 'function') {
      throw new Error(`${target} artifact is missing required export: ${name}`);
    }
  }
  return exports;
}
