# ADR 037: Exercise multi-source async state and component ownership in an external quote board

Status: Accepted for the Phase 5 user journey, coherence and ordering
constraints. The remaining application and ownership work is tracked separately.
[Issue #585](https://github.com/dijdzv/metonic/issues/585) tracks acceptance of
this contract.

## Context

ADR 035 supplies a Scope-owned synchronous graph with dynamic Memo dependencies.
ADR 036 supplies keyed Sources, coordinated Cycles, grouped admission and a
two-Source `derive_pair`. The existing paired example demonstrates independent
detail and related work. It cannot establish a reusable contract for three or
more Sources, an independent result that changes on its own schedule, or a
downstream request that starts when a derived upstream result becomes ready.
The independent Memo application exercises dynamic controls and storage, but
its own application model cannot serve as the sole proof of external adoption.

## Decision: user operation

Build a separate source consumer for an item-and-quote board using the documented
application entry. The first vertical slice may use deterministic, controllable
data and the current low-level controls; it must pass requests through the real
host Driver. Do not copy Memo modules or import host implementation packages
into application-common code. Native, browser JS and browser WasmGC run the
same common application model; WasmGC remains the primary browser target.

The app selects an item, fetches its **detail A** and **stock B** under one
item key and coordinated Cycle, and fetches a **currency rate C** under its own
currency key and Cycle. The yen display does not read C; another currency's
converted display does. When the current A/B pair is complete, the app starts
a **shipping quote D** for that pair and the edited quantity. D is a distinct
owned operation and carries the A/B provenance plus its own request generation.
The app also edits a note and saves it through an independent, app-owned
persistence operation. Product names and fixture values are illustrative; this
four-Source dependency relationship is the required test case.

The first end-to-end path is: select an item; observe A or B finishing first;
observe the coherent pair; observe D start and finish; edit quantity and note;
save; refresh; switch item and currency during pending work; fail one request
and retry; remove and recreate the detail component before an old completion;
close after work has retired. Each step has a visible state and a bounded
automatic assertion. The app's package checks use the public source entry from
its own workspace, without manual edits to dependency sources or host copies.

## Observable state and coherence

| Event | Required observable result |
| --- | --- |
| First selection | A/B are pending for the selected key/Cycle; no invented complete result or retained display exists. C starts only when the chosen currency needs it. |
| One of A/B completes | Partial data may be identified as partial, but D does not start and a current complete item/quote is not reported. |
| A/B both complete | The pair is current only if both keys and Cycles match the selected item. A single D proposal becomes eligible at the application event boundary. |
| C completes independently | A/B and D do not change Cycle. A converted display uses C's own currency key/Cycle; it is not assigned a fictitious common Cycle. The yen branch does not depend on C. |
| Same-identity refresh | A previously complete aggregate may remain visible only as a previous result, with its original provenance, while new work is pending. Partial new results never overwrite it as current. |
| Item, quantity, currency or conditional branch changes | The old *combined display* snapshot is released. A/B may remain current after a quantity or currency change if their own key/Cycle remains valid; D may remain current after a currency-only change. A result with an invalid Source input or provenance cannot become the new current display merely because a visible label matches. |
| Failure, cancellation or rejected admission | The reason and affected owner are observable. Rejection does not publish Pending for work that was not admitted. Retry is an explicit later action; no unbounded automatic resubmission loop occurs. |
| Detail component removal/recreation | Its Scope, D operation, subscriptions and semantic controls become invalid. A late success, failure or progress from the old generation cannot update the new component with the same item key. Requesting cancellation is distinct from the Driver's joined cleanup. |
| Save completes after UI change | Storage success and saved revision remain an app-level fact, even if the originating component or its presentation request is stale. Acknowledging revision r cannot mark a newer edit r+1 saved or roll back a later acknowledgement. |

Retention uses a previously complete **aggregate** recorded by a
Scope-owned publication of the final display state. It must not be
reconstructed by zipping unrelated per-Source `previous` fields. A retained
aggregate has its original item, quantity, currency branch and Source
provenance. It remains distinguishable from a current successful result and is
cleared when those semantic inputs change. "Published" means a display
snapshot committed at the application boundary, not a claim that a physical
frame was presented.

Related composition requires the expected item key and shared A/B Cycle.
Independent composition preserves the C key/Cycle beside the A/B and D origins
instead of asserting one global Cycle. A multi-stage derivation must retain
the origins of values shared across stages; two paths cannot combine different
generations of the same Source into one current value. A branch that does not
read C must not be invalidated by C. These are contracts for a general derived
async view, not a request for a `derive_pair` alias or app-specific tuple cases.

The proposed common representation separates a pure current result from
history. A `Current[T]` carries Idle, blocked, pending, failed, canceled or
ready state for the active inputs. Ready carries a value and complete
provenance; earlier values never become current merely because they are
retained. Provenance identifies each Source instance and its admitted request
stamp, which in turn is associated with its typed key and Cycle. Source
identity is distinct from a visible key and is never reused after recreation.
The stamp is allocated only on successful admission and published with the
Source state; constructing or rejecting a proposal changes neither. Repeated
admission with the same key and Cycle still receives a new stamp.
A related join checks the expected key/Cycle; an independent join preserves
both origins without requiring a common Cycle. If two derivation paths contain
the same Source with different stamps, their join cannot be Ready. Active
causes are aggregated without depending on join order: failure precedes
cancellation, which precedes pending/blocked; all-idle inputs yield Idle.
Causes from an unselected branch do not participate. `map` and join operations
on `Current` are pure and can be composed in Memos over two or more stages. A
conditional Memo reads only its selected branch; returning to an earlier
branch does not restore history cleared by a changed demand.

A `Publication[T]` belongs to the display owner's Scope and owns the last
complete `Current.Ready` published for one semantic demand. The demand includes
item, quantity and currency branch, but not an incidental refresh Cycle.
The host performs a publication round after initialization, registration and
every applied input or valid progress/completion, including edits that return no
Request and rejected admission. It first applies the event and flushes the
synchronous graph, reconciles pure desired work and submits any eligible
Request to the existing Driver, reflects acceptance or rejection, and flushes
again. It then samples every live Publication's demand and pure `Current` and
builds immutable candidate snapshots. After all samples are complete, it
commits them in one Graph batch outside Memo/Binding/Effect evaluation, flushes
that batch, and only then renders the view. There is no `await`, application
callback, re-entry or Request submission between the end of sampling and the
end of the commit batch; Bindings/Effects see the new published values only
after the whole batch. This ordering prevents a just-admitted D request from
missing Pending until a later event and prevents a reader of two Publications
from seeing a half-updated round.

A Ready candidate replaces that Publication's last complete value. An
incomplete candidate may expose the last complete value only for the same
demand, marked as previous. A changed demand clears it. A discarded or never
sampled transient Ready value is not added to history; a sampled Ready value
can be retained even when frame presentation is skipped. Values published as
complete must not later mutate through shared Arrays/Refs; the API must require
immutable values or transfer/copy ownership on publication. Publication
outputs cannot feed their own or another Publication's input in this first
contract, preventing a publication loop. Scope disposal unregisters the owner
without writing a disposed Signal. The timing and provenance guarantees are
part of this contract.

The first implementation uses `PublicationRegistry::new(root)` and registers
each display with `register(owner, sample)`, where `sample` returns a semantic
demand and `Current[T]`. `Publication::get()` returns a `Published[K, T]?`;
`None` means the host has not published the first round. A published value
contains the current `CurrentView`, and a `previous` whole `Completed` value
only while demand still matches. Both include Source provenance. The
application passes `Some(registry)` in its `publications` field, and the native
and browser hosts invoke the same `Application::publish()` at their event
boundaries. `K` and `T` must be immutable or copied before sampling; generic
deep copying of application values is not part of this API. A component that
removes its owner Scope must also stop reading its disposed Publication.

The downstream boundary is `DownstreamRegistry::new(root)` plus
`register(owner, desired, run)` (or `register_result` for typed failures).
`desired` returns a pure `Current[K]`; a complete value and its provenance form
the child identity. The app passes the registry as `downstreams: Some(registry)`
and connects it in `connect_tasks`. At every host publication boundary, the host
samples all live desired inputs, retires obsolete child work, submits eligible
grouped requests to the existing Driver, then publishes complete displays.
`Downstream::current()` preserves upstream causes while the child is waiting,
exposes Pending only after admission, and combines upstream and child origins
when Ready. Rejection remains blocked until `Downstream::retry()` explicitly
changes the attempt revision. A returned `Bool` from reconciliation reports a
state change, including a rejection; only accepted requests wake the browser
task scheduler. Scope disposal unregisters the child and rejects late results.

## Ownership and request boundary

The Scope tree is app → selected item → detail component. A/B live in the item
owner Scope. C lives in the app Scope because currency work is independent of
the detail component. The detail child owns D, its derived presentation,
semantic controls and subscriptions. Dependencies read by a derived node must
outlive that node's Scope; a parent Memo does not directly depend on a shorter
child Source. Replacing an item owner invalidates its old children and work
before another owner can reuse visible keys. Cleanup does not call
`Source.dispose` from a Scope disposer that forbids reactive writes; the
existing Resource invalidation and Driver retirement path remains responsible.

The save Operation and saved revision live in the app Scope, not the removable
detail child. The event boundary passes a fixed document identity, immutable
save value and edit revision to that owner; the save callback never reads a
disposed detail Signal. Saves for one document are serialized rather than
replacing or canceling an in-flight storage write because its UI became stale.
After the storage acknowledgement is applied, the next queued save may begin.
An acknowledgement for revision r records the external success but does not
clear an unsaved indicator for r+1 or roll back a newer acknowledgement. A
close request waits for the save acknowledgement and joined cleanup or offers
an explicit unsaved decision; it cannot silently discard a completed write.

A pure derived value may describe the desired D input after A/B complete, but
Memo, Binding and Effect evaluation does not submit work, perform I/O or write
reactive state. The host boundary above compares the desired D identity with
the last admitted one and submits a proposal once when needed. D's desired
identity includes the A/B admitted stamps, quantity and detail-owner identity;
C's change alone does not restart D. New desired input makes the old D
non-current immediately, even if a new D proposal is rejected. Its late
success, failure and progress remain rejected for the new display. Rejection
does not publish phantom Pending or trigger a tight resubmission loop; a later
explicit Retry or defined capacity recovery may propose again. The public
callback/type is an implementation decision, but its ordering is fixed above.
Grouped initial A/B admission remains all-or-none. No second scheduler or
implicit tracking across `await` is required.

## Verification and implementation boundaries

Platform-free tests cover reverse arrival order, three or more Source origins,
two-stage and diamond derivation, conditional C dependency, retained complete
aggregate, different key/Cycle, failure, cancellation, rejected admission,
retry, old progress, component deletion/recreation and saved-revision
acknowledgement. They prove that a transient J1 completion while J2 is pending
does not create a retained J2 value; an unsampled transient Ready is not
history; changing only currency reuses valid A/B/D, while quantity invalidates
D but can reuse A/B; a same-value new admission has a new stamp; a rejected new
D does not revive old D; returning to an earlier conditional branch does not
restore cleared history; and two Publications never appear half-committed.
Storage tests cover a completed write before UI acknowledgement followed by
component deletion, item change, further edits and close.
Native and browser JS/WasmGC checks observe rendered text/state, controls,
focus, selection, basic accessibility, cleanup and package contents through
their public application entries. Diagnostics must identify the pending Source
and owner, admission/failure/stale-result reasons and cleanup wait without
logging note text by default. Fixed synchronous-graph and 1,000-Memo benchmarks
remain regression limits; physical IME and assistive-client observations are
reported separately from synthetic tests.

This ADR does not choose a final standard-component API, a new scheduling
runtime, or real network service. Its fixture is a controlled way to prove the
public contract before widening data sources and the component catalog.
Independent deliverables are [multi-Source current composition](https://github.com/dijdzv/metonic/issues/586),
[whole-display publication](https://github.com/dijdzv/metonic/issues/587),
[downstream admission](https://github.com/dijdzv/metonic/issues/588),
[keyed component ownership](https://github.com/dijdzv/metonic/issues/589),
[bounded diagnostics](https://github.com/dijdzv/metonic/issues/590), and the
[external consumer](https://github.com/dijdzv/metonic/issues/591). Their GitHub
blocked-by relationships record actual implementation prerequisites.
