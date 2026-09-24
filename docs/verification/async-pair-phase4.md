# Paired asynchronous application verification

The [paired application](../../examples/async_pair/application/application.mbt)
uses only `core/application`, `core/reactive`, `core/reactive_task`,
`core/application_task`, `core/semantics`, and the public clock capability.
One selection action admits independent detail and related-data operations as
one group. The host owns their execution and cleanup. A Memo derives the view;
it never starts work. Item `two` deliberately fails its first related-data
request, then succeeds on Retry. The data is deterministic demonstration data,
not a network or storage service.

Run the model and native window checks with `mise run async-pair:model` and
`mise run async-pair:native-verify`. The native check opens a hidden owned
window, observes real rendered GPU frames through the development-only host
capture, activates semantic buttons, then closes the window. It checks the
visible model text and different rendered pixels at ready, loading, failed and
retried states. It also checks retained refresh and cancellation. A separate
release-style owned-window start/close check was run with
`METONIC_RELEASE_EXECUTABLE` pointing to the `async-pair` executable and
`METONIC_RELEASE_TITLE=Async pair`; both normal close and system-key close
passed. The production entry does not include the development controller.

Run `mise run browser:build`, then `mise run browser:serve` in one terminal and
`mise run async-pair:browser-verify` in another. The browser check runs both
MoonBit JS and WasmGC outputs in headless Chromium with SwiftShader. It checks
five semantic buttons, no page errors, canvas changes across selection,
failure, retry, retained refresh and cancellation, and the Stop path. These
browser outputs share the WebGPU canvas renderer; neither is a DOM renderer.
DOM supplies the accessible controls and input boundary. WasmGC remains the
primary browser release target; JS is a comparison target.

The application tests assert exact visible text and interleaved completions.
They also reject an old result after a key switch and a pending result after
Scope disposal. The lower-level `core/reactive_task` tests cover the retained
pair's cycle identity, stale success/failure/progress and rejected updates;
the grouped Driver tests cover all-or-none admission. Existing Notes save tests
remain the control that a committed storage fact is not rolled back by a stale
UI request.

All checks above passed on Windows 11 Pro 10.0.26200, Intel i5-13400, Moon
`0.1.20260904` and Node 26.8.1. The browser check used headless Chromium 153
and SwiftShader. No physical IME, screen-reader behavior or clean-machine
installation is inferred from these checks.

The fixed synchronous Graph benchmark from the
[pre-change baseline](reactive-phase4-baseline.md) was repeated after the
implementation. For three 100,000-update runs, Native measured 39/37/41 ms
(before: 36/34/34), JS 72/64/60 ms (before: 68/58/53), and WasmGC 14/15/11 ms
(before: 11/12/11); all expected checksums matched. These short runs use an
integer-millisecond clock and do not establish a material performance change.
The independent Notes 1,000-memo operation runs passed on browser JS/WasmGC and
native (one warmup and three measured runs each). The native release-resource
runs also passed one warmup and three measured runs. Detailed measurements are
retained locally in the ignored `.work/scale/` directory.
