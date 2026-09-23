# Metonic Notes browser distribution

Serve this directory over HTTP on localhost or HTTPS. Open `index.html?target=js`
or `index.html?target=wasm-gc` in a browser supporting WebGPU; the latter also
requires WebAssembly GC. Opening `index.html` as a local file is unsupported.
The folder is self-contained: no source checkout, Node installation, package
manager, development server or external asset CDN is required by the browser.

Create a memo with New, select an item in the scrolling list, edit its text, then
Save or Discard. Move up and Move down change the selected memo's order.
Delete requires a second confirmation. Unsaved changes prevent
the app's Stop action; save before closing the browser tab. Storage uses
`localStorage`, under `metonic-notes.snapshot.v1`, for the current browser
profile and origin. Changing the host, port or scheme selects a different store.
Private browsing and clearing site data can remove it. This is not a backup or
cross-device synchronization service. Load/save failures expose retry actions.

`package.json` records each shipped file's byte count and SHA256 and the pinned
framework source. It is an inventory, not an npm package or signature. Keep all
listed files together. No development CLI/MCP adapter or verification runner is
included. Verification tools and packaging dependencies are not shipped.

## Included components and notices

| Component | Notice files |
| --- | --- |
| Metonic shared runtime and compiled framework code | `LICENSE-MIT`, `LICENSE-APACHE` |
| MoonBit core, including its upstream attributions | `LICENSE-moonbit-core`, `NOTICE-moonbit-core` |
| MoonBit async (0.22.1, with the framework's prepared changes) | `LICENSE-async` |
| Chicle layout library | `LICENSE-chicle` |
| Generated WebSys browser bindings | `LICENSE-websys` |
| Noto Sans JP font | `OFL.txt` |

The framework revision in the inventory fixes the compiler/core archive,
WebSys source revision, async preparation and font asset selection. Native wgpu,
AccessKit and native font-shaping libraries are not part of this browser package.
