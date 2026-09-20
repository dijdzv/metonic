# Native accessibility presentation

The native AccessKit bridge consumes semantic nodes from `core/semantics` and an
application-defined `Presentation`. It does not import the P0 model or identify
controls by sample IDs. `native_host/p0_accessibility` maps the sample's controls,
moving toggle and status text into this representation.

A presentation provides the window title and client size, one `Control` for each
semantic node, optional `Status` elements, and optional retained-text ownership.
Controls supply exact `NodeRef` values, bounds and optional toggle states. Their
order need not match semantic registration order. Toggle state is only valid for
a button. Duplicate semantic IDs, missing controls, stale references and invalid
text-owner roles are rejected. Bounds may be empty but cannot have negative size.

Semantic IDs remain in the positive `Int` range; status IDs occupy
2147483648–4294967295. Applications choose distinct status IDs in that range.
The bridge allocates text-fragment IDs starting at 4294967296, independently of
application control order. It still supports one active native bridge per
process, matching the current window-loop integration.

`open` validates before attaching. `Bridge::update` returns false if the bridge
is closed or presentation/layout validation fails; callers must handle this
result. Valid updates copy node and presentation arrays and text-layout cells,
so later mutation of supplied arrays cannot change the published snapshot.

The optional `text_owner` identifies the input whose full text layout is supplied
with the update. That input exposes character geometry and selection; other
inputs retain their value/focus actions. The current bridge retains one full
text layout, not an independent text provider for every input. Its composition
flag advertises that retained input as read-only, omits its published selection,
and rejects selection resolution while composition is active. The P0 adapter
preserves its existing composition policy and input-action guards.

Layout offsets must be valid UTF-16 boundaries in the owner's current value.
Changes to owner identity, text or layout replace fragment IDs; scrolling or
status changes alone preserve them. Selection requests referencing replaced
fragments are rejected. The supplied scroll offset and control bounds determine
the published geometry, so neither the sample editor position nor its ID is
embedded in the bridge.

This boundary is independent of development CLI/MCP. Production accessibility
continues to operate without those development entry points. The existing native
accessibility integration gate verifies P0's UI Automation behavior; independent
presentation tests cover alternate IDs/order, retained-text ownership, stale
references and snapshot ownership.
