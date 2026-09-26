///|
test "keyed list keeps selected rows across reorder and revokes removed rows" {
  let scope = @reactive.Scope::root(@reactive.Graph::new())
  let tree = @semantics.empty(96, 1)
  let ui = UiRoot::new(scope, tree)
  let selected = @reactive.Signal::new(scope, Some("a"))
  let list = ui.fixed("results").list("items", "Results", selected).unwrap()
  let a = ListRow::{ key: "a", label: "Alpha", enabled: true, }
  let b = ListRow::{ key: "b", label: "Beta", enabled: false, }
  let c = ListRow::{ key: "c", label: "Gamma", enabled: true, }
  assert_true(list.reconcile([a, b, c]))
  let first = list.items()
  assert_eq(
    @semantics.node(tree, first[0].reference()).unwrap().parent,
    Some(list.reference()),
  )
  assert_true(@semantics.node(tree, first[0].reference()).unwrap().selected)
  assert_false(@semantics.node(tree, first[1].reference()).unwrap().enabled)
  assert_eq(
    ui.navigate_list(first[0].reference(), Next),
    Some(first[2].reference()),
  )
  assert_true(@semantics.node(tree, first[2].reference()).unwrap().focused)
  ignore(ui.activate(first[2].reference()))
  assert_eq(selected.peek(), Some("c"))
  assert_true(ui.synchronize(None))
  assert_true(@semantics.node(tree, first[2].reference()).unwrap().selected)
  assert_false(@semantics.node(tree, first[0].reference()).unwrap().selected)
  assert_true(list.reconcile([c, a, b]))
  let reordered = list.items()
  assert_eq(reordered[0].reference(), first[2].reference())
  assert_true(@semantics.node(tree, reordered[0].reference()).unwrap().selected)
  assert_true(list.reconcile([a, b]))
  assert_eq(selected.peek(), None)
  assert_true(
    @semantics.node(tree, first[2].reference()) is Err("stale_target"),
  )
  assert_true(@semantics.node(tree, first[0].reference()).unwrap().focused)
  ignore(ui.activate(first[2].reference()))
  assert_eq(selected.peek(), None)
  assert_true(list.reconcile([a, b, c]))
  assert_true(list.items()[2].reference() != first[2].reference())
  ignore(ui.activate(first[2].reference()))
  assert_eq(selected.peek(), None)
  assert_eq(
    ui.navigate_list(first[0].reference(), Last),
    Some(list.items()[2].reference()),
  )
  scope.dispose()
  assert_true(@semantics.node(tree, list.reference()) is Err(_))
}

///|
priv struct TrackedRowRead {
  title : @reactive.StoreRead[String]
}

///|
priv struct TrackedRowWrite {
  title : @reactive.StoreField[String]
  details : @reactive.StoreField[String]
}

///|
test "tracked list rows react to title and order without detail or unrelated control work" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let document = root.child()
  let tree = @semantics.empty(99, 1)
  let ui = UiRoot::new(document, tree)
  let owner = ui.fixed("results")
  let query = @reactive.Signal::new(owner.scope(), "")
  let selected = @reactive.Signal::new(document, Some("a"))
  let list = owner.list("orders", "Orders", selected).unwrap()
  list.track_selection(document)
  let selection_label = owner
    .label(
      "selection",
      Read::tracked(document, () => selected.get().unwrap_or("none")),
    )
    .unwrap()
  let items : @reactive.KeyedStore[String, TrackedRowRead, TrackedRowWrite] = @reactive.Store::new(
    document,
  ).keyed()
  let first = items
    .insert("a", builder => {
      let title = builder.field("Alpha")
      let details = builder.field("private detail")
      ({ title: title.read(), }, { title, details, })
    })
    .unwrap()
  ignore(
    items.insert("b", builder => {
      let title = builder.field("Beta")
      let details = builder.field("other detail")
      ({ title: title.read(), }, { title, details, })
    }),
  )
  let rows = items.read()
  let row_evaluations = Ref(0)
  let unrelated_evaluations = Ref(0)
  let unrelated = @reactive.Signal::new(document, "status")
  let status = owner
    .label(
      "status",
      Read::tracked(document, () => {
        unrelated_evaluations.val += 1
        unrelated.get()
      }),
    )
    .unwrap()
  list.bind_rows(
    Read::tracked(owner.scope(), () => {
      row_evaluations.val += 1
      let result : Array[ListRow[String]] = []
      for key in rows.keys() {
        let fields = rows.lookup(key).unwrap().fields().unwrap()
        let title = fields.title.get()
        if query.get() == "" || title.contains(query.get()) {
          result.push({ key, label: title, enabled: true, })
        }
      }
      result
    }),
  )
  assert_eq((row_evaluations.val, unrelated_evaluations.val), (1, 1))
  let originals = list.items()
  assert_eq(originals.length(), 2)
  assert_true(@semantics.node(tree, originals[0].reference()).unwrap().selected)
  assert_false(ui.synchronize(None))
  let revision = @semantics.revision(tree)
  first.fields().unwrap().details.set("changed detail")
  assert_eq(row_evaluations.val, 1)
  assert_false(ui.synchronize(None))
  assert_eq(@semantics.revision(tree), revision)
  first.fields().unwrap().title.set("Alpha updated")
  assert_eq(row_evaluations.val, 2)
  assert_true(ui.synchronize(None))
  assert_eq(
    @semantics.node(tree, originals[0].reference()).unwrap().name,
    "Alpha updated",
  )
  assert_eq(
    @semantics.node(tree, originals[1].reference()).unwrap().name,
    "Beta",
  )
  assert_eq(unrelated_evaluations.val, 1)
  ignore(@semantics.focus(tree, originals[0].reference()))
  assert_eq(items.reorder(["b", "a"]), Ok(()))
  assert_true(ui.synchronize(None))
  assert_eq(list.items().map(item => item.reference()), [
    originals[1].reference(),
    originals[0].reference(),
  ])
  assert_true(@semantics.node(tree, originals[0].reference()).unwrap().focused)
  query.set("Beta")
  assert_true(ui.synchronize(None))
  assert_eq(list.items().length(), 1)
  assert_eq(selected.peek(), None)
  assert_eq(
    @semantics.node(tree, selection_label.reference()).unwrap().name,
    "none",
  )
  assert_true(
    @semantics.node(tree, originals[0].reference()) is Err("stale_target"),
  )
  assert_eq(@semantics.node(tree, status.reference()).unwrap().name, "status")
  root.dispose()
}
