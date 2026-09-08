# Browser input host

The packaged browser application links `browser_host/app` and the shared
`examples/p0/browser` state once. MoonBit owns listeners for the main textarea
and User ID input, including composition, selection, focus and disposal.
Direct string calls share validation with the numeric control API. The remaining
JavaScript host owns WebGPU calls and frame scheduling; the
[MoonBit HTTP host](browser-http.md) owns bounded fetch and cancellation.
`metonic-input` requests a render after an input update.

`scripts/prepare-browser-deps.mbtx` downloads webapi commit
`ecae5a4b07b011e46de343efe2ac1c450b7ed3a2` and verifies the archive SHA256 before
extracting bindings and the Apache-2.0 license. Existing prepared sources are
compared rather than overwritten. The callback-identity patch preserves the
same Wasm closure wrapper across listener registration/removal using weak keys.
Compiler warnings 20, 35 and 83 are disabled only in the pinned generated
dependency: those concern deprecated syntax and the DOM method named `extend`.
Metonic code retains `--deny-warn`.

Run `mise run browser:headless` for the integrated JS/WasmGC and packaged WasmGC
checks. The release includes the matching `webapi.mjs` runtime and upstream
license. Both loaders supply js-string builtins, imported string constants and
the required console import. Release packaging keeps its explicit asset list
and development-content checks.

The MoonBit `browser_host/app/probe` covers both input fields, synthetic
composition, selection, stop and restart. Synthetic input and pixel checks do
not establish physical Japanese IME behavior, candidate placement or browser
event ordering. Follow the [integrated demo](integrated-demo.md) for real-system
acceptance; the native IME path remains separate.
