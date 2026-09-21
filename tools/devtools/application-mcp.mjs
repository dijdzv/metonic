import { McpServer } from '@modelcontextprotocol/server';
import { serveStdio } from '@modelcontextprotocol/server/stdio';
import { z } from 'zod/v4';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createMoonBitSession } from './moonbit-session.mjs';
import { window_mcp_result } from '../../_build/js/release/build/tools/session_wire/session_wire.js';

const args = process.argv.slice(2);
if (args.length !== 2 || args[0] !== '--session') {
  throw new Error('usage: application-mcp.mjs --session session.json');
}
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const session = await createMoonBitSession({
  protocol: 'window-attach',
  executable: path.join(root, '.tools/moonbit/bin/moonrun.exe'),
  args: [path.join(root, '_build/wasm/release/build/tools/native_cli/native_cli.wasm'), '--session-wire', path.resolve(args[1])],
});
try {
  const capabilities = await session.client.request('capabilities', {});
  if (capabilities.application_protocol !== 1) {
    throw new Error('Session does not support application control');
  }
} catch (error) {
  await session.close();
  throw error;
}
const integer = z.number().int().min(0).max(2147483647);
const target = z.object({ session: integer, window: integer, id: integer, generation: integer }).strict();
const mutation = { target, expected_semantic_revision: integer };
function factory() {
  const server = new McpServer({ name: 'metonic-application', version: '0.0.0' });
  const definitions = [
    ['snapshot', 'Read application controls and their target identities and revision.', z.object({}).strict(), true],
    ['capture', 'Read an offscreen render of the application; this does not certify physical display or IME input.', z.object({}).strict(), true],
    ['insert', 'Replace the target input selection with text using the observed revision.', z.object({ ...mutation, text: z.string() }).strict(), false],
    ['select', 'Select a UTF-16 range in the target input.', z.object({ ...mutation, selection_start: integer, selection_end: integer }).strict(), false],
    ['backspace', 'Delete the target input selection or preceding character.', z.object(mutation).strict(), false],
    ['activate', 'Activate an enabled application button.', z.object(mutation).strict(), false],
  ];
  for (const [op, description, inputSchema, readOnlyHint] of definitions) {
    server.registerTool(`application_${op}`, { description, inputSchema, annotations: { readOnlyHint } }, async (values, ctx) => {
      try {
        const state = await session.client.request(op, values, { signal: ctx.mcpReq.signal });
        if (state.application_protocol !== 1) throw new Error('Session does not support application control');
        const result = JSON.parse(window_mcp_result(session.client.session, JSON.stringify(state)));
        result.isError = state.error !== '';
        return result;
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
