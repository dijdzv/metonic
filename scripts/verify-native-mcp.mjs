import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import { Client } from '@modelcontextprotocol/client';
import { StdioClientTransport } from '@modelcontextprotocol/client/stdio';
import { verify } from '../_build/js/release/build/tools/verify_native_mcp/verify_native_mcp.js';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const outputRoot = path.join(repoRoot, '.work', 'native-mcp');
const server = path.join(repoRoot, 'tools', 'devtools', 'native-mcp.mjs');

async function runVerification() {
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
    const result = JSON.parse(await verify(client));
    const mode = process.env.METONIC_GPU_FALLBACK === '1' ? 'fallback' : 'default';
    const image = Buffer.from(result.image_base64, 'base64');
    await fs.writeFile(path.join(outputRoot, `${mode}.png`), image);
    const serverVersion = typeof client.getServerVersion === 'function' ? client.getServerVersion() : null;
    await fs.writeFile(path.join(outputRoot, `${mode}.json`), JSON.stringify({ session_id: result.session_id, state: result.state, server_version: serverVersion }, null, 2));
    return { mode, session_id: result.session_id, state: result.state, server_version: serverVersion };
  } finally {
    await client.close().catch(() => {});
    await transport.close().catch(() => {});
  }
}

let timer;
let transportForTimeout;
let clientForTimeout;
const run = runVerification();
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
