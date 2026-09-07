# Native development session verification

The session host uses MoonBit's Wasm host runtime, the existing native-control
client and `mizchi/image` PNG encoder. Node retains the official MCP SDK and a
subprocess/AbortSignal adapter. See [ADR 029](../adr/029-moonbit-development-session.md).

## Reproduction

From a configured repository, run:

```text
mise run native:session-test
mise run devtools:test
mise run native:mcp-test
```

Repeat with `METONIC_GPU_FALLBACK=1` to request the software adapter. The ordinary
pre-commit gate includes these checks. The session verifier writes mode-specific
results to ignored `.work/native-session`; the existing MCP verifier writes its
decoded image and result to `.work/native-mcp`.

## Observed scope

The MoonBit verifier passed on both the default and fallback GPU paths. It checks
the ready envelope, the eight-element initial state, move and activation
revisions, a PNG capture against every expected pixel, stale mutation rejection,
and unchanged state after rejection. It observes the capture file before closing
stdin and checks that the host removed its temporary directory. A separate case
closes stdin immediately after readiness.

The SDK-side tests exercise sixteen simultaneous pending requests, rejection of a
seventeenth, exclusive capture, a pre-aborted call that leaves the session usable,
dispatch followed immediately by cancellation, and repeated close. The cancellation
test proves rejection and teardown at the adapter boundary; it does not prove
that a GPU operation had begun or that cancellation can undo a mutation.

The existing official-SDK verifier checks the five MCP tools, scene mutations,
capture image decoding and pixels, stale revisions and invalid resize rejection.
This additionally tests the composition through the real SDK rather than only
the internal session protocol.

The dedicated MoonBit `tools/session_fixture` host exercises the SDK adapter
without a GPU. Its fourteen tests cover missing executables (preserving ENOENT),
invalid readiness, raw invalid UTF-8, truncated output, malformed responses with
two pending callers, unknown identifiers, output beyond 32 MiB, readiness timeout,
exit code 19 and forced termination. Locally rejected oversized, cyclic and invalid
arguments leave the session usable. A 4095-byte JSON body succeeds; 4096 bytes is
rejected before dispatch, excluding the line delimiter. Recoverable fixture
shutdown checks require exit code zero without forced termination.

`mise run devtools:test` builds this fixture and runs both fixture and real-renderer
adapter tests. The fixture tests passed with no skipped cases on Windows using
the pinned MoonBit runtime and Node 26.8.1. Forced termination is an expected
failure case, not evidence of resource cleanup.

## Limits

The session wire is an internal development boundary, not a stable public API.
The MoonBit native-client fixture suite covers the renderer protocol separately
from the SDK adapter. Forced termination cannot establish cleanup; successful adapter close
must report a normal host exit. The fixture cases do not establish sustained
input-flood resistance or arbitrary fault recovery in the renderer itself.

These checks do not establish live-window attachment, physical input, Japanese
IME composition, OS accessibility or exclusion from a production artifact.
