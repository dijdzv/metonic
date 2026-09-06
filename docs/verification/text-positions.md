# Text position boundary

## Implemented contract

`examples/p0/text_position` converts between UTF-16 code-unit offsets, UTF-8 byte
offsets and Unicode scalar indices. Every public function states both units in
its name. Offsets describe prefix boundaries, including zero and the end.

Negative, out-of-range, mid-surrogate and mid-UTF-8-sequence offsets return
`None`. An unpaired surrogate anywhere in the input invalidates every conversion,
including offset zero. Each call validates the whole string and scans it; this
is an O(n) correctness probe, not an indexed editing buffer.

For `A日本😀e` followed by U+0301 COMBINING ACUTE ACCENT:

| UTF-16 code units | UTF-8 bytes | Unicode scalars |
| --- | --- | --- |
| 0 | 0 | 0 |
| 1 | 1 | 1 |
| 2 | 4 | 2 |
| 3 | 7 | 3 |
| 5 | 11 | 4 |
| 6 | 12 | 5 |
| 7 | 14 | 6 |

The boundary before a combining mark is a valid scalar boundary. It is not
necessarily a grapheme boundary or a cursor stop. Glyph clusters, grapheme
segmentation, bidi affinity and screen coordinates require the text layout
adapter; these functions do not implement them.

The semantic model reuses this boundary check for selection. `set_text` rejects
malformed UTF-16 as `invalid_text`, preserving value, selection and revision.
The existing session, generation, role and enabled checks remain in force.

## Verification

Six position tests cover independent expected offsets in mixed Japanese/Latin
text, emoji, a ZWJ sequence, combining marks, two-byte UTF-8, empty input and
malformed surrogate sequences. A semantic regression test checks selection and
state preservation on rejected text. These run with `mise run verify` (JS and
WasmGC) and `mise run verify-native` (MSVC/native).

This is part of P0-F/P0-G preparation. It does not demonstrate glyph shaping,
text rendering, actual IME composition or candidate placement.

## Rendering comparison to perform

The next experiment must shape and render the same licensed font and mixed-script
sample on native and browser targets, recording font bytes, engine versions,
cluster units, missing-glyph behavior and bridge copies.

| Candidate | Documented capability | Evaluation still required |
| --- | --- | --- |
| [COSMIC Text 0.19.0](https://docs.rs/cosmic-text/0.19.0/cosmic_text/) | Shaping, layout, font fallback and optional swash rasterization | Native/Wasm build, explicit font loading, cluster mapping and GPU upload |
| [Parley 0.11.1](https://docs.rs/parley/0.11.1/parley/) | Rich-text shaping, line breaking, bidi layout and alignment | Rasterizer integration and bridge size compared with COSMIC Text |

These are candidates, not adopted dependencies or measured results. The
[Noto Sans JP source](https://github.com/google/fonts/tree/main/ofl/notosansjp)
is a font candidate; its exact revision, file checksum and license must be
recorded before it is distributed with an experiment. No font is bundled by
this position-boundary change.
