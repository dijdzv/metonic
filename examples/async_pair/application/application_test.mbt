///|
fn visible_status(app : @app.Application) -> String {
  (app.view)()[5].element.text
}

///|
fn button(app : @app.Application, index : Int) -> @semantics.NodeRef {
  (app.view)()[index].element.reference.unwrap()
}

///|
async test "paired application shows only coherent detail and related results" {
  let app = create(_ => ())
  (app.connect_tasks)(@task.task_control(_ => ()))
  assert_eq(visible_status(app), "Idle")
  let first = (app.initialize)().unwrap()
  first.invalidate()
  assert_eq(visible_status(app), "Loading one")
  let first_members = first.members()
  assert_eq(first_members[0].prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(visible_status(app), "Loading one")
  assert_eq(first_members[1].prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(visible_status(app), "Ready one: Detail one / Related one")

  let refresh = (app.activate)(button(app, 2)).unwrap()
  refresh.invalidate()
  assert_eq(visible_status(app), "Refreshing one: Detail one / Related one")
  let refresh_members = refresh.members()
  assert_eq(refresh_members[1].prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(visible_status(app), "Refreshing one: Detail one / Related one")
  assert_eq(refresh_members[0].prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(visible_status(app), "Ready one: Detail one / Related one")

  let switch = (app.activate)(button(app, 1)).unwrap()
  switch.invalidate()
  assert_eq(visible_status(app), "Loading two")
  let switch_members = switch.members()
  assert_eq(switch_members[0].prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(visible_status(app), "Loading two")
  assert_eq(switch_members[1].prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(visible_status(app), "Failed two: related data unavailable")

  let retry = (app.activate)(button(app, 3)).unwrap()
  retry.invalidate()
  assert_eq(visible_status(app), "Loading two")
  let retry_members = retry.members()
  assert_eq(retry_members[1].prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(visible_status(app), "Loading two")
  assert_eq(retry_members[0].prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(visible_status(app), "Ready two: Detail two / Related two")

  let pending = (app.activate)(button(app, 2)).unwrap()
  pending.invalidate()
  assert_eq(visible_status(app), "Refreshing two: Detail two / Related two")
  let late = pending.members()[0].prepare().unwrap().run()
  let cancel = (app.activate)(button(app, 4)).unwrap()
  cancel.invalidate()
  assert_eq(visible_status(app), "Canceled two")
  assert_eq(late.apply(), @task.Rejected)
  (app.dispose)()
}

///|
async test "selection replacement and disposal reject late paired work" {
  let app = create(_ => ())
  (app.connect_tasks)(@task.task_control(_ => ()))
  let first = (app.initialize)().unwrap()
  first.invalidate()
  let old = first.members()[1].prepare().unwrap().run()
  let switched = (app.activate)(button(app, 1)).unwrap()
  switched.invalidate()
  assert_eq(visible_status(app), "Loading two")
  assert_eq(old.apply(), @task.Rejected)
  assert_eq(visible_status(app), "Loading two")
  let new_result = switched.members()[0].prepare().unwrap().run()
  (app.dispose)()
  assert_eq(new_result.apply(), @task.Rejected)
}
