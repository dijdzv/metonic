# ADR 026: Launch-scoped native control client

Date: 2026-09-06.

Status: experimental implementation. The window, semantic, attach, and production
gates in [ADR 023](023-development-automation.md) remain open.

## Scope relative to independent attachment

Launch ownership remains useful for automated fixtures, but is not the final P0
interaction model. A developer may start a development application independently;
CLI and MCP clients must be able to connect afterward, disconnect and reconnect
without ending that application. MCP does not need to launch the application.
The inherited-stdio mode below retains its explicit child-process ownership.
Its close/kill rules must not be applied to an attached application.

The development window also supports an explicit Windows named-pipe listener
selected by `METONIC_DEV_PIPE`. It shares request dispatch and bounded framing
with stdio, allocates request-ID state per connection, and closes only the
connection on client EOF. Window shutdown cancels the listener/controller before
the pipe is released. `mise run native:window-attach` verifies reconnection with
preserved editor state and window closure during accept, read and blocked capture
output.

The host publishes `session.json` in its uniquely reserved temporary directory
and prints its path with `METONIC_DEV_SESSION` on stderr after writing it.
The document contains `pipe`, `session_id` and `protocol_version`. Clients must
read it, require a supported version, and compare `capabilities` with the expected
session before sending operations. Pipe requests other than `capabilities` require
that session ID; stale IDs do not mutate state. The ID is not a secret credential.
Normal app exit removes the document and reservation. The shared MoonBit client
in `tools/window_attach` validates discovery and correlates bounded responses;
both CLI and MCP select it with `--session`. A timeout, cancellation or malformed
response closes that connection without owning the application's lifetime.
Abnormal exit can retain metadata: clients reject an unavailable endpoint or a
different session identity instead of retrying against another application.
Automatic stale-record deletion is not implemented.

## Composition

The CLI and MCP session host use the MoonBit native-control client. The external
MCP stdio adapter retains the official Node SDK. Each
launch owns one dedicated native headless process and a private temporary capture
directory. The client selects absolute executable and capture paths. The headless
renderer links its GPU binding statically and needs no custom DLL selection. There
is no attach discovery or listening TCP endpoint. This inherited-stdio experiment
does not settle the Windows named-pipe ACL and discovery requirements.

The MoonBit client in `tools/native_control` provides the same launch-scoped
transport for migrated development verification. Its pure JSON envelope and
bounded line framing live in `tools/native_wire`; process scheduling and pipe
ownership use the existing MoonBit async library on native/Wasm host runtimes.
The native-control tests use a MoonBit fixture process, including delayed and
malformed responses. The earlier Node client and fixture have been removed after
their contracts were covered by the MoonBit tests. The MCP session boundary is described in
[ADR 029](029-moonbit-development-session.md).
This host runtime choice does not establish browser WasmGC support.

The CLI in `tools/native_cli` uses the Wasm host runtime, not browser WasmGC.
It accepts `{op,args}` JSON lines and preserves the capture envelope containing
`response` and a base64 PNG `image`. Its input framer in `tools/cli_lines` recovers
after an oversized line; malformed replies from the native process instead remain
fatal to the client session. Input is decoded as strict UTF-8 so invalid bytes
produce an error rather than being silently replaced. The default repository root
is the current directory; an explicit `--root PATH` supports launch from elsewhere.

MoonBit remains the scene-state owner. The client correlates bounded JSON-line
requests, limits outstanding operations, and translates completed RGBA captures
to PNG. MCP types and dependencies exist only under the development tool root;
they are not added to the MoonBit module or Rust renderer dependency graph.
This is not yet the paired production-artifact exclusion proof.

## Failure semantics

Requests have monotonically allocated IDs and optional expected scene revisions.
Unknown response IDs, malformed replies, process failure, timeout, and in-flight
cancellation terminate the control session and reject outstanding requests.
Cancellation cannot roll back an operation already applied by the native process;
the client therefore does not retry or claim that cancellation prevented mutation.
A signal cancelled before dispatch rejects only that request.

Capture is exclusive until its file has been read, preventing a second capture
from replacing bytes belonging to the first response. The response's dimensions
and revision describe those bytes even if later scene mutations are queued.
Capture completes after offscreen readback, not window presentation.

## MCP surface

Five tools expose snapshot, move, resize, activate, and capture. Inputs reject
unknown fields and bound integers. The output contains a launch-session identity;
this is not a generation-tagged semantic node reference. Capture returns standard
MCP image content. SDK cancellation is forwarded to the native client.

Use the official SDK 2.0.0 server/client packages with exact development dependency
pins. The SDK owns protocol framing and compatibility handling; native JSON lines
are a separate internal protocol. See the
[SDK stdio API](https://ts.sdk.modelcontextprotocol.io/v2/api/%40modelcontextprotocol/server/stdio.html).

## Remaining gates

Real window enqueue/wakeup and nonblocking completion, semantic node identity,
accessibility, attach discovery/ACLs, reconnect behavior, and production exclusion
need their own implementations and verification. Passing this probe does not
close P0-A, P0-C, or P0-H.
