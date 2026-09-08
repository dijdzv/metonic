import { Client } from '@modelcontextprotocol/client';
import { StdioClientTransport } from '@modelcontextprotocol/client/stdio';
import { verify, verify_attachment } from '../_build/js/release/build/tools/verify_window_mcp/verify_window_mcp.js';
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
} finally {
  clearTimeout(timer);
  await client.close();
}
