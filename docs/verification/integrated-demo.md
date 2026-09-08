# Integrated local demo

After the Windows setup in [the development guide](../development.md), run
`mise run demo` from the repository root. This builds both browser targets, the
existing browser HTTP server, and the ordinary native release window. A MoonBit
launcher starts the server, waits up to ten seconds for readiness, then starts
the native window with that same server origin. Port 4173 must be available.
An existing server is not reused or terminated.

Open `http://127.0.0.1:4173/release/` in a WebGPU-capable browser. The packaged
WasmGC UI excludes the development control adapter. The separate comparison
page at `/` retains JS and diagnostic controls. The launcher does not start or
control a browser process. See [the selection and package record](browser-target.md).

## Common operation sequence

The two frontends share model implementations and the HTTP contract, not a live
editing session. Perform the sequence separately in each UI.

`examples/p0/application` owns each demo instance's scene, editor, task scope and
RPC result. Both hosts use its result and delayed-movement transitions, including
rejection of canceled, superseded and stopped requests. Window/browser events,
transport execution and GPU resources remain in their host adapters. This is the
sample application's shared behavior, not a general component or reactive API.

`application/view.mbt` defines the editor, request button and result bounds and
labels. `examples/p0/view_renderer` uses the same text rasterizer for both hosts;
each host presents those layers through its normal GPU pass. The browser's
transparent textarea and button provide input and semantic behavior at the shared
bounds. Their visible content comes from the GPU. Native exposes the same request
button through AccessKit. Development snapshots include the shared view and its
`load_user` operation.

| Operation | Native | Browser |
| --- | --- | --- |
| Replace the initial text | Ctrl+A, type Japanese and Latin text | Focus the text input, select all and type |
| Select and replace a range | Click and Shift+click the GPU text, then type | Use the text input's selection and type |
| Move the insertion position | Left/Right, Home/End; hold Shift to select | Use the text input's keyboard controls |
| Choose a user | Edit the GPU User ID field (initially `1`) | Edit the GPU User ID field (initially `1`) |
| Load the sample user | Click Load user, or focus it and press Enter/Space; F7 also works | Click Load user or focus it and press Enter/Space, with User ID `1` |
| Observe the result | `月兎` below the editor; editor text preserved | Same result below the GPU editor |
| Start delayed scene movement | Move after delay; F5 also works | Move after delay |
| Cancel before completion | Cancel; F6 also works | Cancel |
| Resize | Resize the native window | Resize the browser window |
| End the session | Close the native window | Stop disposes the browser UI; close the tab separately |

For a domain error, enter `missing` in User ID and activate Load user. Change it
back to `1` to retry successfully. Both hosts retain the separate editor contents;
the native F7 shortcut also uses the current User ID. Each app instance owns its
query value. The ID field occupies the right side of the result row.
Native and browser HTTP results use a dedicated row below the GPU editor, so multiline editor
contents do not push the result out of its viewport. The editor itself remains
a fixed-height viewport without scrolling.
Both hosts render the delayed-update controls and task status through the shared
GPU view. The demo delay is one second. Cancel applies to the active delayed update
or HTTP request; completion and cancellation preserve editor contents.
For viewports at least 400 pixels wide and 260 pixels high, a height below 352
uses side-by-side task buttons and a status row above them. Taller viewports keep
the stacked controls. Native uses client-area pixels; the browser uses CSS pixels.
Below 400x260, complete control visibility is not supported; enlarge the viewport.
This sample layout does not implement scrolling or a general responsive layout engine.
Native left/right keys edit while text is focused; Tab cycles through text, the
scene, Load user, Move after delay, Cancel and User ID. Clicking the scene returns its keyboard focus. Scene focus enables
Up/down movement and Enter/Space activation. Those keys do not operate the scene
while editing, composing or focusing Load user; Space inserts text while editing. Vertical editor
navigation is not implemented. The browser requires canvas focus for scene keyboard
controls. Native uses a steady caret and scalar-boundary horizontal navigation;
grapheme-aware and visual bidi navigation, vertical editing navigation and caret
blinking remain unfinished. This is not full editing parity.

Closing native ends the launcher and its owned server. An unexpected server exit
fails the session and terminates its owned native child. Startup failure also
cleans up the server. Each child is a direct leaf executable; this launcher does
not supervise independently spawned descendants. Normal native close runs the
UI's resource cleanup; forced termination after a server failure does not prove
that application-level cleanup ran.

## Verification boundaries

`mise run demo:test` exercises normal child exit, invalid readiness, native
startup failure and unexpected server exit with process fixtures. It does not
prove user interaction or rendering. Existing `browser:headless`,
`native:window-rpc`, `native:window-mcp` and `native:window` checks exercise their
respective UI paths. `native:release-lifecycle` checks the production window's
startup and close, not its editor or pixels.

`native:accessibility` exercises the ordinary release executable through OS
accessibility and messages sent to its own window: replace text, activate Load user
against an owned real HTTP server, observe the result, resize, continue editing
and close. It checks editor preservation and updated accessible layout. This
connects the production session's semantic behavior; it does not establish
presented pixels, physical keyboard input or real IME.

The packaged browser omits the development adapter and comparison artifact.
Native uses the release artifact with the existing development-code exclusion
check. Physical Japanese
IME, OS accessibility and production input/rendering evidence remain separate
requirements; see [native IME verification](native-ime.md).
