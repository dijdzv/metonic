# Browser RGBA transfer

The text renderer transfers one complete RGBA layer per call. JS uses MoonBit's
Uint8Array representation and immediately copies it with the browser's `slice()`.
The returned source array is internal and must not be mutated by the host.
WasmGC uses the pinned compiler's JS-string builtins: pairs of bytes travel as
raw UTF-16 code units and are unpacked with `charCodeAt`. This is not text and
must never pass through UTF-8 encoding or Unicode normalization. RGBA lengths
are multiples of four. Unexpected types or lengths are rejected before upload.

No new dependency or C bridge is required. This is a target-specific compiler
boundary, not an assumption that JavaScript can directly access WasmGC arrays.
Invalid layer indices return an empty buffer; text disposal removes the layers.
GPU upload and texture ownership retain their existing behavior.

## Reproduction and evidence

Run `mise run browser:headless` with the pinned toolchain. Its test page injects
an oracle comparison into the renderer, compares every uploaded word with
`view_layer_pixel`, and measures the actual transfer code on a rendered layer.
Instrumentation is not written into the packaged application. Results are in
`.work/browser-headless/default/results.json` under each target's
`rgbaComparedBytes` and `rgbaTransferTiming` fields.

The 2026-09-09 Chromium 153.0.8010.12 run compared 2,429,440 bytes per target
without a mismatch. The integrated suite also passed text pixels, resize,
stop, HTTP failure/recovery and production development-feature exclusion.
For a 245,760-byte layer, ten warmups precede thirty measurements per method;
execution order alternates and full byte checks occur outside the timed interval.

| Target | Per-pixel median | Bulk median | Export calls, old / new |
| --- | ---: | ---: | ---: |
| JS | 0.4 ms | below timer resolution | 61,440 / 1 |
| WasmGC | 0.6 ms | 0.4 ms | 61,440 / 1 |

Both paths allocate a destination byte array of the same size. WasmGC additionally
creates a binary string; this is not zero-copy. Heap allocation pressure was not
profiled. These are CPU transfer measurements, not GPU submission or frame times,
and no timing threshold is used as a correctness gate. This change does not
reduce upload bytes, rasterization, or texture/pipeline creation.

Prior isolated comparisons rejected Base64 and a MoonBit FixedArray allocation
and blit copy as slower. Raw UTF-16 transfer was slower on JS, hence the separate
JS boundary. The isolated probe preserved all 65,536 code units, including lone
surrogates, and verified independent JS copies. See issue #214 for investigation
details. The integrated oracle remains the ongoing check for actual layer bytes.
