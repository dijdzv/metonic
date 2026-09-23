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

///|
test "reactive persistence state reports transitions once and close is idempotent" {
  let scope = @reactive.Scope::root(@reactive.Graph::new())
  let model = create_scoped(scope, action => action())
  let seen : Array[State] = []
  let _ = @reactive.Binding::new(scope, () => model.state(), state => {
    seen.push(state)
  })
  let load = model.begin_load().unwrap()
  assert_true(model.finish_load(load, Ok(Some("seed"))))
  assert_false(model.finish_load(load, Ok(Some("ignored"))))
  assert_true(model.edit("next"))
  let (save, _) = model.begin_save().unwrap()
  assert_true(model.cancel_save(save))
  let (retry, _) = model.begin_save().unwrap()
  assert_true(model.finish_save(retry, Err("disk")))
  model.close()
  model.close()
  assert_eq(seen, [
    Unloaded,
    Loading,
    Ready,
    Saving,
    Ready,
    Saving,
    SaveFailed("disk"),
    Closed,
  ])
  scope.dispose()
}

///|
async test "load publishes ready state with its document update atomically" {
  let graph = @reactive.Graph::new()
  let scope = @reactive.Scope::root(graph)
  let model = create_scoped(scope, action => graph.batch(action))
  let document_version = @reactive.Signal::new(scope, 0)
  let seen : Array[(State, Int)] = []
  let _ = @reactive.Binding::new(
    scope,
    () => (model.state(), document_version.get()),
    state => seen.push(state),
  )
  let request = model
    .load_request({ load: () => Ok(Some("saved")), save: _ => Ok(()), }, () => {
      document_version.set(1)
    })
    .unwrap()
  request.invalidate()
  assert_eq(request.prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(seen, [(Unloaded, 0), (Loading, 0), (Ready, 1)])
  scope.dispose()
}

///|
async test "late save work and completion are inert after Scope disposal" {
  let scope = @reactive.Scope::root(@reactive.Graph::new())
  let model = create_scoped(scope, action => action())
  let load = model.begin_load().unwrap()
  assert_true(model.finish_load(load, Ok(Some("saved"))))
  assert_true(model.edit("new"))
  let request = model
    .save_request(
      { load: () => Ok(None), save: _ => Ok(()), },
      () => (),
      @task.Operation::new(),
      before_save=_ => false,
    )
    .unwrap()
  request.invalidate()
  let work = request.prepare().unwrap()
  scope.dispose()
  assert_eq(work.run().apply(), @task.Unchanged)
  assert_eq(model.state(), Closed)

  let scope = @reactive.Scope::root(@reactive.Graph::new())
  let model = create_scoped(scope, action => action())
  let load = model.begin_load().unwrap()
  assert_true(model.finish_load(load, Ok(Some("saved"))))
  assert_true(model.edit("new"))
  let request = model
    .save_request(
      { load: () => Ok(None), save: _ => Ok(()), },
      () => (),
      @task.Operation::new(),
    )
    .unwrap()
  request.invalidate()
  let completion = request.prepare().unwrap().run()
  model.close()
  scope.dispose()
  assert_eq(completion.apply(), @task.Rejected)
}

///|
async test "a written snapshot survives retirement before its UI completion" {
  let model = create()
  assert_true(model.finish_load(model.begin_load().unwrap(), Ok(Some("saved"))))
  assert_true(model.edit("draft"))
  let request = model
    .save_request(
      { load: () => Ok(None), save: _ => Ok(()), },
      () => (),
      @task.Operation::new(),
    )
    .unwrap()
  request.invalidate()
  let completion = request.prepare().unwrap().run()
  assert_eq(model.saved_text(), Some("draft"))
  assert_eq(model.state(), Saving)
  model.retire_save()
  assert_eq(model.state(), Ready)
  assert_false(model.dirty())
  assert_eq(completion.apply(), @task.Rejected)
}

///|
async test "a completed disk write is recorded after Scope disposal" {
  let scope = @reactive.Scope::root(@reactive.Graph::new())
  let model = create_scoped(scope, action => action())
  assert_true(model.finish_load(model.begin_load().unwrap(), Ok(Some("saved"))))
  assert_true(model.edit("draft"))
  let entered = @cond_var.Cond()
  let release = @cond_var.Cond()
  let request = model
    .save_request(
      {
        load: () => Ok(None),
        save: _ => {
          entered.signal()
          release.wait()
          Ok(())
        },
      },
      () => (),
      @task.Operation::new(),
    )
    .unwrap()
  request.invalidate()
  let work = request.prepare().unwrap()
  @async.with_task_group(group => {
    let running = group.spawn(() => work.run())
    entered.wait()
    scope.dispose()
    release.signal()
    assert_eq(running.wait().apply(), @task.Rejected)
  })
  assert_eq(model.state(), Closed)
  assert_eq(model.saved_text(), Some("draft"))
}
