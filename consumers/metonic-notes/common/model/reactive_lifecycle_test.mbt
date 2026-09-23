///|
async test "reactive Notes lifecycle keeps semantic state through retry and disposal" {
  let stored : Ref[String?] = Ref(None)
  let fail_save = Ref(true)
  let disposed = Ref(0)
  let canceled : Array[@task.Operation] = []
  let app = create_collection(
    {
      load: () => Ok(stored.val),
      save: value => {
        if fail_save.val {
          Err("storage unavailable")
        } else {
          stored.val = Some(value)
          Ok(())
        }
      },
    },
    () => disposed.val += 1,
    _ => (),
  )
  (app.connect_tasks)(@task.task_control(operation => canceled.push(operation)))
  finish((app.initialize)())
  let action = index => (app.view)()[index].element.reference.unwrap()
  let new_memo = action(3)
  let editor = app.default_input.unwrap()
  ignore((app.activate)(new_memo))
  assert_eq(@semantics.set_text(app.editor, editor, "Alpha 日本語"), "")
  ignore((app.activate)(new_memo))
  assert_eq(@semantics.set_text(app.editor, editor, "Beta"), "")

  finish((app.activate)(action(1)))
  assert_true(
    (app.view)().last().unwrap().element.text.has_prefix("Save failed:"),
  )
  assert_false((app.can_close)())
  fail_save.val = false
  finish((app.activate)(action(1)))
  assert_eq(@collection.decode(stored.val).unwrap().items().length(), 2)
  assert_true((app.can_close)())

  finish(Some(search_edit(app, "Alpha")))
  assert_eq(listed_memos(app), ["Memo 1"])
  let alpha_row = listed_memo_refs(app)[0]
  ignore((app.activate)(alpha_row))
  assert_eq(
    @semantics.node(app.editor, editor).unwrap().value,
    "Alpha 日本語",
  )
  let clear = search_edit(app, "")
  clear.invalidate()
  assert_true(clear.prepare() is None)
  assert_eq(listed_memos(app), ["* Memo 1", "Memo 2"])
  ignore((app.activate)(action(4)))
  ignore((app.activate)(action(4)))
  assert_true(@semantics.node(app.editor, alpha_row) is Err(_))
  finish((app.activate)(action(1)))
  assert_eq(
    @collection.decode(stored.val).unwrap().items().map(note => note.text),
    ["Beta"],
  )

  let late = search_edit(app, "Beta")
  late.invalidate()
  let late_result = late.prepare().unwrap().run()
  let late_failure = late.failure("late")
  (app.stop)()
  (app.stop)()
  assert_eq(late_result.apply(), @task.Rejected)
  assert_eq(late_failure.apply(), @task.Rejected)
  assert_eq(canceled.length(), 2)
  assert_true(canceled[0] != canceled[1])
  (app.dispose)()
  assert_eq(disposed.val, 1)
}
