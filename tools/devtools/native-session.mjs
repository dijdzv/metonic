import { fileURLToPath } from 'node:url';
import path from 'node:path';
import fs from 'node:fs/promises';
import { NativeClient } from './native-client.mjs';

export async function createNativeSession() {
  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
  const workspace = path.join(repoRoot, '.work', 'devtools');
  await fs.mkdir(workspace, { recursive: true });
  const directory = await fs.mkdtemp(path.join(workspace, 'session-'));
  const client = new NativeClient({
    executable: path.join(repoRoot, '_build', 'native', 'release', 'build', 'examples', 'p0', 'native_headless', 'native_headless.exe'),
    bridge: path.join(repoRoot, '.work', 'native-cargo', 'release', 'metonic_wgpu_probe.dll'),
    capturePath: path.join(directory, 'capture.rgba'),
  });
  let closePromise;
  return {
    client,
    directory,
    async close() {
      if (!closePromise) {
        closePromise = (async () => {
          try { await client.close(); } finally { await fs.rm(directory, { recursive: true, force: true }); }
        })();
      }
      await closePromise;
    },
  };
}

export async function encodeCapture({ response, rgba }) {
  const { PNG } = await import('pngjs');
  const width = Number(response?.state?.[6]);
  const height = Number(response?.state?.[7]);
  if (!Number.isInteger(width) || !Number.isInteger(height) || width < 1 || height < 1 || width > 2048 || height > 2048) {
    throw new Error('capture response has invalid dimensions');
  }
  const expected = width * height * 4;
  if (!rgba || rgba.length !== expected) throw new Error('capture buffer has an invalid size');
  const png = new PNG({ width, height });
  Buffer.from(rgba.buffer, rgba.byteOffset, expected).copy(png.data);
  return PNG.sync.write(png);
}
