# Owned components and application state

Metonic supplies `Graph`, `Signal`, `Memo`, `Scope` and typed `Store` fields for
state, and `core/component.UiRoot` for owned controls. These are experimental public source
APIs, not a stable published package. Start an independent workspace using the
[source-consumer instructions](application-entry.md#external-workspace-builds)
and pin the framework revision. The executable
[quote board](../consumers/metonic-quote-board/README.md) and
[gallery](../examples/component_gallery/gallery.mbt) show the integrated API.

## Choose the state owner

| Lifetime | Current pattern |
| --- | --- |
| One component | Create Signals/Memos under its owner Scope; dispose them with that owner. |
| One screen or document | Keep the shared model in an ancestor Scope and pass the needed references to children. Removing one view need not remove the model. |
| One application | Keep settings and shared models under that application's root Scope. Separate applications have separate roots. |

Derived nodes must not depend on a shorter-lived child. Promote shared state to
the appropriate ancestor instead. `Memo` computes synchronous derived values;
its evaluation must not write state or start I/O. `Store::new(owner)` uses that
owner's Graph and Scope. Create independent typed fields for the model values
that must invalidate independently:

```moonbit
let store = @reactive.Store::new(document_scope)
let title = store.field("Inspect entry light")
let details = store.field("Check the switch and lamp.")
let title_for_view = title.read()
let label = @reactive.Memo::new(document_scope, () => title_for_view.get())
store.batch(() => {
  title.set("Replace room filter")
  details.set("Confirm the replacement size.")
})
```

`StoreRead[T]` exposes tracked `get` and untracked `peek`, not a setter. Keep
`StoreField[T]` with the model owner and pass the read handle to consumers.
The compiler does not make a mutable `T` immutable: do not expose a mutable
Array, Ref or other shared object through a read handle without copying it or
transferring ownership. `Store::batch` uses the existing Graph batch for fields
on that Graph, so observers see the final combination after the outer batch;
it is not a rollback transaction. Wrapping an entire model in one Signal does
not establish field-level invalidation. A general Context/provider API is not
supplied.

## Ordered keyed state

`Store::keyed()` creates a `KeyedStore[K, R, W]` under the document Store's
Scope. `K` must support equality and hashing and remain immutable while in the
collection. Define an item-specific read
projection `R` containing `StoreRead` fields and a writer projection `W`
containing the corresponding `StoreField`s. `insert(key, builder => (read,
write))` makes those fields through `StoreItemBuilder::field` or `field_by`.
The builder is usable only during insertion. Keep `W` with the model owner;
pass `KeyedStore::read()` and its `KeyedItemRead` values to consumers. The
collection's read-only API does not expose the writer projection.

For a retained item, call `KeyedItemRead::fields()` on each read and handle
`StaleItem` before accessing a field. This checked access tracks item liveness,
so removing the item invalidates a Memo even when the projection contains no
reactive fields. Avoid retaining a raw `StoreRead` or `StoreField` beyond that
item's lifetime.

`keys()` tracks order and returns a copy. `lookup(key)` tracks membership and
returns a generation-bearing item handle; `fields()` checks that its generation
is still live. Changing one item field does not invalidate order, membership,
or other item fields. Reordering changes only order and retains item handles.
Insertion and removal change order and membership. The first lookup policy
invalidates all membership readers on any insertion or removal, even when a
different key changes; it does not do so on field edits or reorder.

Duplicate insertion, unknown removal and an incomplete, duplicate or unknown
reorder return a typed error without changing the collection. Removing an item
retires its field nodes and registrations. Recreating the same key issues a new
generation; old `KeyedItemRead::fields()` and `KeyedItemWrite::fields()` return
`StaleItem`. A field projection obtained *before* removal must not be used
afterwards: its underlying Store field follows the existing disposed-Signal
contract. Retaining an item handle does not keep the retired field payload or
registrations in the collection. A document-level Memo may read item fields
because their dependency Scope is the document's Scope, while the keyed
collection releases each item's nodes when it is removed. The Graph rule
against longer-lived readers depending on a shorter-lived Scope remains.
Structural edits attempted from inside the same collection's item factory
return `ReentrantEdit`, and an owner closed during construction retires the
partially built fields before returning `ClosedStore`.

`Store::batch` can group remove/reinsert and field updates, including a
same-key recreation. Observers run after the outer batch and see the final
generation. Reads made explicitly *inside* a batch see the state at that point;
there is no rollback. Bound UI lists apply structural changes at the next
application synchronization boundary.

## Construct controls once per owner

Create `UiRoot::new(scope, tree)` using the application's Scope and semantic
Tree. Use `ui.fixed("editor")` for a retained region. For dynamic keyed regions,
use `KeyedChildren::reconcile` and `ui.adopt(child_owner)` so controls and the
existing child Scope share one lifetime. Do not recreate controls in `view`.
Keys must be unique for the corresponding owner; recreating a removed key gives
it a new generation, so old references cannot target the replacement.

The following initialization excerpt assumes `ui` already exists and uses
`@component` and `@reactive` for those public packages:

```moonbit
let owner = ui.fixed("editor")
let text = @reactive.Signal::new(owner.scope(), "")
let input = owner.text_area(
  "body",
  "Note",
  @component.Controlled::tracked(
    owner.scope(),
    () => text.get(),
    value => {
      text.set(value)
      None
    },
  ),
).unwrap()
let clear = owner.button("clear", "Clear", () => {
  text.set("")
  None
}).unwrap()
let heading = owner.label("heading", @component.Read::constant("Note editor")).unwrap()
```

Use `Read::tracked(scope, sample)` or `Controlled::tracked(scope, sample,
commit)` when `sample` calls tracked `get` on Signals, Store reads, or Memos.
Use `Read::constant` for fixed values. The existing `Read::new` and
`Controlled::new` remain useful for nonreactive values or `peek` closures,
but poll at each synchronization boundary. The tracking Scope must be able to
read every dependency according to the Graph lifetime rule: place a component
under its document Scope when its input combines document state with local
state. The component owner disposes its subscription; dispose or rebind the
component when its source Scope ends.

`Read` and `Controlled` use the existing reactive Graph. Tracked inputs prepare
desired values when dependencies change, then apply semantic changes at the
host's existing event boundary; they do not introduce another scheduler. The
Controlled callback receives committed edits and may return a task Request.
The semantic editor keeps selection and IME composition. The host avoids
overwriting active composition and rechecks rejected edits even if the model
value did not change. Unchanged text preserves selection. This contract does
not imply physical IME verification on every OS.

## Connect the existing Application boundary

Set `Application.components` to `Some(ui)`. Route `activate` through
`ui.activate(reference)` and `edited` through
`ui.edited(edit.target, edit.text, edit.revision)`. These return the Request for
the host to submit; do not submit it again from the callback. Low-level controls
can coexist, but their explicit dispatch remains the application's responsibility.
The quote board's Save note button is an example of remaining low-level dispatch.

Render handles with `core/application.label`, `button`, `input`, `checkbox`,
`list`, `list_item` and `status`, supplying bounds. `Widget`, `StackItem`,
`Stack` and `ScrollView` compose layout over the shared `core/layout` contract.
Wire scrolling/reveal through `Application.viewport` when using a viewport;
creating a ScrollView alone does not install application callbacks.
The current layout does not virtualize the model or dispose offscreen owners.

The first group includes Label, Button, TextInput, TextArea, Checkbox, selectable
List, Status and a separate Retry Button. List uses an application-owned
`Signal[Key?]` for selection; focus navigation and selection are distinct.
Reordering keeps keyed owners, while removing a selected row clears selection.
Call `list.bind_rows(Read::tracked(scope, () => rows.get()))` to derive rows
from a tracked source. Return a fresh row array from the sample; the list copies
it before applying changes. `list.track_selection(scope)` also avoids polling
the selection Signal. Bound rows and manual `list.reconcile` cannot be mixed.
Row structure and selection are applied together at the application boundary,
while a field change unrelated to the row source leaves its owners untouched.
Loading/error/previous-result messages derive from application async state;
Status does not own requests or a separate loading state machine.

Pass a valid `core/theme.Theme` to UiRoot or replace it with `ui.set_theme` at
an application event boundary. The hosts consume the same theme. Text-layout
reuse exists, but neither a whole-model update nor a theme change promises
minimal GPU submissions. See the [measured scope](verification/phase5-component-theme.md).

## Keep asynchronous state and resource ownership explicit

Use Source/Current for admitted async state, DownstreamRegistry for derived work,
PublicationRegistry for complete current/previous displays, and SerialRegistry
for ordered writes. Connect the registries and Sources in `connect_tasks` and
provide the corresponding Application fields. Keep app-owned saves alive when
a removable view disappears. Do not mirror every Source into a second store.
See [application tasks](application-tasks.md) and the
[multi-source contract](adr/037-phase5-external-quote-board.md).

Shared operation contracts include `capabilities/clock` and `capabilities/http`.
An injectable boundary need not live in that folder: native clipboard tests use
`core/text_clipboard.Backend`, while native and browser storage deliberately
have different persistence and shutdown guarantees. Host-owned GPU, window and
DOM resources keep their platform boundaries. Choose test substitutes at the
boundary being tested; substituting storage or clipboard contents does not
substitute OS input delivery. The [resource responsibilities](application-entry.md#resource-responsibilities)
and [capability policy](adr/033-capability-platform-boundaries.md) define this split.
