const failures = new WeakMap();

function requestTiming(request) {
  try {
    const timing = request.timing();
    // Missing phases (-1) also occur with reused connections; they are not a diagnosis.
    return Object.fromEntries([
      'domainLookupStart', 'domainLookupEnd', 'connectStart', 'connectEnd',
      'secureConnectionStart', 'requestStart', 'responseStart', 'responseEnd',
    ].map(key => [key, Number.isFinite(timing[key]) ? timing[key] : null]));
  } catch { return null; }
}

export async function observedPage(browser, options) {
  const page = await browser.newPage(options);
  const errors = [];
  const requests = [];
  const pending = new Map();
  const saved = { errors, requests, pending, pendingCount: 0 };
  failures.set(page, saved);
  page.on('request', request => {
    saved.pendingCount += 1;
    // Keep the oldest outstanding requests: a busy page must not evict its stall.
    if (pending.size < 8) {
      let path = '(invalid URL)';
      try { path = new URL(request.url()).pathname.slice(0, 512); } catch {}
      pending.set(request, { path, method: request.method(), started: performance.now() });
    }
  });
  const finished = request => {
    saved.pendingCount = Math.max(0, saved.pendingCount - 1);
    pending.delete(request);
  };
  page.on('requestfinished', finished);
  page.on('requestfailed', finished);
  page.on('requestfailed', request => {
    // Queries and credentials are irrelevant to identifying the failed asset.
    let path = '(invalid URL)';
    try { path = new URL(request.url()).pathname.slice(0, 512); } catch {}
    requests.push({ path, method: request.method(), error: String(request.failure()?.errorText ?? '').slice(0, 512), timing: requestTiming(request) });
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
  const pending = [...(saved?.pending.values() ?? [])].map(({ path, method, started }) => ({
    path, method, elapsedMs: Math.max(0, Math.floor(performance.now() - started)),
  }));
  const network = { requests, pending, pendingCount: saved?.pendingCount ?? 0 };
  if (page.isClosed()) return { observation: 'closed', errors, ...network };
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
    return state ? { observation: 'available', ...state, errors, ...network } : { observation: 'timeout', errors, ...network };
  } catch {
    return { observation: 'unavailable', errors, ...network };
  } finally { clearTimeout(timer); }
}

export async function reportFailure(page) {
  console.error('BROWSER_FAILURE_OBSERVATION ' + JSON.stringify(await observeFailure(page)));
}
