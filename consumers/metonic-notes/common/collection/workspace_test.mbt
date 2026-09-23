///|
test "switching preserves edits and is not itself an unsaved document change" {
  let model = workspace(empty())
  let first = model.create_note().unwrap()
  model.edit("first edit").unwrap()
  let second = model.create_note().unwrap()
  model.edit("second edit").unwrap()
  assert_true(model.select(first))
  assert_eq(model.active().unwrap().text, "first edit")
  model.acknowledge_save(model.snapshot())
  assert_true(model.select(second))
  assert_false(model.dirty())
  assert_eq(model.active().unwrap().text, "second edit")
}

///|
test "deletion requires confirmation and switching cancels the old target" {
  let model = workspace(empty())
  let first = model.create_note().unwrap()
  let second = model.create_note().unwrap()
  assert_false(model.confirm_delete())
  assert_true(model.request_delete())
  assert_true(model.select(first))
  assert_false(model.confirm_delete())
  assert_true(model.request_delete())
  assert_true(model.confirm_delete())
  assert_eq(model.active().unwrap().id, second)
  assert_true(model.request_delete())
  assert_true(model.confirm_delete())
  assert_eq(model.active(), None)
}

///|
test "save completion acknowledges only its snapshot and discard restores the collection" {
  let model = workspace(empty())
  let first = model.create_note().unwrap()
  model.edit("saved").unwrap()
  let snapshot = model.snapshot()
  model.edit("later edit").unwrap()
  ignore(model.create_note().unwrap())
  model.acknowledge_save(snapshot)
  assert_true(model.dirty())
  model.discard()
  assert_false(model.dirty())
  assert_eq(model.items(), [{ id: first, text: "saved", }])
  assert_eq(model.active().unwrap().id, first)
}

///|
test "moving the selected memo keeps its ID, clears delete, and discard restores order" {
  let (one, first) = empty().create_note().unwrap()
  let one = one.edit(first, "first").unwrap()
  let (two, second) = one.create_note().unwrap()
  let two = two.edit(second, "second").unwrap()
  let (three, third) = two.create_note().unwrap()
  let document = three.edit(third, "third").unwrap()
  let model = workspace(document)

  assert_true(model.select(second))
  assert_true(model.request_delete())
  assert_true(model.reorder_selected(MoveDirection::Up))
  assert_false(model.deletion_pending())
  assert_eq(model.active().unwrap().id, second)
  assert_eq(model.items().map(note => note.id), [second, first, third])
  assert_true(model.dirty())

  assert_eq(
    decode(Some(model.snapshot().encode()))
    .unwrap()
    .items()
    .map(note => note.id),
    [second, first, third],
  )
  model.discard()
  assert_eq(model.items().map(note => note.id), [first, second, third])
  assert_eq(model.active().unwrap().id, second)
  assert_false(model.dirty())

  assert_true(model.select(first))
  assert_true(model.request_delete())
  assert_false(model.reorder_selected(MoveDirection::Up))
  assert_false(model.deletion_pending())
  assert_eq(model.active().unwrap().id, first)

  assert_true(model.select(third))
  assert_true(model.request_delete())
  assert_false(model.reorder_selected(MoveDirection::Down))
  assert_false(model.deletion_pending())
  assert_eq(model.active().unwrap().id, third)
  assert_false(model.dirty())
}
