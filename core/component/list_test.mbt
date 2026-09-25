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
