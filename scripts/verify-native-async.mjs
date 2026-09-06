import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const executable = path.join(repo, '_build/native/release/build/examples/p0/native_async/native_async.exe');
const bridge = path.join(repo, '.work/native-cargo/release/metonic_wgpu_probe.dll');
const output = path.join(repo, '.work/native-async');
const scope = 'worker completion through hidden HWND; not network, visible input, IME or general closure FFI';
await mkdir(output, { recursive: true });

function run(mode, fallback) {
  return new Promise((resolve, reject) => {
    const started = Date.now();
    const child = spawn(executable, [], { windowsHide: true, env: { ...process.env, METONIC_GPU_BRIDGE: bridge, METONIC_WINDOW_TEST: '1', METONIC_GPU_FALLBACK: fallback ? '1' : '0' } });
    const stdoutChunks = [], stderrChunks = [];
    let stdoutBytes = 0, stderrBytes = 0, overflow = false, timedOut = false;
    const append = (chunks, bytes, chunk) => {
      const room = Math.max(0, 64 * 1024 - bytes);
      if (room) chunks.push(chunk.subarray(0, room));
      if (bytes + chunk.byteLength > 64 * 1024) overflow = true;
      return bytes + chunk.byteLength;
    };
    child.stdout.on('data', (chunk) => { stdoutBytes = append(stdoutChunks, stdoutBytes, chunk); if (overflow) child.kill(); });
    child.stderr.on('data', (chunk) => { stderrBytes = append(stderrChunks, stderrBytes, chunk); if (overflow) child.kill(); });
    const timer = setTimeout(() => { timedOut = true; child.kill(); }, 20_000);
    child.once('error', (error) => { clearTimeout(timer); reject(error); });
    child.once('close', async (exit, signal) => {
      clearTimeout(timer);
      try {
        const stdout = Buffer.concat(stdoutChunks).toString('utf8');
        const stderr = Buffer.concat(stderrChunks).toString('utf8');
        const shutdownMatches = [...stdout.matchAll(/^NATIVE_ASYNC_SHUTDOWN_MS=(\d+)$/gm)];
        assert.equal(shutdownMatches.length, 1, `${mode}: missing or duplicate shutdown timing`);
        const shutdownMs = Number(shutdownMatches[0][1]);
        const report = { stdout, stderr, exit, signal, timedOut, elapsedMs: Date.now() - started, shutdownMs, mode, scope };
        await writeFile(path.join(output, `${mode}.json`), JSON.stringify(report, null, 2));
        assert.equal(overflow, false, `${mode}: output exceeded 64KiB`);
        assert.equal(timedOut, false, `${mode}: timeout`);
        assert.equal(exit, 0, `${mode}: exit`);
        assert.ok(shutdownMs < 4000, `${mode}: shutdown ${shutdownMs}ms`);
        assert.equal(stdout.includes('FAILED'), false, `${mode}: FAILED marker`);
        assert.ok(stdout.split(/\r?\n/).some((line) => line === 'NATIVE_ASYNC_OK'), `${mode}: missing NATIVE_ASYNC_OK`);
        resolve(report);
      } catch (error) { reject(error); }
    });
  });
}

try {
  if (process.env.METONIC_GPU_FALLBACK === '1') await run('fallback', true);
  else { await run('default', false); await run('fallback', true); }
  console.log('native async probe verified');
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
}
