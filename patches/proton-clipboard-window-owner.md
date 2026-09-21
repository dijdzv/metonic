# Windows text clipboard ownership

The native clipboard backend reuses `moonbit-community/proton_clipboard` 0.3.3.
Preparation verifies its release archive SHA-256 as
`215422f7abcfd217cc46c401380460748d20366139502374ae61bbc51f53a966`,
applies `proton-clipboard-window-owner.patch`, and publishes the complete source
tree as `.work/native-deps/sources/proton-clipboard-window-owner`. Reuse compares
the complete prepared tree; verification input discovery includes that tree.

The released Windows writer calls `OpenClipboard(NULL)` followed by
`EmptyClipboard()` and `SetClipboardData`. Microsoft's
[OpenClipboard contract](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-openclipboard)
states that this leaves a NULL owner and causes `SetClipboardData` to fail.
This is a source-contract finding; it has not been reproduced against the
unmodified backend in an isolated Windows clipboard session.

The patch creates a hidden message-only window for the write operation and
passes its HWND to `OpenClipboard`. Every exit destroys that window. Failure
paths preserve the original Windows error before cleanup and release memory
that has not transferred to the clipboard. A successful `SetClipboardData`
transfers the allocation to Windows; the library must not free it. Reading,
non-Windows backends and the MoonBit API remain unchanged.

## Verification and limits

The prepared dependency compiles with the pinned MoonBit/MSVC toolchain.
Metonic's semantic tests and injected native key-path tests cover editing and
failure preservation independently of the OS clipboard. They do not validate
the production Windows read/write roundtrip or this C ownership correction.
That backend acceptance remains required before declaring clipboard support
complete. Automatic tests must not overwrite the user's clipboard to obtain it.

## Upstream applicability

The same writer is present in upstream commit
`25d77e6236420025ddf1ab04995c0c2a05bba9ed`. The ownership correction belongs in
the clipboard library rather than a second Metonic clipboard bridge. An upstream
proposal should include an isolated ownership/error regression test and Windows
runtime evidence. No third-party issue or PR has been posted.
