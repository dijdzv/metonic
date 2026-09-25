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

      const list = page.getByRole('listbox', { name: 'Selectable items' });
      const option = name => page.getByRole('option', { name, exact: true });
      assert.equal(await list.count(), 1);
      assert.equal(await page.getByRole('option').count(), 12);
      assert.equal(await option('Item 0').getAttribute('aria-selected'), 'true');
      assert.equal(await option('Item 4').getAttribute('aria-disabled'), 'true');
      await option('Item 1').click();
      assert.equal(await option('Item 1').getAttribute('aria-selected'), 'true');
      await option('Item 1').press('ArrowDown');
      assert.equal(await option('Item 2').evaluate(element => document.activeElement === element), true);
      await option('Item 2').press('Home');
      assert.equal(await option('Item 0').evaluate(element => document.activeElement === element), true);
      await option('Item 0').press('End');
      assert.equal(await option('Item 11').evaluate(element => document.activeElement === element), true);
      const topBefore = await option('Item 11').evaluate(element => element.getBoundingClientRect().top);
      await option('Item 11').hover();
      await page.mouse.wheel(0, -80);
      await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      const topAfter = await option('Item 11').evaluate(element => element.getBoundingClientRect().top);
      assert.notEqual(topAfter, topBefore, 'List wheel did not move row placements');

      await page.locator('#stop').click();
      assert.equal(await page.locator('#controls button').count(), 0);
      assert.deepEqual(errors, []);
      results.push({ target, pointer: true, keyboard: true, accessibility: true, disabled: true, invalid: true, keyedRecreate: true, pixels: true, stop: true });
    } catch (error) { await reportFailure(page); throw error; }
    finally { await page.close(); }
  }
  await fs.writeFile(path.join(outputDir, 'checkbox-gallery-results.json'), JSON.stringify(results, null, 2));
}
