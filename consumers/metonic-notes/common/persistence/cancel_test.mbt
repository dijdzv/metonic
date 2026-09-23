///|
async test "canceling suspended storage releases saving state without acknowledging it" {
  let model = @persistence.create()
  assert_true(model.finish_load(model.begin_load().unwrap(), Ok(Some("saved"))))
  assert_true(model.edit("draft"))
  let entered = @cond_var.Cond()
  let blocked = @cond_var.Cond()
  let changes = Ref(0)
  let operation = @task.Operation::new()
  let request = model
    .save_request(
      {
        load: () => Ok(None),
        save: _ => {
          entered.signal()
          blocked.wait()
          Ok(())
        },
      },
      () => changes.val += 1,
      operation,
    )
    .unwrap()
  request.invalidate()
  let work = request.prepare().unwrap()
  @async.with_task_group(group => {
    group.spawn_bg(() => ignore(work.run()))
    entered.wait()
    assert_true(model.edit("newer"))
    group.return_immediately(())
  })
  assert_eq(changes.val, 1)
  assert_eq(model.state(), @persistence.Ready)
  assert_eq(model.text(), "newer")
  assert_true(model.is_saved("saved"))
  assert_true(model.dirty())
  let retry = model
    .save_request(
      { load: () => Ok(None), save: _ => Ok(()), },
      () => (),
      operation,
    )
    .unwrap()
  retry.invalidate()
  assert_eq(retry.prepare().unwrap().run().apply(), @task.Changed)
  assert_true(model.is_saved("newer"))
}
