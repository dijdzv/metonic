# Windows GPU and external-loop integration

## Scope

This isolated comparison connects the corrected `wzzc-dev/window` candidate and
`moonbitlang/async@0.21.2` external loop to the existing `native_gpu` package.
The renderer, initialization owner and published `Milky2018/wgpu_mbt@0.16.0`
binding are reused unchanged. The product window and worker implementation is
still the comparison baseline; this experiment does not replace it.

The candidate revision and waiter correction are pinned in the
[resource cleanup record](native-resource-cleanup.md). The current
[combined window patch](../../experiments/window_pump_contract/windows-pump.patch)
also includes explicit redraw queuing and client-size correction. Apply this
version once to the pinned revision, rather than stacking historical versions.

## Contract

The hidden application window supplies HWND and HINSTANCE through the candidate's
public API. The binding converts the integer handles to opaque pointers. A
context-free native wake thunk retains the existing foreign-thread restriction;
no new C renderer or handle helper is introduced.

GPU initialization and first presentation precede application I/O and tasks.
Three consecutive redraw requests must coalesce into one callback and one frame;
an extra zero-timeout pump must not duplicate it. A subsequent client-size request
must produce a resize event and a new frame at 800 by 450. Event counters are
captured before each request, so a startup or synchronous callback cannot be
mistaken for a later notification.

File I/O must add foreign wakes, proxy callbacks and indefinite polls relative
to snapshots taken immediately before reading the sentinel. GPU initialization
notifications cannot satisfy these delta assertions. The fixture then verifies
a finite timer and cancellation of sixteen structured tasks, with no normal
long-task completion and no pending tasks.

Termination first requires zero pending GPU initialization and tasks. It closes
the renderer, releases surface and instance, then destroys the application and
message HWNDs. Input or rendering errors are retained through this sequence and
re-raised after a failure result. The parent observer bounds execution to thirty
seconds and each output stream to 64 KiB. Expected-input-error mode additionally
requires the actual input path and `@fs.open()` in the parsed error, successful
GPU stage counters, and both HWND destruction checks.

## Candidate corrections

The earlier `request_redraw` only invalidated the HWND. In the hidden experiment,
no redraw callback arrived within two seconds after initial presentation.
The correction also uses the existing MoonBit redraw queue. Pending redraws
prevent the next pump from blocking in the OS, while existing deduplication and
the bounded message drain remain in place. This is an explicit application
redraw request, not evidence of physical input or an OS exposure event.

The earlier `request_inner_size(800,450)` produced a 784 by 411 client area because
it passed client dimensions directly as outer-window dimensions. The correction
uses current style, extended style, menu presence and DPI with
[AdjustWindowRectExForDpi](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-adjustwindowrectexfordpi).
It checks the adjusted dimensions before calling the existing position API and
retains the optional return contract. Invalid sizes or failed adjustment do not
resize the window.

The adjustment is a direct borrowed-buffer FFI, without a new C stub. Generated
C was inspected: a four-element `int32_t` array is passed as `int32_t*`, matching
the Windows RECT fields; it remains live across the call and is released by
MoonBit afterward. This avoids assuming a stable MoonBit struct layout. See
[MoonBit FFI ownership](https://docs.moonbitlang.com/en/stable/language/ffi.html).
This binding was verified for Windows x64. The Windows API requires Windows 10
version 1607 or later; older systems and other architectures were not tested.

## Observations

On 2026-09-07, the corrected default-adapter run exited zero on NVIDIA GeForce
RTX 3060. It reported three frames, two redraws, one resize, client size 800 by
450, four additional I/O wakes/proxies/indefinite polls, sixteen task cleanups,
zero pending initialization/tasks and destruction of both HWNDs. The timer
measured 105 ms; task shutdown measured 0 ms at the clock's resolution.

The fallback run also exited zero on Microsoft Basic Render Driver, with the
same frame, size, I/O-delta and cleanup counts and a 110 ms timer. Missing input
was rejected by the ordinary observer, and accepted as a diagnostic failure only
in expected-error mode on both adapters. Both failures completed the GPU stage,
reported zero pending work, destroyed both HWNDs and retained the exact missing
path in the file-open error. Valid input in expected-error mode was rejected
because the child succeeded. The observer requires the complete supplied path
and JSON null for a successful run's original error.

The final combined window patch also passed all seven existing pump cases and
the separate-process sender/receiver case.

The retained earlier runs rejected missing redraw delivery and then the incorrect
784 by 411 size. Both failure results retained the specific assertion and reported
both HWNDs destroyed; their file/task stages were not reached. This establishes
that the observer rejected the discovered gaps rather than accepting weaker
dimensions or bypassing the redraw callback.

## Reproduction

Use the project toolchain and the corrected isolated workspace described in
[resource cleanup](native-resource-cleanup.md). Add `Milky2018/wgpu_mbt@0.16.0`
and `local/p0@0.0.0` to the candidate `modules/window/moon.mod`. Create
`modules/metonic/moon.mod` in that checkout:

```toml
name = "local/p0"
version = "0.0.0"
license = "MIT OR Apache-2.0"
preferred_target = "native"
import {
  "moonbitlang/async@0.21.2",
  "Milky2018/wgpu_mbt@0.16.0",
}
```

Add `"./modules/metonic"` to the candidate root `moon.work`. Copy the root
`native_gpu` package into `modules/metonic/native_gpu`, preserving the sources.
The measured run compared hashes of `moon.pkg`, `initialization.mbt`,
`gpu_initialization.mbt`, `bounded_readback.mbt`, `gpu_readback.mbt`,
`renderer.mbt` and `surface_renderer.mbt`; all seven matched the product sources.
Copy only `main.mbt`, `moon.pkg` and `wake.c` from `experiments/window_gpu_async`
into `modules/window/examples/metonic_gpu_async`. Its standalone manifest must
not replace a candidate module manifest. Resolve the workspace dependencies.

From a Visual Studio x64 Native Tools command prompt at the metonic root:

```bat
set "MOON_HOME=%CD%\.tools\moonbit"
mise exec -- .tools\moonbit\bin\moon.exe -C .work\window-pump-source\modules\window update
mise exec -- .tools\moonbit\bin\moon.exe -C .work\window-pump-source\modules\window build examples/metonic_gpu_async --target native --target-dir "%CD%\.work\window-gpu-integration"
set "METONIC_GPU_FALLBACK=0"
mise exec -- .tools\moonbit\bin\moon.exe run scripts/verify-window-gpu-async.mbtx -- "%CD%\.work\window-gpu-integration\native\debug\build\wzzc-dev\window\examples\metonic_gpu_async\metonic_gpu_async.exe" "%CD%\experiments\window_async_contract\input.txt"
```

Use a fresh target directory for changed native dependencies. Repeat with
`METONIC_GPU_FALLBACK=1`. A nonexistent absolute input path must fail ordinarily
and pass only with `--expect-input-error` appended; valid input with that flag
must fail. Keep the product gate separate from these opt-in candidate tests.

## Limits

Successful presentation does not verify screenshot pixels, physical input, IME,
UI Automation, or exclusion of development tooling from production. Existing
renderer/readback tests remain separate evidence. Non-default DPI, menus,
minimized windows and injected adjustment failures were not exercised. The
single-instance window and pending-initialization ownership restrictions still
apply. Replacing the existing worker scenarios and product host remains follow-up
work under [Issue 31](https://github.com/dijdzv/metonic/issues/31) and
[Issue 54](https://github.com/dijdzv/metonic/issues/54).
