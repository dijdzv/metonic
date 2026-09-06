import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const executable = path.join(repo, '_build/native/release/build/examples/p0/native_window/native_window.exe');
const bridge = path.join(repo, '.work/native-cargo/release/metonic_wgpu_probe.dll');
const output = path.join(repo, '.work/native-window');
await mkdir(output, { recursive: true });
const scope = 'hidden HWND swapchain and own-window message dispatch; not visible UI, IME, accessibility or desktop automation';

function run(mode, fallback) {
  return new Promise((resolve, reject) => {
    const child = spawn(executable, [], { windowsHide: true, env: { ...process.env, METONIC_GPU_BRIDGE: bridge, METONIC_WINDOW_TEST: '1', METONIC_GPU_FALLBACK: fallback ? '1' : '0' } });
    const stdoutChunks = [];
    const stderrChunks = [];
    let stdoutBytes = 0;
    let stderrBytes = 0;
    let overflow = false;
    const append = (which, chunk) => {
      const chunks = which === 'stdout' ? stdoutChunks : stderrChunks;
      const bytes = which === 'stdout' ? stdoutBytes : stderrBytes;
      const room = Math.max(0, 64 * 1024 - bytes);
      if (room > 0) chunks.push(chunk.subarray(0, room));
      if (which === 'stdout') stdoutBytes += chunk.byteLength; else stderrBytes += chunk.byteLength;
      if (bytes + chunk.byteLength > 64 * 1024) { overflow = true; child.kill(); }
    };
    child.stdout.on('data', (chunk) => append('stdout', chunk));
    child.stderr.on('data', (chunk) => append('stderr', chunk));
    let timedOut = false;
    const timer = setTimeout(() => { timedOut = true; child.kill(); }, 20_000);
    child.once('error', (error) => { clearTimeout(timer); reject(error); });
    child.once('close', async (code, signal) => {
      clearTimeout(timer);
      try {
        const stdout = Buffer.concat(stdoutChunks).toString('utf8');
        const stderr = Buffer.concat(stderrChunks).toString('utf8');
        const report = { exit: code, signal, timedOut, stdout, stderr, mode, scope };
        await writeFile(path.join(output, `${mode}.json`), JSON.stringify(report, null, 2));
        assert.equal(overflow, false, `${mode}: output exceeded 64KiB`);
        assert.equal(timedOut, false, `${mode}: process timed out`);
        assert.equal(code, 0, `${mode}: process exit`);
        assert.equal(stdout.includes('FAILED'), false, `${mode}: FAILED marker`);
        assert.ok(stdout.split(/\r?\n/).some((line) => line === 'WINDOW_PROBE_OK'), `${mode}: missing WINDOW_PROBE_OK`);
        resolve(report);
      } catch (error) { reject(error); }
    });
  });
}

try {
  if (process.env.METONIC_GPU_FALLBACK === '1') await run('fallback', true);
  else { await run('default', false); await run('fallback', true); }
  console.log('native window probe verified');
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
}
