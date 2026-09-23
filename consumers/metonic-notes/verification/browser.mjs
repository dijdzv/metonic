import { chromium } from 'playwright';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import { serve } from './static-server.mjs';

const root = path.resolve(process.argv[2] || 'browser/.metonic-dist');
await mkdir('verification-output', { recursive: true });
const server = await serve(root);
let browser;
try {
  browser = await chromium.launch({ headless: true, channel: 'chromium', args: ['--use-webgpu-adapter=swiftshader', '--use-angle=d3d11-warp', '--enable-unsafe-webgpu', '--enable-unsafe-swiftshader'] });
  for (const target of ['js', 'wasm-gc']) {
    const page = await browser.newPage({ viewport: { width: 800, height: 600 } });
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.goto(`${server.url}?target=${target}`);
    await page.waitForFunction(() => !document.querySelector('#status').textContent.startsWith('Loading'), null, { timeout: 30000 });
    assert.equal(await page.locator('#status').textContent(), `Ready: Memo (${target})`);
    const field = page.locator('[aria-label="Memo"]'), canvas = page.locator('#canvas');
    await page.waitForFunction(() => document.querySelector(':is([aria-label="New memo"],[aria-label="Cancel"])')?.disabled === false);
    await page.locator(':is([aria-label="New memo"],[aria-label="Cancel"])').click();
    await page.waitForFunction(() => document.querySelector('[aria-label="Memo"]')?.disabled === false);
    assert.equal(await field.inputValue(), '');
    const settle = () => page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))));
    await settle();
    const before = await canvas.screenshot();
    await field.fill('独立アプリ\n編集できる');
    await settle();
    assert.equal(await field.inputValue(), '独立アプリ\n編集できる');
    const after = await canvas.screenshot({ path: `verification-output/browser-${target}.png` });
    assert.notDeepEqual(after, before, 'editing did not change rendered pixels');
    // Headless Chromium uses a virtual clipboard, not the user's OS clipboard.
    // Exercise default DOM editing; synthetic ClipboardEvent has no default action.
    await field.fill('A😀日本\n末尾B');
    await field.evaluate(el => el.setSelectionRange(1, el.value.length - 1));
    await field.press('Control+c');
    assert.equal(await field.inputValue(), 'A😀日本\n末尾B');
    await field.press('Control+x');
    assert.equal(await field.inputValue(), 'AB');
    await field.press('Control+v');
    assert.equal(await field.inputValue(), 'A😀日本\n末尾B');
    await field.evaluate(el => el.setSelectionRange(0, el.value.length));
    await field.press('Control+v');
    const clipboardText = '😀日本\n末尾';
    assert.equal(await field.inputValue(), clipboardText);
    await page.locator(':is([aria-label="Save all"],[aria-label="Save"],[aria-label="Retry load"])').click();
    await page.waitForFunction(text => {
      const raw = localStorage.getItem('metonic-notes.snapshot.v1');
      return raw && JSON.parse(raw.slice(raw.indexOf('\n') + 1)).notes[0].text === text;
    }, clipboardText);
    await page.reload();
    await page.waitForFunction(text => document.querySelector('[aria-label="Memo"]')?.value === text, clipboardText);
    assert.equal(await field.inputValue(), clipboardText, 'clipboard edits were not restored from application storage');
    const longText = Array.from({ length: 18 }, (_, i) => `日本語の行 ${i + 1}`).join('\n');
    await field.fill(longText);
    for (const [width, height] of [[336, 540], [496, 580], [776, 700], [1216, 1080]]) {
      await page.setViewportSize({ width, height });
      await settle();
      assert.equal(await field.inputValue(), longText);
      assert.equal(await page.evaluate(() => document.activeElement.getAttribute('aria-label')), 'Memo');
      const placements = await page.evaluate(() => {
        const canvas = document.querySelector('#canvas').getBoundingClientRect();
        const controls = [...document.querySelectorAll('.view button, [aria-label="Memo"]')].map(el => {
          const r = el.getBoundingClientRect();
          return { id: el.id, x: r.left - canvas.left, y: r.top - canvas.top, width: r.width, height: r.height };
        });
        return { width: canvas.width, height: canvas.height, controls };
      });
      for (let i = 0; i < placements.controls.length; i++) {
        const a = placements.controls[i];
        assert.ok(a.x >= 0 && a.y >= 0 && a.x + a.width <= placements.width + 1 && a.y + a.height <= placements.height + 1, `${a.id} outside canvas`);
        for (const b of placements.controls.slice(i + 1)) {
          assert.ok(a.x + a.width <= b.x || b.x + b.width <= a.x || a.y + a.height <= b.y || b.y + b.height <= a.y, `${a.id} overlaps ${b.id}`);
        }
      }
      const inputState = await field.evaluate(el => ({
        scroll: el.scrollTop, scrollHeight: el.scrollHeight, height: el.clientHeight,
        end: el.selectionEnd, length: el.value.length,
      }));
      assert.equal(inputState.end, inputState.length);
      assert.ok(inputState.scroll + inputState.height >= inputState.scrollHeight - 1, 'resize hid the end of the active editor');
      await canvas.screenshot({ path: `verification-output/layout-${target}-${width}.png` });
    }
    await page.setViewportSize({ width: 496, height: 580 });
    await settle();
    await field.evaluate(el => { el.scrollTop = 96; });
    await settle();
    await page.setViewportSize({ width: 336, height: 540 });
    await settle();
    assert.equal(await field.evaluate(el => el.scrollTop), 96, 'resize moved a reader to the end');
    const savedBeforeDiscard = await page.evaluate(() => {
      const raw = localStorage.getItem('metonic-notes.snapshot.v1');
      return JSON.parse(raw.slice(raw.indexOf('\n') + 1)).notes[0].text;
    });
    await field.fill('discard-before-autosave');
    await page.locator(':is([aria-label="Discard all changes"],[aria-label="Discard"])').click();
    await page.waitForFunction(text => document.querySelector('[aria-label="Memo"]')?.value === text, savedBeforeDiscard);
    await field.fill('close draft 日本語');
    await field.dispatchEvent('compositionstart', { data: '' });
    await page.locator('#stop').click();
    assert.equal(await field.isDisabled(), false, 'close froze an active composition');
    assert.equal(await page.locator(':is([aria-label="New memo"],[aria-label="Cancel"])').textContent(), 'New memo');
    assert.equal(await field.inputValue(), 'close draft 日本語');
    await field.dispatchEvent('compositionend', { data: '' });
    await page.locator('#stop').click();
    await page.waitForFunction(() => document.querySelector('[aria-label="Memo"]')?.disabled && document.querySelector(':is([aria-label="New memo"],[aria-label="Cancel"])')?.textContent === 'Cancel');
    await canvas.screenshot({ path: `verification-output/close-dialog-${target}.png` });
    await page.locator(':is([aria-label="New memo"],[aria-label="Cancel"])').click();
    assert.equal(await field.isDisabled(), false);
    assert.equal(await field.inputValue(), 'close draft 日本語');
    await page.locator('#stop').click();
    await page.evaluate(() => {
      window.closeWriteAttempts = 0;
      window.restoreCloseStorage = Storage.prototype.setItem;
      Storage.prototype.setItem = function () { window.closeWriteAttempts++; throw new Error('close-save-denied'); };
    });
    await page.locator(':is([aria-label="Save all"],[aria-label="Save"],[aria-label="Retry load"])').click();
    await page.waitForFunction(() => window.closeWriteAttempts === 1 && document.querySelector(':is([aria-label="Save all"],[aria-label="Save"],[aria-label="Retry load"])')?.disabled === false);
    assert.notEqual(await page.locator('#status').textContent(), 'Stopped.');
    assert.equal(await field.inputValue(), 'close draft 日本語');
    await page.evaluate(() => { Storage.prototype.setItem = window.restoreCloseStorage; });
    await page.locator(':is([aria-label="Save all"],[aria-label="Save"],[aria-label="Retry load"])').click();
    await page.waitForFunction(() => document.querySelector('#status').textContent === 'Stopped.');
    await page.reload();
    await page.waitForFunction(() => document.querySelector('[aria-label="Memo"]')?.value === 'close draft 日本語');
    await field.fill('discard before close');
    await page.locator('#stop').click();
    await page.locator(':is([aria-label="Discard all changes"],[aria-label="Discard"])').click();
    await page.waitForFunction(() => document.querySelector('#status').textContent === 'Stopped.');
    assert.equal(await page.evaluate(() => {
      const raw = localStorage.getItem('metonic-notes.snapshot.v1');
      return JSON.parse(raw.slice(raw.indexOf('\n') + 1)).notes[0].text;
    }), 'close draft 日本語');
    assert.equal(await page.locator('#status').textContent(), 'Stopped.');
    assert.equal(await field.count(), 0);
    assert.deepEqual(errors, []);
    await page.close();
    console.log(`EXTERNAL_NOTES_BROWSER_OK target=${target}`);
  }
} finally {
  await browser?.close();
  await server.close();
}
