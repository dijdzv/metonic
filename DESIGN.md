# metonic Architecture

Design revision: 0.3 · Boundary policy updated 2026-09-22 · Status: experimental application foundation

This document defines the intended architecture. Implemented behavior and test
results are recorded separately in [P0 verification](docs/verification/p0.md).
Examples of future APIs are design sketches, not supported interfaces.

## 1. Goals and boundaries

metonic is a MoonBit-first GPU UI framework. Its application foundation targets
Windows and WebGPU browsers, including Japanese input, persistent application
state and explicit host/resource ownership. Contract/RPC packages support
optional integrations; a backend or RPC service is not required by an application.

| Area | Policy |
| --- | --- |
| Application language | MoonBit for UI, state, components, and backend business logic |
| UI syntax | Existing MoonBit functions, methods, and closures; no JSX or compiler fork |
| Native platform | Windows x64 first; additional platforms need separate verification |
| Browser | WebGPU is a first-class target from the initial experiments |
| Rendering | GPU-rendered standard UI on both platforms |
| State | Fine-grained reactive state and persistent UI nodes |
| RPC | Independent of UI; contract-first with typed input, output, and domain errors |
| gRPC | Deferred optional transport; not a prerequisite for the application foundation |
| Development tools | CLI/MCP automation is a first-class development capability |
| Production | Excludes the development control endpoint and instrumentation; retains accessibility |

Rust/C may provide OS, GPU, text, and layout primitives behind explicit bridges.
GPUI, Solid, and Slint are design references, not mandatory runtimes.

Before adding a bridge, compare existing MoonBit implementations and bindings for
the required target. Preserve working baselines while evaluating replacements;
see the [library reuse evaluation](docs/verification/library-reuse.md) for pinned
candidates, executed checks and remaining acceptance criteria. Candidate lists do
not constitute adoption decisions.

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

[ADR 035](docs/adr/035-reactive-graph-ownership.md) fixes the Phase 3 graph
ownership and scheduling boundary for persistent UI nodes; the consumer and
performance acceptance remain separate from the core package.

[ADR 038](docs/adr/038-standard-ui-components.md) defines the staged standard
control contract over those same scopes and the existing host event boundary.
It specifies fixed and keyed owners, controlled input, semantic roles, and
shared style before exposing the first widget group.

A scope owns subscriptions and tasks. Disposing it prevents subsequent writes.
Async completions carry request identity/generation so superseded responses cannot
overwrite newer state. Worker threads enqueue results; only the UI thread mutates
UI state. Cancellation is an explicit outcome, not proof that external work stopped.

Shared resource contracts and environment-specific APIs follow
[ADR 033](docs/adr/033-capability-platform-boundaries.md). A shared capability
requires shared meaning and guarantees; platform-only APIs need no dummy
implementation on another host. Build targets, execution environments and runtime
permissions are separate concerns.

External dependencies can be expressed as small capability traits independently
of reactive effects. Delayed operations use `capabilities/clock`; hosts supply real
time and `async_runtime/clock` supplies virtual time for tests. Both retain the
same task ownership and stale-result checks. [ADR 031](docs/adr/031-clock-capability.md)
defines this boundary; it does not introduce a global Runtime or effect scheduler.

User loading depends on `capabilities/http`, with deadline composition supplied by
`async_runtime/http`. Native and generated-WebSys adapters own transport resources;
the sample owns JSON and domain semantics in `examples/p0/user_load`.
[ADR 032](docs/adr/032-http-capability.md) defines this bounded exchange and its
verification requirements.

Platform event loops own blocking waits. The host wakes the UI thread for input,
task completion, and development commands. A second runtime must not block the
same thread. Callbacks do not hold locks across reentrant UI work.

## 4. Scene, layout, and rendering

The reusable editing state lives in `core/semantics`, alongside `core/text_position`
and `core/task_scope`. A semantic tree starts empty or from explicit initial nodes;
registration order does not assign special behavior. Composition requires an
explicit target. Restoring a removed input slot issues a new generation, so old
references and in-flight compositions cannot address its replacement.
`examples/p0/semantics` supplies the sample's initial controls, toggle policy and
legacy default-input operations. It delegates editing to the core rather than
implementing a second editor. Windows IMM attribute interpretation belongs to
`platform/windows/ime_presentation`, not the platform-independent editor.

`core/view` defines geometry and application-defined elements. `core/view_renderer`
consumes an ordered list of text or bordered-control items, without importing a
sample model. An explicit retained-item index separates the input layout needed
for hit testing from layer compositing order. The P0 renderer adapter only maps
its view and input presentation to these items; sample labels and layout remain
in the application. See [rendering items](docs/rendering-items.md) for the current
API and bounds.

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

The P0 implementation uses MoonBit native and the existing `wgpu_mbt` binding
over wgpu-native. The project's custom Rust GPU wrapper has been removed; see
the [binding evaluation](docs/verification/wgpu-mbt.md). The window/event loop
and asynchronous ownership are described in
[Windows async integration](docs/verification/windows-async-integration.md).

Verify the C ABI and event loop on Windows. Do not assume a compiler target name
proves callback ownership or representation compatibility. Runtime and distribution
dependencies must be recorded separately from build tools.

### Browser

P0 selects MoonBit WasmGC plus a JS host; MoonBit JS output remains a comparison
target. See the [selection and packaging record](docs/verification/browser-target.md).
State has one
owner in the selected application target; the JS host owns browser resources,
not a second reactive graph. A separate MoonBit-to-JS host build is optional.

Compare initialization, async errors/callback lifetimes, transfer sizes, text
integration, and deployment assets. Do not assume MoonBit and a separate Rust Wasm
module share a heap or C ABI.

The host handles secure-context/WebGPU availability and displays initialization
failures. Request animation frames when work is dirty; avoid perpetual polling
for a static screen. Input DOM and semantic DOM are permitted even though standard
visible components are GPU-rendered.

The [browser host boundaries](docs/browser-host-boundaries.md) separate input,
GPU sessions, HTTP, timers, font resources and DOM placement from sample routing.
Applications own their semantic model and configure these services explicitly.

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

P0 adopts the official AccessKit C adapter for Windows, with MoonBit owning the
semantic model and action handling. Browser semantics use DOM adapters.
Input layout and navigation use [reference-keyed presentation state](docs/input-presentation.md).
The [native application host](docs/native-application-host.md) owns the reusable
window loop; P0 and Notes supply their models, views and actions through adapters.
Asynchronous application work uses [event-thread completions](docs/application-tasks.md)
without exposing application result types to the native event loop.
The native bridge accepts [application-defined presentation](docs/native-accessibility-presentation.md)
for bounds, toggle state, status elements and retained-text ownership. P0 supplies
that mapping through its adapter; the bridge does not recognize sample control IDs.
The [production accessibility record](docs/verification/native-accessibility.md)
documents implemented Value/Text selection and request actions, the C ownership
boundary, and remaining geometry and real assistive-technology acceptance.
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

Start with HTTP/JSON; gRPC and its Protobuf schema/code generation remain optional.
The comparison, tradeoffs and reconsideration criteria are in
[ADR 028](docs/adr/028-rpc-wire-formats.md). Define protocol version,
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
| Optional P0-E Protobuf/gRPC | Separate adapter experiment; not a prerequisite for the standard HTTP/JSON path or P0 completion |
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
