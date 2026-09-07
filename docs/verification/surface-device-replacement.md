# Surface lifetime across device replacement

## Purpose and scope

Compare reusing a Windows DX12 surface after replacing its adapter/device with
recreating the surface on the same HWND. This is a controlled replacement of
healthy devices, not a physical driver-reset or device-loss injection test.
Tracking: [Issue 58](https://github.com/dijdzv/metonic/issues/58).

The probe uses `Milky2018/wgpu_mbt` 0.16.0 and the pinned wgpu-native 29.0.1.1
Windows x64 archive. The existing C boundary supplies a hidden HWND. The raw
path uses synchronous adapter/device requests and only a clear render pass,
submission and presentation; it does not use `SurfaceRenderer`, rectangle
shaders, pipelines or uniform buffers. Synchronous initialization is limited
to this diagnostic and does not establish responsive production initialization.

## Reproduction

Use the Windows toolchain setup in [the development guide](../development.md).
Run each condition separately so an expected failing condition does not prevent
the other observations. `native:surface` builds the executable and runs it under
a parent with a 20-second deadline and a hidden-window requirement.

```powershell
$env:METONIC_SURFACE_RAW = '1'
$env:METONIC_SURFACE_FRESH = '0'
$env:METONIC_GPU_FALLBACK = '1'
mise run native:surface
```

Set `METONIC_SURFACE_FRESH` to `1` for the fresh-surface control. Set
`METONIC_GPU_FALLBACK` to `0` for the default-adapter run; that task also runs the
fallback condition if the default condition succeeds. Clear all three variables
after the diagnostic. Each run overwrites its report under
`.work/native-surface`, so preserve reports before changing conditions.

## Observations on 2026-09-07

| Condition | Default adapter | Fallback adapter |
| --- | --- | --- |
| Same surface, replacement device | Child exit -1073740791 | Child exit -1073740791 |
| Fresh surface, same HWND, replacement device | Child exit 0 | Child exit 0 |

The reuse failures occur during the second generation. Native cleanup reports
`Parent device is lost` from `wgpuTextureRelease` and aborts. The fresh controls
reach `RAW_SURFACE_OK` and complete process cleanup. This narrows the necessary
trigger below the metonic renderer class, but does not by itself attribute the
fault to the binding, native implementation or application lifetime contract.

Additional stage tracing on both adapters records the original failure
before cleanup: `wgpuSurfacePresent failed (status=Error, u32=2)`. Configuration,
frame acquisition and submission return before that failure. The subsequent
texture-release panic is therefore a second failure during unwinding, rather
than the first observed API error. Return from submission alone does not prove
GPU execution completed successfully.

The verifier requires `RAW_SURFACE_OK` in raw mode and records `rawSurface`,
`freshSurface` and a scope excluding renderer, resize and input coverage.
The raw executable also emits the older shared success marker, but the verifier
does not use that marker to establish raw success.

## Source investigation and limits

The normal `mise run native:surface` path, with `METONIC_SURFACE_RAW` unset,
uses asynchronous owned initialization and creates a fresh surface for each of
three renderer generations. On 2026-09-07 it passed on NVIDIA GeForce RTX 3060
and Microsoft Basic Render Driver, with child exit 0 and no timeout or overflow.
The first generation checks initial and active rendering, rejected dimensions
and rectangle bounds, and an HWND resize to 317 by 193. Each generation checks
idempotent close and rejection of presentation after close. Both replacements
render again and leave no pending initialization tickets.

This validates deliberate renderer replacement with a live HWND. It does not
inject GPU loss, verify on-screen pixels or establish a responsive event loop
during initialization. The normal pre-commit gate forces raw mode off so a
diagnostic environment setting cannot substitute the smaller raw probe.

The [native manifest](https://github.com/gfx-rs/wgpu-native/blob/v29.0.1.1/Cargo.toml)
declares wgpu-core and wgpu-hal 29.0.1. In that version, the
[DX12 surface implementation](https://github.com/gfx-rs/wgpu/blob/v29.0.1/wgpu-hal/src/dx12/mod.rs)
reuses an existing swapchain through `ResizeBuffers` when configuring it again.
That branch does not compare device identity. This is a candidate explanation,
not a verified causal fix.

The ordinary window host now uses the MoonBit renderer and bounded event polling.
The worker-completion probe also uses the shared MoonBit surface renderer; its
worker-lifetime assertions remain separate from this device-replacement diagnostic.
These hidden-window observations do not verify real input, IME, OS accessibility
or recovery from physical GPU loss.
