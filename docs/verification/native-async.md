# Native asynchronous completion probe

## Contract

The native probe uses the same MoonBit task scope as the browser experiment.
Success and failure cross the native boundary as request IDs and integer
payloads. Workers never call MoonBit or render; the UI thread receives a private
window message and performs scope validation before updating scene state.

At most 16 worker slots exist. Each worker waits on its own cancellation event
with a bounded delay. A slot stays occupied until the UI thread joins the worker
and consumes its completion. Scope cancellation only prevents result application;
the late completion is deliberately delivered to test rejection. Shutdown signals
all remaining workers and joins them before destroying the surface and HWND.
New work is rejected after shutdown. A join failure retains the window/resources
rather than invalidating a handle still referenced by a worker.

The implementation uses caller-owned thread handles from
[`_beginthreadex`](https://learn.microsoft.com/en-us/cpp/c-runtime-library/reference/beginthread-beginthreadex?view=msvc-170),
[`WaitForSingleObject`](https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-waitforsingleobject)
and [`PostMessageW`](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-postmessagew).

## Reproduction and assertions

```powershell
mise run native:async
```

Set `METONIC_GPU_FALLBACK=1` for fallback only; otherwise both default and fallback
adapters run. Reports are under `.work/native-async/`. The test creates a hidden
HWND and addresses input messages only to that window, without desktop automation.

The executable checks these steps in order:

1. Right-arrow input changes the scene while the first request remains pending.
2. A successful worker completion updates the scene to x=40 and submits rendering.
3. A newer request updates x=90; the older completion is rejected.
4. A cancelled request's completion is rejected.
5. An error completion enters the error state without moving the scene.
6. A completion after scope disposal is rejected.
7. Sixteen five-second workers fill the host capacity; the seventeenth is rejected.
8. Close cancels and joins pending workers, empties the slots, and rejects restart.

The verifier requires one success marker, no failure marker, a successful process
exit, bounded output and a 20-second deadline. It checks shutdown alone takes less
than four seconds, separately from GPU startup, to detect waiting for the full
five-second worker delay instead of cancelling it. This is a watchdog assertion,
not a performance benchmark.

## Scope

On 2026-09-06, local Windows x64 runs passed with NVIDIA GeForce RTX 3060
(DX12) and Microsoft Basic Render Driver (DX12). Both completed the sequence and
reported zero milliseconds at the shutdown clock's resolution. This is not a
claim that shutdown has no cost. The existing native-window sequence also passed
after adding the shared worker support.

This proves a bounded worker-thread wakeup path into the native event loop and
request-lifetime validation. It does not implement network I/O, a general task
runtime, arbitrary MoonBit closure transfer, or a reusable thread pool. Visible
input, IME and accessibility remain separate verification gates. The scope is
single-use; this probe does not implement reset within the same HWND.

The native build wrappers invalidate the generated stub object before building
so edits to included C/header files are reflected by the pinned compiler's build.
