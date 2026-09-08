# AccessKit Windows focus ownership

The Windows adapter patch targets `accesskit_windows` 0.34.0 in AccessKit C
0.22.3. It adds `ProviderOptions_ProviderOwnsSetFocus` to the existing server-side
provider options. It does not change text geometry, threading or the C ABI.

Windows documents this flag as suppressing UI Automation's attempt to focus the
nearest HWND on the provider's behalf. metonic already handles AccessKit Focus
requests on its UI thread: it requests window focus through the window library
and updates the shared semantic focus. The patch keeps this handler responsible
for focus; it does not bypass Windows foreground restrictions or prove physical
keyboard focus when Windows denies activation.

The unpatched production reproduction takes approximately two seconds before a
Click reaches the application's AccessKit callback. A one-second task can finish
before Cancel is delivered. Both the legacy client API and an independent COM
client reproduced this. The isolated flag-only candidate takes 0–16 ms in the
measured Invoke calls and passes serial start, pending state, cancellation,
re-use, editor preservation, HTTP, resize, close and stale-provider checks.
GetTickCount64 resolution does not establish sub-millisecond latency. Physical
input, real IME and foreground-focus acceptance remain separate requirements.

`scripts/prepare-accesskit-focus.mbtx` verifies fixed source archive hashes,
applies this patch, and builds the original AccessKit C dependency lock with
only the Windows package changed to the local source path. Rust 1.93.0 must be
on PATH. The generated source directory `.work/accesskit-focus-source` is
disposable build input, reconstructed by this command; edits there are not
maintained. Make changes to the tracked patch instead. The shared Cargo registry
is never edited. The output is `.work/accesskit-focus-build/release/accesskit.dll`.
Native builds retain the official ABI header, import library and license files,
and copy the rebuilt DLL into each executable's directory.

Upstream main at `e98d5a281d7f5c5c2db97343e78d56acc84b2d51` still returns only
`ProviderOptions_ServerSideProvider`. This is a host-tested local patch, not
proof that every AccessKit consumer satisfies the focus-ownership contract.
The upstream proposal and remaining latency investigation are tracked in
[#159](https://github.com/dijdzv/metonic/issues/159); no upstream submission is claimed.

Contract: [Windows ProviderOptions](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationcore/ne-uiautomationcore-provideroptions).
