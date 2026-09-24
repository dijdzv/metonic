# Reactive Notes lifecycle acceptance

At the recorded Issue #504 acceptance run, the independent Notes source
consumer pinned framework revision `47fdff0` (the current pin is in
`consumers/metonic-notes/dependency.json`) and used one Scope-owned Resource
each for search and save. The consumer's
workspace, query, persistence state and control availability feed Memos and
Bindings; ordinary updates keep editor and action references.

`common/model/reactive_lifecycle_test.mbt` exercises one model sequence:
create and edit two notes, fail and retry a save, filter and select a semantic
row, clear the query, delete and save, then stop with a prepared search result
and failure pending. It asserts persisted content, status, semantic row removal,
rejected late callbacks, two distinct cancellations, and one storage disposal.
The same source test runs in the JS and Windows native model suites. The
WasmGC test runner does not execute async tests; the browser WasmGC host flows
below exercise real asynchronous work instead.

| Boundary | Verification | Observed result |
| --- | --- | --- |
| Consumer model, JS and WasmGC | `mise -C consumers/metonic-notes run verify:model` | JS 56/56; WasmGC synchronous 20/20 |
| Consumer model, Windows native | `mise -C consumers/metonic-notes exec -- moon -C native test ../common/model --target native --deny-warn` | 25/25 |
| Browser host, JS and WasmGC | `mise -C consumers/metonic-notes run verify:browser` | Both targets: create/edit/select, delete and discard, restart, storage failure and retry, search and semantic selection, schema failure and retry, empty state, then stop; collection and dynamic-list checks passed |
| Windows native host | `mise -C consumers/metonic-notes run verify:persistence` | Two-process sequence: create/edit/select, close cancellation, failed save without snapshot corruption, retry, search and semantic selection, discard, window close and restart, restored content, delete and discard, then window cleanup passed |
| Source dependency | `mise -C consumers/metonic-notes run verify:source-contract` | Pin, dirty-checkout rejection and missing-bootstrap checks passed |

The browser and native host scenarios are separate from the model lifecycle
test: a model assertion alone does not prove WebGPU rendering or Windows window
behavior. Conversely, these automated paths do not simulate physical IME input.
The shared Resource rejects stale callbacks at the UI event boundary; the
existing Driver remains responsible for joining asynchronous cleanup.
Autosave emits a non-terminal Driver result when its debounce ends. The host
applies that progress, updates control availability and requests a redraw while
the save lane remains active. The async worker and its cancellation cleanup do
not write reactive Signals. A successful storage call records its snapshot before
the UI completion is applied; replacement reconciles this write fact, and Scope
disposal rejects the UI result without erasing it. Controlled tests cover a
blocked write after progress, retirement before stale completion, and a write
that finishes after Scope disposal. The browser JS/WasmGC autosave and search
flows and native persistence probe passed with this consumer revision.
The model sequence supplies the subscription and resource observations: two
independent lane cancellations, rejected late callbacks and failures, and one
storage disposal. Browser stop and native window close supply host cleanup
observations. Together with the complete host sequences above, this is the
recorded acceptance path for Issue #504; it does not imply that a host script
can inspect internal subscription counts by itself.

`Collection::view` still projects viewport layout, clipping, status text and
the current unflushed editor value into Controls. Status includes the semantic
input value and input error. Those are host view-time values, not stable
semantic-node properties. Bindings instead own persistent row identities and
control properties. This projection does not walk the whole collection to
synchronize its state.
