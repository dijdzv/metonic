import assert from 'node:assert/strict';
import { chromium } from 'playwright';
import { Client } from '@modelcontextprotocol/client';
import { StdioClientTransport } from '@modelcontextprotocol/client/stdio';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, readFile, rm, mkdir } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { serve } from './static-server.mjs';

const execute = promisify(execFile);
const playwright = path.resolve('node_modules/playwright/cli.js');
const profile = await mkdtemp(path.join(os.tmpdir(), 'memo-browser-control-'));
const output = path.resolve('verification-output/browser-control');
await mkdir(output, { recursive: true });
const server = await serve(path.resolve('browser/.metonic-dist'));
let context;
try {
  context = await chromium.launchPersistentContext(profile, {
    headless: true, channel: 'chromium', viewport: { width: 800, height: 600 },
    args: ['--remote-debugging-port=0', '--remote-debugging-address=127.0.0.1',
      '--use-webgpu-adapter=swiftshader', '--use-angle=d3d11-warp',
      '--enable-unsafe-webgpu', '--enable-unsafe-swiftshader'],
  });
  const port = (await readFile(path.join(profile, 'DevToolsActivePort'), 'utf8')).split('\n')[0];
  assert.match(port, /^\d+$/);
  const endpoint = `http://127.0.0.1:${port}`;
  const page = context.pages()[0];
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  for (const target of ['js', 'wasm-gc']) {
    await page.goto(`${server.url}?target=${target}`);
    await page.waitForFunction(() => document.querySelector(':is([aria-label="New memo"],[aria-label="Cancel"])')?.disabled === false);
    const expected = `MCP ${target}\n独立したブラウザ接続`;
    for (let connection = 0; connection < 2; connection++) {
      const client = new Client({ name: 'memo-browser-verifier', version: '0.0.0' });
      const transport = new StdioClientTransport({ command: process.execPath,
        args: [playwright, 'mcp', '--cdp-endpoint', endpoint, '--output-dir', output],
        stderr: 'pipe',
      });
      const call = async (name, args = {}) => {
        const result = await client.callTool({ name, arguments: args });
        assert.ok(!result.isError, JSON.stringify(result));
        return result;
      };
      try {
        await client.connect(transport);
        const tabs = await call('browser_tabs', { action: 'list' });
        assert.ok(JSON.stringify(tabs).includes(`${server.url}?target=${target}`));
        const snapshot = await call('browser_snapshot');
        assert.ok(JSON.stringify(snapshot).includes('New memo'));
        if (connection === 0) {
          await call('browser_click', { target: ':is([aria-label="New memo"],[aria-label="Cancel"])' });
          await call('browser_type', { target: '[aria-label="Memo"]', text: expected });
          await call('browser_click', { target: ':is([aria-label="Save all"],[aria-label="Save"],[aria-label="Retry load"])' });
          await page.waitForFunction(text => {
            const saved = localStorage.getItem('metonic-notes.snapshot.v1');
            return saved && saved.includes(JSON.stringify(text).slice(1, -1));
          }, expected);
        }
        assert.equal(await page.locator('[aria-label="Memo"]').inputValue(), expected);
        const capture = await call('browser_take_screenshot', { target: '#canvas', scale: 'css', type: 'png' });
        assert.ok(capture.content.some(item => item.type === 'image' && item.mimeType === 'image/png'));
      } finally { await client.close(); }
      assert.equal(page.isClosed(), false, 'MCP disconnect closed the app');
      assert.equal(await page.locator('[aria-label="Memo"]').inputValue(), expected);
    }
    const session = `memo-${process.pid}-${target}`;
    const cli = async (...args) => {
      const result = await execute(process.execPath, [playwright, 'cli', `-s=${session}`, ...args],
        { windowsHide: true, timeout: 30000, maxBuffer: 1024 * 1024 });
      assert.ok(!result.stdout.includes('### Error'), result.stdout);
      return result.stdout;
    };
    try {
      await cli('attach', `--cdp=${endpoint}`);
      assert.ok((await cli('tab-list')).includes(`${server.url}?target=${target}`));
      await cli('snapshot');
      await cli('fill', '[aria-label="Memo"]', `${expected}\nCLIの編集`);
      await cli('click', ':is([aria-label="Save all"],[aria-label="Save"],[aria-label="Retry load"])');
      assert.equal(await page.locator('[aria-label="Memo"]').inputValue(), `${expected}\nCLIの編集`);
      await page.waitForFunction(text => {
        const saved = localStorage.getItem('metonic-notes.snapshot.v1');
        return saved && saved.includes(JSON.stringify(text).slice(1, -1));
      }, `${expected}\nCLIの編集`);
    } finally { await cli('detach'); }
    assert.equal(page.isClosed(), false, 'CLI detach closed the app');
    await page.reload();
    await page.waitForFunction(() => document.querySelector('[aria-label="Memo"]')?.disabled === false);
    assert.equal(await page.locator('[aria-label="Memo"]').inputValue(), `${expected}\nCLIの編集`);
    assert.deepEqual(errors, []);
    console.log(`BROWSER_CONTROL_OK target=${target} mcp_edit_save_capture_reconnect cli_edit_save_detach reload`);
    await page.evaluate(() => localStorage.removeItem('metonic-notes.snapshot.v1'));
  }
} finally {
  await context?.close();
  await server.close();
  // The browser owns profile contents; remove only this test's uniquely created directory.
  await rm(profile, { recursive: true, force: true });
}
