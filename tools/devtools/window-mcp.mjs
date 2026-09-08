import { McpServer } from '@modelcontextprotocol/server';
import { serveStdio } from '@modelcontextprotocol/server/stdio';
import { z } from 'zod/v4';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createMoonBitSession } from './moonbit-session.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const launchArgs = process.argv.slice(2);
if (launchArgs.length && (launchArgs.length !== 2 || launchArgs[0] !== '--session')) {
  throw new Error('usage: window-mcp.mjs [--session session.json]');
}
const session = await createMoonBitSession(launchArgs.length ? {
  protocol: 'window-attach',
  executable: path.join(root, '.tools/moonbit/bin/moonrun.exe'),
  args: [path.join(root, '_build/wasm/release/build/tools/native_cli/native_cli.wasm'), '--session-wire', path.resolve(launchArgs[1])],
} : {
  protocol: 'window',
  executable: path.join(root, '.work/native-host-build/native/debug/build/local/native_host/window_dev/window_dev.exe'),
  args: [],
});
const revision = z.number().int().min(0).max(2147483647).optional();
function factory() {
  const server = new McpServer({ name: 'metonic-window', version: '0.0.0' });
  const definitions = [
    ['snapshot', 'Read the integrated window state.', z.object({}).strict(), true],
    ['capture', 'Capture the integrated UI through its shared offscreen GPU pass.', z.object({}).strict(), true],
    ['insert', 'Insert text into the integrated window editor.', z.object({ text: z.string(), expected_semantic_revision: revision }).strict(), false],
    ['backspace', 'Delete the selection or preceding Unicode scalar.', z.object({ expected_semantic_revision: revision }).strict(), false],
    ['select', 'Select a UTF-16 range in the integrated editor.', z.object({ selection_start: z.number().int().min(0).max(2147483647), selection_end: z.number().int().min(0).max(2147483647), expected_semantic_revision: revision }).strict(), false],
    ['start_update', 'Start or replace the delayed scene update.', z.object({}).strict(), false],
    ['load_user', 'Fetch a user over HTTP and display the result in the integrated window.', z.object({ user_id: z.string().optional() }).strict(), false],
    ['cancel_update', 'Cancel the pending scene update.', z.object({}).strict(), false],
  ];
  for (const [op, description, inputSchema, readOnlyHint] of definitions) {
    server.registerTool(`window_${op}`, { description, inputSchema, annotations: { readOnlyHint } }, async (args, ctx) => {
      try {
        const state = await session.client.request(op, args, { signal: ctx.mcpReq.signal });
        const { image, ...metadata } = state;
        const content = [{ type: 'text', text: JSON.stringify({ session_id: session.client.session, ...metadata }) }];
        if (image) {
          content.push({ type: 'image', data: image.data, mimeType: image.mimeType });
          content.push({ type: 'text', text: JSON.stringify({ width: image.width, height: image.height, frame: image.frame, source: image.source }) });
        }
        return { content };
      } catch (error) {
        return { isError: true, content: [{ type: 'text', text: error instanceof Error ? error.message : String(error) }] };
      }
    });
  }
  return server;
}
let closing;
const handle = serveStdio(factory, { onerror: error => console.error(error) });
function stop() {
  process.stdin.pause();
  closing ??= (async () => {
    try { await handle.close(); } finally { await session.close(); }
  })();
  closing.catch(error => { console.error(error); process.exitCode = 1; });
}
process.once('SIGINT', stop);
process.once('SIGTERM', stop);
process.stdin.once('end', stop);
process.stdin.once('error', stop);
