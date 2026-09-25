# Development async diagnostics

The optional `TraceRegistry` describes live async Sources, derived values and
their Scope owners without retaining application values. Create it only in a
development entry, pass it to the development host, and register the owners and
Sources whose behavior matters. A production application need not construct or
pass a registry.

Register a root owner with `track_owner(scope, None, ApplicationOwner, 0)`, then
register Sources with `track_source(source, owner_id, key_id)`. `key_id` must
return a stable, opaque integer for each key; it must not encode user text,
credentials or saved content. A component uses a child Scope and
`ComponentOwner` with its parent owner ID and instance generation. For a live
combined value, `track_derived(scope, id, owner_id, sample)` accepts a read-only
function returning `Current[T]`. The sampler runs without reactive dependency
tracking when the snapshot is read. It must not start work, write state or
perform I/O. IDs are meaningful within one registry instance, not across app
launches.

The snapshot contains `owners`, `sources`, `derived`, `events`, `capacity` and
`dropped`. Source rows include owner and Operation IDs, opaque key ID, Cycle,
admission ID, state revision, phase and generations whose cancellation has been
requested but whose cleanup has not joined. Derived rows include their owner,
phase and immediate source causes or ready origins. Event rows use the same IDs
and distinguish admission, rejection reason, expected and unexpected failure,
stale progress or completion rejection, cancellation request, cleanup join and
disposal. The ring holds 1–1024 events; `dropped` counts overwritten events.
Failure messages, request bodies and displayed values are not serialized.

For native development, the existing application-control `snapshot` response
adds `diagnostics` when the debug host receives a registry. The
`async-pair:diagnostics-test` task exercises that route through a separate
development entry. Browser development uses the dedicated
`/async-diagnostics/` entry and its `metonicAsyncDiagnostics()` inspection
function; `async-pair:diagnostics-browser` exercises both JS and WasmGC. The
ordinary release inventory does not include either development entry.

The browser release packager scans its fixed asset inventory for diagnostic
entry markers and verifies that the production WasmGC module does not retain
diagnostic history strings. The native release entry has no diagnostic
controller. The diagnostics fixtures and release checks are separate so an
inspection helper cannot silently become a required application API.
