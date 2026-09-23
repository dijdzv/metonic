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

///|
test "workspace value transitions preserve earlier snapshots" {
  let initial = workspace_state(empty())
  let (created, first) = initial.create_note().unwrap()
  let edited = created.edit("first edit").unwrap()
  let saved = edited.acknowledge_save(edited.snapshot())
  let (later, second) = saved.create_note().unwrap()
  let later = later.edit("second edit").unwrap()
  assert_eq(initial.items(), [])
  assert_eq(created.active().unwrap().text, "")
  assert_eq(saved.items(), [{ id: first, text: "first edit", }])
  assert_false(saved.dirty())
  assert_true(later.dirty())
  assert_eq(later.active().unwrap().id, second)
  let restored = later.discard()
  assert_eq(restored.items(), saved.items())
  assert_eq(restored.active().unwrap().id, first)
  assert_eq(later.items().length(), 2)
}

///|
test "workspace value deletion and reorder clear only their own confirmation" {
  let (one, first) = workspace_state(empty()).create_note().unwrap()
  let (two, second) = one.create_note().unwrap()
  let (pending, requested) = two.request_delete()
  assert_true(requested)
  assert_false(two.deletion_pending())
  assert_true(pending.deletion_pending())
  let (boundary, moved) = pending.reorder_selected(MoveDirection::Down)
  assert_false(moved)
  assert_false(boundary.deletion_pending())
  let (pending_again, _) = pending.request_delete()
  let (deleted, removed) = pending_again.confirm_delete()
  assert_true(removed)
  assert_eq(deleted.items().map(note => note.id), [first])
  assert_eq(deleted.active().unwrap().id, first)
  assert_eq(pending_again.items().map(note => note.id), [first, second])
}
