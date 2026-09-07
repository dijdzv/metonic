# ADR 023: Development automation and accessibility boundaries

Date: 2026-09-06.

Status: **accepted direction; adapters and transport are proposed, not implemented**.
AccessKit adoption remains open pending P0-H evidence.

## Context

GPU rendering does not automatically expose a useful element tree to automation
tools. Native UI creation needs stable inspection, actions, input, screenshots,
and completion signals from the beginning. Browser DevTools helps inspect the
host, but cannot infer framework widgets solely from pixels in a WebGPU canvas.

Production applications also need accessibility. Its semantic information overlaps
with automation, but an accessibility provider and a development control endpoint
have different responsibilities and lifetimes.

## Existing implementation examined

The reference is `dijdzv/egui-mcp`, commit
`e72926b0285913ac2b145539f9a0d58f15c4560c`. This is a source review, not a local
execution or a claim of Windows compatibility.

| Evidence | Observation | Consequence for metonic |
| --- | --- | --- |
| [Demo initialization](https://github.com/dijdzv/egui-mcp/blob/e72926b0285913ac2b145539f9a0d58f15c4560c/examples/demo-app/src/main.rs#L89) | Enables egui AccessKit integration | egui provides the semantic producer; metonic must implement its own producer |
| [Element actions](https://github.com/dijdzv/egui-mcp/blob/e72926b0285913ac2b145539f9a0d58f15c4560c/crates/egui-mcp-server/src/tools/action.rs#L10) | Uses AT-SPI on Linux and returns unavailable elsewhere | Do not reuse this as a ready-made Windows adapter |
| [IPC server](https://github.com/dijdzv/egui-mcp/blob/e72926b0285913ac2b145539f9a0d58f15c4560c/crates/egui-mcp-client/src/server.rs#L13) | Uses Unix sockets for app-specific operations | Select and verify a Windows transport independently |
| [Input hook](https://github.com/dijdzv/egui-mcp/blob/e72926b0285913ac2b145539f9a0d58f15c4560c/examples/demo-app/src/main.rs#L137) | Drains queued input into egui RawInput | Route control through the normal UI thread/input path |
| [Frame loop](https://github.com/dijdzv/egui-mcp/blob/e72926b0285913ac2b145539f9a0d58f15c4560c/examples/demo-app/src/main.rs#L189) | Requests a repaint every 16 ms to service input | Prefer explicit wakeups; automation must not require idle polling |
| [Demo dependency](https://github.com/dijdzv/egui-mcp/blob/e72926b0285913ac2b145539f9a0d58f15c4560c/examples/demo-app/Cargo.toml) | MCP client is an ordinary dependency | metonic needs a separately tested production-exclusion boundary |

The reference's README documents gaps in EditableText/selection support. Treat
those as findings for that version, not universal current AccessKit limitations.
No reference implementation code is copied into metonic.

## Semantic source of truth

The MoonBit interaction layer owns semantic nodes: stable identity, role, name,
value, bounds, focus, selection, enabled state, hierarchy, and supported actions.
Both production accessibility and development inspection consume that model.

The model must not embed AccessKit structs, COM providers, MCP objects, or an IPC
server. Platform adapters translate it. Core actions route through the same
interaction handlers regardless of whether they originated from keyboard,
accessibility, or a development command.

Production semantics are not optional debug metadata. Test-only IDs, diagnostic
properties, snapshots, and remote control are separate additions.

## AccessKit evaluation

| Option | Advantages | Costs and questions | Status |
| --- | --- | --- | --- |
| MoonBit semantics → official AccessKit C adapter → Windows UIA | Reuses the platform provider through its published ABI without a custom Rust bridge | Small foreign-thread ownership and ABI boundary; full text patterns and closure-race evidence remain | Adopted for initial production nodes/actions |
| MoonBit semantics → direct Windows UIA provider | Full control of provider behavior and representations | More COM/provider implementation and long-term maintenance; still needs a semantic model | Comparison baseline |
| Use only OS UIA as the development interface | Can test production accessibility from outside | Cannot cover all frame capture, exact input, renderer diagnostics, or internal completion barriers | Supplemental tests only |
| Put MCP directly into the production UI core | Fewer initial process boundaries | Adds protocol, control and diagnostic dependencies to every app | Rejected |

AccessKit is meaningful here only as a low-level adapter: it does not require
adopting egui, GPUI, or a Rust component model. A successful spike must demonstrate
that the adapter can consume the MoonBit model without forcing platform types
into its public API. See the [AccessKit architecture](https://accesskit.dev/how-it-works/).

The initial Windows adapter uses official AccessKit C 0.22.3 (Windows adapter
0.34.0) after a MoonBit attachment experiment and external UIA verification against
the ordinary production window. `Milky2018/moon_accesskit@0.4.1` provides common
and consumer data, not the Windows platform adapter. Direct UIA would also require
COM provider identities, navigation/pattern implementations, threading and event
delivery; it offers no demonstrated advantage for the existing shared model.
The official ABI is therefore selected while text support remains incomplete.

Foreign-thread request ownership uses a bounded C mailbox rather than a MoonBit
GC object or posted owning pointer. The official provider holds a weak context,
but an operation already in progress can retain it during adapter destruction;
freeing the adapter alone is not an admission barrier for our application queue.
See the fixed [platform node implementation](https://github.com/AccessKit/accesskit/blob/accesskit_windows-v0.34.0/platforms/windows/src/node.rs)
and [subclass lifecycle](https://github.com/AccessKit/accesskit/blob/accesskit_windows-v0.34.0/platforms/windows/src/subclass.rs).
The [verification record](../verification/native-accessibility.md) describes the
remaining C boundary, reproducible check and unverified requirements. OS UIA
remains production accessibility; it does not replace development capture or
completion barriers.

Browser accessibility uses a semantic DOM adapter from the same model. Sharing
meaning does not imply a shared native/browser memory layout or identical wire DTOs.

## Development control topology

```text
CLI ------------------+
                      +--> versioned local control client --> development host
MCP stdio adapter ----+                                      |
                                                            v
                                              bounded queue + UI wakeup
                                                            |
                                                            v
                                                 normal UI dispatch
                                                            |
                                             semantic/frame completion
```

The MCP server is an external development process. It adapts a small, versioned
control protocol; the CLI uses the same client and behavior. MCP JSON-RPC does
not become the UI's internal event representation. The stdio adapter keeps protocol
output on stdout and diagnostics on stderr, following the
[MCP transport specification](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports).

Windows named pipes are the initial transport candidate. Validate current-user
ACLs, rejection of remote clients, per-session discovery, timeouts, disconnects,
and multi-window routing before adopting them. Do not expose an unauthenticated
fixed TCP port. A launch-scoped capability and an explicit attach target prevent
accidental control of a different app/session.

The browser can use a development-only host bridge connected by DevTools, with
the same semantic/action contract. Its global hook must be absent from production
bundles. DevTools remains useful for host errors and browser traces even without
that hook.

## Initial command contract

The following are proposed operations, not implemented CLI commands or tools.

| Operation | Contract |
| --- | --- |
| capabilities | Protocol version, supported operations, session/window identity |
| snapshot / find | Semantic nodes and revision; role/name/test ID selectors; ambiguity is an error |
| action | Invoke a declared semantic action on a current node reference |
| input | Send normalized pointer/key/text events through the regular input path |
| capture | Image for a specified presented frame, with pixel size and DPI/scale metadata |
| wait | Await semantic revision or presented frame with deadline and cancellation |

Node references include session, window, node identity, and generation. Reject
stale/recycled IDs rather than operating on an unrelated replacement node.
Commands carry request IDs and return structured errors for stale target,
unsupported action, disabled node, ambiguous selector, queue saturation, timeout,
cancellation, and closed window.

Distinguish accepted, applied, and presented states. A screenshot after a mutation
must wait for its relevant frame; queue acceptance alone is not completion.
Not every semantic update requires painting, so semantic and frame revisions are
separate. Report asynchronous app work as pending instead of claiming global idle.

Background transport threads only enqueue commands and wake the UI thread. They
never update MoonBit state directly or block the UI while waiting for a response.
Closing a scope/window cancels outstanding waits and releases callbacks/resources.
Use bounded message sizes, queues, and diagnostic buffers. Password values and
session capabilities are not exposed in snapshots or routine logs.

Raw key/text injection, semantic actions, and OS accessibility actions are distinct
test modes. In particular, text insertion cannot stand in for a real IME conversion
session or candidate-window test.

## Production exclusion

Use a dedicated development composition/entry point and explicit opt-in build
selection. A release optimization flag is not the security boundary: developers
may need optimized automation builds, and an ordinary debug app should not open
a control endpoint accidentally.

| Production contains | Production excludes |
| --- | --- |
| Semantic model and normal action dispatch | Control listener, attach/discovery capability handling |
| Keyboard/input/focus/IME behavior | Development request queue and protocol handlers |
| OS/browser accessibility adapters | MCP runtime or stdio server |
| Product-required rendering/logging | Dev-only test IDs, inspectors, overlays, capture/log buffers |

Do not rely on a runtime environment variable to disable code that was linked in.
The product dependency graph and build inputs must omit development adapters.
For Rust bridges this may use optional features and separate entry points; for
MoonBit and the browser use separately composed roots/modules. Exact compiler
mechanisms must be proven with the pinned toolchain before becoming a build rule.

The release gate must inspect dependency/link inputs, confirm that no endpoint
or development discovery metadata is created, and verify that the binary cannot
be attached through the development protocol. Symbol/string checks may supplement
these checks but are not sufficient proof by themselves. Accessibility tests must
still pass on the same production artifact.

## P0-H acceptance

1. Produce a small MoonBit semantic tree with Button/TextInput-like data and stable
   identity; compare AccessKit and direct UIA bridge costs.
2. On Windows, inspect that tree and route an accessibility action; verify focus,
   text/selection representation, removal, and window teardown. Record limitations.
3. Through a development entry point, inspect a node, apply a queued action, wait
   for its completion, and reject a stale reference. CLI first; MCP is a thin adapter.
4. Once P0-A draws a real frame, verify capture-after-action and idle wakeups.
5. Build the paired production artifact without the development composition;
   verify dependency exclusion, no attach endpoint, and retained accessibility.

P0-H begins alongside P0-A/B and informs I1. IPC/MCP implementation does not wait
for the full component library, but cannot be called complete before a real host
and the paired production checks exist.
