# Native CLI and MCP verification

## Native semantic revision wait

The development-only native `Handle.wait_semantic(revision, timeout_ms)` waits
until the editor semantic revision reaches or exceeds the requested value.
It returns an empty error on success, `timeout` at the deadline, `closed` for a
closed window, or `invalid_wait` for a negative revision or a timeout outside
1–60000 milliseconds. Task cancellation propagates as cancellation.

The wait uses the async library's condition variable, signaled after normal UI
event dispatch, rather than periodically polling the revision. Its cleanup
also clears canceled condition waiters. The existing hidden capture scenario
checks an already reached revision, invalid arguments, deadline expiration,
completion after a queued edit, and cancellation before continuing GPU capture.
The development wire operation `wait_semantic` accepts `semantic_revision` and
`timeout_ms`. A separate bounded reader continues observing EOF during a wait;
EOF cancels that wait with `disconnected`. Requests retain sequential execution,
and more than 64 queued input records terminates the connection rather than
blocking EOF observation behind admission. The control verifier checks timeout
recovery and EOF during a 60-second wait, with process exit required within two
seconds of EOF. MCP exposes `window_wait_semantic` with the same arguments.
The CLI and MCP transport use the shared MoonBit deadline calculation: a valid
wait gets at least its requested duration plus 1000 milliseconds for a response.
Ordinary and malformed requests retain their normal transport timeout. Explicit
outer client deadlines and cancellation may still end the operation sooner.
The attachment verifier also checks a timed-out wait, sends a subsequent
60-second wait and disconnects, then reconnects through CLI and MCP while
preserving the independently started application's edited state. This checks
connection cancellation without acquiring ownership of the app's lifetime.
Its MCP checks also exercise successful and expired semantic waits followed by
a state request on the same connection.
This does not wait for GPU submission or presentation; those are separate
completion conditions.

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

## Retained integrated surface copies

The development window protocol exposes `retained_frame_id` and `frame_scope`
in snapshots. Pass both to `capture_retained` (`frame_id` is the snapshot's
`retained_frame_id`). MCP exposes the same operation as
`window_capture_retained`. IDs are decimal strings to preserve Int64 precision
across JavaScript clients. The scope belongs to the running development app;
an attachment reconnect retains it, while another app start obtains a new scope.

The renderer keeps the latest two surface copies taken before Present. The
returned PNG identifies its frame, configuration generation, physical pixel
dimensions, scope and `display_scale`. The integrated window records the window
API's scale at draw time; renderers without a window may leave it null. A later
edit does not redraw that image. `source: retained_surface_copy` identifies the
image source; `display_completion_confirmed` separately identifies whether the
exact frame has been observed in presentation statistics. Ordinary development
hosts have no statistics reader and return false. The opt-in display-feedback
host can return true after exact-ID confirmation. The enclosing response describes current application state;
it is not a historical semantic snapshot of the retained image. Existing
`capture` continues to use its shared offscreen pass.

Both Handle capture operations await normal event-processing notifications rather
than a periodic timer. Cancellation remains cancellation when a completion signal
arrives concurrently; subsequent capture requests remain usable.

An unmatched scope returns `stale_frame_scope`. Invalid, future and evicted IDs
return `invalid_frame`, `frame_not_submitted` and `frame_evicted`, respectively.
The surface must support COPY_SRC; otherwise retention is unavailable. Copies
are development-only and released on eviction or renderer close.

`native:window` checks preserved pixels, eviction, specific ID errors, recovery
and an actual hidden-window resize from 640x360 to 800x480 with new generation
and image dimensions. It also cancels an outstanding Handle capture request and
checks that a subsequent capture of the same frame still returns identical pixels.
This does not pin cancellation to a particular GPU mapping phase.
`native:window-control` checks wire retrieval after an edit and scope
rejection on both adapters. `native:window-mcp` decodes the retained PNG and
checks its identity metadata. `native:window-attach` verifies CLI retrieval after
disconnect/reconnect and rejection of a previous app start's scope.
The production-exclusion verifier uses development
generated code as a positive control for retained image and capture code.
The control verifier additionally stops draining a retained PNG response after
its first byte, queues an edit and closes the owned hidden window. It requires
exit within two seconds, an incomplete response followed by EOF, no later reply
and rejection of subsequent input. This checks response backpressure shutdown;
it does not prove that an already applied action was rolled back.
The `native:window` display-wait probe injects statistics into the real hidden
window renderer. It checks that DISJOINT, a decreasing present counter, and
resize invalidate an unconfirmed retained frame; neither waiting nor capture
may report that old image as displayed. After resize, the new retained image has
a newer configuration generation and remains pending without a confirming
sample. These negative checks run on default and fallback adapters, together
with waiter deadline, cancellation, idle-observation and owner-close checks.
They do not establish real display completion; the opt-in
`native:window-display` task provides separate positive wire/CLI/MCP evidence.

