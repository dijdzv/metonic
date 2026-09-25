# ADR 038: Build standard controls over the existing owner and host boundary

Status: Accepted for staged Phase 5 implementation. [Issue #618](https://github.com/dijdzv/metonic/issues/618) records the contract; implementation is tracked in smaller dependent issues.

## Context

ADR 035 owns synchronous values with `Graph` and `Scope`; ADR 037 owns dynamic UI lifetime through `KeyedChildren` and the host's event boundary. The external quote board proves those low-level contracts, but its `Board::view` constructs each `Control` and absolute rectangle, looks up semantic nodes to recover focus and text, and its `Application.activate` compares every `NodeRef` to route events. The note field separately creates its semantic input and mirrors edits. A second app must not have to repeat that wiring to get a button or editable field.

The present `core/component` only wraps keyed child `Scope`s and their semantic references. `core/application` renders `Text`, `Button`, and `Input`; `core/semantics` has only Button and TextInput roles. The browser host maps those controls to DOM elements, while the native host maps semantic nodes to AccessKit and draws through the shared view. These are the boundaries to extend, not parallel component, editor, or task runtimes.

## Decision: one owner, one event boundary

Introduce a public `UiRoot` attached to an application `Scope` and semantic `Tree`. It provides a fixed child owner for permanent screen regions and adapts the existing `ChildOwner` returned by `KeyedChildren::reconcile` for dynamic regions. Each widget registers its semantic reference, event handler, and presentation source under its owner. Root disposal retires them; removal immediately makes a reference undispatchable, even when a new child later uses the same stable key. A stable key locates a retained owner; `NodeRef` and owner generation identify one live instance. No global component registry or store is needed.

The application passes this optional root to the host. At the existing event boundary, after an input or valid async completion and the publication round, the host asks the root to synchronize *programmatic* controlled values and enabled/selected states with the semantic tree, then samples the pure application view. Synchronization is not called from `Binding`, `Memo`, or `view`; it does not submit tasks. Existing applications without a root keep their present callbacks. Widget event dispatch happens through `Application.activate` and `Application.edited` into `UiRoot::activate`/`edited`, on the same host event thread and task handoff already used by applications. A callback may change a Signal or return a `Request`; the host submits a returned request after callback completion. The root checks live owner, reference generation, role, enabled state, and edit revision before invoking the handler. No callback survives owner disposal.

Expose a read-only `Read[T]` descriptor for labels and derived display values, and a `Controlled[T]` descriptor with `read` and `write` for editable/selected values. These descriptors are owner-scoped sampling and event contracts, not another reactive graph. `read` can refer to `Signal`, `Memo`, or a published async view. `write` runs only in response to a valid host event. The semantic editor owns the in-progress text, selection, and IME composition. The controlled value receives committed edits; a programmatic change is reconciled at the host event boundary, preserving selection when text is unchanged. Preedit is never copied back into the application model or reset by a render. An input may be read-only or disabled without pretending that its value callback should run.

The following is the **target consumer shape**, illustrating the contract rather than claiming these names are implemented already:

```moonbit
let ui = @component.UiRoot::new(app_scope, tree, theme=theme)
let actions = ui.fixed("actions")
let amber = actions.button(
  "amber", label="Amber lamp",
  on_activate=() => board.select_item("amber"),
)
let note = ui.fixed("note")
let body = note.text_area(
  "body", label="Note",
  value=@component.Controlled::new(
    read=() => board.note.text(),
    write=text => board.note.edit(text),
  ),
)
let save = note.button(
  "save", label="Save note",
  on_activate=() => board.note.save_request(),
)
let details : @component.KeyedChildren[String, Unit, Detail] =
  @component.KeyedChildren::new(app_scope, tree)
details.reconcile(specs, (child_owner, key, _) => {
  let child = ui.adopt(child_owner)
  Detail::new(key, child.button("retry", label="Retry", on_activate=retry))
}, (detail, _) => detail.refresh())
// Application carries `components: Some(ui)`; existing view/activate/edited
// slots return ui.layout(...), ui.activate(reference), ui.edited(edit).
```

Here `UiRoot::fixed` owns a child `Scope`; `adopt` uses the already-created keyed `ChildOwner` instead of creating a second lifetime. Widget handles expose identity and state to layout without making app code compare `NodeRef`s. A fixed region can also be hidden without disposal; a keyed region can be removed and recreated. Visibility does not stop tasks; owner disposal does. Shared model state belongs to an ancestor Scope, while local widget state belongs to the widget owner. A parent may read a child's state only while that child is live; long-lived shared values must be promoted deliberately to an ancestor.

The quote board currently builds six fixed button rectangles, conditional quantity/retry rectangles, four text rectangles, a note rectangle, and a save rectangle in `Board::view`, and branches on the associated references in `activate`. With this contract the app still supplies labels, data dependencies, callbacks, and a layout arrangement; component creation, focus/disabled state, semantic registration, live-reference checks, and dispatch move into the framework. The expected reduction is the repeated control and routing code, not the app's A/B/C/D request logic. Implementation acceptance compares the resulting consumer source and built behavior to this baseline; this ADR does not claim a measured reduction before migration.

## Semantics and presentation path

The first group consists of Label, Button, TextInput, TextArea, Checkbox, Stack, ScrollView, selectable List, and Loading/Error/Retry state presentation. A widget's semantic meaning is independent of its appearance:

| Widget | Semantic and input contract | Presentation contract |
| --- | --- | --- |
| Label | Static text, optionally associated with a control; no activation. | `Text` with theme typography. |
| Button | Button role, accessible name, enabled/focus state; pointer, Enter, Space, accessibility invoke. | Button surface with theme state. |
| TextInput/TextArea | TextInput role with single/multiline distinction; semantic editor retains selection, composition, focus, and committed value. | Existing input presentation; theme state must not replace editor behavior. |
| Checkbox | Dedicated Checkbox role and checked state; pointer, Space, accessibility toggle. | Check mark and label; never expose it as a Button with a toggled caption. |
| Stack/ScrollView | Layout and viewport ownership; not focusable semantic controls by themselves. | Reuse `core/layout` placements, clipping, wheel and reveal behavior. |
| Selectable List | List/ListItem roles, selected state, stable keyed row owners; arrow, Home/End, activation, focus reveal. | Virtual/visible placements from `VerticalList`; row removal revokes input and references. |
| Loading/Error/Retry | Loading and error have status semantics with bounded announcements; Retry is a real Button. | Content and theme state derive from the existing async view; no separate async state machine. |

The implementation must extend `core/semantics` role/state and registration before Checkbox/List/Status become public; `core/application.Kind` and `core/view` must carry the corresponding visual kind and style without overloading Text/Button/Input. Browser `application_host` must create compatible DOM controls and native `window_host`/AccessKit must expose matching roles, checked/selected state and actions. The browser's WebGPU rendering path and native renderer may draw them differently, but both consume the same common application controls and semantic nodes. Accessibility is verified from host-visible nodes, not inferred from a label on a painted rectangle. Static labels and statuses should have stable identity where announcement or association requires it; positional text identity is insufficient for a dynamic list.

## Theme and invalidation

Use a small common theme of typography, spacing, background/foreground/border colors, and focus/error indicators. Each widget resolves `normal`, `disabled`, `focused`, and `error` states from semantic/application state; callers may override tokens, not fork host behavior. The theme is app-scoped and read-only while a frame is prepared. A theme update is an application event, not a mutation during render.

Separate text layout inputs (text, font, size, available width) from paint-only inputs (colors, border and focus ring). A state-only change reuses text shaping and layout when those inputs are equal; it repaints affected visible bounds as needed. Focus/error transitions still require a visible frame. Both hosts need a regression check for unchanged text geometry and a measurement of redraw/layout work; do not claim that the current renderer already has this optimization.

## Stages and acceptance

1. Root and event/value contract: add fixed-owner and keyed-owner adaptation, read/controlled descriptors, live dispatch, semantic synchronization at the existing host boundary, and removal/recreation tests. Preserve low-level `Application` use.
2. Label and Button: make fixed and keyed cases render and operate in browser JS/WasmGC and native; verify pointer, keyboard, accessibility invoke, disabled/focus, disposal, and a quote-board button migration.
3. TextInput and TextArea: reuse the existing editor, verify committed edits, selection, IME cancellation, programmatic value changes, disabled/read-only, and removed focused input on both hosts. Migrate the quote-board note field.
4. Stack and ScrollView: reuse `core/layout`, test resize, clipping, wheel and keyboard reveal, and replace quote-board absolute placements where practical.
5. Checkbox and selectable List: add distinct semantic roles/actions and host support before exposing widgets. Test keyed reorder/removal, selection, keyboard navigation, and accessibility state in both hosts.
6. Loading/Error/Retry, theme, and gallery: derive state views from current/previous async results; exercise every widget alone and combined with add/remove/reorder and pending completion. Keep the quote board as the independent external consumer and use the gallery as additional coverage.
7. Rebuild/package JS, WasmGC, and native external examples; rerun relevant Notes editing, IME, persistence, close, CLI/MCP, production exclusion, and fixed performance/resource baselines. Record code-size and layout/paint measurements and resolve actual consumer friction in the public API.

Each stage is a small vertical issue with its own host and consumer acceptance. Native UIA roles and input require Windows verification; synthetic composition cannot prove physical IME. A temporary backend mismatch is an incomplete stage, not a reason to publish a misleading role. Radio, Select, Dialog, Menu, Tabs, a global Store, a second editor, a new task scheduler, and an implicit `await` dependency tracker are outside this first group.

## Alternatives considered

Keeping the low-level controls and adding only helper constructors would shorten rectangles but leave reference routing, lifetime and IME synchronization in every app. Building widgets around host DOM or AccessKit directly would split common app code. Adding a global Store or replacing the editor would enlarge the change without solving the immediate owner/dispatch problem. The staged owner-based contract gives standard behavior while retaining explicit low-level escape hatches.
