# Windows pointer capture termination

The pinned window dependency captured the mouse on each button press and
released it on every button release. It did not deliver capture loss or
cancellation to the application, so a text-drag owner could not reliably abandon
a gesture after capture transferred to another window.

This patch extends the existing window boundary with
`WindowEvent::PointerCanceled(DeviceId?)`. On Windows, both `WM_CAPTURECHANGED`
and `WM_CANCELMODE` cancel an active pointer gesture. The latter retains default
window handling for menus, scrolling and capture release. It can consequently
produce a second cancellation notification; consumers must treat cancellation
as idempotent. No release coordinate is invented. The legacy winit event adapter
has no equivalent event and returns an empty array for this new variant.

Button release is dispatched before `ReleaseCapture`, which can synchronously
notify capture loss. Capture is released only when it belongs to the current
HWND and the message reports no remaining mouse buttons pressed. Releasing a
secondary button therefore does not terminate a left-button drag. Focus loss and
destruction remain explicit existing events; gesture owners must end dragging
on those events too.

Button press skips `SetCapture` when this HWND already owns capture. Reacquiring
the same HWND can itself deliver capture loss; the owned-window regression
detects the resulting cancellation between a left press and a secondary release.

The contracts are documented by Microsoft for
[capture loss](https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-capturechanged),
[cancellation](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-cancelmode)
and [button release](https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-lbuttonup).

## Preparation and verification

Preparation publishes the combined dependency as `window-pointer-capture` and
compares its complete source tree on reuse. It leaves the older prepared tree
untouched, avoiding a partial in-place update of overlapping window patches.
Workspace imports and verification input collection use the new tree.

The patch includes owned hidden-window tests for release ordering, negative
coordinates, multi-button ownership, transfer to another owned HWND,
cancellation, focus notification and destruction. Decoder checks cover unknown
window identities and legacy event conversion. `native:notes-test` selects these
alongside the existing minimum-size checks. Synthetic window messages establish
OS-boundary delivery, not physical pointer input or text dragging; application
drag selection remains separate work.

## Upstream applicability

The upstream `moui-support` branch at
`5b1f9b1718d5a52583e740ee2e1f422781247e00` still contains the same capture behavior.
This is a reusable window-library correction and a candidate for an upstream
contribution. The local patch is based on the prepared dependency; an upstream
submission should retain the capture change and its tests without unrelated
IME or minimum-size changes. No upstream issue or PR has been posted.
