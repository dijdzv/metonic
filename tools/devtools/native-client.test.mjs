import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const fixture = path.join(here, 'fixtures/control-host.mjs');
const clientModule = await import('./native-client.mjs');
const NativeClient = clientModule.NativeClient ?? clientModule.default;
assert.equal(typeof NativeClient, 'function', 'native-client must export NativeClient');

function makeClient(options = {}) {
  return new NativeClient({
    executable: process.execPath,
    args: [fixture],
    bridge: path.join(here, 'fixtures/fake-bridge.dll'),
    capturePath: path.join(here, 'fixtures/capture.rgba'),
    timeoutMs: 2000,
    maxPending: 8,
    ...options,
  });
}

test('successful request preserves id and supports snapshot/echo', async () => {
  const client = makeClient();
  try {
    const echo = await client.request('echo', { hello: 'world' });
    assert.equal(echo.ok, true);
    assert.equal(echo.id, 1);
    assert.equal(echo.version, 1);
    assert.deepEqual(echo.state, [260, 144, 120, 72, 0, 0, 640, 360]);
    const snapshot = await client.request('snapshot');
    assert.equal(snapshot.state[5], 0);
  } finally { await client.close(); }
});

test('capture sends expected revision and returns diagnostics', async () => {
  const client = makeClient();
  try {
    await client.request('snapshot');
    await assert.rejects(client.capture({ expected_revision: 99 }), /revision|capture|unsupported/i);
    assert.ok(client.diagnostics !== undefined);
  } finally { await client.close(); }
});

test('timeout rejects multiple pending requests', async () => {
  const client = makeClient({ timeoutMs: 2000 });
  try {
    const startup = await client.request('snapshot');
    assert.equal(startup.ok, true);
    client.timeoutMs = 50;
    const pending = [client.request('delay', { ms: 200 }), client.request('delay', { ms: 200 })];
    const results = await Promise.allSettled(pending);
    assert.deepEqual(results.map((result) => result.status), ['rejected', 'rejected']);
  } finally { await client.close(); }
});

test('AbortSignal cancels requests without killing the session', async () => {
  const client = makeClient();
  const controller = new AbortController();
  controller.abort();
  try {
    await assert.rejects(client.request('echo', { sent: false }, { signal: controller.signal }), /abort/i);
    const snapshot = await client.request('snapshot');
    assert.equal(snapshot.ok, true);
    const midflight = new AbortController();
    const pending = client.request('delay', { ms: 200 }, { signal: midflight.signal });
    midflight.abort();
    await assert.rejects(pending, /abort/i);
  } finally { await client.close(); }
});

test('queue limit, malformed response, unknown id, early exit and close are reported', async () => {
  const client = makeClient({ maxPending: 1, timeoutMs: 2000 });
  try {
    const first = client.request('delay', { ms: 80 });
    await assert.rejects(client.request('echo', { queued: false }), /pending|queue|busy/i);
    await first;
  } finally { await client.close(); await client.close(); }

  const malformed = makeClient();
  try { await assert.rejects(malformed.request('malformed'), /malformed|protocol|JSON/i); } finally { await malformed.close(); }

  const unknown = makeClient();
  try { await assert.rejects(unknown.request('unknownID'), /unknown|protocol|id/i); } finally { await unknown.close(); }

  const early = makeClient();
  try { await assert.rejects(early.request('exit', { code: 19 }), /exit|closed|child|process/i); } finally { await early.close(); }

  const oversize = makeClient();
  try { await assert.rejects(oversize.request('oversize', { bytes: 2 * 1024 * 1024 }), /size|exceeds|protocol|frame/i); } finally { await oversize.close(); }

  const stderr = makeClient();
  try {
    assert.equal((await stderr.request('stderrFlood', { bytes: 65536 })).ok, true);
    await stderr.close();
    assert.equal(stderr.diagnostics?.stderr?.length, 16 * 1024);
    await assert.rejects(stderr.request('snapshot'), /closed|close|process/i);
  } finally { await stderr.close(); }
});
