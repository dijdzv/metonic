# Native production accessibility

Run `mise run native:accessibility` after the Windows setup in the
[development guide](../development.md). It builds the ordinary release window
and an external MoonBit UIA client, then a MoonBit supervisor owns both processes
and a real loopback HTTP server under a 65-second deadline. The window is visible
briefly. The client selects
only the supervisor's child PID; it does not inspect other applications.

The normal pre-commit gate includes this check. No automatic PR/push CI is added.
The optional [presentation check](native-presentation.md) captures the same owned
window through the official winapp CLI and checks color transitions separately
from UIA state.

## Implemented behavior

The ordinary window attaches AccessKit C 0.22.3 with the reviewed local
[Windows focus-ownership patch](../../patches/accesskit-windows-focus.md) before
becoming visible. Its source build retains the official C ABI.
The adapter maps the shared semantic model into a Window root, Toggle button,
Text editor, Load user, Move after delay and Cancel buttons. The buttons use the common view's label
and bounds and exposes Invoke. Scene activation synchronizes the Toggle value.
The current RPC result is a separate Label populated from the same result used
by GPU rendering. It has no editing actions and does not replace editor text.
Task status is a separate Label from the shared task state. The external verifier
starts a delayed task, observes pending state, cancels it, checks that late
completion does not replace Canceled, and successfully starts another task.
Draw/resize publishes current values and physical bounds. Accessibility Click
and Focus requests rejoin the ordinary UI event queue. Focus requests also ask
the window library to focus the window. Active IME composition currently rejects
these application actions.

The editor supports UIA Value replacement through the shared editor's validation
and caret reset behavior. Requests are limited to 64 KiB of UTF-8 before queue
admission; MoonBit decodes the owned bytes on the UI thread. During composition
the adapter advertises read-only and the UI handler rejects queued external
mutations. Value calls return before the application applies the queued request;
clients must observe resulting state rather than treating a successful return as
an application completion barrier. Full Text/selection patterns are not yet
implemented, so this remains incomplete accessibility.

`prepare-accesskit.mbtx` pins the official archive and verifies SHA256
`b652e380fb78efe6721ad892f15b2224f38f661c3fb20436ef4c5b3ce0fe8177` before extracting
the header, Windows x64 MSVC import library/DLL, and licenses. The window build
copies the DLL and both AccessKit licenses beside the executable. The compiler's
INCLUDE/LIB environment is scoped to that build. This is a Windows x64 MSVC
configuration; no additional Rust toolchain or custom Rust bridge is required.

## Boundary and lifetime

MoonBit creates trees, translates state, processes actions and asserts results.
`native_host/accessibility/mailbox.c` owns at most 32 pending official request
objects under an SRW lock. The foreign-thread callback cannot safely use a
MoonBit GC queue. Closing rejects further admission and frees pending requests
before destroying the adapter. A generation cookie prevents a callback from an
older adapter entering a later window session. The static lock/queue have process
lifetime; no application object is captured by the foreign-thread callback.
Unsupported requests and overload are dropped and freed. Action delivery is not
transactional under overload; no stronger guarantee is claimed.

The same C boundary accesses official request fields and passes the by-value
rectangle and selection ABI. These use the header rather than hard-coded offsets. The external
test has a separate small SDK cache-navigation adapter in `accessibility_probe`;
it is not linked into the production window. The new C code contains neither
application state nor an independently implemented UIA provider.

## Observed evidence and remaining work

The production check verifies the exact root/button/editor names, Button/Edit
roles, the initial Japanese/Latin editor value, the toggle's off-to-on change
after an external Toggle request, editor preservation, normal process exit,
four Value round trips (Japanese/Latin, supplementary characters and empty text),
ordinary posted character/backspace messages after replacement, an Invoke request
from the Load user button to the owned HTTP server and exact `月兎` result, actual window resize
with updated accessible editor bounds, continued editing without losing the
result or toggle state, HWND destruction
and rejection by retained Toggle/Value providers after close. Success emits
`WINDOW_PRODUCTION_UIA_OK` and `WINDOW_PRODUCTION_UIA_PROCESSES_OK`.

The same command accepts `METONIC_VIEW_ACTION=pointer` to post a click at the
button's observed UIA bounds, or `METONIC_VIEW_ACTION=keyboard` to focus it through
UIA and post Down/Enter. The keyboard case verifies that Down does not move the
scene while the request button is focused. These are automated OS-message paths,
not evidence of physical input. `native:presentation` may be combined with a mode
to capture the owned production window through the official CLI.

Text runs come from the retained editor layout, including wrapped and offscreen
lines. Run-local AccessKit character indices map explicitly to editor UTF-16
offsets; a supplementary scalar and a CRLF pair each form one selectable unit.
The shared editor rejects selection inside CRLF and skips the pair for horizontal
navigation and backward deletion. When an edit forms a new CRLF pair across its
boundary, the caret moves to the end of that pair. Stored text remains unchanged
and offsets remain UTF-16; this is not newline normalization or full grapheme
navigation.

The external probe verifies exact document and selected text for Japanese,
supplementary characters, CRLF and wrapped text. It selects the interior of
`A…B`, waits for the published selection to match, types `X`, observes `AXB`,
checks rejection of the obsolete range, and continues typing to obtain `AXYB`.
Selection-only updates retain run IDs; changed text or width creates new IDs.
Requests retain raw IDs until application so a later tree cannot reuse cached
offsets from an earlier layout. Forced queue interleavings still need separate
evidence.

Character positions and widths now come from retained shaped-run highlights,
with explicit selectable-unit alignment. The production probe checks Japanese,
Latin, digits, supplementary text, CRLF and wrapped ranges before and after
resize against client coordinates. Empty and offscreen ranges have no rectangle;
replaced ranges reject coordinate queries. Combining clusters omit unsupported
per-scalar geometry. The [AccessKit clipping correction](../../patches/accesskit-clipping.md)
preserves document text outside the editor viewport and shares the existing
source build with the focus correction.

Existing six native scenarios still exercise shared input/rendering after
attachment; a staged-composition check rejects a queued accessibility value
replacement without changing committed text. This is not a real IME run.
UIA properties and posted messages do not prove presented GPU pixels, real keyboard or
pointer delivery, Japanese IME behavior, or screen-reader usability. Forced queue
overflow, action/close races and adapter recreation need dedicated evidence;
the current normal-close check does not claim to cover those races. Complex-cluster
geometry, composition-aware focus and assistive-technology testing
remain required. See [ADR 023](../adr/023-development-automation.md) for selection.
