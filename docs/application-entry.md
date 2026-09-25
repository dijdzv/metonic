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

Windows `window_host.run` accepts `minimum_size=Some((width, height))` in
physical client-area pixels. Both dimensions must be positive; omission leaves
the window unconstrained. The host passes this constraint to the window library,
which accounts for the current non-client frame and DPI when Windows queries its
minimum tracking size. Requested client sizes are also clamped to the minimum.
Browser applications set their minimum canvas dimensions and overflow policy in
their page layout; the host cannot constrain the browser window.

Native builds place the default font and its OFL notice in `assets/` beside each
window executable. The host resolves `assets/NotoSansJP.ttf` relative to the
running executable, so moving the bundle or changing the working directory does
not change resource lookup. Applications can pass `font_path=Some(path)` to
`window_host.run`; this takes precedence over `METONIC_FONT_PATH`, which remains
available for development and existing launchers. An explicit path is used as
given, and a missing font produces a path-specific error rather than falling back
to a different font. Include the complete asset directory when copying a build.

`native_host/resources.asset_path(relative)` resolves other bundled files from
the same executable directory. It accepts relative paths with either Windows
or forward separators and rejects rooted paths, drive/stream prefixes, empty
components and `.`/`..`. It does not change the process working directory or own
application data storage. Its executable path comes from
[GetModuleFileNameW](https://learn.microsoft.com/en-us/windows/win32/api/libloaderapi/nf-libloaderapi-getmodulefilenamew),
with retry on a truncated buffer; the pinned core/async APIs do not provide this
query. This is a Windows FFI boundary implemented in MoonBit, not a C helper.

`mise run native:notes-test` includes a relocated owned-window check under a
Unicode directory with an unrelated working directory and no font override. It
checks rendering/editing/cleanup and the missing-font diagnostic. The release
lifecycle probe also accepts `METONIC_RELEASE_EXECUTABLE` and
`METONIC_RELEASE_TITLE` to verify a copied external application's start and close;
it still selects only a window belonging to its owned child process. These checks
do not replace the complete dependency/license inventory required for packaging.

Initialization, activation and committed text edits return an optional
`core/application_task.Request`.
The host owns execution and cleanup; the application supplies the typed work and
the completion that updates its model. Returning `None` permits synchronous
changes without starting work. Create and retain a `core/application_task.Operation`
for each independently replaceable operation (for example, saving and searching),
then pass it as `operation` to `replace` and `cancel`. Omitting it retains the
legacy single operation. Allocate a new identity for a newly owned component;
do not create a fresh identity for every replacement of the same operation.
Expected failures should be returned as typed work results and displayed by the
application. Rendering must not start storage or network operations.

One callback can return `Some(@task.group(requests, batch, on_admitted~))` to
admit multiple independent operations together without changing the existing
`Request?` callback shape. Each member needs its own `Operation` identity;
two requests using the legacy default identity in one group are rejected.
Supply `batch` as `apply => graph.batch(apply)` when the invalidations or
`on_admitted` update reactive state. The callback runs after all member
invalidations, inside that same batch, so it can publish a shared request cycle.
The Driver checks closure, command/lane capacity, duplicate identities and
nested groups before accepting any member. Rejection leaves all member state
unchanged; accepted work runs and cancels independently. The group has no
operation identity or direct Work of its own. Its `on_prepared` acknowledgement
runs once after every member has prepared or retired, including closure before
preparation. Existing single requests retain their behavior.

`Application.connect_tasks` receives a host-owned `TaskControl` exactly once
before `initialize`. An application with no scoped asynchronous resources may
use `connect_tasks: _ => ()`. The control exposes only
`cancel(operation)`: it can invalidate one existing Driver lane without
submitting a Request, including when the Request queue is full. It is safe to
call during shutdown, when the lane may already be gone. The application must
invalidate its own model state separately, and may release resources requiring
joined cleanup only in its later async `dispose` callback. Browser and native
hosts keep normal Request admission, result delivery and input gates.

`core/reactive_task.Resource` is an optional, Scope-owned adapter for one
replaceable operation. Create it under the component's `core/reactive.Scope`,
connect the host control once in `connect_tasks`, and return its `replace`,
`replace_prepared` or `cancel` Request from an application action. The adapter
does not submit or run work. `replace_prepared` accepts a Work-producing
callback when the application must prepare typed work after earlier cleanup;
`replace` covers the common async result-and-apply case. A proposed Request
does not invalidate current results until the host admits it. Accepted
replacement or cancel, and Scope disposal, reject stale results and failures.
On disposal the adapter asks the host to cancel its Operation immediately;
the Driver still owns asynchronous cleanup and joining. Keep separate Resource
instances for independent lanes such as search and save. A Resource does not
substitute for capability ports, which describe external services.

`core/reactive_task.Source[K, V]` adds a keyed observable state over one
Resource. Give independently fetched values separate Sources in the component
Scope, connect each to the same host `TaskControl`, and mint one opaque
`Cycle::new()` for a coordinated selection or refresh. Pass that cycle to both
`replace` proposals, then return their requests as one `@task.group` with
`apply => graph.batch(apply)`. Check that both proposals exist before making
the group. The group's `on_admitted` callback can publish the selected key and
cycle in the same batch; a rejected group changes neither source. Each source
exposes `Idle`, `Pending`, `Ready`, `Failed` and `Canceled`. A same-key refresh
can retain an earlier ready snapshot; a changed key cannot retain it. The
`derive_pair` function returns a current pair only when both Sources are ready
for the selected key and cycle, and retains a previous pair only when its two
snapshots share one earlier cycle. It also exposes failed/canceled/pending
presentation without launching work from a Memo. `replace_with_progress`
forwards posted completions through the same Resource generation and host
application boundary; progress callbacks must update state only when applied
there. Explicit `Source.dispose` marks pending work canceled before disposing
its child Resource. Parent Scope disposal rejects later callbacks without
writing an already disposed Signal. Use Source for replaceable presentation
results; a successful storage write remains an external fact even if the UI
request becomes stale. Match its saved revision before changing an unsaved
indicator instead of treating cancellation as a rollback.
The [paired async application](../examples/async_pair/application/application.mbt)
shows the same public model on native and browser hosts; its
[verification record](verification/async-pair-phase4.md) includes visible
pending, retained, failed, retried and canceled states.

For related Sources, create one `Related[K]` from the expected typed key and
Cycle, then read each Source through that contract and call `join_related`.
The join checks that both inputs have the same key and Cycle; this can be
chained for three or more related Sources. Call `RelatedCurrent::current` to
obtain a `Current[T]`, then use `join_independent` to add Sources with their own
keys and Cycles. `Source::current` provides the typed projection for each
independent Source. `Current::map` and either join can be composed through
multiple Memo stages. `Current::view` reports Idle, Blocked, Pending, Ready,
Failed and Canceled with the active per-input causes.

Every intermediate `Current` retains the leaf observations, including Ready
origins while other inputs are incomplete. Consequently grouping nested joins
does not change their phase or causes. Different admissions or state revisions
of the same Source cannot form one Ready value, even when payloads and visible
keys compare equal. A proposal that is never admitted does not change the
origin; Source recreation creates a new identity. These operations are pure:
place them in Memos, and read a conditional Source only in the selected branch.
A previous Source snapshot never becomes current Ready. The [Phase 5 quote-board
contract](adr/037-phase5-external-quote-board.md) uses related item detail/stock
A+B and an independent currency C to exercise this distinction.

For a whole-display snapshot, create one `PublicationRegistry` under the
application's root Scope and pass `publications: Some(registry)` to
`Application`. Register each live display with
`registry.register(component_scope, () => (semantic_demand, current))`.
The host calls `Application::publish()` after it has applied input or task
state and before rendering; the application should read `Publication::get()`
in its view. Before the first round it returns `None`. Thereafter the result
has a `current` phase and an optional earlier *complete* `previous` value
with its original provenance. Previous is available only while the semantic
demand matches; include item, quantity and conditional currency branch in
that demand, but exclude an incidental refresh Cycle. Changing the demand
clears history, including if the user later returns to the old demand.

The registration callback must be a pure, synchronous derivation. It cannot
start work, write Signals or read any Publication output. Two registered
displays are sampled first and committed together in one graph batch, so
observers do not see half of a publication round. `K` and `T` must be
immutable or copy-owned: the registry cannot deep-copy arbitrary MoonBit
application values. Dispose the component Scope and stop reading its
Publication when that component is removed. Downstream request admission
and keyed component ownership remain separate Phase 5 tasks.

Both hosts use the shared operation driver. Replacement invalidates earlier
results for that identity synchronously when admission succeeds, then awaits its
active cleanup before preparing new work. The canceled model state is visible
at admission, before resource cleanup finishes.
Other operations and the native event loop can continue during that wait.
Native control commands await their own preparation (including preceding cleanup)
and the queued redraw before returning a snapshot; they do not await work completion.
The driver's optional `on_prepared` callback runs once for an accepted submission
after preparation or retirement by replacement/closure. Rejected submissions
do not invoke it. Acknowledgement alone does not mean that work succeeded.
Cancellation keeps the identity reusable; removing a component must cancel its
owned operations and invalidate its model references. Independent operation
identities do not automatically infer semantic-node ownership. The host-owned
`Driver.cancel_operation(operation)` invalidates that lane immediately and
requests cancellation of running work without occupying a Request slot. It
returns false when the lane is absent or the driver is closed. It does not run a
Request's model-invalidation callback: the owner must invalidate component
state separately. The call does not wait for cleanup; the lane retires only
after cleanup, and a new request for the same Operation waits for it.

Submissions are rejected after closure or when capacity is exhausted: at most
16 commands awaiting preparation and 16 operation slots are retained. Running
work releases its command slot. A queued completion holds its operation slot
until applied, superseded or explicitly canceled through the driver, so a host
that stops consuming results cannot accumulate unlimited identities. Rejection
does not invoke invalidation or prepare work. Both hosts report capacity exhaustion
through `input_error`; browser activation also returns rejection.

A completion delivered before same-operation replacement or host closure is
rejected if applied afterward. Applying it consumes it once. An unexpected work
exception is delivered as `Outcome::Failed(message)` without terminating unrelated
operations. `replace` accepts `on_failure` to update application state on the host
event loop; stale failures do not invoke this callback. Without a handler, both
hosts report the message through `input_error`. Cancellation does not produce a
failure notification. Unexpected failure messages are diagnostic text, not typed
domain errors or a stable machine-readable error protocol.

`work_with_progress` may post non-terminal completions through the same Driver
result callback while work remains active. A posted progress completion keeps its
operation lane; its application checks the current Driver generation and, when
wrapped by a Resource, the owning Scope. The host decides when to apply and draw.
Use this for a state transition between asynchronous stages, not for direct
Signal writes inside the worker or cancellation cleanup.

Stop prevents further application mutations and requests cancellation; the
asynchronous driver returns after all owned cleanup, including superseded work.
This does not promise that a browser page exit waits for pending storage writes.

`stop` invalidates application state synchronously and must be idempotent.
`dispose` is a separate asynchronous callback invoked once after host-owned
application work has ended, including failed startup and host failure paths.
Release stores and other resources that active work may still use in `dispose`,
not `stop`. Hosts protect disposal from cancellation. Browser shutdown requests
this cleanup asynchronously; navigation or process termination cannot guarantee
that it finishes. Storage must not rely on page-exit cleanup to save edits.

`can_close` is a side-effect-free query of the application's close policy.
While IME composition is active, interactive close keeps the editor available
and reports that composition must be finished or canceled before retrying close.
It does not freeze inputs under a live preedit or silently discard that preedit.
Native close requests and the browser Stop action consult it before stopping.
When it returns false, the host calls `close_requested` and redraws the app so
the application can present save/discard/cancel actions. Repeated requests must
not restart a pending save. `close_ready` is a side-effect-free indication that
the application has completed an explicit pending close decision; cancel must
clear that intention. After an application event or task completion, the host
closes only when both `close_ready` and `can_close` are true. Applications which
never defer close can supply no-op `close_requested` and false `close_ready`.
Saving failure must leave the decision pending and preserve the document.
Browser navigation does not invoke the interactive close callback: it installs
a `beforeunload` handler, requesting the browser's confirmation when close is
refused. Browser policy can suppress that prompt, and forced termination cannot
be vetoed. Fatal host failures and an already-committed page exit still perform
unconditional cleanup.

### Committed text edits

`Application.edited` receives `TextEdit { target, text, revision }` after a host
accepts a content change. `target` retains the semantic node generation, `text`
is the accepted content snapshot and `revision` is the tree revision at that
notification. Return a task request to schedule save/search work through the
same operation driver, or `None` for a synchronous model update. Applications
that do not need edit notifications supply `edited: _ => None`.

Keyboard editing, clipboard mutations, native accessibility value edits and
development text-edit commands use this boundary. Selection-only movement,
unchanged text, failed edits and application/model-to-view updates do not emit
notifications. The callback runs after mutation; it is not input validation and
cannot veto an already accepted edit. Rendering remains free of IO.

IME preview does not emit committed edits. At completion or cancellation, a
changed final value emits once. Canceling a replacement can leave the originally
selected range deleted; this is the established input behavior, not restoration
of the old selection. Native intermediate selection removal is withheld until
that composition finishes. Removed/replaced inputs, obsolete composition
snapshots and stopped hosts cannot deliver late edit notifications.
Composition ownership checks the target's identity, content, selection and
enabled state. Updating an unrelated control does not invalidate that input.

The revision describes an event, not a promise that the model will remain at
that revision. Capture the desired save value, use operation-scoped replacement
for debounce, and check current ownership before applying asynchronous results.
Programmatic changes must schedule their own work explicitly; they do not loop
back through `edited`.

### Native text clipboard

Focused, enabled native inputs handle Ctrl+C, Ctrl+X and Ctrl+V. Copy and cut
require a nonempty committed selection. During active IME preedit the host does
not access the clipboard. Cut writes before deleting; a failed write preserves
the text and selection. Paste reads once, leaves the selection unchanged when
there is no text, normalizes CRLF/CR to LF and removes newlines in single-line
inputs. Embedded NUL is rejected rather than silently truncating text.

`Application.input_error` receives `Some(message)` on an editing operation
failure and `None` after a successful clipboard operation. Applications should
display this status without replacing their storage error state. No automatic
retry waits for another clipboard owner; users can retry the operation.
Application-specific content limits remain the application's responsibility.

`window_host.run(clipboard=Some(backend))` overrides the synchronous
`core/text_clipboard.Backend` for tests or embedding. Ordinary applications omit
it and use the native platform backend. The Windows implementation reuses
`moonbit-community/proton_clipboard` 0.3.3 with a
[clipboard ownership correction](../patches/proton-clipboard-window-owner.md).
Native writes use Windows CRLF line endings. The browser continues to use its
DOM input editing path; this API does not grant browser clipboard permissions.

`native:notes-test` checks copy, failed/successful cut, Unicode paste and error
notification through synthetic key messages with an injected backend. These
checks do not read or overwrite the user's clipboard, and do not establish the
production OS clipboard roundtrip.

### Native pointer selection

Text inputs use their retained layout for left-button drag selection. The press
chooses the input and selection anchor; movement and the final release update
the caret without activating controls crossed by the gesture. Shift+press keeps
the existing selection anchor. Dragging outside the input advances the viewport
incrementally while the button remains held, including multiline content.

Capture loss, cancellation, focus loss and shutdown end the gesture. A disabled,
removed or unfocused input, or an externally changed text/selection, invalidates
its ownership. An active IME composition keeps the existing completion-before-
pointer contract: selection never extends through live preedit, and completion
after button release may apply the deferred click but cannot restart dragging.

The vertical mouse wheel scrolls an enabled multiline input under the pointer
without moving its selection or changing its text. Line-based wheel events move
three 32-pixel lines per unit; pixel-based events use their reported distance.
The viewport is clamped to the document. Ordinary redraws preserve a manually
scrolled viewport; editing, selection navigation or a new pointer selection
reveals the caret again. Single-line inputs do not consume vertical scrolling.

`native:notes-test` covers selection, replacement, cancellation and scrolling
with synthetic messages in an owned hidden window. These checks do not establish
physical mouse or IME behavior.

### Shared list layout, clipping and viewport

`core/layout.VerticalList` is the current shared layout primitive. It uses the
pinned `Milky2018/chicle@0.6.1` dependency behind the `core/layout` package;
application code consumes `VerticalList` and `Placement`, not Chicle tree or
style types. `VerticalList::new(row_height~, gap?)` defines one fixed pixel
height and an optional pixel gap. `arrange(viewport, references)` lays out a
single column of equal-height rows that fill the viewport width and returns one
placement per semantic reference, including its bounds and visible intersection.
The list retains and clamps its scroll offset when arranged again. It lays out
every supplied reference; it does not virtualize offscreen rows or provide
general measurement, nesting, or responsive layout.

`core/layout.layout_linear` arranges fixed and weighted fill tracks along a
horizontal or vertical axis. It accepts a container `Bounds`, gap and padding,
then returns one `Bounds` per track. Applications can pass a returned area to
another layout call, including `VerticalList.arrange`, to place an editor beside
a scrolling list. The application chooses when to use a horizontal or vertical
composition; this API does not infer breakpoints from content. The root may be
up to 2048 pixels per axis. The default `areas=Drawable` limits each returned
area to 1024 pixels per axis. Use `areas=Container` for intermediate,
non-rendered areas when nesting calls across a wider window; those areas may
reach 2048 pixels per axis and must be divided before drawing controls. Fixed
tracks do not shrink; fill tracks declare positive
weight, minimum and maximum sizes. Insufficient space returns an error rather
than overlapping controls. This API has no scroll state.

Row height must be 1–1024 pixels and gap 0–1024. The viewport origin must be
nonnegative and at most 1,000,000 on either axis, each viewport dimension must
be 1–1024 pixels, and an arrangement accepts at most 100,000 unique semantic
references. `scroll_at` consumes pixel deltas only when the pointer lies in the
viewport; `scroll` clamps to the content extent. `reveal` scrolls a known row
into view, and `hit` resolves only visible row bounds.

`Control.clip` clips one control to a `Bounds`; `Control.visible_bounds` reports
the intersection. Native rendering crops the raster layer, rejects hits outside
the clip, and publishes clipped bounds to accessibility. The browser managed
host applies the same intersection as a DOM `clip-path`. `Application.viewport`
connects application layout to host input through `scroll(x, y, delta_pixels)`
and `reveal(reference)` callbacks. Native sends unhandled wheel input to the
callback; the browser normalizes wheel deltas to pixels and lets the callback
handle scrolling outside text inputs. Both hosts call `reveal` when semantic
focus changes and redraw the view when it moves the list. Coordinates are native
client pixels on Windows and CSS pixels in the browser.

This is a constrained shared list, not a general layout engine or an automatic
application migration. `examples/notes/application/application.mbt` still emits
explicit bounds and sets `viewport: None`; migration of the independent Notes
application to the shared list remains incomplete.

## Browser entry

Export one `create` function returning `application_host.Instance`. Pass the
application, stable semantic-reference-to-element-ID bindings, canvas ID, refresh
event name and font URL/SHA-256 to `application_host.create`. The returned opaque
host instance contains the rendering callbacks consumed by the shared browser
runtime. Its JS object boundary uses typed FFI callbacks rather than exposing
MoonBit record layouts. Application code does not implement GPU forwarding.

For dynamic views, pass an empty binding array and `root_id=Some("controls")`.
The HTML supplies that container and the canvas, status and Stop elements; the
host creates the view's inputs, buttons and display text. Omit `controls` from
`runApplication`. The container has one active owner and each running surface
needs its own container and refresh event name. Do not mutate host-owned children
or the reserved `data-metonic-owner` attribute from application code.

Interactive controls require unique live semantic references. Their full
session/window/id/generation identity retains DOM, listeners, selection,
composition and scroll across reordering. Changing an existing identity's kind
is rejected; replace its semantic node instead. Anonymous display text has
positional identity and carries no editing state. The host uses DOM `moveBefore`
to preserve input state during moves; browsers must support that operation.
Input and button styling uses the `gpu-input` and `gpu-button` classes shown in
the Notes page. The application supplies bounds to the browser host; it may
derive those bounds from `core/layout.VerticalList` as described above.

Removing an input revokes its listeners and pending composition before DOM
detachment. Late callbacks cannot target a replacement generation. Stop removes
owned children and releases the container. A second instance cannot claim an
active container, and stopping that rejected instance leaves its owner intact.

Omitting `root_id` retains the explicit-binding path: HTML supplies the input and
button elements, and action indices refer to the supplied stable binding array.
Input nodes can enter and leave the view when their bindings already exist;
creating arbitrary DOM controls requires the managed path. Do not combine
managed containers with explicit bindings.

On resize, multiline fields preserve their scroll position. A field scrolled to
the bottom remains at the bottom after its viewport changes; a fully visible,
focused field with its collapsed caret at the end follows that end when it
becomes scrollable. A reader positioned earlier in the text is not moved to the
bottom. The host applies the resulting DOM scroll offset before rasterizing.

Each render synchronizes a bound button's DOM text and disabled state from its
semantic node. Use `semantics.set_name` when a reusable control represents a new
item; this preserves its identity, focus and input selection while invalidating
the accessibility tree. Update the view's displayed text alongside its semantic
name. Bound buttons must be `HTMLButtonElement` elements and contain plain text;
the host replaces their text content.

Button activation focuses the target before calling the application. An
application may then focus another semantic control (for example the editor of
a newly selected item); the browser host reflects that focus after creating any
new DOM binding. An unchanged semantic focus target does not reclaim browser
focus during an unrelated redraw.

Each raster layer supports dimensions from 1 to 1024 pixels on either axis. The
native surface accepts at most 64 raster layers in an installed layer set. On
each submitted native update, the host creates a texture, texture view, shader
module, render pipeline and bind group for every layer, uploads its complete
RGBA8 pixel buffer, then releases the prior set. This makes layer count and area
direct GPU update costs; 64 is a hard ceiling, not a performance target.
`VerticalList` does not enforce this surface limit, and a dense viewport can
produce more than 64 visible rows. The application must keep each native layer
set within the limit. Clipping removes fully hidden raster layers before GPU
installation, but offscreen controls still participate in list layout and can
incur CPU layout and raster work. The browser also uploads each submitted layer
and replaces the old set, but this native 64-layer ceiling is not a browser
limit. These per-layer bounds do not limit how many records an application can
store.

The small browser entry calls `runApplication` from `runtime/application.mjs`
with the artifact prefix, element IDs, refresh event name and button actions.
In the explicit-binding path, an action is an index into the stable binding
array, not the current view order. Managed buttons activate their semantic
reference directly and do not need an application-supplied action index.
The host checks that the bound reference still represents an enabled button in
the current view before invoking the application. Inputs retain per-field
composition preview and scroll state, separate from committed semantic text.

The runtime owns GPU acquisition, artifact loading, font installation, frame
submission, legacy DOM button listeners, resizing and shutdown. The MoonBit host
owns managed DOM/button listeners, input sessions, raster layers, GPU resources
and application disposal. Startup
and disposal use the existing surface and input ownership rules. Stop is
idempotent; a stopped instance rejects another font request and returns failure
for start, resize, rendering and activation. An instance is not restartable.

## External workspace builds

The experimental source entry `scripts/application-source.mbtx` runs from the
pinned Metonic checkout. It accepts a consumer directory without requiring that
consumer to be a Git repository. The consumer supplies `dependency.json` with
the exact Metonic commit and `metonic.application.json` with its own workspace
members and entry packages. Metonic supplies its internal workspace members,
prepares only the selected target's dependencies, and then delegates to its
native or browser builder. Native and browser workspaces select different async
adapters and remain separate. This is source consumption, not a published
package or stable installer.

The source entry also gives each generated consumer workspace a CommonJS
package-scope marker at `.mooncakes/package.json`. The pinned `wgpu_mbt`
dependency runs a CommonJS `.js` prebuild; without the marker, an ESM
application's root `package.json` makes Node interpret that dependency script
as ESM. Metonic does not edit the downloaded dependency package. An existing
workspace marker must already specify `"type":"commonjs"`; conflicting
settings fail preparation instead of being overwritten. Remove this temporary
scope marker when a pinned upstream release uses explicit `.cjs` scripts.
The [external ESM consumer verification](verification/external-esm-consumer.md)
records the tested build path and its limits.

The pinned compiler must be bootstrapped once before this MoonBit script can
run. From the consumer, clone the exact `dependency.json` revision into
`.metonic/framework`, run that checkout's mise bootstrap, then use its compiler
under `mise -C .metonic/framework exec`. For example, from the checkout:

```text
moon run scripts/application-source.mbtx -- prepare <consumer-directory> browser
moon run scripts/application-source.mbtx -- build <consumer-directory> browser main release
moon run scripts/application-source.mbtx -- build <consumer-directory> native main release
```

`prepare` validates the full source revision, the clean non-ignored Git source,
and the pinned compiler/core marker before preparing dependencies and generating
the selected `moon.work`. `build` does the same preparation before building.
It never resets or cleans the checkout. An existing handwritten `moon.work` is
left alone; migrate its application members into the manifest before allowing
Metonic to generate it. The generated workspaces have one top-level directory
each. A browser build produces both JS and WasmGC release artifacts. A native
build accepts `release` or `debug` and selects an entry defined by the consumer.
The consumer may add its own HTML and distribution packaging after the build.
When updating Metonic, check out the new commit and change `dependency.json` to
that same full SHA. Rerun the checkout's bootstrap if `toolchain.json` changed,
then build each required target again. The entry refuses to build while the
checkout, lock, or installed compiler disagree; an earlier successful build
does not bypass these checks.

The manifest contains only the consumer's workspace paths and entries, for
example:

```json
{
  "schema_version": 1,
  "targets": {
    "browser": {
      "workspace": "browser",
      "members": ["app", "../common"],
      "entries": {
        "main": {
          "entry_package": "app/main",
          "artifact": "local/my_app_browser/main"
        }
      }
    }
  }
}
```

An application may declare only the target it uses. The workspace must be one
top-level directory; application members must resolve within the consumer.
The exact framework revision appears only in `dependency.json`, not a second
manifest field.

WebSys and native dependency preparation flatten the archives' outer directories
to keep staging and generator artifact paths short on Windows. WebSys child Git
processes enable long paths without
modifying global Git settings. This avoids the known nested-checkout failure;
it does not guarantee that every tool supports arbitrarily long directory paths.

For a native consumer, its manifest gives the entry directory relative to its
workspace and the fully qualified artifact name. For example, `main` and
`local/my_app/main` identify the entry directory and compiler artifact. Output
is under the consumer workspace's
`.metonic-build/native/<profile>/build/<qualified-package>/`. AccessKit DLL and
licenses are staged beside the executable, with the default font and its notice
under `assets/`. No font environment override is needed when retaining that
layout. The build output is not a complete distribution: the application must
select its runtime files and include the remaining dependency notices.

For a browser consumer, define the entry package and artifact in the same
manifest, then select that entry with the public source build command. The
consumer workspace's
`.metonic-dist` contains `app.mjs`, `app.wasm`, the shared browser runtime,
generated WebSys imports, font and license files. Add the application's HTML
and small `runApplication` entry and serve that directory over HTTP. The
artifact prefix in that entry is `./app`. This path does not build or stage
the P0 application or development diagnostics.

Package paths use slash-separated ASCII letters, digits, dots, underscores and
hyphens; empty, `.` and `..` segments are rejected. The builder assumes Moon's
workspace artifact layout. The manifest's application members remain explicit;
Metonic-internal prepared members and dependency preparation are not consumer
configuration. The low-level builders' environment variables remain internal
implementation inputs, not the source-consumer entry contract.

## Native development control

A separate debug entry can pass
`controller=Some(application_control.control)` to `window_host.run`. Import
`local/native_host/application_control` in that entry only. The ordinary release
entry must omit the controller and its import; the release host API does not
expose it. This interface is experimental and Windows-only. It does not establish
browser development control.

Set `METONIC_DEV_PIPE` to a unique local name before starting the debug app. Its
stderr announces `METONIC_DEV_SESSION <path>`. Keep that discovery path for the
instance. After building `tools/native_cli` for Wasm release, run the pinned
`moonrun` with its artifact and `--session <path>`. Send JSON lines such as
`{"op":"snapshot"}`; mutation arguments belong in `args`.

Alternatively, after `mise run devtools:wire-build`, an MCP client can run
`node tools/devtools/application-mcp.mjs --session <path>` from the framework
directory. This connects to an already-running app; it does not start one. It
checks the application protocol before exposing operations. The P0 window MCP
entry remains separate.

Snapshots contain a semantic revision and controls with target identity, role,
name, value, enabled/focused state and selection. Use the returned target and
`expected_semantic_revision` for `insert`, `select`, `backspace` and `activate`.
Targets include session, window, ID and generation; do not infer them from list
positions. `insert` replaces the selected text. Selection offsets are UTF-16
positions. Re-read state after a successful mutation or `stale_revision` error.
Host dispatch rejects disabled/stale targets, unsupported roles and operations
during active composition. Button activation uses the application's callback and
normal task queue; success does not mean its asynchronous work has completed.

`capture` returns a PNG from the shared offscreen pass and its corresponding
state. It does not certify physical presentation or IME behavior. The connection
has bounded input lines and request admission. Disconnecting a pipe client leaves
the app running; reconnecting obtains the current state. Cancellation cannot undo
an operation already dispatched. Without `METONIC_DEV_PIPE`, the entry serves
stdin/stdout and requests normal app closure at EOF; the application's unsaved
changes policy still applies.

`mise run native:application-control-test` checks the generic Notes fixture's
stdio edit/capture/EOF shutdown and MCP edit/capture/reconnect. The attachment
test terminates its owned app afterward; it is not a normal pipe-mode shutdown
test. External consumer acceptance and browser support require separate checks.

## Browser development control

The pinned Playwright 1.63.0 includes both CLI and MCP entry points. Use its
existing-browser attachment with the application's semantic DOM controls;
Metonic does not require a second browser control protocol or a page-global
development hook. The normal button and input handlers remain responsible for
application updates, including the JS and WasmGC builds.

Start a dedicated Chromium development instance with a separate user-data
directory and loopback remote debugging, for example using the browser's
`--remote-debugging-address=127.0.0.1`, `--remote-debugging-port=9222` and
`--user-data-dir=<dedicated-development-profile>` launch options. Open the
application's served URL in that instance. Do not point automation at a personal
profile or expose its debugging port to the network. A debug browser endpoint
grants control of the browser, not just the application's origin.

From the prepared framework checkout:

```text
mise exec -- pnpm exec playwright cli -s=metonic-dev attach --cdp=http://127.0.0.1:9222
mise exec -- pnpm exec playwright cli -s=metonic-dev tab-list
mise exec -- pnpm exec playwright cli -s=metonic-dev tab-select <index>
mise exec -- pnpm exec playwright cli -s=metonic-dev snapshot
mise exec -- pnpm exec playwright cli -s=metonic-dev click <current-button-reference>
mise exec -- pnpm exec playwright cli -s=metonic-dev fill <current-input-reference> "Text"
mise exec -- pnpm exec playwright cli -s=metonic-dev screenshot
mise exec -- pnpm exec playwright cli -s=metonic-dev detach
```

Inspect the tab list and select the application's exact URL before operating.
Read a fresh snapshot after navigation or a UI change; references belong to the
current page. The DOM automation path does not provide native control's
`expected_semantic_revision` transaction guard. Serialize editing clients and
observe the application's save/error state instead of interpreting a successful
click as completed asynchronous work.

For an MCP client, launch the pinned Node executable with the absolute path to
`node_modules/playwright/cli.js`, followed by `mcp --cdp-endpoint
http://127.0.0.1:9222`. This is a stdio MCP server. Use `browser_tabs` to inspect
and select the existing tab, `browser_snapshot` for controls, `browser_click` and
`browser_type` for operations, and `browser_take_screenshot` for rendering.
Ending the attaching MCP connection or using CLI `detach` leaves the app open;
do not use a browser/tab-close command when only disconnecting is intended.

The application does not import Playwright or an MCP SDK. Keep these tools and
the development browser profile outside the distribution inventory. The same
ordinary application bundle is inspected through browser-owned DevTools, so
there is no Metonic debug endpoint to strip from its runtime. This boundary is
different from native's separately compiled controller.

An external consumer should verify attachment, editing, actual persistence,
capture, reconnect, detach and reload on both JS and WasmGC. DOM text insertion
and headless screenshots do not establish physical IME or on-screen display
behavior. Browser automation retains the browser's permission and storage
semantics; it cannot make private-profile data durable or bypass denied access.

## Distribution

Package an explicit inventory of runtime files rather than copying the build
directory. For Windows, include the release executable, `accesskit.dll`, bundled
assets and dependency notices. Keep the DLL beside the executable. The current
Windows x64 AccessKit build requires the Visual C++ x64 runtime
(`VCRUNTIME140.dll`); copying a development machine's system DLLs is not a runtime
installation procedure. A GUI application can select the Windows subsystem in
its own entry's native linker configuration; Metonic does not impose that choice
on console applications or test executables.

Run `moon run scripts/prepare-native-rust-notices.mbtx` with the pinned compiler
in the mise environment after native dependency preparation. It produces
`.work/native-rust-notices/distribution/inventory.json` and the referenced notice
files for AccessKit and wgpu. Verify the inventory's sizes and SHA256 hashes when
copying them. Include the separate Chromium notice as well as the generated
reports. These Rust reports do not replace notices for MoonBit, the framework,
fonts and other native dependencies. The generator's configuration and source
clarifications are documented in [native notices](../scripts/native-notices/README.md).

For browsers, include the JS and WasmGC artifacts, shared runtime, generated
imports, application HTML/entry, font and applicable notices. Serve the bundle
over HTTP with JavaScript and WebAssembly MIME types. Browser storage remains
associated with the serving origin, not the directory containing the bundle.

Keep development probes and control entries outside the distribution inventory.
Verify the application's own release output, not just a framework example: use
generated-code/link checks with a development positive control, then exercise
the copied application from an unrelated working directory with isolated data.
Check editing, saving, restart/restore and shutdown in addition to startup.
Relocation on a development machine does not establish clean-machine runtime
availability or physical IME behavior.

## Resource responsibilities

The application entry does not require an application-wide resource container.
Compose resources at startup and retain their cleanup until host-owned work has
ended. The following boundaries are deliberately different:

| Resource | Shared contract and platform entry | Application responsibility and limits |
| --- | --- | --- |
| Time | `capabilities/clock.Clock`; `async_runtime/clock.SystemClock::new()` for production; `VirtualClock` for tests | Select a clock when work needs one. One production instance supports repeated and concurrent waits; cancellation belongs to each async task, not the clock. |
| HTTP | Bounded POST through `capabilities/http.Http`, native `http.NativeHttp`, browser `http_transport.create`; `async_runtime/http.TimedHttp` adds a deadline | Select the endpoint, accepted content types and response limit. Browser CORS/permissions still apply. Create a browser transport per exchange; its controller/reader are cleaned up after use. |
| Display and host | `core/application.Control`, native `application.from_application`/`window_host.run`, browser `application_host.create` | Define layout, state, semantic references and actions. Hosts own GPU objects, rasterization, input and shutdown. Ordinary applications need no GPU types. The managed browser entry reconciles element bindings with the current view. |
| Storage | Native `snapshot_store.Store` and browser `snapshot_store.load/save` | Adapt bytes or strings into the application's format and recovery policy. Native locking/async IO and browser synchronous origin-scoped storage have different lifetime and failure contracts, described below. |
| Clipboard | `core/text_clipboard` editing policy and native backend; browser DOM editing | Display input-operation failures separately from storage failures. Native access does not grant browser clipboard permissions. Rich text, images and clipboard history are not provided. |
| Fonts and packaged assets | Native executable-relative resource resolution/font override; browser font URL and digest | Select and distribute licensed resources. Host code loads and rasterizes the configured font. `resources.asset_path` resolves a file path; it does not decode an image. |
| Images | No image control or image-loading API in the portable entry | The current control kinds are Text, Button and Input. Image widgets/decoders require a separate extension; access to low-level rendering internals is not a portable image API. |

Storage serialization and memo CRUD belong to the consumer. GPU setup, OS input
handling and resource teardown belong to the hosts. Task requests use the
shared replacement/cancellation driver with independent operation identities; resource interfaces do not own a second
scheduler or hide platform permissions and persistence differences.

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

The browser application host accepts input up to 1024 UTF-16 code units. The
semantic editor and native clipboard policy do not impose that same content cap;
applications must enforce their own document limits and report rejection without
discarding unsaved text. The existing raster layer size limits also apply.
The native default input is optional, allowing empty and button-only views. The
managed browser entry creates DOM controls dynamically and places them at the
bounds supplied by the application. The shared fixed-height vertical list is
available, but a general layout system and list virtualization are not.
Unexpected task failures use the handler/outcome contract described above;
there is no automatic retry or durable background job queue.
The portable task entry alone does not establish durable saving or recovery;
applications must connect a storage backend and handle its returned failures.

The Notes owned-window probe and browser JS/WasmGC gate exercise the same
application definition. Browser checks cover actual rendered edits, selection,
activation, resize, stopped input, stopping during initialization and stopping
an additional instance without affecting the running application. The artifact
exports only `create`; P0/development-exclusion guards remain required. These
checks do not establish physical IME acceptance.

The separate local memo consumer exercises independent autosave and search
operations with production storage and clocks. See the
[memo operation verification record](verification/memo-operations.md) for the
behavior, tested commands and limits of that local evidence.
