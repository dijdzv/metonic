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
    const input = page.getByRole('textbox', { name: 'Memo', exact: true });
    const query = page.getByRole('textbox', { name: 'Search memos', exact: true });
    const rows = page.getByRole('button', { name: /^\*? ?Memo \d+$/ });
    await page.getByRole('button', { name: 'New memo', exact: true }).click();
    await input.fill('Alpha 日本語');
    await page.getByRole('button', { name: 'New memo', exact: true }).click();
    await input.fill('Beta latest');
    await query.fill('alpha');
    await page.waitForFunction(() => [...document.querySelectorAll('button')].filter(el => /^\*? ?Memo \d+$/.test(el.getAttribute('aria-label') || '')).length === 1);
    assert.equal(await rows.first().getAttribute('aria-label'), 'Memo 1');
    assert.equal(await input.inputValue(), 'Beta latest');
    await page.waitForFunction(() => localStorage.getItem('metonic-notes.snapshot.v1')?.includes('Beta latest'), null, { timeout: 5000 });
    await query.fill('Beta');
    await query.fill('日本語');
    await page.waitForFunction(() => document.querySelector('[aria-label="Memo 1"]') && !document.querySelector('[aria-label="* Memo 2"]'));
    await query.fill('no match');
    await page.waitForFunction(() => [...document.querySelectorAll('button')].every(el => !/^\*? ?Memo \d+$/.test(el.getAttribute('aria-label') || '')));
    assert.equal(await rows.count(), 0);
    await query.fill('');
    await page.waitForFunction(() => [...document.querySelectorAll('button')].filter(el => /^\*? ?Memo \d+$/.test(el.getAttribute('aria-label') || '')).length === 2);
    assert.equal(await input.inputValue(), 'Beta latest');
    assert.deepEqual(errors, []);
    await page.close();
    console.log(`MEMO_SEARCH_AUTOSAVE_OK ${target}`);
  }
} finally {
  await browser?.close();
  await server.close();
}
