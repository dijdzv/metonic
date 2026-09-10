const failures = new WeakMap();

export async function observedPage(browser, options) {
  const page = await browser.newPage(options);
  const errors = [];
  const requests = [];
  failures.set(page, { errors, requests });
  page.on('requestfailed', request => {
    // Queries and credentials are irrelevant to identifying the failed asset.
    let path = '(invalid URL)';
    try { path = new URL(request.url()).pathname.slice(0, 512); } catch {}
    requests.push({ path, method: request.method(), error: String(request.failure()?.errorText ?? '').slice(0, 512) });
    if (requests.length > 8) requests.shift();
  });
  page.on('pageerror', error => {
    errors.push(String(error).slice(0, 512));
    if (errors.length > 8) errors.shift();
  });
  return page;
}

export async function observeFailure(page) {
  if (!page) return { observation: 'no-page', errors: [] };
  const saved = failures.get(page);
  const errors = [...(saved?.errors ?? [])];
  const requests = [...(saved?.requests ?? [])];
  if (page.isClosed()) return { observation: 'closed', errors, requests };
  let timer;
  try {
    // A stalled renderer must not turn failure reporting into another unbounded wait.
    const state = await Promise.race([
      page.evaluate(() => ({
        status: (document.querySelector('#status')?.textContent ?? '').slice(0, 512),
        readyState: document.readyState,
        target: (document.querySelector('#target')?.textContent ?? '').slice(0, 64),
      })),
      new Promise(resolve => { timer = setTimeout(() => resolve(null), 500); }),
    ]);
    return state ? { observation: 'available', ...state, errors, requests } : { observation: 'timeout', errors, requests };
  } catch {
    return { observation: 'unavailable', errors, requests };
  } finally { clearTimeout(timer); }
}

export async function reportFailure(page) {
  console.error('BROWSER_FAILURE_OBSERVATION ' + JSON.stringify(await observeFailure(page)));
}
