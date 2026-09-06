# metonic Architecture

Design revision: 0.3 · 2026-09-06 · Status: technical validation

This document defines the intended architecture. Implemented behavior and test
results are recorded separately in [P0 verification](docs/verification/p0.md).
Examples of future APIs are design sketches, not supported interfaces.

## 1. Goals and boundaries

metonic is a MoonBit-first GPU UI framework and an independently usable typed
RPC library. The first integrated milestone is one MoonBit application running
on Windows and in a WebGPU browser, accepting Japanese input and calling a
MoonBit backend through a typed contract.

| Area | Policy |
| --- | --- |
| Application language | MoonBit for UI, state, components, and backend business logic |
| UI syntax | Existing MoonBit functions, methods, and closures; no JSX or compiler fork |
| Native platform | Windows x64 first; additional platforms need separate verification |
| Browser | WebGPU is a first-class target from the initial experiments |
| Rendering | GPU-rendered standard UI on both platforms |
| State | Fine-grained reactive state and persistent UI nodes |
| RPC | Independent of UI; contract-first with typed input, output, and domain errors |
| gRPC | High-priority optional transport; validated before the component library is complete |
| Development tools | CLI/MCP automation is a first-class development capability |
| Production | Excludes the development control endpoint and instrumentation; retains accessibility |

Rust/C may provide OS, GPU, text, and layout primitives behind explicit bridges.
GPUI, Solid, and Slint are design references, not mandatory runtimes.

Non-goals include React/Solid/Vue compatibility renderers, a DOM/CSS engine,
a custom UI language, arbitrary npm execution, and a bundled Node/Bun/WebView
runtime. External JS integrations and embedded web panels are deferred until a
specific use case requires them. Necessary browser hosting, input DOM, and
accessibility connections remain core functionality.

## 2. Architecture and ownership

```text
MoonBit application
  ├─ components → interaction/semantics → persistent UI nodes
  │                ↑ reactive state          ↓
  │                                    layout / text → scene
  │                                                      ↓
  │                                   Windows GPU / Browser WebGPU
  └─ typed client → contract / codec / protocol → backend

semantic model → native accessibility adapter / browser semantic DOM
development host → command queue → normal UI input/action dispatch
CLI / MCP adapter → development host (development builds only)
```

| Layer | Owns | Must not depend on |
| --- | --- | --- |
| Reactive core | Signals, dependency graph, scopes, scheduling | OS, GPU, DOM, RPC |
| UI core | Persistent nodes, hierarchy, events, semantic state | Concrete Rust or JS object types |
| Interaction base | Focus, keyboard behavior, selection, roles/actions | Product-specific styling |
| Styled components | Theme and visual composition | Direct platform calls |
| Layout/text facade | Measurement, shaping results, text-position conversions | Public native pointers |
| Renderer | Scene order, clipping, GPU resources | Business state and RPC |
| Platform host | Window, normalized input, clocks, wakeups | Application state ownership |
| RPC core | Procedures, typed calls, errors, cancellation | UI, frame scheduling, GPU |
| Resource adapter | Async results connected to reactive lifetimes | Transport implementation |
| Development adapter | Inspection, queued operations, diagnostics | Production entry point |

Ports are responsibility boundaries, not a requirement to publish an empty
package for every layer. Add modules when a working implementation needs them.

## 3. Reactive state and lifetimes

Signal stores state. Memo caches derived values. Binding connects derived values
to node properties. Effect owns external side effects and cleanup. Resource
connects asynchronous work to a scope. These are framework concepts rather than
a language effect-system requirement.

Component construction creates persistent nodes once per instance. Subsequent
state updates invalidate the affected bindings and necessary rendering stages.
Tests must cover dynamic dependency changes, diamond graphs, equality suppression,
batching, untracked reads, cycles, conditional child removal, and cleanup exactly once.

A scope owns subscriptions and tasks. Disposing it prevents subsequent writes.
Async completions carry request identity/generation so superseded responses cannot
overwrite newer state. Worker threads enqueue results; only the UI thread mutates
UI state. Cancellation is an explicit outcome, not proof that external work stopped.

Platform event loops own blocking waits. The host wakes the UI thread for input,
task completion, and development commands. A second runtime must not block the
same thread. Callbacks do not hold locks across reentrant UI work.

## 4. Scene, layout, and rendering

Track style/paint, layout, text-shaping, and semantic invalidation separately.
A color change must not require reshaping text. Layout invalidation propagates
to ancestors only when their measurements depend on the changed child.

