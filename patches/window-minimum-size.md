# Windows minimum client sizes

`window-minimum-size.patch` fills the existing Windows constraint API in
`wzzc-dev/window`. The Windows bridge already handles `WM_GETMINMAXINFO` through
a synchronous MoonBit callback; no new production C bridge is needed.

The patch stores an optional minimum beside each registered window handle.
Logical sizes are retained as logical values and converted at the window's
current DPI, rounding up to avoid falling below the requested minimum. Physical
sizes remain pixel counts. Nonpositive, nonfinite and overflowing dimensions
are ignored by the setter, preserving the previous constraint. `None` clears
the constraint. Destroying a window removes its constraint with its handle.

Frame adjustment uses the current style, extended style, menu and DPI. Both
interactive tracking and `request_inner_size` honor the minimum. Setting a larger
minimum grows a smaller client area; lowering or clearing it does not shrink
the window automatically. Maximum-size policy is unchanged.

## Verification

`mise run native:notes-test` includes three pure conversion/lifetime tests and
a hidden owned-window probe. The pure tests cover physical versus logical sizes
at scale factors 1, 1.25, 1.5 and 2, upward rounding, invalid inputs and removal
of window state. The window probe checks creation, setter/getter aliases,
requested resizing, constraint clearing, separate windows and calls after
destruction. It sends `WM_GETMINMAXINFO` to the real HWND and compares the
returned tracking size to the measured outer rectangle at the minimum client
size. This direct Win32 call is test-only.

The owned-window run was verified with standard decorated windows at scale 1.
Other physical monitor DPI settings, live monitor transitions and custom menu
or undecorated styles are not established by that run. Pure conversion tests
are not evidence for those OS configurations.

Preparation checks the complete dependency tree. A recognized pre-patch tree is
upgraded after validation; unknown edits still fail comparison. The patch also
updates the existing event-test fixture for the prepared event loop's `closed`
field and uses explicit `Show::to_string` so the Windows test package compiles
without deprecated implicit method promotion.

## Upstream applicability

The upstream default branch `moui-support` was checked at
`5b1f9b1718d5a52583e740ee2e1f422781247e00`. Its minimum setters are still no-ops
and its synchronous query still reports no constraints. This is a reusable
window-library contract and is suitable for a focused upstream contribution.

This repository's patch applies after its prepared dependency patches. It is
not directly applicable to that upstream revision: the existing requested-size
client-to-frame conversion and its `AdjustWindowRectExForDpi`/`GetMenu` imports
are prerequisites, tracked in issue #368. An upstream submission should extract
that correction first, then transplant the minimum-size change and tests,
omitting the local event-loop fixture adjustment when unnecessary. No upstream
issue or pull request has been posted by this work.
