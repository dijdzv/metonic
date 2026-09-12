import test from 'node:test';
import assert from 'node:assert/strict';
import { createMoonBitSession } from './moonbit-session.mjs';

test('MoonBit session normal request and repeated close', async () => {
  const session = await createMoonBitSession();
  try { assert.equal((await session.client.request('snapshot')).ok, true); }
  finally { await session.close(); assert.equal(session.diagnostics().forced_kill, false); assert.equal(session.diagnostics().exit_code, 0); await session.close(); }
});

test('pre-aborted request preserves the session', async () => {
  const session = await createMoonBitSession();
  try {
    const controller = new AbortController();
    controller.abort();
    await assert.rejects(session.client.request('snapshot', {}, { signal: controller.signal }));
    assert.equal((await session.client.request('snapshot')).ok, true);
  } finally { await session.close(); }
});

test('pending limit, capture exclusion, and close rejection', async () => {
  const session = await createMoonBitSession();
  try {
    const requests = Array.from({ length: 16 }, () => session.client.request('snapshot'));
    await assert.rejects(session.client.request('snapshot'));
    await Promise.all(requests);
    await session.close();
    await assert.rejects(session.client.request('snapshot'));
  } finally { await session.close(); }
});

test('capture is exclusive and returns a PNG image', async () => {
  const session = await createMoonBitSession();
  try {
    const first = session.client.capture();
    await assert.rejects(session.client.capture());
    const captured = await first;
    assert.equal(captured.image.mimeType, 'image/png');
    assert.ok(captured.image.data.length > 0);
    const next = await session.client.capture();
    assert.equal(next.image.mimeType, 'image/png');
    assert.ok(next.image.data.length > 0);
  } finally { await session.close(); }
});

test('midflight abort rejects pending requests and closes session', async () => {
  const session = await createMoonBitSession();
  try {
    const controller = new AbortController();
    const pending = [session.client.request('snapshot', {}, { signal: controller.signal }), session.client.request('snapshot')];
    controller.abort();
    const results = await Promise.allSettled(pending);
    assert.equal(results[0].status, 'rejected');
    assert.equal(results[1].status, 'rejected');
    assert.equal(session.diagnostics().pending, 0);
    await assert.rejects(session.client.request('snapshot'));
  } finally { await session.close(); }
});
