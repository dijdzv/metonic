import { spawn } from 'node:child_process';
import path from 'node:path';
import { StringDecoder } from 'node:string_decoder';
import { fileURLToPath } from 'node:url';

const MAX_PENDING = 16;
const MAX_STDOUT = 32 * 1024 * 1024;
const MAX_STDERR = 16 * 1024;

export async function createMoonBitSession() {
  const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
  const executable = path.join(repo, '.tools', 'moonbit', 'bin', 'moonrun.exe');
  const program = path.join(repo, '_build', 'wasm', 'release', 'build', 'tools', 'native_session', 'native_session.wasm');
  const child = spawn(executable, [program, '--root', repo], { cwd: repo, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
  const pending = new Map();
  const decoder = new StringDecoder('utf8');
  let line = '';
  let nextId = 1;
  let sessionId;
  let fatalError;
  let closing = false;
  let closePromise;
  let captureBusy = false;
  let readyResolve;
  let readyReject;
  const ready = new Promise((resolve, reject) => { readyResolve = resolve; readyReject = reject; });
  const stderrChunks = [];
  let stderrBytes = 0;
  let exited = false;
  let exitCode;
  let forcedKill = false;
  let stdinEnded = false;
  let resolveExited;
  const exitedPromise = new Promise(resolve => { resolveExited = resolve; });

  function diagnosticError(message) {
    const error = new Error(message);
    error.stderr = Buffer.concat(stderrChunks).toString('utf8');
    return error;
  }
  function fail(error) {
    if (fatalError) return;
    fatalError = error instanceof Error ? error : new Error(String(error));
    readyReject(fatalError);
    for (const waiter of pending.values()) waiter.reject(fatalError);
    pending.clear();
    void close().catch(error => console.error(error));
  }
  function dispatch(value) {
    if (value?.id === 0 && !sessionId) {
      if (value.ok !== true || typeof value.session_id !== 'string' || value.session_id.length === 0) return fail(new Error('invalid session ready response'));
      sessionId = value.session_id;
      readyResolve(sessionId);
      return;
    }
    if (!Number.isSafeInteger(value?.id) || value.id < 1 || typeof value.ok !== 'boolean') return fail(new Error('invalid response schema'));
    const waiter = pending.get(value.id);
    if (!waiter) return fail(new Error('unknown response id'));
    if (value.ok !== true) {
      if (typeof value.error !== 'string') return fail(new Error('invalid response error'));
      pending.delete(value.id);
      waiter.reject(new Error(value.error));
    } else {
      if (!validNativeResponse(value.response)) return fail(new Error('invalid native response'));
      pending.delete(value.id);
      waiter.resolve(value);
    }
  }
  function validNativeResponse(response) {
    const state = response?.state;
    return response && typeof response === 'object' && Number.isInteger(response.version) && response.version === 1 &&
      Number.isInteger(response.id) && response.id > 0 && typeof response.ok === 'boolean' &&
      (response.ok || typeof response.error === 'string') && Array.isArray(state) && state.length === 8 &&
      state.every(Number.isInteger) && Number.isInteger(state[6]) && state[6] >= 1 && state[6] <= 2048 &&
      Number.isInteger(state[7]) && state[7] >= 1 && state[7] <= 2048 && Number.isInteger(response.frame) && response.frame >= 0;
  }
  child.stdout.on('data', (chunk) => {
    line += decoder.write(chunk);
    let index;
    while ((index = line.indexOf('\n')) >= 0) {
      const text = line.slice(0, index).replace(/\r$/, '');
      line = line.slice(index + 1);
      if (Buffer.byteLength(text, 'utf8') > MAX_STDOUT) return fail(new Error('native session response line exceeds 32MiB'));
      try { dispatch(JSON.parse(text)); } catch (error) { fail(new Error(`invalid native session response: ${error.message}`)); }
    }
    if (Buffer.byteLength(line, 'utf8') > MAX_STDOUT) return fail(new Error('native session response line exceeds 32MiB'));
  });
  child.stdout.on('error', fail);
  child.stdin.on('error', fail);
  child.stderr.on('data', (chunk) => {
    const data = Buffer.from(chunk);
    stderrChunks.push(data);
    stderrBytes += data.length;
    while (stderrBytes > MAX_STDERR) {
      const first = stderrChunks[0];
      const excess = stderrBytes - MAX_STDERR;
      if (first.length <= excess) { stderrChunks.shift(); stderrBytes -= first.length; }
      else { stderrChunks[0] = first.subarray(excess); stderrBytes -= excess; }
    }
  });
  child.on('error', fail);
  child.on('close', (code, signal) => {
    exited = true;
    exitCode = code;
    resolveExited();
    if (!closing && !fatalError) fail(diagnosticError(`native session exited (${code ?? 'null'}, ${signal ?? 'none'})`));
  });
  const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));
  const waitExited = (ms) => {
    let timer;
    return Promise.race([exitedPromise, new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('native session exit timeout')), ms); })]).finally(() => clearTimeout(timer));
  };
  const abortError = () => new Error('native session request aborted');
  async function requestEnvelope(op, args = {}, options = {}) {
    if (options.signal?.aborted) return Promise.reject(abortError());
    if (fatalError || closing) return Promise.reject(new Error('native session is closed'));
    if (pending.size >= MAX_PENDING) return Promise.reject(new Error('native session pending limit exceeded'));
    const id = nextId++;
    if (id > 2147483647) return Promise.reject(new Error('native session request id exhausted'));
    return new Promise((resolve, reject) => {
      const signal = options.signal;
      const cleanup = () => { clearTimeout(timer); signal?.removeEventListener('abort', onAbort); };
      const timer = setTimeout(() => { cleanup(); pending.delete(id); fail(new Error('native session request timed out')); reject(new Error('native session request timed out')); }, 15000);
      const onAbort = () => { cleanup(); pending.delete(id); fail(abortError()); reject(abortError()); };
      pending.set(id, { resolve: value => { cleanup(); resolve(value); }, reject: error => { cleanup(); reject(error); } });
      signal?.addEventListener('abort', onAbort, { once: true });
      try { child.stdin.write(`${JSON.stringify({ id, op, args })}\n`); }
      catch (error) { cleanup(); pending.delete(id); fail(error); reject(error); }
    });
  }
  async function request(op, args = {}, options = {}) {
    const envelope = await requestEnvelope(op, args, options);
    return envelope.response;
  }
  async function capture({ expected_revision, signal } = {}) {
    if (captureBusy) throw new Error('native session capture already in progress');
    captureBusy = true;
    try {
      const value = await requestEnvelope('capture', { expected_revision }, { signal });
      if (!value.image || value.image.mimeType !== 'image/png' || typeof value.image.data !== 'string' || value.image.data.length === 0) throw new Error('native session capture has no valid image');
      return { response: value.response, image: value.image };
    } finally { captureBusy = false; }
  }
  async function close() {
    if (closePromise) return closePromise;
    closePromise = (async () => {
      closing = true;
      for (const waiter of pending.values()) waiter.reject(new Error('native session closed'));
      pending.clear();
      if (!stdinEnded) { stdinEnded = true; child.stdin.end(); }
      try {
        await waitExited(2000);
      } catch (error) {
        if (!exited) { forcedKill = true; child.kill('SIGKILL'); }
        await waitExited(2000).catch(() => {});
        if (!exited) throw error;
      }
      if (!exited) throw diagnosticError('native session did not exit');
      if (forcedKill || exitCode !== 0) throw diagnosticError(`native session close failed (${exitCode ?? 'null'})`);
    })();
    return closePromise;
  }
  let readyTimer;
  try {
    await Promise.race([ready, new Promise((_, reject) => { readyTimer = setTimeout(() => reject(diagnosticError('native session ready timeout')), 15000); })]);
  } catch (error) {
    await close();
    throw error;
  } finally {
    clearTimeout(readyTimer);
  }
  const diagnostics = () => ({ session: sessionId, stderr: Buffer.concat(stderrChunks).toString('utf8'), pending: pending.size, forced_kill: forcedKill, exit_code: exitCode });
  return { client: { session: sessionId, request, capture, diagnostics }, close, diagnostics };
}
