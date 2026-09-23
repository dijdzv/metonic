///|
async test "Notes Scope cancels independent search and save tasks once" {
  let app = create_collection(
    { load: () => Ok(None), save: _ => Ok(()), },
    () => (),
    _ => (),
  )
  let canceled : Array[@task.Operation] = []
  (app.connect_tasks)(@task.task_control(operation => canceled.push(operation)))
  finish((app.initialize)())
  let new_memo = (app.view)()[3].element.reference.unwrap()
  let save = (app.activate)(new_memo).unwrap()
  let search = search_edit(app, "Memo")
  assert_true(save.operation() != search.operation())
  (app.stop)()
  assert_eq(canceled.length(), 2)
  assert_true(canceled[0] == search.operation())
  assert_true(canceled[1] == save.operation())
  (app.stop)()
  assert_eq(canceled.length(), 2)
}

///|
async test "prepared autosave does not touch disposed presentation state" {
  let app = create_collection(
    { load: () => Ok(None), save: _ => Ok(()), },
    () => (),
    _ => (),
  )
  finish((app.initialize)())
  let new_memo = (app.view)()[3].element.reference.unwrap()
  let request = (app.activate)(new_memo).unwrap()
  request.invalidate()
  let work = request.prepare().unwrap()
  (app.stop)()
  assert_eq(work.run().apply(), @task.Unchanged)
}
