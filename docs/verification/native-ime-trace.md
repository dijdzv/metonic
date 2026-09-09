# Native IME diagnostics

The development window snapshot exposes two bounded histories. They help diagnose
conversion behavior without changing the editor's cursor policy. Neither history
adds entered strings; the ordinary snapshot still contains editor text and preedit.

| Field | Meaning |
| --- | --- |
| `ime_events` | Latest 128 processed composition events: sequence, tick, field, UTF-16 length, supplied/applied cursor and selection |
| `ime_dropped` | Number of older processed events discarded |
| `raw_ime_events` | Latest 128 Windows IME messages: sequence, tick, message, flags, cursor query status and signed result |
| `raw_ime_dropped` | Number of older Windows messages discarded |

`tick_ms` uses the Windows monotonic tick counter. The histories have independent
sequence counters: a Windows message can generate zero or multiple application
events. Compare timestamps, flags, lengths and event order; do not join rows by
sequence number. Histories belong to the window/application instance and start
fresh when a new instance is created. They are not persisted on shutdown.

Only interpret `cursor_result` when `cursor_queried` is true. A false status is
not cursor zero. Negative API returns are preserved before the window library
maps the position to an optional cursor. The processed history separately shows
the application's fallback/clamping. A valid zero must not be replaced with the
preedit end merely because the displayed caret is unexpected.

## Build boundary

Use the supported mise build tasks. The MoonBit build script selects the C
diagnostic macro for debug, undefines it for release and regenerates the specific
Windows C object. Environment-only compiler flag changes do not invalidate that
object in the evaluated compiler cache. C-stub `targets` declarations did not
provide the expected profile selection in a minimal probe.

The raw record is captured at the existing IMM call site; no additional IMM query
is performed to manufacture diagnostic values. The small C addition retains the
message and signed return before information is lost at that boundary. MoonBit
owns processed-event storage, snapshot serialization and verification.

The negative-value fixture is compiled only into `window_probe`. Normal
development and production builds exclude that fixture. Production also excludes
the raw getter, raw storage and MoonBit histories. The exclusion verifier checks
generated C and the corresponding C objects, with the development/probe builds as
positive controls.

## Verification and real-system use

`mise run native:window` checks owned-window message dispatch, queried/unqueried
cursor paths, bounded histories and retained order. A probe-only fixture checks
signed results -2, -1, 0 and 99 through the same recording function. These fixture
values are not evidence that the installed IME returned those values.

`mise run native:window-control` and `mise run native:window-mcp` require the
histories in external snapshots and check that API edits do not fabricate OS
input. Build both `native:window-dev-build` and `native:window-release-build`
before running `scripts/verify-window-production-exclusion.mbtx`; the normal
pre-commit gate supplies the probe and other prerequisite artifacts as well.

For a physical investigation, use the development window and capture snapshots
before typing, during Space conversion, during Tab conversion and after Enter or
Escape. Repeat in both fields. Preserve OS/IME version, scaling, build revision
and the actual action sequence alongside the snapshots. Retain traces locally
with awareness that ordinary snapshots contain text. Follow the
[integrated walkthrough](integrated-demo.md) for the remaining acceptance steps.
Synthetic messages and fixture return values do not establish candidate placement
or physical Japanese IME correctness.
