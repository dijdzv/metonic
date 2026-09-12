# Windows surface probe

## Reproduction

Use the pinned MoonBit toolchain described in the
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

The `query` and `query-latin` cases run hidden User ID editing against a private
loopback HTTP fixture. They compare the complete submitted JSON body with the
Japanese or Latin spaced value, and compare GPU captures with single-line text
raster output using the surface's actual sRGB encoding. They cover Home/End,
resize, scrolled pointer placement, Backspace, selection reversal and replacement,
and cursor-area coordinates passed to Windows during injected preedit/cancellation.
Directed selection uses a debug-only semantic fixture; insertion, navigation and
pointer input use owned-window messages. These checks do not certify physical IME,
keyboard, or screen-reader behavior. Both application and fixture must terminate.

## Local evidence

On 2026-09-07, the Windows x64 native host build using `Milky2018/wgpu_mbt` 0.16.0
and wgpu-native 29.0.1.1 passed with the pinned compiler. Both runs exited
successfully with `WINDOW_PROBE_OK`, with a missing Rust DLL path supplied:

| Adapter | Backend | Result |
| --- | --- | --- |
| NVIDIA GeForce RTX 3060 | DX12 | Hidden surface and event sequence passed |
| Microsoft Basic Render Driver | DX12 | Hidden surface and event sequence passed |

The MoonBit loop requires right-arrow movement from x=260 to x=270, resize to
317 by 193, activation from a pointer event inside the current rectangle, at
least three successful rendering calls, and a close event at the expected stage.
MoonBit SurfaceRenderer calls acquire, draw, submit and present through the
published binding. Cleanup releases the renderer and surface before the HWND.

`native_host/window_app` uses the shared `windows_loop` driver and the prepared
`wzzc-dev/window/windows` dependency. The old application-owned C event queue and
window procedure are removed from this path. The separate surface diagnostic
retains its C window fixture under `tools/native_surface_probe`.

Initialization runs in a child task while the parent drains a bounded MoonBit
event queue and yields to the async scheduler. Completion draws the current scene
even if an earlier paint was consumed. The shared driver bounds message dispatch. The host
currently sleeps one millisecond between iterations; idle scheduling has not
been optimized or benchmarked.

The normal test posts its first key after initial rendering. Two additional
hidden cases run with `METONIC_WINDOW_INIT_TEST=input` and `close`; the verifier
selects all three cases explicitly for each adapter and records separate reports
such as `default-input.json` and `fallback-close.json`.

The dedicated cases yield cooperatively until a real initialization ticket is
retained, then post an own-window key or close message and poll at most 64 times
without yielding. The target event must be handled while the ticket is still
retained. The input case preserves x=270 through the first frame, then performs
the normal resize, pointer and close sequence. The close case cancels and waits
for initialization, requires no published renderer or rendered frame, and checks
that no initialization tickets remain before ordered teardown.

On 2026-09-07 both dedicated cases passed on both adapters: each reported
`WINDOW_INIT_RETAINED=1`, `WINDOW_INIT_REMAINING=0` and its dedicated success
marker, with child exit 0 and no timeout or output overflow. The verifier rejects
missing, duplicated or invalid numeric markers. A retained ticket can already
have received its native callback and be paused before ownership transfer; this
test does not prove that the driver callback itself is still pending. No artificial
GPU delay is introduced. Driver stalls and physical device loss remain untested.
Pending initialization prevents HWND destruction; the parent deadline contains
cleanup that cannot finish safely. Every case also requires `WINDOW_CLEANUP_OK`
exactly once, after GPU teardown, window destruction, and event-loop disposal.
The host checks both application and message HWNDs with `IsWindow` before reporting
success. `PostMessageW` and `IsWindow` are direct OS FFI declarations; the shared
driver retains its context-free C wake callback.

This test does not read back surface pixels or inspect visible output. Full
pixel comparisons remain in the separate [offscreen probe](native-headless.md).
Visible presentation, focus, DPI changes, real input, IME, accessibility and
live-window MCP attachment are not verified by this test. No Computer Use or
desktop input injection is involved.

The architecture and remaining scope are recorded in
[ADR 027](../adr/027-native-window-probe.md).
