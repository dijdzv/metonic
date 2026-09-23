import assert from 'node:assert/strict';
import path from 'node:path';
import { chromium } from 'playwright';
import { serve } from './static-server.mjs';

const server = await serve(path.resolve(process.argv[2] ?? 'browser/.metonic-dist'));
let browser;
try {
  browser = await chromium.launch({ headless: true, channel: 'chromium', args: ['--use-webgpu-adapter=swiftshader', '--use-angle=d3d11-warp', '--enable-unsafe-webgpu', '--enable-unsafe-swiftshader'] });
  for (const target of ['js', 'wasm-gc']) {
    const page = await browser.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(`${server.url}?target=${target}`);
    await page.getByRole('button', { name: 'New memo', exact: true }).click();
    const input = page.getByRole('textbox', { name: 'Memo', exact: true });
    await input.fill('autosave-proof-old');
    await input.fill('autosave-proof-latest 日本語');
    await page.waitForFunction(() => localStorage.getItem('metonic-notes.snapshot.v1')?.includes('autosave-proof-latest'), null, { timeout: 5000 });
    await page.reload();
    await input.waitFor();
    await page.waitForFunction(() => document.querySelector('[aria-label="Memo"]')?.value === 'autosave-proof-latest 日本語');
    assert.equal(await input.inputValue(), 'autosave-proof-latest 日本語');
    assert.deepEqual(errors, []);
    await page.close();
    console.log(`MEMO_AUTOSAVE_RESTORED ${target}`);
  }
} finally {
  await browser?.close();
  await server.close();
}
