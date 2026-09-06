import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, '..');
const serverScript = path.join(here, 'serve-browser.mjs');
const child = spawn(process.execPath, [serverScript], {
  cwd: repoRoot,
  stdio: ['ignore', 'pipe', 'pipe'],
});
let stdout = '';
let stderr = '';
child.stdout.setEncoding('utf8');
child.stderr.setEncoding('utf8');
child.stdout.on('data', (chunk) => { stdout += chunk; });
child.stderr.on('data', (chunk) => { stderr += chunk; });

const base = 'http://127.0.0.1:4173';
const ready = 'http://127.0.0.1:4173/\n';

function waitForReady() {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('server readiness timeout')), 10_000);
    const finish = (error) => {
      clearTimeout(timer);
      child.stdout.off('data', onData);
      child.off('error', onError);
      child.off('exit', onExit);
      if (error) reject(error); else resolve();
    };
    const onData = () => {
      if (stdout === ready) finish();
      else if (stdout.length > ready.length || !ready.startsWith(stdout)) {
        finish(new Error(`unexpected server stdout: ${JSON.stringify(stdout)}`));
      }
    };
    const onError = (error) => finish(error);
    const onExit = (code, signal) => finish(new Error(`server exited before ready: ${code ?? signal}`));
    child.stdout.on('data', onData);
    child.on('error', onError);
    child.on('exit', onExit);
  });
}

async function request(method, pathname) {
  return fetch(`${base}${pathname}`, { method });
}

try {
  await waitForReady();
  for (const pathname of ['/', '/host.mjs', '/app.wasm']) {
    const response = await request('GET', pathname);
    assert.equal(response.status, 200, `GET ${pathname}`);
    assert.match(response.headers.get('content-type') ?? '', /^(text\/html|text\/javascript|application\/wasm)/);
    assert.equal(response.headers.get('cache-control'), 'no-store');
  }
  const wasm = await request('GET', '/app.wasm');
  const wasmBody = await wasm.arrayBuffer();
  const head = await request('HEAD', '/app.wasm');
  assert.equal(head.status, 200);
  assert.equal(head.headers.get('content-length'), String(wasmBody.byteLength));
  assert.equal(await head.text(), '');

  const post = await request('POST', '/');
  assert.equal(post.status, 405);
  assert.equal(post.headers.get('allow'), 'GET, HEAD');
  for (const pathname of ['/package.json', '/.env', '/toolchain.json', '/../package.json', '/app.wasm/extra', '/..%2fpackage.json']) {
    assert.equal((await request('GET', pathname)).status, 404, `GET ${pathname}`);
  }
  assert.equal((await request('GET', '/?target=js')).status, 200);
  console.log('browser server constraints verified');
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  if (stderr) console.error(stderr.trim());
  process.exitCode = 1;
} finally {
  child.kill();
}
