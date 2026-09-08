# AccessKit Windows text clipping

The consumer patch targets `accesskit_consumer` 0.38.0 and the Windows patch
targets `accesskit_windows` 0.34.0 in AccessKit C 0.22.3. A separate
`clipped_bounding_boxes` operation intersects transformed text rectangles with
ancestor clipping bounds; the Windows TextRange provider uses that operation.
The original consumer geometry API and document text remain unchanged.
Degenerate and wholly clipped ranges return no rectangles.

`scripts/prepare-accesskit-focus.mbtx` verifies the consumer archive SHA256
`5d10a236f96f87d70732e44520046785431ef01d5bcd6b041317bfadd2f88245`
and applies both geometry patches alongside the existing focus patch. The
original dependency lock is preserved except for the two local source entries;
Cargo builds with `--locked`. There is one dependency build and DLL output.

The production UIA verifier compares Japanese, Latin, digits, CRLF and wrapped
text rectangles with the owned window's client origin and retained raster
geometry before and after resize. A range below the fixed editor viewport must
return no rectangle while its document text remains readable. The combined
focus/clipping build passed that sequence locally on 2026-09-08, including
HTTP, editing, task cancellation/reuse and close.
The external check also covers a supplementary-character range, an empty
range and rejection of old geometry after replacing its text. A pinned-font
combining-character case verifies that unsupported per-scalar geometry is
omitted, and retained-layout queries reject mismatched text.

The current layout publishes geometry only when glyph clusters align with
selectable units. It does not invent widths inside a multi-unit cluster.
Arbitrary rotation/skew, overlapping-window occlusion and actual assistive
technology use are not established by these axis-aligned editor checks.

Independent candidate tests cover visible, unclipped, fully/partially clipped,
translated and scaled ancestors. The final candidate passed six such cases and
206 consumer tests. These are local correction candidates; no upstream
submission is claimed. Follow-up and upstream review are tracked in
[#147](https://github.com/dijdzv/metonic/issues/147).
