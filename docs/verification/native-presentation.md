# Production window presentation

Run `mise run native:presentation` after the Windows setup in
[the development guide](../development.md). This opt-in check runs the production
edit/HTTP/resize/close sequence and captures its owned HWND at the initial,
toggled and resized stages. It opens a visible window briefly. Computer Use and
desktop-wide capture are not used.

## Reused tool

`scripts/prepare-winapp.mbtx` downloads Microsoft's [winapp CLI v0.6.0](https://github.com/microsoft/winappCli/releases/tag/v0.6.0)
x64 ZIP and verifies SHA256
`f6dc42e3b4e4709c8f617003008e2cfdd9a51735e04e7170d60edda258db78a8`.
Only `winapp.exe` and `libSkiaSharp.dll` are extracted under `.work/winapp-assets`.
The CLI is [MIT-licensed](https://github.com/microsoft/winappCli/blob/v0.6.0/LICENSE).
It remains an external verification dependency and is not included in Metonic's
production artifacts. Invocations set `WINAPP_CLI_TELEMETRY_OPTOUT=1`.

MoonBit owns process supervision, target selection, metadata decoding, PNG
decoding and assertions. The CLI receives `ui screenshot -w HWND --json --output
PATH` without screen-capture or foreground options. The existing supervisor
bounds the complete session to 65 seconds and owns the native window and client.

## Evidence and limits

The check rejects mismatched HWND/PID metadata and PNG dimensions. It invalidates
each prior output before invoking capture. Color-region counts distinguish the
initial cyan rectangle from the orange toggled rectangle and check the orange
state after resize. UIA separately verifies editor preservation, HTTP result and
updated editor bounds. The native Win32 title is checked independently of UIA.
The rectangle mask must occupy exactly 120x72 pixels at the scene's client-area
position (260,144). DWM extended frame bounds and the client origin translate
that position into capture coordinates; the capture must match the reported
frame dimensions. This rejects displaced, scaled, incomplete or extra colored
regions in the tested flow, including after resize.
The initial local run and a repeat with `METONIC_GPU_FALLBACK=1` passed these
assertions. This records the two requested adapter modes on the current display,
not coverage of every GPU or display configuration.

The initial 624x96 editor region also compares the shared rasterizer's opaque
black glyph interiors and white background at exact client coordinates. The
reference uses the pinned font and the initial Japanese/Latin/digit sample.
Captured channels must remain within two byte levels of black or white, and
the reference must contain both ink and background. This checks transfer and
placement agreement, including unexpected marks in blank space. Antialiased
edge values are excluded because surface color conversion changes them; the
check does not independently validate the shaping engine or font design.

PNG artifacts are `.work/presentation-initial.png`,
`.work/presentation-toggled.png` and `.work/presentation-resized.png`. These include
window chrome. Inspection of the initial local images showed Japanese/Latin text,
the color transition and the resized HTTP result. It also revealed a default
`winit window` title, corrected to `Metonic`. The sample emoji is a missing-glyph
box with the current font; preserving supplementary text does not prove font
coverage.

The long-editor regression uses four committed lines after HTTP success. The
editor keeps its 96-pixel viewport; the result occupies a separate 32-pixel row
below it. `.work/presentation-long-editor.png` must contain result ink in that
row, and its result pixels must exactly match `.work/presentation-result.png`
after restoring the short editor text. This detects the previous clipping of the
result by editor contents. It does not establish scrolling of the editor's own
offscreen lines.

The CLI's screenshot JSON does not report capture mode. Its pinned source tries
Windows Graphics Capture and may fall back to PrintWindow. Consequently this
record calls the images HWND-scoped captures, not verified WGC frames. A
machine-readable mode and optional require-WGC behavior are upstream improvement
candidates. No upstream change has been submitted.

This is not a complete presentation acceptance test: color regions do not prove
glyph correctness, text layout, every display scale, occlusion behavior, real
keyboard input or Japanese IME candidate placement. The opt-in check does not
replace those requirements. GDI GetDC/GetPixel sampling was evaluated first but
did not reproduce the Toggle color transition and was not adopted.
