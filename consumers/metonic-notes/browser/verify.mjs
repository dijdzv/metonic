import assert from 'node:assert/strict';
import { chromium } from '../node_modules/playwright/index.mjs';
import { serve } from '../verification/static-server.mjs';
import { fileURLToPath } from 'node:url';

const key = 'metonic-notes.snapshot.v1';
const server = await serve(process.argv[2] || fileURLToPath(new URL('./.metonic-dist', import.meta.url)));
let browser;
try {
  browser = await chromium.launch({ headless: true, channel: 'chromium' });
  for (const target of ['js', 'wasm-gc']) {
    const context = await browser.newContext();
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });

    const ready = () => page.waitForFunction(() => document.querySelector(':is([aria-label="New memo"],[aria-label="Cancel"])')?.disabled === false).catch(async error => {
      throw new Error(`${target}: ${await page.locator('#status').textContent()}; ${errors.join('; ')}`, { cause: error });
    });
    const saved = () => page.evaluate(key => localStorage.getItem(key), key);
    const memo = page.locator('[aria-label="Memo"]');
    await page.goto(`${server.url}?target=${target}`);
    await ready();
    assert.equal(await memo.isDisabled(), true);
    assert.equal(await page.locator(':is([aria-label="Delete memo"],[aria-label="Confirm delete"])').isDisabled(), true);
    assert.equal(await page.locator('[aria-label="Memo 1"]').count(), 0);
    for (let i = 1; i <= 5; i++) {
      await page.locator(':is([aria-label="New memo"],[aria-label="Cancel"])').click();
      assert.equal(await page.evaluate(() => document.activeElement.getAttribute('aria-label')), 'Memo');
      await memo.fill(`日本語メモ${i}\n編集を維持`);
    }
    assert.equal(await page.locator('[aria-label="* Memo 5"]').count(), 1);
    assert.equal(await page.locator('[aria-label="Move down"]').isDisabled(), true);
    await page.locator('[aria-label="Memo 1"]').click();
    assert.equal(await page.evaluate(() => document.activeElement.getAttribute('aria-label')), 'Memo');
    assert.equal(await memo.inputValue(), '日本語メモ1\n編集を維持');
    await page.locator('#stop').click();
    assert.match(await page.locator('#status').textContent(), /Save or discard/);
    await page.locator(':is([aria-label="Save all"],[aria-label="Save"],[aria-label="Retry load"])').click();
    await page.waitForFunction(key => {
      const text = localStorage.getItem(key);
      return text && JSON.parse(text.slice(text.indexOf('\n') + 1)).notes.length === 5;
    }, key);
    const collection = await saved();
    await page.reload();
    await ready();
    assert.equal(await memo.inputValue(), '日本語メモ1\n編集を維持');
    await page.locator('[aria-label="Memo 5"]').click();
    assert.equal(await memo.inputValue(), '日本語メモ5\n編集を維持');
    await page.locator(':is([aria-label="Delete memo"],[aria-label="Confirm delete"])').click();
    assert.equal(await page.locator(':is([aria-label="Delete memo"],[aria-label="Confirm delete"])').textContent(), 'Confirm delete');
    assert.equal(await memo.inputValue(), '日本語メモ5\n編集を維持');
    await memo.fill('取消した削除');
    await page.locator(':is([aria-label="Delete memo"],[aria-label="Confirm delete"])').click();
    assert.equal(await memo.inputValue(), '取消した削除', 'editing must cancel the earlier deletion request');
    await page.locator(':is([aria-label="Delete memo"],[aria-label="Confirm delete"])').click();
    assert.equal(await memo.inputValue(), '日本語メモ1\n編集を維持');
    assert.equal(await page.locator(':is([aria-label="Memo 5"],[aria-label="* Memo 5"])').count(), 0);
    await page.locator(':is([aria-label="Discard all changes"],[aria-label="Discard"])').click();
    await page.locator('[aria-label="Memo 5"]').click();
    assert.equal(await memo.inputValue(), '日本語メモ5\n編集を維持');
    await page.evaluate(() => {
      window.originalSetItem = Storage.prototype.setItem;
      window.quotaFailureCalls = 0;
      Storage.prototype.setItem = () => { window.quotaFailureCalls++; throw new DOMException('full', 'QuotaExceededError'); };
    });
    await memo.fill('再試行する編集');
    await page.locator(':is([aria-label="Save all"],[aria-label="Save"],[aria-label="Retry load"])').click();
    await page.waitForFunction(() => window.quotaFailureCalls === 1 && document.querySelector(':is([aria-label="Save all"],[aria-label="Save"],[aria-label="Retry load"])')?.disabled === false);
    assert.equal(await saved(), collection);
    assert.equal(await memo.inputValue(), '再試行する編集');
    await page.evaluate(() => { Storage.prototype.setItem = window.originalSetItem; });
    await page.locator(':is([aria-label="Save all"],[aria-label="Save"],[aria-label="Retry load"])').click();
    await page.waitForFunction(key => localStorage.getItem(key).includes('再試行する編集'), key);
    const search = page.locator('[aria-label="Search memos"]');
    await search.fill('日本語メモ1');
    await page.locator('[aria-label="Memo 1"]').waitFor();
    await page.locator(':is([aria-label="Memo 5"],[aria-label="* Memo 5"])').waitFor({ state: 'hidden' });
    await page.locator('[aria-label="Memo 1"]').click();
    assert.equal(await memo.inputValue(), '日本語メモ1\n編集を維持');
    await search.fill('');
    await page.locator('[aria-label="Memo 5"]').waitFor();
    await page.locator('[aria-label="Memo 5"]').click();
    assert.equal(await memo.inputValue(), '再試行する編集');
    const updated = await saved();
    await page.evaluate(key => localStorage.setItem(key, 'METONIC_NOTES\n{"version":99}'), key);
    await page.reload();
    await page.waitForFunction(() => document.querySelector(':is([aria-label="Save all"],[aria-label="Save"],[aria-label="Retry load"])')?.textContent === 'Retry load');
    assert.equal(await memo.isDisabled(), true);
    assert.equal(await page.locator(':is([aria-label="New memo"],[aria-label="Cancel"])').isDisabled(), true);
    assert.equal(await saved(), 'METONIC_NOTES\n{"version":99}');
    await page.evaluate(({key, updated}) => localStorage.setItem(key, updated), {key, updated});
    await page.locator(':is([aria-label="Save all"],[aria-label="Save"],[aria-label="Retry load"])').click();
    await ready();
    await page.locator('[aria-label="Memo 5"]').click();
    assert.equal(await memo.inputValue(), '再試行する編集');
    await page.evaluate(key => localStorage.setItem(key, '移行する旧メモ'), key);
    await page.reload();
    await ready();
    assert.equal(await memo.inputValue(), '移行する旧メモ');
    await page.locator(':is([aria-label="Save all"],[aria-label="Save"],[aria-label="Retry load"])').click();
    await page.waitForFunction(key => localStorage.getItem(key).startsWith('METONIC_NOTES\n'), key);
    await page.locator(':is([aria-label="Delete memo"],[aria-label="Confirm delete"])').click();
    await page.locator(':is([aria-label="Delete memo"],[aria-label="Confirm delete"])').click();
    assert.equal(await memo.isDisabled(), true);
    await page.locator(':is([aria-label="Save all"],[aria-label="Save"],[aria-label="Retry load"])').click();
    await page.waitForFunction(key => JSON.parse(localStorage.getItem(key).split('\n').slice(1).join('\n')).notes.length === 0, key);
    await page.reload();
    await ready();
    assert.equal(await memo.isDisabled(), true);
    await page.addInitScript(() => {
      const descriptor = Object.getOwnPropertyDescriptor(window, 'localStorage');
      window.restoreStorageAccess = () => Object.defineProperty(window, 'localStorage', descriptor);
      Object.defineProperty(window, 'localStorage', { configurable: true, get() {
        throw new DOMException('denied', 'SecurityError');
      } });
    });
    await page.reload();
    await page.waitForFunction(() => document.querySelector(':is([aria-label="Save all"],[aria-label="Save"],[aria-label="Retry load"])')?.textContent === 'Retry load');
    assert.equal(await memo.isDisabled(), true);
    assert.equal(await page.locator(':is([aria-label="New memo"],[aria-label="Cancel"])').isDisabled(), true);
    await page.evaluate(() => window.restoreStorageAccess());
    await page.locator(':is([aria-label="Save all"],[aria-label="Save"],[aria-label="Retry load"])').click();
    await ready();
    assert.equal(await memo.isDisabled(), true);
    await page.locator('#stop').click();
    assert.equal(await page.locator('#status').textContent(), 'Stopped.');
    await page.waitForTimeout(150);
    assert.equal(await page.locator('#status').textContent(), 'Stopped.');
    assert.deepEqual(errors, []);
    await context.close();
    console.log(`NOTES_COLLECTION_OK target=${target} create select edit retained-list delete discard restart quota retry search select schema retry migration empty stop`);

    const overflowContext = await browser.newContext({ viewport: { width: 480, height: 420 } });
    const overflowPage = await overflowContext.newPage();
    const overflowErrors = [];
    overflowPage.on('pageerror', error => overflowErrors.push(error.message));
    await overflowPage.goto(`${server.url}?target=${target}`);
    await overflowPage.waitForFunction(() => document.querySelector('[aria-label="New memo"]')?.disabled === false);
    for (let i = 1; i <= 12; i++) {
      await overflowPage.locator('[aria-label="New memo"]').click();
      await overflowPage.locator('[aria-label="Memo"]').fill(`record ${i}`);
    }
    const first = overflowPage.locator('[aria-label="Memo 1"]');
    const last = overflowPage.locator('[aria-label="* Memo 12"]');
    assert.equal(await overflowPage.locator('#controls > button').count(), 8);
    assert.equal(await first.count(), 0);
    const lastBox = await last.boundingBox();
    await overflowPage.mouse.move(lastBox.x + lastBox.width / 2, lastBox.y + lastBox.height / 2);
    await overflowPage.mouse.wheel(0, -4096);
    await first.waitFor();
    const editorBox = await overflowPage.locator('[aria-label="Memo"]').boundingBox();
    await overflowPage.mouse.move(editorBox.x + editorBox.width / 2,
      editorBox.y + editorBox.height / 2);
    await overflowPage.mouse.wheel(0, 36);
    await overflowPage.waitForTimeout(100);
    assert.equal(await first.count(), 1);
    const firstId = await first.getAttribute('id');
    const second = overflowPage.locator('[aria-label="Memo 2"]');
    const secondId = await second.getAttribute('id');
    const firstBox = await first.boundingBox();
    await overflowPage.mouse.move(firstBox.x + firstBox.width / 2,
      firstBox.y + firstBox.height / 2);
    await overflowPage.mouse.wheel(0, 36);
    await overflowPage.locator('[aria-label="Memo 3"]').waitFor();
    assert.equal(await first.count(), 0);
    assert.equal(await second.getAttribute('id'), secondId);
    await overflowPage.mouse.wheel(0, -36);
    await first.waitFor();
    const firstIdAfterReturn = await first.getAttribute('id');
    assert.notEqual(firstIdAfterReturn, firstId);
    await first.click();
    await overflowPage.locator('[aria-label="Move down"]').click();
    assert.equal(await overflowPage.locator('[aria-label="* Memo 1"]').getAttribute('id'), firstIdAfterReturn);
    await overflowPage.locator('[aria-label="Save all"]').click();
    await overflowPage.waitForFunction(key => {
      const raw = localStorage.getItem(key);
      if (!raw) return false;
      const notes = JSON.parse(raw.slice(raw.indexOf('\n') + 1)).notes;
      return notes.length === 12 && notes[0].id === 2 && notes[1].id === 1;
    }, key);
    await overflowPage.reload();
    await overflowPage.waitForFunction(() => document.querySelector('[aria-label="New memo"]')?.disabled === false);
    assert.equal(await overflowPage.locator('#controls > button').count(), 8);
    const restoredOrder = await overflowPage.locator('#controls > button').evaluateAll(buttons =>
      buttons.map(button => button.getAttribute('aria-label')).filter(label => /^\*? ?Memo \d+$/.test(label)).map(label => label.replace(/^\* /, '')));
    assert.deepEqual(restoredOrder.slice(0, 2), ['Memo 2', 'Memo 1']);
    assert.deepEqual(overflowErrors, []);
    await overflowContext.close();
    console.log(`NOTES_DYNAMIC_LIST_OK target=${target} overflow wheel stable_identity reorder saved_restore`);
  }
} finally {
  await browser?.close();
  await server.close();
}
