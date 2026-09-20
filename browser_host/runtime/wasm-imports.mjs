import { createImports } from './websys-input.mjs';

export function wasmImports() {
  let buffer = '';
  const websys = createImports();
  websys.websys.input_document = () => document;
  websys.websys.input_window = () => window;
  websys.websys.gpu_resolve = value => Promise.resolve(value);
  websys.websys.gpu_then = (promise, callback) => promise.then(callback);
  websys.websys.font_completion = () => Promise.withResolvers();
  websys.websys.font_promise = completion => completion.promise;
  websys.websys.font_resolve = (completion, value) => completion.resolve(value);
  websys.websys.font_reject = (completion, message) => completion.reject(new Error(message));
  return { ...websys, console: { log: (...values) => console.log(...values) }, spectest: { print_char(codepoint) {
    buffer += String.fromCodePoint(Number(codepoint));
    if (buffer.includes('\n') || buffer.length >= 1024) {
      console.warn(buffer);
      buffer = '';
    }
  } } };
}
