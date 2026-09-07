# Native external-loop resource cleanup

## Scope and source

This Windows experiment extends the [async integration](windows-async-integration.md)
before product adoption. The working application window and worker boundary is
unchanged. The two isolated corrections target:

- `wzzc-dev/window` revision `b33c9f0ac85002bca4a9cceccbbcd512d13b7ceb`:
  [combined pump and lifetime patch](../../experiments/window_pump_contract/windows-pump.patch).
- `moonbitlang/async@0.21.2`:
  [waiter lifetime patch](../../experiments/async_waiter_handles/windows-waiter.patch).
  The original `src/internal/event_loop/event_bus.c` SHA256 is
  `4D1C9EAC539F50B59C96ABB3DE32D168A8DE00422D2B6DDD39BBE31A41E75860`.

Both patches include Apache-2.0 source context; see [LICENSE-APACHE](../../LICENSE-APACHE).
They are local modifications, not published upstream changes or registry releases.
The window patch replaces the earlier pump-only patch and applies once to the
pinned revision. Do not stack both versions.

## Ownership contract

The original async waiter joins its Windows thread but does not close its HANDLE.
Its Windows mutex destruction macro also does not release the critical section.
The correction closes the HANDLE after a successful join and destroys the critical
section before freeing the waiter. Failed allocation returns null; on Windows it
sets the allocation error. Failed Windows thread creation releases initialized
resources and preserves the OS error. A failed join or handle close aborts rather
than freeing storage that might still be used by a thread. The shared allocation
guard also changes the Unix allocation-failure path; Unix was not executed.

The original Windows `EventLoop::drop` is a no-op. The corrected `try_drop` requires
the owner thread, no remaining application windows and no active dispatch handler.
It destroys the message-only HWND, releases native callback references, clears
hooks and pending queues, and marks the loop closed. Repeated drop succeeds;
closed pumping returns `Exit(0)` and window creation/run entry points reject use.
Foreign producers must be stopped before drop. The class registration and IMM
library cache remain process-lifetime resources, and the single-instance creation
guard remains set: this patch does not support recreating an event loop.

The async fixture retains an input error until external-loop termination, after
the runtime waiter has joined. It destroys the application HWND and message HWND,
emits a diagnostic result, then raises the retained error. Its final success flag
requires successful main completion; cleanup alone cannot turn an error into success.

## Observed results

Windows native execution on 2026-09-07 used the pinned project toolchain and MSVC.

| Case | Observation |
| --- | --- |
| Original waiter, one warmup then 32 cycles | HANDLE count 112 to 144, delta 32; expected 32 accepted |
| Original waiter, expected zero | Rejected with observed delta 32 |
| Corrected waiter, same cycle count | HANDLE count 111 to 111, delta zero; accepted |
| Corrected waiter, expected 32 | Rejected with observed delta zero |
| Normal async input | Success; 16 task cleanups, zero pending, both HWNDs destroyed |
| Missing input, ordinary observer | Rejected; child error preserved and both HWNDs destroyed |
| Missing input, expected-error observer | Accepted diagnostic failure; actual `@fs.open()` missing-file error retained |
| Valid input, expected-error observer | Rejected because the child succeeded |

The normal async run reported five foreign wakes, four proxies, two finite polls,
five zero polls, four indefinite polls, and a 103 ms timer. Missing input reported
zero task cleanups because it failed before those tasks were created. Both cases
reported zero pending tasks and successful `IsWindow` destruction checks. The
fixture also rejects drop while the application HWND is alive, verifies both
HWNDs survive that rejection, and checks repeated drop and closed pump/create.

The combined window patch also passed all seven existing pump cases and the
cross-process sender/receiver case. Finite wait measured 109 ms, the future
deadline 110 ms, and the expired deadline 0 ms; the flood yielded after 64
callbacks and quit preserved exit code 17.

The waiter probe uses a synchronous main and a context-free C callback. It creates
and destroys an event bus and waiter each cycle, without repeatedly initializing
the async runtime or violating the window singleton restriction. The observer
requires one result, matching handle arithmetic and child success; it bounds the
process to ten seconds and each output stream to 64 KiB.

## Reproduction

Prepare the pinned separate window checkout and CommonJS boundary described in
the [pump experiment](windows-event-pump.md), applying the current combined window
patch. Add `moonbitlang/async@0.21.2` to `modules/window/moon.mod` and resolve it.
Copy that exact resolved async module into `modules/async` in the candidate
checkout and add `"./modules/async"` to its root `moon.work` members. Preserve the
original registry copy for comparison; do not patch the product dependency cache.
Verify the original C file hash above before applying the waiter patch.

Copy `main.mbt`, `moon.pkg`, and `host.c` from `experiments/async_waiter_handles`
to `modules/window/examples/metonic_waiter_handles` in the candidate. Copy the
three package files for the async fixture as described in its verification record.
Do not copy either fixture's standalone `moon.mod` over the candidate module.

In a Visual Studio x64 Native Tools command prompt at the metonic root:

```bat
set "MOON_HOME=%CD%\.tools\moonbit"
mise exec -- .tools\moonbit\bin\moon.exe -C .work\window-pump-source\modules\window build examples/metonic_waiter_handles --target native --target-dir "%CD%\.work\waiter-original"
mise exec -- .tools\moonbit\bin\moon.exe run scripts/verify-waiter-handles.mbtx -- "%CD%\.work\waiter-original\native\debug\build\wzzc-dev\window\examples\metonic_waiter_handles\metonic_waiter_handles.exe" 32
git -C .work\window-pump-source apply --check --directory=modules/async "%CD%\experiments\async_waiter_handles\windows-waiter.patch"
git -C .work\window-pump-source apply --directory=modules/async "%CD%\experiments\async_waiter_handles\windows-waiter.patch"
mise exec -- .tools\moonbit\bin\moon.exe -C .work\window-pump-source\modules\window build examples/metonic_waiter_handles --target native --target-dir "%CD%\.work\waiter-corrected"
mise exec -- .tools\moonbit\bin\moon.exe run scripts/verify-waiter-handles.mbtx -- "%CD%\.work\waiter-corrected\native\debug\build\wzzc-dev\window\examples\metonic_waiter_handles\metonic_waiter_handles.exe" 0
```

Use a fresh target directory for each C revision. Repeat the original observer
with `0` and the corrected observer with `32`; each must fail. Build the async
fixture against the corrected workspace into another fresh directory and run
its observer with the committed input file. Repeat with a nonexistent absolute
input path, first normally (must fail), then with `--expect-input-error` as the
last argument (must succeed with `ok:false`). The same flag with valid input
must fail. These are opt-in candidate tests, separate from the product gate.

## Limits

HANDLE stability does not measure all heap allocations or prove critical-section
cleanup. Creation/join failure branches were source-reviewed, not fault-injected.
Wrong-thread destruction and active callback destruction have guards but were not
executed as negative cases. Hidden HWND checks do not validate real input, IME,
UI Automation, GPU presentation, or production exclusion of development tooling.
These results address the tested lifetime paths, not complete product adoption.
