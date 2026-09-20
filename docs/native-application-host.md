# Native application host

`native_host/window_host` runs the Windows event loop, semantic editing, IME
transfer, GPU presentation, accessibility and asynchronous task completion. It
does not import the P0 application. `native_host/window_ui` is the P0 entry and
development-API adapter; existing P0 verification and CLI/MCP clients use it.

An application supplies `native_host/application.Application`: its semantic tree,
default input reference, initialization and cleanup callbacks, initial window size,
view, focus order and actions. The view supplies render items, input modes and
accessibility presentation. A scene rectangle is optional. Synchronous callbacks
run on the host event thread. Asynchronous actions return the existing
[typed task request](application-tasks.md); completion is applied on that thread.
The host owns no separate scheduler.

Call `window_host.run(application)` from a native async entry point. The model and
adapter remain application-owned. See `examples/notes/application`,
`native_host/notes_application` and `native_host/notes_app` for a second application
without User ID, HTTP or a moving rectangle. Its editor and Clear note button use
the same host as P0. Build the release executable with `mise run native:notes-build`;
run `.work/native-host-build/native/release/build/local/native_host/notes_app/notes_app.exe`
from the repository root after normal setup.

## Input and redraw ownership

Each live input reference has its own raster layout and scroll position. The
presenter prepares its visible text, selection, composition ranges and caret, then
compares prepared items with the preceding frame. Unchanged text pixels are reused
when an application changes only the optional rectangle. Pointer and vertical
navigation resolve the relevant input's retained geometry rather than a primary
editor's width. Do not mutate retained raster engines outside this host/presenter.

The default input must remain a live TextInput during host operation. This first
host API does not yet support input-free applications. View items have the current
raster limits (width at most 1024, height at most 96); viewport dimensions are at
most 2048. The accessibility bridge currently exposes full text-run geometry for
one declared text owner. These limits are not claims of a general widget toolkit.

## Verification and production boundaries

`mise run native:notes-test` checks the local dependency graph for P0 imports and
runs an owned hidden window. It verifies editing, capture, button activation and
shutdown through the shared host. It runs in the normal integration gate. This is
not physical Japanese IME acceptance or desktop screenshot verification.

P0 production and control integration gates remain required. Debug-only host
observation/control handlers and the P0 protocol adapter are excluded from release
file selection; production artifact checks verify their absence. A passing Notes
probe alone does not prove that exclusion. Browser host extraction is separate;
the Notes model is platform independent, but its browser adapter is not provided
by this native milestone.