The initial scene supports rectangles, clipping, colors, simple transforms, and
ordered drawing. Extend it to glyphs and images with explicit resource ownership.
Handle resizing, DPI/DPR, minimization, device loss, and resource release.

Native and browser implementations consume the same scene meaning. The browser
must not be an empty or simulated renderer. Prefer batched, explicitly defined
numeric/byte transfers over per-node FFI. Copy counts and transfer costs are
measured; zero-copy is not assumed.

Performance claims require environment, build mode, workload, and measurements.
First verify recomputation counts and correctness, then real rendering latency.

## 5. Platform implementation choices

### Windows

Use MoonBit native plus a low-level C ABI bridge. Compare a Rust wgpu wrapper
with wgpu-native before adopting one. winit is a window/event-loop candidate,
not a renderer or a complete input framework.

Verify the C ABI and event loop on Windows. Do not assume a compiler target name
proves callback ownership or representation compatibility. Runtime and distribution
dependencies must be recorded separately from build tools.

### Browser

Compare MoonBit WasmGC plus a small JS host with MoonBit JS output. State has one
owner in the selected application target; the JS host owns browser resources,
not a second reactive graph. A separate MoonBit-to-JS host build is optional.

Compare initialization, async errors/callback lifetimes, transfer sizes, text
integration, and deployment assets. Do not assume MoonBit and a separate Rust Wasm
module share a heap or C ABI.

The host handles secure-context/WebGPU availability and displays initialization
failures. Request animation frames when work is dirty; avoid perpetual polling
for a static screen. Input DOM and semantic DOM are permitted even though standard
visible components are GPU-rendered.

## 6. Text, input, and accessibility

Text rendering and text editing share a coherent position model but have separate
responsibilities. Compare suitable shaping/layout engines, font loading, fallback,
glyph caching, and their native/browser bridges. Record font licenses.

Every text offset states its unit: UTF-8 bytes, UTF-16 code units, Unicode scalars,
grapheme boundaries, or glyph positions. Conversion tests include Japanese, emoji,
surrogate pairs, and combining marks. Selection and composition ranges must not
silently mix units.

Windows input is an OS integration. Browser input compares EditContext with a
textarea-based bridge. Test Japanese composition, commit/cancel, Enter during
composition, selection, candidate placement, DPI changes, clipboard, and keyboard
navigation. Synthetic text insertion does not count as a real IME test.

The MoonBit interaction/semantic model is the source of truth for role, accessible
name, value, enabled state, focus, actions, and hierarchy. It is shared by production
accessibility and development inspection, without requiring identical wire formats.

**AccessKit is a candidate, not an adopted dependency.** Compare a thin Rust
AccessKit adapter with a direct Windows UI Automation provider. Browser semantics
will use a DOM/accessibility adapter. Measure bridge complexity, text selection,
action dispatch, focus events, tree updates, and lifetime behavior before selecting.
See [ADR 023](docs/adr/023-development-automation.md).

Accessibility remains enabled in production. Removing MCP support must never
remove keyboard interaction, semantic nodes, or the OS accessibility provider.

## 7. Components

Separate interaction primitives from themed components. Start with Button,
TextInput, Checkbox, Tabs, ScrollArea, Dialog/Overlay, and VirtualList.
Each includes disabled/focus states, keyboard behavior, and semantics.

Provide a consistent theme, examples, a working gallery, and extension rules.
Changing style must not break input behavior. Virtualization must preserve focus
and stable identity. Standard components must not require each application to
reimplement IME, focus, or accessibility.

## 8. Typed RPC

Applications place public contracts in `backend/api`. Frontends import that
package, never backend handlers, storage, secrets, or server startup code.
UI/RPC libraries do not contain sample application business contracts.

A procedure ties Input, Output, and DomainError to stable metadata. Begin with
unary calls and explicit registration. Later stream APIs remain distinct rather
than hiding stream shape behind string flags.

Contracts contain data/schema information, not executable handlers or sessions.
Server binding checks all three types. Network decoding and runtime validation
remain necessary even when frontend and backend share source types.

Start with HTTP/JSON while independently validating gRPC. Define protocol version,
procedure ID, content type, size limits, deadlines, cancellation, and known/unknown
error behavior. Distinguish domain errors, remote status, unavailable, timeout,
cancelled, decode/protocol failure, and unsupported capabilities.

