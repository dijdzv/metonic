# Native CLI and MCP verification

## Integrated window capture consistency

The window capture response carries the snapshot taken immediately before its
shared offscreen pass. Subsequent queued events can advance the application while
the caller resumes; they must not replace the image's state with a later snapshot.
The response's frame counter is the application's submitted-frame counter at that
observation, not an independently confirmed presentation timestamp. The image
remains explicitly attributed to `shared_offscreen_pass`.

`mise run native:window` includes a capture followed by a queued move on both
default and fallback adapters. It checks that the live state advances while the
captured frame, coordinates, scene revision and dimensions retain their original
values, followed by normal cleanup. Substituting a post-capture snapshot makes
the regression fail with different frame counters. This tests the native Handle
and GPU readback; it does not establish real IME or a specified presented-frame
capture/wait contract. Production-window presentation remains a separate check.

## Original launch-scoped verification

Date: 2026-09-06.

The launch-scoped control experiment uses a MoonBit client from both the JSON-line
CLI and the MCP session host. Node retains the official MCP SDK boundary. See
[ADR 026](../adr/026-launch-scoped-native-control.md).

The shared headless client requires an executable, its arguments, an absolute
capture path and positive timeout/pending limits. It no longer accepts or injects
a custom GPU DLL path: the headless executable links the native binding
statically. The separate window/worker launcher still selects its required DLL.

## Local evidence

The current native-control suite has thirteen tests, including a configuration
contract and twelve tests using a MoonBit fixture process. The configuration test
accepts a bridge-free launch and checks exact errors for relative executable or
capture paths and nonpositive timeout or pending limits.
It covers the earlier Node suite's response, capture rejection, timeout, pre-cancel,
queue, malformed/unknown/oversized output, early-exit, diagnostics and close
contracts. Snapshot and echo assertions also check identifiers, protocol version,
state and payload. The out-of-order test requires the slow request to remain
unfinished when the fast request returns. The fixture runs in the pinned Wasm
host; its explicit exit-code injection uses the existing async runtime export.

- Five transport test groups passed: response correlation, failed capture,
  pending request timeout, cancellation, queue limits, malformed/unknown replies,
  early process exit, bounded diagnostics, and close behavior.
- The shared client drove snapshot, move, activate, and capture on RTX 3060/DX12
  and Microsoft Basic Render Driver. Complete pixel comparisons passed, as did
  stale revision rejection and concurrent capture rejection.
- The official MCP SDK client connected to the external stdio server, listed all
  five tools, moved the rectangle to (10, 20), activated it, and received a PNG for
  frame 1/revision 2. Complete pixel comparisons passed on both adapter modes.
  Stale mutation and invalid resize were rejected without changing scene state.
- A CLI JSON-line sequence returned the same state transitions and PNG content.

Versions: Node 26.8.1, MCP server/client SDK 2.0.0, Zod 4.5.4; native versions are
recorded in the [GPU probe record](native-headless.md). SDK tests establish
interoperability with that client, not every MCP host or legacy protocol revision.

The official-SDK verifier's tool sequence, JSON response checks and PNG pixel
checks live in the JS-target MoonBit package `tools/verify_native_mcp`. It uses
the pinned async library's Promise bridge and `mizchi/image`. Its exported
entry point returns a Promise that rejects on validation failure. Node retains
SDK connection/close, the outer 30-second deadline and filesystem output; the
test still talks through the official SDK to the external stdio server.
The migrated verifier passed in both default and fallback GPU modes. It checks
the PNG signature, first IHDR dimensions and response dimensions before decoding,
then compares every RGBA channel with the expected scene (tolerance one).
The existing independent codec checks remain separate.
Five MoonBit whitebox tests passed for missing/invalid response text, valid and
incorrect pixels, mismatched and oversized PNG dimensions, and Promise rejection
with the expected tool-list diagnostic. The rejection test has a two-second
deadline; timeout is a failure. These tests run in the normal local gate.

## Reproduction

After the setup in the [development guide](../development.md):

```powershell
mise exec -- pnpm install --frozen-lockfile
mise run native:build
mise run native:client-test
mise run devtools:test
mise run native:control
mise run native:cli-test
mise run native:mcp-test
$env:METONIC_GPU_FALLBACK = '1'
mise run native:control
mise run native:cli-test
mise run native:mcp-test
Remove-Item Env:METONIC_GPU_FALLBACK
```

Images and JSON evidence are stored in `.work/native-control`, `.work/native-cli`,
and `.work/native-mcp`.
The development processes use per-launch temporary capture directories and remove
them on normal shutdown. No desktop input automation is involved.

The MoonBit control verifier uses `mizchi/image@0.4.3` for PNG output, with
`mizchi/zlib@0.4.8`. Its PNG contract tests cover 3x2 and 257x129 RGBA patterns
with alpha 0/127/255, exact roundtrips, and invalid dimensions/data lengths.
An independent pngjs decode of those patterns matched every original byte
(24 and 132612 bytes respectively). This selects PNG encoding for development
captures; it does not adopt the library's other image formats or replace the
renderer. See the [published codec API](https://mooncakes.io/docs/mizchi/image).

On 2026-09-07 the migrated verifier completed on both DX12 adapters. Independent
pngjs decoding of each resulting 640x360 PNG matched all 230400 expected scene
pixels: the active rectangle at (10, 20), its background and opaque alpha. The
verifier also preserved stale mutation/capture rejection and the requirement that
two simultaneous capture attempts produce one success and one busy rejection.

The MoonBit CLI verifier also completed in both adapter modes on 2026-09-07.
It reads protocol stdout to EOF and requires a zero child exit code. Its sequence
checks initial state, move/activate revisions, the capture envelope and MIME type,
640x360 PNG pixels, stale mutation rejection, and unchanged state after malformed
JSON. Separate cases check recovery after a 5000-byte line and an unterminated
final request at EOF. These are offscreen process tests, not live-window control.

Additional CLI cases passed in both modes: invalid UTF-8, null arguments and
out-of-range/fractional revisions are rejected with recovery; a 4095-byte request
is accepted and a 4096-byte request is rejected. Lifecycle checks give the child
dedicated TEMP/TMP directories, confirm a capture file exists, then require those
directories to be empty after normal EOF or graceful cancellation. EOF also
requires exit code zero. Each case is bounded by a timeout. This exercises the
async library's Windows cancellation path, not every terminal or OS shutdown event.

## Boundaries

This is an offscreen, dedicated child-process probe. It does not attach to existing
windows, produce semantic node references, test Windows IPC ACLs, or establish
nonblocking UI-thread scheduling. Production accessibility and exclusion of the
development composition still require paired artifact tests. Cancellation ends
the session; it cannot prove that an already submitted action was never applied.
The local pre-commit gate runs these checks. Automatic PR/push CI does not repeat
the same verification; manual dispatch remains available for hosted diagnosis.
