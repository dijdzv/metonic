# Work-order persistence integration

## Purpose and environment

This verifies the Phase 6 external consumer's explicit Save flow through the
injected text snapshot capability. It is an application workspace with a pinned
Metonic source checkout, not an internal example package. The verification was
run on Windows x64 on 2026-09-26 with the compiler/core pair in
[`toolchain.json`](../../toolchain.json), Node 26.8.1 and headless Chromium via
Playwright 1.63.0. The consumer pin was
`b54eb3cf5586f213267bb06793b8a686e7e422ee`.

## Checks and observed results

From the pinned framework checkout, the normal `application-source.mbtx build`
entry built the browser release and native main release/development entries.
The consumer's browser and native packaging entries also assembled fresh
distribution directories (19 and 26 files respectively).
The common `work_orders` package tests passed 8/8 on JS and native. WasmGC ran
the three synchronous codec tests; the five async model tests are not executed
by its test runner, so the actual WasmGC browser flow is checked separately.

From the Metonic checkout after those builds:

```text
moon run scripts/verify-work-orders-storage.mbtx
moon run tools/verify_work_orders_close --target native
node scripts/verify-work-orders-browser.mjs
```

The native storage check launched the real development executable in a fresh
temporary directory, edited and saved a title through the application control
protocol, exited normally, then launched another process against the same
directory and read back the saved title. The close check sent `WM_CLOSE` to the
owned hidden app window: Keep editing resumed the document; Discard
exited without creating a snapshot; Save from a close request completed and
exited with a snapshot. The checks remove their own temporary files on success.

Headless Chromium served the built browser files over a local HTTP origin.
For both JS and WasmGC, it observed Save then reload restore, an unsaved edit
discarded by reload, malformed stored JSON preserved without overwrite, repair
followed by Retry load, a `SecurityError` from storage access, and a
`QuotaExceededError` from storage write. The error cases use browser-native
exception injection while the successful persistence cases use real
`localStorage` in the page origin. No page errors were observed.

The common model tests additionally verify that a successful older write does
not mark a later edit as saved, a failed write retains the draft for retry, and
missing storage is distinct from malformed data. Native and browser adapter
contract tests reside with the framework packages.

## Limits

These checks exercise a real Windows file-backed store and browser-origin
storage, but do not prove power-loss durability, concurrent-tab coordination,
or physical IME behavior. Browser page unload cannot wait for asynchronous
work; the app does not promise a final save or warning on navigation. The native
close test uses an owned hidden window and an OS close message, not visual
inspection of the displayed controls. The browser storage error injection
verifies response to the named DOM exceptions; it does not establish every
browser permission or quota policy.
