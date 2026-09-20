# ADR 031: Separate time from task ownership

## Status

Accepted for the delayed-operation boundary; implementation acceptance is tracked in
[Issue 419](https://github.com/dijdzv/metonic/issues/419).

## Context

Native delayed movement sleeps inside an existing structured task group. Browser
movement uses host timers and task IDs. Both hosts already reject obsolete
results through application task state. Replacing these lifetime rules with an
effect interpreter would couple an otherwise small time dependency to task
ownership and UI state.

## Proposed boundary

Use a public `Clock` trait with `now` and asynchronous `sleep`. A caller states
its dependency through a type constraint; `after` waits and returns a supplied
value without owning the task or applying that value to application state.
The capability package has no async-runtime import. Host adapters supply the
existing runtime, and cancellation propagates through its ordinary async calls.

Compose concrete adapters at the host boundary rather than requiring every
operation to accept an application-wide Runtime containing unrelated services.
A future Clock/Http operation can constrain only those capabilities it needs.
Do not introduce a Command representation for an ordinary wait.

Virtual time owns deadlines and wake signals, not coroutine execution. The
existing async library suspends and resumes tasks. Waiting registrations must
be removed on completion and cancellation. Tests advance time explicitly and
await the affected tasks; advancing time alone does not promise to drain every
continuation or transitively scheduled operation.

## Time contract

Durations are non-negative Int milliseconds; zero permits immediate completion
but does not promise whether an adapter yields. Negative durations raise
`InvalidTime`. `now` returns the adapter's Int64 millisecond time coordinate;
values from different clocks are not comparable and production time is not a
promise of a monotonic wall clock. Virtual clocks start at a non-negative time
and reject backwards advancement and Int64 overflow without modifying state.

Virtual time wakes elapsed deadlines in deadline order, using registration order
for ties. A pending count includes registrations awaiting coroutine cleanup.
Cancellation and disposal of application work still belong to the task owner;
advancing a clock does not grant a stale task permission to update application
state.

`async_runtime/clock` provides reusable virtual-time support, separate from the
runtime-independent trait in `effects/clock`. It is a workspace module so the
native and browser workspaces resolve their own pinned async implementation.
Its application task-scope dependency is confined to acceptance tests.

The browser adapter retains its host timer ownership. Entering async from a host
timer/reset callback is necessary to resume a condition-variable waiter; merely
signaling it outside the scheduler can leave runnable work unprocessed. This
uses the already-pinned experimental entry, not a second scheduler. The adapter
retains rejection of superseded task results, and reset releases host timers and
suspended waits.

## Required evidence before acceptance

- Production and virtual clocks execute the same delayed operation.
- Deadline boundaries, equal-deadline ordering and cancellation cleanup are
  deterministic without real sleeps.
- Replacement and disposal still reject obsolete results through task state.
- Browser reset/cancellation releases timers, and native task-group ownership
  remains unchanged.
- JS/WasmGC browser and native integration checks pass.

The maintained tests in `async_runtime/clock/virtual_test.mbt` cover deadline
boundaries, cancellation cleanup, stable ordering, stale-result rejection and
invalid time. The same tests run against browser-workspace async on JS and
native-workspace async on Windows through pre-commit. Browser application
behavior is exercised on JS and WasmGC by `mise run browser:async`; the normal
native integration gate exercises production delayed movement and cancellation.

The WasmGC application check does not execute the virtual-clock test suite in
WasmGC. It establishes the production adapter path; virtual-time runtime evidence
currently covers JS and native.

HTTP deadlines, a general scheduler, record/replay and a central Effect enum are
outside this decision.
