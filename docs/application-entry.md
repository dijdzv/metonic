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

## External workspace builds

The experimental build scripts run from the Metonic source directory and reuse
its pinned compiler, native assets and generated WebSys bindings. They accept an
explicit consumer workspace; no Git repository is required for the consumer.
The workspace must include the corresponding Metonic modules and prepared
dependencies. Native and browser workspaces select different async adapters and
must remain separate.

WebSys and native dependency preparation flatten the archives' outer directories
to keep staging and generator artifact paths short on Windows. WebSys child Git
processes enable long paths without
modifying global Git settings. This avoids the known nested-checkout failure;
it does not guarantee that every tool supports arbitrarily long directory paths.

For a native consumer, set `METONIC_NATIVE_BUILD` to `application` (debug) or
`application-release`. Set `METONIC_NATIVE_WORKSPACE` to its workspace directory,
`METONIC_NATIVE_PACKAGE` to the entry directory relative to that workspace, and
`METONIC_NATIVE_ARTIFACT` to the fully qualified package name. For example,
`native/main` and `local/my_app/main` identify the entry directory and compiler
artifact respectively. Run `moon run scripts/build-native.mbtx` with the pinned
compiler in the mise environment. Output is under the consumer workspace's
`.metonic-build/native/<profile>/build/<qualified-package>/`. AccessKit DLL and
licenses are staged beside the executable. Set `METONIC_FONT_PATH` to the
prepared `NotoSansJP.ttf` when launching; this build entry does not yet assemble
a standalone Windows distribution.

For a browser consumer, set `METONIC_BROWSER_WORKSPACE`,
`METONIC_BROWSER_PACKAGE` and `METONIC_BROWSER_ARTIFACT` using the same path
conventions, then run `moon run scripts/build-browser-application.mbtx`.
Both JS and WasmGC release artifacts are built. The consumer workspace's
`.metonic-dist` contains `app.mjs`, `app.wasm`, the shared browser runtime,
generated WebSys imports, font and license files. Add the application's HTML
and small `runApplication` entry and serve that directory over HTTP. The
artifact prefix in that entry is `./app`. This path does not build or stage
the P0 application or development diagnostics.

Package paths use slash-separated ASCII letters, digits, dots, underscores and
hyphens; empty, `.` and `..` segments are rejected. These scripts currently
assume Moon's workspace artifact layout and explicit workspace membership.
Pinned consumer dependency installation and relocation verification are still
being established; a successful build against a sibling checkout is not proof
of a reproducible external installation.

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
