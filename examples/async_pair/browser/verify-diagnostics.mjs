import assert from 'node:assert/strict';
import { chromium } from 'playwright';

const base = process.env.METONIC_BROWSER_BASE;
assert.ok(base, 'supervised browser endpoint required');
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
    const page = await browser.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(new URL(`async-diagnostics/?target=${target}`, base).href);
    await page.waitForFunction(() => document.querySelector('#status')?.textContent ===
      `Ready: Async diagnostics (${new URL(location.href).searchParams.get('target')})`,
      null, { timeout: 30000 });
    await page.waitForFunction(() => window.metonicAsyncDiagnostics?.().sources
      ?.every(source => source.phase === 'ready'), null, { timeout: 30000 });
    const first = await page.evaluate(() => window.metonicAsyncDiagnostics());
    assert.equal(first.owners.length, 1);
    assert.equal(first.sources.length, 2);
    assert.equal(first.derived.length, 1);
    assert.equal(first.derived[0].phase, 'ready');
    assert.ok(first.sources.every(source => source.operation_id > 0 &&
      source.owner_id === first.owners[0].id));
    assert.equal(first.derived[0].owner_id, first.owners[0].id);
    assert.ok(first.events.some(event => event.kind === 'request_admitted'));
    assert.ok(first.events.some(event => event.kind === 'ready'));
    assert.ok(!JSON.stringify(first).includes('Detail one'));
    await page.locator('[aria-label="Two"]').click();
    await page.waitForFunction(() => window.metonicAsyncDiagnostics?.().events
      ?.some(event => event.kind === 'expected_failure'), null, { timeout: 30000 });
    const failed = await page.evaluate(() => window.metonicAsyncDiagnostics());
    assert.ok(!JSON.stringify(failed).includes('related data unavailable'));
    await page.locator('[aria-label="Retry"]').click();
    await page.waitForFunction(() => window.metonicAsyncDiagnostics?.().sources
      ?.every(source => source.phase === 'ready'), null, { timeout: 30000 });
    await page.locator('[aria-label="Refresh"]').click();
    const joinedBefore = await page.evaluate(() => window.metonicAsyncDiagnostics().events
      .filter(event => event.kind === 'cleanup_joined').length);
    await page.locator('[aria-label="Cancel"]').click();
    await page.waitForFunction(previous => window.metonicAsyncDiagnostics?.().events
      ?.filter(event => event.kind === 'cleanup_joined').length > previous,
      joinedBefore, { timeout: 30000 });
    const canceled = await page.evaluate(() => window.metonicAsyncDiagnostics());
    assert.ok(canceled.events.some(event => event.kind === 'cancel_requested'));
    assert.deepEqual(errors, [], `${target}: browser errors`);
    await page.locator('#stop').click();
    await page.close();
  }
  console.log('BROWSER_ASYNC_DIAGNOSTICS_OK targets=js,wasm-gc');
} finally {
  await browser.close();
}
