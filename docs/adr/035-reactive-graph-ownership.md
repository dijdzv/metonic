# ADR 035: Own the reactive graph and bind it to persistent UI lifetimes

Status: Accepted for the Phase 3 core; the consumer integration and scale
acceptance remain open.

## Context

Metonic keeps UI nodes and semantic references across updates. The browser and
native hosts own input, frames and GPU resources, while `application_task` owns
asynchronous work. A reactive library for DOM components cannot decide those
lifetimes or the required layout, text, paint and semantic invalidation stages.

The published `mizchi/signals@0.6.5` offers dependency tracking, Memo, batch and
Owner. In a separate fixture using Metonic's pinned compiler, dynamic branch
replacement, a nested-batch diamond and ordinary cleanup passed on JS, WasmGC
and native. On all three targets, an unchanged parity Memo still reran its
observing render effect; registering an effect under an already-disposed Owner
also left a live subscription. A bounded effect writeback stopped after one
write rather than reaching its final value or rejecting the write. These are
observed differences from the contracts required here, not a general judgment
on the library. `bikallem/rsignal@0.3.0` uses explicit subscriptions and mapped
signals; it does not provide the required dynamic dependency graph.

The published signals package names a GitHub repository that returned 404 to
our authenticated repository lookup on 2026-09-23. A current upstream patch
target could not be confirmed. If one becomes available, the reproductions can
be proposed upstream. Metonic does not make that upstream change a prerequisite
for its own component and renderer architecture.

## Decision

Implement a small MoonBit reactive graph in `core/reactive`, owned by Metonic.
This adopts dependency-tracked state, not Solid's component construction or DOM
update model. Each application owns a Graph. A Scope owns its subscriptions and
child scopes; a dependency may outlive its observer, but not the reverse.
Cross-graph tracked reads are rejected. Component construction retains its UI
nodes and semantic references; Binding updates properties of those nodes and
lets the host coalesce only the affected rendering stages.

Signal and Memo accept `Eq` or an explicit comparator. A Memo is lazy and
publishes a new version only when its value changes. Dynamic reads replace its
dependencies. Batch delays reactions until the outermost boundary, while reads
inside a batch see current values. Untracked disables dependency collection,
not the prohibition on synchronous writes during computation, comparison,
Binding application, Effect execution or cleanup. Such writes are rejected as
programmer errors rather than silently dropping an update.
The transformation passed to Signal.update is evaluated under the same guard.

Bindings and reactive Effects execute synchronously when created outside a
batch; creation inside a batch runs at its outer flush. Effects own ordered
cleanup and are for external connections, not a chain of derived Signal writes.
Scopes invalidate subscriptions immediately on disposal. Callback and cycle
violations currently abort the process with a diagnostic; recovery after such
a programming error is not promised. The graph is confined to the UI thread
and never tracks reads across an async suspension.

`capabilities/clock` and `capabilities/http` remain external capability ports.
The Driver has an operation-scoped cancellation control that does not use the
normal Request queue. It rejects a posted result immediately but retains the
lane until running cleanup exits; a replacement of that Operation waits for
the cleanup. `core/reactive_task.Resource` owns one Operation under a Scope,
builds normal replace/cancel Requests, and asks that cancellation control to
retire its lane on disposal. Request admission advances the Resource generation;
constructing a Request alone does not. Completion and failure callbacks apply
at the UI event boundary only while the Scope and generation remain valid.
A cancellation request is not proof that asynchronous cleanup has joined.
No second runtime or frame loop is introduced.

## Consequences and next evidence

The core contract tests can run without OS or GPU services on JS, WasmGC and
native. Negative cycle and reentry cases need isolated-process checks because
they intentionally abort. This initial package does not establish the memo
consumer integration, host invalidation granularity, accessibility behavior or
1,000-item performance. Those are separate Phase 3 acceptance steps. The
[library comparison](../verification/library-reuse.md) records candidate
evidence; current implementation work is tracked in Issues #500 and #501.
