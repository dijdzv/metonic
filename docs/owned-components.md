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
on that Graph, so
observers see the final combination after the outer batch; it is not a rollback
transaction. A keyed item collection and tracked list reconciliation are still
separate work. Wrapping an entire model in one Signal does not establish
field-level invalidation. A general Context/provider API is not supplied.

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
  @component.Controlled::new(
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
let heading = owner.label(
  "heading", @component.Read::new(() => "Note editor"),
).unwrap()
```

`Read` and `Controlled` describe sampling and event callbacks; they do not
create a second reactive graph. The Controlled callback receives committed
edits and may return a task Request. The semantic editor keeps selection and
IME composition. The host synchronizes programmatic values at its event
boundary and avoids overwriting active composition. Unchanged text preserves
selection. This contract does not imply physical IME verification on every OS.

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
