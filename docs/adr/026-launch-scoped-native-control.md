# ADR 026: Launch-scoped native control client

Date: 2026-09-06.

Status: experimental implementation. The window, semantic, attach, and production
gates in [ADR 023](023-development-automation.md) remain open.

## Composition

The CLI and external MCP stdio adapter share a Node native-control client. Each
launch owns one dedicated native headless process and a private temporary capture
directory. The client selects absolute executable, DLL, and capture paths. There
is no attach discovery or listening TCP endpoint. This inherited-stdio experiment
does not settle the Windows named-pipe ACL and discovery requirements.

The MoonBit client in `tools/native_control` provides the same launch-scoped
transport for migrated development verification. Its pure JSON envelope and
bounded line framing live in `tools/native_wire`; process scheduling and pipe
ownership use the existing MoonBit async library on native/Wasm host runtimes.
The Node client remains for CLI/MCP consumers until their behavior is migrated
and verified. This host runtime choice does not establish browser WasmGC support.

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
