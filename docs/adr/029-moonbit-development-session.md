# ADR 029: MoonBit ownership of native development sessions

Status: accepted

## Context

The previous native MCP adapter owned renderer process correlation, capture files
and PNG encoding in JavaScript. The existing MoonBit control client and image
codec can provide those operations. The interactive CLI processes lines serially;
using it unchanged would alter concurrent MCP requests and cancellation.

Existing MoonBit MCP SDKs were compared before introducing another boundary.
`colmugx/mcp@0.17.5` builds natively and dispatches asynchronous stdio tools, but an
isolated runtime probe showed that a cancellation notification did not stop a
running tool. Closing stdin also allowed the tool to finish. Its Wasm artifact
requires crypto imports absent from the pinned moonrun host. These results do
not justify replacing the working official SDK. The investigation and exact
scope are recorded in [issue 30](https://github.com/dijdzv/metonic/issues/30).

## Decision

Keep the official MCP SDK and strict tool schemas in the Node boundary. Move
renderer ownership, capture-file lifecycle and PNG encoding into a MoonBit host
using the existing control client. The internal line protocol connects that host
to the SDK adapter; it is not an implementation of the MCP protocol.

Each host launch owns one scene and temporary capture directory. A ready message
provides a stable session identifier. Positive request identifiers correlate
concurrent operations, with at most sixteen in flight. Capture remains exclusive
through encoding. Individual responses carry either native response data and an
optional PNG image, or a host error.

An already-aborted SDK call must leave the session usable. Aborting an in-flight
call ends the session, matching the existing client's fatal cancellation policy.
The adapter closes host stdin; the host cancels outstanding tasks and releases
the renderer and temporary files. Normal close uses the same ownership boundary.
Both sides bound their input and teardown waits. Forced termination is a final
fallback and must not be presented as proof that temporary files were cleaned.

## Verification boundary

The change must preserve real GPU capture pixels, stale revisions, strict SDK
argument rejection, request correlation, capture exclusion, cancellation and EOF
cleanup. The existing CLI checks and MoonBit native-client fixture coverage remain
separate from SDK adapter tests. A successful MCP connection alone does
not prove those properties.

This is still launch-scoped development control. It does not establish attachment
to a running window, OS accessibility, real IME input or production exclusion.
