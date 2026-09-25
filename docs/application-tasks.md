# Application work and event-thread completion

`core/application_task` defines a small boundary for asynchronous work that must
finish by updating an application's UI state. `work` pairs an `async () -> T`
operation with a `(T) -> Outcome` completion. The result retains its concrete
type inside the closure; the host does not need a union of every application's
HTTP responses and other result types.

`work_with_progress` adds non-terminal completions from a running operation.
The Driver posts them through the same host result callback without retiring its
operation lane. It checks the current lane before delivery and again when the
host applies a queued progress result. The Scope-owned Resource adds its own
lifetime and admitted-generation check. A worker may record an external write
fact, but updates to reactive UI state belong in the delivered completion.

Running work produces a `Completion` without invoking the state update. The host
queues that completion and calls `apply` on its event-processing path. Applying
the same completion twice invokes the application only once. `Changed` requests
a redraw, `Unchanged` needs none, and `Rejected` exposes a rejected stale result
to host diagnostics. Application lifetime checks still determine whether a
result is current; single delivery alone does not make a result current.

For an exclusive replaceable operation, a `Request` carries invalidation and
preparation callbacks. `async_runtime/application_task.dispatch` performs them
in this order:

1. Invalidate the previous application operation's identity.
2. Cancel and await the previous task, preserving non-cancellation failures.
3. Prepare the new work on the event path.
4. Spawn it in the caller's official async task group and post its completion.

A cancel request prepares no work. The caller processes requests serially and
retains the returned task for replacement or shutdown. There is no additional
scheduler, worker pool or global task registry. Parallel application operations
can use separate owned task slots; the helper does not impose a single global
operation on an application.

## Ordered writes

`core/reactive_task.SerialRegistry` connects Scope-owned `SerialTask` writers to
the same Driver. Register one writer under the application Scope for each
independent document or write lane. `enqueue(identity, value)` captures the
caller's immutable write value and places it after any active write in that
lane. A later edit may enqueue a newer revision while the earlier write is
running; it does not replace that write. Acknowledgements and failures are
applied on the host event path through the caller's `on_applied` callback.
The next write is admitted only on a later host reconciliation after that
callback returns. Separate writers can run concurrently.

An application passes `Some(registry)` as its `serials` field and connects it
in `connect_tasks`. The native and browser hosts reconcile it alongside
derived downstream requests. The caller can inspect `snapshot()` for the
active job, queued jobs, last completion and admission rejection. A rejected
admission remains queued until `retry()` is called; it never appears as an
active write. Duplicate identities already active, queued or successfully
acknowledged are ignored. `cancel()` or disposal of the owning Scope requests
Driver cleanup and prevents a late acknowledgement from changing UI state.

The native caller and host-boundary check in
`native_host/notes_probe/serial.mbt` shows two revisions entering one writer;
the browser application probe exercises the same contract on JS and WasmGC.
An app-owned writer must not be placed under a transient UI child's Scope when
its acknowledgement needs to survive that child disappearing.

Before shutdown, the application invalidates its lifetime and the host cancels
and awaits owned tasks. Queued results must still pass the application's
lifetime guard. Preparation and invalidation are synchronous; only the work and
task cleanup suspend. This boundary is for operations crossing an asynchronous
event boundary, not a requirement to represent ordinary editing as commands or
replace fine-grained state updates.

The current native and browser workspaces pin different async versions. Native
cancellation waiting handles the 0.21 cancellation error; the browser workspace
uses the 0.22 `TaskCancelled` result for a canceled child. Both preserve caller
cancellation and other failures. These backend files follow the existing pinned
workspace configuration and must be reviewed when those dependencies change.

`examples/p0/tasks` defines delayed movement and user loading with injected
Clock/Http implementations and the existing application task scope. The native
adapter supplies the real clock and bounded, timed HTTP transport. The native
event loop handles generic requests/completions; P0 shortcuts and action routing
remain in its adapter. The current browser application host also uses the shared
Driver for requests and completions.

Tests exercise deferred single application, queued stale results, replacement
cleanup order, failure propagation, virtual-time movement and controlled HTTP
against the same P0 work definitions. They run on JS and native through the
configured workspaces. WasmGC receives a compile check; this alone does not
establish WasmGC event-loop execution of these jobs.
