///|
async test "virtual deadlines wake only after the requested elapsed time" {
  let clock = @clock.VirtualClock::new()
  @async.with_task_group(group => {
    let task = group.spawn(() => @capability.after(clock, 1000, 42))
    @async.pause()
    assert_eq(clock.pending(), 1)
    clock.advance(999)
    assert_eq(task.try_wait(), None)
    clock.advance(1)
    assert_eq(task.wait(), 42)
    assert_eq(clock.pending(), 0)
  })
}

///|
async test "task group cancellation detaches virtual waiters" {
  let clock = @clock.VirtualClock::new()
  let completed = Ref(false)
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      ignore(@capability.after(clock, 1000, 42))
      completed.val = true
    })
    @async.pause()
    assert_eq(clock.pending(), 1)
    group.return_immediately(())
  })
  assert_eq(clock.pending(), 0)
  clock.advance(1000)
  assert_false(completed.val)
}

///|
async test "elapsed deadlines precede later deadlines with stable ties" {
  let clock = @clock.VirtualClock::new()
  let completed : Array[Int] = []
  @async.with_task_group(group => {
    let tasks = []
    for (delay, value) in [(1000, 3), (500, 1), (500, 2)] {
      tasks.push(
        group.spawn(() => completed.push(@capability.after(clock, delay, value))),
      )
      @async.pause()
    }
    clock.advance(1000)
    for task in tasks {
      task.wait()
    }
    assert_eq(completed, [1, 2, 3])
    assert_eq(clock.pending(), 0)
  })
}

///|
async test "replaced canceled and disposed operations reject late values" {
  for action in ["replace", "cancel", "dispose"] {
    let clock = @clock.VirtualClock::new()
    let scope = @task_scope.create()
    let id = @task_scope.begin(scope)
    @async.with_task_group(group => {
      let task = group.spawn(() => {
        let value = @capability.after(clock, 1000, 42)
        @task_scope.complete(scope, id, value)
      })
      @async.pause()
      match action {
        "replace" => {
          let fresh = @task_scope.begin(scope)
          assert_true(@task_scope.complete(scope, fresh, 7))
        }
        "cancel" => assert_true(@task_scope.cancel(scope))
        _ => assert_true(@task_scope.dispose(scope))
      }
      clock.advance(1000)
      assert_false(task.wait())
      assert_eq(
        @task_scope.field(scope, 2),
        if action == "replace" {
          7
        } else {
          0
        },
      )
      assert_eq(clock.pending(), 0)
    })
  }
}

///|
async test "invalid durations and overflow leave no waiter or time change" {
  let clock = @clock.VirtualClock::new(start=9223372036854775806L)
  for duration in [-1, 2] {
    let rejected = try {
      ignore(@capability.after(clock, duration, 1))
      false
    } catch {
      @capability.InvalidTime => true
      other => raise other
    }
    assert_true(rejected)
    assert_eq(clock.pending(), 0)
    let advance_rejected = try {
      clock.advance(duration)
      false
    } catch {
      @capability.InvalidTime => true
    }
    assert_true(advance_rejected)
  }
  assert_eq(@capability.Clock::now(clock), 9223372036854775806L)
  assert_eq(@capability.after(clock, 0, 3), 3)
  clock.advance(1)
  assert_eq(@capability.Clock::now(clock), 9223372036854775807L)
}
