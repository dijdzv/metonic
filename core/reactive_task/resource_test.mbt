///|
test "resource binds one cancellation control and disposes once" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let resource = Resource::new(root)
  let canceled : Array[@task.Operation] = []
  let control = @task.task_control(operation => canceled.push(operation))
  assert_true(resource.connect(control))
  assert_false(resource.connect(control))
  assert_false(resource.is_disposed())
  root.dispose()
  resource.dispose()
  assert_true(resource.is_disposed())
  assert_eq(canceled.length(), 1)
  assert_false(resource.connect(control))
  assert_true(resource.cancel(() => ()) is None)
}

///|
test "request admission and separate operation identities are target independent" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let first = Resource::new(root)
  let second = Resource::new(root)
  let control = @task.task_control(_ => ())
  assert_true(first.connect(control))
  assert_true(second.connect(control))
  let invalidated = Ref(0)
  let failures = Ref(0)
  let proposal = first
    .replace_prepared(() => invalidated.val += 1, () => None, on_failure=_ => {
      failures.val += 1
      @task.Failed("late")
    })
    .unwrap()
  let other = second.cancel(() => ()).unwrap()
  assert_false(proposal.operation() == other.operation())
  assert_eq(invalidated.val, 0)
  assert_eq(proposal.failure("not admitted").apply(), @task.Rejected)
  proposal.invalidate()
  assert_eq(invalidated.val, 1)
  assert_true(proposal.prepare() is None)
  assert_eq(proposal.failure("admitted").apply(), @task.Failed("late"))
  assert_eq(failures.val, 1)
  root.dispose()
  assert_eq(proposal.failure("disposed").apply(), @task.Rejected)
}

///|
async test "accepted replacement rejects old completion but an unadmitted proposal does not" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let resource = Resource::new(root)
  assert_true(resource.connect(@task.task_control(_ => ())))
  let invalidations = Ref(0)
  let values : Array[Int] = []
  let make = value => {
    resource
    .replace(() => invalidations.val += 1, () => value, result => {
      values.push(result)
      @task.Changed
    })
    .unwrap()
  }
  let first = make(1)
  first.invalidate()
  let first_completion = first.prepare().unwrap().run()
  let unadmitted = make(2)
  assert_eq(first_completion.apply(), @task.Changed)
  assert_eq(values, [1])
  assert_eq(invalidations.val, 1)
  assert_true(unadmitted.prepare() is None)
  let second = make(2)
  second.invalidate()
  let second_completion = second.prepare().unwrap().run()
  let third = make(3)
  third.invalidate()
  assert_eq(second_completion.apply(), @task.Rejected)
  assert_eq(third.prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(values, [1, 3])
  root.dispose()
}

///|
async test "cancel and scope disposal reject pending results and failures" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let resource = Resource::new(root)
  assert_true(resource.connect(@task.task_control(_ => ())))
  let applied = Ref(0)
  let failed = Ref(0)
  let make = () => {
    resource
    .replace(
      () => (),
      () => 1,
      _ => {
        applied.val += 1
        @task.Changed
      },
      on_failure=_ => {
        failed.val += 1
        @task.Failed("failed")
      },
    )
    .unwrap()
  }
  let first = make()
  first.invalidate()
  let pending = first.prepare().unwrap().run()
  let failure = first.failure("old")
  let cancel = resource.cancel(() => ()).unwrap()
  cancel.invalidate()
  assert_eq(pending.apply(), @task.Rejected)
  assert_eq(failure.apply(), @task.Rejected)
  let second = make()
  second.invalidate()
  let pending = second.prepare().unwrap().run()
  let failure = second.failure("disposed")
  root.dispose()
  assert_eq(pending.apply(), @task.Rejected)
  assert_eq(failure.apply(), @task.Rejected)
  assert_eq(applied.val, 0)
  assert_eq(failed.val, 0)
}

///|
async test "independent resources do not invalidate one another" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let left = Resource::new(root)
  let right = Resource::new(root)
  let control = @task.task_control(_ => ())
  assert_true(left.connect(control))
  assert_true(right.connect(control))
  let applied : Array[String] = []
  let first = left
    .replace(() => (), () => "left", value => {
      applied.push(value)
      @task.Changed
    })
    .unwrap()
  let second = right
    .replace(() => (), () => "right", value => {
      applied.push(value)
      @task.Changed
    })
    .unwrap()
  first.invalidate()
  second.invalidate()
  let left_completion = first.prepare().unwrap().run()
  let right_completion = second.prepare().unwrap().run()
  left.dispose()
  assert_eq(left_completion.apply(), @task.Rejected)
  assert_eq(right_completion.apply(), @task.Changed)
  assert_eq(applied, ["right"])
  root.dispose()
}

///|
async test "prepared work applies once and remains owned by the resource" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let resource = Resource::new(root)
  assert_true(resource.connect(@task.task_control(_ => ())))
  let prepared = Ref(0)
  let applied = Ref(0)
  let request = resource
    .replace_prepared(() => (), () => {
      prepared.val += 1
      Some(
        @task.work(() => 7, value => {
          applied.val += value
          @task.Changed
        }),
      )
    })
    .unwrap()
  assert_eq(prepared.val, 0)
  request.invalidate()
  let work = request.prepare().unwrap()
  assert_eq(prepared.val, 1)
  let completion = work.run()
  assert_eq(applied.val, 0)
  assert_eq(completion.apply(), @task.Changed)
  assert_eq(applied.val, 7)
  assert_eq(completion.apply(), @task.Unchanged)
  root.dispose()
}
