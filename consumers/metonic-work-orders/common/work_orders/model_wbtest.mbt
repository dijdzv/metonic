///|
test "work-order fields update independently and retired generations reject edits" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let document = root.child()
  let model = OrderModel::new(document)
  model.replace_all(seed_orders())
  let first = model.identity("WO-101").unwrap()
  let previous = model.read().lookup("WO-101").unwrap()
  let title_samples = Ref(0)
  let detail_samples = Ref(0)
  let title = @reactive.Binding::new(
    document,
    () => {
      title_samples.val += 1
      previous.fields().unwrap().title.get()
    },
    _ => (),
  )
  let details = @reactive.Binding::new(
    document,
    () => {
      detail_samples.val += 1
      previous.fields().unwrap().details.get()
    },
    _ => (),
  )
  assert_eq((title_samples.val, detail_samples.val), (1, 1))
  assert_true(model.edit(first, "Updated title", true))
  assert_eq((title_samples.val, detail_samples.val), (2, 1))
  assert_true(model.edit(first, "Updated details", false))
  assert_eq((title_samples.val, detail_samples.val), (2, 2))
  assert_false(model.edit(first, "Updated details", false))
  assert_eq(model.snapshot()[0].title, "Updated title")
  assert_eq(model.snapshot()[0].details, "Updated details")
  title.dispose()
  details.dispose()
  model.replace_all(seed_orders())
  assert_true(previous.fields() is Err(@reactive.StaleItem))
  assert_true(model.identity("WO-101").unwrap() != first)
  assert_false(model.edit(first, "late edit", true))
  assert_eq(model.snapshot()[0].title, "Inspect entry light")
  root.dispose()
}

///|
test "work-order list ignores detail edits and retires a recreated identity" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let document = root.child()
  let model = OrderModel::new(document)
  model.replace_all(seed_orders())
  let read = model.read()
  let setting = @reactive.Store::new(root).field(false)
  let selected = @reactive.Signal::new(document, model.identity("WO-101"))
  let tree = @semantics.empty(118, 1)
  let ui = @component.UiRoot::new(document, tree)
  let owner = ui.fixed("results")
  let query = @reactive.Store::new(owner.scope()).field("")
  let list = owner.list("orders", "Orders", selected).unwrap()
  list.track_selection(document)
  let row_samples = Ref(0)
  list.bind_rows(
    @component.Read::tracked(owner.scope(), () => {
      row_samples.val += 1
      visible_rows(read, query.read(), setting.read())
    }),
  )
  let detail_owner = ui.fixed("detail")
  let title_samples = Ref(0)
  let detail_samples = Ref(0)
  let title = detail_owner
    .text_input(
      "title",
      "Title",
      @component.Controlled::tracked(
        detail_owner.scope(),
        () => {
          title_samples.val += 1
          selected_fields(read, selected)
          .map(fields => fields.title.get())
          .unwrap_or("")
        },
        _ => None,
      ),
    )
    .unwrap()
  let details = detail_owner
    .text_area(
      "details",
      "Details",
      @component.Controlled::tracked(
        detail_owner.scope(),
        () => {
          detail_samples.val += 1
          selected_fields(read, selected)
          .map(fields => fields.details.get())
          .unwrap_or("")
        },
        _ => None,
      ),
    )
    .unwrap()
  assert_eq(row_samples.val, 1)
  assert_eq((title_samples.val, detail_samples.val), (1, 1))
  assert_eq(list.items().length(), 2)
  let first = list.items()[0].reference()
  let revision = @semantics.revision(tree)
  assert_true(model.edit(selected.peek().unwrap(), "New details", false))
  assert_true(ui.synchronize(None))
  assert_eq(row_samples.val, 1)
  assert_eq((title_samples.val, detail_samples.val), (1, 2))
  assert_eq(@semantics.revision(tree), revision + 1)
  assert_eq(
    @semantics.node(tree, title.reference()).unwrap().value,
    "Inspect entry light",
  )
  assert_eq(
    @semantics.node(tree, details.reference()).unwrap().value,
    "New details",
  )
  assert_true(model.edit(selected.peek().unwrap(), "Renamed", true))
  assert_eq(row_samples.val, 2)
  assert_true(ui.synchronize(None))
  assert_eq((title_samples.val, detail_samples.val), (2, 2))
  assert_eq(@semantics.node(tree, first).unwrap().name, "WO-101  Renamed")
  assert_eq(@semantics.focus(tree, first), "")
  assert_eq(model.items.reorder(["WO-102", "WO-101", "WO-103"]), Ok(()))
  assert_true(ui.synchronize(None))
  assert_eq(list.items()[1].reference(), first)
  assert_true(@semantics.node(tree, first).unwrap().focused)
  query.set("WO-102")
  assert_true(ui.synchronize(None))
  assert_eq(list.items().length(), 1)
  query.set("")
  assert_true(ui.synchronize(None))
  let restored = list.items()[0].reference()
  model.replace_all(seed_orders())
  assert_true(ui.synchronize(None))
  assert_true(@semantics.node(tree, restored) is Err("stale_target"))
  assert_eq(selected.peek(), None)
  assert_true(list.items()[0].reference() != restored)
  ignore(ui.activate(restored))
  assert_eq(selected.peek(), None)
  setting.set(true)
  assert_true(ui.synchronize(None))
  assert_eq(list.items().length(), 3)
  root.dispose()
}
