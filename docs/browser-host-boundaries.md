# Browser host boundaries

The browser module provides JS and WasmGC implementations through generated
WebSys bindings. The module root is the P0 sample adapter. Applications import
the reusable subpackages rather than importing that root or implementing the
sample's export list. These are experimental workspace APIs, not published
package names.

| Package under `local/browser_host/` | Responsibility |
| --- | --- |
| `input_binding` | Register supplied input elements and editing callbacks; own event listeners, composition state and pending animation frames |
| `gpu_renderer` | Own scene/text resources and frame submission in an explicit `Session`; accept caller-supplied layer dimensions and counts |
| `http_transport` | Implement the bounded POST `Http` contract; expose shared response/stream operations used by resource loading |
| `clock_driver` | Implement the production `Clock` contract and explicit cancellation using browser timers and official async wakeups |
| `font_loader` | Fetch and verify a font from a configured URL and SHA-256; own replacement and cancellation per loader |
| `dom_view` | Position supplied HTML elements relative to an anchor using common view bounds |

The dependency guard in `scripts/verify-host-boundaries.mbtx` traverses these
packages and rejects dependencies on `examples/p0`, its native adapters, or the
P0 browser entry. The P0 adapter retains fixed element IDs, user-load
orchestration, diagnostic exports and its view-to-element mapping.

`browser_host/runtime/surface.mjs` owns browser GPU acquisition, canvas backing
size/DPR configuration, resize observation and requested animation frames. Its
callbacks supply application rendering and resize behavior; it does not inspect
an application model or require P0 exports. Dispose it after releasing application
rendering resources. Disposal cancels pending frames and observers, unconfigures
the canvas and destroys the owned device. A device returned after disposal is
destroyed without being exposed to the application.

`browser_host/runtime/wasm-imports.mjs` constructs the generated WebSys runtime
and the remaining document/window, Promise and console imports. Both files are
shared browser host code extracted from the existing JS adapter; application
state and editing remain in MoonBit. The development and release packagers include
the same runtime files. The P0 loader separately validates its sample exports.

`layer-renderer.mjs` handles raster-layer transfer, upload batches and per-layer
GPU recording through supplied callbacks. P0 and the [Notes example](notes-example.md)
provide their own model-to-layer adapters; neither copies that transfer loop.

## Ownership

Create an input session from application-provided `Binding` values. Each binding
owns an element and callbacks for focus, scroll, composition and committed edits.
Stopping the session removes its listeners and cancels pending frame callbacks.
The application owns its semantic model and decides how edits affect it.

Create a GPU session per rendering owner. Text uploads form a pending batch:
add consecutive layers, then commit with the expected count, or abort the batch.
Layer dimensions are limited to 1024 by 96 pixels. Frame begin, recording and
submission belong to the same session. Applications remain responsible for
surface/device ownership and invoking disposal when they stop.

The current HTTP transport and Clock driver are operation-scoped. Construct a
fresh transport per exchange and a fresh driver per delay/deadline; do not share
them across concurrent operations or reuse a completed/cancelled operation.
Transport cleanup aborts its request and cancels/releases an owned stream reader.
Clock cancellation wakes its waiter through the official async scheduler. These
objects do not provide a separate scheduler or application task registry.

A font loader is reusable. `create(url, sha256)` rejects an empty URL or a digest
other than 64 lowercase hexadecimal characters. `fetch()` replaces that loader's
previous request; `cancel()` invalidates the pending request, including results
arriving after cancellation. Different loader instances hold separate pending
requests. Each download has a 16 MiB limit and must match SHA-256 before its bytes
are returned. The loader does not select a font family, install a raster engine,
or modify an application model.

DOM placement takes actual elements, bounds and optional class names. The caller
owns element creation, accessible labels, event routing and styles. Placement
does not infer application actions from IDs.

## Backend boundaries

WebSys supplies DOM, Fetch/Streams, WebCrypto and WebGPU conversions. Small host
imports provide document/window access and Promise settlement on WasmGC. The
experimental async dependency does not yet expose the same Promise-returning
entry as its JS implementation; the font loader retains that settlement bridge.
Both backends expose a typed Promise of ArrayBuffer for font loading.

The JS HTTP helper needs the official async AbortController type; WasmGC accepts
an abort callback. The HTTP package narrowly disables unused-import warning 29
because imports cannot be selected per backend like its source files can.
The identity conversion preserves the same underlying controller so cancellation
reaches the Fetch request.

## Verification scope

The maintained browser headless suite exercises these boundaries through the P0
adapter on JS and WasmGC, including input callback lifetime, GPU lifecycle,
request/font failures, cancellation and production artifacts. It does not prove
physical IME behavior. The Notes consumer additionally exercises configured
elements, text-only GPU rendering, resize and shutdown on both backends, including
stopping during asynchronous device/font acquisition. A separate GPU probe holds
two sessions on one real device, disposes one while frames are pending and checks
that the other can still submit without WebGPU validation errors. Probe artifacts
are included only in the development test staging, not P0 or Notes packages.
