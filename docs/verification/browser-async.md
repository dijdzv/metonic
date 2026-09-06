# Browser asynchronous completion probe

Date: 2026-09-06.

## Contract

The MoonBit task scope accepts a completion only for its current pending request.
Replacing, cancelling, or disposing that request prevents subsequent writes from
an old completion. Success, failure, cancellation, and disposal are separate
states. Request identifiers are not reused within a scope.

The browser host owns bounded timers (at most 16). A completion crosses the
JS/WasmGC export boundary using an integer request ID and result/error value.
Only an accepted success changes the rectangle and schedules rendering. Failure
and stale completion update diagnostics without scheduling a GPU frame.

Reset clears callbacks and advances a host epoch before replacing the MoonBit
scope. Stop clears callbacks and disposes the scope. Host-side epoch checks and
MoonBit request checks serve different lifetime boundaries.

## Evidence

Six scope-state tests passed on JS and WasmGC. Real headless Chromium GPU checks
passed for both targets with normal adapter selection and explicit SwiftShader:

- ArrowRight changes the scene revision while a delayed completion is pending.
- Success moves the rendered rectangle to x=40; PNG pixels verify its bounds.
- A newer completion moves it to x=90; a late older result is counted as rejected.
- Cancellation and failure leave the submitted-frame count unchanged.
- Reset produces its own frame, clears pending callbacks, and remains unchanged
  beyond the old timer deadline.
- Stop disposes the scope, clears pending callbacks, rejects new work, and submits
  no further frames beyond the old deadline.

Run `mise run browser:async`; set `METONIC_GPU_BACKEND=swiftshader` for the software
run. Images and target-specific results are under `.work/browser-async/<backend>`.
This uses the same pinned MoonBit and Chromium versions as the browser GPU probe.

## Limits

This proves timer-driven completion and explicit result/error transfer. It does
not implement a general async runtime, network cancellation, worker-thread wakeup,
or a native interactive event loop. The host retains numeric tokens rather than
MoonBit closure objects, so it does not establish arbitrary callback/closure FFI
lifetime support. The diagnostic global belongs to the development harness;
production exclusion still needs separate build evidence. CI integration is pending.
