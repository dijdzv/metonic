# Native Japanese IME verification

Status: implementation under verification; real IME acceptance is not complete.

The shared editor stages preedit separately from committed text. Commit replaces
the original selection once; cancellation leaves the text unchanged. A revision
change invalidates the composition. CLI/MCP edits and selection changes are
rejected with `composition_active` while the IME owns the edit.

The pinned window library needs `patches/window-ime-position.patch`. It forwards
the IMM composition cursor, including cursor-only and empty-preedit updates, and
applies the requested caret rectangle with ImmSetCandidateWindow and
ImmSetCompositionWindow. Preparation applies the patch to pristine sources; do
not edit `.work/native-deps/sources`. The upstream-compatible working copy has
not been submitted upstream.

## Automated evidence

- Shared semantic tests cover preedit isolation, one-time commit, cancellation,
  intervening edits and disposal on JS and WasmGC.
- `mise run native:window` injects composition events into the integrated UI and
  checks preview, retained committed text/selection, cursor value and cancellation.
  When preview text differs from committed text, it also checks that committed
  accessibility text runs disappear and cancellation restores runs with fresh
  identifiers. This verifies invalidation rather than reusing stale geometry.
- These tests do not drive a Japanese IME. Builds and cached candidate coordinates
  do not prove that an OS candidate window appears at the requested position.

## Real input procedure

Run the integrated production demo from the repository root:

```powershell
mise run demo
```

This builds and launches the release window with its owned HTTP server. Follow
the [common operation sequence](integrated-demo.md#common-operation-sequence)
before and after the composition checks below: confirm ordinary editing, F7
result display, resize and continued editing. Close native last; the launcher
must report `DEMO_STOPPED`. A successful automated UIA run does not replace
this physical-input check.

Use Microsoft Japanese IME or record the exact alternative IME and version.
Record Windows version, display scaling and monitor for each run.

1. Select the current text with Ctrl+A. Type `nihongo` in Hiragana input mode.
   Confirm the preedit is visible without permanently deleting the original text.
2. Press Escape until composition is canceled. Confirm the original text returns.
3. Compose again, convert with Space, and commit with Enter. Confirm one committed
   replacement, with no duplicate characters or control characters.
4. Compose a longer phrase and move within the composition. Confirm the candidate
   position follows the composition cursor rather than always using its end.
5. Resize during composition, then move to a monitor with different scaling if
   available. Confirm candidate placement remains near the insertion position.
6. Cancel, change focus during another composition, and close while composing.
   Record text loss, unexpected commits, duplicate input or a lingering window.

Record the tested commit, production build, Windows/IME version and display
scale, then a pass/fail/not-run result for each step and the actual observed
text or popup behavior. Put run-specific results on #94 (composition) and #92
(ordinary input); keep this document as the reproducible procedure. Do not
infer a pass for an unperformed step from an automated or development run.

If diagnosis needs internal state, use a separate development session through
the [CLI/MCP integration](../development.md#integrated-window-http-requests).
Do not enable a development endpoint in the production executable.
For that development session, `window_snapshot` exposes `composing`, `preedit`,
`preedit_cursor` and `ime_requested_x/y`. The last two are requested client-area
physical coordinates, not measured OS candidate-window positions. MCP capture
contains the application's shared offscreen pass, not the external IME popup.
Human observation is required for the popup; Computer Use is not used.

Keep this requirement open until the scenarios have actual observed evidence.
Missing multi-monitor hardware must be recorded as unverified, not passed.