Specify absent vs optional fields, unknown fields, integer range, enum evolution,
dates, and bytes. Preserve 64-bit values without JavaScript Number rounding;
string identifiers are the initial default.

The Resource integration is a separate adapter. It must discard stale results
without making RPC depend on the UI runtime.

## 9. Protobuf and gRPC

For gRPC endpoints, `.proto` is the wire-schema source of truth; generate DTOs
rather than hand-maintaining field numbers twice. Test a fixed generator version
and interoperation with an existing implementation.

Keep contract, schema/codec, protocol, and network carrier distinct. Protobuf
generation alone is not a working gRPC runtime. Validate method/service mapping,
framing, status, metadata, deadlines, cancellation, and size limits.

Compare a native implementation such as a tonic bridge and browser Connect or
gRPC-Web. Record whether a server adapter or proxy is required. Prefer a generic
byte/metadata bridge over a handwritten Rust FFI function for every application API.

Unary interoperability is the first gate. If server streaming is added, test
midstream errors, slow consumers, cancellation, and cleanup. Client/bidirectional
streaming is not an initial release requirement. Builds without gRPC must remain valid.

## 10. Development CLI/MCP

Development automation is designed alongside the UI host rather than added after
components are complete. The CLI and MCP process share a versioned command model.
They inspect and act through the app's development adapter.

The adapter exposes stable node references, snapshots, semantic actions, raw input,
and screenshot/frame synchronization. Commands are applied through the normal UI
dispatch path. It does not mutate business state directly.

An OS accessibility client alone is insufficient as the complete automation API:
rendered-frame capture, precise input, and diagnostic synchronization need an
explicit host connection. Conversely, an internal action test does not prove
that an OS accessibility provider works.

Development integration requires an explicit build selection and an explicit
session at launch. Production entry points must not import/link the listener,
dev command queue, MCP adapter, test-ID registry, or diagnostic capture. The
production gate checks dependency/build inputs as well as endpoint absence.
Detailed protocol and security constraints are in ADR 023.

## 11. Roadmap and acceptance gates

| Stage | Acceptance |
| --- | --- |
| P0-A Native GPU | Window, rectangle, input, resize, shutdown through the chosen bridge |
| P0-B Browser GPU | Real WebGPU path and WasmGC/JS comparison |
| P0-C Async | Non-blocking completion, cancellation, stale/disposed result handling |
| P0-D Contract | Contract-only FE build; wrong input/output/error rejected |
| P0-E Protobuf/gRPC | Generated DTO interop; native/browser protocol decision |
| P0-F Text | Japanese/Latin shaping and rendering with explicit position units |
| P0-G IME | Browser composition, selection, candidate position on real systems |
| P0-H Semantics/devtools | Accessibility bridge comparison; dev control and production exclusion experiment |
| R1 Reactive core | Deterministic dependency/lifetime tests without GPU or OS |
| G1 Renderer | Shared scene rendered correctly on Windows and browser |
| T1 Text/layout | Mixed-script layout and editing-position consistency |
| I1 Input/a11y | Real Japanese IME, keyboard navigation, Narrator/browser checks |
| C1 Components | Theme/gallery/extensions with interaction tests |
| N1 HTTP/JSON | Typed calls across processes including failure/cancel scenarios |
| N2 gRPC | Existing-client/server unary interoperability and optional build |
| A1 Distribution | One app on both platforms, complete assets, clean-environment launch |

P0-H begins before the renderer/interaction interfaces are fixed. It does not
block independent RPC work. N2 does not wait for C1. GUI tests that cannot run
are recorded as unexecuted, never passed.

## 12. Evidence and decisions

Record toolchain versions/commits, dependencies and licenses, commands, results,
unexecuted tests, and next acceptance criteria. ADRs contain context, alternatives,
decision status, consequences, and evidence.

The current implementation is smaller than this architecture. Refer to
[verification](docs/verification/p0.md) and [issues](https://github.com/dijdzv/metonic/issues)
for actual progress. Architecture revisions are not product release versions.

Technical references: [MoonBit](https://docs.moonbitlang.com/),
[wgpu](https://github.com/gfx-rs/wgpu),
[wgpu-native](https://github.com/gfx-rs/wgpu-native),
[AccessKit](https://accesskit.dev/how-it-works/),
[EditContext](https://www.w3.org/TR/edit-context/),
[Protocol Buffers](https://protobuf.dev/programming-guides/proto3/),
[Connect](https://connectrpc.com/docs/web/choosing-a-protocol/).
