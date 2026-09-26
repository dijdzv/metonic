///|
test "tracked component input prepares only relevant changes and releases its owner" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let owner = root.child()
  let title = @reactive.Signal::new(root, "first")
  let details = @reactive.Signal::new(root, "unchanged")
  let samples = Ref(0)
  let input = PreparedInput::new(
    owner,
    Read::tracked(root, () => {
      samples.val += 1
      title.get()
    }),
  )
  assert_true(input.needs_sync())
  assert_eq(input.current(), "first")
  assert_eq(samples.val, 1)
  input.consume()
  details.set("other")
  assert_false(input.needs_sync())
  assert_eq(samples.val, 1)
  title.set("second")
  assert_true(input.needs_sync())
  assert_eq(input.current(), "second")
  assert_eq(samples.val, 2)
  input.consume()
  title.set("second")
  assert_false(input.needs_sync())
  input.mark_pending()
  assert_true(input.needs_sync())
  assert_eq(input.current(), "second")
  assert_eq(samples.val, 2)
  input.consume()
  owner.dispose()
  title.set("third")
  assert_false(input.needs_sync())
  assert_eq(samples.val, 2)
  root.dispose()
}

///|
test "legacy component input still polls nonreactive and peek-based sources" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let source = @reactive.Signal::new(root, "first")
  let raw = Ref("first")
  let samples = Ref(0)
  let input = PreparedInput::new(
    root,
    Read::new(() => {
      samples.val += 1
      source.peek() + raw.val
    }),
  )
  assert_true(input.needs_sync())
  assert_eq(input.current(), "firstfirst")
  input.consume()
  source.set("second")
  raw.val = "changed"
  assert_true(input.needs_sync())
  assert_eq(input.current(), "secondchanged")
  assert_eq(samples.val, 2)
  root.dispose()
}

///|
test "tracked Controlled retains its commit callback" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let source = @reactive.Signal::new(root, false)
  let controlled = Controlled::tracked(root, () => source.get(), value => {
    source.set(value)
    None
  })
  let input = PreparedInput::new(root, controlled.as_read())
  assert_false(input.current())
  input.consume()
  ignore((controlled.commit)(true))
  assert_true(input.needs_sync())
  assert_true(input.current())
  root.dispose()
}

///|
test "tracked UI input may read a sibling document without outliving its widget" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let document = root.child()
  let widget = root.child()
  let title = @reactive.Signal::new(document, "document")
  let samples = Ref(0)
  let input = PreparedInput::new(
    widget,
    Read::tracked(document, () => {
      samples.val += 1
      title.get()
    }),
  )
  assert_eq(input.current(), "document")
  input.consume()
  title.set("changed")
  assert_true(input.needs_sync())
  assert_eq(input.current(), "changed")
  assert_eq(samples.val, 2)
  input.consume()
  widget.dispose()
  title.set("after widget disposal")
  assert_false(input.needs_sync())
  assert_eq(samples.val, 2)
  root.dispose()
}
