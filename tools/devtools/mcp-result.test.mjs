import assert from 'node:assert/strict';
import test from 'node:test';
import { native_mcp_result, native_mcp_failure, window_mcp_result } from '../../_build/js/release/build/tools/session_wire/session_wire.js';

function normalized(result) {
  return { ...result, content: result.content.map(item => item.type === 'text' ? { ...item, text: JSON.parse(item.text) } : item) };
}

test('generated MoonBit results preserve the native SDK content contract', () => {
  for (const response of [
    { ok: true, frame: 9007199254740991, state: [0, 1, 2] },
    { ok: false, error: '古い結果\nretry', session_id: 'response-session' },
  ]) {
    for (const image of [undefined, { data: 'AA==', mimeType: 'image/png' }, { data: 'AA==', mimeType: '' }]) {
      const content = [{ type: 'text', text: JSON.stringify({ session_id: 'session', ...response }) }];
      if (image) content.push({ type: 'image', data: image.data, mimeType: image.mimeType || 'image/png' });
      const actual = JSON.parse(native_mcp_result('session', JSON.stringify(response), image ? JSON.stringify(image) : ''));
      assert.deepEqual(normalized(actual), normalized({ content, isError: response.ok === false }));
    }
  }
  assert.deepEqual(normalized(JSON.parse(native_mcp_failure('session', '取消\nfailed'))), {
    isError: true, content: [{ type: 'text', text: { session_id: 'session', ok: false, error: '取消\nfailed' } }],
  });
});

test('generated MoonBit window content preserves image ordering and optional metadata', () => {
  for (const image of [undefined, { data: 'AA==', mimeType: 'image/png' }, { data: 'AA==', mimeType: 'image/png', width: 3, height: 4, frame: 42, source: 'offscreen' }]) {
    const state = { text: '日本語\nabc', frames: 42, session_id: 'response-session', image };
    const { image: ignored, ...metadata } = state;
    const content = [{ type: 'text', text: JSON.stringify({ session_id: 'session', ...metadata }) }];
    if (image) {
      content.push({ type: 'image', data: image.data, mimeType: image.mimeType });
      content.push({ type: 'text', text: JSON.stringify({ width: image.width, height: image.height, frame: image.frame, source: image.source }) });
    }
    assert.deepEqual(normalized(JSON.parse(window_mcp_result('session', JSON.stringify(state)))), normalized({ content }));
  }
});
