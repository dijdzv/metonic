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

| Operation | Native | Browser |
| --- | --- | --- |
| Replace the initial text | Ctrl+A, type Japanese and Latin text | Focus the text input, select all and type |
| Select and replace a range | Click and Shift+click the GPU text, then type | Use the text input's selection and type |
| Move the insertion position | Left/Right, Home/End; hold Shift to select | Use the text input's keyboard controls |
| Load the sample user | F7 | Load user, with User ID `1` |
| Observe the result | `月兎` below the editor; editor text preserved | Same result below the GPU editor and in the result output |
| Start delayed scene movement | F5 | Move after delay |
| Cancel before completion | F6 | Cancel |
| Resize | Resize the native window | Resize the browser window |
| End the session | Close the native window | Stop disposes the browser UI; close the tab separately |

For a domain error, the browser can request `missing`. The native shortcut uses
user `1`; arbitrary IDs are available through the separate development CLI/MCP.
Native HTTP results use a dedicated row below the editor, so multiline editor
contents do not push the result out of its viewport. The editor itself remains
a fixed-height viewport without scrolling.
Native left/right keys edit while text is focused; Tab switches between text and
the scene, and clicking the scene returns its keyboard focus. Scene focus enables
Up/down movement and Enter/Space activation. Those keys do not operate the scene
while editing or composing; Space inserts text while editing. Vertical editor
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
accessibility and messages sent to its own window: replace text, invoke F7
against an owned real HTTP server, observe the result, resize, continue editing
and close. It checks editor preservation and updated accessible layout. This
connects the production session's semantic behavior; it does not establish
presented pixels, physical keyboard input or real IME.

The packaged browser omits the development adapter and comparison artifact.
Native uses the release artifact with the existing development-code exclusion
check. Physical Japanese
IME, OS accessibility and production input/rendering evidence remain separate
requirements; see [native IME verification](native-ime.md).
