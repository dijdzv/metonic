///|
test "status keeps one semantic identity across loading, previous and failure" {
  let scope = @reactive.Scope::root(@reactive.Graph::new())
  let tree = @semantics.empty(97, 1)
  let ui = UiRoot::new(scope, tree)
  let current = @reactive.Signal::new(
    scope,
    StatusState::Waiting("Shipping: waiting"),
  )
  let owner = ui.fixed("status")
  let status = owner
    .status("shipping", Read::new(() => current.peek()))
    .unwrap()
  let reference = status.reference()
  assert_eq(@semantics.node(tree, reference).unwrap().role, @semantics.Status)
  assert_eq(@semantics.focus(tree, reference), "unsupported_action")
  assert_false(ui.synchronize(None))
  current.set(StatusState::Loading("Shipping: loading"))
  assert_true(ui.synchronize(None))
  assert_eq(@semantics.node(tree, reference).unwrap().name, "Shipping: loading")
  assert_false(ui.synchronize(None))
  current.set(StatusState::RetainedPrevious("Shipping: loading", "112"))
  assert_true(ui.synchronize(None))
  assert_eq(
    @semantics.node(tree, reference).unwrap().name,
    "Shipping: loading (previous 112)",
  )
  current.set(StatusState::Rejected("Shipping: failed"))
  assert_true(ui.synchronize(None))
  assert_true(@semantics.node(tree, reference).unwrap().invalid)
  current.set(StatusState::Ready("Shipping: 224"))
  assert_true(ui.synchronize(None))
  assert_false(@semantics.node(tree, reference).unwrap().invalid)
  assert_eq(status.reference(), reference)
  scope.dispose()
  assert_true(@semantics.node(tree, reference) is Err("stale_target"))
}

///|
test "status bounds announcements without exposing long values" {
  let private = "confidential".repeat(30)
  assert_eq(StatusState::Failed(private).message(), "Operation failed")
  assert_eq(
    StatusState::RetainedPrevious("Shipping: loading", private).message(),
    "Previous result available",
  )
}
