# Font-backed MoonBit text evaluation

Date: 2026-09-06. The initial isolated dependency evaluation now also has a
browser integration. This does not adopt a complete text/IME stack or replace
the native renderer.

## Reproduction and inputs

Run `mise run text:verify` with the pinned project toolchain. The MoonBit script
`scripts/verify-text-layout.mbtx` uses published `Milky2018/moon_cosmic@0.3.3`
and `moonbitlang/async@0.21.2`. Its default execution target is WasmGC.

The script downloads Noto Sans JP and its SIL Open Font License into ignored
`.work/text-assets` paths. Both URLs use google/fonts commit
`66a36c8c94b1a5d992ee4e7f392fccfe4945767c`. The font's SHA256 must equal
`c2f3b4d463500a2ddcd3849cded1fceeb9fd6d1c32e6cbecd568453ba50fc68f` before loading.
The font is not bundled in the library or committed into the repository.

The input is `日本語の描画を確認します ABC 123`, with font size 24 and line height 32.
Font loading, nonzero glyph IDs, repeated layout consistency, and coverage of
every non-space UTF-16 position are checked. This BMP-only sample does not test
surrogate pairs, grapheme navigation, emoji fallback or bidirectional editing.

## Observed results

| Configuration | Lines | Maximum line width |
| --- | ---: | ---: |
| Width 640, Word | 1 | 384.3840026855469 |
| Width 96, Word | 2 | 288 |
| Width 96, WordOrGlyph | 4 | 96 |

Word wrapping alone allows the long Japanese segment to overflow this sample's
width. WordOrGlyph satisfies the bounded-width test without dropping non-space
characters. The test preserves both results rather than treating an increased
line count as proof of bounded layout. This does not establish Japanese line-break
tailoring or punctuation rules.

WasmGC and Windows native runs passed. The native run used the existing MSVC
environment bootstrap with `MOON_CC=cl` and the pinned compiler's
`moon run scripts/verify-text-layout.mbtx --target native`. Both reported the
same layout metrics. Rendering the wide buffer produced 3,567 callbacks with
positive alpha. The glyph raster callback coordinates and alpha are serialized
into `.work/text-assets/japanese-wide.svg` on a white background.

The SVG was rendered using the installed Playwright screenshot CLI with headless
Chromium at 640×96. Visual inspection confirmed the Japanese and ASCII sentence
was readable and complete. It is a CPU glyph raster artifact, not Browser WebGPU
or native GPU presentation evidence. No desktop input automation was used.

## Native GPU texture integration

The font script also creates a 640×96 RGBA8 bitmap on a white background. Glyph
callback rectangles are clipped to that canvas and composited in MoonBit using
integer source-over alpha. Nonwhite and white pixels must both exist.

`mise run native:binding` regenerates this bitmap before running the native tests.
The isolated `text_test.mbt` reads it through `moonbitlang/x/fs@0.4.45`, validates
its length and opaque alpha, uploads it through wgpu_mbt, and draws a fullscreen
triangle with a texture-reading fragment shader into a separate RGBA8 texture.
It then reads back and compares all 245,760 bytes against the source, allowing
at most one channel value of rounding difference. It does not substitute a
texture copy for the shader draw.

NVIDIA GeForce RTX 3060 and Microsoft Basic Render Driver both passed this DX12
test for all 61,440 pixels on 2026-09-06. The existing rectangle and hidden HWND
tests also passed, for three tests total. GPU handles use scope-bound cleanup.
No metonic Rust/C bridge code was added; file I/O uses the existing MoonBit library.
The standalone `text:verify` task remains available, while pre-commit runs it
through `native:binding` to avoid generating the same fixture twice.

## Boundaries and next integration

The original `.mbtx` script does not compile with `--target js`: async's file/process
APIs used by this harness are unavailable on that target. This is not evidence
that moon_cosmic itself fails on JS; its separately recorded upstream JS tests
passed. The browser now supplies font bytes to `text_raster`, a shared MoonBit
package with no file/process or browser imports. The original script remains an
independent CPU/native reference; its raster loop has not yet been replaced by
this package.

The native result establishes an offscreen GPU texture path. The browser input
can update displayed text, but selection/caret remain in the DOM input rather
than the GPU canvas. This is not a GPU text editor or glyph atlas. Next gates are
native interactive integration, mixed-script and emoji fallback, selection/hit-testing,
and input normalization.
Real IME composition and candidate positioning require separate OS integration.
The existing [text-position contracts](text-positions.md) remain authoritative.

## Browser architecture

`text_raster` uses published moon_cosmic 0.3.3 for shaping, WordOrGlyph layout and
glyph rasterization. Its engine retains the font system and swash cache across
updates. The browser probe limits text to 1,024 UTF-16 units and output to a
96-pixel-high surface. Content beyond that height is clipped; there is no scrolling
or fallback guarantee for glyphs absent from the supplied font.

The host fetches and hashes the same pinned font, transfers packed four-byte
words, and submits UTF-16 units through scalar exports shared by JS and WasmGC.
MoonBit validates surrogate sequences and produces RGBA pixels. This explicit
copying boundary avoids assuming that a WasmGC array has a linear-memory address;
it is a correctness baseline, not a final bulk-transfer or performance choice.

The WebGPU adapter uploads the result and samples it in a separate draw within
the existing canvas pass. Text/width changes invalidate the raster; rectangle
movement and activation reuse it. Stop destroys textures/buffers and drops the
MoonBit text state. Asynchronous font completion checks disposal before writing
new state. The release Wasm artifact retains `spectest.print_char`; the host
provides bounded diagnostic output rather than silently dropping it.

## Browser verification

`mise run browser:headless` runs the integrated input, rectangle and lifecycle
checks. The physical NVIDIA adapter passed the following on 2026-09-06:

- JS and WasmGC produced identical 640×96 Japanese text crops. Replacing the text
  changed the image, empty input produced opaque white pixels, and restoring the
  original input restored the exact image.
- Rectangle movement preserved the text raster/upload counts. A narrower viewport
  changed the raster width. One initial raster uploads 245,760 bytes.
- The JS DPR-2 image matched a 2× nearest-neighbor expansion of the DPR-1 text crop.
- JS font HTTP failure, hash mismatch, and stopping during font loading were
  checked alongside the existing artifact-loading and lifecycle failures.

Pixel-comparison pages align the canvas's layout origin to integer CSS pixels;
otherwise a fractional locator screenshot clip introduces an extra edge row.
Canvas size and GPU raster data are unchanged by that alignment. Screenshots and
machine-readable results remain under `.work/browser-headless/<backend>`.

Four MoonBit boundary tests passed on both JS and WasmGC, including complete
surrogate decoding and rejection of isolated surrogates. The shared package also
passes native static checking; that is not native interactive rendering evidence.
Synthetic DOM input is used here, not an OS IME or GPU selection/caret test.
