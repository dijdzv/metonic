import { Client } from '@modelcontextprotocol/client';
import { StdioClientTransport } from '@modelcontextprotocol/client/stdio';
import { verify, verify_attachment, verify_cancel_result, verify_sdk_cancel } from '../_build/js/release/build/tools/verify_window_mcp/verify_window_mcp.js';
import { createMoonBitSession } from '../tools/devtools/moonbit-session.mjs';
import path from 'node:path';
const attachment = process.argv.slice(2);
if (attachment.length && (attachment.length !== 3 || attachment[0] !== '--session')) throw new Error('invalid verifier arguments');
const transport = new StdioClientTransport({
  command: process.execPath,
  args: ['tools/devtools/window-mcp.mjs', ...attachment.slice(0, 2)],
  cwd: process.cwd(),
  env: { ...process.env, METONIC_DEV_HIDDEN: '1', METONIC_WINDOW_TEST: '0' },
  stderr: 'pipe',
});
const client = new Client({ name: 'metonic-window-verifier', version: '0.0.0' });
const timer = setTimeout(() => { console.error('window MCP verification timed out'); void transport.close(); }, 25000);
try {
  await client.connect(transport);
  console.log(await (attachment.length ? verify_attachment(client, attachment[2]) : verify(client)));
  if (attachment.length) {
    const controller = new AbortController();
    const send = transport.send.bind(transport);
    let notified = false;
    transport.send = async (message, options) => {
      await send(message, options);
      if (message.method === 'notifications/cancelled') notified = true;
      if (message.method === 'tools/call' && message.params?.name === 'window_capture') controller.abort();
    };
    let rejected = false;
    try { await client.callTool({ name: 'window_capture', arguments: {} }, { signal: controller.signal }); }
    catch { rejected = true; }
    console.log(await verify_sdk_cancel(client, rejected, notified));
  }
} finally {
  clearTimeout(timer);
  await client.close();
}
if (attachment.length) {
  const session = await createMoonBitSession({
    protocol: 'window-attach',
    executable: path.resolve('.tools/moonbit/bin/moonrun.exe'),
    args: [path.resolve('_build/wasm/release/build/tools/native_cli/native_cli.wasm'), '--session-wire', path.resolve(attachment[1])],
  });
  try {
    const controller = new AbortController();
    const pending = [session.client.request('snapshot', {}, { signal: controller.signal }), session.client.request('snapshot')];
    controller.abort();
    const results = await Promise.allSettled(pending);
    await session.close();
    verify_cancel_result(JSON.stringify({ statuses: results.map(result => result.status), ...session.diagnostics() }), attachment[2]);
  } finally { await session.close(); }
  console.log('WINDOW_ATTACH_CANCEL_OK');
}
