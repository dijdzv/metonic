# Browser input host

Browser P0 IME acceptance is complete in
[#6](https://github.com/dijdzv/metonic/issues/6). User-operated checks accepted
conversion, selection replacement/cancellation, subsequent Enter, candidate
placement during scrolling/resizing and composition-confirming Enter without
query submission or changes to the main editor. These observations complement
the controlled tests below; they do not establish every browser/IME combination
or an exact internal event-order trace. Repeat affected checks only after a
relevant change or a newly reported regression.

The packaged browser application links `browser_host/app` and the shared
`examples/p0/browser` state once. MoonBit owns listeners for the main textarea
and User ID input, including composition, selection, focus and disposal.
Direct string calls share validation with the numeric control API. The remaining
JavaScript adapter acquires the GPU adapter/device and coordinates canvas
presentation and frame scheduling. MoonBit `view_dom.mbt` places both input fields
and the request/task buttons from the shared view, including CSS classes and the
request label. It uses the generated WebSys DOM binding; resize invokes the same
placement path for development and packaged hosts. MoonBit `scene_gpu.mbt` and `frame_gpu.mbt`
own scene drawing and frame encoding/submission through generated WebSys; the
[MoonBit text GPU renderer](browser-text-gpu.md) owns text GPU resources and draws. The
[MoonBit HTTP host](browser-http.md) owns bounded fetch and cancellation.
`metonic-input` requests a render after an input update.

The DOM remains authoritative for viewport offsets as well: the input host sends
User ID's horizontal offset and the main textarea's vertical offset through
generated WebSys bindings. Offset changes invalidate the retained GPU text frame;
the shared rasterizer applies the same displacement to text, selection and caret.
Headless checks exercise the packaged application and both development targets
with multiline scrolling, pixel displacement, selection and keyboard navigation.
These checks do not establish actual IME candidate-window placement.

During composition, the DOM text and caret are authoritative for presentation;
they do not commit the shared editor state. The host reconciles on `input` and
on a frame after `compositionupdate`, because the latter can precede the DOM
edit and existing-text composition may not emit another input event. Pending
reconciliation is canceled on composition end and host stop.

Preedit text and its caret are rendered without the committed-selection
background. The validated composition range remains available for cursor
validation; it is not an IME conversion-target range. Textarea/input events do
not expose the conversion-target attributes, so the GPU host does not invent a
target highlight over the whole preedit. Exact conversion-target styling remains
unavailable through this interface. If the DOM differs from the shared preview,
its full text and caret win without guessing a range from equal prefixes or
repeated characters. Pixel checks cover both fields: ordinary selection remains
highlighted, replacement preedit loses that background, cursor movement changes
pixels, and cancellation follows the supplied DOM value. These controlled events
do not establish actual OS IME acceptance.

The input host uses WebSys through `input_js.mbt` and `input_wasm.mbt`.
The shared composition state machine remains in `input.mbt`. Both adapters keep
the registered listener handle for removal, preserve UTF-16 selection endpoints,
and cancel pending frame reconciliation on composition end and stop. Element and
event downcasts are checked. Document/window acquisition remains a host boundary;
it does not duplicate DOM operations or input state management.

`scripts/prepare-websys-input.mbtx` verifies the SHA256 of WebSys revision
`9249b44b6920c10d1c30a58fd122f64588514da1`. It combines the upstream JS sources
with the WasmGC surface generated from `browser_host/input.idl` and
`browser_host/gpu.idl` and `browser_host/http.idl`, selecting files
by target in one local module. The generator uses its own pinned compiler and
Bun 1.3.14 through mise; Metonic checks the resulting package with its compiler.
Unused-import warning 29 is disabled only in that generated package because its
backend-specific imports are unused on the other target. The browser workspace
uses the upstream official-async candidate and minimal WasmGC patch bundled in
the verified WebSys source. Preparation verifies the candidate revision and
patch, without modifying registry packages. This supports generated GPU Promise
types and HTTP request/cleanup coroutines; it does not move input scheduling to
that library. The native workspace
retains its existing async dependency. MoonBit 0.10.12 is required for the
candidate's cancellation intrinsic.

Preparation verifies the archive on every invocation. A content fingerprint of
the preparation script, IDL, toolchain manifest, generated sources/manifests,
runtime and license permits reuse after successful generation and checks.
Changed, missing or additional MoonBit sources invalidate it. Regeneration
replaces the generated source set so removed upstream files cannot linger.

The same WebSys source supplies the renderer, HTTP, font, timer and control-placement
bindings. The browser workspace no longer needs a second WebIDL generator or
runtime. Metonic code and the generated dependency retain `--deny-warn`.

Run `mise run browser:headless` for the integrated JS/WasmGC and packaged WasmGC
checks. The release includes `websys-input.mjs` and the WebSys/async licenses.
Both loaders supply WebSys's namespace, js-string builtins, imported string constants and
the required console import. Release packaging keeps its explicit asset list
and development-content checks.

The MoonBit `browser_host/app/probe` covers both input fields, synthetic
composition, selection, stop and restart. Cancellation cases supply either
restored or empty DOM text at composition end in each field, then verify the
exact shared text, selection and continued input for both fields, including
same-length different text and supplementary characters. The User ID check also
requires shared composition to end. These controlled events check synchronization, not which cancellation
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
callback receives the field identifier. The development adapter records Text's
editor state or User ID's own shared text, UTF-16 selection and composition flag.
Both readers use the running development artifact's application instance; the
separate recorder does not instantiate another editor. DOM values remain available
for both fields.
Values are observed during
event delivery, not a guarantee of the browser's state after its default action.
These records supplement physical observations and do not simulate an actual IME.

While recording, call `sample()` after an input action has finished to read the
current DOM values/selections and available shared state separately from event
history. `after_sequence` identifies the last recorded event at sampling time;
sampling does not append events. It distinguishes empty text from LF without
claiming that an earlier event row reflects a completed default action. It does
not wait for pending frames or IME work.
After `stop()`, sampling returns an empty field list and no retained callback is
invoked; take a sample before stopping when final state is needed.

Stopping the application removes the listeners. The diagnostics JavaScript is a
separate development asset; the production package omits it and its entry points,
and the server does not serve it under `/release/`. The normal headless suite
checks bounded history, stop/restart and composition records using a MoonBit probe.

`prepare-browser-dev.mbtx` generates a development module from the shared host
sources plus `browser_host/development/observe.mbt`. It shares the existing browser
workspace and pinned dependencies. Explicit forwarding wrappers would duplicate
the host's foreign API; the generated module instead keeps one source of editing
and host logic. It is regenerated before building and verification fingerprinting.
The production package takes the original host artifact directly, not the development
Wasm from `browser-dist`. Packaged verification inspects the production Wasm export
table; development input checks provide the positive control for `query_state_json`.
