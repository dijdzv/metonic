///|
async test "production clock supports repeated waits on one instance" {
  let clock = @clock.SystemClock::new()
  for value in [1, 2, 3] {
    assert_eq(@capability.after(clock, 2, value), value)
  }
}

///|
async test "canceling one production wait preserves another and subsequent waits" {
  let clock = @clock.SystemClock::new()
  let canceled_completed = Ref(false)
  @async.with_task_group(group => {
    let canceled = group.spawn(() => {
      @async.with_task_group(owner => {
        owner.spawn_bg(() => {
          ignore(@capability.after(clock, 60000, 1))
          canceled_completed.val = true
        })
        @async.pause()
        owner.return_immediately(())
      })
    })
    let kept = group.spawn(() => @capability.after(clock, 5, 2))
    @async.pause()
    canceled.wait()
    assert_eq(kept.wait(), 2)
  })
  assert_false(canceled_completed.val)
  assert_eq(@capability.after(clock, 2, 3), 3)
}
