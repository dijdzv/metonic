import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import { PNG } from 'pngjs';
import { Client } from '@modelcontextprotocol/client';
import { StdioClientTransport } from '@modelcontextprotocol/client/stdio';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const outputRoot = path.join(repoRoot, '.work', 'native-mcp');
const server = path.join(repoRoot, 'tools', 'devtools', 'native-mcp.mjs');

function responseText(result) {
  const block = result?.content?.find((item) => item.type === 'text');
  if (!block) throw new Error('MCP response has no text content');
  return JSON.parse(block.text);
}

function assertSession(response, sessionId) {
  assert.equal(response.session_id, sessionId);
}

async function verify() {
  await fs.mkdir(outputRoot, { recursive: true });
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [server],
    cwd: repoRoot,
    env: Object.fromEntries(Object.entries(process.env).filter(([, value]) => typeof value === 'string')),
    stderr: 'pipe',
  });
  const client = new Client({ name: 'metonic-verifier', version: '0.0.0' });
  clientForTimeout = client;
  transportForTimeout = transport;
  try {
    await client.connect(transport);
    const listed = await client.listTools();
    const names = listed.tools.map((tool) => tool.name).sort();
    assert.deepEqual(names, ['native_activate', 'native_capture', 'native_move', 'native_resize', 'native_snapshot']);
    const initial = responseText(await client.callTool({ name: 'native_snapshot', arguments: {} }));
    const sessionId = initial.session_id;
    assert.deepEqual(initial.state, [260, 144, 120, 72, 0, 0, 640, 360]);
    const moved = responseText(await client.callTool({ name: 'native_move', arguments: { x: 10, y: 20, expected_revision: 0 } }));
    assertSession(moved, sessionId);
    assert.deepEqual(moved.state.slice(0, 2), [10, 20]);
    assert.equal(moved.state[5], 1);
    const activated = responseText(await client.callTool({ name: 'native_activate', arguments: { expected_revision: 1 } }));
    assertSession(activated, sessionId);
    assert.equal(activated.state[4], 1);
    assert.equal(activated.state[5], 2);
    const capturedResult = await client.callTool({ name: 'native_capture', arguments: { expected_revision: 2 } });
    assert.equal(capturedResult.isError, false);
    const captured = responseText(capturedResult);
    assertSession(captured, sessionId);
    assert.equal(captured.state[5], 2);
    assert.equal(captured.frame, 1);
    const imageBlock = capturedResult.content.find((item) => item.type === 'image');
    assert.ok(imageBlock?.data, 'capture must include an image content block');
    const png = PNG.sync.read(Buffer.from(imageBlock.data, 'base64'));
    const [x, y, width, height] = captured.state;
    assert.equal(png.width, captured.state[6]);
    assert.equal(png.height, captured.state[7]);
    for (let py = 0; py < png.height; py += 1) {
      for (let px = 0; px < png.width; px += 1) {
        const offset = (py * png.width + px) * 4;
        const inside = px >= x && px < x + width && py >= y && py < y + height;
        const expected = inside ? [242, 97, 26, 255] : [5, 20, 38, 255];
        for (let channel = 0; channel < 4; channel += 1) assert.ok(Math.abs(png.data[offset + channel] - expected[channel]) <= 1);
      }
    }
    const stale = await client.callTool({ name: 'native_move', arguments: { x: 1, y: 1, expected_revision: 0 } });
    assert.equal(stale.isError, true);
    assert.equal(responseText(stale).error, 'stale_revision');
    const invalid = await client.callTool({ name: 'native_resize', arguments: { width: 0, height: 0, expected_revision: 2 } });
    assert.equal(invalid.isError, true);
    const afterInvalid = responseText(await client.callTool({ name: 'native_snapshot', arguments: {} }));
    assertSession(afterInvalid, sessionId);
    assert.deepEqual(afterInvalid.state, captured.state);
    const mode = process.env.METONIC_GPU_FALLBACK === '1' ? 'fallback' : 'default';
    await fs.writeFile(path.join(outputRoot, `${mode}.png`), Buffer.from(imageBlock.data, 'base64'));
    let serverVersion = null;
    if (typeof client.getServerVersion === 'function') serverVersion = client.getServerVersion();
    await fs.writeFile(path.join(outputRoot, `${mode}.json`), JSON.stringify({ session_id: sessionId, state: captured.state, server_version: serverVersion }, null, 2));
    return { mode, session_id: sessionId, state: captured.state, server_version: serverVersion };
  } finally {
    await client.close().catch(() => {});
    await transport.close().catch(() => {});
  }
}

let timer;
let transportForTimeout;
let clientForTimeout;
const run = verify();
const deadline = new Promise((_, reject) => {
  timer = setTimeout(async () => {
    await clientForTimeout?.close().catch(() => {});
    await transportForTimeout?.close().catch(() => {});
    reject(new Error('verification timed out after 30 seconds'));
  }, 30_000);
});
try {
  const result = await Promise.race([run, deadline]);
  process.stdout.write(`${JSON.stringify({ ok: true, ...result })}\n`);
} catch (error) {
  process.stderr.write(`${error?.stack || error}\n`);
  process.exitCode = 1;
} finally {
  clearTimeout(timer);
}
