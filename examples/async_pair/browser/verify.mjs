import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { chromium } from 'playwright';

const base = process.argv[2] || process.env.METONIC_BROWSER_BASE;
assert.ok(base, 'usage: node examples/async_pair/browser/verify.mjs http://127.0.0.1:PORT/');
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const browser = await chromium.launch({
  headless: true,
  channel: 'chromium',
  args: [
    '--use-webgpu-adapter=swiftshader', '--use-angle=d3d11-warp',
    '--enable-unsafe-webgpu', '--enable-unsafe-swiftshader',
  ],
});

try {
  for (const target of ['js', 'wasm-gc']) {
    const page = await browser.newPage({ viewport: { width: 800, height: 600 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(new URL(`async-pair/?target=${target}`, base).href);
    await page.waitForFunction(() => document.querySelector('#status')?.textContent === `Ready: Async pair (${new URL(location.href).searchParams.get('target')})`, null, { timeout: 30000 });
    assert.equal(await page.locator('#controls button').count(), 5);
    const frame = () => page.locator('#canvas').screenshot().then(digest);
    await page.waitForTimeout(950);
    const ready = await frame();
    await page.locator('[aria-label="Two"]').click();
    const loading = await frame();
    assert.notEqual(loading, ready, `${target}: selection did not redraw`);
    await page.waitForTimeout(950);
    const failed = await frame();
    assert.notEqual(failed, loading, `${target}: expected failure did not redraw`);
    await page.locator('[aria-label="Retry"]').click();
    await page.waitForTimeout(950);
    const retried = await frame();
    assert.notEqual(retried, failed, `${target}: retry did not redraw`);
    await page.locator('[aria-label="Refresh"]').click();
    const refreshing = await frame();
    assert.notEqual(refreshing, retried, `${target}: retained refresh did not redraw`);
    await page.locator('[aria-label="Cancel"]').click();
    const canceled = await frame();
    assert.notEqual(canceled, refreshing, `${target}: cancellation did not redraw`);
    assert.deepEqual(errors, [], `${target}: browser errors`);
    await page.locator('#stop').click();
    assert.equal(await page.locator('#status').textContent(), 'Stopped.');
    await page.close();
  }
  console.log('BROWSER_ASYNC_PAIR_DISPLAY_OK targets=js,wasm-gc');
} finally {
  await browser.close();
}
