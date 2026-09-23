///|
async test "canceled save cannot acknowledge a draft or complete pending close" {
  let entered = @cond_var.Cond()
  let blocked = @cond_var.Cond()
  let app = create_collection(
    {
      load: () => Ok(Some("original")),
      save: _ => {
        entered.signal()
        blocked.wait()
        Ok(())
      },
    },
    () => (),
    _ => (),
  )
  initialize(app)
  assert_eq(
    @semantics.set_text(app.editor, app.default_input.unwrap(), "draft"),
    "",
  )
  let request = (app.activate)((app.view)()[1].element.reference.unwrap()).unwrap()
  request.invalidate()
  let work = request.prepare().unwrap()
  @async.with_task_group(group => {
    group.spawn_bg(() => ignore(work.run()))
    entered.wait()
    (app.close_requested)()
    group.return_immediately(())
  })
  assert_true((app.view)().last().unwrap().element.text.contains("Saving..."))
  assert_false((app.close_ready)())
  assert_eq(
    @semantics.node(app.editor, app.default_input.unwrap()).unwrap().value,
    "draft",
  )
  assert_false((app.can_close)())
  (app.stop)()
}
