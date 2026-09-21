# Application entry

`core/application.Application` is an experimental platform-independent entry for
synchronous text, button and input views. It contains the semantic editor,
default input reference, initial size, view, activation, resize and disposal
callbacks. A view supplies `Control` values with a common view element and kind.
The application owns its model and semantic references; it does not own GPU
devices, raster engines or platform input listeners.

`examples/notes/application.Model::application` is a minimal implementation.
Windows uses `native_host/application.from_application` to adapt it to the
existing window host. The richer native task/action interface remains available;
asynchronous persistence and its application notifications are not yet represented
by this first portable entry. It is not a stable public package release.

## Browser entry

Export one `create` function returning `application_host.Instance`. Pass the
application, stable semantic-reference-to-element-ID bindings, canvas ID, refresh
event name and font URL/SHA-256 to `application_host.create`. The returned opaque
host instance contains the rendering callbacks consumed by the shared browser
runtime. Its JS object boundary uses typed FFI callbacks rather than exposing
MoonBit record layouts. Application code does not implement GPU forwarding.

The HTML supplies accessible, initially disabled input and button elements.
Bindings and input kinds are fixed at startup. Changing text, geometry and button
availability is supported; adding or replacing input nodes requires a new host
instance. Give each running surface its own elements and refresh event name.

The small browser entry calls `runApplication` from `runtime/application.mjs`
with the artifact prefix, element IDs, refresh event name and button actions.
An action is an index into the stable binding array, not the current view order.
The host checks that the bound reference still represents an enabled button in
the current view before invoking the application. Inputs retain per-field
composition preview and scroll state, separate from committed semantic text.

The runtime owns GPU acquisition, artifact loading, font installation, frame
submission, DOM button listeners, resizing and shutdown. The MoonBit host owns
input sessions, raster layers, GPU resources and application disposal. Startup
and disposal use the existing surface and input ownership rules. Stop is
idempotent; a stopped instance rejects another font request and returns failure
for start, resize, rendering and activation. An instance is not restartable.

## Current limits and verification

Input is limited to 1024 UTF-16 code units and the existing raster layer limits
apply. Native still requires a live default input. The browser configuration
does not dynamically create DOM controls or provide a general layout system.
Persistence, application task notifications and external dependency preparation
remain separate work; this entry removes host duplication before those features
are added.

The Notes owned-window probe and browser JS/WasmGC gate exercise the same
application definition. Browser checks cover actual rendered edits, selection,
activation, resize, stopped input, stopping during initialization and stopping
an additional instance without affecting the running application. The artifact
exports only `create`; P0/development-exclusion guards remain required. These
checks do not establish physical IME acceptance.
