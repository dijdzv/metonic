# Windows system-key dispatch

The window dependency forwards `WM_SYSKEYDOWN` and `WM_SYSKEYUP` to MoonBit but
returns zero, suppressing the default Windows handling. `window-system-keys.patch`
keeps that notification and then calls `DefWindowProcW`. This restores the OS
close path instead of adding an Alt+F4 special case to the demo.

The same suppression was present in the upstream default branch when checked.
Its Issue tracker is disabled; no upstream submission is claimed. The two-line
behavioral change is suitable for a focused upstream proposal after validation.
See [the task](https://github.com/dijdzv/metonic/issues/273) and Microsoft's
[system-keystroke contract](https://learn.microsoft.com/en-us/windows/win32/inputdev/about-keyboard-input).

`mise run native:release-lifecycle` checks ordinary `WM_CLOSE` and an Alt-context
`WM_SYSKEYDOWN` for F4 against separate owned production processes. The latter
timed out before the correction. It checks process/window termination; synthetic
messages do not establish physical key delivery or IME behavior. Repeat actual
Alt+F4 through Computer Use on development and production builds.

Dependency preparation upgrades an existing cache only after its complete tree
matches the known previous source/configuration and the async tree passes its
normal comparison. It replaces only the corrected C file. Unknown source edits
remain errors; a fresh checkout applies the patch during staging.