## Display wait and capture contract

Use the snapshot's `frame_scope` and decimal Int64 `retained_frame_id` together.
The wire/attached CLI operation `wait_display` accepts them as `frame_scope` and
`frame_id`, with `timeout_ms` from 1 through 60000. MCP exposes the same contract
as `window_wait_display`; the UI Handle receives the ID within its own owner.
CLI and MCP transport deadlines allow the requested wait plus a response margin.
Success means exact-frame confirmation, not merely a newer submission. Capture
that same ID with `capture_retained` or MCP `window_capture_retained`; another
render may evict it before capture, which remains an explicit failure rather than
substituting the latest image.

The display-feedback host returns `display_unavailable` when statistics cannot
identify the image, `stale_display_epoch` after epoch invalidation, and `timeout`
when a pending frame does not become confirmed by the deadline. Invalid/future/
evicted IDs and closed owners have distinct errors. A confirmed historical frame
does not become unconfirmed solely because later statistics become disjoint.
No periodic display-wait polling runs without active waiters; present and capture
can still sample statistics. Active waits use separate 16-ms timers and serialize
surface access through the UI event queue.

Reproduce positive observations using the prerequisites and command in
[development display feedback](../../patches/wgpu-native-display-feedback.md).
This path is Windows DX12 and opt-in development only. Pixel dimensions and
draw-time window scale describe the retained image; the enclosing current
snapshot must not be used as its historical geometry. These checks do not prove
cross-monitor DPI transitions, physical device-loss recovery, or an exact scanout
timestamp. QPC in the statistics is a synchronization sample.

The same hidden-window gate uses a probe-only entry point with nonconfirming
statistics and the ordinary control protocol. A short wait must time out before
a long wait is interrupted. Closing stdin produces a final `disconnected`
response, process exit and stdout EOF. Closing a named-pipe client instead leaves
the application alive: a new connection must preserve the session's text and
frame scope and accept another edit within two seconds. Replies from the old
wait must not appear on that new connection.

The reconnect case deliberately terminates its owned test process after proving
continued operation; this is not normal-shutdown evidence. After process cleanup,
the verifier removes only discovery metadata whose pipe and session identifiers
match its own fixture. The stdin case separately verifies normal process exit.

These tests do not establish physical IME input,
or cross-monitor DPI/scale acceptance.

## Boundaries

This is an offscreen, dedicated child-process probe. It does not attach to existing
windows, produce semantic node references, test Windows IPC ACLs, or establish
nonblocking UI-thread scheduling. Production accessibility and exclusion of the
development composition still require paired artifact tests. Cancellation ends
the session; it cannot prove that an already submitted action was never applied.
The local pre-push runtime gate runs these checks. Automatic PR/push CI does not repeat
the same verification; manual dispatch remains available for hosted diagnosis.
## Retained display state across renderer recreation

`mise run native:surface` also builds the development surface probe and runs
`display-recreation` on default and fallback adapters. Three fresh surfaces and
healthy renderer/device generations share the same HWND. Each generation starts
with retained frame 1 and an unconfirmed capture under injected presentation
statistics. Closing a generation rejects capture and returns closed display
status; constructing another generation does not reopen the previous renderer.

The injected counts establish lifecycle isolation, not physical presentation.
The ordinary release probe remains separate and contains no retained-display
checks. App-lifetime frame scopes are verified by the attachment tests; these
renderer-local checks do not permit carrying numeric frame IDs between owners.
This does not test recovery from physical device loss or reuse of one surface
with a different device.
