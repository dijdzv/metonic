import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createMoonBitSession } from './moonbit-session.mjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const moonrun = path.join(repo, '.tools', 'moonbit', 'bin', 'moonrun.exe');
const fixture = path.join(repo, '_build', 'wasm', 'release', 'build', 'tools', 'session_fixture', 'session_fixture.wasm');
const opts = (mode, extra = {}) => ({ executable: moonrun, args: [fixture, mode], readyTimeoutMs: 2000, requestTimeoutMs: 2000, closeTimeoutMs: 200, ...extra });

for (const mode of ['attachment-change', 'attachment-empty']) {
  test(`${mode} rejects outstanding requests and releases the child`, { timeout: 10000 }, async () => {
    const session = await createMoonBitSession(opts(mode, { protocol: 'window-attach' }));
    try {
      assert.equal(session.client.session, 'fixture-session');
      const results = await Promise.allSettled([session.client.request('snapshot'), session.client.request('snapshot')]);
      for (const result of results) {
        assert.equal(result.status, 'rejected');
        assert.match(result.reason.message, /attachment session identity mismatch/);
      }
      assert.equal(session.diagnostics().pending, 0);
      await assert.rejects(session.client.request('snapshot'), /closed/);
    } finally {
      await session.close();
      assert.equal(session.diagnostics().exit_code, 0);
      assert.equal(session.diagnostics().forced_kill, false);
    }
  });
}

test('missing executable preserves ENOENT', { timeout: 10000 }, async () => {
  await assert.rejects(createMoonBitSession(opts('normal', { executable: path.join(repo, 'missing-session-executable.exe') })), e => e?.code === 'ENOENT');
});

test('invalid ready response is rejected', { timeout: 10000 }, async () => {
  await assert.rejects(createMoonBitSession(opts('bad-ready')), /invalid session ready response/);
});

test('invalid UTF-8 ready response is rejected', { timeout: 10000 }, async () => {
  await assert.rejects(createMoonBitSession(opts('bad-utf8-ready')), /UTF-8/);
});

test('partial ready response is rejected', { timeout: 10000 }, async () => {
  await assert.rejects(createMoonBitSession(opts('partial-ready')), /truncated/);
});

test('malformed response rejects all pending requests', { timeout: 10000 }, async () => {
  const session = await createMoonBitSession(opts('bad-response'));
  try {
    const results = await Promise.allSettled([session.client.request('snapshot'), session.client.request('snapshot')]);
    assert.equal(results[0].status, 'rejected');
    assert.equal(results[1].status, 'rejected');
    assert.match(results[0].reason.message, /invalid native response/);
    assert.match(results[1].reason.message, /invalid native response/);
    assert.equal(session.diagnostics().pending, 0);
  } finally { await session.close(); assert.equal(session.diagnostics().exit_code, 0); assert.equal(session.diagnostics().forced_kill, false); }
});

test('unknown response id is fatal', { timeout: 10000 }, async () => {
  const session = await createMoonBitSession(opts('unknown-id'));
  try {
    await assert.rejects(session.client.request('snapshot'), /unknown response id/);
    assert.equal(session.diagnostics().pending, 0);
  } finally { await session.close(); assert.equal(session.diagnostics().exit_code, 0); assert.equal(session.diagnostics().forced_kill, false); }
});

test('overlong response line is rejected', { timeout: 10000 }, async () => {
  const session = await createMoonBitSession(opts('overlong'));
  try { await assert.rejects(session.client.request('snapshot'), /exceeds 32MiB/); assert.equal(session.diagnostics().pending, 0); }
  finally { await session.close(); assert.equal(session.diagnostics().exit_code, 0); assert.equal(session.diagnostics().forced_kill, false); }
});

test('missing ready times out', { timeout: 10000 }, async () => {
  await assert.rejects(createMoonBitSession(opts('no-ready', { readyTimeoutMs: 500 })), /ready timeout/);
});

