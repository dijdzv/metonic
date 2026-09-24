///|
async test "source distinguishes first load, refresh, failure and key switch" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let source : Source[String, Int] = Source::new(root)
  assert_true(source.connect(@task.task_control(_ => ())))
  assert_eq(source.get(), Idle)
  let cycle1 = Cycle::new()
  let cycle2 = Cycle::new()
  let cycle3 = Cycle::new()
  let cycle4 = Cycle::new()
  let first = source.replace("one", cycle1, true, () => 10).unwrap()
  assert_eq(source.peek(), Idle)
  assert_true(first.prepare() is None)
  first.invalidate()
  assert_eq(source.get(), Pending("one", cycle1, None))
  assert_eq(first.prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(source.get(), Ready("one", cycle1, 10, None))

  let refresh = source.replace("one", cycle2, true, () => 20).unwrap()
  refresh.invalidate()
  let old : Snapshot[String, Int] = { key: "one", cycle: cycle1, value: 10, }
  assert_eq(source.get(), Pending("one", cycle2, Some(old)))
  assert_eq(refresh.failure("offline").apply(), @task.Failed("offline"))
  assert_eq(source.get(), Failed("one", cycle2, "offline", Some(old)))

  let retry = source.replace("one", cycle3, true, () => 30).unwrap()
  retry.invalidate()
  assert_eq(source.get(), Pending("one", cycle3, Some(old)))
  assert_eq(retry.prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(source.get(), Ready("one", cycle3, 30, Some(old)))

  let switch = source.replace("two", cycle4, true, () => 40).unwrap()
  switch.invalidate()
  assert_eq(source.get(), Pending("two", cycle4, None))
  assert_eq(switch.prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(source.get(), Ready("two", cycle4, 40, None))
  let cycle5 = Cycle::new()
  let expected = source
    .replace_result(
      "two",
      cycle5,
      true,
      fn() -> Result[Int, String] { Err("not found") },
      error => error,
    )
    .unwrap()
  expected.invalidate()
  let previous : Snapshot[String, Int] = {
    key: "two",
    cycle: cycle4,
    value: 40,
  }
  assert_eq(source.get(), Pending("two", cycle5, Some(previous)))
  assert_eq(expected.prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(source.get(), Failed("two", cycle5, "not found", Some(previous)))
  root.dispose()
}

///|
async test "source rejects stale success, failure and progress after replacement" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let source : Source[String, Int] = Source::new(root)
  assert_true(source.connect(@task.task_control(_ => ())))
  let progress = Ref(0)
  let posted : Array[@task.Completion] = []
  let cycle1 = Cycle::new()
  let cycle2 = Cycle::new()
  let first = source
    .replace_with_progress("one", cycle1, false, post => {
      post(
        @task.completion(() => {
          progress.val += 1
          @task.Changed
        }),
      )
      10
    })
    .unwrap()
  first.invalidate()
  let old_done = first
    .prepare()
    .unwrap()
    .run(post_progress=event => posted.push(event))
  assert_eq(posted.length(), 1)
  let replacement = source.replace("one", cycle2, false, () => 20).unwrap()
  replacement.invalidate()
  assert_eq(posted[0].apply(), @task.Rejected)
  assert_eq(old_done.apply(), @task.Rejected)
  assert_eq(first.failure("old failure").apply(), @task.Rejected)
  assert_eq(progress.val, 0)
  assert_eq(source.get(), Pending("one", cycle2, None))
  assert_eq(replacement.prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(source.get(), Ready("one", cycle2, 20, None))
  root.dispose()
}

///|
async test "source cancel and disposal leave no live result writer" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let source : Source[String, Int] = Source::new(root)
  let canceled = Ref(0)
  assert_true(source.connect(@task.task_control(_ => canceled.val += 1)))
  let cycle1 = Cycle::new()
  let cycle2 = Cycle::new()
  let cycle3 = Cycle::new()
  let first = source.replace("one", cycle1, false, () => 10).unwrap()
  first.invalidate()
  let old_done = first.prepare().unwrap().run()
  let cancel = source.cancel().unwrap()
  cancel.invalidate()
  assert_eq(source.get(), Canceled("one", cycle1, None))
  assert_eq(old_done.apply(), @task.Rejected)
  assert_true(cancel.prepare() is None)

  let second = source.replace("one", cycle2, false, () => 20).unwrap()
  second.invalidate()
  let late = second.prepare().unwrap().run()
  source.dispose()
  assert_eq(source.get(), Canceled("one", cycle2, None))
  assert_eq(late.apply(), @task.Rejected)
  assert_eq(canceled.val, 1)
  assert_true(source.replace("one", cycle3, false, () => 30) is None)
  root.dispose()
}

///|
async test "parent scope disposal rejects late source results without signal writes" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let source : Source[String, Int] = Source::new(root)
  let canceled = Ref(0)
  assert_true(source.connect(@task.task_control(_ => canceled.val += 1)))
  let request = source.replace("one", Cycle::new(), false, () => 10).unwrap()
  request.invalidate()
  let completion = request.prepare().unwrap().run()
  root.dispose()
  assert_eq(canceled.val, 1)
  assert_eq(completion.apply(), @task.Rejected)
  assert_eq(request.failure("late").apply(), @task.Rejected)
  assert_true(source.replace("one", Cycle::new(), false, () => 20) is None)
}

///|
test "pair requires matching current and retained cycles" {
  let old_cycle = Cycle::new()
  let active_cycle = Cycle::new()
  let other_cycle = Cycle::new()
  let switched_cycle = Cycle::new()
  let old_left : Snapshot[String, Int] = {
    key: "one",
    cycle: old_cycle,
    value: 10,
  }
  let old_right : Snapshot[String, Int] = {
    key: "one",
    cycle: old_cycle,
    value: 20,
  }
  let old_pair : PairSnapshot[String, Int, Int] = {
    key: "one",
    cycle: old_cycle,
    left: 10,
    right: 20,
  }
  let idle_left : AsyncState[String, Int] = Idle
  let idle_right : AsyncState[String, Int] = Idle
  assert_eq(derive_pair("one", active_cycle, idle_left, idle_right), PairIdle)
  assert_eq(
    derive_pair(
      "one",
      active_cycle,
      Pending("one", active_cycle, Some(old_left)),
      Pending("one", active_cycle, Some(old_right)),
    ),
    PairPending("one", active_cycle, Some(old_pair)),
  )
  assert_eq(
    derive_pair(
      "one",
      active_cycle,
      Ready("one", active_cycle, 11, Some(old_left)),
      Pending("one", active_cycle, Some(old_right)),
    ),
    PairPending("one", active_cycle, Some(old_pair)),
  )
  assert_eq(
    derive_pair(
      "one",
      active_cycle,
      Ready("one", active_cycle, 11, Some(old_left)),
      Ready("one", active_cycle, 21, Some(old_right)),
    ),
    PairReady("one", active_cycle, 11, 21),
  )
  assert_eq(
    derive_pair(
      "one",
      active_cycle,
      Ready("one", old_cycle, 10, None),
      Ready("one", active_cycle, 21, Some(old_right)),
    ),
    PairPending("one", active_cycle, None),
  )
  let pending_two : AsyncState[String, Int] = Pending(
    "two",
    switched_cycle,
    None,
  )
  assert_eq(
    derive_pair(
      "two",
      switched_cycle,
      pending_two,
      Ready("one", active_cycle, 21, Some(old_right)),
    ),
    PairPending("two", switched_cycle, None),
  )
  let mismatched : Snapshot[String, Int] = {
    key: "one",
    cycle: other_cycle,
    value: 20,
  }
  assert_eq(
    derive_pair(
      "one",
      active_cycle,
      Pending("one", active_cycle, Some(old_left)),
      Pending("one", active_cycle, Some(mismatched)),
    ),
    PairPending("one", active_cycle, None),
  )
  assert_eq(
    derive_pair(
      "one",
      active_cycle,
      Failed("one", active_cycle, "bad", Some(old_left)),
      Pending("one", active_cycle, Some(old_right)),
    ),
    PairFailed("one", active_cycle, Left("bad"), Some(old_pair)),
  )
  assert_eq(
    derive_pair(
      "one",
      active_cycle,
      Canceled("one", active_cycle, Some(old_left)),
      Pending("one", active_cycle, Some(old_right)),
    ),
    PairCanceled("one", active_cycle, Some(old_pair)),
  )
}

///|
async test "two sources publish one coherent derived view through graph batches" {
  let graph = @reactive.Graph::new()
  let root = @reactive.Scope::root(graph)
  let left : Source[String, Int] = Source::new(root)
  let right : Source[String, Int] = Source::new(root)
  let control = @task.task_control(_ => ())
  assert_true(left.connect(control))
  assert_true(right.connect(control))
  let selected = @reactive.Signal::new(root, "one")
  let cycle = @reactive.Signal::new(root, Cycle::new())
  let view = @reactive.Memo::new(root, fn() {
    derive_pair(selected.get(), cycle.get(), left.get(), right.get())
  })
  let seen : Array[PairView[String, Int, Int]] = []
  let _ = @reactive.Binding::new(root, fn() { view.get() }, fn(value) {
    seen.push(value)
  })
  assert_eq(seen, [PairIdle])

  let first_cycle = Cycle::new()
  let first = @task.group(
    [
      left.replace("one", first_cycle, true, () => 10).unwrap(),
      right.replace("one", first_cycle, true, () => 20).unwrap(),
    ],
    apply => graph.batch(apply),
    on_admitted=() => cycle.set(first_cycle),
  )
  first.invalidate()
  assert_eq(seen.last(), Some(PairPending("one", first_cycle, None)))
  assert_eq(seen.length(), 2)
  let members = first.members()
  assert_eq(members[0].prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(seen.last(), Some(PairPending("one", first_cycle, None)))
  assert_eq(seen.length(), 2)
  assert_eq(members[1].prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(seen.last(), Some(PairReady("one", first_cycle, 10, 20)))
  assert_eq(seen.length(), 3)

  let next_cycle = Cycle::new()
  let refresh = @task.group(
    [
      left.replace("one", next_cycle, true, () => 11).unwrap(),
      right.replace("one", next_cycle, true, () => 21).unwrap(),
    ],
    apply => graph.batch(apply),
    on_admitted=() => cycle.set(next_cycle),
  )
  refresh.invalidate()
  let old_pair : PairSnapshot[String, Int, Int] = {
    key: "one",
    cycle: first_cycle,
    left: 10,
    right: 20,
  }
  assert_eq(seen.last(), Some(PairPending("one", next_cycle, Some(old_pair))))
  assert_eq(seen.length(), 4)
  let refresh_members = refresh.members()
  assert_eq(refresh_members[0].prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(seen.last(), Some(PairPending("one", next_cycle, Some(old_pair))))
  assert_eq(seen.length(), 4)
  assert_eq(
    refresh_members[1].failure("offline").apply(),
    @task.Failed("offline"),
  )
  assert_eq(
    seen.last(),
    Some(PairFailed("one", next_cycle, Right("offline"), Some(old_pair))),
  )
  assert_eq(seen.length(), 5)

  let switch_cycle = Cycle::new()
  let switched = @task.group(
    [
      left.replace("two", switch_cycle, true, () => 30).unwrap(),
      right.replace("two", switch_cycle, true, () => 40).unwrap(),
    ],
    apply => graph.batch(apply),
    on_admitted=() => {
      selected.set("two")
      cycle.set(switch_cycle)
    },
  )
  switched.invalidate()
  assert_eq(seen.last(), Some(PairPending("two", switch_cycle, None)))
  assert_eq(seen.length(), 6)
  root.dispose()
}
