# Native asynchronous completion probe

## Contract

`native_host/async_app` reuses the existing MoonBit scene, task scope and
`SurfaceRenderer`. The prepared dependencies and shared external-loop adapter
are described in [ADR 030](../adr/030-native-external-event-loop.md).
Jobs use a structured task group and bounded completion queue. Each job reads
the real fixture asynchronously; a timer controls completion order. The runtime's
foreign-thread notification reaches the UI loop through the context-free C wake
thunk. Application workers no longer need custom C thread/cancellation handling.

Sixteen admission slots include completed results not yet consumed. Logical scope
cancellation and disposal leave the job running so its late result actually reaches
the rejection check. Shutdown closes admission, cancels and joins jobs before GPU
and window teardown. Task-group cleanup clears slots after all children terminate.
Original I/O errors remain failures after cleanup.

The hidden window requests and verifies a 640 by 360 client area. GPU initialization
and first presentation precede jobs. Key and close messages target only its own
HWND. This is synthetic-message coverage, not physical input or desktop automation.

## Reproduction and assertions

```powershell
mise run native:async
```

The task prepares pinned dependencies and builds the native host workspace.
Set `METONIC_GPU_FALLBACK=1` for fallback only; otherwise both adapters run.
Reports under `.work/native-async/` are overwritten by later runs.
`METONIC_ASYNC_INPUT` may override the fixture for failure diagnosis.

The executable checks these steps:

1. Right-key input moves the scene while the first request is loading.
2. Its successful completion moves x=40.
3. A newer request moves x=90; the older result is received and rejected.
4. A cancelled request's late result is rejected, preserving cancelled status.
5. A domain failure sets error code 7 without moving the scene.
6. A result after disposal is rejected.
7. Sixteen active five-second jobs fill capacity; the next is rejected.
8. Close cancels and joins jobs, empties slots, and prevents restart.

Initial state, input, first success and newer success each submit a frame.
External-loop termination emits the final record after releasing GPU resources,
the application HWND and message-only HWND. Destruction is checked with
`IsWindow`; pending GPU initialization or active jobs prevent resource release.

The MoonBit observer requires exit zero, exactly one success marker, exactly one
correctly typed JSON result, no failure marker, bounded output and a 20-second
deadline. It checks at least four frames, final scene/scope state, three rejected
results, zero outstanding jobs, I/O wake/proxy/indefinite-poll deltas and both HWND
destruction flags. Shutdown must take less than one second separately from GPU
startup. This is a watchdog assertion, not a benchmark.

## Observed comparison and limits

On 2026-09-07, the comparison observer passed on NVIDIA GeForce RTX 3060 and
Microsoft Basic Render Driver. Both reported four frames, x=90, disposed status,
three rejected results, zero active/pending jobs and both HWNDs destroyed.
Shutdown measured 6 ms each; wake/proxy/indefinite-poll deltas were 24/24/21.
The old C-worker baseline also passed before removal was authorized.

A missing-input run retained the file-open error and supplied path, with zero
active/pending jobs and both HWNDs destroyed. The ordinary observer rejected its
nonzero exit. After switching the canonical `native:async` task and removing the
old sources, both adapters passed again with four frames, the same final state
and complete HWND cleanup. Shutdown measured 2 ms and 0 ms at clock resolution;
all three I/O deltas were 21. A zero reading does not imply cost-free shutdown.

This does not verify physical input, IME, OS accessibility, network I/O, physical
device loss, arbitrary foreign-thread MoonBit closures or a reusable thread pool.
Input during GPU initialization remains separate. The window and scope are
single-use.
