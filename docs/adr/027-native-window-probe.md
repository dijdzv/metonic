# ADR 027: Windows surface and event-loop probe

Date: 2026-09-06.

Status: experimental; not a final cross-platform windowing decision.

## Decision

Add a Windows-only probe alongside the offscreen renderer. MoonBit owns scene
state and input interpretation. A small C stub owns HWND creation and a blocking
Win32 message loop. Rust owns the wgpu DX12 surface, device, pipeline and queue.
The existing rectangle shader is shared with the offscreen probe.

This isolates the Windows lifetime boundary without introducing another event
loop abstraction. A portable windowing library remains an alternative when
additional platforms are implemented. This experiment does not establish a
performance advantage for direct Win32 or choose an accessibility adapter.

## Lifetime and scheduling

The C stub forwards paint, nonzero resize, key, pointer and close events through
a bounded ring. An overflow terminates the probe. GetMessage blocks when no
events are pending; unrelated messages are dispatched without being treated as
application events or errors. State changes and paint events trigger rendering.

WM_CLOSE is forwarded without destroying the HWND. MoonBit exits its loop and
calls cleanup, which destroys the surface before the HWND and unloads the DLL.
The raw window handle must remain valid throughout the surface lifetime.
Surface loss or an outdated surface causes one reconfiguration and acquisition
retry. Other acquisition failures terminate this bounded probe; recovery and
occlusion scheduling for a production application remain unimplemented.

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
