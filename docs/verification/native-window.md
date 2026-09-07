# Windows surface probe

## Reproduction

Use the pinned MoonBit and Rust toolchains described in the
[development guide](../development.md), with Visual Studio C++ build tools.

```powershell
mise run native:window
```

The verifier runs default and forced-fallback adapters. Set
`METONIC_GPU_FALLBACK=1` to run only the fallback case on CI. It writes bounded
stdout/stderr and exit information under `.work/native-window/`. Each child has
a 20-second deadline. Failure markers, missing success, nonzero exit, timeout
or excessive output fail verification.

`scripts/verify-native-probes.mbtx` provides the process verification using the
pinned MoonBit async library. It shares process handling with the worker-completion
probe while keeping their success and shutdown assertions separate. Each output
stream is capped at 64 KiB during collection.

## Local evidence

On 2026-09-06, the Windows x64 release build passed with the pinned compiler and
wgpu 30.0.1. Both runs exited successfully with `WINDOW_PROBE_OK`:

| Adapter | Backend | Result |
| --- | --- | --- |
| NVIDIA GeForce RTX 3060 | DX12 | Hidden surface and event sequence passed |
| Microsoft Basic Render Driver | DX12 | Hidden surface and event sequence passed |

The MoonBit loop requires right-arrow movement from x=260 to x=270, resize to
317 by 193, activation from a pointer event inside the current rectangle, at
least three successful rendering calls, and a close event at the expected stage.
Rust rendering calls acquire a surface texture, draw, submit and present.
Cleanup releases the surface before destroying the HWND.

This test does not read back surface pixels or inspect visible output. Full
pixel comparisons remain in the separate [offscreen probe](native-headless.md).
Visible presentation, focus, DPI changes, real input, IME, accessibility and
live-window MCP attachment are not verified by this test. No Computer Use or
desktop input injection is involved.

The architecture and remaining scope are recorded in
[ADR 027](../adr/027-native-window-probe.md).
