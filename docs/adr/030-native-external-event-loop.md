# ADR 030: Evaluate the native async external-loop boundary

## Status

Accepted for staged adoption. The isolated integration and resource experiments
are recorded below. Reproducible preparation and product scenario parity remain
required in [Issue 77](https://github.com/dijdzv/metonic/issues/77).

## Context

The current native asynchronous probe uses explicit C worker slots and a bounded
Win32 poll followed by a MoonBit async yield. That establishes a worker completion
path but leaves application-owned thread creation, cancellation events and joins.
Replacing these with timers alone would remove the existing foreign-thread
notification evidence without establishing native I/O integration.

The resolved `moonbitlang/async@0.21.2` exposes `ExternalEventLoop`. Its native
runtime contains a Windows IOCP waiter which notifies a caller-supplied main loop.
This implementation is more specific evidence than the package README's older
platform summary. It still requires Windows execution before adoption.

## Decision

Evaluate the public external-loop API against the pinned Windows window candidate
and its [bounded pump correction](../verification/windows-event-pump.md). Forward
zero, finite and indefinite timeouts without substituting periodic polling.
Use real asynchronous file I/O to exercise the runtime's waiter notification and
use structured tasks to check cancellation cleanup.

Keep a minimal context-free C wake thunk where the foreign-thread callback
contract requires it. The thunk may read an initialized native thread ID, post a
Win32 thread message and maintain native atomic diagnostics. It must not retain,
release or access MoonBit objects. The callback must call that FFI directly:
capturing a MoonBit proxy object would violate the async library's documented
foreign-thread restriction. Application policy and task sequencing stay in
MoonBit; the thunk does not create workers or implement a scheduler.

Destroy the test application HWND in `ExternalEventLoop::terminate`, after the
async main task and its child tasks have completed. The runtime performs further
cleanup after `async fn main` returns, so dropping the host directly at the end of
main would be premature. Verify the final success record from terminate, not
merely from main.

The isolated lifetime correction also destroys the message-only HWND after
application windows and the waiter have stopped. Keep the process-single-instance
restriction and process-lifetime class/IMM caches. Preserve input errors through
termination and rethrow after cleanup; a cleanup result cannot hide main failure.
The [resource experiment](../verification/native-resource-cleanup.md) records
the local patches, handle-count comparison and untested failure paths.

For the next GPU integration comparison, reuse the existing `native_gpu`
renderer and initialization owner unchanged. Obtain HWND and HINSTANCE from the
candidate's public window API and convert them through the published wgpu binding;
do not add another handle or renderer bridge. Finish initial presentation before
starting application I/O/tasks. Derive surface dimensions from window events and
verify requested client dimensions rather than substituting outer-window sizes.
On termination, require no pending initialization, then release renderer, surface
and instance before destroying the application and message windows. Track this
adoption prerequisite in [Issue 75](https://github.com/dijdzv/metonic/issues/75).

Explicit redraw requests use the candidate's existing MoonBit queue so hidden
development windows do not depend on OS paint delivery. Pending redraws suppress
OS waiting for that pump. Client-size requests use Windows style/DPI adjustment
through borrowed-buffer FFI, preserving the requested client dimensions. The
[GPU integration record](../verification/windows-gpu-external-loop.md) describes
the direct ABI inspection and measured boundaries.

## Reproducible adoption workspace

Share the Windows external-loop adapter through `native_host/windows_loop`.
The adapter owns timeout forwarding, the context-free wake boundary and poll/wake
diagnostics. It accepts the application's window handler and a termination
callback rather than embedding scenario state or GPU policy. Applications retain
their window/GPU ownership and perform ordered cleanup in that callback after
the async runtime has joined its tasks. The adapter does not destroy windows on
their behalf. Keep the adapter out of the handler state to avoid a reference cycle
between the stored handler and termination closure.

Prepare adoption in a separate native workspace that includes the root module
as a workspace member. Import `local/p0/native_gpu` and the existing scene/task
packages directly; do not copy their source into a dependency module. Keep the
root module's browser/default command scope unchanged.

Source preparation uses fixed window and async archives with SHA256 verification
and the reviewed local patches. Reconstruct the patched source tree before
reusing prepared sources and reject differences rather than silently accepting
local edits. Offline preparation requires verified cached archives. Keep the
archives and extracted dependencies under ignored `.work` paths, and provide a
CommonJS boundary for dependency prebuild scripts without changing the browser's
ES-module configuration. Track adoption and runtime parity in
[Issue 77](https://github.com/dijdzv/metonic/issues/77).

## Consequences

The existing worker probe stays intact during comparison. Passing this experiment
would establish the tested I/O and task-lifetime integration; it would not prove
arbitrary MoonBit closure execution on OS threads, GPU initialization behavior,
real input, IME, or complete resource cleanup.

In particular, joining the async waiter is distinct from closing its Windows
thread handle, and dropping an application HWND is distinct from destroying the
candidate's message-only HWND. Track those ownership paths separately before
product adoption. No upstream source changes are published by this decision.
