# Browser input host

The packaged browser application links `browser_host/app` and the shared
`examples/p0/browser` state once. MoonBit owns listeners for the main textarea
and User ID input, including composition, selection, focus and disposal.
Direct string calls share validation with the numeric control API. The remaining
JavaScript adapter acquires the GPU adapter/device and coordinates canvas/DOM
presentation and frame scheduling. MoonBit `scene_gpu.mbt` and `frame_gpu.mbt`
own scene drawing and frame encoding/submission through generated webapi; the
[MoonBit text GPU renderer](browser-text-gpu.md) owns text GPU resources and draws. The
[MoonBit HTTP host](browser-http.md) owns bounded fetch and cancellation.
`metonic-input` requests a render after an input update.

During composition, the DOM text and caret are authoritative for presentation;
they do not commit the shared editor state. The host reconciles on `input` and
on a frame after `compositionupdate`, because the latter can precede the DOM
edit and existing-text composition may not emit another input event. Pending
reconciliation is canceled on composition end and host stop.

A matching shared preview retains its validated composition highlight. If the
DOM differs, the host displays its full text and caret without a range highlight.
Textarea/input selection does not reveal the actual composition range, so the
host does not guess it from equal prefixes or repeated characters. This preserves
text while leaving exact highlighting of such existing-text compositions as a
limitation. The release pixel check compares both fields before, during and after
that synthetic sequence; ordinary highlighted composition remains covered too.

The input host uses WebSys through `input_js.mbt` and `input_wasm.mbt`.
The shared composition state machine remains in `input.mbt`. Both adapters keep
the registered listener handle for removal, preserve UTF-16 selection endpoints,
and cancel pending frame reconciliation on composition end and stop. Element and
event downcasts are checked. Document/window acquisition remains a host boundary;
it does not duplicate DOM operations or input state management.

`scripts/prepare-websys-input.mbtx` verifies the SHA256 of WebSys revision
`2ffc99595ca4eeaac316864e9318dc988494c4d3`. It combines the unchanged JS sources
with the WasmGC surface generated from `browser_host/input.idl`, selecting files
by target in one local module. The generator uses its own pinned compiler and
Bun 1.3.14 through mise; Metonic checks the resulting package with its compiler.
Unused-import warning 29 is disabled only in that generated package because its
JS dependency is unused on WasmGC. The JS source imports async 0.21.3; this does
not move Metonic's input scheduling to that library.

Preparation verifies the archive on every invocation. A content fingerprint of
the preparation script, IDL, toolchain manifest, generated sources/manifests,
runtime and license permits reuse after successful generation and checks.
Changed, missing or additional MoonBit sources invalidate it. Regeneration
replaces the generated source set so removed upstream files cannot linger.

Other browser operations still use the working webapi binding.
`scripts/prepare-browser-gpu.mbtx` prepares webapi commit
`ecae5a4b07b011e46de343efe2ac1c450b7ed3a2` and verifies the archive SHA256 before
extracting the generator and Apache-2.0 license. It regenerates bindings using
the fixed Web IDL archive and reviewed generator patch. The callback-identity correction preserves the
same Wasm closure wrapper across listener registration/removal using weak keys.
Compiler warnings 20, 35 and 83 are disabled only in the pinned generated
dependency: those concern deprecated syntax and the DOM method named `extend`.
Metonic code retains `--deny-warn`.

Run `mise run browser:headless` for the integrated JS/WasmGC and packaged WasmGC
checks. The release includes matching `webapi.mjs` and `websys-input.mjs`
runtimes and their upstream licenses. Both loaders preserve webapi's cached
compiler closure hook while supplying WebSys's namespace, js-string builtins, imported string constants and
the required console import. Release packaging keeps its explicit asset list
and development-content checks.

The MoonBit `browser_host/app/probe` covers both input fields, synthetic
composition, selection, stop and restart. Cancellation cases supply either
restored or empty DOM text at composition end in each field, then verify the
shared view length and continued input; the editor also checks exact text and
selection. These controlled events check synchronization, not which cancellation
result an actual IME should produce. The normal browser suite builds
and runs the probe on JS and WasmGC in separate intercepted pages, outside the
packaged release assets. Its frame-lifetime checks queue reconciliation in each
field and advance two animation frames after stop or restart; a live-host control
requires reconciliation to occur. Success is published only after asynchronous
assertions finish. Missing completion, failure text and page exceptions reject
the check. These checks do
not establish physical Japanese IME behavior, candidate placement or browser
event ordering. Follow the [integrated demo](integrated-demo.md) for real-system
acceptance; the native IME path remains separate.

## Development input recording

The development page exposes `window.metonicInputTrace`. Call `start()` before
the reproduction, `stop()` afterward, and `snapshot()` to retrieve JSON-compatible
data. Starting again resets the history. Recording is opt-in and retains the last
256 events plus a total count; it records the test text verbatim in memory.

The MoonBit diagnostics module records both fields' DOM value and selection,
event order, composition data and keyboard/input-event details. Its shared-state
callback currently records the main editor state, including during User ID events;
do not interpret that callback as a User ID snapshot. Values are observed during
event delivery, not a guarantee of the browser's state after its default action.
These records supplement physical observations and do not simulate an actual IME.

Stopping the application removes the listeners. The diagnostics JavaScript is a
separate development asset; the production package omits it and its entry points,
and the server does not serve it under `/release/`. The normal headless suite
checks bounded history, stop/restart and composition records using a MoonBit probe.