test('nonzero close is reported', { timeout: 10000 }, async () => {
  const session = await createMoonBitSession(opts('nonzero'));
  try { await assert.rejects(session.close(), /close failed/); assert.equal(session.diagnostics().exit_code, 19); }
  finally { await session.close().catch(() => {}); }
});

test('hung close is force killed', { timeout: 10000 }, async () => {
  const session = await createMoonBitSession(opts('hang-close'));
  try { assert.equal((await session.client.request('snapshot')).ok, true); await assert.rejects(session.close(), /close failed|did not exit|timeout/); assert.equal(session.diagnostics().forced_kill, true); }
  finally { await session.close().catch(() => {}); }
});

test('oversized request rejection preserves session', { timeout: 10000 }, async () => {
  const session = await createMoonBitSession(opts('normal'));
  try { await assert.rejects(session.client.request('echo', { value: 'x'.repeat(5000) }), /exceeds 4095 bytes/); assert.equal((await session.client.request('snapshot')).ok, true); assert.equal(session.diagnostics().pending, 0); }
  finally { await session.close(); assert.equal(session.diagnostics().exit_code, 0); assert.equal(session.diagnostics().forced_kill, false); }
});

test('cyclic arguments reject and session recovers', { timeout: 10000 }, async () => {
  const session = await createMoonBitSession(opts('normal'));
  try {
    const cyclic = {};
    cyclic.self = cyclic;
    await assert.rejects(session.client.request('echo', cyclic), /circular|serialize|JSON/i);
    assert.equal((await session.client.request('snapshot')).ok, true);
  } finally {
    await session.close();
    assert.equal(session.diagnostics().exit_code, 0);
    assert.equal(session.diagnostics().forced_kill, false);
  }
});

test('JSON request body accepts 4095 and rejects 4096 bytes', { timeout: 10000 }, async () => {
  const session = await createMoonBitSession(opts('normal'));
  try {
    const prefix = '{"id":1,"op":"echo","args":{"value":"';
    const suffix = '"}}';
    const valueLength = target => target - Buffer.byteLength(prefix) - Buffer.byteLength(suffix);
    const body4095 = prefix + 'x'.repeat(valueLength(4095)) + suffix;
    const body4096 = prefix + 'x'.repeat(valueLength(4096)) + suffix;
    assert.equal(Buffer.byteLength(body4095), 4095);
    assert.equal(Buffer.byteLength(body4096), 4096);
    await session.client.request('echo', { value: 'x'.repeat(valueLength(4095)) });
    await assert.rejects(session.client.request('echo', { value: 'x'.repeat(valueLength(4096)) }), /exceeds 4095 bytes/);
    assert.equal((await session.client.request('snapshot')).ok, true);
  } finally {
    await session.close();
    assert.equal(session.diagnostics().exit_code, 0);
    assert.equal(session.diagnostics().forced_kill, false);
  }
});

test('invalid arguments rejection preserves session', { timeout: 10000 }, async () => {
  const session = await createMoonBitSession(opts('normal'));
  try { await assert.rejects(session.client.request('snapshot', null), /invalid native session request/); await assert.rejects(session.client.request('snapshot', []), /invalid native session request/); assert.equal((await session.client.request('snapshot')).ok, true); assert.equal(session.diagnostics().pending, 0); }
  finally { await session.close(); assert.equal(session.diagnostics().exit_code, 0); assert.equal(session.diagnostics().forced_kill, false); }
});

test('serialized non-object arguments reject before transport and preserve session', { timeout: 10000 }, async () => {
  const session = await createMoonBitSession(opts('normal'));
  try {
    for (const value of [null, [], 'text', 1]) {
      await assert.rejects(session.client.request('echo', { toJSON: () => value }), /invalid native session request/);
      assert.equal(session.diagnostics().pending, 0);
    }
    assert.equal((await session.client.request('snapshot')).ok, true);
  } finally {
    await session.close();
    assert.equal(session.diagnostics().exit_code, 0);
    assert.equal(session.diagnostics().forced_kill, false);
  }
});
