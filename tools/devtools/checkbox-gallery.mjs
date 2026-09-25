import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { observedPage, reportFailure } from './browser-observation.mjs';

export async function verifyCheckboxGallery(browser, baseUrl, outputDir) {
  const results = [];
  for (const target of ['js', 'wasm-gc']) {
    const page = await observedPage(browser, { viewport: { width: 800, height: 600 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    const suffix = target === 'js' ? 'js' : 'wasm';
    const artifact = path.resolve(`browser_host/_build/${target}/release/build/local/browser_host/checkbox_probe/checkbox_probe.${suffix}`);
    await page.route(`**/notes/notes.${target === 'js' ? 'mjs' : 'wasm'}`, route => route.fulfill({
      path: artifact, contentType: target === 'js' ? 'text/javascript' : 'application/wasm',
    }));
    try {
      await page.goto(`${baseUrl}/notes/?target=${target}`);
      await page.waitForFunction(() => document.querySelector('#status')?.textContent?.startsWith('Ready:'));
      const checkbox = name => page.getByRole('checkbox', { name, exact: true });
      assert.equal(await checkbox('Checked').getAttribute('aria-checked'), 'true');
      assert.equal(await checkbox('Unchecked').getAttribute('aria-checked'), 'false');
      assert.equal(await checkbox('Disabled').isDisabled(), true);
      assert.equal(await checkbox('Error').getAttribute('aria-invalid'), 'true');
      assert.equal(await checkbox('Dynamic').count(), 1);

      const canvas = page.locator('#canvas');
      await checkbox('Unchecked').focus();
      await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      const before = await canvas.screenshot();
      await checkbox('Unchecked').click();
      assert.equal(await checkbox('Unchecked').getAttribute('aria-checked'), 'true');
      assert.notDeepEqual(await canvas.screenshot(), before, 'Pointer toggle did not change GPU pixels');
      await checkbox('Unchecked').press('Space');
      assert.equal(await checkbox('Unchecked').getAttribute('aria-checked'), 'false');
      assert.deepEqual(await canvas.screenshot(), before, 'Space toggle did not restore GPU pixels');

      const previous = await checkbox('Dynamic').elementHandle();
      await page.getByRole('button', { name: 'Toggle dynamic', exact: true }).click();
      assert.equal(await checkbox('Dynamic').count(), 0);
      await page.getByRole('button', { name: 'Toggle dynamic', exact: true }).click();
      assert.equal(await checkbox('Dynamic').getAttribute('aria-checked'), 'false');
      await previous.evaluate(element => element.click());
      assert.equal(await checkbox('Dynamic').getAttribute('aria-checked'), 'false', 'Removed control changed a new instance');
      await previous.dispose();

      await page.locator('#stop').click();
      assert.equal(await page.locator('#controls button').count(), 0);
      assert.deepEqual(errors, []);
      results.push({ target, pointer: true, keyboard: true, accessibility: true, disabled: true, invalid: true, keyedRecreate: true, pixels: true, stop: true });
    } catch (error) { await reportFailure(page); throw error; }
    finally { await page.close(); }
  }
  await fs.writeFile(path.join(outputDir, 'checkbox-gallery-results.json'), JSON.stringify(results, null, 2));
}
