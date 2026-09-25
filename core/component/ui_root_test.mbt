///|
test "UI root dispatches live fixed controls and synchronizes committed values" {
  let scope = @reactive.Scope::root(@reactive.Graph::new())
  let tree = @semantics.empty(80, 1)
  let ui = UiRoot::new(scope, tree)
  let owner = ui.fixed("main")
  assert_true(physical_equal(owner, ui.fixed("main")))
  let pressed = Ref(0)
  let button = owner
    .button("run", "Run", () => {
      pressed.val += 1
      None
    })
    .unwrap()
  let value = @reactive.Signal::new(scope, "old")
  let input = owner
    .text_input(
      "note",
      "Note",
      Controlled::new(() => value.peek(), text => {
        value.set(text)
        None
      }),
    )
    .unwrap()
  assert_true(ui.activate(button) is None)
  assert_eq(pressed.val, 1)
  assert_eq(@semantics.set_enabled(tree, button, false), "")
  assert_true(ui.activate(button) is None)
  assert_eq(pressed.val, 1)
  assert_eq(@semantics.set_enabled(tree, button, true), "")
  assert_eq(@semantics.set_text(tree, input, "new"), "")
  assert_true(ui.edited(input, "new", @semantics.revision(tree) - 1) is None)
  assert_eq(value.peek(), "old")
  assert_true(ui.edited(input, "new", @semantics.revision(tree)) is None)
  assert_eq(value.peek(), "new")
  assert_false(ui.synchronize(None))
  assert_eq(@semantics.set_selection(tree, input, 0, 2), "")
  assert_false(ui.synchronize(None))
  assert_eq(@semantics.node(tree, input).unwrap().selection_end, 2)
  value.set("programmatic")
  assert_false(ui.synchronize(Some(input)))
  assert_eq(@semantics.node(tree, input).unwrap().value, "new")
  assert_true(ui.synchronize(None))
  assert_eq(@semantics.node(tree, input).unwrap().value, "programmatic")
  scope.dispose()
  assert_true(ui.activate(button) is None)
  assert_true(ui.edited(input, "stale", @semantics.revision(tree)) is None)
  assert_false(ui.synchronize(None))
  assert_eq(pressed.val, 1)
  assert_true(@semantics.node(tree, button) is Err(_))
  assert_true(@semantics.node(tree, input) is Err(_))
}

///|
test "keyed UI owner revokes an old reference before same-key recreation" {
  let scope = @reactive.Scope::root(@reactive.Graph::new())
  let tree = @semantics.empty(81, 1)
  let ui = UiRoot::new(scope, tree)
  let children : KeyedChildren[String, Unit, @semantics.NodeRef] = KeyedChildren::new(
    scope, tree,
  )
  let pressed = Ref(0)
  let create = (child : ChildOwner, _ : String, _ : Unit) => {
    ui
    .adopt(child)
    .button("retry", "Retry", () => {
      pressed.val += 1
      None
    })
    .unwrap()
  }
  assert_true(
    children.reconcile([{ key: "same", props: (), }], create, (_, _) => ()),
  )
  let old = children.get("same").unwrap()
  ignore(ui.activate(old))
  assert_eq(pressed.val, 1)
  assert_true(children.clear())
  assert_true(
    children.reconcile([{ key: "same", props: (), }], create, (_, _) => ()),
  )
  let fresh = children.get("same").unwrap()
  assert_true(old != fresh)
  ignore(ui.activate(old))
  assert_eq(pressed.val, 1)
  ignore(ui.activate(fresh))
  assert_eq(pressed.val, 2)
  scope.dispose()
}

///|
test "disposed fixed owner recreates a new instance under the same key" {
  let scope = @reactive.Scope::root(@reactive.Graph::new())
  let tree = @semantics.empty(82, 1)
  let ui = UiRoot::new(scope, tree)
  let old_owner = ui.fixed("panel")
  let old = old_owner.button("action", "Old", () => None).unwrap()
  old_owner.scope().dispose()
  let fresh_owner = ui.fixed("panel")
  let fresh = fresh_owner.button("action", "New", () => None).unwrap()
  assert_true(old_owner.generation() != fresh_owner.generation())
  assert_true(old != fresh)
  assert_true(@semantics.node(tree, old) is Err(_))
  assert_eq(@semantics.node(tree, fresh).unwrap().name, "New")
  scope.dispose()
}
