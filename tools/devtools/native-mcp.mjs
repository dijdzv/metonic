import { McpServer } from '@modelcontextprotocol/server';
import { serveStdio } from '@modelcontextprotocol/server/stdio';
import { z } from 'zod/v4';
import { createMoonBitSession } from './moonbit-session.mjs';
import { native_mcp_result, native_mcp_failure } from '../../_build/js/release/build/tools/session_wire/session_wire.js';

const session = await createMoonBitSession();
const sessionId = session.client.session;
let handle;
let closePromise;

function result(response, image) {
  return JSON.parse(native_mcp_result(sessionId, JSON.stringify(response), image === undefined ? '' : JSON.stringify(image)));
}

function failure(error) {
  const message = error instanceof Error ? error.message : String(error);
  return JSON.parse(native_mcp_failure(sessionId, message));
}

function nativeResponse(value) {
  return value?.response ?? value;
}

function revisionSchema() {
  return z.number().int().min(0).max(2147483647).optional();
}

const coordinate = z.number().int().min(-2147483648).max(2147483647);

function factory() {
  const server = new McpServer({ name: 'metonic-native-probe', version: '0.0.0' });
  server.registerTool('native_snapshot', {
    description: 'Read the native probe state, revision, and completed frame number.',
    inputSchema: z.object({}).strict(),
    annotations: { readOnlyHint: true },
  }, async (_args, ctx) => {
    try { return result(nativeResponse(await session.client.request('snapshot', {}, { signal: ctx.mcpReq.signal }))); } catch (error) { return failure(error); }
  });
  server.registerTool('native_move', {
    description: 'Move the probe position with stale revision protection and coordinate clamping.',
    inputSchema: z.object({ x: coordinate, y: coordinate, expected_revision: revisionSchema() }).strict(),
    annotations: { readOnlyHint: false },
  }, async ({ x, y, expected_revision }, ctx) => {
    try { return result(nativeResponse(await session.client.request('move', { x, y, expected_revision }, { signal: ctx.mcpReq.signal }))); } catch (error) { return failure(error); }
  });
  server.registerTool('native_resize', {
    description: 'Resize the native viewport with dimensions bounded to 1..2048 and stale revision protection.',
    inputSchema: z.object({ width: z.number().int().min(1).max(2048), height: z.number().int().min(1).max(2048), expected_revision: revisionSchema() }).strict(),
    annotations: { readOnlyHint: false },
  }, async ({ width, height, expected_revision }, ctx) => {
    try { return result(nativeResponse(await session.client.request('resize', { width, height, expected_revision }, { signal: ctx.mcpReq.signal }))); } catch (error) { return failure(error); }
  });
  server.registerTool('native_activate', {
    description: 'Toggle the native probe active state with stale revision protection.',
    inputSchema: z.object({ expected_revision: revisionSchema() }).strict(),
    annotations: { readOnlyHint: false },
  }, async ({ expected_revision }, ctx) => {
    try { return result(nativeResponse(await session.client.request('activate', { expected_revision }, { signal: ctx.mcpReq.signal }))); } catch (error) { return failure(error); }
  });
  server.registerTool('native_capture', {
    description: 'Capture the completed native frame and return it as a PNG image.',
    inputSchema: z.object({ expected_revision: revisionSchema() }).strict(),
    annotations: { readOnlyHint: false },
  }, async ({ expected_revision }, ctx) => {
    try {
      const captured = await session.client.capture({ expected_revision, signal: ctx.mcpReq.signal });
      const response = captured.response ?? captured;
      const image = captured.image;
      return result(response, image);
    } catch (error) { return failure(error); }
  });
  return server;
}

async function close() {
  if (closePromise) return closePromise;
  closePromise = (async () => {
    if (handle) {
      try { await handle.close(); } catch (error) { console.error(error); }
    }
    try { await session.close(); } catch (error) { console.error(error); }
  })();
  return closePromise;
}

function stop() { process.stdin.pause(); void close(); }
process.once('SIGINT', stop);
process.once('SIGTERM', stop);
process.stdin.once('end', stop);
process.stdin.once('error', stop);

handle = serveStdio(factory, { onerror: (error) => console.error(error) });
