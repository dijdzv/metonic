# Browser asynchronous completion probe

Initial probe: 2026-09-06. MoonBit verifier migration: 2026-09-07.

## Contract

The MoonBit task scope accepts a completion only for its current pending request.
Replacing, cancelling, or disposing that request prevents subsequent writes from
an old completion. Success, failure, cancellation, and disposal are separate
states. Request identifiers are not reused within a scope.

The browser host owns bounded timers (at most 16). A completion crosses the
JS/WasmGC export boundary using an integer request ID and result/error value.
Only an accepted success changes the rectangle. Accepted task-status transitions,
including failure and cancellation, also schedule rendering of the shared status
label. Rejected completions cannot move the rectangle; an unchanged task status
does not itself schedule another frame.

Reset clears callbacks and advances a host epoch before replacing the MoonBit
scope. Stop clears callbacks and disposes the scope. Host-side epoch checks and
MoonBit request checks serve different lifetime boundaries.

## Evidence

Six scope-state tests passed on JS and WasmGC. Real headless Chromium GPU checks
passed for both targets with normal adapter selection and explicit SwiftShader:

- ArrowRight changes the scene revision while a delayed completion is pending.
- Success moves the rendered rectangle to x=40; PNG pixels verify its bounds.
- A newer completion moves it to x=90; a late older result is counted as rejected.
- Cancellation and failure preserve rectangle pixels while presenting their status.
- Reset produces its own frame, clears pending callbacks, and remains unchanged
  beyond the old timer deadline.
- Stop disposes the scope, clears pending callbacks, rejects new work, and submits
  no further frames beyond the old deadline.

Run `mise run browser:async`; set `METONIC_GPU_BACKEND=swiftshader` for the software
run. Images and target-specific results are under `.work/browser-async/<backend>`.
This uses the same pinned MoonBit and Chromium versions as the browser GPU probe.

The verification sequence, snapshot checks, polling conditions and PNG decoding
run in `tools/verify_browser_async`, compiled to JavaScript. Direct Playwright
operations cross small foreign-function adapters. The JavaScript entry point retains
browser lifecycle, page readiness, page-error collection and artifact
writing; this is not yet a complete migration of browser verification tooling.
The MoonBit browser supervisor owns server startup and verifier process lifetime;
`mise run browser:async` is the supported entry point for the combined check.
Polling uses 25-millisecond delays and a three-second condition deadline. That
deadline does not establish a hard bound on every external Playwright call.
The verifier runs in Node as JavaScript while Chromium loads each application
target. Its use of MoonBit async does not establish a browser WasmGC runtime path
for that library.

Five verifier tests cover malformed snapshots, invalid bounds, decoded PNG
acceptance and rejection, invalid numeric fields, and rejection through the
exported Promise. A resolved Promise fails the rejection test. The real browser
sequence remains the positive integration check for both application targets.

## Limits

This proves timer-driven completion and explicit result/error transfer. It does
not implement a general async runtime, network cancellation, worker-thread wakeup,
or a native interactive event loop. The host retains numeric tokens rather than
MoonBit closure objects, so it does not establish arbitrary callback/closure FFI
lifetime support. The diagnostic global belongs to the development harness;
production exclusion is verified separately in the [browser package record](browser-target.md).
The local pre-commit
gate runs this verification; automatic PR/push CI does not duplicate it.
