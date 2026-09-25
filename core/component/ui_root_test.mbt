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
    .reference()
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
    .reference()
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
    .reference()
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
  let old = old_owner.button("action", "Old", () => None).unwrap().reference()
  old_owner.scope().dispose()
  let fresh_owner = ui.fixed("panel")
  let fresh = fresh_owner
    .button("action", "New", () => None)
    .unwrap()
    .reference()
  assert_true(old_owner.generation() != fresh_owner.generation())
  assert_true(old != fresh)
  assert_true(@semantics.node(tree, old) is Err(_))
  assert_eq(@semantics.node(tree, fresh).unwrap().name, "New")
  scope.dispose()
}

///|
test "label identity and button enabled state follow their owner" {
  let scope = @reactive.Scope::root(@reactive.Graph::new())
  let tree = @semantics.empty(83, 1)
  let ui = UiRoot::new(scope, tree)
  let owner = ui.fixed("summary")
  let text = @reactive.Signal::new(scope, "Waiting")
  let enabled = @reactive.Signal::new(scope, false)
  let label = owner.label("status", Read::new(() => text.peek())).unwrap()
  let pressed = Ref(0)
  let button = owner
    .button(
      "retry",
      "Retry",
      () => {
        pressed.val += 1
        None
      },
      enabled=Read::new(() => enabled.peek()),
    )
    .unwrap()
  assert_eq(
    @semantics.node(tree, label.reference()).unwrap().role,
    @semantics.Label,
  )
  assert_eq(@semantics.focus(tree, label.reference()), "unsupported_action")
  assert_eq(
    label.element({ x: 1, y: 2, width: 80, height: 20, }).text,
    "Waiting",
  )
  assert_false(@semantics.node(tree, button.reference()).unwrap().enabled)
  ignore(ui.activate(button.reference()))
  assert_eq(pressed.val, 0)
  text.set("Ready")
  enabled.set(true)
  assert_true(ui.synchronize(None))
  assert_eq(label.element({ x: 1, y: 2, width: 80, height: 20, }).text, "Ready")
  assert_true(@semantics.node(tree, button.reference()).unwrap().enabled)
  ignore(ui.activate(button.reference()))
  assert_eq(pressed.val, 1)
  owner.scope().dispose()
  assert_true(@semantics.node(tree, label.reference()) is Err(_))
  assert_true(@semantics.node(tree, button.reference()) is Err(_))
  assert_true(ui.activate(button.reference()) is None)
  scope.dispose()
}

///|
test "keyed buttons retain handlers across reorder and revoke removed instances" {
  let scope = @reactive.Scope::root(@reactive.Graph::new())
  let tree = @semantics.empty(84, 1)
  let ui = UiRoot::new(scope, tree)
  let children : KeyedChildren[String, Unit, UiButton] = KeyedChildren::new(
    scope, tree,
  )
  let activated : Array[String] = []
  let create = (child : ChildOwner, key : String, _ : Unit) => {
    ui
    .adopt(child)
    .button(key, key, () => {
      activated.push(key)
      None
    })
    .unwrap()
  }
  let specs : Array[ChildSpec[String, Unit]] = [
    { key: "a", props: (), },
    { key: "b", props: (), },
  ]
  assert_true(children.reconcile(specs, create, (_, _) => ()))
  let a = children.get("a").unwrap()
  let b = children.get("b").unwrap()
  assert_true(children.reconcile([specs[1], specs[0]], create, (_, _) => ()))
  assert_eq(children.ordered().map(button => button.reference()), [
    b.reference(),
    a.reference(),
  ])
  ignore(ui.activate(a.reference()))
  ignore(ui.activate(b.reference()))
  assert_eq(activated, ["a", "b"])
  assert_true(children.reconcile([specs[1]], create, (_, _) => ()))
  assert_true(@semantics.node(tree, a.reference()) is Err(_))
  ignore(ui.activate(a.reference()))
  ignore(ui.activate(b.reference()))
  assert_eq(activated, ["a", "b", "b"])
  assert_true(children.reconcile(specs, create, (_, _) => ()))
  let recreated = children.get("a").unwrap()
  assert_true(recreated.reference() != a.reference())
  ignore(ui.activate(a.reference()))
  ignore(ui.activate(recreated.reference()))
  assert_eq(activated, ["a", "b", "b", "a"])
  scope.dispose()
}

///|
test "controlled single and multiline inputs keep editing and ownership separate" {
  let scope = @reactive.Scope::root(@reactive.Graph::new())
  let tree = @semantics.empty(85, 1)
  let ui = UiRoot::new(scope, tree)
  let owner = ui.fixed("form")
  let value = @reactive.Signal::new(scope, "line one")
  let enabled = @reactive.Signal::new(scope, true)
  let read_only = @reactive.Signal::new(scope, false)
  let commits = Ref(0)
  let field = owner
    .text_input(
      "title",
      "Title",
      Controlled::new(() => value.peek(), text => {
        commits.val += 1
        value.set(text)
        None
      }),
      enabled=Read::new(() => enabled.peek()),
      read_only=Read::new(() => read_only.peek()),
    )
    .unwrap()
  let area = owner
    .text_area("body", "Body", Controlled::new(() => "a\nb", _ => None))
    .unwrap()
  assert_true(field.single_line())
  assert_false(area.single_line())
  assert_eq(area.element({ x: 0, y: 0, width: 80, height: 30, }).text, "a\nb")
  let reference = field.reference()
  assert_eq(@semantics.set_selection(tree, reference, 0, 4), "")
  assert_false(ui.synchronize(None))
  assert_eq(@semantics.node(tree, reference).unwrap().selection_end, 4)
  assert_eq(@semantics.replace_selection(tree, reference, "new"), "")
  ignore(ui.edited(reference, "new one", @semantics.revision(tree)))
  assert_eq(commits.val, 1)
  read_only.set(true)
  assert_true(ui.synchronize(None))
  assert_true(@semantics.node(tree, reference).unwrap().read_only)
  assert_eq(@semantics.replace_selection(tree, reference, "bad"), "read_only")
  ignore(ui.edited(reference, "new one", @semantics.revision(tree)))
  assert_eq(commits.val, 1)
  enabled.set(false)
  value.set("external")
  assert_true(ui.synchronize(None))
  assert_false(@semantics.node(tree, reference).unwrap().enabled)
  assert_eq(@semantics.node(tree, reference).unwrap().value, "external")
  owner.scope().dispose()
  assert_true(@semantics.node(tree, reference) is Err(_))
  ignore(ui.edited(reference, "late", @semantics.revision(tree)))
  assert_eq(commits.val, 1)
  scope.dispose()
}
