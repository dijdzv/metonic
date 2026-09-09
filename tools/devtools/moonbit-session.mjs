import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { validate_response } from '../../_build/js/release/build/tools/session_wire/session_wire.js';

const MAX_PENDING = 16;
const MAX_STDOUT = 32 * 1024 * 1024;
const MAX_STDERR = 16 * 1024;

export async function createMoonBitSession(options = {}) {
  const attached = options.protocol === 'window-attach';
  const windowProtocol = options.protocol === 'window' || attached;
  if (options.protocol !== undefined && !['window', 'window-attach', 'headless'].includes(options.protocol)) throw new Error('unknown session protocol');
  const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
  const executable = options.executable ?? path.join(repo, '.tools', 'moonbit', 'bin', 'moonrun.exe');
  const program = path.join(repo, '_build', 'wasm', 'release', 'build', 'tools', 'native_session', 'native_session.wasm');
  const args = options.args ?? [program, '--root', repo];
  const readyTimeoutMs = options.readyTimeoutMs ?? 15000;
  const requestTimeoutMs = options.requestTimeoutMs ?? 15000;
  const closeTimeoutMs = options.closeTimeoutMs ?? 2000;
  if (!path.isAbsolute(executable) || !Array.isArray(args) || !args.every(arg => typeof arg === 'string') ||
      !Number.isFinite(readyTimeoutMs) || readyTimeoutMs <= 0 || !Number.isFinite(requestTimeoutMs) || requestTimeoutMs <= 0 ||
      !Number.isFinite(closeTimeoutMs) || closeTimeoutMs <= 0) throw new Error('invalid MoonBit session launch options');
  const child = spawn(executable, args, { cwd: repo, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
  const pending = new Map();
  const decoder = new TextDecoder('utf-8', { fatal: true });
  let lineParts = [];
  let lineBytes = 0;
  let nextId = 1;
  let sessionId = windowProtocol && !attached ? randomUUID() : undefined;
  let fatalError;
  let closing = false;
  let closePromise;
  let captureBusy = false;
  let readyResolve;
  let readyReject;
  const ready = new Promise((resolve, reject) => { readyResolve = resolve; readyReject = reject; });
  if (windowProtocol) ready.catch(() => {});
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
    lineParts = [];
    lineBytes = 0;
    void close().catch(error => console.error(error));
  }
  function dispatch(value) {
    if (attached) {
      if (typeof value.session_id !== 'string' || !value.session_id ||
          (sessionId && sessionId !== value.session_id)) return fail(new Error('attachment session identity mismatch'));
      sessionId = value.session_id;
    }
    if (windowProtocol) {
      value = { id: value.id, ok: value.error === '', error: value.error, response: value };
    }
    if (value?.id === 0 && !sessionId) {
      sessionId = value.session_id;
      readyResolve(sessionId);
      return;
    }
    const waiter = pending.get(value.id);
    if (!waiter) return fail(new Error('unknown response id'));
    if (value.ok !== true) {
      pending.delete(value.id);
      waiter.reject(new Error(value.error));
    } else {
      pending.delete(value.id);
      waiter.resolve(value);
    }
  }
  child.stdout.on('data', (chunk) => {
    if (fatalError) return;
    let decoded;
    try { decoded = decoder.decode(chunk, { stream: true }); }
    catch (error) { fail(new Error(`invalid UTF-8 from native session: ${error.message}`)); return; }
    const parts = decoded.split('\n');
    for (let i = 0; i < parts.length - 1; i += 1) {
      lineParts.push(parts[i]);
      lineBytes += Buffer.byteLength(parts[i], 'utf8');
      if (lineBytes > MAX_STDOUT) return fail(new Error('native session response line exceeds 32MiB'));
      const text = lineParts.join('').replace(/\r$/, '');
      lineParts = [];
      lineBytes = 0;
      try {
        const error = validate_response(text, windowProtocol, !sessionId);
        if (error) { fail(new Error(error)); return; }
        dispatch(JSON.parse(text));
      } catch (error) { fail(new Error(`invalid native session response: ${error.message}`)); return; }
      if (fatalError) return;
    }
    const tail = parts[parts.length - 1];
    lineParts.push(tail);
    lineBytes += Buffer.byteLength(tail, 'utf8');
    if (lineBytes > MAX_STDOUT) return fail(new Error('native session response line exceeds 32MiB'));
  });
  child.stdout.on('end', () => {
    if (fatalError) return;
    try {
      lineParts.push(decoder.decode());
      if (lineParts.join('').length > 0) fail(new Error('truncated native session response line'));
    } catch (error) { fail(new Error(`invalid UTF-8 at native session EOF: ${error.message}`)); }
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
    if (typeof op !== 'string' || !args || typeof args !== 'object' || Array.isArray(args)) return Promise.reject(new Error('invalid native session request'));
    let payload;
    try { payload = `${JSON.stringify(windowProtocol ? { ...args, id, op } : { id, op, args })}\n`; }
    catch (error) { return Promise.reject(new Error(`invalid native session request: ${error.message}`)); }
    if (Buffer.byteLength(payload, 'utf8') - 1 > 4095) return Promise.reject(new Error('native session request exceeds 4095 bytes'));
    return new Promise((resolve, reject) => {
      const signal = options.signal;
      const cleanup = () => { clearTimeout(timer); signal?.removeEventListener('abort', onAbort); };
      const timer = setTimeout(() => { cleanup(); pending.delete(id); fail(new Error('native session request timed out')); reject(new Error('native session request timed out')); }, requestTimeoutMs);
      const onAbort = () => { cleanup(); pending.delete(id); fail(abortError()); reject(abortError()); };
      pending.set(id, { resolve: value => { cleanup(); resolve(value); }, reject: error => { cleanup(); reject(error); } });
      signal?.addEventListener('abort', onAbort, { once: true });
      try { child.stdin.write(payload); }
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
        await waitExited(closeTimeoutMs);
      } catch (error) {
        if (!exited) { forcedKill = true; child.kill('SIGKILL'); }
        await waitExited(closeTimeoutMs).catch(() => {});
        if (!exited) throw error;
      }
      if (!exited) throw diagnosticError('native session did not exit');
      if (forcedKill || exitCode !== 0) throw diagnosticError(`native session close failed (${exitCode ?? 'null'})`);
    })();
    return closePromise;
  }
  let readyTimer;
  try {
    const readiness = windowProtocol ? requestEnvelope('snapshot') : ready;
    await Promise.race([readiness, new Promise((_, reject) => { readyTimer = setTimeout(() => reject(diagnosticError('native session ready timeout')), readyTimeoutMs); })]);
  } catch (error) {
    try { await close(); }
    catch (cleanupError) { error.cleanupError = cleanupError; }
    throw error;
  } finally {
    clearTimeout(readyTimer);
  }
  const diagnostics = () => ({ session: sessionId, stderr: Buffer.concat(stderrChunks).toString('utf8'), pending: pending.size, forced_kill: forcedKill, exit_code: exitCode });
  return { client: { session: sessionId, request, capture, diagnostics }, close, diagnostics };
}
