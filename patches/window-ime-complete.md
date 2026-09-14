# Windows IME completion request

`window-ime-complete.patch` adds a Windows-specific
`Window::request_ime_completion() -> Bool` method to the pinned window dependency.
It uses `ImmNotifyIME(NI_COMPOSITIONSTR, CPS_COMPLETE)` through the dependency's
existing IMM loader and releases the acquired input context on both outcomes.
The C addition is an OS API boundary; focus routing remains in MoonBit.

A true return value means that the request was accepted. It does not mean that
the application's event queue has consumed the result string or composition-end
event. The caller must keep the original input target through those events.
Do not substitute the displayed preedit for the OS result string, or toggle
`set_ime_allowed` to simulate completion: that setter only changes library state.

The native host retains the latest pointer intent, requests completion once,
and applies the intent while processing the composition-end event. It does not
put the intent behind later input events. Failed requests and window-focus loss
discard the intent. Development edits return `composition_active` while the
transition is pending; observation requests continue to receive responses.

The patch is a local upstream candidate, not an upstream-accepted API. Upstream
`14e49f8a811819ec48b8cc531af62f598c9c393a` was inspected before implementation.
Run-specific evidence and remaining acceptance are maintained in Issue #94.

Reference: [ImmNotifyIME](https://learn.microsoft.com/en-us/windows/win32/api/imm/nf-imm-immnotifyime).
