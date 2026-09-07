# Native production accessibility

Run `mise run native:accessibility` after the Windows setup in the
[development guide](../development.md). It builds the ordinary release window
and an external MoonBit UIA client, then a MoonBit supervisor owns both processes
under a 25-second deadline. The window is visible briefly. The client selects
only the supervisor's child PID; it does not inspect other applications.

The normal pre-commit gate includes this check. No automatic PR/push CI is added.

## Implemented behavior

The ordinary window attaches official AccessKit C 0.22.3 before becoming visible.
The adapter maps the shared semantic model into a Window root, Toggle button and
Text editor. Scene activation synchronizes the button's semantic toggle value;
draw/resize publishes current values and physical bounds. Accessibility Click
and Focus requests rejoin the ordinary UI event queue. Focus requests also ask
the window library to focus the window. Active IME composition currently rejects
these application actions.

The text value is readable through UIA, but Value mutation and Text/selection
patterns are not implemented. The adapter advertises the value as read-only
until its mutation contract exists. This is incomplete accessibility, not a
claim that keyboard editing is read-only or that P0 accessibility is complete.

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
rectangle ABI. These use the header rather than hard-coded offsets. The external
test has a separate small SDK cache-navigation adapter in `accessibility_probe`;
it is not linked into the production window. The new C code contains neither
application state nor an independently implemented UIA provider.

## Observed evidence and remaining work

The production check verifies the exact root/button/editor names, Button/Edit
roles, the initial Japanese/Latin editor value, the toggle's off-to-on change
after an external Toggle request, editor preservation, normal process exit,
HWND destruction and rejection by a retained provider after close. Success emits
`WINDOW_PRODUCTION_UIA_OK` and `WINDOW_PRODUCTION_UIA_PROCESSES_OK`.

Existing six native scenarios still exercise shared input/rendering after
attachment. UIA properties do not prove presented GPU pixels, real keyboard or
pointer delivery, Japanese IME behavior, or screen-reader usability. Forced queue
overflow, action/close races and adapter recreation need dedicated evidence;
the current normal-close check does not claim to cover those races. Full text
patterns, selection, composition-aware focus and assistive-technology testing
remain required. See [ADR 023](../adr/023-development-automation.md) for selection.
