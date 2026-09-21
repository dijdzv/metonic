# Application entry

`core/application.Application` is an experimental platform-independent entry for
text, button and input views. It contains the semantic editor,
default input reference, initial size, initialization, view, activation, resize and disposal
callbacks. A view supplies `Control` values with a common view element and kind.
The application owns its model and semantic references; it does not own GPU
devices, raster engines or platform input listeners.

`examples/notes/application.Model::application` is a minimal implementation.
Windows uses `native_host/application.from_application` to adapt it to the
existing window host. It is not a stable public package release.

Initialization and activation return an optional `core/application_task.Request`.
The host owns execution and cleanup; the application supplies the typed work and
the completion that updates its model. Returning `None` permits synchronous
changes without starting work. Requests share one replace/cancel lane per host;
independent concurrent application operations are not provided by this entry.
Expected failures should be returned as typed work results and displayed by the
application. Rendering must not start storage or network operations.

The browser driver rejects submissions after closure or when its bounded queue
is full. Replacement invalidates earlier results and awaits active work cleanup
before preparing new work. A completion delivered before replacement or closure
is rejected if applied afterward. Stop prevents further application mutations
and requests cancellation; the asynchronous driver returns after owned cleanup.
This does not promise that a browser page exit waits for pending storage writes.

`stop` invalidates application state synchronously and must be idempotent.
`dispose` is a separate asynchronous callback invoked once after host-owned
application work has ended, including failed startup and task failure paths.
Release stores and other resources that active work may still use in `dispose`,
not `stop`. Hosts protect disposal from cancellation. Browser shutdown requests
this cleanup asynchronously; navigation or process termination cannot guarantee
that it finishes. Storage must not rely on page-exit cleanup to save edits.

`can_close` is the application's close policy. Native close requests and the
browser Stop action consult it before stopping. Return false while unsaved edits
or an in-flight save require attention; provide an explicit save/retry/discard
operation so users can resolve that condition. Browser navigation also installs
a `beforeunload` handler, requesting the browser's confirmation when close is
refused. Browser policy can suppress that prompt, and forced termination cannot
be vetoed. Fatal host failures and an already-committed page exit still perform
unconditional cleanup.

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

Each render synchronizes a bound button's DOM text and disabled state from its
semantic node. Use `semantics.set_name` when a reusable control represents a new
item; this preserves its identity, focus and input selection while invalidating
the accessibility tree. Update the view's displayed text alongside its semantic
name. Bound buttons must be `HTMLButtonElement` elements and contain plain text;
the host replaces their text content.

Button activation focuses the target before calling the application. An
application may then focus another semantic control (for example the editor of
a newly selected item); the browser host reflects that focus in its DOM binding.

Each raster layer supports dimensions from 1 to 1024 pixels on either axis.
The native surface currently accepts at most 16 layers per frame. Applications
must keep their visible controls within these bounds; these are resource limits,
not a limit on how many records an application can store.

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

`native_host/snapshot_store` stores one opaque snapshot in an application-selected
directory. It holds an exclusive writer lock until `Store.close`, bounds reads
and writes to 1 MiB, writes a sibling staging file with file synchronization, and
replaces the live snapshot only after staging succeeds. A missing snapshot is
distinct from an IO failure. The application owns serialization, its storage
directory and user-visible recovery; this package does not interpret memo data.

The caller must finish or cancel and await outstanding IO before closing the
store. Concurrent calls and premature close are rejected. A failed or canceled
save may leave `snapshot.pending`; it is replaced by the next save under the
writer lock. This mechanism protects against truncating the last snapshot during
staging, but does not claim power-loss durability of directory metadata or support
for noncooperating writers. Close the store in the application's `dispose`
callback, after host-owned work has ended.

`browser_host/app/snapshot_store` exposes `load(key)` and `save(key, text)` on JS
and WasmGC, returning `Result` for storage access and write failures. It uses
the current origin's localStorage through generated WebSys bindings. A missing
key returns `Ok(None)`; access denial is an error. The application owns the key,
serialization, versioning and retry policy. Calls are synchronous and intended
for small snapshots; use them inside the application's task adapter, not its
view callback.

Browser storage belongs to a browser profile and origin, so changing the host or
port changes the visible data. Private browsing, site-data removal, browser
retention policies and quota limits affect availability. A successful write means
localStorage accepted the value, not a backup or a power-loss durability promise.
This API does not coordinate competing tabs: the latest successful write wins.
Applications requiring concurrent editing must add conflict detection or use a
storage backend with the required transaction contract.

Input is limited to 1024 UTF-16 code units and the existing raster layer limits
apply. Native still requires a live default input. The browser configuration
does not dynamically create DOM controls or provide a general layout system.
Application-visible unexpected task failure reporting remains under development.
The portable task entry alone does not establish durable saving or recovery;
applications must connect a storage backend and handle its returned failures.

The Notes owned-window probe and browser JS/WasmGC gate exercise the same
application definition. Browser checks cover actual rendered edits, selection,
activation, resize, stopped input, stopping during initialization and stopping
an additional instance without affecting the running application. The artifact
exports only `create`; P0/development-exclusion guards remain required. These
checks do not establish physical IME acceptance.
