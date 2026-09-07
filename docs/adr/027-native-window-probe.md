# ADR 027: Windows surface and event-loop probe

Date: 2026-09-06.

Status: experimental; not a final cross-platform windowing decision.

## Decision

Add a Windows-only probe alongside the offscreen renderer. MoonBit owns scene
state, input interpretation and the DX12 renderer through the published MoonBit
binding. A small C stub owns HWND creation and bounded Win32 message polling.
The worker-completion probe retains the blocking C loop and Rust renderer.

This isolates the Windows lifetime boundary without introducing another event
loop abstraction. A portable windowing library remains an alternative when
additional platforms are implemented. This experiment does not establish a
performance advantage for direct Win32 or choose an accessibility adapter.

## Lifetime and scheduling

The C stub forwards paint, nonzero resize, key, pointer and close events through
a bounded ring. An overflow terminates the probe. The window host polls at most
64 Win32 messages per call and yields through the MoonBit async scheduler between
iterations. Unrelated messages do not become application events. The worker
baseline retains blocking GetMessage. State changes and paint trigger rendering.

WM_CLOSE is forwarded without destroying the HWND. MoonBit exits its loop and
calls cleanup, which destroys the surface before the HWND. The worker baseline
also unloads its Rust DLL.
The raw window handle must remain valid throughout the surface lifetime.
Surface loss or an outdated surface causes one reconfiguration and acquisition
retry. Other acquisition failures terminate this bounded probe; recovery and
occlusion scheduling for a production application remain unimplemented.

### MoonBit renderer replacement contract

The binding-based renderer evaluation treats the surface as part of a device
generation. Replacing the device requires closing the renderer, releasing the
caller's surface reference, and creating a fresh surface on the still-live HWND.
Resizing within the same device generation continues to reconfigure that surface.
This distinction avoids carrying a DX12 swapchain across device generations:
the pinned binding/native combination fails the same-surface replacement probe.
See the [replacement verification](../verification/surface-device-replacement.md)
for the comparison and its limits; fresh-surface success does not mean that
same-surface reuse has been fixed upstream.

The HWND must outlive both the renderer and pending adapter/device callbacks.
If initialization leaves a pending callback, closing the renderer alone does
not authorize HWND destruction. The normal window sequence verifies input after
initialization; pending-initialization input and close still require dedicated
verification. The Rust worker-completion probe remains a separate baseline.

## Automated verification boundary

With METONIC_WINDOW_TEST=1, the probe creates a hidden HWND and posts messages only
to that HWND. It does not inject desktop input. It verifies right-arrow movement,
resize to 317 by 193, activation by a pointer message inside the rectangle, and
close. Each rendering success requires surface acquisition, command submission
and presentation through wgpu. A watchdog bounds the executable run.

The separate offscreen CLI/MCP probe remains the pixel-readback and semantic
automation path. Hidden HWND tests establish neither visible compositor output
nor user-input delivery, focus behavior, IME, DPI transitions or accessibility.
Attaching CLI/MCP to a live window and excluding development hooks from product
builds are still required work. These executables are development experiments,
not production artifacts.

See [verification results](../verification/native-window.md).
