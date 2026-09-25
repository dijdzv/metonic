///|
fn note_save_button(app : @app.Application) -> @semantics.NodeRef {
  (app.view)()
  .iter()
  .find_first(control => control.element.text == "Save note")
  .unwrap().element.reference.unwrap()
}

///|
fn edit_note(app : @app.Application, text : String) -> Unit raise {
  let target = app.default_input.unwrap()
  assert_eq(@semantics.set_text(app.editor, target, text), "")
  assert_true(
    (app.edited)({ target, text, revision: @semantics.revision(app.editor), })
    is None,
  )
}

///|
async test "a newer note edit waits for its own saved revision" {
  let writes : Array[SaveSnapshot] = []
  let app = create_with_save(_ => (), _ => Ok(2), snapshot => {
    writes.push(snapshot)
    Ok(())
  })
  (app.connect_tasks)(@task.task_control(_ => ()))
  assert_eq(line(app, 8), "Note: no edits")
  edit_note(app, "first")
  assert_eq(line(app, 8), "Note: unsaved revision 1")
  assert_true((app.activate)(note_save_button(app)) is None)
  let admitted : Array[@task.Request] = []
  assert_true(
    app.reconcile_tasks(request => {
      admitted.push(request)
      request.invalidate()
      true
    }),
  )
  assert_eq(line(app, 8), "Note: saving revision 1")
  let first = admitted[0].prepare().unwrap().run()
  assert_eq(writes.length(), 1)
  assert_eq(writes[0].document, "quote-board-note")
  assert_eq(writes[0].text, "first")
  assert_eq(writes[0].revision, 1)

  edit_note(app, "first and second")
  assert_true((app.activate)(note_save_button(app)) is None)
  assert_true((app.activate)(note_save_button(app)) is None)
  assert_false(app.reconcile_tasks(_ => abort("save must not overlap")))
  assert_eq(line(app, 8), "Note: saving revision 1; newer edit 2 is unsaved")
  assert_eq(first.apply(), @task.Changed)
  assert_false((app.can_close)())
  assert_eq(line(app, 8), "Note: queued for save")
  assert_true(
    app.reconcile_tasks(request => {
      admitted.push(request)
      request.invalidate()
      true
    }),
  )
  assert_eq(admitted.length(), 2)
  assert_eq(line(app, 8), "Note: saved revision 1; saving revision 2")
  assert_eq(admitted[1].prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(writes.length(), 2)
  assert_eq(writes[1].text, "first and second")
  assert_eq(writes[1].revision, 2)
  assert_eq(line(app, 8), "Note: saved revision 2")
  assert_true((app.can_close)())
  (app.dispose)()
}

///|
async test "removing item detail does not discard its app-owned note acknowledgement" {
  let writes : Array[SaveSnapshot] = []
  let app = create_with_save(_ => (), _ => Ok(2), snapshot => {
    writes.push(snapshot)
    Ok(())
  })
  (app.connect_tasks)(@task.task_control(_ => ()))
  let item = (app.initialize)().unwrap()
  item.invalidate()
  edit_note(app, "survives detail removal")
  ignore((app.activate)(note_save_button(app)))
  let admitted : Array[@task.Request] = []
  assert_true(
    app.reconcile_tasks(request => {
      admitted.push(request)
      request.invalidate()
      true
    }),
  )
  let acknowledgement = admitted[0].prepare().unwrap().run()
  let old_quantity = button(app, 2)
  assert_true((app.activate)(button(app, 3)) is None)
  assert_true(@semantics.node(app.editor, old_quantity) is Err(_))
  assert_true((app.activate)(button(app, 1)) is Some(_))
  assert_eq(line(app, 4), "Item: blue · Quantity: 1 · Currency: JPY")
  assert_eq(acknowledgement.apply(), @task.Changed)
  assert_eq(writes.length(), 1)
  assert_eq(line(app, 8), "Note: saved revision 1")
  assert_true((app.can_close)())
  (app.dispose)()
}

///|
async test "close waits for active and newer queued note writes" {
  let writes : Array[SaveSnapshot] = []
  let app = create_with_save(_ => (), _ => Ok(2), snapshot => {
    writes.push(snapshot)
    Ok(())
  })
  (app.connect_tasks)(@task.task_control(_ => ()))
  edit_note(app, "first")
  ignore((app.activate)(note_save_button(app)))
  let admitted : Array[@task.Request] = []
  assert_true(
    app.reconcile_tasks(request => {
      admitted.push(request)
      request.invalidate()
      true
    }),
  )
  let first = admitted[0].prepare().unwrap().run()
  edit_note(app, "second")
  assert_false((app.can_close)())
  (app.close_requested)()
  assert_false((app.close_ready)())
  assert_eq(
    line(app, 8),
    "Closing · Note: saving revision 1; newer edit 2 is unsaved",
  )
  assert_eq(first.apply(), @task.Changed)
  assert_false((app.close_ready)())
  assert_true(
    app.reconcile_tasks(request => {
      admitted.push(request)
      request.invalidate()
      true
    }),
  )
  assert_eq(admitted[1].prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(writes.length(), 2)
  assert_eq(writes[1].text, "second")
  assert_true((app.close_ready)())
  assert_true((app.can_close)())
  (app.dispose)()
}

///|
async test "rejected save retries its snapshot and queues a newer edit" {
  let writes : Array[SaveSnapshot] = []
  let app = create_with_save(_ => (), _ => Ok(2), snapshot => {
    writes.push(snapshot)
    Ok(())
  })
  (app.connect_tasks)(@task.task_control(_ => ()))
  edit_note(app, "first")
  ignore((app.activate)(note_save_button(app)))
  assert_true(app.reconcile_tasks(_ => false))
  assert_eq(line(app, 8), "Note: save not admitted; press Save note to retry")
  assert_false((app.can_close)())
  edit_note(app, "second")
  ignore((app.activate)(note_save_button(app)))
  let admitted : Array[@task.Request] = []
  assert_true(
    app.reconcile_tasks(request => {
      admitted.push(request)
      request.invalidate()
      true
    }),
  )
  assert_eq(admitted[0].prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(writes[0].text, "first")
  assert_false((app.can_close)())
  assert_true(
    app.reconcile_tasks(request => {
      admitted.push(request)
      request.invalidate()
      true
    }),
  )
  assert_eq(admitted[1].prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(writes[1].text, "second")
  assert_eq(line(app, 8), "Note: saved revision 2")
  (app.dispose)()
}

///|
async test "failed close save stays open until an explicit retry succeeds" {
  let attempts = Ref(0)
  let app = create_with_save(_ => (), _ => Ok(2), _ => {
    attempts.val += 1
    if attempts.val == 1 {
      Err("disk full")
    } else {
      Ok(())
    }
  })
  (app.connect_tasks)(@task.task_control(_ => ()))
  edit_note(app, "draft")
  (app.close_requested)()
  let admitted : Array[@task.Request] = []
  assert_true(
    app.reconcile_tasks(request => {
      admitted.push(request)
      request.invalidate()
      true
    }),
  )
  assert_eq(admitted[0].prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(line(app, 8), "Closing · Note: save failed: disk full")
  assert_false((app.can_close)())
  assert_false((app.close_ready)())
  ignore((app.activate)(note_save_button(app)))
  assert_true(
    app.reconcile_tasks(request => {
      admitted.push(request)
      request.invalidate()
      true
    }),
  )
  assert_eq(admitted[1].prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(attempts.val, 2)
  assert_true((app.close_ready)())
  (app.dispose)()
}
