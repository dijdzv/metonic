# ADR 036: Propagate owned async results through the reactive graph

Status: Accepted for Phase 4. `core/reactive_task.Source`, `Cycle` and
`derive_pair` implement the contract, and the
[two-host application verification](../verification/async-pair-phase4.md)
records the integrated checks. See
[#567](https://github.com/dijdzv/metonic/issues/567) and the
[pre-change baseline](../verification/reactive-phase4-baseline.md).

## Context

ADR 035 gives Metonic a synchronous, Scope-owned reactive graph. A Memo tracks
its reads and cannot suspend; Effects and Bindings cannot start or modify
reactive work while evaluating. `core/reactive_task.Resource` wraps one
operation in the shared Driver. Admission advances its generation; application,
failure and progress callbacks are rejected after replacement or disposal. The
Driver owns execution, cancellation and joined cleanup. This is the accepted
Phase 3 B path, but an application still manages its own waiting, previous,
failure and multi-result state.

The current `Application` entry returns at most one Request from each event.
A selected item that needs a detail request and a related-items request cannot
submit both independently from that event through this entry. Treat that as an
application API gap, rather than forcing the two results into one work operation
or making a view callback launch work.

## Decision

Keep async execution in Driver/Resource and reactive derivation synchronous.
Expose a Scope-owned, keyed async state value backed by a Signal; ordinary Memos
derive display values from those states. Async suspension is never dependency
tracked. A source's state has these observable phases:

| Phase | Meaning |
| --- | --- |
| Idle | No admitted request or retained result for this source. |
| Pending | An admitted request is active for a key and cycle. It may carry a previously completed value only when that value belongs to the same key and the caller chose retention. |
| Ready | The current key/cycle completed with a value. |
| Failed | The current key/cycle failed with an explicit error. A retained prior value is separately visible, not reclassified as success. |
| Canceled | The current key/cycle was canceled. It is no longer pending; a retained prior value follows the same key rule. |

The cycle is a shared identity for a group of related requests, not a timestamp
or an application-visible cache key. A new selection or coordinated refresh
mints a new cycle. The key identifies the requested subject. Two independently
fetched values combine into a current result only when **both** are Ready for
the selected key and the **same cycle**. An older detail cannot combine with
new related items merely because both keys happen to match. During a pair
refresh, a previous complete pair may remain visible if the caller chose
retention and both prior values belong to one earlier cycle for that key.
Otherwise the derived view is pending; partial new data does not masquerade as
a complete pair. One source's failure makes the current pair failed with a
retry action, while a retained previous pair stays identifiable as previous.

First load has no previous value. A refresh can keep a previous value without
claiming the new request succeeded. Changing the selected key clears visible
previous data for that subject; a result from the old key cannot populate the
new view. A retry starts a new cycle. An unadmitted proposal changes neither
source state nor the selected cycle. A canceled or disposed source cannot later
publish success, failure or progress from that flight. The cancellation request
does not imply cleanup has joined; the Driver still gates replacement on joined
cleanup.

Application events need a way to return multiple independently owned Requests.
Admission of a related set must be all-or-none after checking command and lane
capacity and duplicate operation identities. On acceptance, publish the cycle
and each source's Pending state within one Graph batch, then let the Driver run
the operations independently. On rejection, publish none of them and report
the existing capacity/input failure. A partial admission cannot leave a view
waiting forever for an operation that was never queued. The exact public batch
type is an implementation task; it must preserve current single-operation
behavior during consumer migration.

Allocate the observable state in the component Scope, so a sibling Memo/Binding
does not depend on a shorter-lived Resource child Scope. The Resource still
owns its operation in a child Scope. Explicit resource disposal may publish a
terminal state before disposing that child; Scope cleanup itself is write
guarded and must not call `Signal.set`. Disposing the component Scope invalidates
its readers and rejects late callbacks without trying to render another state.

All admitted success, expected failure and progress updates pass through the
same Resource/Driver generation and host application boundary. Unexpected work
failure also enters an observable failed state and remains reported through
the host error channel. A computation waiting on a source does not execute an
effect with an invented value; it derives an explicit pending/failed view.
Memo evaluation and Binding application do not start requests, mutate storage,
or write reactive state. A save that actually reached storage is an external
fact: superseding an obsolete UI response may suppress its presentation but
must not erase the successful storage acknowledgement or mark unsaved data as
saved without matching the saved revision.

## Solid 2.0 comparison

[Solid's async-data RFC at revision 886850b](https://github.com/solidjs/solid/blob/886850bfc721a4f5bcd414c0ca934832a608b495/documentation/solid-2.0/05-async-data.md)
allows async computations and uses Loading boundaries, pending queries and
previous-value reads for coordinated updates. Metonic adopts the requirement
that derived values can express not-ready data and preserve an earlier view
without mixing incompatible answers. It does **not** adopt implicit async
tracking across suspension, automatically held graph transactions, SSR/hydration,
AsyncIterables, optimistic stores or a new frame scheduler. The explicit state
and cycle fit Metonic's existing Driver admission and host-owned UI boundary.
Those larger features need a separate consumer and acceptance case before
consideration.

## Acceptance before marking this ADR accepted

- A platform-free state/combination test covers first load, paired refresh,
  retained complete prior pair, same-key different-cycle results, key change,
  one failure, cancel and retry. Assert the visible view, not only private
  generation counters.
- The Driver admission test covers two independent operations accepted together,
  capacity rejection without either invalidation, duplicate identity rejection,
  and the existing single-request path. Verify cleanup ordering independently.
- A small external-style example requests selected-item detail and related
  information separately from one action, presents their derived result and
  failure/retry state, and runs through native and the primary browser backend.
  JS remains a comparison target for the shared browser behavior.
- Stale progress/success/failure after replacement or Scope disposal cannot
  update either source or combined presentation. A storage-success control
  demonstrates that UI staleness does not erase an external success fact.
- Re-run the [synchronous graph baseline](../verification/reactive-phase4-baseline.md)
  and the existing 1,000-memo input-response scenario after implementation.
  Explain material regressions instead of relaxing the fixed acceptance limits.
