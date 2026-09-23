///|
test "failed loading cannot turn existing storage into an empty save" {
  let model = create()
  let ticket = model.begin_load().unwrap()
  assert_false(model.edit("accidental overwrite"))
  assert_true(model.finish_load(ticket, Err("unavailable")))
  assert_eq(model.begin_save(), None)
  let retry = model.begin_load().unwrap()
  assert_false(model.finish_load(ticket, Ok(None)))
  assert_true(model.finish_load(retry, Ok(Some("日本語\nメモ"))))
  assert_eq(model.text(), "日本語\nメモ")
  assert_false(model.dirty())
}

///|
test "save completion acknowledges its snapshot rather than edits made meanwhile" {
  let model = create()
  assert_true(model.finish_load(model.begin_load().unwrap(), Ok(None)))
  assert_true(model.edit("first"))
  let (ticket, snapshot) = model.begin_save().unwrap()
  assert_eq(snapshot, "first")
  assert_false(model.can_close())
  assert_true(model.edit("second"))
  assert_true(model.finish_save(ticket, Ok(())))
  assert_true(model.dirty())
  assert_eq(model.text(), "second")
  assert_false(model.can_close())
  let (ticket, snapshot) = model.begin_save().unwrap()
  assert_eq(snapshot, "second")
  assert_true(model.finish_save(ticket, Ok(())))
  assert_false(model.dirty())
  assert_true(model.can_close())
}

///|
test "save failure retains edits and permits explicit retry" {
  let model = create()
  assert_true(model.finish_load(model.begin_load().unwrap(), Ok(Some("old"))))
  assert_true(model.edit("new"))
  let (ticket, _) = model.begin_save().unwrap()
  assert_eq(model.begin_save(), None)
  assert_true(model.finish_save(ticket, Err("disk full")))
  assert_eq(model.state(), SaveFailed("disk full"))
  assert_true(model.dirty())
  let (retry, snapshot) = model.begin_save().unwrap()
  assert_eq(snapshot, "new")
  assert_false(model.finish_save(ticket, Ok(())))
  assert_true(model.finish_save(retry, Ok(())))
  assert_true(model.can_close())
}

///|
test "closed application rejects late load and save completions" {
  let model = create()
  let loading = model.begin_load().unwrap()
  model.close()
  assert_false(model.finish_load(loading, Ok(Some("late"))))
  assert_eq(model.begin_load(), None)
  assert_false(model.edit("late"))
  let model = create()
  assert_true(model.finish_load(model.begin_load().unwrap(), Ok(None)))
  assert_true(model.edit("pending"))
  let (saving, _) = model.begin_save().unwrap()
  model.close()
  assert_false(model.finish_save(saving, Ok(())))
  assert_eq(model.state(), Closed)
}

///|
test "canceled save preserves newer edits and rejects late completion" {
  let model = create()
  assert_true(model.finish_load(model.begin_load().unwrap(), Ok(Some("saved"))))
  assert_true(model.edit("writing"))
  let (old, _) = model.begin_save().unwrap()
  assert_true(model.edit("newer"))
  assert_true(model.cancel_save(old))
  assert_eq(model.state(), Ready)
  assert_eq(model.text(), "newer")
  assert_true(model.is_saved("saved"))
  assert_true(model.dirty())
  assert_false(model.finish_save(old, Ok(())))
  let (current, snapshot) = model.begin_save().unwrap()
  assert_eq(snapshot, "newer")
  assert_false(model.cancel_save(old))
  assert_eq(model.state(), Saving)
  assert_true(model.finish_save(current, Ok(())))
  assert_true(model.can_close())
}

///|
test "save cancellation cannot reopen a closed model" {
  let model = create()
  assert_true(model.finish_load(model.begin_load().unwrap(), Ok(None)))
  assert_true(model.edit("draft"))
  let (ticket, _) = model.begin_save().unwrap()
  model.close()
  assert_false(model.cancel_save(ticket))
  assert_eq(model.state(), Closed)
}
