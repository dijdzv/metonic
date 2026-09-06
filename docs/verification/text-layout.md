# Font-backed MoonBit text evaluation

Date: 2026-09-06. This is an isolated dependency evaluation, not adoption of a
complete text/IME stack or a replacement of the current renderer.

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

The same `.mbtx` script does not compile with `--target js`: async's file/process
APIs used by this harness are unavailable on that target. This is not evidence
that moon_cosmic itself fails on JS; its separately recorded upstream JS tests
passed. A browser integration should supply font bytes through the browser host
and reuse pure text processing, without adding Node I/O to the product.

This establishes an offscreen GPU texture path, not a glyph atlas/cache or text
widgets in the interactive hosts. Next gates are interactive native/browser
integration, mixed-script and emoji fallback, selection/hit-testing, and input normalization.
Real IME composition and candidate positioning require separate OS integration.
The existing [text-position contracts](text-positions.md) remain authoritative.
