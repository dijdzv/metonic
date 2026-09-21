import assert from 'node:assert/strict';
import path from 'node:path';
import fs from 'node:fs/promises';
import { observedPage, reportFailure } from './browser-observation.mjs';

export async function verifyDynamicControls(browser, baseUrl, outputDir) {
  const results = [];
  for (const target of ['js', 'wasm-gc']) {
    const page = await observedPage(browser, { viewport: { width: 800, height: 600 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    const artifact = path.resolve(`browser_host/_build/${target}/release/build/local/browser_host/application_probe/application_probe.${target === 'js' ? 'js' : 'wasm'}`);
    await page.route(`**/notes/notes.${target === 'js' ? 'mjs' : 'wasm'}`, route => route.fulfill({
      path: artifact, contentType: target === 'js' ? 'text/javascript' : 'application/wasm',
    }));
    await page.addInitScript(() => {
      const instantiate = WebAssembly.instantiateStreaming.bind(WebAssembly);
      WebAssembly.instantiateStreaming = async (...args) => {
        const result = await instantiate(...args);
        if (result.instance.exports.change) globalThis.dynamicProbe = result.instance.exports;
        return result;
      };
    });
    const change = command => page.evaluate(async ({ target, command }) => {
      const probe = target === 'js' ? await import('./notes.mjs') : globalThis.dynamicProbe;
      probe.change(command);
      document.dispatchEvent(new Event('metonic-notes'));
      await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    }, { target, command });
    try {
      await page.goto(`${baseUrl}/notes/?target=${target}`);
      await page.waitForFunction(() => !document.querySelector('#status').textContent.startsWith('Loading'));
      assert.equal(await page.locator('#status').textContent(), `Ready: Notes (${target})`);
      assert.equal(await page.locator('#controls textarea').count(), 0);
      const edits = () => page.evaluate(async target => {
        const probe = target === 'js' ? await import('./notes.mjs') : globalThis.dynamicProbe;
        return [probe.edit_count(), probe.edit_completed(), probe.edit_text()];
      }, target);
      assert.deepEqual(await edits(), [0, 0, '']);
      await page.getByRole('button', { name: 'Add input', exact: true }).click();
      const first = page.getByRole('textbox', { name: 'Input 1', exact: true });
      assert.equal(await first.evaluate(element => document.activeElement === element), true);
      await change(7);
      assert.equal(await first.isDisabled(), true);
      await change(8);
      assert.equal(await first.isDisabled(), false);
      await page.locator('#stop').focus();
      await change(-1);
      assert.equal(await page.locator('#stop').evaluate(element => document.activeElement === element), true);
      await first.fill('abcdef\none\ntwo\nthree\nfour\nfive');
      assert.deepEqual(await edits(), [1, 1, 'abcdef\none\ntwo\nthree\nfour\nfive']);
      const retained = await first.elementHandle();
      await retained.evaluate(element => {
        globalThis.retainedInput = element;
        element.focus();
        element.setSelectionRange(1, 4, 'backward');
        element.scrollTop = 20;
        element.dispatchEvent(new Event('select'));
        element.dispatchEvent(new Event('scroll'));
      });
      const before = await retained.evaluate(element => [element.selectionStart, element.selectionEnd, element.selectionDirection, element.scrollTop]);
      await change(0);
      assert.equal(await page.locator('#controls textarea').count(), 2);
      await change(1);
      assert.deepEqual(await page.locator('#controls textarea').evaluateAll(elements => elements.map(element => element.getAttribute('aria-label'))), ['Input 2', 'Input 1']);
      assert.equal(await retained.evaluate(element => element === globalThis.retainedInput && document.activeElement === element), true);
      assert.deepEqual(await retained.evaluate(element => [element.selectionStart, element.selectionEnd, element.selectionDirection, element.scrollTop]), before);
      await retained.evaluate(element => {
        element.dispatchEvent(new CompositionEvent('compositionstart', { data: '' }));
        element.value = 'あお';
        element.setSelectionRange(2, 2);
        element.dispatchEvent(new CompositionEvent('compositionupdate', { data: 'あお' }));
        element.dispatchEvent(new InputEvent('input', { isComposing: true, data: 'あお' }));
      });
      await change(1);
      assert.equal(await retained.evaluate(element => element.value), 'あお');
      assert.equal((await edits())[0], 1);
      assert.equal(await retained.evaluate(element => document.activeElement === element), true);
      await change(3);
      assert.equal(await retained.evaluate(element => element.isConnected), false);
      const replacement = page.getByRole('textbox', { name: 'Replacement', exact: true });
      assert.equal(await replacement.inputValue(), 'safe');
      await retained.evaluate(element => {
        element.value = 'late';
        element.dispatchEvent(new CompositionEvent('compositionend', { data: 'late' }));
        element.dispatchEvent(new Event('input'));
      });
      assert.equal(await replacement.inputValue(), 'safe');
      await retained.dispose();
      assert.equal((await edits())[0], 1);
      await replacement.fill('あいう');
      assert.deepEqual(await edits(), [2, 2, 'あいう']);
      const compose = async (finish, value) => replacement.evaluate((element, { finish, value }) => {
        if (!finish) {
          element.setSelectionRange(0, 2);
          element.dispatchEvent(new Event('select'));
          element.dispatchEvent(new CompositionEvent('compositionstart', { data: '' }));
          element.value = '青う';
          element.dispatchEvent(new InputEvent('input', { isComposing: true, data: '青' }));
        } else {
          element.value = value;
          element.setSelectionRange(1, 1);
          element.dispatchEvent(new CompositionEvent('compositionend', { data: value }));
          element.dispatchEvent(new InputEvent('input', { isComposing: false, data: value }));
        }
      }, { finish, value });
      await compose(false, '');
      assert.equal((await edits())[0], 2);
      await compose(true, '青う');
      assert.deepEqual(await edits(), [3, 3, '青う']);
      await compose(false, '');
      assert.equal((await edits())[0], 3);
      await compose(true, '');
      assert.deepEqual(await edits(), [4, 4, '']);
      await replacement.evaluate(element => {
        element.dispatchEvent(new Event('select'));
        element.dispatchEvent(new Event('scroll'));
        element.dispatchEvent(new Event('input'));
      });
      assert.equal((await edits())[0], 4);
      await compose(false, '');
      await change(11);
      await compose(true, 'obsolete');
      assert.equal(await replacement.inputValue(), 'programmatic');
      assert.equal((await edits())[0], 4);
      await change(6);
      assert.equal(await page.locator('#controls textarea').count(), 0);
      await page.getByRole('button', { name: 'Add input', exact: true }).click();
      assert.equal(await page.locator('#controls textarea').count(), 1);
      const secondOwner = await page.evaluate(async target => {
        const probe = target === 'js' ? await import('./notes.mjs') : globalThis.dynamicProbe;
        const candidate = probe.create();
        const adapter = await navigator.gpu.requestAdapter();
        const device = await adapter.requestDevice();
        try {
          candidate.install_font(await candidate.load_font());
          const started = candidate.start(device, navigator.gpu.getPreferredCanvasFormat());
          candidate.stop();
          return { started, remaining: document.querySelectorAll('#controls textarea').length, owned: document.querySelector('#controls').hasAttribute('data-metonic-owner') };
        } finally { candidate.stop(); device.destroy(); }
      }, target);
      assert.deepEqual(secondOwner, { started: 0, remaining: 1, owned: true });
      await page.locator('#stop').click();
      assert.equal(await page.locator('#controls textarea, #controls button').count(), 0);
      assert.equal(await page.locator('#controls').getAttribute('data-metonic-owner'), null);
      for (const invalid of [4, 5]) {
        await page.reload();
        await page.waitForFunction(() => document.querySelector('#status').textContent.startsWith('Ready:'));
        await page.getByRole('button', { name: 'Add input', exact: true }).click();
        await change(invalid);
        assert.equal(await page.locator('#status').textContent(), 'MoonBit rasterization rejected input');
        assert.equal(await page.locator('#controls textarea, #controls button').count(), 0);
        assert.equal(await page.locator('#controls').getAttribute('data-metonic-owner'), null);
      }
      await page.reload();
      await page.waitForFunction(() => document.querySelector('#status').textContent.startsWith('Ready:'));
      await change(10);
      await page.getByRole('button', { name: 'Add input', exact: true }).click();
      const single = page.getByRole('textbox', { name: 'Input 1', exact: true });
      await single.fill('あいう');
      assert.deepEqual(await edits(), [1, 1, 'あいう']);
      await single.evaluate(element => {
        element.setSelectionRange(0, 2);
        element.dispatchEvent(new Event('select'));
        element.dispatchEvent(new CompositionEvent('compositionstart', { data: '' }));
        element.value = '青う';
        element.dispatchEvent(new InputEvent('input', { isComposing: true, data: '青' }));
      });
      assert.equal((await edits())[0], 1);
      await single.evaluate(element => {
        element.value = 'う';
        element.dispatchEvent(new CompositionEvent('compositionend', { data: '' }));
        element.dispatchEvent(new Event('input'));
      });
      assert.deepEqual(await edits(), [2, 2, 'う']);
      const stoppedInput = await single.elementHandle();
      await page.locator('#stop').click();
      await stoppedInput.evaluate(element => {
        element.value = 'late';
        element.dispatchEvent(new Event('input'));
      });
      assert.equal((await edits())[0], 2);
      await stoppedInput.dispose();
      await page.reload();
      await page.waitForFunction(() => document.querySelector('#status').textContent.startsWith('Ready:'));
      await change(9);
      const state = index => page.evaluate(async ({ target, index }) => {
        const probe = target === 'js' ? await import('./notes.mjs') : globalThis.dynamicProbe;
        return probe.operation_state(index);
      }, { target, index });
      const waitState = async (index, expected) => {
        await page.waitForFunction(async ({ target, index, expected }) => {
          const probe = target === 'js' ? await import('./notes.mjs') : globalThis.dynamicProbe;
          return probe.operation_state(index) === expected;
        }, { target, index, expected });
      };
      await page.getByRole('button', { name: 'Start slow', exact: true }).click();
      await waitState(0, 1);
      await page.getByRole('button', { name: 'Run other', exact: true }).click();
      await waitState(1, 1);
      assert.equal(await state(0), 1);
      assert.equal(await state(3), 0);
      await page.getByRole('button', { name: 'Fail work', exact: true }).click();
      await waitState(2, 1);
      assert.equal(await state(0), 1);
      await page.getByRole('button', { name: 'Cancel slow', exact: true }).click();
      await waitState(0, 3);
      await waitState(3, 1);
      await page.getByRole('button', { name: 'Run other', exact: true }).click();
      await waitState(1, 2);
      await page.getByRole('button', { name: 'Start slow', exact: true }).click();
      await waitState(0, 1);
      await page.locator('#stop').click();
      await waitState(4, 1);
      assert.equal(await state(3), 2);
      assert.deepEqual(errors, []);
      results.push({ target, add: true, reorder: true, retainedSelectionScrollComposition: true, replaceGeneration: true, lateEvents: true, removeLast: true, stop: true, exclusiveRoot: true, duplicateAndKindRejection: true });
    } catch (error) { await reportFailure(page); throw error; }
    finally { await page.close(); }
  }
  await fs.writeFile(path.join(outputDir, 'dynamic-controls-results.json'), JSON.stringify(results, null, 2));
}
