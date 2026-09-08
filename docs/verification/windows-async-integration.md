# Windows async external-loop integration

## Scope

This record preserves the initial isolated experiment connecting `moonbitlang/async@0.21.2` to the
`wzzc-dev/window` Windows candidate at
`b33c9f0ac85002bca4a9cceccbbcd512d13b7ceb`, with the
[local pump correction](windows-event-pump.md). That boundary was subsequently
adopted by the native application; the former custom worker implementation was
removed. For current preparation and commands, use the [development guide](../development.md)
and [native async record](native-async.md). The design boundary is
recorded in [ADR 030](../adr/030-native-external-event-loop.md).

The application handler creates a hidden HWND. The external-loop adapter forwards
the async runtime's timeout directly to the candidate pump. A context-free C
callback posts the proxy thread message; the runtime's own IOCP waiter invokes
that callback. The callback touches only native state and Win32 APIs, never
MoonBit-managed objects. It does not create a worker thread.

The fixture reads the committed sentinel file through the async filesystem API,
checks a finite timer, then starts and cancels sixteen five-second tasks. Each
task accounts for its own completion and cleanup. Success requires cleanup of
all sixteen, no normal completion, no pending tasks and cancellation cleanup in
less than one second. These are cooperative async tasks, not sixteen OS threads.

The final RESULT is emitted from `ExternalEventLoop::terminate`, after async main
and child cleanup. It checks foreign notifications, proxy delivery, finite and
indefinite polling, drops the hidden application window and checks `IsWindow`.
The observer requires process success and exactly one matching RESULT, with a
ten-second deadline and 64 KiB per output stream. Its process group joins before
pipe handles are closed, including on cancellation.

The current fixture also checks message-only HWND destruction, rejected drop
while an application window is alive, repeated drop and closed-loop behavior.
Input errors are retained through cleanup and rethrown after a failure RESULT.
See the [resource cleanup record](native-resource-cleanup.md) for the required
combined patch, exact current results and expected-error observer mode.

## Observations

On Windows on 2026-09-07, the normal observer exited 0. The post-read counters
were four foreign wakes, four proxy callbacks and four indefinite polls. This
places the notification evidence before timer/cancellation/shutdown processing,
instead of relying only on final counters. The complete run reported five foreign
wakes, four delivered proxies, two finite polls, a 104 ms timer, sixteen cleanup
actions, zero pending tasks, zero normal long-task completions, and successful
application HWND destruction. Shutdown measured 0 ms at the clock's resolution;
this is not a claim of zero cost.

A missing executable and a missing input file each produced observer exit 1.
In that earlier fixture, the latter exercises rejection of a failing async main rather than merely a
process launch error. It is not proof of graceful resource cleanup on every
exception path. Counts and timing are observations from one run, not fixed
performance guarantees. A final wake may remain queued after the last pump while
the runtime shuts down, so total wakes need not equal delivered proxy callbacks.
The final run also routed startup through the adapter's zero-timeout method and
asserted that path was exercised. It recorded five zero polls, two finite polls,
four indefinite polls, a 113 ms timer and the same I/O/cleanup counters. Both
negative cases were rerun with diagnostics preserved in the observer log.

## Historical isolated reproduction

The instructions below reproduce the original separate-checkout experiment.
For the maintained repository integration, run `mise run native:host-verify`
and `mise run native:async`; normal builds prepare the pinned patched sources.

Use the pinned [toolchain](../development.md) and a Visual Studio x64 Native Tools
command prompt. Prepare the separate checkout and apply the patch as described
in [the pump experiment](windows-event-pump.md). Add
`"moonbitlang/async@0.21.2"` to that checkout's `modules/window/moon.mod` import
block. Copy only `main.mbt`, `moon.pkg` and `wake.c` from
`experiments/window_async_contract` into
`modules/window/examples/metonic_async_contract`; the standalone `moon.mod`
must not replace the candidate's module manifest.

For the current fixture, also prepare the isolated async module and apply the
waiter correction in the [resource cleanup setup](native-resource-cleanup.md).
The current window patch includes both pump and lifetime corrections.

```bat
set "MOON_HOME=%CD%\.tools\moonbit"
mise exec -- .tools\moonbit\bin\moon.exe -C .work\window-pump-source\modules\window update
mise exec -- .tools\moonbit\bin\moon.exe -C .work\window-pump-source\modules\window build examples/metonic_async_contract --target native --target-dir "%CD%\.work\window-async-build"
mise exec -- .tools\moonbit\bin\moon.exe run scripts/verify-window-async.mbtx -- "%CD%\.work\window-async-build\native\debug\build\wzzc-dev\window\examples\metonic_async_contract\metonic_async_contract.exe" "%CD%\experiments\window_async_contract\input.txt"
```

Use a fresh target directory when changing native sources. The candidate needs
the CommonJS boundary documented in the pump experiment. A missing executable or
missing sentinel is a negative case and must produce a nonzero observer exit.

## Limits

This experiment addresses the runtime waiter and structured task cleanup; it does
not validate arbitrary MoonBit closures on worker threads, GPU presentation,
physical input, IME or UI Automation. The original application-HWND result alone
did not prove message-HWND or waiter-HANDLE release. The additional ownership
measurements and their limits are recorded in
[resource cleanup](native-resource-cleanup.md). Current structured-job
completion and shutdown evidence remains separate in
[the native async probe](native-async.md).
