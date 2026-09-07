import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';
import { verify } from '../_build/js/release/build/tools/verify_browser_async/verify_browser_async.js';

if (process.env.METONIC_BROWSER_SUPERVISED !== '1') throw new Error('Run mise run browser:async/headless');

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const out = path.join(repo, '.work/browser-async', process.env.METONIC_GPU_BACKEND ?? 'default');
await mkdir(out, { recursive: true });
let browser;
try {
  const backend = process.env.METONIC_GPU_BACKEND ?? 'default';
  const launchOptions = { headless: true, channel: 'chromium' };
  if (backend === 'swiftshader') launchOptions.args = ['--use-angle=d3d11-warp', '--use-webgpu-adapter=swiftshader', '--enable-unsafe-webgpu', '--enable-unsafe-swiftshader'];
  browser = await chromium.launch(launchOptions);
  const results = [];
  for (const target of ['js', 'wasm-gc']) {
    const page = await browser.newPage();
    const errors = [];
    page.on('pageerror', (error) => errors.push(String(error)));
    await page.goto(`http://127.0.0.1:4173/?target=${target}`, { waitUntil: 'load' });
    try {
      await page.waitForFunction(() => document.querySelector('#status')?.textContent?.includes('Ready:'), null, { polling: 25, timeout: 10_000 });
    } catch (error) {
      const status = await page.locator('#status').textContent().catch(() => '<missing>');
      throw new Error(`target ${target} was not ready: status=${status}; pageerrors=${errors.join(' | ')}`, { cause: error });
    }
  const result = JSON.parse(await verify(page, target, out));
  if (errors.length !== 0) throw new Error(`target ${target} pageerrors: ${errors.join(' | ')}`);
  results.push({ ...result, errors });
  await page.close();
  }
  await writeFile(path.join(out, 'results.json'), JSON.stringify({ backend, results }, null, 2));
} catch (error) {
  throw error;
} finally {
  await browser?.close();
}
