const failures = new WeakMap();

export async function observedPage(browser, options) {
  const page = await browser.newPage(options);
  const errors = [];
  failures.set(page, errors);
  page.on('pageerror', error => {
    errors.push(String(error).slice(0, 512));
    if (errors.length > 8) errors.shift();
  });
  return page;
}

export async function observeFailure(page) {
  if (!page) return { observation: 'no-page', errors: [] };
  const errors = [...(failures.get(page) ?? [])];
  if (page.isClosed()) return { observation: 'closed', errors };
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
    return state ? { observation: 'available', ...state, errors } : { observation: 'timeout', errors };
  } catch {
    return { observation: 'unavailable', errors };
  } finally { clearTimeout(timer); }
}

export async function reportFailure(page) {
  console.error('BROWSER_FAILURE_OBSERVATION ' + JSON.stringify(await observeFailure(page)));
}
