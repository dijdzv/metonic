# Notes example

Notes is a small independent application built on the same Metonic editing and
rendering primitives as P0. Its shared model is in `examples/notes/application`;
it does not import the P0 model or backend. The native adapter uses
`native_host/window_host`. The browser adapter uses the input, font, GPU and DOM
packages described in [Browser host boundaries](browser-host-boundaries.md).
Both adapters consume the same [application definition](application-entry.md).
The browser artifact exports only `create`; shared host code owns its rendering
and input callbacks.

## Browser

From the configured mise environment, run `mise run browser:serve`, then open
`http://127.0.0.1:4173/notes/`. WasmGC is the default. Use
`http://127.0.0.1:4173/notes/?target=js` for the JS backend. WebGPU requires a
supported browser and a secure context such as localhost.

Enter a note, select text, or activate **Clear note**. The input element supplies
browser editing and accessibility, while the visible text, selection, caret and
button are GPU-rendered. **Stop** cancels loading, disconnects input, releases GPU
resources and disables the controls. Reload the page to start another instance.

The browser build stages a standalone directory at `.work/browser-notes`, including
both application artifacts, the shared host/runtime, the pinned font and license
files. Serve its contents over HTTP; opening the HTML as a local file does not
establish a supported WebGPU or module-loading environment.

`mise run browser:headless` covers P0 and Notes on JS and WasmGC. Notes acceptance
checks Japanese/multiline value changes, GPU output changes after editing and
selection, clearing, viewport resizing and rejection of input after stopping.
It also stops during adapter acquisition, device acquisition and pending font
streaming, checking that late devices are destroyed and font readers are released.
The packaged JS/WasmGC export lists are checked against the Notes API, and the
packager rejects P0 and development-control markers with positive controls.
These are synthetic browser operations, not physical IME acceptance. Generated
screenshots and results are retained with the other browser verification artifacts.

## Native

Run `mise run native:notes-build` and launch the resulting `notes_app.exe` under
the native workspace build directory. `mise run native:notes-test` runs the owned
window probe and the production dependency guard. See
[Native application host](native-application-host.md) for its build paths and
host constraints.

## Scope

This is an in-memory example: it does not save notes, make HTTP requests, or add
development CLI/MCP controls. The browser input is limited to 1024 UTF-16 code
units; the current shared raster layer is at most 1024 by 96 pixels. Its note area
scrolls, while the clear control remains a separate layer. It demonstrates a
different application using the shared host without implementing P0-shaped
placeholder APIs.
