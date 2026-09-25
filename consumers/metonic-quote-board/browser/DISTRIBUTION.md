# Metonic Quote Board browser distribution

Serve this directory over HTTP on localhost or HTTPS. Open
`index.html?target=js` or `index.html?target=wasm-gc` in a browser supporting
WebGPU; WasmGC also requires WebAssembly GC. Opening `index.html` as a local
file is unsupported. No source checkout, MoonBit, Node, package manager or
external asset CDN is needed to run this folder.

Select an item, increase quantity, choose JPY or USD, and refresh or retry a
failed quote. Detail and stock are coordinated; the USD rate is independent.
The quote and rate are deterministic fixtures, not live service data. Note
saves use an in-memory delayed fixture. A saved note does not survive closing
the application or browser. This is an API demonstration, not a persistence
product.

`package.json` records shipped files, byte counts, SHA256 hashes and the
pinned framework source. It is an inventory, not an npm package or a signature.
Keep all listed files together. The development diagnostics entry, verification
runner and source checkout are excluded.

## Included notices

| Component | Notice files |
| --- | --- |
| Metonic shared runtime and compiled framework code | `LICENSE-MIT`, `LICENSE-APACHE` |
| MoonBit core and upstream attributions | `LICENSE-moonbit-core`, `NOTICE-moonbit-core` |
| Prepared MoonBit async dependency | `LICENSE-async` |
| Chicle layout library | `LICENSE-chicle` |
| Generated WebSys browser bindings | `LICENSE-websys` |
| Noto Sans JP font | `OFL.txt` |

The framework revision in the inventory fixes the compiler and prepared
dependency versions. Native-only libraries are not included here.
